<?php
declare(strict_types=1);

/*
 * Paso 6: líneas de la factura (servicios). Cada línea lleva descripción,
 * cantidad, unidad, precio (con o sin IVA según la tarifa del cliente) y
 * descuento. Se puede partir de un artículo del catálogo o escribir la
 * línea a mano, igual que en el programa. Las líneas se guardan en la
 * sesión hasta crear la factura.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = exigir_paso('lineas');
$cabecera = cabecera_provisional($pdo, $usuario, $borrador);
$impuestosIncluidos = es_si((string)$cabecera['ESIMP_INCL_TARIFA_CLIENTE_FAC']);
$configuracion = configuracion_fiscal($cabecera);
$porcentajeIva = porcentaje_iva_tipo($configuracion, 'N');
$defectosLinea = valores_defecto($pdo, 'fza_facturas_lineas');
$unidadDefecto = trim((string)($defectosLinea['TIPO_CANTIDAD_ARTICULO_FACLIN'] ?? 'Uds'));
if ($unidadDefecto === '') {
    $unidadDefecto = 'Uds';
}

$errores = [];
$resultadosArticulos = [];
$formulario = [
    'codigo'      => '',
    'descripcion' => '',
    'cantidad'    => '1',
    'unidad'      => $unidadDefecto,
    'precio'      => '',
    'dto'         => '0',
];

if (es_post()) {
    comprobar_csrf();
    $accion = campo('accion');
    if (campo('elegir') !== '') {
        $accion = 'elegir';
    }
    foreach (array_keys($formulario) as $campo) {
        $formulario[$campo] = campo($campo, $formulario[$campo]);
    }
    $formulario['codigo'] = strtoupper($formulario['codigo']);

    if ($accion === 'quitar') {
        $indice = (int)campo('indice', '-1');
        if (isset($borrador['lineas'][$indice])) {
            array_splice($borrador['lineas'], $indice, 1);
            borrador_guardar($borrador);
            aviso('ok', t('Línea quitada.'));
        }
        redirigir('lineas');
    }

    if ($accion === 'buscar') {
        $texto = $formulario['codigo'] !== '' ? $formulario['codigo'] : $formulario['descripcion'];
        if (trim($texto) === '') {
            $errores[] = t('Escribe parte del código o de la descripción del artículo para buscarlo.');
        } else {
            $resultadosArticulos = articulos_buscar($pdo, $texto, (string)$cabecera['TARIFA_ARTICULO_CLIENTE_FAC']);
            if ($resultadosArticulos === []) {
                $errores[] = t('No hay ningún artículo que coincida con "{texto}". Puedes escribir la línea a mano.', ['texto' => $texto]);
            }
        }
    }

    if ($accion === 'elegir') {
        $articulo = articulo_por_codigo($pdo, campo('elegir'), (string)$cabecera['TARIFA_ARTICULO_CLIENTE_FAC']);
        if ($articulo === null) {
            $errores[] = t('El artículo elegido no existe.');
        } else {
            $formulario['codigo'] = (string)$articulo['CODIGO_ART_ART'];
            $formulario['descripcion'] = mb_substr((string)$articulo['DESCRIPCION_ART'], 0, 100);
            $formulario['unidad'] = trim((string)$articulo['TIPO_CANTIDAD_ART']) !== ''
                ? (string)$articulo['TIPO_CANTIDAD_ART'] : $unidadDefecto;
            $formulario['precio'] = $articulo['PRECIO_SALIDA_ARTTAR'] === null
                ? '' : number_format((float)$articulo['PRECIO_SALIDA_ARTTAR'], 2, ',', '');
            $formulario['dto'] = '0';
        }
    }

    if ($accion === 'anadir') {
        $descripcion = mb_substr($formulario['descripcion'], 0, 100);
        $cantidad = numero_desde_texto($formulario['cantidad']);
        $precio = numero_desde_texto($formulario['precio']);
        $dto = $formulario['dto'] === '' ? 0.0 : numero_desde_texto($formulario['dto']);
        if ($descripcion === '') {
            $errores[] = t('La descripción de la línea es obligatoria.');
        }
        if ($cantidad === null || $cantidad == 0.0) {
            $errores[] = t('Indica la cantidad.');
        }
        if ($precio === null) {
            $errores[] = t('Indica el precio.');
        }
        if ($dto === null || $dto < 0 || $dto > 100) {
            $errores[] = t('El descuento debe estar entre 0 y 100.');
        }
        if ($errores === []) {
            $articulo = $formulario['codigo'] !== ''
                ? articulo_por_codigo($pdo, $formulario['codigo'], (string)$cabecera['TARIFA_ARTICULO_CLIENTE_FAC'])
                : null;
            $borrador['lineas'][] = [
                'codigo'        => $formulario['codigo'],
                'descripcion'   => $descripcion,
                'cantidad'      => $cantidad,
                'unidad'        => mb_substr($formulario['unidad'] === '' ? $unidadDefecto : $formulario['unidad'], 0, 20),
                'precio'        => $precio,
                'dto'           => $dto,
                'tipo_iva'      => $articulo !== null ? (string)$articulo['TIPO_IVA_ART'] : 'N',
                'tipo_articulo' => $articulo !== null ? (string)$articulo['TIPO_ART'] : 'SERVICIO',
                'familia'       => $articulo !== null ? (string)($articulo['CODIGO_FAM_ART'] ?? '') : '',
            ];
            borrador_guardar($borrador);
            aviso('ok', t('Línea añadida.'));
            redirigir('lineas');
        }
    }
}

$calculo = calcular_factura($cabecera, $borrador['lineas']);
$lineas = $calculo['lineas'];
$totales = $calculo['totales'];
$avisos = [];
if ($porcentajeIva == 0.0) {
    /* Diagnóstico: por qué la factura sale sin IVA. */
    $zona = trim((string)$borrador['empresa']['GRUPO_ZONA_IVA_EMP']);
    $motivos = [];
    if ($zona === '') {
        $motivos[] = t('la copia de la empresa en esta factura no tiene zona de IVA');
    } elseif (!isset($cabecera['CODIGO_IVA_FAC'])) {
        $detalle = [];
        try {
            $detalle[] = 'base ' . (string)$pdo->query('SELECT DATABASE()')->fetchColumn();
            $detalle[] = 'fza_ivas del grupo: ' . (string)consultar_una($pdo,
                'SELECT COUNT(*) AS N FROM fza_ivas WHERE IVA_IVAGRP = ?', [$zona])['N'];
            $detalle[] = 'fza_ivas_grupos: ' . (string)consultar_una($pdo,
                'SELECT COUNT(*) AS N FROM fza_ivas_grupos WHERE IVA_IVAGRP = ?', [$zona])['N'];
            $filaVista = consultar_una($pdo,
                'SELECT COUNT(*) AS N, MIN(FECHA_DESDE_IVA) AS DESDE, MAX(IFNULL(FECHA_HASTA_IVA, \'siempre\')) AS HASTA ' .
                'FROM vi_ivas WHERE IVA_IVAGRP = ?', [$zona]);
            $detalle[] = 'vi_ivas del grupo: ' . (string)$filaVista['N'] .
                ($filaVista['N'] > 0 ? ' (desde ' . $filaVista['DESDE'] . ' hasta ' . $filaVista['HASTA'] . ')' : '');
        } catch (Throwable $error) {
            $detalle[] = 'error al consultar: ' . $error->getMessage();
        }
        $motivos[] = t('la zona de IVA "{zona}" no tiene porcentajes vigentes el {fecha} [{detalle}]', [
            'zona' => $zona, 'fecha' => fecha_es((string)$borrador['fecha']), 'detalle' => implode('; ', $detalle),
        ]);
    } elseif ((float)($cabecera['PORCENTAJE_IVAN_FAC'] ?? 0) == 0.0) {
        $motivos[] = t('la zona de IVA "{zona}" tiene el tipo normal al 0 %', ['zona' => $zona]);
    }
    if ($configuracion['iva_exento']) {
        $causas = [];
        $clienteDiag = is_array($borrador['cliente']) ? $borrador['cliente'] : [];
        if (es_si((string)($clienteDiag['ESIVA_EXENTO_CLI'] ?? 'N'))) {
            $causas[] = t('cliente exento de IVA');
        }
        if (es_si((string)($clienteDiag['ESINTRACOMUNITARIO_CLI'] ?? 'N'))) {
            $causas[] = t('cliente intracomunitario');
        }
        if (es_si((string)$borrador['empresa']['ESREGIMENESPECIALAGRICOLA_EMP'])) {
            $causas[] = t('empresa en régimen agrario (REAGP)');
        }
        if (es_si((string)($clienteDiag['ESREGIMENESPECIALAGRICOLA_CLI'] ?? 'N'))) {
            $causas[] = t('cliente en régimen agrario (REAGP)');
        }
        $motivos[] = t('la venta se trata como exenta ({causas})', ['causas' => implode(', ', $causas ?: [t('reglas fiscales')])]);
    }
    $avisos[] = t('IVA al 0 % porque {motivos}. La web usa la copia de empresa y cliente confirmada en los pasos 2 y 5: si has corregido datos en la base, vuelve a confirmar la empresa y el cliente o empieza una factura nueva desde el menú.', [
        'motivos' => implode(t(' y '), $motivos ?: [t('no se ha podido determinar el tipo')]),
    ]);
}
$etiquetaPrecio = $impuestosIncluidos
    ? t('Precio unitario con IVA incluido')
    : t('Precio unitario sin IVA');

