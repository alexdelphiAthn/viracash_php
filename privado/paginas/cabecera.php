<?php
declare(strict_types=1);

/*
 * Paso 3: fecha, serie y número de la factura (ventas mayor -> facturas).
 * La serie se propone desde empresas -> series de la empresa emisora ya
 * confirmada y el número queda a 0 para que lo asigne el contador
 * automático al grabar.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = exigir_paso('cabecera');
$empresa = $borrador['empresa'];
$codigoEmpresa = (string)$empresa['CODIGO_EMP_EMP'];
/* Al modificar una factura existente, la serie y el número no cambian. */
$edicion = editando($borrador);

$fecha = (string)$borrador['fecha'];
$serie = (string)$borrador['serie'];
$numero = (string)$borrador['numero'];
$otraSerie = '';
$errores = [];
/* La simplificada no tiene cliente del que copiar la forma de pago: se
   elige aquí, como el cobro de la caja. */
$simplificada = es_simplificada($borrador);
$formasPago = $simplificada ? formas_pago_listar($pdo) : [];
$formaPago = (string)$borrador['forma_pago'];
if ($simplificada && $formaPago === '') {
    $formaPago = forma_pago_defecto($pdo);
}

function fecha_valida(string $fecha): bool
{
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})$/', $fecha, $partes) !== 1) {
        return false;
    }
    return checkdate((int)$partes[2], (int)$partes[3], (int)$partes[1]);
}

if (es_post()) {
    comprobar_csrf();
    $fecha = fecha_iso_desde_es(campo('fecha'));
    $serieSeleccionada = campo('serie');
    $otraSerie = strtoupper(campo('otra_serie'));
    $numero = campo('numero', '0');
    $refrescar = campo('accion') === 'refrescar';
    if ($simplificada) {
        $formaPago = campo('forma_pago', $formaPago);
    }
    if ($edicion !== null) {
        $serieSeleccionada = (string)$edicion['serie'];
        $otraSerie = '';
        $numero = (string)$edicion['numero'];
    }

    if (!fecha_valida($fecha)) {
        $errores[] = t('Indica una fecha válida.');
        $fecha = date('Y-m-d');
    }
    if ($refrescar) {
        $serie = $serieSeleccionada;
    } else {
        $serie = $otraSerie !== '' ? $otraSerie : $serieSeleccionada;
        if ($serie === '') {
            $errores[] = t('Indica la serie de la factura.');
        } elseif (strlen($serie) > 12 || preg_match('#^[A-Za-z0-9._/-]+$#', $serie) !== 1) {
            $errores[] = t('La serie admite hasta 12 caracteres: letras, números, punto, guion y barra.');
        }
        $numero = ltrim($numero) === '' ? '0' : $numero;
        if (preg_match('/^\d{1,20}$/', $numero) !== 1) {
            $errores[] = t('El número debe ser numérico (déjalo a 0 para el contador automático).');
        } elseif ((int)$numero === 0) {
            $numero = '0';
        } elseif ($serie !== '' && $edicion === null) {
            /* Número manual: mismos ceros a la izquierda que el contador de la serie. */
            $digitos = contador_factura_digitos($pdo, $serie, $codigoEmpresa);
            $numero = str_pad(ltrim($numero, '0'), max($digitos, 1), '0', STR_PAD_LEFT);
        }
        if ($errores === []) {
            $borrador['fecha'] = $fecha;
            $borrador['serie'] = $serie;
            $borrador['numero'] = $numero;
            $borrador['forma_pago'] = $simplificada ? $formaPago : '';
            borrador_guardar($borrador);
            redirigir($simplificada ? 'lineas' : 'cliente');
        }
    }
}

$series = $edicion === null ? series_factura($pdo, $codigoEmpresa, $fecha) : [];
if ($serie === '' && $edicion === null) {
    $serie = serie_defecto($pdo, $codigoEmpresa, $fecha, $series);
}
$opcionesSerie = [];
foreach ($series as $filaSerie) {
    $codigoSerie = (string)$filaSerie['SERIE_CON'];
    $texto = $codigoSerie;
    if (es_si($filaSerie['ESSERIE_EMPRESA'] ?? 'N')) {
        $texto .= ' · ' . t('empresa');
    }
    if (es_si($filaSerie['DEFAULT_CON'] ?? 'N')) {
        $texto .= ' · ' . t('por defecto');
    }
    $opcionesSerie[$codigoSerie] = $texto;
}
if ($serie !== '' && !isset($opcionesSerie[$serie]) && $otraSerie === '') {
    $otraSerie = $serie;
}
$serieEnLista = isset($opcionesSerie[$serie]) ? $serie : '';
$previsto = $serie !== '' ? contador_factura_previsto($pdo, $serie, $codigoEmpresa) : null;
$textoPrevisto = '';
if ($previsto !== null) {
    $textoPrevisto = t(': ahora sería el <strong>{numero}</strong>', ['numero' => h($previsto['numero'])]) .
        ($previsto['existe'] ? '' : ' ' . h(t('(el contador de esta serie se creará al grabar)')));
}

