<?php
declare(strict_types=1);

/*
 * Paso 2: datos de la empresa emisora. Se muestran siempre, aunque no
 * cambie nada; al confirmar se graban con PRC_CREAR_ACTUALIZAR_EMPRESA (el
 * mismo procedimiento que usa la factura del programa) solo si hay cambios,
 * o se crea la empresa con el siguiente código del contador EM.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$borrador = exigir_paso('empresa_datos');

$pendiente = $borrador['empresa_pendiente'];
if (!is_array($pendiente)) {
    $pendiente = [
        'codigo' => (string)$borrador['empresa']['CODIGO_EMP_EMP'],
        'nif'    => (string)$borrador['empresa']['NIF_EMP'],
    ];
}
$codigo = (string)$pendiente['codigo'];
$original = $codigo !== '' ? empresa_por_codigo($pdo, $codigo) : null;
if ($codigo !== '' && $original === null) {
    aviso('error', t('La empresa elegida ya no existe.'));
    redirigir('empresa');
}
$esNueva = $original === null;

$paises = paises_listar($pdo);
$grupos = grupos_iva_listar($pdo);
$defectos = valores_defecto($pdo, 'fza_empresas');
$grupoDefecto = '';
foreach ($grupos as $grupo) {
    if (es_si($grupo['ESDEFAULT_IVA_IVAGRP'])) {
        $grupoDefecto = (string)$grupo['IVA_IVAGRP'];
        break;
    }
}

const CAMPOS_EMPRESA = [
    'RAZON_SOCIAL_EMP', 'NIF_EMP', 'MOVIL_EMP', 'EMAIL_EMP', 'DIRECCION1_EMP',
    'DIRECCION2_EMP', 'POBLACION_EMP', 'PROVINCIA_EMP', 'CODIGO_POSTAL_EMP',
    'NOMBRE_PAI_EMP', 'CODIGO_PAI_EMP', 'ESRETENCIONES_EMP',
    'ESREGIMENESPECIALAGRICOLA_EMP', 'GRUPO_ZONA_IVA_EMP',
];

$datos = $original ?? [
    'CODIGO_EMP_EMP'                => '',
    'RAZON_SOCIAL_EMP'              => '',
    'NIF_EMP'                       => (string)$pendiente['nif'],
    'MOVIL_EMP'                     => '',
    'EMAIL_EMP'                     => '',
    'DIRECCION1_EMP'                => '',
    'DIRECCION2_EMP'                => '',
    'POBLACION_EMP'                 => '',
    'PROVINCIA_EMP'                 => '',
    'CODIGO_POSTAL_EMP'             => '',
    'CODIGO_PAI_EMP'                => 'ES',
    'NOMBRE_PAI_EMP'                => 'España',
    'GRUPO_ZONA_IVA_EMP'            => $grupoDefecto,
    'ESRETENCIONES_EMP'             => $defectos['ESRETENCIONES_EMP'] ?? 'N',
    'ESREGIMENESPECIALAGRICOLA_EMP' => $defectos['ESREGIMENESPECIALAGRICOLA_EMP'] ?? 'N',
    'IBAN_EMP'                      => '',
    'SERIE_CON_EMP'                 => '',
];
foreach (CAMPOS_EMPRESA as $campo) {
    $datos[$campo] = trim((string)($datos[$campo] ?? ''));
}
$errores = [];

if (es_post()) {
    comprobar_csrf();
    foreach (['RAZON_SOCIAL_EMP', 'NIF_EMP', 'MOVIL_EMP', 'EMAIL_EMP', 'DIRECCION1_EMP',
              'DIRECCION2_EMP', 'POBLACION_EMP', 'PROVINCIA_EMP', 'CODIGO_POSTAL_EMP',
              'GRUPO_ZONA_IVA_EMP'] as $campo) {
        $datos[$campo] = campo($campo);
    }
    $datos['NIF_EMP'] = strtoupper($datos['NIF_EMP']);
    $datos['ESRETENCIONES_EMP'] = campo_sn('ESRETENCIONES_EMP');
    $datos['ESREGIMENESPECIALAGRICOLA_EMP'] = campo_sn('ESREGIMENESPECIALAGRICOLA_EMP');

    $paisElegido = pais_resolver($paises, campo('PAIS'));
    $paisOriginal = pais_resolver($paises, (string)($original['CODIGO_PAI_EMP'] ?? ''));
    if ($paisElegido !== null) {
        $mismoPais = $paisOriginal !== null &&
            $paisOriginal['CODIGO_PAI_PAI'] === $paisElegido['CODIGO_PAI_PAI'];
        $datos['CODIGO_PAI_EMP'] = $mismoPais
            ? (string)$original['CODIGO_PAI_EMP']
            : (string)$paisElegido['CODIGO_PAI_PAI'];
        $datos['NOMBRE_PAI_EMP'] = $mismoPais
            ? (string)$original['NOMBRE_PAI_EMP']
            : (string)$paisElegido['NOMBRE_SPA_PAI'];
    }

    if ($datos['RAZON_SOCIAL_EMP'] === '') {
        $errores[] = t('La razón social es obligatoria.');
    }
    if ($datos['NIF_EMP'] === '') {
        $errores[] = t('El NIF es obligatorio.');
    }
    if ($datos['EMAIL_EMP'] !== '' && filter_var($datos['EMAIL_EMP'], FILTER_VALIDATE_EMAIL) === false) {
        $errores[] = t('El correo electrónico no es válido.');
    }
    if ($datos['GRUPO_ZONA_IVA_EMP'] === '') {
        $errores[] = t('Elige la zona de IVA de la empresa.');
    }

    if ($errores === []) {
        $nombreUsuario = (string)$usuario['usuario'];
        if ($esNueva) {
            $codigo = contador_siguiente($pdo, 'EM', $nombreUsuario);
            $datos['CODIGO_EMP_EMP'] = $codigo;
            empresa_guardar($pdo, $datos, $nombreUsuario);
            aviso('ok', t('Empresa creada con el código {codigo}.', ['codigo' => $codigo]));
        } else {
            $hayCambios = false;
            foreach (CAMPOS_EMPRESA as $campo) {
                if ($datos[$campo] !== trim((string)($original[$campo] ?? ''))) {
                    $hayCambios = true;
                    break;
                }
            }
            if ($hayCambios) {
                empresa_guardar($pdo, $datos, $nombreUsuario);
                aviso('ok', t('Datos de la empresa actualizados.'));
            } else {
                aviso('ok', t('Empresa confirmada sin cambios.'));
            }
        }
        $fila = empresa_por_codigo($pdo, $codigo);
        if ($fila === null) {
            throw new RuntimeException(t('No se ha podido releer la empresa {codigo}.', ['codigo' => $codigo]));
        }
        $empresaAnterior = is_array($borrador['empresa'])
            ? (string)$borrador['empresa']['CODIGO_EMP_EMP']
            : '';
        $borrador['empresa'] = $fila;
        $borrador['empresa_pendiente'] = null;
        if ($empresaAnterior !== $codigo) {
            /* Otra empresa: la serie y el número se proponen de nuevo. */
            $borrador['serie'] = '';
            $borrador['numero'] = '0';
        }
        borrador_guardar($borrador);
        redirigir('cabecera');
    }
}

