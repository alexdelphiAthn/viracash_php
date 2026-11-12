<?php
declare(strict_types=1);

/*
 * Menú principal tras entrar: nueva factura, facturas existentes, factura en
 * curso y el panel Verifactu (modo SIN / PRE / PRO, certificado de la
 * empresa, instalación SIF, cola y accesos a parámetros y registro).
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = borrador();
$edicion = editando($borrador);
$enCurso = is_array($borrador['empresa']);
if ($borrador['lineas'] !== []) {
    $pasoEnCurso = 'resumen';
} elseif (is_array($borrador['cliente']) || (es_simplificada($borrador) && $borrador['serie'] !== '')) {
    $pasoEnCurso = 'lineas';
} elseif ($borrador['serie'] !== '') {
    $pasoEnCurso = 'cliente';
} else {
    $pasoEnCurso = 'cabecera';
}

/* Verifactu: estado para la empresa del usuario (o la única activa). */
$modo = verifactu_modo_web($pdo, $usuario);
$empresas = empresas_listar($pdo);
$empresaInicial = empresa_inicial($pdo, $usuario);
$codigoEmpresa = (string)($empresaInicial['CODIGO_EMP_EMP'] ?? ($empresas[0]['CODIGO_EMP_EMP'] ?? ''));
$nombreEmpresa = (string)($empresaInicial['RAZON_SOCIAL_EMP'] ?? ($empresas[0]['RAZON_SOCIAL_EMP'] ?? ''));
$certificado = $codigoEmpresa !== '' ? certificado_disponible($codigoEmpresa) : null;
$hayCertificado = certificados_empresas_disponibles($pdo) !== [];
$sif = $codigoEmpresa !== '' ? sif_estado_empresa($pdo, $codigoEmpresa) : null;
$cola = verifactu_cola_resumen($pdo);
$esAdmin = !empty($usuario['admin']);

ob_start();
?>
<p class="nota"><?= t('Hola, <strong>{usuario}</strong>. ¿Qué quieres hacer?', ['usuario' => h((string)$usuario['usuario'])]) ?></p>
<div class="menu">
  <a class="boton principal" href="<?= h(url('empresa', ['nueva' => 1])) ?>"><?= h(t('Crear nueva factura')) ?></a>
  <a class="boton secundario" href="<?= h(url('empresa', ['nueva' => 1, 'tipo' => 'simplificada'])) ?>"><?= h(t('Crear factura simplificada (ticket)')) ?></a>
  <a class="boton secundario" href="<?= h(url('facturas')) ?>"><?= h(t('Ver facturas existentes')) ?></a>
  <a class="boton secundario" href="<?= h(url('resumen_facturas')) ?>"><?= h(t('Resumen de facturas entre fechas (Excel)')) ?></a>
  <?php if ($enCurso): ?>
  <a class="boton secundario" href="<?= h(url($pasoEnCurso)) ?>">
    <?= h($edicion !== null
        ? t('Seguir modificando la factura {numero}', ['numero' => (string)$edicion['numero_formateado']])
        : t('Continuar la factura en curso')) ?>
  </a>
  <?php endif; ?>
</div>
<p class="ayuda"><?= h(t('La factura simplificada (ticket) no lleva cliente: se imprime en PDF con el formato del ticket de caja, en papel de 80 mm. El pie del ticket y el empleado que atiende se configuran en "Parámetros e instalación SIF".')) ?></p>
<p class="ayuda"><?= h(t('En "facturas existentes" puedes reimprimir el PDF de cualquier factura, emitir las que siguen en borrador y modificar o borrar las que aún no se han emitido.')) ?></p>

<section class="tarjeta verifactu">
  <h2>Verifactu</h2>
  <p><a class="boton secundario" target="_blank" rel="noopener" href="<?= h(url('declaracion', ['empresa'=>$codigoEmpresa])) ?>"><?= h(t('Declaración responsable del SIF')) ?></a></p>
  <dl class="ficha">
    <dt><?= h(t('Modo')) ?></dt><dd><?= html_etiqueta_modo($modo['modo']) ?></dd>
    <?php if ($codigoEmpresa !== ''): ?>
    <dt><?= h(t('Empresa')) ?></dt><dd><?= h($nombreEmpresa) ?> (<?= h($codigoEmpresa) ?>)</dd>
    <dt><?= h(t('Certificado')) ?></dt><dd><?= html_estado_certificado($certificado) ?></dd>
    <dt><?= h(t('Instalación SIF')) ?></dt><dd><?= $sif === null ? '—' : h(($sif['numero'] !== '' ? $sif['numero'] . ' · ' : '') . $sif['mensaje']) ?></dd>
    <?php endif; ?>
    <dt><?= h(t('Cola')) ?></dt><dd><?= h(t('{pendientes} pendiente(s) · {errores} con error · {enviadas} enviada(s)', [
        'pendientes' => (int)$cola['PENDIENTE'], 'errores' => (int)$cola['ERROR'], 'enviadas' => (int)$cola['ENVIADA'],
    ])) ?></dd>
  </dl>
  <p class="pie-enlaces"><a href="<?= h(url('verifactu')) ?>"><?= h(t('Cola y registro de eventos')) ?></a>
    <?php if ($esAdmin): ?> · <a href="<?= h(url('parametros')) ?>"><?= h(t('Parámetros e instalación SIF')) ?></a><?php endif; ?></p>
</section>

<?php if ($esAdmin): ?>
<section class="tarjeta">
  <h2><?= h(t('Cambiar de modo')) ?></h2>
  <?= html_formulario_modo($modo['modo'], $hayCertificado, $modo['entorno']) ?>
</section>
<?php endif; ?>

<?php if ($codigoEmpresa !== ''): ?>
<section class="tarjeta">
  <h2><?= h(t('Certificado de la empresa')) ?></h2>
  <?php if ($certificado !== null): ?>
  <p class="ayuda"><?= html_estado_certificado($certificado) ?></p>
  <?= html_botones_certificado($certificado, $codigoEmpresa) ?>
  <p class="ayuda"><?= h(t('Para cambiarlo, carga otro fichero:')) ?></p>
  <?php else: ?>
  <p class="ayuda"><?= h(t('Sin certificado no se puede pasar a PRE ni a PRO ni enviar facturas a la AEAT. Puedes cargarlo solo para esta sesión (se descarta al salir) o dejarlo guardado en el servidor, en una carpeta privada.')) ?></p>
  <?php endif; ?>
  <?= html_formulario_certificado($empresas, $codigoEmpresa, 'menu') ?>
</section>
<?php endif; ?>
<?php
pagina(t('Menú'), (string)ob_get_clean());
