<?php
declare(strict_types=1);

/*
 * Arranque común: configuración, sesión, conexión PDO y utilidades.
 * Lo incluye publico/index.php antes de despachar cualquier página.
 */

error_reporting(E_ALL);
ini_set('display_errors', '0');
mb_internal_encoding('UTF-8');
date_default_timezone_set('Europe/Madrid');

const FZA_RUTA_PRIVADA = __DIR__;
const FZA_RUTA_CONFIG = __DIR__ . '/../config.php';

function configuracion(): array
{
    static $config = null;
    if ($config === null) {
        /* FZA_CONFIG permite apuntar a otro config.php (pruebas locales). */
        $ruta = (string)(getenv('FZA_CONFIG') ?: FZA_RUTA_CONFIG);
        if (!is_file($ruta)) {
            throw new RuntimeException(
                'Falta el fichero config.php en la raíz de la aplicación.');
        }
        $config = require $ruta;
        if (!is_array($config) || !isset($config['bbdd'])) {
            throw new RuntimeException('config.php no devuelve la configuración esperada.');
        }
    }
    return $config;
}

function es_https(): bool
{
    return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ||
        (string)($_SERVER['SERVER_PORT'] ?? '') === '443' ||
        strtolower((string)($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '')) === 'https';
}

function iniciar_sesion(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) {
        return;
    }
    session_name('FZAFACTURAS');
    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'secure'   => es_https(),
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    session_start();
}

function bbdd(): PDO
{
    static $pdo = null;
    if ($pdo === null) {
        $cfg = configuracion()['bbdd'];
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
            (string)($cfg['host'] ?? '127.0.0.1'),
            (int)($cfg['puerto'] ?? 3306),
            (string)($cfg['nombre'] ?? '')
        );
        $pdo = new PDO(
            $dsn,
            (string)($cfg['usuario'] ?? ''),
            (string)($cfg['password'] ?? ''),
            [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_STRINGIFY_FETCHES  => true,
            ]
        );
        /* NOW() en hora de Madrid aunque el servidor MySQL esté en otro huso
           (el de DreamHost va en hora del Pacífico): instantes de alta,
           consolidación y cola coherentes con los del programa. */
        $pdo->exec("SET time_zone = '" . date('P') . "'");
    }
    return $pdo;
}

/* ----- Utilidades de presentación ----- */

function h(?string $texto): string
{
    return htmlspecialchars((string)$texto, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function url(string $pagina, array $parametros = []): string
{
    $parametros = ['p' => $pagina] + $parametros;
    return 'index.php?' . http_build_query($parametros);
}

function redirigir(string $pagina, array $parametros = []): never
{
    header('Location: ' . url($pagina, $parametros), true, 303);
    exit;
}

function es_post(): bool
{
    return ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST';
}

/** Valor de un campo POST recortado, sin saltos de línea de control. */
function campo(string $nombre, string $defecto = ''): string
{
    $valor = $_POST[$nombre] ?? $defecto;
    if (!is_string($valor)) {
        return $defecto;
    }
    $valor = str_replace(["\r", "\0"], '', $valor);
    return trim($valor);
}

/** Casilla de verificación: marcada => 'S', si no => 'N'. */
function campo_sn(string $nombre): string
{
    return isset($_POST[$nombre]) && $_POST[$nombre] !== '' ? 'S' : 'N';
}

function es_si(?string $valor): bool
{
    return strtoupper(trim((string)$valor)) === 'S';
}

function fecha_es(?string $fechaIso): string
{
    if ($fechaIso === null || $fechaIso === '') {
        return '';
    }
    $fecha = DateTimeImmutable::createFromFormat('Y-m-d', substr($fechaIso, 0, 10));
    return $fecha === false ? $fechaIso : $fecha->format('d/m/Y');
}

/** Convierte la fecha escrita en pantalla al formato interno de la BBDD. */
function fecha_iso_desde_es(string $valor): string
{
    $valor = trim($valor);
    if (preg_match('~^([0-9]{2})/([0-9]{2})/([0-9]{4})$~D', $valor, $p) !== 1 ||
        !checkdate((int)$p[2], (int)$p[1], (int)$p[3])) {
        return '';
    }
    return $p[3] . '-' . $p[2] . '-' . $p[1];
}

/** Presentación de instantes sin modificar la hora ni los datos guardados. */
function fecha_hora_es(?string $valor): string
{
    if ($valor === null || $valor === '') {
        return '';
    }
    return fecha_es($valor) . (strlen($valor) > 10 ? ' ' . substr($valor, 11) : '');
}

function formatear_porcentaje(?string $valor): string
{
    if ($valor === null || $valor === '') {
        return '0';
    }
    $numero = (float)$valor;
    $texto = number_format($numero, 2, ',', '.');
    return preg_replace('/,?0+$/', '', $texto) ?? $texto;
}

/* ----- CSRF ----- */

function csrf_token(): string
{
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(16));
    }
    return (string)$_SESSION['csrf'];
}

function campo_csrf(): string
{
    return '<input type="hidden" name="csrf" value="' . h(csrf_token()) . '">';
}

function comprobar_csrf(): void
{
    $recibido = (string)($_POST['csrf'] ?? '');
    if ($recibido === '' || !hash_equals(csrf_token(), $recibido)) {
        throw new RuntimeException(
            t('El formulario ha caducado. Vuelve a intentarlo.'));
    }
}

/* ----- Mensajes entre páginas ----- */

function aviso(string $tipo, string $mensaje): void
{
    $_SESSION['avisos'][] = ['tipo' => $tipo, 'mensaje' => $mensaje];
}

function avisos_pendientes(): array
{
    $avisos = $_SESSION['avisos'] ?? [];
    unset($_SESSION['avisos']);
    return is_array($avisos) ? $avisos : [];
}

/* ----- Sesión de usuario ----- */

function usuario_actual(): ?array
{
    $usuario = $_SESSION['usuario'] ?? null;
    return is_array($usuario) ? $usuario : null;
}

function exigir_usuario(): array
{
    $usuario = usuario_actual();
    if ($usuario === null) {
        redirigir('login');
    }
    return $usuario;
}

/** Solo grupos administradores (ESGRUPOADMINISTRADOR_USUGRP), como los parámetros Verifactu del programa. */
function exigir_administrador(): array
{
    $usuario = exigir_usuario();
    if (empty($usuario['admin'])) {
        aviso('error', t('Solo un usuario de un grupo administrador puede hacer esto.'));
        redirigir('menu');
    }
    return $usuario;
}
