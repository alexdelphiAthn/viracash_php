<?php
declare(strict_types=1);

/*
 * Resumen de cabeceras de facturas entre dos fechas (para la gestoría o la
 * declaración trimestral): en pantalla, los totales por tipo de IVA; para
 * descargar, un CSV que Excel abre directamente (UTF-8 con BOM, separador
 * punto y coma, coma decimal y fechas dd/mm/aaaa), una fila por factura.
 *
 * Solo lectura de fza_facturas: no graba nada.
 */

$usuario = exigir_usuario();
$pdo = bbdd();

/** Fecha AAAA-MM-DD válida o null. */
function resumen_fecha_valida(string $valor): ?string
{
    $fecha = DateTimeImmutable::createFromFormat('!Y-m-d', trim($valor));
    return $fecha !== false && $fecha->format('Y-m-d') === trim($valor) ? $fecha->format('Y-m-d') : null;
}

/** Importe o porcentaje para el CSV: dos decimales con coma y sin separador de miles. */
function resumen_numero_csv(float $valor): string
{
    return number_format(round($valor, 2), 2, ',', '');
}

/** Texto para el CSV: evita que Excel interprete como fórmula lo que empieza por =, +, -, @. */
function resumen_texto_csv(?string $valor): string
{
    $valor = trim(str_replace(["\r", "\n", "\t"], ' ', (string)$valor));
    return $valor !== '' && str_contains('=+-@', $valor[0]) ? "'" . $valor : $valor;
}

/** Factura que cuenta como emitida: ni borrador sin consolidar ni anulada. */
function resumen_factura_emitida(array $factura): bool
{
    return !factura_editable($factura) &&
        !str_ends_with(strtoupper(trim((string)($factura['FASE_FAC'] ?? ''))), 'ANULADA');
}

/** Tramos de IVA de la cabecera: sufijo de columna => nombre. */
const RESUMEN_TRAMOS_IVA = ['N' => 'general', 'R' => 'reducido', 'S' => 'superreducido', 'E' => 'exento'];

/* ----- Filtros (GET, para poder guardar el enlace) ----- */

$hoy = new DateTimeImmutable('today');
$trimestreActual = intdiv((int)$hoy->format('n') - 1, 3);
$inicioTrimestre = $hoy->setDate((int)$hoy->format('Y'), $trimestreActual * 3 + 1, 1);
$desde = resumen_fecha_valida((string)($_GET['desde'] ?? '')) ?? $inicioTrimestre->format('Y-m-d');
$hasta = resumen_fecha_valida((string)($_GET['hasta'] ?? '')) ??
    $inicioTrimestre->modify('+3 months -1 day')->format('Y-m-d');
$empresa = trim((string)($_GET['empresa'] ?? ''));
$soloEmitidas = ($_GET['estado'] ?? '') === 'emitidas';
$errores = [];
if ($desde > $hasta) {
    $errores[] = t('La fecha inicial es posterior a la final.');
}

$empresas = empresas_listar($pdo);
$codigosEmpresa = array_map(static fn(array $e): string => (string)$e['CODIGO_EMP_EMP'], $empresas);
if ($empresa !== '' && !in_array($empresa, $codigosEmpresa, true)) {
    $empresa = '';
}

$facturas = [];
if ($errores === []) {
    $facturas = facturas_entre_fechas($pdo, $desde, $hasta, $empresa);
    if ($soloEmitidas) {
        $facturas = array_values(array_filter($facturas, 'resumen_factura_emitida'));
    }
}

$filtros = ['desde' => $desde, 'hasta' => $hasta, 'empresa' => $empresa, 'estado' => $soloEmitidas ? 'emitidas' : 'todas'];

/* ----- Descarga CSV ----- */

