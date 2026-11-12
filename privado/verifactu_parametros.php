<?php
declare(strict_types=1);

/*
 * Parámetros de aplicación de Verifactu y de los servicios web, leídos y
 * escritos en fza_usuarios_perfiles exactamente como el programa (formulario
 * 'frmMtoAppParam', PRC_GETPERFILFORMULARIO con prioridad usuario > grupo >
 * Todos y PRC_SETPERFILFORMULARIO). Las definiciones (nombre, descripción y
 * valor por defecto) son las de inLibAppParam.pas.
 */

const VERIFACTU_FORMULARIO_PARAMETROS = 'frmMtoAppParam';

const VERIFACTU_MODO_SIN = 'SIN';
const VERIFACTU_MODO_VERIFACTU = 'VERIFACTU';
const VERIFACTU_MODO_NO_VERIFACTU = 'NO_VERIFACTU';
/* Suministro Inmediato de Información: sustituye a VERIFACTU y usa la misma cola. */
const VERIFACTU_MODO_SII = 'SII';

/** Definiciones: nombre => [categoría, descripción, tipo, valor por defecto]. */
function verifactu_definiciones_parametros(): array
{
    return [
        'appVerifactuModo' => ['Verifactu', 'Modo fiscal: SIN, VERIFACTU, NO_VERIFACTU o SII', 'string', 'SIN'],
        'appVerifactuActivo' => ['Verifactu', 'Activar SIF (False fuerza modo SIN y no imprime QR)', 'bool', 'False'],
        'appVerifactuFirmaCertificado' => ['Verifactu', 'Firmar registros y eventos con certificado de empresa', 'bool', 'False'],
        'appVerifactuEntorno' => ['Verifactu', 'Entorno AEAT: PRE (pruebas) o PRO (producción)', 'string', 'PRE'],
        'appVerifactuUrlQRPre' => ['Verifactu', 'URL de cotejo del QR en preproducción', 'string',
            'https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQR'],
        'appVerifactuUrlQRPro' => ['Verifactu', 'URL de cotejo del QR en producción', 'string',
            'https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQR'],
        'appNoVerifactuUrlQRPre' => ['Verifactu', 'URL de remisión del QR NO VERI*FACTU en preproducción', 'string',
            'https://prewww2.aeat.es/wlpl/TIKE-CONT/ValidarQRNoVerifactu'],
        'appNoVerifactuUrlQRPro' => ['Verifactu', 'URL de remisión del QR NO VERI*FACTU en producción', 'string',
            'https://www2.agenciatributaria.gob.es/wlpl/TIKE-CONT/ValidarQRNoVerifactu'],
        'appVerifactuSegundosCiclo' => ['Verifactu', 'Segundos entre ciclos del hilo de la cola Verifactu', 'int', '60'],
        'appVerifactuMaxIntentos' => ['Verifactu', 'Reintentos de envío antes de marcar ERROR definitivo', 'int', '10'],
        'appVerifactuUrlEnvioPre' => ['Verifactu', 'URL del servicio SOAP de envío en preproducción', 'string',
            'https://prewww1.aeat.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP'],
        'appVerifactuUrlEnvioPro' => ['Verifactu', 'URL del servicio SOAP de envío en producción', 'string',
            'https://www1.agenciatributaria.gob.es/wlpl/TIKE-CONT/ws/SistemaFacturacion/VerifactuSOAP'],
        'appSiiUrlEnvioPre' => ['Verifactu', 'URL del servicio SOAP del SII en preproducción', 'string',
            'https://prewww1.aeat.es/wlpl/SSII-FACT/ws/fe/SiiFactFEV1SOAP'],
        'appSiiUrlEnvioPro' => ['Verifactu', 'URL del servicio SOAP del SII en producción', 'string',
            'https://www1.agenciatributaria.gob.es/wlpl/SSII-FACT/ws/fe/SiiFactFEV1SOAP'],
        'appSiiVersion' => ['Verifactu', 'Versión del esquema del SII (IDVersionSii)', 'string', '1.1'],
        'appSiiTipoOperacionDefecto' => ['Verifactu', 'Tipo de operación del SII por defecto: Entrega o PrestacionServicios',
            'string', 'Entrega'],
        'appSiiDiasAvisoPlazo' => ['Verifactu', 'Antigüedad en días naturales a partir de la que se avisa', 'int', '3'],
        'appVerifactuSifNombreRazon' => ['Verifactu', 'Productor del software (SistemaInformatico.NombreRazon)', 'string',
            'Alejandro Laorden Hidalgo'],
        'appVerifactuSifNif' => ['Verifactu', 'NIF del productor del software (SistemaInformatico.NIF)', 'string', ''],
        'appVerifactuSifDireccion' => ['Verifactu', 'Dirección postal del productor del software', 'string', ''],
        'appVerifactuDeclaracionLugar' => ['Verifactu', 'Lugar de suscripción de la declaración responsable', 'string', ''],
        'appVerifactuDeclaracionFecha' => ['Verifactu', 'Fecha de suscripción de la declaración responsable', 'string', ''],
        'appVerifactuDescripcionOpe' => ['Verifactu', 'Texto de DescripcionOperacion del registro de alta', 'string', 'Venta'],
        'appVerifactuNtpServidores' => ['Verifactu', 'Servidores NTP para validar el reloj fiscal NO VERI*FACTU', 'string',
            'time.google.com,time.windows.com,pool.ntp.org'],
        'appVerifactuNtpTimeoutMs' => ['Verifactu', 'Timeout por servidor NTP para control del reloj fiscal', 'int', '1500'],
        'appVerifactuNtpMargenSegundos' => ['Verifactu', 'Margen máximo admitido del reloj fiscal en segundos', 'int', '60'],
        'appApiUrl' => ['Servicios web', 'URL general del servicio web (asignación de SIF)', 'string',
            'https://webservice.veryverifactu.com/api/v1/'],
        'appApiToken' => ['Servicios web', 'API key / token de la instalación', 'string', ''],
        'appApiReferencia' => ['Servicios web', 'Referencia global de la instalación', 'string', ''],
    ];
}

