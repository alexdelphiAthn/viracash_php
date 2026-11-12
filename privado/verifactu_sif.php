<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Número de instalación del SIF (NumeroInstalacion del bloque
 * SistemaInformatico). Lo asigna el servicio web del productor
 * (appApiUrl + sif/instalacion.php, autenticado con appApiToken y la
 * referencia appApiReferencia) y se guarda por empresa en fza_empresas, igual
 * que hace inLibVerifactuInstalacion.GenerarInstalacionSifEmpresa.
 */

const SIF_RUTA_INSTALACION = 'sif/instalacion.php';

/** Presentación sin la navegación del sitio del productor; la copia original no cambia. */
function sif_declaracion_solo_documento(string $html): string
{
    $dom = new DOMDocument();
    $anterior = libxml_use_internal_errors(true);
    try {
        $dom->loadHTML('<?xml encoding="UTF-8">' . $html, LIBXML_NONET);
        $xpath = new DOMXPath($dom);
        foreach ($xpath->query('//nav | //button | //form | //script | //base') as $nodo) {
            $nodo->parentNode?->removeChild($nodo);
        }
        // Los enlaces relativos apuntarían al dominio donde está instalada la web.
        foreach ($xpath->query('//a[@href]') as $enlace) {
            $destino = trim($enlace->getAttribute('href'));
            if (!preg_match('~^https://~i', $destino) && !str_starts_with($destino, '#')) {
                $enlace->removeAttribute('href');
            }
        }
        return (string)$dom->saveHTML();
    } finally {
        libxml_clear_errors();
        libxml_use_internal_errors($anterior);
    }
}

/** Verifica la versión y la integridad del documento entregado por el productor. */
function sif_validar_declaracion(array $respuesta, string $version): string
{
    $datos = $respuesta['datos'] ?? [];
    $html = (string)($datos['contenido_html'] ?? '');
    if (($datos['sif'] ?? '') !== 'FZ' || ($datos['version'] ?? '') !== $version ||
        trim($html) === '' || !hash_equals(hash('sha256', $html), strtolower((string)($datos['sha256'] ?? '')))) {
        throw new RuntimeException(t('La declaración recibida no corresponde al SIF y versión solicitados o está incompleta.'));
    }
    return $html;
}

/** Consulta documental: no solicita ni modifica el número de instalación. */
function sif_obtener_declaracion(PDO $pdo, array $usuario, string $version): array
{
    if ($version === '') {
        throw new RuntimeException(t('La empresa no tiene una versión de SIF registrada. Revisa Parámetros e instalación SIF.'));
    }
    $url = substr(sif_url_servicio($pdo, $usuario), 0, -strlen(SIF_RUTA_INSTALACION)) . 'sif/declaracion.php';
    $referencia = trim(parametro_app($pdo, $usuario, 'appApiReferencia'));
    $token = trim(parametro_app($pdo, $usuario, 'appApiToken'));
    $carpeta = __DIR__ . '/declaraciones_sif_cache';
    $archivo = $carpeta . '/' . hash('sha256', $url . '|' . $referencia . '|FZ|' . $version) . '.json';
    try {
        if ($token === '' || $referencia === '') {
            throw new RuntimeException(t('Configura appApiToken y appApiReferencia en Parámetros para consultar la declaración.'));
        }
        if (strtolower((string)parse_url($url, PHP_URL_SCHEME)) !== 'https') {
            throw new RuntimeException(t('La URL del servicio de declaraciones debe utilizar HTTPS.'));
        }
        $ch = curl_init($url);
        $opciones = [CURLOPT_POST=>true, CURLOPT_RETURNTRANSFER=>true,
            CURLOPT_CONNECTTIMEOUT=>10, CURLOPT_TIMEOUT=>20,
            CURLOPT_HTTPHEADER=>['Content-Type: application/json', 'X-API-Key: ' . $token],
            CURLOPT_POSTFIELDS=>json_encode(['sif'=>'FZ', 'version'=>$version, 'referencia'=>$referencia], JSON_THROW_ON_ERROR)];
        $ca = configuracion()['verifactu']['ca_bundle'] ?? '';
        if ($ca !== '') { $opciones[CURLOPT_CAINFO] = $ca; }
        curl_setopt_array($ch, $opciones);
        $cuerpo = curl_exec($ch);
        $estado = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
        curl_close($ch);
        if (!is_string($cuerpo) || $estado !== 200) {
            throw new RuntimeException(t('No se ha podido obtener la declaración del servicio (HTTP {estado}).', ['estado' => $estado]));
        }
        $respuesta = json_decode($cuerpo, true, 512, JSON_THROW_ON_ERROR);
        $html = sif_validar_declaracion($respuesta, $version);
        if (!is_dir($carpeta)) { @mkdir($carpeta, 0700, true); }
        $guardada = is_dir($carpeta) &&
            file_put_contents($archivo, $cuerpo, LOCK_EX) !== false;
        return ['html'=>$html, 'aviso'=>$guardada ? '' : t('No se pudo guardar una copia privada de la declaración.')];
    } catch (Throwable $e) {
        if (is_file($archivo)) {
            $respuesta = json_decode((string)file_get_contents($archivo), true, 512, JSON_THROW_ON_ERROR);
            return ['html'=>sif_validar_declaracion($respuesta, $version),
                'aviso'=>t('El servicio no está disponible. Se muestra la copia privada de esta versión.')];
        }
        throw $e;
    }
}