if (($_GET['formato'] ?? '') === 'csv' && $errores === []) {
    $datosEmpresa = [];
    $formasPago = [];
    $cabecera = [
        t('Fecha'), t('Serie'), t('Número'), t('Factura'), t('Tipo'), t('Estado'),
        t('NIF emisor'), t('Emisor'), t('Código cliente'), t('NIF cliente'), t('Cliente'),
        t('Código postal'), t('Población'), t('País'),
    ];
    foreach (['N', 'R', 'S'] as $tramo) {
        $nombre = t(RESUMEN_TRAMOS_IVA[$tramo]);
        $cabecera[] = t('Base IVA {tramo}', ['tramo' => $nombre]);
        $cabecera[] = t('% IVA {tramo}', ['tramo' => $nombre]);
        $cabecera[] = t('Cuota IVA {tramo}', ['tramo' => $nombre]);
    }
    array_push(
        $cabecera,
        t('Base exenta'), t('Recargo de equivalencia'), t('Total bases'), t('Total impuestos'),
        t('% retención'), t('Retención'), t('Total factura'), t('Forma de pago'), t('Factura relacionada')
    );

    $salida = fopen('php://temp', 'w+b');
    fwrite($salida, "\xEF\xBB\xBF");
    fputcsv($salida, $cabecera, ';', '"', '', "\r\n");
    foreach ($facturas as $factura) {
        $codigoEmpresa = (string)$factura['CODIGO_EMP_FAC'];
        $datosEmpresa[$codigoEmpresa] ??= empresa_por_codigo($pdo, $codigoEmpresa);
        $codigoPago = (string)$factura['FORMA_PAGO_FAC'];
        if ($codigoPago !== '' && !isset($formasPago[$codigoPago])) {
            $formasPago[$codigoPago] = (string)forma_pago_leer($pdo, $codigoPago)['descripcion'];
        }
        $tipo = trim((string)$factura['TIPO_FAC']);
        $tipoVerifactu = trim((string)$factura['TIPO_FACTURA_VERIFACTU_FAC']);
        $relacionada = trim((string)$factura['SERIE_FAC_ABONO_FAC']) !== '' || trim((string)$factura['NUMERO_FAC_ABONO_FAC']) !== ''
            ? numero_documento_formateado($datosEmpresa[$codigoEmpresa], (string)$factura['SERIE_FAC_ABONO_FAC'], (string)$factura['NUMERO_FAC_ABONO_FAC'])
            : '';
        $fila = [
            fecha_es((string)$factura['FECHA_FAC']),
            resumen_texto_csv((string)$factura['SERIE_FAC']),
            resumen_texto_csv((string)$factura['NUMERO_FAC']),
            resumen_texto_csv(numero_documento_formateado($datosEmpresa[$codigoEmpresa], (string)$factura['SERIE_FAC'], (string)$factura['NUMERO_FAC'])),
            resumen_texto_csv($tipo . ($tipoVerifactu !== '' ? ' (' . $tipoVerifactu . ')' : '')),
            resumen_texto_csv(fase_factura_texto($factura)),
            resumen_texto_csv((string)$factura['NIF_EMPRESA_FAC']),
            resumen_texto_csv((string)$factura['RAZON_SOCIAL_EMPRESA_FAC']),
            resumen_texto_csv((string)$factura['CODIGO_CLI_FAC']),
            resumen_texto_csv((string)$factura['NIF_CLIENTE_FAC']),
            resumen_texto_csv((string)$factura['RAZON_SOCIAL_CLIENTE_FAC']),
            resumen_texto_csv((string)$factura['CODIGO_POSTAL_CLIENTE_FAC']),
            resumen_texto_csv((string)$factura['POBLACION_CLIENTE_FAC']),
            resumen_texto_csv((string)$factura['NOMBRE_PAI_CLIENTE_FAC']),
        ];
        foreach (['N', 'R', 'S'] as $tramo) {
            $base = (float)$factura['TOTAL_BASEI_IVA' . $tramo . '_FAC'];
            $cuota = (float)$factura['TOTAL_IVA' . $tramo . '_FAC'];
            $fila[] = resumen_numero_csv($base);
            /* El porcentaje solo donde hay base: evita tipos "fantasma" en facturas que no los usan. */
            $fila[] = $base != 0.0 || $cuota != 0.0 ? resumen_numero_csv((float)$factura['PORCENTAJE_IVA' . $tramo . '_FAC']) : '';
            $fila[] = resumen_numero_csv($cuota);
        }
        $recargo = (float)$factura['TOTAL_REN_FAC'] + (float)$factura['TOTAL_RER_FAC'] +
            (float)$factura['TOTAL_RES_FAC'] + (float)$factura['TOTAL_REE_FAC'];
        $retencion = (float)$factura['TOTAL_RETENCION_FAC'];
        array_push(
            $fila,
            resumen_numero_csv((float)$factura['TOTAL_BASEI_IVAE_FAC']),
            resumen_numero_csv($recargo),
            resumen_numero_csv((float)$factura['TOTAL_BASES_FAC']),
            resumen_numero_csv((float)$factura['TOTAL_IMPUESTOS_FAC']),
            $retencion != 0.0 ? resumen_numero_csv((float)$factura['PORCENTAJE_RETENCION_FAC']) : '',
            resumen_numero_csv($retencion),
            resumen_numero_csv((float)$factura['TOTAL_LIQUIDO_FAC']),
            resumen_texto_csv($codigoPago !== '' ? ($formasPago[$codigoPago] !== '' ? $formasPago[$codigoPago] : $codigoPago) : ''),
            resumen_texto_csv($relacionada)
        );
        fputcsv($salida, $fila, ';', '"', '', "\r\n");
    }
    rewind($salida);
    $contenido = (string)stream_get_contents($salida);
    fclose($salida);

    $nombreFichero = 'facturas_' . $desde . '_' . $hasta .
        ($empresa !== '' ? '_' . preg_replace('/[^A-Za-z0-9_-]+/', '_', $empresa) : '') . '.csv';
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Length: ' . strlen($contenido));
    header('Content-Disposition: attachment; filename="' . $nombreFichero . '"');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    echo $contenido;
    exit;
}

