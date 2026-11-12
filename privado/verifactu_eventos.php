<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Registro de eventos Verifactu en fza_verifactu_eventos, el mismo log que
 * usa el programa (inLibVerifactu.RegistrarEventoVerifactu +
 * inLibVerifactuRegistroEventos): cada evento lleva el XML sf:RegistroEvento,
 * la huella SHA-256 encadenada con la del evento anterior y los datos de la
 * empresa obligada y del productor del software.
 */

const EVENTO_VERIFACTU_INFO = 1;
const EVENTO_VERIFACTU_ENCOLADO = 2;
const EVENTO_VERIFACTU_ENVIO_OK = 3;
const EVENTO_VERIFACTU_ENVIO_ERROR = 4;
const EVENTO_VERIFACTU_INICIO = 101;
const EVENTO_VERIFACTU_FIN = 102;
const EVENTO_VERIFACTU_CAMBIO_CONFIG = 103;
const EVENTO_VERIFACTU_EXPORT_FACTURAS = 108;
const EVENTO_VERIFACTU_EXPORT_EVENTOS = 109;
const EVENTO_VERIFACTU_INCIDENCIA_CERT = 110;
const EVENTO_VERIFACTU_INCIDENCIA_RELOJ = 111;

const VERIFACTU_NS_EVENTOS =
    'https://www2.agenciatributaria.gob.es/static_files/common/internet/dep/aplicaciones/es/aeat/tike/cont/ws/EventosSIF.xsd';

/** Versión con la que la web se identifica si la empresa no tiene versión de instalación SIF. */
const VERIFACTU_VERSION_WEB = 'web-1.0';

/**
 * Empresa obligada para los eventos: la primera activa por orden, como
 * ConsultarEmpresa del programa. Incluye si hay varias activas (multi OT).
 */
function verifactu_empresa_eventos(PDO $pdo): array
{
    $fila = consultar_una(
        $pdo,
        'SELECT CODIGO_EMP_EMP, RAZON_SOCIAL_EMP, NIF_EMP, CODIGO_CERTIFICADO_EMP, ' .
        'TITULAR_CERTIFICADO_EMP, NUMERO_INSTALACION_EMP, VERSION_INSTALACION_EMP, ' .
        'CODIGO_SIF_INSTALACION_EMP, ' .
        '(SELECT COUNT(*) FROM fza_empresas WHERE ESACTIVO_EMP = \'S\') AS NUM_EMP ' .
        'FROM fza_empresas ORDER BY IF(ESACTIVO_EMP = \'S\', 0, 1), ORDEN_EMP, CODIGO_EMP_EMP LIMIT 1'
    );
    if ($fila === null) {
        throw new RuntimeException(t('No hay empresa configurada para registrar eventos Verifactu.'));
    }
    return [
        'codigo'              => trim((string)$fila['CODIGO_EMP_EMP']),
        'nombre_obligado'     => trim((string)$fila['RAZON_SOCIAL_EMP']),
        'nif_obligado'        => verifactu_normalizar_nif((string)$fila['NIF_EMP']),
        'serial_certificado'  => trim((string)($fila['CODIGO_CERTIFICADO_EMP'] ?? '')),
        'titular_certificado' => trim((string)($fila['TITULAR_CERTIFICADO_EMP'] ?? '')),
        'numero_instalacion'  => trim((string)($fila['NUMERO_INSTALACION_EMP'] ?? '')),
        'version_instalacion' => trim((string)($fila['VERSION_INSTALACION_EMP'] ?? '')),
        'codigo_sif'          => trim((string)($fila['CODIGO_SIF_INSTALACION_EMP'] ?? '')),
        'multi_ot'            => (int)$fila['NUM_EMP'] > 1 ? 'S' : 'N',
    ];
}

/**
 * Comprueba el número de instalación SIF de una empresa (ValidarInstalacionSif
 * del programa, salvo la comparación con la versión del ejecutable: la web
 * toma como versión la registrada en la empresa).
 */
function verifactu_validar_instalacion_sif(string $numero, string $version, string $codigoSif, string $nombreEmpresa, string $nifEmpresa): void
{
    if (trim($numero) === '') {
        throw new RuntimeException(t(
            'La empresa {empresa} ({nif}) no tiene número de instalación SIF. Genéralo desde Parámetros > Instalación SIF.',
            ['empresa' => trim($nombreEmpresa), 'nif' => trim($nifEmpresa)]));
    }
    if (strcasecmp(trim($codigoSif), VERIFACTU_SIF_ID) !== 0) {
        throw new RuntimeException(t(
            'El número de instalación SIF de la empresa {empresa} no corresponde al SIF FZ.', ['empresa' => trim($nombreEmpresa)]));
    }
    if (trim($version) === '') {
        throw new RuntimeException(t(
            'El número de instalación SIF de la empresa {empresa} no tiene versión asociada. Genéralo de nuevo.',
            ['empresa' => trim($nombreEmpresa)]));
    }
}