/**
 * Valores del formulario de parámetros con la prioridad del programa
 * (PRC_GETPERFILFORMULARIO): nombre => ['valor' => ..., 'ambito' => ...].
 * Se cachea por petición.
 */
/** Caché por petición de los valores cargados (referencia para poder vaciarla). */
function &parametros_app_cache(): array
{
    static $cache = [];
    return $cache;
}

function parametros_app_cargar(PDO $pdo, array $usuario, bool $recargar = false): array
{
    $cache = &parametros_app_cache();
    $clave = (string)$usuario['usuario'] . '|' . (string)$usuario['grupo'];
    if ($recargar || !isset($cache[$clave])) {
        try {
            $filas = consultar(
                $pdo,
                'CALL PRC_GETPERFILFORMULARIO(?, ?, ?)',
                [(string)$usuario['usuario'], (string)$usuario['grupo'], VERIFACTU_FORMULARIO_PARAMETROS]
            );
        } catch (PDOException $error) {
            /* Sin el procedimiento, o con sus parámetros en otra intercalación
               que la tabla (error 1271): misma consulta que contiene el
               procedimiento, con la prioridad usuario > grupo > Todos. */
            $filas = consultar(
                $pdo,
                'SELECT USUARIO_GRUPO_USUPER, SUBKEY_USUPER, VALUE_USUPER FROM fza_usuarios_perfiles ' .
                'WHERE KEY_USUPER = ? AND USUARIO_GRUPO_USUPER IN (?, ?, \'Todos\') ' .
                'ORDER BY SUBKEY_USUPER, CASE USUARIO_GRUPO_USUPER WHEN ? THEN 1 WHEN ? THEN 2 ELSE 3 END',
                [VERIFACTU_FORMULARIO_PARAMETROS, (string)$usuario['usuario'], (string)$usuario['grupo'],
                    (string)$usuario['usuario'], (string)$usuario['grupo']]
            );
            $primeras = [];
            foreach ($filas as $fila) {
                $primeras[(string)$fila['SUBKEY_USUPER']] ??= $fila;
            }
            $filas = array_values($primeras);
        }
        $valores = [];
        foreach ($filas as $fila) {
            $valores[(string)$fila['SUBKEY_USUPER']] = [
                'valor'  => (string)($fila['VALUE_USUPER'] ?? ''),
                'ambito' => (string)$fila['USUARIO_GRUPO_USUPER'],
            ];
        }
        $cache[$clave] = $valores;
    }
    return $cache[$clave];
}

function parametros_app_invalidar(): void
{
    $cache = &parametros_app_cache();
    $cache = [];
}

/** Valor efectivo de un parámetro (vacío en la BBDD => valor por defecto, como GetString). */
function parametro_app(PDO $pdo, array $usuario, string $nombre, ?string $defecto = null): string
{
    $valores = parametros_app_cargar($pdo, $usuario);
    if ($defecto === null) {
        $defecto = (string)(verifactu_definiciones_parametros()[$nombre][3] ?? '');
    }
    $valor = trim((string)($valores[$nombre]['valor'] ?? ''));
    return $valor === '' ? $defecto : $valor;
}

