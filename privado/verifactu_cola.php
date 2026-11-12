<?php
declare(strict_types=1);

/*
 * Emisión fiscal de facturas y cola Verifactu, con las mismas tablas y
 * transiciones que el programa (inLibEmisionFiscal, UniDataVerifactuCola*,
 * inLibVerifactuEnvio):
 *
 *   - Modo SIN: la factura pasa de BORRADOR a SIN_VERIFACTU y queda
 *     consolidada, sin cola ni envío.
 *   - Modo VERIFACTU (PRE o PRO): se valida la emisión, se encola en
 *     fza_verifactu_cola (FASE_FAC = VERIFACTU_PENDIENTE, evento 2) y la web
 *     procesa la cola en el acto: reclama la fila, compone el registro de alta
 *     con la cadena de huellas del emisor (fza_verifactu_cadena bloqueada con
 *     FOR UPDATE), lo envía por SOAP con el certificado de la empresa y
 *     persiste el resultado (fza_facturas_consolidaciones, cadena, fase
 *     VERIFACTU_OK, cola ENVIADA, evento 3) o el error (reintentos con
 *     espera exponencial, VERIFACTU_ERROR al agotarlos, evento 4).
 *   - Modo SII: misma cola y fases; cada fila sale por su SISTEMA_VFCOLA. Las
 *     del SII se envían sin cadena, huella ni QR (sii_registro.php) y dejan
 *     la consolidación en SII_PROCESADO / SII_ACEPT_ERR / SII_DUPLICADO /
 *     SII_MODIFICADO / SII_ANULADO (FZ-ISSUE-295).
 *
 * No hay hilo en segundo plano: la cola se procesa al emitir y desde el botón
 * "Procesar cola" del panel Verifactu.
 */

require_once __DIR__ . '/idiomas.php';
require_once __DIR__ . '/sii_registro.php';

final class VerifactuTransporteException extends RuntimeException
{
}

const VERIFACTU_COLA_SEGUNDOS_SIN_CONEXION = 300;

/* ===================== Mensajes del procesado de la cola ===================== */

/** Añade al resumen un mensaje para el usuario con su tipo de aviso ('ok' o 'aviso'). */
function verifactu_cola_mensaje(array &$resumen, string $tipo, string $texto): void
{
    $resumen['mensajes'][] = ['tipo' => $tipo, 'texto' => $texto];
}

/** Convierte los mensajes de un resumen de la cola en avisos de la sesión. */
function verifactu_cola_avisar(array $resumen): void
{
    foreach ($resumen['mensajes'] ?? [] as $mensaje) {
        if (is_array($mensaje)) {
            aviso((string)($mensaje['tipo'] ?? 'aviso'), (string)($mensaje['texto'] ?? ''));
        } else {
            aviso('aviso', (string)$mensaje);
        }
    }
}

/* ===================== Modo efectivo de la web ===================== */

/**
 * Modo con el que emite la web: 'SIN', 'PRE', 'PRO', 'SII' o 'NO_VERIFACTU'
 * (este último no se puede usar desde la web). Claves: modo, configurado,
 * entorno (en SII, el entorno PRE/PRO del SII).
 */
function verifactu_modo_web(PDO $pdo, array $usuario): array
{
    $configurado = verifactu_modo_configurado($pdo, $usuario);
    $entorno = verifactu_entorno($pdo, $usuario);
    $modo = $configurado === VERIFACTU_MODO_VERIFACTU ? $entorno : $configurado;
    return ['modo' => $modo, 'configurado' => $configurado, 'entorno' => $entorno];
}

function verifactu_modo_descripcion(string $modo): string
{
    return match ($modo) {
        'PRE' => t('VERIFACTU en pruebas (PRE)'),
        'PRO' => t('VERIFACTU en producción (PRO)'),
        'NO_VERIFACTU' => t('NO VERI*FACTU (no disponible en la web)'),
        'SII' => t('SII · Suministro Inmediato de Información'),
        default => t('SIN VERIFACTU'),
    };
}

/**
 * Cambia el modo de la web (SIN, PRE, PRO o SII) escribiendo appVerifactuActivo,
 * appVerifactuModo y appVerifactuEntorno en el ámbito del usuario. Para PRE,
 * PRO o SII hace falta tener cargado el certificado de alguna empresa. En SII
 * el entorno es PRE si se marca «SII en pruebas» y PRO si no.
 */
function verifactu_cambiar_modo(PDO $pdo, array $usuario, string $modo, bool $siiPruebas = false): string
{
    $modo = strtoupper(trim($modo));
    if (!in_array($modo, ['SIN', 'PRE', 'PRO', 'SII'], true)) {
        throw new RuntimeException(t('Modo no válido. Elige SIN, PRE, PRO o SII.'));
    }
    $anterior = verifactu_modo_web($pdo, $usuario)['modo'];
    if ($modo !== 'SIN' && certificados_empresas_disponibles($pdo) === []) {
        throw new RuntimeException(t(
            'Para pasar a {modo} hay que cargar antes el certificado de la empresa (para esta sesión o guardándolo en el servidor).',
            ['modo' => $modo]));
    }
    if ($modo === 'SIN') {
        $valores = ['appVerifactuActivo' => 'False'];
    } elseif ($modo === 'SII') {
        $valores = [
            'appVerifactuActivo'  => 'True',
            'appVerifactuModo'    => VERIFACTU_MODO_SII,
            'appVerifactuEntorno' => $siiPruebas ? 'PRE' : 'PRO',
        ];
    } else {
        $valores = [
            'appVerifactuActivo'  => 'True',
            'appVerifactuModo'    => VERIFACTU_MODO_VERIFACTU,
            'appVerifactuEntorno' => $modo,
        ];
    }
    parametros_app_guardar($pdo, (string)$usuario['usuario'], $valores);
    $aviso = registrar_evento_verifactu_seguro(
        $pdo, $usuario, EVENTO_VERIFACTU_CAMBIO_CONFIG, 'Cambio de configuración Verifactu',
        'Modo de la facturación web: ' . $anterior . ' -> ' . $modo .
        ($modo === 'SII' ? ($siiPruebas ? ' en pruebas (PRE)' : ' en producción (PRO)') : '') .
        ' (parámetros guardados para ' .
        (string)$usuario['usuario'] . ')');
    return $aviso === null ? '' : t('Modo cambiado, pero no se pudo anotar en el log Verifactu: {detalle}', ['detalle' => $aviso]);
}

/* ===================== Estados de la factura ===================== */

function fase_factura_texto(array $factura): string
{
    $fase = strtoupper(trim((string)($factura['FASE_FAC'] ?? '')));
    $consolidada = es_si((string)($factura['ESCONSOLIDADA_FAC'] ?? 'N'));
    return match ($fase) {
        FASE_FACTURA_BORRADOR => $consolidada ? t('Consolidada') : t('Borrador'),
        FASE_FACTURA_SIN_VERIFACTU => t('Emitida sin Verifactu'),
        'SIN_VERIF_ANULADA' => t('Anulada (sin Verifactu)'),
        FASE_FACTURA_VERIFACTU_PENDIENTE => t('Verifactu: pendiente de envío'),
        FASE_FACTURA_VERIFACTU_OK => t('Verifactu: enviada'),
        FASE_FACTURA_VERIFACTU_ERROR => t('Verifactu: error de envío'),
        FASE_FACTURA_VERIFACTU_ANULADA => t('Verifactu: anulada'),
        'NOVERIFACTU_OK' => t('NO VERI*FACTU: registrada'),
        'NOVERIFACTU_ANULADA' => t('NO VERI*FACTU: anulada'),
        'RECTIFICADA' => t('Rectificada'),
        '' => $consolidada ? t('Consolidada') : t('Sin fase'),
        default => ($consolidada ? t('Consolidada') . ' · ' : '') . ucfirst(strtolower($fase)),
    };
}

/**
 * True si la cola tiene la columna SISTEMA_VFCOLA (script 791). Sin ella la
 * base de datos es anterior al SII y todas las filas son de VERIFACTU.
 */
function verifactu_cola_tiene_sistema(PDO $pdo): bool
{
    static $tiene = null;
    if ($tiene === null) {
        $fila = consultar_una($pdo,
            "SELECT COUNT(*) AS N FROM information_schema.columns WHERE table_schema = DATABASE() " .
            "AND table_name = 'fza_verifactu_cola' AND column_name = 'SISTEMA_VFCOLA'");
        $tiene = (int)($fila['N'] ?? 0) > 0;
    }
    return $tiene;
}

/**
 * True si la factura se comunica por el SII: su consolidación está en un
 * estado SII_* o su alta está en la cola con SISTEMA_VFCOLA = 'SII'. Las
 * facturas del SII reutilizan las fases VERIFACTU_* pero no llevan QR.
 */
function factura_es_sii(PDO $pdo, string $serie, string $numero): bool
{
    $consolidacion = consolidacion_leer($pdo, $serie, $numero);
    if (str_starts_with(strtoupper((string)($consolidacion['ESTADO_FACCON'] ?? '')), 'SII_')) {
        return true;
    }
    if (!verifactu_cola_tiene_sistema($pdo)) {
        return false;
    }
    return consultar_una($pdo,
        "SELECT 1 AS SII FROM fza_verifactu_cola WHERE SERIE_FAC_VFCOLA = ? AND NUMERO_FAC_VFCOLA = ? " .
        "AND SISTEMA_VFCOLA = 'SII' LIMIT 1", [$serie, $numero]) !== null;
}

/** Facturas emitidas con Verifactu (llevan QR): pendiente, enviada o con error de envío. */
function factura_es_verifactu(array $factura): bool
{
    return in_array(strtoupper(trim((string)($factura['FASE_FAC'] ?? ''))), [
        FASE_FACTURA_VERIFACTU_PENDIENTE, FASE_FACTURA_VERIFACTU_OK, FASE_FACTURA_VERIFACTU_ERROR,
    ], true);
}

/* ===================== Datos de la factura para el registro ===================== */

