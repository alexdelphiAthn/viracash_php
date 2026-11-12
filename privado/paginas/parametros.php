<?php
declare(strict_types=1);

/*
 * Parámetros de Verifactu y de los servicios web (fza_usuarios_perfiles,
 * formulario frmMtoAppParam, los mismos que "Parámetros de aplicación" del
 * programa) y número de instalación SIF de las empresas, pedido al servicio
 * web del productor. Solo administradores, como en el programa.
 *
 * Aquí se configura también el ticket de las facturas simplificadas: el
 * empleado que atiende (parámetro de caja vgerCodEmpleadoDefecto, formulario
 * frmMtoCajaParam) y las cuatro líneas de pie de ticket de cada empresa
 * (TEXTO_PIE_TICKET_CAJA_1..4_EMP), las mismas que usa la caja del programa.
 */

$usuario = exigir_administrador();
$pdo = bbdd();
$definiciones = verifactu_definiciones_parametros();
$ambitos = parametros_app_ambitos($usuario);

if (es_post()) {
    comprobar_csrf();
    try {
        if (campo('accion') === 'guardar') {
            $ambito = campo('ambito');
            if (!in_array($ambito, $ambitos, true)) {
                throw new RuntimeException(t('Ámbito no válido.'));
            }
            $valores = parametros_app_cargar($pdo, $usuario, true);
            $cambios = [];
            foreach ($definiciones as $nombre => [$categoria, $descripcion, $tipo, $defecto]) {
                if (!array_key_exists('p_' . $nombre, $_POST)) {
                    continue;
                }
                $nuevo = campo('p_' . $nombre);
                if ($tipo === 'bool') {
                    $nuevo = $nuevo === 'True' ? 'True' : 'False';
                } elseif ($tipo === 'int' && $nuevo !== '' && !is_numeric($nuevo)) {
                    throw new RuntimeException(t('El parámetro {nombre} debe ser un número.', ['nombre' => $nombre]));
                }
                $actual = trim((string)($valores[$nombre]['valor'] ?? ''));
                if ($nombre === 'appVerifactuDeclaracionFecha' && $nuevo !== '') {
                    if (fecha_iso_desde_es($nuevo) === '') {
                        throw new RuntimeException(t('La fecha debe ser válida y tener formato dd/mm/yyyy.'));
                    }
                    if ($nuevo === fecha_es($actual)) {
                        $nuevo = $actual;
                    }
                }
                if ($actual === '' && $nuevo === $defecto && !isset($valores[$nombre])) {
                    continue; /* Sin fila y con el valor por defecto: nada que guardar. */
                }
                if ($nuevo !== $actual && !($actual === '' && $nuevo === $defecto && $ambito !== (string)($valores[$nombre]['ambito'] ?? ''))) {
                    $cambios[$nombre] = $nuevo;
                } elseif ($nuevo !== $actual) {
                    $cambios[$nombre] = $nuevo;
                }
            }
            if ($cambios === []) {
                aviso('aviso', t('No había cambios que guardar.'));
            } else {
                parametros_app_guardar($pdo, $ambito, $cambios);
                aviso('ok', t('{n} parámetro(s) guardado(s) para {ambito}: {lista}.', [
                    'n' => count($cambios), 'ambito' => $ambito, 'lista' => implode(', ', array_keys($cambios)),
                ]));
                $detalle = registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_CAMBIO_CONFIG,
                    'Cambio de configuración Verifactu', 'Parámetros guardados para ' . $ambito . ': ' . count($cambios));
                if ($detalle !== null) {
                    aviso('aviso', t('No se pudo anotar el cambio en el log Verifactu: {detalle}', ['detalle' => $detalle]));
                }
            }
        } elseif (campo('accion') === 'ticket') {
            $ambito = campo('ambito_ticket');
            if (!in_array($ambito, $ambitos, true)) {
                throw new RuntimeException(t('Ámbito no válido.'));
            }
            $empleado = campo('empleado');
            if ($empleado !== '' && !empleado_existe($pdo, $empleado)) {
                throw new RuntimeException(t('El empleado elegido ya no existe.'));
            }
            parametros_app_guardar($pdo, $ambito, ['vgerCodEmpleadoDefecto' => $empleado], FORMULARIO_PARAMETROS_CAJA);
            aviso('ok', $empleado === ''
                ? t('El ticket dejará de indicar quién atendió ({ambito}).', ['ambito' => $ambito])
                : t('El ticket indicará que atiende {empleado} ({ambito}).', ['empleado' => $empleado, 'ambito' => $ambito]));
        } elseif (campo('accion') === 'pie') {
            $codigoEmpresa = campo('empresa');
            if (empresa_por_codigo($pdo, $codigoEmpresa) === null) {
                throw new RuntimeException(t('La empresa elegida ya no existe.'));
            }
            empresa_pie_ticket_guardar($pdo, $codigoEmpresa, [
                campo('pie1'), campo('pie2'), campo('pie3'), campo('pie4'),
            ], (string)$usuario['usuario']);
            aviso('ok', t('Pie de ticket guardado para {empresa}.', ['empresa' => $codigoEmpresa]));
        } elseif (campo('accion') === 'sif') {
            $estado = sif_generar_empresa($pdo, $usuario, campo('empresa'), campo('version'));
            aviso('ok', t('Instalación SIF de {empresa}: {numero} ({mensaje})', [
                'empresa' => $estado['razon_social'], 'numero' => $estado['numero'], 'mensaje' => $estado['mensaje'],
            ]));
            $detalle = registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_CAMBIO_CONFIG,
                'Cambio de configuración Verifactu', 'Número de instalación SIF ' . $estado['numero'] . ' registrado para ' .
                $estado['codigo'] . ' (versión ' . $estado['version'] . ') desde la facturación web');
            if ($detalle !== null) {
                aviso('aviso', t('No se pudo anotar el cambio en el log Verifactu: {detalle}', ['detalle' => $detalle]));
            }
        }
    } catch (Throwable $error) {
        aviso('error', $error->getMessage());
    }
    redirigir('parametros');
}