/** NIF para el servicio de instalación (NormalizarNifInstalacion): A-Z0-9 y DNI rellenado a 8 dígitos. */
function sif_normalizar_nif(string $valor): string
{
    $nif = preg_replace('/[^A-Z0-9]/', '', strtoupper($valor)) ?? '';
    if (strlen($nif) >= 2 && strlen($nif) < 9 && ctype_alpha(substr($nif, -1)) && ctype_digit(substr($nif, 0, -1))) {
        $nif = str_pad(substr($nif, 0, -1), 8, '0', STR_PAD_LEFT) . substr($nif, -1);
    }
    return $nif;
}

/** Estado de la instalación SIF de una empresa (ObtenerEmpresaInstalacionSif). */
function sif_estado_empresa(PDO $pdo, string $codigoEmpresa): ?array
{
    $fila = consultar_una(
        $pdo,
        'SELECT CODIGO_EMP_EMP, RAZON_SOCIAL_EMP, NIF_EMP, NUMERO_INSTALACION_EMP, VERSION_INSTALACION_EMP, ' .
        'CODIGO_SIF_INSTALACION_EMP, INSTANTE_INSTALACION_EMP FROM fza_empresas WHERE CODIGO_EMP_EMP = ?',
        [$codigoEmpresa]
    );
    if ($fila === null) {
        return null;
    }
    $estado = [
        'codigo'   => trim((string)$fila['CODIGO_EMP_EMP']),
        'razon_social' => trim((string)$fila['RAZON_SOCIAL_EMP']),
        'nif'      => sif_normalizar_nif((string)$fila['NIF_EMP']),
        'numero'   => trim((string)($fila['NUMERO_INSTALACION_EMP'] ?? '')),
        'version'  => trim((string)($fila['VERSION_INSTALACION_EMP'] ?? '')),
        'sif'      => trim((string)($fila['CODIGO_SIF_INSTALACION_EMP'] ?? '')),
        'instante' => (string)($fila['INSTANTE_INSTALACION_EMP'] ?? ''),
        'valido'   => false,
        'mensaje'  => '',
    ];
    if ($estado['numero'] === '') {
        $estado['mensaje'] = t('Pendiente de generar desde el servicio.');
    } elseif (strcasecmp($estado['sif'], VERIFACTU_SIF_ID) !== 0) {
        $estado['mensaje'] = t('El SIF guardado no coincide con FZ.');
    } elseif ($estado['version'] === '') {
        $estado['mensaje'] = t('El número de instalación no tiene versión asociada.');
    } else {
        $estado['valido'] = true;
        $estado['mensaje'] = t('Válido (versión {version}).', ['version' => $estado['version']]);
    }
    return $estado;
}

/** Versión de SIF propuesta: la de la empresa o la más reciente registrada en cualquier empresa. */
function sif_version_propuesta(PDO $pdo, ?array $estado): string
{
    if ($estado !== null && $estado['version'] !== '') {
        return $estado['version'];
    }
    $fila = consultar_una(
        $pdo,
        'SELECT VERSION_INSTALACION_EMP FROM fza_empresas WHERE COALESCE(VERSION_INSTALACION_EMP, \'\') <> \'\' ' .
        'ORDER BY INSTANTE_INSTALACION_EMP DESC LIMIT 1'
    );
    return trim((string)($fila['VERSION_INSTALACION_EMP'] ?? ''));
}

function sif_url_servicio(PDO $pdo, array $usuario): string
{
    $base = trim(parametro_app($pdo, $usuario, 'appApiUrl'));
    if ($base === '') {
        $base = 'https://webservice.veryverifactu.com/api/v1/';
    }
    if (!str_ends_with($base, '/')) {
        $base .= '/';
    }
    return $base . SIF_RUTA_INSTALACION;
}

/** Mensaje de error de una respuesta JSON del servicio (MensajeErrorServicio). */
function sif_mensaje_error_servicio(string $cuerpo, int $estadoHttp): string
{
    $json = json_decode($cuerpo, true);
    $mensaje = '';
    if (is_array($json)) {
        $mensaje = trim((string)($json['message'] ?? ''));
        if ($mensaje === '' && is_array($json['error'] ?? null)) {
            $mensaje = trim((string)($json['error']['mensaje'] ?? ''));
        }
    }
    return $mensaje !== '' ? $mensaje : t('El servicio respondió con HTTP {estado}.', ['estado' => $estadoHttp]);
}

