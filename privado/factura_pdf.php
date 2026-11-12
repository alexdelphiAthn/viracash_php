<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Maquetación del PDF de factura con el mismo formato que la factura
 * impresa del programa: título, fecha y número, cajas de emisor y receptor,
 * tabla de líneas, desglose de IVA, totales con retención y forma de pago.
 * El documento sale en castellano o, si se pide, en catalán (los rótulos se
 * traducen con tf(); los datos y los textos legales de la factura van tal
 * cual están grabados). Con retención de IRPF se imprimen el "Total factura"
 * (base más impuestos, el importe del registro y del QR Verifactu) y el
 * "Total a pagar" (líquido), como recomienda la AEAT.
 */

/**
 * Lote, serie o temporada de la línea para la descripción del PDF (F-LOTEC):
 * «Lote L2410, cad. 24/10/2026», «N.º serie SN-809», «Temporada PV26».
 * Vacío si la línea no lleva lote (o la base de datos no lo tiene).
 */
function factura_pdf_texto_lote(array $linea, callable $tx): string
{
    $lote = trim((string)($linea['LOTE_FACLIN'] ?? ''));
    if ($lote === '') {
        return '';
    }
    $tipo = strtoupper(trim((string)($linea['TIPO_LOT'] ?? '')));
    if ($tipo === 'S') {
        return $tx('N.º serie {lote}', ['lote' => $lote]);
    }
    if ($tipo === 'T') {
        return $tx('Temporada {lote}', ['lote' => $lote]);
    }
    $caducidad = trim((string)($linea['FECHA_CADUCIDAD_FACLIN'] ?? ''));
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})/', $caducidad, $partes)) {
        return $tx('Lote {lote}, cad. {fecha}', [
            'lote' => $lote,
            'fecha' => $partes[3] . '/' . $partes[2] . '/' . $partes[1],
        ]);
    }
    return $tx('Lote {lote}', ['lote' => $lote]);
}

