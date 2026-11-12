<?php
declare(strict_types=1);

/*
 * Plantilla común. Pensada para móvil (iPhone 7, 375 px): una columna,
 * controles grandes y sin JavaScript imprescindible.
 */

function cabeceras_http(): void
{
    header('Content-Type: text/html; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    header('X-Frame-Options: DENY');
    header('Referrer-Policy: no-referrer');
    header(
        "Content-Security-Policy: default-src 'self'; script-src 'self'; " .
        "style-src 'self'; img-src 'self' data:; form-action 'self'; " .
        "frame-ancestors 'none'; base-uri 'none'; object-src 'none'"
    );
}

/**
 * Imprime la página completa y termina.
 * $opciones: 'paso' (clave de PASOS_FACTURA), 'avisos' (lista de textos),
 * 'errores' (lista de textos).
 */
function pagina(string $titulo, string $contenido, array $opciones = []): never
{
    cabeceras_http();
    $config = configuracion();
    $usuario = usuario_actual();
    $tituloApp = (string)($config['titulo'] ?? 'ViraCash');
    $paso = $opciones['paso'] ?? null;
    $mensajes = avisos_pendientes();
    foreach ($opciones['errores'] ?? [] as $error) {
        $mensajes[] = ['tipo' => 'error', 'mensaje' => $error];
    }
    foreach ($opciones['avisos'] ?? [] as $aviso) {
        $mensajes[] = ['tipo' => 'aviso', 'mensaje' => $aviso];
    }
    ?>
<!doctype html>
<html lang="<?= h(idioma_html()) ?>">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <meta name="theme-color" content="#174c3c">
  <meta name="robots" content="noindex, nofollow">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-title" content="<?= h($tituloApp) ?>">
  <meta name="format-detection" content="telephone=no">
  <title><?= h($titulo) ?> · <?= h($tituloApp) ?></title>
  <link rel="stylesheet" href="estilos.css?v=<?= h(substr(hash_file('sha256', __DIR__ . '/../../publico/estilos.css'), 0, 12)) ?>">
</head>
<body>
<header class="cabecera">
  <div class="marca"><?= h($tituloApp) ?><span class="marca-sub"><?= h(t('Facturación')) ?></span></div>
  <?php if ($usuario !== null): ?>
  <form method="post" action="<?= h(url('salir')) ?>" class="salir">
    <?= campo_csrf() ?>
    <a class="boton-enlace" href="<?= h(url('menu')) ?>"><?= h(t('Menú')) ?></a>
    <span class="usuario"><?= h((string)$usuario['usuario']) ?></span>
    <button type="submit" class="boton-enlace"><?= h(t('Salir')) ?></button>
  </form>
  <?php endif; ?>
</header>
<?php $pasos = pasos_factura(borrador()); if ($paso !== null && isset($pasos[$paso])): ?>
<nav class="pasos" aria-label="<?= h(t('Progreso')) ?>">
  <?php foreach ($pasos as $clave => [$numero, $nombre]): ?>
  <span class="paso<?= $clave === $paso ? ' actual' : '' ?><?= $numero < $pasos[$paso][0] ? ' hecho' : '' ?>"
        title="<?= h(t($nombre)) ?>"><?= $numero ?></span>
  <?php endforeach; ?>
  <span class="paso-texto"><?= h(t('Paso {n} de {total} · {nombre}', [
      'n' => $pasos[$paso][0], 'total' => count($pasos), 'nombre' => t($pasos[$paso][1]),
  ])) ?></span>
</nav>
<?php $edicionActual = editando(borrador()); if ($edicionActual !== null): ?>
<p class="banda-edicion"><?= t('Modificando la factura <strong>{numero}</strong>', ['numero' => h((string)$edicionActual['numero_formateado'])]) ?></p>
<?php endif; ?>
<?php if (es_simplificada(borrador())): ?>
<p class="banda-edicion"><?= h(t('Factura simplificada (ticket): sin datos del cliente')) ?></p>
<?php endif; ?>
<?php endif; ?>
<main class="contenido">
  <h1><?= h($titulo) ?></h1>
  <?php foreach ($mensajes as $mensaje): ?>
  <div class="mensaje <?= h($mensaje['tipo']) ?>" role="alert"><?= h($mensaje['mensaje']) ?></div>
  <?php endforeach; ?>
  <?= $contenido ?>
</main>
<footer class="pie"><?= html_selector_idioma() ?></footer>
<script src="app.js"></script>
</body>
</html>
<?php
    exit;
}

/** Opciones <option> de un select. $opciones es [valor => texto]. */
function opciones_select(array $opciones, string $seleccionado): string
{
    $html = '';
    foreach ($opciones as $valor => $texto) {
        $valor = (string)$valor;
        $html .= '<option value="' . h($valor) . '"' .
            ($valor === $seleccionado ? ' selected' : '') . '>' .
            h($texto) . '</option>';
    }
    return $html;
}

function casilla(string $nombre, string $etiqueta, string $valor, string $ayuda = ''): string
{
    return '<label class="casilla"><input type="checkbox" name="' . h($nombre) .
        '" value="S"' . (es_si($valor) ? ' checked' : '') . '><span>' . h($etiqueta) .
        ($ayuda !== '' ? '<small>' . h($ayuda) . '</small>' : '') . '</span></label>';
}

function campo_texto(
    string $nombre,
    string $etiqueta,
    string $valor,
    array $atributos = []
): string {
    $tipo = (string)($atributos['type'] ?? 'text');
    unset($atributos['type']);
    $extra = '';
    foreach ($atributos as $clave => $atributo) {
        $extra .= ' ' . h((string)$clave) . '="' . h((string)$atributo) . '"';
    }
    return '<label class="campo"><span>' . h($etiqueta) . '</span>' .
        '<input type="' . h($tipo) . '" name="' . h($nombre) .
        '" value="' . h($valor) . '"' . $extra . '></label>';
}
