<?php
declare(strict_types=1);

/*
 * Fragmentos HTML compartidos por las pantallas de Verifactu: estado del
 * certificado, formulario de carga del certificado y etiqueta de modo.
 */

/** Etiqueta del modo con su color. */
function html_etiqueta_modo(string $modo): string
{
    $clase = match ($modo) {
        'PRE' => 'modo-pre',
        'PRO' => 'modo-pro',
        'NO_VERIFACTU' => 'modo-otro',
        'SII' => 'modo-sii',
        default => 'modo-sin',
    };
    return '<span class="estado ' . $clase . '">' . h(verifactu_modo_descripcion($modo)) . '</span>';
}

/** Texto de estado del certificado de una empresa. */
function html_estado_certificado(?array $certificado): string
{
    if ($certificado === null) {
        return '<span class="estado borrador">' . h(t('No cargado')) . '</span>';
    }
    $datos = $certificado['datos'];
    $origen = $certificado['origen'] === 'sesion' ? t('Cargado solo para esta sesión') : t('Guardado en el servidor');
    $vigencia = $datos['vigente']
        ? t('válido hasta {fecha}', ['fecha' => fecha_es($datos['hasta'])])
        : t('NO VIGENTE ({desde} a {hasta})', ['desde' => fecha_es($datos['desde']), 'hasta' => fecha_es($datos['hasta'])]);
    return '<span class="estado ' . ($datos['vigente'] ? 'cerrada' : 'error') . '">' . h($origen) . '</span> ' .
        h($datos['titular']) . ' <small>(' . h(t($datos['tipo'])) . ', ' . h($vigencia) . ')</small>';
}

/**
 * Formulario de carga del certificado (.pfx + contraseña + destino). Si hay
 * varias empresas activas, selector de empresa. $volver: página a la que
 * regresar tras cargarlo (con sus parámetros).
 */
function html_formulario_certificado(array $empresas, string $empresaSeleccionada, string $volver = 'menu', array $parametrosVolver = []): string
{
    $html = '<form method="post" action="' . h(url('certificado')) . '" enctype="multipart/form-data" class="formulario">' .
        campo_csrf() .
        '<input type="hidden" name="accion" value="subir">' .
        '<input type="hidden" name="volver" value="' . h($volver) . '">' .
        '<input type="hidden" name="volver_parametros" value="' . h(http_build_query($parametrosVolver)) . '">';
    if (count($empresas) > 1) {
        $opciones = [];
        foreach ($empresas as $empresa) {
            $opciones[(string)$empresa['CODIGO_EMP_EMP']] = (string)$empresa['RAZON_SOCIAL_EMP'] . ' (' . (string)$empresa['CODIGO_EMP_EMP'] . ')';
        }
        $html .= '<label class="campo"><span>' . h(t('Empresa')) . '</span><select name="empresa">' .
            opciones_select($opciones, $empresaSeleccionada) . '</select></label>';
    } else {
        $html .= '<input type="hidden" name="empresa" value="' . h($empresaSeleccionada) . '">';
    }
    $html .= '<label class="campo"><span>' . h(t('Fichero del certificado (.pfx / .p12)')) . '</span>' .
        '<input type="file" name="certificado" accept=".pfx,.p12,application/x-pkcs12" required></label>' .
        campo_texto('contrasena_certificado', t('Contraseña del certificado'), '', [
            'type' => 'password', 'autocomplete' => 'off', 'required' => 'required',
        ]) .
        '<div class="opciones-radio">' .
        '<label class="casilla"><input type="radio" name="destino" value="sesion" checked>' .
        '<span>' . h(t('Solo para esta sesión')) . '<small>' . h(t('Se descarta al salir; habrá que volver a cargarlo la próxima vez.')) . '</small></span></label>' .
        '<label class="casilla"><input type="radio" name="destino" value="servidor">' .
        '<span>' . h(t('Guardar en el servidor')) . '<small>' . h(t('En la carpeta privada de la web, con la clave cifrada. Se puede borrar cuando quieras.')) . '</small></span></label>' .
        '</div>' .
        '<button type="submit" class="boton secundario">' . h(t('Cargar certificado')) . '</button>' .
        '</form>';
    return $html;
}

