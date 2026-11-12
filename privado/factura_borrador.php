<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Factura en curso. Los datos de cada pantalla se guardan en la sesión y,
 * al final, la factura se graba en fza_facturas y fza_facturas_lineas
 * exactamente como lo hace el programa al dar de alta una factura de venta
 * mayor:
 *
 *   1. Valores por defecto de fza_valores_defecto (AplicarValoresPorDefecto).
 *   2. Tarifa y forma de pago por defecto, fecha, fase BORRADOR, tipo NORMAL.
 *   3. Copia de los datos de la empresa emisora y de su zona de IVA.
 *   4. Retención de la empresa vigente en la fecha.
 *   5. Copia de los datos fiscales y comerciales del cliente.
 *   6. Número desde el contador de la serie (PRC_GET_NEXT_CONT_FACT_SERIE)
 *      cuando se deja a 0.
 *   7. Líneas numeradas con PRC_FNC_GET_NEXT_LINEA_FACTURA y totales
 *      calculados con las mismas reglas que el programa (facturas_calculo).
 */

const PASOS_FACTURA = [
    'empresa'       => [1, 'Empresa emisora'],
    'empresa_datos' => [2, 'Datos de la empresa'],
    'cabecera'      => [3, 'Fecha y serie'],
    'cliente'       => [4, 'Cliente'],
    'cliente_datos' => [5, 'Datos del cliente'],
    'lineas'        => [6, 'Líneas'],
    'resumen'       => [7, 'Totales'],
];

/* La factura simplificada (ticket) no lleva destinatario: sin pasos 4 y 5. */
const PASOS_FACTURA_SIMPLIFICADA = [
    'empresa'       => [1, 'Empresa emisora'],
    'empresa_datos' => [2, 'Datos de la empresa'],
    'cabecera'      => [3, 'Fecha, serie y pago'],
    'lineas'        => [4, 'Líneas'],
    'resumen'       => [5, 'Totales'],
];

/** Pasos de la factura en curso (los de la simplificada si lo es). */
function pasos_factura(array $borrador): array
{
    return es_simplificada($borrador) ? PASOS_FACTURA_SIMPLIFICADA : PASOS_FACTURA;
}

function borrador(): array
{
    $borrador = $_SESSION['factura'] ?? [];
    if (!is_array($borrador)) {
        $borrador = [];
    }
    $borrador += [
        'fecha'             => date('Y-m-d'),
        'serie'             => '',
        'numero'            => '0',
        'empresa'           => null,
        'empresa_pendiente' => null,
        'cliente'           => null,
        'cliente_pendiente' => null,
        'lineas'            => [],
        'editando'          => null,
        'simplificada'      => false,
        'forma_pago'        => '',
    ];
    if (!is_array($borrador['lineas'])) {
        $borrador['lineas'] = [];
    }
    return $borrador;
}

/** Factura simplificada (ticket, TIPO_FAC = SIMPLIFICADA) sin destinatario. */
function es_simplificada(array $borrador): bool
{
    return !empty($borrador['simplificada']);
}

/** Datos de la factura que se está modificando, o null si es una factura nueva. */
function editando(array $borrador): ?array
{
    return is_array($borrador['editando'] ?? null) ? $borrador['editando'] : null;
}

/**
 * Carga una factura existente (en borrador) en la sesión para modificarla:
 * empresa, cliente, fecha, serie, número y líneas. Lanza excepción si no
 * se puede modificar.
 */
