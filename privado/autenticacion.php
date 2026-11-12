<?php
declare(strict_types=1);

/*
 * Autenticación contra fza_usuarios, igual que la pantalla de logon del
 * programa (UniDataLogonRepositorio): la contraseña se guarda como MD5 en
 * hexadecimal mayúsculas y se compara con la introducida; al entrar se
 * actualiza ULTIMO_LOGIN_USU.
 */

const SQL_AUTENTICAR =
    'SELECT U.PASSWORD_USU, COALESCE(U.ESACTIVO_USU, \'N\') AS ESACTIVO_USU, ' .
    'U.GRUPO_USU, U.EMPRESA_DEFECTO_USU, U.ALMACEN_DEFECTO_USU, ' .
    'U.CAJA_DEFECTO_USU, ' .
    'COALESCE(G.ESGRUPOADMINISTRADOR_USUGRP, \'N\') AS ESGRUPOADMINISTRADOR_USUGRP ' .
    'FROM fza_usuarios U ' .
    'LEFT JOIN fza_usuarios_grupos G ON G.GRUPO_USUGRP = U.GRUPO_USU ' .
    'WHERE U.USUARIO_USU = ? ' .
    'ORDER BY U.USUARIO_USU LIMIT 1';

const SQL_ULTIMO_LOGIN =
    'UPDATE fza_usuarios SET ULTIMO_LOGIN_USU = NOW() WHERE USUARIO_USU = ?';

/** Mismo hash que sMD5 de inLibWin: MD5 del texto en UTF-8, hexadecimal mayúsculas. */
function hash_contrasena(string $contrasena): string
{
    return strtoupper(md5($contrasena));
}

/**
 * Devuelve los datos de sesión del usuario o null si las credenciales no
 * son válidas. No distingue entre usuario inexistente y contraseña errónea.
 */
function autenticar(PDO $pdo, string $usuario, string $contrasena): ?array
{
    $usuario = trim($usuario);
    if ($usuario === '' || $contrasena === '') {
        return null;
    }
    $consulta = $pdo->prepare(SQL_AUTENTICAR);
    $consulta->execute([$usuario]);
    $fila = $consulta->fetch();
    $consulta->closeCursor();
    if (!is_array($fila)) {
        return null;
    }
    $esperado = strtoupper(trim((string)($fila['PASSWORD_USU'] ?? '')));
    if ($esperado === '' || !hash_equals($esperado, hash_contrasena($contrasena))) {
        return null;
    }
    if (!es_si($fila['ESACTIVO_USU'] ?? 'N')) {
        return null;
    }
    $actualizacion = $pdo->prepare(SQL_ULTIMO_LOGIN);
    $actualizacion->execute([$usuario]);
    $actualizacion->closeCursor();
    return [
        'usuario'  => $usuario,
        'grupo'    => (string)($fila['GRUPO_USU'] ?? ''),
        'admin'    => es_si($fila['ESGRUPOADMINISTRADOR_USUGRP'] ?? 'N'),
        'empresa'  => trim((string)($fila['EMPRESA_DEFECTO_USU'] ?? '')),
        'almacen'  => trim((string)($fila['ALMACEN_DEFECTO_USU'] ?? '')),
        'caja'     => trim((string)($fila['CAJA_DEFECTO_USU'] ?? '')),
    ];
}

function abrir_sesion_usuario(array $datos): void
{
    session_regenerate_id(true);
    $_SESSION['usuario'] = $datos;
    unset($_SESSION['factura']);
}

function cerrar_sesion_usuario(): void
{
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $parametros = session_get_cookie_params();
        setcookie(session_name(), '', [
            'expires'  => time() - 42000,
            'path'     => $parametros['path'],
            'domain'   => $parametros['domain'],
            'secure'   => $parametros['secure'],
            'httponly' => $parametros['httponly'],
            'samesite' => $parametros['samesite'],
        ]);
    }
    session_destroy();
}
