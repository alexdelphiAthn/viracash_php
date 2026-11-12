<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Registro del SII (Suministro Inmediato de Información) del libro de
 * facturas emitidas sin acceso a la base de datos: alta (A0), modificación
 * (A1), baja, sobre SOAP e interpretación de la respuesta. Transcripción de
 * inLibSiiConstruccionEnvio del programa (FZ-ISSUE-295): mismos elementos,
 * mismo orden y mismos formatos, de modo que el XML coincide byte a byte con
 * el que genera ViraCash para la misma factura. Si se cambia uno, hay que
 * cambiar el otro.
 *
 * La entrada es el array de verifactu_cargar_datos_factura (verifactu_cola.php)
 * más 'serie', 'numero', 'clave_regimen_sii', 'tipo_operacion_defecto'
 * (Entrega / PrestacionServicios) y 'descripcion_operacion'.
 */

const SII_NS_SOAP = 'http://schemas.xmlsoap.org/soap/envelope/';
const SII_NS_LR =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/ssii/fact/ws/SuministroLR.xsd';
const SII_NS_INF =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/ssii/fact/ws/SuministroInformacion.xsd';
const SII_ID_VERSION = '1.1';
const SII_TIPO_OPERACION_ENTREGA = 'Entrega';
const SII_TIPO_OPERACION_SERVICIOS = 'PrestacionServicios';
const SII_TIPO_COMUNICACION_ALTA = 'A0';
const SII_TIPO_COMUNICACION_MODIFICACION = 'A1';
const SII_CLAVE_REGIMEN_GENERAL = '01';
const SII_CLAVE_REGIMEN_EXPORTACION = '02';
/* IdOperacionesTrascendenciaTributariaType del XSD v1.1: 01..16 */
const SII_CLAVE_REGIMEN_MAXIMA = 16;
const SII_CODIGO_DUPLICADO = '3000';
const SII_IMPORTE_MINIMO = 0.001;

/* ===================== Etiquetas y formatos ===================== */

/** Elemento del espacio de nombres SuministroInformacion (prefijo sii). */
function sii_etiqueta(string $nombre, string $contenido): string
{
    return '<sii:' . $nombre . '>' . $contenido . '</sii:' . $nombre . '>';
}

/** Elemento del espacio de nombres SuministroLR (prefijo siiLR). */
function sii_etiqueta_lr(string $nombre, string $contenido): string
{
    return '<siiLR:' . $nombre . '>' . $contenido . '</siiLR:' . $nombre . '>';
}

function sii_etiqueta_importe(string $nombre, float $importe): string
{
    return sii_etiqueta($nombre, verifactu_formatear_importe($importe));
}

function sii_mensaje_factura(array $e, string $plantilla): string
{
    return sprintf(t($plantilla), $e['tipo_factura'], $e['serie'], $e['numero']);
}

function sii_es_rectificativa(array $e): bool
{
    return substr((string)$e['tipo_factura'], 0, 1) === 'R';
}

function sii_es_sustitutiva(array $e): bool
{
    return sii_es_rectificativa($e) && $e['tipo_rectificativa'] === 'S';
}

function sii_validar_rectificativa(array $e): void
{
    if (sii_es_rectificativa($e) && $e['tipo_rectificativa'] !== 'I' && $e['tipo_rectificativa'] !== 'S') {
        throw new RuntimeException(sii_mensaje_factura($e,
            'La factura %s %s\\%s es rectificativa y su tipo fiscal debe ser I o S.'));
    }
    if (sii_es_sustitutiva($e) && empty($e['tiene_importe_rectificacion'])) {
        throw new RuntimeException(sii_mensaje_factura($e,
            'La rectificativa sustitutiva %s %s\\%s no tiene los importes de la factura original.'));
    }
}

/* ===================== Cabecera e identificación ===================== */

