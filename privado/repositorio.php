<?php
declare(strict_types=1);

require_once __DIR__ . '/idiomas.php';

/*
 * Acceso a datos. Usa las mismas tablas, vistas y procedimientos
 * almacenados que el programa de escritorio (ViraCash) para que todo lo
 * escrito desde la web sea visible y editable desde el programa:
 *
 *   - Contadores:      PRC_GET_NEXT_CONT (maestros) y
 *                      PRC_GET_NEXT_CONT_FACT_SERIE (número de factura).
 *   - Empresa:         PRC_CREAR_ACTUALIZAR_EMPRESA.
 *   - Cliente:         PRC_CREAR_ACTUALIZAR_CLIENTE.
 *   - Series:          fza_contadores + vi_empresas_series (como el
 *                      selector de serie de facturas del programa).
 *   - Valores defecto: fza_valores_defecto y perfiles de usuario.
 */

const COLUMNAS_EMPRESA =
    'CODIGO_EMP_EMP, ESACTIVO_EMP, RAZON_SOCIAL_EMP, NIF_EMP, MOVIL_EMP, ' .
    'EMAIL_EMP, DIRECCION1_EMP, DIRECCION2_EMP, CODIGO_POSTAL_EMP, ' .
    'POBLACION_EMP, PROVINCIA_EMP, CODIGO_PAI_EMP, NOMBRE_PAI_EMP, ' .
    'SERIE_CON_EMP, IBAN_EMP, GRUPO_ZONA_IVA_EMP, ESRETENCIONES_EMP, ' .
    'ESIVA_RECARGO_COMPRAS_EMP, ESREGIMENESPECIALAGRICOLA_EMP, ' .
    'TEXTO_LEGAL_FACTURA_EMP, FORMATO_DOCUMENTO_EMP';

const COLUMNAS_CLIENTE =
    'CODIGO_CLI_CLI, ESACTIVO_CLI, RAZON_SOCIAL_CLI, NIF_CLI, MOVIL_CLI, ' .
    'EMAIL_CLI, DIRECCION1_CLI, DIRECCION2_CLI, POBLACION_CLI, PROVINCIA_CLI, ' .
    'CODIGO_POSTAL_CLI, CODIGO_PAI_CLI, NOMBRE_PAI_CLI, ' .
    'NOMBRE_PERSONA_CLIENTE_CLI, APELLIDOS_PERSONA_CLIENTE_CLI, ' .
    'CODIGO_OFICINA_CONTABLE_CLI, CODIGO_ORGANO_GESTOR_CLI, ' .
    'CODIGO_UNIDAD_TRAMITADORA_CLI, TELEFONO_CLI, IBAN_CLI, ' .
    'ESIVA_RECARGO_CLI, ESRETENCIONES_CLI, ESIVA_EXENTO_CLI, ' .
    'ESINTRACOMUNITARIO_CLI, ESREGIMENESPECIALAGRICOLA_CLI, CODIGO_FP_CLI, ' .
    'TARIFA_ARTICULO_CLI, SERIE_CON_CLI, TEXTO_LEGAL_FACTURA_CLI';

/* ===================== Utilidades internas ===================== */

function consultar(PDO $pdo, string $sql, array $parametros = []): array
{
    $consulta = $pdo->prepare($sql);
    $consulta->execute($parametros);
    $filas = $consulta->fetchAll();
    $consulta->closeCursor();
    return $filas;
}

function consultar_una(PDO $pdo, string $sql, array $parametros = []): ?array
{
    $filas = consultar($pdo, $sql, $parametros);
    return $filas[0] ?? null;
}

function ejecutar(PDO $pdo, string $sql, array $parametros = []): int
{
    $consulta = $pdo->prepare($sql);
    $consulta->execute($parametros);
    $afectadas = $consulta->rowCount();
    $consulta->closeCursor();
    return $afectadas;
}

/**
 * Ejecuta un procedimiento con un parámetro OUT y devuelve su valor.
 * Los procedimientos de contadores gestionan su propia transacción, por lo
 * que se llaman siempre fuera de una transacción PDO.
 */
function llamar_procedimiento_out(PDO $pdo, string $llamada, array $parametros): string
{
    if ($pdo->inTransaction()) {
        throw new LogicException(
            'Los contadores no pueden pedirse dentro de una transacción.');
    }
    $consulta = $pdo->prepare($llamada);
    $consulta->execute($parametros);
    $consulta->closeCursor();
    $valor = $pdo->query('SELECT @fza_salida')->fetchColumn();
    return trim((string)$valor);
}

/* ===================== Contadores ===================== */

/** Siguiente código de un maestro (CL clientes, EM empresas, ...). */
function contador_siguiente(PDO $pdo, string $tipoDocumento, string $usuario): string
{
    $valor = llamar_procedimiento_out(
        $pdo,
        'CALL PRC_GET_NEXT_CONT(?, ?, @fza_salida)',
        [$tipoDocumento, $usuario]
    );
    if ($valor === '') {
        throw new RuntimeException(
            t("El contador automático '{tipo}' no ha devuelto ningún código.", ['tipo' => $tipoDocumento]));
    }
    return $valor;
}

/** Siguiente número de factura de una serie y empresa (contador FC). */
function contador_siguiente_factura(
    PDO $pdo,
    string $serie,
    string $empresa,
    string $usuario
): string {
    $valor = llamar_procedimiento_out(
        $pdo,
        'CALL PRC_GET_NEXT_CONT_FACT_SERIE(?, \'FC\', ?, ?, @fza_salida)',
        [$serie, $empresa, $usuario]
    );
    if ($valor === '') {
        throw new RuntimeException(
            t("El contador de la serie '{serie}' no ha devuelto ningún número.", ['serie' => $serie]));
    }
    return $valor;
}

/**
 * Número que entregará el contador de facturas sin consumirlo. Devuelve
 * ['numero' => '000176', 'existe' => true|false].
 */
function contador_factura_previsto(PDO $pdo, string $serie, string $empresa): array
{
    if ($empresa === '') {
        $empresa = '-';
    }
    $fila = consultar_una(
        $pdo,
        'SELECT CON, NUM_DIGITOS_CON FROM fza_contadores ' .
        'WHERE TIPO_DOC_CON = \'FC\' AND EMPRESA_CON = ? AND SERIE_CON = ?',
        [$empresa, $serie]
    );
    if ($fila === null) {
        return ['numero' => str_pad('1', 6, '0', STR_PAD_LEFT), 'existe' => false];
    }
    $siguiente = max((int)$fila['CON'], 1);
    $digitos = (int)$fila['NUM_DIGITOS_CON'];
    $numero = $digitos > 0
        ? str_pad((string)$siguiente, $digitos, '0', STR_PAD_LEFT)
        : (string)$siguiente;
    return ['numero' => $numero, 'existe' => true];
}

/* ===================== Empresas ===================== */

function empresas_listar(PDO $pdo): array
{
    return consultar(
        $pdo,
        'SELECT ' . COLUMNAS_EMPRESA . ' FROM fza_empresas ' .
        'WHERE COALESCE(ESACTIVO_EMP, \'S\') = \'S\' ' .
        'ORDER BY COALESCE(ORDEN_EMP, 2147483647), RAZON_SOCIAL_EMP'
    );
}