ob_start();
?>
<p class="nota"><?= t('Factura <strong>{numero}</strong> · {cliente}<br>Tarifa {tarifa}: {precios} · IVA {iva} %', [
    'numero' => h(numero_documento_formateado($borrador['empresa'], (string)$borrador['serie'], $borrador['numero'] === '0' ? '…' : (string)$borrador['numero'])),
    'cliente' => h(is_array($borrador['cliente'])
        ? (string)$borrador['cliente']['RAZON_SOCIAL_CLI']
        : t('venta sin cliente (ticket)')),
    'tarifa' => h((string)$cabecera['TARIFA_ARTICULO_CLIENTE_FAC']),
    'precios' => h($impuestosIncluidos ? t('precios con IVA incluido') : t('precios sin IVA')),
    'iva' => h(formatear_porcentaje((string)$porcentajeIva)),
]) ?></p>

<?php if ($lineas !== []): ?>
<h2><?= h(t('Líneas ({n})', ['n' => count($lineas)])) ?></h2>
<div class="lista">
  <?php foreach ($lineas as $i => $linea): ?>
  <div class="linea">
    <div class="linea-texto">
      <strong><?= h((string)$linea['descripcion']) ?></strong>
      <small><?= h(formatear_cantidad((float)$linea['cantidad'])) ?> <?= h((string)$linea['unidad']) ?> ×
        <?= h(formatear_importe((float)$linea['precio'])) ?><?= (float)$linea['dto'] > 0 ? ' − ' . h(formatear_porcentaje((string)$linea['dto'])) . ' %' : '' ?>
        = <?= h(formatear_importe((float)$linea['base_linea'])) ?> <?= h(t('sin IVA')) ?><?= $linea['codigo'] !== '' ? ' · ' . h((string)$linea['codigo']) : '' ?></small>
    </div>
    <form method="post" action="<?= h(url('lineas')) ?>" class="linea-accion">
      <?= campo_csrf() ?>
      <input type="hidden" name="accion" value="quitar">
      <input type="hidden" name="indice" value="<?= $i ?>">
      <button type="submit" class="boton-quitar" aria-label="<?= h(t('Quitar línea')) ?>"><?= h(t('Quitar')) ?></button>
    </form>
  </div>
  <?php endforeach; ?>