/** Carga de la factura como CargarDatosFactura del programa; null si no existe. */
function verifactu_cargar_datos_factura(PDO $pdo, string $serie, string $numero): ?array
{
    $f = consultar_una(
        $pdo,
        'SELECT f.CODIGO_EMP_FAC, f.NIF_EMPRESA_FAC, f.RAZON_SOCIAL_EMPRESA_FAC, f.FECHA_FAC, f.TIPO_FAC, ' .
        'f.TIPO_RECTIFICATIVA_FAC, f.TIPO_FACTURA_VERIFACTU_FAC, f.NIF_CLIENTE_FAC, f.RAZON_SOCIAL_CLIENTE_FAC, ' .
        'f.TOTAL_IMPUESTOS_FAC, f.TOTAL_BASES_FAC, ' .
        'f.PORCENTAJE_IVAN_FAC, f.TOTAL_BASEI_IVAN_FAC, f.TOTAL_IVAN_FAC, f.PORCENTAJE_REN_FAC, f.TOTAL_REN_FAC, ' .
        'f.PORCENTAJE_IVAR_FAC, f.TOTAL_BASEI_IVAR_FAC, f.TOTAL_IVAR_FAC, f.PORCENTAJE_RER_FAC, f.TOTAL_RER_FAC, ' .
        'f.PORCENTAJE_IVAS_FAC, f.TOTAL_BASEI_IVAS_FAC, f.TOTAL_IVAS_FAC, f.PORCENTAJE_RES_FAC, f.TOTAL_RES_FAC, ' .
        'f.PORCENTAJE_IVAE_FAC, f.TOTAL_BASEI_IVAE_FAC, f.TOTAL_IVAE_FAC, f.TIPO_OPER_VFACTU_FAC, ' .
        'f.CODIGO_PAI_CLIENTE_FAC, pc.COD_ALPHA2_PAI, pc.ESMIEMBRO_UE_PAI, vo.CLAVE_REGIMEN_VFO, ' .
        'vo.CALIFICACION_VFO, vo.OPERACION_EXENTA_VFO, vo.ESREPERCUTE_IVA_VFO, e.CODIGO_CERTIFICADO_EMP, ' .
        'e.TITULAR_CERTIFICADO_EMP, e.NUMERO_INSTALACION_EMP, e.VERSION_INSTALACION_EMP, e.CODIGO_SIF_INSTALACION_EMP, ' .
        'e.FORMATO_DOCUMENTO_EMP ' .
        'FROM fza_facturas f ' .
        'LEFT JOIN fza_empresas e ON e.CODIGO_EMP_EMP = f.CODIGO_EMP_FAC ' .
        'LEFT JOIN fza_paises pc ON pc.CODIGO_PAI_PAI = f.CODIGO_PAI_CLIENTE_FAC ' .
        'LEFT JOIN fza_verifactu_operaciones vo ON vo.CODIGO_VFO = f.TIPO_OPER_VFACTU_FAC ' .
        'WHERE f.SERIE_FAC = ? AND f.NUMERO_FAC = ?',
        [$serie, $numero]
    );
    if ($f === null) {
        return null;
    }
    $tipoFac = strtoupper(trim((string)($f['TIPO_FAC'] ?? '')));
    $fechaIso = substr((string)$f['FECHA_FAC'], 0, 10);
    $datos = [
        'codigo_empresa'        => trim((string)$f['CODIGO_EMP_FAC']),
        'formato_documento'     => (string)($f['FORMATO_DOCUMENTO_EMP'] ?? ''),
        'nif_emisor'            => verifactu_normalizar_nif((string)$f['NIF_EMPRESA_FAC']),
        'nombre_emisor'         => trim((string)$f['RAZON_SOCIAL_EMPRESA_FAC']),
        'numero_instalacion'    => trim((string)($f['NUMERO_INSTALACION_EMP'] ?? '')),
        'version_instalacion'   => trim((string)($f['VERSION_INSTALACION_EMP'] ?? '')),
        'codigo_sif'            => trim((string)($f['CODIGO_SIF_INSTALACION_EMP'] ?? '')),
        'fecha_iso'             => $fechaIso,
        'fecha_expedicion'      => verifactu_fecha_aeat($fechaIso),
        'tipo_fac'              => $tipoFac,
        'tipo_factura'          => verifactu_tipo_factura($tipoFac),
        'tipo_rectificativa'    => '',
        'rect_serie'            => '',
        'rect_numero'           => '',
        'rect_fecha'            => '',
        'rect_base'             => 0.0,
        'rect_cuota'            => 0.0,
        'rect_cuota_re'         => 0.0,
        'tiene_importe_rectificacion' => false,
        'nif_cliente'           => verifactu_normalizar_nif((string)$f['NIF_CLIENTE_FAC']),
        'nombre_cliente'        => trim((string)$f['RAZON_SOCIAL_CLIENTE_FAC']),
        'cuota_total'           => (float)$f['TOTAL_IMPUESTOS_FAC'],
        /* Verifactu comunica el bruto de IVA, antes de descontar la retención. */
        'importe_total'         => verifactu_importe_total($f),
        'serial_cert'           => trim((string)($f['CODIGO_CERTIFICADO_EMP'] ?? '')),
        'titular_cert'          => trim((string)($f['TITULAR_CERTIFICADO_EMP'] ?? '')),
        'op_definida'           => trim((string)($f['TIPO_OPER_VFACTU_FAC'] ?? '')) !== '' && $f['CLAVE_REGIMEN_VFO'] !== null,
        'op_clave_regimen'      => trim((string)($f['CLAVE_REGIMEN_VFO'] ?? '')),
        'op_calificacion'       => trim((string)($f['CALIFICACION_VFO'] ?? '')),
        'op_operacion_exenta'   => trim((string)($f['OPERACION_EXENTA_VFO'] ?? '')),
        'op_repercute_iva'      => strcasecmp(trim((string)($f['ESREPERCUTE_IVA_VFO'] ?? '')), 'N') !== 0,
        'pais_cliente_iso2'     => trim((string)($f['COD_ALPHA2_PAI'] ?? '')),
        'cliente_ue'            => strcasecmp(trim((string)($f['ESMIEMBRO_UE_PAI'] ?? '')), 'S') === 0,
        'bandas'                => [],
    ];
    $datos['cliente_extranjero'] = $datos['pais_cliente_iso2'] !== '' &&
        strcasecmp($datos['pais_cliente_iso2'], 'ES') !== 0 &&
        trim((string)($f['CODIGO_PAI_CLIENTE_FAC'] ?? '')) !== '724';
    foreach ([['N', false], ['R', false], ['S', false], ['E', true]] as [$sufijo, $exenta]) {
        $datos['bandas'][] = [
            'porcentaje'        => (float)$f['PORCENTAJE_IVA' . $sufijo . '_FAC'],
            'base'              => (float)$f['TOTAL_BASEI_IVA' . $sufijo . '_FAC'],
            'cuota'             => (float)$f['TOTAL_IVA' . $sufijo . '_FAC'],
            'porcentaje_recargo' => $exenta ? 0.0 : (float)$f['PORCENTAJE_RE' . $sufijo . '_FAC'],
            'cuota_recargo'     => $exenta ? 0.0 : (float)$f['TOTAL_RE' . $sufijo . '_FAC'],
            'exenta'            => $exenta,
        ];
    }
    if ($tipoFac === 'RECTIFICATIVA') {
        $tipoVerifactu = strtoupper(trim((string)($f['TIPO_FACTURA_VERIFACTU_FAC'] ?? '')));
        if ($tipoVerifactu !== '' && !in_array($tipoVerifactu, ['R1', 'R2', 'R3', 'R4', 'R5'], true)) {
            throw new RuntimeException(t('El tipo VERI*FACTU de la rectificativa no es válido.'));
        }
        $datos['tipo_factura_rectificativa'] = $tipoVerifactu;
        $datos['tipo_rectificativa'] = strtoupper(trim((string)($f['TIPO_RECTIFICATIVA_FAC'] ?? ''))) ?: 'I';
        if (!in_array($datos['tipo_rectificativa'], ['I', 'S'], true)) {
            throw new RuntimeException(t('El tipo fiscal de rectificativa debe ser I o S.'));
        }
    }
    verifactu_cargar_antecesora($pdo, $serie, $numero, $datos);
    return $datos;
}

/** Factura rectificada o sustituida (fza_facturas_relaciones o enlace ABONO), como CargarAntecesora. */
function verifactu_cargar_antecesora(PDO $pdo, string $serie, string $numero, array &$datos): void
{
    if (!in_array($datos['tipo_fac'], ['RECTIFICATIVA', 'NORMAL'], true)) {
        return;
    }
    $importes = 'DATE_FORMAT(o.FECHA_FAC, \'%d-%m-%Y\') AS FECHA_TXT, COALESCE(o.TOTAL_BASES_FAC, 0) AS BASE_RECT, ' .
        'COALESCE(o.TOTAL_IVAN_FAC, 0) + COALESCE(o.TOTAL_IVAR_FAC, 0) + COALESCE(o.TOTAL_IVAS_FAC, 0) + ' .
        'COALESCE(o.TOTAL_IVAE_FAC, 0) AS CUOTA_RECT, COALESCE(o.TOTAL_REN_FAC, 0) + COALESCE(o.TOTAL_RER_FAC, 0) + ' .
        'COALESCE(o.TOTAL_RES_FAC, 0) + COALESCE(o.TOTAL_REE_FAC, 0) AS CUOTA_RE_RECT';
    $origen = consultar_una(
        $pdo,
        'SELECT o.SERIE_FAC, o.NUMERO_FAC, o.TIPO_FAC, ' . $importes . ' FROM fza_facturas_relaciones r ' .
        'JOIN fza_facturas o ON o.SERIE_FAC = r.SERIE_FAC_ORIGEN_FACREL AND o.NUMERO_FAC = r.NUMERO_FAC_ORIGEN_FACREL ' .
        'WHERE r.SERIE_FAC_FACREL = ? AND r.NUMERO_FAC_FACREL = ? ORDER BY r.ID_FACREL DESC LIMIT 1',
        [$serie, $numero]
    );
    if ($origen === null) {
        $origen = consultar_una(
            $pdo,
            'SELECT o.SERIE_FAC, o.NUMERO_FAC, o.TIPO_FAC, ' . $importes . ' FROM fza_facturas o ' .
            'WHERE o.SERIE_FAC_ABONO_FAC = ? AND o.NUMERO_FAC_ABONO_FAC = ? LIMIT 1',
            [$serie, $numero]
        );
    }
    if ($origen === null) {
        return;
    }
    $origenSimplificada = strcasecmp(trim((string)$origen['TIPO_FAC']), 'SIMPLIFICADA') === 0;
    if ($datos['tipo_fac'] === 'RECTIFICATIVA') {
        if (($datos['tipo_factura_rectificativa'] ?? '') !== '') {
            $datos['tipo_factura'] = $datos['tipo_factura_rectificativa'];
        } else {
            $datos['tipo_factura'] = $origenSimplificada ? 'R5' : 'R1';
        }
        $datos['rect_serie'] = (string)$origen['SERIE_FAC'];
        $datos['rect_numero'] = (string)$origen['NUMERO_FAC'];
        $datos['rect_fecha'] = (string)$origen['FECHA_TXT'];
        $datos['rect_base'] = (float)$origen['BASE_RECT'];
        $datos['rect_cuota'] = (float)$origen['CUOTA_RECT'];
        $datos['rect_cuota_re'] = (float)$origen['CUOTA_RE_RECT'];
        $datos['tiene_importe_rectificacion'] = true;
    } elseif ($origenSimplificada) {
        $datos['tipo_factura'] = 'F3';
        $datos['rect_serie'] = (string)$origen['SERIE_FAC'];
        $datos['rect_numero'] = (string)$origen['NUMERO_FAC'];
        $datos['rect_fecha'] = (string)$origen['FECHA_TXT'];
    }
}