function empresa_por_codigo(PDO $pdo, string $codigo): ?array
{
    if ($codigo === '') {
        return null;
    }
    return consultar_una(
        $pdo,
        'SELECT ' . COLUMNAS_EMPRESA . ' FROM fza_empresas WHERE CODIGO_EMP_EMP = ?',
        [$codigo]
    );
}

function empresas_por_nif(PDO $pdo, string $nif): array
{
    return consultar(
        $pdo,
        'SELECT ' . COLUMNAS_EMPRESA . ' FROM fza_empresas ' .
        'WHERE UPPER(TRIM(NIF_EMP)) = UPPER(TRIM(?)) ' .
        'ORDER BY COALESCE(ESACTIVO_EMP, \'S\') DESC, ' .
        'COALESCE(ORDEN_EMP, 2147483647), RAZON_SOCIAL_EMP',
        [$nif]
    );
}

/**
 * Empresa emisora inicial: la del usuario (EMPRESA_DEFECTO_USU) si existe;
 * si no, la única empresa activa de la base de datos; si no, ninguna.
 */
function empresa_inicial(PDO $pdo, array $usuario): ?array
{
    $empresa = empresa_por_codigo($pdo, (string)($usuario['empresa'] ?? ''));
    if ($empresa !== null) {
        return $empresa;
    }
    $empresas = empresas_listar($pdo);
    return count($empresas) === 1 ? $empresas[0] : null;
}

/**
 * Crea o actualiza la empresa con PRC_CREAR_ACTUALIZAR_EMPRESA, igual que
 * lo hace la factura del programa (CrearEmpresa).
 */
function empresa_guardar(PDO $pdo, array $datos, string $usuario): void
{
    ejecutar(
        $pdo,
        'CALL PRC_CREAR_ACTUALIZAR_EMPRESA(' .
        '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
            $datos['CODIGO_EMP_EMP'],
            $datos['RAZON_SOCIAL_EMP'],
            $datos['NIF_EMP'],
            $datos['MOVIL_EMP'],
            $datos['EMAIL_EMP'],
            $datos['DIRECCION1_EMP'],
            $datos['DIRECCION2_EMP'],
            $datos['POBLACION_EMP'],
            $datos['PROVINCIA_EMP'],
            $datos['CODIGO_POSTAL_EMP'],
            $datos['NOMBRE_PAI_EMP'],
            $datos['CODIGO_PAI_EMP'],
            $datos['ESRETENCIONES_EMP'],
            '',
            $datos['ESREGIMENESPECIALAGRICOLA_EMP'],
            $datos['GRUPO_ZONA_IVA_EMP'],
            $usuario,
        ]
    );
}

/* ===================== Series de factura ===================== */

/**
 * Series de factura (FC) disponibles para una empresa en una fecha: las de
 * fza_contadores (propias o sin empresa) más las vigentes en
 * empresas -> series con subtipo NORMAL. Misma consulta que el selector de
 * serie del programa, con la fecha del documento en lugar de CURDATE().
 * Devuelve filas con SERIE_CON, DEFAULT_CON (contador por defecto) y
 * ESSERIE_EMPRESA (definida en empresas -> series).
 */
function series_factura(PDO $pdo, string $empresa, string $fecha): array
{
    return consultar(
        $pdo,
        'SELECT SERIES.SERIE_CON, ' .
        '       MAX(SERIES.DEFAULT_CON) AS DEFAULT_CON, ' .
        '       MAX(SERIES.ESSERIE_EMPRESA) AS ESSERIE_EMPRESA ' .
        '  FROM (SELECT SERIE_CON, DEFAULT_CON, \'N\' AS ESSERIE_EMPRESA ' .
        '          FROM fza_contadores ' .
        '         WHERE TIPO_DOC_CON = \'FC\' ' .
        '           AND ESACTIVO_CON = \'S\' ' .
        '           AND EMPRESA_CON IN (?, \'-\') ' .
        '         UNION ALL ' .
        '        SELECT EMPSER AS SERIE_CON, \'N\' AS DEFAULT_CON, \'S\' AS ESSERIE_EMPRESA ' .
        '          FROM vi_empresas_series ' .
        '         WHERE CODIGO_EMP_EMPSER = ? ' .
        '           AND TIPO_DOC_EMPSER = \'FC\' ' .
        '           AND (SUBTIPO_EMPSER = \'NORMAL\' ' .
        '                OR IFNULL(SUBTIPO_EMPSER, \'\') = \'\') ' .
        '           AND (FECHA_DESDE_EMPSER IS NULL ' .
        '                OR FECHA_DESDE_EMPSER <= ?) ' .
        '           AND (FECHA_HASTA_EMPSER IS NULL ' .
        '                OR FECHA_HASTA_EMPSER >= ?)) SERIES ' .
        ' GROUP BY SERIES.SERIE_CON ' .
        ' ORDER BY ESSERIE_EMPRESA DESC, DEFAULT_CON DESC, SERIES.SERIE_CON',
        [$empresa, $empresa, $fecha, $fecha]
    );
}

/**
 * Serie por defecto: la vigente en empresas -> series (subtipo NORMAL, como
 * hace la pantalla de facturas de venta mayor al crear una factura); si no
 * hay, el contador marcado por defecto; si no, la primera de la lista.
 */
function serie_defecto(PDO $pdo, string $empresa, string $fecha, array $series): string
{
    $fila = consultar_una(
        $pdo,
        'SELECT EMPSER FROM vi_empresas_series ' .
        'WHERE CODIGO_EMP_EMPSER = ? AND TIPO_DOC_EMPSER = \'FC\' ' .
        'AND (SUBTIPO_EMPSER = \'NORMAL\' OR IFNULL(SUBTIPO_EMPSER, \'\') = \'\') ' .
        'AND (FECHA_DESDE_EMPSER IS NULL OR FECHA_DESDE_EMPSER <= ?) ' .
        'AND (FECHA_HASTA_EMPSER IS NULL OR FECHA_HASTA_EMPSER >= ?) ' .
        'ORDER BY CASE WHEN SUBTIPO_EMPSER = \'NORMAL\' THEN 0 ELSE 1 END, ' .
        'FECHA_DESDE_EMPSER DESC, EMPSER LIMIT 1',
        [$empresa, $fecha, $fecha]
    );
    if ($fila !== null && trim((string)$fila['EMPSER']) !== '') {
        return trim((string)$fila['EMPSER']);
    }
    foreach ($series as $serie) {
        if (es_si($serie['DEFAULT_CON'] ?? 'N')) {
            return (string)$serie['SERIE_CON'];
        }
    }
    return isset($series[0]) ? (string)$series[0]['SERIE_CON'] : '';
}

/* ===================== Clientes ===================== */

function cliente_por_codigo(PDO $pdo, string $codigo): ?array
{
    if ($codigo === '') {
        return null;
    }
    return consultar_una(
        $pdo,
        'SELECT ' . COLUMNAS_CLIENTE . ' FROM fza_clientes WHERE CODIGO_CLI_CLI = ?',
        [$codigo]
    );
}