/** La cabecera de la baja (CabeceraSiiBaja) no lleva TipoComunicacion. */
function sii_cabecera(array $e, string $tipoComunicacion): string
{
    $contenido = sii_etiqueta('IDVersionSii', SII_ID_VERSION) .
        sii_etiqueta('Titular',
            sii_etiqueta('NombreRazon', verifactu_escapar_xml((string)$e['nombre_emisor'])) .
            sii_etiqueta('NIF', verifactu_escapar_xml((string)$e['nif_emisor'])));
    if ($tipoComunicacion !== '') {
        $contenido .= sii_etiqueta('TipoComunicacion', $tipoComunicacion);
    }
    return sii_etiqueta('Cabecera', $contenido);
}

/** Periodo de liquidación = mes de FECHA_FAC. */
function sii_periodo_liquidacion(array $e): string
{
    return sii_etiqueta('PeriodoLiquidacion',
        sii_etiqueta('Ejercicio', substr((string)$e['fecha_iso'], 0, 4)) .
        sii_etiqueta('Periodo', substr((string)$e['fecha_iso'], 5, 2)));
}

function sii_id_factura(array $e): string
{
    return sii_etiqueta_lr('IDFactura',
        sii_etiqueta('IDEmisorFactura', sii_etiqueta('NIF', verifactu_escapar_xml((string)$e['nif_emisor']))) .
        sii_etiqueta('NumSerieFacturaEmisor', verifactu_escapar_xml(
            verifactu_num_serie((string)$e['formato_documento'], (string)$e['serie'], (string)$e['numero']))) .
        sii_etiqueta('FechaExpedicionFacturaEmisor', verifactu_fecha_aeat((string)$e['fecha_iso'])));
}

/* ===================== Rectificación ===================== */

function sii_facturas_rectificadas(array $e): string
{
    if ((string)$e['rect_numero'] === '') {
        return '';
    }
    return sii_etiqueta('FacturasRectificadas',
        sii_etiqueta('IDFacturaRectificada',
            sii_etiqueta('NumSerieFacturaEmisor', verifactu_escapar_xml(
                verifactu_num_serie((string)$e['formato_documento'], (string)$e['rect_serie'], (string)$e['rect_numero']))) .
            sii_etiqueta('FechaExpedicionFacturaEmisor', (string)$e['rect_fecha'])));
}

function sii_importe_rectificacion(array $e): string
{
    if (!sii_es_sustitutiva($e)) {
        return '';
    }
    $contenido = sii_etiqueta_importe('BaseRectificada', (float)$e['rect_base']) .
        sii_etiqueta_importe('CuotaRectificada', (float)$e['rect_cuota']);
    if (abs((float)$e['rect_cuota_re']) > SII_IMPORTE_MINIMO) {
        $contenido .= sii_etiqueta_importe('CuotaRecargoRectificado', (float)$e['rect_cuota_re']);
    }
    return sii_etiqueta('ImporteRectificacion', $contenido);
}

function sii_rectificacion(array $e): string
{
    if (!sii_es_rectificativa($e)) {
        return '';
    }
    return sii_etiqueta('TipoRectificativa', (string)$e['tipo_rectificativa']) .
        sii_facturas_rectificadas($e) . sii_importe_rectificacion($e);
}

/* ===================== Contraparte ===================== */

/** Obligatoria en F1, F3 y R1..R4; F2 y R5 (simplificadas) no la llevan. */
function sii_tiene_contraparte(array $e): bool
{
    return in_array($e['tipo_factura'], ['F1', 'F3', 'R1', 'R2', 'R3', 'R4'], true);
}

/** UE → NIF-IVA (02); resto → documento oficial del país (04). */
function sii_id_otro(array $e): string
{
    if (trim((string)$e['nif_cliente']) === '') {
        throw new RuntimeException(sii_mensaje_factura($e,
            'La factura %s %s\\%s a cliente extranjero requiere el NIF-IVA del destinatario.'));
    }
    return sii_etiqueta('IDOtro',
        sii_etiqueta('CodigoPais', verifactu_escapar_xml((string)$e['pais_cliente_iso2'])) .
        sii_etiqueta('IDType', !empty($e['cliente_ue']) ? '02' : '04') .
        sii_etiqueta('ID', verifactu_escapar_xml((string)$e['nif_cliente'])));
}