/** Botones para borrar el certificado del servidor o quitarlo de la sesión. */
function html_botones_certificado(array $certificado, string $empresa): string
{
    $accion = $certificado['origen'] === 'sesion' ? 'quitar_sesion' : 'borrar_servidor';
    $texto = $certificado['origen'] === 'sesion' ? t('Quitar el certificado de la sesión') : t('Borrar el certificado del servidor');
    return '<form method="post" action="' . h(url('certificado')) . '" class="formulario-linea">' .
        campo_csrf() .
        '<input type="hidden" name="accion" value="' . h($accion) . '">' .
        '<input type="hidden" name="empresa" value="' . h($empresa) . '">' .
        '<button type="submit" class="boton-mini peligro">' . h($texto) . '</button></form>';
}

/**
 * Formulario de cambio de modo (SIN / PRE / PRO / SII). $entorno es el
 * entorno configurado: marca de inicio la casilla «SII en pruebas».
 */
function html_formulario_modo(string $modoActual, bool $hayCertificado, string $entorno = 'PRE'): string
{
    $deshabilitado = $hayCertificado ? '' : ' disabled';
    $html = '<form method="post" action="' . h(url('verifactu_modo')) . '" class="formulario">' . campo_csrf() .
        '<div class="opciones-radio">' .
        '<label class="casilla"><input type="radio" name="modo" value="SIN"' . ($modoActual === 'SIN' ? ' checked' : '') . '>' .
        '<span>' . h(t('SIN VERIFACTU')) . '<small>' . h(t('Las facturas se emiten sin registro fiscal ni QR.')) . '</small></span></label>' .
        '<label class="casilla' . ($hayCertificado ? '' : ' deshabilitada') . '"><input type="radio" name="modo" value="PRE"' .
        ($modoActual === 'PRE' ? ' checked' : '') . $deshabilitado . '>' .
        '<span>' . h(t('PRE · pruebas de la AEAT')) . '<small>' . h(t('Envío al entorno de preproducción (prewww1.aeat.es).')) . '</small></span></label>' .
        '<label class="casilla' . ($hayCertificado ? '' : ' deshabilitada') . '"><input type="radio" name="modo" value="PRO"' .
        ($modoActual === 'PRO' ? ' checked' : '') . $deshabilitado . '>' .
        '<span>' . h(t('PRO · producción')) . '<small>' . h(t('Envío real a la sede electrónica de la AEAT.')) . '</small></span></label>' .
        '<label class="casilla' . ($hayCertificado ? '' : ' deshabilitada') . '"><input type="radio" name="modo" value="SII"' .
        ($modoActual === 'SII' ? ' checked' : '') . $deshabilitado . '>' .
        '<span>' . h(t('SII · Suministro Inmediato de Información')) . '<small>' .
        h(t('Libro de facturas emitidas en la AEAT, sin QR ni leyenda VERI*FACTU. Los envíos los hace ViraCash.')) .
        '</small></span></label>' .
        '<label class="casilla sii-pruebas' . ($hayCertificado ? '' : ' deshabilitada') . '"><input type="checkbox" name="sii_pruebas" value="S"' .
        ($entorno === 'PRE' ? ' checked' : '') . $deshabilitado . '>' .
        '<span>' . h(t('SII en pruebas (preproducción)')) . '</span></label>' .
        '</div>';
    if (!$hayCertificado) {
        $html .= '<p class="ayuda">' . h(t('Para pasar a PRE, PRO o SII carga antes el certificado de la empresa.')) . '</p>';
    }
    $html .= '<button type="submit" class="boton secundario">' . h(t('Cambiar modo')) . '</button></form>';
    return $html;
}

/** Imagen del QR como data URI (PNG) para mostrarla en pantalla. */
function html_imagen_qr(array $matriz, string $alt = 'QR tributario'): string
{
    $png = CodigoQR::png($matriz, 4, 4);
    return '<img class="qr" src="data:image/png;base64,' . base64_encode($png) . '" alt="' . h(t($alt)) . '" width="' .
        (count($matriz) + 8) * 4 . '" height="' . (count($matriz) + 8) * 4 . '">';
}
