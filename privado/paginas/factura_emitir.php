<?php
declare(strict_types=1);

/*
 * Emisión (consolidación) de un borrador según el modo Verifactu de la web:
 * SIN → fase SIN_VERIFACTU; PRE/PRO → cola Verifactu y envío a la AEAT con
 * el certificado de la empresa, que puede cargarse aquí mismo si no lo hay.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$serie = trim((string)(es_post() ? campo('serie') : ($_GET['serie'] ?? '')));
$numero = trim((string)(es_post() ? campo('numero') : ($_GET['numero'] ?? '')));
$factura = $serie !== '' && $numero !== '' ? factura_leer($pdo, $serie, $numero) : null;
if ($factura === null) {
    aviso('error', t('No existe la factura {serie} {numero}.', ['serie' => $serie, 'numero' => $numero]));
    redirigir('facturas');
}
if (!factura_editable($factura)) {
    aviso('error', t('La factura {serie} {numero} ya está emitida ({fase}).',
        ['serie' => $serie, 'numero' => $numero, 'fase' => fase_factura_texto($factura)]));
    redirigir('facturas');
}
$empresa = empresa_por_codigo($pdo, (string)$factura['CODIGO_EMP_FAC']);
$codigoEmpresa = (string)$factura['CODIGO_EMP_FAC'];
$numeroFormateado = numero_documento_formateado($empresa, $serie, $numero);
$modo = verifactu_modo_web($pdo, $usuario);
/* El SII también exige el certificado de la empresa. */
$esVerifactu = in_array($modo['configurado'], [VERIFACTU_MODO_VERIFACTU, VERIFACTU_MODO_SII], true);
$parametrosVolver = ['serie' => $serie, 'numero' => $numero];