function clientes_por_nif(PDO $pdo, string $nif): array
{
    return consultar(
        $pdo,
        'SELECT ' . COLUMNAS_CLIENTE . ' FROM fza_clientes ' .
        'WHERE UPPER(TRIM(NIF_CLI)) = UPPER(TRIM(?)) ' .
        'ORDER BY COALESCE(ESACTIVO_CLI, \'S\') DESC, RAZON_SOCIAL_CLI',
        [$nif]
    );
}

/**
 * Crea o actualiza el cliente con PRC_CREAR_ACTUALIZAR_CLIENTE (el mismo
 * procedimiento que usa la factura del programa). La forma de pago no forma
 * parte del procedimiento: se graba aparte con auditoría, como hace el
 * mantenimiento de clientes.
 */
function cliente_guardar(PDO $pdo, array $datos, string $usuario, bool $grabarFormaPago): void
{
    ejecutar(
        $pdo,
        'CALL PRC_CREAR_ACTUALIZAR_CLIENTE(' .
        '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
            $datos['CODIGO_CLI_CLI'],
            $datos['RAZON_SOCIAL_CLI'],
            $datos['NIF_CLI'],
            $datos['MOVIL_CLI'],
            $datos['EMAIL_CLI'],
            $datos['DIRECCION1_CLI'],
            $datos['DIRECCION2_CLI'],
            $datos['POBLACION_CLI'],
            $datos['PROVINCIA_CLI'],
            $datos['CODIGO_POSTAL_CLI'],
            $datos['CODIGO_PAI_CLI'],
            $datos['NOMBRE_PAI_CLI'],
            $datos['ESIVA_EXENTO_CLI'],
            $datos['ESRETENCIONES_CLI'],
            $datos['ESIVA_RECARGO_CLI'],
            $datos['ESINTRACOMUNITARIO_CLI'],
            $datos['ESREGIMENESPECIALAGRICOLA_CLI'],
            $datos['TARIFA_ARTICULO_CLI'],
            $usuario,
        ]
    );
    if ($grabarFormaPago) {
        ejecutar(
            $pdo,
            'UPDATE fza_clientes SET CODIGO_FP_CLI = ?, USUARIO_MODIF = ?, ' .
            'INSTANTE_MODIF = NOW() WHERE CODIGO_CLI_CLI = ?',
            [
                $datos['CODIGO_FP_CLI'] === '' ? null : $datos['CODIGO_FP_CLI'],
                $usuario,
                $datos['CODIGO_CLI_CLI'],
            ]
        );
    }
}

/* ===================== Catálogos ===================== */

function paises_listar(PDO $pdo): array
{
    return consultar(
        $pdo,
        'SELECT CODIGO_PAI_PAI, COD_ALPHA2_PAI, COD_ALPHA3_PAI, NOMBRE_SPA_PAI, ' .
        'ESMIEMBRO_UE_PAI FROM fza_paises ' .
        'ORDER BY COALESCE(ORDEN_PAI, 2147483647), NOMBRE_SPA_PAI'
    );
}

/** Busca un país por código numérico, alfa-2 o alfa-3 (la BBDD mezcla los tres). */
function pais_resolver(array $paises, string $codigo): ?array
{
    $codigo = strtoupper(trim($codigo));
    if ($codigo === '') {
        return null;
    }
    foreach ($paises as $pais) {
        if (strtoupper(trim((string)$pais['CODIGO_PAI_PAI'])) === $codigo ||
            strtoupper(trim((string)$pais['COD_ALPHA2_PAI'])) === $codigo ||
            strtoupper(trim((string)$pais['COD_ALPHA3_PAI'])) === $codigo) {
            return $pais;
        }
    }
    return null;
}

function tarifas_listar(PDO $pdo): array
{
    return consultar(
        $pdo,
        'SELECT CODIGO_TAR_ARTTAR, NOMBRE_TAR_TAR, COALESCE(ESIMP_INCL_TAR, \'S\') AS ESIMP_INCL_TAR ' .
        'FROM fza_tarifas WHERE COALESCE(ESACTIVO_ARTTAR, \'S\') = \'S\' ' .
        'ORDER BY COALESCE(ORDEN_TAR, 2147483647), CODIGO_TAR_ARTTAR'
    );
}

function tarifa_por_codigo(array $tarifas, string $codigo): ?array
{
    foreach ($tarifas as $tarifa) {
        if ((string)$tarifa['CODIGO_TAR_ARTTAR'] === $codigo) {
            return $tarifa;
        }
    }
    return null;
}

function formas_pago_listar(PDO $pdo): array
{
    return consultar(
        $pdo,
        'SELECT CODIGO_FP_FP, DESCRIPCION_FORMA_PAGO_FP, ' .
        'COALESCE(ESDEFAULT_FORMA_PAGO_FP, \'N\') AS ESDEFAULT_FORMA_PAGO_FP ' .
        'FROM fza_formas_pago WHERE COALESCE(ESACTIVO_FORMA_PAGO_FP, \'S\') = \'S\' ' .
        'ORDER BY COALESCE(ORDEN_FORMA_PAGO_FP, 2147483647), CODIGO_FP_FP'
    );
}

/** Forma de pago por defecto (ESDEFAULT_FORMA_PAGO_FP = 'S'), como ObtenerValorPorDefecto. */
function forma_pago_defecto(PDO $pdo): string
{
    $fila = consultar_una(
        $pdo,
        'SELECT CODIGO_FP_FP FROM fza_formas_pago ' .
        'WHERE ESDEFAULT_FORMA_PAGO_FP = \'S\' LIMIT 1'
    );
    return $fila === null ? '' : (string)$fila['CODIGO_FP_FP'];
}

function grupos_iva_listar(PDO $pdo): array
{
    return consultar(
        $pdo,
        'SELECT IVA_IVAGRP, DESCRIPCION_IVA_IVAGRP, PALABRA_REPORTS_IVA_IVAGRP, ' .
        'COALESCE(ESDEFAULT_IVA_IVAGRP, \'N\') AS ESDEFAULT_IVA_IVAGRP ' .
        'FROM fza_ivas_grupos ORDER BY ESDEFAULT_IVA_IVAGRP DESC, IVA_IVAGRP'
    );
}

