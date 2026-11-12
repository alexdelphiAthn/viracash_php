<?php
declare(strict_types=1);

/* Confirmación y borrado de una factura en borrador (con sus líneas). */

exigir_usuario();
$pdo = bbdd();
$serie = trim((string)(es_post() ? campo('serie') : ($_GET['serie'] ?? '')));
$numero = trim((string)(es_post() ? campo('numero') : ($_GET['numero'] ?? '')));
$factura = $serie !== '' && $numero !== '' ? factura_leer($pdo, $serie, $numero) : null;
if ($factura === null) {
    aviso('error', t('No existe la factura {serie} {numero}.', ['serie' => $serie, 'numero' => $numero]));
    redirigir('facturas');
}
if (!factura_editable($factura)) {
    aviso('error', t('Solo se pueden borrar facturas en borrador sin consolidar.'));
    redirigir('facturas');
}
$empresa = empresa_por_codigo($pdo, (string)$factura['CODIGO_EMP_FAC']);
$numeroFormateado = numero_documento_formateado($empresa, $serie, $numero);

if (es_post()) {
    comprobar_csrf();
    if (campo('confirmar') !== 'S') {
        redirigir('facturas');
    }
    $borrada = factura_borrar($pdo, $serie, $numero);
    $borrador = borrador();
    $edicion = editando($borrador);
    if ($edicion !== null && $edicion['serie'] === $serie && $edicion['numero'] === $numero) {
        borrador_reiniciar();
    }
    aviso($borrada ? 'ok' : 'error', $borrada
        ? t('Factura {numero} borrada.', ['numero' => $numeroFormateado])
        : t('No se ha podido borrar la factura {numero}.', ['numero' => $numeroFormateado]));
    redirigir('facturas');
}

ob_start();
?>
<section class="tarjeta">
  <h2><?= h(t('Factura {numero}', ['numero' => $numeroFormateado])) ?></h2>
  <dl class="ficha">
    <dt><?= h(t('Fecha')) ?></dt><dd><?= h(fecha_es((string)$factura['FECHA_FAC'])) ?></dd>
    <dt><?= h(t('Cliente')) ?></dt><dd><?= h((string)$factura['RAZON_SOCIAL_CLIENTE_FAC']) ?></dd>
    <dt><?= h(t('Total')) ?></dt><dd><?= h(formatear_importe((float)$factura['TOTAL_LIQUIDO_FAC'])) ?></dd>
    <dt><?= h(t('Estado')) ?></dt><dd><?= h(t('Borrador')) ?></dd>
  </dl>
</section>
<form method="post" action="<?= h(url('factura_borrar')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <input type="hidden" name="serie" value="<?= h($serie) ?>">
  <input type="hidden" name="numero" value="<?= h($numero) ?>">
  <input type="hidden" name="confirmar" value="S">
  <p class="ayuda"><?= h(t('Se borrarán la cabecera y sus líneas. El número de la serie no se reutiliza: el contador sigue en el siguiente, igual que en el programa.')) ?></p>
  <button type="submit" class="boton peligro"><?= h(t('Borrar la factura')) ?></button>
</form>
<p class="pie-enlaces"><a href="<?= h(url('facturas')) ?>"><?= h(t('‹ No borrar, volver')) ?></a></p>
<?php
pagina(t('Borrar factura'), (string)ob_get_clean());