</div>
<dl class="ficha totales-breves">
  <dt><?= h(t('Base imponible')) ?></dt><dd><?= h(formatear_importe($totales['total_bases'])) ?></dd>
  <dt><?= h(t('Total con impuestos')) ?></dt><dd><?= h(formatear_importe($totales['total_con_impuestos'])) ?></dd>
</dl>
<a class="boton principal" href="<?= h(url('resumen')) ?>"><?= h(t('Continuar a totales')) ?></a>
<?php endif; ?>

<h2><?= h($lineas === [] ? t('Primera línea') : t('Añadir otra línea')) ?></h2>
<form method="post" action="<?= h(url('lineas')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <input type="hidden" name="accion" value="anadir">
  <div class="fila-buscar">
    <?= campo_texto('codigo', t('Artículo (código, opcional)'), $formulario['codigo'], [
        'autocapitalize' => 'characters', 'autocorrect' => 'off', 'maxlength' => '20',
        'placeholder' => t('Vacío = línea escrita a mano'),
    ]) ?>
    <button type="submit" name="accion" value="buscar" formnovalidate class="boton secundario"><?= h(t('Buscar en artículos')) ?></button>
  </div>
  <?php if ($resultadosArticulos !== []): ?>
  <p class="ayuda"><?= h(t('Toca un artículo para copiar su descripción y su precio en la línea.')) ?></p>
  <div class="lista">
    <?php foreach ($resultadosArticulos as $articulo): ?>
    <button type="submit" name="elegir" value="<?= h((string)$articulo['CODIGO_ART_ART']) ?>" formnovalidate class="elemento">
      <strong><?= h((string)$articulo['DESCRIPCION_ART']) ?></strong>
      <small><?= h((string)$articulo['CODIGO_ART_ART']) ?> · <?= $articulo['PRECIO_SALIDA_ARTTAR'] === null ? h(t('sin precio en la tarifa')) : h(formatear_importe((float)$articulo['PRECIO_SALIDA_ARTTAR'])) ?></small>
    </button>
    <?php endforeach; ?>
  </div>
  <?php endif; ?>
  <?= campo_texto('descripcion', t('Descripción'), $formulario['descripcion'], [
      'required' => 'required', 'maxlength' => '100', 'autocapitalize' => 'characters',
  ]) ?>
  <div class="fila-dos">
    <?= campo_texto('cantidad', t('Cantidad'), $formulario['cantidad'], [
        'inputmode' => 'decimal', 'required' => 'required', 'maxlength' => '12',
    ]) ?>
    <?= campo_texto('unidad', t('Unidad'), $formulario['unidad'], ['maxlength' => '20']) ?>
  </div>
  <div class="fila-dos">
    <?= campo_texto('precio', $etiquetaPrecio, $formulario['precio'], [
        'inputmode' => 'decimal', 'required' => 'required', 'maxlength' => '14', 'placeholder' => '0,00',
    ]) ?>
    <?= campo_texto('dto', t('Descuento %'), $formulario['dto'], ['inputmode' => 'decimal', 'maxlength' => '6']) ?>
  </div>
  <button type="submit" class="boton <?= $lineas === [] ? 'principal' : 'secundario' ?>"><?= h(t('Añadir línea')) ?></button>
</form>
<?php if (es_simplificada($borrador)): ?>
<p class="pie-enlaces"><a href="<?= h(url('cabecera')) ?>"><?= h(t('‹ Volver a fecha, serie y pago')) ?></a></p>
<?php else: ?>
<p class="pie-enlaces"><a href="<?= h(url('cliente_datos')) ?>"><?= h(t('‹ Volver al cliente')) ?></a></p>
<?php endif; ?>
<?php
pagina(t('Líneas'), (string)ob_get_clean(), ['paso' => 'lineas', 'errores' => $errores, 'avisos' => $avisos]);