/** Booleano como GetBool del programa: solo 'True' (sin distinguir mayúsculas) o '1'. */
function parametro_app_bool(PDO $pdo, array $usuario, string $nombre, bool $defecto = false): bool
{
    $valor = strtoupper(parametro_app($pdo, $usuario, $nombre, $defecto ? 'True' : 'False'));
    return $valor === 'TRUE' || $valor === '1';
}

function parametro_app_int(PDO $pdo, array $usuario, string $nombre, int $defecto): int
{
    $valor = parametro_app($pdo, $usuario, $nombre, (string)$defecto);
    return is_numeric($valor) ? (int)$valor : $defecto;
}

/**
 * Guarda valores (nombre => valor) en el ámbito indicado (usuario, grupo o
 * 'Todos') con PRC_SETPERFILFORMULARIO, en el formulario de parámetros de
 * aplicación o en el que se indique ('frmMtoCajaParam' para los de caja,
 * como el empleado del ticket). Si el procedimiento no puede
 * ejecutarse por su DEFINER (error 1449 del servidor remoto), se hace el mismo
 * INSERT ... ON DUPLICATE KEY UPDATE que contiene el procedimiento.
 */
function parametros_app_guardar(
    PDO $pdo,
    string $ambito,
    array $valores,
    string $formulario = VERIFACTU_FORMULARIO_PARAMETROS
): void {
    foreach ($valores as $nombre => $valor) {
        try {
            ejecutar(
                $pdo,
                'CALL PRC_SETPERFILFORMULARIO(?, ?, ?, ?)',
                [$ambito, $formulario, (string)$nombre, (string)$valor]
            );
        } catch (PDOException $error) {
            $codigo = (int)($error->errorInfo[1] ?? 0);
            if (!in_array($codigo, [1449, 1370, 1305], true)) {
                throw $error;
            }
            ejecutar(
                $pdo,
                'INSERT INTO fza_usuarios_perfiles ' .
                '(USUARIO_GRUPO_USUPER, KEY_USUPER, SUBKEY_USUPER, VALUE_USUPER, ' .
                ' INSTANTE_MODIF, INSTANTE_ALTA, USUARIO_MODIF, USUARIO_ALTA) ' .
                'VALUES (?, ?, ?, ?, NOW(), NOW(), ?, ?) ' .
                'ON DUPLICATE KEY UPDATE VALUE_USUPER = VALUES(VALUE_USUPER), ' .
                'INSTANTE_MODIF = NOW(), USUARIO_MODIF = VALUES(USUARIO_MODIF)',
                [$ambito, $formulario, (string)$nombre, (string)$valor, $ambito, $ambito]
            );
        }
    }
    parametros_app_invalidar();
}

/** Modo fiscal configurado (ModoVerifactuTexto del programa): SIN, VERIFACTU, NO_VERIFACTU o SII. */
function verifactu_modo_configurado(PDO $pdo, array $usuario): string
{
    if (!parametro_app_bool($pdo, $usuario, 'appVerifactuActivo', false)) {
        return VERIFACTU_MODO_SIN;
    }
    $modo = strtoupper(parametro_app($pdo, $usuario, 'appVerifactuModo', ''));
    if ($modo === '') {
        return VERIFACTU_MODO_VERIFACTU;
    }
    if (!in_array($modo, [VERIFACTU_MODO_VERIFACTU, VERIFACTU_MODO_NO_VERIFACTU, VERIFACTU_MODO_SII], true)) {
        return VERIFACTU_MODO_SIN;
    }
    return $modo;
}

/** Entorno AEAT configurado: PRO o PRE (VerifactuEntorno del programa). */
function verifactu_entorno(PDO $pdo, array $usuario): string
{
    return strtoupper(parametro_app($pdo, $usuario, 'appVerifactuEntorno', 'PRE')) === 'PRO' ? 'PRO' : 'PRE';
}

/** Ámbitos en los que puede guardar el usuario, como el desplegable del programa. */
function parametros_app_ambitos(array $usuario): array
{
    $ambitos = [(string)$usuario['usuario']];
    if (trim((string)$usuario['grupo']) !== '') {
        $ambitos[] = (string)$usuario['grupo'];
    }
    $ambitos[] = 'Todos';
    return array_values(array_unique($ambitos));
}