function factura_cargar_en_borrador(PDO $pdo, string $serie, string $numero): array
{
    $factura = factura_leer($pdo, $serie, $numero);
    if ($factura === null) {
        throw new RuntimeException(t('No existe la factura {serie} {numero}.', ['serie' => $serie, 'numero' => $numero]));
    }
    if (!factura_editable($factura)) {
        throw new RuntimeException(t('Solo se pueden modificar facturas en borrador sin consolidar. Esta factura está en fase {fase}.',
            ['fase' => (string)$factura['FASE_FAC']]));
    }
    $empresa = empresa_por_codigo($pdo, (string)$factura['CODIGO_EMP_FAC']);
    if ($empresa === null) {
        throw new RuntimeException(t('La empresa emisora {codigo} ya no existe.', ['codigo' => (string)$factura['CODIGO_EMP_FAC']]));
    }
    $simplificada = strcasecmp(trim((string)$factura['TIPO_FAC']), 'SIMPLIFICADA') === 0;
    $cliente = null;
    if (!$simplificada) {
        $cliente = cliente_por_codigo($pdo, (string)$factura['CODIGO_CLI_FAC']);
        if ($cliente === null) {
            throw new RuntimeException(t('El cliente {codigo} de la factura ya no existe.', ['codigo' => (string)$factura['CODIGO_CLI_FAC']]));
        }
    }
    $lineas = [];
    foreach (factura_lineas($pdo, $serie, $numero) as $linea) {
        $lineas[] = [
            'codigo'        => trim((string)($linea['CODIGO_ART_FACLIN'] ?? '')),
            'descripcion'   => (string)$linea['DESCRIPCION_ARTICULO_FACLIN'],
            'cantidad'      => (float)$linea['CANTIDAD_FACLIN'],
            'unidad'        => (string)$linea['TIPO_CANTIDAD_ARTICULO_FACLIN'],
            'precio'        => (float)$linea['PRECIO_SALIDA_FACLIN'],
            'dto'           => (float)$linea['PORCENTAJE_DTO_FACLIN'],
            'tipo_iva'      => trim((string)$linea['TIPO_IVA_ARTICULO_FACLIN']) ?: 'N',
            'tipo_articulo' => trim((string)($linea['TIPO_ARTICULO_FACLIN'] ?? '')) ?: 'SERVICIO',
            'familia'       => trim((string)($linea['CODIGO_FAM_FACLIN'] ?? '')),
        ];
    }
    $borrador = borrador();
    $borrador['fecha'] = substr((string)$factura['FECHA_FAC'], 0, 10);
    $borrador['serie'] = $serie;
    $borrador['numero'] = $numero;
    $borrador['empresa'] = $empresa;
    $borrador['empresa_pendiente'] = null;
    $borrador['cliente'] = $cliente;
    $borrador['cliente_pendiente'] = null;
    $borrador['simplificada'] = $simplificada;
    $borrador['forma_pago'] = $simplificada ? trim((string)$factura['FORMA_PAGO_FAC']) : '';
    $borrador['lineas'] = $lineas;
    $borrador['editando'] = [
        'serie'             => $serie,
        'numero'            => $numero,
        'numero_formateado' => numero_documento_formateado($empresa, $serie, $numero),
    ];
    borrador_guardar($borrador);
    return $borrador;
}

function borrador_guardar(array $borrador): void
{
    $_SESSION['factura'] = $borrador;
}

function borrador_reiniciar(): void
{
    unset($_SESSION['factura']);
}

/**
 * Comprueba que los pasos anteriores están completos; si no, redirige al
 * que falta. Orden: empresa -> datos empresa -> fecha y serie -> cliente ->
 * datos cliente -> líneas -> totales.
 */
function exigir_paso(string $paso): array
{
    $borrador = borrador();
    $empresaLista = is_array($borrador['empresa']);
    $cabeceraLista = $borrador['serie'] !== '' && $borrador['fecha'] !== '';
    /* La simplificada no tiene destinatario: el paso del cliente no existe. */
    $clienteListo = es_simplificada($borrador) || is_array($borrador['cliente']);
    $hayLineas = $borrador['lineas'] !== [];
    if (es_simplificada($borrador) && in_array($paso, ['cliente', 'cliente_datos'], true)) {
        redirigir($cabeceraLista ? 'lineas' : 'cabecera');
    }
    switch ($paso) {
        case 'empresa_datos':
            if (!is_array($borrador['empresa_pendiente']) && !$empresaLista) {
                redirigir('empresa');
            }
            break;
        case 'cabecera':
            if (!$empresaLista) {
                redirigir('empresa');
            }
            break;
        case 'cliente':
            if (!$empresaLista) {
                redirigir('empresa');
            }
            if (!$cabeceraLista) {
                redirigir('cabecera');
            }
            break;
        case 'cliente_datos':
            if (!$empresaLista) {
                redirigir('empresa');
            }
            if (!$cabeceraLista) {
                redirigir('cabecera');
            }
            if (!is_array($borrador['cliente_pendiente']) && !$clienteListo) {
                redirigir('cliente');
            }
            break;
        case 'lineas':
        case 'resumen':
        case 'crear':
            if (!$empresaLista) {
                redirigir('empresa');
            }
            if (!$cabeceraLista) {
                redirigir('cabecera');
            }
            if (!$clienteListo) {
                redirigir('cliente');
            }
            if ($paso !== 'lineas' && !$hayLineas) {
                aviso('aviso', t('Añade al menos una línea antes de continuar.'));
                redirigir('lineas');
            }
            break;
    }
    return $borrador;
}

function columnas_tabla(PDO $pdo, string $tabla): array
{
    $filas = consultar(
        $pdo,
        'SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS ' .
        'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
        [$tabla]
    );
    $columnas = [];
    foreach ($filas as $fila) {
        $columnas[strtoupper((string)$fila['COLUMN_NAME'])] = true;
    }
    return $columnas;
}

function filtrar_columnas(array $fila, array $columnas): array
{
    foreach (array_keys($fila) as $columna) {
        if (!isset($columnas[$columna])) {
            unset($fila[$columna]);
        }
    }
    return $fila;
}

/** Número decimal como texto SQL (punto decimal, 6 decimales como las columnas). */
function decimal_sql(float $valor): string
{
    return number_format($valor, 6, '.', '');
}

/**
 * Avisos no bloqueantes antes de crear la factura (los mismos que muestra el
 * programa al grabar la cabecera): fecha futura, fecha anterior a la última
 * emitida en la serie y hueco de numeración con número manual.
 */
