<?php
declare(strict_types=1);

/*
 * Cambio del idioma de las pantallas desde el selector del pie de página.
 * Solo por POST con CSRF; guarda privado/idioma.json (no los parámetros de
 * la aplicación) y vuelve a la pantalla de origen. Está disponible también
 * antes de entrar, para la pantalla de acceso.
 */

/* Páginas que solo responden a POST: al volver a ellas por GET redirigirían solas. */
const PAGINAS_SIN_VUELTA = ['idioma', 'salir', 'crear', 'certificado', 'verifactu_modo', 'factura_editar', 'pdf'];

$volver = campo('volver');
if (!in_array($volver, PAGINAS, true) || in_array($volver, PAGINAS_SIN_VUELTA, true)) {
    $volver = usuario_actual() === null ? 'login' : 'menu';
}
parse_str(campo('volver_parametros'), $parametrosVolver);
$parametrosVolver = array_filter((array)$parametrosVolver, 'is_string');

if (es_post()) {
    comprobar_csrf();
    try {
        $web = idioma_normalizar(campo('web'), IDIOMAS_WEB);
        if ($web === null) {
            throw new RuntimeException(t('Idioma no válido.'));
        }
        idioma_guardar($web);
    } catch (Throwable $error) {
        aviso('error', $error->getMessage());
    }
}
redirigir($volver, $parametrosVolver);
