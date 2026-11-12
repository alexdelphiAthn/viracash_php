<?php
declare(strict_types=1);

/* Carga una factura en borrador en la sesión para modificarla. */

exigir_usuario();
if (!es_post()) {
    redirigir('facturas');
}
comprobar_csrf();
$pdo = bbdd();
$serie = campo('serie');
$numero = campo('numero');
try {
    $borrador = factura_cargar_en_borrador($pdo, $serie, $numero);
} catch (RuntimeException $error) {
    aviso('error', $error->getMessage());
    redirigir('facturas');
}
aviso('ok', t('Modificando la factura {numero}. La empresa, la serie y el número no cambian; revisa fecha, cliente y líneas.',
    ['numero' => $borrador['editando']['numero_formateado']]));
redirigir('cabecera');
