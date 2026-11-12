<?php
declare(strict_types=1);

/*
 * Punto de entrada único. El servidor web debe apuntar a este directorio
 * (publico); config.php y privado quedan fuera del alcance del navegador.
 */

require __DIR__ . '/../privado/arranque.php';
require __DIR__ . '/../privado/idiomas.php';
require __DIR__ . '/../privado/autenticacion.php';
require __DIR__ . '/../privado/repositorio.php';
require __DIR__ . '/../privado/facturas_calculo.php';
require __DIR__ . '/../privado/factura_borrador.php';
require __DIR__ . '/../privado/pdf_minimo.php';
require __DIR__ . '/../privado/factura_pdf.php';
require __DIR__ . '/../privado/ticket_pdf.php';
require __DIR__ . '/../privado/qr.php';
require __DIR__ . '/../privado/pkcs12.php';
require __DIR__ . '/../privado/verifactu_parametros.php';
require __DIR__ . '/../privado/verifactu_registro.php';
require __DIR__ . '/../privado/verifactu_certificado.php';
require __DIR__ . '/../privado/verifactu_eventos.php';
require __DIR__ . '/../privado/verifactu_cola.php';
require __DIR__ . '/../privado/verifactu_sif.php';
require __DIR__ . '/../privado/vistas/plantilla.php';
require __DIR__ . '/../privado/vistas/verifactu_vistas.php';

const PAGINAS = [
    'login', 'menu', 'facturas', 'factura_editar', 'factura_borrar',
    'cabecera', 'empresa', 'empresa_datos', 'cliente',
    'cliente_datos', 'lineas', 'resumen', 'crear', 'creada', 'pdf', 'salir',
    'diagnostico', 'factura_anular_verifactu', 'declaracion',
    'factura_emitir', 'verifactu', 'verifactu_modo', 'certificado', 'parametros',
    'idioma', 'resumen_facturas',
];

function mensaje_error(Throwable $error): string
{
    if ($error instanceof PDOException) {
        $detalle = (string)($error->errorInfo[2] ?? $error->getMessage());
        return t('Error de base de datos: {detalle}', ['detalle' => $detalle]);
    }
    return $error->getMessage();
}

try {
    iniciar_sesion();
    $pagina = (string)($_GET['p'] ?? '');
    if (!in_array($pagina, PAGINAS, true)) {
        $pagina = usuario_actual() === null ? 'login' : 'menu';
    }
    require FZA_RUTA_PRIVADA . '/paginas/' . $pagina . '.php';
} catch (Throwable $error) {
    error_log('FacturacionWeb ' . get_class($error) . ': ' . $error->getMessage() .
        ' en ' . $error->getFile() . ':' . $error->getLine());
    $detalle = '';
    if (!empty(configuracion()['depuracion'])) {
        $detalle = '<pre class="detalle">' . h($error->getFile() . ':' . $error->getLine() .
            "\n" . $error->getTraceAsString()) . '</pre>';
    }
    $volver = usuario_actual() === null ? url('login') : url('menu');
    pagina(
        t('No se ha podido continuar'),
        '<p class="ayuda">' . h(t('Nada se ha grabado a medias: revisa el mensaje y vuelve a intentarlo.')) . '</p>' .
        $detalle .
        '<a class="boton principal" href="' . h($volver) . '">' . h(t('Volver')) . '</a>',
        ['errores' => [mensaje_error($error)]]
    );
}