/** Eslabón actual de la cadena del emisor, bloqueado (FOR UPDATE) dentro de la transacción en curso. */
function verifactu_obtener_cadena(PDO $pdo, string $usuario, string $nif): array
{
    ejecutar(
        $pdo,
        'INSERT IGNORE INTO fza_verifactu_cadena (NIF_VFCAD, CONTADOR_VFCAD, INSTANTE_ALTA, USUARIO_ALTA) VALUES (?, 0, NOW(), ?)',
        [$nif, $usuario]
    );
    $fila = consultar_una(
        $pdo,
        'SELECT CONTADOR_VFCAD, SERIE_FAC_VFCAD, NUMERO_FAC_VFCAD, DATE_FORMAT(FECHA_FAC_VFCAD, \'%d-%m-%Y\') AS FECHA_TXT, ' .
        'HUELLA_VFCAD FROM fza_verifactu_cadena WHERE NIF_VFCAD = ? FOR UPDATE',
        [$nif]
    );
    return [
        'contador' => (int)($fila['CONTADOR_VFCAD'] ?? 0),
        'serie'    => (string)($fila['SERIE_FAC_VFCAD'] ?? ''),
        'numero'   => (string)($fila['NUMERO_FAC_VFCAD'] ?? ''),
        'fecha'    => (string)($fila['FECHA_TXT'] ?? ''),
        'huella'   => trim((string)($fila['HUELLA_VFCAD'] ?? '')),
    ];
}

/** Bloque SistemaInformatico con los parámetros y la instalación SIF de la empresa emisora. */
function verifactu_sistema_informatico(PDO $pdo, array $usuario, array $datos): string
{
    $nombre = parametro_app($pdo, $usuario, 'appVerifactuSifNombreRazon', 'Alejandro Laorden Hidalgo');
    $nif = verifactu_normalizar_nif(parametro_app($pdo, $usuario, 'appVerifactuSifNif', ''));
    if (strlen($nif) !== 9) {
        throw new RuntimeException(t(
            'Parámetro appVerifactuSifNif (NIF del productor del software) vacío o no válido: "{nif}". Rellenarlo en Parámetros, categoría Verifactu.',
            ['nif' => $nif]));
    }
    verifactu_validar_instalacion_sif($datos['numero_instalacion'], $datos['version_instalacion'],
        $datos['codigo_sif'], $datos['nombre_emisor'], $datos['nif_emisor']);
    $activas = consultar_una($pdo, 'SELECT COUNT(*) AS N FROM fza_empresas WHERE ESACTIVO_EMP = \'S\'');
    $multiOt = (int)($activas['N'] ?? 0) > 1 ? 'S' : 'N';
    return verifactu_sistema_informatico_xml($nombre, $nif, $datos['version_instalacion'], $datos['numero_instalacion'], $multiOt);
}

/**
 * Compone el registro de alta de la factura (ConstruirRegistroFactura):
 * ['datos', 'cadena', 'registro', 'huella', 'fecha_hora_huso'] o null si la
 * factura no existe. Debe llamarse dentro de una transacción (bloquea la
 * cadena del emisor).
 */
function verifactu_construir_registro(PDO $pdo, array $usuario, string $serie, string $numero, string $tipoOperacion): ?array
{
    $datos = verifactu_cargar_datos_factura($pdo, $serie, $numero);
    if ($datos === null) {
        return null;
    }
    if (strlen($datos['nif_emisor']) !== 9) {
        throw new RuntimeException(t(
            'NIF de la empresa emisora vacío o no válido para Verifactu: "{nif}". Revisar la ficha de la empresa (NIF de 9 caracteres, sin guiones).',
            ['nif' => $datos['nif_emisor']]));
    }
    if (!in_array($tipoOperacion, ['ALTA', 'SUBSANACION', 'ANULACION'], true)) {
        throw new RuntimeException(t('La operación {operacion} no está disponible en la facturación web.', ['operacion' => $tipoOperacion]));
    }
    $cadena = verifactu_obtener_cadena($pdo, (string)$usuario['usuario'], $datos['nif_emisor']);
    $fechaHoraHuso = verifactu_fecha_hora_huso(new DateTimeImmutable('now'));
    $sif = verifactu_sistema_informatico($pdo, $usuario, $datos);
    if ($tipoOperacion === 'ANULACION') {
        verifactu_validar_destino_anulacion($pdo, $usuario, $serie, $numero);
        $datos['serie'] = $serie;
        $datos['numero'] = $numero;
        $registro = verifactu_registro_anulacion($datos, $cadena, $sif, $fechaHoraHuso);
        return ['datos' => $datos, 'cadena' => $cadena, 'registro' => $registro['xml'],
            'huella' => $registro['huella'], 'fecha_hora_huso' => $fechaHoraHuso];
    }

    $entradaDesglose = [
        'operacion' => [
            'definida'          => $datos['op_definida'],
            'clave_regimen'     => $datos['op_clave_regimen'],
            'calificacion'      => $datos['op_calificacion'],
            'operacion_exenta'  => $datos['op_operacion_exenta'],
            'repercute_iva'     => $datos['op_repercute_iva'],
            'cliente_ue'        => $datos['cliente_ue'],
            'cliente_extranjero' => $datos['cliente_extranjero'],
        ],
        'bandas' => $datos['bandas'],
    ];
    $entrada = [
        'serie'                     => $serie,
        'numero'                    => $numero,
        'num_serie_factura'         => verifactu_num_serie($datos['formato_documento'], $serie, $numero),
        'nif_emisor'                => $datos['nif_emisor'],
        'nombre_emisor'             => $datos['nombre_emisor'],
        'fecha_expedicion'          => $datos['fecha_expedicion'],
        'tipo_factura'              => $datos['tipo_factura'],
        'tipo_rectificativa'        => $datos['tipo_rectificativa'],
        'rect_numero'               => $datos['rect_numero'],
        'rect_num_serie_factura'    => verifactu_num_serie($datos['formato_documento'], $datos['rect_serie'], $datos['rect_numero']),
        'rect_fecha'                => $datos['rect_fecha'],
        'rect_base'                 => verifactu_formatear_importe($datos['rect_base']),
        'rect_cuota'                => verifactu_formatear_importe($datos['rect_cuota']),
        'rect_cuota_re'             => verifactu_formatear_importe($datos['rect_cuota_re']),
        'tiene_rect_cuota_re'       => abs($datos['rect_cuota_re']) > 0.001,
        'tiene_importe_rectificacion' => $datos['tiene_importe_rectificacion'],
        'nif_cliente'               => $datos['nif_cliente'],
        'nombre_cliente'            => $datos['nombre_cliente'],
        'pais_cliente_iso2'         => $datos['pais_cliente_iso2'],
        'cliente_ue'                => $datos['cliente_ue'],
        'cliente_extranjero'        => $datos['cliente_extranjero'],
        'cuota_total'               => verifactu_formatear_importe($datos['cuota_total']),
        'importe_total'             => verifactu_formatear_importe($datos['importe_total']),
        'cadena_num_serie_factura'  => verifactu_num_serie($datos['formato_documento'], $cadena['serie'], $cadena['numero']),
        'cadena_fecha'              => $cadena['fecha'],
        'huella_anterior'           => $cadena['huella'],
        'fecha_hora_huso'           => $fechaHoraHuso,
        'sistema_informatico_xml'   => $sif,
        'desglose_xml'              => verifactu_desglose_fiscal($entradaDesglose),
        'descripcion_operacion'     => parametro_app($pdo, $usuario, 'appVerifactuDescripcionOpe', 'Venta'),
        'subsanacion'               => $tipoOperacion === 'SUBSANACION',
    ];
    $registro = verifactu_registro_alta($entrada);
    return [
        'datos'           => $datos,
        'cadena'          => $cadena,
        'registro'        => $registro['xml'],
        'huella'          => $registro['huella'],
        'fecha_hora_huso' => $fechaHoraHuso,
    ];
}

/* ===================== Transporte HTTP ===================== */

function verifactu_url_envio(PDO $pdo, array $usuario): string
{
    return verifactu_entorno($pdo, $usuario) === 'PRO'
        ? parametro_app($pdo, $usuario, 'appVerifactuUrlEnvioPro')
        : parametro_app($pdo, $usuario, 'appVerifactuUrlEnvioPre');
}

/**
 * POST SOAP con certificado de cliente. Devuelve [código HTTP, cuerpo]. Los
 * fallos de conectividad (DNS, conexión, timeout) lanzan
 * VerifactuTransporteException para que la cola no consuma el intento.
 */
function verifactu_enviar_http(string $url, string $peticion, array $certificado): array
{
    if (!function_exists('curl_init')) {
        throw new RuntimeException(t('La extensión cURL de PHP no está disponible: no se puede enviar a la AEAT.'));
    }
    $temporales = [];
    $ch = curl_init($url);
    try {
        curl_setopt_array($ch, [
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $peticion,
            CURLOPT_HTTPHEADER => ['Content-Type: text/xml; charset=utf-8', 'SOAPAction: ""'],
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_CONNECTTIMEOUT => 30,
            CURLOPT_TIMEOUT => 90,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_SSLCERTTYPE => 'PEM',
            CURLOPT_SSLKEYTYPE => 'PEM',
        ]);
        /* Raíces de confianza para verificar el servidor de la AEAT: las del
           sistema salvo que config.php indique un fichero ('verifactu' =>
           ['ca_bundle' => ...]), necesario en PHP para Windows sin curl.cainfo. */
        $caBundle = (string)(configuracion()['verifactu']['ca_bundle'] ?? '');
        if ($caBundle !== '' && is_file($caBundle)) {
            curl_setopt($ch, CURLOPT_CAINFO, $caBundle);
        }
        /* El certificado y la clave van en memoria (sesión, o guardados en el
           servidor y descifrados al cargarlos): a cURL como blobs o, si es
           antiguo, como ficheros temporales en la carpeta privada. */
        if (defined('CURLOPT_SSLCERT_BLOB') && defined('CURLOPT_SSLKEY_BLOB')) {
            curl_setopt($ch, CURLOPT_SSLCERT_BLOB, $certificado['cert']);
            curl_setopt($ch, CURLOPT_SSLKEY_BLOB, $certificado['pkey']);
        } else {
            foreach (['cert', 'pkey'] as $parte) {
                $ruta = (string)tempnam(certificados_carpeta(), 'tmp_');
                file_put_contents($ruta, $certificado[$parte]);
                @chmod($ruta, 0600);
                $temporales[$parte] = $ruta;
            }
            curl_setopt($ch, CURLOPT_SSLCERT, $temporales['cert']);
            curl_setopt($ch, CURLOPT_SSLKEY, $temporales['pkey']);
        }
        $cuerpo = curl_exec($ch);
        $errno = curl_errno($ch);
        $error = curl_error($ch);
        $estado = (int)curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    } finally {
        curl_close($ch);
        foreach ($temporales as $ruta) {
            @unlink($ruta);
        }
    }
    if ($errno !== 0) {
        $mensaje = 'Error de conexión con la AEAT (cURL ' . $errno . '): ' . $error;
        /* Solo las caídas de conectividad se consideran temporales (como
           EsFalloTemporalTransporteHttp del programa): DNS, conexión, timeout
           y cortes de red que no sean un rechazo TLS del certificado. */
        $caida = in_array($errno, [CURLE_COULDNT_RESOLVE_HOST, CURLE_COULDNT_CONNECT, CURLE_OPERATION_TIMEOUTED,
            CURLE_GOT_NOTHING], true) ||
            (in_array($errno, [CURLE_SEND_ERROR, CURLE_RECV_ERROR], true) &&
                preg_match('/ssl|tls|alert|certificate|handshake/i', $error) !== 1);
        if ($caida) {
            throw new VerifactuTransporteException($mensaje);
        }
        throw new RuntimeException($mensaje);
    }
    return [$estado, (string)$cuerpo];
}

