<?php
declare(strict_types=1);

/*
 * Cálculo de líneas y totales de factura, réplica del programa:
 *   - TLinFac.CalcularLinea (inLibFacturas): descuento, precio con/sin IVA
 *     y totales de línea con la precisión de Currency (4 decimales).
 *   - Motor fiscal de venta (inLibMotorFiscalVenta) con la configuración
 *     que usa TFacturaTotales: redondeo por línea a 2 decimales, IVA
 *     incluido calculado por diferencia, recargo y retención según las
 *     reglas de AplicarReglas y CrearConfiguracionMotorFiscal.
 */

function redondear4(float $valor): float
{
    return round($valor, 4);
}

function redondear2(float $valor): float
{
    return round($valor, 2);
}

/**
 * Calcula una línea a partir de precio de salida, % descuento, cantidad,
 * % de IVA y si la tarifa incluye impuestos. Devuelve los importes que se
 * graban en fza_facturas_lineas.
 */
function calcular_linea(
    float $precioSalida,
    float $porcentajeDto,
    float $cantidad,
    float $porcentajeIva,
    bool $impuestosIncluidos
): array {
    $dto = redondear4($precioSalida * ($porcentajeDto / 100));
    $precioFinal = redondear4($precioSalida - $dto);
    if ($impuestosIncluidos) {
        $precioCiva = $precioFinal;
        $precioSiva = $porcentajeIva == 0.0
            ? $precioCiva
            : redondear4($precioCiva / (1 + $porcentajeIva / 100));
    } else {
        $precioSiva = $precioFinal;
        $precioCiva = redondear4($precioSiva * (1 + $porcentajeIva / 100));
    }
    return [
        'precio_salida'  => redondear4($precioSalida),
        'porcentaje_dto' => redondear4($porcentajeDto),
        'precio_dto'     => $dto,
        'precio_siva'    => $precioSiva,
        'precio_civa'    => $precioCiva,
        'porcentaje_iva' => $porcentajeIva,
        'total_siva'     => redondear4($precioSiva * $cantidad),
        'total_civa'     => redondear4($precioCiva * $cantidad),
        'cantidad'       => redondear4($cantidad),
    ];
}

/**
 * Configuración fiscal de la factura a partir de la cabecera (misma lógica
 * que TFacturaTotales.AplicarReglas + CrearConfiguracionMotorFiscal).
 * $cabecera usa los nombres de columna de fza_facturas.
 */
function configuracion_fiscal(array $cabecera): array
{
    $si = static fn(string $campo): bool => es_si((string)($cabecera[$campo] ?? 'N'));
    $agricolaEmpresa = $si('ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC');
    $agricolaCliente = $si('ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC');
    $intracomunitario = $si('ESINTRACOMUNITARIO_CLIENTE_FAC');
    $ventaActivoFijo = $si('ESVENTA_ACTIVO_FIJO_FAC');
    $ivaExento = $si('ESIVA_EXENTO_CLIENTE_FAC');
    $retencionesCliente = $si('ESRETENCIONES_CLIENTE_FAC');
    $retencionesEmpresa = $si('ESRETENCIONES_EMPRESA_FAC');
    $ivaRecargo = $si('ESIVA_RECARGO_CLIENTE_FAC');

    if ($agricolaEmpresa) {
        $retencionesEmpresa = true;
        $ivaRecargo = false;
    }
    if ($intracomunitario) {
        $ivaExento = true;
        $retencionesCliente = false;
        $agricolaCliente = false;
    }
    if ($ventaActivoFijo && $agricolaEmpresa) {
        $ivaExento = true;
    }
    if ($agricolaEmpresa && $agricolaCliente) {
        $retencionesCliente = true;
        $ivaExento = true;
    }
    if ($agricolaEmpresa && !$agricolaCliente && !$retencionesCliente) {
        $ivaExento = true;
    }
    $porcentajes = [
        'N' => (float)($cabecera['PORCENTAJE_IVAN_FAC'] ?? 0),
        'R' => (float)($cabecera['PORCENTAJE_IVAR_FAC'] ?? 0),
        'S' => (float)($cabecera['PORCENTAJE_IVAS_FAC'] ?? 0),
        'E' => (float)($cabecera['PORCENTAJE_IVAE_FAC'] ?? 0),
    ];
    $recargos = [
        'N' => (float)($cabecera['PORCENTAJE_REN_FAC'] ?? 0),
        'R' => (float)($cabecera['PORCENTAJE_RER_FAC'] ?? 0),
        'S' => (float)($cabecera['PORCENTAJE_RES_FAC'] ?? 0),
        'E' => (float)($cabecera['PORCENTAJE_REE_FAC'] ?? 0),
    ];
    if ($ivaExento) {
        $porcentajes['N'] = $porcentajes['E'];
        $porcentajes['R'] = $porcentajes['E'];
        $porcentajes['S'] = $porcentajes['E'];
        $recargos = ['N' => 0.0, 'R' => 0.0, 'S' => 0.0, 'E' => 0.0];
    }
    $simplificada = strtoupper((string)($cabecera['TIPO_FAC'] ?? 'NORMAL')) === 'SIMPLIFICADA';
    $clienteConDatosFiscales = trim((string)($cabecera['NIF_CLIENTE_FAC'] ?? '')) !== '';
    $aplicaRetencion = $retencionesCliente && $retencionesEmpresa &&
        !($ventaActivoFijo && $agricolaEmpresa);
    $porcentajeRetencion = (float)($cabecera['PORCENTAJE_RETENCION_FAC'] ?? 0);
    if ($ventaActivoFijo && $agricolaEmpresa) {
        $porcentajeRetencion = 0.0;
    }
    return [
        'iva_exento'              => $ivaExento,
        'porcentajes'             => $porcentajes,
        'recargos'                => $recargos,
        'aplica_recargo'          => $si('ESAPLICA_RE_ZONA_IVA_FAC') && $ivaRecargo &&
                                     !$simplificada && $clienteConDatosFiscales,
        'aplica_retencion'        => $aplicaRetencion && !$simplificada && $clienteConDatosFiscales,
        'retencion_con_impuestos' => $si('ESIRPF_IMP_INCL_ZONA_IVA_FAC'),
        'porcentaje_retencion'    => $porcentajeRetencion,
        'retenciones_cliente'     => $retencionesCliente,
        'retenciones_empresa'     => $retencionesEmpresa,
        'impuestos_incluidos'     => $si('ESIMP_INCL_TARIFA_CLIENTE_FAC'),
        'palabra_iva'             => (string)($cabecera['PALABRA_REPORTS_ZONA_IVA_FAC'] ?? 'IVA'),
    ];
}

