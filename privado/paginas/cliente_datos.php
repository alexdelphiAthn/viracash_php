<?php
declare(strict_types=1);

/*
 * Paso 5: datos del cliente. Primero los fiscales y después las
 * condiciones de facturación: retención de IRPF, tarifa (con o sin IVA
 * incluido; un cliente nuevo nace con VENTA MAYOR, precios sin IVA), forma
 * de pago y régimen de IVA. Al confirmar se graba con
 * PRC_CREAR_ACTUALIZAR_CLIENTE; un cliente nuevo recibe el siguiente código
 * del contador CL, como en el programa.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = exigir_paso('cliente_datos');

$pendiente = $borrador['cliente_pendiente'];
if (!is_array($pendiente)) {
    $pendiente = [
        'codigo' => (string)$borrador['cliente']['CODIGO_CLI_CLI'],
        'nif'    => (string)$borrador['cliente']['NIF_CLI'],
    ];
}
$codigo = (string)$pendiente['codigo'];
$original = $codigo !== '' ? cliente_por_codigo($pdo, $codigo) : null;
if ($codigo !== '' && $original === null) {
    aviso('error', t('El cliente elegido ya no existe.'));
    redirigir('cliente');
}
$esNuevo = $original === null;

$paises = paises_listar($pdo);
$tarifas = tarifas_listar($pdo);
$formasPago = formas_pago_listar($pdo);
$defectos = valores_defecto($pdo, 'fza_clientes');

/* Campos que graba PRC_CREAR_ACTUALIZAR_CLIENTE. */
const CAMPOS_CLIENTE = [
    'RAZON_SOCIAL_CLI', 'NIF_CLI', 'MOVIL_CLI', 'EMAIL_CLI', 'DIRECCION1_CLI',
    'DIRECCION2_CLI', 'POBLACION_CLI', 'PROVINCIA_CLI', 'CODIGO_POSTAL_CLI',
    'CODIGO_PAI_CLI', 'NOMBRE_PAI_CLI', 'ESIVA_EXENTO_CLI', 'ESRETENCIONES_CLI',
    'ESIVA_RECARGO_CLI', 'ESINTRACOMUNITARIO_CLI', 'ESREGIMENESPECIALAGRICOLA_CLI',
    'TARIFA_ARTICULO_CLI',
];

$datos = $original ?? [
    'CODIGO_CLI_CLI'                => '',
    'RAZON_SOCIAL_CLI'              => '',
    'NIF_CLI'                       => (string)$pendiente['nif'],
    'MOVIL_CLI'                     => '',
    'EMAIL_CLI'                     => '',
    'DIRECCION1_CLI'                => '',
    'DIRECCION2_CLI'                => '',
    'POBLACION_CLI'                 => '',
    'PROVINCIA_CLI'                 => '',
    'CODIGO_POSTAL_CLI'             => '',
    'CODIGO_PAI_CLI'                => '724',
    'NOMBRE_PAI_CLI'                => 'España',
    'ESIVA_EXENTO_CLI'              => $defectos['ESIVA_EXENTO_CLI'] ?? 'N',
    'ESRETENCIONES_CLI'             => $defectos['ESRETENCIONES_CLI'] ?? 'N',
    'ESIVA_RECARGO_CLI'             => $defectos['ESIVA_RECARGO_CLI'] ?? 'N',
    'ESINTRACOMUNITARIO_CLI'        => $defectos['ESINTRACOMUNITARIO_CLI'] ?? 'N',
    'ESREGIMENESPECIALAGRICOLA_CLI' => $defectos['ESREGIMENESPECIALAGRICOLA_CLI'] ?? 'N',
    'TARIFA_ARTICULO_CLI'           => tarifa_nuevo_cliente($pdo, $usuario),
    'CODIGO_FP_CLI'                 => forma_pago_defecto($pdo),
    'IBAN_CLI'                      => '',
    'SERIE_CON_CLI'                 => '',
];
foreach (array_merge(CAMPOS_CLIENTE, ['CODIGO_FP_CLI']) as $campo) {
    $datos[$campo] = trim((string)($datos[$campo] ?? ''));
}
$errores = [];