if (es_post()) {
    comprobar_csrf();
    try {
        if ($esVerifactu && isset($_FILES['certificado']) && (int)($_FILES['certificado']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_NO_FILE) {
            $enServidor = campo('destino') === 'servidor';
            $datos = certificado_instalar($pdo, $usuario, $codigoEmpresa, $_FILES['certificado'],
                (string)($_POST['contrasena_certificado'] ?? ''), $enServidor);
            aviso('ok', $enServidor
                ? t('Certificado de {titular} guardado en el servidor.', ['titular' => $datos['titular']])
                : t('Certificado de {titular} cargado para esta sesión.', ['titular' => $datos['titular']]));
        }
        $resultado = factura_emitir($pdo, $usuario, $serie, $numero);
        $actual = factura_leer($pdo, $serie, $numero) ?? $factura;
        $_SESSION['factura_creada'] = [
            'modificada'        => false,
            'emitida'           => true,
            'serie'             => $serie,
            'numero'            => $numero,
            'numero_formateado' => $numeroFormateado,
            'fecha'             => substr((string)$actual['FECHA_FAC'], 0, 10),
            'empresa'           => (string)$actual['RAZON_SOCIAL_EMPRESA_FAC'],
            'cliente'           => (string)$actual['RAZON_SOCIAL_CLIENTE_FAC'],
            'total_bases'       => (float)$actual['TOTAL_BASES_FAC'],
            'total_impuestos'   => (float)$actual['TOTAL_IMPUESTOS_FAC'],
            'total_retencion'   => (float)$actual['TOTAL_RETENCION_FAC'],
            'total_liquido'     => (float)$actual['TOTAL_LIQUIDO_FAC'],
        ];
        aviso('ok', $resultado['mensaje']);
        if (is_array($resultado['cola'])) {
            verifactu_cola_avisar($resultado['cola']);
        }
        redirigir('creada');
    } catch (Throwable $error) {
        aviso('error', $error->getMessage());
        redirigir('factura_emitir', $parametrosVolver);
    }
}

/* Comprobaciones previas para avisar antes de emitir. */
$avisos = [];
$errores = [];
$certificado = null;
$sif = null;
if ($esVerifactu) {
    $certificado = certificado_disponible($codigoEmpresa);
    $sif = sif_estado_empresa($pdo, $codigoEmpresa);
    if ($sif !== null && !$sif['valido']) {
        $errores[] = t('Instalación SIF de la empresa: {mensaje} Se genera desde Parámetros.', ['mensaje' => $sif['mensaje']]);
    }
    if ($certificado === null) {
        $avisos[] = t('La empresa no tiene certificado cargado: cárgalo aquí para poder enviar el registro a la AEAT.');
    } elseif (!$certificado['datos']['vigente']) {
        $errores[] = t('El certificado cargado no está vigente.');
    }
    try {
        if ($certificado !== null) {
            verifactu_validar_emision($pdo, $usuario, $serie, $numero);
        }
    } catch (Throwable $error) {
        $errores[] = $error->getMessage();
    }
} elseif ($modo['modo'] === 'NO_VERIFACTU') {
    $errores[] = t('El modo NO VERI*FACTU no está disponible en la web. Cambia el modo desde el menú.');
}
$puedeEmitir = $errores === [];

ob_start();
?>
<section class="tarjeta">
  <h2><?= h(t('Factura {numero}', ['numero' => $numeroFormateado])) ?></h2>
  <dl class="ficha">
    <dt><?= h(t('Fecha')) ?></dt><dd><?= h(fecha_es((string)$factura['FECHA_FAC'])) ?></dd>
    <dt><?= h(t('Emisor')) ?></dt><dd><?= h((string)$factura['RAZON_SOCIAL_EMPRESA_FAC']) ?> · <?= h((string)$factura['NIF_EMPRESA_FAC']) ?></dd>
    <dt><?= h(t('Cliente')) ?></dt><dd><?= h((string)$factura['RAZON_SOCIAL_CLIENTE_FAC']) ?> · <?= h((string)$factura['NIF_CLIENTE_FAC']) ?></dd>
    <dt><?= h(t('Total')) ?></dt><dd><?= h(formatear_importe((float)$factura['TOTAL_LIQUIDO_FAC'])) ?></dd>
    <dt><?= h(t('Estado')) ?></dt><dd><?= h(fase_factura_texto($factura)) ?></dd>
    <dt><?= h(t('Modo')) ?></dt><dd><?= html_etiqueta_modo($modo['modo']) ?></dd>
    <?php if ($esVerifactu): ?>
    <dt><?= h(t('Instalación SIF')) ?></dt><dd><?= $sif === null ? '—' : h(($sif['numero'] !== '' ? $sif['numero'] . ' · ' : '') . $sif['mensaje']) ?></dd>
    <dt><?= h(t('Certificado')) ?></dt><dd><?= html_estado_certificado($certificado) ?></dd>
    <?php endif; ?>
  </dl>
</section>
<form method="post" action="<?= h(url('factura_emitir')) ?>" class="formulario" enctype="multipart/form-data">
  <?= campo_csrf() ?>
  <input type="hidden" name="serie" value="<?= h($serie) ?>">
  <input type="hidden" name="numero" value="<?= h($numero) ?>">
  <?php if ($esVerifactu && $certificado === null): ?>
  <section class="tarjeta">
    <h2><?= h(t('Certificado de la empresa')) ?></h2>
    <label class="campo"><span><?= h(t('Fichero del certificado (.pfx / .p12)')) ?></span>
      <input type="file" name="certificado" accept=".pfx,.p12,application/x-pkcs12"></label>
    <?= campo_texto('contrasena_certificado', t('Contraseña del certificado'), '', ['type' => 'password', 'autocomplete' => 'off']) ?>
    <div class="opciones-radio">
      <label class="casilla"><input type="radio" name="destino" value="sesion" checked>
        <span><?= h(t('Solo para esta sesión')) ?><small><?= h(t('Se descarta al salir de la web.')) ?></small></span></label>
      <label class="casilla"><input type="radio" name="destino" value="servidor">
        <span><?= h(t('Guardar en el servidor')) ?><small><?= h(t('Carpeta privada, clave cifrada; se puede borrar desde el menú.')) ?></small></span></label>
    </div>
  </section>
  <?php endif; ?>
  <?php if ($esVerifactu): ?>
  <p class="ayuda"><?= h(t('La factura pasa a VERIFACTU_PENDIENTE, se registra en la cola Verifactu y se envía en el acto a la AEAT ({modo}) con el certificado de la empresa. El registro queda encadenado: después no se puede modificar ni borrar.', ['modo' => $modo['modo']])) ?></p>
  <button type="submit" class="boton principal"<?= $puedeEmitir ? '' : ' disabled' ?>><?= h(t('Emitir y enviar a la AEAT ({modo})', ['modo' => $modo['modo']])) ?></button>
  <?php else: ?>
  <p class="ayuda"><?= h(t('La factura pasa a emitida en modo SIN VERIFACTU (sin registro fiscal ni QR). Después no se puede modificar ni borrar.')) ?></p>
  <button type="submit" class="boton principal"<?= $puedeEmitir ? '' : ' disabled' ?>><?= h(t('Emitir factura')) ?></button>
  <?php endif; ?>
</form>
<p class="pie-enlaces"><a href="<?= h(url('facturas')) ?>"><?= h(t('‹ No emitir, volver')) ?></a></p>
<?php
pagina(t('Emitir factura'), (string)ob_get_clean(), ['errores' => $errores, 'avisos' => $avisos]);
