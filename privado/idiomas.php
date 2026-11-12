<?php
declare(strict_types=1);

/*
 * Idiomas de la web: castellano (es), catalán (ca), inglés (en) y chino
 * simplificado (zh) para las pantallas. La factura en PDF y los textos
 * legales van siempre en castellano; solo con la web en catalán se ofrece,
 * además, la factura en catalán.
 *
 * La elección no se guarda en los parámetros de la aplicación sino en un
 * fichero de la propia web (privado/idioma.json), común a todos los usuarios
 * y vigente también en la pantalla de entrada. Los textos del código siguen
 * en castellano: t() los busca en privado/idiomas/<idioma>.php y, si no hay
 * traducción, devuelve el original.
 */

const IDIOMAS_WEB = ['es' => 'Español', 'ca' => 'Català', 'en' => 'English', 'zh' => '中文'];
const IDIOMAS_FACTURA = ['es' => 'Español', 'ca' => 'Català'];
const IDIOMA_RUTA_FICHERO = __DIR__ . '/idioma.json';

/** Código admitido en minúsculas o null si no está entre los idiomas dados. */
function idioma_normalizar(string $codigo, array $admitidos): ?string
{
    $codigo = strtolower(trim($codigo));
    return isset($admitidos[$codigo]) ? $codigo : null;
}

/** Idioma de las pantallas guardado en privado/idioma.json (castellano si no hay fichero). */
function idioma_actual(bool $recargar = false): string
{
    static $idioma = null;
    if ($idioma === null || $recargar) {
        $idioma = 'es';
        if (is_file(IDIOMA_RUTA_FICHERO)) {
            $datos = json_decode((string)file_get_contents(IDIOMA_RUTA_FICHERO), true);
            if (is_array($datos)) {
                $idioma = idioma_normalizar((string)($datos['web'] ?? ''), IDIOMAS_WEB) ?? 'es';
            }
        }
    }
    return $idioma;
}

/** Guarda el idioma de las pantallas (escritura atómica del fichero). */
function idioma_guardar(string $web): void
{
    $json = json_encode(['web' => $web], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR) . "\n";
    $temporal = IDIOMA_RUTA_FICHERO . '.' . bin2hex(random_bytes(4)) . '.tmp';
    if (@file_put_contents($temporal, $json, LOCK_EX) === false || !@rename($temporal, IDIOMA_RUTA_FICHERO)) {
        @unlink($temporal);
        throw new RuntimeException(t('No se ha podido guardar el idioma en el fichero {fichero} de la web.',
            ['fichero' => basename(IDIOMA_RUTA_FICHERO)]));
    }
    idioma_actual(true);
}

/**
 * Idioma de la factura en PDF: castellano siempre, salvo que la web esté en
 * catalán y se pida expresamente el catalán (parámetro idioma=ca del PDF).
 */
function idioma_factura(?string $solicitado = null): string
{
    if (idioma_actual() === 'ca' && $solicitado !== null && idioma_normalizar($solicitado, IDIOMAS_FACTURA) === 'ca') {
        return 'ca';
    }
    return 'es';
}

/** True si, además del PDF en castellano, procede ofrecer el PDF en catalán. */
function idioma_ofrece_factura_catalan(): bool
{
    return idioma_actual() === 'ca';
}

/** Valor del atributo lang de HTML. */
function idioma_html(?string $idioma = null): string
{
    $idioma ??= idioma_actual();
    return $idioma === 'zh' ? 'zh-Hans' : $idioma;
}

/** Diccionario castellano => traducción de un idioma (cargado una vez por petición). */
function &diccionario_idioma(string $idioma): array
{
    static $diccionarios = [];
    if (!isset($diccionarios[$idioma])) {
        $ruta = __DIR__ . '/idiomas/' . $idioma . '.php';
        $diccionario = is_file($ruta) ? require $ruta : [];
        $diccionarios[$idioma] = is_array($diccionario) ? $diccionario : [];
    }
    return $diccionarios[$idioma];
}

/**
 * Traduce un texto escrito en castellano al idioma indicado y sustituye los
 * marcadores {clave} por $valores. Sin traducción devuelve el original. Los
 * valores se insertan tal cual: en HTML, o se escapa el resultado completo
 * con h() o se pasan los valores ya escapados cuando el texto lleva etiquetas.
 */
function tf(string $texto, string $idioma, array $valores = []): string
{
    if ($idioma !== 'es') {
        $diccionario = &diccionario_idioma($idioma);
        $texto = $diccionario[$texto] ?? $texto;
    }
    if ($valores !== []) {
        $sustituciones = [];
        foreach ($valores as $clave => $valor) {
            $sustituciones['{' . $clave . '}'] = (string)$valor;
        }
        $texto = strtr($texto, $sustituciones);
    }
    return $texto;
}

/** Traducción al idioma de las pantallas. */
function t(string $texto, array $valores = []): string
{
    return tf($texto, idioma_actual(), $valores);
}

/** Textos legales: solo castellano o catalán (con la web en inglés o chino se muestran en castellano). */
function t_legal(string $texto, array $valores = []): string
{
    return tf($texto, idioma_actual() === 'ca' ? 'ca' : 'es', $valores);
}

/** Nombre de un idioma para mostrarlo en la interfaz. */
function idioma_nombre(string $codigo): string
{
    return IDIOMAS_WEB[$codigo] ?? $codigo;
}

/**
 * Selector del pie de página. Cada botón envía el formulario (POST con CSRF)
 * a la página "idioma", que guarda el fichero y vuelve a la pantalla actual.
 */
function html_selector_idioma(): string
{
    $actual = idioma_actual();
    $volver = (string)($_GET['p'] ?? '');
    $parametros = [];
    foreach ($_GET as $clave => $valor) {
        if (is_string($valor) && $clave !== 'p') {
            $parametros[(string)$clave] = $valor;
        }
    }
    $html = '<form method="post" action="' . h(url('idioma')) . '" class="idiomas" aria-label="' . h(t('Idioma')) . '">' .
        campo_csrf() .
        '<input type="hidden" name="volver" value="' . h($volver) . '">' .
        '<input type="hidden" name="volver_parametros" value="' . h(http_build_query($parametros)) . '">' .
        '<span class="idiomas-grupo"><span class="idiomas-titulo">' . h(t('Idioma')) . '</span>';
    foreach (IDIOMAS_WEB as $codigo => $nombre) {
        $activo = $codigo === $actual;
        $html .= '<button type="submit" name="web" value="' . $codigo . '" lang="' . h(idioma_html($codigo)) . '"' .
            ' class="idioma' . ($activo ? ' activo' : '') . '"' . ($activo ? ' aria-current="true"' : '') . '>' .
            h($nombre) . '</button>';
    }
    return $html . '</span></form>';
}