/* ----- Totales en pantalla ----- */

$porTipo = [];
$totales = ['bases' => 0.0, 'impuestos' => 0.0, 'retencion' => 0.0, 'liquido' => 0.0];
$borradores = 0;
foreach ($facturas as $factura) {
    if (factura_editable($factura)) {
        $borradores++;
    }
    foreach (RESUMEN_TRAMOS_IVA as $tramo => $nombre) {
        $base = (float)$factura['TOTAL_BASEI_IVA' . $tramo . '_FAC'];
        $cuota = (float)$factura['TOTAL_IVA' . $tramo . '_FAC'];
        $recargo = (float)$factura['TOTAL_RE' . $tramo . '_FAC'];
        if ($base == 0.0 && $cuota == 0.0 && $recargo == 0.0) {
            continue;
        }
        $porcentaje = $tramo === 'E' ? 0.0 : round((float)$factura['PORCENTAJE_IVA' . $tramo . '_FAC'], 2);
        $clave = number_format($porcentaje, 2, '.', '');
        $porTipo[$clave] ??= ['porcentaje' => $porcentaje, 'base' => 0.0, 'cuota' => 0.0, 'recargo' => 0.0];
        $porTipo[$clave]['base'] += $base;
        $porTipo[$clave]['cuota'] += $cuota;
        $porTipo[$clave]['recargo'] += $recargo;
    }
    $totales['bases'] += (float)$factura['TOTAL_BASES_FAC'];
    $totales['impuestos'] += (float)$factura['TOTAL_IMPUESTOS_FAC'];
    $totales['retencion'] += (float)$factura['TOTAL_RETENCION_FAC'];
    $totales['liquido'] += (float)$factura['TOTAL_LIQUIDO_FAC'];
}
krsort($porTipo, SORT_NUMERIC);
$hayRecargo = array_filter($porTipo, static fn(array $t): bool => $t['recargo'] != 0.0) !== [];

/* Accesos rápidos: los cuatro trimestres y el año de la fecha inicial. */
$anio = (int)substr($desde, 0, 4);
$periodos = [];
for ($t = 1; $t <= 4; $t++) {
    $inicio = sprintf('%04d-%02d-01', $anio, ($t - 1) * 3 + 1);
    $periodos[] = [t('{n}T', ['n' => $t]), $inicio, (new DateTimeImmutable($inicio))->modify('+3 months -1 day')->format('Y-m-d')];
}
$periodos[] = [(string)$anio, $anio . '-01-01', $anio . '-12-31'];

ob_start();
?>
<p class="filtros">
  <a href="<?= h(url('resumen_facturas', ['desde' => ($anio - 1) . '-01-01', 'hasta' => ($anio - 1) . '-12-31'] + $filtros)) ?>"
     title="<?= h(t('Año anterior')) ?>">‹</a>
  <?php foreach ($periodos as [$texto, $inicio, $fin]): ?>
  <a href="<?= h(url('resumen_facturas', ['desde' => $inicio, 'hasta' => $fin] + $filtros)) ?>"
     class="<?= $inicio === $desde && $fin === $hasta ? 'activo' : '' ?>"><?= h($texto) ?></a>
  <?php endforeach; ?>
  <a href="<?= h(url('resumen_facturas', ['desde' => ($anio + 1) . '-01-01', 'hasta' => ($anio + 1) . '-12-31'] + $filtros)) ?>"
     title="<?= h(t('Año siguiente')) ?>">›</a>