function factura_pdf_generar(
    array $factura,
    array $lineas,
    string $numeroFormateado,
    string $formaPago,
    string $iban = '',
    ?array $qr = null,
    string $idioma = 'es'
): string {
    $idioma = idioma_normalizar($idioma, IDIOMAS_FACTURA) ?? 'es';
    $tx = static fn(string $texto, array $valores = []): string => tf($texto, $idioma, $valores);
    $pdf = new PdfMinimo();
    $izquierda = 45.0;
    $anchoUtil = PdfMinimo::ANCHO - 2 * $izquierda;
    $palabraIva = trim((string)($factura['PALABRA_REPORTS_ZONA_IVA_FAC'] ?? '')) ?: 'IVA';
    /* Nota de borrador al pie: desactivada hasta que empiece Verifactu.
       Se activa con 'pdf_nota_borrador' => true en config.php. */
    $notaBorrador = !empty(configuracion()['pdf_nota_borrador']) &&
        strtoupper((string)($factura['FASE_FAC'] ?? '')) === 'BORRADOR';

    /* Columnas de la tabla de líneas. */
    $columnas = [
        'descripcion' => ['x' => $izquierda,        'ancho' => 262.0, 'alineacion' => 'I', 'titulo' => $tx('Descripción')],
        'cantidad'    => ['x' => $izquierda + 262,  'ancho' => 68.0,  'alineacion' => 'D', 'titulo' => $tx('Cantidad')],
        'precio'      => ['x' => $izquierda + 330,  'ancho' => 65.0,  'alineacion' => 'D', 'titulo' => $tx('Precio')],
        'iva'         => ['x' => $izquierda + 395,  'ancho' => 45.0,  'alineacion' => 'D', 'titulo' => '% ' . $palabraIva],
        'total'       => ['x' => $izquierda + 440,  'ancho' => 65.0,  'alineacion' => 'D', 'titulo' => $tx('Total')],
    ];

    $cabeceraPagina = function (bool $completa) use ($pdf, $izquierda, $anchoUtil, $factura, $numeroFormateado, $columnas, $qr, $tx): float {
        $pdf->nuevaPagina();
        $pdf->fuente(true, 12);
        $ancho = $pdf->texto($izquierda, 60, $tx('FACTURA'), 'C', $anchoUtil);
        $centro = $izquierda + $anchoUtil / 2;
        $pdf->linea($centro - $ancho / 2, 62.5, $centro + $ancho / 2, 62.5, 0.8);
        $pdf->fuente(false, 10);
        $pdf->texto($izquierda, 92, $tx('Fecha: {fecha}', ['fecha' => fecha_es((string)$factura['FECHA_FAC'])]));
        $pdf->texto($izquierda, 108, $tx('Número de Factura: {numero}', ['numero' => $numeroFormateado]));
        if ($completa && $qr !== null) {
            factura_pdf_qr($pdf, $qr, $izquierda, $anchoUtil, $tx);
        }
        $y = 128.0;
        if ($completa) {
            $y = factura_pdf_cajas($pdf, $factura, $izquierda, $anchoUtil, 128.0, $tx);
        }
        /* Cabecera de la tabla de líneas. */
        $pdf->rectangulo($izquierda, $y, $anchoUtil, 18);
        $pdf->fuente(true, 9);
        foreach ($columnas as $columna) {
            $pdf->texto($columna['x'] + 4, $y + 12.5, $columna['titulo'], $columna['alineacion'], $columna['ancho'] - 8);
        }
        /* Primera línea 14 pt bajo el borde, como en el desglose de IVA. */
        return $y + 32;
    };

    $y = $cabeceraPagina(true);
    $limiteLineas = 640.0;
    $interlineado = 11.0;
    $pdf->fuente(false, 9);
    foreach ($lineas as $linea) {
        $descripcion = trim((string)$linea['DESCRIPCION_ARTICULO_FACLIN']);
        $variacion = trim((string)($linea['DESCRIPCION_VARIACION_FACLIN'] ?? ''));
        if ($variacion !== '') {
            $descripcion .= ' ' . $variacion;
        }
        $lote = factura_pdf_texto_lote($linea, $tx);
        if ($lote !== '') {
            $descripcion .= ' ' . $lote;
        }
        $descuento = (float)$linea['PORCENTAJE_DTO_FACLIN'];
        if ($descuento != 0.0) {
            $descripcion .= ' ' . $tx('(dto. {pct} %)', ['pct' => formatear_porcentaje((string)$descuento)]);
        }
        $pdf->fuente(false, 9);
        $textoLineas = $pdf->partirTexto($descripcion, $columnas['descripcion']['ancho'] - 8);
        $altoFila = count($textoLineas) * $interlineado + 6;
        if ($y + $altoFila > $limiteLineas) {
            $y = $cabeceraPagina(false);
            $pdf->fuente(false, 9);
        }
        foreach ($textoLineas as $i => $texto) {
            $pdf->texto($columnas['descripcion']['x'] + 4, $y + $i * $interlineado, $texto);
        }
        $cantidad = formatear_cantidad((float)$linea['CANTIDAD_FACLIN']) . ' ' . trim((string)$linea['TIPO_CANTIDAD_ARTICULO_FACLIN']);
        $pdf->texto($columnas['cantidad']['x'] + 4, $y, $cantidad, 'D', $columnas['cantidad']['ancho'] - 8);
        $pdf->texto($columnas['precio']['x'] + 4, $y, formatear_importe((float)$linea['PRECIO_VENTA_SIVA_ARTICULO_FACLIN']), 'D', $columnas['precio']['ancho'] - 8);
        $pdf->texto($columnas['iva']['x'] + 4, $y, formatear_porcentaje((string)$linea['PORCENTAJE_IVA_FACLIN']), 'D', $columnas['iva']['ancho'] - 8);
        $pdf->texto($columnas['total']['x'] + 4, $y, formatear_importe((float)$linea['TOTAL_FAC_SIVA_FACLIN']), 'D', $columnas['total']['ancho'] - 8);
        $y += $altoFila;
    }

    /* Bloque de totales: al pie de la página, o en otra si no cabe. */
    $altoTotales = 150.0;
    $inicioTotales = max($y + 20, PdfMinimo::ALTO - 45 - $altoTotales - 40);
    if ($inicioTotales + $altoTotales > PdfMinimo::ALTO - 40) {
        $y = $cabeceraPagina(false);
        $inicioTotales = PdfMinimo::ALTO - 45 - $altoTotales - 40;
    }
    factura_pdf_totales($pdf, $factura, $izquierda, $anchoUtil, $inicioTotales, $palabraIva, $formaPago, $iban, $tx);

    /* Textos legales y nota de borrador. */
    $yPie = $inicioTotales + $altoTotales + ($iban !== '' ? 22 : 8);
    $pdf->fuente(false, 8);
    foreach (['TEXTO_LEGAL_EMPRESA_FAC', 'TEXTO_LEGAL_CLIENTE_FAC'] as $campo) {
        $texto = trim((string)($factura[$campo] ?? ''));
        if ($texto !== '') {
            $lineasTexto = $pdf->parrafo($izquierda, $yPie, $anchoUtil, $texto, 10);
            $yPie += $lineasTexto * 10 + 4;
        }
    }
    if ($notaBorrador) {
        $pdf->fuente(false, 7);
        $pdf->texto($izquierda, PdfMinimo::ALTO - 22, $tx('Borrador generado desde la web. Pendiente de consolidar en ViraCash.'), 'D', $anchoUtil);
    }
    return $pdf->generar($tx('Factura {numero}', ['numero' => $numeroFormateado]));
}

