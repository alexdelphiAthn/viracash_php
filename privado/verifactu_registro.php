<?php
declare(strict_types=1);

/* El IRPF no interviene en el registro ni en el QR tributario. */
function verifactu_importe_total(array $factura): float
{
    if (!isset($factura['TOTAL_BASES_FAC'], $factura['TOTAL_IMPUESTOS_FAC'])) {
        throw new RuntimeException('Faltan base e impuestos para el importe VeriFactu.');
    }
    return (float)$factura['TOTAL_BASES_FAC'] + (float)$factura['TOTAL_IMPUESTOS_FAC'];
}


/*
 * Construcción del registro de facturación Verifactu sin acceso a la base
 * de datos: huella SHA-256 encadenada, XML del RegistroAlta (esquemas
 * SuministroLR / SuministroInformacion), desglose fiscal, bloque
 * SistemaInformatico, sobre SOAP, URL del QR tributario e interpretación de la
 * respuesta de la AEAT. Es una transcripción de inLibVerifactu,
 * inLibVerifactuConstruccionEnvio, inLibVerifactuDesgloseFiscal e
 * inLibVerifactuEnvio del programa: mismos campos, mismo orden y mismos textos,
 * de modo que el registro y la huella coinciden con los que generaría ViraCash.
 */

const VERIFACTU_NS_SOAP = 'http://schemas.xmlsoap.org/soap/envelope/';
const VERIFACTU_NS_LR =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroLR.xsd';
const VERIFACTU_NS_INF =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/SuministroInformacion.xsd';
const VERIFACTU_NS_DSIG = 'http://www.w3.org/2000/09/xmldsig#';

const VERIFACTU_SIF_NOMBRE = 'ViraCash';
const VERIFACTU_SIF_ID = 'FZ';

/* Fases de fza_facturas.FASE_FAC (inLibVerifactu). */
const FASE_FACTURA_BORRADOR = 'BORRADOR';
const FASE_FACTURA_SIN_VERIFACTU = 'SIN_VERIFACTU';
const FASE_FACTURA_VERIFACTU_PENDIENTE = 'VERIFACTU_PENDIENTE';
const FASE_FACTURA_VERIFACTU_OK = 'VERIFACTU_OK';
const FASE_FACTURA_VERIFACTU_ERROR = 'VERIFACTU_ERROR';
const FASE_FACTURA_VERIFACTU_ANULADA = 'VERIFACTU_ANULADA';

/* ===================== Formatos ===================== */

/** Instante con huso horario: yyyy-mm-ddThh:nn:ss+hh:mm (FechaHoraHusoGen). */
function verifactu_fecha_hora_huso(DateTimeInterface $instante): string
{
    return $instante->format('Y-m-d\TH:i:sP');
}

/** Importe con dos decimales y punto (FormatearImporteVerifactu). */
function verifactu_formatear_importe(float $importe): string
{
    $texto = number_format($importe, 2, '.', '');
    return $texto === '-0.00' ? '0.00' : $texto;
}

/** Solo letras A-Z y dígitos, en mayúsculas (NormalizarNifVerifactu). */
function verifactu_normalizar_nif(string $valor): string
{
    return preg_replace('/[^A-Z0-9]/', '', strtoupper(trim($valor))) ?? '';
}

/**
 * Número de la factura tal como figura en ella: serie y número con el
 * separador del formato de documento de la empresa (FORMATO_DOCUMENTO_EMP),
 * igual que ComponerNumSerieFactura / FormatearDocumento de Delphi.
 */