function factura_avisos(PDO $pdo, array $borrador): array
{
    $avisos = [];
    $empresa = (string)$borrador['empresa']['CODIGO_EMP_EMP'];
    if ($borrador['fecha'] > date('Y-m-d')) {
        $avisos[] = 'La fecha de la factura es posterior a hoy.';
    }
    $ultima = factura_ultima_fecha_serie($pdo, $borrador['serie'], $empresa);
    if ($ultima !== null && $borrador['fecha'] < $ultima) {
        $avisos[] = 'La fecha es anterior a la última factura emitida en la serie ' .
            $borrador['serie'] . ' (' . fecha_es($ultima) . ').';
    }
    if ($borrador['numero'] !== '0' && editando($borrador) === null) {
        $fila = consultar_una(
            $pdo,
            'SELECT MAX(CAST(NUMERO_FAC AS UNSIGNED)) AS MAXNUM FROM fza_facturas ' .
            'WHERE SERIE_FAC = ? AND CODIGO_EMP_FAC = ? ' .
            'AND CAST(NUMERO_FAC AS UNSIGNED) < ?',
            [$borrador['serie'], $empresa, (int)$borrador['numero']]
        );
        $maximo = $fila['MAXNUM'] ?? null;
        if ($maximo !== null && (int)$maximo < (int)$borrador['numero'] - 1) {
            $avisos[] = 'Queda un hueco de numeración en la serie ' .
                $borrador['serie'] . ': la última factura es la ' . $maximo . '.';
        }
        if (factura_existe($pdo, $borrador['numero'], $borrador['serie'])) {
            $avisos[] = 'Ya existe la factura ' . $borrador['serie'] . ' ' .
                $borrador['numero'] . ': cambia el número o déjalo a 0.';
        }
    }
    return $avisos;
}

/** Número que recibirá la factura (ya relleno con los ceros del contador). */
function factura_numero_previsto(PDO $pdo, array $borrador): array
{
    $empresa = (string)$borrador['empresa']['CODIGO_EMP_EMP'];
    if (editando($borrador) !== null) {
        return ['numero' => (string)$borrador['numero'], 'texto' => t('factura existente')];
    }
    if ($borrador['numero'] !== '0') {
        return ['numero' => (string)$borrador['numero'], 'texto' => t('asignado a mano')];
    }
    $previsto = contador_factura_previsto($pdo, $borrador['serie'], $empresa);
    return [
        'numero' => $previsto['numero'],
        'texto' => $previsto['existe']
            ? t('siguiente del contador automático')
            : t('siguiente del contador automático, que se creará al grabar'),
    ];
}

/**
 * Cabecera de la factura tal como se grabará (sin número), construida con
 * las mismas reglas que el alta del programa. Sirve para calcular líneas y
 * totales antes de crearla.
 */