/** Configuración de IVA vigente del grupo (vi_ivas), como CargarConfiguracionIvaFactura. */
function iva_configuracion(PDO $pdo, string $grupo, string $fecha): ?array
{
    if ($grupo === '') {
        return null;
    }
    /* Misma información que la vista vi_ivas (fza_ivas + fza_ivas_grupos),
       leída de las tablas para no depender de que la vista exista. */
    return consultar_una(
        $pdo,
        'SELECT I.CODIGO_IVA, I.IVA_IVAGRP, I.DESCRIPCION_IVA_IVAGRP, ' .
        'I.PORCENTAJE_EXENTO_IVA, I.PORCENTAJE_EXENTO_RE_IVA, ' .
        'I.PORCENTAJE_NORMAL_IVA, I.PORCENTAJE_NORMAL_RE_IVA, ' .
        'I.PORCENTAJE_REDUCIDO_IVA, I.PORCENTAJE_REDUCIDO_RE_IVA, ' .
        'I.PORCENTAJE_SUPERREDUCIDO_IVA, I.PORCENTAJE_SUPERREDUCIDO_RE_IVA, ' .
        'COALESCE(G.ESAPLICA_RE_IVA_IVAGRP, \'S\') AS ESAPLICA_RE_IVA_IVAGRP, ' .
        'COALESCE(G.ESIVAAGRICOLA_IVA_IVAGRP, \'N\') AS ESIVAAGRICOLA_IVA_IVAGRP, ' .
        'COALESCE(G.ESIRPF_IMP_INCL_IVA_IVAGRP, \'N\') AS ESIRPF_IMP_INCL_IVA_IVAGRP, ' .
        'COALESCE(G.PALABRA_REPORTS_IVA_IVAGRP, \'IVA\') AS PALABRA_REPORTS_IVA_IVAGRP ' .
        'FROM fza_ivas I ' .
        'LEFT JOIN fza_ivas_grupos G ON G.IVA_IVAGRP = I.IVA_IVAGRP ' .
        'WHERE I.IVA_IVAGRP = ? AND I.FECHA_DESDE_IVA <= ? ' .
        'AND (I.FECHA_HASTA_IVA >= ? OR I.FECHA_HASTA_IVA IS NULL) ' .
        'ORDER BY I.FECHA_DESDE_IVA DESC LIMIT 1',
        [$grupo, $fecha, $fecha]
    );
}

/** Porcentaje de retención vigente de la empresa (AplicarRetencionEmpresaFactura). */
function retencion_empresa(PDO $pdo, string $empresa, string $fecha): ?string
{
    $fila = consultar_una(
        $pdo,
        'SELECT PORCENTAJE_EMPRET FROM fza_empresas_retenciones ' .
        'WHERE CODIGO_EMP_EMPRET = ? AND FECHA_DESDE_EMPRET <= ? ' .
        'AND (FECHA_HASTA_EMPRET >= ? OR FECHA_HASTA_EMPRET IS NULL) LIMIT 1',
        [$empresa, $fecha, $fecha]
    );
    return $fila === null ? null : (string)$fila['PORCENTAJE_EMPRET'];
}

/** Valores por defecto de una tabla (fza_valores_defecto), campo => valor. */
function valores_defecto(PDO $pdo, string $tabla): array
{
    $filas = consultar(
        $pdo,
        'SELECT CAMPO_OBJETIVO_DEF_VD, VALOR_DEF_VD, TIPO_DATO_DEF_VD ' .
        'FROM fza_valores_defecto WHERE TABLA_OBJETIVO_DEF_VD = ?',
        [$tabla]
    );
    $valores = [];
    foreach ($filas as $fila) {
        $campo = (string)$fila['CAMPO_OBJETIVO_DEF_VD'];
        $valor = (string)($fila['VALOR_DEF_VD'] ?? '');
        $tipo = strtoupper((string)($fila['TIPO_DATO_DEF_VD'] ?? 'STRING'));
        if ($tipo === 'INTEGER') {
            $valores[$campo] = (string)(int)$valor;
        } elseif ($tipo === 'FLOAT') {
            $valores[$campo] = (string)(float)str_replace(',', '.', $valor);
        } elseif ($tipo === 'BOOLEAN') {
            $valores[$campo] = (strtoupper($valor) === 'TRUE' || $valor === '1') ? 'S' : 'N';
        } else {
            $valores[$campo] = $valor;
        }
    }
    return $valores;
}

/**
 * Parámetro de perfil de usuario (fza_usuarios_perfiles) con la prioridad
 * del programa: usuario > grupo > Todos.
 */
function perfil_valor(
    PDO $pdo,
    array $usuario,
    string $formulario,
    string $clave,
    string $defecto
): string {
    $fila = consultar_una(
        $pdo,
        'SELECT VALUE_USUPER FROM fza_usuarios_perfiles ' .
        'WHERE KEY_USUPER = ? AND SUBKEY_USUPER = ? ' .
        'AND USUARIO_GRUPO_USUPER IN (?, ?, \'Todos\') ' .
        'ORDER BY CASE USUARIO_GRUPO_USUPER WHEN ? THEN 1 WHEN ? THEN 2 ELSE 3 END ' .
        'LIMIT 1',
        [
            $formulario,
            $clave,
            (string)$usuario['usuario'],
            (string)$usuario['grupo'],
            (string)$usuario['usuario'],
            (string)$usuario['grupo'],
        ]
    );
    if ($fila === null || trim((string)$fila['VALUE_USUPER']) === '') {
        return $defecto;
    }
    return trim((string)$fila['VALUE_USUPER']);
}

/** Formulario de los parámetros de caja del programa (tarifa, empleado...). */
const FORMULARIO_PARAMETROS_CAJA = 'frmMtoCajaParam';

/** Tarifa por defecto del usuario (parámetro vgerDefTarifa de caja, 'PVP' si no hay). */
function tarifa_defecto(PDO $pdo, array $usuario): string
{
    return perfil_valor($pdo, $usuario, FORMULARIO_PARAMETROS_CAJA, 'vgerDefTarifa', 'PVP');
}

/**
 * Tarifa que se asigna a un cliente nuevo desde la web: VENTA MAYOR (precios
 * sin IVA); si no existe, la primera tarifa sin impuestos incluidos; si no,
 * la tarifa por defecto del usuario.
 */
function tarifa_nuevo_cliente(PDO $pdo, array $usuario): string
{
    $tarifas = tarifas_listar($pdo);
    foreach ($tarifas as $tarifa) {
        $nombre = strtoupper(preg_replace('/\s+/', '', (string)$tarifa['NOMBRE_TAR_TAR']) ?? '');
        $codigo = strtoupper(preg_replace('/\s+/', '', (string)$tarifa['CODIGO_TAR_ARTTAR']) ?? '');
        if ($nombre === 'VENTAMAYOR' || $codigo === 'VENTAMAYOR') {
            return (string)$tarifa['CODIGO_TAR_ARTTAR'];
        }
    }
    foreach ($tarifas as $tarifa) {
        if (!es_si((string)$tarifa['ESIMP_INCL_TAR'])) {
            return (string)$tarifa['CODIGO_TAR_ARTTAR'];
        }
    }
    return tarifa_defecto($pdo, $usuario);
}

/* ===================== Artículos ===================== */

const SQL_ARTICULO_CON_TARIFA =
    'SELECT A.CODIGO_ART_ART, A.DESCRIPCION_ART, A.TIPO_ART, A.TIPO_IVA_ART, ' .
    'A.TIPO_CANTIDAD_ART, A.CODIGO_FAM_ART, T.PRECIO_SALIDA_ARTTAR ' .
    'FROM fza_articulos A ' .
    'LEFT JOIN fza_articulos_tarifas T ON T.CODIGO_ART_ARTTAR = A.CODIGO_ART_ART ' .
    '  AND COALESCE(T.CODIGO_UNIDAD_ARTTAR, \'\') = \'\' ' .
    '  AND T.CODIGO_TAR_ARTTAR = ? ' .
    '  AND COALESCE(T.ESACTIVO_ARTTAR, \'S\') = \'S\' ' .
    'WHERE COALESCE(A.ESACTIVO_ART, \'S\') = \'S\' ';