function verifactu_num_serie(string $formato, string $serie, string $numero): string
{
    $serie = trim($serie);
    $numero = trim($numero);
    if ($serie === '') {
        return $numero;
    }
    if ($numero === '') {
        return $serie;
    }
    $formato = trim($formato);
    $tokens = ['NroDocumento', 'NumeroDocumento', 'NúmeroDocumento', 'NroFactura', 'NroDoc', 'Numero', 'Número'];
    $conToken = false;
    foreach (array_merge($tokens, ['Serie', 'serie', 'SERIE']) as $token) {
        $conToken = $conToken || str_contains($formato, $token);
    }
    if (!$conToken) {
        $formato = 'Serie.NroDocumento';
    }
    foreach ($tokens as $token) {
        $formato = str_ireplace($token, $numero, $formato);
    }
    return str_ireplace('Serie', $serie, $formato);
}

/** Fecha ISO (yyyy-mm-dd...) a dd-mm-yyyy, formato de la AEAT. */
function verifactu_fecha_aeat(string $fechaIso): string
{
    $fecha = DateTimeImmutable::createFromFormat('Y-m-d', substr($fechaIso, 0, 10));
    if ($fecha === false) {
        throw new RuntimeException("Fecha de factura no válida: $fechaIso");
    }
    return $fecha->format('d-m-Y');
}

/** Percent-encoding RFC 3986 (CodificarParametroURL): solo quedan A-Z a-z 0-9 - . _ ~ . */
function verifactu_codificar_url(string $valor): string
{
    return rawurlencode($valor);
}

/** URL de cotejo del QR tributario (ConstruirUrlQR). $fechaIso en yyyy-mm-dd. */
function verifactu_url_qr(string $base, string $nif, string $formato, string $serie, string $numero, string $fechaIso, float $importeTotal): string
{
    return $base .
        '?nif=' . verifactu_codificar_url(verifactu_normalizar_nif($nif)) .
        '&numserie=' . verifactu_codificar_url(verifactu_num_serie($formato, $serie, $numero)) .
        '&fecha=' . verifactu_codificar_url(verifactu_fecha_aeat($fechaIso)) .
        '&importe=' . verifactu_codificar_url(verifactu_formatear_importe($importeTotal));
}

function verifactu_escapar_xml(string $valor): string
{
    return str_replace(['&', '<', '>', '"', "'"], ['&amp;', '&lt;', '&gt;', '&quot;', '&apos;'], $valor);
}

/** TipoFactura Verifactu a partir de TIPO_FAC (TipoFacturaVerifactu). */
function verifactu_tipo_factura(string $tipoFac): string
{
    $tipo = strtoupper(trim($tipoFac));
    if ($tipo === 'SIMPLIFICADA') {
        return 'F2';
    }
    if ($tipo === 'RECTIFICATIVA') {
        return 'R5';
    }
    return 'F1';
}

/* ===================== Huellas ===================== */

/** Huella SHA-256 del registro de alta (CalcularHuellaAlta): orden y formato fijados por la AEAT. */
function verifactu_huella_alta(array $e): string
{
    return strtoupper(hash('sha256',
        'IDEmisorFactura=' . $e['nif_emisor'] .
        '&NumSerieFactura=' . $e['num_serie_factura'] .
        '&FechaExpedicionFactura=' . $e['fecha_expedicion'] .
        '&TipoFactura=' . $e['tipo_factura'] .
        '&CuotaTotal=' . $e['cuota_total'] .
        '&ImporteTotal=' . $e['importe_total'] .
        '&Huella=' . $e['huella_anterior'] .
        '&FechaHoraHusoGenRegistro=' . $e['fecha_hora_huso']));
}

/* ===================== Desglose fiscal (inLibVerifactuDesgloseFiscal) ===================== */

/**
 * $entrada: ['operacion' => ['definida', 'clave_regimen', 'calificacion',
 * 'operacion_exenta', 'repercute_iva', 'cliente_ue', 'cliente_extranjero'],
 * 'bandas' => 4 x ['porcentaje', 'base', 'cuota', 'porcentaje_recargo',
 * 'cuota_recargo', 'exenta']].
 */