function cabecera_provisional(PDO $pdo, array $usuario, array $borrador): array
{
    $empresa = $borrador['empresa'];
    $cliente = $borrador['cliente'];
    $fecha = (string)$borrador['fecha'];

    /* 1. Valores por defecto configurados en fza_valores_defecto. */
    $fila = valores_defecto($pdo, 'fza_facturas');

    /* 2. Alta de cabecera (unqryTablaGAfterInsert del programa). */
    $tarifas = tarifas_listar($pdo);
    $tarifaDefecto = tarifa_defecto($pdo, $usuario);
    $tarifa = tarifa_por_codigo($tarifas, $tarifaDefecto);
    $fila['TARIFA_ARTICULO_CLIENTE_FAC'] = $tarifaDefecto;
    $fila['ESIMP_INCL_TARIFA_CLIENTE_FAC'] = $tarifa === null ? 'S' : (string)$tarifa['ESIMP_INCL_TAR'];
    $fila['FECHA_FAC'] = $fecha;
    $fila['FORMA_PAGO_FAC'] = forma_pago_defecto($pdo);
    $fila['ESCONSOLIDADA_FAC'] = 'N';
    $fila['FASE_FAC'] = 'BORRADOR';
    $fila['TIPO_FAC'] = 'NORMAL';
    /* Solo se facturan servicios sin stock: la factura no mueve almacén. */
    $fila['ESMUEVE_STOCK_FAC'] = 'N';

    /* 3. Empresa emisora (CopiarEmpresaSeleccionadaFactura). */
    $fila['CODIGO_EMP_FAC'] = (string)$empresa['CODIGO_EMP_EMP'];
    $fila['RAZON_SOCIAL_EMPRESA_FAC'] = (string)$empresa['RAZON_SOCIAL_EMP'];
    $fila['NIF_EMPRESA_FAC'] = (string)$empresa['NIF_EMP'];
    $fila['MOVIL_EMPRESA_FAC'] = (string)$empresa['MOVIL_EMP'];
    $fila['EMAIL_EMPRESA_FAC'] = (string)$empresa['EMAIL_EMP'];
    $fila['DIRECCION1_EMPRESA_FAC'] = (string)$empresa['DIRECCION1_EMP'];
    $fila['DIRECCION2_EMPRESA_FAC'] = (string)$empresa['DIRECCION2_EMP'];
    $fila['POBLACION_EMPRESA_FAC'] = (string)$empresa['POBLACION_EMP'];
    $fila['PROVINCIA_EMPRESA_FAC'] = (string)$empresa['PROVINCIA_EMP'];
    $fila['CODIGO_POSTAL_EMPRESA_FAC'] = (string)$empresa['CODIGO_POSTAL_EMP'];
    $fila['NOMBRE_PAI_EMPRESA_FAC'] = (string)$empresa['NOMBRE_PAI_EMP'];
    $fila['CODIGO_PAI_EMPRESA_FAC'] = (string)$empresa['CODIGO_PAI_EMP'];
    $fila['GRUPO_ZONA_IVA_EMPRESA_FAC'] = (string)$empresa['GRUPO_ZONA_IVA_EMP'];
    $fila['ESRETENCIONES_EMPRESA_FAC'] = (string)$empresa['ESRETENCIONES_EMP'];
    $fila['ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC'] = (string)$empresa['ESREGIMENESPECIALAGRICOLA_EMP'];
    $fila['TEXTO_LEGAL_EMPRESA_FAC'] = (string)$empresa['TEXTO_LEGAL_FACTURA_EMP'];

    /* 4. Zona de IVA de la empresa vigente en la fecha (CargarConfiguracionIvaFactura). */
    $iva = iva_configuracion($pdo, (string)$empresa['GRUPO_ZONA_IVA_EMP'], $fecha);
    if ($iva !== null) {
        $fila['PORCENTAJE_IVAN_FAC'] = (string)$iva['PORCENTAJE_NORMAL_IVA'];
        $fila['PORCENTAJE_REN_FAC'] = (string)$iva['PORCENTAJE_NORMAL_RE_IVA'];
        $fila['PORCENTAJE_IVAR_FAC'] = (string)$iva['PORCENTAJE_REDUCIDO_IVA'];
        $fila['PORCENTAJE_RER_FAC'] = (string)$iva['PORCENTAJE_REDUCIDO_RE_IVA'];
        $fila['PORCENTAJE_IVAS_FAC'] = (string)$iva['PORCENTAJE_SUPERREDUCIDO_IVA'];
        $fila['PORCENTAJE_RES_FAC'] = (string)$iva['PORCENTAJE_SUPERREDUCIDO_RE_IVA'];
        $fila['PORCENTAJE_IVAE_FAC'] = (string)$iva['PORCENTAJE_EXENTO_IVA'];
        $fila['PORCENTAJE_REE_FAC'] = (string)$iva['PORCENTAJE_EXENTO_RE_IVA'];
        $fila['ESIRPF_IMP_INCL_ZONA_IVA_FAC'] = (string)$iva['ESIRPF_IMP_INCL_IVA_IVAGRP'];
        $fila['ESAPLICA_RE_ZONA_IVA_FAC'] = (string)$iva['ESAPLICA_RE_IVA_IVAGRP'];
        $fila['CODIGO_IVA_FAC'] = (string)$iva['CODIGO_IVA'];
        $fila['ESIVAAGRICOLA_ZONA_IVA_FAC'] = (string)$iva['ESIVAAGRICOLA_IVA_IVAGRP'];
        $fila['PALABRA_REPORTS_ZONA_IVA_FAC'] = (string)$iva['PALABRA_REPORTS_IVA_IVAGRP'];
    }

    /* 5. Retención de la empresa (AplicarRetencionEmpresaFactura). */
    $fila['PORCENTAJE_RETENCION_FAC'] = '0';
    if (es_si((string)$empresa['ESRETENCIONES_EMP'])) {
        $retencion = retencion_empresa($pdo, (string)$empresa['CODIGO_EMP_EMP'], $fecha);
        if ($retencion !== null) {
            $fila['PORCENTAJE_RETENCION_FAC'] = $retencion;
        }
    }

    /* 6. Cliente (CopiarClienteSeleccionadoFactura) o, en la factura
       simplificada, venta al contado sin destinatario
       (EscribirCabeceraVentaContado de la caja del programa). */
    if (es_simplificada($borrador)) {
        $fila = cabecera_venta_contado($pdo, $usuario, $borrador, $fila, $tarifas);
    } else {
        $fila['CODIGO_CLI_FAC'] = (string)$cliente['CODIGO_CLI_CLI'];
        $fila['RAZON_SOCIAL_CLIENTE_FAC'] = (string)$cliente['RAZON_SOCIAL_CLI'];
        $fila['NIF_CLIENTE_FAC'] = (string)$cliente['NIF_CLI'];
        $fila['MOVIL_CLIENTE_FAC'] = (string)$cliente['MOVIL_CLI'];
        $fila['EMAIL_CLIENTE_FAC'] = (string)$cliente['EMAIL_CLI'];
        $fila['DIRECCION1_CLIENTE_FAC'] = (string)$cliente['DIRECCION1_CLI'];
        $fila['DIRECCION2_CLIENTE_FAC'] = (string)$cliente['DIRECCION2_CLI'];
        $fila['POBLACION_CLIENTE_FAC'] = (string)$cliente['POBLACION_CLI'];
        $fila['PROVINCIA_CLIENTE_FAC'] = (string)$cliente['PROVINCIA_CLI'];
        $fila['CODIGO_POSTAL_CLIENTE_FAC'] = (string)$cliente['CODIGO_POSTAL_CLI'];
        $fila['NOMBRE_PAI_CLIENTE_FAC'] = (string)$cliente['NOMBRE_PAI_CLI'];
        $fila['CODIGO_PAI_CLIENTE_FAC'] = (string)$cliente['CODIGO_PAI_CLI'];
        $fila['ESIVA_RECARGO_CLIENTE_FAC'] = (string)$cliente['ESIVA_RECARGO_CLI'];
        $fila['ESIVA_EXENTO_CLIENTE_FAC'] = (string)$cliente['ESIVA_EXENTO_CLI'];
        $fila['ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC'] = (string)$cliente['ESREGIMENESPECIALAGRICOLA_CLI'];
        $fila['ESRETENCIONES_CLIENTE_FAC'] = (string)$cliente['ESRETENCIONES_CLI'];
        $fila['ESINTRACOMUNITARIO_CLIENTE_FAC'] = (string)$cliente['ESINTRACOMUNITARIO_CLI'];
        $fila['CODIGO_OFICINA_CONTABLE_FAC'] = (string)$cliente['CODIGO_OFICINA_CONTABLE_CLI'];
        $fila['CODIGO_ORGANO_GESTOR_FAC'] = (string)$cliente['CODIGO_ORGANO_GESTOR_CLI'];
        $fila['CODIGO_UNIDAD_TRAMITADORA_FAC'] = (string)$cliente['CODIGO_UNIDAD_TRAMITADORA_CLI'];
        $fila['NOMBRE_PERSONA_CLIENTE_FAC'] = (string)$cliente['NOMBRE_PERSONA_CLIENTE_CLI'];
        $fila['APELLIDOS_PERSONA_CLIENTE_FAC'] = (string)$cliente['APELLIDOS_PERSONA_CLIENTE_CLI'];
        if (trim((string)$cliente['CODIGO_FP_CLI']) !== '') {
            $fila['FORMA_PAGO_FAC'] = (string)$cliente['CODIGO_FP_CLI'];
        }
        if (trim((string)$cliente['TARIFA_ARTICULO_CLI']) !== '') {
            $fila['TARIFA_ARTICULO_CLIENTE_FAC'] = (string)$cliente['TARIFA_ARTICULO_CLI'];
            $tarifaCliente = tarifa_por_codigo($tarifas, (string)$cliente['TARIFA_ARTICULO_CLI']);
            if ($tarifaCliente !== null) {
                $fila['ESIMP_INCL_TARIFA_CLIENTE_FAC'] = (string)$tarifaCliente['ESIMP_INCL_TAR'];
            }
        }
        if (!es_si((string)$cliente['ESRETENCIONES_CLI'])) {
            $fila['PORCENTAJE_RETENCION_FAC'] = '0';
        }
    }

    /* 7. Serie, textos, totales iniciales y auditoría. */
    $fila['SERIE_FAC'] = (string)$borrador['serie'];
    $fila['TEXTO_LEGAL_CLIENTE_FAC'] = is_array($cliente)
        ? (string)($cliente['TEXTO_LEGAL_FACTURA_CLI'] ?? '') : '';
    $fila['COMENTARIOS_FAC'] = '';
    $fila['TOTAL_BASES_FAC'] = $fila['TOTAL_BASES_FAC'] ?? '0';
    $fila['TOTAL_IMPUESTOS_FAC'] = $fila['TOTAL_IMPUESTOS_FAC'] ?? '0';
    $fila['TOTAL_RETENCION_FAC'] = '0';
    $fila['TOTAL_LIQUIDO_FAC'] = $fila['TOTAL_LIQUIDO_FAC'] ?? '0';
    $fila['CONTADOR_LINEAS_FAC'] = $fila['CONTADOR_LINEAS_FAC'] ?? '0';
    $fila['USUARIO_ALTA'] = (string)$usuario['usuario'];
    $fila['USUARIO_MODIF'] = (string)$usuario['usuario'];
    $fila['INSTANTE_ALTA'] = 'NOW()';
    $fila['INSTANTE_MODIF'] = 'NOW()';
    return $fila;
}