if (es_post()) {
    comprobar_csrf();
    foreach (['RAZON_SOCIAL_CLI', 'NIF_CLI', 'MOVIL_CLI', 'EMAIL_CLI', 'DIRECCION1_CLI',
              'DIRECCION2_CLI', 'POBLACION_CLI', 'PROVINCIA_CLI', 'CODIGO_POSTAL_CLI',
              'TARIFA_ARTICULO_CLI', 'CODIGO_FP_CLI'] as $campo) {
        $datos[$campo] = campo($campo);
    }
    $datos['NIF_CLI'] = strtoupper($datos['NIF_CLI']);
    foreach (['ESRETENCIONES_CLI', 'ESIVA_EXENTO_CLI', 'ESIVA_RECARGO_CLI',
              'ESINTRACOMUNITARIO_CLI', 'ESREGIMENESPECIALAGRICOLA_CLI'] as $campo) {
        $datos[$campo] = campo_sn($campo);
    }

    $paisElegido = pais_resolver($paises, campo('PAIS'));
    $paisOriginal = pais_resolver($paises, (string)($original['CODIGO_PAI_CLI'] ?? ''));
    if ($paisElegido !== null) {
        $mismoPais = $paisOriginal !== null &&
            $paisOriginal['CODIGO_PAI_PAI'] === $paisElegido['CODIGO_PAI_PAI'];
        $datos['CODIGO_PAI_CLI'] = $mismoPais
            ? (string)$original['CODIGO_PAI_CLI']
            : (string)$paisElegido['CODIGO_PAI_PAI'];
        $datos['NOMBRE_PAI_CLI'] = $mismoPais
            ? (string)$original['NOMBRE_PAI_CLI']
            : (string)$paisElegido['NOMBRE_SPA_PAI'];
    }

    if ($datos['RAZON_SOCIAL_CLI'] === '') {
        $errores[] = t('El nombre o razón social es obligatorio.');
    }
    if ($datos['NIF_CLI'] === '') {
        $errores[] = t('El DNI/NIF es obligatorio.');
    }
    if ($datos['EMAIL_CLI'] !== '' && filter_var($datos['EMAIL_CLI'], FILTER_VALIDATE_EMAIL) === false) {
        $errores[] = t('El correo electrónico no es válido.');
    }
    $tarifaOriginal = trim((string)($original['TARIFA_ARTICULO_CLI'] ?? ''));
    if ($datos['TARIFA_ARTICULO_CLI'] !== '' &&
        $datos['TARIFA_ARTICULO_CLI'] !== $tarifaOriginal &&
        tarifa_por_codigo($tarifas, $datos['TARIFA_ARTICULO_CLI']) === null) {
        $errores[] = t('La tarifa elegida no existe.');
    }

    if ($errores === []) {
        $nombreUsuario = (string)$usuario['usuario'];
        if ($esNuevo) {
            $codigo = contador_siguiente($pdo, 'CL', $nombreUsuario);
            $datos['CODIGO_CLI_CLI'] = $codigo;
            cliente_guardar($pdo, $datos, $nombreUsuario, $datos['CODIGO_FP_CLI'] !== '');
            aviso('ok', t('Cliente creado con el código {codigo}.', ['codigo' => $codigo]));
        } else {
            $hayCambios = false;
            foreach (CAMPOS_CLIENTE as $campo) {
                if ($datos[$campo] !== trim((string)($original[$campo] ?? ''))) {
                    $hayCambios = true;
                    break;
                }
            }
            $cambiaFormaPago = $datos['CODIGO_FP_CLI'] !== trim((string)($original['CODIGO_FP_CLI'] ?? ''));
            if ($hayCambios || $cambiaFormaPago) {
                cliente_guardar($pdo, $datos, $nombreUsuario, $cambiaFormaPago);
                aviso('ok', t('Datos del cliente actualizados.'));
            } else {
                aviso('ok', t('Cliente confirmado sin cambios.'));
            }
        }
        $fila = cliente_por_codigo($pdo, $codigo);
        if ($fila === null) {
            throw new RuntimeException(t('No se ha podido releer el cliente {codigo}.', ['codigo' => $codigo]));
        }
        $borrador['cliente'] = $fila;
        $borrador['cliente_pendiente'] = null;
        borrador_guardar($borrador);
        redirigir('lineas');
    }
}

$opcionesPais = [];
$paisActual = pais_resolver($paises, $datos['CODIGO_PAI_CLI']);
foreach ($paises as $pais) {
    $opcionesPais[(string)$pais['CODIGO_PAI_PAI']] = (string)$pais['NOMBRE_SPA_PAI'];
}
$opcionesTarifa = ['' => t('— Tarifa por defecto —')];
foreach ($tarifas as $tarifa) {
    $opcionesTarifa[(string)$tarifa['CODIGO_TAR_ARTTAR']] = $tarifa['NOMBRE_TAR_TAR'] . ' · ' .
        (es_si($tarifa['ESIMP_INCL_TAR']) ? t('precios con IVA incluido') : t('precios sin IVA'));
}
/* Un valor antiguo que ya no existe se conserva tal cual salvo que se cambie. */
if ($datos['TARIFA_ARTICULO_CLI'] !== '' && !isset($opcionesTarifa[$datos['TARIFA_ARTICULO_CLI']])) {
    $opcionesTarifa[$datos['TARIFA_ARTICULO_CLI']] = $datos['TARIFA_ARTICULO_CLI'] . ' · ' . t('tarifa no definida');
}
$opcionesFormaPago = ['' => t('— Sin forma de pago fija —')];
foreach ($formasPago as $formaPago) {
    $opcionesFormaPago[(string)$formaPago['CODIGO_FP_FP']] = (string)$formaPago['DESCRIPCION_FORMA_PAGO_FP'];
}
if ($datos['CODIGO_FP_CLI'] !== '' && !isset($opcionesFormaPago[$datos['CODIGO_FP_CLI']])) {
    $opcionesFormaPago[$datos['CODIGO_FP_CLI']] = $datos['CODIGO_FP_CLI'] . ' · ' . t('forma de pago no definida');
}