/* ===================== Envío de un registro ===================== */

function verifactu_resultado_vacio(): array
{
    return [
        'ok' => false, 'mensaje_error' => '', 'estado_registro' => '', 'codigo_error' => '',
        'descripcion_error' => '', 'espera_segundos' => 0, 'request_id' => '', 'issuer_irs_id' => '',
        'issued_time' => '', 'fecha_expedicion' => '', 'chain_number' => '', 'chain_hash' => '',
        'verifactu_url' => '', 'qr_base64' => '', 'qr_png' => '', 'registro_xml' => '', 'firma_digital' => '',
        'serie_certificado' => '', 'titular_certificado' => '', 'huella_certificado' => '',
        'peticion' => '', 'respuesta' => '',
    ];
}

/** URL de cotejo y QR (PNG y base64) para el resultado, como GenerarQrResultadoEnvio. */
function verifactu_generar_qr_resultado(PDO $pdo, array $usuario, array $datos, string $serie, string $numero, array &$resultado): void
{
    $base = verifactu_entorno($pdo, $usuario) === 'PRO'
        ? parametro_app($pdo, $usuario, 'appVerifactuUrlQRPro')
        : parametro_app($pdo, $usuario, 'appVerifactuUrlQRPre');
    $resultado['verifactu_url'] = verifactu_url_qr($base, $datos['nif_emisor'], $datos['formato_documento'], $serie, $numero, $datos['fecha_iso'], $datos['importe_total']);
    try {
        $resultado['qr_png'] = CodigoQR::png(CodigoQR::matriz($resultado['verifactu_url']));
        $resultado['qr_base64'] = base64_encode($resultado['qr_png']);
    } catch (Throwable $error) {
        $resultado['mensaje_error'] = sprintf('(QR PNG no generado: %s) ', $error->getMessage());
    }
}

/**
 * Envía a la AEAT el registro de alta de la factura (EnviarRegistroFactura).
 * Debe llamarse dentro de una transacción: deja bloqueada la fila de la
 * cadena del emisor hasta el commit o rollback del llamador.
 */
function verifactu_enviar_registro_factura(PDO $pdo, array $usuario, string $serie, string $numero, string $tipoOperacion, array $certificado): array
{
    $r = verifactu_resultado_vacio();
    $construido = verifactu_construir_registro($pdo, $usuario, $serie, $numero, $tipoOperacion);
    if ($construido === null) {
        $r['mensaje_error'] = sprintf('Factura %s\\%s no encontrada para el envío Verifactu', $serie, $numero);
        return $r;
    }
    $datos = $construido['datos'];
    $r['registro_xml'] = verifactu_registro_con_namespaces($construido['registro'],
        $tipoOperacion === 'ANULACION' ? 'RegistroAnulacion' : 'RegistroAlta');
    $r['firma_digital'] = $construido['huella'];
    $r['peticion'] = verifactu_envolver_soap($datos['nombre_emisor'], $datos['nif_emisor'], $construido['registro']);
    [$estadoHttp, $cuerpo] = verifactu_enviar_http(verifactu_url_envio($pdo, $usuario), $r['peticion'], $certificado);
    $r['respuesta'] = $cuerpo;
    $respuesta = verifactu_interpretar_respuesta($estadoHttp, $cuerpo);
    if ($tipoOperacion === 'ANULACION') {
        // Un duplicado genérico no acredita que se haya aceptado la anulación.
        $respuesta['aceptado'] = in_array(verifactu_extraer_etiqueta($cuerpo, 'EstadoRegistro'),
            ['Correcto', 'AceptadoConErrores'], true);
    }
    if (!$respuesta['http_correcto']) {
        $descripcion = $respuesta['descripcion_error'] !== '' ? $respuesta['descripcion_error'] : 'Respuesta inesperada del servicio';
        $r['mensaje_error'] = sprintf('AEAT HTTP %d: %s', $estadoHttp, $descripcion);
        return $r;
    }
    $r['codigo_error'] = $respuesta['codigo_error'];
    $r['descripcion_error'] = $respuesta['descripcion_error'];
    $r['espera_segundos'] = $respuesta['espera_segundos'];
    if (!$respuesta['aceptado']) {
        $descripcion = $respuesta['descripcion_error'];
        if ($respuesta['codigo_error'] === '' && $descripcion === '') {
            $descripcion = sprintf('EstadoEnvio: %s', $respuesta['estado_envio']);
        }
        $r['mensaje_error'] = trim(sprintf('AEAT [%s] %s', $respuesta['codigo_error'], $descripcion));
        return $r;
    }
    $r['ok'] = true;
    $r['estado_registro'] = $respuesta['duplicado'] ? 'Duplicado' : $respuesta['estado_registro'];
    $r['request_id'] = $respuesta['csv'];
    $r['issuer_irs_id'] = $datos['nif_emisor'];
    $r['issued_time'] = date('Y-m-d H:i:s');
    $r['fecha_expedicion'] = $datos['fecha_expedicion'];
    $r['chain_number'] = (string)($construido['cadena']['contador'] + 1);
    $r['chain_hash'] = $construido['huella'];
    if ($tipoOperacion !== 'ANULACION') {
        verifactu_generar_qr_resultado($pdo, $usuario, $datos, $serie, $numero, $r);
    }
    if ($respuesta['duplicado'] || strcasecmp($respuesta['estado_registro'], 'AceptadoConErrores') === 0) {
        $r['mensaje_error'] = trim($r['mensaje_error'] . sprintf('AEAT [%s] %s', $respuesta['codigo_error'], $respuesta['descripcion_error']));
    }
    return $r;
}

/* ===================== Envío al SII ===================== */

/** URL del servicio de facturas emitidas del SII; el entorno es el de VERI*FACTU. */
function sii_url_envio(PDO $pdo, array $usuario): string
{
    return verifactu_entorno($pdo, $usuario) === 'PRO'
        ? parametro_app($pdo, $usuario, 'appSiiUrlEnvioPro')
        : parametro_app($pdo, $usuario, 'appSiiUrlEnvioPre');
}

/** Clave de régimen del SII del tipo de operación de la factura (script 791); '' si no tiene. */
function sii_leer_clave_regimen(PDO $pdo, string $serie, string $numero): string
{
    $fila = consultar_una($pdo,
        'SELECT vo.CLAVE_REGIMEN_SII_VFO FROM fza_facturas f ' .
        'JOIN fza_verifactu_operaciones vo ON vo.CODIGO_VFO = f.TIPO_OPER_VFACTU_FAC ' .
        'WHERE f.SERIE_FAC = ? AND f.NUMERO_FAC = ?', [$serie, $numero]);
    return trim((string)($fila['CLAVE_REGIMEN_SII_VFO'] ?? ''));
}

/**
 * Envía al SII el alta (A0), la modificación (SUBSANACION → A1) o la baja
 * (ANULACION) de la factura (EnviarRegistroSiiConResultado). Sin cadena ni
 * huella: un reenvío idéntico lo resuelve el duplicado. Lo que no viene del
 * servicio del SII se trata como corte (VerifactuTransporteException).
 * Además de las claves de verifactu_resultado_vacio devuelve
 * 'rechazo_definitivo'.
 */
function sii_enviar_registro_factura(PDO $pdo, array $usuario, string $serie, string $numero, string $tipoOperacion, array $certificado): array
{
    $r = verifactu_resultado_vacio() + ['rechazo_definitivo' => false];
    if (!in_array($tipoOperacion, ['ALTA', 'SUBSANACION', 'ANULACION'], true)) {
        throw new RuntimeException(t('La operación {operacion} no está disponible en la facturación web.', ['operacion' => $tipoOperacion]));
    }
    $datos = verifactu_cargar_datos_factura($pdo, $serie, $numero);
    if ($datos === null) {
        $r['mensaje_error'] = sprintf('Factura %s\\%s no encontrada para el envío al SII', $serie, $numero);
        return $r;
    }
    if (strlen($datos['nif_emisor']) !== 9) {
        throw new RuntimeException(t(
            'NIF de la empresa emisora vacío o no válido para Verifactu: "{nif}". Revisar la ficha de la empresa (NIF de 9 caracteres, sin guiones).',
            ['nif' => $datos['nif_emisor']]));
    }
    $entrada = $datos + [
        'serie' => $serie,
        'numero' => $numero,
        'clave_regimen_sii' => sii_leer_clave_regimen($pdo, $serie, $numero),
        'tipo_operacion_defecto' => sii_tipo_operacion_desde_texto(
            parametro_app($pdo, $usuario, 'appSiiTipoOperacionDefecto', SII_TIPO_OPERACION_ENTREGA)),
        'descripcion_operacion' => parametro_app($pdo, $usuario, 'appVerifactuDescripcionOpe', 'Venta'),
    ];
    if ($tipoOperacion === 'ANULACION') {
        $r['registro_xml'] = sii_baja_lr_facturas_emitidas($entrada);
    } else {
        $r['registro_xml'] = sii_suministro_lr_facturas_emitidas($entrada, $tipoOperacion === 'SUBSANACION'
            ? SII_TIPO_COMUNICACION_MODIFICACION : SII_TIPO_COMUNICACION_ALTA);
    }
    $r['issuer_irs_id'] = $datos['nif_emisor'];
    $r['fecha_expedicion'] = $datos['fecha_expedicion'];
    $r['peticion'] = sii_envolver_soap($r['registro_xml']);
    [$estadoHttp, $cuerpo] = verifactu_enviar_http(sii_url_envio($pdo, $usuario), $r['peticion'], $certificado);
    $r['respuesta'] = $cuerpo;
    if (!sii_respuesta_definitiva($estadoHttp, $cuerpo)) {
        /* FZ-ISSUE-308: el mensaje dice qué ha contestado el servicio. */
        $extracto = sii_extracto_respuesta($cuerpo);
        if ($extracto === '') {
            $extracto = t('respuesta vacía');
        }
        throw new VerifactuTransporteException(sii_es_pagina_web($cuerpo)
            ? t('AEAT HTTP {http}: en lugar del servicio del SII ha llegado una página web («{extracto}»). Suele ser el certificado de cliente (no se envía o no vale para el SII de este entorno) o un proxy. Se reintentará sin consumir intento.',
                ['http' => $estadoHttp, 'extracto' => $extracto])
            : t('AEAT HTTP {http} sin respuesta válida del SII; ha contestado: «{extracto}». Se reintentará sin consumir intento.',
                ['http' => $estadoHttp, 'extracto' => $extracto]));
    }
    $respuesta = sii_interpretar_respuesta($estadoHttp, $cuerpo);
    $r['codigo_error'] = $respuesta['codigo_error'];
    $r['descripcion_error'] = $respuesta['descripcion_error'];
    if (!$respuesta['http_correcto']) {
        $descripcion = $respuesta['descripcion_error'] !== '' ? $respuesta['descripcion_error'] : 'Respuesta inesperada del servicio';
        $r['mensaje_error'] = sprintf('AEAT HTTP %d: %s', $estadoHttp, $descripcion);
        return $r;
    }
    $r['estado_registro'] = $respuesta['estado_registro'];
    if (!$respuesta['aceptado']) {
        $descripcion = $respuesta['descripcion_error'];
        if ($respuesta['codigo_error'] === '' && $descripcion === '') {
            $descripcion = sprintf('EstadoEnvio: %s', $respuesta['estado_envio']);
        }
        $r['mensaje_error'] = trim(sprintf('AEAT [%s] %s', $respuesta['codigo_error'], $descripcion));
        $r['rechazo_definitivo'] = sii_rechazo_definitivo($respuesta['estado_registro'], $respuesta['codigo_error']);
        return $r;
    }
    $r['ok'] = true;
    if ($respuesta['duplicado']) {
        $r['estado_registro'] = 'Duplicado';
    }
    /* CSV del envío; en un duplicado, el del alta que ya estaba. */
    $r['request_id'] = $respuesta['csv'] !== '' || !$respuesta['duplicado']
        ? $respuesta['csv'] : $respuesta['csv_registro_duplicado'];
    $r['issued_time'] = date('Y-m-d H:i:s');
    if ($respuesta['duplicado'] || $respuesta['aceptado_con_errores']) {
        $r['mensaje_error'] = trim(sprintf('AEAT [%s] %s', $respuesta['codigo_error'], $respuesta['descripcion_error']));
    }
    return $r;
}

