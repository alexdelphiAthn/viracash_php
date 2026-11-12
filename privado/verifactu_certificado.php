<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Certificado electrónico de la empresa emisora para el envío a la AEAT.
 * Se sube como fichero .pfx/.p12 con su contraseña y se puede:
 *   - dejar en el servidor, en una carpeta privada fuera de "publico"
 *     (privado/certificados), con la clave privada cifrada con un secreto
 *     propio del servidor (config.php o privado/certificados/clave.txt);
 *   - o cargarlo solo para la sesión actual (se descarta al salir), para no
 *     tener el certificado en el servidor las 24 horas.
 * Al instalarlo se anotan en fza_empresas los mismos datos que el programa
 * (CODIGO_CERTIFICADO_EMP = número de serie, titular, tipo y fechas).
 */

const CERTIFICADO_TAMANO_MAXIMO = 262144;

function certificados_carpeta(): string
{
    $config = configuracion();
    $carpeta = (string)($config['verifactu']['carpeta_certificados'] ?? (FZA_RUTA_PRIVADA . '/certificados'));
    if (!is_dir($carpeta)) {
        if (!@mkdir($carpeta, 0700, true) && !is_dir($carpeta)) {
            throw new RuntimeException('No se puede crear la carpeta de certificados: ' . $carpeta);
        }
    }
    $htaccess = $carpeta . '/.htaccess';
    if (!is_file($htaccess)) {
        @file_put_contents($htaccess, "Require all denied\n");
    }
    return $carpeta;
}

/** Secreto con el que se cifra la clave privada guardada en el servidor. */
function certificado_secreto(): string
{
    $config = configuracion();
    $secreto = trim((string)($config['verifactu']['clave_certificados'] ?? ''));
    if ($secreto !== '') {
        return $secreto;
    }
    $ruta = certificados_carpeta() . '/clave.txt';
    if (is_file($ruta)) {
        $secreto = trim((string)file_get_contents($ruta));
    }
    if ($secreto === '') {
        $secreto = bin2hex(random_bytes(32));
        if (file_put_contents($ruta, $secreto . "\n") === false) {
            throw new RuntimeException('No se puede escribir el secreto de los certificados en ' . $ruta);
        }
        @chmod($ruta, 0600);
    }
    return $secreto;
}

function certificado_nombre_fichero(string $codigoEmpresa): string
{
    $nombre = preg_replace('/[^A-Za-z0-9._-]+/', '_', trim($codigoEmpresa)) ?? '';
    if ($nombre === '') {
        throw new RuntimeException(t('Código de empresa no válido para el certificado.'));
    }
    return $nombre;
}

/** Rutas [certificado PEM, clave privada cifrada] de una empresa. */
function certificado_rutas(string $codigoEmpresa): array
{
    $base = certificados_carpeta() . '/' . certificado_nombre_fichero($codigoEmpresa);
    return [$base . '.crt.pem', $base . '.key.enc'];
}

/**
 * Cifra la clave privada (PEM) con AES-256-GCM y una clave derivada del
 * secreto del servidor. Se hace a mano, sin openssl_pkey_export(), porque en
 * PHP para Windows esa función exige un openssl.cnf que no siempre existe.
 * Formato: base64(iv de 12 bytes . etiqueta de 16 . cifrado).
 */
function certificado_cifrar_clave(string $pem, string $secreto): string
{
    $iv = random_bytes(12);
    $etiqueta = '';
    $cifrado = openssl_encrypt($pem, 'aes-256-gcm', hash('sha256', $secreto, true), OPENSSL_RAW_DATA, $iv, $etiqueta, 'fza-certificado', 16);
    if ($cifrado === false) {
        throw new RuntimeException(t('No se ha podido cifrar la clave privada del certificado.'));
    }
    return base64_encode($iv . $etiqueta . $cifrado);
}