ob_start();
?>
<?php if ($esNuevo): ?>
<p class="nota"><?= t('Cliente <strong>nuevo</strong>: al confirmar se creará con el siguiente código del contador de clientes.') ?></p>
<?php else: ?>
<p class="nota"><?= t('Código <strong>{codigo}</strong>. Revisa los datos, corrige lo que haga falta y confirma.', ['codigo' => h($codigo)]) ?></p>
<?php endif; ?>
<form method="post" action="<?= h(url('cliente_datos')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <h2><?= h(t('Datos fiscales')) ?></h2>
  <?= campo_texto('RAZON_SOCIAL_CLI', t('Nombre o razón social'), $datos['RAZON_SOCIAL_CLI'], ['required' => 'required', 'maxlength' => '200', 'autocapitalize' => 'characters']) ?>
  <?= campo_texto('NIF_CLI', t('DNI / NIF'), $datos['NIF_CLI'], ['required' => 'required', 'maxlength' => '50', 'autocapitalize' => 'characters', 'autocorrect' => 'off']) ?>
  <?= campo_texto('DIRECCION1_CLI', t('Dirección'), $datos['DIRECCION1_CLI'], ['maxlength' => '200']) ?>
  <?= campo_texto('DIRECCION2_CLI', t('Dirección (2ª línea)'), $datos['DIRECCION2_CLI'], ['maxlength' => '200']) ?>
  <?= campo_texto('CODIGO_POSTAL_CLI', t('Código postal'), $datos['CODIGO_POSTAL_CLI'], ['maxlength' => '15', 'inputmode' => 'numeric']) ?>
  <?= campo_texto('POBLACION_CLI', t('Población'), $datos['POBLACION_CLI'], ['maxlength' => '200']) ?>
  <?= campo_texto('PROVINCIA_CLI', t('Provincia'), $datos['PROVINCIA_CLI'], ['maxlength' => '200']) ?>
  <label class="campo"><span><?= h(t('País')) ?></span>
    <select name="PAIS"><?= opciones_select($opcionesPais, (string)($paisActual['CODIGO_PAI_PAI'] ?? '')) ?></select>
  </label>
  <h2><?= h(t('Contacto')) ?></h2>
  <?= campo_texto('MOVIL_CLI', t('Móvil'), $datos['MOVIL_CLI'], ['type' => 'tel', 'maxlength' => '40']) ?>
  <?= campo_texto('EMAIL_CLI', t('Correo electrónico'), $datos['EMAIL_CLI'], ['type' => 'email', 'maxlength' => '200', 'autocapitalize' => 'none']) ?>
  <h2><?= h(t('Condiciones de facturación')) ?></h2>
  <?= casilla('ESRETENCIONES_CLI', t('Retener IRPF en sus facturas'), $datos['ESRETENCIONES_CLI'], t('Se aplica el porcentaje de retención vigente de la empresa emisora.')) ?>
  <label class="campo"><span><?= h(t('Tarifa de precios')) ?></span>
    <select name="TARIFA_ARTICULO_CLI"><?= opciones_select($opcionesTarifa, $datos['TARIFA_ARTICULO_CLI']) ?></select>
  </label>
  <label class="campo"><span><?= h(t('Forma de pago')) ?></span>
    <select name="CODIGO_FP_CLI"><?= opciones_select($opcionesFormaPago, $datos['CODIGO_FP_CLI']) ?></select>
  </label>
  <h2><?= h(t('Régimen de IVA')) ?></h2>
  <?= casilla('ESIVA_EXENTO_CLI', t('Exento de IVA'), $datos['ESIVA_EXENTO_CLI']) ?>
  <?= casilla('ESIVA_RECARGO_CLI', t('Recargo de equivalencia'), $datos['ESIVA_RECARGO_CLI']) ?>
  <?= casilla('ESINTRACOMUNITARIO_CLI', t('Operador intracomunitario'), $datos['ESINTRACOMUNITARIO_CLI']) ?>
  <?= casilla('ESREGIMENESPECIALAGRICOLA_CLI', t('Régimen especial agrario (REAGP)'), $datos['ESREGIMENESPECIALAGRICOLA_CLI']) ?>
  <button type="submit" class="boton principal"><?= h($esNuevo ? t('Crear cliente y continuar') : t('Confirmar y continuar')) ?></button>
</form>
<p class="pie-enlaces"><a href="<?= h(url('cliente')) ?>"><?= h(t('‹ Buscar otro cliente')) ?></a></p>
<?php
pagina(
    $esNuevo ? t('Nuevo cliente') : t('Datos del cliente'),
    (string)ob_get_clean(),
    ['paso' => 'cliente_datos', 'errores' => $errores]
);
