<?php
declare(strict_types=1);

/*
 * Anulación del registro Verifactu de una factura aceptada. Los textos
 * legales de esta pantalla solo existen en castellano y catalán (t_legal).
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$serie = trim((string)(es_post() ? campo('serie') : ($_GET['serie'] ?? '')));
$numero = trim((string)(es_post() ? campo('numero') : ($_GET['numero'] ?? '')));
$factura = factura_leer($pdo, $serie, $numero);
if ($factura === null || ($factura['FASE_FAC'] ?? '') !== FASE_FACTURA_VERIFACTU_OK) {
    aviso('error', t('Solo se puede cancelar un alta aceptada por VeriFactu.'));
    redirigir('facturas');
}
$codigo = (string)$factura['CODIGO_EMP_FAC'];
$empresa = empresa_por_codigo($pdo, $codigo);
$errores = [];
$motivo = es_post() ? trim(campo('motivo')) : '';
if (es_post()) {
    comprobar_csrf();
    try {
        $certificado = certificado_exigir($codigo, (string)$factura['RAZON_SOCIAL_EMPRESA_FAC']);
        factura_encolar_anulacion($pdo, $usuario, $serie, $numero, $motivo);
        $fila = verifactu_anulacion_cola($pdo, $serie, $numero);
        $resumen = ['procesadas'=>0, 'enviadas'=>0, 'errores'=>0, 'aplazadas'=>0,
            'sin_certificado'=>0, 'mensajes'=>[]];
        verifactu_cola_procesar_fila($pdo, $usuario, $fila, $certificado, $resumen);
        $actual = factura_leer($pdo, $serie, $numero);
        $aceptada = ($actual['FASE_FAC'] ?? '') === FASE_FACTURA_VERIFACTU_ANULADA;
        aviso($aceptada ? 'ok' : 'aviso', $aceptada
            ? t('La AEAT ha aceptado la anulación. Se conserva la factura y su alta original.')
            : t('La anulación está registrada en la cola, pero aún no está aceptada. Consulta el panel VeriFactu.'));
        redirigir('facturas');
    } catch (Throwable $e) {
        $errores[] = $e->getMessage();
    }
}
$permitir = true;
try {
    verifactu_validar_destino_anulacion($pdo, $usuario, $serie, $numero);
    certificado_exigir($codigo, (string)$factura['RAZON_SOCIAL_EMPRESA_FAC']);
    if (verifactu_anulacion_cola($pdo, $serie, $numero) !== null) {
        throw new RuntimeException(t('La anulación ya está en la cola. Consulta el panel VeriFactu.'));
    }
} catch (Throwable $e) {
    $permitir = false;
    $errores[] = $e->getMessage();
}
ob_start();
?>
<p><strong><?= h(numero_documento_formateado($empresa, $serie, $numero)) ?></strong>
 · <?= h(fecha_es((string)$factura['FECHA_FAC'])) ?></p>
<p><?= h(t('Emisor: {nombre}', ['nombre' => (string)$factura['RAZON_SOCIAL_EMPRESA_FAC']])) ?><br>
<?= h(t('Cliente: {nombre}', ['nombre' => (string)$factura['RAZON_SOCIAL_CLIENTE_FAC']])) ?></p>
<p><?= t('Entorno seleccionado: <strong>{modo}</strong>.', ['modo' => h(verifactu_modo_web($pdo, $usuario)['modo'])]) ?></p>
<div class="nota" lang="<?= idioma_actual() === 'ca' ? 'ca' : 'es' ?>">
<p><strong><?= h(t_legal('Cuándo corresponde anular')) ?></strong></p>
<p><?= h(t_legal('La anulación del registro no borra la factura ni permite reutilizar su número. Se conserva el alta original y se genera un registro de anulación vinculado a ella, identificando la factura anulada (artículo 11 del Reglamento aprobado por el RD 1007/2023).')) ?></p>
<p><?= h(t_legal('No utilices esta opción para sustituir una factura rectificativa cuando sea obligatoria. Los errores en los requisitos de la factura, las cuotas repercutidas incorrectas y los supuestos de modificación de la base imponible previstos en la normativa del IVA requieren rectificación en los términos del artículo 15 del RD 1619/2012.')) ?></p>
<p><?= h(t_legal('Este botón solicita a la AEAT la anulación del registro de facturación. Solo se mostrará como anulada cuando la AEAT acepte la solicitud.')) ?></p>
<p><?= h(t_legal('Fuentes:')) ?>
<a href="https://www.boe.es/buscar/act.php?id=BOE-A-2023-24840" target="_blank" rel="noopener"><?= h(t_legal('RD 1007/2023, artículo 11')) ?></a> ·
<a href="https://www.boe.es/buscar/act.php?id=BOE-A-2012-14696#a15" target="_blank" rel="noopener"><?= h(t_legal('RD 1619/2012, artículo 15')) ?></a> ·
<a href="https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/preguntas-frecuentes/registros-facturacion-anulacion.html" target="_blank" rel="noopener"><?= h(t_legal('Criterio de la AEAT sobre anulación y conservación')) ?></a>.</p>
</div>
<?php if ($permitir): ?>
<form method="post" action="<?= h(url('factura_anular_verifactu')) ?>">
<?= campo_csrf() ?>
<input type="hidden" name="serie" value="<?= h($serie) ?>">
<input type="hidden" name="numero" value="<?= h($numero) ?>">
<label for="motivo"><?= h(t('Motivo de anulación')) ?></label>
<textarea id="motivo" name="motivo" required maxlength="500"><?= h($motivo) ?></textarea>
<button class="boton peligro" type="submit"><?= h(t('Confirmar anulación en la AEAT')) ?></button>
</form>
<?php endif; ?>
<?php if (certificado_disponible($codigo) === null && $empresa !== null): ?>
<?= html_formulario_certificado([$empresa], $codigo, 'factura_anular_verifactu', ['serie'=>$serie,'numero'=>$numero]) ?>
<?php endif; ?>
<p><a href="<?= h(url('verifactu')) ?>"><?= h(t('Ver cola y log VeriFactu')) ?></a></p>
<p><a href="<?= h(url('facturas')) ?>"><?= h(t('Volver al histórico')) ?></a></p>
<?php
pagina(t('Cancelar Verifactu'), (string)ob_get_clean(), ['errores'=>array_unique($errores)]);
