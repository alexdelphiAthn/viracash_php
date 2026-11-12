<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Ticket de la factura simplificada en PDF, con el mismo formato que el
 * ticket de caja del programa (inLibGenerarTicket.pas): papel continuo de
 * 80 mm, 42 columnas de texto monoespaciado y, de arriba abajo, QR
 * tributario, número de factura, datos de la empresa, líneas, importe a
 * pagar, forma de pago, desglose de IVA, empleado que atendió y las cuatro
 * líneas de pie de ticket de la empresa (TEXTO_PIE_TICKET_CAJA_n_EMP).
 *
 * Diferencias con el ticket impreso de caja, porque la web no vende por caja:
 * no hay número de operación, almacén ni caja (en su lugar va el código de
 * la empresa), ni cambio, vales o código de barras EAN13; el QR se imprime a
 * 31 mm (el mínimo que pide la AEAT en papel) en lugar de los módulos de la
 * impresora térmica.
 *
 * La fuente es Courier, una de las catorce estándar del formato PDF: la
 * tienen todos los lectores (también los del móvil) sin incrustar nada.
 * El documento va siempre en castellano, como el ticket del programa.
 */

/** Columnas de texto del ticket (N_CHAR_LIN del programa). */
const TICKET_COLUMNAS = 42;
/** Papel de 80 mm en puntos PDF (ANCHO_PAPEL_MM del previsualizador). */
const TICKET_ANCHO_PT = 226.772;
const TICKET_MARGEN_PT = 5.0;
const TICKET_MARGEN_SUPERIOR_PT = 12.0;
const TICKET_MARGEN_INFERIOR_PT = 24.0;
const TICKET_INTERLINEADO_PT = 9.0;
/** QR tributario a 31 mm, como el PDF A4 (el mínimo de la AEAT son 30 mm). */
const TICKET_QR_LADO_PT = 88.0;
/** Aire sobre el QR (bajo el rótulo) y bajo él (sobre la leyenda VERI*FACTU). */
const TICKET_QR_MARGEN_SUPERIOR_PT = 6.0;
const TICKET_QR_MARGEN_INFERIOR_PT = 18.0;

/** Cuerpo con el que 42 caracteres Courier ocupan el ancho útil del papel. */
function ticket_tamano_letra(): float
{
    return (TICKET_ANCHO_PT - 2 * TICKET_MARGEN_PT) / TICKET_COLUMNAS / 0.6;
}

/** Alto que ocupa el QR en el papel, con su aire arriba y abajo. */
function ticket_alto_qr(): float
{
    return TICKET_QR_MARGEN_SUPERIOR_PT + TICKET_QR_LADO_PT + TICKET_QR_MARGEN_INFERIOR_PT;
}

/** Recorta un texto a las columnas del ticket (Copy(..., 1, N_CHAR_LIN)). */
function ticket_recortar(string $texto, int $columnas = TICKET_COLUMNAS): string
{
    return mb_substr($texto, 0, $columnas);
}

/** Rellena con espacios contando caracteres, no bytes (Format('%-26s')). */
function ticket_rellenar(string $texto, int $largo, bool $izquierda = false): string
{
    $faltan = $largo - mb_strlen($texto);
    if ($faltan <= 0) {
        return $texto;
    }
    return $izquierda ? str_repeat(' ', $faltan) . $texto : $texto . str_repeat(' ', $faltan);
}

/** Dos textos en los extremos de la línea (TextoColumnas del programa). */
function ticket_columnas(string $izquierda, string $derecha, int $ancho = TICKET_COLUMNAS): string
{
    $espacios = $ancho - mb_strlen($izquierda) - mb_strlen($derecha);
    if ($espacios < 1) {
        $espacios = 1;
    }
    return $izquierda . str_repeat(' ', $espacios) . $derecha;
}

/** Línea separadora de ancho completo (LineaSeparadora). */
function ticket_separador(string $caracter = '-'): string
{
    return str_repeat($caracter, TICKET_COLUMNAS);
}

/**
 * Empresa, almacén y caja del ticket ('012 Tda.GEN-01', STicketFormatoTienda
 * del programa, con los códigos rellenados de ceros por la izquierda). Si la
 * factura no tiene almacén ni caja (usuario sin almacén ni caja por defecto)
 * solo se imprime el código de la empresa.
 */
function ticket_tienda(array $factura): string
{
    $rellenar = static fn(string $valor, int $largo): string => str_pad($valor, $largo, '0', STR_PAD_LEFT);
    $empresa = trim((string)($factura['CODIGO_EMP_FAC'] ?? ''));
    $almacen = trim((string)($factura['CODIGO_ALM_FAC'] ?? ''));
    $caja = trim((string)($factura['CODIGO_CAJA_FAC'] ?? ''));
    if ($almacen === '' && $caja === '') {
        return $rellenar($empresa, 3);
    }
    return sprintf('%s Tda.%s-%s', $rellenar($empresa, 3), $rellenar($almacen, 3), $rellenar($caja, 2));
}