/** Estado de la consolidación tras un envío aceptado (CrearPlanResultadoEnvioVerifactu). */
function verifactu_estado_consolidacion(string $sistema, string $tipoOperacion, string $estadoRegistro): string
{
    $prefijo = $sistema === VERIFACTU_MODO_SII ? 'SII_' : 'VERIFACTU_';
    if ($tipoOperacion === 'ANULACION') {
        return $prefijo . 'ANULADO';
    }
    if (strcasecmp($estadoRegistro, 'AceptadoConErrores') === 0) {
        return $prefijo . 'ACEPT_ERR';
    }
    if ($tipoOperacion === 'SUBSANACION') {
        return $sistema === VERIFACTU_MODO_SII ? 'SII_MODIFICADO' : 'VERIFACTU_SUBSANADO';
    }
    if (strcasecmp($estadoRegistro, 'Duplicado') === 0) {
        return $prefijo . 'DUPLICADO';
    }
    return $prefijo . 'PROCESADO';
}

/* ===================== Persistencia del resultado ===================== */

/**
 * Guarda un envío aceptado (GuardarEnvioOk): cadena, consolidación, fase y
 * cola. El SII no encadena: fza_verifactu_cadena no cambia. False si la cola
 * ya estaba ENVIADA.
 */
function verifactu_guardar_envio_ok(PDO $pdo, array $usuario, int $idCola, string $serie, string $numero, string $tipoOperacion, array $r,
    string $sistema = VERIFACTU_MODO_VERIFACTU): bool
{
    $estadoCola = consultar_una($pdo, 'SELECT ESTADO_VFCOLA FROM fza_verifactu_cola WHERE ID_VFCOLA = ?', [$idCola]);
    if ($estadoCola !== null && strcasecmp((string)$estadoCola['ESTADO_VFCOLA'], 'ENVIADA') === 0) {
        return false;
    }
    $nombreUsuario = (string)$usuario['usuario'];
    $estadoConsolidacion = verifactu_estado_consolidacion($sistema, $tipoOperacion, (string)$r['estado_registro']);
    if ($sistema !== VERIFACTU_MODO_SII) {
        ejecutar(
            $pdo,
            'UPDATE fza_verifactu_cadena SET CONTADOR_VFCAD = ?, SERIE_FAC_VFCAD = ?, NUMERO_FAC_VFCAD = ?, ' .
            'FECHA_FAC_VFCAD = STR_TO_DATE(?, \'%d-%m-%Y\'), HUELLA_VFCAD = ?, INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? ' .
            'WHERE NIF_VFCAD = ?',
            [$r['chain_number'], $serie, $numero, $r['fecha_expedicion'], $r['chain_hash'], $nombreUsuario, $r['issuer_irs_id']]
        );
    }
    if ($tipoOperacion === 'ANULACION') {
        verifactu_guardar_anulacion_aceptada($pdo, $idCola, $serie, $numero, $r, $estadoConsolidacion);
    } else {
    $consulta = $pdo->prepare(
        'INSERT INTO fza_facturas_consolidaciones (ID_FACCON, SERIE_FAC_FACCON, NUMERO_FAC_FACCON, ' .
        'REQUEST_ID_CONSOLIDACION_FACCON, QUEUE_ID_CONSOLIDACION_FACCON, ISSUER_IRS_ID_CONSOLIDACION_FACCON, ' .
        'ISSUED_TIME_FACCON, CHAIN_NUMBER_FACCON, CHAIN_HASH_FACCON, VERIFACTU_URL_FACCON, QRCODE_BASE64_FACCON, ' .
        'QRCODE_PNG_FACCON, FECHA_PROCESAMIENTO_FACCON, ESTADO_FACCON, CODIGO_ERROR_AEAT_FACCON, ' .
        'DESCRIPCION_ERROR_AEAT_FACCON, RESPUESTA_COMPLETA_FACCON, PETICION_COMPLETA_FACCON, REGISTRO_XML_FACCON, ' .
        'FIRMA_DIGITAL_FACCON, SERIE_CERTIFICADO_FACCON, TITULAR_CERTIFICADO_FACCON, HUELLA_CERTIFICADO_FACCON) ' .
        'SELECT IFNULL(MAX(ID_FACCON), 0) + 1, ?, ?, NULLIF(?, \'\'), ?, NULLIF(?, \'\'), ?, NULLIF(?, \'\'), ' .
        'NULLIF(?, \'\'), NULLIF(?, \'\'), NULLIF(?, \'\'), ?, NOW(), ?, NULLIF(?, \'\'), NULLIF(?, \'\'), ' .
        'NULLIF(?, \'\'), NULLIF(?, \'\'), ?, ?, ?, ?, ? FROM fza_facturas_consolidaciones'
    );
    $valores = [
        $serie, $numero, $r['request_id'], $idCola, $r['issuer_irs_id'],
        $r['issued_time'] !== '' ? $r['issued_time'] : null,
        $r['chain_number'], $r['chain_hash'], $r['verifactu_url'], $r['qr_base64'],
    ];
    $posicion = 1;
    foreach ($valores as $valor) {
        $consulta->bindValue($posicion++, $valor, $valor === null ? PDO::PARAM_NULL : PDO::PARAM_STR);
    }
    $consulta->bindValue($posicion++, $r['qr_png'] !== '' ? $r['qr_png'] : null, $r['qr_png'] !== '' ? PDO::PARAM_LOB : PDO::PARAM_NULL);
    foreach ([$estadoConsolidacion, $r['codigo_error'], $r['descripcion_error'], $r['respuesta'], $r['peticion'],
        $r['registro_xml'], $r['firma_digital'], $r['serie_certificado'], $r['titular_certificado'],
        $r['huella_certificado']] as $valor) {
        $consulta->bindValue($posicion++, $valor, PDO::PARAM_STR);
    }
    $consulta->execute();
    $consulta->closeCursor();
    }
    $fase = $tipoOperacion === 'ANULACION' ? FASE_FACTURA_VERIFACTU_ANULADA : FASE_FACTURA_VERIFACTU_OK;
    ejecutar(
        $pdo,
        'UPDATE fza_facturas SET ESCONSOLIDADA_FAC = \'S\', INSTANTECONSO_FAC = NOW(), FASE_FAC = ?, ' .
        'INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? WHERE SERIE_FAC = ? AND NUMERO_FAC = ?',
        [$fase, $nombreUsuario, $serie, $numero]
    );
    ejecutar(
        $pdo,
        'UPDATE fza_verifactu_cola SET ESTADO_VFCOLA = \'ENVIADA\', INSTANTE_ENVIO_VFCOLA = NOW(), ' .
        'MENSAJE_ERROR_VFCOLA = NULLIF(?, \'\'), INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? WHERE ID_VFCOLA = ?',
        [$r['mensaje_error'], $nombreUsuario, $idCola]
    );
    return true;
}

/** Guarda un envío fallido (GuardarEnvioError): reintento con espera, ERROR al agotar intentos y evento. */
function verifactu_guardar_envio_error(
    PDO $pdo,
    array $usuario,
    int $idCola,
    string $serie,
    string $numero,
    string $mensaje,
    int $intentos,
    bool $noConsumirIntento = false,
    int $esperaSinIntento = 0,
    bool $rechazoDefinitivo = false
): void {
    $nombreUsuario = (string)$usuario['usuario'];
    if ($noConsumirIntento) {
        $estado = 'PENDIENTE';
        $espera = $esperaSinIntento < 1 ? 60 : $esperaSinIntento;
        $incremento = 0;
        $actualizarFactura = false;
    } elseif ($rechazoDefinitivo) {
        /* Rechazo por los datos (EsRechazoDefinitivoSii): reenviar daría lo mismo. */
        $estado = 'ERROR';
        $espera = 0;
        $incremento = 1;
        $actualizarFactura = true;
    } else {
        $maximo = parametro_app_int($pdo, $usuario, 'appVerifactuMaxIntentos', 10);
        $estado = verifactu_estado_reintento($intentos, $maximo);
        $espera = verifactu_espera_reintento($intentos);
        $incremento = 1;
        $actualizarFactura = $estado === 'ERROR';
    }
    ejecutar(
        $pdo,
        'UPDATE fza_verifactu_cola SET ESTADO_VFCOLA = ?, CONTADOR_INTENTOS_VFCOLA = CONTADOR_INTENTOS_VFCOLA + ?, ' .
        'INSTANTE_PROXIMO_INTENTO_VFCOLA = DATE_ADD(NOW(), INTERVAL ? SECOND), MENSAJE_ERROR_VFCOLA = ?, ' .
        'INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? WHERE ID_VFCOLA = ?',
        [$estado, $incremento, $espera, $mensaje, $nombreUsuario, $idCola]
    );
    $operacion = consultar_una($pdo,
        'SELECT TIPO_OPERACION_VFCOLA FROM fza_verifactu_cola WHERE ID_VFCOLA = ?', [$idCola]);
    if ($actualizarFactura && ($operacion['TIPO_OPERACION_VFCOLA'] ?? '') !== 'ANULACION') {
        ejecutar(
            $pdo,
            'UPDATE fza_facturas SET FASE_FAC = ?, INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? WHERE SERIE_FAC = ? AND NUMERO_FAC = ?',
            [FASE_FACTURA_VERIFACTU_ERROR, $nombreUsuario, $serie, $numero]
        );
    }
    if ($noConsumirIntento) {
        registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_INFO,
            'Envío Verifactu aplazado por falta de conexión; el intento no se contabiliza: ' . $mensaje, '', $serie, $numero);
    } else {
        registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_ENVIO_ERROR,
            'Error de envío Verifactu (intento ' . ($intentos + 1) . '): ' . $mensaje, '', $serie, $numero);
    }
}