/**
 * Parte de cliente de una factura simplificada: venta al contado, sin
 * destinatario, como EscribirCabeceraVentaContado de la caja del programa.
 * Deja el tipo SIMPLIFICADA, la tarifa por defecto de caja (vgerDefTarifa),
 * la forma de pago elegida en la web, el empleado que atiende
 * (vgerCodEmpleadoDefecto, en CODIGO_CAJERO_FAC) y sin retención: sin NIF de
 * destinatario no hay recargo de equivalencia ni IRPF.
 */
function cabecera_venta_contado(PDO $pdo, array $usuario, array $borrador, array $fila, array $tarifas): array
{
    $fila['TIPO_FAC'] = 'SIMPLIFICADA';
    /* Sin destinatario: los campos de cliente quedan a NULL, como los deja
       la caja del programa con NULLIF(:CLI, '') al grabar el ticket. */
    foreach ([
        'CODIGO_CLI_FAC', 'RAZON_SOCIAL_CLIENTE_FAC', 'NIF_CLIENTE_FAC', 'MOVIL_CLIENTE_FAC',
        'EMAIL_CLIENTE_FAC', 'DIRECCION1_CLIENTE_FAC', 'DIRECCION2_CLIENTE_FAC',
        'POBLACION_CLIENTE_FAC', 'PROVINCIA_CLIENTE_FAC', 'CODIGO_POSTAL_CLIENTE_FAC',
        'NOMBRE_PAI_CLIENTE_FAC', 'CODIGO_PAI_CLIENTE_FAC', 'CODIGO_OFICINA_CONTABLE_FAC',
        'CODIGO_ORGANO_GESTOR_FAC', 'CODIGO_UNIDAD_TRAMITADORA_FAC',
        'NOMBRE_PERSONA_CLIENTE_FAC', 'APELLIDOS_PERSONA_CLIENTE_FAC',
    ] as $campo) {
        $fila[$campo] = null;
    }
    foreach ([
        'ESIVA_RECARGO_CLIENTE_FAC', 'ESIVA_EXENTO_CLIENTE_FAC',
        'ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC', 'ESRETENCIONES_CLIENTE_FAC',
        'ESINTRACOMUNITARIO_CLIENTE_FAC',
    ] as $campo) {
        $fila[$campo] = 'N';
    }
    $fila['PORCENTAJE_RETENCION_FAC'] = '0';
    $tarifa = tarifa_por_codigo($tarifas, (string)$fila['TARIFA_ARTICULO_CLIENTE_FAC']);
    $fila['ESIMP_INCL_TARIFA_CLIENTE_FAC'] = $tarifa === null ? 'S' : (string)$tarifa['ESIMP_INCL_TAR'];
    $formaPago = trim((string)($borrador['forma_pago'] ?? ''));
    if ($formaPago !== '') {
        $fila['FORMA_PAGO_FAC'] = $formaPago;
    }
    /* Almacén y caja del usuario (ALMACEN_DEFECTO_USU y CAJA_DEFECTO_USU) y
       empleado configurado: los mismos campos que rellena la caja, para que
       el programa vea la factura completa. La web no crea operación de caja
       (fza_caja_operaciones), así que no entra en arqueos ni cierres. */
    $fila['CODIGO_ALM_FAC'] = trim((string)($usuario['almacen'] ?? '')) ?: null;
    $fila['CODIGO_CAJA_FAC'] = trim((string)($usuario['caja'] ?? '')) ?: null;
    $fila['CODIGO_CAJERO_FAC'] = empleado_ticket_defecto($pdo, $usuario) ?: null;
    return $fila;
}