/** Artículos activos cuyo código o descripción contiene el texto, con el precio de la tarifa. */
function articulos_buscar(PDO $pdo, string $texto, string $tarifa): array
{
    $patron = '%' . trim($texto) . '%';
    return consultar(
        $pdo,
        SQL_ARTICULO_CON_TARIFA .
        'AND (A.CODIGO_ART_ART LIKE ? OR A.DESCRIPCION_ART LIKE ?) ' .
        'ORDER BY A.DESCRIPCION_ART LIMIT 20',
        [$tarifa, $patron, $patron]
    );
}

function articulo_por_codigo(PDO $pdo, string $codigo, string $tarifa): ?array
{
    if (trim($codigo) === '') {
        return null;
    }
    return consultar_una(
        $pdo,
        SQL_ARTICULO_CON_TARIFA . 'AND A.CODIGO_ART_ART = ? LIMIT 1',
        [$tarifa, trim($codigo)]
    );
}

/* ===================== Facturas ===================== */

/** Dígitos del contador FC de la serie (6 si el contador aún no existe, como el procedimiento). */
function contador_factura_digitos(PDO $pdo, string $serie, string $empresa): int
{
    $fila = consultar_una(
        $pdo,
        'SELECT NUM_DIGITOS_CON FROM fza_contadores ' .
        'WHERE TIPO_DOC_CON = \'FC\' AND EMPRESA_CON = ? AND SERIE_CON = ?',
        [$empresa === '' ? '-' : $empresa, $serie]
    );
    return $fila === null ? 6 : (int)$fila['NUM_DIGITOS_CON'];
}

/** Siguiente número de línea de la factura (PRC_FNC_GET_NEXT_LINEA_FACTURA). */
function factura_linea_siguiente(PDO $pdo, string $numero, string $serie): string
{
    $valor = llamar_procedimiento_out(
        $pdo,
        'CALL PRC_FNC_GET_NEXT_LINEA_FACTURA(?, ?, @fza_salida)',
        [$numero, $serie]
    );
    if ($valor === '') {
        throw new RuntimeException(t('El contador de líneas no ha devuelto ningún número.'));
    }
    return $valor;
}

/** Inserta una línea de factura. $fila es columna => valor. */
function factura_linea_insertar(PDO $pdo, array $fila): void
{
    $columnas = [];
    $marcadores = [];
    $valores = [];
    foreach ($fila as $columna => $valor) {
        if (preg_match('/^[A-Z0-9_]+$/', (string)$columna) !== 1) {
            throw new LogicException("Columna no válida: $columna");
        }
        $columnas[] = $columna;
        if ($valor === 'NOW()') {
            $marcadores[] = 'NOW()';
        } else {
            $marcadores[] = '?';
            $valores[] = $valor;
        }
    }
    ejecutar(
        $pdo,
        'INSERT INTO fza_facturas_lineas (' . implode(', ', $columnas) . ') ' .
        'VALUES (' . implode(', ', $marcadores) . ')',
        $valores
    );
}

/** Graba en la cabecera los totales calculados (mismas columnas que ActualizarTotalesEnDataSet). */
function factura_actualizar_totales(PDO $pdo, string $serie, string $numero, array $totales, string $usuario): void
{
    $porTipo = $totales['por_tipo'];
    ejecutar(
        $pdo,
        'UPDATE fza_facturas SET ' .
        'TOTAL_BASEI_IVAN_FAC = ?, TOTAL_BASEI_IVAR_FAC = ?, TOTAL_BASEI_IVAS_FAC = ?, TOTAL_BASEI_IVAE_FAC = ?, ' .
        'TOTAL_BASES_FAC = ?, ' .
        'TOTAL_IVAN_FAC = ?, TOTAL_IVAR_FAC = ?, TOTAL_IVAS_FAC = ?, TOTAL_IVAE_FAC = ?, ' .
        'TOTAL_REN_FAC = ?, TOTAL_RER_FAC = ?, TOTAL_RES_FAC = ?, TOTAL_REE_FAC = ?, ' .
        'TOTAL_IMPUESTOS_FAC = ?, TOTAL_RETENCION_FAC = ?, PORCENTAJE_RETENCION_FAC = ?, ' .
        'TOTAL_LIQUIDO_FAC = ?, USUARIO_MODIF = ?, INSTANTE_MODIF = NOW() ' .
        'WHERE SERIE_FAC = ? AND NUMERO_FAC = ?',
        [
            $porTipo['N']['base'], $porTipo['R']['base'], $porTipo['S']['base'], $porTipo['E']['base'],
            $totales['total_bases'],
            $porTipo['N']['iva'], $porTipo['R']['iva'], $porTipo['S']['iva'], $porTipo['E']['iva'],
            $porTipo['N']['recargo'], $porTipo['R']['recargo'], $porTipo['S']['recargo'], $porTipo['E']['recargo'],
            $totales['total_impuestos'], $totales['total_retencion'], $totales['porcentaje_retencion'],
            $totales['total_liquido'], $usuario,
            $serie, $numero,
        ]
    );
}

/** Cabecera de una factura por serie y número (para el PDF). */
function factura_leer(PDO $pdo, string $serie, string $numero): ?array
{
    return consultar_una(
        $pdo,
        'SELECT NUMERO_FAC, SERIE_FAC, FECHA_FAC, TIPO_FAC, FASE_FAC, ESCONSOLIDADA_FAC, CODIGO_EMP_FAC, ' .
        'RAZON_SOCIAL_EMPRESA_FAC, NIF_EMPRESA_FAC, MOVIL_EMPRESA_FAC, EMAIL_EMPRESA_FAC, ' .
        'DIRECCION1_EMPRESA_FAC, DIRECCION2_EMPRESA_FAC, POBLACION_EMPRESA_FAC, PROVINCIA_EMPRESA_FAC, ' .
        'CODIGO_POSTAL_EMPRESA_FAC, NOMBRE_PAI_EMPRESA_FAC, CODIGO_CLI_FAC, RAZON_SOCIAL_CLIENTE_FAC, ' .
        'NIF_CLIENTE_FAC, MOVIL_CLIENTE_FAC, EMAIL_CLIENTE_FAC, DIRECCION1_CLIENTE_FAC, ' .
        'DIRECCION2_CLIENTE_FAC, POBLACION_CLIENTE_FAC, PROVINCIA_CLIENTE_FAC, CODIGO_POSTAL_CLIENTE_FAC, ' .
        'NOMBRE_PAI_CLIENTE_FAC, ESIVA_RECARGO_CLIENTE_FAC, ESIVA_EXENTO_CLIENTE_FAC, ' .
        'ESRETENCIONES_CLIENTE_FAC, ESRETENCIONES_EMPRESA_FAC, ESIMP_INCL_TARIFA_CLIENTE_FAC, ' .
        'PALABRA_REPORTS_ZONA_IVA_FAC, PORCENTAJE_IVAN_FAC, PORCENTAJE_IVAR_FAC, PORCENTAJE_IVAS_FAC, ' .
        'PORCENTAJE_IVAE_FAC, PORCENTAJE_REN_FAC, PORCENTAJE_RER_FAC, PORCENTAJE_RES_FAC, PORCENTAJE_REE_FAC, ' .
        'TOTAL_BASEI_IVAN_FAC, TOTAL_BASEI_IVAR_FAC, TOTAL_BASEI_IVAS_FAC, TOTAL_BASEI_IVAE_FAC, ' .
        'TOTAL_IVAN_FAC, TOTAL_IVAR_FAC, TOTAL_IVAS_FAC, TOTAL_IVAE_FAC, ' .
        'TOTAL_REN_FAC, TOTAL_RER_FAC, TOTAL_RES_FAC, TOTAL_REE_FAC, TOTAL_BASES_FAC, TOTAL_IMPUESTOS_FAC, ' .
        'FORMA_PAGO_FAC, PORCENTAJE_RETENCION_FAC, TOTAL_RETENCION_FAC, TOTAL_LIQUIDO_FAC, ' .
        'TEXTO_LEGAL_CLIENTE_FAC, TEXTO_LEGAL_EMPRESA_FAC, COMENTARIOS_FAC, ' .
        /* Datos del ticket de la factura simplificada (almacén, caja, cajero y hora). */
        'CODIGO_ALM_FAC, CODIGO_CAJA_FAC, CODIGO_CAJERO_FAC, NUMERO_OPERACION_FAC, INSTANTE_ALTA ' .
        'FROM fza_facturas WHERE SERIE_FAC = ? AND NUMERO_FAC = ?',
        [$serie, $numero]
    );
}