</p>
<form method="get" action="index.php" class="formulario">
  <input type="hidden" name="p" value="resumen_facturas">
  <div class="fila-dos">
    <?= campo_texto('desde', t('Desde'), $desde, ['type' => 'date', 'required' => 'required']) ?>
    <?= campo_texto('hasta', t('Hasta'), $hasta, ['type' => 'date', 'required' => 'required']) ?>
  </div>
  <?php if (count($empresas) > 1): ?>
  <label class="campo"><span><?= h(t('Empresa emisora')) ?></span>
    <select name="empresa">
      <option value=""><?= h(t('— Todas las empresas —')) ?></option>
      <?php foreach ($empresas as $fila): ?>
      <option value="<?= h((string)$fila['CODIGO_EMP_EMP']) ?>"<?= (string)$fila['CODIGO_EMP_EMP'] === $empresa ? ' selected' : '' ?>>
        <?= h((string)$fila['RAZON_SOCIAL_EMP']) ?></option>
      <?php endforeach; ?>
    </select>
  </label>
  <?php endif; ?>
  <label class="campo"><span><?= h(t('Facturas')) ?></span>
    <select name="estado"><?= opciones_select([
        'todas' => t('Todas, también los borradores'),
        'emitidas' => t('Solo emitidas (sin borradores ni anuladas)'),
    ], $filtros['estado']) ?></select>
  </label>
  <button type="submit" class="boton secundario"><?= h(t('Ver resumen')) ?></button>
</form>

<?php if ($errores === []): ?>
<section class="tarjeta totales">
  <h2><?= h(t('Del {desde} al {hasta}', ['desde' => fecha_es($desde), 'hasta' => fecha_es($hasta)])) ?></h2>
  <?php if ($facturas === []): ?>
  <p class="nota"><?= h(t('No hay facturas en esas fechas.')) ?></p>
  <?php else: ?>
  <p class="ayuda"><?= h(t('{n} factura(s)', ['n' => count($facturas)])) ?><?= $borradores > 0
      ? ' · ' . h(t('{n} en borrador (sin emitir)', ['n' => $borradores])) : '' ?></p>
  <div class="tabla-envoltorio"><table class="tabla">
    <thead><tr>
      <th><?= h(t('IVA')) ?></th><th class="num"><?= h(t('Base')) ?></th><th class="num"><?= h(t('Cuota')) ?></th>
      <?php if ($hayRecargo): ?><th class="num"><?= h(t('Recargo')) ?></th><?php endif; ?>
    </tr></thead>
    <tbody>
    <?php foreach ($porTipo as $tipo): ?>
      <tr>
        <td><?= h(formatear_porcentaje((string)$tipo['porcentaje'])) ?> %</td>
        <td class="num"><?= h(formatear_importe($tipo['base'])) ?></td>
        <td class="num"><?= h(formatear_importe($tipo['cuota'])) ?></td>
        <?php if ($hayRecargo): ?><td class="num"><?= h(formatear_importe($tipo['recargo'])) ?></td><?php endif; ?>
      </tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
  <dl class="ficha">
    <dt><?= h(t('Total bases')) ?></dt><dd><?= h(formatear_importe($totales['bases'])) ?></dd>
    <dt><?= h(t('Total impuestos')) ?></dt><dd><?= h(formatear_importe($totales['impuestos'])) ?></dd>
    <?php if ($totales['retencion'] != 0.0): ?>
    <dt><?= h(t('Retención')) ?></dt><dd><?= h(formatear_importe($totales['retencion'])) ?></dd>
    <?php endif; ?>
    <dt><?= h(t('Total facturado')) ?></dt><dd class="total-final"><?= h(formatear_importe($totales['liquido'])) ?></dd>
  </dl>
  <a class="boton principal" href="<?= h(url('resumen_facturas', $filtros + ['formato' => 'csv'])) ?>"><?= h(t('Descargar para Excel (CSV)')) ?></a>
  <p class="ayuda"><?= h(t('Una fila por factura con fecha, número, cliente, bases y cuotas por tipo de IVA, recargo, retención y total. Se abre con doble clic en Excel (separador punto y coma y coma decimal).')) ?></p>
  <?php endif; ?>
</section>
<?php endif; ?>
<p class="pie-enlaces"><a href="<?= h(url('menu')) ?>"><?= h(t('‹ Volver al menú')) ?></a></p>
<?php
pagina(t('Resumen de facturas'), (string)ob_get_clean(), ['errores' => $errores]);