/** Porcentaje de IVA que corresponde a un tipo (N, R, S, E) según la configuración. */
function porcentaje_iva_tipo(array $configuracion, string $tipoIva): float
{
    $tipo = strtoupper(trim($tipoIva));
    if (!in_array($tipo, ['N', 'R', 'S', 'E'], true)) {
        $tipo = 'N';
    }
    return (float)$configuracion['porcentajes'][$tipo];
}

/**
 * Calcula las líneas (importes de cada una) y los totales de la factura.
 * $lineas: lista de ['descripcion', 'cantidad', 'precio', 'dto', 'tipo_iva', ...].
 * Devuelve ['lineas' => líneas con importes, 'totales' => [...]].
 */
function calcular_factura(array $cabecera, array $lineas): array
{
    $cfg = configuracion_fiscal($cabecera);
    $porTipo = [];
    foreach (['N', 'R', 'S', 'E'] as $tipo) {
        $porTipo[$tipo] = [
            'base' => 0.0, 'porcentaje_iva' => $cfg['porcentajes'][$tipo], 'iva' => 0.0,
            'porcentaje_recargo' => $cfg['recargos'][$tipo], 'recargo' => 0.0,
        ];
    }
    $lineasCalculadas = [];
    $totalBruto = 0.0;
    $totalDescuentos = 0.0;
    $negativos = false;
    foreach ($lineas as $linea) {
        $tipo = strtoupper(trim((string)($linea['tipo_iva'] ?? 'N')));
        if (!in_array($tipo, ['N', 'R', 'S', 'E'], true)) {
            $tipo = 'N';
        }
        $tipoAcumulacion = $cfg['iva_exento'] ? 'E' : $tipo;
        $porcentajeIva = porcentaje_iva_tipo($cfg, $tipo);
        $importes = calcular_linea(
            (float)$linea['precio'],
            (float)($linea['dto'] ?? 0),
            (float)$linea['cantidad'],
            $porcentajeIva,
            $cfg['impuestos_incluidos']
        );
        /* Motor fiscal: redondeo por línea a 2 decimales. */
        $base = redondear2($importes['total_siva']);
        $totalConIva = redondear2($importes['total_civa']);
        $iva = $cfg['impuestos_incluidos']
            ? $totalConIva - $base
            : $base * $porcentajeIva / 100;
        $iva = redondear2($iva);
        $recargo = 0.0;
        if ($cfg['aplica_recargo']) {
            $recargo = redondear2($base * $cfg['recargos'][$tipoAcumulacion] / 100);
        }
        $porTipo[$tipoAcumulacion]['base'] += $base;
        $porTipo[$tipoAcumulacion]['iva'] += $iva;
        $porTipo[$tipoAcumulacion]['recargo'] += $recargo;
        $totalBruto += $importes['precio_salida'] * $importes['cantidad'];
        $totalDescuentos += $importes['precio_dto'] * $importes['cantidad'];
        if ($base < 0 || $importes['cantidad'] < 0) {
            $negativos = true;
        }
        $lineasCalculadas[] = $linea + $importes + [
            'tipo_iva' => $tipo,
            'base_linea' => $base,
            'iva_linea' => $iva,
        ];
    }
    $totalBases = 0.0;
    $totalIva = 0.0;
    $totalRecargo = 0.0;
    foreach ($porTipo as $tipo => $datos) {
        $totalBases += $datos['base'];
        $totalIva += $datos['iva'];
        $totalRecargo += $datos['recargo'];
    }
    $totalImpuestos = $totalIva + $totalRecargo;
    $retencion = 0.0;
    if ($cfg['aplica_retencion']) {
        $baseRetencion = $totalBases;
        if ($cfg['retencion_con_impuestos']) {
            $baseRetencion += $totalImpuestos;
        }
        /* Una sola vez sobre el total, como en el motor Delphi. */
        $retencion = redondear2(
            $baseRetencion * $cfg['porcentaje_retencion'] / 100);
    }
    return [
        'configuracion' => $cfg,
        'lineas' => $lineasCalculadas,
        'totales' => [
            'por_tipo'             => $porTipo,
            'total_bases'          => $totalBases,
            'total_iva'            => $totalIva,
            'total_recargo'        => $totalRecargo,
            'total_impuestos'      => $totalImpuestos,
            'porcentaje_retencion' => $cfg['aplica_retencion'] ? $cfg['porcentaje_retencion'] : 0.0,
            'total_retencion'      => $retencion,
            'total_con_impuestos'  => $totalBases + $totalImpuestos,
            'total_liquido'        => $totalBases + $totalImpuestos - $retencion,
            'total_bruto'          => $totalBruto,
            'total_descuentos'     => $totalDescuentos,
            'negativos'            => $negativos,
        ],
    ];
}