/**
 * QR tributario Verifactu (31 mm; el mínimo de la AEAT son 30 mm) en la
 * esquina superior derecha, con la leyenda "VERI*FACTU - Factura verificable
 * en la sede electrónica de la AEAT" a su izquierda, como el ticket del
 * programa. La leyenda es la frase fijada por la AEAT y se imprime siempre
 * en castellano; solo se traduce el rótulo "QR tributario".
 */
function factura_pdf_qr(PdfMinimo $pdf, array $qr, float $izquierda, float $anchoUtil, callable $tx): void
{
    $lado = 88.0;
    $xQr = $izquierda + $anchoUtil - $lado;
    $pdf->qr($xQr, 34.0, $lado, $qr['matriz']);
    $xTexto = $xQr - 8;
    $pdf->fuente(true, 8);
    $pdf->texto($xTexto, 70, (string)$qr['leyenda'][0], 'D');
    $pdf->fuente(false, 7);
    $pdf->texto($xTexto, 82, (string)$qr['leyenda'][1], 'D');
    $pdf->texto($xTexto, 92, (string)$qr['leyenda'][2], 'D');
    $pdf->fuente(false, 6);
    $pdf->texto($xTexto, 104, $tx('QR tributario'), 'D');
}

/** Cajas de emisor y receptor; devuelve la coordenada Y siguiente. */
function factura_pdf_cajas(PdfMinimo $pdf, array $factura, float $izquierda, float $anchoUtil, float $y, callable $tx): float
{
    $anchoCaja = ($anchoUtil - 14) / 2;
    $xEmisor = $izquierda;
    $xReceptor = $izquierda + $anchoCaja + 14;
    $pdf->fuente(false, 10);
    $pdf->texto($xEmisor + 4, $y + 8, $tx('Emisor'));
    $pdf->texto($xReceptor + 4, $y + 8, $tx('Receptor'));
    $yCaja = $y + 16;
    $emisor = factura_pdf_lineas_parte($pdf, $factura, 'EMPRESA', $anchoCaja - 12, $tx);
    $receptor = factura_pdf_lineas_parte($pdf, $factura, 'CLIENTE', $anchoCaja - 12, $tx);
    $filas = max(count($emisor), count($receptor));
    $altoCaja = $filas * 13 + 12;
    $pdf->rectangulo($xEmisor, $yCaja, $anchoCaja, $altoCaja);
    $pdf->rectangulo($xReceptor, $yCaja, $anchoCaja, $altoCaja);
    foreach ([[$xEmisor, $emisor], [$xReceptor, $receptor]] as [$x, $textos]) {
        foreach ($textos as $i => [$texto, $negrita]) {
            $pdf->fuente($negrita, 10);
            $pdf->texto($x + 6, $yCaja + 14 + $i * 13, $texto);
        }
    }
    return $yCaja + $altoCaja + 16;
}