function verifactu_desglose_fiscal(array $entrada): string
{
    $op = $entrada['operacion'];
    $reglas = ['clave_regimen' => '01', 'calificacion' => '', 'operacion_exenta' => '', 'repercute_iva' => true];
    if (!empty($op['definida'])) {
        if ((string)$op['clave_regimen'] !== '') {
            $reglas['clave_regimen'] = (string)$op['clave_regimen'];
        }
        $reglas['calificacion'] = (string)$op['calificacion'];
        $reglas['operacion_exenta'] = (string)$op['operacion_exenta'];
        $reglas['repercute_iva'] = (bool)$op['repercute_iva'];
    } elseif (!empty($op['cliente_extranjero']) && empty($op['cliente_ue'])) {
        $reglas['operacion_exenta'] = 'E2';
        $reglas['repercute_iva'] = false;
    }
    $xml = '';
    if (!$reglas['repercute_iva']) {
        $baseTotal = 0.0;
        foreach ($entrada['bandas'] as $banda) {
            $baseTotal += (float)$banda['base'];
        }
        if ($reglas['operacion_exenta'] !== '') {
            $calificacion = '<sum1:OperacionExenta>' . $reglas['operacion_exenta'] . '</sum1:OperacionExenta>';
        } elseif ($reglas['calificacion'] !== '') {
            $calificacion = '<sum1:CalificacionOperacion>' . $reglas['calificacion'] . '</sum1:CalificacionOperacion>';
        } else {
            $calificacion = '<sum1:OperacionExenta>E1</sum1:OperacionExenta>';
        }
        $xml = '<sum1:DetalleDesglose><sum1:Impuesto>01</sum1:Impuesto>' .
            '<sum1:ClaveRegimen>' . $reglas['clave_regimen'] . '</sum1:ClaveRegimen>' .
            $calificacion .
            '<sum1:BaseImponibleOimporteNoSujeto>' . verifactu_formatear_importe($baseTotal) .
            '</sum1:BaseImponibleOimporteNoSujeto></sum1:DetalleDesglose>';
    } else {
        foreach ($entrada['bandas'] as $banda) {
            if (abs((float)$banda['base']) <= 0.001 && abs((float)$banda['cuota']) <= 0.001) {
                continue;
            }
            $detalle = '<sum1:Impuesto>01</sum1:Impuesto>' .
                '<sum1:ClaveRegimen>' . $reglas['clave_regimen'] . '</sum1:ClaveRegimen>';
            if (!empty($banda['exenta'])) {
                $detalle .= '<sum1:OperacionExenta>E1</sum1:OperacionExenta>' .
                    '<sum1:BaseImponibleOimporteNoSujeto>' . verifactu_formatear_importe((float)$banda['base']) .
                    '</sum1:BaseImponibleOimporteNoSujeto>';
            } else {
                $calificacion = $reglas['calificacion'] !== '' ? $reglas['calificacion'] : 'S1';
                $detalle .= '<sum1:CalificacionOperacion>' . $calificacion . '</sum1:CalificacionOperacion>' .
                    '<sum1:TipoImpositivo>' . verifactu_formatear_importe((float)$banda['porcentaje']) . '</sum1:TipoImpositivo>' .
                    '<sum1:BaseImponibleOimporteNoSujeto>' . verifactu_formatear_importe((float)$banda['base']) .
                    '</sum1:BaseImponibleOimporteNoSujeto>' .
                    '<sum1:CuotaRepercutida>' . verifactu_formatear_importe((float)$banda['cuota']) . '</sum1:CuotaRepercutida>';
                if (abs((float)$banda['cuota_recargo']) > 0.001) {
                    $detalle .= '<sum1:TipoRecargoEquivalencia>' . verifactu_formatear_importe((float)$banda['porcentaje_recargo']) .
                        '</sum1:TipoRecargoEquivalencia>' .
                        '<sum1:CuotaRecargoEquivalencia>' . verifactu_formatear_importe((float)$banda['cuota_recargo']) .
                        '</sum1:CuotaRecargoEquivalencia>';
                }
            }
            $xml .= '<sum1:DetalleDesglose>' . $detalle . '</sum1:DetalleDesglose>';
        }
    }
    if ($xml === '') {
        $xml = '<sum1:DetalleDesglose><sum1:Impuesto>01</sum1:Impuesto><sum1:ClaveRegimen>01</sum1:ClaveRegimen>' .
            '<sum1:CalificacionOperacion>S1</sum1:CalificacionOperacion><sum1:TipoImpositivo>0.00</sum1:TipoImpositivo>' .
            '<sum1:BaseImponibleOimporteNoSujeto>0.00</sum1:BaseImponibleOimporteNoSujeto>' .
            '<sum1:CuotaRepercutida>0.00</sum1:CuotaRepercutida></sum1:DetalleDesglose>';
    }
    return $xml;
}