/**
 * Trazabilidad por lote (F-LOTEC, scripts 776-779): las bases de datos que
 * no tienen todavía LOTE_FACLIN ni el catálogo de lotes leen las líneas como
 * antes.
 */
function lotes_lineas_disponibles(PDO $pdo): bool
{
    static $disponible = null;
    if ($disponible === null) {
        $fila = consultar_una(
            $pdo,
            'SELECT COUNT(*) AS N FROM INFORMATION_SCHEMA.COLUMNS ' .
            'WHERE TABLE_SCHEMA = DATABASE() AND (' .
            '(TABLE_NAME = ? AND COLUMN_NAME IN (?, ?)) OR (TABLE_NAME = ? AND COLUMN_NAME = ?))',
            ['fza_facturas_lineas', 'LOTE_FACLIN', 'FECHA_CADUCIDAD_FACLIN', 'fza_articulos_lotes', 'TIPO_LOT']
        );
        $disponible = (int)($fila['N'] ?? 0) === 3;
    }
    return $disponible;
}

/** Líneas de una factura en orden de línea (para el PDF y la modificación). */
function factura_lineas(PDO $pdo, string $serie, string $numero): array
{
    /* Lote o serie de la línea y su tipo en el catálogo (L lote, S serie,
       T temporada), para imprimirlos en el PDF. */
    $lotes = '';
    $catalogo = '';
    if (lotes_lineas_disponibles($pdo)) {
        $lotes = ', L.LOTE_FACLIN, L.FECHA_CADUCIDAD_FACLIN, LT.TIPO_LOT ';
        $catalogo = 'LEFT JOIN fza_articulos_lotes LT ' .
            'ON LT.CODIGO_UNIDAD_LOT = L.CODIGO_UNIDAD_FACLIN AND LT.LOTE_LOT = L.LOTE_FACLIN ';
    }
    return consultar(
        $pdo,
        'SELECT L.LINEA_FACLIN, L.CODIGO_ART_FACLIN, L.DESCRIPCION_ARTICULO_FACLIN, L.DESCRIPCION_VARIACION_FACLIN, ' .
        'L.TIPO_ARTICULO_FACLIN, L.CODIGO_FAM_FACLIN, ' .
        'L.TIPO_CANTIDAD_ARTICULO_FACLIN, L.CANTIDAD_FACLIN, L.PRECIO_SALIDA_FACLIN, L.PORCENTAJE_DTO_FACLIN, ' .
        'L.PRECIO_VENTA_SIVA_ARTICULO_FACLIN, L.PRECIO_VENTA_CIVA_ARTICULO_FACLIN, L.TIPO_IVA_ARTICULO_FACLIN, ' .
        'L.PORCENTAJE_IVA_FACLIN, L.ESIMP_INCL_TARIFA_FACLIN, L.TOTAL_FACLIN, L.TOTAL_FAC_SIVA_FACLIN' .
        $lotes . ' ' .
        'FROM fza_facturas_lineas L ' . $catalogo .
        'WHERE L.SERIE_FAC_FACLIN = ? AND L.NUMERO_FAC_FACLIN = ? ' .
        'ORDER BY L.LINEA_FACLIN',
        [$serie, $numero]
    );
}

/** Últimas facturas por fecha (histórico). $limite: 5, 10, 20 o 100. */
function facturas_ultimas(PDO $pdo, int $limite): array
{
    $limite = in_array($limite, [5, 10, 20, 100], true) ? $limite : 10;
    return consultar(
        $pdo,
        'SELECT NUMERO_FAC, SERIE_FAC, FECHA_FAC, FASE_FAC, ESCONSOLIDADA_FAC, TIPO_FAC, CODIGO_EMP_FAC, ' .
        'RAZON_SOCIAL_EMPRESA_FAC, RAZON_SOCIAL_CLIENTE_FAC, NIF_CLIENTE_FAC, TOTAL_LIQUIDO_FAC, INSTANTE_ALTA ' .
        'FROM fza_facturas ' .
        'ORDER BY FECHA_FAC DESC, INSTANTE_ALTA DESC, NUMERO_FAC DESC ' .
        'LIMIT ' . $limite
    );
}

/**
 * Cabeceras de las facturas con fecha entre $desde y $hasta (AAAA-MM-DD,
 * ambas incluidas), de una empresa emisora o de todas si $empresa es ''.
 * Para el resumen de facturas que se descarga para Excel.
 */
function facturas_entre_fechas(PDO $pdo, string $desde, string $hasta, string $empresa): array
{
    $sql = 'SELECT NUMERO_FAC, SERIE_FAC, FECHA_FAC, TIPO_FAC, TIPO_FACTURA_VERIFACTU_FAC, FASE_FAC, ' .
        'ESCONSOLIDADA_FAC, CODIGO_EMP_FAC, RAZON_SOCIAL_EMPRESA_FAC, NIF_EMPRESA_FAC, ' .
        'CODIGO_CLI_FAC, RAZON_SOCIAL_CLIENTE_FAC, NIF_CLIENTE_FAC, CODIGO_POSTAL_CLIENTE_FAC, ' .
        'POBLACION_CLIENTE_FAC, NOMBRE_PAI_CLIENTE_FAC, ' .
        'PORCENTAJE_IVAN_FAC, PORCENTAJE_IVAR_FAC, PORCENTAJE_IVAS_FAC, PORCENTAJE_IVAE_FAC, ' .
        'TOTAL_BASEI_IVAN_FAC, TOTAL_BASEI_IVAR_FAC, TOTAL_BASEI_IVAS_FAC, TOTAL_BASEI_IVAE_FAC, ' .
        'TOTAL_IVAN_FAC, TOTAL_IVAR_FAC, TOTAL_IVAS_FAC, TOTAL_IVAE_FAC, ' .
        'TOTAL_REN_FAC, TOTAL_RER_FAC, TOTAL_RES_FAC, TOTAL_REE_FAC, ' .
        'TOTAL_BASES_FAC, TOTAL_IMPUESTOS_FAC, PORCENTAJE_RETENCION_FAC, TOTAL_RETENCION_FAC, ' .
        'TOTAL_LIQUIDO_FAC, FORMA_PAGO_FAC, SERIE_FAC_ABONO_FAC, NUMERO_FAC_ABONO_FAC ' .
        'FROM fza_facturas WHERE FECHA_FAC BETWEEN ? AND ?';
    $parametros = [$desde, $hasta];
    if ($empresa !== '') {
        $sql .= ' AND CODIGO_EMP_FAC = ?';
        $parametros[] = $empresa;
    }
    return consultar($pdo, $sql . ' ORDER BY FECHA_FAC, SERIE_FAC, NUMERO_FAC', $parametros);
}

