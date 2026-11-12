<?php
declare(strict_types=1);

/*
 * Panel Verifactu: modo, cola de envíos (fza_verifactu_cola) y registro de
 * eventos (fza_verifactu_eventos), las mismas tablas que el programa, con el
 * botón para procesar la cola (reintentos y facturas pendientes).
 */

$usuario = exigir_usuario();
$pdo = bbdd();

if (es_post()) {
    comprobar_csrf();
    if (campo('accion') === 'procesar') {
        try {
            $resumen = verifactu_cola_procesar($pdo, $usuario);
            aviso('ok', t('Cola procesada: {procesadas} fila(s), {enviadas} enviada(s), {errores} con error, {aplazadas} aplazada(s).', [
                'procesadas' => $resumen['procesadas'], 'enviadas' => $resumen['enviadas'],
                'errores' => $resumen['errores'], 'aplazadas' => $resumen['aplazadas'],
            ]));
            verifactu_cola_avisar($resumen);
        } catch (Throwable $error) {
            aviso('error', $error->getMessage());
        }
    }
    redirigir('verifactu');
}

$modo = verifactu_modo_web($pdo, $usuario);
$resumen = verifactu_cola_resumen($pdo);
$cola = verifactu_cola_listar($pdo, 30);
$eventos = eventos_verifactu_ultimos($pdo, 20);
$empresas = empresas_listar($pdo);
$empresaInicial = empresa_inicial($pdo, $usuario);
$codigoEmpresa = (string)($empresaInicial['CODIGO_EMP_EMP'] ?? ($empresas[0]['CODIGO_EMP_EMP'] ?? ''));
$certificado = $codigoEmpresa !== '' ? certificado_disponible($codigoEmpresa) : null;
/* El SII también exige el certificado de la empresa. */
$esVerifactu = in_array($modo['configurado'], [VERIFACTU_MODO_VERIFACTU, VERIFACTU_MODO_SII], true);

function estado_cola_clase(string $estado): string
{
    return match (strtoupper($estado)) {
        'ENVIADA' => 'cerrada',
        'ERROR' => 'error',
        'PROCESANDO' => 'pendiente',
        default => 'borrador',
    };
}

ob_start();
?>
<section class="tarjeta">
  <h2><?= h(t('Estado')) ?></h2>
  <dl class="ficha">
    <dt><?= h(t('Modo')) ?></dt><dd><?= html_etiqueta_modo($modo['modo']) ?></dd>
    <dt><?= h(t('Cola')) ?></dt><dd><?= h(t('{pendientes} pendiente(s) · {procesando} procesando · {errores} con error · {enviadas} enviada(s)', [
        'pendientes' => (int)$resumen['PENDIENTE'], 'procesando' => (int)$resumen['PROCESANDO'],
        'errores' => (int)$resumen['ERROR'], 'enviadas' => (int)$resumen['ENVIADA'],
    ])) ?></dd>
    <?php if ($codigoEmpresa !== ''): ?>
    <dt><?= h(t('Certificado')) ?></dt><dd><?= html_estado_certificado($certificado) ?></dd>
    <?php endif; ?>
  </dl>
  <?php if ($esVerifactu): ?>
  <form method="post" action="<?= h(url('verifactu')) ?>" class="formulario">
    <?= campo_csrf() ?>
    <input type="hidden" name="accion" value="procesar">
    <p class="ayuda"><?= h(t('Envía las facturas pendientes y reintenta las que dieron error (cuando toque su reintento).')) ?></p>
    <button type="submit" class="boton secundario"><?= h(t('Procesar la cola ahora')) ?></button>
  </form>
  <?php else: ?>
  <p class="ayuda"><?= h(t('La cola solo se procesa en modo VERIFACTU (PRE o PRO).')) ?></p>
  <?php endif; ?>