/**
 * Fila de fza_facturas_lineas para una línea ya calculada (misma
 * información que graba el editor de líneas del programa).
 */
function fila_linea(array $cabecera, array $linea, string $numeroLinea, array $defectos, string $usuario): array
{
    $fila = $defectos;
    $fila['NUMERO_FAC_FACLIN'] = (string)$cabecera['NUMERO_FAC'];
    $fila['SERIE_FAC_FACLIN'] = (string)$cabecera['SERIE_FAC'];
    $fila['CODIGO_EMP_FACLIN'] = (string)$cabecera['CODIGO_EMP_FAC'];
    $fila['LINEA_FACLIN'] = $numeroLinea;
    $fila['CODIGO_ART_FACLIN'] = trim((string)$linea['codigo']) === '' ? null : (string)$linea['codigo'];
    $fila['TIPO_ARTICULO_FACLIN'] = (string)($linea['tipo_articulo'] ?? 'SERVICIO');
    $fila['TIPO_CANTIDAD_ARTICULO_FACLIN'] = (string)$linea['unidad'];
    $fila['CANTIDAD_FACLIN'] = decimal_sql((float)$linea['cantidad']);
    $fila['DESCRIPCION_ARTICULO_FACLIN'] = (string)$linea['descripcion'];
    $fila['DESCRIPCION_VARIACION_FACLIN'] = '';
    $fila['CODIGO_FAM_FACLIN'] = trim((string)($linea['familia'] ?? '')) === '' ? null : (string)$linea['familia'];
    $fila['CODIGO_TAR_FACLIN'] = (string)$cabecera['TARIFA_ARTICULO_CLIENTE_FAC'];
    $fila['ESIMP_INCL_TARIFA_FACLIN'] = (string)$cabecera['ESIMP_INCL_TARIFA_CLIENTE_FAC'];
    $fila['PRECIO_SALIDA_FACLIN'] = decimal_sql((float)$linea['precio_salida']);
    $fila['PORCENTAJE_DTO_FACLIN'] = decimal_sql((float)$linea['porcentaje_dto']);
    $fila['PRECIO_DTO_FACLIN'] = decimal_sql((float)$linea['precio_dto']);
    $fila['PRECIO_VENTA_SIVA_ARTICULO_FACLIN'] = decimal_sql((float)$linea['precio_siva']);
    $fila['TIPO_IVA_ARTICULO_FACLIN'] = (string)$linea['tipo_iva'];
    $fila['PORCENTAJE_IVA_FACLIN'] = decimal_sql((float)$linea['porcentaje_iva']);
    $fila['PRECIO_VENTA_CIVA_ARTICULO_FACLIN'] = decimal_sql((float)$linea['precio_civa']);
    $fila['TOTAL_FACLIN'] = decimal_sql((float)$linea['total_civa']);
    $fila['TOTAL_FAC_SIVA_FACLIN'] = decimal_sql((float)$linea['total_siva']);
    $fila['NUM_ATRIBUTOS_FACLIN'] = '0';
    /* Atributos vacíos, como los graba el editor del programa en una línea
       sin variaciones: en algunas bases estas columnas son NOT NULL sin
       valor por defecto y el INSERT fallaría con el modo estricto. */
    for ($atributo = 1; $atributo <= 5; $atributo++) {
        $fila['ATTR' . $atributo . '_VALOR_FACLIN'] = '';
        $fila['ATTR' . $atributo . '_NOMBRE_FACLIN'] = '';
    }
    $fila['USUARIO_ALTA'] = $usuario;
    $fila['USUARIO_MODIF'] = $usuario;
    $fila['INSTANTE_ALTA'] = 'NOW()';
    $fila['INSTANTE_MODIF'] = 'NOW()';
    return $fila;
}

