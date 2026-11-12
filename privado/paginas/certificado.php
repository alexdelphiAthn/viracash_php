<?php
declare(strict_types=1);

/*
 * Certificado de la empresa: cargarlo (para la sesión o guardándolo en el
 * servidor), borrarlo del servidor o quitarlo de la sesión. Solo por POST;
 * vuelve a la página indicada en "volver" (menú por defecto). Los textos
 * del log Verifactu se anotan siempre en castellano.
 */

$usuario = exigir_usuario();
if (!es_post()) {
    redirigir('menu');
}
comprobar_csrf();
$pdo = bbdd();
$volver = campo('volver', 'menu');
if (!in_array($volver, PAGINAS, true)) {
    $volver = 'menu';
}
parse_str(campo('volver_parametros'), $parametrosVolver);
$parametrosVolver = array_filter((array)$parametrosVolver, 'is_string');
$empresa = campo('empresa');
$nombreEmpresa = (string)(empresa_por_codigo($pdo, $empresa)['RAZON_SOCIAL_EMP'] ?? $empresa);

try {
    switch (campo('accion')) {
        case 'subir':
            if (empresa_por_codigo($pdo, $empresa) === null) {
                throw new RuntimeException(t('Elige la empresa del certificado.'));
            }
            $enServidor = campo('destino') === 'servidor';
            $datos = certificado_instalar($pdo, $usuario, $empresa, $_FILES['certificado'] ?? null,
                (string)($_POST['contrasena_certificado'] ?? ''), $enServidor);
            $valores = [
                'titular' => $datos['titular'], 'tipo' => t($datos['tipo']), 'hasta' => fecha_es($datos['hasta']),
                'empresa' => $nombreEmpresa,
            ];
            aviso('ok', $enServidor
                ? t('Certificado de {titular} ({tipo}, válido hasta {hasta}) guardado en el servidor para la empresa {empresa}.', $valores)
                : t('Certificado de {titular} ({tipo}, válido hasta {hasta}) cargado para esta sesión para la empresa {empresa}.', $valores));
            if (!$datos['vigente']) {
                aviso('aviso', t('El certificado no está vigente: la AEAT rechazará los envíos.'));
            }
            $detalle = registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_CAMBIO_CONFIG,
                'Cambio de configuración Verifactu',
                'Certificado ' . $datos['serie'] . ' de ' . $datos['titular'] . ' ' .
                ($enServidor ? 'guardado en el servidor' : 'cargado en sesión') . ' desde la facturación web (empresa ' . $empresa . ')');
            if ($detalle !== null) {
                aviso('aviso', t('No se pudo anotar el cambio en el log Verifactu: {detalle}', ['detalle' => $detalle]));
            }
            break;
        case 'borrar_servidor':
            $habia = certificado_borrar_servidor($empresa);
            aviso($habia ? 'ok' : 'aviso', $habia
                ? t('Certificado de la empresa {empresa} borrado del servidor.', ['empresa' => $nombreEmpresa])
                : t('No había certificado guardado en el servidor.'));
            registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_CAMBIO_CONFIG,
                'Cambio de configuración Verifactu', 'Certificado borrado del servidor desde la facturación web (empresa ' . $empresa . ')');
            break;
        case 'quitar_sesion':
            aviso(certificado_quitar_sesion() ? 'ok' : 'aviso', t('Certificado retirado de la sesión.'));
            break;
        default:
            throw new RuntimeException(t('Acción no válida.'));
    }
} catch (Throwable $error) {
    aviso('error', $error->getMessage());
}
redirigir($volver, $parametrosVolver);