</section>
<?php if ($esVerifactu && $certificado === null && $codigoEmpresa !== ''): ?>
<section class="tarjeta">
  <h2><?= h(t('Cargar el certificado')) ?></h2>
  <?= html_formulario_certificado($empresas, $codigoEmpresa, 'verifactu') ?>
</section>
<?php endif; ?>
<section class="tarjeta">
  <h2><?= h(t('Cola de envíos')) ?></h2>
  <?php if ($cola === []): ?>
  <p class="nota"><?= h(t('No hay facturas en la cola.')) ?></p>
  <?php endif; ?>
  <div class="lista">
  <?php foreach ($cola as $fila): ?>
    <div class="factura-fila">
      <div class="factura-datos">
        <strong><?= h((string)$fila['SERIE_FAC_VFCOLA'] . ' ' . (string)$fila['NUMERO_FAC_VFCOLA']) ?></strong>
        <span class="estado <?= estado_cola_clase((string)$fila['ESTADO_VFCOLA']) ?>"><?= h((string)$fila['ESTADO_VFCOLA']) ?> · <?= h((string)$fila['TIPO_OPERACION_VFCOLA']) ?></span>
        <small><?= h(t('Intentos: {n}', ['n' => (int)$fila['CONTADOR_INTENTOS_VFCOLA']])) ?>
          <?php if (!empty($fila['INSTANTE_ENVIO_VFCOLA'])): ?> · <?= h(t('enviada el {fecha}', ['fecha' => fecha_hora_es((string)$fila['INSTANTE_ENVIO_VFCOLA'])])) ?><?php endif; ?>
          <?php if (!empty($fila['INSTANTE_PROXIMO_INTENTO_VFCOLA']) && strtoupper((string)$fila['ESTADO_VFCOLA']) !== 'ENVIADA'): ?> · <?= h(t('próximo intento {fecha}', ['fecha' => fecha_hora_es((string)$fila['INSTANTE_PROXIMO_INTENTO_VFCOLA'])])) ?><?php endif; ?></small>
        <?php if (trim((string)($fila['MENSAJE_ERROR_VFCOLA'] ?? '')) !== ''): ?>
        <small><?= h(mb_substr((string)$fila['MENSAJE_ERROR_VFCOLA'], 0, 300)) ?></small>
        <?php endif; ?>
      </div>
    </div>
  <?php endforeach; ?>
  </div>
</section>
<section class="tarjeta">
  <h2><?= h(t('Registro de eventos')) ?></h2>
  <?php if ($eventos === []): ?>
  <p class="nota"><?= h(t('No hay eventos.')) ?></p>
  <?php endif; ?>
  <div class="lista">
  <?php foreach ($eventos as $evento): ?>
    <div class="factura-fila">
      <div class="factura-datos">
        <strong><?= h(t(evento_verifactu_nombre((int)$evento['TIPO_EVENTO_LOG']))) ?></strong>
        <small><?= h(fecha_hora_es((string)$evento['TIMESTAMP_LOG'])) ?> · <?= h((string)$evento['USUARIO_LOG']) ?> · v<?= h((string)$evento['VERSION_LOG']) ?>
          <?php if (trim((string)($evento['SERIE_FAC_LOG'] ?? '')) !== ''): ?> · <?= h((string)$evento['SERIE_FAC_LOG'] . ' ' . (string)$evento['NUMERO_FAC_LOG']) ?><?php endif; ?></small>
        <small><?= h(mb_substr((string)$evento['DESCRIPCION_LOG'], 0, 300)) ?>
          <?php if (trim((string)($evento['DATOS_ADICIONALES_LOG'] ?? '')) !== ''): ?> — <?= h(mb_substr((string)$evento['DATOS_ADICIONALES_LOG'], 0, 200)) ?><?php endif; ?></small>
      </div>
    </div>
  <?php endforeach; ?>
  </div>
</section>
<p class="pie-enlaces"><a href="<?= h(url('menu')) ?>"><?= h(t('‹ Volver al menú')) ?></a></p>
<?php
pagina('Verifactu', (string)ob_get_clean());