/** Líneas de texto de una parte (EMPRESA o CLIENTE): [[texto, negrita], ...]. */
function factura_pdf_lineas_parte(PdfMinimo $pdf, array $factura, string $parte, float $ancho, callable $tx): array
{
    $campo = static fn(string $nombre): string => trim((string)($factura[$nombre . '_' . $parte . '_FAC'] ?? ''));
    $lineas = [];
    $pdf->fuente(true, 10);
    foreach ($pdf->partirTexto($campo('RAZON_SOCIAL'), $ancho) as $texto) {
        $lineas[] = [$texto, true];
    }
    $pdf->fuente(false, 10);
    foreach (['DIRECCION1', 'DIRECCION2'] as $nombre) {
        if ($campo($nombre) !== '') {
            foreach ($pdf->partirTexto($campo($nombre), $ancho) as $texto) {
                $lineas[] = [$texto, false];
            }
        }
    }
    $localidad = trim($campo('CODIGO_POSTAL') . '   ' . $campo('POBLACION'));
    if ($localidad !== '') {
        $lineas[] = [$localidad, false];
    }
    if ($campo('PROVINCIA') !== '') {
        $lineas[] = [$campo('PROVINCIA'), false];
    }
    $contacto = trim($campo('MOVIL') . '     ' . $campo('EMAIL'));
    if ($contacto !== '') {
        if ($pdf->anchoTexto($contacto) <= $ancho) {
            $lineas[] = [$contacto, false];
        } else {
            if ($campo('MOVIL') !== '') {
                $lineas[] = [$campo('MOVIL'), false];
            }
            foreach ($pdf->partirTexto($campo('EMAIL'), $ancho) as $texto) {
                $lineas[] = [$texto, false];
            }
        }
    }
    if ($campo('NIF') !== '') {
        $lineas[] = [$tx('NIF: {nif}', ['nif' => $campo('NIF')]), false];
    }
    return $lineas;
}