/**
 * Número de documento visible según el "Formato documentos" de la empresa
 * (FORMATO_DOCUMENTO_EMP), con los mismos tokens que PRC_FORMATO_DOCUMENTO
 * del programa: Serie y NroDocumento (y sus variantes). Ej.: 'Serie.NroDocumento'
 * -> 'INFOR.26.000018', 'NroDocumento\Serie' -> '000018\INFOR.26'.
 */
function numero_documento_formateado(?array $empresa, string $serie, string $numero): string
{
    $serie = trim($serie);
    $numero = trim($numero);
    if ($serie === '') {
        return $numero;
    }
    if ($numero === '') {
        return $serie;
    }
    $formato = trim((string)($empresa['FORMATO_DOCUMENTO_EMP'] ?? ''));
    if ($formato === '') {
        $formato = 'Serie.NroDocumento';
    }
    $resultado = $formato;
    foreach (['NroDocumento', 'nrodocumento', 'NRODOCUMENTO', 'NumeroDocumento', 'numerodocumento',
              'NUMERODOCUMENTO', 'NúmeroDocumento', 'númerodocumento', 'NÚMERODOCUMENTO',
              'NroFactura', 'nrofactura', 'NROFACTURA', 'NroDoc', 'nrodoc', 'NRODOC',
              'Numero', 'numero', 'NUMERO', 'Número', 'número', 'NÚMERO'] as $token) {
        $resultado = str_replace($token, $numero, $resultado);
    }
    foreach (['Serie', 'serie', 'SERIE'] as $token) {
        $resultado = str_replace($token, $serie, $resultado);
    }
    return $resultado === $formato ? $serie . '.' . $numero : $resultado;
}

/** IBAN en grupos de cuatro caracteres (ES50 0182 5632 ...). */
function formatear_iban(string $iban): string
{
    $limpio = strtoupper(preg_replace('/\s+/', '', $iban) ?? '');
    return $limpio === '' ? '' : trim(chunk_split($limpio, 4, ' '));
}

/** Importe con dos decimales, separador español y símbolo de euro. */
function formatear_importe(float $valor): string
{
    return number_format($valor, 2, ',', '.') . ' €';
}

/** Cantidad sin ceros sobrantes (1, 1,5, 2,25). */
function formatear_cantidad(float $valor): string
{
    $texto = number_format($valor, 4, ',', '.');
    $texto = rtrim(rtrim($texto, '0'), ',');
    return $texto === '' ? '0' : $texto;
}

/** Convierte un número escrito con coma o punto en float; null si no es válido. */
function numero_desde_texto(string $texto): ?float
{
    $texto = str_replace([' ', '€'], '', trim($texto));
    if ($texto === '') {
        return null;
    }
    if (substr_count($texto, ',') === 1 && substr_count($texto, '.') === 0) {
        $texto = str_replace(',', '.', $texto);
    } elseif (substr_count($texto, ',') === 1 && substr_count($texto, '.') >= 1) {
        $texto = str_replace(['.', ','], ['', '.'], $texto);
    } elseif (substr_count($texto, ',') > 1) {
        $texto = str_replace(',', '', $texto);
    }
    if (preg_match('/^-?\d+(\.\d+)?$/', $texto) !== 1) {
        return null;
    }
    return (float)$texto;
}