/* ===================== Procesado de la cola ===================== */

/**
 * Procesa una fila (ProcesarFila del programa). Devuelve los segundos de
 * espera que pide la AEAT, 0 si no hay que esperar o -1 si falló la conexión.
 */
function verifactu_cola_procesar_fila(PDO $pdo, array $usuario, array $fila, array $certificado, array &$resumen): int
{
    $idCola = (int)$fila['ID_VFCOLA'];
    $serie = (string)$fila['SERIE_FAC_VFCOLA'];
    $numero = (string)$fila['NUMERO_FAC_VFCOLA'];
    $tipoOperacion = (string)$fila['TIPO_OPERACION_VFCOLA'];
    $intentos = (int)$fila['CONTADOR_INTENTOS_VFCOLA'];
    /* Cada fila sale por el sistema con el que se encoló (sin la columna, VERI*FACTU). */
    $sistema = strtoupper(trim((string)($fila['SISTEMA_VFCOLA'] ?? ''))) === VERIFACTU_MODO_SII
        ? VERIFACTU_MODO_SII : VERIFACTU_MODO_VERIFACTU;
    $nombreUsuario = (string)$usuario['usuario'];
    $reclamadas = ejecutar(
        $pdo,
        'UPDATE fza_verifactu_cola SET ESTADO_VFCOLA = \'PROCESANDO\', INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? ' .
        'WHERE ID_VFCOLA = ? AND ESTADO_VFCOLA = \'PENDIENTE\'',
        [$nombreUsuario, $idCola]
    );
    if ($reclamadas !== 1) {
        return 0;
    }
    $resumen['procesadas']++;
    $etiqueta = $serie . '\\' . $numero;
    try {
        $pdo->beginTransaction();
        $resultado = $sistema === VERIFACTU_MODO_SII
            ? sii_enviar_registro_factura($pdo, $usuario, $serie, $numero, $tipoOperacion, $certificado)
            : verifactu_enviar_registro_factura($pdo, $usuario, $serie, $numero, $tipoOperacion, $certificado);
        if ($resultado['ok']) {
            try {
                $aplicado = verifactu_guardar_envio_ok($pdo, $usuario, $idCola, $serie, $numero, $tipoOperacion, $resultado,
                    $sistema);
                $textoEvento = 'Registro de facturación (' . $tipoOperacion . ') aceptado por la AEAT (' .
                    $resultado['estado_registro'] . ')';
                if ($aplicado && $sistema === VERIFACTU_MODO_SII) {
                    /* El SII no es un SIF: sin productor configurado el evento no se anota. */
                    registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_ENVIO_OK, $textoEvento . ' (SII)',
                        'CSV: ' . $resultado['request_id'], $serie, $numero);
                } elseif ($aplicado) {
                    registrar_evento_verifactu($pdo, $usuario, EVENTO_VERIFACTU_ENVIO_OK, $textoEvento,
                        'CSV: ' . $resultado['request_id'], $serie, $numero);
                }
                $pdo->commit();
                $resumen['enviadas']++;
                verifactu_cola_mensaje($resumen, 'ok',
                    t('Factura {factura} aceptada por la AEAT ({estado})', ['factura' => $etiqueta, 'estado' => $resultado['estado_registro']]) .
                    ($resultado['request_id'] !== '' ? ', CSV ' . $resultado['request_id'] : '') .
                    ($resultado['mensaje_error'] !== '' ? '. ' . $resultado['mensaje_error'] : '') . '.');
                return $resultado['espera_segundos'];
            } catch (Throwable $error) {
                if ($pdo->inTransaction()) {
                    $pdo->rollBack();
                }
                $mensaje = 'Aceptado por la AEAT pero falló la persistencia local: ' . $error->getMessage();
                verifactu_guardar_envio_error($pdo, $usuario, $idCola, $serie, $numero, $mensaje, $intentos);
                $resumen['errores']++;
                verifactu_cola_mensaje($resumen, 'aviso', t('Factura {factura}: {mensaje}', ['factura' => $etiqueta, 'mensaje' => $mensaje]));
                return 0;
            }
        }
        $pdo->rollBack();
        verifactu_guardar_envio_error($pdo, $usuario, $idCola, $serie, $numero, $resultado['mensaje_error'], $intentos,
            false, 0, !empty($resultado['rechazo_definitivo']));
        $resumen['errores']++;
        verifactu_cola_mensaje($resumen, 'aviso', t('Factura {factura} rechazada: {error}', ['factura' => $etiqueta, 'error' => $resultado['mensaje_error']]));
        return 0;
    } catch (VerifactuTransporteException $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        verifactu_guardar_envio_error($pdo, $usuario, $idCola, $serie, $numero, $error->getMessage(), $intentos,
            true, VERIFACTU_COLA_SEGUNDOS_SIN_CONEXION);
        $resumen['aplazadas']++;
        verifactu_cola_mensaje($resumen, 'aviso', t('Factura {factura} aplazada (sin conexión con la AEAT): {error}', ['factura' => $etiqueta, 'error' => $error->getMessage()]));
        return -1;
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        verifactu_guardar_envio_error($pdo, $usuario, $idCola, $serie, $numero, $error->getMessage(), $intentos);
        $resumen['errores']++;
        verifactu_cola_mensaje($resumen, 'aviso', t('Factura {factura}: {mensaje}', ['factura' => $etiqueta, 'mensaje' => $error->getMessage()]));
        return 0;
    }
}

/**
 * Procesa las filas pendientes de la cola (ProcesarPendientes del programa).
 * Devuelve ['procesadas', 'enviadas', 'errores', 'aplazadas', 'sin_certificado', 'mensajes'].
 */
function verifactu_cola_procesar(PDO $pdo, array $usuario, int $maximo = 25): array
{
    $resumen = ['procesadas' => 0, 'enviadas' => 0, 'errores' => 0, 'aplazadas' => 0, 'sin_certificado' => 0, 'mensajes' => []];
    $modo = verifactu_modo_web($pdo, $usuario);
    if (!in_array($modo['configurado'], [VERIFACTU_MODO_VERIFACTU, VERIFACTU_MODO_SII], true)) {
        verifactu_cola_mensaje($resumen, 'aviso', t('La cola solo se procesa en modo VERIFACTU (PRE o PRO) o SII; el modo actual es {modo}.',
            ['modo' => verifactu_modo_descripcion($modo['modo'])]));
        return $resumen;
    }
    /*
     * Cada fila sale por su SISTEMA_VFCOLA (FZ-ISSUE-295): al cambiar de PRO
     * a SII, lo que quedó pendiente de VERIFACTU se termina de enviar como
     * VERIFACTU, como hace el hilo del programa.
     */
    $columnaSistema = verifactu_cola_tiene_sistema($pdo) ? ', q.SISTEMA_VFCOLA' : '';
    $maxIntentos = parametro_app_int($pdo, $usuario, 'appVerifactuMaxIntentos', 10);
    /* Rescate de filas PROCESANDO huérfanas y reproceso de ERROR con intentos disponibles. */
    ejecutar(
        $pdo,
        'UPDATE fza_verifactu_cola SET ESTADO_VFCOLA = \'PENDIENTE\', INSTANTE_MODIF = NOW() ' .
        'WHERE ESTADO_VFCOLA = \'PROCESANDO\' AND INSTANTE_MODIF < DATE_SUB(NOW(), INTERVAL 10 MINUTE)'
    );
    ejecutar(
        $pdo,
        'UPDATE fza_verifactu_cola SET ESTADO_VFCOLA = \'PENDIENTE\', INSTANTE_PROXIMO_INTENTO_VFCOLA = NULL, ' .
        'INSTANTE_MODIF = NOW() WHERE ESTADO_VFCOLA = \'ERROR\' AND CONTADOR_INTENTOS_VFCOLA < ?',
        [$maxIntentos]
    );
    $filas = consultar(
        $pdo,
        'SELECT q.ID_VFCOLA, q.SERIE_FAC_VFCOLA, q.NUMERO_FAC_VFCOLA, q.TIPO_OPERACION_VFCOLA, ' .
        'q.CONTADOR_INTENTOS_VFCOLA' . $columnaSistema . ', f.CODIGO_EMP_FAC, f.RAZON_SOCIAL_EMPRESA_FAC ' .
        'FROM fza_verifactu_cola q LEFT JOIN fza_facturas f ' .
        'ON f.SERIE_FAC = q.SERIE_FAC_VFCOLA AND f.NUMERO_FAC = q.NUMERO_FAC_VFCOLA ' .
        'WHERE q.ESTADO_VFCOLA = \'PENDIENTE\' AND (q.INSTANTE_PROXIMO_INTENTO_VFCOLA IS NULL ' .
        'OR q.INSTANTE_PROXIMO_INTENTO_VFCOLA <= NOW())' .
        ' ORDER BY q.ID_VFCOLA LIMIT ' . max(1, min(100, $maximo))
    );
    $certificados = [];
    foreach ($filas as $fila) {
        $empresa = trim((string)($fila['CODIGO_EMP_FAC'] ?? ''));
        if (!array_key_exists($empresa, $certificados)) {
            $certificados[$empresa] = $empresa === '' ? null : certificado_disponible($empresa);
        }
        $certificado = $certificados[$empresa];
        if ($certificado === null || !$certificado['datos']['vigente']) {
            /* Sin certificado no se reclama la fila ni se consume el intento. */
            $resumen['sin_certificado']++;
            continue;
        }
        $espera = verifactu_cola_procesar_fila($pdo, $usuario, $fila, $certificado, $resumen);
        if ($espera < 0) {
            break;
        }
        if ($espera > 0) {
            /* Control de flujo de la AEAT: esperas cortas se respetan; largas, en la próxima pasada. */
            if ($espera <= 10) {
                sleep($espera);
            } else {
                verifactu_cola_mensaje($resumen, 'aviso', t('La AEAT pide esperar {segundos} segundos antes del siguiente envío; las demás facturas quedan para la próxima pasada.',
                    ['segundos' => $espera]));
                break;
            }
        }
    }
    if ($resumen['sin_certificado'] > 0) {
        verifactu_cola_mensaje($resumen, 'aviso', t('{n} factura(s) pendiente(s) no se han enviado porque su empresa no tiene un certificado vigente cargado.',
            ['n' => $resumen['sin_certificado']]));
    }
    return $resumen;
}

/* ===================== Emisión de una factura ===================== */

/**
 * Comprueba los requisitos fiscales antes de encolar (ValidarRequisitosFiscalesEmision)
 * y adelanta los errores que la AEAT rechazaría (NIF del cliente en F1). En
 * el SII no hay productor del software ni instalación SIF: solo NIF y certificado.
 */
