<?php
declare(strict_types=1);

/* Paso 7: totales y confirmación antes de grabar la factura. */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = exigir_paso('resumen');
$empresa = $borrador['empresa'];
$cliente = $borrador['cliente'];
$fecha = (string)$borrador['fecha'];

$avisos = factura_avisos($pdo, $borrador);
$cabecera = cabecera_provisional($pdo, $usuario, $borrador);
$calculo = calcular_factura($cabecera, $borrador['lineas']);
$totales = $calculo['totales'];
$cfg = $calculo['configuracion'];
$previsto = factura_numero_previsto($pdo, $borrador);
$numeroFormateado = numero_documento_formateado($empresa, (string)$borrador['serie'], $previsto['numero']);
if (!isset($cabecera['CODIGO_IVA_FAC'])) {
    $avisos[] = t('La zona de IVA de la empresa no tiene porcentajes vigentes en la fecha de la factura.');
}
if (es_si((string)$cabecera['ESRETENCIONES_EMPRESA_FAC']) && es_si((string)$cabecera['ESRETENCIONES_CLIENTE_FAC']) &&
    (float)$cabecera['PORCENTAJE_RETENCION_FAC'] == 0.0) {
    $avisos[] = t('La empresa aplica retenciones pero no tiene porcentaje vigente en empresas → retenciones.');
}
$formaPago = forma_pago_descripcion($pdo, (string)$cabecera['FORMA_PAGO_FAC']);
$palabraIva = $cfg['palabra_iva'] !== '' ? $cfg['palabra_iva'] : 'IVA';

ob_start();
?>
<section class="tarjeta">
  <h2><?= h(t('Factura {numero}', ['numero' => $numeroFormateado])) ?></h2>
  <dl class="ficha">
    <dt><?= h(t('Fecha')) ?></dt><dd><?= h(fecha_es($fecha)) ?></dd>
    <dt><?= h(t('Número')) ?></dt><dd><?= h($previsto['numero']) ?> <small>(<?= h(t($previsto['texto'])) ?>)</small></dd>
    <dt><?= h(t('Emisor')) ?></dt><dd><?= h((string)$empresa['RAZON_SOCIAL_EMP']) ?> · <?= h((string)$empresa['NIF_EMP']) ?></dd>
    <?php if (is_array($cliente)): ?>
    <dt><?= h(t('Cliente')) ?></dt><dd><?= h((string)$cliente['RAZON_SOCIAL_CLI']) ?> · <?= h((string)$cliente['NIF_CLI']) ?></dd>
    <?php else: ?>
    <dt><?= h(t('Tipo')) ?></dt><dd><?= h(t('Factura simplificada (ticket), sin cliente')) ?></dd>
    <?php endif; ?>
    <dt><?= h(t('Forma de pago')) ?></dt><dd><?= h($formaPago === '' ? '—' : $formaPago) ?></dd>
  </dl>
  <a class="enlace-editar" href="<?= h(url('cabecera')) ?>"><?= h(t('Cambiar')) ?></a>
</section>
<section class="tarjeta">
  <h2><?= h(t('Líneas')) ?></h2>
  <div class="tabla-envoltorio">
  <table class="tabla">
    <thead><tr><th><?= h(t('Descripción')) ?></th><th class="num"><?= h(t('Cant.')) ?></th><th class="num"><?= h(t('Precio')) ?></th><th class="num"><?= h(t('Total')) ?></th></tr></thead>
    <tbody>
    <?php foreach ($calculo['lineas'] as $linea): ?>
    <tr>
      <td><?= h((string)$linea['descripcion']) ?><?= (float)$linea['porcentaje_dto'] > 0 ? '<br><small>' . h(t('Dto. {pct} %', ['pct' => formatear_porcentaje((string)$linea['porcentaje_dto'])])) . '</small>' : '' ?></td>
      <td class="num"><?= h(formatear_cantidad((float)$linea['cantidad'])) ?> <?= h((string)$linea['unidad']) ?></td>
      <td class="num"><?= h(formatear_importe((float)$linea['precio_siva'])) ?></td>
      <td class="num"><?= h(formatear_importe((float)$linea['base_linea'])) ?></td>
    </tr>
    <?php endforeach; ?>
    </tbody>
  </table>
  </div>
  <p class="ayuda"><?= h(t('Precios y totales de línea sin {iva}.', ['iva' => $palabraIva])) ?></p>
  <a class="enlace-editar" href="<?= h(url('lineas')) ?>"><?= h(t('Cambiar')) ?></a>
</section>
<section class="tarjeta totales">
  <h2><?= h(t('Totales')) ?></h2>
  <dl class="ficha">
    <dt><?= h(t('Base imponible')) ?></dt><dd><?= h(formatear_importe($totales['total_bases'])) ?></dd>
    <?php foreach ($totales['por_tipo'] as $tipo => $datos): ?>
      <?php if ($datos['base'] != 0.0 || $datos['iva'] != 0.0): ?>
      <dt><?= h($palabraIva) ?> <?= h(formatear_porcentaje((string)$datos['porcentaje_iva'])) ?> %</dt><dd><?= h(formatear_importe($datos['iva'])) ?></dd>
      <?php if ($datos['recargo'] != 0.0): ?>
      <dt><?= h(t('Recargo equiv. {pct} %', ['pct' => formatear_porcentaje((string)$datos['porcentaje_recargo'])])) ?></dt><dd><?= h(formatear_importe($datos['recargo'])) ?></dd>
      <?php endif; ?>
      <?php endif; ?>
    <?php endforeach; ?>
    <?php if ($totales['total_retencion'] != 0.0): ?>
    <dt><?= h(t('Retención IRPF {pct} %', ['pct' => formatear_porcentaje((string)$totales['porcentaje_retencion'])])) ?></dt><dd>−<?= h(formatear_importe($totales['total_retencion'])) ?></dd>
    <?php endif; ?>
    <dt class="total-final"><?= h(t('Total factura')) ?></dt><dd class="total-final"><?= h(formatear_importe($totales['total_liquido'])) ?></dd>
  </dl>
</section>
<form method="post" action="<?= h(url('crear')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <?php if (editando($borrador) !== null): ?>
  <p class="ayuda"><?= h(t('Se guardarán los cambios de fecha, cliente y líneas (renumeradas) y se recalcularán los totales. Después podrás verla e imprimirla en PDF.')) ?></p>
  <button type="submit" class="boton principal"><?= h(t('Guardar cambios')) ?></button>
  <?php else: ?>
  <?php if (es_simplificada($borrador)): ?>
  <p class="ayuda"><?= h(t('Se grabará la factura simplificada en borrador (tipo SIMPLIFICADA, sin cliente), igual que un ticket de caja. Después podrás verla e imprimirla como ticket en PDF.')) ?></p>
  <?php else: ?>
  <p class="ayuda"><?= h(t('Se grabará la factura en borrador con cabecera, líneas y totales, igual que el programa. Después podrás verla e imprimirla en PDF.')) ?></p>
  <?php endif; ?>
  <button type="submit" class="boton principal"><?= h(t('Crear factura')) ?></button>
  <?php endif; ?>
</form>
<p class="pie-enlaces"><a href="<?= h(url('lineas')) ?>"><?= h(t('‹ Volver a las líneas')) ?></a></p>
<?php
pagina(t('Totales'), (string)ob_get_clean(), ['paso' => 'resumen', 'avisos' => $avisos]);