function sii_nif_contraparte(array $e): string
{
    if (strlen((string)$e['nif_cliente']) !== 9) {
        throw new RuntimeException(sprintf(
            t('La factura %s %s\\%s requiere un NIF de cliente válido y tiene "%s"'),
            $e['tipo_factura'], $e['serie'], $e['numero'], $e['nif_cliente']));
    }
    return sii_etiqueta('NIF', verifactu_escapar_xml((string)$e['nif_cliente']));
}

function sii_contraparte(array $e): string
{
    if (!sii_tiene_contraparte($e)) {
        return '';
    }
    $identificacion = !empty($e['cliente_extranjero']) ? sii_id_otro($e) : sii_nif_contraparte($e);
    return sii_etiqueta('Contraparte',
        sii_etiqueta('NombreRazon', verifactu_escapar_xml((string)$e['nombre_cliente'])) . $identificacion);
}

/* ===================== Desglose ===================== */

/**
 * Desglose a nivel de operación cuando la contraparte se identifica con
 * IDOtro o con un NIF que empieza por N (aviso 2006). R2 y R3 solo admiten
 * desglose a nivel de factura (error 1322).
 */
function sii_desglose_por_operacion(array $e): bool
{
    return sii_tiene_contraparte($e) && !in_array($e['tipo_factura'], ['R2', 'R3'], true) &&
        (!empty($e['cliente_extranjero']) || stripos(trim((string)$e['nif_cliente']), 'N') === 0);
}

/** Réplica de ResolverReglasOperacionSii (y de ResolverReglasDesglose de VeriFactu). */
function sii_reglas_operacion(array $e): array
{
    $reglas = ['clave_regimen' => SII_CLAVE_REGIMEN_GENERAL, 'calificacion' => '', 'operacion_exenta' => '',
        'repercute_iva' => true];
    if (!empty($e['op_definida'])) {
        if ((string)$e['op_clave_regimen'] !== '') {
            $reglas['clave_regimen'] = (string)$e['op_clave_regimen'];
        }
        $reglas['calificacion'] = (string)$e['op_calificacion'];
        $reglas['operacion_exenta'] = (string)$e['op_operacion_exenta'];
        $reglas['repercute_iva'] = (bool)$e['op_repercute_iva'];
    } elseif (!empty($e['cliente_extranjero']) && empty($e['cliente_ue'])) {
        $reglas['operacion_exenta'] = 'E2';
        $reglas['repercute_iva'] = false;
    }
    return $reglas;
}

/** Con una sola clave 01 el SII no admite E2/E3 de exportación (error 1301): pasa a 02. */
function sii_clave_regimen(array $e, array $reglas): string
{
    $clave = (string)($e['clave_regimen_sii'] ?? '') !== ''
        ? (string)$e['clave_regimen_sii']
        : sii_traducir_clave_regimen($reglas['clave_regimen']);
    if ($clave === SII_CLAVE_REGIMEN_GENERAL && !$reglas['repercute_iva'] &&
        in_array(strtoupper($reglas['operacion_exenta']), ['E2', 'E3'], true)) {
        $clave = SII_CLAVE_REGIMEN_EXPORTACION;
    }
    return $clave;
}

/** La entrega intracomunitaria (E5) no cabe en PrestacionServicios (error 1302). */
function sii_tipo_operacion_desglose(array $e, array $reglas): string
{
    if (!$reglas['repercute_iva'] && strcasecmp($reglas['operacion_exenta'], 'E5') === 0) {
        return SII_TIPO_OPERACION_ENTREGA;
    }
    return (string)$e['tipo_operacion_defecto'];
}