function certificado_descifrar_clave(string $datos, string $secreto): string
{
    $binario = base64_decode(trim($datos), true);
    if ($binario === false || strlen($binario) < 29) {
        throw new RuntimeException(t('El fichero de la clave privada guardada está dañado.'));
    }
    $pem = openssl_decrypt(substr($binario, 28), 'aes-256-gcm', hash('sha256', $secreto, true), OPENSSL_RAW_DATA,
        substr($binario, 0, 12), substr($binario, 12, 16), 'fza-certificado');
    if ($pem === false) {
        throw new RuntimeException(t('No se ha podido descifrar la clave privada guardada (¿ha cambiado el secreto del servidor?).'));
    }
    return $pem;
}

/**
 * Abre un PKCS#12. Primero con OpenSSL; si falla (los .pfx exportados desde
 * Windows usan RC2-40 y 3DES, que OpenSSL 3 no carga) con el lector propio.
 * Devuelve ['cert' => PEM, 'pkey' => PEM, 'extracerts' => [...]].
 */
function certificado_leer_pfx(string $bytes, string $contrasena): array
{
    if ($bytes === '') {
        throw new RuntimeException(t('El fichero del certificado está vacío.'));
    }
    $certificados = [];
    if (@openssl_pkcs12_read($bytes, $certificados, $contrasena)) {
        while (openssl_error_string() !== false) {
            /* Se vacía la pila de errores de OpenSSL. */
        }
        return [
            'cert' => (string)$certificados['cert'],
            'pkey' => (string)$certificados['pkey'],
            'extracerts' => array_values((array)($certificados['extracerts'] ?? [])),
        ];
    }
    $erroresOpenssl = [];
    while (($error = openssl_error_string()) !== false) {
        $erroresOpenssl[] = $error;
    }
    try {
        return LectorPkcs12::leer($bytes, $contrasena);
    } catch (Throwable $error) {
        $motivo = $error->getMessage();
        if ($erroresOpenssl !== [] && stripos(implode(' ', $erroresOpenssl), 'mac verify') !== false) {
            $motivo = 'La contraseña del certificado no es correcta.';
        }
        throw new RuntimeException(t('No se ha podido abrir el certificado: {motivo}', ['motivo' => t($motivo)]));
    }
}

/** Tipo de certificado por su emisor, como GetCertificateType del programa. */
function certificado_tipo(string $emisor): string
{
    if (stripos($emisor, 'AC Representación') !== false || stripos($emisor, 'AC Representacion') !== false) {
        return 'Representación FNMT';
    }
    if (stripos($emisor, 'AC FNMT Usuarios') !== false) {
        return 'Nominal FNMT';
    }
    return 'Otro';
}

/** Datos descriptivos de un certificado PEM: titular, serie, huella, emisor, vigencia. */
function certificado_datos(string $certPem): array
{
    $info = openssl_x509_parse($certPem);
    if ($info === false) {
        throw new RuntimeException(t('El certificado no se puede interpretar.'));
    }
    $asunto = $info['subject'] ?? [];
    $emisor = $info['issuer'] ?? [];
    $titular = trim((string)($asunto['CN'] ?? ''));
    if ($titular === '') {
        $titular = trim((string)($info['name'] ?? ''));
    }
    $nombreEmisor = trim((string)($emisor['CN'] ?? ''));
    if ($nombreEmisor === '') {
        $nombreEmisor = trim((string)($emisor['O'] ?? ''));
    }
    $desde = (int)($info['validFrom_time_t'] ?? 0);
    $hasta = (int)($info['validTo_time_t'] ?? 0);
    $ahora = time();
    return [
        'titular'   => $titular,
        'asunto'    => trim((string)($info['name'] ?? '')),
        'serie'     => strtoupper((string)($info['serialNumberHex'] ?? '')),
        'huella'    => strtoupper((string)openssl_x509_fingerprint($certPem, 'sha1')),
        'emisor'    => $nombreEmisor,
        'tipo'      => certificado_tipo(implode(' ', array_map('strval', $emisor))),
        'desde'     => date('Y-m-d H:i:s', $desde),
        'hasta'     => date('Y-m-d H:i:s', $hasta),
        'vigente'   => $ahora >= $desde && $ahora <= $hasta,
        'nif'       => trim((string)($asunto['serialNumber'] ?? '')),
    ];
}