/** Pide un número de instalación al servicio (PedirNumeroInstalacionServicio). */
function sif_pedir_numero(PDO $pdo, array $usuario, string $version, string $razonSocial, string $nif): string
{
    $referencia = trim(parametro_app($pdo, $usuario, 'appApiReferencia'));
    $token = trim(parametro_app($pdo, $usuario, 'appApiToken'));
    if ($referencia === '') {
        throw new RuntimeException(t('Falta la referencia global de la instalación (parámetro appApiReferencia).'));
    }
    if ($token === '') {
        throw new RuntimeException(t('Falta la API key de la instalación (parámetro appApiToken).'));
    }
    if (!function_exists('curl_init')) {
        throw new RuntimeException(t('La extensión cURL de PHP no está disponible.'));
    }
    $peticion = json_encode([
        'version' => $version,
        'razon_social' => $razonSocial,
        'nif' => $nif,
        'sif' => VERIFACTU_SIF_ID,
        'referencia' => $referencia,
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    $ch = curl_init(sif_url_servicio($pdo, $usuario));
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $peticion,
        CURLOPT_HTTPHEADER => ['Content-Type: application/json; charset=utf-8', 'X-API-Key: ' . $token],
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 15,
        CURLOPT_TIMEOUT => 30,
    ]);
    $cuerpo = curl_exec($ch);
    $errno = curl_errno($ch);
    $error = curl_error($ch);
    $estado = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    curl_close($ch);
    if ($errno !== 0) {
        throw new RuntimeException(t('No se ha podido conectar con el servicio de instalación SIF: {error}', ['error' => $error]));
    }
    $cuerpo = (string)$cuerpo;
    if ($estado !== 200) {
        throw new RuntimeException(sif_mensaje_error_servicio($cuerpo, $estado));
    }
    $json = json_decode($cuerpo, true);
    if (!is_array($json)) {
        throw new RuntimeException(t('El servicio de instalación SIF ha devuelto una respuesta que no es JSON.'));
    }
    $numero = '';
    if (is_array($json['datos'] ?? null)) {
        $numero = trim((string)($json['datos']['numero_instalacion'] ?? ''));
    }
    foreach (['numero_instalacion', 'numeroInstalacion', 'NumeroInstalacion'] as $clave) {
        if ($numero === '') {
            $numero = trim((string)($json[$clave] ?? ''));
        }
    }
    if ($numero === '') {
        throw new RuntimeException(t('El servicio de instalación SIF no ha devuelto ningún número de instalación.'));
    }
    return $numero;
}

/**
 * Genera (o confirma) el número de instalación SIF de la empresa para la
 * versión indicada y lo guarda en fza_empresas (GenerarInstalacionSifEmpresa).
 */
function sif_generar_empresa(PDO $pdo, array $usuario, string $codigoEmpresa, string $version): array
{
    $estado = sif_estado_empresa($pdo, $codigoEmpresa);
    if ($estado === null) {
        throw new RuntimeException(t('No existe la empresa {codigo}.', ['codigo' => $codigoEmpresa]));
    }
    $version = trim($version);
    if ($version === '') {
        throw new RuntimeException(t('Indica la versión del SIF (la misma que tiene registrada ViraCash).'));
    }
    if ($estado['razon_social'] === '') {
        throw new RuntimeException(t('La empresa no tiene razón social.'));
    }
    if (strlen($estado['nif']) !== 9) {
        throw new RuntimeException(t('El NIF de la empresa no es válido para la instalación SIF: "{nif}".', ['nif' => $estado['nif']]));
    }
    $numero = $estado['valido'] && strcasecmp($estado['version'], $version) === 0 ? $estado['numero'] : '';
    if ($numero === '') {
        $numero = sif_pedir_numero($pdo, $usuario, $version, $estado['razon_social'], $estado['nif']);
    }
    ejecutar(
        $pdo,
        'UPDATE fza_empresas SET NUMERO_INSTALACION_EMP = ?, VERSION_INSTALACION_EMP = ?, ' .
        'CODIGO_SIF_INSTALACION_EMP = ?, INSTANTE_INSTALACION_EMP = NOW(), INSTANTE_MODIF = NOW(), ' .
        'USUARIO_MODIF = ? WHERE CODIGO_EMP_EMP = ?',
        [$numero, $version, VERIFACTU_SIF_ID, (string)$usuario['usuario'], $codigoEmpresa]
    );
    return sif_estado_empresa($pdo, $codigoEmpresa) ?? $estado;
}