/**
 * Graba la factura completa (cabecera, líneas y totales) y devuelve
 * ['serie', 'numero', 'numero_formateado', 'totales'].
 */
function factura_crear(PDO $pdo, array $usuario, array $borrador): array
{
    $empresa = $borrador['empresa'];
    $serie = (string)$borrador['serie'];
    $numero = (string)$borrador['numero'];
    $nombreUsuario = (string)$usuario['usuario'];

    if ($numero !== '0' && factura_existe($pdo, $numero, $serie)) {
        throw new RuntimeException(
            t('Ya existe la factura {serie} {numero}. Cambia el número o déjalo a 0.', ['serie' => $serie, 'numero' => $numero]));
    }
    if ($borrador['lineas'] === []) {
        throw new RuntimeException(t('La factura no tiene líneas.'));
    }

    $cabecera = cabecera_provisional($pdo, $usuario, $borrador);
    $calculo = calcular_factura($cabecera, $borrador['lineas']);

    /* Número: contador automático de la serie salvo que se haya escrito uno. */
    if ($numero === '0') {
        $numero = contador_siguiente_factura(
            $pdo, $serie, (string)$empresa['CODIGO_EMP_EMP'], $nombreUsuario);
    }
    $cabecera['NUMERO_FAC'] = $numero;

    /* Cabecera (solo columnas existentes). */
    factura_insertar($pdo, filtrar_columnas($cabecera, columnas_tabla($pdo, 'fza_facturas')));

    /* Líneas numeradas por el contador de líneas del programa. */
    $defectosLinea = valores_defecto($pdo, 'fza_facturas_lineas');
    $columnasLinea = columnas_tabla($pdo, 'fza_facturas_lineas');
    foreach ($calculo['lineas'] as $linea) {
        $numeroLinea = factura_linea_siguiente($pdo, $numero, $serie);
        $fila = fila_linea($cabecera, $linea, $numeroLinea, $defectosLinea, $nombreUsuario);
        factura_linea_insertar($pdo, filtrar_columnas($fila, $columnasLinea));
    }

    /* Totales, como ActualizarTotalesEnDataSet del programa. */
    factura_actualizar_totales($pdo, $serie, $numero, $calculo['totales'], $nombreUsuario);

    return [
        'serie'             => $serie,
        'numero'            => $numero,
        'numero_formateado' => numero_documento_formateado($empresa, $serie, $numero),
        'totales'           => $calculo['totales'],
    ];
}

