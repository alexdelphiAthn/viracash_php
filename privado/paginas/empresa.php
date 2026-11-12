<?php
declare(strict_types=1);

/*
 * Paso 1: NIF de la empresa emisora. Se propone la empresa por defecto del
 * usuario (EMPRESA_DEFECTO_USU) o la única que exista. Si el NIF no existe,
 * la empresa se creará en la pantalla siguiente con el contador de empresas
 * (EM).
 */

$usuario = exigir_usuario();
$pdo = bbdd();
if (isset($_GET['nueva'])) {
    /* Desde el menú: se descarta cualquier factura o modificación en curso.
       Con tipo=simplificada se empieza un ticket (factura sin destinatario). */
    borrador_reiniciar();
    if ((string)($_GET['tipo'] ?? '') === 'simplificada') {
        $borradorNuevo = borrador();
        $borradorNuevo['simplificada'] = true;
        borrador_guardar($borradorNuevo);
    }
    redirigir('empresa');
}
$borrador = exigir_paso('empresa');
if (editando($borrador) !== null) {
    aviso('aviso', t('Al modificar una factura no se cambia la empresa emisora. Si necesitas otra empresa, bórrala y créala de nuevo.'));
    redirigir('cabecera');
}

$empresaActual = is_array($borrador['empresa'])
    ? $borrador['empresa']
    : empresa_inicial($pdo, $usuario);
$nif = (string)($empresaActual['NIF_EMP'] ?? '');
$empresas = empresas_listar($pdo);
$candidatas = [];
$errores = [];

function empresa_pendiente(array $borrador, string $codigo, string $nif): never
{
    $borrador['empresa_pendiente'] = ['codigo' => $codigo, 'nif' => $nif];
    borrador_guardar($borrador);
    redirigir('empresa_datos');
}

if (es_post()) {
    comprobar_csrf();
    $codigo = campo('codigo');
    $nif = strtoupper(campo('nif'));
    if ($codigo !== '') {
        $elegida = empresa_por_codigo($pdo, $codigo);
        if ($elegida === null) {
            $errores[] = t('La empresa elegida ya no existe.');
        } else {
            empresa_pendiente($borrador, $codigo, (string)$elegida['NIF_EMP']);
        }
    } elseif ($nif === '') {
        $errores[] = t('Escribe el NIF de la empresa emisora.');
    } else {
        $candidatas = empresas_por_nif($pdo, $nif);
        if (count($candidatas) === 1) {
            empresa_pendiente($borrador, (string)$candidatas[0]['CODIGO_EMP_EMP'], $nif);
        }
        if ($candidatas === []) {
            aviso('aviso', t('No hay ninguna empresa con NIF {nif}: se creará una nueva.', ['nif' => $nif]));
            empresa_pendiente($borrador, '', $nif);
        }
    }
}

ob_start();
?>
<p class="nota"><?= h(t('Se propone la empresa por defecto del usuario. Escribe otro NIF o elige una de la lista.')) ?></p>
<form method="post" action="<?= h(url('empresa')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <?= campo_texto('nif', t('NIF de la empresa emisora'), $nif, [
      'autocapitalize' => 'characters',
      'autocorrect' => 'off',
      'spellcheck' => 'false',
      'required' => 'required',
      'autofocus' => 'autofocus',
      'maxlength' => '50',
      'enterkeyhint' => 'go',
  ]) ?>
  <button type="submit" class="boton principal"><?= h(t('Buscar y continuar')) ?></button>
  <?php if ($candidatas !== []): ?>
  <h2><?= h(t('Hay varias empresas con ese NIF')) ?></h2>
  <div class="lista">
    <?php foreach ($candidatas as $candidata): ?>
    <button type="submit" name="codigo" value="<?= h((string)$candidata['CODIGO_EMP_EMP']) ?>" class="elemento">
      <strong><?= h((string)$candidata['RAZON_SOCIAL_EMP']) ?></strong>
      <small><?= h(t('Código {codigo} · {poblacion}', ['codigo' => (string)$candidata['CODIGO_EMP_EMP'], 'poblacion' => (string)$candidata['POBLACION_EMP']])) ?></small>
    </button>
    <?php endforeach; ?>
  </div>
  <?php elseif ($empresas !== []): ?>
  <h2><?= h(t('O elige una empresa')) ?></h2>
  <div class="lista">
    <?php foreach ($empresas as $fila): ?>
    <button type="submit" name="codigo" value="<?= h((string)$fila['CODIGO_EMP_EMP']) ?>" class="elemento">
      <strong><?= h((string)$fila['RAZON_SOCIAL_EMP']) ?></strong>
      <small><?= h((string)$fila['NIF_EMP']) ?> · <?= h((string)$fila['POBLACION_EMP']) ?></small>
    </button>
    <?php endforeach; ?>
  </div>
  <?php endif; ?>
</form>
<?php
pagina(t('Empresa emisora'), (string)ob_get_clean(), ['paso' => 'empresa', 'errores' => $errores]);