/** Guarda en el servidor el certificado de la empresa (clave cifrada con el secreto). */
function certificado_guardar_servidor(string $codigoEmpresa, array $pkcs12): void
{
    [$rutaCert, $rutaClave] = certificado_rutas($codigoEmpresa);
    if (openssl_pkey_get_private($pkcs12['pkey']) === false) {
        throw new RuntimeException(t('La clave privada del certificado no es válida.'));
    }
    $claveCifrada = certificado_cifrar_clave($pkcs12['pkey'], certificado_secreto());
    if (file_put_contents($rutaCert, $pkcs12['cert']) === false || file_put_contents($rutaClave, $claveCifrada) === false) {
        throw new RuntimeException(t('No se ha podido escribir el certificado en {carpeta}', ['carpeta' => dirname($rutaCert)]));
    }
    @chmod($rutaCert, 0600);
    @chmod($rutaClave, 0600);
}

function certificado_borrar_servidor(string $codigoEmpresa): bool
{
    [$rutaCert, $rutaClave] = certificado_rutas($codigoEmpresa);
    $habia = false;
    foreach ([$rutaCert, $rutaClave] as $ruta) {
        if (is_file($ruta)) {
            unlink($ruta);
            $habia = true;
        }
    }
    return $habia;
}

/** Deja el certificado solo en la sesión (se pierde al salir). */
function certificado_guardar_sesion(string $codigoEmpresa, array $pkcs12): void
{
    $_SESSION['verifactu_certificado'] = [
        'empresa'  => $codigoEmpresa,
        'cert'     => $pkcs12['cert'],
        'pkey'     => $pkcs12['pkey'],
        'instante' => time(),
    ];
}

function certificado_quitar_sesion(): bool
{
    $habia = isset($_SESSION['verifactu_certificado']);
    unset($_SESSION['verifactu_certificado']);
    return $habia;
}

/**
 * Certificado utilizable para la empresa: primero el de la sesión, después
 * el guardado en el servidor (clave descifrada en memoria). Devuelve null si
 * no hay ninguno. Claves: origen ('sesion'|'servidor'), cert (PEM), pkey
 * (PEM en claro, solo en memoria), datos.
 */
function certificado_disponible(string $codigoEmpresa): ?array
{
    $sesion = $_SESSION['verifactu_certificado'] ?? null;
    if (is_array($sesion) && (string)$sesion['empresa'] === $codigoEmpresa) {
        return [
            'origen' => 'sesion',
            'cert'   => (string)$sesion['cert'],
            'pkey'   => (string)$sesion['pkey'],
            'datos'  => certificado_datos((string)$sesion['cert']),
        ];
    }
    [$rutaCert, $rutaClave] = certificado_rutas($codigoEmpresa);
    if (is_file($rutaCert) && is_file($rutaClave)) {
        $cert = (string)file_get_contents($rutaCert);
        return [
            'origen' => 'servidor',
            'cert'   => $cert,
            'pkey'   => certificado_descifrar_clave((string)file_get_contents($rutaClave), certificado_secreto()),
            'datos'  => certificado_datos($cert),
        ];
    }
    return null;
}

/** Empresas activas que tienen certificado disponible (sesión o servidor). */
function certificados_empresas_disponibles(PDO $pdo): array
{
    $disponibles = [];
    foreach (empresas_listar($pdo) as $empresa) {
        $codigo = (string)$empresa['CODIGO_EMP_EMP'];
        if (certificado_disponible($codigo) !== null) {
            $disponibles[] = $codigo;
        }
    }
    return $disponibles;
}

/**
 * Comprueba que la empresa tiene un certificado utilizable (como
 * ValidarCertificadoXades en ValidarRequisitosFiscalesEmision) y lo devuelve.
 */
