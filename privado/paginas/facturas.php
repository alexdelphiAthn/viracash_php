<?php
declare(strict_types=1);

/*
 * Histórico: las últimas 5, 10, 20 o 100 facturas por fecha, con PDF,
 * emisión (Verifactu o sin Verifactu, según el modo), modificación y borrado
 * (estos dos solo para facturas en borrador sin consolidar, como en el
 * programa).
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$limite = (int)($_GET['n'] ?? 10);
if (!in_array($limite, [5, 10, 20, 100], true)) {
    $limite = 10;
}
$facturas = facturas_ultimas($pdo, $limite);
$empresas = [];
/* PDF siempre en castellano; con la web en catalán se ofrece además en catalán. */
$ofreceCatalan = idioma_ofrece_factura_catalan();

function clase_estado_factura(array $factura): string
{
    $fase = strtoupper(trim((string)($factura['FASE_FAC'] ?? '')));
    if (factura_editable($factura)) {
        return 'borrador';
    }
    return match ($fase) {
        FASE_FACTURA_VERIFACTU_PENDIENTE => 'pendiente',
        FASE_FACTURA_VERIFACTU_ERROR => 'error',
        default => 'cerrada',
    };
}

ob_start();
?>
<p class="filtros"><?= h(t('Últimas facturas por fecha:')) ?>
  <?php foreach ([5, 10, 20, 100] as $n): ?>
  <a href="<?= h(url('facturas', ['n' => $n])) ?>" class="<?= $n === $limite ? 'activo' : '' ?>"><?= $n ?></a>
  <?php endforeach; ?>
</p>
<?php if ($facturas === []): ?>
<p class="nota"><?= h(t('No hay facturas.')) ?></p>
<?php endif; ?>
<div class="lista">
<?php foreach ($facturas as $factura): ?>
  <?php
    $codigoEmpresa = (string)$factura['CODIGO_EMP_FAC'];
    if (!array_key_exists($codigoEmpresa, $empresas)) {
        $empresas[$codigoEmpresa] = empresa_por_codigo($pdo, $codigoEmpresa);
    }
    $serie = (string)$factura['SERIE_FAC'];
    $numero = (string)$factura['NUMERO_FAC'];
    $numeroFormateado = numero_documento_formateado($empresas[$codigoEmpresa], $serie, $numero);
    $editable = factura_editable($factura);
    $parametros = ['serie' => $serie, 'numero' => $numero];
    $simplificada = strcasecmp(trim((string)($factura['TIPO_FAC'] ?? '')), 'SIMPLIFICADA') === 0;
  ?>
  <div class="factura-fila">
    <div class="factura-datos">
      <strong><?= h($numeroFormateado) ?></strong>
      <span class="estado <?= clase_estado_factura($factura) ?>"><?= h(fase_factura_texto($factura)) ?></span>
      <small><?= h(fecha_es((string)$factura['FECHA_FAC'])) ?> · <?= $simplificada && trim((string)$factura['RAZON_SOCIAL_CLIENTE_FAC']) === ''
          ? h(t('Simplificada (ticket)')) : h((string)$factura['RAZON_SOCIAL_CLIENTE_FAC']) ?>
        <?= trim((string)$factura['NIF_CLIENTE_FAC']) !== '' ? '(' . h((string)$factura['NIF_CLIENTE_FAC']) . ')' : '' ?></small>
      <small><?= h(t('Emisor: {nombre}', ['nombre' => (string)$factura['RAZON_SOCIAL_EMPRESA_FAC']])) ?></small>
      <span class="importe"><?= h(formatear_importe((float)$factura['TOTAL_LIQUIDO_FAC'])) ?></span>
    </div>
    <div class="factura-acciones">
      <a class="boton-mini" href="<?= h(url('pdf', $parametros)) ?>" target="_blank" rel="noopener"><?= $simplificada ? h(t('Ticket')) : 'PDF' ?></a>
      <?php if ($simplificada): ?>
      <a class="boton-mini" href="<?= h(url('pdf', $parametros + ['formato' => 'a4'])) ?>" target="_blank" rel="noopener"
         title="<?= h(t('La misma factura en A4')) ?>">A4</a>
      <?php endif; ?>
      <?php if ($ofreceCatalan): ?>
      <a class="boton-mini" href="<?= h(url('pdf', $parametros + ['idioma' => 'ca'])) ?>" target="_blank" rel="noopener"
         title="<?= h(t('PDF en catalán')) ?>">PDF · CA</a>
      <?php endif; ?>
      <?php if ($editable): ?>
      <a class="boton-mini principal" href="<?= h(url('factura_emitir', $parametros)) ?>"><?= h(t('Emitir')) ?></a>
      <form method="post" action="<?= h(url('factura_editar')) ?>">
        <?= campo_csrf() ?>
        <input type="hidden" name="serie" value="<?= h($serie) ?>">
        <input type="hidden" name="numero" value="<?= h($numero) ?>">
        <button type="submit" class="boton-mini"><?= h(t('Modificar')) ?></button>
      </form>
      <a class="boton-mini peligro" href="<?= h(url('factura_borrar', $parametros)) ?>"><?= h(t('Borrar')) ?></a>
      <?php endif; ?>
      <?php if (($factura['FASE_FAC'] ?? '') === FASE_FACTURA_VERIFACTU_OK): ?>
        <?php $anulacion = verifactu_anulacion_cola($pdo, $serie, $numero); ?>
        <?php if ($anulacion === null): ?>
        <a class="boton-mini peligro" href="<?= h(url('factura_anular_verifactu', $parametros)) ?>"><?= h(t('Cancelar Verifactu')) ?></a>
        <?php else: ?>
        <a class="boton-mini" href="<?= h(url('verifactu')) ?>"><?= h(t('Anulación: {estado}', ['estado' => (string)$anulacion['ESTADO_VFCOLA']])) ?></a>
        <?php endif; ?>
      <?php endif; ?>
    </div>
  </div>
<?php endforeach; ?>
</div>
<p class="pie-enlaces"><a href="<?= h(url('resumen_facturas')) ?>"><?= h(t('Resumen entre fechas para Excel')) ?></a> · <a href="<?= h(url('menu')) ?>"><?= h(t('‹ Volver al menú')) ?></a></p>
<?php
pagina(t('Facturas existentes'), (string)ob_get_clean());