function sii_banda_tiene_importe(array $banda): bool
{
    return abs((float)$banda['base']) > SII_IMPORTE_MINIMO || abs((float)$banda['cuota']) > SII_IMPORTE_MINIMO;
}

/** PrestacionServicios (DetalleIVAEmitidaPrestacionType) no admite recargo. */
function sii_detalle_iva(array $banda, bool $conRecargo): string
{
    $contenido = sii_etiqueta_importe('TipoImpositivo', (float)$banda['porcentaje']) .
        sii_etiqueta_importe('BaseImponible', (float)$banda['base']) .
        sii_etiqueta_importe('CuotaRepercutida', (float)$banda['cuota']);
    if ($conRecargo && abs((float)$banda['cuota_recargo']) > SII_IMPORTE_MINIMO) {
        $contenido .= sii_etiqueta_importe('TipoRecargoEquivalencia', (float)$banda['porcentaje_recargo']) .
            sii_etiqueta_importe('CuotaRecargoEquivalencia', (float)$banda['cuota_recargo']);
    }
    return sii_etiqueta('DetalleIVA', $contenido);
}

function sii_detalle_iva_sin_cuota(float $base): string
{
    return sii_detalle_iva(['porcentaje' => 0.0, 'base' => $base, 'cuota' => 0.0, 'porcentaje_recargo' => 0.0,
        'cuota_recargo' => 0.0], false);
}

function sii_no_exenta(string $tipoNoExenta, string $detalles): string
{
    return sii_etiqueta('NoExenta', sii_etiqueta('TipoNoExenta', $tipoNoExenta) . sii_etiqueta('DesgloseIVA', $detalles));
}

function sii_exenta(string $causa, float $base): string
{
    return sii_etiqueta('Exenta', sii_etiqueta('DetalleExenta',
        sii_etiqueta('CausaExencion', $causa) . sii_etiqueta_importe('BaseImponible', $base)));
}

function sii_tipo_no_exenta(array $reglas): string
{
    return strcasecmp($reglas['calificacion'], 'S2') === 0 ? 'S2' : 'S1';
}

/** Con IVA repercutido: las bandas exentas suman un único E1 y el resto van a DetalleIVA. */
function sii_partes_con_repercusion(array $e, array $reglas, bool $conRecargo): array
{
    $partes = ['exenta' => '', 'no_exenta' => '', 'no_sujeta' => ''];
    $baseExenta = 0.0;
    $hayExenta = false;
    $detalles = '';
    foreach ($e['bandas'] as $banda) {
        if (sii_banda_tiene_importe($banda) && !empty($banda['exenta'])) {
            $baseExenta += (float)$banda['base'];
            $hayExenta = true;
        }
        if (sii_banda_tiene_importe($banda) && empty($banda['exenta'])) {
            $detalles .= sii_detalle_iva($banda, $conRecargo);
        }
    }
    if ($hayExenta) {
        $partes['exenta'] = sii_exenta('E1', $baseExenta);
    }
    if ($detalles !== '') {
        $partes['no_exenta'] = sii_no_exenta(sii_tipo_no_exenta($reglas), $detalles);
    }
    if (!$hayExenta && $detalles === '') {
        $partes['no_exenta'] = sii_no_exenta('S1', sii_detalle_iva_sin_cuota(0.0));
    }
    return $partes;
}

/** Sin repercusión: toda la base va a un solo bloque según la calificación del catálogo. */
function sii_partes_sin_repercusion(array $e, array $reglas): array
{
    $partes = ['exenta' => '', 'no_exenta' => '', 'no_sujeta' => ''];
    $base = 0.0;
    foreach ($e['bandas'] as $banda) {
        $base += (float)$banda['base'];
    }
    if ($reglas['operacion_exenta'] !== '') {
        $partes['exenta'] = sii_exenta($reglas['operacion_exenta'], $base);
    } elseif (strcasecmp($reglas['calificacion'], 'N1') === 0) {
        $partes['no_sujeta'] = sii_etiqueta_importe('ImportePorArticulos7_14_Otros', $base);
    } elseif (strcasecmp($reglas['calificacion'], 'N2') === 0) {
        $partes['no_sujeta'] = sii_etiqueta_importe('ImporteTAIReglasLocalizacion', $base);
    } elseif ($reglas['calificacion'] !== '') {
        $partes['no_exenta'] = sii_no_exenta(sii_tipo_no_exenta($reglas), sii_detalle_iva_sin_cuota($base));
    } else {
        $partes['exenta'] = sii_exenta('E1', $base);
    }
    return $partes;
}