/* ===================== Registro de alta (inLibVerifactuConstruccionEnvio) ===================== */

/** Bloque SistemaInformatico del registro (ConstruirSistemaInformatico). */
function verifactu_sistema_informatico_xml(
    string $nombreProductor,
    string $nifProductor,
    string $version,
    string $numeroInstalacion,
    string $multiOt
): string {
    return '<sum1:SistemaInformatico>' .
        '<sum1:NombreRazon>' . verifactu_escapar_xml($nombreProductor) . '</sum1:NombreRazon>' .
        '<sum1:NIF>' . verifactu_escapar_xml($nifProductor) . '</sum1:NIF>' .
        '<sum1:NombreSistemaInformatico>' . VERIFACTU_SIF_NOMBRE . '</sum1:NombreSistemaInformatico>' .
        '<sum1:IdSistemaInformatico>' . VERIFACTU_SIF_ID . '</sum1:IdSistemaInformatico>' .
        '<sum1:Version>' . verifactu_escapar_xml($version) . '</sum1:Version>' .
        '<sum1:NumeroInstalacion>' . verifactu_escapar_xml($numeroInstalacion) . '</sum1:NumeroInstalacion>' .
        '<sum1:TipoUsoPosibleSoloVerifactu>N</sum1:TipoUsoPosibleSoloVerifactu>' .
        '<sum1:TipoUsoPosibleMultiOT>S</sum1:TipoUsoPosibleMultiOT>' .
        '<sum1:IndicadorMultiplesOT>' . $multiOt . '</sum1:IndicadorMultiplesOT>' .
        '</sum1:SistemaInformatico>';
}

/**
 * XML y huella del RegistroAlta (ConstruirRegistroAltaVerifactu). Claves de
 * $e: serie, numero, num_serie_factura, nif_emisor, nombre_emisor,
 * fecha_expedicion (dd-mm-yyyy), tipo_factura, tipo_rectificativa, rect_numero,
 * rect_num_serie_factura, rect_fecha, rect_base, rect_cuota, rect_cuota_re,
 * tiene_rect_cuota_re, tiene_importe_rectificacion, nif_cliente,
 * nombre_cliente, pais_cliente_iso2, cliente_ue, cliente_extranjero,
 * cuota_total, importe_total, cadena_num_serie_factura, cadena_fecha,
 * huella_anterior, fecha_hora_huso, sistema_informatico_xml, desglose_xml,
 * descripcion_operacion, subsanacion.
 */