/** Importe como en el ticket del programa: 1.234,56 €. */
function ticket_importe(float $valor): string
{
    return number_format($valor, 2, ',', '.') . ' €';
}

/**
 * Compone el ticket como lista de elementos
 * ['texto' => ..., 'alineacion' => 'I'|'C', 'negrita' => bool] y, para el QR,
 * ['qr' => matriz]. Va aparte de la escritura del PDF para poder medir el
 * alto del papel antes de crear la página y para comprobarlo en las pruebas
 * sin generar el fichero.
 *
 * $opciones: 'qr' (QR tributario o null), 'forma_pago' (descripción),
 * 'empleado' (diminutivo de ticket) y 'pie' (líneas de pie de la empresa).
 */
function ticket_contenido(
    array $factura,
    array $lineas,
    string $numeroFormateado,
    array $opciones = []
): array {
    $qr = $opciones['qr'] ?? null;
    $empleado = trim((string)($opciones['empleado'] ?? ''));
    $formaPago = trim((string)($opciones['forma_pago'] ?? ''));
    $pie = $opciones['pie'] ?? [];
    $contenido = [];
    $linea = static function (string $texto, string $alineacion = 'I', bool $negrita = false) use (&$contenido): void {
        $contenido[] = ['texto' => $texto, 'alineacion' => $alineacion, 'negrita' => $negrita];
    };

    /* QR tributario y leyenda VERI*FACTU (EscribirQRTributario). */
    if ($qr !== null) {
        $linea('');
        $linea('QR tributario:', 'C');
        $contenido[] = ['qr' => $qr['matriz']];
        $linea('VERI*FACTU - Factura verificable', 'C');
        $linea('en la sede electrónica de la AEAT', 'C');
    }

    /* Cabecera: número de factura y datos de la empresa emisora. */
    $linea('');
    $linea(sprintf('FACTURA SIMPLIFICADA Nro. %s', $numeroFormateado), 'I', true);
    $linea('');
    $campo = static fn(string $nombre): string => trim((string)($factura[$nombre] ?? ''));
    $linea(ticket_recortar($campo('RAZON_SOCIAL_EMPRESA_FAC')), 'C');
    if ($campo('DIRECCION1_EMPRESA_FAC') !== '') {
        $linea(ticket_recortar($campo('DIRECCION1_EMPRESA_FAC')), 'C');
    }
    $localidad = trim($campo('CODIGO_POSTAL_EMPRESA_FAC') . ' ' . $campo('POBLACION_EMPRESA_FAC'));
    if ($localidad !== '') {
        $linea(ticket_recortar($localidad), 'C');
    }
    if ($campo('NIF_EMPRESA_FAC') !== '') {
        $linea(sprintf('CIF/NIF: %s', $campo('NIF_EMPRESA_FAC')), 'C');
    }
    if ($campo('MOVIL_EMPRESA_FAC') !== '') {
        $linea(sprintf('TELÉFONO: %s', $campo('MOVIL_EMPRESA_FAC')), 'C');
    }
    $linea('');
    /* Sin operación de caja: fecha y hora de alta a la izquierda y, a la
       derecha, empresa, almacén y caja con el formato del ticket. */
    $fechaHora = fecha_es($campo('FECHA_FAC'));
    $instante = $campo('INSTANTE_ALTA');
    if (strlen($instante) >= 16) {
        $fechaHora .= ' ' . substr($instante, 11, 5);
    }
    $linea(ticket_columnas($fechaHora, ticket_tienda($factura)));

    /* Líneas (EscribirArticulos). */
    $linea(ticket_separador());
    $linea('Artículo/Sku                Uds    Total');
    $linea(ticket_separador());
    foreach ($lineas as $fila) {
        $sku = trim((string)($fila['CODIGO_UNIDAD_FACLIN'] ?? ''));
        if ($sku === '') {
            $sku = trim((string)($fila['CODIGO_ART_FACLIN'] ?? ''));
        }
        $descripcion = trim((string)$fila['DESCRIPCION_ARTICULO_FACLIN']);
        $variacion = trim((string)($fila['DESCRIPCION_VARIACION_FACLIN'] ?? ''));
        if ($variacion !== '') {
            $descripcion .= ' ' . $variacion;
        }
        /* Sin artículo (línea escrita a mano) la primera columna lleva la
           descripción, para no dejar el hueco del SKU en blanco. */
        $primeraColumna = $sku !== '' ? $sku : $descripcion;
        $articulo = ticket_rellenar(ticket_recortar($primeraColumna, 26), 26);
        $unidades = ticket_rellenar(formatear_cantidad((float)$fila['CANTIDAD_FACLIN']), 4, true);
        $linea(ticket_columnas($articulo . $unidades, ticket_importe((float)$fila['TOTAL_FACLIN'])));
        if ($descripcion !== '' && ($sku !== '' || mb_strlen($descripcion) > 26)) {
            $linea(ticket_recortar($descripcion));
        }
    }
    $linea(ticket_separador());
    $linea('');

    /* Importes: a pagar, forma de pago y desglose de IVA. */
    $liquido = (float)($factura['TOTAL_LIQUIDO_FAC'] ?? 0);
    $linea(ticket_columnas('A PAGAR', ticket_importe($liquido)), 'I', true);
    if ($formaPago !== '') {
        $linea(ticket_columnas(mb_strtoupper($formaPago), ticket_importe($liquido)), 'I', true);
    }
    $linea('');
    foreach (ticket_desglose_iva($factura) as [$etiquetaBase, $base, $etiquetaCuota, $cuota]) {
        if ($etiquetaBase !== '') {
            $linea(ticket_columnas($etiquetaBase, ticket_importe($base)));
        }
        $linea(ticket_columnas($etiquetaCuota, ticket_importe($cuota)));
    }

    /* Pie: empleado, aviso de IVA incluido, despedida y pie de la empresa. */
    $linea('');
    $linea('');
    if ($empleado !== '') {
        $linea(sprintf('LE ATENDIÓ: %s', $empleado), 'C');
    }
    if (es_si((string)($factura['ESIMP_INCL_TARIFA_CLIENTE_FAC'] ?? 'S'))) {
        $linea('IVA INCLUIDO', 'C');
    }
    $linea('GRACIAS POR SU VISITA', 'C');
    $primeraDelPie = true;
    foreach ($pie as $textoPie) {
        $textoPie = ticket_recortar(trim((string)$textoPie));
        if ($textoPie === '') {
            continue;
        }
        if ($primeraDelPie) {
            $linea('');
            $primeraDelPie = false;
        }
        $linea($textoPie, 'C');
    }
    return $contenido;
}