function certificado_exigir(string $codigoEmpresa, string $nombreEmpresa): array
{
    $certificado = certificado_disponible($codigoEmpresa);
    if ($certificado === null) {
        throw new RuntimeException(t(
            'La empresa {empresa} no dispone de un certificado fiscal utilizable: no hay certificado cargado (cárgalo para esta sesión o guárdalo en el servidor desde el menú).',
            ['empresa' => $nombreEmpresa]));
    }
    if (!$certificado['datos']['vigente']) {
        throw new RuntimeException(t(
            'La empresa {empresa} no dispone de un certificado fiscal utilizable: el certificado de {titular} no está vigente (válido del {desde} al {hasta}).',
            ['empresa' => $nombreEmpresa, 'titular' => $certificado['datos']['titular'],
                'desde' => fecha_es($certificado['datos']['desde']), 'hasta' => fecha_es($certificado['datos']['hasta'])]));
    }
    return $certificado;
}

/** Anota en fza_empresas los datos del certificado, como hace Empresas > Certificados del programa. */
function certificado_actualizar_empresa(PDO $pdo, string $codigoEmpresa, array $datos, string $usuario): void
{
    ejecutar(
        $pdo,
        'UPDATE fza_empresas SET CODIGO_CERTIFICADO_EMP = ?, TITULAR_CERTIFICADO_EMP = ?, ' .
        'TIPO_CERTIFICADO_EMP = ?, FECHA_DESDE_CERTIFICADO_EMP = ?, FECHA_HASTA_CERTIFICADO_EMP = ?, ' .
        'USUARIO_MODIF = ?, INSTANTE_MODIF = NOW() WHERE CODIGO_EMP_EMP = ?',
        [
            mb_substr($datos['serie'], 0, 64),
            mb_substr($datos['titular'], 0, 1000),
            mb_substr($datos['tipo'], 0, 40),
            $datos['desde'],
            $datos['hasta'],
            $usuario,
            $codigoEmpresa,
        ]
    );
}

/**
 * Procesa el fichero subido ($_FILES['certificado']) con su contraseña y
 * devuelve el PKCS#12 abierto más sus datos: ['pkcs12' => ..., 'datos' => ...].
 */
function certificado_procesar_subida(?array $archivo, string $contrasena): array
{
    if ($archivo === null || !isset($archivo['error']) || (int)$archivo['error'] === UPLOAD_ERR_NO_FILE) {
        throw new RuntimeException(t('Elige el fichero del certificado (.pfx o .p12).'));
    }
    if ((int)$archivo['error'] !== UPLOAD_ERR_OK) {
        throw new RuntimeException(t('No se ha podido subir el fichero del certificado (error {codigo}).', ['codigo' => (int)$archivo['error']]));
    }
    if ((int)$archivo['size'] > CERTIFICADO_TAMANO_MAXIMO) {
        throw new RuntimeException(t('El fichero del certificado es demasiado grande.'));
    }
    if (!is_uploaded_file((string)$archivo['tmp_name'])) {
        throw new RuntimeException(t('El fichero del certificado no es válido.'));
    }
    $bytes = (string)file_get_contents((string)$archivo['tmp_name']);
    @unlink((string)$archivo['tmp_name']);
    $pkcs12 = certificado_leer_pfx($bytes, $contrasena);
    $datos = certificado_datos($pkcs12['cert']);
    $clave = openssl_pkey_get_private($pkcs12['pkey']);
    if ($clave === false || !openssl_x509_check_private_key($pkcs12['cert'], $clave)) {
        throw new RuntimeException(t('La clave privada del fichero no corresponde al certificado.'));
    }
    return ['pkcs12' => $pkcs12, 'datos' => $datos];
}

/**
 * Instala un certificado subido para la empresa: en el servidor o solo en la
 * sesión. Actualiza fza_empresas y devuelve los datos del certificado.
 */
function certificado_instalar(PDO $pdo, array $usuario, string $codigoEmpresa, ?array $archivo, string $contrasena, bool $enServidor): array
{
    $resultado = certificado_procesar_subida($archivo, $contrasena);
    if ($enServidor) {
        certificado_guardar_servidor($codigoEmpresa, $resultado['pkcs12']);
        certificado_quitar_sesion();
    } else {
        certificado_guardar_sesion($codigoEmpresa, $resultado['pkcs12']);
    }
    certificado_actualizar_empresa($pdo, $codigoEmpresa, $resultado['datos'], (string)$usuario['usuario']);
    return $resultado['datos'];
}