/** Solo se modifican o borran las facturas en borrador sin consolidar, como en el programa. */
function factura_editable(array $factura): bool
{
    return strtoupper(trim((string)($factura['FASE_FAC'] ?? ''))) === 'BORRADOR' &&
        !es_si((string)($factura['ESCONSOLIDADA_FAC'] ?? 'N'));
}

/** Borra una factura en borrador con sus líneas y pagos. Devuelve si existía. */
function factura_borrar(PDO $pdo, string $serie, string $numero): bool
{
    $pdo->beginTransaction();
    try {
        ejecutar($pdo, 'DELETE FROM fza_facturas_lineas WHERE SERIE_FAC_FACLIN = ? AND NUMERO_FAC_FACLIN = ?', [$serie, $numero]);
        ejecutar($pdo, 'DELETE FROM fza_facturas_pagos WHERE SERIE_FAC_FACPAG = ? AND NUMERO_FAC_FACPAG = ?', [$serie, $numero]);
        $borradas = ejecutar(
            $pdo,
            'DELETE FROM fza_facturas WHERE SERIE_FAC = ? AND NUMERO_FAC = ? ' .
            'AND FASE_FAC = \'BORRADOR\' AND COALESCE(ESCONSOLIDADA_FAC, \'N\') <> \'S\'',
            [$serie, $numero]
        );
        $pdo->commit();
        return $borradas > 0;
    } catch (Throwable $error) {
        $pdo->rollBack();
        throw $error;
    }
}

/** Quita las líneas de una factura y deja el contador de líneas a cero para renumerarlas. */
function factura_lineas_vaciar(PDO $pdo, string $serie, string $numero): void
{
    ejecutar($pdo, 'DELETE FROM fza_facturas_lineas WHERE SERIE_FAC_FACLIN = ? AND NUMERO_FAC_FACLIN = ?', [$serie, $numero]);
    ejecutar($pdo, 'UPDATE fza_facturas SET CONTADOR_LINEAS_FAC = \'0\' WHERE SERIE_FAC = ? AND NUMERO_FAC = ?', [$serie, $numero]);
}

/** Actualiza columnas de la cabecera (columna => valor; 'NOW()' se pasa tal cual). */
function factura_actualizar_cabecera(PDO $pdo, string $serie, string $numero, array $campos): void
{
    $asignaciones = [];
    $valores = [];
    foreach ($campos as $columna => $valor) {
        if (preg_match('/^[A-Z0-9_]+$/', (string)$columna) !== 1) {
            throw new LogicException("Columna no válida: $columna");
        }
        if ($valor === 'NOW()') {
            $asignaciones[] = $columna . ' = NOW()';
        } else {
            $asignaciones[] = $columna . ' = ?';
            $valores[] = $valor;
        }
    }
    if ($asignaciones === []) {
        return;
    }
    $valores[] = $serie;
    $valores[] = $numero;
    ejecutar(
        $pdo,
        'UPDATE fza_facturas SET ' . implode(', ', $asignaciones) . ' WHERE SERIE_FAC = ? AND NUMERO_FAC = ?',
        $valores
    );
}

/**
 * IBAN que se imprime en la factura: la cuenta de cobro asignada al cliente
 * (CODIGO_EMPBAN_CLI en fza_empresas_bancos); si no, la cuenta de cobro por
 * defecto de la empresa; si no, IBAN_EMP de fza_empresas.
 */
function iban_factura(PDO $pdo, string $codigoEmpresa, string $codigoCliente): string
{
    if (trim($codigoCliente) !== '') {
        $fila = consultar_una(
            $pdo,
            'SELECT B.IBAN_EMPBAN FROM fza_clientes C ' .
            'JOIN fza_empresas_bancos B ON B.CODIGO_EMPBAN = C.CODIGO_EMPBAN_CLI ' .
            'WHERE C.CODIGO_CLI_CLI = ? AND B.CODIGO_EMP_EMPBAN = ? ' .
            'AND COALESCE(B.ESACTIVO_EMPBAN, \'S\') = \'S\'',
            [$codigoCliente, $codigoEmpresa]
        );
        if ($fila !== null && trim((string)$fila['IBAN_EMPBAN']) !== '') {
            return trim((string)$fila['IBAN_EMPBAN']);
        }
    }
    $fila = consultar_una(
        $pdo,
        'SELECT IBAN_EMPBAN FROM fza_empresas_bancos ' .
        'WHERE CODIGO_EMP_EMPBAN = ? AND ESDEFECTO_COBRO_EMPBAN = \'S\' ' .
        'AND COALESCE(ESACTIVO_EMPBAN, \'S\') = \'S\' ' .
        'ORDER BY COALESCE(ORDEN_EMPBAN, 0), CODIGO_EMPBAN LIMIT 1',
        [$codigoEmpresa]
    );
    if ($fila !== null && trim((string)$fila['IBAN_EMPBAN']) !== '') {
        return trim((string)$fila['IBAN_EMPBAN']);
    }
    $empresa = empresa_por_codigo($pdo, $codigoEmpresa);
    return trim((string)($empresa['IBAN_EMP'] ?? ''));
}

/**
 * Forma de pago: ['descripcion' => ..., 'ver_banco' => bool]. 'ver_banco' es
 * ESVERBANCOEMPRESA_FORMA_PAGO_FP, que indica si en la factura debe
 * imprimirse la cuenta bancaria de la empresa.
 */
function forma_pago_leer(PDO $pdo, string $codigo): array
{
    $codigo = trim($codigo);
    if ($codigo === '') {
        return ['descripcion' => '', 'ver_banco' => false];
    }
    $fila = consultar_una(
        $pdo,
        'SELECT DESCRIPCION_FORMA_PAGO_FP, ESVERBANCOEMPRESA_FORMA_PAGO_FP ' .
        'FROM fza_formas_pago WHERE CODIGO_FP_FP = ?',
        [$codigo]
    );
    $descripcion = trim((string)($fila['DESCRIPCION_FORMA_PAGO_FP'] ?? ''));
    return [
        'descripcion' => $descripcion === '' ? $codigo : $descripcion,
        'ver_banco'   => $fila !== null && es_si((string)($fila['ESVERBANCOEMPRESA_FORMA_PAGO_FP'] ?? 'N')),
    ];
}

/** Descripción de una forma de pago (o el código si no existe). */
function forma_pago_descripcion(PDO $pdo, string $codigo): string
{
    return forma_pago_leer($pdo, $codigo)['descripcion'];
}