$opcionesPais = [];
$paisActual = pais_resolver($paises, $datos['CODIGO_PAI_EMP']);
foreach ($paises as $pais) {
    $opcionesPais[(string)$pais['CODIGO_PAI_PAI']] = (string)$pais['NOMBRE_SPA_PAI'];
}
$opcionesGrupo = [];
foreach ($grupos as $grupo) {
    $opcionesGrupo[(string)$grupo['IVA_IVAGRP']] = $grupo['DESCRIPCION_IVA_IVAGRP'] .
        ' (' . $grupo['PALABRA_REPORTS_IVA_IVAGRP'] . ')';
}

ob_start();
?>
<?php if ($esNueva): ?>
<p class="nota"><?= t('Empresa <strong>nueva</strong>: al confirmar se creará con el siguiente código del contador de empresas.') ?></p>
<?php else: ?>
<p class="nota"><?= t('Código <strong>{codigo}</strong>. Revisa los datos, corrige lo que haga falta y confirma.', ['codigo' => h($codigo)]) ?></p>
<?php endif; ?>
<form method="post" action="<?= h(url('empresa_datos')) ?>" class="formulario">
  <?= campo_csrf() ?>
  <h2><?= h(t('Datos fiscales')) ?></h2>
  <?= campo_texto('RAZON_SOCIAL_EMP', t('Razón social'), $datos['RAZON_SOCIAL_EMP'], ['required' => 'required', 'maxlength' => '200', 'autocapitalize' => 'characters']) ?>
  <?= campo_texto('NIF_EMP', t('NIF'), $datos['NIF_EMP'], ['required' => 'required', 'maxlength' => '50', 'autocapitalize' => 'characters', 'autocorrect' => 'off']) ?>
  <?= campo_texto('DIRECCION1_EMP', t('Dirección'), $datos['DIRECCION1_EMP'], ['maxlength' => '200', 'autocomplete' => 'street-address']) ?>
  <?= campo_texto('DIRECCION2_EMP', t('Dirección (2ª línea)'), $datos['DIRECCION2_EMP'], ['maxlength' => '200']) ?>
  <?= campo_texto('CODIGO_POSTAL_EMP', t('Código postal'), $datos['CODIGO_POSTAL_EMP'], ['maxlength' => '15', 'inputmode' => 'numeric', 'autocomplete' => 'postal-code']) ?>
  <?= campo_texto('POBLACION_EMP', t('Población'), $datos['POBLACION_EMP'], ['maxlength' => '200']) ?>
  <?= campo_texto('PROVINCIA_EMP', t('Provincia'), $datos['PROVINCIA_EMP'], ['maxlength' => '200']) ?>
  <label class="campo"><span><?= h(t('País')) ?></span>
    <select name="PAIS"><?= opciones_select($opcionesPais, (string)($paisActual['CODIGO_PAI_PAI'] ?? '')) ?></select>
  </label>
  <h2><?= h(t('Contacto')) ?></h2>
  <?= campo_texto('MOVIL_EMP', t('Móvil'), $datos['MOVIL_EMP'], ['type' => 'tel', 'maxlength' => '40', 'autocomplete' => 'tel']) ?>
  <?= campo_texto('EMAIL_EMP', t('Correo electrónico'), $datos['EMAIL_EMP'], ['type' => 'email', 'maxlength' => '200', 'autocomplete' => 'email', 'autocapitalize' => 'none']) ?>
  <h2><?= h(t('Fiscalidad')) ?></h2>
  <label class="campo"><span><?= h(t('Zona de IVA')) ?></span>
    <select name="GRUPO_ZONA_IVA_EMP"><?= opciones_select($opcionesGrupo, $datos['GRUPO_ZONA_IVA_EMP']) ?></select>
  </label>
  <?= casilla('ESRETENCIONES_EMP', t('Aplica retención de IRPF en sus facturas'), $datos['ESRETENCIONES_EMP'], t('Autónomo o profesional: el porcentaje se toma de empresas → retenciones.')) ?>
  <?= casilla('ESREGIMENESPECIALAGRICOLA_EMP', t('Régimen especial agrario (REAGP)'), $datos['ESREGIMENESPECIALAGRICOLA_EMP']) ?>
  <?php if (!$esNueva): ?>
  <h2><?= h(t('Otros datos (solo lectura)')) ?></h2>
  <dl class="ficha">
    <dt>IBAN</dt><dd><?= h($datos['IBAN_EMP'] === '' ? '—' : $datos['IBAN_EMP']) ?></dd>
    <dt><?= h(t('Serie por defecto')) ?></dt><dd><?= h($datos['SERIE_CON_EMP'] === '' ? '—' : $datos['SERIE_CON_EMP']) ?></dd>
  </dl>
  <?php endif; ?>
  <button type="submit" class="boton principal"><?= h($esNueva ? t('Crear empresa y continuar') : t('Confirmar y continuar')) ?></button>
</form>
<p class="pie-enlaces"><a href="<?= h(url('empresa')) ?>"><?= h(t('‹ Cambiar de empresa')) ?></a></p>
<?php
pagina(
    $esNueva ? t('Nueva empresa') : t('Datos de la empresa'),
    (string)ob_get_clean(),
    ['paso' => 'empresa_datos', 'errores' => $errores]
);