function verifactu_validar_emision(PDO $pdo, array $usuario, string $serie, string $numero, bool $sii = false): array
{
    $datos = verifactu_cargar_datos_factura($pdo, $serie, $numero);
    if ($datos === null) {
        throw new RuntimeException(t('No existe la factura {factura} para validar sus requisitos fiscales.', ['factura' => $serie . '\\' . $numero]));
    }
    $nombreEmpresa = $datos['nombre_emisor'] !== '' ? $datos['nombre_emisor'] : $datos['codigo_empresa'];
    if (strlen($datos['nif_emisor']) !== 9) {
        throw new RuntimeException(t('La empresa {empresa} no tiene un NIF válido para la emisión fiscal.', ['empresa' => $nombreEmpresa]));
    }
    if (!$sii) {
        if (strlen(verifactu_normalizar_nif(parametro_app($pdo, $usuario, 'appVerifactuSifNif', ''))) !== 9) {
            throw new RuntimeException(t('El parámetro appVerifactuSifNif no contiene un NIF de productor válido.'));
        }
        verifactu_validar_instalacion_sif($datos['numero_instalacion'], $datos['version_instalacion'], $datos['codigo_sif'],
            $nombreEmpresa, $datos['nif_emisor']);
    }
    $certificado = certificado_exigir($datos['codigo_empresa'], $nombreEmpresa);
    if (in_array($datos['tipo_factura'], ['F1', 'R1', 'F3'], true)) {
        if ($datos['cliente_extranjero'] && $datos['nif_cliente'] === '') {
            throw new RuntimeException(t(
                'La factura {tipo} {factura} a cliente extranjero requiere el NIF-IVA del destinatario.',
                ['tipo' => $datos['tipo_factura'], 'factura' => $serie . '\\' . $numero]));
        }
        if (!$datos['cliente_extranjero'] && strlen($datos['nif_cliente']) !== 9) {
            throw new RuntimeException(t(
                'La factura {tipo} {factura} requiere un NIF de cliente válido y tiene "{nif}". Corrige el cliente antes de emitirla.',
                ['tipo' => $datos['tipo_factura'], 'factura' => $serie . '\\' . $numero, 'nif' => $datos['nif_cliente']]));
        }
    }
    return ['datos' => $datos, 'certificado' => $certificado];
}

/**
 * Emite (consolida) un borrador según el modo de la web. Devuelve
 * ['modo', 'fase', 'mensaje', 'cola' => resumen del procesado o null].
 */
function factura_emitir(PDO $pdo, array $usuario, string $serie, string $numero): array
{
    $factura = factura_leer($pdo, $serie, $numero);
    if ($factura === null) {
        throw new RuntimeException(t('No existe la factura {serie} {numero}.', ['serie' => $serie, 'numero' => $numero]));
    }
    if (!factura_editable($factura)) {
        throw new RuntimeException(t('La factura {serie} {numero} ya está emitida ({fase}).',
            ['serie' => $serie, 'numero' => $numero, 'fase' => fase_factura_texto($factura)]));
    }
    $modo = verifactu_modo_web($pdo, $usuario);
    $nombreUsuario = (string)$usuario['usuario'];
    if ($modo['modo'] === 'SIN') {
        $pdo->beginTransaction();
        try {
            ejecutar(
                $pdo,
                'UPDATE fza_facturas SET ESCONSOLIDADA_FAC = \'S\', INSTANTECONSO_FAC = NOW(), FASE_FAC = ?, ' .
                'INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? WHERE SERIE_FAC = ? AND NUMERO_FAC = ?',
                [FASE_FACTURA_SIN_VERIFACTU, $nombreUsuario, $serie, $numero]
            );
            $pdo->commit();
        } catch (Throwable $error) {
            $pdo->rollBack();
            throw $error;
        }
        return [
            'modo' => 'SIN',
            'fase' => FASE_FACTURA_SIN_VERIFACTU,
            'mensaje' => t('Borrador {factura} emitido en modo SIN VERIFACTU.', ['factura' => $serie . '\\' . $numero]),
            'cola' => null,
        ];
    }
    $esSii = $modo['configurado'] === VERIFACTU_MODO_SII;
    if (!$esSii && $modo['configurado'] !== VERIFACTU_MODO_VERIFACTU) {
        throw new RuntimeException(t('El modo {modo} no está disponible en la facturación web. Cambia a SIN, PRE, PRO o SII desde el menú.',
            ['modo' => verifactu_modo_descripcion($modo['modo'])]));
    }
    $conSistema = verifactu_cola_tiene_sistema($pdo);
    if ($esSii && !$conSistema) {
        throw new RuntimeException(t('La base de datos no tiene la columna SISTEMA_VFCOLA (script 791): no se puede emitir en modo SII.'));
    }
    verifactu_validar_emision($pdo, $usuario, $serie, $numero, $esSii);
    $sistema = $esSii ? VERIFACTU_MODO_SII : VERIFACTU_MODO_VERIFACTU;
    $pdo->beginTransaction();
    try {
        ejecutar(
            $pdo,
            'INSERT INTO fza_verifactu_cola (SERIE_FAC_VFCOLA, NUMERO_FAC_VFCOLA, TIPO_OPERACION_VFCOLA, ESTADO_VFCOLA, ' .
            'CONTADOR_INTENTOS_VFCOLA, INSTANTE_ALTA, USUARIO_ALTA' . ($conSistema ? ', SISTEMA_VFCOLA' : '') . ') ' .
            'VALUES (?, ?, \'ALTA\', \'PENDIENTE\', 0, NOW(), ?' . ($conSistema ? ', ?' : '') . ') ' .
            'ON DUPLICATE KEY UPDATE ESTADO_VFCOLA = \'PENDIENTE\', CONTADOR_INTENTOS_VFCOLA = 0, ' .
            'INSTANTE_PROXIMO_INTENTO_VFCOLA = NULL, MENSAJE_ERROR_VFCOLA = NULL, INSTANTE_MODIF = NOW(), USUARIO_MODIF = ?' .
            ($conSistema ? ', SISTEMA_VFCOLA = VALUES(SISTEMA_VFCOLA)' : ''),
            $conSistema
                ? [$serie, $numero, $nombreUsuario, $sistema, $nombreUsuario]
                : [$serie, $numero, $nombreUsuario, $nombreUsuario]
        );
        ejecutar(
            $pdo,
            'UPDATE fza_facturas SET FASE_FAC = ?, INSTANTE_MODIF = NOW(), USUARIO_MODIF = ? ' .
            'WHERE SERIE_FAC = ? AND NUMERO_FAC = ? AND (FASE_FAC IS NULL OR FASE_FAC IN (\'\', \'BORRADOR\', \'ERROR\', \'VERIFACTU_ERROR\'))',
            [FASE_FACTURA_VERIFACTU_PENDIENTE, $nombreUsuario, $serie, $numero]
        );
        if ($esSii) {
            /* El SII no es un SIF: sin productor configurado el evento no se anota, pero se emite. */
            registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_ENCOLADO,
                'Lanzamiento manual (Emitir) desde la facturación web (SII)', '', $serie, $numero);
        } else {
            registrar_evento_verifactu($pdo, $usuario, EVENTO_VERIFACTU_ENCOLADO,
                'Lanzamiento manual (Emitir) desde la facturación web', '', $serie, $numero);
        }
        $pdo->commit();
    } catch (Throwable $error) {
        if ($pdo->inTransaction()) {
            $pdo->rollBack();
        }
        throw $error;
    }
    $cola = verifactu_cola_procesar($pdo, $usuario);
    $actual = factura_leer($pdo, $serie, $numero);
    $fase = strtoupper(trim((string)($actual['FASE_FAC'] ?? '')));
    if ($fase === FASE_FACTURA_VERIFACTU_OK) {
        $mensaje = t('Factura {factura} emitida y aceptada por la AEAT ({modo}).', ['factura' => $serie . '\\' . $numero, 'modo' => $modo['modo']]);
    } elseif ($esSii) {
        /* El SII no lleva QR: no hay nada que imprimir antes del envío. */
        $mensaje = t('Borrador {factura} en VERIFACTU_PENDIENTE: el envío al SII queda en la cola.',
            ['factura' => $serie . '\\' . $numero]);
    } else {
        $mensaje = t('Borrador {factura} en VERIFACTU_PENDIENTE: el QR ya puede imprimirse y el envío a la AEAT queda en la cola Verifactu.',
            ['factura' => $serie . '\\' . $numero]);
    }
    return ['modo' => $modo['modo'], 'fase' => $fase, 'mensaje' => $mensaje, 'cola' => $cola];
}

/* ===================== Consultas para las pantallas ===================== */

function verifactu_cola_resumen(PDO $pdo): array
{
    $resumen = ['PENDIENTE' => 0, 'PROCESANDO' => 0, 'ENVIADA' => 0, 'ERROR' => 0];
    foreach (consultar($pdo, 'SELECT ESTADO_VFCOLA, COUNT(*) AS N FROM fza_verifactu_cola GROUP BY ESTADO_VFCOLA') as $fila) {
        $resumen[strtoupper((string)$fila['ESTADO_VFCOLA'])] = (int)$fila['N'];
    }
    return $resumen;
}

function verifactu_cola_listar(PDO $pdo, int $limite = 30): array
{
    $limite = max(1, min(200, $limite));
    return consultar(
        $pdo,
        'SELECT ID_VFCOLA, SERIE_FAC_VFCOLA, NUMERO_FAC_VFCOLA, TIPO_OPERACION_VFCOLA, ESTADO_VFCOLA, ' .
        'CONTADOR_INTENTOS_VFCOLA, INSTANTE_PROXIMO_INTENTO_VFCOLA, INSTANTE_ENVIO_VFCOLA, MENSAJE_ERROR_VFCOLA, ' .
        'INSTANTE_ALTA, INSTANTE_MODIF FROM fza_verifactu_cola ORDER BY ID_VFCOLA DESC LIMIT ' . $limite
    );
}

/** Consolidación (respuesta de la AEAT, URL del QR) de una factura, si la hay. */
function verifactu_anulacion_cola(PDO $pdo, string $serie, string $numero): ?array
{
    /* Con SISTEMA_VFCOLA la fila se procesa por su sistema (verifactu_cola_procesar_fila). */
    return consultar_una($pdo,
        "SELECT ID_VFCOLA, ESTADO_VFCOLA, TIPO_OPERACION_VFCOLA, CONTADOR_INTENTOS_VFCOLA, " .
        (verifactu_cola_tiene_sistema($pdo) ? 'SISTEMA_VFCOLA, ' : '') .
        "SERIE_FAC_VFCOLA, NUMERO_FAC_VFCOLA, MENSAJE_ERROR_VFCOLA FROM fza_verifactu_cola " .
        "WHERE SERIE_FAC_VFCOLA=? AND NUMERO_FAC_VFCOLA=? AND TIPO_OPERACION_VFCOLA='ANULACION'",
        [$serie, $numero]);
}