function factura_existe(PDO $pdo, string $numero, string $serie): bool
{
    return consultar_una(
        $pdo,
        'SELECT 1 AS EXISTE FROM fza_facturas WHERE NUMERO_FAC = ? AND SERIE_FAC = ?',
        [$numero, $serie]
    ) !== null;
}

/** Última fecha emitida en la serie (documentos que no son borrador). */
function factura_ultima_fecha_serie(PDO $pdo, string $serie, string $empresa): ?string
{
    $fila = consultar_una(
        $pdo,
        'SELECT MAX(FECHA_FAC) AS ULTIMA FROM fza_facturas ' .
        'WHERE SERIE_FAC = ? AND CODIGO_EMP_FAC = ? ' .
        'AND FECHA_FAC IS NOT NULL AND FASE_FAC <> \'BORRADOR\'',
        [$serie, $empresa]
    );
    $ultima = $fila['ULTIMA'] ?? null;
    return $ultima === null ? null : substr((string)$ultima, 0, 10);
}

/** Inserta la cabecera de factura. $fila es columna => valor. */
function factura_insertar(PDO $pdo, array $fila): void
{
    $columnas = [];
    $marcadores = [];
    $valores = [];
    foreach ($fila as $columna => $valor) {
        if (preg_match('/^[A-Z0-9_]+$/', (string)$columna) !== 1) {
            throw new LogicException("Columna no válida: $columna");
        }
        $columnas[] = $columna;
        if ($valor === 'NOW()') {
            $marcadores[] = 'NOW()';
        } else {
            $marcadores[] = '?';
            $valores[] = $valor;
        }
    }
    ejecutar(
        $pdo,
        'INSERT INTO fza_facturas (' . implode(', ', $columnas) . ') ' .
        'VALUES (' . implode(', ', $marcadores) . ')',
        $valores
    );
}

/* ===================== Ticket de la factura simplificada ===================== */

/** Empleados activos (fza_empleados), como la búsqueda de empleado de caja. */
function empleados_listar(PDO $pdo): array
{
    return consultar(
        $pdo,
        'SELECT CODIGO_EMPL, COALESCE(NOMBRE_EMPL, \'\') AS NOMBRE_EMPL, ' .
        'COALESCE(DIMINUTIVO_TICKET_EMPL, \'\') AS DIMINUTIVO_TICKET_EMPL ' .
        'FROM fza_empleados WHERE COALESCE(ESACTIVO_EMPL, \'S\') = \'S\' ' .
        'ORDER BY CODIGO_EMPL'
    );
}

/**
 * Diminutivo de ticket del empleado (ObtenerDiminutivoVendedor): si no tiene
 * o no existe, se devuelve el propio código para no dejar el dato en blanco.
 */
function empleado_diminutivo_ticket(PDO $pdo, string $codigo): string
{
    $codigo = trim($codigo);
    if ($codigo === '') {
        return '';
    }
    $fila = consultar_una(
        $pdo,
        'SELECT DIMINUTIVO_TICKET_EMPL FROM fza_empleados WHERE CODIGO_EMPL = ?',
        [$codigo]
    );
    $diminutivo = trim((string)($fila['DIMINUTIVO_TICKET_EMPL'] ?? ''));
    return $diminutivo === '' ? $codigo : $diminutivo;
}

/** Comprueba que el empleado existe (al elegirlo en parámetros). */
function empleado_existe(PDO $pdo, string $codigo): bool
{
    return consultar_una($pdo, 'SELECT CODIGO_EMPL FROM fza_empleados WHERE CODIGO_EMPL = ?', [$codigo]) !== null;
}

/**
 * Empleado que atiende las facturas simplificadas de la web: el mismo
 * parámetro de caja que rellena el empleado de una venta nueva
 * (vgerCodEmpleadoDefecto), con la prioridad usuario > grupo > Todos.
 */
function empleado_ticket_defecto(PDO $pdo, array $usuario): string
{
    return perfil_valor($pdo, $usuario, FORMULARIO_PARAMETROS_CAJA, 'vgerCodEmpleadoDefecto', '');
}

/** Columnas del pie de ticket de fza_empresas (TEXTO_PIE_TICKET_CAJA_1..4_EMP). */
const COLUMNAS_PIE_TICKET = [
    'TEXTO_PIE_TICKET_CAJA_1_EMP',
    'TEXTO_PIE_TICKET_CAJA_2_EMP',
    'TEXTO_PIE_TICKET_CAJA_3_EMP',
    'TEXTO_PIE_TICKET_CAJA_4_EMP',
];

/**
 * Comprueba que la empresa tiene las columnas del pie de ticket, como hace
 * el programa antes de leerlas (ComprobarPieTicketDisponible): las bases de
 * datos antiguas no las tienen.
 */
function pie_ticket_disponible(PDO $pdo): bool
{
    static $disponible = null;
    if ($disponible === null) {
        $fila = consultar_una(
            $pdo,
            'SELECT COUNT(*) AS N FROM INFORMATION_SCHEMA.COLUMNS ' .
            'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = \'fza_empresas\' ' .
            'AND COLUMN_NAME IN (?, ?, ?, ?)',
            COLUMNAS_PIE_TICKET
        );
        $disponible = (int)($fila['N'] ?? 0) === count(COLUMNAS_PIE_TICKET);
    }
    return $disponible;
}

/** Las cuatro líneas de pie de ticket de una empresa (ListarPieTicket). */
function empresa_pie_ticket(PDO $pdo, string $codigoEmpresa): array
{
    if (trim($codigoEmpresa) === '' || !pie_ticket_disponible($pdo)) {
        return ['', '', '', ''];
    }
    $fila = consultar_una(
        $pdo,
        'SELECT ' . implode(', ', COLUMNAS_PIE_TICKET) . ' FROM fza_empresas WHERE CODIGO_EMP_EMP = ?',
        [$codigoEmpresa]
    );
    $lineas = [];
    foreach (COLUMNAS_PIE_TICKET as $columna) {
        $lineas[] = trim((string)($fila[$columna] ?? ''));
    }
    return $lineas;
}

/**
 * Guarda el pie de ticket de una empresa en las mismas columnas que
 * Archivo -> Empresas del programa (42 caracteres por línea, como el papel).
 */
function empresa_pie_ticket_guardar(PDO $pdo, string $codigoEmpresa, array $lineas, string $usuario): void
{
    if (!pie_ticket_disponible($pdo)) {
        throw new RuntimeException(t('Esta base de datos no tiene las columnas del pie de ticket en las empresas.'));
    }
    $valores = [];
    foreach (COLUMNAS_PIE_TICKET as $indice => $columna) {
        $valores[] = mb_substr(trim((string)($lineas[$indice] ?? '')), 0, 42);
    }
    $valores[] = $usuario;
    $valores[] = $codigoEmpresa;
    ejecutar(
        $pdo,
        'UPDATE fza_empresas SET ' .
        implode(', ', array_map(static fn(string $columna): string => $columna . ' = ?', COLUMNAS_PIE_TICKET)) .
        ', INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? WHERE CODIGO_EMP_EMP = ?',
        $valores
    );
}