/** Versión del SIF con la que se firman los eventos y registros (VERSION_INSTALACION_EMP). */
function verifactu_version_sif(PDO $pdo, ?array $empresa = null): string
{
    $empresa ??= verifactu_empresa_eventos($pdo);
    $version = trim((string)($empresa['version_instalacion'] ?? ''));
    return $version !== '' ? $version : VERIFACTU_VERSION_WEB;
}

/** Texto del evento como TextoEvento: sin saltos, sin espacios dobles, 100 caracteres. */
function verifactu_texto_evento(string $texto): string
{
    $texto = str_replace(["\r", "\n"], ' ', trim($texto));
    $texto = preg_replace('/ {2,}/', ' ', $texto) ?? $texto;
    return mb_substr($texto, 0, 100);
}

function verifactu_tipo_evento_aeat(int $tipo): string
{
    return match ($tipo) {
        EVENTO_VERIFACTU_INICIO => '01',
        EVENTO_VERIFACTU_FIN => '02',
        EVENTO_VERIFACTU_EXPORT_FACTURAS => '08',
        EVENTO_VERIFACTU_EXPORT_EVENTOS => '09',
        default => '90',
    };
}

/** Último evento registrado (encadenamiento) o null si es el primero. */
function verifactu_evento_anterior(PDO $pdo): ?array
{
    $fila = consultar_una(
        $pdo,
        'SELECT TIPO_EVENTO_LOG, TIMESTAMP_LOG, HASH_PROPIO_LOG FROM fza_verifactu_eventos ORDER BY ID_LOG DESC LIMIT 1'
    );
    if ($fila === null) {
        return null;
    }
    return [
        'tipo'     => (int)$fila['TIPO_EVENTO_LOG'],
        'instante' => new DateTimeImmutable((string)$fila['TIMESTAMP_LOG']),
        'huella'   => (string)$fila['HASH_PROPIO_LOG'],
    ];
}

function verifactu_eventos_tienen_columnas_firma(PDO $pdo): bool
{
    static $tiene = null;
    if ($tiene === null) {
        $fila = consultar_una(
            $pdo,
            'SELECT COUNT(*) AS N FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() ' .
            'AND TABLE_NAME = \'fza_verifactu_eventos\' AND COLUMN_NAME IN (\'REGISTRO_XML_LOG\', ' .
            '\'FIRMA_XADES_LOG\', \'SERIE_CERTIFICADO_LOG\', \'TITULAR_CERTIFICADO_LOG\', \'HUELLA_CERTIFICADO_LOG\')'
        );
        $tiene = (int)($fila['N'] ?? 0) === 5;
    }
    return $tiene;
}

/**
 * XML sf:RegistroEvento y huella del evento (ConstruirXml del programa).
 * Devuelve ['xml' => ..., 'huella' => ...].
 */