$valores = parametros_app_cargar($pdo, $usuario, true);
$categorias = [];
foreach ($definiciones as $nombre => $definicion) {
    $categorias[$definicion[0]][$nombre] = $definicion;
}
$empresas = empresas_listar($pdo);
$empleados = empleados_listar($pdo);
$empleadoTicket = empleado_ticket_defecto($pdo, $usuario);
$hayPieTicket = pie_ticket_disponible($pdo);

ob_start();
?>
<form method="post" action="<?= h(url('parametros')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <input type="hidden" name="accion" value="guardar">
  <?php foreach ($categorias as $categoria => $parametros): ?>
  <section class="tarjeta">
    <h2><?= h(t($categoria)) ?></h2>
    <?php foreach ($parametros as $nombre => [$cat, $descripcion, $tipo, $defecto]): ?>
      <?php
        $fila = $valores[$nombre] ?? null;
        $valor = trim((string)($fila['valor'] ?? ''));
        $efectivo = $valor === '' ? $defecto : $valor;
        $origen = $fila === null ? t('valor por defecto') : t('ámbito {ambito}', ['ambito' => (string)$fila['ambito']]);
      ?>
      <div class="parametro">
        <label class="campo"><span><?= h(t($descripcion)) ?></span>
        <?php if ($tipo === 'bool'): ?>
          <select name="p_<?= h($nombre) ?>"><?= opciones_select(['True' => t('Sí'), 'False' => t('No')], strcasecmp($efectivo, 'True') === 0 || $efectivo === '1' ? 'True' : 'False') ?></select>
        <?php elseif ($tipo === 'int'): ?>
          <input type="number" name="p_<?= h($nombre) ?>" value="<?= h($efectivo) ?>" inputmode="numeric">
        <?php elseif ($nombre === 'appVerifactuDeclaracionFecha'): ?>
          <input type="text" name="p_<?= h($nombre) ?>" value="<?= h(fecha_es($efectivo)) ?>" placeholder="dd/mm/yyyy" maxlength="10" pattern="[0-9]{2}/[0-9]{2}/[0-9]{4}">
        <?php elseif ($nombre === 'appApiToken'): ?>
          <input type="password" name="p_<?= h($nombre) ?>" value="<?= h($efectivo) ?>" autocomplete="off">
        <?php else: ?>
          <input type="text" name="p_<?= h($nombre) ?>" value="<?= h($efectivo) ?>" autocomplete="off" autocapitalize="none">
        <?php endif; ?>
        </label>
        <small><code><?= h($nombre) ?></code> · <?= h($origen) ?></small>
      </div>
    <?php endforeach; ?>
  </section>
  <?php endforeach; ?>
  <label class="campo"><span><?= h(t('Guardar los cambios para')) ?></span>
    <select name="ambito"><?= opciones_select(array_combine($ambitos, $ambitos), (string)$usuario['usuario']) ?></select></label>
  <p class="ayuda"><?= h(t('Se guardan solo los parámetros que cambien, en el ámbito elegido (tu usuario tiene prioridad sobre el grupo y sobre "Todos", igual que en ViraCash). El modo y el entorno también se cambian desde el menú.')) ?></p>
  <button type="submit" class="boton principal"><?= h(t('Guardar parámetros')) ?></button>