function sii_contenido_desglose(array $partes): string
{
    $contenido = '';
    if ($partes['exenta'] !== '' || $partes['no_exenta'] !== '') {
        $contenido = sii_etiqueta('Sujeta', $partes['exenta'] . $partes['no_exenta']);
    }
    if ($partes['no_sujeta'] !== '') {
        $contenido .= sii_etiqueta('NoSujeta', $partes['no_sujeta']);
    }
    return $contenido;
}

function sii_tipo_desglose(array $e, array $reglas): string
{
    $porOperacion = sii_desglose_por_operacion($e);
    $tipoOperacion = sii_tipo_operacion_desglose($e, $reglas);
    $partes = $reglas['repercute_iva']
        ? sii_partes_con_repercusion($e, $reglas, !$porOperacion || $tipoOperacion === SII_TIPO_OPERACION_ENTREGA)
        : sii_partes_sin_repercusion($e, $reglas);
    $contenido = sii_contenido_desglose($partes);
    $desglose = $porOperacion
        ? sii_etiqueta('DesgloseTipoOperacion', sii_etiqueta($tipoOperacion, $contenido))
        : sii_etiqueta('DesgloseFactura', $contenido);
    return sii_etiqueta('TipoDesglose', $desglose);
}

function sii_factura_expedida(array $e): string
{
    $reglas = sii_reglas_operacion($e);
    return sii_etiqueta_lr('FacturaExpedida',
        sii_etiqueta('TipoFactura', (string)$e['tipo_factura']) .
        sii_rectificacion($e) .
        sii_etiqueta('ClaveRegimenEspecialOTrascendencia', sii_clave_regimen($e, $reglas)) .
        sii_etiqueta_importe('ImporteTotal', (float)$e['importe_total']) .
        sii_etiqueta('DescripcionOperacion', verifactu_escapar_xml((string)$e['descripcion_operacion'])) .
        sii_contraparte($e) .
        sii_tipo_desglose($e, $reglas));
}

/* ===================== Mensajes ===================== */

/** SuministroLRFacturasEmitidas con un único registro. $tipoComunicacion: A0 o A1. */
function sii_suministro_lr_facturas_emitidas(array $e, string $tipoComunicacion): string
{
    sii_validar_rectificativa($e);
    return sii_etiqueta_lr('SuministroLRFacturasEmitidas',
        sii_cabecera($e, $tipoComunicacion) .
        sii_etiqueta_lr('RegistroLRFacturasEmitidas',
            sii_periodo_liquidacion($e) . sii_id_factura($e) . sii_factura_expedida($e)));
}

/** BajaLRFacturasEmitidas con un único RegistroLRBajaExpedidas. */
function sii_baja_lr_facturas_emitidas(array $e): string
{
    return sii_etiqueta_lr('BajaLRFacturasEmitidas',
        sii_cabecera($e, '') .
        sii_etiqueta_lr('RegistroLRBajaExpedidas', sii_periodo_liquidacion($e) . sii_id_factura($e)));
}

function sii_envolver_soap(string $cuerpo): string
{
    return '<?xml version="1.0" encoding="UTF-8"?>' .
        '<soapenv:Envelope xmlns:soapenv="' . SII_NS_SOAP . '" ' .
        'xmlns:siiLR="' . SII_NS_LR . '" ' .
        'xmlns:sii="' . SII_NS_INF . '">' .
        '<soapenv:Header/><soapenv:Body>' . $cuerpo .
        '</soapenv:Body></soapenv:Envelope>';
}