function verifactu_construir_evento_xml(
    array $empresa,
    string $nombreProductor,
    string $nifProductor,
    string $version,
    ?array $anterior,
    DateTimeInterface $instanteEvento,
    int $tipoEvento,
    string $otrosDatos
): array {
    $tipoAeat = verifactu_tipo_evento_aeat($tipoEvento);
    $fechaHuso = verifactu_fecha_hora_huso($instanteEvento);
    $huellaAnterior = $anterior === null ? '' : $anterior['huella'];
    $baseHash = 'TipoEvento=' . $tipoAeat .
        '&FechaHoraHusoGenEvento=' . $fechaHuso .
        '&OtrosDatosEvento=' . $otrosDatos .
        '&HuellaEventoAnterior=' . $huellaAnterior;
    $huella = strtoupper(hash('sha256', $baseHash));
    $sistema = '<sf:SistemaInformatico>' .
        '<sf:NombreRazon>' . verifactu_escapar_xml($nombreProductor) . '</sf:NombreRazon>' .
        '<sf:NIF>' . verifactu_escapar_xml($nifProductor) . '</sf:NIF>' .
        '<sf:NombreSistemaInformatico>' . VERIFACTU_SIF_NOMBRE . '</sf:NombreSistemaInformatico>' .
        '<sf:IdSistemaInformatico>' . VERIFACTU_SIF_ID . '</sf:IdSistemaInformatico>' .
        '<sf:Version>' . verifactu_escapar_xml($version) . '</sf:Version>' .
        '<sf:NumeroInstalacion>' . verifactu_escapar_xml($empresa['numero_instalacion']) . '</sf:NumeroInstalacion>' .
        '<sf:TipoUsoPosibleSoloVerifactu>N</sf:TipoUsoPosibleSoloVerifactu>' .
        '<sf:TipoUsoPosibleMultiOT>S</sf:TipoUsoPosibleMultiOT>' .
        '<sf:IndicadorMultiplesOT>' . $empresa['multi_ot'] . '</sf:IndicadorMultiplesOT>' .
        '</sf:SistemaInformatico>';
    $obligado = '<sf:ObligadoEmision>' .
        '<sf:NombreRazon>' . verifactu_escapar_xml($empresa['nombre_obligado']) . '</sf:NombreRazon>' .
        '<sf:NIF>' . verifactu_escapar_xml($empresa['nif_obligado']) . '</sf:NIF>' .
        '</sf:ObligadoEmision>';
    if ($anterior === null) {
        $encadenamiento = '<sf:Encadenamiento><sf:PrimerEvento>S</sf:PrimerEvento></sf:Encadenamiento>';
    } else {
        $encadenamiento = '<sf:Encadenamiento><sf:EventoAnterior>' .
            '<sf:TipoEvento>' . verifactu_tipo_evento_aeat($anterior['tipo']) . '</sf:TipoEvento>' .
            '<sf:FechaHoraHusoGenEvento>' . verifactu_fecha_hora_huso($anterior['instante']) . '</sf:FechaHoraHusoGenEvento>' .
            '<sf:HuellaEvento>' . $anterior['huella'] . '</sf:HuellaEvento>' .
            '</sf:EventoAnterior></sf:Encadenamiento>';
    }
    $xml = '<?xml version="1.0" encoding="UTF-8"?>' .
        '<sf:RegistroEvento xmlns:sf="' . VERIFACTU_NS_EVENTOS . '" xmlns:ds="' . VERIFACTU_NS_DSIG . '">' .
        '<sf:IDVersion>1.0</sf:IDVersion><sf:Evento>' . $sistema . $obligado .
        '<sf:FechaHoraHusoGenEvento>' . $fechaHuso . '</sf:FechaHoraHusoGenEvento>' .
        '<sf:TipoEvento>' . $tipoAeat . '</sf:TipoEvento>';
    if ($otrosDatos !== '') {
        $xml .= '<sf:OtrosDatosEvento>' . verifactu_escapar_xml($otrosDatos) . '</sf:OtrosDatosEvento>';
    }
    $xml .= $encadenamiento . '<sf:TipoHuella>01</sf:TipoHuella><sf:HuellaEvento>' . $huella .
        '</sf:HuellaEvento></sf:Evento></sf:RegistroEvento>';
    return ['xml' => $xml, 'huella' => $huella];
}

/**
 * Registra un evento en fza_verifactu_eventos igual que
 * RegistrarEventoVerifactu del programa (sin firma XAdES: la web no usa el
 * modo NO VERI*FACTU, así que FIRMA_DIGITAL_LOG lleva la propia huella).
 */