function verifactu_registro_alta(array $e): array
{
    $esRectificativa = substr((string)$e['tipo_factura'], 0, 1) === 'R';
    if ($esRectificativa && $e['tipo_rectificativa'] !== 'I' && $e['tipo_rectificativa'] !== 'S') {
        throw new RuntimeException('El tipo fiscal de rectificativa debe ser I o S.');
    }
    if ($esRectificativa && $e['tipo_rectificativa'] === 'S' && empty($e['tiene_importe_rectificacion'])) {
        throw new RuntimeException('La rectificativa sustitutiva no tiene los importes originales.');
    }
    $huella = verifactu_huella_alta($e);
    $nif = verifactu_escapar_xml((string)$e['nif_emisor']);

    $rectificativa = '';
    $facturasRectificadas = '';
    $importeRectificacion = '';
    $fechaOperacion = '';
    if ($esRectificativa) {
        $rectificativa = '<sum1:TipoRectificativa>' . $e['tipo_rectificativa'] . '</sum1:TipoRectificativa>';
        if ((string)$e['rect_numero'] !== '') {
            $facturasRectificadas = '<sum1:FacturasRectificadas><sum1:IDFacturaRectificada>' .
                '<sum1:IDEmisorFactura>' . $nif . '</sum1:IDEmisorFactura>' .
                '<sum1:NumSerieFactura>' . verifactu_escapar_xml((string)$e['rect_num_serie_factura']) . '</sum1:NumSerieFactura>' .
                '<sum1:FechaExpedicionFactura>' . $e['rect_fecha'] . '</sum1:FechaExpedicionFactura>' .
                '</sum1:IDFacturaRectificada></sum1:FacturasRectificadas>';
        }
        if ($e['tipo_rectificativa'] === 'S') {
            $importeRectificacion = '<sum1:ImporteRectificacion>' .
                '<sum1:BaseRectificada>' . $e['rect_base'] . '</sum1:BaseRectificada>' .
                '<sum1:CuotaRectificada>' . $e['rect_cuota'] . '</sum1:CuotaRectificada>';
            if (!empty($e['tiene_rect_cuota_re'])) {
                $importeRectificacion .= '<sum1:CuotaRecargoRectificado>' . $e['rect_cuota_re'] . '</sum1:CuotaRecargoRectificado>';
            }
            $importeRectificacion .= '</sum1:ImporteRectificacion>';
        }
        if ((string)$e['rect_fecha'] !== '') {
            $fechaOperacion = '<sum1:FechaOperacion>' . $e['rect_fecha'] . '</sum1:FechaOperacion>';
        }
    }
    $facturasSustituidas = '';
    if ($e['tipo_factura'] === 'F3' && (string)$e['rect_numero'] !== '') {
        $facturasSustituidas = '<sum1:FacturasSustituidas><sum1:IDFacturaSustituida>' .
            '<sum1:IDEmisorFactura>' . $nif . '</sum1:IDEmisorFactura>' .
            '<sum1:NumSerieFactura>' . verifactu_escapar_xml((string)$e['rect_num_serie_factura']) . '</sum1:NumSerieFactura>' .
            '<sum1:FechaExpedicionFactura>' . $e['rect_fecha'] . '</sum1:FechaExpedicionFactura>' .
            '</sum1:IDFacturaSustituida></sum1:FacturasSustituidas>';
    }

    $destinatarios = '';
    if (in_array($e['tipo_factura'], ['F1', 'R1', 'F3'], true)) {
        if (!empty($e['cliente_extranjero'])) {
            if (trim((string)$e['nif_cliente']) === '') {
                throw new RuntimeException(sprintf(
                    'La factura %s %s\\%s a cliente extranjero requiere el NIF-IVA del destinatario.',
                    $e['tipo_factura'], $e['serie'], $e['numero']));
            }
            $destinatarios = '<sum1:Destinatarios><sum1:IDDestinatario>' .
                '<sum1:NombreRazon>' . verifactu_escapar_xml((string)$e['nombre_cliente']) . '</sum1:NombreRazon>' .
                '<sum1:IDOtro><sum1:CodigoPais>' . verifactu_escapar_xml((string)$e['pais_cliente_iso2']) . '</sum1:CodigoPais>' .
                '<sum1:IDType>' . (!empty($e['cliente_ue']) ? '02' : '04') . '</sum1:IDType>' .
                '<sum1:ID>' . verifactu_escapar_xml((string)$e['nif_cliente']) . '</sum1:ID>' .
                '</sum1:IDOtro></sum1:IDDestinatario></sum1:Destinatarios>';
        } else {
            if (strlen((string)$e['nif_cliente']) !== 9) {
                throw new RuntimeException(sprintf(
                    'La factura %s %s\\%s requiere un NIF de cliente válido y tiene "%s"',
                    $e['tipo_factura'], $e['serie'], $e['numero'], $e['nif_cliente']));
            }
            $destinatarios = '<sum1:Destinatarios><sum1:IDDestinatario>' .
                '<sum1:NombreRazon>' . verifactu_escapar_xml((string)$e['nombre_cliente']) . '</sum1:NombreRazon>' .
                '<sum1:NIF>' . verifactu_escapar_xml((string)$e['nif_cliente']) . '</sum1:NIF>' .
                '</sum1:IDDestinatario></sum1:Destinatarios>';
        }
    }

    if ((string)$e['huella_anterior'] === '') {
        $encadenamiento = '<sum1:Encadenamiento><sum1:PrimerRegistro>S</sum1:PrimerRegistro></sum1:Encadenamiento>';
    } else {
        $encadenamiento = '<sum1:Encadenamiento><sum1:RegistroAnterior>' .
            '<sum1:IDEmisorFactura>' . $nif . '</sum1:IDEmisorFactura>' .
            '<sum1:NumSerieFactura>' . verifactu_escapar_xml((string)$e['cadena_num_serie_factura']) . '</sum1:NumSerieFactura>' .
            '<sum1:FechaExpedicionFactura>' . $e['cadena_fecha'] . '</sum1:FechaExpedicionFactura>' .
            '<sum1:Huella>' . $e['huella_anterior'] . '</sum1:Huella>' .
            '</sum1:RegistroAnterior></sum1:Encadenamiento>';
    }

    $xml = '<sum1:RegistroAlta><sum1:IDVersion>1.0</sum1:IDVersion>' .
        '<sum1:IDFactura><sum1:IDEmisorFactura>' . $nif . '</sum1:IDEmisorFactura>' .
        '<sum1:NumSerieFactura>' . verifactu_escapar_xml((string)$e['num_serie_factura']) . '</sum1:NumSerieFactura>' .
        '<sum1:FechaExpedicionFactura>' . $e['fecha_expedicion'] . '</sum1:FechaExpedicionFactura></sum1:IDFactura>' .
        '<sum1:NombreRazonEmisor>' . verifactu_escapar_xml((string)$e['nombre_emisor']) . '</sum1:NombreRazonEmisor>' .
        (!empty($e['subsanacion']) ? '<sum1:Subsanacion>S</sum1:Subsanacion>' : '') .
        '<sum1:TipoFactura>' . $e['tipo_factura'] . '</sum1:TipoFactura>' .
        $rectificativa . $facturasRectificadas . $facturasSustituidas . $importeRectificacion . $fechaOperacion .
        '<sum1:DescripcionOperacion>' . verifactu_escapar_xml((string)$e['descripcion_operacion']) . '</sum1:DescripcionOperacion>' .
        $destinatarios .
        '<sum1:Desglose>' . $e['desglose_xml'] . '</sum1:Desglose>' .
        '<sum1:CuotaTotal>' . $e['cuota_total'] . '</sum1:CuotaTotal>' .
        '<sum1:ImporteTotal>' . $e['importe_total'] . '</sum1:ImporteTotal>' .
        $encadenamiento . $e['sistema_informatico_xml'] .
        '<sum1:FechaHoraHusoGenRegistro>' . $e['fecha_hora_huso'] . '</sum1:FechaHoraHusoGenRegistro>' .
        '<sum1:TipoHuella>01</sum1:TipoHuella><sum1:Huella>' . $huella . '</sum1:Huella></sum1:RegistroAlta>';
    return ['xml' => $xml, 'huella' => $huella];
}