/* ===================== Respuesta ===================== */

/** Texto desde la primera aparición de $etiqueta hasta el final ('' si no aparece). */
function sii_seccion_desde(string $xml, string $etiqueta): string
{
    $inicio = strpos($xml, $etiqueta);
    return $inicio === false ? '' : substr($xml, $inicio);
}

function sii_seccion_hasta(string $xml, string $etiqueta): string
{
    $fin = strpos($xml, $etiqueta);
    return $fin === false ? $xml : substr($xml, 0, $fin);
}

/** Los faults del SII dicen «Codigo[4102].El XML no cumple el esquema...». */
function sii_codigo_fault(string $faultString): string
{
    if (preg_match('/Codigo\[(\d+)\]/', $faultString, $m) === 1) {
        return $m[1];
    }
    return '';
}

/**
 * Interpretación de la respuesta (InterpretarRespuestaSii): claves
 * http_correcto, aceptado, aceptado_con_errores, duplicado, estado_envio,
 * estado_registro, codigo_error, descripcion_error, csv,
 * csv_registro_duplicado, estado_registro_duplicado.
 */
function sii_interpretar_respuesta(int $estadoHttp, string $xml): array
{
    $r = [
        /* Un fault con HTTP 200 se lee como fault (FZ-ISSUE-308). */
        'http_correcto' => $estadoHttp === 200 && !sii_es_fault($xml), 'aceptado' => false, 'aceptado_con_errores' => false,
        'duplicado' => false, 'estado_envio' => '', 'estado_registro' => '', 'codigo_error' => '',
        'descripcion_error' => '', 'csv' => '', 'csv_registro_duplicado' => '', 'estado_registro_duplicado' => '',
    ];
    if (!$r['http_correcto']) {
        $r['descripcion_error'] = verifactu_extraer_etiqueta($xml, 'faultstring');
        $r['codigo_error'] = sii_codigo_fault($r['descripcion_error']);
        return $r;
    }
    /* La cabecera, su RespuestaLinea y el RegistroDuplicado repiten CSV y EstadoRegistro. */
    $cabecera = sii_seccion_hasta($xml, 'RespuestaLinea>');
    $linea = sii_seccion_desde($xml, 'RespuestaLinea>');
    $duplicado = sii_seccion_desde($linea, 'RegistroDuplicado>');
    $r['estado_envio'] = verifactu_extraer_etiqueta($cabecera, 'EstadoEnvio');
    $r['csv'] = verifactu_extraer_etiqueta($cabecera, 'CSV');
    $r['estado_registro'] = verifactu_extraer_etiqueta($linea, 'EstadoRegistro');
    $r['codigo_error'] = verifactu_extraer_etiqueta($linea, 'CodigoErrorRegistro');
    $r['descripcion_error'] = verifactu_extraer_etiqueta($linea, 'DescripcionErrorRegistro');
    $r['csv_registro_duplicado'] = verifactu_extraer_etiqueta(sii_seccion_hasta($linea, 'RegistroDuplicado>'), 'CSV');
    $r['estado_registro_duplicado'] = verifactu_extraer_etiqueta($duplicado, 'EstadoRegistro');
    if ($r['estado_registro'] === '') {
        $r['estado_registro'] = $r['estado_envio'];
    }
    $r['duplicado'] = $duplicado !== '' || $r['codigo_error'] === SII_CODIGO_DUPLICADO ||
        stripos($r['descripcion_error'], 'duplic') !== false;
    $r['aceptado_con_errores'] = strcasecmp($r['estado_registro'], 'AceptadoConErrores') === 0;
    /* Un duplicado de una factura anulada en el SII no la deja registrada. */
    $r['aceptado'] = strcasecmp($r['estado_registro'], 'Correcto') === 0 || $r['aceptado_con_errores'] ||
        ($r['duplicado'] && strcasecmp($r['estado_registro_duplicado'], 'Anulada') !== 0);
    return $r;
}

