<?php
declare(strict_types=1);

/* Cambio del modo Verifactu de la web (SIN, PRE, PRO o SII) desde el menú. */

$usuario = exigir_administrador();
if (!es_post()) {
    redirigir('menu');
}
comprobar_csrf();
try {
    $aviso = verifactu_cambiar_modo(bbdd(), $usuario, campo('modo'), campo('sii_pruebas') === 'S');
    $modo = verifactu_modo_web(bbdd(), $usuario);
    aviso('ok', t('Modo Verifactu de la web: {modo}.', ['modo' => verifactu_modo_descripcion($modo['modo'])]));
    if ($aviso !== '') {
        aviso('aviso', $aviso);
    }
} catch (Throwable $error) {
    aviso('error', $error->getMessage());
}
redirigir('menu');