/** Registro de anulación y huella, con el mismo encadenamiento que Delphi. */
function verifactu_registro_anulacion(array $datos, array $cadena, string $sif, string $instante): array
{
    $nif = $datos['nif_emisor'];
    $formato = (string)($datos['formato_documento'] ?? '');
    $numero = verifactu_num_serie($formato, $datos['serie'], $datos['numero']);
    $fecha = $datos['fecha_expedicion'];
    $huella = strtoupper(hash('sha256', 'IDEmisorFacturaAnulada=' . $nif .
        '&NumSerieFacturaAnulada=' . $numero . '&FechaExpedicionFacturaAnulada=' . $fecha .
        '&Huella=' . $cadena['huella'] . '&FechaHoraHusoGenRegistro=' . $instante));
    $anterior = $cadena['huella'] === '' ? '<sum1:PrimerRegistro>S</sum1:PrimerRegistro>' :
        '<sum1:RegistroAnterior><sum1:IDEmisorFactura>' . verifactu_escapar_xml($nif) .
        '</sum1:IDEmisorFactura><sum1:NumSerieFactura>' .
        verifactu_escapar_xml(verifactu_num_serie($formato, $cadena['serie'], $cadena['numero'])) .
        '</sum1:NumSerieFactura><sum1:FechaExpedicionFactura>' . $cadena['fecha'] .
        '</sum1:FechaExpedicionFactura><sum1:Huella>' . $cadena['huella'] .
        '</sum1:Huella></sum1:RegistroAnterior>';
    $xml = '<sum1:RegistroAnulacion><sum1:IDVersion>1.0</sum1:IDVersion><sum1:IDFactura>' .
        '<sum1:IDEmisorFacturaAnulada>' . verifactu_escapar_xml($nif) . '</sum1:IDEmisorFacturaAnulada>' .
        '<sum1:NumSerieFacturaAnulada>' . verifactu_escapar_xml($numero) . '</sum1:NumSerieFacturaAnulada>' .
        '<sum1:FechaExpedicionFacturaAnulada>' . $fecha . '</sum1:FechaExpedicionFacturaAnulada>' .
        '</sum1:IDFactura><sum1:Encadenamiento>' . $anterior . '</sum1:Encadenamiento>' . $sif .
        '<sum1:FechaHoraHusoGenRegistro>' . $instante . '</sum1:FechaHoraHusoGenRegistro>' .
        '<sum1:TipoHuella>01</sum1:TipoHuella><sum1:Huella>' . $huella . '</sum1:Huella></sum1:RegistroAnulacion>';
    return ['xml' => $xml, 'huella' => $huella];
}