</form>
<section class="tarjeta">
  <h2><?= h(t('Ticket de la factura simplificada')) ?></h2>
  <p class="ayuda"><?= h(t('El empleado sale en el ticket como "LE ATENDIÓ" y se graba en la factura (CODIGO_CAJERO_FAC). Es el mismo parámetro de caja del programa (vgerCodEmpleadoDefecto), así que vale para las dos.')) ?></p>
  <form method="post" action="<?= h(url('parametros')) ?>" class="formulario">
    <?= campo_csrf() ?>
    <input type="hidden" name="accion" value="ticket">
    <label class="campo"><span><?= h(t('Empleado que atiende')) ?></span>
      <select name="empleado">
        <?php
          $opcionesEmpleado = ['' => t('— Sin empleado —')];
          foreach ($empleados as $filaEmpleado) {
              $diminutivo = trim((string)$filaEmpleado['DIMINUTIVO_TICKET_EMPL']);
              $nombre = trim((string)$filaEmpleado['NOMBRE_EMPL']);
              $opcionesEmpleado[(string)$filaEmpleado['CODIGO_EMPL']] = trim((string)$filaEmpleado['CODIGO_EMPL']) .
                  ($diminutivo !== '' ? ' · ' . $diminutivo : '') . ($nombre !== '' ? ' · ' . $nombre : '');
          }
        ?>
        <?= opciones_select($opcionesEmpleado, $empleadoTicket) ?>
      </select>
    </label>
    <?php if ($empleados === []): ?>
    <p class="ayuda"><?= h(t('No hay empleados activos en fza_empleados: créalos en el programa para poder elegir uno.')) ?></p>
    <?php endif; ?>
    <label class="campo"><span><?= h(t('Guardar los cambios para')) ?></span>
      <select name="ambito_ticket"><?= opciones_select(array_combine($ambitos, $ambitos), (string)$usuario['usuario']) ?></select></label>
    <button type="submit" class="boton secundario"><?= h(t('Guardar el empleado del ticket')) ?></button>
  </form>
</section>
<section class="tarjeta">
  <h2><?= h(t('Pie del ticket')) ?></h2>
  <?php if (!$hayPieTicket): ?>
  <p class="ayuda"><?= h(t('Esta base de datos no tiene las columnas del pie de ticket en las empresas.')) ?></p>
  <?php else: ?>
  <p class="ayuda"><?= h(t('Cuatro líneas por empresa, hasta 42 caracteres cada una (el ancho del papel), que se imprimen centradas al final del ticket. Son las mismas de Archivo → Empresas del programa.')) ?></p>
  <?php foreach ($empresas as $empresa): ?>
    <?php $pie = empresa_pie_ticket($pdo, (string)$empresa['CODIGO_EMP_EMP']); ?>
    <form method="post" action="<?= h(url('parametros')) ?>" class="formulario">
      <?= campo_csrf() ?>
      <input type="hidden" name="accion" value="pie">
      <input type="hidden" name="empresa" value="<?= h((string)$empresa['CODIGO_EMP_EMP']) ?>">
      <h3><?= h((string)$empresa['RAZON_SOCIAL_EMP']) ?> (<?= h((string)$empresa['CODIGO_EMP_EMP']) ?>)</h3>
      <?php foreach ([1, 2, 3, 4] as $n): ?>
      <?= campo_texto('pie' . $n, t('Línea {n}', ['n' => $n]), (string)$pie[$n - 1], [
          'maxlength' => '42', 'autocomplete' => 'off',
      ]) ?>
      <?php endforeach; ?>
      <button type="submit" class="boton secundario"><?= h(t('Guardar el pie de ticket')) ?></button>
    </form>
  <?php endforeach; ?>
  <?php endif; ?>
</section>
<section class="tarjeta">
  <h2><?= h(t('Instalación SIF')) ?></h2>
  <p class="ayuda"><?= h(t('El número de instalación lo asigna el servicio de asignación de SIF (URL, API key y referencia de "Servicios web") y se guarda en la empresa, como en ViraCash. La versión debe ser la del SIF registrado.')) ?></p>
  <?php foreach ($empresas as $empresa): ?>
    <?php $sif = sif_estado_empresa($pdo, (string)$empresa['CODIGO_EMP_EMP']); ?>
    <form method="post" action="<?= h(url('parametros')) ?>" class="formulario sif-empresa">
      <?= campo_csrf() ?>
      <input type="hidden" name="accion" value="sif">
      <input type="hidden" name="empresa" value="<?= h((string)$empresa['CODIGO_EMP_EMP']) ?>">
      <dl class="ficha">
        <dt><?= h(t('Empresa')) ?></dt><dd><?= h((string)$empresa['RAZON_SOCIAL_EMP']) ?> (<?= h((string)$empresa['CODIGO_EMP_EMP']) ?>) · <?= h((string)$empresa['NIF_EMP']) ?></dd>
        <dt><?= h(t('Número')) ?></dt><dd><?= $sif !== null && $sif['numero'] !== '' ? h($sif['numero']) : '—' ?></dd>
        <dt><?= h(t('Estado')) ?></dt><dd><?= h($sif['mensaje'] ?? '') ?><?= $sif !== null && $sif['instante'] !== '' ? ' <small>(' . h(fecha_hora_es($sif['instante'])) . ')</small>' : '' ?></dd>
      </dl>
      <?= campo_texto('version', t('Versión del SIF'), sif_version_propuesta($pdo, $sif), ['autocomplete' => 'off', 'autocapitalize' => 'none']) ?>
      <button type="submit" class="boton secundario"><?= h($sif !== null && $sif['valido'] ? t('Actualizar número de instalación') : t('Generar número de instalación')) ?></button>
    </form>
  <?php endforeach; ?>
</section>
<p class="pie-enlaces"><a href="<?= h(url('menu')) ?>"><?= h(t('‹ Volver al menú')) ?></a></p>
<?php
pagina(t('Parámetros'), (string)ob_get_clean());