ob_start();
?>
<?php if ($edicion !== null): ?>
<p class="nota"><?= t('Factura <strong>{numero}</strong> de <strong>{empresa}</strong>. Al modificar, la empresa, la serie y el número no cambian.', [
    'numero' => h((string)$edicion['numero_formateado']), 'empresa' => h((string)$empresa['RAZON_SOCIAL_EMP']),
]) ?></p>
<?php else: ?>
<p class="nota"><?= t('Series de <strong>{empresa}</strong> ({nif}).', [
    'empresa' => h((string)$empresa['RAZON_SOCIAL_EMP']), 'nif' => h((string)$empresa['NIF_EMP']),
]) ?>
  <a href="<?= h(url('empresa')) ?>"><?= h(t('Cambiar de empresa')) ?></a></p>
<?php endif; ?>
<form method="post" action="<?= h(url('cabecera')) ?>" class="formulario" data-refrescar="1">
  <?= campo_csrf() ?>
  <input type="hidden" name="accion" value="">
  <?= campo_texto('fecha', t('Fecha de la factura'), fecha_es($fecha), [
      'type' => 'text',
      'placeholder' => 'dd/mm/yyyy',
      'maxlength' => '10',
      'pattern' => '[0-9]{2}/[0-9]{2}/[0-9]{4}',
      'required' => 'required',
  ]) ?>
  <?php if ($edicion !== null): ?>
  <input type="hidden" name="serie" value="<?= h((string)$edicion['serie']) ?>">
  <input type="hidden" name="otra_serie" value="">
  <input type="hidden" name="numero" value="<?= h((string)$edicion['numero']) ?>">
  <dl class="ficha">
    <dt><?= h(t('Serie')) ?></dt><dd><?= h((string)$edicion['serie']) ?></dd>
    <dt><?= h(t('Número')) ?></dt><dd><?= h((string)$edicion['numero']) ?></dd>
  </dl>
  <?php elseif ($opcionesSerie !== []): ?>
  <label class="campo"><span><?= h(t('Serie')) ?></span>
    <select name="serie">
      <?= opciones_select(['' => t('— Escribir otra serie —')] + $opcionesSerie, $serieEnLista) ?>
    </select>
  </label>
  <?= campo_texto('otra_serie', t('Otra serie (si no está en la lista)'), $otraSerie, [
      'autocapitalize' => 'characters',
      'autocorrect' => 'off',
      'maxlength' => '12',
      'placeholder' => t('Ej. 2026.AN1'),
  ]) ?>
  <?php else: ?>
  <input type="hidden" name="serie" value="">
  <?= campo_texto('otra_serie', t('Serie'), $otraSerie, [
      'autocapitalize' => 'characters',
      'autocorrect' => 'off',
      'maxlength' => '12',
      'required' => 'required',
      'placeholder' => t('Ej. 2026.AN1'),
  ]) ?>
  <p class="ayuda"><?= h(t('La empresa no tiene series de factura definidas: escribe una y su contador se creará al grabar.')) ?></p>
  <?php endif; ?>
  <?php if ($edicion === null): ?>
  <?= campo_texto('numero', t('Número de factura'), $numero, [
      'inputmode' => 'numeric',
      'pattern' => '[0-9]*',
      'maxlength' => '20',
  ]) ?>
  <p class="ayuda"><?= t('Déjalo a <strong>0</strong> y al grabar la factura tomará el siguiente número del contador automático de la serie{previsto}. Si escribes un número, se grabará tal cual.', [
      'previsto' => $textoPrevisto,
  ]) ?></p>
  <noscript><button type="submit" name="accion" value="refrescar" class="boton secundario"><?= h(t('Actualizar series para la fecha')) ?></button></noscript>
  <?php endif; ?>
  <?php if ($simplificada): ?>
  <label class="campo"><span><?= h(t('Forma de pago')) ?></span>
    <select name="forma_pago">
      <?php
        $opcionesPago = [];
        foreach ($formasPago as $filaPago) {
            $opcionesPago[(string)$filaPago['CODIGO_FP_FP']] = (string)$filaPago['DESCRIPCION_FORMA_PAGO_FP'] .
                (es_si((string)$filaPago['ESDEFAULT_FORMA_PAGO_FP']) ? ' · ' . t('por defecto') : '');
        }
      ?>
      <?= opciones_select($opcionesPago, $formaPago) ?>
    </select>
  </label>
  <p class="ayuda"><?= h(t('La forma de pago sale en el ticket bajo el importe a pagar, como en la caja.')) ?></p>
  <?php endif; ?>
  <button type="submit" class="boton principal"><?= h(t('Continuar')) ?></button>
</form>
<?php if ($edicion === null): ?>
<p class="pie-enlaces"><a href="<?= h(url('empresa_datos')) ?>"><?= h(t('‹ Volver a los datos de la empresa')) ?></a></p>
<?php else: ?>
<p class="pie-enlaces"><a href="<?= h(url('facturas')) ?>"><?= h(t('‹ Volver a las facturas')) ?></a></p>
<?php endif; ?>
<?php
pagina($simplificada ? t('Fecha, serie y pago') : t('Fecha y serie'), (string)ob_get_clean(),
    ['paso' => 'cabecera', 'errores' => $errores]);
