<?php
declare(strict_types=1);

/* Graba la factura (cabecera, líneas y totales) y pasa a la confirmación. */

$usuario = exigir_usuario();
if (!es_post()) {
    redirigir('resumen');
}
comprobar_csrf();
$pdo = bbdd();
$borrador = exigir_paso('crear');

$modificada = editando($borrador) !== null;
$resultado = $modificada
    ? factura_actualizar($pdo, $usuario, $borrador)
    : factura_crear($pdo, $usuario, $borrador);
$_SESSION['factura_creada'] = [
    'modificada'        => $modificada,
    'serie'             => $resultado['serie'],
    'numero'            => $resultado['numero'],
    'numero_formateado' => $resultado['numero_formateado'],
    'fecha'             => (string)$borrador['fecha'],
    'empresa'           => (string)$borrador['empresa']['RAZON_SOCIAL_EMP'],
    'cliente'           => is_array($borrador['cliente'])
        ? (string)$borrador['cliente']['RAZON_SOCIAL_CLI'] : '',
    'simplificada'      => es_simplificada($borrador),
    'total_bases'       => $resultado['totales']['total_bases'],
    'total_impuestos'   => $resultado['totales']['total_impuestos'],
    'total_retencion'   => $resultado['totales']['total_retencion'],
    'total_liquido'     => $resultado['totales']['total_liquido'],
];
borrador_reiniciar();
redirigir('creada');