function verifactu_validar_destino_anulacion(PDO $pdo, array $usuario, string $serie, string $numero): array
{
    $original = consolidacion_leer($pdo, $serie, $numero);
    /* Alta del SII vigente: la baja sale por el SII con el entorno actual; no
       hay QR del que deducirlo (FZ-ISSUE-295). */
    if ($original !== null && in_array($original['ESTADO_FACCON'],
        ['SII_PROCESADO', 'SII_ACEPT_ERR', 'SII_DUPLICADO', 'SII_MODIFICADO'], true)) {
        return $original + ['SISTEMA' => VERIFACTU_MODO_SII];
    }
    if ($original === null || !in_array($original['ESTADO_FACCON'],
        ['VERIFACTU_PROCESADO', 'VERIFACTU_ACEPT_ERR', 'VERIFACTU_DUPLICADO', 'VERIFACTU_SUBSANADO'], true)) {
        throw new RuntimeException(t('No hay un alta aceptada pendiente de anular.'));
    }
    $host = strtolower((string)parse_url((string)$original['VERIFACTU_URL_FACCON'], PHP_URL_HOST));
    $entorno = match ($host) {
        'prewww2.aeat.es' => 'PRE',
        'www2.agenciatributaria.gob.es' => 'PRO',
        default => '',
    };
    if ($entorno === '') {
        throw new RuntimeException(t('No se puede determinar el entorno del alta a partir de su QR guardado.'));
    }
    if (verifactu_modo_web($pdo, $usuario)['modo'] !== $entorno) {
        throw new RuntimeException(t('El alta se envió a {entorno}. Selecciona ese entorno para anularla.', ['entorno' => $entorno]));
    }
    return $original;
}

/** Conserva el alta y su QR; guarda la respuesta de anulación en la misma ficha que Delphi. */
function verifactu_guardar_anulacion_aceptada(PDO $pdo, int $id, string $serie, string $numero, array $r,
    string $estado = 'VERIFACTU_ANULADO'): void
{
    $originales = [
        'ESTADO_ORIGINAL' => 'ESTADO', 'CODIGO_ERROR_ORIGINAL' => 'CODIGO_ERROR_AEAT',
        'DESCRIPCION_ERROR_ORIGINAL' => 'DESCRIPCION_ERROR_AEAT',
        'RESPUESTA_ORIGINAL' => 'RESPUESTA_COMPLETA', 'PETICION_ORIGINAL' => 'PETICION_COMPLETA',
        'REGISTRO_XML_ORIGINAL' => 'REGISTRO_XML', 'FIRMA_DIGITAL_ORIGINAL' => 'FIRMA_DIGITAL',
        'REQUEST_ID_ORIGINAL' => 'REQUEST_ID_CONSOLIDACION',
        'CHAIN_NUMBER_ORIGINAL' => 'CHAIN_NUMBER', 'CHAIN_HASH_ORIGINAL' => 'CHAIN_HASH',
        'SERIE_CERTIFICADO_ORIGINAL' => 'SERIE_CERTIFICADO',
        'TITULAR_CERTIFICADO_ORIGINAL' => 'TITULAR_CERTIFICADO',
        'HUELLA_CERTIFICADO_ORIGINAL' => 'HUELLA_CERTIFICADO',
    ];
    $asignaciones = [];
    foreach ($originales as $destino => $origen) {
        $asignaciones[] = $destino . '_FACCON=COALESCE(' . $destino . '_FACCON,' . $origen . '_FACCON)';
    }
    ejecutar($pdo, 'UPDATE fza_facturas_consolidaciones SET ' . implode(',', $asignaciones) .
        ', QUEUE_ID_CANCEL_FACCON=?, ESTADO_FACCON=?, ' .
        'CHAIN_NUMBER_FACCON=NULLIF(?, \'\'), CHAIN_HASH_FACCON=NULLIF(?, \'\'), RESPUESTA_COMPLETA_FACCON=?, PETICION_COMPLETA_FACCON=?, ' .
        'REGISTRO_XML_FACCON=?, FIRMA_DIGITAL_FACCON=?, CODIGO_ERROR_AEAT_FACCON=?, ' .
        'DESCRIPCION_ERROR_AEAT_FACCON=?, FECHA_PROCESAMIENTO_FACCON=NOW() ' .
        'WHERE SERIE_FAC_FACCON=? AND NUMERO_FAC_FACCON=?',
        [$id, $estado, $r['chain_number'], $r['chain_hash'], $r['respuesta'], $r['peticion'], $r['registro_xml'],
            $r['firma_digital'], $r['codigo_error'], $r['descripcion_error'], $serie, $numero]);
}

/** Encola una sola anulación. El alta, la factura y su numeración permanecen intactas. */
function factura_encolar_anulacion(PDO $pdo, array $usuario, string $serie, string $numero, string $motivo): void
{
    $motivo = trim($motivo);
    if ($motivo === '' || mb_strlen($motivo) > 500) {
        throw new RuntimeException(t('Indica el motivo de anulación (hasta 500 caracteres).'));
    }
    $pdo->beginTransaction();
    try {
        $f = consultar_una($pdo, 'SELECT FASE_FAC, CODIGO_EMP_FAC FROM fza_facturas ' .
            'WHERE SERIE_FAC=? AND NUMERO_FAC=? FOR UPDATE', [$serie, $numero]);
        if (($f['FASE_FAC'] ?? '') !== FASE_FACTURA_VERIFACTU_OK) {
            throw new RuntimeException(t('Solo se pueden anular facturas enviadas y aceptadas por VeriFactu.'));
        }
        certificado_exigir((string)$f['CODIGO_EMP_FAC'], (string)$f['CODIGO_EMP_FAC']);
        $original = verifactu_validar_destino_anulacion($pdo, $usuario, $serie, $numero);
        $esSii = ($original['SISTEMA'] ?? '') === VERIFACTU_MODO_SII;
        $cola = verifactu_anulacion_cola($pdo, $serie, $numero);
        if ($cola !== null) {
            throw new RuntimeException(t('La anulación ya está en la cola ({estado}). Consulta el panel VeriFactu.', ['estado' => $cola['ESTADO_VFCOLA']]));
        }
        $archivo = consultar_una($pdo, 'SELECT REGISTRO_XML_FACCON, PETICION_COMPLETA_FACCON, ' .
            'RESPUESTA_COMPLETA_FACCON, CHAIN_HASH_FACCON, REQUEST_ID_CONSOLIDACION_FACCON ' .
            'FROM fza_facturas_consolidaciones WHERE SERIE_FAC_FACCON=? AND NUMERO_FAC_FACCON=?', [$serie, $numero]);
        /* La baja va por el sistema del alta (SistemaColaAltaFactura del programa). */
        $conSistema = verifactu_cola_tiene_sistema($pdo);
        ejecutar($pdo, 'INSERT INTO fza_verifactu_cola (SERIE_FAC_VFCOLA, NUMERO_FAC_VFCOLA, ' .
            'TIPO_OPERACION_VFCOLA, ESTADO_VFCOLA, CONTADOR_INTENTOS_VFCOLA, MOTIVO_VFCOLA, INSTANTE_ALTA, USUARIO_ALTA' .
            ($conSistema ? ', SISTEMA_VFCOLA' : '') . ') ' .
            "VALUES (?,?,'ANULACION','PENDIENTE',0,?,NOW(),?" . ($conSistema ? ',?' : '') . ')',
            $conSistema
                ? [$serie, $numero, $motivo, $usuario['usuario'], $esSii ? VERIFACTU_MODO_SII : VERIFACTU_MODO_VERIFACTU]
                : [$serie, $numero, $motivo, $usuario['usuario']]);
        $detalle = json_encode(['motivo' => $motivo, 'alta' => $archivo], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
        if ($esSii) {
            /* El SII no es un SIF: sin productor configurado el evento no se anota. */
            registrar_evento_verifactu_seguro($pdo, $usuario, EVENTO_VERIFACTU_ENCOLADO,
                'Anulación SII solicitada desde el histórico', $detalle, $serie, $numero);
        } else {
            registrar_evento_verifactu($pdo, $usuario, EVENTO_VERIFACTU_ENCOLADO,
                'Anulación VeriFactu solicitada desde el histórico', $detalle, $serie, $numero);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) { $pdo->rollBack(); }
        throw $e;
    }
}

function consolidacion_leer(PDO $pdo, string $serie, string $numero): ?array
{
    return consultar_una(
        $pdo,
        'SELECT ID_FACCON, REQUEST_ID_CONSOLIDACION_FACCON, ISSUED_TIME_FACCON, CHAIN_NUMBER_FACCON, CHAIN_HASH_FACCON, ' .
        'VERIFACTU_URL_FACCON, FECHA_PROCESAMIENTO_FACCON, ESTADO_FACCON, CODIGO_ERROR_AEAT_FACCON, ' .
        'DESCRIPCION_ERROR_AEAT_FACCON FROM fza_facturas_consolidaciones ' .
        'WHERE SERIE_FAC_FACCON = ? AND NUMERO_FAC_FACCON = ? ORDER BY ID_FACCON DESC LIMIT 1',
        [$serie, $numero]
    );
}

/**
 * QR tributario de una factura emitida con Verifactu: la URL guardada en la
 * consolidación o, si aún no se ha enviado, la calculada con el entorno
 * actual (como RellenarQRPicture). Null si la factura no lleva QR.
 */
function factura_qr_verifactu(PDO $pdo, array $usuario, array $factura): ?array
{
    if (!factura_es_verifactu($factura)) {
        return null;
    }
    /* El SII no lleva QR ni leyenda VERI*FACTU. */
    if (factura_es_sii($pdo, (string)$factura['SERIE_FAC'], (string)$factura['NUMERO_FAC'])) {
        return null;
    }
    $serie = (string)$factura['SERIE_FAC'];
    $numero = (string)$factura['NUMERO_FAC'];
    $consolidacion = consolidacion_leer($pdo, $serie, $numero);
    $url = trim((string)($consolidacion['VERIFACTU_URL_FACCON'] ?? ''));
    if ($url === '') {
        $base = verifactu_entorno($pdo, $usuario) === 'PRO'
            ? parametro_app($pdo, $usuario, 'appVerifactuUrlQRPro')
            : parametro_app($pdo, $usuario, 'appVerifactuUrlQRPre');
        $importe = verifactu_importe_total($factura);
        $empresa = empresa_por_codigo($pdo, (string)($factura['CODIGO_EMP_FAC'] ?? ''));
        $formato = (string)($empresa['FORMATO_DOCUMENTO_EMP'] ?? '');
        $url = verifactu_url_qr($base, (string)$factura['NIF_EMPRESA_FAC'], $formato, $serie, $numero,
            substr((string)$factura['FECHA_FAC'], 0, 10), $importe);
    }
    return [
        'url'     => $url,
        'matriz'  => CodigoQR::matriz($url),
        'leyenda' => ['VERI*FACTU', 'Factura verificable en la', 'sede electrónica de la AEAT'],
        'estado'  => (string)($consolidacion['ESTADO_FACCON'] ?? ''),
    ];
}
