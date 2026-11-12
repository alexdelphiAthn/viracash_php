<?php
declare(strict_types=1);

/*
 * Paso 4: DNI/NIF del cliente. Si existe se cargan sus datos; si no, se
 * pasa directamente a la ficha para darlo de alta.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = exigir_paso('cliente');

$nif = is_array($borrador['cliente']) ? (string)$borrador['cliente']['NIF_CLI'] : '';
$candidatos = [];
$errores = [];

function cliente_pendiente(array $borrador, string $codigo, string $nif): never
{
    $borrador['cliente_pendiente'] = ['codigo' => $codigo, 'nif' => $nif];
    borrador_guardar($borrador);
    redirigir('cliente_datos');
}

if (es_post()) {
    comprobar_csrf();
    $codigo = campo('codigo');
    $nif = strtoupper(campo('nif'));
    if ($codigo !== '') {
        $elegido = cliente_por_codigo($pdo, $codigo);
        if ($elegido === null) {
            $errores[] = t('El cliente elegido ya no existe.');
        } else {
            cliente_pendiente($borrador, $codigo, (string)$elegido['NIF_CLI']);
        }
    } elseif ($nif === '') {
        $errores[] = t('Escribe el DNI o NIF del cliente.');
    } else {
        $candidatos = clientes_por_nif($pdo, $nif);
        if (count($candidatos) === 1) {
            cliente_pendiente($borrador, (string)$candidatos[0]['CODIGO_CLI_CLI'], $nif);
        }
        if ($candidatos === []) {
            aviso('aviso', t('No hay ningún cliente con NIF {nif}: rellena sus datos para darlo de alta.', ['nif' => $nif]));
            cliente_pendiente($borrador, '', $nif);
        }
    }
}

$empresa = $borrador['empresa'];
ob_start();
?>
<p class="nota"><?= t('Factura <strong>{serie}</strong> del {fecha} · Emisor <strong>{empresa}</strong>', [
    'serie' => h((string)$borrador['serie']),
    'fecha' => h(fecha_es((string)$borrador['fecha'])),
    'empresa' => h((string)$empresa['RAZON_SOCIAL_EMP']),
]) ?></p>
<form method="post" action="<?= h(url('cliente')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <?= campo_texto('nif', t('DNI / NIF del cliente'), $nif, [
      'autocapitalize' => 'characters',
      'autocorrect' => 'off',
      'spellcheck' => 'false',
      'required' => 'required',
      'autofocus' => 'autofocus',
      'maxlength' => '50',
      'enterkeyhint' => 'go',
  ]) ?>
  <button type="submit" class="boton principal"><?= h(t('Buscar y continuar')) ?></button>
  <?php if ($candidatos !== []): ?>
  <h2><?= h(t('Hay varios clientes con ese NIF')) ?></h2>
  <div class="lista">
    <?php foreach ($candidatos as $candidato): ?>
    <button type="submit" name="codigo" value="<?= h((string)$candidato['CODIGO_CLI_CLI']) ?>" class="elemento">
      <strong><?= h((string)$candidato['RAZON_SOCIAL_CLI']) ?></strong>
      <small><?= h(t('Código {codigo} · {poblacion}', ['codigo' => (string)$candidato['CODIGO_CLI_CLI'], 'poblacion' => (string)$candidato['POBLACION_CLI']])) ?></small>
    </button>
    <?php endforeach; ?>
  </div>
  <?php endif; ?>
</form>
<p class="pie-enlaces"><a href="<?= h(url('cabecera')) ?>"><?= h(t('‹ Volver a fecha y serie')) ?></a></p>
<?php
pagina(t('Cliente'), (string)ob_get_clean(), ['paso' => 'cliente', 'errores' => $errores]);