/** SOAP Fault sin respuesta del suministro (con HTTP 200 o 500). */
function sii_es_fault(string $xml): bool
{
    return verifactu_extraer_etiqueta($xml, 'faultstring') !== '' &&
        verifactu_extraer_etiqueta($xml, 'EstadoEnvio') === '';
}

/**
 * Respuesta del servicio que resuelve el envío (EsRespuestaSiiDefinitiva):
 * HTTP 200 con EstadoEnvio, o SOAP Fault con HTTP 200 o 500 (FZ-ISSUE-308:
 * un fault con 200 se reintentaba sin fin sin gastar intento).
 */
function sii_respuesta_definitiva(int $estadoHttp, string $xml): bool
{
    if ($estadoHttp === 200 && verifactu_extraer_etiqueta($xml, 'EstadoEnvio') !== '') {
        return true;
    }
    return in_array($estadoHttp, [200, 500], true) && verifactu_extraer_etiqueta($xml, 'faultstring') !== '';
}

/** Página web (portal, proxy, certificado) en lugar de un mensaje SOAP (EsPaginaWebSii). */
function sii_es_pagina_web(string $cuerpo): bool
{
    return stripos($cuerpo, '<html') !== false || stripos($cuerpo, '<!DOCTYPE html') !== false;
}

/**
 * Lo que contestó el servicio, para el mensaje de la cola (ExtractoRespuestaSii):
 * el faultstring, el título de una página web o el principio del cuerpo en
 * una línea (como mucho 300 caracteres).
 */
function sii_extracto_respuesta(string $cuerpo): string
{
    $extracto = verifactu_extraer_etiqueta($cuerpo, 'faultstring');
    if ($extracto === '' && sii_es_pagina_web($cuerpo)) {
        $extracto = verifactu_extraer_etiqueta($cuerpo, 'title');
    }
    if ($extracto === '') {
        $extracto = mb_substr(trim(str_replace(["\t", "\n", "\r"], ' ', $cuerpo)), 0, 300);
    }
    return $extracto;
}

/**
 * Rechazo por los datos del registro: reenviarlo daría lo mismo
 * (EsRechazoDefinitivoSii; criterio en inLibSiiConstruccionEnvio).
 */
function sii_rechazo_definitivo(string $estadoRegistro, string $codigoError): bool
{
    $codigo = is_numeric(trim($codigoError)) ? (int)trim($codigoError) : 0;
    $definitivo = ($codigo >= 1000 && $codigo <= 1999 && $codigo !== 1184 && $codigo !== 1266) ||
        ($codigo >= 3001 && $codigo <= 3499) || $codigo === 3902;
    return strcasecmp(trim($estadoRegistro), 'Incorrecto') === 0 && $definitivo;
}

/** Valor del parámetro appSiiTipoOperacionDefecto. */
function sii_tipo_operacion_desde_texto(string $texto): string
{
    foreach ([SII_TIPO_OPERACION_ENTREGA, SII_TIPO_OPERACION_SERVICIOS] as $tipo) {
        if (strcasecmp(trim($texto), $tipo) === 0) {
            return $tipo;
        }
    }
    throw new RuntimeException(sprintf(
        t('El tipo de operación SII "%s" no es válido: use Entrega o PrestacionServicios.'), $texto));
}

/**
 * Clave de régimen VeriFactu → ClaveRegimenEspecialOTrascendencia del SII:
 * 01..16 tal cual; 17..20 y cualquier valor no válido, régimen general 01.
 */
function sii_traducir_clave_regimen(string $claveVerifactu): string
{
    $clave = trim($claveVerifactu);
    $numero = ctype_digit($clave) ? (int)$clave : 0;
    return strlen($clave) === 2 && $numero >= 1 && $numero <= SII_CLAVE_REGIMEN_MAXIMA
        ? $clave
        : SII_CLAVE_REGIMEN_GENERAL;
}