/** Desglose de IVA, totales, retención y forma de pago. */
function factura_pdf_totales(
    PdfMinimo $pdf,
    array $factura,
    float $izquierda,
    float $anchoUtil,
    float $y,
    string $palabraIva,
    string $formaPago,
    string $iban,
    callable $tx
): void {
    $tipos = [
        ['base' => 'TOTAL_BASEI_IVAN_FAC', 'porcentaje' => 'PORCENTAJE_IVAN_FAC', 'iva' => 'TOTAL_IVAN_FAC', 'recargo' => 'TOTAL_REN_FAC', 'porcentaje_re' => 'PORCENTAJE_REN_FAC'],
        ['base' => 'TOTAL_BASEI_IVAR_FAC', 'porcentaje' => 'PORCENTAJE_IVAR_FAC', 'iva' => 'TOTAL_IVAR_FAC', 'recargo' => 'TOTAL_RER_FAC', 'porcentaje_re' => 'PORCENTAJE_RER_FAC'],
        ['base' => 'TOTAL_BASEI_IVAS_FAC', 'porcentaje' => 'PORCENTAJE_IVAS_FAC', 'iva' => 'TOTAL_IVAS_FAC', 'recargo' => 'TOTAL_RES_FAC', 'porcentaje_re' => 'PORCENTAJE_RES_FAC'],
        ['base' => 'TOTAL_BASEI_IVAE_FAC', 'porcentaje' => 'PORCENTAJE_IVAE_FAC', 'iva' => 'TOTAL_IVAE_FAC', 'recargo' => 'TOTAL_REE_FAC', 'porcentaje_re' => 'PORCENTAJE_REE_FAC'],
    ];
    $totalRecargo = 0.0;
    foreach ($tipos as $tipo) {
        $totalRecargo += (float)($factura[$tipo['recargo']] ?? 0);
    }
    $hayRecargo = $totalRecargo != 0.0;

    /* Caja izquierda: desglose por tipo de IVA. */
    $anchoCaja = 300.0;
    $altoCaja = 130.0;
    $pdf->rectangulo($izquierda, $y, $anchoCaja, $altoCaja);
    $pdf->fuente(false, 9);
    /* Cada título se alinea a la derecha sobre el mismo borde que sus importes. */
    $columnasIva = [
        'base'       => ['x' => $izquierda + 6,   'ancho' => 90.0, 'titulo' => $tx('Base')],
        'porcentaje' => ['x' => $izquierda + 110, 'ancho' => 40.0, 'titulo' => '% ' . $palabraIva],
        'iva'        => ['x' => $izquierda + 175, 'ancho' => 60.0, 'titulo' => $tx('Total {iva}', ['iva' => $palabraIva])],
    ];
    if ($hayRecargo) {
        $columnasIva['recargo'] = ['x' => $izquierda + 240, 'ancho' => 55.0, 'titulo' => $tx('R.E.')];
    }
    foreach ($columnasIva as $columna) {
        $pdf->texto($columna['x'], $y + 13, $columna['titulo'], 'D', $columna['ancho']);
    }
    $pdf->linea($izquierda, $y + 18, $izquierda + $anchoCaja, $y + 18, 0.5);
    $fila = $y + 32;
    foreach ($tipos as $tipo) {
        $base = (float)($factura[$tipo['base']] ?? 0);
        $iva = (float)($factura[$tipo['iva']] ?? 0);
        if ($base == 0.0 && $iva == 0.0) {
            continue;
        }
        $valores = [
            'base'       => formatear_importe($base),
            'porcentaje' => formatear_porcentaje((string)($factura[$tipo['porcentaje']] ?? 0)) . '%',
            'iva'        => formatear_importe($iva),
            'recargo'    => formatear_importe((float)($factura[$tipo['recargo']] ?? 0)),
        ];
        foreach ($columnasIva as $clave => $columna) {
            $pdf->texto($columna['x'], $fila, $valores[$clave], 'D', $columna['ancho']);
        }
        $fila += 13;
    }

    /* Columna derecha: totales generales. Con retención de IRPF se muestra el
       total de la factura (base + impuestos, el importe del registro y del QR
       Verifactu) y, aparte, el total a pagar una vez descontada la retención. */
    $xTotales = $izquierda + $anchoCaja + 20;
    $anchoTotales = $anchoUtil - $anchoCaja - 20;
    $filaTotal = $y + 32;
    $totalBases = (float)($factura['TOTAL_BASES_FAC'] ?? 0);
    $totalImpuestos = (float)($factura['TOTAL_IMPUESTOS_FAC'] ?? 0);
    $totalIva = $totalImpuestos - $totalRecargo;
    $retencion = (float)($factura['TOTAL_RETENCION_FAC'] ?? 0);
    $porcentajeRetencion = (float)($factura['PORCENTAJE_RETENCION_FAC'] ?? 0);
    $liquido = (float)($factura['TOTAL_LIQUIDO_FAC'] ?? 0);
    $hayRetencion = $retencion != 0.0 || $porcentajeRetencion != 0.0;
    $pdf->fuente(false, 10);
    $conceptos = [
        [$tx('Total Base Imponible'), formatear_importe($totalBases)],
        [$tx('Total {iva}', ['iva' => $palabraIva]), formatear_importe($totalIva)],
    ];
    if ($hayRecargo) {
        $conceptos[] = [$tx('Total Recargo Equiv.'), formatear_importe($totalRecargo)];
    }
    if ($hayRetencion) {
        $conceptos[] = [$tx('Total Factura'), formatear_importe($totalBases + $totalImpuestos)];
        $conceptos[] = [$tx('Retención IRPF {pct}%', ['pct' => formatear_porcentaje((string)$porcentajeRetencion)]), '-' . formatear_importe($retencion)];
    }
    foreach ($conceptos as [$concepto, $importe]) {
        $pdf->texto($xTotales + 4, $filaTotal, $concepto);
        $pdf->texto($xTotales, $filaTotal, $importe, 'D', $anchoTotales - 4);
        $filaTotal += 16;
    }
    $filaTotal += 6;
    $pdf->rectangulo($xTotales, $filaTotal - 12, $anchoTotales, 18, 0.8);
    $pdf->fuente(true, 10);
    $pdf->texto($xTotales + 4, $filaTotal + 1, $hayRetencion ? $tx('Total a Pagar') : $tx('Total Factura'));
    $pdf->texto($xTotales, $filaTotal + 1, formatear_importe($liquido), 'D', $anchoTotales - 4);

    /* Forma de pago bajo la caja y, a continuación, la cuenta bancaria si la
       forma de pago lo pide (ESVERBANCOEMPRESA_FORMA_PAGO_FP = 'S'). */
    $yPago = $y + $altoCaja + 16;
    $pdf->fuente(false, 10);
    $textoPago = $formaPago !== '' ? $tx('Forma de Pago: {forma}', ['forma' => $formaPago]) : '';
    $textoIban = $iban !== '' ? 'IBAN: ' . formatear_iban($iban) : '';
    if ($textoPago !== '' && $textoIban !== '') {
        $enUnaLinea = $textoPago . '     ' . $textoIban;
        if ($pdf->anchoTexto($enUnaLinea) <= $anchoUtil - 12) {
            $pdf->texto($izquierda + 6, $yPago, $enUnaLinea);
        } else {
            $pdf->texto($izquierda + 6, $yPago, $textoPago);
            $pdf->texto($izquierda + 6, $yPago + 14, $textoIban);
        }
    } elseif ($textoPago !== '' || $textoIban !== '') {
        $pdf->texto($izquierda + 6, $yPago, $textoPago !== '' ? $textoPago : $textoIban);
    }
}
