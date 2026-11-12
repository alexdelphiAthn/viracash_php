<?php
declare(strict_types=1);

/* Pantalla 1: usuario y contraseña contra fza_usuarios. */

if (usuario_actual() !== null) {
    redirigir('menu');
}

$errores = [];
$usuarioTexto = '';
if (es_post()) {
    comprobar_csrf();
    $usuarioTexto = campo('usuario');
    $contrasena = (string)($_POST['contrasena'] ?? '');
    $datos = autenticar(bbdd(), $usuarioTexto, $contrasena);
    if ($datos === null) {
        usleep(400000);
        $errores[] = t('Usuario o contraseña incorrectos.');
    } else {
        abrir_sesion_usuario($datos);
        redirigir('menu');
    }
}

ob_start();
?>
<form method="post" action="<?= h(url('login')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <?= campo_texto('usuario', t('Usuario'), $usuarioTexto, [
      'autocomplete' => 'username',
      'autocapitalize' => 'none',
      'autocorrect' => 'off',
      'spellcheck' => 'false',
      'required' => 'required',
      'autofocus' => 'autofocus',
      'enterkeyhint' => 'next',
  ]) ?>
  <?= campo_texto('contrasena', t('Contraseña'), '', [
      'type' => 'password',
      'autocomplete' => 'current-password',
      'required' => 'required',
      'enterkeyhint' => 'go',
  ]) ?>
  <button type="submit" class="boton principal"><?= h(t('Entrar')) ?></button>
</form>
<?php
pagina(t('Entrar'), (string)ob_get_clean(), ['errores' => $errores]);