function verifactu_envolver_soap(string $nombreEmisor, string $nifEmisor, string $registroXml): string
{
    return '<?xml version="1.0" encoding="UTF-8"?>' .
        '<soapenv:Envelope xmlns:soapenv="' . VERIFACTU_NS_SOAP . '" ' .
        'xmlns:sum="' . VERIFACTU_NS_LR . '" xmlns:sum1="' . VERIFACTU_NS_INF . '">' .
        '<soapenv:Header/><soapenv:Body><sum:RegFactuSistemaFacturacion>' .
        '<sum:Cabecera><sum1:ObligadoEmision>' .
        '<sum1:NombreRazon>' . verifactu_escapar_xml($nombreEmisor) . '</sum1:NombreRazon>' .
        '<sum1:NIF>' . verifactu_escapar_xml($nifEmisor) . '</sum1:NIF>' .
        '</sum1:ObligadoEmision></sum:Cabecera>' .
        '<sum:RegistroFactura>' . $registroXml . '</sum:RegistroFactura>' .
        '</sum:RegFactuSistemaFacturacion></soapenv:Body></soapenv:Envelope>';
}

/** XML del registro con sus espacios de nombres, tal como se guarda en REGISTRO_XML_FACCON. */
function verifactu_registro_con_namespaces(string $registroXml, string $raiz = 'RegistroAlta'): string
{
    $apertura = '<sum1:' . $raiz . '>';
    $nueva = '<sum1:' . $raiz . ' xmlns:sum1="' . VERIFACTU_NS_INF . '" xmlns:ds="' . VERIFACTU_NS_DSIG . '">';
    $posicion = strpos($registroXml, $apertura);
    if ($posicion !== false) {
        $registroXml = substr_replace($registroXml, $nueva, $posicion, strlen($apertura));
    }
    return '<?xml version="1.0" encoding="UTF-8"?>' . $registroXml;
}