/** Columnas de la cabecera que se rehacen al modificar una factura en borrador. */
const COLUMNAS_CABECERA_MODIFICABLES = [
    'FECHA_FAC', 'FORMA_PAGO_FAC', 'TARIFA_ARTICULO_CLIENTE_FAC', 'ESIMP_INCL_TARIFA_CLIENTE_FAC',
    'PORCENTAJE_RETENCION_FAC',
    'CODIGO_CLI_FAC', 'RAZON_SOCIAL_CLIENTE_FAC', 'NIF_CLIENTE_FAC', 'MOVIL_CLIENTE_FAC', 'EMAIL_CLIENTE_FAC',
    'DIRECCION1_CLIENTE_FAC', 'DIRECCION2_CLIENTE_FAC', 'POBLACION_CLIENTE_FAC', 'PROVINCIA_CLIENTE_FAC',
    'CODIGO_POSTAL_CLIENTE_FAC', 'NOMBRE_PAI_CLIENTE_FAC', 'CODIGO_PAI_CLIENTE_FAC',
    'ESIVA_RECARGO_CLIENTE_FAC', 'ESIVA_EXENTO_CLIENTE_FAC', 'ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC',
    'ESRETENCIONES_CLIENTE_FAC', 'ESINTRACOMUNITARIO_CLIENTE_FAC', 'CODIGO_OFICINA_CONTABLE_FAC',
    'CODIGO_ORGANO_GESTOR_FAC', 'CODIGO_UNIDAD_TRAMITADORA_FAC', 'NOMBRE_PERSONA_CLIENTE_FAC',
    'APELLIDOS_PERSONA_CLIENTE_FAC', 'TEXTO_LEGAL_CLIENTE_FAC',
    'CODIGO_ALM_FAC', 'CODIGO_CAJA_FAC', 'CODIGO_CAJERO_FAC',
    'PORCENTAJE_IVAN_FAC', 'PORCENTAJE_REN_FAC', 'PORCENTAJE_IVAR_FAC', 'PORCENTAJE_RER_FAC',
    'PORCENTAJE_IVAS_FAC', 'PORCENTAJE_RES_FAC', 'PORCENTAJE_IVAE_FAC', 'PORCENTAJE_REE_FAC',
    'ESIRPF_IMP_INCL_ZONA_IVA_FAC', 'ESAPLICA_RE_ZONA_IVA_FAC', 'CODIGO_IVA_FAC',
    'ESIVAAGRICOLA_ZONA_IVA_FAC', 'PALABRA_REPORTS_ZONA_IVA_FAC',
    'USUARIO_MODIF', 'INSTANTE_MODIF',
];

/**
 * Modifica una factura en borrador: rehace la parte de cliente, fecha, IVA
 * y retención de la cabecera, sustituye las líneas (renumeradas desde 010)
 * y recalcula los totales. Devuelve lo mismo que factura_crear.
 */
function factura_actualizar(PDO $pdo, array $usuario, array $borrador): array
{
    $edicion = editando($borrador);
    if ($edicion === null) {
        throw new LogicException('No hay ninguna factura en modificación.');
    }
    $serie = (string)$edicion['serie'];
    $numero = (string)$edicion['numero'];
    $actual = factura_leer($pdo, $serie, $numero);
    if ($actual === null || !factura_editable($actual)) {
        throw new RuntimeException(t('La factura {serie} {numero} ya no se puede modificar.', ['serie' => $serie, 'numero' => $numero]));
    }
    if ($borrador['lineas'] === []) {
        throw new RuntimeException(t('La factura no tiene líneas.'));
    }
    $nombreUsuario = (string)$usuario['usuario'];
    $cabecera = cabecera_provisional($pdo, $usuario, $borrador);
    $cabecera['NUMERO_FAC'] = $numero;
    $cabecera['SERIE_FAC'] = $serie;
    $calculo = calcular_factura($cabecera, $borrador['lineas']);

    $columnas = columnas_tabla($pdo, 'fza_facturas');
    $campos = [];
    foreach (COLUMNAS_CABECERA_MODIFICABLES as $columna) {
        if (array_key_exists($columna, $cabecera) && isset($columnas[$columna])) {
            $campos[$columna] = $cabecera[$columna];
        }
    }
    factura_actualizar_cabecera($pdo, $serie, $numero, $campos);

    factura_lineas_vaciar($pdo, $serie, $numero);
    $defectosLinea = valores_defecto($pdo, 'fza_facturas_lineas');
    $columnasLinea = columnas_tabla($pdo, 'fza_facturas_lineas');
    foreach ($calculo['lineas'] as $linea) {
        $numeroLinea = factura_linea_siguiente($pdo, $numero, $serie);
        $fila = fila_linea($cabecera, $linea, $numeroLinea, $defectosLinea, $nombreUsuario);
        factura_linea_insertar($pdo, filtrar_columnas($fila, $columnasLinea));
    }
    factura_actualizar_totales($pdo, $serie, $numero, $calculo['totales'], $nombreUsuario);

    return [
        'serie'             => $serie,
        'numero'            => $numero,
        'numero_formateado' => numero_documento_formateado($borrador['empresa'], $serie, $numero),
        'totales'           => $calculo['totales'],
    ];
}
