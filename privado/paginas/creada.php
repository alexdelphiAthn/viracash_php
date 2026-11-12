<?php
declare(strict_types=1);

/*
 * Confirmación de la factura creada, modificada o emitida, con su estado
 * actual, el QR tributario si se emitió con Verifactu, el PDF y el botón
 * para emitirla si sigue en borrador.
 */

$usuario = exigir_usuario();
$creada = $_SESSION['factura_creada'] ?? null;
if (!is_array($creada)) {
    redirigir('menu');
}
$pdo = bbdd();
$serie = (string)$creada['serie'];
$numero = (string)$creada['numero'];
$modificada = !empty($creada['modificada']);
$emitida = !empty($creada['emitida']);
$factura = factura_leer($pdo, $serie, $numero);
$simplificada = !empty($creada['simplificada']) ||
    ($factura !== null && strcasecmp(trim((string)$factura['TIPO_FAC']), 'SIMPLIFICADA') === 0);
/* PDF siempre en castellano; con la web en catalán se ofrece además en catalán. */
$urlPdf = url('pdf', ['serie' => $serie, 'numero' => $numero]);
/* La simplificada sale como ticket; su equivalente en A4 queda a un clic. */
$urlPdfA4 = $simplificada ? url('pdf', ['serie' => $serie, 'numero' => $numero, 'formato' => 'a4']) : '';
$urlPdfCatalan = idioma_ofrece_factura_catalan() ? url('pdf', ['serie' => $serie, 'numero' => $numero, 'idioma' => 'ca']) : '';
$qr = $factura !== null ? factura_qr_verifactu($pdo, $usuario, $factura) : null;
$consolidacion = $factura !== null && factura_es_verifactu($factura) ? consolidacion_leer($pdo, $serie, $numero) : null;
$titulo = $emitida ? t('Factura emitida') : ($modificada ? t('Factura modificada') : t('Factura creada'));

ob_start();
?>
<section class="tarjeta exito">
  <h2><?= h(t('Factura {numero}', ['numero' => (string)$creada['numero_formateado']])) ?></h2>
  <dl class="ficha">
    <dt><?= h(t('Fecha')) ?></dt><dd><?= h(fecha_es((string)$creada['fecha'])) ?></dd>
    <dt><?= h(t('Emisor')) ?></dt><dd><?= h((string)$creada['empresa']) ?></dd>
    <?php if ($simplificada): ?>
    <dt><?= h(t('Tipo')) ?></dt><dd><?= h(t('Factura simplificada (ticket), sin cliente')) ?></dd>
    <?php else: ?>
    <dt><?= h(t('Cliente')) ?></dt><dd><?= h((string)$creada['cliente']) ?></dd>
    <?php endif; ?>
    <dt><?= h(t('Base imponible')) ?></dt><dd><?= h(formatear_importe((float)$creada['total_bases'])) ?></dd>
    <dt><?= h(t('Impuestos')) ?></dt><dd><?= h(formatear_importe((float)$creada['total_impuestos'])) ?></dd>
    <?php if ((float)$creada['total_retencion'] != 0.0): ?>
    <dt><?= h(t('Retención')) ?></dt><dd>−<?= h(formatear_importe((float)$creada['total_retencion'])) ?></dd>
    <?php endif; ?>
    <dt class="total-final"><?= h(t('Total')) ?></dt><dd class="total-final"><?= h(formatear_importe((float)$creada['total_liquido'])) ?></dd>
    <dt><?= h(t('Estado')) ?></dt><dd><?= h($factura === null ? t('Borrador') : fase_factura_texto($factura)) ?></dd>
    <?php if ($consolidacion !== null): ?>
    <dt>AEAT</dt><dd><?= h((string)$consolidacion['ESTADO_FACCON']) ?>
      <?php if (trim((string)($consolidacion['REQUEST_ID_CONSOLIDACION_FACCON'] ?? '')) !== ''): ?> · CSV <?= h((string)$consolidacion['REQUEST_ID_CONSOLIDACION_FACCON']) ?><?php endif; ?>
      <?php if (trim((string)($consolidacion['DESCRIPCION_ERROR_AEAT_FACCON'] ?? '')) !== ''): ?><br><small><?= h((string)$consolidacion['CODIGO_ERROR_AEAT_FACCON'] . ' ' . (string)$consolidacion['DESCRIPCION_ERROR_AEAT_FACCON']) ?></small><?php endif; ?></dd>
    <?php endif; ?>
  </dl>
  <?php if ($qr !== null): ?>
  <?= html_imagen_qr($qr['matriz']) ?>
  <p class="ayuda qr-leyenda"><?= h(implode(' ', $qr['leyenda'])) ?></p>
  <?php endif; ?>
</section>
<?php if ($factura !== null && factura_editable($factura)): ?>
<a class="boton principal" href="<?= h(url('factura_emitir', ['serie' => $serie, 'numero' => $numero])) ?>"><?= h(t('Emitir la factura')) ?></a>
<a class="boton secundario" href="<?= h($urlPdf) ?>" target="_blank" rel="noopener">
  <?= h($simplificada ? t('Ver e imprimir el ticket (borrador)') : t('Ver e imprimir PDF (borrador)')) ?></a>
<?php else: ?>
<a class="boton principal" href="<?= h($urlPdf) ?>" target="_blank" rel="noopener">
  <?= h($simplificada ? t('Ver e imprimir el ticket') : t('Ver e imprimir PDF')) ?></a>
<?php endif; ?>
<?php if ($urlPdfA4 !== ''): ?>
<p class="pie-enlaces"><a href="<?= h($urlPdfA4) ?>" target="_blank" rel="noopener"><?= h(t('La misma factura en A4')) ?></a></p>
<?php endif; ?>
<?php if ($urlPdfCatalan !== ''): ?>
<p class="pie-enlaces"><a href="<?= h($urlPdfCatalan) ?>" target="_blank" rel="noopener"><?= h(t('PDF en catalán')) ?></a></p>
<?php endif; ?>
<a class="boton secundario" href="<?= h(url('empresa', ['nueva' => 1])) ?>"><?= h(t('Nueva factura')) ?></a>
<a class="boton secundario" href="<?= h(url('facturas')) ?>"><?= h(t('Facturas existentes')) ?></a>
<p class="pie-enlaces"><a href="<?= h(url('menu')) ?>"><?= h(t('‹ Volver al menú')) ?></a></p>
<?php
pagina($titulo, (string)ob_get_clean());