/* ===================== Respuesta de la AEAT ===================== */

/** Texto de la primera etiqueta con ese nombre local, con o sin prefijo (ExtraerEtiqueta). */
function verifactu_extraer_etiqueta(string $xml, string $etiqueta): string
{
    $apertura = $etiqueta . '>';
    $inicio = strpos($xml, '<' . $apertura);
    if ($inicio !== false) {
        $inicio += strlen($apertura) + 1;
    } else {
        $inicio = strpos($xml, ':' . $apertura);
        if ($inicio !== false) {
            $inicio += strlen($apertura) + 1;
        }
    }
    if ($inicio === false) {
        return '';
    }
    $fin = strpos($xml, '<', $inicio);
    if ($fin === false || $fin <= $inicio) {
        return '';
    }
    return trim(substr($xml, $inicio, $fin - $inicio));
}

/**
 * Interpretación de la respuesta SOAP (InterpretarRespuestaAeat): claves
 * http_correcto, aceptado, duplicado, estado_envio, estado_registro,
 * codigo_error, descripcion_error, espera_segundos, csv.
 */
function verifactu_interpretar_respuesta(int $estadoHttp, string $xml): array
{
    $r = [
        'http_correcto' => $estadoHttp === 200,
        'aceptado' => false,
        'duplicado' => false,
        'estado_envio' => '',
        'estado_registro' => '',
        'codigo_error' => '',
        'descripcion_error' => '',
        'espera_segundos' => 0,
        'csv' => '',
    ];
    if (!$r['http_correcto']) {
        $r['descripcion_error'] = verifactu_extraer_etiqueta($xml, 'faultstring');
        return $r;
    }
    $r['estado_envio'] = verifactu_extraer_etiqueta($xml, 'EstadoEnvio');
    $r['estado_registro'] = verifactu_extraer_etiqueta($xml, 'EstadoRegistro');
    $r['codigo_error'] = verifactu_extraer_etiqueta($xml, 'CodigoErrorRegistro');
    $r['descripcion_error'] = verifactu_extraer_etiqueta($xml, 'DescripcionErrorRegistro');
    $espera = verifactu_extraer_etiqueta($xml, 'TiempoEsperaEnvio');
    $r['espera_segundos'] = is_numeric($espera) ? (int)$espera : 0;
    $r['csv'] = verifactu_extraer_etiqueta($xml, 'CSV');
    if ($r['estado_registro'] === '') {
        $r['estado_registro'] = $r['estado_envio'];
    }
    $r['duplicado'] = $r['codigo_error'] === '3000' ||
        stripos($r['descripcion_error'], 'duplicado') !== false;
    $r['aceptado'] = strcasecmp($r['estado_envio'], 'Correcto') === 0 ||
        strcasecmp($r['estado_registro'], 'Correcto') === 0 ||
        strcasecmp($r['estado_registro'], 'AceptadoConErrores') === 0 ||
        $r['duplicado'];
    return $r;
}

/* ===================== Reintentos (inLibVerifactuReintentos) ===================== */

function verifactu_espera_reintento(int $intentos): int
{
    return $intentos > 5 ? 60 * 32 : 60 * (1 << $intentos);
}

function verifactu_estado_reintento(int $intentos, int $maxIntentos): string
{
    return ($intentos + 1) >= $maxIntentos ? 'ERROR' : 'PENDIENTE';
}