/**
 * Desglose de IVA del ticket: base y cuota de cada tipo con importe, con los
 * rótulos del programa (normal y reducido) y los equivalentes para
 * superreducido y exento, que el ticket térmico no llega a imprimir.
 */
function ticket_desglose_iva(array $factura): array
{
    $tipos = [
        ['N', 'BASE IMPONIBLE'],
        ['R', 'BASE IMPONIBLE RED.'],
        ['S', 'BASE IMPONIBLE S.RED.'],
        ['E', 'BASE IMPONIBLE EXENTA'],
    ];
    $desglose = [];
    foreach ($tipos as [$sufijo, $etiqueta]) {
        $base = (float)($factura['TOTAL_BASEI_IVA' . $sufijo . '_FAC'] ?? 0);
        $cuota = (float)($factura['TOTAL_IVA' . $sufijo . '_FAC'] ?? 0);
        if (abs($base) < 0.005 && abs($cuota) < 0.005) {
            continue;
        }
        $porcentaje = formatear_porcentaje((string)($factura['PORCENTAJE_IVA' . $sufijo . '_FAC'] ?? '0'));
        $desglose[] = [$etiqueta, $base, sprintf('TOTAL IVA(%s%%)', $porcentaje), $cuota];
        $recargo = (float)($factura['TOTAL_RE' . $sufijo . '_FAC'] ?? 0);
        if (abs($recargo) >= 0.005) {
            $porcentajeRe = formatear_porcentaje((string)($factura['PORCENTAJE_RE' . $sufijo . '_FAC'] ?? '0'));
            $desglose[] = ['', 0.0, sprintf('TOTAL R.E.(%s%%)', $porcentajeRe), $recargo];
        }
    }
    return $desglose;
}

/** PDF del ticket: papel de 80 mm de alto ajustado al contenido. */
function ticket_pdf_generar(
    array $factura,
    array $lineas,
    string $numeroFormateado,
    array $opciones = []
): string {
    $contenido = ticket_contenido($factura, $lineas, $numeroFormateado, $opciones);
    $tamano = ticket_tamano_letra();

    /* Alto del papel: una sola página continua, como el ticket impreso. */
    $alto = TICKET_MARGEN_SUPERIOR_PT + TICKET_MARGEN_INFERIOR_PT;
    foreach ($contenido as $elemento) {
        $alto += isset($elemento['qr']) ? ticket_alto_qr() : TICKET_INTERLINEADO_PT;
    }

    $pdf = new PdfMinimo(TICKET_ANCHO_PT, $alto, 'courier');
    $pdf->nuevaPagina();
    $anchoUtil = TICKET_ANCHO_PT - 2 * TICKET_MARGEN_PT;
    $y = TICKET_MARGEN_SUPERIOR_PT;
    foreach ($contenido as $elemento) {
        if (isset($elemento['qr'])) {
            $pdf->qr(TICKET_MARGEN_PT + ($anchoUtil - TICKET_QR_LADO_PT) / 2,
                $y + TICKET_QR_MARGEN_SUPERIOR_PT, TICKET_QR_LADO_PT, $elemento['qr']);
            $y += ticket_alto_qr();
            continue;
        }
        if ($elemento['texto'] !== '') {
            $pdf->fuente($elemento['negrita'], $tamano);
            $pdf->texto(TICKET_MARGEN_PT, $y, $elemento['texto'], $elemento['alineacion'], $anchoUtil);
        }
        $y += TICKET_INTERLINEADO_PT;
    }
    return $pdf->generar('Factura simplificada ' . $numeroFormateado);
}