function registrar_evento_verifactu(
    PDO $pdo,
    array $usuario,
    int $tipoEvento,
    string $descripcion,
    string $datosAdicionales = '',
    string $serie = '',
    string $numero = ''
): void {
    $nifProductor = verifactu_normalizar_nif(parametro_app($pdo, $usuario, 'appVerifactuSifNif', ''));
    if (strlen($nifProductor) !== 9) {
        throw new RuntimeException(t('Parámetro appVerifactuSifNif vacío o no válido: "{nif}".', ['nif' => $nifProductor]));
    }
    $nombreProductor = parametro_app($pdo, $usuario, 'appVerifactuSifNombreRazon', 'Alejandro Laorden Hidalgo');
    $empresa = verifactu_empresa_eventos($pdo);
    if (strlen($empresa['nif_obligado']) !== 9) {
        throw new RuntimeException(t(
            'NIF de la empresa emisora vacío o no válido para registrar eventos: "{nif}".', ['nif' => $empresa['nif_obligado']]));
    }
    verifactu_validar_instalacion_sif(
        $empresa['numero_instalacion'], $empresa['version_instalacion'], $empresa['codigo_sif'],
        $empresa['nombre_obligado'], $empresa['nif_obligado']);
    $version = verifactu_version_sif($pdo, $empresa);
    $ahora = new DateTimeImmutable('now');
    $anterior = verifactu_evento_anterior($pdo);
    $otrosDatos = verifactu_texto_evento($descripcion . ' ' . $datosAdicionales);
    $evento = verifactu_construir_evento_xml(
        $empresa, $nombreProductor, $nifProductor, $version, $anterior, $ahora, $tipoEvento, $otrosDatos);
    $hashAnterior = $anterior === null ? str_repeat('0', 64) : $anterior['huella'];
    $parametros = [
        $ahora->format('Y-m-d H:i:s.v'),
        $tipoEvento,
        (string)$usuario['usuario'],
        $version,
        $descripcion,
        $datosAdicionales,
        $hashAnterior,
        $evento['huella'],
        $evento['huella'],
        $numero,
        $serie,
    ];
    if (verifactu_eventos_tienen_columnas_firma($pdo)) {
        ejecutar(
            $pdo,
            'INSERT INTO fza_verifactu_eventos (TIMESTAMP_LOG, TIPO_EVENTO_LOG, USUARIO_LOG, VERSION_LOG, ' .
            'DESCRIPCION_LOG, DATOS_ADICIONALES_LOG, HASH_ANTERIOR_LOG, HASH_PROPIO_LOG, FIRMA_DIGITAL_LOG, ' .
            'NUMERO_FAC_LOG, SERIE_FAC_LOG, REGISTRO_XML_LOG, FIRMA_XADES_LOG, SERIE_CERTIFICADO_LOG, ' .
            'TITULAR_CERTIFICADO_LOG, HUELLA_CERTIFICADO_LOG) VALUES ' .
            '(?, ?, ?, ?, ?, NULLIF(?, \'\'), ?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'), ?, NULL, NULL, NULL, NULL)',
            array_merge($parametros, [$evento['xml']])
        );
    } else {
        ejecutar(
            $pdo,
            'INSERT INTO fza_verifactu_eventos (TIMESTAMP_LOG, TIPO_EVENTO_LOG, USUARIO_LOG, VERSION_LOG, ' .
            'DESCRIPCION_LOG, DATOS_ADICIONALES_LOG, HASH_ANTERIOR_LOG, HASH_PROPIO_LOG, FIRMA_DIGITAL_LOG, ' .
            'NUMERO_FAC_LOG, SERIE_FAC_LOG) VALUES ' .
            '(?, ?, ?, ?, ?, NULLIF(?, \'\'), ?, ?, ?, NULLIF(?, \'\'), NULLIF(?, \'\'))',
            $parametros
        );
    }
}

/**
 * Registra el evento sin interrumpir la operación principal (como las
 * variantes "Seguro" del programa): devuelve el mensaje de error o null.
 */
function registrar_evento_verifactu_seguro(
    PDO $pdo,
    array $usuario,
    int $tipoEvento,
    string $descripcion,
    string $datosAdicionales = '',
    string $serie = '',
    string $numero = ''
): ?string {
    try {
        registrar_evento_verifactu($pdo, $usuario, $tipoEvento, $descripcion, $datosAdicionales, $serie, $numero);
        return null;
    } catch (Throwable $error) {
        error_log('FacturacionWeb evento Verifactu no registrado: ' . $error->getMessage());
        return $error->getMessage();
    }
}

/** Últimos eventos del log para mostrarlos. */
function eventos_verifactu_ultimos(PDO $pdo, int $limite = 20): array
{
    $limite = max(1, min(200, $limite));
    return consultar(
        $pdo,
        'SELECT ID_LOG, TIMESTAMP_LOG, TIPO_EVENTO_LOG, USUARIO_LOG, VERSION_LOG, DESCRIPCION_LOG, ' .
        'DATOS_ADICIONALES_LOG, SERIE_FAC_LOG, NUMERO_FAC_LOG, HASH_PROPIO_LOG ' .
        'FROM fza_verifactu_eventos ORDER BY ID_LOG DESC LIMIT ' . $limite
    );
}

function evento_verifactu_nombre(int $tipo): string
{
    return match ($tipo) {
        EVENTO_VERIFACTU_INFO => 'Información',
        EVENTO_VERIFACTU_ENCOLADO => 'Encolado',
        EVENTO_VERIFACTU_ENVIO_OK => 'Envío correcto',
        EVENTO_VERIFACTU_ENVIO_ERROR => 'Error de envío',
        EVENTO_VERIFACTU_INICIO => 'Inicio',
        EVENTO_VERIFACTU_FIN => 'Fin',
        EVENTO_VERIFACTU_CAMBIO_CONFIG => 'Cambio de configuración',
        EVENTO_VERIFACTU_EXPORT_FACTURAS => 'Exportación de facturas',
        EVENTO_VERIFACTU_EXPORT_EVENTOS => 'Exportación de eventos',
        EVENTO_VERIFACTU_INCIDENCIA_CERT => 'Incidencia de certificado',
        EVENTO_VERIFACTU_INCIDENCIA_RELOJ => 'Incidencia de reloj',
        default => 'Tipo ' . $tipo,
    };
}
