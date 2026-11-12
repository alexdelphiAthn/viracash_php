-- Igual que procedimientos_mysql8.sql pero con SQL SECURITY INVOKER (no
-- dependen del definer). Ejecutar con la base en utf8mb4_spanish_ci.
SET NAMES utf8mb4 COLLATE utf8mb4_spanish_ci;
SET SESSION sql_mode = 'NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION';
SET FOREIGN_KEY_CHECKS = 0;

-- Procedimiento ausente: fzaest_recalcular_rango
DROP PROCEDURE IF EXISTS `fzaest_recalcular_rango`;
DELIMITER ;;
CREATE PROCEDURE `fzaest_recalcular_rango`(IN pD1 date, IN pD2 date)
SQL SECURITY INVOKER
BEGIN
  DELETE FROM fzaest_estadisticas_dia WHERE FECHA BETWEEN pD1 AND pD2;
  INSERT INTO fzaest_estadisticas_dia
    (FECHA, CODIGO_ALMACEN, CODIGO_FAMILIA, TEMPORADA,
     NUM_MOVIMIENTOS, UNIDADES_MOV, COSTE_MOV,
     NUM_LINEAS_VENTA, UNIDADES_VENTA, IMPORTE_VENTA)
  SELECT FECHA, CODIGO_ALMACEN, CODIGO_FAMILIA, TEMPORADA,
         NUM_MOVIMIENTOS, UNIDADES_MOV, COSTE_MOV,
         NUM_LINEAS_VENTA, UNIDADES_VENTA, IMPORTE_VENTA
    FROM viest_dia
   WHERE FECHA BETWEEN pD1 AND pD2;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_ADD_INDEX_IF_NOT_EXISTS
DROP PROCEDURE IF EXISTS `PRC_ADD_INDEX_IF_NOT_EXISTS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_ADD_INDEX_IF_NOT_EXISTS`(IN `p_tabla` VARCHAR(64),    /* Nombre de la tabla destino, sin backticks */
    IN `p_indice` VARCHAR(64),       /* Nombre del indice a crear (convencion IDX_<SUF>_<col>) */
    IN `p_columnas` VARCHAR(1000))
SQL SECURITY INVOKER
BEGIN
    /* Crea un indice si no existe ya en la BBDD actual. Idempotente y
       seguro de re-ejecutar. Pensado para migraciones de rendimiento. */
    IF NOT EXISTS (
        SELECT 1
          FROM information_schema.statistics
         WHERE table_schema = DATABASE()
           AND table_name   = p_tabla
           AND index_name   = p_indice
    ) THEN
        SET @ddl = CONCAT('ALTER TABLE `', p_tabla,
                          '` ADD INDEX `', p_indice,
                          '` (', p_columnas, ')');
        PREPARE stmt FROM @ddl;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AGREGAR_VALOR_CONJUNTO
DROP PROCEDURE IF EXISTS `PRC_AGREGAR_VALOR_CONJUNTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AGREGAR_VALOR_CONJUNTO`(IN `p_id_conjunto` INT,         /* ID de la Paleta (ej: 5 para 'Verano 2026') */
    IN `p_valor_texto` VARCHAR(100), /* Lo que escribió el usuario (ej: 'VERDE RADIOACTIVO') */
    IN `p_usuario` VARCHAR(100))
SQL SECURITY INVOKER
BEGIN
    DECLARE v_id_valor INT;
    DECLARE v_tipo_variacion VARCHAR(20);
    
    /* 1. Averiguamos de qué tipo es esta paleta (¿Es de Colores CO o Tallas TC?) */
    SELECT ID_VA_AC INTO v_tipo_variacion
    FROM fza_atributos_conjuntos
    WHERE ID_AC = p_id_conjunto;
    
    /* 2. Usamos el truco del "Find or Create" que vimos antes */
    /* Esto busca el ID de 'VERDE RADIOACTIVO'. Si no existe, lo crea en fza_atributos_valores */
    CALL PRC_GET_CREAR_VALOR(v_tipo_variacion, p_valor_texto, p_usuario, v_id_valor);
    
    /* 3. Ahora que SEGURO tenemos un ID (v_id_valor), lo vinculamos a la paleta */
    /* Usamos INSERT IGNORE para que si ya estaba en la paleta, no de error */
    INSERT IGNORE INTO fza_atributos_conjuntos_det (
        ID_AC_ACD, 
        ID_AV_ACD, 
        USUARIO_ALTA, 
        USUARIO_MODIF, 
        INSTANTE_ALTA
    ) VALUES (
        p_id_conjunto, 
        v_id_valor, 
        p_usuario, 
        p_usuario, 
        NOW()
    );
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADORES
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADORES`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADORES`(
  IN p_USUARIO varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  CALL `PRC_AJUSTAR_CONTADORES_MAESTROS`(p_USUARIO);
  CALL `PRC_AJUSTAR_CONTADORES_DOCUMENTOS`(p_USUARIO);
  CALL `PRC_AJUSTAR_CONTADORES_ID`(p_USUARIO);
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADORES_DOCUMENTOS
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADORES_DOCUMENTOS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADORES_DOCUMENTOS`(
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'FC', 'fza_facturas', 'CODIGO_EMP_FAC', 'SERIE_FAC', 'NUMERO_FAC',
    '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'PE', 'fza_pedidos', 'CODIGO_EMP_PED', 'SERIE_PED', 'NUMERO_PED',
    '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'AV', 'fza_albaranes', 'CODIGO_EMP_ALB', 'SERIE_ALB', 'NUMERO_ALB',
    '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'PC', 'fza_pedidos_compra', 'CODIGO_EMP_PEDC', 'SERIE_PEDC',
    'NUMERO_PEDC', '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'AB', 'fza_albaranes_compra', 'CODIGO_EMP_ALBC', 'SERIE_ALBC',
    'NUMERO_ALBC', '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'DC', 'fza_devoluciones_compra', 'CODIGO_EMP_DEVC', 'SERIE_DEVC',
    'NUMERO_DEVC', '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'FP', 'fza_facturas_compra', 'CODIGO_EMP_FACC', 'SERIE_FACC',
    'NUMERO_FACC', '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'IN', 'fza_inventarios', 'CODIGO_EMP_INV', 'SERIE_INV', 'NUMERO_INV',
    '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'SE', 'fza_compras_sesiones', 'CODIGO_EMP_SES', 'SERIE_SES',
    'NUMERO_SES', '', '', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'TR', 'fza_caja_operaciones', 'CODIGO_EMP_OPCAJA',
    'SERIE_FAC_OPCAJA', 'NUMERO_FAC_OPCAJA', 'TIPO_OPERACION_OPCAJA',
    'TR', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'TA', 'fza_caja_operaciones', 'CODIGO_EMP_OPCAJA',
    'SERIE_FAC_OPCAJA', 'NUMERO_FAC_OPCAJA', 'TIPO_OPERACION_OPCAJA',
    'TA', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
    'TA', 'fza_caja_operaciones', 'CODIGO_EMP_OPCAJA',
    'SERIE_FAC_OPCAJA', 'NUMERO_FAC_OPCAJA', 'TIPO_OPERACION_OPCAJA',
    'AT', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_EMPRESA`(
    'OV', 'fza_caja_operaciones', 'CODIGO_EMP_OPCAJA',
    'NUMERO_OPERACION_OPCAJA', 'OV', 8, pUsuario);
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADORES_ID
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADORES_ID`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADORES_ID`(
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_articulos_tarifas', 'CODIGO_UNICO_ARTTAR', 'ART_TAR', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_articulos_vinculos', 'ID_ARTVIN', 'ART_VINC', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_atributos_basicos', 'ID_ATB', 'ATR_BASIC', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_atributos_conjuntos', 'ID_AC', 'ATR_CONJ', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_atributos_valores', 'ID_AV', 'ATR_VAL', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_atributos_valores_info', 'ID_AVI', 'ATR_VALINF', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_caja_arqueos_recuento', 'ID_ARQR', 'CAJ_ARQREC', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_caja_operaciones', 'ID_OPCAJA', 'CAJ_OPER', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_codigos_barras', 'ID_CB', 'COD_BARRAS', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_documentos_trabajo', 'ID_DTR', 'DOC_TRAB', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_documentos_trabajo_compartidos', 'ID_DTC', 'DOC_COMP', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_documentos_trabajo_lineas', 'ID_DTL', 'DOC_LINEA', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_facturas_relaciones', 'ID_FACREL', 'FAC_REL', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_filtros_guardados', 'ID_FILT', 'FILTRO', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_filtros_guardados_compartidos', 'ID_FILTC', 'FILT_COMP',
    pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_inventarios_recuentos', 'ID_INVREC', 'FZA_INVREC', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_metadatos', 'CODIGO_META_META', 'METADATO', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_propiedades_valores', 'ID_PV_ARTPROP', 'PROP_VAL', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_tarifas_cambios', 'CODIGO_TARC', 'TAR_CAMBIO', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_tarifas_cambios_lineas', 'ID_TARCLIN', 'TAR_LINEA', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_traducciones', 'ID_TRAD', 'TRADUCCION', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_ventas_ws_cola', 'ID_VWSC', 'VENTAS_WS', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_verifactu_cola', 'ID_VFCOLA', 'VF_COLA', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'fza_verifactu_eventos', 'ID_LOG', 'VF_EVENTO', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'inv_almacenes', 'id', 'INV_ALM', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'inv_catalogo', 'id', 'INV_CAT', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'inv_dispositivos', 'id', 'INV_DISP', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'inv_eventos', 'id', 'INV_EVENTO', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_ID`(
    'inv_recuentos', 'id', 'INV_RECUENTO', pUsuario);
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADORES_MAESTROS
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADORES_MAESTROS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADORES_MAESTROS`(
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'AR', 'fza_articulos', 'CODIGO_ART_ART', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'AO', 'fza_articulos', 'ORDEN_ART', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'CL', 'fza_clientes', 'CODIGO_CLI_CLI', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'CO', 'fza_clientes', 'ORDEN_CLI', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'PV', 'fza_proveedores', 'CODIGO_PRV_PRV', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'PO', 'fza_proveedores', 'ORDEN_PRV', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'EM', 'fza_empresas', 'CODIGO_EMP_EMP', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'EO', 'fza_empresas', 'ORDEN_EMP', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'ES', 'fza_empresas_series', 'CODIGO_SERIE_EMPSER', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'EB', 'fza_empresas_bancos', 'CODIGO_EMPBAN', 4, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'RT', 'fza_empresas_retenciones', 'CODIGO_RETENCION_EMPRET', 3,
    pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'FA', 'fza_articulos_familias', 'CODIGO_FAM_FAM', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'FO', 'fza_articulos_familias', 'ORDEN_FAM', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'PG', 'fza_formas_pago', 'CODIGO_FP_FP', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'GO', 'fza_formas_pago', 'ORDEN_FORMA_PAGO_FP', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'GP', 'fza_generadorprocesos', 'CODIGO_GENERADOR_PROCESO_GP', 3,
    pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'IG', 'fza_ivas_grupos', 'IVA_IVAGRP', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'IV', 'fza_ivas', 'CODIGO_IVA', 3, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'MV', 'fza_movimientos_almacen', 'NUMERO_MOV', 10, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'RC', 'fza_remesas_venta', 'NUMERO_REMV', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'RP', 'fza_remesas_compra', 'NUMERO_REMC', 6, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_GLOBAL`(
    'TS', 'fza_traspasos_solicitudes', 'NUMERO_TRSOL', 10, pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_PREFIJO`(
    'BA', 'fza_codigos_barras', 'CODIGO_BARRAS_CB', '21', pUsuario);
  CALL `PRC_AJUSTAR_CONTADOR_PREFIJO`(
    'TK', 'fza_facturas', 'CODIGO_BARRAS_FAC', '29', pUsuario);
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADOR_DOCUMENTO
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADOR_DOCUMENTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADOR_DOCUMENTO`(
  IN pTipo varchar(2),
  IN pTabla varchar(64),
  IN pEmpresa varchar(64),
  IN pSerie varchar(64),
  IN pNumero varchar(64),
  IN pColumnaFiltro varchar(64),
  IN pValorFiltro varchar(20),
  IN pDigitos int,
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vExiste int DEFAULT 0;
  DECLARE vExisteFiltro int DEFAULT 1;
  DECLARE vFiltro varchar(500) DEFAULT '';
  DECLARE vUsuario varchar(100);
  SELECT COUNT(*) INTO vExiste
    FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = pTabla
     AND COLUMN_NAME IN (pEmpresa, pSerie, pNumero);
  IF COALESCE(pColumnaFiltro, '') <> '' THEN
    SELECT COUNT(*) INTO vExisteFiltro
      FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE()
       AND TABLE_NAME = pTabla
       AND COLUMN_NAME = pColumnaFiltro;
    SET vFiltro = CONCAT(' AND TRIM(`',
      REPLACE(pColumnaFiltro, '`', '``'), '`) = ', QUOTE(pValorFiltro));
  END IF;
  IF vExiste = 3 AND vExisteFiltro = 1 THEN
    SET vUsuario = COALESCE(NULLIF(TRIM(pUsuario), ''), 'SISTEMA');
    SET @sSqlAjusteContador = CONCAT(
      'INSERT INTO `fza_contadores` (',
      '`TIPO_DOC_CON`, `EMPRESA_CON`, `SERIE_CON`, `CON`, ',
      '`NUM_DIGITOS_CON`, `ESACTIVO_CON`, `DEFAULT_CON`, ',
      '`INSTANTE_ALTA`, `INSTANTE_MODIF`, ',
      '`USUARIO_ALTA`, `USUARIO_MODIF`) SELECT ', QUOTE(pTipo), ', ',
      'TRIM(`', REPLACE(pEmpresa, '`', '``'), '`), TRIM(`',
      REPLACE(pSerie, '`', '``'), '`), MAX(CAST(TRIM(`',
      REPLACE(pNumero, '`', '``'), '`) AS UNSIGNED)) + 1, ',
      'GREATEST(', GREATEST(pDigitos, 1), ', CHAR_LENGTH(CAST(',
      'MAX(CAST(TRIM(`', REPLACE(pNumero, '`', '``'),
      '`) AS UNSIGNED)) + 1 AS CHAR))), ''S'', ''N'', ',
      'CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ', QUOTE(vUsuario), ', ',
      QUOTE(vUsuario), ' FROM `', REPLACE(pTabla, '`', '``'), '` ',
      'WHERE TRIM(COALESCE(`', REPLACE(pEmpresa, '`', '``'),
      '`, '''')) <> '''' AND TRIM(COALESCE(`',
      REPLACE(pSerie, '`', '``'), '`, '''')) <> '''' AND ',
      'TRIM(COALESCE(`', REPLACE(pNumero, '`', '``'),
      '`, '''')) REGEXP ''^[0-9]+$''', vFiltro, ' GROUP BY TRIM(`',
      REPLACE(pEmpresa, '`', '``'), '`), TRIM(`',
      REPLACE(pSerie, '`', '``'), '`) ON DUPLICATE KEY UPDATE ',
      '`USUARIO_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'VALUES(`USUARIO_MODIF`), `USUARIO_MODIF`), ',
      '`INSTANTE_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'CURRENT_TIMESTAMP, `INSTANTE_MODIF`), ',
      '`CON` = GREATEST(`CON`, VALUES(`CON`)), ',
      '`NUM_DIGITOS_CON` = GREATEST(`NUM_DIGITOS_CON`, ',
      'VALUES(`NUM_DIGITOS_CON`))'
    );
    PREPARE oSentenciaAjusteContador FROM @sSqlAjusteContador;
    EXECUTE oSentenciaAjusteContador;
    DEALLOCATE PREPARE oSentenciaAjusteContador;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADOR_EMPRESA
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADOR_EMPRESA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADOR_EMPRESA`(
  IN pTipo varchar(2),
  IN pTabla varchar(64),
  IN pEmpresa varchar(64),
  IN pNumero varchar(64),
  IN pSerie varchar(12),
  IN pDigitos int,
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vExiste int DEFAULT 0;
  DECLARE vUsuario varchar(100);
  SELECT COUNT(*) INTO vExiste
    FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = pTabla
     AND COLUMN_NAME IN (pEmpresa, pNumero);
  IF vExiste = 2 THEN
    SET vUsuario = COALESCE(NULLIF(TRIM(pUsuario), ''), 'SISTEMA');
    SET @sSqlAjusteContador = CONCAT(
      'INSERT INTO `fza_contadores` (',
      '`TIPO_DOC_CON`, `EMPRESA_CON`, `SERIE_CON`, `CON`, ',
      '`NUM_DIGITOS_CON`, `ESACTIVO_CON`, `DEFAULT_CON`, ',
      '`INSTANTE_ALTA`, `INSTANTE_MODIF`, ',
      '`USUARIO_ALTA`, `USUARIO_MODIF`) SELECT ', QUOTE(pTipo), ', ',
      'TRIM(`', REPLACE(pEmpresa, '`', '``'), '`), ', QUOTE(pSerie),
      ', MAX(CAST(TRIM(`', REPLACE(pNumero, '`', '``'),
      '`) AS UNSIGNED)) + 1, GREATEST(', GREATEST(pDigitos, 1),
      ', CHAR_LENGTH(CAST(MAX(CAST(TRIM(`',
      REPLACE(pNumero, '`', '``'), '`) AS UNSIGNED)) + 1 AS CHAR))), ',
      '''S'', ''N'', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ',
      QUOTE(vUsuario), ', ', QUOTE(vUsuario), ' FROM `',
      REPLACE(pTabla, '`', '``'), '` WHERE TRIM(COALESCE(`',
      REPLACE(pEmpresa, '`', '``'), '`, '''')) <> '''' AND ',
      'TRIM(COALESCE(`', REPLACE(pNumero, '`', '``'),
      '`, '''')) REGEXP ''^[0-9]+$'' GROUP BY TRIM(`',
      REPLACE(pEmpresa, '`', '``'), '`) ON DUPLICATE KEY UPDATE ',
      '`USUARIO_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'VALUES(`USUARIO_MODIF`), `USUARIO_MODIF`), ',
      '`INSTANTE_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'CURRENT_TIMESTAMP, `INSTANTE_MODIF`), ',
      '`CON` = GREATEST(`CON`, VALUES(`CON`)), ',
      '`NUM_DIGITOS_CON` = GREATEST(`NUM_DIGITOS_CON`, ',
      'VALUES(`NUM_DIGITOS_CON`))'
    );
    PREPARE oSentenciaAjusteContador FROM @sSqlAjusteContador;
    EXECUTE oSentenciaAjusteContador;
    DEALLOCATE PREPARE oSentenciaAjusteContador;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADOR_GLOBAL
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADOR_GLOBAL`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADOR_GLOBAL`(
  IN pTipo varchar(2),
  IN pTabla varchar(64),
  IN pColumna varchar(64),
  IN pDigitos int,
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vExiste int DEFAULT 0;
  DECLARE vUsuario varchar(100);
  SELECT COUNT(*) INTO vExiste
    FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = pTabla
     AND COLUMN_NAME = pColumna;
  IF vExiste = 1 THEN
    SET vUsuario = COALESCE(NULLIF(TRIM(pUsuario), ''), 'SISTEMA');
    SET @sSqlAjusteContador = CONCAT(
      'INSERT INTO `fza_contadores` (',
      '`TIPO_DOC_CON`, `EMPRESA_CON`, `SERIE_CON`, `CON`, ',
      '`NUM_DIGITOS_CON`, `ESACTIVO_CON`, `DEFAULT_CON`, ',
      '`INSTANTE_ALTA`, `INSTANTE_MODIF`, ',
      '`USUARIO_ALTA`, `USUARIO_MODIF`) ',
      'SELECT ', QUOTE(pTipo), ', ''-'', ''-'', ',
      'COALESCE(MAX(CAST(TRIM(`', REPLACE(pColumna, '`', '``'),
      '`) AS UNSIGNED)), 0) + 1, ',
      'GREATEST(', GREATEST(pDigitos, 1), ', CHAR_LENGTH(CAST(',
      'COALESCE(MAX(CAST(TRIM(`', REPLACE(pColumna, '`', '``'),
      '`) AS UNSIGNED)), 0) + 1 AS CHAR))), ',
      '''S'', ''S'', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ',
      QUOTE(vUsuario), ', ', QUOTE(vUsuario), ' FROM `',
      REPLACE(pTabla, '`', '``'), '` WHERE TRIM(COALESCE(`',
      REPLACE(pColumna, '`', '``'), '`, '''')) REGEXP ''^[0-9]+$'' ',
      'ON DUPLICATE KEY UPDATE ',
      '`USUARIO_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'VALUES(`USUARIO_MODIF`), `USUARIO_MODIF`), ',
      '`INSTANTE_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'CURRENT_TIMESTAMP, `INSTANTE_MODIF`), ',
      '`CON` = GREATEST(`CON`, VALUES(`CON`)), ',
      '`NUM_DIGITOS_CON` = GREATEST(`NUM_DIGITOS_CON`, ',
      'VALUES(`NUM_DIGITOS_CON`))'
    );
    PREPARE oSentenciaAjusteContador FROM @sSqlAjusteContador;
    EXECUTE oSentenciaAjusteContador;
    DEALLOCATE PREPARE oSentenciaAjusteContador;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADOR_ID
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADOR_ID`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADOR_ID`(
  IN pTabla varchar(64),
  IN pColumna varchar(64),
  IN pSerie varchar(12),
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vExiste int DEFAULT 0;
  DECLARE vUsuario varchar(100);
  SELECT COUNT(*) INTO vExiste
    FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = pTabla
     AND COLUMN_NAME = pColumna;
  IF vExiste = 1 THEN
    SET vUsuario = COALESCE(NULLIF(TRIM(pUsuario), ''), 'SISTEMA');
    SET @sSqlAjusteContador = CONCAT(
      'INSERT INTO `fza_contadores` (',
      '`TIPO_DOC_CON`, `EMPRESA_CON`, `SERIE_CON`, `CON`, ',
      '`NUM_DIGITOS_CON`, `ESACTIVO_CON`, `DEFAULT_CON`, ',
      '`INSTANTE_ALTA`, `INSTANTE_MODIF`, ',
      '`USUARIO_ALTA`, `USUARIO_MODIF`) ',
      'SELECT ''ID'', ''-'', ', QUOTE(pSerie), ', ',
      'COALESCE(MAX(CAST(TRIM(`', REPLACE(pColumna, '`', '``'),
      '`) AS UNSIGNED)), 0) + 1, 20, ''S'', ''N'', ',
      'CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ', QUOTE(vUsuario), ', ',
      QUOTE(vUsuario), ' FROM `', REPLACE(pTabla, '`', '``'),
      '` WHERE TRIM(COALESCE(`', REPLACE(pColumna, '`', '``'),
      '`, '''')) REGEXP ''^[0-9]+$'' ',
      'ON DUPLICATE KEY UPDATE ',
      '`USUARIO_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'VALUES(`USUARIO_MODIF`), `USUARIO_MODIF`), ',
      '`INSTANTE_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'CURRENT_TIMESTAMP, `INSTANTE_MODIF`), ',
      '`CON` = GREATEST(`CON`, VALUES(`CON`)), ',
      '`NUM_DIGITOS_CON` = GREATEST(`NUM_DIGITOS_CON`, ',
      'VALUES(`NUM_DIGITOS_CON`))'
    );
    PREPARE oSentenciaAjusteContador FROM @sSqlAjusteContador;
    EXECUTE oSentenciaAjusteContador;
    DEALLOCATE PREPARE oSentenciaAjusteContador;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_AJUSTAR_CONTADOR_PREFIJO
DROP PROCEDURE IF EXISTS `PRC_AJUSTAR_CONTADOR_PREFIJO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_AJUSTAR_CONTADOR_PREFIJO`(
  IN pTipo varchar(2),
  IN pTabla varchar(64),
  IN pColumna varchar(64),
  IN pPrefijo varchar(2),
  IN pUsuario varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vExiste int DEFAULT 0;
  DECLARE vUsuario varchar(100);
  SELECT COUNT(*) INTO vExiste
    FROM INFORMATION_SCHEMA.COLUMNS
   WHERE TABLE_SCHEMA = DATABASE()
     AND TABLE_NAME = pTabla
     AND COLUMN_NAME = pColumna;
  IF vExiste = 1 AND pPrefijo REGEXP '^[0-9]{2}$' THEN
    SET vUsuario = COALESCE(NULLIF(TRIM(pUsuario), ''), 'SISTEMA');
    SET @sSqlAjusteContador = CONCAT(
      'INSERT INTO `fza_contadores` (',
      '`TIPO_DOC_CON`, `EMPRESA_CON`, `SERIE_CON`, `CON`, ',
      '`NUM_DIGITOS_CON`, `ESACTIVO_CON`, `DEFAULT_CON`, ',
      '`INSTANTE_ALTA`, `INSTANTE_MODIF`, ',
      '`USUARIO_ALTA`, `USUARIO_MODIF`) SELECT ', QUOTE(pTipo),
      ', ''-'', ''-'', COALESCE(MAX(CAST(SUBSTRING(TRIM(`',
      REPLACE(pColumna, '`', '``'), '`), 3, 10) AS UNSIGNED)), 0) + 1, ',
      '10, ''S'', ''S'', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, ',
      QUOTE(vUsuario), ', ', QUOTE(vUsuario), ' FROM `',
      REPLACE(pTabla, '`', '``'), '` WHERE TRIM(`',
      REPLACE(pColumna, '`', '``'), '`) REGEXP ',
      QUOTE(CONCAT('^', pPrefijo, '[0-9]{11}$')), ' ',
      'ON DUPLICATE KEY UPDATE ',
      '`USUARIO_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'VALUES(`USUARIO_MODIF`), `USUARIO_MODIF`), ',
      '`INSTANTE_MODIF` = IF(VALUES(`CON`) > `CON` OR ',
      'VALUES(`NUM_DIGITOS_CON`) > `NUM_DIGITOS_CON`, ',
      'CURRENT_TIMESTAMP, `INSTANTE_MODIF`), ',
      '`CON` = GREATEST(`CON`, VALUES(`CON`)), ',
      '`NUM_DIGITOS_CON` = GREATEST(`NUM_DIGITOS_CON`, ',
      'VALUES(`NUM_DIGITOS_CON`))'
    );
    PREPARE oSentenciaAjusteContador FROM @sSqlAjusteContador;
    EXECUTE oSentenciaAjusteContador;
    DEALLOCATE PREPARE oSentenciaAjusteContador;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_ALB_CREAR_FACTURA_FIN
DROP PROCEDURE IF EXISTS `PRC_ALB_CREAR_FACTURA_FIN`;
DELIMITER ;;
CREATE PROCEDURE `PRC_ALB_CREAR_FACTURA_FIN`(
  IN p_NUMERO_FAC varchar(20),
  IN p_SERIE_FAC varchar(20),
  IN p_NUMERO_ALB varchar(20),
  IN p_SERIE_ALB varchar(20),
  IN p_USUARIO varchar(100))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_total_base decimal(18,6) DEFAULT 0;
  DECLARE v_total_iva decimal(18,6) DEFAULT 0;
  DECLARE v_por_retencion decimal(19,6) DEFAULT 0;
  DECLARE v_total_retencion decimal(18,6) DEFAULT 0;
  DECLARE v_pendientes int DEFAULT 0;
  SELECT IFNULL(SUM(`CANTIDAD_FACLIN` *
                    `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`), 0),
         IFNULL(SUM(`CANTIDAD_FACLIN` *
              (`PRECIO_VENTA_CIVA_ARTICULO_FACLIN` -
               `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`)), 0)
    INTO v_total_base, v_total_iva
    FROM `fza_facturas_lineas`
   WHERE `NUMERO_FAC_FACLIN` = p_NUMERO_FAC
     AND `SERIE_FAC_FACLIN` = p_SERIE_FAC;
  SELECT IFNULL(`PORCENTAJE_RETENCION_FAC`, 0)
    INTO v_por_retencion
    FROM `fza_facturas`
   WHERE `NUMERO_FAC` = p_NUMERO_FAC
     AND `SERIE_FAC` = p_SERIE_FAC;
  SET v_total_retencion = v_total_base * v_por_retencion / 100;
  UPDATE `fza_facturas`
     SET `TOTAL_BASES_FAC` = v_total_base,
         `TOTAL_IMPUESTOS_FAC` = v_total_iva,
         `TOTAL_RETENCION_FAC` = v_total_retencion,
         `TOTAL_LIQUIDO_FAC` =
           v_total_base + v_total_iva - v_total_retencion,
         `INSTANTE_MODIF` = NOW(),
         `USUARIO_MODIF` = p_USUARIO
   WHERE `NUMERO_FAC` = p_NUMERO_FAC
     AND `SERIE_FAC` = p_SERIE_FAC;
  IF p_NUMERO_ALB IS NOT NULL AND p_NUMERO_ALB <> '' THEN
    SELECT COUNT(*)
      INTO v_pendientes
      FROM `fza_albaranes_lineas`
     WHERE `NUMERO_ALB_ALBLIN` = p_NUMERO_ALB
       AND `SERIE_ALB_ALBLIN` = p_SERIE_ALB
       AND IFNULL(`ESFACTURADA_ALBLIN`, 'N') <> 'S';
    IF v_pendientes = 0 THEN
      UPDATE `fza_albaranes`
         SET `ESTADO_ALB` = 'FACTURADO',
             `NUMERO_FAC_ALB` = p_NUMERO_FAC,
             `SERIE_FAC_ALB` = p_SERIE_FAC,
             `INSTANTE_MODIF` = NOW(),
             `USUARIO_MODIF` = p_USUARIO
       WHERE `NUMERO_ALB` = p_NUMERO_ALB
         AND `SERIE_ALB` = p_SERIE_ALB;
    ELSE
      UPDATE `fza_albaranes`
         SET `ESTADO_ALB` = 'PARCIAL',
             `INSTANTE_MODIF` = NOW(),
             `USUARIO_MODIF` = p_USUARIO
       WHERE `NUMERO_ALB` = p_NUMERO_ALB
         AND `SERIE_ALB` = p_SERIE_ALB;
    END IF;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_ALB_CREAR_FACTURA_INICIO
DROP PROCEDURE IF EXISTS `PRC_ALB_CREAR_FACTURA_INICIO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_ALB_CREAR_FACTURA_INICIO`(
  IN p_NUMERO_ALB varchar(20),
  IN p_SERIE_ALB varchar(20),
  IN p_USUARIO varchar(100),
  OUT p_NUMERO_FAC varchar(20),
  OUT p_SERIE_FAC varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_serie varchar(20);
  DECLARE v_numero varchar(20);
  SELECT `SERIE_ALB`
    INTO v_serie
    FROM `fza_albaranes`
   WHERE `NUMERO_ALB` = p_NUMERO_ALB
     AND `SERIE_ALB` = p_SERIE_ALB;
  SELECT LPAD(IFNULL(MAX(CAST(`NUMERO_FAC` AS UNSIGNED)), 0) + 1, 6, '0')
    INTO v_numero
    FROM `fza_facturas`
   WHERE `SERIE_FAC` = v_serie;
  INSERT INTO `fza_facturas` (
    `NUMERO_FAC`, `SERIE_FAC`, `FECHA_FAC`, `FASE_FAC`, `TIPO_FAC`,
    `CODIGO_EMP_FAC`, `RAZON_SOCIAL_EMPRESA_FAC`, `NIF_EMPRESA_FAC`,
    `MOVIL_EMPRESA_FAC`, `EMAIL_EMPRESA_FAC`,
    `DIRECCION1_EMPRESA_FAC`, `DIRECCION2_EMPRESA_FAC`,
    `POBLACION_EMPRESA_FAC`, `PROVINCIA_EMPRESA_FAC`,
    `CODIGO_PAI_EMPRESA_FAC`, `NOMBRE_PAI_EMPRESA_FAC`,
    `CODIGO_POSTAL_EMPRESA_FAC`, `GRUPO_ZONA_IVA_EMPRESA_FAC`,
    `CODIGO_CLI_FAC`, `RAZON_SOCIAL_CLIENTE_FAC`, `NIF_CLIENTE_FAC`,
    `MOVIL_CLIENTE_FAC`, `EMAIL_CLIENTE_FAC`,
    `DIRECCION1_CLIENTE_FAC`, `DIRECCION2_CLIENTE_FAC`,
    `POBLACION_CLIENTE_FAC`, `PROVINCIA_CLIENTE_FAC`,
    `CODIGO_POSTAL_CLIENTE_FAC`, `CODIGO_PAI_CLIENTE_FAC`,
    `NOMBRE_PAI_CLIENTE_FAC`, `CODIGO_IVA_FAC`,
    `ESIVA_RECARGO_CLIENTE_FAC`, `ESIVA_EXENTO_CLIENTE_FAC`,
    `ESINTRACOMUNITARIO_CLIENTE_FAC`,
    `TARIFA_ARTICULO_CLIENTE_FAC`, `ESIMP_INCL_TARIFA_CLIENTE_FAC`,
    `PORCENTAJE_IVAN_FAC`, `PORCENTAJE_IVAR_FAC`,
    `PORCENTAJE_IVAS_FAC`, `PORCENTAJE_IVAE_FAC`,
    `PORCENTAJE_RETENCION_FAC`, `FORMA_PAGO_FAC`, `CONTADOR_LINEAS_FAC`,
    `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`)
  SELECT v_numero, v_serie, CURRENT_DATE(), 'BORRADOR', 'NORMAL',
         A.`CODIGO_EMP_ALB`, A.`RAZON_SOCIAL_EMPRESA_ALB`,
         A.`NIF_EMPRESA_ALB`, A.`MOVIL_EMPRESA_ALB`, A.`EMAIL_EMPRESA_ALB`,
         A.`DIRECCION1_EMPRESA_ALB`, A.`DIRECCION2_EMPRESA_ALB`,
         A.`POBLACION_EMPRESA_ALB`, A.`PROVINCIA_EMPRESA_ALB`,
         A.`CODIGO_PAI_EMPRESA_ALB`, A.`NOMBRE_PAI_EMPRESA_ALB`,
         A.`CODIGO_POSTAL_EMPRESA_ALB`, A.`GRUPO_ZONA_IVA_EMPRESA_ALB`,
         A.`CODIGO_CLI_ALB`, A.`RAZON_SOCIAL_CLIENTE_ALB`,
         A.`NIF_CLIENTE_ALB`, A.`MOVIL_CLIENTE_ALB`, A.`EMAIL_CLIENTE_ALB`,
         A.`DIRECCION1_CLIENTE_ALB`, A.`DIRECCION2_CLIENTE_ALB`,
         A.`POBLACION_CLIENTE_ALB`, A.`PROVINCIA_CLIENTE_ALB`,
         A.`CODIGO_POSTAL_CLIENTE_ALB`, A.`CODIGO_PAI_CLIENTE_ALB`,
         A.`NOMBRE_PAI_CLIENTE_ALB`, A.`CODIGO_IVA_ALB`,
         A.`ESIVA_RECARGO_CLIENTE_ALB`, A.`ESIVA_EXENTO_CLIENTE_ALB`,
         A.`ESINTRACOMUNITARIO_CLIENTE_ALB`,
         A.`TARIFA_ARTICULO_CLIENTE_ALB`,
         A.`ESIMP_INCL_TARIFA_CLIENTE_ALB`,
         A.`PORCENTAJE_IVAN_ALB`, A.`PORCENTAJE_IVAR_ALB`,
         A.`PORCENTAJE_IVAS_ALB`, A.`PORCENTAJE_IVAE_ALB`,
         A.`PORCENTAJE_RETENCION_ALB`, A.`FORMA_PAGO_ALB`, '0',
         NOW(), p_USUARIO, p_USUARIO
    FROM `fza_albaranes` A
   WHERE A.`NUMERO_ALB` = p_NUMERO_ALB
     AND A.`SERIE_ALB` = p_SERIE_ALB;
  SET p_NUMERO_FAC = v_numero;
  SET p_SERIE_FAC = v_serie;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_ALB_CREAR_FACTURA_LINEA
DROP PROCEDURE IF EXISTS `PRC_ALB_CREAR_FACTURA_LINEA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_ALB_CREAR_FACTURA_LINEA`(
  IN p_NUMERO_FAC varchar(20),
  IN p_SERIE_FAC varchar(20),
  IN p_NUMERO_ALB varchar(20),
  IN p_SERIE_ALB varchar(20),
  IN p_LINEA_ALB varchar(4),
  IN p_USUARIO varchar(100))
SQL SECURITY INVOKER
PRC: BEGIN
  DECLARE v_linea_fac varchar(4);
  DECLARE v_contador_fac int DEFAULT 0;
  DECLARE v_facturada varchar(1);
  SELECT IFNULL(`ESFACTURADA_ALBLIN`, 'N')
    INTO v_facturada
    FROM `fza_albaranes_lineas`
   WHERE `NUMERO_ALB_ALBLIN` = p_NUMERO_ALB
     AND `SERIE_ALB_ALBLIN` = p_SERIE_ALB
     AND `LINEA_ALBLIN` = p_LINEA_ALB;
  IF v_facturada = 'S' THEN
    LEAVE PRC;
  END IF;
  SELECT IFNULL(CAST(NULLIF(`CONTADOR_LINEAS_FAC`, '') AS UNSIGNED), 0) + 10
    INTO v_contador_fac
    FROM `fza_facturas`
   WHERE `NUMERO_FAC` = p_NUMERO_FAC
     AND `SERIE_FAC` = p_SERIE_FAC
   FOR UPDATE;
  IF v_contador_fac = 0 THEN
    LEAVE PRC;
  END IF;
  UPDATE `fza_facturas`
     SET `CONTADOR_LINEAS_FAC` = LPAD(v_contador_fac, 8, '0')
   WHERE `NUMERO_FAC` = p_NUMERO_FAC
     AND `SERIE_FAC` = p_SERIE_FAC;
  IF ROW_COUNT() = 0 THEN
    LEAVE PRC;
  END IF;
  SET v_linea_fac = LPAD(v_contador_fac, 4, '0');
  INSERT INTO `fza_facturas_lineas` (
    `NUMERO_FAC_FACLIN`, `SERIE_FAC_FACLIN`, `LINEA_FACLIN`,
    `CODIGO_ART_FACLIN`, `CODIGO_UNIDAD_FACLIN`,
    `LOTE_FACLIN`, `FECHA_CADUCIDAD_FACLIN`,
    `CODIGO_FAM_FACLIN`, `NOMBRE_FAM_FACLIN`,
    `DESCRIPCION_ARTICULO_FACLIN`, `DESCRIPCION_VARIACION_FACLIN`,
    `TIPO_CANTIDAD_ARTICULO_FACLIN`, `CANTIDAD_FACLIN`,
    `CODIGO_TAR_FACLIN`, `ESIMP_INCL_TARIFA_FACLIN`,
    `TIPO_IVA_ARTICULO_FACLIN`, `PORCENTAJE_IVA_FACLIN`,
    `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`,
    `PRECIO_VENTA_CIVA_ARTICULO_FACLIN`,
    `TOTAL_FACLIN`, `CODIGO_ALM_FACLIN`,
    `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`)
  SELECT p_NUMERO_FAC, p_SERIE_FAC, v_linea_fac,
         AL.`CODIGO_ART_ALBLIN`, AL.`CODIGO_UNIDAD_ALBLIN`,
         AL.`LOTE_ALBLIN`, AL.`FECHA_CADUCIDAD_ALBLIN`,
         AL.`CODIGO_FAM_ALBLIN`, AL.`NOMBRE_FAM_ALBLIN`,
         AL.`DESCRIPCION_ARTICULO_ALBLIN`,
         AL.`DESCRIPCION_VARIACION_ALBLIN`,
         AL.`TIPO_CANTIDAD_ARTICULO_ALBLIN`, AL.`CANTIDAD_ALBLIN`,
         AL.`CODIGO_TAR_ALBLIN`, AL.`ESIMP_INCL_TARIFA_ALBLIN`,
         AL.`TIPO_IVA_ARTICULO_ALBLIN`, AL.`PORCENTAJE_IVA_ALBLIN`,
         AL.`PRECIO_VENTA_SIVA_ARTICULO_ALBLIN`,
         AL.`PRECIO_VENTA_CIVA_ARTICULO_ALBLIN`, AL.`TOTAL_ALBLIN`,
         AL.`CODIGO_ALMACEN_ALBLIN`, NOW(), p_USUARIO, p_USUARIO
    FROM `fza_albaranes_lineas` AL
   WHERE AL.`NUMERO_ALB_ALBLIN` = p_NUMERO_ALB
     AND AL.`SERIE_ALB_ALBLIN` = p_SERIE_ALB
     AND AL.`LINEA_ALBLIN` = p_LINEA_ALB;
  UPDATE `fza_albaranes_lineas`
     SET `ESFACTURADA_ALBLIN` = 'S',
         `NUMERO_FAC_ALBLIN` = p_NUMERO_FAC,
         `SERIE_FAC_ALBLIN` = p_SERIE_FAC,
         `LINEA_FAC_ALBLIN` = v_linea_fac,
         `INSTANTE_MODIF` = NOW(),
         `USUARIO_MODIF` = p_USUARIO
   WHERE `NUMERO_ALB_ALBLIN` = p_NUMERO_ALB
     AND `SERIE_ALB_ALBLIN` = p_SERIE_ALB
     AND `LINEA_ALBLIN` = p_LINEA_ALB;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_BUSQUEDA_ARTICULOS
DROP PROCEDURE IF EXISTS `PRC_BUSQUEDA_ARTICULOS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_BUSQUEDA_ARTICULOS`(IN p_tarifa     VARCHAR(10),
    IN p_almacen    VARCHAR(10),
    IN p_fecha      DATE,
    IN p_token      VARCHAR(100),
    IN p_solostock  TINYINT,
    IN p_solotarifa TINYINT)
SQL SECURITY INVOKER
BEGIN
    IF p_tarifa IS NULL OR TRIM(p_tarifa) = '' THEN
        SET p_tarifa := 'PVP';
    END IF;
    IF p_fecha IS NULL THEN
        SET p_fecha := CURDATE();
    END IF;

    SELECT
        v.*,
        COALESCE(stk.STOCK_DISPONIBLE, 0) AS STOCK_DISPONIBLE
    FROM vi_art_busquedas v

    /* Stock unificado: por SKU + por código directo */
    LEFT JOIN (
        SELECT COD_ART, SUM(STOCK) AS STOCK_DISPONIBLE
        FROM (
            /* Artículos CON SKU: sumar por artículo padre */
            SELECT sku.CODIGO_ART_SKU AS COD_ART,
                   s.CANTIDAD_STK          AS STOCK
              FROM fza_articulos_stockactual s
              JOIN fza_articulos_skus sku
                ON s.CODIGO_UNIDAD_STK = sku.CODIGO_UNIDAD_SKU
             WHERE s.CODIGO_ALM_STK = p_almacen
            UNION ALL
            /* Artículos SIN SKU: código directo no existe en fza_articulos_skus */
            SELECT s.CODIGO_UNIDAD_STK AS COD_ART,
                   s.CANTIDAD_STK      AS STOCK
              FROM fza_articulos_stockactual s
             WHERE s.CODIGO_ALM_STK = p_almacen
               AND NOT EXISTS (
                   SELECT 1 FROM fza_articulos_skus sku2
                    WHERE sku2.CODIGO_UNIDAD_SKU = s.CODIGO_UNIDAD_STK
               )
        ) t
        GROUP BY COD_ART
    ) stk ON v.CODIGO_ART_ART = stk.COD_ART

    WHERE (v.CODIGO_TAR_ARTTAR = p_tarifa OR v.CODIGO_TAR_ARTTAR IS NULL)
      AND v.FECHA_DESDE_ARTTAR <= p_fecha
      AND (v.FECHA_HASTA_ARTTAR IS NULL OR v.FECHA_HASTA_ARTTAR >= p_fecha)
      AND (p_token IS NULL OR p_token = ''
           OR v.CODIGO_ART_ART      LIKE p_token
           OR v.DESCRIPCION_ART LIKE p_token
           OR v.DESCRIPCION_FAM  LIKE p_token)
      AND (p_solostock  = 0 OR COALESCE(stk.STOCK_DISPONIBLE, 0) > 0)
      AND (p_solotarifa = 0 OR v.CODIGO_TAR_ARTTAR IS NOT NULL)

    ORDER BY v.CODIGO_ART_ART;

END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CALCULAR_FACTURA_NETOS
DROP PROCEDURE IF EXISTS `PRC_CALCULAR_FACTURA_NETOS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CALCULAR_FACTURA_NETOS`(IN `pSERIE_FACTURA` VARCHAR(12), 
  IN `pNRO_FACTURA` VARCHAR(12))
SQL SECURITY INVOKER
BEGIN
  DECLARE pPRECIOSIVA decimal(19,6);
  DECLARE pPRECIOCIVA decimal(19,6);
  DECLARE pPORCEN decimal(19,6);
  DECLARE pTIPO VARCHAR(2);
  DECLARE pZONAIVA_RE varchar(1) DEFAULT '';          /* CAMBIADO */
  DECLARE pAPLICA_RE_CLIENTE varchar(1) DEFAULT '';   /* CAMBIADO */
  DECLARE pIVA_EXENTO varchar(1) DEFAULT '';
  DECLARE pREG_AG_EMP varchar(1) DEFAULT '';
  DECLARE pREG_AG_CLI varchar(1) DEFAULT '';
  DECLARE pINTRACOMUNITARIO varchar(1) DEFAULT '';
  DECLARE pAPLICA_RETENCIONES_CLI varchar(1) DEFAULT '';
  DECLARE pAPLICA_RETENCIONES_EMP varchar(1) DEFAULT '';
  DECLARE pPORCENREN decimal(19,6) DEFAULT 0;
  DECLARE pPORCENRER decimal(19,6) DEFAULT 0;
  DECLARE pPORCENRES decimal(19,6) DEFAULT 0;
  DECLARE pPORCENREE decimal(19,6) DEFAULT 0;
  DECLARE pSUMBASEN decimal(19,6) DEFAULT 0;
  DECLARE pSUMBASER decimal(19,6) DEFAULT 0;
  DECLARE pSUMBASES decimal(19,6) DEFAULT 0;
  DECLARE pSUMBASEE decimal(19,6) DEFAULT 0;
  DECLARE pTOTN decimal(19,6) DEFAULT 0;
  DECLARE pTOTR decimal(19,6) DEFAULT 0;
  DECLARE pTOTS decimal(19,6) DEFAULT 0;
  DECLARE pTOTE decimal(19,6) DEFAULT 0;
  DECLARE pTOTRECN decimal(19,6) DEFAULT 0;
  DECLARE pTOTRECR decimal(19,6) DEFAULT 0;
  DECLARE pTOTRECS decimal(19,6) DEFAULT 0;
  DECLARE pTOTRECE decimal(19,6) DEFAULT 0;
  DECLARE pSUMTOTREC decimal(19,6) DEFAULT 0;
  DECLARE pSUMTOT decimal(19,6) DEFAULT 0;
  DECLARE pPORCENN decimal(19,6) DEFAULT 0;
  DECLARE pTOTBASES decimal(19,6) DEFAULT 0;
  DECLARE pPORCENR decimal(19,6) DEFAULT 0;
  DECLARE pPORCENS decimal(19,6) DEFAULT 0;
  DECLARE pPORCENE decimal(19,6) DEFAULT 0;
  DECLARE pPORCENRET decimal(19,6) DEFAULT 0;
  DECLARE pGRUPO_ZONA_IVA varchar(12);
  DECLARE pCODIGO_IVA varchar(12);
  DECLARE pTOTALRET decimal(19,6) DEFAULT 0;
  DECLARE pFECHA datetime;
  DECLARE pLINEA varchar(3);
  DECLARE pIMP_INCL varchar(1);
  DECLARE pCANTIDAD decimal(19,6) DEFAULT 0;
  DECLARE pCODART varchar(20);
  DECLARE pTIPOIVAF varchar(1) DEFAULT 'X';
  DECLARE pIRPF_IMP_INCL VARCHAR(1);
  DECLARE pVENTA_ACT_FIJ VARCHAR(1);
  DECLARE finished INTEGER DEFAULT 0;
  DECLARE pCODEMPRESA varchar(8);
  
  DECLARE CUR_LINEAS 
          CURSOR FOR 
              SELECT LINEA_FACLIN,
                     CODIGO_ART_FACLIN,
                     PRECIO_VENTA_SIVA_ARTICULO_FACLIN AS PRECIOSIVA,
                     PRECIO_VENTA_CIVA_ARTICULO_FACLIN AS PRECIOCIVA,
                     PORCENTAJE_IVA_FACLIN AS PORCEN,
                     TIPO_IVA_ARTICULO_FACLIN AS TIPO,
                     ESIMP_INCL_TARIFA_FACLIN AS IMP_INCL,
                     CANTIDAD_FACLIN as CANTIDAD_ARTVIN
                FROM fza_facturas_lineas 
               WHERE SERIE_FAC_FACLIN = pSERIE_FACTURA 
                 AND NUMERO_FAC_FACLIN = pNRO_FACTURA;
                 
  DECLARE CONTINUE HANDLER 
          FOR NOT FOUND SET finished = 1;

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
          
  START TRANSACTION;
  
  SELECT PORCENTAJE_IVAN_FAC,
         PORCENTAJE_IVAR_FAC,
         PORCENTAJE_IVAS_FAC,
         PORCENTAJE_IVAE_FAC,
         PORCENTAJE_RETENCION_FAC,
         ESAPLICA_RE_ZONA_IVA_FAC,
         ESIVA_RECARGO_CLIENTE_FAC,
         ESIVA_EXENTO_CLIENTE_FAC,
         ESRETENCIONES_CLIENTE_FAC,
         ESRETENCIONES_EMPRESA_FAC,
         ESIRPF_IMP_INCL_ZONA_IVA_FAC,
         PORCENTAJE_REN_FAC,
         PORCENTAJE_RER_FAC,
         PORCENTAJE_RES_FAC,
         PORCENTAJE_REE_FAC,
         ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC,
         ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC,
         GRUPO_ZONA_IVA_EMPRESA_FAC,
         CODIGO_IVA_FAC,
         ESINTRACOMUNITARIO_CLIENTE_FAC,
         FECHA_FAC,
         CODIGO_EMP_FAC,
         ESVENTA_ACTIVO_FIJO_FAC
    INTO pPORCENN,
         pPORCENR,
         pPORCENS,
         pPORCENE,
         pPORCENRET,
         pZONAIVA_RE,              /* CAMBIADO */
         pAPLICA_RE_CLIENTE,       /* CAMBIADO */
         pIVA_EXENTO,
         pAPLICA_RETENCIONES_CLI,
         pAPLICA_RETENCIONES_EMP,
         pIRPF_IMP_INCL,
         pPORCENREN,
         pPORCENRER,
         pPORCENRES,
         pPORCENREE,
         pREG_AG_EMP,
         pREG_AG_CLI,
         pGRUPO_ZONA_IVA,
         pCODIGO_IVA,
         pINTRACOMUNITARIO,
         pFECHA,
         pCODEMPRESA,
         pVENTA_ACT_FIJ
    FROM fza_facturas
   WHERE SERIE_FAC = pSERIE_FACTURA
     AND NUMERO_FAC = pNRO_FACTURA;
     
  /* Resto de la lógica igual hasta el cálculo de recargos... */
  
  /* CAMBIO EN LA CONDICIÓN DE RECARGOS: */
  IF ( (pZONAIVA_RE ='S') AND (pAPLICA_RE_CLIENTE = 'S') ) THEN
    SET pTOTRECN = pSUMBASEN * (1 + pPORCENREN/100) - pSUMBASEN;
    SET pTOTRECR = pSUMBASER * (1 + pPORCENRER/100) - pSUMBASER;
    SET pTOTRECS = pSUMBASES * (1 + pPORCENRES/100) - pSUMBASES;
    SET pTOTRECE = pSUMBASEE * (1 + pPORCENREE/100) - pSUMBASEE;
    SET pSUMTOTREC = pTOTRECN + pTOTRECR + pTOTRECS + pTOTRECE;
  ELSE 
    SET pTOTRECN = 0;
    SET pTOTRECR = 0;
    SET pTOTRECS = 0;
    SET pTOTRECE = 0;
    SET pSUMTOTREC = 0;
  END IF;
  
  /* ... resto de código ... */
  
  /* CAMBIO EN EL UPDATE FINAL: */
  UPDATE fza_facturas 
     SET TOTAL_BASEI_IVAN_FAC = pSUMBASEN,
         TOTAL_BASEI_IVAR_FAC = pSUMBASER,
         TOTAL_BASEI_IVAS_FAC = pSUMBASES,
         TOTAL_BASEI_IVAE_FAC = pSUMBASEE,
         TOTAL_IVAN_FAC = pTOTN,
         TOTAL_IVAR_FAC = pTOTR,
         TOTAL_IVAS_FAC = pTOTS,
         TOTAL_IVAE_FAC = pTOTE,
         TOTAL_REN_FAC = PTOTRECN,
         TOTAL_RER_FAC = PTOTRECR,
         TOTAL_RES_FAC = PTOTRECS,
         TOTAL_REE_FAC = PTOTRECE,
         TOTAL_BASES_FAC = pTOTBASES,
         TOTAL_RETENCION_FAC = pTOTALRET,
         TOTAL_LIQUIDO_FAC = pTOTBASES + pSUMTOT - PTOTALRET + pSUMTOTREC,
         ESIVA_EXENTO_CLIENTE_FAC = pIVA_EXENTO,
         ESRETENCIONES_CLIENTE_FAC = pAPLICA_RETENCIONES_CLI,
         ESRETENCIONES_EMPRESA_FAC = pAPLICA_RETENCIONES_EMP,
         /* NO ACTUALIZAR: ESIVA_RECARGO_CLIENTE_FAC */
         TOTAL_IMPUESTOS_FAC = pSUMTOTREC + pSUMTOT,
         GRUPO_ZONA_IVA_EMPRESA_FAC = pGRUPO_ZONA_IVA,
         CODIGO_IVA_FAC = pCODIGO_IVA,
         PORCENTAJE_IVAN_FAC = pPORCENN,
         PORCENTAJE_IVAE_FAC = pPORCENE,
         PORCENTAJE_IVAR_FAC = pPORCENR,
         PORCENTAJE_IVAS_FAC = pPORCENS,
         PORCENTAJE_RETENCION_FAC = pPORCENRET
   WHERE NUMERO_FAC = pNRO_FACTURA 
     AND SERIE_FAC = pSERIE_FACTURA;
     
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_ARTICULO
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_ARTICULO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_ARTICULO`(
    IN pCODIGO_ARTICULO               varchar(20),
    IN pDESCRIPCION_ARTICULO          varchar(1000),
    IN pTIPOIVA_ARTICULO              varchar(2),
    IN pTIPO_CANTIDAD_ARTICULO        varchar(20),
    IN pESACTIVO_FIJO_ARTICULO        varchar(1),
    IN pCODIGO_FAMILIA                varchar(20),
    IN pNOMBRE_FAMILIA                varchar(200),
    IN pCODIGO_PROVEEDOR              varchar(20),
    IN pRAZONSOCIAL_PROVEEDOR         varchar(200),
    IN pESPROVEEDORPRINCIPAL          varchar(1),
    IN pPRECIO_ULT_COMPRA             decimal(19,6),
    IN pCODIGO_TARIFA                 varchar(20),
    IN pPRECIOSALIDA_TARIFA           decimal(19,6),
    IN pPRECIOFINAL_TARIFA            decimal(19,6),
    IN pPRECIO_DTO_TARIFA             decimal(19,6),
    IN pPORCEN_DTO_TARIFA             decimal(19,6),
    IN pUSUARIO                       varchar(100)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE pCONT BIGINT;

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
    
    START TRANSACTION;

    IF (TRIM(pCODIGO_ARTICULO) <> '') THEN
        
        /* Comprobar si el artículo existe */
        IF ( EXISTS( SELECT *
                     FROM fza_articulos
                     WHERE `CODIGO_ART_ART` = pCODIGO_ARTICULO) ) THEN
                     
            UPDATE fza_articulos
            SET 
                DESCRIPCION_ART      = pDESCRIPCION_ARTICULO,
                ESACTIVO_FIJO_ART    = pESACTIVO_FIJO_ARTICULO,
                TIPO_IVA_ART          = pTIPOIVA_ARTICULO,
                TIPO_CANTIDAD_ART    = pTIPO_CANTIDAD_ARTICULO,
                CODIGO_FAM_ART   = pCODIGO_FAMILIA,
                USUARIO_MODIF              = pUSUARIO,
                INSTANTE_MODIF             = CURRENT_TIMESTAMP 
            WHERE CODIGO_ART_ART = pCODIGO_ARTICULO;
            
        ELSE
            /* Si no existe, crear uno nuevo */
            CALL PRC_FNC_GET_NEXT_NRO_DOC('AO', pCONT);
            
            INSERT INTO fza_articulos (
                CODIGO_ART_ART,
                ORDEN_ART,        
                DESCRIPCION_ART,
                TIPO_IVA_ART,
                TIPO_CANTIDAD_ART,
                CODIGO_FAM_ART,
                ESACTIVO_FIJO_ART,
                USUARIO_MODIF,
                INSTANTE_MODIF,
                USUARIO_ALTA,
                INSTANTE_ALTA                      
            ) VALUES (
                pCODIGO_ARTICULO,                                                                                         
                pCONT,
                pDESCRIPCION_ARTICULO, 
                pTIPOIVA_ARTICULO,
                pTIPO_CANTIDAD_ARTICULO,
                pCODIGO_FAMILIA,
                pESACTIVO_FIJO_ARTICULO,
                pUSUARIO,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                CURRENT_TIMESTAMP              
            );
            
        END IF;

        /* Llamadas adicionales que siempre ocurren si el código del artículo no estaba vacío */
        CALL PRC_CREAR_ACTUALIZAR_FAMILIA(pCODIGO_FAMILIA, pNOMBRE_FAMILIA, pUSUARIO);
        CALL PRC_CREAR_ACTUALIZAR_PROVEEDOR(pCODIGO_PROVEEDOR, pRAZONSOCIAL_PROVEEDOR, pUSUARIO);
        CALL PRC_CREAR_ACTUALIZAR_ARTICULO_PROVEEDOR(pCODIGO_ARTICULO, pCODIGO_PROVEEDOR, pESPROVEEDORPRINCIPAL, pPRECIO_ULT_COMPRA, pUSUARIO);
        CALL PRC_CREAR_ACTUALIZAR_TARIFA(pCODIGO_ARTICULO, pCODIGO_TARIFA, pPRECIOSALIDA_TARIFA, pPRECIOFINAL_TARIFA, pPRECIO_DTO_TARIFA, pPORCEN_DTO_TARIFA, pUSUARIO);
        
    END IF; 

    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_ARTICULO_PROVEEDOR
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_ARTICULO_PROVEEDOR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_ARTICULO_PROVEEDOR`(
    IN pCODIGO_ARTICULO               varchar(20),
    IN pCODIGO_PROVEEDOR              varchar(20),
    IN pESPROVEEDORPRINCIPAL          varchar(1),
    IN pPRECIO_ULT_COMPRA             decimal(19,6),
    IN pUSUARIO                       varchar(100)
)
SQL SECURITY INVOKER
BEGIN

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
    START TRANSACTION;

    IF ((TRIM(pCODIGO_PROVEEDOR) <> '') AND (TRIM(pCODIGO_ARTICULO) <> '')) THEN
        
        /* Comprobar si ya existe la relación artículo-proveedor */
        IF ( EXISTS( SELECT *
                     FROM fza_articulos_proveedores
                     WHERE `CODIGO_PRV_AP` = pCODIGO_PROVEEDOR
                       AND CODIGO_ART_AP = pCODIGO_ARTICULO )) THEN
                       
            UPDATE fza_articulos_proveedores
            SET 
                PRECIO_ULT_COMPRA_AP    = pPRECIO_ULT_COMPRA,
                ESPROVEEDORPRINCIPAL_AP = pESPROVEEDORPRINCIPAL,
                USUARIO_MODIF                            = pUSUARIO,
                INSTANTE_MODIF                           = CURRENT_TIMESTAMP             
            WHERE `CODIGO_PRV_AP` = pCODIGO_PROVEEDOR
              AND CODIGO_ART_AP = pCODIGO_ARTICULO;
              
        ELSE
            /* Si no existe, insertar */
            INSERT INTO fza_articulos_proveedores (
                CODIGO_PRV_AP, 
                CODIGO_ART_AP,                  
                PRECIO_ULT_COMPRA_AP,
                ESPROVEEDORPRINCIPAL_AP,                                                                                        
                USUARIO_MODIF,
                INSTANTE_MODIF,
                USUARIO_ALTA,
                INSTANTE_ALTA                     
            ) VALUES (
                pCODIGO_PROVEEDOR,
                pCODIGO_ARTICULO,
                pPRECIO_ULT_COMPRA,       
                pESPROVEEDORPRINCIPAL,                                                                                                      
                pUSUARIO,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                CURRENT_TIMESTAMP              
            );
            
        END IF;
        
    END IF;        

    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_CLIENTE
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_CLIENTE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_CLIENTE`(
    IN `pCODIGO_CLIENTE`                    varchar(20),
    IN `pRAZONSOCIAL_CLIENTE`               varchar(200),
    IN `pNIF_CLIENTE`                       varchar(50),
    IN `pMOVIL_CLIENTE`                     varchar(40),
    IN `pEMAIL_CLIENTE`                     varchar(200),
    IN `pDIRECCION1_CLIENTE`                varchar(200),
    IN `pDIRECCION2_CLIENTE`                varchar(200),
    IN `pPOBLACION_CLIENTE`                 varchar(200),
    IN `pPROVINCIA_CLIENTE`                 varchar(200),
    IN `pCPOSTAL_CLIENTE`                   varchar(15),
    IN `pCOD_PAIS_CLIENTE`                  varchar(3),
    IN `pPAIS_CLIENTE`                      varchar(150),
    IN `pESIVA_EXENTO_CLIENTE`              varchar(1),
    IN `pESRETENCIONES_CLIENTE`             varchar(1),
    IN `pESIVA_RECARGO_CLIENTE`             varchar(1),
    IN `pESINTRACOMUNITARIO_CLIENTE`        varchar(1),
    IN `pESREGIMENESPECIALAGRICOLA_CLIENTE` varchar(1),
    IN `pTARIFA_ARTICULO_CLIENTE`           varchar(20),
    IN `pUSUARIO`                           varchar(100)
)
SQL SECURITY INVOKER
BEGIN

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
    START TRANSACTION;
    
    /* Comprobar si el cliente ya existe */
    IF ( EXISTS( SELECT *
                 FROM fza_clientes
                 WHERE `CODIGO_CLI_CLI` = pCODIGO_CLIENTE) ) THEN
                 
        UPDATE fza_clientes
        SET 
            RAZON_SOCIAL_CLI               = pRAZONSOCIAL_CLIENTE,
            NIF_CLI                       = pNIF_CLIENTE,
            MOVIL_CLI                     = pMOVIL_CLIENTE,
            EMAIL_CLI                     = pEMAIL_CLIENTE,
            DIRECCION1_CLI                = pDIRECCION1_CLIENTE,
            DIRECCION2_CLI                = pDIRECCION2_CLIENTE,
            POBLACION_CLI                 = pPOBLACION_CLIENTE,
            PROVINCIA_CLI                 = pPROVINCIA_CLIENTE,
            CODIGO_POSTAL_CLI                   = pCPOSTAL_CLIENTE,
            NOMBRE_PAI_CLI               = pPAIS_CLIENTE,
            CODIGO_PAI_CLI               = pCOD_PAIS_CLIENTE,
            ESIVA_EXENTO_CLI              = pESIVA_EXENTO_CLIENTE,
            ESRETENCIONES_CLI             = pESRETENCIONES_CLIENTE,
            ESIVA_RECARGO_CLI             = pESIVA_RECARGO_CLIENTE,
            ESREGIMENESPECIALAGRICOLA_CLI = pESREGIMENESPECIALAGRICOLA_CLIENTE,
            ESINTRACOMUNITARIO_CLI        = pESINTRACOMUNITARIO_CLIENTE,
            TARIFA_ARTICULO_CLI           = pTARIFA_ARTICULO_CLIENTE,
            USUARIO_MODIF                      = pUSUARIO,
            INSTANTE_MODIF                     = CURRENT_TIMESTAMP
        WHERE CODIGO_CLI_CLI = pCODIGO_CLIENTE;
        
    ELSE
    
        /* Si no existe, insertar */
        INSERT INTO fza_clientes (
            CODIGO_CLI_CLI,
            RAZON_SOCIAL_CLI,
            NIF_CLI,
            MOVIL_CLI,
            EMAIL_CLI,
            DIRECCION1_CLI,
            DIRECCION2_CLI,
            POBLACION_CLI,
            PROVINCIA_CLI,
            CODIGO_POSTAL_CLI,
            NOMBRE_PAI_CLI,
            CODIGO_PAI_CLI,
            ESIVA_EXENTO_CLI,
            ESRETENCIONES_CLI,
            ESIVA_RECARGO_CLI,
            ESREGIMENESPECIALAGRICOLA_CLI,
            ESINTRACOMUNITARIO_CLI,
            TARIFA_ARTICULO_CLI,
            USUARIO_MODIF,
            USUARIO_ALTA,
            INSTANTE_ALTA,
            INSTANTE_MODIF
        ) VALUES (
            pCODIGO_CLIENTE,
            pRAZONSOCIAL_CLIENTE,
            pNIF_CLIENTE,
            pMOVIL_CLIENTE,
            pEMAIL_CLIENTE,
            pDIRECCION1_CLIENTE,
            pDIRECCION2_CLIENTE,
            pPOBLACION_CLIENTE,
            pPROVINCIA_CLIENTE,
            pCPOSTAL_CLIENTE,
            pPAIS_CLIENTE,
            pCOD_PAIS_CLIENTE,
            pESIVA_EXENTO_CLIENTE,
            pESRETENCIONES_CLIENTE,
            pESIVA_RECARGO_CLIENTE,
            pESREGIMENESPECIALAGRICOLA_CLIENTE,
            pESINTRACOMUNITARIO_CLIENTE,
            pTARIFA_ARTICULO_CLIENTE,
            pUSUARIO,
            pUSUARIO,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        );
        
    END IF;
    
    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_EMPRESA
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_EMPRESA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_EMPRESA`(
  in pCODIGO_EMPRESA varchar(10),
  in pRAZONSOCIAL_EMPRESA varchar(200),
  in pNIF_EMPRESA varchar(50),
  in pMOVIL_EMPRESA varchar(40),
  in pEMAIL_EMPRESA varchar(200),
  in pDIRECCION1_EMPRESA varchar(200),
  in pDIRECCION2_EMPRESA varchar(200),
  in pPOBLACION_EMPRESA varchar(200),
  in pPROVINCIA_EMPRESA varchar(200),
  in pCPOSTAL_EMPRESA varchar(15),
  in pPAIS_EMPRESA varchar(150),
  in pCODPAIS_EMPRESA varchar(150),
  in pRETENCIONES_EMPRESA varchar(1),
  in pIVA_RECARGO_EMPRESA varchar(1),
  in pREGIMENESPECIALAGRICOLA_EMPRESA varchar(1),
  in pGRUPO_ZONA_IVA_EMPRESA varchar(10),
  in pUSUARIO varchar(100))
SQL SECURITY INVOKER
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  kk: BEGIN
    ROLLBACK;
    RESIGNAL;
  END kk;
  START TRANSACTION;
  IF (EXISTS (
  SELECT *
  FROM fza_empresas
  WHERE CODIGO_EMP_EMP = pCODIGO_EMPRESA)) THEN
    UPDATE fza_empresas
      SET RAZON_SOCIAL_EMP = pRAZONSOCIAL_EMPRESA,
      NIF_EMP = pNIF_EMPRESA,
      MOVIL_EMP = pMOVIL_EMPRESA,
      EMAIL_EMP = pEMAIL_EMPRESA,
      DIRECCION1_EMP = pDIRECCION1_EMPRESA,
      DIRECCION2_EMP = pDIRECCION2_EMPRESA,
      POBLACION_EMP = pPOBLACION_EMPRESA,
      PROVINCIA_EMP = pPROVINCIA_EMPRESA,
      CODIGO_POSTAL_EMP = pCPOSTAL_EMPRESA,
      NOMBRE_PAI_EMP = pPAIS_EMPRESA,
      CODIGO_PAI_EMP = pCODPAIS_EMPRESA,
      ESRETENCIONES_EMP = pRETENCIONES_EMPRESA,
      ESREGIMENESPECIALAGRICOLA_EMP = pREGIMENESPECIALAGRICOLA_EMPRESA,
      GRUPO_ZONA_IVA_EMP = pGRUPO_ZONA_IVA_EMPRESA,
      USUARIO_MODIF = pUSUARIO,
      INSTANTE_MODIF = CURRENT_TIMESTAMP
      WHERE CODIGO_EMP_EMP = pCODIGO_EMPRESA;
  ELSE
    INSERT INTO fza_empresas(CODIGO_EMP_EMP,
      RAZON_SOCIAL_EMP,
      NIF_EMP,
      MOVIL_EMP,
      EMAIL_EMP,
      DIRECCION1_EMP,
      DIRECCION2_EMP,
      POBLACION_EMP,
      PROVINCIA_EMP,
      CODIGO_POSTAL_EMP,
      NOMBRE_PAI_EMP,
      CODIGO_PAI_EMP,
      ESRETENCIONES_EMP,
      ESREGIMENESPECIALAGRICOLA_EMP,
      GRUPO_ZONA_IVA_EMP,
      USUARIO_MODIF,
      USUARIO_ALTA,
      INSTANTE_ALTA,
      INSTANTE_MODIF
      )
      VALUES
      (pCODIGO_EMPRESA,
      pRAZONSOCIAL_EMPRESA,
      pNIF_EMPRESA,
      pMOVIL_EMPRESA,
      pEMAIL_EMPRESA,
      pDIRECCION1_EMPRESA,
      pDIRECCION2_EMPRESA,
      pPOBLACION_EMPRESA,
      pPROVINCIA_EMPRESA,
      pCPOSTAL_EMPRESA,
      pPAIS_EMPRESA,
      pCODPAIS_EMPRESA,
      pRETENCIONES_EMPRESA,
      pREGIMENESPECIALAGRICOLA_EMPRESA,
      pGRUPO_ZONA_IVA_EMPRESA,
      pUSUARIO,
      pUSUARIO,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
      );
  END IF;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_FAMILIA
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_FAMILIA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_FAMILIA`(
    IN pCODIGO_FAMILIA      varchar(20),
    IN pNOMBRE_FAMILIA      varchar(200),
    IN pUSUARIO             varchar(100)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE pCONT BIGINT;

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
    
    START TRANSACTION;

    IF (TRIM(pCODIGO_FAMILIA) <> '') THEN
        
        /* Comprobar si la familia ya existe */
        IF ( EXISTS( SELECT *
                     FROM fza_articulos_familias
                     WHERE `CODIGO_FAM_FAM` = pCODIGO_FAMILIA) ) THEN
                     
            UPDATE fza_articulos_familias
            SET 
                NOMBRE_FAM_FAM      = pNOMBRE_FAMILIA,
                DESCRIPCION_FAM = pNOMBRE_FAMILIA,
                USUARIO_MODIF        = pUSUARIO,
                INSTANTE_MODIF       = CURRENT_TIMESTAMP             
            WHERE CODIGO_FAM_FAM = pCODIGO_FAMILIA;
            
        ELSE
            /* Si no existe, insertar */
            CALL PRC_FNC_GET_NEXT_NRO_DOC('FO', pCONT);
            
            INSERT INTO fza_articulos_familias (
                CODIGO_FAM_FAM,
                ORDEN_FAM,
                NOMBRE_FAM_FAM,
                DESCRIPCION_FAM,
                USUARIO_MODIF,
                INSTANTE_MODIF,
                USUARIO_ALTA,
                INSTANTE_ALTA                     
            ) VALUES (
                pCODIGO_FAMILIA,
                pCONT,
                pNOMBRE_FAMILIA,
                pNOMBRE_FAMILIA,
                pUSUARIO,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                CURRENT_TIMESTAMP              
            );
            
        END IF;
        
    END IF;        

    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_KEY
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_KEY`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_KEY`(
    IN pUSUARIO       varchar(200),
    IN pKEY           varchar(100),
    IN pSUBKEY        varchar(100),
    IN pVALUE         varchar(200),
    IN pVALUE_TEXT    text,
    IN pUSUARIO_MODIF varchar(100)
)
SQL SECURITY INVOKER
BEGIN

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
    START TRANSACTION;    
    /* Comprobamos si el registro existe */
    IF ( EXISTS(
             SELECT 1
             FROM `fza_usuarios_perfiles`
             WHERE `USUARIO_GRUPO_USUPER` = pUSUARIO
               AND `KEY_USUPER`           = pKEY 
               AND `SUBKEY_USUPER`        = pSUBKEY 
        )) THEN
        
        UPDATE `fza_usuarios_perfiles`
        SET `VALUE_USUPER`      = pVALUE,
            `VALUE_TEXT_USUPER` = pVALUE_TEXT,
            `USUARIO_MODIF`        = pUSUARIO_MODIF
        WHERE `USUARIO_GRUPO_USUPER` = pUSUARIO
          AND `KEY_USUPER`           = pKEY 
          AND `SUBKEY_USUPER`        = pSUBKEY;
          
    ELSE
    
        INSERT INTO fza_usuarios_perfiles (
            `USUARIO_GRUPO_USUPER`, 
            `KEY_USUPER`, 
            `SUBKEY_USUPER`, 
            `VALUE_USUPER`, 
            `VALUE_TEXT_USUPER`, 
            `INSTANTE_ALTA`, 
            `USUARIO_ALTA`, 
            `USUARIO_MODIF`
        ) VALUES (
            pUSUARIO,
            pKEY,
            pSUBKEY,
            pVALUE,
            pVALUE_TEXT,
            CURRENT_TIMESTAMP,
            pUSUARIO_MODIF,
            pUSUARIO_MODIF
        );
        
    END IF;
    
    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_PROVEEDOR
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_PROVEEDOR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_PROVEEDOR`(
    IN pCODIGO_PROVEEDOR      varchar(20),
    IN pRAZONSOCIAL_PROVEEDOR varchar(200),
    IN pUSUARIO               varchar(100)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE pCONT BIGINT;

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
    
    START TRANSACTION;

    IF (TRIM(pCODIGO_PROVEEDOR) <> '') THEN
        
        /* Comprobar si el proveedor ya existe */
        IF ( EXISTS( SELECT *
                     FROM fza_proveedores
                     WHERE `CODIGO_PRV_PRV` = pCODIGO_PROVEEDOR) ) THEN
                     
            UPDATE fza_proveedores
            SET 
                RAZON_SOCIAL_PRV = pRAZONSOCIAL_PROVEEDOR,
                USUARIO_MODIF          = pUSUARIO,
                INSTANTE_MODIF         = CURRENT_TIMESTAMP             
            WHERE CODIGO_PRV_PRV = pCODIGO_PROVEEDOR;
            
        ELSE
            /* Si no existe, obtener el siguiente número e insertar */
            CALL PRC_FNC_GET_NEXT_NRO_DOC('PO', pCONT);
            
            INSERT INTO fza_proveedores (
                CODIGO_PRV_PRV,
                ORDEN_PRV,
                RAZON_SOCIAL_PRV,
                USUARIO_MODIF,
                INSTANTE_MODIF,
                USUARIO_ALTA,
                INSTANTE_ALTA                     
            ) VALUES (
                pCODIGO_PROVEEDOR,
                pCONT,
                pRAZONSOCIAL_PROVEEDOR,
                pUSUARIO,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                CURRENT_TIMESTAMP              
            );
            
        END IF;
        
    END IF;        

    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_TARIFA
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_TARIFA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_TARIFA`(
    IN pCODIGO_ARTICULO     varchar(20),
    IN pCODIGO_TARIFA       varchar(20),
    IN pPRECIOSALIDA_TARIFA decimal(19,6),
    IN pPRECIOFINAL_TARIFA  decimal(19,6),
    IN pPRECIO_DTO_TARIFA   decimal(19,6),
    IN pPORCEN_DTO_TARIFA   decimal(19,6),
    IN pUSUARIO             varchar(100)
)
SQL SECURITY INVOKER
BEGIN

    DECLARE ppPRECIOSALIDA_TARIFA decimal(19,6);
    DECLARE ppPRECIOFINAL_TARIFA  decimal(19,6);
    DECLARE ppPORCEN_DTO_TARIFA   decimal(19,6);
    DECLARE ppPRECIO_DTO_TARIFA   decimal(19,6);

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;

    START TRANSACTION;

    IF (TRIM(pCODIGO_TARIFA) <> '') THEN
        
        /* Obtener precios actuales */
        CALL PRC_FNC_GET_PRECIO_ARTICULO_FECHA(
            pCODIGO_ARTICULO, 
            CURRENT_DATE, 
            ppPRECIOSALIDA_TARIFA, 
            ppPRECIOFINAL_TARIFA,
            ppPORCEN_DTO_TARIFA,
            ppPRECIO_DTO_TARIFA
        );

        IF (ppPRECIOFINAL_TARIFA IS NOT NULL) THEN
            
            UPDATE fza_articulos_tarifas
            SET 
                PRECIO_SALIDA_ARTTAR = pPRECIOSALIDA_TARIFA,
                PRECIO_FINAL_ARTTAR  = pPRECIOFINAL_TARIFA,
                PRECIO_DTO_ARTTAR   = pPRECIO_DTO_TARIFA,
                PORCENTAJE_DTO_ARTTAR   = pPORCEN_DTO_TARIFA,
                USUARIO_MODIF        = pUSUARIO,
                INSTANTE_MODIF       = CURRENT_TIMESTAMP             
            WHERE CODIGO_ART_ARTTAR = pCODIGO_ARTICULO
              AND CODIGO_TAR_ARTTAR = pCODIGO_TARIFA;
              
        ELSE
            
            INSERT INTO fza_articulos_tarifas ( 
                CODIGO_ART_ARTTAR,
                CODIGO_TAR_ARTTAR,
                PRECIO_SALIDA_ARTTAR,
                PRECIO_FINAL_ARTTAR,
                PRECIO_DTO_ARTTAR,
                PORCENTAJE_DTO_ARTTAR,
                FECHA_DESDE_ARTTAR,
                USUARIO_MODIF,
                INSTANTE_MODIF,
                USUARIO_ALTA,
                INSTANTE_ALTA                     
            ) VALUES (
                pCODIGO_ARTICULO,
                pCODIGO_TARIFA,
                pPRECIOSALIDA_TARIFA,
                pPRECIOFINAL_TARIFA,
                pPRECIO_DTO_TARIFA,
                pPORCEN_DTO_TARIFA,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                CURRENT_TIMESTAMP              
            );
            
        END IF;
        
    END IF;        
    
    COMMIT;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_ACTUALIZAR_TEST
DROP PROCEDURE IF EXISTS `PRC_CREAR_ACTUALIZAR_TEST`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_ACTUALIZAR_TEST`()
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FNC_GET_PRECIO_ARTICULO_FECHA('PAÑITOS', CURRENT_DATE, @PRECIOFINAL, @PRECIO_INICIAL, @PORCEN_DTO, @PRECIO_DTO);
  /* SELECT @PRECIOFINAL, @PRECIO_INICIAL, @PORCEN_DTO, @PRECIO_DTO; */
			IF (@PRECIOFINAL IS NULL) THEN
			  SELECT 'HOLA';
		 ELSE
		   SELECT 'NO HAY';
		 END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_FACTURA_ABONO
DROP PROCEDURE IF EXISTS `PRC_CREAR_FACTURA_ABONO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_FACTURA_ABONO`(
    IN `pidseriefactura`      varchar(200),
    IN `pidnumfactura`        varchar(200),
    IN `pidseriefacturaabono` varchar(200),
    IN `pidcodigo_empresa`    varchar(200),
    IN `pfechafacturaabono`   date,
    OUT `pidnumfacturaabono`  varchar(200),
    IN `pUSUARIO`             varchar(100)
)
SQL SECURITY INVOKER
BEGIN   
    DECLARE contadorped varchar(200);
    DECLARE pFecha date;

    /* Manejo de errores para asegurar la consistencia */    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN        
        ROLLBACK;
        RESIGNAL;
    END kk;

    START TRANSACTION;
    
    /* Pasamos contadorped directamente sin usar @cont */
    CALL PRC_GET_NEXT_CONT_FACT_SERIE(pidseriefacturaabono, 'FC', pidcodigo_empresa, pUSUARIO, contadorped);   
    
    /* Asignación limpia sin DATE_FORMAT innecesario */
    SET pFecha = pfechafacturaabono;
    SET pidnumfacturaabono = contadorped;

    INSERT INTO fza_facturas (
        `NUMERO_FAC`, `SERIE_FAC`, `FECHA_FAC`, `CODIGO_EMP_FAC`,
        `RAZON_SOCIAL_EMPRESA_FAC`, `NIF_EMPRESA_FAC`, `MOVIL_EMPRESA_FAC`, `EMAIL_EMPRESA_FAC`,
        `DIRECCION1_EMPRESA_FAC`, `DIRECCION2_EMPRESA_FAC`, `POBLACION_EMPRESA_FAC`, `PROVINCIA_EMPRESA_FAC`,
        `NOMBRE_PAI_EMPRESA_FAC`, `CODIGO_PAI_EMPRESA_FAC`, `CODIGO_POSTAL_EMPRESA_FAC`, `ESRETENCIONES_EMPRESA_FAC`,
        `GRUPO_ZONA_IVA_EMPRESA_FAC`, `ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC`, `CODIGO_CLI_FAC`, `RAZON_SOCIAL_CLIENTE_FAC`,
        `NIF_CLIENTE_FAC`, `MOVIL_CLIENTE_FAC`, `EMAIL_CLIENTE_FAC`, `DIRECCION1_CLIENTE_FAC`,
        `DIRECCION2_CLIENTE_FAC`, `POBLACION_CLIENTE_FAC`, `PROVINCIA_CLIENTE_FAC`, `CODIGO_POSTAL_CLIENTE_FAC`,
        `NOMBRE_PAI_CLIENTE_FAC`, `CODIGO_PAI_CLIENTE_FAC`, `ESIVA_RECARGO_CLIENTE_FAC`, `ESIVA_EXENTO_CLIENTE_FAC`,
        `ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC`, `ESRETENCIONES_CLIENTE_FAC`, `TARIFA_ARTICULO_CLIENTE_FAC`, `ESIMP_INCL_TARIFA_CLIENTE_FAC`,
        `ESINTRACOMUNITARIO_CLIENTE_FAC`, `ESIRPF_IMP_INCL_ZONA_IVA_FAC`, `ESAPLICA_RE_ZONA_IVA_FAC`, `ESIVAAGRICOLA_ZONA_IVA_FAC`,
        `PALABRA_REPORTS_ZONA_IVA_FAC`, `CODIGO_IVA_FAC`, `ESVENTA_ACTIVO_FIJO_FAC`, `PORCENTAJE_IVAN_FAC`,
        `TOTAL_IVAN_FAC`, `PORCENTAJE_REN_FAC`, `TOTAL_REN_FAC`, `TOTAL_BASEI_IVAN_FAC`,
        `PORCENTAJE_IVAR_FAC`, `TOTAL_IVAR_FAC`, `PORCENTAJE_RER_FAC`, `TOTAL_RER_FAC`,
        `TOTAL_BASEI_IVAR_FAC`, `PORCENTAJE_IVAS_FAC`, `TOTAL_IVAS_FAC`, `PORCENTAJE_RES_FAC`,
        `TOTAL_RES_FAC`, `TOTAL_BASEI_IVAS_FAC`, `PORCENTAJE_IVAE_FAC`, `TOTAL_IVAE_FAC`,
        `PORCENTAJE_REE_FAC`, `TOTAL_REE_FAC`, `TOTAL_BASEI_IVAE_FAC`, `TOTAL_BASES_FAC`,
        `TOTAL_IMPUESTOS_FAC`, `FORMA_PAGO_FAC`, `PORCENTAJE_RETENCION_FAC`, `TOTAL_RETENCION_FAC`,
        `TOTAL_LIQUIDO_FAC`, `NUMERO_FAC_ABONO_FAC`, `SERIE_FAC_ABONO_FAC`, `TEXTO_LEGAL_CLIENTE_FAC`,
        `TEXTO_LEGAL_EMPRESA_FAC`, `DOCUMENTO_FAC`, `COMENTARIOS_FAC`, `CONTADOR_LINEAS_FAC`,
        `ESCREARARTICULOS_FAC`, `ESDESCRIPCIONES_AMP_FAC`, `ESFECHADEENTREGA_FAC`, 
        `INSTANTE_MODIF`, `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`
    )                                 
    SELECT 
        contadorped,                 /* SIN comillas */
        pidseriefacturaabono,        /* SIN comillas */
        pFecha,                      /* SIN comillas (y sin la arroba) */
        `CODIGO_EMP_FAC`, `RAZON_SOCIAL_EMPRESA_FAC`, `NIF_EMPRESA_FAC`, `MOVIL_EMPRESA_FAC`, `EMAIL_EMPRESA_FAC`,
        `DIRECCION1_EMPRESA_FAC`, `DIRECCION2_EMPRESA_FAC`, `POBLACION_EMPRESA_FAC`, `PROVINCIA_EMPRESA_FAC`,
        `NOMBRE_PAI_EMPRESA_FAC`, `CODIGO_PAI_EMPRESA_FAC`, `CODIGO_POSTAL_EMPRESA_FAC`, `ESRETENCIONES_EMPRESA_FAC`,
        `GRUPO_ZONA_IVA_EMPRESA_FAC`, `ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC`, `CODIGO_CLI_FAC`, `RAZON_SOCIAL_CLIENTE_FAC`,
        `NIF_CLIENTE_FAC`, `MOVIL_CLIENTE_FAC`, `EMAIL_CLIENTE_FAC`, `DIRECCION1_CLIENTE_FAC`,
        `DIRECCION2_CLIENTE_FAC`, `POBLACION_CLIENTE_FAC`, `PROVINCIA_CLIENTE_FAC`, `CODIGO_POSTAL_CLIENTE_FAC`,
        `NOMBRE_PAI_CLIENTE_FAC`, `CODIGO_PAI_CLIENTE_FAC`, `ESIVA_RECARGO_CLIENTE_FAC`, `ESIVA_EXENTO_CLIENTE_FAC`,
        `ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC`, `ESRETENCIONES_CLIENTE_FAC`, `TARIFA_ARTICULO_CLIENTE_FAC`, `ESIMP_INCL_TARIFA_CLIENTE_FAC`,
        `ESINTRACOMUNITARIO_CLIENTE_FAC`, `ESIRPF_IMP_INCL_ZONA_IVA_FAC`, `ESAPLICA_RE_ZONA_IVA_FAC`, `ESIVAAGRICOLA_ZONA_IVA_FAC`,
        `PALABRA_REPORTS_ZONA_IVA_FAC`, `CODIGO_IVA_FAC`, `ESVENTA_ACTIVO_FIJO_FAC`, `PORCENTAJE_IVAN_FAC`,
        `TOTAL_IVAN_FAC`, `PORCENTAJE_REN_FAC`, `TOTAL_REN_FAC`, `TOTAL_BASEI_IVAN_FAC`,
        `PORCENTAJE_IVAR_FAC`, `TOTAL_IVAR_FAC`, `PORCENTAJE_RER_FAC`, `TOTAL_RER_FAC`,
        `TOTAL_BASEI_IVAR_FAC`, `PORCENTAJE_IVAS_FAC`, `TOTAL_IVAS_FAC`, `PORCENTAJE_RES_FAC`,
        `TOTAL_RES_FAC`, `TOTAL_BASEI_IVAS_FAC`, `PORCENTAJE_IVAE_FAC`, `TOTAL_IVAE_FAC`,
        `PORCENTAJE_REE_FAC`, `TOTAL_REE_FAC`, `TOTAL_BASEI_IVAE_FAC`, `TOTAL_BASES_FAC`,
        `TOTAL_IMPUESTOS_FAC`, `FORMA_PAGO_FAC`, `PORCENTAJE_RETENCION_FAC`, `TOTAL_RETENCION_FAC`,
        `TOTAL_LIQUIDO_FAC`, `NUMERO_FAC_ABONO_FAC`, `SERIE_FAC_ABONO_FAC`, `TEXTO_LEGAL_CLIENTE_FAC`,
        `TEXTO_LEGAL_EMPRESA_FAC`, `DOCUMENTO_FAC`, `COMENTARIOS_FAC`, `CONTADOR_LINEAS_FAC`,
        `ESCREARARTICULOS_FAC`, `ESDESCRIPCIONES_AMP_FAC`, `ESFECHADEENTREGA_FAC`, 
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 
        pUSUARIO,                    /* SIN comillas */
        pUSUARIO                     /* SIN comillas */
    FROM `fza_facturas` 
    WHERE `NUMERO_FAC`   = pidnumfactura     /* SIN comillas */
      AND `SERIE_FAC` = pidseriefactura;  /* SIN comillas */

    INSERT INTO `fza_facturas_lineas` (
        `NUMERO_FAC_FACLIN`, `SERIE_FAC_FACLIN`, `LINEA_FACLIN`, `CODIGO_ART_FACLIN`,
        `TIPO_CANTIDAD_ARTICULO_FACLIN`, `ESIMP_INCL_TARIFA_FACLIN`, `TIPO_IVA_ARTICULO_FACLIN`,
        `DESCRIPCION_ARTICULO_FACLIN`, `CANTIDAD_FACLIN`, `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`,
        `PORCENTAJE_IVA_FACLIN`, `PRECIO_VENTA_CIVA_ARTICULO_FACLIN`, `TOTAL_FACLIN`,
        `INSTANTE_MODIF`, `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`
    ) 
    SELECT 
        contadorped,                 /* SIN comillas */
        pidseriefacturaabono,        /* SIN comillas */
        `LINEA_FACLIN`, `CODIGO_ART_FACLIN`, `TIPO_CANTIDAD_ARTICULO_FACLIN`,
        `ESIMP_INCL_TARIFA_FACLIN`, `TIPO_IVA_ARTICULO_FACLIN`, `DESCRIPCION_ARTICULO_FACLIN`,
        (`CANTIDAD_FACLIN` * -1),  /* ¡Perfecto esto para el abono! */
        `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`, `PORCENTAJE_IVA_FACLIN`, `PRECIO_VENTA_CIVA_ARTICULO_FACLIN`,
        (`TOTAL_FACLIN` * -1),     /* ¡Perfecto esto para el abono! */
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 
        pUSUARIO,                    /* SIN comillas */
        pUSUARIO                     /* SIN comillas */
    FROM `fza_facturas_lineas` 
    WHERE `SERIE_FAC_FACLIN` = pidseriefactura   /* SIN comillas */
      AND `NUMERO_FAC_FACLIN`   = pidnumfactura;    /* SIN comillas */

    CALL `PRC_CALCULAR_FACTURA_NETOS`(pidseriefacturaabono, contadorped);
   
    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_FACTURA_DUPLICADA
DROP PROCEDURE IF EXISTS `PRC_CREAR_FACTURA_DUPLICADA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_FACTURA_DUPLICADA`(
    IN pidseriefactura      varchar(200),
    IN pidnumfactura        varchar(200),
    IN pidseriefacturaabono varchar(200),
    IN pidcodigo_empresa    varchar(200),
    IN pfechafacturaabono   date,
    IN pUSUARIO             varchar(100),
    OUT pidnumfacturaabono  varchar(200)
)
SQL SECURITY INVOKER
BEGIN   
    DECLARE contadorped varchar(200);
    DECLARE pfecha date;

    /* Manejo de errores para asegurar la consistencia */    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN        
        ROLLBACK;
        RESIGNAL;
    END kk;

    START TRANSACTION;
    
    CALL PRC_GET_NEXT_CONT_FACT_SERIE(pidseriefacturaabono, 
                                      'FC', 
                                      pidcodigo_empresa,
                                      pUSUARIO,
                                      contadorped);
                                      
    SET pFecha = pfechafacturaabono;
    SET pidnumfacturaabono = contadorped;

    INSERT INTO fza_facturas (
        `NUMERO_FAC`, `SERIE_FAC`, `FECHA_FAC`, `CODIGO_EMP_FAC`,
        `RAZON_SOCIAL_EMPRESA_FAC`, `NIF_EMPRESA_FAC`, `MOVIL_EMPRESA_FAC`, `EMAIL_EMPRESA_FAC`,
        `DIRECCION1_EMPRESA_FAC`, `DIRECCION2_EMPRESA_FAC`, `POBLACION_EMPRESA_FAC`, `PROVINCIA_EMPRESA_FAC`,
        `NOMBRE_PAI_EMPRESA_FAC`, `CODIGO_PAI_EMPRESA_FAC`, `CODIGO_POSTAL_EMPRESA_FAC`, `ESRETENCIONES_EMPRESA_FAC`,
        `GRUPO_ZONA_IVA_EMPRESA_FAC`, `ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC`, `CODIGO_CLI_FAC`, `RAZON_SOCIAL_CLIENTE_FAC`,
        `NIF_CLIENTE_FAC`, `MOVIL_CLIENTE_FAC`, `EMAIL_CLIENTE_FAC`, `DIRECCION1_CLIENTE_FAC`,
        `DIRECCION2_CLIENTE_FAC`, `POBLACION_CLIENTE_FAC`, `PROVINCIA_CLIENTE_FAC`, `CODIGO_POSTAL_CLIENTE_FAC`,
        `NOMBRE_PAI_CLIENTE_FAC`, `CODIGO_PAI_CLIENTE_FAC`, `ESIVA_RECARGO_CLIENTE_FAC`, `ESIVA_EXENTO_CLIENTE_FAC`,
        `ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC`, `ESRETENCIONES_CLIENTE_FAC`, `TARIFA_ARTICULO_CLIENTE_FAC`, `ESIMP_INCL_TARIFA_CLIENTE_FAC`,
        `ESINTRACOMUNITARIO_CLIENTE_FAC`, `ESIRPF_IMP_INCL_ZONA_IVA_FAC`, `ESAPLICA_RE_ZONA_IVA_FAC`, `ESIVAAGRICOLA_ZONA_IVA_FAC`,
        `PALABRA_REPORTS_ZONA_IVA_FAC`, `CODIGO_IVA_FAC`, `ESVENTA_ACTIVO_FIJO_FAC`, `PORCENTAJE_IVAN_FAC`,
        `TOTAL_IVAN_FAC`, `PORCENTAJE_REN_FAC`, `TOTAL_REN_FAC`, `TOTAL_BASEI_IVAN_FAC`,
        `PORCENTAJE_IVAR_FAC`, `TOTAL_IVAR_FAC`, `PORCENTAJE_RER_FAC`, `TOTAL_RER_FAC`,
        `TOTAL_BASEI_IVAR_FAC`, `PORCENTAJE_IVAS_FAC`, `TOTAL_IVAS_FAC`, `PORCENTAJE_RES_FAC`,
        `TOTAL_RES_FAC`, `TOTAL_BASEI_IVAS_FAC`, `PORCENTAJE_IVAE_FAC`, `TOTAL_IVAE_FAC`,
        `PORCENTAJE_REE_FAC`, `TOTAL_REE_FAC`, `TOTAL_BASEI_IVAE_FAC`, `TOTAL_BASES_FAC`,
        `TOTAL_IMPUESTOS_FAC`, `FORMA_PAGO_FAC`, `PORCENTAJE_RETENCION_FAC`, `TOTAL_RETENCION_FAC`,
        `TOTAL_LIQUIDO_FAC`, `NUMERO_FAC_ABONO_FAC`, `SERIE_FAC_ABONO_FAC`, `TEXTO_LEGAL_CLIENTE_FAC`,
        `TEXTO_LEGAL_EMPRESA_FAC`, `DOCUMENTO_FAC`, `COMENTARIOS_FAC`, `CONTADOR_LINEAS_FAC`,
        `ESCREARARTICULOS_FAC`, `ESDESCRIPCIONES_AMP_FAC`, `ESFECHADEENTREGA_FAC`, `INSTANTE_MODIF`,
        `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`
    )
    SELECT 
        contadorped,                  
        pidseriefacturaabono,         
        pFecha,                       
        `CODIGO_EMP_FAC`, `RAZON_SOCIAL_EMPRESA_FAC`, `NIF_EMPRESA_FAC`, `MOVIL_EMPRESA_FAC`, `EMAIL_EMPRESA_FAC`,
        `DIRECCION1_EMPRESA_FAC`, `DIRECCION2_EMPRESA_FAC`, `POBLACION_EMPRESA_FAC`, `PROVINCIA_EMPRESA_FAC`,
        `NOMBRE_PAI_EMPRESA_FAC`, `CODIGO_PAI_EMPRESA_FAC`, `CODIGO_POSTAL_EMPRESA_FAC`, `ESRETENCIONES_EMPRESA_FAC`,
        `GRUPO_ZONA_IVA_EMPRESA_FAC`, `ESREGIMENESPECIALAGRICOLA_EMPRESA_FAC`, `CODIGO_CLI_FAC`, `RAZON_SOCIAL_CLIENTE_FAC`,
        `NIF_CLIENTE_FAC`, `MOVIL_CLIENTE_FAC`, `EMAIL_CLIENTE_FAC`, `DIRECCION1_CLIENTE_FAC`,
        `DIRECCION2_CLIENTE_FAC`, `POBLACION_CLIENTE_FAC`, `PROVINCIA_CLIENTE_FAC`, `CODIGO_POSTAL_CLIENTE_FAC`,
        `NOMBRE_PAI_CLIENTE_FAC`, `CODIGO_PAI_CLIENTE_FAC`, `ESIVA_RECARGO_CLIENTE_FAC`, `ESIVA_EXENTO_CLIENTE_FAC`,
        `ESREGIMENESPECIALAGRICOLA_CLIENTE_FAC`, `ESRETENCIONES_CLIENTE_FAC`, `TARIFA_ARTICULO_CLIENTE_FAC`, `ESIMP_INCL_TARIFA_CLIENTE_FAC`,
        `ESINTRACOMUNITARIO_CLIENTE_FAC`, `ESIRPF_IMP_INCL_ZONA_IVA_FAC`, `ESAPLICA_RE_ZONA_IVA_FAC`, `ESIVAAGRICOLA_ZONA_IVA_FAC`,
        `PALABRA_REPORTS_ZONA_IVA_FAC`, `CODIGO_IVA_FAC`, `ESVENTA_ACTIVO_FIJO_FAC`, `PORCENTAJE_IVAN_FAC`,
        `TOTAL_IVAN_FAC`, `PORCENTAJE_REN_FAC`, `TOTAL_REN_FAC`, `TOTAL_BASEI_IVAN_FAC`,
        `PORCENTAJE_IVAR_FAC`, `TOTAL_IVAR_FAC`, `PORCENTAJE_RER_FAC`, `TOTAL_RER_FAC`,
        `TOTAL_BASEI_IVAR_FAC`, `PORCENTAJE_IVAS_FAC`, `TOTAL_IVAS_FAC`, `PORCENTAJE_RES_FAC`,
        `TOTAL_RES_FAC`, `TOTAL_BASEI_IVAS_FAC`, `PORCENTAJE_IVAE_FAC`, `TOTAL_IVAE_FAC`,
        `PORCENTAJE_REE_FAC`, `TOTAL_REE_FAC`, `TOTAL_BASEI_IVAE_FAC`, `TOTAL_BASES_FAC`,
        `TOTAL_IMPUESTOS_FAC`, `FORMA_PAGO_FAC`, `PORCENTAJE_RETENCION_FAC`, `TOTAL_RETENCION_FAC`,
        `TOTAL_LIQUIDO_FAC`, `NUMERO_FAC_ABONO_FAC`, `SERIE_FAC_ABONO_FAC`, `TEXTO_LEGAL_CLIENTE_FAC`,
        `TEXTO_LEGAL_EMPRESA_FAC`, `DOCUMENTO_FAC`, `COMENTARIOS_FAC`, `CONTADOR_LINEAS_FAC`,
        `ESCREARARTICULOS_FAC`, `ESDESCRIPCIONES_AMP_FAC`, `ESFECHADEENTREGA_FAC`, 
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 
        pUSUARIO,                     
        pUSUARIO                      
    FROM `fza_facturas` 
    WHERE `NUMERO_FAC` = pidnumfactura     
      AND `SERIE_FAC` = pidseriefactura;  

    INSERT INTO fza_facturas_lineas (
        `NUMERO_FAC_FACLIN`, `SERIE_FAC_FACLIN`, `LINEA_FACLIN`, `CODIGO_ART_FACLIN`,
        `TIPO_CANTIDAD_ARTICULO_FACLIN`, `ESIMP_INCL_TARIFA_FACLIN`, `TIPO_IVA_ARTICULO_FACLIN`,
        `DESCRIPCION_ARTICULO_FACLIN`, `CANTIDAD_FACLIN`, `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`,
        `PORCENTAJE_IVA_FACLIN`, `PRECIO_VENTA_CIVA_ARTICULO_FACLIN`, `TOTAL_FACLIN`,
        `INSTANTE_MODIF`, `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`
    )
    SELECT 
        contadorped,                  
        pidseriefacturaabono,         
        `LINEA_FACLIN`, `CODIGO_ART_FACLIN`,
        `TIPO_CANTIDAD_ARTICULO_FACLIN`, `ESIMP_INCL_TARIFA_FACLIN`, `TIPO_IVA_ARTICULO_FACLIN`,
        `DESCRIPCION_ARTICULO_FACLIN`, `CANTIDAD_FACLIN`, `PRECIO_VENTA_SIVA_ARTICULO_FACLIN`,
        `PORCENTAJE_IVA_FACLIN`, `PRECIO_VENTA_CIVA_ARTICULO_FACLIN`, `TOTAL_FACLIN`,
        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 
        pUSUARIO,                     
        pUSUARIO                      
    FROM `fza_facturas_lineas`                            
    WHERE `SERIE_FAC_FACLIN` = pidseriefactura   
      AND `NUMERO_FAC_FACLIN` = pidnumfactura;      
      
    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_METADATOS
DROP PROCEDURE IF EXISTS `PRC_CREAR_METADATOS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_METADATOS`(IN `pDATABASENAME` varchar(100))
SQL SECURITY INVOKER
BEGIN

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
START TRANSACTION;
  DROP TABLE IF EXISTS `fza_metadatos`;
  CREATE TABLE `fza_metadatos`  (
    `CODIGO_META_META` int(20) NOT NULL AUTO_INCREMENT,
    `NOMBRE_META_META` varchar(100) CHARACTER SET utf8mb4 
                               COLLATE utf8mb4_spanish_ci NOT NULL,
    `PARENT_META` varchar(20) CHARACTER SET utf8mb4 
                               COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (`CODIGO_META_META`) USING BTREE
  ) ENGINE = InnoDB AUTO_INCREMENT = 4 CHARACTER SET = utf8mb4 
             COLLATE = utf8mb4_spanish_ci ROW_FORMAT = Dynamic;
  INSERT INTO `fza_metadatos` (`PARENT_META`, `NOMBRE_META_META`)
  SELECT '1' AS `PARENT_META`,
         `table_name` as `NOMBRE_META_META`
    FROM `information_schema`.`TABLES` 
   WHERE `table_schema` = `pDATABASENAME`  
     AND `table_type` = 'BASE TABLE';
  INSERT INTO `fza_metadatos` (`PARENT_META`, `NOMBRE_META_META`)    
  SELECT '2' AS `PARENT_META`,
         `table_name` as `NOMBRE_META_META`
    FROM `information_schema`.`TABLES` 
   WHERE `table_schema` = `pDATABASENAME`
     AND `table_type` = 'VIEW';
   INSERT INTO `fza_metadatos` (`PARENT_META`, `NOMBRE_META_META`) 
   SELECT '3' AS `PARENT_META`,
          `SPECIFIC_NAME` AS `NOMBRE_META_META`
     FROM `information_schema`.`ROUTINES` 
    WHERE `ROUTINE_SCHEMA` = pDATABASENAME  
      AND `ROUTINE_TYPE` = 'PROCEDURE';     
   
   INSERT INTO `fza_metadatos` (`CODIGO_META_META`, 
                                `PARENT_META`, 
                                `NOMBRE_META_META`) 
                        VALUES (1, '-1','Tablas');  
   INSERT INTO `fza_metadatos` (`CODIGO_META_META`, 
                                `PARENT_META`, 
                                `NOMBRE_META_META`) 
                        VALUES (2, '-1','Vistas');
   INSERT INTO `fza_metadatos` (`CODIGO_META_META`, 
                                `PARENT_META`, 
                                `NOMBRE_META_META`) 
                        VALUES (3, '-1','Procedimientos');
COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_RECIBOS_FACTURA
DROP PROCEDURE IF EXISTS `PRC_CREAR_RECIBOS_FACTURA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_RECIBOS_FACTURA`(
    IN pSERIE_FACTURA varchar(12),
    IN pNRO_FACTURA   varchar(12),
    IN pUSUARIO       varchar(100)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE pCODIGO_FORMAPAGO VARCHAR(20);
    DECLARE pFORMA_PAGO_FACTURA VARCHAR(100);
    DECLARE pN_PLAZOS int(10); 
    DECLARE I int(10);
    DECLARE pDIAS_ENTRE_PLAZOS int(10);
    DECLARE pPORCEN_ANTICIPO decimal(5,2);
    DECLARE pCODIGO_CLIENTE  varchar(20);
    DECLARE pIBAN varchar(34);
    DECLARE pRAZONSOCIAL_CLIENTE varchar(200);
    DECLARE pDIRECCION1_CLIENTE  varchar(200);
    DECLARE pPOBLACION_CLIENTE  varchar(200);
    DECLARE pPOBLACION_EMPRESA varchar(200);
    DECLARE pPROVINCIA_CLIENTE  varchar(200);
    DECLARE pCPOSTAL_CLIENTE  varchar(15);
    DECLARE pIMPORTE_LETRA  varchar(150);
    DECLARE pTOTAL_LIQUIDO_FACTURA decimal(18,6);
    DECLARE pIMPORTE_RECIBO decimal(18,6);
    DECLARE pIMPORTE_RESTO decimal(18,6);
    DECLARE pIMPORTE_ANTICIPO decimal(18,6);
    DECLARE pFECHA_VENCIMIENTO date;
    DECLARE pFECHA_FACTURA date;
    DECLARE finished INTEGER DEFAULT 0;

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;

    START TRANSACTION;

    /* Limpiamos los recibos existentes de esta factura */
    DELETE FROM fza_recibos 
    WHERE NUMERO_FAC_REC = pNRO_FACTURA
      AND SERIE_FAC_REC = pSERIE_FACTURA;   

    /* Obtenemos los datos de la factura */
    SELECT FORMA_PAGO_FAC, 
           CODIGO_CLI_FAC,
           TOTAL_LIQUIDO_FAC,
           RAZON_SOCIAL_CLIENTE_FAC,
           DIRECCION1_CLIENTE_FAC,
           POBLACION_CLIENTE_FAC,
           PROVINCIA_CLIENTE_FAC,
           CODIGO_POSTAL_CLIENTE_FAC,
           FECHA_FAC,
           POBLACION_EMPRESA_FAC
    INTO pFORMA_PAGO_FACTURA,
         pCODIGO_CLIENTE,
         pTOTAL_LIQUIDO_FACTURA,
         pRAZONSOCIAL_CLIENTE,
         pDIRECCION1_CLIENTE,
         pPOBLACION_CLIENTE,
         pPROVINCIA_CLIENTE,
         pCPOSTAL_CLIENTE,
         pFECHA_FACTURA,
         pPOBLACION_EMPRESA
    FROM fza_facturas
    WHERE SERIE_FAC = pSERIE_FACTURA
      AND NUMERO_FAC = pNRO_FACTURA;
         
    /* Obtenemos el IBAN del cliente */
    SELECT IBAN_CLI 
    INTO pIBAN
    FROM fza_clientes
    WHERE CODIGO_CLI_CLI = pCODIGO_CLIENTE;
         
    /* Comprobamos que existe la forma de pago */
    IF( EXISTS( SELECT *
                FROM fza_formas_pago
                WHERE CODIGO_FP_FP = pFORMA_PAGO_FACTURA) ) THEN
        
        /* Obtenemos los detalles de la forma de pago */
        SELECT CODIGO_FP_FP, 
               N_PLAZOS_FORMA_PAGO_FP, 
               N_DIAS_ENTRE_PLAZOS_FORMA_PAGO_FP, 
               PORCENTAJE_ANTICIPO_FORMA_PAGO_FP 
        INTO pCODIGO_FORMAPAGO,
             pN_PLAZOS, 
             pDIAS_ENTRE_PLAZOS,  
             pPORCEN_ANTICIPO
        FROM fza_formas_pago
        WHERE CODIGO_FP_FP = pFORMA_PAGO_FACTURA;
            
        /* Si es anticipo del 100% (un solo recibo al contado) */
        IF (pPORCEN_ANTICIPO = 100) THEN
        
            CALL PRC_GET_NUMEROS_A_LETRAS(pTOTAL_LIQUIDO_FACTURA, pIMPORTE_LETRA);
            
            INSERT INTO fza_recibos (
                NUMERO_FAC_REC,
                SERIE_FAC_REC,
                NUMERO_PLAZO_REC,
                FORMA_PAGO_ORIGEN_RECIBO_REC,
                FORMA_PAGO_DESCRIPCION_ORIGEN_RECIBO_REC,                               
                EUROS_RECIBO_REC,
                ESTADO_RECIBO_REC,
                FECHA_EXPEDICION_RECIBO_REC,
                FECHA_VENCIMIENTO_RECIBO_REC,
                IBAN_CLI_REC,
                FECHA_PAGO_RECIBO_REC,
                LOCALIDAD_EXPEDICION_RECIBO_REC,
                CODIGO_CLI_REC,
                RAZON_SOCIAL_CLI_REC,
                DIRECCION1_CLIENTE_RECIBO_REC,
                POBLACION_CLI_REC,
                PROVINCIA_CLI_REC,
                CODIGO_POSTAL_CLI_REC,
                IMPORTE_LETRA_RECIBO_REC,
                INSTANTE_ALTA,
                INSTANTE_MODIF,
                USUARIO_ALTA,
                USUARIO_MODIF    
            ) VALUES ( 
                pNRO_FACTURA,
                pSERIE_FACTURA,
                1,
                pCODIGO_FORMAPAGO,
                pFORMA_PAGO_FACTURA,
                pTOTAL_LIQUIDO_FACTURA,
                'Pagado',
                pFECHA_FACTURA,
                pFECHA_FACTURA,
                pIBAN,
                pFECHA_FACTURA,
                pPOBLACION_EMPRESA,
                pCODIGO_CLIENTE,
                pRAZONSOCIAL_CLIENTE,
                pDIRECCION1_CLIENTE,
                pPOBLACION_CLIENTE,
                pPROVINCIA_CLIENTE,
                pCPOSTAL_CLIENTE,
                pIMPORTE_LETRA,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP,
                pUSUARIO,
                pUSUARIO
            );
            
        ELSE 
            /* Si va por plazos */
            IF (pN_PLAZOS >= 1) THEN
                SET I = 1;
                
                WHILE (I <= pN_PLAZOS) DO
                
                    IF (I = 1) THEN 
                        SET pFECHA_VENCIMIENTO = ADDDATE(pFECHA_FACTURA, INTERVAL pDIAS_ENTRE_PLAZOS DAY);
                        SET pIMPORTE_ANTICIPO = pTOTAL_LIQUIDO_FACTURA * (pPORCEN_ANTICIPO / 100);
                        SET pIMPORTE_RESTO = (pTOTAL_LIQUIDO_FACTURA - pIMPORTE_ANTICIPO);
                    END IF;                                  
                    
                    IF ((I = 1) AND (pPORCEN_ANTICIPO > 0)) THEN
                        SET pIMPORTE_RECIBO = pIMPORTE_ANTICIPO;
                    ELSE
                        IF pN_PLAZOS > 1 THEN 
                            SET pIMPORTE_RECIBO = pIMPORTE_RESTO / (pN_PLAZOS);
                        ELSE
                            SET pIMPORTE_RECIBO = pIMPORTE_RESTO;
                        END IF;
                    END IF;
                    
                    CALL PRC_GET_NUMEROS_A_LETRAS(pIMPORTE_RECIBO, pIMPORTE_LETRA);   
                    
                    IF (I <> 1) THEN
                        SET pFECHA_VENCIMIENTO = ADDDATE(pFECHA_VENCIMIENTO, INTERVAL pDIAS_ENTRE_PLAZOS DAY);
                    END IF;
                    
                    INSERT INTO fza_recibos (
                        NUMERO_FAC_REC,
                        SERIE_FAC_REC,
                        NUMERO_PLAZO_REC,
                        FORMA_PAGO_ORIGEN_RECIBO_REC,                                                 
                        FORMA_PAGO_DESCRIPCION_ORIGEN_RECIBO_REC,
                        EUROS_RECIBO_REC,
                        ESTADO_RECIBO_REC,
                        FECHA_EXPEDICION_RECIBO_REC,
                        FECHA_VENCIMIENTO_RECIBO_REC,
                        IBAN_CLI_REC,
                        FECHA_PAGO_RECIBO_REC,
                        LOCALIDAD_EXPEDICION_RECIBO_REC,
                        CODIGO_CLI_REC,
                        RAZON_SOCIAL_CLI_REC,
                        DIRECCION1_CLIENTE_RECIBO_REC,
                        POBLACION_CLI_REC,
                        PROVINCIA_CLI_REC,
                        CODIGO_POSTAL_CLI_REC,
                        IMPORTE_LETRA_RECIBO_REC,   
                        INSTANTE_ALTA,
                        INSTANTE_MODIF,
                        USUARIO_ALTA,
                        USUARIO_MODIF    
                    ) VALUES (  
                        pNRO_FACTURA,
                        pSERIE_FACTURA,
                        I,
                        pCODIGO_FORMAPAGO,                                      
                        pFORMA_PAGO_FACTURA,
                        pIMPORTE_RECIBO,
                        'Emitido',
                        pFECHA_FACTURA,
                        pFECHA_VENCIMIENTO,
                        pIBAN,
                        NULL,
                        pPOBLACION_EMPRESA,
                        pCODIGO_CLIENTE,
                        pRAZONSOCIAL_CLIENTE,
                        pDIRECCION1_CLIENTE,
                        pPOBLACION_CLIENTE,
                        pPROVINCIA_CLIENTE,
                        pCPOSTAL_CLIENTE,
                        pIMPORTE_LETRA,
                        CURRENT_TIMESTAMP,
                        CURRENT_TIMESTAMP,
                        pUSUARIO,
                        pUSUARIO
                    );
                    SET I = I + 1; 
                END WHILE;
            END IF;
        END IF;
    END IF;
    COMMIT;    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_CREAR_TRASPASO
DROP PROCEDURE IF EXISTS `PRC_CREAR_TRASPASO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_CREAR_TRASPASO`(IN pUsuario VARCHAR(50),
    IN pEmpresa VARCHAR(20),
    IN pAlmacenOrigen VARCHAR(10),
    IN pAlmacenDestino VARCHAR(10),
    IN pSku VARCHAR(50),
    IN pCantidad DECIMAL(19,6))
SQL SECURITY INVOKER
BEGIN
    DECLARE vSerie VARCHAR(20) DEFAULT 'TRAS';
    DECLARE vNroDoc VARCHAR(20);
    
    /* Generamos un número de documento único basado en la fecha y hora (simplificado) */
    SET vNroDoc = DATE_FORMAT(NOW(), '%Y%m%d%H%i%s');

    START TRANSACTION;

    /* 1. SALIDA DEL ORIGEN (Resta stock en Origen) */
    INSERT INTO `fza_movimientos_almacen` 
    (TIPO_DOC_MOV, SERIE_DOC_MOV, NUMERO_DOC_MOV, LINEA_MOV, CODIGO_EMP_MOV, 
     CODIGO_ALM_MOV, CODIGO_ALM_CONTRA_MOV, FECHA_MOV, 
     CODIGO_UNIDAD_MOV, TIPO_MOV, CANTIDAD_MOV, 
     DESCRIPCION_ARTICULO_MOV, USUARIO_ALTA, USUARIO_MODIF)
    VALUES 
    ('TR', vSerie, vNroDoc, '001', pEmpresa, 
     pAlmacenOrigen, pAlmacenDestino, NOW(), 
     pSku, 'S', pCantidad, 
     CONCAT('Traspaso a ', pAlmacenDestino), pUsuario, pUsuario);

    /* 2. ENTRADA EN DESTINO (Suma stock en Destino) */
    /* Referenciamos al movimiento anterior para trazabilidad */
    INSERT INTO `fza_movimientos_almacen` 
    (TIPO_DOC_MOV, SERIE_DOC_MOV, NUMERO_DOC_MOV, LINEA_MOV, CODIGO_EMP_MOV, 
     CODIGO_ALM_MOV, CODIGO_ALM_CONTRA_MOV, FECHA_MOV, 
     CODIGO_UNIDAD_MOV, TIPO_MOV, CANTIDAD_MOV, 
     DESCRIPCION_ARTICULO_MOV, USUARIO_ALTA, USUARIO_MODIF,
     TIPO_DOC_REF_MOV, SERIE_DOC_REF_MOV, NUMERO_DOC_REF_MOV, LINEA_REF_MOV)
    VALUES 
    ('TR', vSerie, vNroDoc, '002', pEmpresa, 
     pAlmacenDestino, pAlmacenOrigen, NOW(), 
     pSku, 'E', pCantidad, 
     CONCAT('Traspaso desde ', pAlmacenOrigen), pUsuario, pUsuario,
     'TR', vSerie, vNroDoc, '001');

    COMMIT;
    
    SELECT CONCAT('Traspaso realizado. Doc: ', vSerie, '-', vNroDoc) as MENSAJE;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_EFEC_CONCILIAR_PAGO
DROP PROCEDURE IF EXISTS `PRC_EFEC_CONCILIAR_PAGO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_EFEC_CONCILIAR_PAGO`(
    IN  p_SERIE      varchar(20),
    IN  p_NUMERO     varchar(20),
    IN  p_NUM_EFEC   int,
    IN  p_FECHA      date,
    IN  p_IMPORTE    decimal(18,6),
    IN  p_TIPO       varchar(50),
    IN  p_REFERENCIA varchar(100),
    IN  p_ENTIDAD    varchar(100),
    IN  p_USUARIO    varchar(100),
    OUT p_RESULTADO  int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_existe   int DEFAULT 0;
  DECLARE v_importe  decimal(18,6) DEFAULT 0;
  DECLARE v_pend     decimal(18,6) DEFAULT 0;
  DECLARE v_pago     decimal(18,6) DEFAULT 0;
  DECLARE v_resto    decimal(18,6) DEFAULT 0;
  DECLARE v_nuevo    int DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  START TRANSACTION;
  SELECT COUNT(*)
    INTO v_existe
    FROM fza_efectos_compra
   WHERE SERIE_FACC_EFEC  = p_SERIE
     AND NUMERO_FACC_EFEC = p_NUMERO
     AND NUMERO_EFEC      = p_NUM_EFEC
     AND COALESCE(ESTADO_EFEC, '') NOT IN
         ('PAGADO', 'ANULADO', 'DEVUELTO', 'CONCILIADO')
     AND COALESCE(IMPORTE_PENDIENTE_EFEC, IMPORTE_EFEC, 0) > 0;
  IF v_existe > 0 AND COALESCE(p_IMPORTE, 0) > 0 THEN
    SELECT COALESCE(IMPORTE_EFEC, 0),
           COALESCE(IMPORTE_PENDIENTE_EFEC, IMPORTE_EFEC, 0)
      INTO v_importe, v_pend
      FROM fza_efectos_compra
     WHERE SERIE_FACC_EFEC  = p_SERIE
       AND NUMERO_FACC_EFEC = p_NUMERO
       AND NUMERO_EFEC      = p_NUM_EFEC
       FOR UPDATE;
    SET v_pago = COALESCE(p_IMPORTE, 0);
    IF v_pago > v_pend THEN
      SET v_pago = v_pend;
    END IF;
    SET v_resto = v_pend - v_pago;
    IF v_resto <= 0.000001 THEN
      UPDATE fza_efectos_compra
         SET IMPORTE_PAGADO_EFEC    = v_importe,
             IMPORTE_PENDIENTE_EFEC = 0,
             FECHA_PAGO_EFEC        = COALESCE(p_FECHA, CURDATE()),
             TIPO_PAGO_EFEC         = NULLIF(p_TIPO, ''),
             REFERENCIA_PAGO_EFEC   = NULLIF(p_REFERENCIA, ''),
             ENTIDAD_PAGO_EFEC      = NULLIF(p_ENTIDAD, ''),
             ESCONCILIADO_EFEC      = 'S',
             ESTADO_EFEC            = 'PAGADO',
             INSTANTE_MODIF         = NOW(),
             USUARIO_MODIF          = p_USUARIO
       WHERE SERIE_FACC_EFEC  = p_SERIE
         AND NUMERO_FACC_EFEC = p_NUMERO
         AND NUMERO_EFEC      = p_NUM_EFEC;
      SET p_RESULTADO = 1;
    ELSE
      SELECT COALESCE(MAX(NUMERO_EFEC), 0) + 1
        INTO v_nuevo
        FROM fza_efectos_compra
       WHERE SERIE_FACC_EFEC  = p_SERIE
         AND NUMERO_FACC_EFEC = p_NUMERO;
      UPDATE fza_efectos_compra
         SET IMPORTE_EFEC           = v_pago,
             IMPORTE_PAGADO_EFEC    = v_pago,
             IMPORTE_PENDIENTE_EFEC = 0,
             FECHA_PAGO_EFEC        = COALESCE(p_FECHA, CURDATE()),
             TIPO_PAGO_EFEC         = NULLIF(p_TIPO, ''),
             REFERENCIA_PAGO_EFEC   = NULLIF(p_REFERENCIA, ''),
             ENTIDAD_PAGO_EFEC      = NULLIF(p_ENTIDAD, ''),
             ESCONCILIADO_EFEC      = 'S',
             ESTADO_EFEC            = 'PAGADO',
             INSTANTE_MODIF         = NOW(),
             USUARIO_MODIF          = p_USUARIO
       WHERE SERIE_FACC_EFEC  = p_SERIE
         AND NUMERO_FACC_EFEC = p_NUMERO
         AND NUMERO_EFEC      = p_NUM_EFEC;
      INSERT INTO fza_efectos_compra
        (SERIE_FACC_EFEC, NUMERO_FACC_EFEC, NUMERO_EFEC,
         CODIGO_EMP_EFEC, CODIGO_PRV_EFEC, RAZON_SOCIAL_PRV_EFEC,
         NIF_PRV_EFEC, CODIGO_TEFE_EFEC, ESTADO_EFEC,
         ORDEN_PLAZO_EFEC, FECHA_EMISION_EFEC, FECHA_VENCIMIENTO_EFEC,
         FECHA_PAGO_EFEC, TIPO_PAGO_EFEC, REFERENCIA_PAGO_EFEC,
         ENTIDAD_PAGO_EFEC, ESCONCILIADO_EFEC, IMPORTE_EFEC,
         IMPORTE_PAGADO_EFEC, IMPORTE_PENDIENTE_EFEC, SERIE_REMC_EFEC,
         NUMERO_REMC_EFEC, ENTIDAD_EFEC, OFICINA_EFEC,
         DIGITO_CONTROL_EFEC, CUENTA_EFEC, IBAN_EFEC,
         CODIGO_EMPBAN_EFEC, IBAN_EMP_EFEC, DOC_EXTERNO_EFEC,
         REFERENCIA_DOCUMENTO_EFEC, SERIE_FACC_CONCILIACION_EFEC,
         NUMERO_FACC_CONCILIACION_EFEC, NUMERO_EFEC_CONCILIACION_EFEC,
         OBSERVACIONES_EFEC, INSTANTE_ALTA, USUARIO_ALTA,
         INSTANTE_MODIF, USUARIO_MODIF)
      SELECT SERIE_FACC_EFEC, NUMERO_FACC_EFEC, v_nuevo,
             CODIGO_EMP_EFEC, CODIGO_PRV_EFEC, RAZON_SOCIAL_PRV_EFEC,
             NIF_PRV_EFEC, CODIGO_TEFE_EFEC,
             CASE
               WHEN COALESCE(SERIE_REMC_EFEC, '') <> '' THEN 'REMESADO'
               ELSE 'PENDIENTE'
             END,
             ORDEN_PLAZO_EFEC, FECHA_EMISION_EFEC,
             FECHA_VENCIMIENTO_EFEC, NULL, NULL, NULL, NULL, 'N',
             v_resto, 0, v_resto, SERIE_REMC_EFEC, NUMERO_REMC_EFEC,
             ENTIDAD_EFEC, OFICINA_EFEC, DIGITO_CONTROL_EFEC,
             CUENTA_EFEC, IBAN_EFEC, CODIGO_EMPBAN_EFEC, IBAN_EMP_EFEC,
             DOC_EXTERNO_EFEC, REFERENCIA_DOCUMENTO_EFEC,
             SERIE_FACC_CONCILIACION_EFEC,
             NUMERO_FACC_CONCILIACION_EFEC,
             NUMERO_EFEC_CONCILIACION_EFEC,
             OBSERVACIONES_EFEC, NOW(), p_USUARIO,
             NOW(), p_USUARIO
        FROM fza_efectos_compra
       WHERE SERIE_FACC_EFEC  = p_SERIE
         AND NUMERO_FACC_EFEC = p_NUMERO
         AND NUMERO_EFEC      = p_NUM_EFEC;
      SET p_RESULTADO = 2;
    END IF;
  END IF;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_EFEC_GENERAR_DESDE_FACTURA
DROP PROCEDURE IF EXISTS `PRC_EFEC_GENERAR_DESDE_FACTURA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_EFEC_GENERAR_DESDE_FACTURA`(
    IN  p_SERIE   varchar(20),
    IN  p_NUMERO  varchar(20),
    IN  p_USUARIO varchar(100),
    OUT p_RESULTADO int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_liquido  decimal(18,6) DEFAULT 0;
  DECLARE v_fp       varchar(200);
  DECLARE v_fecha    date;
  DECLARE v_emp      varchar(8);
  DECLARE v_prv      varchar(20);
  DECLARE v_razon    varchar(200);
  DECLARE v_nif      varchar(50);
  DECLARE v_docext   varchar(50);
  DECLARE v_ent      varchar(4);
  DECLARE v_ofi      varchar(4);
  DECLARE v_dc       varchar(2);
  DECLARE v_cta      varchar(10);
  DECLARE v_iban     varchar(34);
  DECLARE v_nplazos  int DEFAULT 1;
  DECLARE v_dias     int DEFAULT 0;
  DECLARE v_escontado varchar(1) DEFAULT 'N';
  DECLARE v_tefe     varchar(20);
  DECLARE v_bloqueados int DEFAULT 0;
  DECLARE v_i        int DEFAULT 1;
  DECLARE v_imp      decimal(18,6) DEFAULT 0;
  DECLARE v_acum     decimal(18,6) DEFAULT 0;
  DECLARE v_vto      date;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  /* ¿Hay efectos que no se pueden regenerar (pagados / remesados)? */
  SELECT COUNT(*)
    INTO v_bloqueados
    FROM fza_efectos_compra
   WHERE SERIE_FACC_EFEC  = p_SERIE
     AND NUMERO_FACC_EFEC = p_NUMERO
     AND (COALESCE(ESTADO_EFEC, '') IN ('PAGADO', 'REMESADO')
          OR COALESCE(IMPORTE_PAGADO_EFEC, 0) > 0
          OR COALESCE(ESTADO_EFEC, '') = 'CONCILIADO'
          OR COALESCE(ESCONCILIADO_EFEC, 'N') = 'S'
          OR SERIE_REMC_EFEC IS NOT NULL
          OR SERIE_FACC_CONCILIACION_EFEC IS NOT NULL);
  IF v_bloqueados = 0 THEN
    /* Datos de la factura. */
    SELECT COALESCE(TOTAL_LIQUIDO_FACC, 0), FORMA_PAGO_FACC,
           COALESCE(FECHA_FACC, CURDATE()), CODIGO_EMP_FACC,
           CODIGO_PRV_FACC, RAZON_SOCIAL_PRV_FACC, NIF_PRV_FACC,
           DOC_EXTERNO_FACC, ENTIDAD_FACC, OFICINA_FACC,
           DIGITO_CONTROL_FACC, CUENTA_FACC, IBAN_FACC
      INTO v_liquido, v_fp, v_fecha, v_emp, v_prv, v_razon, v_nif,
           v_docext, v_ent, v_ofi, v_dc, v_cta, v_iban
      FROM fza_facturas_compra
     WHERE SERIE_FACC = p_SERIE AND NUMERO_FACC = p_NUMERO;
    /* Parametros de la forma de pago (si existe). */
    SELECT COALESCE(N_PLAZOS_FORMA_PAGO_FP, 1),
           COALESCE(N_DIAS_ENTRE_PLAZOS_FORMA_PAGO_FP, 0),
           COALESCE(ESCONTADO_FORMA_PAGO_FP, 'N')
      INTO v_nplazos, v_dias, v_escontado
      FROM fza_formas_pago
     WHERE CODIGO_FP_FP = v_fp;
    IF v_nplazos IS NULL OR v_nplazos < 1 THEN
      SET v_nplazos = 1;
    END IF;
    /* Tipo de efecto por defecto segun contado/aplazado. */
    SET v_tefe = IF(v_escontado = 'S', 'CONTADO', 'RECIBO');
    /* Limpiar efectos previos (todos PENDIENTE en este punto). */
    START TRANSACTION;
    DELETE FROM fza_efectos_compra
     WHERE SERIE_FACC_EFEC  = p_SERIE
       AND NUMERO_FACC_EFEC = p_NUMERO;
    SET v_acum = 0;
    WHILE v_i <= v_nplazos DO
      IF v_i = v_nplazos THEN
        SET v_imp = v_liquido - v_acum;          /* ultimo: resto exacto */
      ELSE
        SET v_imp = ROUND(v_liquido / v_nplazos, 2);
        SET v_acum = v_acum + v_imp;
      END IF;
      SET v_vto = DATE_ADD(v_fecha, INTERVAL (v_i * v_dias) DAY);
      INSERT INTO fza_efectos_compra
        (SERIE_FACC_EFEC, NUMERO_FACC_EFEC, NUMERO_EFEC, CODIGO_EMP_EFEC,
         CODIGO_PRV_EFEC, RAZON_SOCIAL_PRV_EFEC, NIF_PRV_EFEC,
         CODIGO_TEFE_EFEC, ESTADO_EFEC, ORDEN_PLAZO_EFEC,
         FECHA_EMISION_EFEC, FECHA_VENCIMIENTO_EFEC, IMPORTE_EFEC,
         IMPORTE_PAGADO_EFEC, IMPORTE_PENDIENTE_EFEC, ENTIDAD_EFEC,
         OFICINA_EFEC, DIGITO_CONTROL_EFEC, CUENTA_EFEC, IBAN_EFEC,
         DOC_EXTERNO_EFEC, REFERENCIA_DOCUMENTO_EFEC, INSTANTE_ALTA,
         USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF)
      VALUES
        (p_SERIE, p_NUMERO, v_i, v_emp, v_prv, v_razon, v_nif,
         v_tefe, 'PENDIENTE', v_i, v_fecha, v_vto, v_imp,
         0, v_imp, v_ent, v_ofi, v_dc, v_cta, v_iban,
         v_docext, COALESCE(NULLIF(v_docext, ''),
         CONCAT(p_SERIE, '/', p_NUMERO)), NOW(), p_USUARIO, NOW(),
         p_USUARIO);
      SET v_i = v_i + 1;
    END WHILE;
    COMMIT;
    SET p_RESULTADO = v_nplazos;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_EFV_CONCILIAR_COBRO
DROP PROCEDURE IF EXISTS `PRC_EFV_CONCILIAR_COBRO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_EFV_CONCILIAR_COBRO`(
    IN p_SERIE varchar(20),
    IN p_NUMERO varchar(20),
    IN p_NUM_EFV int,
    IN p_FECHA date,
    IN p_IMPORTE decimal(18,6),
    IN p_TIPO varchar(50),
    IN p_REFERENCIA varchar(100),
    IN p_ENTIDAD varchar(100),
    IN p_USUARIO varchar(100),
    OUT p_RESULTADO int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_existe int DEFAULT 0;
  DECLARE v_importe decimal(18,6) DEFAULT 0;
  DECLARE v_pend decimal(18,6) DEFAULT 0;
  DECLARE v_cobro decimal(18,6) DEFAULT 0;
  DECLARE v_resto decimal(18,6) DEFAULT 0;
  DECLARE v_nuevo int DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  START TRANSACTION;
  SELECT COUNT(*)
    INTO v_existe
    FROM fza_efectos_venta
   WHERE SERIE_FAC_EFV = p_SERIE
     AND NUMERO_FAC_EFV = p_NUMERO
     AND NUMERO_EFV = p_NUM_EFV
     AND COALESCE(ESTADO_EFV, '') NOT IN
         ('COBRADO', 'ANULADO', 'DEVUELTO', 'CONCILIADO')
     AND COALESCE(IMPORTE_PENDIENTE_EFV, IMPORTE_EFV, 0) > 0;
  IF v_existe > 0 AND COALESCE(p_IMPORTE, 0) > 0 THEN
    SELECT COALESCE(IMPORTE_EFV, 0),
           COALESCE(IMPORTE_PENDIENTE_EFV, IMPORTE_EFV, 0)
      INTO v_importe, v_pend
      FROM fza_efectos_venta
     WHERE SERIE_FAC_EFV = p_SERIE
       AND NUMERO_FAC_EFV = p_NUMERO
       AND NUMERO_EFV = p_NUM_EFV
       FOR UPDATE;
    SET v_cobro = COALESCE(p_IMPORTE, 0);
    IF v_cobro > v_pend THEN
      SET v_cobro = v_pend;
    END IF;
    SET v_resto = v_pend - v_cobro;
    IF v_resto <= 0.000001 THEN
      UPDATE fza_efectos_venta
         SET IMPORTE_COBRADO_EFV = v_importe,
             IMPORTE_PENDIENTE_EFV = 0,
             FECHA_COBRO_EFV = COALESCE(p_FECHA, CURDATE()),
             TIPO_COBRO_EFV = NULLIF(p_TIPO, ''),
             REFERENCIA_COBRO_EFV = NULLIF(p_REFERENCIA, ''),
             ENTIDAD_COBRO_EFV = NULLIF(p_ENTIDAD, ''),
             ESCONCILIADO_EFV = 'S',
             ESTADO_EFV = 'COBRADO',
             INSTANTE_MODIF = NOW(),
             USUARIO_MODIF = p_USUARIO
       WHERE SERIE_FAC_EFV = p_SERIE
         AND NUMERO_FAC_EFV = p_NUMERO
         AND NUMERO_EFV = p_NUM_EFV;
      SET p_RESULTADO = 1;
    ELSE
      SELECT COALESCE(MAX(NUMERO_EFV), 0) + 1
        INTO v_nuevo
        FROM fza_efectos_venta
       WHERE SERIE_FAC_EFV = p_SERIE
         AND NUMERO_FAC_EFV = p_NUMERO;
      UPDATE fza_efectos_venta
         SET IMPORTE_EFV = v_cobro,
             IMPORTE_COBRADO_EFV = v_cobro,
             IMPORTE_PENDIENTE_EFV = 0,
             FECHA_COBRO_EFV = COALESCE(p_FECHA, CURDATE()),
             TIPO_COBRO_EFV = NULLIF(p_TIPO, ''),
             REFERENCIA_COBRO_EFV = NULLIF(p_REFERENCIA, ''),
             ENTIDAD_COBRO_EFV = NULLIF(p_ENTIDAD, ''),
             ESCONCILIADO_EFV = 'S',
             ESTADO_EFV = 'COBRADO',
             INSTANTE_MODIF = NOW(),
             USUARIO_MODIF = p_USUARIO
       WHERE SERIE_FAC_EFV = p_SERIE
         AND NUMERO_FAC_EFV = p_NUMERO
         AND NUMERO_EFV = p_NUM_EFV;
      INSERT INTO fza_efectos_venta
        (SERIE_FAC_EFV, NUMERO_FAC_EFV, NUMERO_EFV,
         CODIGO_EMP_EFV, CODIGO_CLI_EFV, RAZON_SOCIAL_CLI_EFV,
         NIF_CLI_EFV, CODIGO_TEFE_EFV, ESTADO_EFV,
         ORDEN_PLAZO_EFV, FECHA_EMISION_EFV, FECHA_VENCIMIENTO_EFV,
         ESCONCILIADO_EFV, IMPORTE_EFV, IMPORTE_COBRADO_EFV,
         IMPORTE_PENDIENTE_EFV, SERIE_REMV_EFV, NUMERO_REMV_EFV,
         ENTIDAD_EFV, OFICINA_EFV, DIGITO_CONTROL_EFV, CUENTA_EFV,
         IBAN_EFV, CODIGO_EMPBAN_EFV, IBAN_EMP_EFV, DOC_EXTERNO_EFV,
         REFERENCIA_DOCUMENTO_EFV, SERIE_FAC_CONCILIACION_EFV,
         NUMERO_FAC_CONCILIACION_EFV, NUMERO_EFV_CONCILIACION_EFV,
         OBSERVACIONES_EFV, INSTANTE_ALTA, USUARIO_ALTA,
         INSTANTE_MODIF, USUARIO_MODIF)
      SELECT SERIE_FAC_EFV, NUMERO_FAC_EFV, v_nuevo,
             CODIGO_EMP_EFV, CODIGO_CLI_EFV, RAZON_SOCIAL_CLI_EFV,
             NIF_CLI_EFV, CODIGO_TEFE_EFV,
             CASE
               WHEN COALESCE(SERIE_REMV_EFV, '') <> '' THEN 'REMESADO'
               ELSE 'PENDIENTE'
             END,
             ORDEN_PLAZO_EFV, FECHA_EMISION_EFV,
             FECHA_VENCIMIENTO_EFV, 'N', v_resto, 0, v_resto,
             SERIE_REMV_EFV, NUMERO_REMV_EFV, ENTIDAD_EFV, OFICINA_EFV,
             DIGITO_CONTROL_EFV, CUENTA_EFV, IBAN_EFV, CODIGO_EMPBAN_EFV,
             IBAN_EMP_EFV, DOC_EXTERNO_EFV, REFERENCIA_DOCUMENTO_EFV,
             SERIE_FAC_CONCILIACION_EFV, NUMERO_FAC_CONCILIACION_EFV,
             NUMERO_EFV_CONCILIACION_EFV, OBSERVACIONES_EFV,
             NOW(), p_USUARIO, NOW(), p_USUARIO
        FROM fza_efectos_venta
       WHERE SERIE_FAC_EFV = p_SERIE
         AND NUMERO_FAC_EFV = p_NUMERO
         AND NUMERO_EFV = p_NUM_EFV;
      SET p_RESULTADO = 2;
    END IF;
  END IF;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_EFV_GENERAR_DESDE_FACTURA
DROP PROCEDURE IF EXISTS `PRC_EFV_GENERAR_DESDE_FACTURA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_EFV_GENERAR_DESDE_FACTURA`(
    IN p_SERIE varchar(20),
    IN p_NUMERO varchar(20),
    IN p_USUARIO varchar(100),
    IN p_CODIGO_EMPBAN varchar(8),
    IN p_IBAN_EMP varchar(34),
    OUT p_RESULTADO int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_liquido decimal(18,6) DEFAULT 0;
  DECLARE v_fp varchar(200);
  DECLARE v_fecha date;
  DECLARE v_emp varchar(8);
  DECLARE v_cli varchar(20);
  DECLARE v_razon varchar(200);
  DECLARE v_nif varchar(50);
  DECLARE v_iban varchar(34);
  DECLARE v_nplazos int DEFAULT 1;
  DECLARE v_dias int DEFAULT 0;
  DECLARE v_escontado varchar(1) DEFAULT 'N';
  DECLARE v_tefe varchar(20);
  DECLARE v_bloqueados int DEFAULT 0;
  DECLARE v_i int DEFAULT 1;
  DECLARE v_imp decimal(18,6) DEFAULT 0;
  DECLARE v_acum decimal(18,6) DEFAULT 0;
  DECLARE v_vto date;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  SELECT COUNT(*)
    INTO v_bloqueados
    FROM fza_efectos_venta
   WHERE SERIE_FAC_EFV = p_SERIE
     AND NUMERO_FAC_EFV = p_NUMERO
     AND (COALESCE(ESTADO_EFV, '') IN
          ('COBRADO', 'REMESADO', 'CONCILIADO')
          OR COALESCE(IMPORTE_COBRADO_EFV, 0) > 0
          OR COALESCE(ESCONCILIADO_EFV, 'N') = 'S'
          OR COALESCE(SERIE_REMV_EFV, '') <> ''
          OR COALESCE(SERIE_FAC_CONCILIACION_EFV, '') <> '');
  IF v_bloqueados = 0 THEN
    SELECT COALESCE(f.TOTAL_LIQUIDO_FAC, 0), f.FORMA_PAGO_FAC,
           COALESCE(f.FECHA_FAC, CURDATE()), f.CODIGO_EMP_FAC,
           f.CODIGO_CLI_FAC, f.RAZON_SOCIAL_CLIENTE_FAC,
           f.NIF_CLIENTE_FAC, cli.IBAN_CLI,
           COALESCE(fp.N_PLAZOS_FORMA_PAGO_FP, 1),
           COALESCE(fp.N_DIAS_ENTRE_PLAZOS_FORMA_PAGO_FP, 0),
           COALESCE(fp.ESCONTADO_FORMA_PAGO_FP, 'N')
      INTO v_liquido, v_fp, v_fecha, v_emp, v_cli, v_razon, v_nif,
           v_iban, v_nplazos, v_dias, v_escontado
      FROM fza_facturas f
      LEFT JOIN fza_clientes cli
        ON cli.CODIGO_CLI_CLI = f.CODIGO_CLI_FAC
      LEFT JOIN fza_formas_pago fp
        ON fp.CODIGO_FP_FP = f.FORMA_PAGO_FAC
     WHERE f.SERIE_FAC = p_SERIE
       AND f.NUMERO_FAC = p_NUMERO;
    IF v_nplazos IS NULL OR v_nplazos < 1 THEN
      SET v_nplazos = 1;
    END IF;
    SET v_tefe = IF(v_escontado = 'S', 'CONTADO', 'RECIBO');
    IF v_liquido > 0 THEN
      START TRANSACTION;
      DELETE FROM fza_efectos_venta
       WHERE SERIE_FAC_EFV = p_SERIE
         AND NUMERO_FAC_EFV = p_NUMERO;
      SET v_acum = 0;
      WHILE v_i <= v_nplazos DO
        IF v_i = v_nplazos THEN
          SET v_imp = v_liquido - v_acum;
        ELSE
          SET v_imp = ROUND(v_liquido / v_nplazos, 2);
          SET v_acum = v_acum + v_imp;
        END IF;
        SET v_vto = DATE_ADD(v_fecha, INTERVAL (v_i * v_dias) DAY);
        INSERT INTO fza_efectos_venta
          (SERIE_FAC_EFV, NUMERO_FAC_EFV, NUMERO_EFV, CODIGO_EMP_EFV,
           CODIGO_CLI_EFV, RAZON_SOCIAL_CLI_EFV, NIF_CLI_EFV,
           CODIGO_TEFE_EFV, ESTADO_EFV, ORDEN_PLAZO_EFV,
           FECHA_EMISION_EFV, FECHA_VENCIMIENTO_EFV, IMPORTE_EFV,
           IMPORTE_COBRADO_EFV, IMPORTE_PENDIENTE_EFV, IBAN_EFV,
           CODIGO_EMPBAN_EFV, IBAN_EMP_EFV, REFERENCIA_DOCUMENTO_EFV,
           INSTANTE_ALTA, USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF)
        VALUES
          (p_SERIE, p_NUMERO, v_i, v_emp, v_cli, v_razon, v_nif,
           v_tefe, 'PENDIENTE', v_i, v_fecha, v_vto, v_imp,
           0, v_imp, v_iban, NULLIF(p_CODIGO_EMPBAN, ''),
           NULLIF(p_IBAN_EMP, ''), CONCAT(p_SERIE, '/', p_NUMERO),
           NOW(), p_USUARIO, NOW(), p_USUARIO);
        SET v_i = v_i + 1;
      END WHILE;
      COMMIT;
      SET p_RESULTADO = v_nplazos;
    END IF;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FACC_ACTUALIZAR_DTOS_ALBARANES
DROP PROCEDURE IF EXISTS `PRC_FACC_ACTUALIZAR_DTOS_ALBARANES`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FACC_ACTUALIZAR_DTOS_ALBARANES`(
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_bruto, v_dtoCom, v_baseFin, v_dtoFin decimal(18,6) DEFAULT 0;
  SELECT COALESCE(SUM(COALESCE(TOTAL_FACCLIN, 0)), 0)
    INTO v_bruto
    FROM fza_facturas_compra_lineas
   WHERE SERIE_FACC_FACCLIN = p_SERIE
     AND NUMERO_FACC_FACCLIN = p_NUMERO;
  SELECT COALESCE(SUM(COALESCE(a.TOTAL_DTO_COMERCIAL_ALBC, 0)), 0),
         COALESCE(SUM(COALESCE(a.TOTAL_DTO_FINANCIERO_ALBC, 0)), 0)
    INTO v_dtoCom, v_dtoFin
    FROM (
      SELECT DISTINCT SERIE_ALBC_FACCLIN, NUMERO_ALBC_FACCLIN
        FROM fza_facturas_compra_lineas
       WHERE SERIE_FACC_FACCLIN = p_SERIE
         AND NUMERO_FACC_FACCLIN = p_NUMERO
         AND COALESCE(SERIE_ALBC_FACCLIN, '') <> ''
         AND COALESCE(NUMERO_ALBC_FACCLIN, '') <> ''
    ) l
    JOIN fza_albaranes_compra a
      ON a.SERIE_ALBC = l.SERIE_ALBC_FACCLIN
     AND a.NUMERO_ALBC = l.NUMERO_ALBC_FACCLIN;
  SET v_baseFin = v_bruto - v_dtoCom;
  IF v_baseFin < 0 THEN
    SET v_baseFin = 0;
  END IF;
  UPDATE fza_facturas_compra
     SET PORCENTAJE_DTO_COMERCIAL_FACC =
           CASE WHEN v_bruto > 0
                THEN v_dtoCom / v_bruto * 100
                ELSE 0 END,
         TOTAL_DTO_COMERCIAL_FACC = v_dtoCom,
         PORCENTAJE_DTO_FINANCIERO_FACC =
           CASE WHEN v_baseFin > 0
                THEN v_dtoFin / v_baseFin * 100
                ELSE 0 END,
         TOTAL_DTO_FINANCIERO_FACC = v_dtoFin
   WHERE SERIE_FACC = p_SERIE
     AND NUMERO_FACC = p_NUMERO;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FACC_FACTURAR_ALBARAN
DROP PROCEDURE IF EXISTS `PRC_FACC_FACTURAR_ALBARAN`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FACC_FACTURAR_ALBARAN`(
  IN p_SERIE_ALB varchar(20),
  IN p_NUMERO_ALB varchar(20),
  IN p_SERIE_FAC varchar(20),
  IN p_NUMERO_FAC varchar(20),
  IN p_USUARIO varchar(100),
  OUT p_SERIE_FAC_OUT varchar(20),
  OUT p_NUMERO_FAC_OUT varchar(20),
  OUT p_RESULTADO int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_existe int DEFAULT 0;
  DECLARE v_prv_alb varchar(20);
  DECLARE v_emp_alb varchar(8);
  DECLARE v_re_alb varchar(1);
  DECLARE v_exento_alb varchar(1);
  DECLARE v_prv_fac varchar(20);
  DECLARE v_emp_fac varchar(8);
  DECLARE v_re_fac varchar(1);
  DECLARE v_exento_fac varchar(1);
  DECLARE v_cont bigint DEFAULT 0;
  DECLARE v_nlineas int DEFAULT 0;
  DECLARE v_nro bigint DEFAULT 0;
  DECLARE v_serie varchar(3);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  SET p_SERIE_FAC_OUT = '';
  SET p_NUMERO_FAC_OUT = '';
  SELECT COUNT(*)
    INTO v_existe
    FROM fza_albaranes_compra
   WHERE SERIE_ALBC = p_SERIE_ALB
     AND NUMERO_ALBC = p_NUMERO_ALB
     AND COALESCE(ESTADO_ALBC, '') NOT IN ('FACTURADO', 'CANCELADO');
  IF v_existe > 0 THEN
    IF p_NUMERO_FAC IS NULL OR p_NUMERO_FAC = '' THEN
      CALL PRC_FNC_GET_NEXT_NRO_DOC('FP', v_nro);
      CALL PRC_FNC_GET_SERIE_TIPODOC('FP', v_serie);
    END IF;
    START TRANSACTION;
    BEGIN
      DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_existe = 0;
      SET v_existe = 1;
      SELECT CODIGO_PRV_ALBC, CODIGO_EMP_ALBC,
             COALESCE(NULLIF(ESIVA_RECARGO_COMPRAS_ALBC, ''), 'N'),
             COALESCE(
               NULLIF(ESIVA_EXENTO_INTRACOMUNITARIO_ALBC, ''), 'N')
        INTO v_prv_alb, v_emp_alb, v_re_alb, v_exento_alb
        FROM fza_albaranes_compra
       WHERE SERIE_ALBC = p_SERIE_ALB
         AND NUMERO_ALBC = p_NUMERO_ALB
         AND COALESCE(ESTADO_ALBC, '') NOT IN ('FACTURADO', 'CANCELADO')
       LIMIT 1
         FOR UPDATE;
    END;
    IF v_existe > 0 THEN
      IF p_NUMERO_FAC IS NULL OR p_NUMERO_FAC = '' THEN
        SET p_NUMERO_FAC_OUT = LPAD(v_nro, 6, '0');
        SET p_SERIE_FAC_OUT = v_serie;
      INSERT INTO fza_facturas_compra
        (NUMERO_FACC, SERIE_FACC, FECHA_FACC, ESTADO_FACC,
         CODIGO_EMP_FACC, RAZON_SOCIAL_EMPRESA_FACC, NIF_EMPRESA_FACC,
         MOVIL_EMPRESA_FACC, EMAIL_EMPRESA_FACC, DIRECCION1_EMPRESA_FACC,
         DIRECCION2_EMPRESA_FACC, POBLACION_EMPRESA_FACC,
         PROVINCIA_EMPRESA_FACC, CODIGO_PAI_EMPRESA_FACC,
         NOMBRE_PAI_EMPRESA_FACC, CODIGO_POSTAL_EMPRESA_FACC,
         CODIGO_PRV_FACC, RAZON_SOCIAL_PRV_FACC, NIF_PRV_FACC,
         MOVIL_PRV_FACC, EMAIL_PRV_FACC, DIRECCION1_PRV_FACC,
         DIRECCION2_PRV_FACC, POBLACION_PRV_FACC, PROVINCIA_PRV_FACC,
         CODIGO_PAI_PRV_FACC, NOMBRE_PAI_PRV_FACC, CODIGO_POSTAL_PRV_FACC,
         CODIGO_ALM_FACC, CODIGO_IVA_FACC, ESIVA_RECARGO_COMPRAS_FACC,
         ESIVA_EXENTO_INTRACOMUNITARIO_FACC,
         PORCENTAJE_IVAN_FACC, PORCENTAJE_IVAR_FACC,
         PORCENTAJE_IVAS_FACC, PORCENTAJE_IVAE_FACC,
         PORCENTAJE_REN_FACC, PORCENTAJE_RER_FACC,
         PORCENTAJE_RES_FACC, PORCENTAJE_REE_FACC,
         PORCENTAJE_RETENCION_FACC, FORMA_PAGO_FACC,
         ESAGRUPAR_ALBARANES_FACC, CONTADOR_LINEAS_FACC,
         INSTANTE_ALTA, USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF)
      SELECT p_NUMERO_FAC_OUT, p_SERIE_FAC_OUT, CURDATE(), 'ABIERTA',
         CODIGO_EMP_ALBC, RAZON_SOCIAL_EMPRESA_ALBC, NIF_EMPRESA_ALBC,
         MOVIL_EMPRESA_ALBC, EMAIL_EMPRESA_ALBC, DIRECCION1_EMPRESA_ALBC,
         DIRECCION2_EMPRESA_ALBC, POBLACION_EMPRESA_ALBC,
         PROVINCIA_EMPRESA_ALBC, CODIGO_PAI_EMPRESA_ALBC,
         NOMBRE_PAI_EMPRESA_ALBC, CODIGO_POSTAL_EMPRESA_ALBC,
         CODIGO_PRV_ALBC, RAZON_SOCIAL_PRV_ALBC, NIF_PRV_ALBC,
         MOVIL_PRV_ALBC, EMAIL_PRV_ALBC, DIRECCION1_PRV_ALBC,
         DIRECCION2_PRV_ALBC, POBLACION_PRV_ALBC, PROVINCIA_PRV_ALBC,
         CODIGO_PAI_PRV_ALBC, NOMBRE_PAI_PRV_ALBC, CODIGO_POSTAL_PRV_ALBC,
         CODIGO_ALM_ALBC, CODIGO_IVA_ALBC,
         COALESCE(NULLIF(ESIVA_RECARGO_COMPRAS_ALBC, ''), 'N'),
         COALESCE(NULLIF(ESIVA_EXENTO_INTRACOMUNITARIO_ALBC, ''), 'N'),
         PORCENTAJE_IVAN_ALBC, PORCENTAJE_IVAR_ALBC,
         PORCENTAJE_IVAS_ALBC, PORCENTAJE_IVAE_ALBC,
         PORCENTAJE_REN_ALBC, PORCENTAJE_RER_ALBC,
         PORCENTAJE_RES_ALBC, PORCENTAJE_REE_ALBC,
         PORCENTAJE_RETENCION_ALBC, FORMA_PAGO_ALBC,
         'S', '0', NOW(), p_USUARIO, NOW(), p_USUARIO
        FROM fza_albaranes_compra
       WHERE SERIE_ALBC = p_SERIE_ALB
         AND NUMERO_ALBC = p_NUMERO_ALB;
      SET v_existe = 1;
    ELSE
      BEGIN
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_existe = 0;
        SET v_existe = 1;
        SELECT CODIGO_PRV_FACC, CODIGO_EMP_FACC,
               COALESCE(NULLIF(ESIVA_RECARGO_COMPRAS_FACC, ''), v_re_alb),
               COALESCE(
                 NULLIF(ESIVA_EXENTO_INTRACOMUNITARIO_FACC, ''),
                 v_exento_alb)
          INTO v_prv_fac, v_emp_fac, v_re_fac, v_exento_fac
          FROM fza_facturas_compra
         WHERE SERIE_FACC = p_SERIE_FAC
           AND NUMERO_FACC = p_NUMERO_FAC
           AND COALESCE(ESTADO_FACC, '') IN ('ABIERTA', 'CERRADA')
         LIMIT 1
           FOR UPDATE;
      END;
      IF v_existe > 0
         AND COALESCE(v_prv_fac, '') = COALESCE(v_prv_alb, '')
         AND COALESCE(v_emp_fac, '') = COALESCE(v_emp_alb, '')
         AND COALESCE(v_re_fac, 'N') = COALESCE(v_re_alb, 'N')
         AND COALESCE(v_exento_fac, 'N') = COALESCE(v_exento_alb, 'N') THEN
        SET p_SERIE_FAC_OUT = p_SERIE_FAC;
        SET p_NUMERO_FAC_OUT = p_NUMERO_FAC;
        UPDATE fza_facturas_compra
           SET ESIVA_RECARGO_COMPRAS_FACC =
               COALESCE(NULLIF(ESIVA_RECARGO_COMPRAS_FACC, ''), v_re_alb),
               ESIVA_EXENTO_INTRACOMUNITARIO_FACC =
               COALESCE(NULLIF(ESIVA_EXENTO_INTRACOMUNITARIO_FACC, ''),
                        v_exento_alb)
         WHERE SERIE_FACC = p_SERIE_FAC_OUT
           AND NUMERO_FACC = p_NUMERO_FAC_OUT;
      ELSE
        SET v_existe = 0;
      END IF;
    END IF;
    IF v_existe > 0 THEN
      SELECT CAST(COALESCE(NULLIF(CONTADOR_LINEAS_FACC, ''), '0')
                  AS UNSIGNED)
        INTO v_cont
        FROM fza_facturas_compra
       WHERE SERIE_FACC = p_SERIE_FAC_OUT
         AND NUMERO_FACC = p_NUMERO_FAC_OUT;
      INSERT INTO fza_facturas_compra_lineas
        (NUMERO_FACC_FACCLIN, SERIE_FACC_FACCLIN, LINEA_FACCLIN,
         NUMERO_ALBC_FACCLIN, SERIE_ALBC_FACCLIN, LINEA_ALBC_FACCLIN,
         CODIGO_ART_FACCLIN, CODIGO_UNIDAD_FACCLIN, REF_PRV_FACCLIN,
         ID_AC_PIVOT_FACCLIN, CODIGO_FAM_FACCLIN, NOMBRE_FAM_FACCLIN,
         DESCRIPCION_ARTICULO_FACCLIN, TIPO_CANTIDAD_ARTICULO_FACCLIN,
         CANTIDAD_FACCLIN, TOTAL_UNIDADES_FACCLIN,
         TIPO_IVA_ARTICULO_FACCLIN, PORCENTAJE_IVA_FACCLIN,
         PRECIO_COMPRA_SIVA_ARTICULO_FACCLIN,
         PRECIO_COMPRA_CIVA_ARTICULO_FACCLIN, TOTAL_FACCLIN,
         CODIGO_ALMACEN_FACCLIN, LOTE_FACCLIN, FECHA_CADUCIDAD_FACCLIN,
         DESCRIPCION_VARIACION_FACCLIN,
         INSTANTE_ALTA, USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF)
      SELECT p_NUMERO_FAC_OUT, p_SERIE_FAC_OUT,
         LPAD(v_cont + 10 * ROW_NUMBER() OVER (ORDER BY LINEA_ALBCLIN),
              4, '0'),
         NUMERO_ALBC_ALBCLIN, SERIE_ALBC_ALBCLIN, LINEA_ALBCLIN,
         CODIGO_ART_ALBCLIN, CODIGO_UNIDAD_ALBCLIN, REF_PRV_ALBCLIN,
         ID_AC_PIVOT_ALBCLIN, CODIGO_FAM_ALBCLIN, NOMBRE_FAM_ALBCLIN,
         DESCRIPCION_ARTICULO_ALBCLIN, TIPO_CANTIDAD_ARTICULO_ALBCLIN,
         CANTIDAD_ALBCLIN, TOTAL_UNIDADES_ALBCLIN,
         CASE WHEN v_exento_alb = 'S'
              THEN 'E' ELSE TIPO_IVA_ARTICULO_ALBCLIN END,
         CASE WHEN v_exento_alb = 'S'
              THEN 0 ELSE PORCENTAJE_IVA_ALBCLIN END,
         PRECIO_COMPRA_SIVA_ARTICULO_ALBCLIN,
         CASE WHEN v_exento_alb = 'S'
              THEN PRECIO_COMPRA_SIVA_ARTICULO_ALBCLIN
              ELSE PRECIO_COMPRA_CIVA_ARTICULO_ALBCLIN END,
         TOTAL_ALBCLIN,
         CODIGO_ALMACEN_ALBCLIN, LOTE_ALBCLIN, FECHA_CADUCIDAD_ALBCLIN,
         DESCRIPCION_VARIACION_ALBCLIN,
         NOW(), p_USUARIO, NOW(), p_USUARIO
        FROM fza_albaranes_compra_lineas
       WHERE SERIE_ALBC_ALBCLIN = p_SERIE_ALB
         AND NUMERO_ALBC_ALBCLIN = p_NUMERO_ALB;
      SET v_nlineas = ROW_COUNT();
      UPDATE fza_facturas_compra
         SET CONTADOR_LINEAS_FACC = CAST(v_cont + 10 * v_nlineas AS CHAR),
             USUARIO_MODIF = p_USUARIO
       WHERE SERIE_FACC = p_SERIE_FAC_OUT
         AND NUMERO_FACC = p_NUMERO_FAC_OUT;
      UPDATE fza_albaranes_compra_lineas
         SET ESFACTURADA_ALBCLIN = 'S',
             NUMERO_FAC_ALBCLIN = p_NUMERO_FAC_OUT,
             SERIE_FAC_ALBCLIN = p_SERIE_FAC_OUT,
             USUARIO_MODIF = p_USUARIO
       WHERE SERIE_ALBC_ALBCLIN = p_SERIE_ALB
         AND NUMERO_ALBC_ALBCLIN = p_NUMERO_ALB;
      UPDATE fza_albaranes_compra
         SET ESTADO_ALBC = 'FACTURADO',
             NUMERO_FAC_ALBC = p_NUMERO_FAC_OUT,
             SERIE_FAC_ALBC = p_SERIE_FAC_OUT,
             USUARIO_MODIF = p_USUARIO
       WHERE SERIE_ALBC = p_SERIE_ALB
         AND NUMERO_ALBC = p_NUMERO_ALB;
      CALL PRC_FACC_ACTUALIZAR_DTOS_ALBARANES(
        p_SERIE_FAC_OUT, p_NUMERO_FAC_OUT);
      CALL PRC_FACC_RECALCULAR_TOTALES(
        p_SERIE_FAC_OUT, p_NUMERO_FAC_OUT);
      SET p_RESULTADO = 1;
      END IF;
    END IF;
    COMMIT;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FACC_RECALCULAR_TOTALES
DROP PROCEDURE IF EXISTS `PRC_FACC_RECALCULAR_TOTALES`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FACC_RECALCULAR_TOTALES`(
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_baseN, v_baseR, v_baseS, v_baseE decimal(18,6) DEFAULT 0;
  DECLARE v_ivaN, v_ivaR, v_ivaS decimal(18,6) DEFAULT 0;
  DECLARE v_reN, v_reR, v_reS, v_reE decimal(18,6) DEFAULT 0;
  DECLARE v_pN, v_pR, v_pS decimal(19,6) DEFAULT 0;
  DECLARE v_prN, v_prR, v_prS, v_prE decimal(19,6) DEFAULT 0;
  DECLARE v_suma_bases, v_impuestos, v_total decimal(18,6) DEFAULT 0;
  DECLARE v_reten, v_liquido, v_pRet decimal(18,6) DEFAULT 0;
  DECLARE v_dto, v_pp, v_rap, v_fin, v_por decimal(18,6) DEFAULT 0;
  DECLARE v_codIva varchar(20) DEFAULT '';
  DECLARE v_aplicaRe varchar(1) DEFAULT 'N';
  DECLARE v_exento varchar(1) DEFAULT 'N';
  SELECT COALESCE(NULLIF(ESIVA_RECARGO_COMPRAS_FACC, ''), 'N'),
         COALESCE(NULLIF(ESIVA_EXENTO_INTRACOMUNITARIO_FACC, ''), 'N'),
         COALESCE(CODIGO_IVA_FACC, ''),
         COALESCE(PORCENTAJE_RETENCION_FACC, 0),
         COALESCE(TOTAL_DTO_COMERCIAL_FACC, 0),
         COALESCE(TOTAL_PRONTO_PAGO_FACC, 0),
         COALESCE(TOTAL_RAPPEL_FACC, 0),
         COALESCE(TOTAL_FINANCIACION_FACC, 0),
         COALESCE(TOTAL_PORTES_FACC, 0)
    INTO v_aplicaRe, v_exento, v_codIva, v_pRet,
         v_dto, v_pp, v_rap, v_fin, v_por
    FROM fza_facturas_compra
   WHERE SERIE_FACC = p_SERIE
     AND NUMERO_FACC = p_NUMERO;
  IF v_exento = 'S' THEN
    SET v_aplicaRe = 'N';
  END IF;
  SELECT COALESCE(PORCENTAJE_NORMAL_RE_IVA, 0),
         COALESCE(PORCENTAJE_REDUCIDO_RE_IVA, 0),
         COALESCE(PORCENTAJE_SUPERREDUCIDO_RE_IVA, 0),
         COALESCE(PORCENTAJE_EXENTO_RE_IVA, 0)
    INTO v_prN, v_prR, v_prS, v_prE
    FROM fza_ivas
   WHERE CODIGO_IVA = v_codIva;
  SELECT COALESCE(SUM(CASE WHEN TIPO = 'N' THEN TOTAL_FACCLIN END), 0),
         COALESCE(SUM(CASE WHEN TIPO = 'R' THEN TOTAL_FACCLIN END), 0),
         COALESCE(SUM(CASE WHEN TIPO = 'S' THEN TOTAL_FACCLIN END), 0),
         COALESCE(SUM(CASE WHEN TIPO = 'E' THEN TOTAL_FACCLIN END), 0),
         COALESCE(SUM(CASE WHEN TIPO = 'N'
                           THEN TOTAL_FACCLIN * PORCENTAJE_EFECTIVO / 100
                      END), 0),
         COALESCE(SUM(CASE WHEN TIPO = 'R'
                           THEN TOTAL_FACCLIN * PORCENTAJE_EFECTIVO / 100
                      END), 0),
         COALESCE(SUM(CASE WHEN TIPO = 'S'
                           THEN TOTAL_FACCLIN * PORCENTAJE_EFECTIVO / 100
                      END), 0),
         COALESCE(MAX(CASE WHEN TIPO = 'N'
                           THEN PORCENTAJE_EFECTIVO END), 0),
         COALESCE(MAX(CASE WHEN TIPO = 'R'
                           THEN PORCENTAJE_EFECTIVO END), 0),
         COALESCE(MAX(CASE WHEN TIPO = 'S'
                           THEN PORCENTAJE_EFECTIVO END), 0)
    INTO v_baseN, v_baseR, v_baseS, v_baseE,
         v_ivaN, v_ivaR, v_ivaS, v_pN, v_pR, v_pS
    FROM (
      SELECT TOTAL_FACCLIN,
             CASE WHEN v_exento = 'S'
                  THEN 0 ELSE PORCENTAJE_IVA_FACCLIN END AS PORCENTAJE_EFECTIVO,
             CASE
               WHEN v_exento = 'S' THEN 'E'
               WHEN COALESCE(TIPO_IVA_ARTICULO_FACCLIN, '') IN ('N','R','S','E')
                 THEN TIPO_IVA_ARTICULO_FACCLIN
               WHEN COALESCE(PORCENTAJE_IVA_FACCLIN, 0) <= 0 THEN 'E'
               WHEN COALESCE(PORCENTAJE_IVA_FACCLIN, 0) < 6 THEN 'S'
               WHEN COALESCE(PORCENTAJE_IVA_FACCLIN, 0) < 13 THEN 'R'
               ELSE 'N'
             END AS TIPO
        FROM fza_facturas_compra_lineas
       WHERE SERIE_FACC_FACCLIN = p_SERIE
         AND NUMERO_FACC_FACCLIN = p_NUMERO
    ) x;
  IF v_aplicaRe = 'S' THEN
    SET v_reN = v_baseN * v_prN / 100;
    SET v_reR = v_baseR * v_prR / 100;
    SET v_reS = v_baseS * v_prS / 100;
    SET v_reE = v_baseE * v_prE / 100;
  END IF;
  SET v_suma_bases = v_baseN + v_baseR + v_baseS + v_baseE;
  SET v_impuestos = v_ivaN + v_ivaR + v_ivaS + v_reN + v_reR + v_reS + v_reE;
  SET v_total = v_suma_bases + v_impuestos;
  SET v_reten = ROUND(v_suma_bases * v_pRet / 100, 2);
  SET v_liquido = v_total - v_reten - v_dto - v_pp - v_rap + v_fin + v_por;
  UPDATE fza_facturas_compra
     SET PORCENTAJE_IVAN_FACC = v_pN,
         TOTAL_BASEI_IVAN_FACC = v_baseN,
         TOTAL_IVAN_FACC = v_ivaN,
         PORCENTAJE_REN_FACC = v_prN,
         TOTAL_REN_FACC = v_reN,
         PORCENTAJE_IVAR_FACC = v_pR,
         TOTAL_BASEI_IVAR_FACC = v_baseR,
         TOTAL_IVAR_FACC = v_ivaR,
         PORCENTAJE_RER_FACC = v_prR,
         TOTAL_RER_FACC = v_reR,
         PORCENTAJE_IVAS_FACC = v_pS,
         TOTAL_BASEI_IVAS_FACC = v_baseS,
         TOTAL_IVAS_FACC = v_ivaS,
         PORCENTAJE_RES_FACC = v_prS,
         TOTAL_RES_FACC = v_reS,
         PORCENTAJE_IVAE_FACC = 0,
         TOTAL_BASEI_IVAE_FACC = v_baseE,
         TOTAL_IVAE_FACC = 0,
         PORCENTAJE_REE_FACC = v_prE,
         TOTAL_REE_FACC = v_reE,
         TOTAL_BRUTO_FACC = v_suma_bases,
         TOTAL_BASES_FACC = v_suma_bases,
         TOTAL_IMPUESTOS_FACC = v_impuestos,
         TOTAL_FACC = v_total,
         TOTAL_RETENCION_FACC = v_reten,
         TOTAL_LIQUIDO_FACC = v_liquido
   WHERE SERIE_FACC = p_SERIE
     AND NUMERO_FACC = p_NUMERO;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FNC_GET_NEXT_LINEA_FACTURA
DROP PROCEDURE IF EXISTS `PRC_FNC_GET_NEXT_LINEA_FACTURA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FNC_GET_NEXT_LINEA_FACTURA`(
    IN  `pnumfac` VARCHAR(12), 
    IN  `pserie`  VARCHAR(12), 
    OUT `presul`  VARCHAR(3)
)
SQL SECURITY INVOKER
BEGIN    
    DECLARE v_NextValue BIGINT;

    /* Manejo de errores para asegurar la consistencia (etiqueta para Uniscript) */    
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN        
        ROLLBACK;
        RESIGNAL;
    END kk;
    
    START TRANSACTION;
    
    /* 1 y 4 FUSIONADOS: Bloqueamos, calculamos y actualizamos de golpe */
    UPDATE `fza_facturas`
    SET `CONTADOR_LINEAS_FAC` = LPAD(
        LAST_INSERT_ID(
            CASE 
                /* Si es la primera vez (nulo, vacío o 0), preparamos el TERRENO para el futuro (20) */
                WHEN `CONTADOR_LINEAS_FAC` IS NULL 
                  OR `CONTADOR_LINEAS_FAC` = '' 
                  OR `CONTADOR_LINEAS_FAC` = '0' THEN 20
                /* Si ya tiene valor, le sumamos 10 */
                ELSE CAST(`CONTADOR_LINEAS_FAC` AS UNSIGNED) + 10
            END
        ), 3, '0'
    )
    WHERE `SERIE_FAC` = pserie 
      AND `NUMERO_FAC`   = pnumfac;
    
    /* Comprobamos si la factura existía y se actualizó */
    IF ROW_COUNT() > 0 THEN
        /* Si hemos guardado 20, nos toca devolver 10 ('010')
           Si hemos guardado 30, nos toca devolver 20 ('020')
        */
        SET v_NextValue = LAST_INSERT_ID() - 10;
        SET `presul` = LPAD(v_NextValue, 3, '0');
    ELSE
        /* Comportamiento de seguridad igual al tuyo: 
           Si por algún motivo la factura aún no existe en fza_facturas, devolvemos '010' 
        */
        SET `presul` = '010';
    END IF;
    
    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FNC_GET_NEXT_NRO_DOC
DROP PROCEDURE IF EXISTS `PRC_FNC_GET_NEXT_NRO_DOC`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FNC_GET_NEXT_NRO_DOC`(IN  `ptipodoc` VARCHAR(8), 
                                             INOUT `ppresul`   BIGINT)
SQL SECURITY INVOKER
BEGIN

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;
START TRANSACTION;
UPDATE `fza_contadores`
   SET `CON` = CON + 1
 WHERE `SERIE_CON` = '-'
   AND `TIPO_DOC_CON` = `pTipoDoc`;
  SET `ppresul` = (SELECT `CON` - 1
                     FROM `fza_contadores`
                    WHERE `SERIE_CON` = '-'
                      AND `DEFAULT_CON` = 'S'
                      AND `TIPO_DOC_CON` = `pTipoDoc` 
                    LIMIT 1);
COMMIT;

END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FNC_GET_PRECIO_ARTICULO_FECHA
DROP PROCEDURE IF EXISTS `PRC_FNC_GET_PRECIO_ARTICULO_FECHA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FNC_GET_PRECIO_ARTICULO_FECHA`(
  in pCODIGO_ARTICULO varchar(20),
  in pFECHA date,
  inout pPRECIOSALIDA_TARIFA decimal(19,6),
  inout pPRECIOFINAL_TARIFA decimal(19,6),
  inout pPORCEN_DTO_TARIFA decimal(19,6),
  inout pPRECIO_DTO_TARIFA decimal(19,6))
SQL SECURITY INVOKER
BEGIN
  SELECT PRECIO_SALIDA_ARTTAR,
    PRECIO_FINAL_ARTTAR,
    PORCENTAJE_DTO_ARTTAR,
    PRECIO_DTO_ARTTAR
    INTO
    pPRECIOSALIDA_TARIFA,
    pPRECIOFINAL_TARIFA,
    pPORCEN_DTO_TARIFA,
    pPRECIO_DTO_TARIFA
    FROM fza_articulos_tarifas
    WHERE CODIGO_ART_ARTTAR = pCODIGO_ARTICULO
    AND FECHA_DESDE_ARTTAR <= pFECHA
    AND (FECHA_HASTA_ARTTAR IS NULL OR
    FECHA_HASTA_ARTTAR >= pFECHA);
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FNC_GET_SERIE_TIPODOC
DROP PROCEDURE IF EXISTS `PRC_FNC_GET_SERIE_TIPODOC`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FNC_GET_SERIE_TIPODOC`(IN `ptipodoc` VARCHAR(8), 
                                                OUT `presul` VARCHAR(3))
SQL SECURITY INVOKER
BEGIN


DECLARE pserie varchar(3);
SET pserie = (select SERIE_CON
FROM fza_contadores
  where DEFAULT_CON = 'S'
and TIPO_DOC_CON = ptipodoc);
IF (pserie IS NULL) THEN
   SET presul = '-';
ELSE
   SET presul = pserie;
END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FORMATO_DOCUMENTO
DROP PROCEDURE IF EXISTS `PRC_FORMATO_DOCUMENTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FORMATO_DOCUMENTO`(
  IN p_FORMATO varchar(80),
  IN p_SERIE varchar(50),
  IN p_NUMERO varchar(50),
  OUT p_DOCUMENTO_FORMATO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_formato varchar(80);
  DECLARE v_original varchar(200);
  DECLARE v_resultado varchar(200);
  DECLARE v_serie varchar(50);
  DECLARE v_numero varchar(50);

  SET v_serie = TRIM(COALESCE(p_SERIE, ''));
  SET v_numero = TRIM(COALESCE(p_NUMERO, ''));

  IF v_serie = '' THEN
    SET p_DOCUMENTO_FORMATO = v_numero;
  ELSEIF v_numero = '' THEN
    SET p_DOCUMENTO_FORMATO = v_serie;
  ELSE
    SET v_formato = NULLIF(TRIM(COALESCE(p_FORMATO, '')), '');

    IF v_formato IS NULL THEN
      SET v_formato = 'Serie.NroDocumento';
    END IF;

    SET v_resultado = v_formato;
    SET v_original = v_resultado;

    SET v_resultado = REPLACE(v_resultado, 'NroDocumento', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'nrodocumento', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NRODOCUMENTO', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NumeroDocumento', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'numerodocumento', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NUMERODOCUMENTO', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NúmeroDocumento', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'númerodocumento', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NÚMERODOCUMENTO', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NroFactura', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'nrofactura', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NROFACTURA', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NroDoc', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'nrodoc', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NRODOC', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'Numero', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'numero', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NUMERO', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'Número', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'número', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'NÚMERO', v_numero);
    SET v_resultado = REPLACE(v_resultado, 'Serie', v_serie);
    SET v_resultado = REPLACE(v_resultado, 'serie', v_serie);
    SET v_resultado = REPLACE(v_resultado, 'SERIE', v_serie);

    IF v_resultado = v_original THEN
      SET p_DOCUMENTO_FORMATO = CONCAT(v_serie, '.', v_numero);
    ELSE
      SET p_DOCUMENTO_FORMATO = v_resultado;
    END IF;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_AJUSTAR_ACUMULADO_STK
DROP PROCEDURE IF EXISTS `PRC_FZA_AJUSTAR_ACUMULADO_STK`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_AJUSTAR_ACUMULADO_STK`(
  IN p_TIPO_DOC_MOV varchar(20),
  IN p_TIPO_MOV varchar(1),
  IN p_CODIGO_ALM varchar(10),
  IN p_CODIGO_UNIDAD varchar(50),
  IN p_CANTIDAD decimal(19,6),
  IN p_VALOR decimal(19,6),
  IN p_MULT int
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_signo int;
  DECLARE v_filas int DEFAULT 0;
  SET v_signo = IF(p_TIPO_MOV = 'E', 1, -1);
  UPDATE fza_articulos_stockactual
     SET CANTIDAD_STK = CANTIDAD_STK +
           (v_signo * p_MULT * p_CANTIDAD),
         VALOR_TOTAL_STK = VALOR_TOTAL_STK +
           (v_signo * p_MULT * p_VALOR),
         PRECIO_MEDIO_STK = IF(
           CANTIDAD_STK > 0, VALOR_TOTAL_STK / CANTIDAD_STK, 0),
         INSTANTE_MODIF = NOW(),
         CANTIDAD_ENT_COMPRA_STK = CANTIDAD_ENT_COMPRA_STK +
           IF(p_TIPO_DOC_MOV = 'AC' AND p_TIPO_MOV = 'E',
             p_MULT * p_CANTIDAD, 0),
         CANTIDAD_ENT_TRASPASO_STK = CANTIDAD_ENT_TRASPASO_STK +
           IF(p_TIPO_DOC_MOV IN ('TR', 'AT', 'TA') AND
             p_TIPO_MOV = 'E', p_MULT * p_CANTIDAD, 0),
         CANTIDAD_SAL_TRASPASO_STK = CANTIDAD_SAL_TRASPASO_STK +
           IF(p_TIPO_DOC_MOV IN ('TR', 'AT', 'TA') AND
             p_TIPO_MOV = 'S', p_MULT * p_CANTIDAD, 0),
         CANTIDAD_ENT_DEPOSITO_STK = CANTIDAD_ENT_DEPOSITO_STK +
           IF(p_TIPO_DOC_MOV = 'DP' AND p_TIPO_MOV = 'E',
             p_MULT * p_CANTIDAD, 0),
         CANTIDAD_SAL_DEPOSITO_STK = CANTIDAD_SAL_DEPOSITO_STK +
           IF(p_TIPO_DOC_MOV = 'DP' AND p_TIPO_MOV = 'S',
             p_MULT * p_CANTIDAD, 0),
         CANTIDAD_SAL_VENTA_STK = CANTIDAD_SAL_VENTA_STK +
           IF(p_TIPO_DOC_MOV IN ('VE', 'FC') AND p_TIPO_MOV = 'S',
             p_MULT * p_CANTIDAD, 0),
         CANTIDAD_ENT_REGULAR_STK = CANTIDAD_ENT_REGULAR_STK +
           IF(p_TIPO_DOC_MOV = 'IN' AND p_TIPO_MOV = 'E',
             p_MULT * p_CANTIDAD, 0),
         CANTIDAD_SAL_ALBVENTA_STK = CANTIDAD_SAL_ALBVENTA_STK +
           IF(p_TIPO_DOC_MOV = 'AV' AND p_TIPO_MOV = 'S',
             p_MULT * p_CANTIDAD, 0),
         CANTIDAD_ENT_ALBENTRADA_STK = CANTIDAD_ENT_ALBENTRADA_STK +
           IF(p_TIPO_DOC_MOV = 'AE' AND p_TIPO_MOV = 'E',
             p_MULT * p_CANTIDAD, 0)
   WHERE CODIGO_ALM_STK = p_CODIGO_ALM
     AND CODIGO_UNIDAD_STK = p_CODIGO_UNIDAD;
  SET v_filas = ROW_COUNT();
  IF v_filas > 0 AND EXISTS (
    SELECT 1
      FROM fza_almacenes ALM
     WHERE ALM.CODIGO_ALM_ALM = p_CODIGO_ALM
       AND ALM.ESWEB_ALM = 'S'
       AND ALM.ESACTIVO_ALM = 'S'
       AND ALM.ESFISICO_ALM = 'S'
       AND UPPER(TRIM(ALM.TIPO_USO_ALM)) = 'ESTANDAR'
  ) THEN
    CALL PRC_PRESTASHOP_ENCOLAR_CAMBIO_ALMACEN(
      '', p_CODIGO_UNIDAD, 'N', 'S', '', p_CODIGO_ALM);
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_DEPOSITOS_INSERT
DROP PROCEDURE IF EXISTS `PRC_FZA_DEPOSITOS_INSERT`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_DEPOSITOS_INSERT`(
    IN p_ID_DEP VARCHAR(20),
    IN p_EMP VARCHAR(20),
    IN p_ALM_DEP VARCHAR(10),
    IN p_CLI VARCHAR(20),
    IN p_ART VARCHAR(50),
    IN p_SKU VARCHAR(50),
    IN p_PRECIO DECIMAL(19,6),
    IN p_CANTIDAD DECIMAL(19,6),
    IN p_ANTICIPO DECIMAL(19,6),
    IN p_TIPOIVA CHAR(1),
    IN p_PORCIVA DECIMAL(19,6),
    IN p_IMPINCL CHAR(1),
    IN p_CAJA VARCHAR(10),        /* NUEVO */
    IN p_NUMOP VARCHAR(20),       /* NUEVO */
    IN p_USUARIO VARCHAR(100)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_deuda_nueva DECIMAL(19,6) DEFAULT 0;

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;

    START TRANSACTION;

    /* 1. Insertamos el depósito en la tabla */
    INSERT INTO fza_depositos_cliente (
        ID_DEPOSITO_DEP, CODIGO_EMP_DEP, CODIGO_ALM_DEP,
        CODIGO_CLI_DEP, CODIGO_ART_DEP, CODIGO_UNIDAD_DEP,
        ESTADO_DEP, PRECIO_VENTA_DEP, CANTIDAD_PENDIENTE_DEP, IMPORTE_ANTICIPO_DEP,
        TIPO_IVA_DEP, PORCENTAJE_IVA_DEP, ESIMP_INCL_DEP,
        CODIGO_CAJA_DEP, NUMERO_OPERACION_DEP, /* NUEVOS CAMPOS */
        INSTANTE_ALTA, USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF
    ) VALUES (
        p_ID_DEP, p_EMP, p_ALM_DEP,
        p_CLI, p_ART, p_SKU, 
        'PENDIENTE', p_PRECIO, p_CANTIDAD, p_ANTICIPO,
        p_TIPOIVA, p_PORCIVA, p_IMPINCL,
        p_CAJA, p_NUMOP, /* NUEVOS VALORES */
        NOW(), p_USUARIO, NOW(), p_USUARIO
    );

    /* 2. Calculamos la nueva deuda (Lógica adaptada de tu trigger) */
    SET v_deuda_nueva = (p_PRECIO * COALESCE(p_CANTIDAD, 1)) - COALESCE(p_ANTICIPO, 0);

    /* 3. Si hay deuda generada, actualizamos el cliente */
    IF v_deuda_nueva > 0 AND p_CLI IS NOT NULL THEN
        UPDATE fza_clientes 
           SET TOTAL_DEUDA_CLI = COALESCE(TOTAL_DEUDA_CLI, 0) + v_deuda_nueva 
         WHERE CODIGO_CLI_CLI = p_CLI;
    END IF;

    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_DEPOSITOS_UPDATE
DROP PROCEDURE IF EXISTS `PRC_FZA_DEPOSITOS_UPDATE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_DEPOSITOS_UPDATE`(
    IN SKU VARCHAR(50),
    IN CLI VARCHAR(20),
    IN ESTADO VARCHAR(15),
    IN INC_ANTICIPO DECIMAL(19,6),
    IN USUARIO VARCHAR(100),
    OUT P_ID_DEPOSITO VARCHAR(20)
)
SQL SECURITY INVOKER
BEGIN
    /* Variables para almacenar los datos actuales del depósito */
    DECLARE v_ID_DEPOSITO VARCHAR(20);
    DECLARE v_OLD_ESTADO VARCHAR(15);
    DECLARE v_OLD_PRECIO DECIMAL(19,6);
    DECLARE v_OLD_CANTIDAD_PTE DECIMAL(19,6);
    DECLARE v_OLD_ANTICIPO DECIMAL(19,6);

    /* Variables para calcular los nuevos valores y la deuda */
    DECLARE v_NUEVO_ESTADO VARCHAR(15);
    DECLARE v_NUEVO_ANTICIPO DECIMAL(19,6);
    DECLARE v_deuda_antigua DECIMAL(19,6) DEFAULT 0;
    DECLARE v_deuda_nueva DECIMAL(19,6) DEFAULT 0;
    DECLARE v_diferencia DECIMAL(19,6) DEFAULT 0;

    /* Manejador de errores: Deshace todo si algo falla */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    /* 1. Buscar el depósito que coincide con el Cliente y el SKU */
    /* Buscamos el que esté 'PENDIENTE' y lo bloqueamos para evitar concurrencia */
    SELECT ID_DEPOSITO_DEP, ESTADO_DEP, PRECIO_VENTA_DEP, CANTIDAD_PENDIENTE_DEP, IMPORTE_ANTICIPO_DEP
      INTO v_ID_DEPOSITO, v_OLD_ESTADO, v_OLD_PRECIO, v_OLD_CANTIDAD_PTE, v_OLD_ANTICIPO
      FROM fza_depositos_cliente
     WHERE CODIGO_CLI_DEP = CLI
       AND CODIGO_UNIDAD_DEP = SKU
       AND ESTADO_DEP = 'PENDIENTE'
     LIMIT 1 /* Por seguridad, nos quedamos con uno en caso de anomalía de datos */
       FOR UPDATE;
    SET P_ID_DEPOSITO = v_ID_DEPOSITO;
    /* Solo procedemos si encontramos un depósito válido */
    IF v_ID_DEPOSITO IS NOT NULL THEN

        /* 2. Calcular los nuevos valores a guardar */
        /* Sumamos el anticipo actual con el incremento que viene de Delphi */
        SET v_NUEVO_ANTICIPO = v_OLD_ANTICIPO + COALESCE(INC_ANTICIPO, 0);
        
        /* Si Delphi manda NULL (ParamByName('ESTADO').Clear), mantenemos el estado anterior */
        SET v_NUEVO_ESTADO = COALESCE(ESTADO, v_OLD_ESTADO); 

        /* 3. Calcular la variación de la deuda para actualizar al cliente */
        IF v_OLD_ESTADO = 'PENDIENTE' THEN
            SET v_deuda_antigua = (v_OLD_PRECIO * COALESCE(v_OLD_CANTIDAD_PTE, 1)) - v_OLD_ANTICIPO;
        END IF;

        IF v_NUEVO_ESTADO = 'PENDIENTE' THEN
            SET v_deuda_nueva = (v_OLD_PRECIO * COALESCE(v_OLD_CANTIDAD_PTE, 1)) - v_NUEVO_ANTICIPO;
        END IF;

        SET v_diferencia = v_deuda_nueva - v_deuda_antigua;

        /* 4. Actualizar la tabla del depósito */
        UPDATE fza_depositos_cliente
           SET IMPORTE_ANTICIPO_DEP = v_NUEVO_ANTICIPO,
               ESTADO_DEP = v_NUEVO_ESTADO,
               USUARIO_MODIF = USUARIO,
               INSTANTE_MODIF = NOW()
         WHERE ID_DEPOSITO_DEP = v_ID_DEPOSITO;

        /* 5. Actualizar la deuda total en el cliente si hubo cambios */
        IF v_diferencia <> 0 THEN
            UPDATE fza_clientes
               SET TOTAL_DEUDA_CLI = COALESCE(TOTAL_DEUDA_CLI, 0) + v_diferencia
             WHERE CODIGO_CLI_CLI = CLI;
        END IF;

    END IF;

    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_INVENTARIOS_ACTUALIZAR_TEORICO
DROP PROCEDURE IF EXISTS `PRC_FZA_INVENTARIOS_ACTUALIZAR_TEORICO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_INVENTARIOS_ACTUALIZAR_TEORICO`(
  IN p_EMPRESA varchar(10),
  IN p_ALMACEN varchar(10),
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20),
  IN p_USUARIO varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_ESTADO varchar(20);
  DECLARE v_FECHA datetime;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
  SELECT ESTADO_INV,
         TIMESTAMP(DATE_SUB(DATE(FECHA_INV), INTERVAL 1 DAY), '23:59:59')
    INTO v_ESTADO, v_FECHA
    FROM fza_inventarios
   WHERE CODIGO_EMP_INV = p_EMPRESA
     AND CODIGO_ALM_INV = p_ALMACEN
     AND SERIE_INV = p_SERIE
     AND NUMERO_INV = p_NUMERO
   FOR UPDATE;
  IF IFNULL(v_ESTADO, '') <> 'ABIERTO' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El inventario no esta ABIERTO';
  END IF;
  CALL PRC_FZA_INVENTARIOS_CALCULAR_LINEAS(
    p_EMPRESA, p_ALMACEN, p_SERIE, p_NUMERO, p_USUARIO, v_FECHA);
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_INVENTARIOS_APLICAR
DROP PROCEDURE IF EXISTS `PRC_FZA_INVENTARIOS_APLICAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_INVENTARIOS_APLICAR`(
  IN p_EMPRESA varchar(10),
  IN p_ALMACEN varchar(10),
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20),
  IN p_USUARIO varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_FIN int DEFAULT 0;
  DECLARE v_ESTADO varchar(20);
  DECLARE v_FECHA datetime;
  DECLARE v_LINEA varchar(8);
  DECLARE v_ARTICULO varchar(20);
  DECLARE v_SKU varchar(50);
  DECLARE v_TEORICA decimal(19,6);
  DECLARE v_FISICA decimal(19,6);
  DECLARE v_PMP_HIST decimal(19,6);
  DECLARE v_PMP_NUEVO decimal(19,6);
  DECLARE v_RECUENTO datetime;
  DECLARE v_SALIDA datetime;
  DECLARE v_NUM_SALIDA varchar(20);
  DECLARE v_NUM_ENTRADA varchar(20);
  DECLARE cur CURSOR FOR
    SELECT LINEA_INVLIN, CODIGO_ART_INVLIN, CODIGO_UNIDAD_INVLIN,
           CANTIDAD_TEORICA_INVLIN, CANTIDAD_FISICA_INVLIN,
           PRECIO_MEDIO_INVLIN, PRECIO_MEDIO_NUEVO_INVLIN,
           FECHA_RECUENTO_INVLIN
      FROM fza_inventarios_lineas
     WHERE CODIGO_EMP_INVLIN = p_EMPRESA
       AND CODIGO_ALM_INVLIN = p_ALMACEN
       AND SERIE_INV_INVLIN = p_SERIE
       AND NUMERO_INV_INVLIN = p_NUMERO;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_FIN = 1;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
  SELECT ESTADO_INV,
         TIMESTAMP(DATE_SUB(DATE(FECHA_INV), INTERVAL 1 DAY), '23:59:59')
    INTO v_ESTADO, v_FECHA
    FROM fza_inventarios
   WHERE CODIGO_EMP_INV = p_EMPRESA
     AND CODIGO_ALM_INV = p_ALMACEN
     AND SERIE_INV = p_SERIE
     AND NUMERO_INV = p_NUMERO
   FOR UPDATE;
  IF IFNULL(v_ESTADO, '') <> 'ABIERTO' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El inventario no esta ABIERTO';
  END IF;
  CALL PRC_FZA_INVENTARIOS_CALCULAR_LINEAS(
    p_EMPRESA, p_ALMACEN, p_SERIE, p_NUMERO, p_USUARIO, v_FECHA);
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  OPEN cur;
  bucle: LOOP
    FETCH cur INTO v_LINEA, v_ARTICULO, v_SKU, v_TEORICA, v_FISICA,
                   v_PMP_HIST, v_PMP_NUEVO, v_RECUENTO;
    IF v_FIN = 1 THEN
      LEAVE bucle;
    END IF;
    SET v_RECUENTO = IFNULL(v_RECUENTO, v_FECHA);
    SET v_SALIDA = DATE_SUB(v_RECUENTO, INTERVAL 1 SECOND);
    SET v_NUM_SALIDA = CONCAT('IVS', LEFT(SHA2(CONCAT_WS(CHAR(31),
      p_EMPRESA, p_ALMACEN, p_SERIE, p_NUMERO, v_LINEA), 256), 17));
    SET v_NUM_ENTRADA = CONCAT('IVE', LEFT(SHA2(CONCAT_WS(CHAR(31),
      p_EMPRESA, p_ALMACEN, p_SERIE, p_NUMERO, v_LINEA), 256), 17));
    CALL PRC_FZA_MOVIMIENTOS_ALMACEN_INSERT(
      v_NUM_SALIDA, 'IN', p_SERIE, p_NUMERO, v_LINEA,
      p_EMPRESA, p_ALMACEN, NULL, v_SKU, 'S', v_TEORICA,
      v_PMP_HIST, v_TEORICA * v_PMP_HIST, p_USUARIO,
      p_ALMACEN, NULL, NULL, NULL, v_ARTICULO);
    UPDATE fza_movimientos_almacen
       SET FECHA_MOV = v_SALIDA
     WHERE NUMERO_MOV = v_NUM_SALIDA;
    CALL PRC_FZA_MOVIMIENTOS_ALMACEN_INSERT(
      v_NUM_ENTRADA, 'IN', p_SERIE, p_NUMERO, v_LINEA,
      p_EMPRESA, p_ALMACEN, NULL, v_SKU, 'E', v_FISICA,
      v_PMP_NUEVO, v_FISICA * v_PMP_NUEVO, p_USUARIO,
      p_ALMACEN, NULL, NULL, NULL, v_ARTICULO);
    UPDATE fza_movimientos_almacen
       SET FECHA_MOV = v_RECUENTO
     WHERE NUMERO_MOV = v_NUM_ENTRADA;
    CALL PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR(
      p_EMPRESA, p_ALMACEN, v_SKU, v_SALIDA);
  END LOOP;
  CLOSE cur;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
  UPDATE fza_inventarios
     SET ESTADO_INV = 'APLICADO',
         TOTAL_UNIDADES_DIFERENCIA_INV = (
           SELECT IFNULL(SUM(CANTIDAD_DIFERENCIA_INVLIN), 0)
             FROM fza_inventarios_lineas
            WHERE CODIGO_EMP_INVLIN = p_EMPRESA
              AND CODIGO_ALM_INVLIN = p_ALMACEN
              AND SERIE_INV_INVLIN = p_SERIE
              AND NUMERO_INV_INVLIN = p_NUMERO),
         TOTAL_EUROS_DIFERENCIA_INV = (
           SELECT IFNULL(SUM(TOTAL_COSTE_DIFERENCIA_INVLIN), 0)
             FROM fza_inventarios_lineas
            WHERE CODIGO_EMP_INVLIN = p_EMPRESA
              AND CODIGO_ALM_INVLIN = p_ALMACEN
              AND SERIE_INV_INVLIN = p_SERIE
              AND NUMERO_INV_INVLIN = p_NUMERO),
         USUARIO_MODIF = p_USUARIO,
         INSTANTE_MODIF = NOW()
   WHERE CODIGO_EMP_INV = p_EMPRESA
     AND CODIGO_ALM_INV = p_ALMACEN
     AND SERIE_INV = p_SERIE
     AND NUMERO_INV = p_NUMERO;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_INVENTARIOS_CALCULAR_LINEAS
DROP PROCEDURE IF EXISTS `PRC_FZA_INVENTARIOS_CALCULAR_LINEAS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_INVENTARIOS_CALCULAR_LINEAS`(
  IN p_EMPRESA varchar(10),
  IN p_ALMACEN varchar(10),
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20),
  IN p_USUARIO varchar(100),
  IN p_FECHA_DEFECTO datetime
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_FIN int DEFAULT 0;
  DECLARE v_LINEA varchar(8);
  DECLARE v_SKU varchar(50);
  DECLARE v_FISICA decimal(19,6);
  DECLARE v_PMP_NUEVO decimal(19,6);
  DECLARE v_ES_CORREGIDO varchar(1);
  DECLARE v_RECUENTO datetime;
  DECLARE v_STOCK decimal(19,6);
  DECLARE v_PMP decimal(19,6);
  DECLARE cur CURSOR FOR
    SELECT LINEA_INVLIN, CODIGO_UNIDAD_INVLIN, CANTIDAD_FISICA_INVLIN,
           PRECIO_MEDIO_NUEVO_INVLIN,
           ESPRECIO_MEDIO_CORREGIDO_INVLIN, FECHA_RECUENTO_INVLIN
      FROM fza_inventarios_lineas
     WHERE CODIGO_EMP_INVLIN = p_EMPRESA
       AND CODIGO_ALM_INVLIN = p_ALMACEN
       AND SERIE_INV_INVLIN = p_SERIE
       AND NUMERO_INV_INVLIN = p_NUMERO;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_FIN = 1;
  OPEN cur;
  bucle: LOOP
    FETCH cur INTO v_LINEA, v_SKU, v_FISICA, v_PMP_NUEVO,
                   v_ES_CORREGIDO, v_RECUENTO;
    IF v_FIN = 1 THEN
      LEAVE bucle;
    END IF;
    SET v_RECUENTO = IFNULL(v_RECUENTO, p_FECHA_DEFECTO);
    SELECT IFNULL(SUM(IF(TIPO_MOV = 'E', CANTIDAD_MOV, -CANTIDAD_MOV)), 0)
      INTO v_STOCK
      FROM fza_movimientos_almacen
     WHERE CODIGO_ALM_MOV = p_ALMACEN
       AND CODIGO_UNIDAD_MOV = v_SKU
       AND IFNULL(FECHA_MOV, '1000-01-01 00:00:00') <= v_RECUENTO
       AND ESACTIVO_MOV = 'S';
    SET v_PMP = IFNULL((
      SELECT PRECIO_MEDIO_MOV
        FROM fza_movimientos_almacen
       WHERE CODIGO_ALM_MOV = p_ALMACEN
         AND CODIGO_UNIDAD_MOV = v_SKU
         AND IFNULL(FECHA_MOV, '1000-01-01 00:00:00') <= v_RECUENTO
         AND ESACTIVO_MOV = 'S'
       ORDER BY IFNULL(FECHA_MOV, '1000-01-01 00:00:00') DESC,
                IFNULL(INSTANTE_ALTA, '1000-01-01 00:00:00') DESC,
                NUMERO_MOV DESC
       LIMIT 1), 0);
    IF IFNULL(v_ES_CORREGIDO, 'N') <> 'S' THEN
      SET v_PMP_NUEVO = v_PMP;
    END IF;
    UPDATE fza_inventarios_lineas
       SET CANTIDAD_TEORICA_INVLIN = v_STOCK,
           PRECIO_MEDIO_INVLIN = v_PMP,
           PRECIO_MEDIO_NUEVO_INVLIN = IFNULL(v_PMP_NUEVO, 0),
           CANTIDAD_DIFERENCIA_INVLIN = v_FISICA - v_STOCK,
           TOTAL_COSTE_DIFERENCIA_INVLIN =
             (v_FISICA * IFNULL(v_PMP_NUEVO, 0)) - (v_STOCK * v_PMP),
           FECHA_RECUENTO_INVLIN = v_RECUENTO,
           USUARIO_MODIF = p_USUARIO,
           INSTANTE_MODIF = NOW()
     WHERE CODIGO_EMP_INVLIN = p_EMPRESA
       AND CODIGO_ALM_INVLIN = p_ALMACEN
       AND SERIE_INV_INVLIN = p_SERIE
       AND NUMERO_INV_INVLIN = p_NUMERO
       AND LINEA_INVLIN = v_LINEA;
  END LOOP;
  CLOSE cur;
  UPDATE fza_inventarios i
     SET TOTAL_UNIDADES_DIFERENCIA_INV = (
           SELECT IFNULL(SUM(CANTIDAD_DIFERENCIA_INVLIN), 0)
             FROM fza_inventarios_lineas
            WHERE CODIGO_EMP_INVLIN = p_EMPRESA
              AND CODIGO_ALM_INVLIN = p_ALMACEN
              AND SERIE_INV_INVLIN = p_SERIE
              AND NUMERO_INV_INVLIN = p_NUMERO),
         TOTAL_EUROS_DIFERENCIA_INV = (
           SELECT IFNULL(SUM(TOTAL_COSTE_DIFERENCIA_INVLIN), 0)
             FROM fza_inventarios_lineas
            WHERE CODIGO_EMP_INVLIN = p_EMPRESA
              AND CODIGO_ALM_INVLIN = p_ALMACEN
              AND SERIE_INV_INVLIN = p_SERIE
              AND NUMERO_INV_INVLIN = p_NUMERO),
         USUARIO_MODIF = p_USUARIO,
         INSTANTE_MODIF = NOW()
   WHERE CODIGO_EMP_INV = p_EMPRESA
     AND CODIGO_ALM_INV = p_ALMACEN
     AND SERIE_INV = p_SERIE
     AND NUMERO_INV = p_NUMERO;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_INVENTARIOS_ELIMINAR_REGUL
DROP PROCEDURE IF EXISTS `PRC_FZA_INVENTARIOS_ELIMINAR_REGUL`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_INVENTARIOS_ELIMINAR_REGUL`(
  IN p_EMPRESA varchar(10),
  IN p_ALMACEN varchar(10),
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20),
  IN p_USUARIO varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_ESTADO varchar(20);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
  SELECT ESTADO_INV INTO v_ESTADO
    FROM fza_inventarios
   WHERE CODIGO_EMP_INV = p_EMPRESA
     AND CODIGO_ALM_INV = p_ALMACEN
     AND SERIE_INV = p_SERIE
     AND NUMERO_INV = p_NUMERO
   FOR UPDATE;
  IF IFNULL(v_ESTADO, '') <> 'APLICADO' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El inventario no esta APLICADO';
  END IF;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_DOCUMENTO(
    'IN', p_SERIE, p_NUMERO);
  DELETE FROM fza_movimientos_almacen
   WHERE TIPO_DOC_MOV = 'IN'
     AND SERIE_DOC_MOV = p_SERIE
     AND NUMERO_DOC_MOV = p_NUMERO;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
  UPDATE fza_inventarios
     SET ESTADO_INV = 'ABIERTO',
         USUARIO_MODIF = p_USUARIO,
         INSTANTE_MODIF = NOW()
   WHERE CODIGO_EMP_INV = p_EMPRESA
     AND CODIGO_ALM_INV = p_ALMACEN
     AND SERIE_INV = p_SERIE
     AND NUMERO_INV = p_NUMERO;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_ALMACEN_DELETE
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_ALMACEN_DELETE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_ALMACEN_DELETE`(
  IN p_NUMERO_MOV varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT IFNULL(CODIGO_EMP_MOV, ''), CODIGO_ALM_MOV, CODIGO_UNIDAD_MOV,
         IFNULL(FECHA_MOV, '1000-01-01 00:00:00')
    FROM fza_movimientos_almacen
   WHERE NUMERO_MOV = p_NUMERO_MOV;
  DELETE FROM fza_movimientos_almacen WHERE NUMERO_MOV = p_NUMERO_MOV;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_ALMACEN_UPDATE
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_ALMACEN_UPDATE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_ALMACEN_UPDATE`(
  IN p_NUMERO_MOV varchar(20),
  IN p_NUEVA_CANTIDAD decimal(19,6),
  IN p_NUEVO_PRECIO decimal(19,6),
  IN p_USUARIO varchar(100)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT IFNULL(CODIGO_EMP_MOV, ''), CODIGO_ALM_MOV, CODIGO_UNIDAD_MOV,
         IFNULL(FECHA_MOV, '1000-01-01 00:00:00')
    FROM fza_movimientos_almacen
   WHERE NUMERO_MOV = p_NUMERO_MOV;
  UPDATE fza_movimientos_almacen
     SET CANTIDAD_MOV = p_NUEVA_CANTIDAD,
         PRECIO_COSTE_UNITARIO_MOV = p_NUEVO_PRECIO,
         USUARIO_MODIF = p_USUARIO,
         INSTANTE_MODIF = NOW()
   WHERE NUMERO_MOV = p_NUMERO_MOV;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULAR_DOCUMENTO
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULAR_DOCUMENTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULAR_DOCUMENTO`(
  IN p_TIPO varchar(5),
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_DOCUMENTO(
    p_TIPO, p_SERIE, p_NUMERO);
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULAR_MOVIMIENTO
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULAR_MOVIMIENTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULAR_MOVIMIENTO`(
  IN p_NUMERO varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT IFNULL(CODIGO_EMP_MOV, ''), CODIGO_ALM_MOV, CODIGO_UNIDAD_MOV,
         IFNULL(FECHA_MOV, '1000-01-01 00:00:00')
    FROM fza_movimientos_almacen
   WHERE NUMERO_MOV = p_NUMERO;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULAR_OPERACION
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULAR_OPERACION`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULAR_OPERACION`(
  IN p_OPERACION varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_OPERACION(p_OPERACION);
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_ACTUALIZAR_STOCK
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_ACTUALIZAR_STOCK`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_ACTUALIZAR_STOCK`()
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_recalculo_final;
  CREATE TEMPORARY TABLE tmp_recalculo_final (
    almacen varchar(10) NOT NULL,
    sku varchar(50) NOT NULL,
    stock_final decimal(19,6) NOT NULL,
    pmp_final decimal(19,6) NOT NULL,
    PRIMARY KEY (almacen, sku)
  ) ENGINE=InnoDB;
  INSERT INTO tmp_recalculo_final (
    almacen,
    sku,
    stock_final,
    pmp_final
  )
  SELECT S.almacen,
         S.sku,
         IFNULL(O.stock_nuevo, S.stock_semilla),
         IFNULL(O.pmp_nuevo, S.pmp_semilla)
    FROM tmp_recalculo_semillas S
    LEFT JOIN (
      SELECT X.almacen,
             X.sku,
             X.stock_nuevo,
             X.pmp_nuevo
        FROM tmp_movimientos_ordenados X
        JOIN (
          SELECT almacen,
                 sku,
                 MAX(rn) AS rn
            FROM tmp_movimientos_ordenados
           GROUP BY almacen, sku
        ) U ON U.rn = X.rn
    ) O ON O.almacen = S.almacen
       AND O.sku = S.sku;
  INSERT INTO fza_articulos_stockactual (
    CODIGO_ALM_STK,
    CODIGO_UNIDAD_STK,
    CANTIDAD_STK,
    VALOR_TOTAL_STK,
    PRECIO_MEDIO_STK,
    INSTANTE_MODIF,
    CANTIDAD_ENT_COMPRA_STK,
    CANTIDAD_ENT_TRASPASO_STK,
    CANTIDAD_SAL_TRASPASO_STK,
    CANTIDAD_ENT_DEPOSITO_STK,
    CANTIDAD_SAL_DEPOSITO_STK,
    CANTIDAD_SAL_VENTA_STK,
    CANTIDAD_ENT_REGULAR_STK,
    CANTIDAD_SAL_ALBVENTA_STK,
    CANTIDAD_ENT_ALBENTRADA_STK
  )
  SELECT F.almacen,
         F.sku,
         F.stock_final,
         IF(F.stock_final > 0, F.stock_final * F.pmp_final, 0),
         IF(F.stock_final > 0, F.pmp_final, 0),
         NOW(),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV = 'AC' AND M.TIPO_MOV = 'E',
           M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV IN ('TR', 'AT', 'TA') AND
           M.TIPO_MOV = 'E', M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV IN ('TR', 'AT', 'TA') AND
           M.TIPO_MOV = 'S', M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV = 'DP' AND M.TIPO_MOV = 'E',
           M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV = 'DP' AND M.TIPO_MOV = 'S',
           M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV IN ('VE', 'FC') AND
           M.TIPO_MOV = 'S', M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV = 'IN' AND M.TIPO_MOV = 'E',
           M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV = 'AV' AND M.TIPO_MOV = 'S',
           M.CANTIDAD_MOV, 0)), 0),
         IFNULL(SUM(IF(M.TIPO_DOC_MOV = 'AE' AND M.TIPO_MOV = 'E',
           M.CANTIDAD_MOV, 0)), 0)
    FROM tmp_recalculo_final F
    LEFT JOIN fza_movimientos_almacen M
      ON M.CODIGO_ALM_MOV = F.almacen
     AND M.CODIGO_UNIDAD_MOV = F.sku
     AND M.ESACTIVO_MOV = 'S'
   GROUP BY F.almacen, F.sku, F.stock_final, F.pmp_final
  ON DUPLICATE KEY UPDATE
    CANTIDAD_STK = VALUES(CANTIDAD_STK),
    VALOR_TOTAL_STK = VALUES(VALOR_TOTAL_STK),
    PRECIO_MEDIO_STK = VALUES(PRECIO_MEDIO_STK),
    INSTANTE_MODIF = NOW(),
    CANTIDAD_ENT_COMPRA_STK = VALUES(CANTIDAD_ENT_COMPRA_STK),
    CANTIDAD_ENT_TRASPASO_STK = VALUES(CANTIDAD_ENT_TRASPASO_STK),
    CANTIDAD_SAL_TRASPASO_STK = VALUES(CANTIDAD_SAL_TRASPASO_STK),
    CANTIDAD_ENT_DEPOSITO_STK = VALUES(CANTIDAD_ENT_DEPOSITO_STK),
    CANTIDAD_SAL_DEPOSITO_STK = VALUES(CANTIDAD_SAL_DEPOSITO_STK),
    CANTIDAD_SAL_VENTA_STK = VALUES(CANTIDAD_SAL_VENTA_STK),
    CANTIDAD_ENT_REGULAR_STK = VALUES(CANTIDAD_ENT_REGULAR_STK),
    CANTIDAD_SAL_ALBVENTA_STK = VALUES(CANTIDAD_SAL_ALBVENTA_STK),
    CANTIDAD_ENT_ALBENTRADA_STK = VALUES(CANTIDAD_ENT_ALBENTRADA_STK);
  CALL PRC_PRESTASHOP_ENCOLAR_STOCK_RECALCULO('');
  DROP TEMPORARY TABLE IF EXISTS tmp_recalculo_final;
  DROP TEMPORARY TABLE IF EXISTS tmp_movimientos_ordenados;
  DROP TEMPORARY TABLE IF EXISTS tmp_recalculo_semillas;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_CALCULAR_COLA
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_CALCULAR_COLA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_CALCULAR_COLA`()
SQL SECURITY INVOKER
BEGIN
  SET @clave_previa := '';
  SET @stock := CAST(0 AS DECIMAL(19,6));
  SET @pmp := CAST(0 AS DECIMAL(19,6));
  UPDATE tmp_movimientos_ordenados
     SET cantidad = IF(es_cierre_inventario = 'S' AND tipo_mov = 'S',
           IF(@clave_previa <> clave, stock_semilla, @stock), cantidad),
         coste_unitario = IF(es_cierre_inventario = 'S' AND
                              tipo_mov = 'E' AND es_pmp_manual <> 'S',
           IF(@clave_previa <> clave, pmp_semilla, @pmp), coste_unitario),
         pmp_nuevo = (@pmp := IF(
           @clave_previa <> clave,
           IF(tipo_mov = 'E',
              IF(stock_semilla <= 0, coste_unitario,
                 IF(stock_semilla + cantidad = 0, coste_unitario,
                    ((stock_semilla * pmp_semilla) +
                     (cantidad * coste_unitario)) /
                    (stock_semilla + cantidad))),
              pmp_semilla),
           IF(tipo_mov = 'E',
              IF(@stock <= 0, coste_unitario,
                 IF(@stock + cantidad = 0, coste_unitario,
                    ((@stock * @pmp) + (cantidad * coste_unitario)) /
                    (@stock + cantidad))),
              @pmp))),
         coste_nuevo = IF(tipo_mov = 'E', cantidad * coste_unitario,
                                           cantidad * @pmp),
         stock_nuevo = (@stock := IF(
           @clave_previa <> clave,
           stock_semilla + IF(tipo_mov = 'E', cantidad, -cantidad),
           @stock + IF(tipo_mov = 'E', cantidad, -cantidad))),
         clave_previa = (@clave_previa := clave)
   ORDER BY rn;
  UPDATE fza_movimientos_almacen m
  JOIN tmp_movimientos_ordenados o ON o.numero_mov = m.NUMERO_MOV
     SET m.CANTIDAD_MOV = o.cantidad,
         m.PRECIO_COSTE_UNITARIO_MOV = IF(
           o.es_cierre_inventario = 'S',
           IF(o.tipo_mov = 'S', o.pmp_nuevo, o.coste_unitario),
           m.PRECIO_COSTE_UNITARIO_MOV),
         m.PRECIO_MEDIO_MOV = o.pmp_nuevo,
         m.TOTAL_COSTE_MOV = o.coste_nuevo,
         m.INSTANTE_MODIF = NOW();
  UPDATE fza_inventarios_lineas l
  JOIN fza_inventarios i
    ON i.CODIGO_EMP_INV = l.CODIGO_EMP_INVLIN
   AND i.CODIGO_ALM_INV = l.CODIGO_ALM_INVLIN
   AND i.SERIE_INV = l.SERIE_INV_INVLIN
   AND i.NUMERO_INV = l.NUMERO_INV_INVLIN
  JOIN fza_movimientos_almacen s
    ON s.TIPO_DOC_MOV = 'IN'
   AND s.TIPO_MOV = 'S'
   AND s.CODIGO_ALM_MOV = l.CODIGO_ALM_INVLIN
   AND s.SERIE_DOC_MOV = l.SERIE_INV_INVLIN
   AND s.NUMERO_DOC_MOV = l.NUMERO_INV_INVLIN
   AND CAST(s.LINEA_MOV AS UNSIGNED) = CAST(l.LINEA_INVLIN AS UNSIGNED)
  JOIN tmp_movimientos_ordenados o
    ON o.numero_mov = s.NUMERO_MOV
   AND o.es_cierre_inventario = 'S'
  LEFT JOIN fza_movimientos_almacen e
    ON e.TIPO_DOC_MOV = 'IN'
   AND e.TIPO_MOV = 'E'
   AND e.CODIGO_ALM_MOV = l.CODIGO_ALM_INVLIN
   AND e.SERIE_DOC_MOV = l.SERIE_INV_INVLIN
   AND e.NUMERO_DOC_MOV = l.NUMERO_INV_INVLIN
   AND CAST(e.LINEA_MOV AS UNSIGNED) = CAST(l.LINEA_INVLIN AS UNSIGNED)
     SET l.CANTIDAD_TEORICA_INVLIN = s.CANTIDAD_MOV,
         l.PRECIO_MEDIO_INVLIN = s.PRECIO_MEDIO_MOV,
         l.PRECIO_MEDIO_NUEVO_INVLIN = IF(
           l.ESPRECIO_MEDIO_CORREGIDO_INVLIN = 'S',
           l.PRECIO_MEDIO_NUEVO_INVLIN,
           IFNULL(e.PRECIO_COSTE_UNITARIO_MOV, s.PRECIO_MEDIO_MOV)),
         l.CANTIDAD_DIFERENCIA_INVLIN =
           l.CANTIDAD_FISICA_INVLIN - s.CANTIDAD_MOV,
         l.TOTAL_COSTE_DIFERENCIA_INVLIN =
           (l.CANTIDAD_FISICA_INVLIN * IF(
             l.ESPRECIO_MEDIO_CORREGIDO_INVLIN = 'S',
             l.PRECIO_MEDIO_NUEVO_INVLIN,
             IFNULL(e.PRECIO_COSTE_UNITARIO_MOV, s.PRECIO_MEDIO_MOV))) -
           (s.CANTIDAD_MOV * s.PRECIO_MEDIO_MOV),
         l.INSTANTE_MODIF = NOW()
   WHERE i.ESTADO_INV = 'APLICADO' OR i.ESTADO_INV = 'ABIERTO';
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR`()
SQL SECURITY INVOKER
BEGIN
  DECLARE v_CAMBIOS int DEFAULT 1;
  DECLARE v_PASADAS int DEFAULT 0;
  WHILE EXISTS(SELECT 1 FROM tmp_movimientos_recalculo) AND
        v_CAMBIOS > 0 AND v_PASADAS < 100 DO
    CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PASADA();
    CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PROPAGAR(v_CAMBIOS);
    SET v_PASADAS = v_PASADAS + 1;
  END WHILE;
  IF v_PASADAS >= 100 AND
     EXISTS(SELECT 1 FROM tmp_movimientos_recalculo) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
        'No converge la propagacion cronologica de traspasos';
  END IF;
  DROP TEMPORARY TABLE IF EXISTS tmp_movimientos_recalculo;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR`(
  IN p_EMPRESA varchar(20),
  IN p_ALMACEN varchar(10),
  IN p_SKU varchar(50),
  IN p_INSTANTE_DESDE datetime
)
SQL SECURITY INVOKER
BEGIN
  IF IFNULL(p_ALMACEN, '') <> '' AND IFNULL(p_SKU, '') <> '' THEN
    INSERT INTO tmp_movimientos_recalculo
      (empresa, almacen, sku, instante_desde)
    VALUES
      (IFNULL(p_EMPRESA, ''), p_ALMACEN, p_SKU,
       IFNULL(p_INSTANTE_DESDE, '1000-01-01 00:00:00'))
    ON DUPLICATE KEY UPDATE
      empresa = IF(empresa = '', VALUES(empresa), empresa),
      instante_desde = LEAST(instante_desde, VALUES(instante_desde));
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_DOCUMENTO
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_DOCUMENTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_DOCUMENTO`(
  IN p_TIPO varchar(5),
  IN p_SERIE varchar(20),
  IN p_NUMERO varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT MIN(IFNULL(CODIGO_EMP_MOV, '')),
         CODIGO_ALM_MOV,
         CODIGO_UNIDAD_MOV,
         MIN(IFNULL(FECHA_MOV, '1000-01-01 00:00:00'))
    FROM fza_movimientos_almacen
   WHERE TIPO_DOC_MOV = p_TIPO
     AND SERIE_DOC_MOV = p_SERIE
     AND NUMERO_DOC_MOV = p_NUMERO
   GROUP BY CODIGO_ALM_MOV, CODIGO_UNIDAD_MOV
  ON DUPLICATE KEY UPDATE
    empresa = IF(empresa = '', VALUES(empresa), empresa),
    instante_desde = LEAST(instante_desde, VALUES(instante_desde));
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_OPERACION
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_OPERACION`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR_OPERACION`(
  IN p_OPERACION varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT MIN(IFNULL(CODIGO_EMP_MOV, '')),
         CODIGO_ALM_MOV,
         CODIGO_UNIDAD_MOV,
         MIN(IFNULL(FECHA_MOV, '1000-01-01 00:00:00'))
    FROM fza_movimientos_almacen
   WHERE NUMERO_OPERACION_DOC_MOV = p_OPERACION
   GROUP BY CODIGO_ALM_MOV, CODIGO_UNIDAD_MOV
  ON DUPLICATE KEY UPDATE
    empresa = IF(empresa = '', VALUES(empresa), empresa),
    instante_desde = LEAST(instante_desde, VALUES(instante_desde));
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_PASADA
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_PASADA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_PASADA`()
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR_COLA();
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_CALCULAR_COLA();
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_ACTUALIZAR_STOCK();
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR`()
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_movimientos_recalculo;
  CREATE TEMPORARY TABLE tmp_movimientos_recalculo (
    empresa varchar(20) NOT NULL DEFAULT '',
    almacen varchar(10) NOT NULL,
    sku varchar(50) NOT NULL,
    instante_desde datetime NOT NULL,
    PRIMARY KEY (almacen, sku)
  ) ENGINE=InnoDB;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR_COLA
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR_COLA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR_COLA`()
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_recalculo_semillas;
  CREATE TEMPORARY TABLE tmp_recalculo_semillas (
    almacen varchar(10) NOT NULL,
    sku varchar(50) NOT NULL,
    instante_desde datetime NOT NULL,
    stock_semilla decimal(19,6) NOT NULL DEFAULT 0,
    pmp_semilla decimal(19,6) NOT NULL DEFAULT 0,
    PRIMARY KEY (almacen, sku)
  ) ENGINE=InnoDB;
  INSERT INTO tmp_recalculo_semillas
    (almacen, sku, instante_desde, stock_semilla)
  SELECT r.almacen,
         r.sku,
         r.instante_desde,
         IFNULL(SUM(IF(m.TIPO_MOV = 'E', m.CANTIDAD_MOV,
                                         -m.CANTIDAD_MOV)), 0)
    FROM tmp_movimientos_recalculo r
    LEFT JOIN fza_movimientos_almacen m
      ON m.CODIGO_ALM_MOV = r.almacen
     AND m.CODIGO_UNIDAD_MOV = r.sku
     AND m.ESACTIVO_MOV = 'S'
     AND IFNULL(m.FECHA_MOV, '1000-01-01 00:00:00') < r.instante_desde
   GROUP BY r.almacen, r.sku, r.instante_desde;
  UPDATE tmp_recalculo_semillas s
     SET s.pmp_semilla = IFNULL((
       SELECT m.PRECIO_MEDIO_MOV
         FROM fza_movimientos_almacen m
        WHERE m.CODIGO_ALM_MOV = s.almacen
          AND m.CODIGO_UNIDAD_MOV = s.sku
          AND m.ESACTIVO_MOV = 'S'
          AND IFNULL(m.FECHA_MOV, '1000-01-01 00:00:00') <
              s.instante_desde
        ORDER BY IFNULL(m.FECHA_MOV, '1000-01-01 00:00:00') DESC,
                 IFNULL(m.INSTANTE_ALTA, '1000-01-01 00:00:00') DESC,
                 m.NUMERO_MOV DESC
        LIMIT 1), 0);
  DROP TEMPORARY TABLE IF EXISTS tmp_movimientos_ordenados;
  CREATE TEMPORARY TABLE tmp_movimientos_ordenados (
    rn bigint NOT NULL AUTO_INCREMENT,
    numero_mov varchar(20) NOT NULL,
    almacen varchar(10) NOT NULL,
    sku varchar(50) NOT NULL,
    clave varchar(101) NOT NULL,
    tipo_doc varchar(5) NOT NULL,
    tipo_mov varchar(1) NOT NULL,
    cantidad decimal(19,6) NOT NULL,
    coste_unitario decimal(19,6) NOT NULL,
    es_cierre_inventario varchar(1) NOT NULL DEFAULT 'N',
    es_pmp_manual varchar(1) NOT NULL DEFAULT 'N',
    stock_semilla decimal(19,6) NOT NULL,
    pmp_semilla decimal(19,6) NOT NULL,
    stock_nuevo decimal(19,6) NOT NULL DEFAULT 0,
    pmp_nuevo decimal(19,6) NOT NULL DEFAULT 0,
    coste_nuevo decimal(19,6) NOT NULL DEFAULT 0,
    clave_previa varchar(101) NULL,
    PRIMARY KEY (rn),
    KEY idx_movimiento (numero_mov),
    KEY idx_clave (almacen, sku)
  ) ENGINE=InnoDB;
  INSERT INTO tmp_movimientos_ordenados
    (numero_mov, almacen, sku, clave, tipo_doc, tipo_mov, cantidad,
     coste_unitario, es_cierre_inventario, es_pmp_manual,
     stock_semilla, pmp_semilla)
  SELECT m.NUMERO_MOV,
         m.CODIGO_ALM_MOV,
         m.CODIGO_UNIDAD_MOV,
         CONCAT(m.CODIGO_ALM_MOV, CHAR(31), m.CODIGO_UNIDAD_MOV),
         m.TIPO_DOC_MOV,
         m.TIPO_MOV,
         IFNULL(m.CANTIDAD_MOV, 0),
         IFNULL(m.PRECIO_COSTE_UNITARIO_MOV, 0),
         IF(i.NUMERO_INV IS NULL, 'N', 'S'),
         IFNULL(l.ESPRECIO_MEDIO_CORREGIDO_INVLIN, 'N'),
         s.stock_semilla,
         s.pmp_semilla
    FROM fza_movimientos_almacen m
    JOIN tmp_recalculo_semillas s
     ON s.almacen = m.CODIGO_ALM_MOV
     AND s.sku = m.CODIGO_UNIDAD_MOV
    LEFT JOIN fza_inventarios i
      ON m.TIPO_DOC_MOV = 'IN'
     AND i.CODIGO_ALM_INV = m.CODIGO_ALM_MOV
     AND i.SERIE_INV = m.SERIE_DOC_MOV
     AND i.NUMERO_INV = m.NUMERO_DOC_MOV
    LEFT JOIN fza_inventarios_lineas l
      ON l.CODIGO_EMP_INVLIN = i.CODIGO_EMP_INV
     AND l.CODIGO_ALM_INVLIN = i.CODIGO_ALM_INV
     AND l.SERIE_INV_INVLIN = i.SERIE_INV
     AND l.NUMERO_INV_INVLIN = i.NUMERO_INV
     AND CAST(l.LINEA_INVLIN AS UNSIGNED) =
         CAST(m.LINEA_MOV AS UNSIGNED)
   WHERE m.ESACTIVO_MOV = 'S'
     AND IFNULL(m.FECHA_MOV, '1000-01-01 00:00:00') >= s.instante_desde
   ORDER BY m.CODIGO_ALM_MOV,
            m.CODIGO_UNIDAD_MOV,
            IFNULL(m.FECHA_MOV, '1000-01-01 00:00:00'),
            IFNULL(m.INSTANTE_ALTA, '1000-01-01 00:00:00'),
            m.NUMERO_MOV;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_MOVIMIENTOS_RECALCULO_PROPAGAR
DROP PROCEDURE IF EXISTS `PRC_FZA_MOVIMIENTOS_RECALCULO_PROPAGAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_MOVIMIENTOS_RECALCULO_PROPAGAR`(
  OUT p_CAMBIOS int
)
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_traspasos_propagar;
  CREATE TEMPORARY TABLE tmp_traspasos_propagar (
    numero_entrada varchar(20) NOT NULL,
    empresa varchar(20) NOT NULL,
    almacen varchar(10) NOT NULL,
    sku varchar(50) NOT NULL,
    instante_desde datetime NOT NULL,
    coste_salida decimal(19,6) NOT NULL,
    PRIMARY KEY (numero_entrada)
  ) ENGINE=InnoDB;
  INSERT INTO tmp_traspasos_propagar
    (numero_entrada, empresa, almacen, sku, instante_desde, coste_salida)
  SELECT e.NUMERO_MOV,
         IFNULL(e.CODIGO_EMP_MOV, ''),
         e.CODIGO_ALM_MOV,
         e.CODIGO_UNIDAD_MOV,
         IFNULL(e.FECHA_MOV, '1000-01-01 00:00:00'),
         SUM(s.TOTAL_COSTE_MOV) / NULLIF(SUM(s.CANTIDAD_MOV), 0)
    FROM tmp_movimientos_recalculo r
    JOIN fza_movimientos_almacen s
      ON s.CODIGO_ALM_MOV = r.almacen
     AND s.CODIGO_UNIDAD_MOV = r.sku
     AND s.ESACTIVO_MOV = 'S'
     AND s.TIPO_DOC_MOV IN ('TR', 'AT', 'TA')
     AND s.TIPO_MOV = 'S'
     AND IFNULL(s.FECHA_MOV, '1000-01-01 00:00:00') >= r.instante_desde
    JOIN fza_movimientos_almacen e
      ON e.TIPO_DOC_MOV = s.TIPO_DOC_MOV
     AND e.SERIE_DOC_MOV = s.SERIE_DOC_MOV
     AND e.NUMERO_DOC_MOV = s.NUMERO_DOC_MOV
     AND e.CODIGO_UNIDAD_MOV = s.CODIGO_UNIDAD_MOV
     AND e.CODIGO_ALM_MOV = s.CODIGO_ALM_CONTRA_MOV
     AND e.CODIGO_ALM_CONTRA_MOV = s.CODIGO_ALM_MOV
     AND e.ESACTIVO_MOV = 'S'
     AND e.TIPO_MOV = 'E'
     AND (e.LINEA_MOV = s.LINEA_MOV OR
          (IFNULL(e.NUMERO_OPERACION_DOC_MOV, '') <> '' AND
           e.NUMERO_OPERACION_DOC_MOV = s.NUMERO_OPERACION_DOC_MOV))
   GROUP BY e.NUMERO_MOV, e.CODIGO_EMP_MOV, e.CODIGO_ALM_MOV,
            e.CODIGO_UNIDAD_MOV, e.FECHA_MOV,
            e.PRECIO_COSTE_UNITARIO_MOV
  HAVING ABS(IFNULL(e.PRECIO_COSTE_UNITARIO_MOV, 0) -
         (SUM(s.TOTAL_COSTE_MOV) / NULLIF(SUM(s.CANTIDAD_MOV), 0))) >
         0.0000005;
  SELECT COUNT(*) INTO p_CAMBIOS FROM tmp_traspasos_propagar;
  UPDATE fza_movimientos_almacen e
  JOIN tmp_traspasos_propagar p ON p.numero_entrada = e.NUMERO_MOV
     SET e.PRECIO_COSTE_UNITARIO_MOV = p.coste_salida,
         e.INSTANTE_MODIF = NOW();
  DELETE FROM tmp_movimientos_recalculo;
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT MIN(empresa), almacen, sku, MIN(instante_desde)
    FROM tmp_traspasos_propagar
   GROUP BY almacen, sku;
  DROP TEMPORARY TABLE IF EXISTS tmp_traspasos_propagar;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_FZA_STOCK_BLOQUEAR_CLAVE
DROP PROCEDURE IF EXISTS `PRC_FZA_STOCK_BLOQUEAR_CLAVE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_FZA_STOCK_BLOQUEAR_CLAVE`(
  IN p_CODIGO_ALMACEN varchar(10),
  IN p_CODIGO_UNIDAD varchar(50),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  IF NULLIF(TRIM(p_CODIGO_ALMACEN), '') IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No se puede bloquear stock sin almacen';
  END IF;
  IF NULLIF(TRIM(p_CODIGO_UNIDAD), '') IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No se puede bloquear stock sin SKU';
  END IF;
  INSERT INTO `fza_stock_bloqueos` (
    `CODIGO_ALM_STKBLQ`, `CODIGO_UNIDAD_STKBLQ`,
    `INSTANTE_ALTA`, `USUARIO_ALTA`,
    `INSTANTE_MODIF`, `USUARIO_MODIF`
  ) VALUES (
    p_CODIGO_ALMACEN, p_CODIGO_UNIDAD,
    NOW(), LEFT(COALESCE(NULLIF(TRIM(p_USUARIO), ''), 'SISTEMA'), 50),
    NULL, NULL
  )
  ON DUPLICATE KEY UPDATE
    `CODIGO_ALM_STKBLQ` = VALUES(`CODIGO_ALM_STKBLQ`);
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GENERAR_CODIGO_VALE
DROP PROCEDURE IF EXISTS `PRC_GENERAR_CODIGO_VALE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GENERAR_CODIGO_VALE`(IN pEmpresa VARCHAR(10),
    IN pAlmacen VARCHAR(10),
    IN pCaja VARCHAR(10),
    IN pNumOperacion VARCHAR(20),
    IN pUsuario VARCHAR(100),
    OUT pCodigoFinal VARCHAR(100))
SQL SECURITY INVOKER
BEGIN
    /* DECLARE vContador VARCHAR(20); */
    
    /* 1. Obtenemos el contador secuencial (Le pasamos 'VL' y el Usuario) */
    /* CALL PRC_GET_NEXT_CONT('VL', pUsuario, vContador); */
    
    /* 2. Construimos el código final concatenando todo */
    /* Resultado ejemplo: 00014_VL_1_ALM01_CAJ1_4509 */
    SET pCodigoFinal = CONCAT(pEmpresa, '_', pAlmacen, '_', pCaja, '_', pNumOperacion);
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GETPERFILFORMULARIO
DROP PROCEDURE IF EXISTS `PRC_GETPERFILFORMULARIO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GETPERFILFORMULARIO`(IN `p_usuario` VARCHAR(200),
    IN `p_grupo` VARCHAR(200),
    IN `p_formulario` VARCHAR(100))
SQL SECURITY INVOKER
BEGIN
    /* Usamos una CTE para calcular la prioridad y luego filtrar */
    WITH perfiles_con_prioridad AS (
        SELECT 
            USUARIO_GRUPO_USUPER,
            KEY_USUPER,
            SUBKEY_USUPER,
            VALUE_USUPER,
            VALUE_TEXT_USUPER,
            TYPE_BLOB_USUPER,
            VALUE_BLOB_USUPER,
            CASE USUARIO_GRUPO_USUPER
                WHEN p_usuario THEN 1
                WHEN p_grupo   THEN 2
                WHEN 'Todos'   THEN 3
            END AS prioridad,
            ROW_NUMBER() OVER (
                PARTITION BY SUBKEY_USUPER 
                ORDER BY CASE USUARIO_GRUPO_USUPER
                    WHEN p_usuario THEN 1
                    WHEN p_grupo   THEN 2
                    WHEN 'Todos'   THEN 3
                END
            ) AS rn
        FROM fza_usuarios_perfiles
        WHERE KEY_USUPER = p_formulario 
          AND USUARIO_GRUPO_USUPER IN (p_usuario, p_grupo, 'Todos')
    )
    SELECT 
        USUARIO_GRUPO_USUPER,
        KEY_USUPER,
        SUBKEY_USUPER,
        VALUE_USUPER,
        VALUE_TEXT_USUPER,
        TYPE_BLOB_USUPER,
        VALUE_BLOB_USUPER
    FROM perfiles_con_prioridad
    WHERE rn = 1
    ORDER BY SUBKEY_USUPER;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_BALANCE_ALMACEN_SIN_TALLAS
DROP PROCEDURE IF EXISTS `PRC_GET_BALANCE_ALMACEN_SIN_TALLAS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_BALANCE_ALMACEN_SIN_TALLAS`(
    IN `p_MODO`         VARCHAR(1),   /* 'F' entre fechas, 'A' por acumulados */
    IN `p_DESDE`        DATE,         /* inclusive (solo modo 'F') */
    IN `p_HASTA`        DATE,         /* inclusive (solo modo 'F') */
    IN `p_ALMACENES`    TEXT,         /* CSV "01,50" o '' = todos los activos */
    IN `p_FAMILIAS`     TEXT,         /* CSV; '' = todas. Una padre incluye sus hijas */
    IN `p_PROVEEDORES`  TEXT,         /* CSV de códigos de proveedor; '' = todos */
    IN `p_TEMPORADAS`   TEXT,         /* CSV de valores de temporada; '' = todas */
    IN `p_ARTICULOS`    TEXT,         /* CSV de códigos de artículo; '' = todos */
    IN `p_COD_TARIFA`   VARCHAR(20),  /* tarifa para valorar ventas/salidas */
    IN `p_DESGLOSADO`   VARCHAR(1),   /* 'S'/'N' (solo aplica a modo 'F') */
    IN `p_BANDAS`       TEXT,         /* CSV de códigos de banda; '' = todas */
    IN `p_NIVEL1`       VARCHAR(3),   /* 1er nivel de agrupación: PRV/FAM/TMP/ALM/'' */
    IN `p_NIVEL2`       VARCHAR(3),   /* 2o nivel de agrupación */
    IN `p_NIVEL3`       VARCHAR(3),   /* 3er nivel de agrupación */
    IN `p_NIVEL_FAM`    INT           /* nivel del árbol de familias al agrupar */
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_alms      TEXT;
    DECLARE v_tarifa    VARCHAR(20);
    DECLARE v_desde     DATE;
    DECLARE v_hasta     DATE;
    DECLARE v_por_alm   BOOLEAN DEFAULT FALSE;  /* TRUE si se agrupa por almacén */
    DECLARE v_nivel_fam INT;                    /* nivel efectivo del árbol fam. */
    /* Normalización de parámetros. */
    SET p_MODO       = IFNULL(NULLIF(p_MODO, ''), 'A');
    SET p_DESGLOSADO  = IFNULL(NULLIF(p_DESGLOSADO, ''), 'N');
    SET p_FAMILIAS    = IFNULL(p_FAMILIAS, '');
    SET p_PROVEEDORES = IFNULL(p_PROVEEDORES, '');
    SET p_TEMPORADAS  = IFNULL(p_TEMPORADAS, '');
    SET p_ARTICULOS   = IFNULL(p_ARTICULOS, '');
    SET p_BANDAS      = IFNULL(p_BANDAS, '');
    /* Niveles de agrupación: normalizados a mayúsculas. Se admiten PRV */
    /* (proveedor), FAM (familia), TMP (temporada) y ALM (almacén); cualquier */
    /* otro valor (o vacío) deshabilita ese nivel. */
    SET p_NIVEL1      = UPPER(IFNULL(p_NIVEL1, ''));
    SET p_NIVEL2      = UPPER(IFNULL(p_NIVEL2, ''));
    SET p_NIVEL3      = UPPER(IFNULL(p_NIVEL3, ''));
    SET v_por_alm     = (p_NIVEL1 = 'ALM' OR p_NIVEL2 = 'ALM' OR p_NIVEL3 = 'ALM');
    SET v_nivel_fam   = IF(IFNULL(p_NIVEL_FAM, 0) < 1, 9999, p_NIVEL_FAM);
    SET v_tarifa      = IFNULL(NULLIF(p_COD_TARIFA, ''), 'PVP');
    SET v_desde      = IFNULL(p_DESDE, '1900-01-01');
    SET v_hasta      = IFNULL(p_HASTA, CURRENT_DATE);
    /* Almacenes efectivos en una tabla temporal INDEXADA (PK), para filtrar */
    /* por IN en vez de FIND_IN_SET sobre las tablas grandes (no es sargable y */
    /* obliga a escanear; fza_articulos_stockactual tiene CODIGO_ALM_STK como */
    /* 1ª columna del PK). Sin selección = todos los almacenes activos. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_alm`;
    CREATE TEMPORARY TABLE `tmp_bst_alm` (
        `CODIGO_ALM` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bst_alm` (`CODIGO_ALM`)
    SELECT `CODIGO_ALM_ALM` FROM `fza_almacenes`
     WHERE IF(IFNULL(p_ALMACENES, '') = '',
              `ESACTIVO_ALM` = 'S',
              FIND_IN_SET(`CODIGO_ALM_ALM`, p_ALMACENES));

    /* ----------------------------------------------------------------- */
    /* Filtros de artículo (familias con descendencia, proveedores, */
    /* temporadas) + mapa de familia por nivel del árbol. Igual que el */
    /* balance por tallas. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_fam`;
    CREATE TEMPORARY TABLE `tmp_bst_fam` (
        `CODIGO_FAM` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bst_fam` (`CODIGO_FAM`)
    WITH RECURSIVE `fam_tree` AS (
        SELECT `CODIGO_FAM_FAM`
          FROM `fza_articulos_familias`
         WHERE FIND_IN_SET(`CODIGO_FAM_FAM`, p_FAMILIAS)
        UNION ALL
        SELECT f.`CODIGO_FAM_FAM`
          FROM `fza_articulos_familias` f
          JOIN `fam_tree` t ON f.`CODIGO_PADRE_FAM` = t.`CODIGO_FAM_FAM`
    )
    SELECT DISTINCT `CODIGO_FAM_FAM` FROM `fam_tree`;
    /* Mapa familia -> ancestro al nivel pedido (para agrupar por FAM "por */
    /* nivel"). Ver balance_almacen_tallas.sql para el detalle. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_fam_grp`;
    CREATE TEMPORARY TABLE `tmp_bst_fam_grp` (
        `CODIGO_FAM` VARCHAR(20)  NOT NULL PRIMARY KEY,
        `COD_GRP`    VARCHAR(20)  NOT NULL,
        `DESC_GRP`   VARCHAR(200) NULL
    );
    INSERT IGNORE INTO `tmp_bst_fam_grp` (`CODIGO_FAM`, `COD_GRP`, `DESC_GRP`)
    WITH RECURSIVE `fam_path` AS (
        SELECT `CODIGO_FAM_FAM` AS `COD`,
               CAST(`CODIGO_FAM_FAM` AS CHAR(1000)) AS `RUTA`
          FROM `fza_articulos_familias`
         WHERE `CODIGO_PADRE_FAM` IS NULL OR `CODIGO_PADRE_FAM` = ''
        UNION ALL
        SELECT f.`CODIGO_FAM_FAM`,
               CONCAT(pa.`RUTA`, '>', f.`CODIGO_FAM_FAM`)
          FROM `fza_articulos_familias` f
          JOIN `fam_path` pa ON f.`CODIGO_PADRE_FAM` = pa.`COD`
    )
    SELECT pa.`COD`,
           SUBSTRING_INDEX(SUBSTRING_INDEX(pa.`RUTA`, '>', v_nivel_fam), '>', -1),
           NULL
      FROM `fam_path` pa;
    UPDATE `tmp_bst_fam_grp` g
      JOIN `fza_articulos_familias` f ON f.`CODIGO_FAM_FAM` = g.`COD_GRP`
       SET g.`DESC_GRP` = COALESCE(f.`DESCRIPCION_FAM`, f.`NOMBRE_FAM_FAM`,
                                   g.`COD_GRP`);
    /* Conjunto de artículos activos que pasan familia, proveedor y temporada. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_arts`;
    CREATE TEMPORARY TABLE `tmp_bst_arts` (
        `CODIGO_ART` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bst_arts` (`CODIGO_ART`)
    SELECT a.`CODIGO_ART_ART`
      FROM `fza_articulos` a
     WHERE a.`ESACTIVO_ART` = 'S'
       AND (p_ARTICULOS = ''
            OR FIND_IN_SET(a.`CODIGO_ART_ART`, p_ARTICULOS))
       AND (p_FAMILIAS = ''
            OR a.`CODIGO_FAM_ART` IN (SELECT `CODIGO_FAM` FROM `tmp_bst_fam`))
       AND (p_PROVEEDORES = ''
            OR EXISTS (SELECT 1 FROM `fza_articulos_proveedores` ap
                        WHERE ap.`CODIGO_ART_AP` = a.`CODIGO_ART_ART`
                          AND FIND_IN_SET(ap.`CODIGO_PRV_AP`, p_PROVEEDORES)))
       AND (p_TEMPORADAS = ''
            OR EXISTS (SELECT 1 FROM `fza_articulos_propiedades` tp
                        LEFT JOIN `fza_propiedades_valores` tpv
                          ON tpv.`ID_PV_ARTPROP` = tp.`ID_PV_ARTPROP`
                        WHERE tp.`CODIGO_ART_ART` = a.`CODIGO_ART_ART`
                          AND tp.`CODIGO_PROP_ARTPROP` = 'TEMPORADA'
                          AND FIND_IN_SET(
                                COALESCE(tpv.`PV`, tp.`VALOR_LIBRE_ARTPROP`),
                                p_TEMPORADAS)));

    /* ----------------------------------------------------------------- */
    /* SKUs en juego: unidad -> (artículo, color). SIN posición de talla: */
    /* entra cualquier SKU de los artículos filtrados (con o sin tallas), */
    /* por eso el informe cubre todo el catálogo. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_sku`;
    CREATE TEMPORARY TABLE `tmp_bst_sku` (
        `CODIGO_UNIDAD` VARCHAR(50)  NOT NULL PRIMARY KEY,
        `CODIGO_ART`    VARCHAR(20)  NOT NULL,
        `COLOR`         VARCHAR(100) NOT NULL DEFAULT '',
        `COLOR_HEX`     VARCHAR(7)   NULL,
        `ORDEN_COLOR`   INT          NOT NULL DEFAULT 0,
        KEY `IDX_BST_SKU_ART` (`CODIGO_ART`)
    );
    INSERT IGNORE INTO `tmp_bst_sku`
    SELECT sku.`CODIGO_UNIDAD_SKU`, sku.`CODIGO_ART_SKU`,
           COALESCE(co.`AV`, ''), COALESCE(atb.`HEX_ATB`, ''),
           COALESCE(co.`ORDEN_AV`, 0)
      FROM `fza_articulos_skus` sku
      JOIN `fza_articulos` a
        ON a.`CODIGO_ART_ART` = sku.`CODIGO_ART_SKU`
       AND a.`ESACTIVO_ART` = 'S'
       AND a.`CODIGO_ART_ART` IN (SELECT `CODIGO_ART` FROM `tmp_bst_arts`)
      /* Color del SKU: SOLO su fila de atributo de color. El discriminante */
      /* ID_VA_AV='CO' DEBE ir también en el ON de `sac`; si solo se filtra en */
      /* `co`, `sac` casa además la fila de talla (color NULL) y el SKU genera */
      /* dos filas. Con INSERT IGNORE sobre la PK del SKU sobrevive una al azar */
      /* y el SKU podía quedar SIN color (banda "sin color" fantasma). */
      LEFT JOIN `fza_atributos_sku` sac
        ON sac.`CODIGO_UNIDAD_SKU_SA` = sku.`CODIGO_UNIDAD_SKU`
       AND sac.`ID_AV_SA` IN (SELECT `ID_AV` FROM `fza_atributos_valores`
                               WHERE `ID_VA_AV` = 'CO')
      LEFT JOIN `fza_atributos_valores` co
        ON co.`ID_AV` = sac.`ID_AV_SA` AND co.`ID_VA_AV` = 'CO'
      LEFT JOIN `fza_atributos_basicos` atb ON atb.`ID_ATB` = co.`ID_ATB_AV`;

    /* ----------------------------------------------------------------- */
    /* Base de medidas por (artículo, almacén, color). Igual lógica que el */
    /* balance por tallas pero agrupando por color (no por talla). */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_base`;
    CREATE TEMPORARY TABLE `tmp_bst_base` (
        `CODIGO_ART`    VARCHAR(20)  NOT NULL,
        `CODIGO_ALM`    VARCHAR(20)  NOT NULL DEFAULT '',
        `COLOR`         VARCHAR(100) NOT NULL DEFAULT '',
        `COLOR_HEX`     VARCHAR(7)   NULL,
        `ORDEN_COLOR`   INT          NOT NULL DEFAULT 0,
        `EXI_INI`       DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT`           DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL`           DECIMAL(19,6) NOT NULL DEFAULT 0,
        `VEN`           DECIMAL(19,6) NOT NULL DEFAULT 0,
        `EXI_FIN`       DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_COMPRA`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_ALBENTRADA` DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_TRASPASO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_DEPOSITO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_REGULAR`   DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_TRASPASO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_DEPOSITO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_ALBVENTA`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_VENTA`     DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`)
    );

    IF p_MODO = 'A' THEN
        /* Acumulados denormalizados del stock actual. */
        INSERT INTO `tmp_bst_base`
            (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
             `EXI_INI`, `ENT`, `SAL`, `VEN`, `EXI_FIN`,
             `ENT_COMPRA`, `ENT_ALBENTRADA`, `ENT_TRASPASO`, `ENT_DEPOSITO`,
             `ENT_REGULAR`, `SAL_TRASPASO`, `SAL_DEPOSITO`, `SAL_ALBVENTA`,
             `SAL_VENTA`)
        SELECT s.`CODIGO_ART`, IF(v_por_alm, st.`CODIGO_ALM_STK`, ''),
               s.`COLOR`, MIN(s.`COLOR_HEX`), MIN(s.`ORDEN_COLOR`),
               0,
               SUM(st.`CANTIDAD_ENT_COMPRA_STK` + st.`CANTIDAD_ENT_TRASPASO_STK`
                 + st.`CANTIDAD_ENT_DEPOSITO_STK` + st.`CANTIDAD_ENT_REGULAR_STK`
                 + st.`CANTIDAD_ENT_ALBENTRADA_STK`),
               SUM(st.`CANTIDAD_SAL_TRASPASO_STK` + st.`CANTIDAD_SAL_DEPOSITO_STK`
                 + st.`CANTIDAD_SAL_VENTA_STK` + st.`CANTIDAD_SAL_ALBVENTA_STK`),
               SUM(st.`CANTIDAD_SAL_VENTA_STK` + st.`CANTIDAD_SAL_ALBVENTA_STK`),
               SUM(st.`CANTIDAD_STK`),
               SUM(st.`CANTIDAD_ENT_COMPRA_STK`), SUM(st.`CANTIDAD_ENT_ALBENTRADA_STK`),
               SUM(st.`CANTIDAD_ENT_TRASPASO_STK`), SUM(st.`CANTIDAD_ENT_DEPOSITO_STK`),
               SUM(st.`CANTIDAD_ENT_REGULAR_STK`), SUM(st.`CANTIDAD_SAL_TRASPASO_STK`),
               SUM(st.`CANTIDAD_SAL_DEPOSITO_STK`), SUM(st.`CANTIDAD_SAL_ALBVENTA_STK`),
               SUM(st.`CANTIDAD_SAL_VENTA_STK`)
          FROM `tmp_bst_sku` s
          JOIN `fza_articulos_stockactual` st
            ON st.`CODIGO_UNIDAD_STK` = s.`CODIGO_UNIDAD`
           AND st.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_bst_alm`)
         GROUP BY s.`CODIGO_ART`, IF(v_por_alm, st.`CODIGO_ALM_STK`, ''),
                  s.`COLOR`;
    ELSE
        /* Entre fechas: stock actual + movimientos firmados unificados por */
        /* (unidad, almacén). Si no se agrupa por almacén, ALM = '' y colapsa. */
        INSERT INTO `tmp_bst_base`
            (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
             `EXI_INI`, `ENT`, `SAL`, `VEN`, `EXI_FIN`,
             `ENT_COMPRA`, `ENT_ALBENTRADA`, `ENT_TRASPASO`, `ENT_DEPOSITO`,
             `ENT_REGULAR`, `SAL_TRASPASO`, `SAL_DEPOSITO`, `SAL_ALBVENTA`,
             `SAL_VENTA`)
        SELECT s.`CODIGO_ART`, COALESCE(mv.`ALM`, ''),
               s.`COLOR`, MIN(s.`COLOR_HEX`), MIN(s.`ORDEN_COLOR`),
               SUM(COALESCE(mv.`STOCK_NOW`, 0) - COALESCE(mv.`DELTA_DESDE`, 0)),
               SUM(COALESCE(mv.`ENT`, 0)),
               SUM(COALESCE(mv.`SAL`, 0)),
               SUM(COALESCE(mv.`VEN`, 0)),
               SUM(COALESCE(mv.`STOCK_NOW`, 0) - COALESCE(mv.`DELTA_HASTA`, 0)),
               SUM(COALESCE(mv.`ENT_COMPRA`, 0)), SUM(COALESCE(mv.`ENT_ALBENTRADA`, 0)),
               SUM(COALESCE(mv.`ENT_TRASPASO`, 0)), SUM(COALESCE(mv.`ENT_DEPOSITO`, 0)),
               SUM(COALESCE(mv.`ENT_REGULAR`, 0)), SUM(COALESCE(mv.`SAL_TRASPASO`, 0)),
               SUM(COALESCE(mv.`SAL_DEPOSITO`, 0)), SUM(COALESCE(mv.`SAL_ALBVENTA`, 0)),
               SUM(COALESCE(mv.`SAL_VENTA`, 0))
          FROM `tmp_bst_sku` s
          LEFT JOIN (
                SELECT u.`CODIGO_UNIDAD`, u.`ALM`,
                       SUM(u.`STOCK_NOW`)      AS `STOCK_NOW`,
                       SUM(u.`ENT`)            AS `ENT`,
                       SUM(u.`SAL`)            AS `SAL`,
                       SUM(u.`VEN`)            AS `VEN`,
                       SUM(u.`ENT_COMPRA`)     AS `ENT_COMPRA`,
                       SUM(u.`ENT_ALBENTRADA`) AS `ENT_ALBENTRADA`,
                       SUM(u.`ENT_TRASPASO`)   AS `ENT_TRASPASO`,
                       SUM(u.`ENT_DEPOSITO`)   AS `ENT_DEPOSITO`,
                       SUM(u.`ENT_REGULAR`)    AS `ENT_REGULAR`,
                       SUM(u.`SAL_TRASPASO`)   AS `SAL_TRASPASO`,
                       SUM(u.`SAL_DEPOSITO`)   AS `SAL_DEPOSITO`,
                       SUM(u.`SAL_ALBVENTA`)   AS `SAL_ALBVENTA`,
                       SUM(u.`SAL_VENTA`)      AS `SAL_VENTA`,
                       SUM(u.`DELTA_DESDE`)    AS `DELTA_DESDE`,
                       SUM(u.`DELTA_HASTA`)    AS `DELTA_HASTA`
                  FROM (
                        SELECT st2.`CODIGO_UNIDAD_STK` AS `CODIGO_UNIDAD`,
                               IF(v_por_alm, st2.`CODIGO_ALM_STK`, '') AS `ALM`,
                               st2.`CANTIDAD_STK` AS `STOCK_NOW`,
                               0 AS `ENT`, 0 AS `SAL`, 0 AS `VEN`,
                               0 AS `ENT_COMPRA`, 0 AS `ENT_ALBENTRADA`,
                               0 AS `ENT_TRASPASO`, 0 AS `ENT_DEPOSITO`,
                               0 AS `ENT_REGULAR`, 0 AS `SAL_TRASPASO`,
                               0 AS `SAL_DEPOSITO`, 0 AS `SAL_ALBVENTA`,
                               0 AS `SAL_VENTA`, 0 AS `DELTA_DESDE`,
                               0 AS `DELTA_HASTA`
                          FROM `fza_articulos_stockactual` st2
                         WHERE st2.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_bst_alm`)
                           /* Solo los SKUs del informe (IDX_STK_UNIDAD): no */
                           /* recorrer todo el stock para descartarlo al unir. */
                           AND st2.`CODIGO_UNIDAD_STK` IN
                               (SELECT `CODIGO_UNIDAD` FROM `tmp_bst_sku`)
                        UNION ALL
                        SELECT m.`CODIGO_UNIDAD_MOV`,
                               IF(v_por_alm, m.`CODIGO_ALM_MOV`, ''),
                               0,
                               IF(m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_MOV` = 'S'
                                  AND m.`TIPO_DOC_MOV` IN ('VE', 'FC', 'AV')
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'AC' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'AE' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` IN ('TR', 'AT', 'TA') AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'DP' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'IN' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` IN ('TR', 'AT', 'TA') AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'DP' AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'AV' AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` IN ('VE', 'FC') AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(DATE(m.`FECHA_MOV`) >= v_desde,
                                  IF(m.`TIPO_MOV` = 'E', m.`CANTIDAD_MOV`,
                                     -m.`CANTIDAD_MOV`), 0),
                               IF(DATE(m.`FECHA_MOV`) > v_hasta,
                                  IF(m.`TIPO_MOV` = 'E', m.`CANTIDAD_MOV`,
                                     -m.`CANTIDAD_MOV`), 0)
                          FROM `fza_movimientos_almacen` m
                         WHERE m.`ESACTIVO_MOV` = 'S'
                           AND m.`CODIGO_ALM_MOV` IN (SELECT `CODIGO_ALM` FROM `tmp_bst_alm`)
                           /* Solo los SKUs del informe (igual que el LEFT JOIN */
                           /* de abajo): no agrega TODA la tabla de movimientos */
                           /* para descartarla. Indexado por CODIGO_UNIDAD_MOV. */
                           AND m.`CODIGO_UNIDAD_MOV` IN
                               (SELECT `CODIGO_UNIDAD` FROM `tmp_bst_sku`)
                           /* Movs. anteriores a 'desde' aportan 0 a las 16 */
                           /* medidas (todas exigen fecha >= desde): se podan. */
                           AND m.`FECHA_MOV` >= v_desde
                       ) u
                 GROUP BY u.`CODIGO_UNIDAD`, u.`ALM`
               ) mv ON mv.`CODIGO_UNIDAD` = s.`CODIGO_UNIDAD`
         GROUP BY s.`CODIGO_ART`, COALESCE(mv.`ALM`, ''), s.`COLOR`;
    END IF;

    /* Ventas REALES por (artículo, almacén, color) desde las líneas de */
    /* factura: fuente de verdad de las ventas (cantidad e importe). Los */
    /* acumulados de stock (CANTIDAD_SAL_VENTA_STK) pueden no estar mantenidos */
    /* y dar 0 aunque haya venta. Se sobrescribe VEN ANTES del descarte para */
    /* que (a) la banda de ventas muestre la cantidad real y (b) no se borre un */
    /* color que solo tiene ventas (existencias netas 0). Mismo filtro de */
    /* almacén/periodo y mismos SKUs (tmp_bst_sku) que la valoración vt. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_ven`;
    CREATE TEMPORARY TABLE `tmp_bst_ven` (
        `CODIGO_ART` VARCHAR(20)   NOT NULL,
        `CODIGO_ALM` VARCHAR(20)   NOT NULL DEFAULT '',
        `COLOR`      VARCHAR(100)  NOT NULL DEFAULT '',
        `VEN_QTY`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`)
    );
    INSERT INTO `tmp_bst_ven`
    SELECT s.`CODIGO_ART`,
           IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, ''),
           s.`COLOR`,
           SUM(fl.`CANTIDAD_FACLIN`)
      FROM `fza_facturas_lineas` fl
      JOIN `fza_facturas` f
        ON f.`NUMERO_FAC` = fl.`NUMERO_FAC_FACLIN`
       AND f.`SERIE_FAC` = fl.`SERIE_FAC_FACLIN`
      JOIN `tmp_bst_sku` s
        ON s.`CODIGO_UNIDAD` = fl.`CODIGO_UNIDAD_FACLIN`
     WHERE fl.`CODIGO_ALM_FACLIN` IN (SELECT `CODIGO_ALM` FROM `tmp_bst_alm`)
       AND (p_MODO = 'A'
            OR DATE(f.`FECHA_FAC`) BETWEEN v_desde AND v_hasta)
     GROUP BY s.`CODIGO_ART`,
              IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, ''), s.`COLOR`;
    /* Sobrescribir la cantidad de ventas del stock con la real de facturas. */
    UPDATE `tmp_bst_base` b
      JOIN `tmp_bst_ven` v
        ON v.`CODIGO_ART` = b.`CODIGO_ART`
       AND v.`CODIGO_ALM` = b.`CODIGO_ALM`
       AND v.`COLOR` = b.`COLOR`
       SET b.`VEN` = v.`VEN_QTY`;

    /* Descartar (artículo, color) sin existencias ni movimientos: cubrir todo */
    /* el catálogo si no llenaría el informe de artículos inactivos a cero. */
    DELETE FROM `tmp_bst_base`
     WHERE `EXI_INI` = 0 AND `ENT` = 0 AND `SAL` = 0 AND `VEN` = 0
       AND `EXI_FIN` = 0 AND `ENT_COMPRA` = 0 AND `ENT_ALBENTRADA` = 0
       AND `ENT_TRASPASO` = 0 AND `ENT_DEPOSITO` = 0 AND `ENT_REGULAR` = 0
       AND `SAL_TRASPASO` = 0 AND `SAL_DEPOSITO` = 0 AND `SAL_ALBVENTA` = 0
       AND `SAL_VENTA` = 0;

    /* ----------------------------------------------------------------- */
    /* Desdoblar en bandas (forma larga), igual que el balance por tallas */
    /* pero sin posición de talla. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_medidas`;
    CREATE TEMPORARY TABLE `tmp_bst_medidas` (
        `CODIGO_ART`     VARCHAR(20)  NOT NULL,
        `CODIGO_ALM`     VARCHAR(20)  NOT NULL DEFAULT '',
        `COLOR`          VARCHAR(100) NULL,
        `COLOR_HEX`      VARCHAR(7)   NULL,
        `ORDEN_COLOR`    INT          NOT NULL DEFAULT 0,
        `BANDA`          VARCHAR(20)  NOT NULL,
        `ORDEN_BANDA`    INT          NOT NULL,
        `ETIQUETA_BANDA` VARCHAR(40)  NOT NULL,
        `ES_COSTE`       TINYINT      NOT NULL DEFAULT 0,
        `CANTIDAD`       DECIMAL(19,6) NOT NULL DEFAULT 0,
        KEY `IDX_BST_MED` (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `ORDEN_BANDA`)
    );
    /* Existencias iniciales: solo entre fechas. */
    IF p_MODO = 'F' THEN
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'EXIINI', 10, 'Existencias iniciales', 1, `EXI_INI`
          FROM `tmp_bst_base`;
    END IF;
    /* Simplificado (F) o acumulados (A). Entradas = albaranes (compra + alb. */
    /* entrada) + recuentos + traspasos NETOS (entrada - salida). SIN depósitos */
    /* y SIN banda Salidas: las ventas van en su banda. Balance: Ex.ini + */
    /* Entradas - Ventas = Ex.final (los depósitos quedan fuera). */
    IF (p_MODO = 'F' AND p_DESGLOSADO = 'N') OR p_MODO = 'A' THEN
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'ENT', 20, 'Entradas', 1,
               `ENT_COMPRA` + `ENT_ALBENTRADA` + `ENT_REGULAR`
                 + `ENT_TRASPASO` - `SAL_TRASPASO`
          FROM `tmp_bst_base`;
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'VEN', 50, 'Ventas', 0, `VEN`
          FROM `tmp_bst_base`;
    END IF;
    /* Entradas desglosadas: solo modo entre fechas desglosado. Traspasos y */
    /* depósitos netos (entrada - salida), sin bandas de salida salvo alb. */
    /* venta. Mismos subtipos que la consulta de stock (Ctrl+U). */
    IF p_MODO = 'F' AND p_DESGLOSADO = 'S' THEN
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'ENTCMP', 21, 'Ent. compra', 1, `ENT_COMPRA`
          FROM `tmp_bst_base`;
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'ENTALB', 22, 'Alb. entrada', 1, `ENT_ALBENTRADA`
          FROM `tmp_bst_base`;
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'ENTTRA', 23, 'Traspasos (neto)', 1,
               `ENT_TRASPASO` - `SAL_TRASPASO`
          FROM `tmp_bst_base`;
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'ENTDEP', 24, 'Depósitos (neto)', 1,
               `ENT_DEPOSITO` - `SAL_DEPOSITO`
          FROM `tmp_bst_base`;
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'ENTREG', 25, 'Regulariz.', 1, `ENT_REGULAR`
          FROM `tmp_bst_base`;
        /* Sal. traspaso / Sal. depósito ya no salen: neteadas en sus bandas de */
        /* entrada. Albarán de venta sí se mantiene (es una venta). */
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'SALALB', 43, 'Alb. venta', 0, `SAL_ALBVENTA`
          FROM `tmp_bst_base`;
        /* Cantidad de ventas = VEN (ya sobrescrito con la cantidad real de */
        /* facturas), igual que en simplificado/acumulados. */
        INSERT INTO `tmp_bst_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               'VEN', 50, 'Ventas', 0, `VEN`
          FROM `tmp_bst_base`;
    END IF;
    /* Existencias finales: siempre. */
    INSERT INTO `tmp_bst_medidas`
    SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
           'EXIFIN', 90, 'Existencias finales', 1, `EXI_FIN`
      FROM `tmp_bst_base`;
    /* Selección de bandas: sin selección = todas las de la configuración. */
    IF p_BANDAS <> '' THEN
        DELETE FROM `tmp_bst_medidas` WHERE NOT FIND_IN_SET(`BANDA`, p_BANDAS);
    END IF;

    /* ----------------------------------------------------------------- */
    /* Salida final: una fila por (artículo, color, banda), enriquecida con */
    /* familia, foto, valoración y columnas de agrupación. */
    /* ----------------------------------------------------------------- */
    SELECT
        COALESCE(fam.`ORDEN_FAM`, 999999)             AS `ORDEN_FAM`,
        art.`CODIGO_FAM_ART`                          AS `CODIGO_FAM`,
        COALESCE(fam.`DESCRIPCION_FAM`,
                 fam.`NOMBRE_FAM_FAM`, art.`CODIGO_FAM_ART`) AS `DESCRIPCION_FAM`,
        p.`CODIGO_ART`                                AS `CODIGO_ART_ART`,
        art.`DESCRIPCION_ART`                         AS `DESCRIPCION_ART`,
        p.`CODIGO_ALM`                                AS `CODIGO_ALM`,
        COALESCE(alm.`NOMBRE_ALM_ALM`, '')            AS `NOMBRE_ALM`,
        prov.`REF_PROVEEDOR_AP`                       AS `REF_PRV`,
        ROUND(COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0), 2) AS `COSTE_ART`,
        ROUND(COALESCE(pvp.`PVP`, 0), 2)              AS `PVP_ART`,
        p.`ORDEN_COLOR`, p.`COLOR`, p.`COLOR_HEX`,
        p.`ORDEN_BANDA`, p.`BANDA`, p.`ETIQUETA_BANDA`, p.`ES_COSTE`,
        p.`CANTIDAD`,
        ROUND(IF(p.`BANDA` = 'VEN',
                 IF(p.`CANTIDAD` <> 0,
                    COALESCE(vt.`VEN_IMPORTE`, 0) / p.`CANTIDAD`, 0),
                 IF(p.`ES_COSTE` = 1,
                    COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0),
                    COALESCE(pvp.`PVP`, 0))), 2)        AS `PRECIO`,
        /* Importe de la banda. La banda de ventas (VEN) se valora al PRECIO */
        /* REAL de venta (con descuentos, con IVA) tomado de fza_facturas_lineas; */
        /* el resto a coste/PMP o a tarifa según ES_COSTE. */
        ROUND(IF(p.`BANDA` = 'VEN',
                 COALESCE(vt.`VEN_IMPORTE`, 0),
                 p.`CANTIDAD` * IF(p.`ES_COSTE` = 1,
                   COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0),
                   COALESCE(pvp.`PVP`, 0))), 2)          AS `IMPORTE`,
        /* Ventas reales (con descuento, con IVA) solo en la banda de ventas */
        /* (VEN); 0 en el resto. Al sumarla por artículo/grupo/total da el */
        /* acumulado de ventas (las existencias se leen banda a banda; las */
        /* ventas hay que irlas sumando). */
        ROUND(IF(p.`BANDA` = 'VEN', COALESCE(vt.`VEN_IMPORTE`, 0), 0), 2)
                                                      AS `VENTAS`,
        /* Existencias finales aisladas (cantidad y valor a PMP) solo en la */
        /* banda EXIFIN, 0 en el resto, para que el total por grupo/general */
        /* muestre SOLO el stock final. */
        IF(p.`BANDA` = 'EXIFIN', p.`CANTIDAD`, 0)     AS `EXIFIN_CANT`,
        ROUND(IF(p.`BANDA` = 'EXIFIN',
                 p.`CANTIDAD` * COALESCE(NULLIF(cst.`COSTE`, 0),
                                         prov.`COSTE_PRV`, 0),
                 0), 2)                               AS `EXIFIN_IMP`,
        CASE p_NIVEL1
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN p.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO1_COD`,
        CASE p_NIVEL1
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`,
                          art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), p.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO1_ETIQ`,
        CASE p_NIVEL2
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN p.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO2_COD`,
        CASE p_NIVEL2
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`,
                          art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), p.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO2_ETIQ`,
        CASE p_NIVEL3
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN p.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO3_COD`,
        CASE p_NIVEL3
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`,
                          art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), p.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO3_ETIQ`
      FROM (
            SELECT m.`CODIGO_ART`, m.`CODIGO_ALM`, m.`COLOR`,
                   MIN(m.`COLOR_HEX`) AS `COLOR_HEX`,
                   MIN(m.`ORDEN_COLOR`) AS `ORDEN_COLOR`,
                   m.`BANDA`, m.`ORDEN_BANDA`, m.`ETIQUETA_BANDA`, m.`ES_COSTE`,
                   SUM(m.`CANTIDAD`) AS `CANTIDAD`
              FROM `tmp_bst_medidas` m
             GROUP BY m.`CODIGO_ART`, m.`CODIGO_ALM`, m.`COLOR`, m.`BANDA`,
                      m.`ORDEN_BANDA`, m.`ETIQUETA_BANDA`, m.`ES_COSTE`
           ) p
      JOIN `fza_articulos` art ON art.`CODIGO_ART_ART` = p.`CODIGO_ART`
      LEFT JOIN `fza_articulos_familias` fam
        ON fam.`CODIGO_FAM_FAM` = art.`CODIGO_FAM_ART`
      LEFT JOIN `tmp_bst_fam_grp` fg ON fg.`CODIGO_FAM` = art.`CODIGO_FAM_ART`
      LEFT JOIN `fza_almacenes` alm ON alm.`CODIGO_ALM_ALM` = p.`CODIGO_ALM`
      LEFT JOIN (
            SELECT t.`CODIGO_ART_ARTTAR` AS `CODIGO_ART`,
                   MAX(t.`PRECIO_FINAL_ARTTAR`) AS `PVP`
              FROM `fza_articulos_tarifas` t
             WHERE t.`CODIGO_TAR_ARTTAR` = v_tarifa
               /* Solo los artículos del informe (se une por artículo filtrado). */
               AND t.`CODIGO_ART_ARTTAR` IN
                   (SELECT `CODIGO_ART` FROM `tmp_bst_arts`)
               AND IFNULL(t.`CODIGO_UNIDAD_ARTTAR`, '') = ''
               AND t.`ESACTIVO_ARTTAR` = 'S'
               AND (t.`FECHA_DESDE_ARTTAR` IS NULL
                    OR t.`FECHA_DESDE_ARTTAR` <= CURRENT_DATE)
               AND (t.`FECHA_HASTA_ARTTAR` IS NULL
                    OR t.`FECHA_HASTA_ARTTAR` >= CURRENT_DATE)
             GROUP BY t.`CODIGO_ART_ARTTAR`
           ) pvp ON pvp.`CODIGO_ART` = p.`CODIGO_ART`
      LEFT JOIN (
            SELECT sk.`CODIGO_ART_SKU` AS `CODIGO_ART`,
                   IF(SUM(st.`CANTIDAD_STK`) <> 0,
                      SUM(st.`VALOR_TOTAL_STK`) / SUM(st.`CANTIDAD_STK`), 0) AS `COSTE`
              FROM `fza_articulos_stockactual` st
              JOIN `fza_articulos_skus` sk
                ON sk.`CODIGO_UNIDAD_SKU` = st.`CODIGO_UNIDAD_STK`
             WHERE st.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_bst_alm`)
               /* Solo los SKUs del informe (se une por artículo ya filtrado). */
               AND st.`CODIGO_UNIDAD_STK` IN
                   (SELECT `CODIGO_UNIDAD` FROM `tmp_bst_sku`)
             GROUP BY sk.`CODIGO_ART_SKU`
           ) cst ON cst.`CODIGO_ART` = p.`CODIGO_ART`
      LEFT JOIN (
            SELECT ap.`CODIGO_ART_AP` AS `CODIGO_ART`,
                   MAX(ap.`REF_PROVEEDOR_AP`)   AS `REF_PROVEEDOR_AP`,
                   MAX(ap.`PRECIO_ULT_COMPRA_AP`) AS `COSTE_PRV`,
                   MAX(ap.`CODIGO_PRV_AP`)      AS `CODIGO_PRV`,
                   MAX(pr.`RAZON_SOCIAL_PRV`)   AS `RAZON`
              FROM `fza_articulos_proveedores` ap
              LEFT JOIN `fza_proveedores` pr
                ON pr.`CODIGO_PRV_PRV` = ap.`CODIGO_PRV_AP`
             WHERE ap.`ESPROVEEDORPRINCIPAL_AP` = 'S'
               /* Solo los artículos del informe (se une por artículo filtrado). */
               AND ap.`CODIGO_ART_AP` IN
                   (SELECT `CODIGO_ART` FROM `tmp_bst_arts`)
             GROUP BY ap.`CODIGO_ART_AP`
           ) prov ON prov.`CODIGO_ART` = p.`CODIGO_ART`
      /* Temporada EFECTIVA por color (Fase 4): la vista de propiedades */
      /* efectivas resuelve color -> articulo; tmp_bst_sku da el color del */
      /* SKU. Los SKU de un mismo color comparten temporada (el MAX colapsa */
      /* sin ambiguedad). Sin datos de color resuelve al valor de articulo. */
      LEFT JOIN (
            SELECT s.`CODIGO_ART` AS `CODIGO_ART`, s.`COLOR` AS `COLOR`,
                   MAX(COALESCE(e.`VALOR_PV`,
                                e.`VALOR_LIBRE_ARTPROP`)) AS `TEMPORADA`
              FROM `tmp_bst_sku` s
              JOIN `vi_articulos_propiedades_efectivas` e
                ON e.`CODIGO_UNIDAD_SKU` = s.`CODIGO_UNIDAD`
               AND e.`CODIGO_PROP_ARTPROP` = 'TEMPORADA'
             GROUP BY s.`CODIGO_ART`, s.`COLOR`
           ) tmp ON tmp.`CODIGO_ART` = p.`CODIGO_ART`
                AND tmp.`COLOR` = p.`COLOR`
      LEFT JOIN (
            /* Ventas REALES (con descuento, con IVA) por (artículo, almacén, */
            /* color), de las líneas de factura/ticket. Periodo por fecha de */
            /* factura (entre fechas) o histórico (acumulados). */
            SELECT s.`CODIGO_ART`,
                   IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, '') AS `CODIGO_ALM`,
                   s.`COLOR`,
                   SUM(fl.`CANTIDAD_FACLIN`) AS `VEN_QTY`,
                   SUM(fl.`TOTAL_FACLIN`)    AS `VEN_IMPORTE`
              FROM `fza_facturas_lineas` fl
              JOIN `fza_facturas` f
                ON f.`NUMERO_FAC` = fl.`NUMERO_FAC_FACLIN`
               AND f.`SERIE_FAC` = fl.`SERIE_FAC_FACLIN`
              JOIN `tmp_bst_sku` s
                ON s.`CODIGO_UNIDAD` = fl.`CODIGO_UNIDAD_FACLIN`
             WHERE fl.`CODIGO_ALM_FACLIN` IN (SELECT `CODIGO_ALM` FROM `tmp_bst_alm`)
               AND (p_MODO = 'A'
                    OR DATE(f.`FECHA_FAC`) BETWEEN v_desde AND v_hasta)
             GROUP BY s.`CODIGO_ART`,
                      IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, ''), s.`COLOR`
           ) vt ON vt.`CODIGO_ART` = p.`CODIGO_ART`
               AND vt.`CODIGO_ALM` = p.`CODIGO_ALM`
               AND vt.`COLOR` = p.`COLOR`
     ORDER BY `GRUPO1_COD`, `GRUPO2_COD`, `GRUPO3_COD`,
              COALESCE(fam.`ORDEN_FAM`, 999999), art.`CODIGO_FAM_ART`,
              p.`CODIGO_ART`, p.`ORDEN_COLOR`, p.`COLOR`, p.`ORDEN_BANDA`;

    /* Limpieza de temporales. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_medidas`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_ven`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_base`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_sku`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_arts`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_fam_grp`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_fam`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bst_alm`;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_BALANCE_ALMACEN_TALLAS
DROP PROCEDURE IF EXISTS `PRC_GET_BALANCE_ALMACEN_TALLAS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_BALANCE_ALMACEN_TALLAS`(
    IN `p_MODO`         VARCHAR(1),   /* 'F' entre fechas, 'A' por acumulados */
    IN `p_DESDE`        DATE,         /* inclusive (solo modo 'F') */
    IN `p_HASTA`        DATE,         /* inclusive (solo modo 'F') */
    IN `p_ALMACENES`    TEXT,         /* CSV "01,50" o '' = todos los activos */
    IN `p_FAMILIAS`     TEXT,         /* CSV; '' = todas. Una padre incluye sus hijas */
    IN `p_PROVEEDORES`  TEXT,         /* CSV de códigos de proveedor; '' = todos */
    IN `p_TEMPORADAS`   TEXT,         /* CSV de valores de temporada; '' = todas */
    IN `p_ARTICULOS`    TEXT,         /* CSV de códigos de artículo; '' = todos */
    IN `p_COD_TARIFA`   VARCHAR(20),  /* tarifa para valorar ventas/salidas */
    IN `p_DESGLOSADO`   VARCHAR(1),   /* 'S'/'N' (solo aplica a modo 'F') */
    IN `p_BANDAS`       TEXT,         /* CSV de códigos de banda; '' = todas */
    IN `p_NIVEL1`       VARCHAR(3),   /* 1er nivel de agrupación: PRV/FAM/TMP/ALM/'' */
    IN `p_NIVEL2`       VARCHAR(3),   /* 2o nivel de agrupación */
    IN `p_NIVEL3`       VARCHAR(3),   /* 3er nivel de agrupación */
    IN `p_NIVEL_FAM`    INT           /* nivel del árbol de familias al agrupar */
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_alms      TEXT;
    DECLARE v_tarifa    VARCHAR(20);
    DECLARE v_desde     DATE;
    DECLARE v_hasta     DATE;
    DECLARE v_por_alm   BOOLEAN DEFAULT FALSE;  /* TRUE si se agrupa por almacén */
    DECLARE v_nivel_fam INT;                    /* nivel efectivo del árbol fam. */
    /* Normalización de parámetros. */
    SET p_MODO       = IFNULL(NULLIF(p_MODO, ''), 'A');
    SET p_DESGLOSADO  = IFNULL(NULLIF(p_DESGLOSADO, ''), 'N');
    SET p_FAMILIAS    = IFNULL(p_FAMILIAS, '');
    SET p_PROVEEDORES = IFNULL(p_PROVEEDORES, '');
    SET p_TEMPORADAS  = IFNULL(p_TEMPORADAS, '');
    SET p_ARTICULOS   = IFNULL(p_ARTICULOS, '');
    SET p_BANDAS      = IFNULL(p_BANDAS, '');
    /* Niveles de agrupación: normalizados a mayúsculas. Se admiten PRV */
    /* (proveedor), FAM (familia), TMP (temporada) y ALM (almacén); cualquier */
    /* otro valor (o vacío) deshabilita ese nivel. */
    SET p_NIVEL1      = UPPER(IFNULL(p_NIVEL1, ''));
    SET p_NIVEL2      = UPPER(IFNULL(p_NIVEL2, ''));
    SET p_NIVEL3      = UPPER(IFNULL(p_NIVEL3, ''));
    /* Si algún nivel es ALM hay que conservar el almacén en el grano de los */
    /* cálculos (si no, se agregan todos los almacenes filtrados en uno). */
    SET v_por_alm     = (p_NIVEL1 = 'ALM' OR p_NIVEL2 = 'ALM' OR p_NIVEL3 = 'ALM');
    /* Nivel del árbol de familias para agrupar por FAM. <1 (o NULL) = familia */
    /* hoja del artículo (comportamiento clásico); 1 = familia raíz, etc. */
    SET v_nivel_fam   = IF(IFNULL(p_NIVEL_FAM, 0) < 1, 9999, p_NIVEL_FAM);
    SET v_tarifa      = IFNULL(NULLIF(p_COD_TARIFA, ''), 'PVP');
    SET v_desde      = IFNULL(p_DESDE, '1900-01-01');
    SET v_hasta      = IFNULL(p_HASTA, CURRENT_DATE);
    /* Almacenes efectivos en una tabla temporal INDEXADA (PK), para filtrar */
    /* por IN en vez de FIND_IN_SET sobre las tablas grandes: FIND_IN_SET no es */
    /* sargable y obliga a escanear (p. ej. fza_articulos_stockactual, cuyo PK */
    /* empieza por CODIGO_ALM_STK). Con el IN, MariaDB puede usar el índice. */
    /* Sin selección = todos los almacenes activos ("nada marcado = todos"). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_alm`;
    CREATE TEMPORARY TABLE `tmp_bat_alm` (
        `CODIGO_ALM` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bat_alm` (`CODIGO_ALM`)
    SELECT `CODIGO_ALM_ALM` FROM `fza_almacenes`
     WHERE IF(IFNULL(p_ALMACENES, '') = '',
              `ESACTIVO_ALM` = 'S',
              FIND_IN_SET(`CODIGO_ALM_ALM`, p_ALMACENES));

    /* ----------------------------------------------------------------- */
    /* Filtros de artículo: familias (con su descendencia), proveedores y */
    /* temporadas. Se materializa en tmp_bat_arts el conjunto de artículos */
    /* que pasan los tres filtros; el resto del SP se restringe a él. */
    /* ----------------------------------------------------------------- */
    /* Familias elegidas expandidas a TODA su descendencia: si se filtra una */
    /* familia padre, entran también sus hijas (CTE recursivo por */
    /* CODIGO_PADRE_FAM). Con p_FAMILIAS vacío sale vacía y no se aplica. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_fam`;
    CREATE TEMPORARY TABLE `tmp_bat_fam` (
        `CODIGO_FAM` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bat_fam` (`CODIGO_FAM`)
    WITH RECURSIVE `fam_tree` AS (
        SELECT `CODIGO_FAM_FAM`
          FROM `fza_articulos_familias`
         WHERE FIND_IN_SET(`CODIGO_FAM_FAM`, p_FAMILIAS)
        UNION ALL
        SELECT f.`CODIGO_FAM_FAM`
          FROM `fza_articulos_familias` f
          JOIN `fam_tree` t ON f.`CODIGO_PADRE_FAM` = t.`CODIGO_FAM_FAM`
    )
    SELECT DISTINCT `CODIGO_FAM_FAM` FROM `fam_tree`;
    /* Mapa de cada familia a su ancestro al nivel pedido (v_nivel_fam), para */
    /* agrupar por FAM "por nivel": si el árbol tiene padres-hijos se puede */
    /* agrupar por la familia raíz (nivel 1), la de 2º nivel, etc. Se construye */
    /* el camino raíz->familia y se toma el código del nivel solicitado (o la */
    /* propia familia si es menos profunda que el nivel pedido). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_fam_grp`;
    CREATE TEMPORARY TABLE `tmp_bat_fam_grp` (
        `CODIGO_FAM` VARCHAR(20)  NOT NULL PRIMARY KEY,
        `COD_GRP`    VARCHAR(20)  NOT NULL,
        `DESC_GRP`   VARCHAR(200) NULL
    );
    INSERT IGNORE INTO `tmp_bat_fam_grp` (`CODIGO_FAM`, `COD_GRP`, `DESC_GRP`)
    WITH RECURSIVE `fam_path` AS (
        SELECT `CODIGO_FAM_FAM` AS `COD`,
               CAST(`CODIGO_FAM_FAM` AS CHAR(1000)) AS `RUTA`
          FROM `fza_articulos_familias`
         WHERE `CODIGO_PADRE_FAM` IS NULL OR `CODIGO_PADRE_FAM` = ''
        UNION ALL
        SELECT f.`CODIGO_FAM_FAM`,
               CONCAT(pa.`RUTA`, '>', f.`CODIGO_FAM_FAM`)
          FROM `fza_articulos_familias` f
          JOIN `fam_path` pa ON f.`CODIGO_PADRE_FAM` = pa.`COD`
    )
    SELECT pa.`COD`,
           SUBSTRING_INDEX(SUBSTRING_INDEX(pa.`RUTA`, '>', v_nivel_fam), '>', -1),
           NULL
      FROM `fam_path` pa;
    /* Descripción del grupo (familia ancestro elegida). */
    UPDATE `tmp_bat_fam_grp` g
      JOIN `fza_articulos_familias` f ON f.`CODIGO_FAM_FAM` = g.`COD_GRP`
       SET g.`DESC_GRP` = COALESCE(f.`DESCRIPCION_FAM`, f.`NOMBRE_FAM_FAM`,
                                   g.`COD_GRP`);
    /* Conjunto de artículos activos que pasan familia, proveedor y temporada. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_arts`;
    CREATE TEMPORARY TABLE `tmp_bat_arts` (
        `CODIGO_ART` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bat_arts` (`CODIGO_ART`)
    SELECT a.`CODIGO_ART_ART`
      FROM `fza_articulos` a
     WHERE a.`ESACTIVO_ART` = 'S'
       AND (p_ARTICULOS = ''
            OR FIND_IN_SET(a.`CODIGO_ART_ART`, p_ARTICULOS))
       AND (p_FAMILIAS = ''
            OR a.`CODIGO_FAM_ART` IN (SELECT `CODIGO_FAM` FROM `tmp_bat_fam`))
       AND (p_PROVEEDORES = ''
            OR EXISTS (SELECT 1 FROM `fza_articulos_proveedores` ap
                        WHERE ap.`CODIGO_ART_AP` = a.`CODIGO_ART_ART`
                          AND FIND_IN_SET(ap.`CODIGO_PRV_AP`, p_PROVEEDORES)))
       AND (p_TEMPORADAS = ''
            OR EXISTS (SELECT 1 FROM `fza_articulos_propiedades` tp
                        LEFT JOIN `fza_propiedades_valores` tpv
                          ON tpv.`ID_PV_ARTPROP` = tp.`ID_PV_ARTPROP`
                        WHERE tp.`CODIGO_ART_ART` = a.`CODIGO_ART_ART`
                          AND tp.`CODIGO_PROP_ARTPROP` = 'TEMPORADA'
                          AND FIND_IN_SET(
                                COALESCE(tpv.`PV`, tp.`VALOR_LIBRE_ARTPROP`),
                                p_TEMPORADAS)));

    /* ----------------------------------------------------------------- */
    /* 1) Posiciones de talla por artículo (T01..T14). */
    /*    Mismo criterio que TfrmStockConsulta.TallasArticulo: el conjunto */
    /*    pivote del artículo (atributo no-color asignado) define el orden */
    /*    de las columnas; si el artículo no tiene asignación, se usan las */
    /*    tallas presentes en sus SKUs como respaldo. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_pos`;
    CREATE TEMPORARY TABLE `tmp_bat_pos` (
        `CODIGO_ART` VARCHAR(20)  NOT NULL,
        `ID_AV`      INT          NOT NULL,
        `ETIQ`       VARCHAR(100) NULL,
        `POSICION`   INT          NOT NULL,
        PRIMARY KEY (`CODIGO_ART`, `ID_AV`)
    );
    /* 1a) Artículos con conjunto pivote asignado. */
    INSERT IGNORE INTO `tmp_bat_pos` (`CODIGO_ART`, `ID_AV`, `ETIQ`, `POSICION`)
    SELECT asg.`CODIGO_ART`, acd.`ID_AV_ACD`, av.`AV`,
           ROW_NUMBER() OVER (PARTITION BY asg.`CODIGO_ART`
                              ORDER BY acd.`ORDEN_ACD`, acd.`ID_AV_ACD`)
      FROM (SELECT a.`CODIGO_ART_ART` AS `CODIGO_ART`,
                   MIN(asa.`ID_AC_ACA`) AS `ID_AC`
              FROM `fza_articulos` a
              JOIN `fza_articulos_conjuntos_asign` asa
                ON asa.`CODIGO_ART_ACA` = a.`CODIGO_ART_ART`
               AND asa.`ID_VA_ACA` <> 'CO'
             WHERE a.`ESACTIVO_ART` = 'S'
               AND a.`CODIGO_ART_ART` IN (SELECT `CODIGO_ART` FROM `tmp_bat_arts`)
             GROUP BY a.`CODIGO_ART_ART`) asg
      JOIN `fza_atributos_conjuntos_det` acd ON acd.`ID_AC_ACD` = asg.`ID_AC`
      JOIN `fza_atributos_valores` av ON av.`ID_AV` = acd.`ID_AV_ACD`;
    /* Artículos ya resueltos (para excluirlos del respaldo sin */
    /* autorreferenciar tmp_bat_pos en el mismo statement). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_pos_arts`;
    CREATE TEMPORARY TABLE `tmp_bat_pos_arts` (
        `CODIGO_ART` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_bat_pos_arts`
    SELECT DISTINCT `CODIGO_ART` FROM `tmp_bat_pos`;
    /* 1b) Respaldo: artículos sin asignación -> tallas de sus SKUs. */
    INSERT IGNORE INTO `tmp_bat_pos` (`CODIGO_ART`, `ID_AV`, `ETIQ`, `POSICION`)
    SELECT x.`CODIGO_ART`, x.`ID_AV`, x.`AV`,
           ROW_NUMBER() OVER (PARTITION BY x.`CODIGO_ART`
                              ORDER BY x.`ORDEN_AV`, x.`AV`)
      FROM (SELECT DISTINCT a.`CODIGO_ART_ART` AS `CODIGO_ART`,
                   av.`ID_AV`, av.`AV`, COALESCE(av.`ORDEN_AV`, 0) AS `ORDEN_AV`
              FROM `fza_articulos` a
              JOIN `fza_articulos_skus` sku
                ON sku.`CODIGO_ART_SKU` = a.`CODIGO_ART_ART`
              JOIN `fza_atributos_sku` sa
                ON sa.`CODIGO_UNIDAD_SKU_SA` = sku.`CODIGO_UNIDAD_SKU`
              JOIN `fza_atributos_valores` av
                ON av.`ID_AV` = sa.`ID_AV_SA` AND av.`ID_VA_AV` <> 'CO'
             WHERE a.`ESACTIVO_ART` = 'S'
               AND a.`CODIGO_ART_ART` IN (SELECT `CODIGO_ART` FROM `tmp_bat_arts`)
               AND a.`CODIGO_ART_ART` NOT IN
                   (SELECT `CODIGO_ART` FROM `tmp_bat_pos_arts`)) x;

    /* Etiquetas de cabecera por artículo (ETIQ_T01..ETIQ_T14). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_etiq`;
    CREATE TEMPORARY TABLE `tmp_bat_etiq` AS
    SELECT `CODIGO_ART`,
           MAX(CASE WHEN `POSICION` =  1 THEN `ETIQ` END) AS `ETIQ_T01`,
           MAX(CASE WHEN `POSICION` =  2 THEN `ETIQ` END) AS `ETIQ_T02`,
           MAX(CASE WHEN `POSICION` =  3 THEN `ETIQ` END) AS `ETIQ_T03`,
           MAX(CASE WHEN `POSICION` =  4 THEN `ETIQ` END) AS `ETIQ_T04`,
           MAX(CASE WHEN `POSICION` =  5 THEN `ETIQ` END) AS `ETIQ_T05`,
           MAX(CASE WHEN `POSICION` =  6 THEN `ETIQ` END) AS `ETIQ_T06`,
           MAX(CASE WHEN `POSICION` =  7 THEN `ETIQ` END) AS `ETIQ_T07`,
           MAX(CASE WHEN `POSICION` =  8 THEN `ETIQ` END) AS `ETIQ_T08`,
           MAX(CASE WHEN `POSICION` =  9 THEN `ETIQ` END) AS `ETIQ_T09`,
           MAX(CASE WHEN `POSICION` = 10 THEN `ETIQ` END) AS `ETIQ_T10`,
           MAX(CASE WHEN `POSICION` = 11 THEN `ETIQ` END) AS `ETIQ_T11`,
           MAX(CASE WHEN `POSICION` = 12 THEN `ETIQ` END) AS `ETIQ_T12`,
           MAX(CASE WHEN `POSICION` = 13 THEN `ETIQ` END) AS `ETIQ_T13`,
           MAX(CASE WHEN `POSICION` = 14 THEN `ETIQ` END) AS `ETIQ_T14`
      FROM `tmp_bat_pos`
     GROUP BY `CODIGO_ART`;
    ALTER TABLE `tmp_bat_etiq` ADD PRIMARY KEY (`CODIGO_ART`);

    /* ----------------------------------------------------------------- */
    /* 2) SKUs en juego: artículo + color + posición de talla. Solo las */
    /*    tallas que están en el conjunto pivote (POSICION 1..14). */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_sku`;
    CREATE TEMPORARY TABLE `tmp_bat_sku` (
        `CODIGO_UNIDAD` VARCHAR(50)  NOT NULL PRIMARY KEY,
        `CODIGO_ART`    VARCHAR(20)  NOT NULL,
        `COLOR`         VARCHAR(100) NOT NULL DEFAULT '',
        `COLOR_HEX`     VARCHAR(7)   NULL,
        `ORDEN_COLOR`   INT          NOT NULL DEFAULT 0,
        `POSICION`      INT          NOT NULL,
        KEY `IDX_BAT_SKU_ART` (`CODIGO_ART`)
    );
    INSERT IGNORE INTO `tmp_bat_sku`
    SELECT sku.`CODIGO_UNIDAD_SKU`, sku.`CODIGO_ART_SKU`,
           COALESCE(co.`AV`, ''), COALESCE(atb.`HEX_ATB`, ''),
           COALESCE(co.`ORDEN_AV`, 0), p.`POSICION`
      FROM `fza_articulos_skus` sku
      JOIN `fza_articulos` a
        ON a.`CODIGO_ART_ART` = sku.`CODIGO_ART_SKU`
       AND a.`ESACTIVO_ART` = 'S'
      JOIN `fza_atributos_sku` sat
        ON sat.`CODIGO_UNIDAD_SKU_SA` = sku.`CODIGO_UNIDAD_SKU`
      JOIN `fza_atributos_valores` ta
        ON ta.`ID_AV` = sat.`ID_AV_SA` AND ta.`ID_VA_AV` <> 'CO'
      JOIN `tmp_bat_pos` p
        ON p.`CODIGO_ART` = sku.`CODIGO_ART_SKU` AND p.`ID_AV` = ta.`ID_AV`
      /* Color del SKU: SOLO su fila de atributo de color. El discriminante */
      /* ID_VA_AV='CO' DEBE ir también en el ON de `sac`; si solo se filtra en */
      /* `co`, `sac` casa además la fila de talla (color NULL) y el SKU genera */
      /* dos filas. Con INSERT IGNORE sobre la PK del SKU sobrevive una al azar */
      /* y el SKU podía quedar SIN color (banda "sin color" fantasma). */
      LEFT JOIN `fza_atributos_sku` sac
        ON sac.`CODIGO_UNIDAD_SKU_SA` = sku.`CODIGO_UNIDAD_SKU`
       AND sac.`ID_AV_SA` IN (SELECT `ID_AV` FROM `fza_atributos_valores`
                               WHERE `ID_VA_AV` = 'CO')
      LEFT JOIN `fza_atributos_valores` co
        ON co.`ID_AV` = sac.`ID_AV_SA` AND co.`ID_VA_AV` = 'CO'
      LEFT JOIN `fza_atributos_basicos` atb ON atb.`ID_ATB` = co.`ID_ATB_AV`;

    /* ----------------------------------------------------------------- */
    /* 3) Base de medidas por (artículo, color, posición). Se rellena con */
    /*    ramas distintas según el modo para no calcular ventanas de */
    /*    movimientos cuando se pide acumulados. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_base`;
    CREATE TEMPORARY TABLE `tmp_bat_base` (
        `CODIGO_ART`    VARCHAR(20)  NOT NULL,
        `CODIGO_ALM`    VARCHAR(20)  NOT NULL DEFAULT '',
        `COLOR`         VARCHAR(100) NOT NULL DEFAULT '',
        `COLOR_HEX`     VARCHAR(7)   NULL,
        `ORDEN_COLOR`   INT          NOT NULL DEFAULT 0,
        `POSICION`      INT          NOT NULL,
        `EXI_INI`       DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT`           DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL`           DECIMAL(19,6) NOT NULL DEFAULT 0,
        `VEN`           DECIMAL(19,6) NOT NULL DEFAULT 0,
        `EXI_FIN`       DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_COMPRA`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_ALBENTRADA` DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_TRASPASO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_DEPOSITO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `ENT_REGULAR`   DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_TRASPASO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_DEPOSITO`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_ALBVENTA`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        `SAL_VENTA`     DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`, `POSICION`, `COLOR`)
    );

    IF p_MODO = 'A' THEN
        /* Acumulados denormalizados del stock actual. */
        INSERT INTO `tmp_bat_base`
            (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
             `POSICION`,
             `EXI_INI`, `ENT`, `SAL`, `VEN`, `EXI_FIN`,
             `ENT_COMPRA`, `ENT_ALBENTRADA`, `ENT_TRASPASO`, `ENT_DEPOSITO`,
             `ENT_REGULAR`, `SAL_TRASPASO`, `SAL_DEPOSITO`, `SAL_ALBVENTA`,
             `SAL_VENTA`)
        SELECT s.`CODIGO_ART`, IF(v_por_alm, st.`CODIGO_ALM_STK`, ''),
               s.`COLOR`, MIN(s.`COLOR_HEX`),
               MIN(s.`ORDEN_COLOR`), s.`POSICION`,
               0,
               SUM(st.`CANTIDAD_ENT_COMPRA_STK` + st.`CANTIDAD_ENT_TRASPASO_STK`
                 + st.`CANTIDAD_ENT_DEPOSITO_STK` + st.`CANTIDAD_ENT_REGULAR_STK`
                 + st.`CANTIDAD_ENT_ALBENTRADA_STK`),
               SUM(st.`CANTIDAD_SAL_TRASPASO_STK` + st.`CANTIDAD_SAL_DEPOSITO_STK`
                 + st.`CANTIDAD_SAL_VENTA_STK` + st.`CANTIDAD_SAL_ALBVENTA_STK`),
               SUM(st.`CANTIDAD_SAL_VENTA_STK` + st.`CANTIDAD_SAL_ALBVENTA_STK`),
               SUM(st.`CANTIDAD_STK`),
               SUM(st.`CANTIDAD_ENT_COMPRA_STK`), SUM(st.`CANTIDAD_ENT_ALBENTRADA_STK`),
               SUM(st.`CANTIDAD_ENT_TRASPASO_STK`), SUM(st.`CANTIDAD_ENT_DEPOSITO_STK`),
               SUM(st.`CANTIDAD_ENT_REGULAR_STK`), SUM(st.`CANTIDAD_SAL_TRASPASO_STK`),
               SUM(st.`CANTIDAD_SAL_DEPOSITO_STK`), SUM(st.`CANTIDAD_SAL_ALBVENTA_STK`),
               SUM(st.`CANTIDAD_SAL_VENTA_STK`)
          FROM `tmp_bat_sku` s
          JOIN `fza_articulos_stockactual` st
            ON st.`CODIGO_UNIDAD_STK` = s.`CODIGO_UNIDAD`
           AND st.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_bat_alm`)
         GROUP BY s.`CODIGO_ART`, IF(v_por_alm, st.`CODIGO_ALM_STK`, ''),
                  s.`POSICION`, s.`COLOR`;
    ELSE
        /* Entre fechas: movimientos del periodo + existencias */
        /* reconstruidas desde el stock actual. */
        INSERT INTO `tmp_bat_base`
            (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
             `POSICION`,
             `EXI_INI`, `ENT`, `SAL`, `VEN`, `EXI_FIN`,
             `ENT_COMPRA`, `ENT_ALBENTRADA`, `ENT_TRASPASO`, `ENT_DEPOSITO`,
             `ENT_REGULAR`, `SAL_TRASPASO`, `SAL_DEPOSITO`, `SAL_ALBVENTA`,
             `SAL_VENTA`)
        SELECT s.`CODIGO_ART`, COALESCE(mv.`ALM`, ''),
               s.`COLOR`, MIN(s.`COLOR_HEX`),
               MIN(s.`ORDEN_COLOR`), s.`POSICION`,
               /* Existencias iniciales: stock actual menos movimientos */
               /* firmados desde p_DESDE (inclusive). */
               SUM(COALESCE(mv.`STOCK_NOW`, 0) - COALESCE(mv.`DELTA_DESDE`, 0)),
               SUM(COALESCE(mv.`ENT`, 0)),
               SUM(COALESCE(mv.`SAL`, 0)),
               SUM(COALESCE(mv.`VEN`, 0)),
               /* Existencias finales: stock actual menos movimientos */
               /* firmados posteriores a p_HASTA. */
               SUM(COALESCE(mv.`STOCK_NOW`, 0) - COALESCE(mv.`DELTA_HASTA`, 0)),
               SUM(COALESCE(mv.`ENT_COMPRA`, 0)), SUM(COALESCE(mv.`ENT_ALBENTRADA`, 0)),
               SUM(COALESCE(mv.`ENT_TRASPASO`, 0)), SUM(COALESCE(mv.`ENT_DEPOSITO`, 0)),
               SUM(COALESCE(mv.`ENT_REGULAR`, 0)), SUM(COALESCE(mv.`SAL_TRASPASO`, 0)),
               SUM(COALESCE(mv.`SAL_DEPOSITO`, 0)), SUM(COALESCE(mv.`SAL_ALBVENTA`, 0)),
               SUM(COALESCE(mv.`SAL_VENTA`, 0))
          FROM `tmp_bat_sku` s
          LEFT JOIN (
                /* Stock actual y movimientos firmados unificados por unidad y */
                /* almacén (UNION ALL para sumarlos en el mismo grano). Si no se */
                /* agrupa por almacén, ALM = '' y todo colapsa en un único */
                /* bucket (resultado idéntico al cálculo agregado anterior). */
                SELECT u.`CODIGO_UNIDAD`, u.`ALM`,
                       SUM(u.`STOCK_NOW`)      AS `STOCK_NOW`,
                       SUM(u.`ENT`)            AS `ENT`,
                       SUM(u.`SAL`)            AS `SAL`,
                       SUM(u.`VEN`)            AS `VEN`,
                       SUM(u.`ENT_COMPRA`)     AS `ENT_COMPRA`,
                       SUM(u.`ENT_ALBENTRADA`) AS `ENT_ALBENTRADA`,
                       SUM(u.`ENT_TRASPASO`)   AS `ENT_TRASPASO`,
                       SUM(u.`ENT_DEPOSITO`)   AS `ENT_DEPOSITO`,
                       SUM(u.`ENT_REGULAR`)    AS `ENT_REGULAR`,
                       SUM(u.`SAL_TRASPASO`)   AS `SAL_TRASPASO`,
                       SUM(u.`SAL_DEPOSITO`)   AS `SAL_DEPOSITO`,
                       SUM(u.`SAL_ALBVENTA`)   AS `SAL_ALBVENTA`,
                       SUM(u.`SAL_VENTA`)      AS `SAL_VENTA`,
                       SUM(u.`DELTA_DESDE`)    AS `DELTA_DESDE`,
                       SUM(u.`DELTA_HASTA`)    AS `DELTA_HASTA`
                  FROM (
                        SELECT st2.`CODIGO_UNIDAD_STK` AS `CODIGO_UNIDAD`,
                               IF(v_por_alm, st2.`CODIGO_ALM_STK`, '') AS `ALM`,
                               st2.`CANTIDAD_STK` AS `STOCK_NOW`,
                               0 AS `ENT`, 0 AS `SAL`, 0 AS `VEN`,
                               0 AS `ENT_COMPRA`, 0 AS `ENT_ALBENTRADA`,
                               0 AS `ENT_TRASPASO`, 0 AS `ENT_DEPOSITO`,
                               0 AS `ENT_REGULAR`, 0 AS `SAL_TRASPASO`,
                               0 AS `SAL_DEPOSITO`, 0 AS `SAL_ALBVENTA`,
                               0 AS `SAL_VENTA`, 0 AS `DELTA_DESDE`,
                               0 AS `DELTA_HASTA`
                          FROM `fza_articulos_stockactual` st2
                         WHERE st2.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_bat_alm`)
                           /* Solo los SKUs del informe (IDX_STK_UNIDAD): no */
                           /* recorrer todo el stock para descartarlo al unir. */
                           AND st2.`CODIGO_UNIDAD_STK` IN
                               (SELECT `CODIGO_UNIDAD` FROM `tmp_bat_sku`)
                        UNION ALL
                        SELECT m.`CODIGO_UNIDAD_MOV`,
                               IF(v_por_alm, m.`CODIGO_ALM_MOV`, ''),
                               0,
                               IF(m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_MOV` = 'S'
                                  AND m.`TIPO_DOC_MOV` IN ('VE', 'FC', 'AV')
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'AC' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'AE' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` IN ('TR', 'AT', 'TA') AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'DP' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'IN' AND m.`TIPO_MOV` = 'E'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` IN ('TR', 'AT', 'TA') AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'DP' AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` = 'AV' AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(m.`TIPO_DOC_MOV` IN ('VE', 'FC') AND m.`TIPO_MOV` = 'S'
                                  AND DATE(m.`FECHA_MOV`) BETWEEN v_desde AND v_hasta,
                                  m.`CANTIDAD_MOV`, 0),
                               IF(DATE(m.`FECHA_MOV`) >= v_desde,
                                  IF(m.`TIPO_MOV` = 'E', m.`CANTIDAD_MOV`,
                                     -m.`CANTIDAD_MOV`), 0),
                               IF(DATE(m.`FECHA_MOV`) > v_hasta,
                                  IF(m.`TIPO_MOV` = 'E', m.`CANTIDAD_MOV`,
                                     -m.`CANTIDAD_MOV`), 0)
                          FROM `fza_movimientos_almacen` m
                         WHERE m.`ESACTIVO_MOV` = 'S'
                           AND m.`CODIGO_ALM_MOV` IN (SELECT `CODIGO_ALM` FROM `tmp_bat_alm`)
                           /* Solo los SKUs del informe (igual que el LEFT JOIN */
                           /* de abajo): no agrega TODA la tabla de movimientos */
                           /* para descartarla. Indexado por CODIGO_UNIDAD_MOV. */
                           AND m.`CODIGO_UNIDAD_MOV` IN
                               (SELECT `CODIGO_UNIDAD` FROM `tmp_bat_sku`)
                           /* Movs. anteriores a 'desde' aportan 0 a las 16 */
                           /* medidas (todas exigen fecha >= desde): se podan. */
                           AND m.`FECHA_MOV` >= v_desde
                       ) u
                 GROUP BY u.`CODIGO_UNIDAD`, u.`ALM`
               ) mv ON mv.`CODIGO_UNIDAD` = s.`CODIGO_UNIDAD`
         GROUP BY s.`CODIGO_ART`, COALESCE(mv.`ALM`, ''),
                  s.`POSICION`, s.`COLOR`;
    END IF;

    /* ----------------------------------------------------------------- */
    /* 3b) Ventas REALES por (artículo, almacén, color, posición) desde las */
    /*     líneas de factura. Es la fuente de verdad de las ventas (cantidad */
    /*     E importe): los acumulados de stock (CANTIDAD_SAL_VENTA_STK) pueden */
    /*     no estar mantenidos y dar cantidad 0 aunque haya venta. La banda VEN */
    /*     toma de aquí su CANTIDAD por talla (antes salía del acumulado y no */
    /*     cuadraba con el importe, que ya venía de facturas). Mismo filtro de */
    /*     almacén/periodo y mismo conjunto de SKUs (tmp_bat_sku) que la */
    /*     valoración de ventas (vt) del SELECT final, para que cantidad e */
    /*     importe sean coherentes. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_ven`;
    CREATE TEMPORARY TABLE `tmp_bat_ven` (
        `CODIGO_ART` VARCHAR(20)   NOT NULL,
        `CODIGO_ALM` VARCHAR(20)   NOT NULL DEFAULT '',
        `COLOR`      VARCHAR(100)  NOT NULL DEFAULT '',
        `POSICION`   INT           NOT NULL,
        `VEN_QTY`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `POSICION`)
    );
    INSERT INTO `tmp_bat_ven`
    SELECT s.`CODIGO_ART`,
           IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, ''),
           s.`COLOR`, s.`POSICION`,
           SUM(fl.`CANTIDAD_FACLIN`)
      FROM `fza_facturas_lineas` fl
      JOIN `fza_facturas` f
        ON f.`NUMERO_FAC` = fl.`NUMERO_FAC_FACLIN`
       AND f.`SERIE_FAC` = fl.`SERIE_FAC_FACLIN`
      JOIN `tmp_bat_sku` s
        ON s.`CODIGO_UNIDAD` = fl.`CODIGO_UNIDAD_FACLIN`
     WHERE fl.`CODIGO_ALM_FACLIN` IN (SELECT `CODIGO_ALM` FROM `tmp_bat_alm`)
       AND (p_MODO = 'A'
            OR DATE(f.`FECHA_FAC`) BETWEEN v_desde AND v_hasta)
     GROUP BY s.`CODIGO_ART`,
              IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, ''),
              s.`COLOR`, s.`POSICION`;

    /* ----------------------------------------------------------------- */
    /* 4) Desdoblar en bandas (forma larga). Cada banda es un INSERT */
    /*    independiente (referencia tmp_bat_base una sola vez) y se filtra */
    /*    por modo/desglosado. ES_COSTE marca cómo se valora la banda. */
    /*    ORDEN_BANDA fija el orden vertical del informe. */
    /* ----------------------------------------------------------------- */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_medidas`;
    CREATE TEMPORARY TABLE `tmp_bat_medidas` (
        `CODIGO_ART`     VARCHAR(20)  NOT NULL,
        `CODIGO_ALM`     VARCHAR(20)  NOT NULL DEFAULT '',
        `COLOR`          VARCHAR(100) NULL,
        `COLOR_HEX`      VARCHAR(7)   NULL,
        `ORDEN_COLOR`    INT          NOT NULL DEFAULT 0,
        `POSICION`       INT          NOT NULL,
        `BANDA`          VARCHAR(20)  NOT NULL,
        `ORDEN_BANDA`    INT          NOT NULL,
        `ETIQUETA_BANDA` VARCHAR(40)  NOT NULL,
        `ES_COSTE`       TINYINT      NOT NULL DEFAULT 0,
        `CANTIDAD`       DECIMAL(19,6) NOT NULL DEFAULT 0,
        KEY `IDX_BAT_MED` (`CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `ORDEN_BANDA`)
    );

    /* Existencias iniciales: solo entre fechas. */
    IF p_MODO = 'F' THEN
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'EXIINI', 10, 'Existencias iniciales', 1, `EXI_INI`
          FROM `tmp_bat_base`;
    END IF;
    /* Simplificado (F) o acumulados (A). Entradas = albaranes (compra + alb. */
    /* entrada) + recuentos (regularizaciones) + traspasos NETOS (entrada - */
    /* salida). SIN depósitos y SIN banda Salidas: las ventas van en su banda. */
    /* Balance: Ex.ini + Entradas - Ventas = Ex.final (los depósitos quedan */
    /* fuera de la ecuación, según lo pedido). */
    IF (p_MODO = 'F' AND p_DESGLOSADO = 'N') OR p_MODO = 'A' THEN
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'ENT', 20, 'Entradas', 1,
               `ENT_COMPRA` + `ENT_ALBENTRADA` + `ENT_REGULAR`
                 + `ENT_TRASPASO` - `SAL_TRASPASO`
          FROM `tmp_bat_base`;
        /* Cantidad de la banda de ventas: de facturas (tmp_bat_ven) por talla, */
        /* no del acumulado de stock. LEFT JOIN sobre la base para conservar la */
        /* fila de ventas de cada color (0 si no hubo venta). */
        INSERT INTO `tmp_bat_medidas`
        SELECT b.`CODIGO_ART`, b.`CODIGO_ALM`, b.`COLOR`, b.`COLOR_HEX`,
               b.`ORDEN_COLOR`, b.`POSICION`,
               'VEN', 50, 'Ventas', 0, COALESCE(v.`VEN_QTY`, 0)
          FROM `tmp_bat_base` b
          LEFT JOIN `tmp_bat_ven` v
            ON v.`CODIGO_ART` = b.`CODIGO_ART`
           AND v.`CODIGO_ALM` = b.`CODIGO_ALM`
           AND v.`COLOR` = b.`COLOR`
           AND v.`POSICION` = b.`POSICION`;
    END IF;
    /* Entradas desglosadas: solo modo entre fechas desglosado. Mismos */
    /* subtipos que la consulta de stock (Ctrl+U), con traspasos y depósitos */
    /* netos (entrada - salida) y sin bandas de salida salvo alb. venta. */
    IF p_MODO = 'F' AND p_DESGLOSADO = 'S' THEN
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'ENTCMP', 21, 'Ent. compra', 1, `ENT_COMPRA`
          FROM `tmp_bat_base`;
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'ENTALB', 22, 'Alb. entrada', 1, `ENT_ALBENTRADA`
          FROM `tmp_bat_base`;
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'ENTTRA', 23, 'Traspasos (neto)', 1,
               `ENT_TRASPASO` - `SAL_TRASPASO`
          FROM `tmp_bat_base`;
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'ENTDEP', 24, 'Depósitos (neto)', 1,
               `ENT_DEPOSITO` - `SAL_DEPOSITO`
          FROM `tmp_bat_base`;
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'ENTREG', 25, 'Regulariz.', 1, `ENT_REGULAR`
          FROM `tmp_bat_base`;
        /* Sal. traspaso / Sal. depósito ya no salen: se han neteado en sus */
        /* bandas de entrada (Traspasos/Depósitos neto). Albarán de venta sí se */
        /* mantiene (es una venta). */
        INSERT INTO `tmp_bat_medidas`
        SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
               `POSICION`,
               'SALALB', 43, 'Alb. venta', 0, `SAL_ALBVENTA`
          FROM `tmp_bat_base`;
        /* Cantidad de ventas: de facturas (tmp_bat_ven) por talla, igual que */
        /* en simplificado/acumulados (no del acumulado SAL_VENTA del stock). */
        INSERT INTO `tmp_bat_medidas`
        SELECT b.`CODIGO_ART`, b.`CODIGO_ALM`, b.`COLOR`, b.`COLOR_HEX`,
               b.`ORDEN_COLOR`, b.`POSICION`,
               'VEN', 50, 'Ventas', 0, COALESCE(v.`VEN_QTY`, 0)
          FROM `tmp_bat_base` b
          LEFT JOIN `tmp_bat_ven` v
            ON v.`CODIGO_ART` = b.`CODIGO_ART`
           AND v.`CODIGO_ALM` = b.`CODIGO_ALM`
           AND v.`COLOR` = b.`COLOR`
           AND v.`POSICION` = b.`POSICION`;
    END IF;
    /* Existencias finales: siempre. */
    INSERT INTO `tmp_bat_medidas`
    SELECT `CODIGO_ART`, `CODIGO_ALM`, `COLOR`, `COLOR_HEX`, `ORDEN_COLOR`,
           `POSICION`,
           'EXIFIN', 90, 'Existencias finales', 1, `EXI_FIN`
      FROM `tmp_bat_base`;
    /* Selección de bandas: sin selección = todas las de la configuración */
    /* (modo/detalle). FIND_IN_SET sobre el código de banda. */
    IF p_BANDAS <> '' THEN
        DELETE FROM `tmp_bat_medidas` WHERE NOT FIND_IN_SET(`BANDA`, p_BANDAS);
    END IF;

    /* ----------------------------------------------------------------- */
    /* 5) Pivote final por (artículo, color, banda) y enriquecido con */
    /*    familia, etiquetas de cabecera, foto y valoración. El pivote */
    /*    va en una subconsulta para no mezclar agregados con columnas */
    /*    de adorno (ONLY_FULL_GROUP_BY-safe). */
    /* ----------------------------------------------------------------- */
    SELECT
        COALESCE(fam.`ORDEN_FAM`, 999999)             AS `ORDEN_FAM`,
        art.`CODIGO_FAM_ART`                          AS `CODIGO_FAM`,
        COALESCE(fam.`DESCRIPCION_FAM`,
                 fam.`NOMBRE_FAM_FAM`, art.`CODIGO_FAM_ART`) AS `DESCRIPCION_FAM`,
        p.`CODIGO_ART`                                AS `CODIGO_ART_ART`,
        art.`DESCRIPCION_ART`                         AS `DESCRIPCION_ART`,
        p.`CODIGO_ALM`                                AS `CODIGO_ALM`,
        COALESCE(alm.`NOMBRE_ALM_ALM`, '')            AS `NOMBRE_ALM`,
        prov.`REF_PROVEEDOR_AP`                       AS `REF_PRV`,
        ROUND(COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0), 2) AS `COSTE_ART`,
        ROUND(COALESCE(pvp.`PVP`, 0), 2)              AS `PVP_ART`,
        p.`ORDEN_COLOR`, p.`COLOR`, p.`COLOR_HEX`,
        p.`ORDEN_BANDA`, p.`BANDA`, p.`ETIQUETA_BANDA`, p.`ES_COSTE`,
        et.`ETIQ_T01`, et.`ETIQ_T02`, et.`ETIQ_T03`, et.`ETIQ_T04`,
        et.`ETIQ_T05`, et.`ETIQ_T06`, et.`ETIQ_T07`, et.`ETIQ_T08`,
        et.`ETIQ_T09`, et.`ETIQ_T10`, et.`ETIQ_T11`, et.`ETIQ_T12`,
        et.`ETIQ_T13`, et.`ETIQ_T14`,
        p.`T01`, p.`T02`, p.`T03`, p.`T04`, p.`T05`, p.`T06`, p.`T07`,
        p.`T08`, p.`T09`, p.`T10`, p.`T11`, p.`T12`, p.`T13`, p.`T14`,
        p.`CANTIDAD`,
        ROUND(IF(p.`BANDA` = 'VEN',
                 IF(p.`CANTIDAD` <> 0,
                    COALESCE(vt.`VEN_IMPORTE`, 0) / p.`CANTIDAD`, 0),
                 IF(p.`ES_COSTE` = 1,
                    COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0),
                    COALESCE(pvp.`PVP`, 0))), 2)        AS `PRECIO`,
        /* Importe de la banda. La banda de ventas (VEN) se valora al PRECIO */
        /* REAL de venta (con descuentos, con IVA) tomado de fza_facturas_lineas; */
        /* el resto a coste/PMP o a tarifa según ES_COSTE. */
        ROUND(IF(p.`BANDA` = 'VEN',
                 COALESCE(vt.`VEN_IMPORTE`, 0),
                 p.`CANTIDAD` * IF(p.`ES_COSTE` = 1,
                   COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0),
                   COALESCE(pvp.`PVP`, 0))), 2)          AS `IMPORTE`,
        /* Ventas reales (con descuento, con IVA) solo en la banda de ventas */
        /* (VEN); 0 en el resto. Al sumarla por artículo/grupo/total da el */
        /* acumulado de ventas (las existencias se leen banda a banda; las */
        /* ventas hay que irlas sumando). */
        ROUND(IF(p.`BANDA` = 'VEN', COALESCE(vt.`VEN_IMPORTE`, 0), 0), 2)
                                                      AS `VENTAS`,
        /* Existencias finales aisladas (cantidad y valor a PMP) solo en la */
        /* banda EXIFIN, 0 en el resto. Permite que el total por grupo/general */
        /* muestre SOLO el stock final, sin mezclar entradas/salidas/ventas. */
        IF(p.`BANDA` = 'EXIFIN', p.`CANTIDAD`, 0)     AS `EXIFIN_CANT`,
        ROUND(IF(p.`BANDA` = 'EXIFIN',
                 p.`CANTIDAD` * COALESCE(NULLIF(cst.`COSTE`, 0),
                                         prov.`COSTE_PRV`, 0),
                 0), 2)                               AS `EXIFIN_IMP`,
        /* Niveles de agrupación configurables. GRUPOn_COD identifica el grupo */
        /* (para el corte y el orden); GRUPOn_ETIQ es la etiqueta a mostrar en */
        /* la cabecera/resumen. Si el nivel no está activo (''), salen vacíos y */
        /* el cliente no dibuja banda de grupo a ese nivel. */
        CASE p_NIVEL1
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN p.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO1_COD`,
        CASE p_NIVEL1
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`,
                          art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), p.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO1_ETIQ`,
        CASE p_NIVEL2
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN p.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO2_COD`,
        CASE p_NIVEL2
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`,
                          art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), p.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO2_ETIQ`,
        CASE p_NIVEL3
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN p.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO3_COD`,
        CASE p_NIVEL3
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`,
                          art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), p.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO3_ETIQ`
      FROM (
            SELECT m.`CODIGO_ART`, m.`CODIGO_ALM`, m.`COLOR`,
                   MIN(m.`COLOR_HEX`) AS `COLOR_HEX`,
                   MIN(m.`ORDEN_COLOR`) AS `ORDEN_COLOR`,
                   m.`BANDA`, m.`ORDEN_BANDA`, m.`ETIQUETA_BANDA`, m.`ES_COSTE`,
                   SUM(IF(m.`POSICION` =  1, m.`CANTIDAD`, 0)) AS `T01`,
                   SUM(IF(m.`POSICION` =  2, m.`CANTIDAD`, 0)) AS `T02`,
                   SUM(IF(m.`POSICION` =  3, m.`CANTIDAD`, 0)) AS `T03`,
                   SUM(IF(m.`POSICION` =  4, m.`CANTIDAD`, 0)) AS `T04`,
                   SUM(IF(m.`POSICION` =  5, m.`CANTIDAD`, 0)) AS `T05`,
                   SUM(IF(m.`POSICION` =  6, m.`CANTIDAD`, 0)) AS `T06`,
                   SUM(IF(m.`POSICION` =  7, m.`CANTIDAD`, 0)) AS `T07`,
                   SUM(IF(m.`POSICION` =  8, m.`CANTIDAD`, 0)) AS `T08`,
                   SUM(IF(m.`POSICION` =  9, m.`CANTIDAD`, 0)) AS `T09`,
                   SUM(IF(m.`POSICION` = 10, m.`CANTIDAD`, 0)) AS `T10`,
                   SUM(IF(m.`POSICION` = 11, m.`CANTIDAD`, 0)) AS `T11`,
                   SUM(IF(m.`POSICION` = 12, m.`CANTIDAD`, 0)) AS `T12`,
                   SUM(IF(m.`POSICION` = 13, m.`CANTIDAD`, 0)) AS `T13`,
                   SUM(IF(m.`POSICION` = 14, m.`CANTIDAD`, 0)) AS `T14`,
                   SUM(m.`CANTIDAD`) AS `CANTIDAD`
              FROM `tmp_bat_medidas` m
             GROUP BY m.`CODIGO_ART`, m.`CODIGO_ALM`, m.`COLOR`, m.`BANDA`,
                      m.`ORDEN_BANDA`, m.`ETIQUETA_BANDA`, m.`ES_COSTE`
           ) p
      JOIN `fza_articulos` art ON art.`CODIGO_ART_ART` = p.`CODIGO_ART`
      LEFT JOIN `fza_articulos_familias` fam
        ON fam.`CODIGO_FAM_FAM` = art.`CODIGO_FAM_ART`
      LEFT JOIN `tmp_bat_fam_grp` fg ON fg.`CODIGO_FAM` = art.`CODIGO_FAM_ART`
      LEFT JOIN `fza_almacenes` alm ON alm.`CODIGO_ALM_ALM` = p.`CODIGO_ALM`
      LEFT JOIN `tmp_bat_etiq` et ON et.`CODIGO_ART` = p.`CODIGO_ART`
      LEFT JOIN (
            SELECT t.`CODIGO_ART_ARTTAR` AS `CODIGO_ART`,
                   MAX(t.`PRECIO_FINAL_ARTTAR`) AS `PVP`
              FROM `fza_articulos_tarifas` t
             WHERE t.`CODIGO_TAR_ARTTAR` = v_tarifa
               /* Solo los artículos del informe (se une por artículo filtrado). */
               AND t.`CODIGO_ART_ARTTAR` IN
                   (SELECT `CODIGO_ART` FROM `tmp_bat_arts`)
               AND IFNULL(t.`CODIGO_UNIDAD_ARTTAR`, '') = ''
               AND t.`ESACTIVO_ARTTAR` = 'S'
               AND (t.`FECHA_DESDE_ARTTAR` IS NULL
                    OR t.`FECHA_DESDE_ARTTAR` <= CURRENT_DATE)
               AND (t.`FECHA_HASTA_ARTTAR` IS NULL
                    OR t.`FECHA_HASTA_ARTTAR` >= CURRENT_DATE)
             GROUP BY t.`CODIGO_ART_ARTTAR`
           ) pvp ON pvp.`CODIGO_ART` = p.`CODIGO_ART`
      LEFT JOIN (
            SELECT sk.`CODIGO_ART_SKU` AS `CODIGO_ART`,
                   SUM(st.`VALOR_TOTAL_STK`) AS `VAL`,
                   SUM(st.`CANTIDAD_STK`)    AS `CAN`,
                   IF(SUM(st.`CANTIDAD_STK`) <> 0,
                      SUM(st.`VALOR_TOTAL_STK`) / SUM(st.`CANTIDAD_STK`), 0) AS `COSTE`
              FROM `fza_articulos_stockactual` st
              JOIN `fza_articulos_skus` sk
                ON sk.`CODIGO_UNIDAD_SKU` = st.`CODIGO_UNIDAD_STK`
             WHERE st.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_bat_alm`)
               /* Solo los SKUs del informe (se une por artículo ya filtrado). */
               AND st.`CODIGO_UNIDAD_STK` IN
                   (SELECT `CODIGO_UNIDAD` FROM `tmp_bat_sku`)
             GROUP BY sk.`CODIGO_ART_SKU`
           ) cst ON cst.`CODIGO_ART` = p.`CODIGO_ART`
      LEFT JOIN (
            SELECT ap.`CODIGO_ART_AP` AS `CODIGO_ART`,
                   MAX(ap.`REF_PROVEEDOR_AP`)   AS `REF_PROVEEDOR_AP`,
                   MAX(ap.`PRECIO_ULT_COMPRA_AP`) AS `COSTE_PRV`,
                   MAX(ap.`CODIGO_PRV_AP`)      AS `CODIGO_PRV`,
                   MAX(pr.`RAZON_SOCIAL_PRV`)   AS `RAZON`
              FROM `fza_articulos_proveedores` ap
              LEFT JOIN `fza_proveedores` pr
                ON pr.`CODIGO_PRV_PRV` = ap.`CODIGO_PRV_AP`
             WHERE ap.`ESPROVEEDORPRINCIPAL_AP` = 'S'
               /* Solo los artículos del informe (se une por artículo filtrado). */
               AND ap.`CODIGO_ART_AP` IN
                   (SELECT `CODIGO_ART` FROM `tmp_bat_arts`)
             GROUP BY ap.`CODIGO_ART_AP`
           ) prov ON prov.`CODIGO_ART` = p.`CODIGO_ART`
      /* Temporada EFECTIVA por color (Fase 3): la vista de propiedades */
      /* efectivas resuelve color -> articulo; tmp_bat_sku da el color del */
      /* SKU. Los SKU de un mismo color comparten temporada (el MAX colapsa */
      /* sin ambiguedad). Sin datos de color resuelve al valor de articulo. */
      LEFT JOIN (
            SELECT s.`CODIGO_ART` AS `CODIGO_ART`, s.`COLOR` AS `COLOR`,
                   MAX(COALESCE(e.`VALOR_PV`,
                                e.`VALOR_LIBRE_ARTPROP`)) AS `TEMPORADA`
              FROM `tmp_bat_sku` s
              JOIN `vi_articulos_propiedades_efectivas` e
                ON e.`CODIGO_UNIDAD_SKU` = s.`CODIGO_UNIDAD`
               AND e.`CODIGO_PROP_ARTPROP` = 'TEMPORADA'
             GROUP BY s.`CODIGO_ART`, s.`COLOR`
           ) tmp ON tmp.`CODIGO_ART` = p.`CODIGO_ART`
                AND tmp.`COLOR` = p.`COLOR`
      LEFT JOIN (
            /* Ventas REALES (con descuento, con IVA) por (artículo, almacén, */
            /* color), de las líneas de factura/ticket. Periodo por fecha de */
            /* factura (entre fechas) o histórico (acumulados). Se enlaza el SKU */
            /* de la línea a tmp_bat_sku para resolver artículo/color y restringir */
            /* a los artículos filtrados. */
            SELECT s.`CODIGO_ART`,
                   IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, '') AS `CODIGO_ALM`,
                   s.`COLOR`,
                   SUM(fl.`CANTIDAD_FACLIN`) AS `VEN_QTY`,
                   SUM(fl.`TOTAL_FACLIN`)    AS `VEN_IMPORTE`
              FROM `fza_facturas_lineas` fl
              JOIN `fza_facturas` f
                ON f.`NUMERO_FAC` = fl.`NUMERO_FAC_FACLIN`
               AND f.`SERIE_FAC` = fl.`SERIE_FAC_FACLIN`
              JOIN `tmp_bat_sku` s
                ON s.`CODIGO_UNIDAD` = fl.`CODIGO_UNIDAD_FACLIN`
             WHERE fl.`CODIGO_ALM_FACLIN` IN (SELECT `CODIGO_ALM` FROM `tmp_bat_alm`)
               AND (p_MODO = 'A'
                    OR DATE(f.`FECHA_FAC`) BETWEEN v_desde AND v_hasta)
             GROUP BY s.`CODIGO_ART`,
                      IF(v_por_alm, fl.`CODIGO_ALM_FACLIN`, ''), s.`COLOR`
           ) vt ON vt.`CODIGO_ART` = p.`CODIGO_ART`
               AND vt.`CODIGO_ALM` = p.`CODIGO_ALM`
               AND vt.`COLOR` = p.`COLOR`
     ORDER BY `GRUPO1_COD`, `GRUPO2_COD`, `GRUPO3_COD`,
              COALESCE(fam.`ORDEN_FAM`, 999999), art.`CODIGO_FAM_ART`,
              p.`CODIGO_ART`, p.`ORDEN_COLOR`, p.`COLOR`, p.`ORDEN_BANDA`;

    /* Limpieza de temporales para no arrastrarlas en la sesión. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_medidas`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_ven`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_base`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_sku`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_etiq`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_pos_arts`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_pos`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_arts`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_fam_grp`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_fam`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_bat_alm`;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_CAJA_STOCK_PIVOTADO
DROP PROCEDURE IF EXISTS `PRC_GET_CAJA_STOCK_PIVOTADO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_CAJA_STOCK_PIVOTADO`(IN p_input VARCHAR(50))
SQL SECURITY INVOKER
BEGIN
    DECLARE v_codigo_articulo VARCHAR(20);
    DECLARE v_es_sku BOOLEAN DEFAULT FALSE;

    /* Variables para identificar que es Talla (Pivot) y que es Color (Grupo) */
    DECLARE v_id_atributo_pivot VARCHAR(20);  /* Ej: TAL */
    DECLARE v_id_atributo_grupo VARCHAR(20);  /* Ej: CO */

    /* Variable para filtrar si entramos con un SKU especifico (Ej: NEGRO) */
    DECLARE v_valor_grupo_filtro VARCHAR(50) DEFAULT NULL;

    DECLARE v_columnas_dinamicas TEXT;

    /* 1. RESOLUCION DE IDENTIDAD (¿Es Padre o SKU?)
       Antes: 2 sub-queries secuenciales (~100ms cada una con overhead SP).
       Ahora: COALESCE en una sola sentencia. PK seek en fza_articulos
       primero (el caso comun); si devuelve NULL, PK seek en
       fza_articulos_skus. El optimizador evalua el segundo SELECT solo
       cuando el primero da NULL.
       Si el resultado difiere del input literal, era un SKU. */
    SELECT COALESCE(
        (SELECT CODIGO_ART_ART
           FROM fza_articulos
          WHERE CODIGO_ART_ART = p_input
          LIMIT 1),
        (SELECT CODIGO_ART_SKU
           FROM fza_articulos_skus
          WHERE CODIGO_UNIDAD_SKU = p_input
          LIMIT 1)
    ) INTO v_codigo_articulo;

    IF v_codigo_articulo IS NOT NULL AND v_codigo_articulo <> p_input THEN
        SET v_es_sku = TRUE;
    END IF;

    /* 2. ESTRATEGIA DE ATRIBUTOS
       Antes: SET v_id_atributo_pivot = (SELECT ... 4-way JOIN sk -> ask -> av -> va
              WHERE sk.CODIGO_ART_SKU = v_codigo_articulo ORDER BY va.ORDEN_VA DESC LIMIT 1)
              + idem para el grupo. 2 round-trips, 8 JOINs en total.
       Ahora: PK seek sobre fza_articulos para sacar TIPO_VARIACION_ART, y
              index seek sobre fza_variaciones_atributos. Los atributos de
              la variacion estan definidos ahi, no hace falta recorrer SKUs.
              Mismo cambio que metimos en ActualizarColumnasDinamicas. */
    IF v_codigo_articulo IS NOT NULL THEN
        SELECT vat.ID_ATB_VA
          INTO v_id_atributo_pivot
          FROM fza_articulos art
          JOIN fza_variaciones_atributos vat
            ON vat.ID_VAR_VA = art.TIPO_VARIACION_ART
         WHERE art.CODIGO_ART_ART = v_codigo_articulo
         ORDER BY vat.ORDEN_VA DESC
         LIMIT 1;

        SELECT vat.ID_ATB_VA
          INTO v_id_atributo_grupo
          FROM fza_articulos art
          JOIN fza_variaciones_atributos vat
            ON vat.ID_VAR_VA = art.TIPO_VARIACION_ART
         WHERE art.CODIGO_ART_ART = v_codigo_articulo
           AND vat.ID_ATB_VA <> COALESCE(v_id_atributo_pivot, '')
         ORDER BY vat.ORDEN_VA DESC
         LIMIT 1;
    END IF;

    /* 3. SI TENEMOS ESTRUCTURA PARA PIVOTAR... */
    IF v_id_atributo_pivot IS NOT NULL THEN

        /* 3.1 Si es SKU, detectamos el valor del atributo "Grupo".
           Sin cambios — 2 JOINs filtrados por PK del SKU. */
        IF v_es_sku = TRUE AND v_id_atributo_grupo IS NOT NULL THEN
            SET v_valor_grupo_filtro = (
                SELECT av.AV
                  FROM fza_atributos_sku ask
                  JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
                 WHERE ask.CODIGO_UNIDAD_SKU_SA = p_input
                   AND av.ID_VA_AV = v_id_atributo_grupo
                 LIMIT 1
            );
        END IF;

        /* 3.2 Construir columnas dinamicas (S, M, L...).
           Sin cambios — necesitamos los AV REALES presentes en los SKUs del
           articulo, no los del catalogo (un articulo puede no usar todas las
           tallas posibles). Filtrado por CODIGO_ART_SKU (IDX_SKU_ART_ACT) y
           ID_VA_AV (IDX_VAR_AV). */
        SELECT GROUP_CONCAT(DISTINCT
            CONCAT(
                'SUM(CASE WHEN av_p.AV = ''', REPLACE(av.AV, '''', ''''''),
                ''' THEN stk.CANTIDAD_STK ELSE 0 END) AS `', REPLACE(av.AV, '`', '``'), '`'
            )
            ORDER BY av.ID_AV
        ) INTO v_columnas_dinamicas
        FROM fza_articulos_skus sk
        JOIN fza_atributos_sku ask ON sk.CODIGO_UNIDAD_SKU = ask.CODIGO_UNIDAD_SKU_SA
        JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
        WHERE sk.CODIGO_ART_SKU = v_codigo_articulo
          AND av.ID_VA_AV = v_id_atributo_pivot;

        /* 3.3 Construir Query Final — sin cambios. */
        IF v_columnas_dinamicas IS NOT NULL THEN
            SET @sql = CONCAT(
                'SELECT
                    CONCAT(''', v_codigo_articulo, ''',
                        CASE
                            WHEN av_g.AV IS NOT NULL THEN CONCAT(''/'', av_g.AV)
                            ELSE ''''
                        END
                    ) AS Codigo,
                    alm.NOMBRE_ALM_ALM AS Almacen, ',
                    v_columnas_dinamicas, ',
                    SUM(stk.CANTIDAD_STK) AS Total
                 FROM fza_articulos_stockactual stk
                 JOIN fza_almacenes alm ON stk.CODIGO_ALM_STK = alm.CODIGO_ALM_ALM
                 JOIN fza_articulos_skus sk ON stk.CODIGO_UNIDAD_STK = sk.CODIGO_UNIDAD_SKU

                 JOIN fza_atributos_sku ask_p ON sk.CODIGO_UNIDAD_SKU = ask_p.CODIGO_UNIDAD_SKU_SA
                 JOIN fza_atributos_valores av_p ON ask_p.ID_AV_SA = av_p.ID_AV
                    AND av_p.ID_VA_AV = ''', v_id_atributo_pivot, '''

                 LEFT JOIN fza_atributos_sku ask_g ON sk.CODIGO_UNIDAD_SKU = ask_g.CODIGO_UNIDAD_SKU_SA
                 LEFT JOIN fza_atributos_valores av_g ON ask_g.ID_AV_SA = av_g.ID_AV
                    AND av_g.ID_VA_AV = ''', IFNULL(v_id_atributo_grupo, 'xxx'), '''

                 WHERE sk.CODIGO_ART_SKU = ''', v_codigo_articulo, '''
                 ',
                 CASE WHEN v_valor_grupo_filtro IS NOT NULL THEN
                    CONCAT(' AND av_g.AV = ''', REPLACE(v_valor_grupo_filtro, '''', ''''''), ''' ')
                 ELSE '' END, '

                 GROUP BY av_g.AV, alm.NOMBRE_ALM_ALM
                 ORDER BY alm.NOMBRE_ALM_ALM, av_g.AV'
            );

            PREPARE stmt FROM @sql;
            EXECUTE stmt;
            DEALLOCATE PREPARE stmt;

        END IF;
    END IF;

    /* CASO B: FALLBACK (Si no tiene atributos complejos o falla el pivotado) */
    IF v_columnas_dinamicas IS NULL THEN
        SELECT stk.CODIGO_UNIDAD_STK as Codigo,
            alm.NOMBRE_ALM_ALM as Almacen,
            SUM(stk.CANTIDAD_STK) as Stock_Total
        FROM fza_articulos_stockactual stk
        JOIN fza_almacenes alm ON stk.CODIGO_ALM_STK = alm.CODIGO_ALM_ALM
        WHERE stk.CODIGO_UNIDAD_STK = p_input
        GROUP BY stk.CODIGO_UNIDAD_STK, alm.NOMBRE_ALM_ALM
        ORDER BY alm.NOMBRE_ALM_ALM;
    END IF;

END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_CAJA_STOCK_PIVOTADO_ANT
DROP PROCEDURE IF EXISTS `PRC_GET_CAJA_STOCK_PIVOTADO_ANT`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_CAJA_STOCK_PIVOTADO_ANT`(IN p_input VARCHAR(50))
SQL SECURITY INVOKER
BEGIN
    DECLARE v_codigo_articulo VARCHAR(20);
    DECLARE v_es_sku BOOLEAN DEFAULT FALSE;
    DECLARE v_id_atributo_pivot VARCHAR(20);
    DECLARE v_nombre_atributo_pivot VARCHAR(50);
    DECLARE v_columnas_dinamicas TEXT;
    DECLARE v_filtros_fijos TEXT DEFAULT '';
    DECLARE v_sql_query TEXT;

    /* 1. RESOLUCIÓN DE IDENTIDAD (¿Es Artículo padre o es un SKU?) */
    /* Buscamos primero si es un código padre directo */
    SELECT CODIGO_ART_ART INTO v_codigo_articulo 
    FROM fza_articulos WHERE CODIGO_ART_ART = p_input;

    IF v_codigo_articulo IS NULL THEN
        /* Si no es padre, miramos si es un SKU hijo */
        SELECT CODIGO_ART_SKU INTO v_codigo_articulo 
        FROM fza_articulos_skus WHERE CODIGO_UNIDAD_SKU = p_input;
        
        IF v_codigo_articulo IS NOT NULL THEN
            SET v_es_sku = TRUE;
        END IF;
    END IF;

    /* 2. BUSCAR ATRIBUTO PARA PIVOTAR (Talla, Color, etc.) */
    /* Solo intentamos buscar atributos si encontramos un padre válido */
    IF v_codigo_articulo IS NOT NULL THEN
        SELECT va.ID_ATB_VA, va.NOMBRE_VA
        INTO v_id_atributo_pivot, v_nombre_atributo_pivot
        FROM fza_articulos_skus sk
        JOIN fza_atributos_sku ask ON sk.CODIGO_UNIDAD_SKU = ask.CODIGO_UNIDAD_SKU_SA
        JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
        JOIN fza_variaciones_atributos va ON av.ID_VA_AV = va.ID_ATB_VA
        WHERE sk.CODIGO_ART_SKU = v_codigo_articulo
        ORDER BY va.ORDEN_VA DESC
        LIMIT 1;
    END IF;

    /* 3. DECISIÓN DE EJECUCIÓN */

    /* CASO A: TIENE ATRIBUTOS -> HACEMOS PIVOT (Lógica compleja) */
    IF v_id_atributo_pivot IS NOT NULL THEN
    
        /* 3.1 Generar columnas dinámicas (S, M, L...) */
        SELECT GROUP_CONCAT(DISTINCT
            CONCAT(
                'SUM(CASE WHEN av.AV = ''', av.AV, 
                ''' THEN stk.CANTIDAD_STK ELSE 0 END) AS `', av.AV, '`'
            )
            ORDER BY av.ID_AV
        ) INTO v_columnas_dinamicas
        FROM fza_articulos_skus sk
        JOIN fza_atributos_sku ask ON sk.CODIGO_UNIDAD_SKU = ask.CODIGO_UNIDAD_SKU_SA
        JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
        WHERE sk.CODIGO_ART_SKU = v_codigo_articulo
          AND av.ID_VA_AV = v_id_atributo_pivot;

        /* 3.2 Filtros si el usuario escaneó un SKU específico (ej. ZAPATO-ROJO) */
        IF v_es_sku = TRUE THEN
            SELECT GROUP_CONCAT(
                CONCAT(
                    ' AND EXISTS (SELECT 1 FROM fza_atributos_sku f_ask ',
                    ' JOIN fza_atributos_valores f_av ON f_ask.ID_AV_SA = f_av.ID_AV ',
                    ' WHERE f_ask.CODIGO_UNIDAD_SKU_SA = sk.CODIGO_UNIDAD_SKU ',
                    ' AND f_av.ID_VA_AV = ''', av.ID_VA_AV, ''' ',
                    ' AND f_av.AV = ''', av.AV, ''') '
                ) SEPARATOR ' '
            ) INTO v_filtros_fijos
            FROM fza_atributos_sku ask
            JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
            WHERE ask.CODIGO_UNIDAD_SKU_SA = p_input 
              AND av.ID_VA_AV <> v_id_atributo_pivot;
        END IF;

        IF v_filtros_fijos IS NULL THEN SET v_filtros_fijos = ''; END IF;

        /* 3.3 Query Pivotada */
        SET @sql = CONCAT(
            'SELECT sk.CODIGO_UNIDAD_SKU AS Código,
                alm.NOMBRE_ALM_ALM AS Almacén, ', 
                v_columnas_dinamicas, ',
                SUM(stk.CANTIDAD_STK) AS Total
             FROM fza_articulos_stockactual stk
             JOIN fza_almacenes alm ON stk.CODIGO_ALM_STK = alm.CODIGO_ALM_ALM
             JOIN fza_articulos_skus sk ON stk.CODIGO_UNIDAD_STK = sk.CODIGO_UNIDAD_SKU
             JOIN fza_atributos_sku ask ON sk.CODIGO_UNIDAD_SKU = ask.CODIGO_UNIDAD_SKU_SA
             JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
             WHERE sk.CODIGO_ART_SKU = ''', v_codigo_articulo, '''
               AND av.ID_VA_AV = ''', v_id_atributo_pivot, ''' ',
               v_filtros_fijos, '
             GROUP BY alm.NOMBRE_ALM_ALM
             ORDER BY alm.NOMBRE_ALM_ALM'
        );

        PREPARE stmt FROM @sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;

    ELSE
        /* CASO B: NO TIENE ATRIBUTOS O NO ES SKU (Artículo Simple) */
        /* Aquí quitamos el JOIN con fza_articulos_skus para permitir stock directo */
        
        SELECT stk.CODIGO_UNIDAD_STK as Código,  
            alm.NOMBRE_ALM_ALM as Almacén, 
            SUM(stk.CANTIDAD_STK) as `Stock Total`
        FROM fza_articulos_stockactual stk
        JOIN fza_almacenes alm ON stk.CODIGO_ALM_STK = alm.CODIGO_ALM_ALM
        WHERE stk.CODIGO_UNIDAD_STK = p_input /* Buscamos exactamente lo que escribió el usuario */
        GROUP BY alm.NOMBRE_ALM_ALM
        ORDER BY alm.NOMBRE_ALM_ALM;
        
    END IF;

END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_CAJA_STOCK_PIVOTADO_WITHZ
DROP PROCEDURE IF EXISTS `PRC_GET_CAJA_STOCK_PIVOTADO_WITHZ`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_CAJA_STOCK_PIVOTADO_WITHZ`(IN p_input VARCHAR(50))
SQL SECURITY INVOKER
BEGIN
    DECLARE v_codigo_articulo VARCHAR(20);
    DECLARE v_es_sku BOOLEAN DEFAULT FALSE;

    /* Variables para las COLUMNAS (Pivot - Ej: Talla) */
    DECLARE v_id_atributo_pivot VARCHAR(20);
    DECLARE v_nombre_atributo_pivot VARCHAR(50);
    DECLARE v_columnas_dinamicas TEXT;

    /* Variables para las FILAS (Desglose - Ej: Color) */
    DECLARE v_id_atributo_fila VARCHAR(20) DEFAULT NULL;
    DECLARE v_nombre_atributo_fila VARCHAR(50) DEFAULT NULL;
    DECLARE v_select_fila TEXT DEFAULT '';
    DECLARE v_join_fila TEXT DEFAULT '';
    DECLARE v_groupby_fila TEXT DEFAULT '';
    DECLARE v_src_select_fila TEXT DEFAULT '';

    DECLARE v_filtros_fijos TEXT DEFAULT '';
    DECLARE v_sql_query TEXT;

    /* 1. IDENTIFICAR ARTICULO O SKU — COALESCE en una sola sentencia. */
    SELECT COALESCE(
        (SELECT CODIGO_ART_ART
           FROM fza_articulos
          WHERE CODIGO_ART_ART = p_input
          LIMIT 1),
        (SELECT CODIGO_ART_SKU
           FROM fza_articulos_skus
          WHERE CODIGO_UNIDAD_SKU = p_input
          LIMIT 1)
    ) INTO v_codigo_articulo;

    IF v_codigo_articulo IS NOT NULL AND v_codigo_articulo <> p_input THEN
        SET v_es_sku = TRUE;
    END IF;

    /* 2. BUSCAR ATRIBUTO PIVOTE (Para las columnas).
       Optimizado: via TIPO_VARIACION_ART (PK seek + index seek). */
    IF v_codigo_articulo IS NOT NULL THEN
        SELECT vat.ID_ATB_VA, vat.NOMBRE_VA
          INTO v_id_atributo_pivot, v_nombre_atributo_pivot
          FROM fza_articulos art
          JOIN fza_variaciones_atributos vat
            ON vat.ID_VAR_VA = art.TIPO_VARIACION_ART
         WHERE art.CODIGO_ART_ART = v_codigo_articulo
         ORDER BY vat.ORDEN_VA DESC
         LIMIT 1;
    END IF;

    /* 2.1 BUSCAR ATRIBUTO DE FILA (Ej: Color) SI ES UN ARTICULO GENERICO.
       Mantenemos ORDER BY ORDEN_VA ASC (la semantica original del SP _WITHZ
       difiere del PIVOTADO sin Z, que usaba DESC excluyendo el pivot).
       Para variaciones de 2 atributos da el mismo resultado. */
    IF v_codigo_articulo IS NOT NULL AND v_es_sku = FALSE THEN
        SELECT vat.ID_ATB_VA, vat.NOMBRE_VA
          INTO v_id_atributo_fila, v_nombre_atributo_fila
          FROM fza_articulos art
          JOIN fza_variaciones_atributos vat
            ON vat.ID_VAR_VA = art.TIPO_VARIACION_ART
         WHERE art.CODIGO_ART_ART = v_codigo_articulo
           AND vat.ID_ATB_VA <> v_id_atributo_pivot
         ORDER BY vat.ORDEN_VA ASC
         LIMIT 1;
    END IF;

    /* 3. CONSTRUCCION DE LA CONSULTA */
    IF v_id_atributo_pivot IS NOT NULL THEN

        /* Preparamos los textos dinamicos para desglosar el Color en filas */
        IF v_id_atributo_fila IS NOT NULL THEN
            SET v_select_fila = CONCAT(', COALESCE(src.VALOR_FILA, ''-'') AS `', v_nombre_atributo_fila, '`');
            SET v_src_select_fila = ', av_fila.AV AS VALOR_FILA';
            SET v_join_fila = CONCAT(' LEFT JOIN fza_atributos_sku ask_fila ON sk.CODIGO_UNIDAD_SKU = ask_fila.CODIGO_UNIDAD_SKU_SA LEFT JOIN fza_atributos_valores av_fila ON ask_fila.ID_AV_SA = av_fila.ID_AV AND av_fila.ID_VA_AV = ''', v_id_atributo_fila, ''' ');
            SET v_groupby_fila = ', src.VALOR_FILA';
        END IF;

        /* Generamos columnas dinamicas apuntando a la subconsulta 'src'.
           Sin cambios — necesita los AV reales de los SKUs. */
        SELECT GROUP_CONCAT(DISTINCT
            CONCAT(
                'SUM(CASE WHEN src.AV = ''', av.AV,
                ''' THEN src.CANTIDAD_STK ELSE 0 END) AS `', av.AV, '`'
            )
            ORDER BY av.ID_AV
        ) INTO v_columnas_dinamicas
        FROM fza_articulos_skus sk
        JOIN fza_atributos_sku ask ON sk.CODIGO_UNIDAD_SKU = ask.CODIGO_UNIDAD_SKU_SA
        JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
        WHERE sk.CODIGO_ART_SKU = v_codigo_articulo
          AND av.ID_VA_AV = v_id_atributo_pivot;

        /* Filtros SKU (Solo aplica si buscas un SKU especifico) */
        IF v_es_sku = TRUE THEN
            SELECT GROUP_CONCAT(
                CONCAT(
                    ' AND EXISTS (SELECT 1 FROM fza_atributos_sku f_ask ',
                    ' JOIN fza_atributos_valores f_av ON f_ask.ID_AV_SA = f_av.ID_AV ',
                    ' WHERE f_ask.CODIGO_UNIDAD_SKU_SA = sk.CODIGO_UNIDAD_SKU ',
                    ' AND f_av.ID_VA_AV = ''', av.ID_VA_AV, ''' ',
                    ' AND f_av.AV = ''', av.AV, ''') '
                ) SEPARATOR ' '
            ) INTO v_filtros_fijos
            FROM fza_atributos_sku ask
            JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV
            WHERE ask.CODIGO_UNIDAD_SKU_SA = p_input
              AND av.ID_VA_AV <> v_id_atributo_pivot;
        END IF;

        IF v_filtros_fijos IS NULL THEN SET v_filtros_fijos = ''; END IF;

        /* Si el articulo tiene atributo pivote definido pero todavia no
           tiene SKUs cargados, GROUP_CONCAT devuelve NULL. CONCAT con un
           argumento NULL devuelve NULL, y PREPARE stmt FROM NULL revienta
           con "near 'NULL' at line 1". Caemos al fallback. */
        IF v_columnas_dinamicas IS NOT NULL THEN

            /* QUERY FINAL: Almacen + Atributo Fila (Color) + Columnas Dinamicas (Talla) */
            SET @sql = CONCAT(
                'SELECT
                    alm.NOMBRE_ALM_ALM AS Almacen',
                    v_select_fila, ', ',
                    v_columnas_dinamicas, ',
                    COALESCE(SUM(src.CANTIDAD_STK), 0) AS Total
                 FROM fza_almacenes alm
                 LEFT JOIN (
                    SELECT stk.CODIGO_ALM_STK, av.AV, stk.CANTIDAD_STK', v_src_select_fila, '
                    FROM fza_articulos_stockactual stk
                    JOIN fza_articulos_skus sk ON stk.CODIGO_UNIDAD_STK = sk.CODIGO_UNIDAD_SKU
                    JOIN fza_atributos_sku ask ON sk.CODIGO_UNIDAD_SKU = ask.CODIGO_UNIDAD_SKU_SA
                    JOIN fza_atributos_valores av ON ask.ID_AV_SA = av.ID_AV',
                    v_join_fila, '
                    WHERE sk.CODIGO_ART_SKU = ''', v_codigo_articulo, '''
                      AND av.ID_VA_AV = ''', v_id_atributo_pivot, ''' ',
                      v_filtros_fijos, '
                 ) src ON alm.CODIGO_ALM_ALM = src.CODIGO_ALM_STK
                 WHERE alm.ESACTIVO_ALM = ''S''
                 GROUP BY alm.NOMBRE_ALM_ALM', v_groupby_fila, '
                 ORDER BY alm.NOMBRE_ALM_ALM', v_groupby_fila
            );

            PREPARE stmt FROM @sql;
            EXECUTE stmt;
            DEALLOCATE PREPARE stmt;

        END IF;

    END IF;

    /* Fallback: articulo simple, articulo sin TIPO_VARIACION_ART o
       articulo con pivote pero sin SKUs. Devuelve fila por almacen
       con stock total (0 si no hay nada todavia). */
    IF v_id_atributo_pivot IS NULL OR v_columnas_dinamicas IS NULL THEN
        SELECT
            alm.NOMBRE_ALM_ALM as Almacen,
            COALESCE(SUM(stk.CANTIDAD_STK), 0) as `Stock Total`
        FROM fza_almacenes alm
        LEFT JOIN fza_articulos_stockactual stk
            ON alm.CODIGO_ALM_ALM = stk.CODIGO_ALM_STK
            AND stk.CODIGO_UNIDAD_STK = p_input
        WHERE alm.ESACTIVO_ALM = 'S'
        GROUP BY alm.NOMBRE_ALM_ALM
        ORDER BY alm.NOMBRE_ALM_ALM;
    END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_CREAR_VALOR
DROP PROCEDURE IF EXISTS `PRC_GET_CREAR_VALOR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_CREAR_VALOR`(IN `p_id_va` VARCHAR(20),       /* Tipo de Variación (ej: 'CO') */
    IN `p_valor` VARCHAR(100),      /* El valor escrito (ej: 'VERDE LIMA') */
    IN `p_usuario` VARCHAR(100),    /* Usuario que hace la acción */
    OUT `p_id_resultado` INT)
SQL SECURITY INVOKER
BEGIN
    /* 1. Intentamos buscar el ID si ya existe */
    SELECT `ID_AV` INTO p_id_resultado
    FROM `fza_atributos_valores`
    WHERE `ID_VA_AV` = p_id_va 
      AND UPPER(`AV`) = UPPER(p_valor) /* Comparamos ignorando mayúsculas */
    LIMIT 1;

    /* 2. Si p_id_resultado sigue siendo NULL, significa que no existe. LO CREAMOS. */
    IF p_id_resultado IS NULL THEN
        INSERT INTO `fza_atributos_valores` (
            `ID_VA_AV`, 
            `AV`, 
            `USUARIO_ALTA`, 
            `USUARIO_MODIF`, 
            `INSTANTE_ALTA`
        ) VALUES (
            p_id_va, 
            p_valor, 
            p_usuario, 
            p_usuario, 
            NOW()
        );
        
        /* Obtenemos el ID que se acaba de generar */
        SET p_id_resultado = LAST_INSERT_ID();
    END IF;

    /* Al final, p_id_resultado siempre tiene un número válido (viejo o nuevo). */
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_DATA_ARTICULO
DROP PROCEDURE IF EXISTS `PRC_GET_DATA_ARTICULO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_DATA_ARTICULO`(
    IN pidcodarticulo varchar(200),
    OUT pidnomarticulo varchar(1000),
    OUT ptipoiva varchar(2)
)
SQL SECURITY INVOKER
BEGIN
    /* Declaramos una bandera para saber si lo encuentra o no */
    DECLARE v_found INT DEFAULT 1;
    
    /* Si el SELECT INTO no encuentra filas, baja esta bandera en vez de dar error */
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_found = 0;

    /* Hacemos la consulta UNA SOLA VEZ */
    SELECT DESCRIPCION_ART, TIPO_IVA_ART 
    INTO pidnomarticulo, ptipoiva 
    FROM fza_articulos 
    WHERE CODIGO_ART_ART = pidcodarticulo;

    /* Verificamos si la bandera cayó */
    IF v_found = 0 THEN
        SET pidnomarticulo = 'NO EXISTE';
        SET ptipoiva = 'N';
    END IF;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_DATA_CLIENTE
DROP PROCEDURE IF EXISTS `PRC_GET_DATA_CLIENTE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_DATA_CLIENTE`(
    IN  pCODIGO_CLIENTE                    varchar(10),
    OUT pRAZONSOCIAL_CLIENTE               varchar(200),
    OUT pNIF_CLIENTE                       varchar(50),
    OUT pCODIGO_ZONA_IVA_CLIENTE           int,
    OUT pMOVIL_CLIENTE                     varchar(40),
    OUT pESIVA_RECARGO_CLIENTE             varchar(1),
    OUT pESRETENCIONES_CLIENTE             varchar(1),
    OUT pESIVA_EXENTO_CLIENTE              varchar(1),
    OUT pESINTRACOMUNITARIO_CLIENTE        varchar(1),
    OUT pESREGIMENESPECIALAGRICOLA_CLIENTE varchar(1),
    OUT pEMAIL_CLIENTE                     varchar(200),
    OUT pDIRECCION1_CLIENTE                varchar(200),
    OUT pDIRECCION2_CLIENTE                varchar(200),
    OUT pPOBLACION_CLIENTE                 varchar(200),
    OUT pPROVINCIA_CLIENTE                 varchar(200),
    OUT pCPOSTAL_CLIENTE                   varchar(15),
    OUT pTARIFA_ARTICULO_CLIENTE           varchar(10),
    OUT pTEXTO_LEGAL_FACTURA_CLIENTE       varchar(1000),
    OUT pPAIS_CLIENTE                      varchar(150),
    OUT pCOD_PAIS_CLIENTE                  varchar(150)
)
SQL SECURITY INVOKER
BEGIN

    /* Comprobamos si el cliente existe (Usamos SELECT 1 por rendimiento) */
    IF ( EXISTS( SELECT 1
                 FROM fza_clientes
                 WHERE CODIGO_CLI_CLI = pCODIGO_CLIENTE ) ) THEN
                 
        /* Si existe, metemos los datos en las variables OUT */
        SELECT  RAZON_SOCIAL_CLI,
                NIF_CLI,
                CODIGO_ZONA_IVA_CLIENTE,
                ESIVA_RECARGO_CLI,
                ESRETENCIONES_CLI,
                ESIVA_EXENTO_CLI,
                ESINTRACOMUNITARIO_CLI,
                ESREGIMENESPECIALAGRICOLA_CLI,
                MOVIL_CLI,
                EMAIL_CLI,
                DIRECCION1_CLI,
                DIRECCION2_CLI,
                POBLACION_CLI,
                PROVINCIA_CLI,
                CODIGO_POSTAL_CLI,
                TARIFA_ARTICULO_CLI,
                TEXTO_LEGAL_FACTURA_CLI,
                NOMBRE_PAI_CLI,
                CODIGO_PAI_CLI 
        INTO    pRAZONSOCIAL_CLIENTE,
                pNIF_CLIENTE,
                pCODIGO_ZONA_IVA_CLIENTE,
                pESIVA_RECARGO_CLIENTE,
                pESRETENCIONES_CLIENTE,
                pESIVA_EXENTO_CLIENTE,
                pESINTRACOMUNITARIO_CLIENTE,
                pESREGIMENESPECIALAGRICOLA_CLIENTE,
                pMOVIL_CLIENTE,
                pEMAIL_CLIENTE,
                pDIRECCION1_CLIENTE,
                pDIRECCION2_CLIENTE,
                pPOBLACION_CLIENTE,
                pPROVINCIA_CLIENTE,
                pCPOSTAL_CLIENTE,
                pTARIFA_ARTICULO_CLIENTE,
                pTEXTO_LEGAL_FACTURA_CLIENTE,
                pPAIS_CLIENTE,
                pCOD_PAIS_CLIENTE
        FROM fza_clientes
        WHERE CODIGO_CLI_CLI = pCODIGO_CLIENTE;
        
    ELSE
    
        /* Si no existe, devolvemos un aviso */
        SET pRAZONSOCIAL_CLIENTE = 'CLIENTE NO ENCONTRADO';
        
    END IF;

END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_IVA_ZONA_FECHA
DROP PROCEDURE IF EXISTS `PRC_GET_IVA_ZONA_FECHA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_IVA_ZONA_FECHA`(IN `pFECHA` DATE, 
                                       IN `pZONA` INT, 
                                       OUT `pRESUL` INT, 
                                       OUT `pEXENTO_IVA` DECIMAL(18,6), 
                                       OUT `pEXENTO_RE_IVA` DECIMAL(18,6), 
                                       OUT `pNORMAL_IVA` DECIMAL(18,6), 
                                       OUT `pNORMAL_RE_IVA` DECIMAL(18,6), 
                                       OUT `pREDUCIDO_IVA` DECIMAL(18,6), 
                                       OUT `pREDUCIDO_RE_IVA` DECIMAL(18,6), 
                                       OUT `pSUPERREDUCIDO_IVA` DECIMAL(18,6), 
                                       OUT `pSUPERREDUCIDO_RE_IVA` DECIMAL(18,6))
SQL SECURITY INVOKER
BEGIN
    IF( EXISTS(
             SELECT *
               FROM fza_ivas
              WHERE FECHA_DESDE_IVA >=  FECHA
                AND (FECHA_HASTA_IVA <= FECHA 
                 OR FECHA_HASTA_IVA IS NULL)
                AND  IVA_IVAGRP = pZONA)) THEN
  SELECT `PORCENTAJE_EXENTO_IVA` ,
         `PORCENTAJE_EXENTO_RE_IVA`,
         `PORCENTAJE_NORMAL_IVA` ,
         `PORCENTAJE_NORMAL_RE_IVA`,
         `PORCENTAJE_REDUCIDO_IVA` ,
         `PORCENTAJE_REDUCIDO_RE_IVA` ,
         `PORCENTAJE_SUPERREDUCIDO_IVA` ,
         `PORCENTAJE_SUPERREDUCIDO_RE_IVA`
    INTO
         pEXENTO_IVA,
         pEXENTO_RE_IVA,
         pNORMAL_IVA ,
         pNORMAL_RE_IVA,
         pREDUCIDO_IVA,
         pREDUCIDO_RE_IVA ,
         pSUPERREDUCIDO_IVA,
         pSUPERREDUCIDO_RE_IVA
    FROM fza_ivas
   WHERE (FECHA_DESDE_IVA >=  FECHA
     AND (FECHA_HASTA_IVA <= FECHA OR 
          FECHA_HASTA_IVA IS NULL))
     AND CODIGO_ZONA_IVA_IVAZON = pZONA;
ELSE
    SELECT `PORCENTAJE_EXENTO_IVA` ,
           `PORCENTAJE_EXENTO_RE_IVA`,
           `PORCENTAJE_NORMAL_IVA` ,
           `PORCENTAJE_NORMAL_RE_IVA`,
           `PORCENTAJE_REDUCIDO_IVA` ,
           `PORCENTAJE_REDUCIDO_RE_IVA` ,
           `PORCENTAJE_SUPERREDUCIDO_IVA` ,
           `PORCENTAJE_SUPERREDUCIDO_RE_IVA`
       INTO
            pEXENTO_IVA,
            pEXENTO_RE_IVA,
            pNORMAL_IVA ,
            pNORMAL_RE_IVA,
            pREDUCIDO_IVA,
            pREDUCIDO_RE_IVA ,
            pSUPERREDUCIDO_IVA,
            pSUPERREDUCIDO_RE_IVA
      FROM  fza_ivas
     WHERE (FECHA_DESDE_IVA >=  FECHA
       AND FECHA_HASTA_IVA IS NULL )
       AND CODIGO_ZONA_IVA_IVAZON = pZONA;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_MOV_VENTAS_ART
DROP PROCEDURE IF EXISTS `PRC_GET_MOV_VENTAS_ART`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_MOV_VENTAS_ART`(
    IN `p_DESDE`          DATE,         /* inicio periodo de VENTAS (inclusive) */
    IN `p_HASTA`          DATE,         /* fin periodo de VENTAS (inclusive) */
    IN `p_INICIO_COMPRAS` DATE,         /* 1a compra del artículo >= esta fecha */
    IN `p_ALMACENES`      TEXT,         /* CSV "01,50" o '' = todos los activos */
    IN `p_FAMILIAS`       TEXT,         /* CSV; '' = todas. Una padre incluye sus hijas */
    IN `p_PROVEEDORES`    TEXT,         /* CSV de códigos de proveedor; '' = todos */
    IN `p_TEMPORADAS`     TEXT,         /* CSV de valores de temporada; '' = todas */
    IN `p_ARTICULOS`      TEXT,         /* CSV de códigos de artículo; '' = todos */
    IN `p_NIVEL1`         VARCHAR(3),   /* 1er nivel de agrupación: PRV/FAM/TMP/ALM/'' */
    IN `p_NIVEL2`         VARCHAR(3),   /* 2o nivel de agrupación */
    IN `p_NIVEL3`         VARCHAR(3),   /* 3er nivel de agrupación */
    IN `p_NIVEL_FAM`      INT,          /* nivel del árbol de familias al agrupar */
                                        /* por FAM (1 = raíz; <1 = familia hoja) */
    IN `p_SOLO_VENTAS`    VARCHAR(1)    /* 'S' = solo artículos con ventas en el */
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_desde     DATE;
    DECLARE v_hasta     DATE;
    DECLARE v_ini_cmp   DATE;
    DECLARE v_por_alm   BOOLEAN DEFAULT FALSE;  /* TRUE si se agrupa por almacén */
    DECLARE v_filtra_cmp BOOLEAN DEFAULT FALSE; /* TRUE si hay filtro inicio compras */
    DECLARE v_nivel_fam INT;                    /* nivel efectivo del árbol fam. */
    /* Normalización de parámetros. */
    SET p_FAMILIAS    = IFNULL(p_FAMILIAS, '');
    SET p_PROVEEDORES = IFNULL(p_PROVEEDORES, '');
    SET p_TEMPORADAS  = IFNULL(p_TEMPORADAS, '');
    SET p_ARTICULOS   = IFNULL(p_ARTICULOS, '');
    SET p_SOLO_VENTAS = IFNULL(NULLIF(p_SOLO_VENTAS, ''), 'N');
    SET p_NIVEL1      = UPPER(IFNULL(p_NIVEL1, ''));
    SET p_NIVEL2      = UPPER(IFNULL(p_NIVEL2, ''));
    SET p_NIVEL3      = UPPER(IFNULL(p_NIVEL3, ''));
    SET v_por_alm     = (p_NIVEL1 = 'ALM' OR p_NIVEL2 = 'ALM' OR p_NIVEL3 = 'ALM');
    SET v_nivel_fam   = IF(IFNULL(p_NIVEL_FAM, 0) < 1, 9999, p_NIVEL_FAM);
    SET v_desde       = IFNULL(p_DESDE, '1900-01-01');
    SET v_hasta       = IFNULL(p_HASTA, CURRENT_DATE);
    SET v_ini_cmp     = p_INICIO_COMPRAS;
    SET v_filtra_cmp  = (v_ini_cmp IS NOT NULL);

    /* Almacenes efectivos en tabla temporal indexada (filtrar por IN, no por */
    /* FIND_IN_SET sobre tablas grandes). Sin selección = todos los activos. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_alm`;
    CREATE TEMPORARY TABLE `tmp_mva_alm` (
        `CODIGO_ALM` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_mva_alm` (`CODIGO_ALM`)
    SELECT `CODIGO_ALM_ALM` FROM `fza_almacenes`
     WHERE IF(IFNULL(p_ALMACENES, '') = '',
              `ESACTIVO_ALM` = 'S',
              FIND_IN_SET(`CODIGO_ALM_ALM`, p_ALMACENES));

    /* Familias elegidas expandidas a TODA su descendencia (CTE recursivo). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_fam`;
    CREATE TEMPORARY TABLE `tmp_mva_fam` (
        `CODIGO_FAM` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_mva_fam` (`CODIGO_FAM`)
    WITH RECURSIVE `fam_tree` AS (
        SELECT `CODIGO_FAM_FAM`
          FROM `fza_articulos_familias`
         WHERE FIND_IN_SET(`CODIGO_FAM_FAM`, p_FAMILIAS)
        UNION ALL
        SELECT f.`CODIGO_FAM_FAM`
          FROM `fza_articulos_familias` f
          JOIN `fam_tree` t ON f.`CODIGO_PADRE_FAM` = t.`CODIGO_FAM_FAM`
    )
    SELECT DISTINCT `CODIGO_FAM_FAM` FROM `fam_tree`;

    /* Mapa de cada familia a su ancestro al nivel pedido (para agrupar por FAM */
    /* "por nivel": raíz, intermedio o familia hoja). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_fam_grp`;
    CREATE TEMPORARY TABLE `tmp_mva_fam_grp` (
        `CODIGO_FAM` VARCHAR(20)  NOT NULL PRIMARY KEY,
        `COD_GRP`    VARCHAR(20)  NOT NULL,
        `DESC_GRP`   VARCHAR(200) NULL
    );
    INSERT IGNORE INTO `tmp_mva_fam_grp` (`CODIGO_FAM`, `COD_GRP`, `DESC_GRP`)
    WITH RECURSIVE `fam_path` AS (
        SELECT `CODIGO_FAM_FAM` AS `COD`,
               CAST(`CODIGO_FAM_FAM` AS CHAR(1000)) AS `RUTA`
          FROM `fza_articulos_familias`
         WHERE `CODIGO_PADRE_FAM` IS NULL OR `CODIGO_PADRE_FAM` = ''
        UNION ALL
        SELECT f.`CODIGO_FAM_FAM`,
               CONCAT(pa.`RUTA`, '>', f.`CODIGO_FAM_FAM`)
          FROM `fza_articulos_familias` f
          JOIN `fam_path` pa ON f.`CODIGO_PADRE_FAM` = pa.`COD`
    )
    SELECT pa.`COD`,
           SUBSTRING_INDEX(SUBSTRING_INDEX(pa.`RUTA`, '>', v_nivel_fam), '>', -1),
           NULL
      FROM `fam_path` pa;
    UPDATE `tmp_mva_fam_grp` g
      JOIN `fza_articulos_familias` f ON f.`CODIGO_FAM_FAM` = g.`COD_GRP`
       SET g.`DESC_GRP` = COALESCE(f.`DESCRIPCION_FAM`, f.`NOMBRE_FAM_FAM`,
                                   g.`COD_GRP`);

    /* Universo de artículos por los filtros que NO dependen de movimientos */
    /* (familia, proveedor, temporada, lista). Se materializa ANTES de los */
    /* escaneos de compras/ventas/coste para restringirlos al conjunto pedido */
    /* en vez de agregar todo el catálogo y descartar al final. El filtro */
    /* "Inicio compras" se aplica después sobre este universo (tmp_mva_arts). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_arts0`;
    CREATE TEMPORARY TABLE `tmp_mva_arts0` (
        `CODIGO_ART` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_mva_arts0` (`CODIGO_ART`)
    SELECT a.`CODIGO_ART_ART`
      FROM `fza_articulos` a
     WHERE a.`ESACTIVO_ART` = 'S'
       AND (p_ARTICULOS = ''
            OR FIND_IN_SET(a.`CODIGO_ART_ART`, p_ARTICULOS))
       AND (p_FAMILIAS = ''
            OR a.`CODIGO_FAM_ART` IN (SELECT `CODIGO_FAM` FROM `tmp_mva_fam`))
       AND (p_PROVEEDORES = ''
            OR EXISTS (SELECT 1 FROM `fza_articulos_proveedores` ap
                        WHERE ap.`CODIGO_ART_AP` = a.`CODIGO_ART_ART`
                          AND FIND_IN_SET(ap.`CODIGO_PRV_AP`, p_PROVEEDORES)))
       AND (p_TEMPORADAS = ''
            OR EXISTS (SELECT 1 FROM `fza_articulos_propiedades` tp
                        LEFT JOIN `fza_propiedades_valores` tpv
                          ON tpv.`ID_PV_ARTPROP` = tp.`ID_PV_ARTPROP`
                        WHERE tp.`CODIGO_ART_ART` = a.`CODIGO_ART_ART`
                          AND tp.`CODIGO_PROP_ARTPROP` = 'TEMPORADA'
                          AND FIND_IN_SET(
                                COALESCE(tpv.`PV`, tp.`VALOR_LIBRE_ARTPROP`),
                                p_TEMPORADAS)));

    /* Entradas de stock por artículo y, si procede, almacén: totales de */
    /* unidades y coste. Se cuentan las entradas que representan adquisición */
    /* REAL de género: compra (AC) y albarán de entrada (AE). Se EXCLUYEN los */
    /* traspasos (TR/AT/TA), movimientos internos entre almacenes (doble */
    /* conteo); los depósitos (DP), que no son gasto hasta venderse; y el */
    /* inventario/regularización (IN), que es un ajuste, no una compra. El */
    /* artículo del movimiento se resuelve por su SKU (CODIGO_UNIDAD_MOV) para */
    /* no depender de CODIGO_ART_MOV, que puede venir nulo. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_ent`;
    CREATE TEMPORARY TABLE `tmp_mva_ent` (
        `CODIGO_ART` VARCHAR(20)   NOT NULL,
        `CODIGO_ALM` VARCHAR(20)   NOT NULL DEFAULT '',
        `UNI_ENT`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        `IMP_ENT`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`)
    );
    INSERT INTO `tmp_mva_ent`
    SELECT sk.`CODIGO_ART_SKU`,
           IF(v_por_alm, m.`CODIGO_ALM_MOV`, ''),
           SUM(m.`CANTIDAD_MOV`),
           SUM(m.`TOTAL_COSTE_MOV`)
      FROM `fza_movimientos_almacen` m
      JOIN `fza_articulos_skus` sk
        ON sk.`CODIGO_UNIDAD_SKU` = m.`CODIGO_UNIDAD_MOV`
     WHERE m.`ESACTIVO_MOV` = 'S'
       AND m.`TIPO_MOV` = 'E'
       AND m.`TIPO_DOC_MOV` IN ('AC', 'AE')
       AND m.`CODIGO_ALM_MOV` IN (SELECT `CODIGO_ALM` FROM `tmp_mva_alm`)
       /* Solo los artículos del informe: no agregar las compras de todo el */
       /* catálogo para descartarlas al unir con tmp_mva_base. */
       AND sk.`CODIGO_ART_SKU` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
     GROUP BY sk.`CODIGO_ART_SKU`, IF(v_por_alm, m.`CODIGO_ALM_MOV`, '');

    /* Primera ENTRADA por artículo, para el filtro Inicio compras: el artículo */
    /* entra solo si su primera entrada de género (global a los almacenes */
    /* filtrados) es >= v_ini_cmp. Usa los MISMOS tipos que las entradas */
    /* (AC compra, AE albarán de entrada): si mirara solo 'AC', los artículos */
    /* que entran por albarán de entrada se caerían del informe aunque tengan */
    /* entradas y ventas. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_primera`;
    CREATE TEMPORARY TABLE `tmp_mva_primera` (
        `CODIGO_ART` VARCHAR(20) NOT NULL PRIMARY KEY,
        `PRIMERA`    DATE        NULL
    );
    INSERT INTO `tmp_mva_primera`
    SELECT sk.`CODIGO_ART_SKU`, MIN(DATE(m.`FECHA_MOV`))
      FROM `fza_movimientos_almacen` m
      JOIN `fza_articulos_skus` sk
        ON sk.`CODIGO_UNIDAD_SKU` = m.`CODIGO_UNIDAD_MOV`
     WHERE m.`ESACTIVO_MOV` = 'S'
       AND m.`TIPO_MOV` = 'E'
       AND m.`TIPO_DOC_MOV` IN ('AC', 'AE')
       AND m.`CODIGO_ALM_MOV` IN (SELECT `CODIGO_ALM` FROM `tmp_mva_alm`)
       /* Solo los artículos del informe (mismo universo que las entradas). */
       AND sk.`CODIGO_ART_SKU` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
     GROUP BY sk.`CODIGO_ART_SKU`;

    /* Ventas del periodo por artículo y, si procede, almacén (líneas de */
    /* factura/ticket por fecha de factura). El artículo se resuelve por SKU. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_ven`;
    CREATE TEMPORARY TABLE `tmp_mva_ven` (
        `CODIGO_ART` VARCHAR(20)   NOT NULL,
        `CODIGO_ALM` VARCHAR(20)   NOT NULL DEFAULT '',
        `UDS_VEN`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        `IMP_VEN`    DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`)
    );
    /* El almacén de la venta puede venir vacío en la línea */
    /* (CODIGO_ALM_FACLIN nulo); se cae a la cabecera de la factura */
    /* (CODIGO_ALM_FAC). Sin esto las líneas sin almacén de línea quedan fuera */
    /* del filtro de almacenes y la venta no cuenta. */
    INSERT INTO `tmp_mva_ven`
    SELECT sk.`CODIGO_ART_SKU`,
           IF(v_por_alm, COALESCE(fl.`CODIGO_ALM_FACLIN`, f.`CODIGO_ALM_FAC`), ''),
           SUM(fl.`CANTIDAD_FACLIN`),
           SUM(fl.`TOTAL_FACLIN`)
      FROM `fza_facturas_lineas` fl
      JOIN `fza_facturas` f
        ON f.`NUMERO_FAC` = fl.`NUMERO_FAC_FACLIN`
       AND f.`SERIE_FAC` = fl.`SERIE_FAC_FACLIN`
      JOIN `fza_articulos_skus` sk
        ON sk.`CODIGO_UNIDAD_SKU` = fl.`CODIGO_UNIDAD_FACLIN`
     WHERE COALESCE(fl.`CODIGO_ALM_FACLIN`, f.`CODIGO_ALM_FAC`)
           IN (SELECT `CODIGO_ALM` FROM `tmp_mva_alm`)
       AND DATE(f.`FECHA_FAC`) BETWEEN v_desde AND v_hasta
       /* Una sustitutiva S reemplaza íntegramente a la simplificada original. */
       AND NOT EXISTS (
           SELECT 1
             FROM `fza_facturas` fo
             JOIN `fza_facturas_relaciones` fr
               ON fr.`SERIE_FAC_ORIGEN_FACREL` = fo.`SERIE_FAC`
              AND fr.`NUMERO_FAC_ORIGEN_FACREL` = fo.`NUMERO_FAC`
             JOIN `fza_facturas` fs
               ON fs.`CODIGO_EMP_FAC` = fo.`CODIGO_EMP_FAC`
              AND fs.`SERIE_FAC` = fr.`SERIE_FAC_FACREL`
              AND fs.`NUMERO_FAC` = fr.`NUMERO_FAC_FACREL`
            WHERE fo.`CODIGO_EMP_FAC` = f.`CODIGO_EMP_FAC`
              AND fo.`SERIE_FAC` = f.`SERIE_FAC`
              AND fo.`NUMERO_FAC` = f.`NUMERO_FAC`
              AND fo.`TIPO_FAC` = 'SIMPLIFICADA'
              AND fo.`FASE_FAC` = 'RECTIFICADA'
              AND fr.`TIPO_RELACION_FACREL` = 'RECTIFICA'
              AND fs.`TIPO_RECTIFICATIVA_FAC` = 'S'
       )
       /* Solo los artículos del informe: no agregar las ventas de todo el */
       /* catálogo para descartarlas al unir con tmp_mva_base. */
       AND sk.`CODIGO_ART_SKU` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
     GROUP BY sk.`CODIGO_ART_SKU`,
              IF(v_por_alm, COALESCE(fl.`CODIGO_ALM_FACLIN`, f.`CODIGO_ALM_FAC`), '');

    /* Coste historico de las ventas del periodo: se toma del movimiento de */
    /* salida ya valorado en el momento de vender. Con SKUs de coste distinto */
    /* evita recalcular ventas antiguas con el PMP vivo del articulo. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_coste_ven`;
    CREATE TEMPORARY TABLE `tmp_mva_coste_ven` (
        `CODIGO_ART` VARCHAR(20)   NOT NULL,
        `CODIGO_ALM` VARCHAR(20)   NOT NULL DEFAULT '',
        `COSTE_VEN`  DECIMAL(19,6) NOT NULL DEFAULT 0,
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`)
    );
    INSERT INTO `tmp_mva_coste_ven`
    SELECT sk.`CODIGO_ART_SKU`,
           IF(v_por_alm, m.`CODIGO_ALM_MOV`, ''),
           SUM(m.`TOTAL_COSTE_MOV`)
      FROM `fza_movimientos_almacen` m
      JOIN `fza_facturas` f
        ON f.`SERIE_FAC` = m.`SERIE_DOC_MOV`
       AND f.`NUMERO_FAC` = m.`NUMERO_DOC_MOV`
      JOIN `fza_articulos_skus` sk
        ON sk.`CODIGO_UNIDAD_SKU` = m.`CODIGO_UNIDAD_MOV`
     WHERE m.`ESACTIVO_MOV` = 'S'
       AND m.`TIPO_MOV` = 'S'
       AND m.`TIPO_DOC_MOV` IN ('VE', 'FC')
       AND DATE(f.`FECHA_FAC`) BETWEEN v_desde AND v_hasta
       AND m.`CODIGO_ALM_MOV` IN (SELECT `CODIGO_ALM` FROM `tmp_mva_alm`)
       AND sk.`CODIGO_ART_SKU` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
     GROUP BY sk.`CODIGO_ART_SKU`, IF(v_por_alm, m.`CODIGO_ALM_MOV`, '');

    /* Universo final = tmp_mva_arts0 (familia/proveedor/temporada/lista) más */
    /* el filtro Inicio compras (primera compra AC/AE >= v_ini_cmp). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_arts`;
    CREATE TEMPORARY TABLE `tmp_mva_arts` (
        `CODIGO_ART` VARCHAR(20) NOT NULL PRIMARY KEY
    );
    INSERT IGNORE INTO `tmp_mva_arts` (`CODIGO_ART`)
    SELECT a0.`CODIGO_ART`
      FROM `tmp_mva_arts0` a0
     WHERE NOT v_filtra_cmp
        OR EXISTS (SELECT 1 FROM `tmp_mva_primera` pc
                    WHERE pc.`CODIGO_ART` = a0.`CODIGO_ART`
                      AND pc.`PRIMERA` >= v_ini_cmp);

    /* Coste medio ponderado (PMP) por artículo desde el stock actual de los */
    /* almacenes filtrados (respaldo: último precio de compra del proveedor). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_coste`;
    CREATE TEMPORARY TABLE `tmp_mva_coste` (
        `CODIGO_ART` VARCHAR(20)   NOT NULL PRIMARY KEY,
        `COSTE`      DECIMAL(19,6) NOT NULL DEFAULT 0
    );
    INSERT INTO `tmp_mva_coste`
    SELECT sk.`CODIGO_ART_SKU`,
           IF(SUM(st.`CANTIDAD_STK`) <> 0,
              SUM(st.`VALOR_TOTAL_STK`) / SUM(st.`CANTIDAD_STK`), 0)
      FROM `fza_articulos_stockactual` st
      JOIN `fza_articulos_skus` sk
        ON sk.`CODIGO_UNIDAD_SKU` = st.`CODIGO_UNIDAD_STK`
     WHERE st.`CODIGO_ALM_STK` IN (SELECT `CODIGO_ALM` FROM `tmp_mva_alm`)
       /* Solo los artículos del informe (se une por artículo ya filtrado). */
       AND sk.`CODIGO_ART_SKU` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
     GROUP BY sk.`CODIGO_ART_SKU`;

    /* Universo de filas del informe: (artículo, almacén) presentes en compras */
    /* o ventas, restringido a los artículos filtrados. Una fila por artículo */
    /* (o por artículo+almacén si se agrupa por ALM). */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_base`;
    CREATE TEMPORARY TABLE `tmp_mva_base` (
        `CODIGO_ART` VARCHAR(20) NOT NULL,
        `CODIGO_ALM` VARCHAR(20) NOT NULL DEFAULT '',
        PRIMARY KEY (`CODIGO_ART`, `CODIGO_ALM`)
    );
    INSERT IGNORE INTO `tmp_mva_base`
    SELECT e.`CODIGO_ART`, e.`CODIGO_ALM`
      FROM `tmp_mva_ent` e
     WHERE e.`CODIGO_ART` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts`);
    INSERT IGNORE INTO `tmp_mva_base`
    SELECT v.`CODIGO_ART`, v.`CODIGO_ALM`
      FROM `tmp_mva_ven` v
     WHERE v.`CODIGO_ART` IN (SELECT `CODIGO_ART` FROM `tmp_mva_arts`);

    /* ----------------------------------------------------------------- */
    /* Resultado final: una fila por artículo (o artículo+almacén), con las */
    /* magnitudes de compra y venta y los dos márgenes. Los porcentajes se */
    /* calculan aquí; en los totales por grupo el cliente los recalcula a */
    /* partir de las sumas de las bases (no se pueden sumar porcentajes). */
    /* ----------------------------------------------------------------- */
    SELECT
        COALESCE(fam.`ORDEN_FAM`, 999999)             AS `ORDEN_FAM`,
        art.`CODIGO_FAM_ART`                          AS `CODIGO_FAM`,
        COALESCE(fam.`DESCRIPCION_FAM`,
                 fam.`NOMBRE_FAM_FAM`, art.`CODIGO_FAM_ART`) AS `DESCRIPCION_FAM`,
        b.`CODIGO_ART`                                AS `CODIGO_ART_ART`,
        art.`DESCRIPCION_ART`                         AS `DESCRIPCION_ART`,
        prov.`REF_PROVEEDOR_AP`                       AS `REF_PRV`,
        ROUND(COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0), 2) AS `COSTE_ART`,
        ROUND(COALESCE(pvp.`PVP`, 0), 2)              AS `PVP_ART`,
        b.`CODIGO_ALM`                                AS `CODIGO_ALM`,
        COALESCE(alm.`NOMBRE_ALM_ALM`, '')            AS `NOMBRE_ALM`,
        /* Magnitudes base (sumables en los totales). */
        ROUND(COALESCE(e.`UNI_ENT`, 0), 2)            AS `UNI_ENT_TOT`,
        ROUND(COALESCE(e.`IMP_ENT`, 0), 2)            AS `IMP_ENT_TOT`,
        ROUND(COALESCE(v.`UDS_VEN`, 0), 2)            AS `UDS_VENTA`,
        ROUND(COALESCE(v.`IMP_VEN`, 0), 2)            AS `IMP_VENTA`,
        ROUND(COALESCE(cv.`COSTE_VEN`,
              COALESCE(v.`UDS_VEN`, 0)
              * COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0)), 2)
                                                      AS `IMP_COSTE`,
        ROUND(COALESCE(v.`IMP_VEN`, 0)
              - COALESCE(cv.`COSTE_VEN`,
                COALESCE(v.`UDS_VEN`, 0)
                * COALESCE(NULLIF(cst.`COSTE`, 0), prov.`COSTE_PRV`, 0)), 2)
                                                      AS `BENEFICIO`,
        ROUND(COALESCE(v.`IMP_VEN`, 0) - COALESCE(e.`IMP_ENT`, 0), 2)
                                                      AS `VENTA_ENT`,
        /* Porcentajes / márgenes (no sumables; se recalculan en los totales). */
        ROUND(IF(COALESCE(cv.`COSTE_VEN`,
                 COALESCE(v.`UDS_VEN`, 0)
                 * COALESCE(NULLIF(cst.`COSTE`, 0),
                            prov.`COSTE_PRV`, 0)) <> 0,
                 (COALESCE(v.`IMP_VEN`, 0)
                  - COALESCE(cv.`COSTE_VEN`,
                    COALESCE(v.`UDS_VEN`, 0)
                    * COALESCE(NULLIF(cst.`COSTE`, 0),
                               prov.`COSTE_PRV`, 0)))
                 / COALESCE(cv.`COSTE_VEN`,
                    COALESCE(v.`UDS_VEN`, 0)
                    * COALESCE(NULLIF(cst.`COSTE`, 0),
                               prov.`COSTE_PRV`, 0))
                 * 100, 0), 2)                        AS `PCT_BNFCO`,
        ROUND(IF(COALESCE(e.`IMP_ENT`, 0) <> 0,
                 (COALESCE(v.`IMP_VEN`, 0) - COALESCE(e.`IMP_ENT`, 0))
                 / COALESCE(e.`IMP_ENT`, 0) * 100, 0), 2) AS `VENT_ENT`,
        ROUND(IF(COALESCE(v.`IMP_VEN`, 0) <> 0,
                 (COALESCE(v.`IMP_VEN`, 0)
                  - COALESCE(cv.`COSTE_VEN`,
                    COALESCE(v.`UDS_VEN`, 0)
                    * COALESCE(NULLIF(cst.`COSTE`, 0),
                               prov.`COSTE_PRV`, 0)))
                 / COALESCE(v.`IMP_VEN`, 0) * 100, 0), 2) AS `MARGEN1`,
        ROUND(IF(COALESCE(v.`IMP_VEN`, 0) <> 0,
                 (COALESCE(v.`IMP_VEN`, 0) - COALESCE(e.`IMP_ENT`, 0))
                 / COALESCE(v.`IMP_VEN`, 0) * 100, 0), 2) AS `MARGEN2`,
        ROUND(IF(COALESCE(e.`UNI_ENT`, 0) <> 0,
                 COALESCE(v.`UDS_VEN`, 0) / COALESCE(e.`UNI_ENT`, 0) * 100, 0), 2)
                                                      AS `PCT_VDTO`,
        ROUND(IF(COALESCE(e.`IMP_ENT`, 0) <> 0,
                 COALESCE(v.`IMP_VEN`, 0) / COALESCE(e.`IMP_ENT`, 0) * 100, 0), 2)
                                                      AS `PCT_VLAST`,
        /* Niveles de agrupación configurables (mismo criterio que el balance). */
        CASE p_NIVEL1
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN b.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO1_COD`,
        CASE p_NIVEL1
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`, art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), b.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO1_ETIQ`,
        CASE p_NIVEL2
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN b.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO2_COD`,
        CASE p_NIVEL2
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`, art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), b.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO2_ETIQ`,
        CASE p_NIVEL3
            WHEN 'PRV' THEN COALESCE(prov.`CODIGO_PRV`, '')
            WHEN 'FAM' THEN COALESCE(fg.`COD_GRP`, art.`CODIGO_FAM_ART`)
            WHEN 'TMP' THEN COALESCE(tmp.`TEMPORADA`, '')
            WHEN 'ALM' THEN b.`CODIGO_ALM`
            ELSE ''
        END                                           AS `GRUPO3_COD`,
        CASE p_NIVEL3
            WHEN 'PRV' THEN CONCAT('Proveedor: ',
                 COALESCE(NULLIF(prov.`RAZON`, ''), prov.`CODIGO_PRV`,
                          '(sin proveedor)'))
            WHEN 'FAM' THEN CONCAT('Familia: ',
                 COALESCE(fg.`DESC_GRP`, fg.`COD_GRP`, art.`CODIGO_FAM_ART`))
            WHEN 'TMP' THEN CONCAT('Temporada: ',
                 COALESCE(NULLIF(tmp.`TEMPORADA`, ''), '(sin temporada)'))
            WHEN 'ALM' THEN CONCAT('Almacén: ',
                 COALESCE(NULLIF(alm.`NOMBRE_ALM_ALM`, ''), b.`CODIGO_ALM`,
                          '(sin almacén)'))
            ELSE ''
        END                                           AS `GRUPO3_ETIQ`
      FROM `tmp_mva_base` b
      JOIN `fza_articulos` art ON art.`CODIGO_ART_ART` = b.`CODIGO_ART`
      LEFT JOIN `tmp_mva_ent` e
        ON e.`CODIGO_ART` = b.`CODIGO_ART` AND e.`CODIGO_ALM` = b.`CODIGO_ALM`
      LEFT JOIN `tmp_mva_ven` v
        ON v.`CODIGO_ART` = b.`CODIGO_ART` AND v.`CODIGO_ALM` = b.`CODIGO_ALM`
      LEFT JOIN `tmp_mva_coste_ven` cv
        ON cv.`CODIGO_ART` = b.`CODIGO_ART` AND cv.`CODIGO_ALM` = b.`CODIGO_ALM`
      LEFT JOIN `tmp_mva_coste` cst ON cst.`CODIGO_ART` = b.`CODIGO_ART`
      LEFT JOIN `fza_articulos_familias` fam
        ON fam.`CODIGO_FAM_FAM` = art.`CODIGO_FAM_ART`
      LEFT JOIN `tmp_mva_fam_grp` fg ON fg.`CODIGO_FAM` = art.`CODIGO_FAM_ART`
      LEFT JOIN `fza_almacenes` alm ON alm.`CODIGO_ALM_ALM` = b.`CODIGO_ALM`
      LEFT JOIN (
            SELECT t.`CODIGO_ART_ARTTAR` AS `CODIGO_ART`,
                   MAX(t.`PRECIO_FINAL_ARTTAR`) AS `PVP`
              FROM `fza_articulos_tarifas` t
             WHERE IFNULL(t.`CODIGO_UNIDAD_ARTTAR`, '') = ''
               /* Solo los artículos del informe (se une por artículo). */
               AND t.`CODIGO_ART_ARTTAR` IN
                   (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
               AND t.`ESACTIVO_ARTTAR` = 'S'
               AND (t.`FECHA_DESDE_ARTTAR` IS NULL
                    OR t.`FECHA_DESDE_ARTTAR` <= CURRENT_DATE)
               AND (t.`FECHA_HASTA_ARTTAR` IS NULL
                    OR t.`FECHA_HASTA_ARTTAR` >= CURRENT_DATE)
             GROUP BY t.`CODIGO_ART_ARTTAR`
           ) pvp ON pvp.`CODIGO_ART` = b.`CODIGO_ART`
      LEFT JOIN (
            SELECT ap.`CODIGO_ART_AP` AS `CODIGO_ART`,
                   MAX(ap.`REF_PROVEEDOR_AP`)     AS `REF_PROVEEDOR_AP`,
                   MAX(ap.`PRECIO_ULT_COMPRA_AP`) AS `COSTE_PRV`,
                   MAX(ap.`CODIGO_PRV_AP`)        AS `CODIGO_PRV`,
                   MAX(pr.`RAZON_SOCIAL_PRV`)     AS `RAZON`
              FROM `fza_articulos_proveedores` ap
              LEFT JOIN `fza_proveedores` pr
                ON pr.`CODIGO_PRV_PRV` = ap.`CODIGO_PRV_AP`
             WHERE ap.`ESPROVEEDORPRINCIPAL_AP` = 'S'
               /* Solo los artículos del informe (se une por artículo). */
               AND ap.`CODIGO_ART_AP` IN
                   (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
             GROUP BY ap.`CODIGO_ART_AP`
           ) prov ON prov.`CODIGO_ART` = b.`CODIGO_ART`
      /* Temporada a nivel ARTICULO (Fase 3): este informe es por articulo, */
      /* sin desglose de color, asi que usa la temporada del articulo. El */
      /* filtro CODIGO_UNIDAD_ARTPROP = '' evita mezclar/duplicar con las */
      /* temporadas de color (el color se ve en el balance de tallas). */
      LEFT JOIN (
            SELECT tp.`CODIGO_ART_ART` AS `CODIGO_ART`,
                   MAX(COALESCE(tpv.`PV`, tp.`VALOR_LIBRE_ARTPROP`)) AS `TEMPORADA`
              FROM `fza_articulos_propiedades` tp
              LEFT JOIN `fza_propiedades_valores` tpv
                ON tpv.`ID_PV_ARTPROP` = tp.`ID_PV_ARTPROP`
             WHERE tp.`CODIGO_PROP_ARTPROP` = 'TEMPORADA'
               AND tp.`CODIGO_UNIDAD_ARTPROP` = ''
               /* Solo los artículos del informe (se une por artículo). */
               AND tp.`CODIGO_ART_ART` IN
                   (SELECT `CODIGO_ART` FROM `tmp_mva_arts0`)
             GROUP BY tp.`CODIGO_ART_ART`
           ) tmp ON tmp.`CODIGO_ART` = b.`CODIGO_ART`
     /* "Solo artículos con ventas": descarta las filas sin ventas en el */
     /* periodo (las que solo tienen entradas). Sin marcar = todos los que */
     /* tengan actividad (entradas o ventas). */
     WHERE (p_SOLO_VENTAS <> 'S' OR COALESCE(v.`UDS_VEN`, 0) <> 0)
     ORDER BY `GRUPO1_COD`, `GRUPO2_COD`, `GRUPO3_COD`,
              COALESCE(fam.`ORDEN_FAM`, 999999), art.`CODIGO_FAM_ART`,
              b.`CODIGO_ART`, b.`CODIGO_ALM`;

    /* Limpieza de temporales. */
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_base`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_coste`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_arts`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_arts0`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_coste_ven`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_ven`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_primera`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_ent`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_fam_grp`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_fam`;
    DROP TEMPORARY TABLE IF EXISTS `tmp_mva_alm`;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_NEXT_CONT
DROP PROCEDURE IF EXISTS `PRC_GET_NEXT_CONT`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_NEXT_CONT`(
  IN pTipoDoc varchar(2) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci,
  IN pUSUARIO_MODIF varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci,
  OUT pcont varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vSerie varchar(12) DEFAULT NULL;
  INSERT IGNORE INTO `fza_contadores` (
    `TIPO_DOC_CON`, `EMPRESA_CON`, `SERIE_CON`, `CON`,
    `NUM_DIGITOS_CON`, `ESACTIVO_CON`, `DEFAULT_CON`,
    `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`
  ) VALUES (
    pTipoDoc, '-', '-', 1, 3, 'S', 'S',
    CURRENT_TIMESTAMP, pUSUARIO_MODIF, pUSUARIO_MODIF
  );
  SELECT `SERIE_CON` INTO vSerie
    FROM `fza_contadores`
   WHERE `TIPO_DOC_CON` = pTipoDoc
     AND `EMPRESA_CON` = '-'
     AND `DEFAULT_CON` = 'S'
     AND `ESACTIVO_CON` = 'S'
   ORDER BY `SERIE_CON`
   LIMIT 1;
  IF vSerie IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No existe un contador por defecto activo';
  END IF;
  CALL `PRC_GET_NEXT_CONTADOR`(pTipoDoc, '-', vSerie, pUSUARIO_MODIF, pcont);
END ;;
DELIMITER ;

-- Procedimiento ausente (versión compatible MySQL 8): PRC_GET_NEXT_CONTADOR
DROP PROCEDURE IF EXISTS PRC_GET_NEXT_CONTADOR;

DELIMITER ;;

CREATE PROCEDURE PRC_GET_NEXT_CONTADOR(
  IN pTipoDoc varchar(2),
  IN pEmpresa varchar(10),
  IN pSerie varchar(12),
  IN pUsuario varchar(100),
  OUT pContador varchar(20)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE vContador bigint DEFAULT NULL;
  DECLARE vNumeroDigitos int DEFAULT NULL;

  SET pEmpresa = COALESCE(NULLIF(TRIM(pEmpresa), ''), '-');
  SET pSerie = COALESCE(NULLIF(TRIM(pSerie), ''), '-');
  SET pContador = NULL;

  SELECT NUM_DIGITOS_CON
    INTO vNumeroDigitos
    FROM fza_contadores
   WHERE TIPO_DOC_CON = pTipoDoc
     AND EMPRESA_CON = pEmpresa
     AND SERIE_CON = pSerie
     AND ESACTIVO_CON = 'S'
   LIMIT 1;

  IF vNumeroDigitos IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El contador solicitado no existe o esta inactivo';
  END IF;
  IF vNumeroDigitos > 20 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'El contador supera los 20 digitos admitidos';
  END IF;

  /* Reserva atómica: LAST_INSERT_ID(expr) guarda para esta conexión el
     valor entregado y el UPDATE deja almacenado el siguiente. */
  UPDATE fza_contadores
     SET CON = LAST_INSERT_ID(GREATEST(CON, 1)) + 1,
         USUARIO_MODIF = pUsuario
   WHERE TIPO_DOC_CON = pTipoDoc
     AND EMPRESA_CON = pEmpresa
     AND SERIE_CON = pSerie
     AND ESACTIVO_CON = 'S';

  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No se pudo actualizar el contador';
  END IF;

  SET vContador = LAST_INSERT_ID();
  IF vNumeroDigitos > 0 THEN
    SET pContador = LPAD(vContador, vNumeroDigitos, '0');
  ELSE
    SET pContador = CAST(vContador AS char);
  END IF;
END ;;

DELIMITER ;

-- Procedimiento ausente: PRC_GET_NEXT_CONT_FACT_SERIE
DROP PROCEDURE IF EXISTS `PRC_GET_NEXT_CONT_FACT_SERIE`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_NEXT_CONT_FACT_SERIE`(
    IN pserie VARCHAR(12),
    IN pTipoDoc VARCHAR(2),
    IN pEMPRESA_CONTADOR VARCHAR(10),
    IN pUSUARIOMODIF VARCHAR(100),
    OUT pcont VARCHAR(12)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE pNUMDIGIT INT;
    DECLARE v_NextValue BIGINT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    ManejoError: BEGIN
        ROLLBACK;
        RESIGNAL;
    END ManejoError;
    START TRANSACTION;
    IF (pEMPRESA_CONTADOR = '' OR pEMPRESA_CONTADOR IS NULL) THEN
        SET pEMPRESA_CONTADOR = '-';
    END IF;
    IF NOT EXISTS (
        SELECT 1
          FROM fza_contadores
         WHERE TIPO_DOC_CON = pTipoDoc
           AND EMPRESA_CON = pEMPRESA_CONTADOR
           AND SERIE_CON = pserie
    ) THEN
        INSERT INTO fza_contadores (
            TIPO_DOC_CON, SERIE_CON, CON, EMPRESA_CON, DEFAULT_CON,
            NUM_DIGITOS_CON, INSTANTE_ALTA, USUARIO_ALTA, USUARIO_MODIF
        ) VALUES (
            pTipoDoc, pserie, 1, pEMPRESA_CONTADOR, 'N',
            6, CURRENT_TIMESTAMP, pUSUARIOMODIF, pUSUARIOMODIF
        );
    END IF;
    UPDATE fza_contadores
       SET CON = LAST_INSERT_ID(GREATEST(CON, 1) + 1),
           USUARIO_MODIF = pUSUARIOMODIF
     WHERE SERIE_CON = pserie
       AND EMPRESA_CON = pEMPRESA_CONTADOR
       AND TIPO_DOC_CON = pTipoDoc;
    IF ROW_COUNT() = 0 THEN
        SIGNAL SQLSTATE '45000'
           SET MESSAGE_TEXT = 'No se pudo actualizar el contador';
    END IF;
    SET v_NextValue = LAST_INSERT_ID() - 1;
    IF v_NextValue < 1 THEN
        SIGNAL SQLSTATE '45000'
           SET MESSAGE_TEXT = 'El contador no puede devolver numero 0';
    END IF;
    SELECT NUM_DIGITOS_CON
      INTO pNUMDIGIT
      FROM fza_contadores
     WHERE SERIE_CON = pserie
       AND TIPO_DOC_CON = pTipoDoc
       AND EMPRESA_CON = pEMPRESA_CONTADOR
     LIMIT 1;
    IF (pNUMDIGIT IS NOT NULL AND pNUMDIGIT > 0) THEN
        SET pcont = LPAD(v_NextValue, pNUMDIGIT, '0');
    ELSE
        SET pcont = CAST(v_NextValue AS CHAR);
    END IF;
    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_NEXT_OP_CAJA
DROP PROCEDURE IF EXISTS `PRC_GET_NEXT_OP_CAJA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_NEXT_OP_CAJA`(
    IN  pEmpresa  VARCHAR(10),
    IN  pAlmacen  VARCHAR(10),
    IN  pCaja     VARCHAR(10),
    IN  pUsuario  VARCHAR(100),
    OUT pSerie    VARCHAR(12),
    OUT pcont     VARCHAR(20)
)
SQL SECURITY INVOKER
BEGIN    
    DECLARE pPADD    BIGINT;
    DECLARE vSerie   VARCHAR(12);

    START TRANSACTION;

        /* 1. Obtener serie vigente */        
        SELECT EMPSER          
          INTO vSerie          
          FROM fza_empresas_series         
         WHERE TIPO_DOC_EMPSER        = 'OV'           
           AND CODIGO_EMP_EMPSER = pEmpresa           
           AND CODIGO_ALM_EMPSER = pAlmacen           
           AND CODIGO_CAJA_EMPSER    = pCaja           
           AND FECHA_DESDE_EMPSER   <= CURDATE()
           AND (FECHA_HASTA_EMPSER  >= CURDATE() OR FECHA_HASTA_EMPSER IS NULL)
         LIMIT 1;

        /* 2. Crear serie si no existe (Sustituye el bloque de Error) */
        IF vSerie IS NULL THEN            
            SET vSerie = 'OV'; /* Nombre por defecto de la nueva serie */
            
            INSERT INTO fza_empresas_series (
                TIPO_DOC_EMPSER,
                CODIGO_EMP_EMPSER,
                CODIGO_ALM_EMPSER,
                CODIGO_CAJA_EMPSER,
                EMPSER,
                FECHA_DESDE_EMPSER,
                FECHA_HASTA_EMPSER
                /* Descomenta y ajusta si tu tabla tiene columnas de auditoría:
                , INSTANTE_ALTA,
                USUARIO_ALTA
                */
            ) VALUES (
                'OV',
                pEmpresa,
                pAlmacen,
                pCaja,
                vSerie,
                CURDATE(),
                NULL
                /*
                , CURRENT_TIMESTAMP,
                pUsuario
                */
            );
        END IF;

        /* 3. Crear fila de contador si no existe */        
        IF NOT EXISTS (
            SELECT 1              
              FROM fza_contadores             
             WHERE TIPO_DOC_CON = 'OV'               
               AND EMPRESA_CON = pEmpresa               
               AND SERIE_CON   = vSerie        
        ) THEN            
            INSERT INTO fza_contadores (
                TIPO_DOC_CON,
                EMPRESA_CON,
                SERIE_CON,
                CON,
                NUM_DIGITOS_CON,
                ESACTIVO_CON,
                DEFAULT_CON,
                INSTANTE_ALTA,
                USUARIO_ALTA,
                USUARIO_MODIF)
            VALUES (
                'OV',
                pEmpresa,
                vSerie,
                1,
                8,
                'S',
                'S',
                CURRENT_TIMESTAMP,
                pUsuario,
                pUsuario);
        END IF;

        /* 4. Bloquear fila y leer dígitos */        
        SELECT NUM_DIGITOS_CON          
          INTO pPADD          
          FROM fza_contadores         
         WHERE TIPO_DOC_CON = 'OV'           
           AND EMPRESA_CON = pEmpresa           
           AND SERIE_CON   = vSerie         
         LIMIT 1           
           FOR UPDATE;

        /* 5. Incrementar */        
        UPDATE fza_contadores           
           SET CON = CON + 1,
               USUARIO_MODIF      = pUsuario         
         WHERE TIPO_DOC_CON  = 'OV'           
           AND EMPRESA_CON  = pEmpresa           
           AND SERIE_CON    = vSerie;

        /* 6. Devolver serie y número formateado */        
        SET pSerie := vSerie;

        SELECT LPAD(CON - 1, pPADD, '0')
          INTO pcont          
          FROM fza_contadores         
         WHERE TIPO_DOC_CON = 'OV'           
           AND EMPRESA_CON = pEmpresa           
           AND SERIE_CON   = vSerie         
         LIMIT 1;

    COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_NUMEROS_A_LETRAS
DROP PROCEDURE IF EXISTS `PRC_GET_NUMEROS_A_LETRAS`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_NUMEROS_A_LETRAS`(
    IN NUMERO DECIMAL(12,2), 
    OUT pResul varchar(200)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE MILLARES INT;
    DECLARE CENTENAS INT;
    DECLARE CENTIMOS INT;
    DECLARE CENTIMO_AUX VARCHAR(200);
    DECLARE CENTIMO_AUX_CON VARCHAR(200);
    DECLARE EN_LETRAS VARCHAR(200);
    DECLARE ENTERO INT;
    DECLARE AUX VARCHAR(15);
    DECLARE INTER VARCHAR(200);
    
    SET EN_LETRAS = '';
    SET CENTIMO_AUX_CON = '';
    SET ENTERO = TRUNCATE(NUMERO, 0);
    SET MILLARES = TRUNCATE(ENTERO / 1000, 0);
    SET CENTENAS = ENTERO MOD 1000;
    SET CENTIMOS = (TRUNCATE(NUMERO, 2) * 100) MOD 100;
    
    /* Procesar Millares */
    IF (MILLARES = 1) THEN
        SET EN_LETRAS = 'MIL ';
    ELSE 
        IF (MILLARES > 0) THEN
            CALL PRC_GET_NUMERO_MENOR_MIL(MILLARES, INTER); 
            SET EN_LETRAS = CONCAT(EN_LETRAS, INTER, 'MIL ');
            SET EN_LETRAS = REPLACE(EN_LETRAS, 'UNO ', 'UN ');
        END IF;
    END IF;
    
    /* Procesar Centenas */
    IF ((CENTENAS > 0) OR ((ENTERO = 0) AND (CENTIMOS = 0))) THEN
        CALL PRC_GET_NUMERO_MENOR_MIL(CENTENAS, INTER);
        SET EN_LETRAS = CONCAT(EN_LETRAS, INTER);            
    END IF;
    
    /* Procesar Céntimos */
    IF (CENTIMOS > 0) THEN
        
        IF (CENTIMOS = 1) THEN
            SET AUX = 'CÉNTIMO ';
        ELSE
            SET AUX = 'CÉNTIMOS ';
        END IF;    
        
        CALL PRC_GET_NUMERO_MENOR_MIL(CENTIMOS, INTER);
        SET CENTIMO_AUX = INTER;
        SET CENTIMO_AUX = REPLACE(CENTIMO_AUX, 'UNO ', 'UN '); 
        
        IF (ENTERO <> 0) THEN 
            SET CENTIMO_AUX_CON = 'CON '; 
        END IF;
        
        SET EN_LETRAS = CONCAT(EN_LETRAS, CENTIMO_AUX_CON, CENTIMO_AUX, AUX);
        
    END IF;
    
    SET pResul = EN_LETRAS;
    
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_GET_NUMERO_MENOR_MIL
DROP PROCEDURE IF EXISTS `PRC_GET_NUMERO_MENOR_MIL`;
DELIMITER ;;
CREATE PROCEDURE `PRC_GET_NUMERO_MENOR_MIL`(IN NUMERO DECIMAL(4), OUT pResul varchar(100))
SQL SECURITY INVOKER
BEGIN
       DECLARE CENTENAS INT;
       DECLARE DECENAS INT;
       DECLARE UNIDADES INT;
       DECLARE EN_LETRAS VARCHAR(100);
       DECLARE UNIR VARCHAR(2);
			 SET EN_LETRAS = '';
        IF (NUMERO = 100) THEN
            SET pResul = ('CIEN ');
        ELSEIF NUMERO = 0 THEN
            SET pResul = ('CERO ');
        ELSEIF NUMERO = 1 THEN
            SET pResul = ('UNO ');
        ELSE
            SET CENTENAS = TRUNCATE(NUMERO / 100,0);
            SET DECENAS  = TRUNCATE((NUMERO MOD 100)/10,0);
            SET UNIDADES = NUMERO MOD 10;
            SET UNIR = 'Y ';
            
						IF CENTENAS = 1 THEN
                SET EN_LETRAS = 'CIENTO ';
            ELSEIF CENTENAS = 2 THEN
                SET EN_LETRAS = 'DOSCIENTOS ';
            ELSEIF CENTENAS = 3 THEN
                SET EN_LETRAS = 'TRESCIENTOS ';
            ELSEIF CENTENAS = 4 THEN
                SET EN_LETRAS = 'CUATROCIENTOS ';
            ELSEIF CENTENAS = 5 THEN
                SET EN_LETRAS = 'QUINIENTOS ';
            ELSEIF CENTENAS = 6 THEN
                SET EN_LETRAS = 'SEISCIENTOS ';
            ELSEIF CENTENAS = 7 THEN
                SET EN_LETRAS = 'SETECIENTOS ';
            ELSEIF CENTENAS = 8 THEN
                SET EN_LETRAS = 'OCHOCIENTOS ';
            ELSEIF CENTENAS = 9 THEN
                SET EN_LETRAS = 'NOVECIENTOS ';
            END IF;
            
						IF DECENAS = 3 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'TREINTA ');
            ELSEIF DECENAS = 4 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'CUARENTA ');
            ELSEIF DECENAS = 5 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'CINCUENTA ');
            ELSEIF DECENAS = 6 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'SESENTA ');
            ELSEIF DECENAS = 7 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'SETENTA ');
            ELSEIF DECENAS = 8 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'OCHENTA ');
            ELSEIF DECENAS = 9 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , 'NOVENTA ');
            ELSEIF DECENAS = 1 THEN
                IF UNIDADES < 6 THEN
                    IF UNIDADES = 0 THEN
                        SET EN_LETRAS = CONCAT(EN_LETRAS , 'DIEZ ');
                    ELSEIF UNIDADES = 1 THEN
                        SET EN_LETRAS = CONCAT(EN_LETRAS , 'ONCE ');
                    ELSEIF UNIDADES = 2 THEN
                        SET EN_LETRAS = CONCAT(EN_LETRAS , 'DOCE ');
                    ELSEIF UNIDADES = 3 THEN
                        SET EN_LETRAS = CONCAT(EN_LETRAS , 'TRECE ');
                    ELSEIF UNIDADES = 4 THEN
                        SET EN_LETRAS = CONCAT(EN_LETRAS , 'CATORCE ');
                    ELSEIF UNIDADES = 5 THEN
                        SET EN_LETRAS = CONCAT(EN_LETRAS , 'QUINCE ');
                    END IF;
                    SET UNIDADES = 0;
                ELSE
                    SET EN_LETRAS = CONCAT(EN_LETRAS, 'DIECI');
                    SET UNIR = '';
                END IF;
            ELSEIF (DECENAS = 2) THEN
                IF (UNIDADES = 0) THEN
                    SET EN_LETRAS = CONCAT(EN_LETRAS, 'VEINTE ');
                ELSE
                    SET EN_LETRAS = CONCAT(EN_LETRAS, 'VEINTI');
                END IF;
                SET UNIR = '';
            ELSEIF (DECENAS = 0) THEN
                SET UNIR = '';
            END IF;
						
            IF (UNIDADES = 1) THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'UNO ');
            ELSEIF UNIDADES = 2 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'DOS ');
            ELSEIF UNIDADES = 3 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'TRES ');
            ELSEIF UNIDADES = 4 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'CUATRO ');
            ELSEIF UNIDADES = 5 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'CINCO ');
            ELSEIF UNIDADES = 6 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'SEIS ');
            ELSEIF UNIDADES = 7 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'SIETE ');
            ELSEIF UNIDADES = 8 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS, UNIR, 'OCHO ');
            ELSEIF UNIDADES = 9 THEN
                SET EN_LETRAS = CONCAT(EN_LETRAS , UNIR , 'NUEVE ');
            END IF;
        END IF;
        SET pResul = EN_LETRAS;
    END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PED_CREAR_ALBARAN_FIN
DROP PROCEDURE IF EXISTS `PRC_PED_CREAR_ALBARAN_FIN`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PED_CREAR_ALBARAN_FIN`(
  IN p_NUMERO_ALB varchar(20),
  IN p_SERIE_ALB varchar(20),
  IN p_NUMERO_PED varchar(20),
  IN p_SERIE_PED varchar(20),
  IN p_USUARIO varchar(100))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_total_base decimal(18,6) DEFAULT 0;
  DECLARE v_total_iva decimal(18,6) DEFAULT 0;
  DECLARE v_pendientes int DEFAULT 0;
  SELECT IFNULL(SUM(`CANTIDAD_ALBLIN` *
                    `PRECIO_VENTA_SIVA_ARTICULO_ALBLIN`), 0),
         IFNULL(SUM(`CANTIDAD_ALBLIN` *
              (`PRECIO_VENTA_CIVA_ARTICULO_ALBLIN` -
               `PRECIO_VENTA_SIVA_ARTICULO_ALBLIN`)), 0)
    INTO v_total_base, v_total_iva
    FROM `fza_albaranes_lineas`
   WHERE `NUMERO_ALB_ALBLIN` = p_NUMERO_ALB
     AND `SERIE_ALB_ALBLIN` = p_SERIE_ALB;
  UPDATE `fza_albaranes`
     SET `TOTAL_BASES_ALB` = v_total_base,
         `TOTAL_IMPUESTOS_ALB` = v_total_iva,
         `TOTAL_RETENCION_ALB` = v_total_base *
           IFNULL(`PORCENTAJE_RETENCION_ALB`, 0) / 100,
         `TOTAL_LIQUIDO_ALB` = v_total_base + v_total_iva -
           v_total_base * IFNULL(`PORCENTAJE_RETENCION_ALB`, 0) / 100,
         `INSTANTE_MODIF` = NOW(),
         `USUARIO_MODIF` = p_USUARIO
   WHERE `NUMERO_ALB` = p_NUMERO_ALB
     AND `SERIE_ALB` = p_SERIE_ALB;
  SELECT COUNT(*)
    INTO v_pendientes
    FROM `fza_pedidos_lineas`
   WHERE `NUMERO_PED_PEDLIN` = p_NUMERO_PED
     AND `SERIE_PED_PEDLIN` = p_SERIE_PED
     AND IFNULL(`CANTIDAD_PEDLIN`, 0) >
         IFNULL(`CANTIDAD_ENTREGADA_PEDLIN`, 0);
  IF v_pendientes = 0 THEN
    UPDATE `fza_pedidos`
       SET `ESTADO_PED` = 'ENTREGADO',
           `INSTANTE_MODIF` = NOW(),
           `USUARIO_MODIF` = p_USUARIO
     WHERE `NUMERO_PED` = p_NUMERO_PED
       AND `SERIE_PED` = p_SERIE_PED;
  ELSE
    UPDATE `fza_pedidos`
       SET `ESTADO_PED` = 'PARCIAL',
           `INSTANTE_MODIF` = NOW(),
           `USUARIO_MODIF` = p_USUARIO
     WHERE `NUMERO_PED` = p_NUMERO_PED
       AND `SERIE_PED` = p_SERIE_PED;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PED_CREAR_ALBARAN_INICIO
DROP PROCEDURE IF EXISTS `PRC_PED_CREAR_ALBARAN_INICIO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PED_CREAR_ALBARAN_INICIO`(
  IN p_NUMERO_PED varchar(20),
  IN p_SERIE_PED varchar(20),
  IN p_USUARIO varchar(100),
  OUT p_NUMERO_ALB varchar(20),
  OUT p_SERIE_ALB varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_serie varchar(20);
  DECLARE v_numero varchar(20);
  SELECT `SERIE_PED`
    INTO v_serie
    FROM `fza_pedidos`
   WHERE `NUMERO_PED` = p_NUMERO_PED
     AND `SERIE_PED` = p_SERIE_PED;
  SELECT LPAD(IFNULL(MAX(CAST(`NUMERO_ALB` AS UNSIGNED)), 0) + 1, 6, '0')
    INTO v_numero
    FROM `fza_albaranes`
   WHERE `SERIE_ALB` = v_serie;
  INSERT INTO `fza_albaranes` (
    `NUMERO_ALB`, `SERIE_ALB`, `FECHA_ALB`,
    `INSTANTE_MOVIMIENTO_ALB`, `ESTADO_ALB`,
    `NUMERO_PED_ALB`, `SERIE_PED_ALB`,
    `CODIGO_EMP_ALB`, `CODIGO_ALM_ALB`,
    `RAZON_SOCIAL_EMPRESA_ALB`, `NIF_EMPRESA_ALB`,
    `MOVIL_EMPRESA_ALB`, `EMAIL_EMPRESA_ALB`,
    `DIRECCION1_EMPRESA_ALB`, `DIRECCION2_EMPRESA_ALB`,
    `POBLACION_EMPRESA_ALB`, `PROVINCIA_EMPRESA_ALB`,
    `CODIGO_PAI_EMPRESA_ALB`, `NOMBRE_PAI_EMPRESA_ALB`,
    `CODIGO_POSTAL_EMPRESA_ALB`, `GRUPO_ZONA_IVA_EMPRESA_ALB`,
    `CODIGO_CLI_ALB`, `RAZON_SOCIAL_CLIENTE_ALB`,
    `NIF_CLIENTE_ALB`, `MOVIL_CLIENTE_ALB`, `EMAIL_CLIENTE_ALB`,
    `DIRECCION1_CLIENTE_ALB`, `DIRECCION2_CLIENTE_ALB`,
    `POBLACION_CLIENTE_ALB`, `PROVINCIA_CLIENTE_ALB`,
    `CODIGO_POSTAL_CLIENTE_ALB`, `CODIGO_PAI_CLIENTE_ALB`,
    `NOMBRE_PAI_CLIENTE_ALB`, `NOMBRE_CLI_ENVIO_ALB`,
    `MOVIL_CLIENTE_ENVIO_ALB`, `DIRECCION1_CLIENTE_ENVIO_ALB`,
    `DIRECCION2_CLIENTE_ENVIO_ALB`, `POBLACION_CLIENTE_ENVIO_ALB`,
    `PROVINCIA_CLIENTE_ENVIO_ALB`, `CODIGO_POSTAL_CLIENTE_ENVIO_ALB`,
    `CODIGO_PAI_CLIENTE_ENVIO_ALB`, `NOMBRE_PAI_CLIENTE_ENVIO_ALB`,
    `TRANSPORTISTA_ALB`, `CODIGO_IVA_ALB`,
    `ESIVA_RECARGO_CLIENTE_ALB`, `ESIVA_EXENTO_CLIENTE_ALB`,
    `ESINTRACOMUNITARIO_CLIENTE_ALB`, `TARIFA_ARTICULO_CLIENTE_ALB`,
    `ESIMP_INCL_TARIFA_CLIENTE_ALB`, `PORCENTAJE_IVAN_ALB`,
    `PORCENTAJE_IVAR_ALB`, `PORCENTAJE_IVAS_ALB`, `PORCENTAJE_IVAE_ALB`,
    `PORCENTAJE_RETENCION_ALB`, `FORMA_PAGO_ALB`, `CONTADOR_LINEAS_ALB`,
    `INSTANTE_ALTA`, `USUARIO_ALTA`, `USUARIO_MODIF`)
  SELECT v_numero, v_serie, CURRENT_DATE(), NOW(), 'ABIERTO',
         p_NUMERO_PED, p_SERIE_PED,
         P.`CODIGO_EMP_PED`, P.`CODIGO_ALM_PED`,
         P.`RAZON_SOCIAL_EMPRESA_PED`, P.`NIF_EMPRESA_PED`,
         P.`MOVIL_EMPRESA_PED`, P.`EMAIL_EMPRESA_PED`,
         P.`DIRECCION1_EMPRESA_PED`, P.`DIRECCION2_EMPRESA_PED`,
         P.`POBLACION_EMPRESA_PED`, P.`PROVINCIA_EMPRESA_PED`,
         P.`CODIGO_PAI_EMPRESA_PED`, P.`NOMBRE_PAI_EMPRESA_PED`,
         P.`CODIGO_POSTAL_EMPRESA_PED`, P.`GRUPO_ZONA_IVA_EMPRESA_PED`,
         P.`CODIGO_CLI_PED`, P.`RAZON_SOCIAL_CLIENTE_FISCAL_PED`,
         P.`NIF_CLIENTE_PED`, P.`MOVIL_CLIENTE_FISCAL_PED`,
         P.`EMAIL_CLIENTE_PED`, P.`DIRECCION1_CLIENTE_FISCAL_PED`,
         P.`DIRECCION2_CLIENTE_FISCAL_PED`,
         P.`POBLACION_CLIENTE_FISCAL_PED`,
         P.`PROVINCIA_CLIENTE_FISCAL_PED`,
         P.`CODIGO_POSTAL_CLIENTE_FISCAL_PED`,
         P.`CODIGO_PAI_CLIENTE_FISCAL_PED`,
         P.`NOMBRE_PAI_CLIENTE_FISCAL_PED`,
         P.`NOMBRE_CLI_ENVIO_PED`, P.`MOVIL_CLIENTE_ENVIO_PED`,
         P.`DIRECCION1_CLIENTE_ENVIO_PED`,
         P.`DIRECCION2_CLIENTE_ENVIO_PED`,
         P.`POBLACION_CLIENTE_ENVIO_PED`,
         P.`PROVINCIA_CLIENTE_ENVIO_PED`,
         P.`CODIGO_POSTAL_CLIENTE_ENVIO_PED`,
         P.`CODIGO_PAI_CLIENTE_ENVIO_PED`,
         P.`NOMBRE_PAI_CLIENTE_ENVIO_PED`,
         P.`TRANSPORTISTAPS_PED`, P.`CODIGO_IVA_PED`,
         P.`ESIVA_RECARGO_CLIENTE_PED`, P.`ESIVA_EXENTO_CLIENTE_PED`,
         P.`ESINTRACOMUNITARIO_CLIENTE_PED`,
         P.`TARIFA_ARTICULO_CLIENTE_PED`,
         P.`ESIMP_INCL_TARIFA_CLIENTE_PED`, P.`PORCENTAJE_IVAN_PED`,
         P.`PORCENTAJE_IVAR_PED`, P.`PORCENTAJE_IVAS_PED`,
         P.`PORCENTAJE_IVAE_PED`, P.`PORCENTAJE_RETENCION_PED`,
         P.`FORMA_PAGO_PED`, '0', NOW(), p_USUARIO, p_USUARIO
    FROM `fza_pedidos` P
   WHERE P.`NUMERO_PED` = p_NUMERO_PED
     AND P.`SERIE_PED` = p_SERIE_PED;
  SET p_NUMERO_ALB = v_numero;
  SET p_SERIE_ALB = v_serie;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PED_CREAR_ALBARAN_LINEA
DROP PROCEDURE IF EXISTS `PRC_PED_CREAR_ALBARAN_LINEA`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PED_CREAR_ALBARAN_LINEA`(
  IN p_NUMERO_ALB varchar(20),
  IN p_SERIE_ALB varchar(20),
  IN p_NUMERO_PED varchar(20),
  IN p_SERIE_PED varchar(20),
  IN p_LINEA_PED varchar(4),
  IN p_CANTIDAD decimal(19,6),
  IN p_CODIGO_ALM varchar(10),
  IN p_USUARIO varchar(100))
SQL SECURITY INVOKER
PRC: BEGIN
  DECLARE v_linea varchar(4);
  DECLARE v_pedida decimal(19,6) DEFAULT 0;
  DECLARE v_albaranada decimal(19,6) DEFAULT 0;
  DECLARE v_objetivo decimal(19,6) DEFAULT 0;
  DECLARE v_pendiente decimal(19,6) DEFAULT 0;
  DECLARE v_cantidad decimal(19,6) DEFAULT 0;
  SELECT IFNULL(`CANTIDAD_PEDLIN`, 0)
    INTO v_pedida
    FROM `fza_pedidos_lineas`
   WHERE `NUMERO_PED_PEDLIN` = p_NUMERO_PED
     AND `SERIE_PED_PEDLIN` = p_SERIE_PED
     AND `LINEA_PEDLIN` = p_LINEA_PED;
  SELECT IFNULL(SUM(`CANTIDAD_ALBLIN`), 0)
    INTO v_albaranada
    FROM `fza_albaranes_lineas`
   WHERE `NUMERO_PED_ALBLIN` = p_NUMERO_PED
     AND `SERIE_PED_ALBLIN` = p_SERIE_PED
     AND `LINEA_PED_ALBLIN` = p_LINEA_PED;
  SET v_objetivo = LEAST(IFNULL(p_CANTIDAD, 0), v_pedida);
  SET v_pendiente = v_pedida - v_albaranada;
  SET v_cantidad = v_objetivo - v_albaranada;
  IF v_pedida <= 0 OR v_pendiente <= 0 OR v_cantidad <= 0 THEN
    LEAVE PRC;
  END IF;
  IF v_cantidad > v_pendiente THEN
    SET v_cantidad = v_pendiente;
  END IF;
  UPDATE `fza_albaranes`
     SET `CONTADOR_LINEAS_ALB` = LPAD(LAST_INSERT_ID(
           IFNULL(CAST(NULLIF(`CONTADOR_LINEAS_ALB`, '')
           AS UNSIGNED), 0) + 10), 8, '0')
   WHERE `NUMERO_ALB` = p_NUMERO_ALB
     AND `SERIE_ALB` = p_SERIE_ALB;
  IF ROW_COUNT() = 0 THEN
    LEAVE PRC;
  END IF;
  SET v_linea = LPAD(LAST_INSERT_ID(), 4, '0');
  INSERT INTO `fza_albaranes_lineas` (
    `NUMERO_ALB_ALBLIN`, `SERIE_ALB_ALBLIN`, `LINEA_ALBLIN`,
    `NUMERO_PED_ALBLIN`, `SERIE_PED_ALBLIN`, `LINEA_PED_ALBLIN`,
    `CODIGO_ART_ALBLIN`, `CODIGO_UNIDAD_ALBLIN`,
    `CODIGO_FAM_ALBLIN`, `NOMBRE_FAM_ALBLIN`,
    `DESCRIPCION_ARTICULO_ALBLIN`, `TIPO_CANTIDAD_ARTICULO_ALBLIN`,
    `CANTIDAD_ALBLIN`, `CODIGO_TAR_ALBLIN`, `ESIMP_INCL_TARIFA_ALBLIN`,
    `TIPO_IVA_ARTICULO_ALBLIN`, `PORCENTAJE_IVA_ALBLIN`,
    `PRECIO_VENTA_SIVA_ARTICULO_ALBLIN`,
    `PRECIO_VENTA_CIVA_ARTICULO_ALBLIN`, `TOTAL_ALBLIN`,
    `CODIGO_ALMACEN_ALBLIN`, `INSTANTE_ALTA`, `USUARIO_ALTA`,
    `USUARIO_MODIF`)
  SELECT p_NUMERO_ALB, p_SERIE_ALB, v_linea,
         p_NUMERO_PED, p_SERIE_PED, p_LINEA_PED,
         PL.`CODIGO_ART_PEDLIN`,
         COALESCE(NULLIF(PL.`CODIGOPRODPS_PEDLIN`, ''),
                  NULLIF(PL.`CODIGO_UNIDAD_PEDLIN`, ''),
                  PL.`CODIGO_ART_PEDLIN`),
         PL.`CODIGO_FAM_PEDLIN`, PL.`NOMBRE_FAM_PEDLIN`,
         PL.`DESCRIPCION_ARTICULO_PEDLIN`,
         PL.`TIPO_CANTIDAD_ARTICULO_PEDLIN`,
         v_cantidad, PL.`CODIGO_TAR_PEDLIN`,
         PL.`ESIMP_INCL_TARIFA_PEDLIN`,
         PL.`TIPO_IVA_ARTICULO_PEDLIN`, PL.`PORCENTAJE_IVA_PEDLIN`,
         PL.`PRECIO_VENTA_SIVA_ARTICULO_PEDLIN`,
         PL.`PRECIO_VENTA_CIVA_ARTICULO_PEDLIN`,
         v_cantidad * PL.`PRECIO_VENTA_SIVA_ARTICULO_PEDLIN`,
         COALESCE(NULLIF(p_CODIGO_ALM, ''),
                  PL.`CODIGO_ALMACEN_PEDLIN`),
         NOW(), p_USUARIO, p_USUARIO
    FROM `fza_pedidos_lineas` PL
   WHERE PL.`NUMERO_PED_PEDLIN` = p_NUMERO_PED
     AND PL.`SERIE_PED_PEDLIN` = p_SERIE_PED
     AND PL.`LINEA_PEDLIN` = p_LINEA_PED;
  UPDATE `fza_pedidos_lineas`
     SET `CANTIDAD_ENTREGADA_PEDLIN` = v_albaranada + v_cantidad,
         `CANTIDAD_PENDIENTE_PEDLIN` =
           GREATEST(`CANTIDAD_PEDLIN` -
                    (v_albaranada + v_cantidad), 0),
         `CANTIDAD_A_ALBARANAR_PEDLIN` = 0,
         `ESENTREGADA_PEDLIN` = CASE
           WHEN `CANTIDAD_PEDLIN` <= v_albaranada + v_cantidad
           THEN 'S' ELSE 'N' END,
         `INSTANTE_MODIF` = NOW(),
         `USUARIO_MODIF` = p_USUARIO
   WHERE `NUMERO_PED_PEDLIN` = p_NUMERO_PED
     AND `SERIE_PED_PEDLIN` = p_SERIE_PED
     AND `LINEA_PEDLIN` = p_LINEA_PED;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_CAMBIO
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_CAMBIO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_CAMBIO`(
  IN p_CODIGO_ART varchar(20),
  IN p_CODIGO_UNIDAD varchar(50),
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_codigo_art varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  SET v_codigo_art = NULLIF(TRIM(p_CODIGO_ART), '');
  IF v_codigo_art IS NULL AND
     NULLIF(TRIM(p_CODIGO_UNIDAD), '') IS NOT NULL THEN
    SELECT S.CODIGO_ART_SKU
      INTO v_codigo_art
      FROM fza_articulos_skus S
     WHERE S.CODIGO_UNIDAD_SKU = TRIM(p_CODIGO_UNIDAD)
     LIMIT 1;
  END IF;
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
  CREATE TEMPORARY TABLE tmp_prestashop_encolar_articulos (
    codigo_art varchar(20) COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (codigo_art)
  ) ENGINE=InnoDB;
  IF v_codigo_art IS NOT NULL THEN
    INSERT IGNORE INTO tmp_prestashop_encolar_articulos (codigo_art)
    VALUES (v_codigo_art);
  END IF;
  CALL PRC_PRESTASHOP_ENCOLAR_TEMP(
    p_ES_PRECIO, p_ES_STOCK, p_USUARIO, '');
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_CAMBIO_ALMACEN
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_CAMBIO_ALMACEN`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_CAMBIO_ALMACEN`(
  IN p_CODIGO_ART varchar(20),
  IN p_CODIGO_UNIDAD varchar(50),
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200),
  IN p_CODIGO_ALM varchar(10)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_codigo_art varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  SET v_codigo_art = NULLIF(TRIM(p_CODIGO_ART), '');
  IF v_codigo_art IS NULL AND
     NULLIF(TRIM(p_CODIGO_UNIDAD), '') IS NOT NULL THEN
    SELECT S.CODIGO_ART_SKU
      INTO v_codigo_art
      FROM fza_articulos_skus S
     WHERE S.CODIGO_UNIDAD_SKU = TRIM(p_CODIGO_UNIDAD)
     LIMIT 1;
  END IF;
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
  CREATE TEMPORARY TABLE tmp_prestashop_encolar_articulos (
    codigo_art varchar(20) COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (codigo_art)
  ) ENGINE=InnoDB;
  IF v_codigo_art IS NOT NULL THEN
    INSERT IGNORE INTO tmp_prestashop_encolar_articulos (codigo_art)
    VALUES (v_codigo_art);
  END IF;
  CALL PRC_PRESTASHOP_ENCOLAR_TEMP(
    p_ES_PRECIO, p_ES_STOCK, p_USUARIO, p_CODIGO_ALM);
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_STOCK_ALMACEN
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_STOCK_ALMACEN`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_STOCK_ALMACEN`(
  IN p_CODIGO_ALM varchar(10),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
  CREATE TEMPORARY TABLE tmp_prestashop_encolar_articulos (
    codigo_art varchar(20) COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (codigo_art)
  ) ENGINE=InnoDB;
  INSERT IGNORE INTO tmp_prestashop_encolar_articulos (codigo_art)
  SELECT A.CODIGO_ART_ART
    FROM fza_articulos_stockactual STK
    LEFT JOIN fza_articulos_skus S
      ON S.CODIGO_UNIDAD_SKU = STK.CODIGO_UNIDAD_STK
    JOIN fza_articulos A
      ON A.CODIGO_ART_ART = COALESCE(
        S.CODIGO_ART_SKU, STK.CODIGO_UNIDAD_STK)
     AND A.ESWEB_ART = 'S'
   WHERE STK.CODIGO_ALM_STK = p_CODIGO_ALM;
  CALL PRC_PRESTASHOP_ENCOLAR_TEMP(
    'N', 'S', p_USUARIO, p_CODIGO_ALM);
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_STOCK_RECALCULO
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_STOCK_RECALCULO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_STOCK_RECALCULO`(
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
  CREATE TEMPORARY TABLE tmp_prestashop_encolar_articulos (
    codigo_art varchar(20) COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (codigo_art)
  ) ENGINE=InnoDB;
  INSERT IGNORE INTO tmp_prestashop_encolar_articulos (codigo_art)
  SELECT A.CODIGO_ART_ART
    FROM tmp_recalculo_final R
    JOIN fza_almacenes ALM
      ON ALM.CODIGO_ALM_ALM = R.almacen
     AND ALM.ESWEB_ALM = 'S'
     AND ALM.ESACTIVO_ALM = 'S'
     AND ALM.ESFISICO_ALM = 'S'
     AND UPPER(TRIM(ALM.TIPO_USO_ALM)) = 'ESTANDAR'
    LEFT JOIN fza_articulos_skus S
      ON S.CODIGO_UNIDAD_SKU = R.sku
    JOIN fza_articulos A
      ON A.CODIGO_ART_ART = COALESCE(S.CODIGO_ART_SKU, R.sku)
     AND A.ESWEB_ART = 'S';
  CALL PRC_PRESTASHOP_ENCOLAR_TEMP('N', 'S', p_USUARIO, '');
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_TEMP
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_TEMP`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_TEMP`(
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200),
  IN p_CODIGO_ALM_EVENTO varchar(10)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_url varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_tienda_texto varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_sincronizar_texto varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_crear_texto varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_empresa varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_tarifa varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_api_key varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_empresa_evento varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_grupo varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_clave char(64);
  DECLARE v_tienda int DEFAULT 1;
  DECLARE v_es_usuario varchar(1) DEFAULT 'N';
  DECLARE v_peticion_precio varchar(1) DEFAULT 'N';
  DECLARE v_peticion_stock varchar(1) DEFAULT 'N';
  DECLARE v_sincronizar varchar(1) DEFAULT 'N';
  DECLARE v_crear varchar(1) DEFAULT 'N';
  DECLARE v_es_precio varchar(1) DEFAULT 'N';
  DECLARE v_es_stock varchar(1) DEFAULT 'N';
  DECLARE v_usuario_perfil varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_usuario_auditoria varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  SET v_usuario_perfil = TRIM(COALESCE(p_USUARIO, ''));
  SET v_usuario_auditoria = LEFT(COALESCE(
    NULLIF(TRIM(p_USUARIO), ''), 'PRESTASHOP'), 50);
  SELECT MAX(U.GRUPO_USU), IF(COUNT(*) > 0, 'S', 'N')
    INTO v_grupo, v_es_usuario
    FROM fza_usuarios U
   WHERE U.USUARIO_USU = v_usuario_perfil
     COLLATE utf8mb4_spanish_ci
     AND U.ESACTIVO_USU = 'S';
  IF v_es_usuario <> 'S' THEN
    SET v_usuario_perfil = '';
    SET v_grupo = '';
  END IF;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER = 'appPrestaShopUrl'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), '')
    INTO v_url;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER = 'appPrestaShopApiKey'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), '')
    INTO v_api_key;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER = 'appPrestaShopIdTienda'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), '1')
    INTO v_tienda_texto;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER =
         'appPrestaShopSincronizarStockPrecios'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), 'False')
    INTO v_sincronizar_texto;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER = 'appPrestaShopCrearArticulos'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), 'False')
    INTO v_crear_texto;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER = 'appPrestaShopEmpresa'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), '1')
    INTO v_empresa;
  SELECT COALESCE((
    SELECT TRIM(P.VALUE_USUPER)
      FROM fza_usuarios_perfiles P
     WHERE P.KEY_USUPER = 'frmMtoAppParam'
       AND P.SUBKEY_USUPER = 'appPrestaShopTarifa'
       AND (P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci OR
         (v_es_usuario = 'S' AND
          (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
             COLLATE utf8mb4_spanish_ci OR
           P.USUARIO_GRUPO_USUPER = v_grupo
             COLLATE utf8mb4_spanish_ci)))
     ORDER BY CASE P.USUARIO_GRUPO_USUPER
       WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
       WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
       ELSE 3 END
     LIMIT 1), 'PVP')
    INTO v_tarifa;
  SET v_url = TRIM(TRAILING '/' FROM TRIM(v_url));
  IF TRIM(v_tienda_texto) REGEXP '^[+-]?[0-9]+$' AND
     LENGTH(TRIM(v_tienda_texto)) <= 11 AND
     CAST(TRIM(v_tienda_texto) AS signed)
       BETWEEN -2147483648 AND 2147483647 THEN
    SET v_tienda = CAST(TRIM(v_tienda_texto) AS signed);
  END IF;
  SET v_clave = UPPER(SHA2(v_url, 256));
  SET v_peticion_precio = IF(
    UPPER(TRIM(p_ES_PRECIO)) = 'S', 'S', 'N');
  SET v_peticion_stock = IF(
    UPPER(TRIM(p_ES_STOCK)) = 'S', 'S', 'N');
  SET v_sincronizar = IF(
    UPPER(TRIM(v_sincronizar_texto)) IN ('TRUE', '1', 'S'), 'S', 'N');
  SET v_crear = IF(
    UPPER(TRIM(v_crear_texto)) IN ('TRUE', '1', 'S'), 'S', 'N');
  SET v_es_precio = IF(
    (v_sincronizar = 'S' AND v_peticion_precio = 'S') OR
    (v_sincronizar = 'N' AND v_crear = 'S' AND
     (v_peticion_precio = 'S' OR v_peticion_stock = 'S')),
    'S', 'N');
  SET v_es_stock = IF(
    v_sincronizar = 'S' AND v_peticion_stock = 'S', 'S', 'N');
  SET v_empresa_evento = '';
  IF NULLIF(TRIM(p_CODIGO_ALM_EVENTO), '') IS NOT NULL THEN
    SELECT MAX(A.CODIGO_EMP_ALM)
      INTO v_empresa_evento
      FROM fza_almacenes A
     WHERE A.CODIGO_ALM_ALM =
       TRIM(p_CODIGO_ALM_EVENTO) COLLATE utf8mb4_spanish_ci;
  END IF;
  UPDATE fza_prestashop_cola C
  JOIN tmp_prestashop_encolar_articulos T
    ON T.codigo_art = C.CODIGO_ART_PSCOLA
  LEFT JOIN fza_articulos A
    ON A.CODIGO_ART_ART = T.codigo_art
     SET C.ESCAMBIO_PRECIO_PSCOLA = 'N',
         C.ESCAMBIO_STOCK_PSCOLA = 'N',
         C.VERSION_DESEADA_PSCOLA = C.VERSION_DESEADA_PSCOLA + 1,
         C.VERSION_RECLAMADA_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.VERSION_RECLAMADA_PSCOLA, NULL),
         C.ESCAMBIO_PRECIO_RECLAMADO_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.ESCAMBIO_PRECIO_RECLAMADO_PSCOLA, 'N'),
         C.ESCAMBIO_STOCK_RECLAMADO_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.ESCAMBIO_STOCK_RECLAMADO_PSCOLA, 'N'),
         C.ACCION_VISIBILIDAD_RECLAMADA_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.ACCION_VISIBILIDAD_RECLAMADA_PSCOLA, 'N'),
         C.CONTADOR_INTENTOS_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.CONTADOR_INTENTOS_PSCOLA, 0),
         C.INSTANTE_PROXIMO_INTENTO_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.INSTANTE_PROXIMO_INTENTO_PSCOLA, NULL),
         C.ID_RECLAMACION_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.ID_RECLAMACION_PSCOLA, NULL),
         C.INSTANTE_RECLAMACION_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.INSTANTE_RECLAMACION_PSCOLA, NULL),
         C.MENSAJE_ERROR_PSCOLA = IF(
           LEFT(COALESCE(C.MENSAJE_ERROR_PSCOLA, ''), 18) =
             '[ALTA_PRESTASHOP] ',
           C.MENSAJE_ERROR_PSCOLA, NULL),
         C.ESTADO_PSCOLA = IF(
           C.ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
           C.ESTADO_PSCOLA, 'ENVIADA'),
         C.INSTANTE_ULTIMO_CAMBIO_PSCOLA = NOW(),
         C.INSTANTE_MODIF = NOW(),
         C.USUARIO_MODIF = v_usuario_auditoria
   WHERE ((v_peticion_precio = 'N' AND v_peticion_stock = 'N')
      OR COALESCE(A.ESWEB_ART, 'N') <> 'S')
     AND C.ACCION_VISIBILIDAD_PSCOLA = 'N';
  IF (v_es_precio = 'S' OR v_es_stock = 'S') AND
     NULLIF(v_url, '') IS NOT NULL AND
     NULLIF(TRIM(v_api_key), '') IS NOT NULL AND
     NULLIF(TRIM(v_empresa), '') IS NOT NULL AND
     NULLIF(TRIM(v_tarifa), '') IS NOT NULL AND
     v_tienda > 0 AND
     (NULLIF(TRIM(p_CODIGO_ALM_EVENTO), '') IS NULL OR
      UPPER(TRIM(v_empresa_evento)) = UPPER(TRIM(v_empresa))) THEN
    CALL PRC_PRESTASHOP_ENCOLAR_TEMP_DESTINO(
      v_clave,
      v_tienda,
      v_es_precio,
      v_es_stock,
      v_usuario_auditoria);
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_TEMP_DESTINO
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_TEMP_DESTINO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_TEMP_DESTINO`(
  IN p_CLAVE_INSTALACION char(64),
  IN p_ID_TIENDA int,
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_es_precio varchar(1) DEFAULT 'N';
  DECLARE v_es_stock varchar(1) DEFAULT 'N';
  DECLARE v_usuario varchar(50);
  SET v_es_precio = IF(UPPER(TRIM(p_ES_PRECIO)) = 'S', 'S', 'N');
  SET v_es_stock = IF(UPPER(TRIM(p_ES_STOCK)) = 'S', 'S', 'N');
  SET v_usuario = LEFT(COALESCE(NULLIF(TRIM(p_USUARIO), ''),
    'PRESTASHOP'), 50);
  IF NULLIF(TRIM(p_CLAVE_INSTALACION), '') IS NOT NULL AND
     p_ID_TIENDA > 0 AND
     (v_es_precio = 'S' OR v_es_stock = 'S') THEN
    INSERT INTO fza_prestashop_cola (
      CLAVE_INSTALACION_PSCOLA,
      ID_TIENDA_PSCOLA,
      CODIGO_ART_PSCOLA,
      ESCAMBIO_PRECIO_PSCOLA,
      ESCAMBIO_STOCK_PSCOLA,
      VERSION_DESEADA_PSCOLA,
      ESTADO_PSCOLA,
      CONTADOR_INTENTOS_PSCOLA,
      INSTANTE_ULTIMO_CAMBIO_PSCOLA,
      INSTANTE_ALTA,
      USUARIO_ALTA
    )
    SELECT UPPER(TRIM(p_CLAVE_INSTALACION)),
           p_ID_TIENDA,
           T.codigo_art,
           v_es_precio,
           v_es_stock,
           1,
           'PENDIENTE',
           0,
           NOW(),
           NOW(),
           v_usuario
      FROM tmp_prestashop_encolar_articulos T
      JOIN fza_articulos A
        ON A.CODIGO_ART_ART = T.codigo_art
       AND A.ESWEB_ART = 'S'
    ON DUPLICATE KEY UPDATE
      ESCAMBIO_PRECIO_PSCOLA = IF(
        ESCAMBIO_PRECIO_PSCOLA = 'S' OR
        VALUES(ESCAMBIO_PRECIO_PSCOLA) = 'S', 'S', 'N'),
      ESCAMBIO_STOCK_PSCOLA = IF(
        ESCAMBIO_STOCK_PSCOLA = 'S' OR
        VALUES(ESCAMBIO_STOCK_PSCOLA) = 'S', 'S', 'N'),
      VERSION_DESEADA_PSCOLA = VERSION_DESEADA_PSCOLA + 1,
      CONTADOR_INTENTOS_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        CONTADOR_INTENTOS_PSCOLA, 0),
      INSTANTE_PROXIMO_INTENTO_PSCOLA = NULL,
      MENSAJE_ERROR_PSCOLA = IF(
        LEFT(COALESCE(MENSAJE_ERROR_PSCOLA, ''), 18) =
          '[ALTA_PRESTASHOP] ' OR
        LEFT(COALESCE(MENSAJE_ERROR_PSCOLA, ''), 20) =
          '[GUARDADO_ARTICULO] ',
        MENSAJE_ERROR_PSCOLA, NULL),
      VERSION_RECLAMADA_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        VERSION_RECLAMADA_PSCOLA, NULL),
      ESCAMBIO_PRECIO_RECLAMADO_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ESCAMBIO_PRECIO_RECLAMADO_PSCOLA, 'N'),
      ESCAMBIO_STOCK_RECLAMADO_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ESCAMBIO_STOCK_RECLAMADO_PSCOLA, 'N'),
      ACCION_VISIBILIDAD_RECLAMADA_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ACCION_VISIBILIDAD_RECLAMADA_PSCOLA, 'N'),
      ID_RECLAMACION_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ID_RECLAMACION_PSCOLA, NULL),
      INSTANTE_RECLAMACION_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        INSTANTE_RECLAMACION_PSCOLA, NULL),
      ESTADO_PSCOLA = IF(
        ESTADO_PSCOLA = 'ERROR' AND
        LEFT(COALESCE(MENSAJE_ERROR_PSCOLA, ''), 20) =
          '[GUARDADO_ARTICULO] ',
        'ERROR',
        IF(ESTADO_PSCOLA IN
             ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
          IF(ESTADO_PSCOLA = 'PROCESANDO_VISIBILIDAD' OR
             ACCION_VISIBILIDAD_PSCOLA IN ('A', 'D'),
            'PROCESANDO_VISIBILIDAD', 'PROCESANDO'),
          IF(ACCION_VISIBILIDAD_PSCOLA IN ('A', 'D'),
            'PENDIENTE_VISIBILIDAD', 'PENDIENTE'))),
      INSTANTE_ULTIMO_CAMBIO_PSCOLA = NOW(),
      INSTANTE_MODIF = NOW(),
      USUARIO_MODIF = v_usuario;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_TODOS_WEB
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_TODOS_WEB`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_TODOS_WEB`(
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
  CREATE TEMPORARY TABLE tmp_prestashop_encolar_articulos (
    codigo_art varchar(20) COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (codigo_art)
  ) ENGINE=InnoDB;
  INSERT IGNORE INTO tmp_prestashop_encolar_articulos (codigo_art)
  SELECT A.CODIGO_ART_ART
    FROM fza_articulos A
   WHERE A.ESWEB_ART = 'S';
  CALL PRC_PRESTASHOP_ENCOLAR_TEMP(
    p_ES_PRECIO, p_ES_STOCK, p_USUARIO, '');
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_TODOS_WEB_DESTINO
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_TODOS_WEB_DESTINO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_TODOS_WEB_DESTINO`(
  IN p_CLAVE_INSTALACION char(64),
  IN p_ID_TIENDA int,
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
  CREATE TEMPORARY TABLE tmp_prestashop_encolar_articulos (
    codigo_art varchar(20) COLLATE utf8mb4_spanish_ci NOT NULL,
    PRIMARY KEY (codigo_art)
  ) ENGINE=InnoDB;
  INSERT IGNORE INTO tmp_prestashop_encolar_articulos (codigo_art)
  SELECT A.CODIGO_ART_ART
    FROM fza_articulos A
   WHERE A.ESWEB_ART = 'S';
  CALL PRC_PRESTASHOP_ENCOLAR_TEMP_DESTINO(
    p_CLAVE_INSTALACION,
    p_ID_TIENDA,
    p_ES_PRECIO,
    p_ES_STOCK,
    p_USUARIO);
  DROP TEMPORARY TABLE IF EXISTS tmp_prestashop_encolar_articulos;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD`(
  IN p_CODIGO_ART varchar(20),
  IN p_ACCION varchar(1),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_accion char(1);
  DECLARE v_api_key varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_cancelacion_local char(1) DEFAULT 'N';
  DECLARE v_clave char(64);
  DECLARE v_codigo_art varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_crear char(1) DEFAULT 'N';
  DECLARE v_crear_texto varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_empresa varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_es_precio char(1) DEFAULT 'N';
  DECLARE v_es_stock char(1) DEFAULT 'N';
  DECLARE v_es_usuario char(1) DEFAULT 'N';
  DECLARE v_esweb char(1) DEFAULT 'N';
  DECLARE v_existe_articulo int DEFAULT 0;
  DECLARE v_grupo varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_sincronizar char(1) DEFAULT 'N';
  DECLARE v_sincronizar_texto varchar(200)
    CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_tarifa varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_tienda int DEFAULT 1;
  DECLARE v_tienda_texto varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_url varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_usuario_auditoria varchar(50)
    CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_usuario_perfil varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;

  SET v_codigo_art = NULLIF(TRIM(p_CODIGO_ART), '');
  SET v_accion = UPPER(TRIM(COALESCE(p_ACCION, 'N')));
  IF v_codigo_art IS NULL THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
        'La visibilidad PrestaShop no identifica el articulo';
  END IF;
  IF v_accion NOT IN ('N', 'A', 'D') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Accion de visibilidad PrestaShop no valida';
  END IF;

  SELECT COUNT(*), COALESCE(MAX(A.ESWEB_ART), 'N')
    INTO v_existe_articulo, v_esweb
    FROM fza_articulos A
   WHERE A.CODIGO_ART_ART = v_codigo_art;
  IF v_existe_articulo = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'No existe el articulo indicado para PrestaShop';
  END IF;
  IF v_esweb = 'S' AND v_accion = 'D' THEN
    SET v_accion = 'N';
  END IF;
  IF v_esweb <> 'S' AND v_accion = 'A' THEN
    SET v_accion = 'N';
  END IF;
  IF v_esweb <> 'S' AND v_accion = 'N' THEN
    SET v_cancelacion_local = 'S';
    UPDATE fza_prestashop_cola
       SET ESCAMBIO_PRECIO_PSCOLA = 'N',
           ESCAMBIO_STOCK_PSCOLA = 'N',
           ACCION_VISIBILIDAD_PSCOLA = 'N',
           VERSION_DESEADA_PSCOLA = VERSION_DESEADA_PSCOLA + 1,
           VERSION_RECLAMADA_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             VERSION_RECLAMADA_PSCOLA, NULL),
           ESCAMBIO_PRECIO_RECLAMADO_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             ESCAMBIO_PRECIO_RECLAMADO_PSCOLA, 'N'),
           ESCAMBIO_STOCK_RECLAMADO_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             ESCAMBIO_STOCK_RECLAMADO_PSCOLA, 'N'),
           ACCION_VISIBILIDAD_RECLAMADA_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             ACCION_VISIBILIDAD_RECLAMADA_PSCOLA, 'N'),
           CONTADOR_INTENTOS_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             CONTADOR_INTENTOS_PSCOLA, 0),
           INSTANTE_PROXIMO_INTENTO_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             INSTANTE_PROXIMO_INTENTO_PSCOLA, NULL),
           ID_RECLAMACION_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             ID_RECLAMACION_PSCOLA, NULL),
           INSTANTE_RECLAMACION_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             INSTANTE_RECLAMACION_PSCOLA, NULL),
           MENSAJE_ERROR_PSCOLA = IF(
             LEFT(COALESCE(MENSAJE_ERROR_PSCOLA, ''), 18) =
               '[ALTA_PRESTASHOP] ',
             MENSAJE_ERROR_PSCOLA, NULL),
           ESTADO_PSCOLA = IF(
             ESTADO_PSCOLA IN
               ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
             ESTADO_PSCOLA, 'ENVIADA'),
           INSTANTE_ULTIMO_CAMBIO_PSCOLA = NOW(),
           INSTANTE_MODIF = NOW(),
           USUARIO_MODIF = LEFT(COALESCE(
             NULLIF(TRIM(p_USUARIO), ''), 'PRESTASHOP'), 50)
     WHERE CODIGO_ART_PSCOLA = v_codigo_art;
  END IF;

  SET v_usuario_perfil = TRIM(COALESCE(p_USUARIO, ''));
  SET v_usuario_auditoria = LEFT(COALESCE(
    NULLIF(v_usuario_perfil, ''), 'PRESTASHOP'), 50);
  SELECT MAX(U.GRUPO_USU), IF(COUNT(*) > 0, 'S', 'N')
    INTO v_grupo, v_es_usuario
    FROM fza_usuarios U
   WHERE U.USUARIO_USU = v_usuario_perfil
     COLLATE utf8mb4_spanish_ci
     AND U.ESACTIVO_USU = 'S';
  IF v_es_usuario <> 'S' THEN
    SET v_usuario_perfil = '';
    SET v_grupo = '';
  END IF;

  SELECT
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER = 'appPrestaShopUrl'
      AND R.RN = 1 THEN TRIM(R.VALUE_USUPER) END), ''),
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER = 'appPrestaShopApiKey'
      AND R.RN = 1 THEN TRIM(R.VALUE_USUPER) END), ''),
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER = 'appPrestaShopIdTienda'
      AND R.RN = 1 THEN TRIM(R.VALUE_USUPER) END), '1'),
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER =
      'appPrestaShopSincronizarStockPrecios' AND R.RN = 1
      THEN TRIM(R.VALUE_USUPER) END), 'False'),
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER =
      'appPrestaShopCrearArticulos' AND R.RN = 1
      THEN TRIM(R.VALUE_USUPER) END), 'False'),
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER = 'appPrestaShopEmpresa'
      AND R.RN = 1 THEN TRIM(R.VALUE_USUPER) END), '1'),
    COALESCE(MAX(CASE WHEN R.SUBKEY_USUPER = 'appPrestaShopTarifa'
      AND R.RN = 1 THEN TRIM(R.VALUE_USUPER) END), 'PVP')
    INTO v_url, v_api_key, v_tienda_texto,
         v_sincronizar_texto, v_crear_texto, v_empresa, v_tarifa
    FROM (
      SELECT P.SUBKEY_USUPER, P.VALUE_USUPER,
             ROW_NUMBER() OVER (
               PARTITION BY P.SUBKEY_USUPER
               ORDER BY CASE P.USUARIO_GRUPO_USUPER
                 WHEN v_usuario_perfil COLLATE utf8mb4_spanish_ci THEN 1
                 WHEN v_grupo COLLATE utf8mb4_spanish_ci THEN 2
                 ELSE 3 END) AS RN
        FROM fza_usuarios_perfiles P
       WHERE P.KEY_USUPER = 'frmMtoAppParam'
         AND P.SUBKEY_USUPER IN (
           'appPrestaShopUrl',
           'appPrestaShopApiKey',
           'appPrestaShopIdTienda',
           'appPrestaShopSincronizarStockPrecios',
           'appPrestaShopCrearArticulos',
           'appPrestaShopEmpresa',
           'appPrestaShopTarifa')
         AND (P.USUARIO_GRUPO_USUPER =
                'Todos' COLLATE utf8mb4_spanish_ci OR
           (v_es_usuario = 'S' AND
            (P.USUARIO_GRUPO_USUPER = v_usuario_perfil
               COLLATE utf8mb4_spanish_ci OR
             P.USUARIO_GRUPO_USUPER = v_grupo
               COLLATE utf8mb4_spanish_ci)))
    ) R;

  SET v_url = TRIM(TRAILING '/' FROM TRIM(v_url));
  IF TRIM(v_tienda_texto) REGEXP '^[+]?[0-9]+$' AND
     LENGTH(TRIM(v_tienda_texto)) <= 10 AND
     CAST(TRIM(v_tienda_texto) AS unsigned) <= 2147483647 THEN
    SET v_tienda = CAST(TRIM(v_tienda_texto) AS signed);
  ELSE
    SET v_tienda = 0;
  END IF;
  SET v_sincronizar = IF(
    UPPER(TRIM(v_sincronizar_texto)) IN ('TRUE', '1', 'S'),
    'S', 'N');
  SET v_crear = IF(
    UPPER(TRIM(v_crear_texto)) IN ('TRUE', '1', 'S'),
    'S', 'N');
  IF v_esweb = 'S' THEN
    SET v_es_precio = IF(
      v_sincronizar = 'S' OR
      (v_accion <> 'A' AND v_crear = 'S'), 'S', 'N');
    SET v_es_stock = IF(v_sincronizar = 'S', 'S', 'N');
  ELSE
    SET v_es_precio = 'N';
    SET v_es_stock = 'N';
  END IF;

  IF v_cancelacion_local = 'N' AND v_accion IN ('A', 'D') AND
     (NULLIF(v_url, '') IS NULL OR v_tienda <= 0) THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
        'Faltan URL o tienda para cambiar la visibilidad PrestaShop';
  END IF;

  IF v_cancelacion_local = 'N' AND
     NULLIF(v_url, '') IS NOT NULL AND
     v_tienda > 0 THEN
    SET v_clave = UPPER(SHA2(v_url, 256));
    INSERT INTO fza_prestashop_cola (
      CLAVE_INSTALACION_PSCOLA,
      ID_TIENDA_PSCOLA,
      CODIGO_ART_PSCOLA,
      ESCAMBIO_PRECIO_PSCOLA,
      ESCAMBIO_STOCK_PSCOLA,
      ACCION_VISIBILIDAD_PSCOLA,
      VERSION_DESEADA_PSCOLA,
      ESTADO_PSCOLA,
      CONTADOR_INTENTOS_PSCOLA,
      INSTANTE_ULTIMO_CAMBIO_PSCOLA,
      INSTANTE_ALTA,
      USUARIO_ALTA
    ) VALUES (
      v_clave,
      v_tienda,
      v_codigo_art,
      v_es_precio,
      v_es_stock,
      v_accion,
      1,
      CASE WHEN v_accion IN ('A', 'D')
        THEN 'PENDIENTE_VISIBILIDAD'
        WHEN v_es_precio = 'S' OR v_es_stock = 'S'
        THEN 'PENDIENTE' ELSE 'ENVIADA' END,
      0,
      NOW(),
      NOW(),
      v_usuario_auditoria
    )
    ON DUPLICATE KEY UPDATE
      ESCAMBIO_PRECIO_PSCOLA = VALUES(ESCAMBIO_PRECIO_PSCOLA),
      ESCAMBIO_STOCK_PSCOLA = VALUES(ESCAMBIO_STOCK_PSCOLA),
      ACCION_VISIBILIDAD_PSCOLA = VALUES(ACCION_VISIBILIDAD_PSCOLA),
      VERSION_DESEADA_PSCOLA = VERSION_DESEADA_PSCOLA + 1,
      CONTADOR_INTENTOS_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        CONTADOR_INTENTOS_PSCOLA, 0),
      INSTANTE_PROXIMO_INTENTO_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        INSTANTE_PROXIMO_INTENTO_PSCOLA, NULL),
      MENSAJE_ERROR_PSCOLA = IF(
        LEFT(COALESCE(MENSAJE_ERROR_PSCOLA, ''), 18) =
          '[ALTA_PRESTASHOP] ',
        MENSAJE_ERROR_PSCOLA, NULL),
      VERSION_RECLAMADA_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        VERSION_RECLAMADA_PSCOLA, NULL),
      ESCAMBIO_PRECIO_RECLAMADO_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ESCAMBIO_PRECIO_RECLAMADO_PSCOLA, 'N'),
      ESCAMBIO_STOCK_RECLAMADO_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ESCAMBIO_STOCK_RECLAMADO_PSCOLA, 'N'),
      ACCION_VISIBILIDAD_RECLAMADA_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ACCION_VISIBILIDAD_RECLAMADA_PSCOLA, 'N'),
      ID_RECLAMACION_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        ID_RECLAMACION_PSCOLA, NULL),
      INSTANTE_RECLAMACION_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        INSTANTE_RECLAMACION_PSCOLA, NULL),
      ESTADO_PSCOLA = IF(
        ESTADO_PSCOLA IN ('PROCESANDO', 'PROCESANDO_VISIBILIDAD'),
        IF(ESTADO_PSCOLA = 'PROCESANDO_VISIBILIDAD' OR
           VALUES(ACCION_VISIBILIDAD_PSCOLA) IN ('A', 'D'),
          'PROCESANDO_VISIBILIDAD', 'PROCESANDO'),
        CASE WHEN VALUES(ACCION_VISIBILIDAD_PSCOLA) IN ('A', 'D')
          THEN 'PENDIENTE_VISIBILIDAD'
          WHEN VALUES(ESCAMBIO_PRECIO_PSCOLA) = 'S' OR
               VALUES(ESCAMBIO_STOCK_PSCOLA) = 'S'
          THEN 'PENDIENTE' ELSE 'ENVIADA' END),
      INSTANTE_ULTIMO_CAMBIO_PSCOLA = NOW(),
      INSTANTE_MODIF = NOW(),
      USUARIO_MODIF = v_usuario_auditoria;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_RECLAMAR_RECUPERACION
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_RECLAMAR_RECUPERACION`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_RECLAMAR_RECUPERACION`(
  IN p_SEGUNDOS int,
  IN p_CLAVE_INSTALACION char(64),
  IN p_TIENDA int,
  IN p_USUARIO varchar(200),
  OUT p_RECLAMADA tinyint
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_segundos int DEFAULT 60;
  DECLARE v_proxima bigint unsigned DEFAULT 0;
  DECLARE v_usuario varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_clave char(64);
  DECLARE v_tienda int;
  DECLARE v_subclave varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RECLAMADA = 0;
    RESIGNAL;
  END;
  SET p_RECLAMADA = 0;
  SET v_segundos = LEAST(120, GREATEST(60, COALESCE(p_SEGUNDOS, 60)));
  SET v_clave = UPPER(TRIM(COALESCE(p_CLAVE_INSTALACION, '')));
  SET v_tienda = COALESCE(p_TIENDA, 0);
  IF v_clave = '' OR v_tienda <= 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
        'Destino PrestaShop incompleto para recuperar la cola';
  END IF;
  SET v_usuario = LEFT(COALESCE(NULLIF(TRIM(p_USUARIO), ''),
    'PRESTASHOP'), 100);
  SET v_subclave = CONCAT(
    'RECUPERACION_',
    UPPER(SHA2(CONCAT(v_clave, '|', v_tienda), 256)));
  START TRANSACTION;
  INSERT IGNORE INTO fza_usuarios_perfiles (
    USUARIO_GRUPO_USUPER,
    KEY_USUPER,
    SUBKEY_USUPER,
    VALUE_USUPER,
    INSTANTE_MODIF,
    INSTANTE_ALTA,
    USUARIO_ALTA,
    USUARIO_MODIF
  ) VALUES (
    'Todos',
    'dmPrestaShopCola',
    v_subclave,
    '0',
    NOW(),
    NOW(),
    v_usuario,
    v_usuario
  );
  SELECT CAST(COALESCE(NULLIF(P.VALUE_USUPER, ''), '0') AS unsigned)
    INTO v_proxima
    FROM fza_usuarios_perfiles P
   WHERE P.USUARIO_GRUPO_USUPER =
           'Todos' COLLATE utf8mb4_spanish_ci
     AND P.KEY_USUPER =
           'dmPrestaShopCola' COLLATE utf8mb4_spanish_ci
     AND P.SUBKEY_USUPER =
           v_subclave COLLATE utf8mb4_spanish_ci
   FOR UPDATE;
  IF v_proxima <= UNIX_TIMESTAMP() THEN
    UPDATE fza_usuarios_perfiles P
       SET P.VALUE_USUPER = CAST(UNIX_TIMESTAMP() + v_segundos AS char),
           P.INSTANTE_MODIF = NOW(),
           P.USUARIO_MODIF = v_usuario
     WHERE P.USUARIO_GRUPO_USUPER =
             'Todos' COLLATE utf8mb4_spanish_ci
       AND P.KEY_USUPER =
             'dmPrestaShopCola' COLLATE utf8mb4_spanish_ci
       AND P.SUBKEY_USUPER =
             v_subclave COLLATE utf8mb4_spanish_ci;
    SET p_RECLAMADA = 1;
  END IF;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_PRESTASHOP_RECONCILIAR
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_RECONCILIAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_RECONCILIAR`(
  IN p_HORAS int,
  IN p_CLAVE_INSTALACION char(64),
  IN p_ID_TIENDA int,
  IN p_CODIGO_EMPRESA varchar(20),
  IN p_CODIGO_TARIFA varchar(20),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200)
)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_horas int DEFAULT 24;
  DECLARE v_ultimo bigint unsigned DEFAULT 0;
  DECLARE v_usuario varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_empresa varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_tarifa varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE v_clave char(64);
  DECLARE v_tienda int;
  DECLARE v_es_stock varchar(1) DEFAULT 'N';
  DECLARE v_subclave varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  IF p_HORAS BETWEEN 1 AND 720 THEN
    SET v_horas = p_HORAS;
  END IF;
  SET v_clave = UPPER(TRIM(p_CLAVE_INSTALACION));
  SET v_tienda = p_ID_TIENDA;
  SET v_empresa = TRIM(COALESCE(p_CODIGO_EMPRESA, ''));
  SET v_tarifa = TRIM(COALESCE(p_CODIGO_TARIFA, ''));
  IF v_clave = '' OR v_tienda <= 0 OR
     v_empresa = '' OR v_tarifa = '' THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT =
        'Destino PrestaShop incompleto para el barrido';
  END IF;
  SET v_es_stock = IF(UPPER(TRIM(p_ES_STOCK)) = 'S', 'S', 'N');
  SET v_subclave = CONCAT(
    'ULTIMO_BARRIDO_',
    UPPER(SHA2(CONCAT(
      v_clave, '|', v_tienda, '|', v_empresa, '|', v_tarifa, '|',
      v_es_stock), 256)));
  SET v_usuario = LEFT(COALESCE(NULLIF(TRIM(p_USUARIO), ''),
    'PRESTASHOP'), 50);
  START TRANSACTION;
  INSERT IGNORE INTO fza_usuarios_perfiles (
    USUARIO_GRUPO_USUPER,
    KEY_USUPER,
    SUBKEY_USUPER,
    VALUE_USUPER,
    INSTANTE_MODIF,
    INSTANTE_ALTA,
    USUARIO_ALTA,
    USUARIO_MODIF
  ) VALUES (
    'Todos',
    'dmPrestaShopCola',
    v_subclave,
    '0',
    NOW(),
    NOW(),
    v_usuario,
    v_usuario
  );
  SELECT CAST(COALESCE(NULLIF(P.VALUE_USUPER, ''), '0') AS unsigned)
    INTO v_ultimo
     FROM fza_usuarios_perfiles P
    WHERE P.USUARIO_GRUPO_USUPER =
            'Todos' COLLATE utf8mb4_spanish_ci
      AND P.KEY_USUPER =
            'dmPrestaShopCola' COLLATE utf8mb4_spanish_ci
      AND P.SUBKEY_USUPER =
            v_subclave COLLATE utf8mb4_spanish_ci
   FOR UPDATE;
  IF v_ultimo <= UNIX_TIMESTAMP() - (v_horas * 3600) THEN
    UPDATE fza_usuarios_perfiles P
       SET P.VALUE_USUPER = CAST(UNIX_TIMESTAMP() AS char),
           P.INSTANTE_MODIF = NOW(),
           P.USUARIO_MODIF = v_usuario
      WHERE P.USUARIO_GRUPO_USUPER =
              'Todos' COLLATE utf8mb4_spanish_ci
        AND P.KEY_USUPER =
              'dmPrestaShopCola' COLLATE utf8mb4_spanish_ci
        AND P.SUBKEY_USUPER =
              v_subclave COLLATE utf8mb4_spanish_ci;
    CALL PRC_PRESTASHOP_ENCOLAR_TODOS_WEB_DESTINO(
      v_clave,
      v_tienda,
      'S',
      v_es_stock,
      v_usuario);
  END IF;
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REALIZAR_TRASPASO
DROP PROCEDURE IF EXISTS `PRC_REALIZAR_TRASPASO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REALIZAR_TRASPASO`(
    IN pUsuario VARCHAR(50),
    IN pEmpresa VARCHAR(20),
    IN pAlmacenOrigen VARCHAR(10),
    IN pAlmacenDestino VARCHAR(10),
    IN pSku VARCHAR(50),
    IN pCantidad DECIMAL(19,6))
SQL SECURITY INVOKER
BEGIN
    DECLARE vSerie VARCHAR(20) DEFAULT 'TRAS';
    DECLARE vNroDoc VARCHAR(20);

    /* Manejo de errores para asegurar la consistencia */
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    kk: BEGIN
        ROLLBACK;
        RESIGNAL;
    END kk;

    /* Generamos un número de documento único basado en la fecha y hora */
    SET vNroDoc = DATE_FORMAT(NOW(), '%Y%m%d%H%i%s');

    START TRANSACTION;

    /* 1. SALIDA DEL ORIGEN (Resta stock en Origen) */
    INSERT INTO `fza_movimientos_almacen` 
    (TIPO_DOC_MOV, SERIE_DOC_MOV, NUMERO_DOC_MOV, LINEA_MOV, CODIGO_EMP_MOV,
      CODIGO_ALM_MOV, CODIGO_ALM_CONTRA_MOV, FECHA_MOV,
      CODIGO_UNIDAD_MOV, TIPO_MOV, CANTIDAD_MOV,
      DESCRIPCION_ARTICULO_MOV, USUARIO_ALTA, USUARIO_MODIF)
    VALUES 
    ('TR', vSerie, vNroDoc, '001', pEmpresa,
      pAlmacenOrigen, pAlmacenDestino, NOW(),
      pSku, 'S', pCantidad,
      CONCAT('Traspaso a ', pAlmacenDestino), pUsuario, pUsuario);

    /* 2. ENTRADA EN DESTINO (Suma stock en Destino) */
    INSERT INTO `fza_movimientos_almacen` 
    (TIPO_DOC_MOV, SERIE_DOC_MOV, NUMERO_DOC_MOV, LINEA_MOV, CODIGO_EMP_MOV,
      CODIGO_ALM_MOV, CODIGO_ALM_CONTRA_MOV, FECHA_MOV,
      CODIGO_UNIDAD_MOV, TIPO_MOV, CANTIDAD_MOV,
      DESCRIPCION_ARTICULO_MOV, USUARIO_ALTA, USUARIO_MODIF,
     TIPO_DOC_REF_MOV, SERIE_DOC_REF_MOV, NUMERO_DOC_REF_MOV, LINEA_REF_MOV)
    VALUES 
    ('TR', vSerie, vNroDoc, '002', pEmpresa,
      pAlmacenDestino, pAlmacenOrigen, NOW(),
      pSku, 'E', pCantidad,
      CONCAT('Traspaso desde ', pAlmacenOrigen), pUsuario, pUsuario,
     'TR', vSerie, vNroDoc, '001');

    COMMIT;

    SELECT CONCAT('Traspaso realizado. Doc: ', vSerie, '-', vNroDoc) AS MENSAJE;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_RECALCULAR_STOCK
DROP PROCEDURE IF EXISTS `PRC_RECALCULAR_STOCK`;
DELIMITER ;;
CREATE PROCEDURE `PRC_RECALCULAR_STOCK`()
SQL SECURITY INVOKER
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  bloque_error: BEGIN
    ROLLBACK;
    SELECT 'ERROR: No se pudo recalcular el stock' AS MENSAJE;
  END bloque_error;
  START TRANSACTION;
  DELETE FROM fza_articulos_stockactual;
  INSERT INTO fza_articulos_stockactual (
    CODIGO_ALM_STK,
    CODIGO_UNIDAD_STK,
    CANTIDAD_STK,
    INSTANTE_MODIF
  )
  SELECT CODIGO_ALM_MOV,
         CODIGO_UNIDAD_MOV,
         SUM(IF(TIPO_MOV = 'E', CANTIDAD_MOV, -CANTIDAD_MOV)),
         NOW()
    FROM fza_movimientos_almacen
   WHERE ESACTIVO_MOV = 'S'
   GROUP BY CODIGO_ALM_MOV, CODIGO_UNIDAD_MOV;
  CALL PRC_PRESTASHOP_ENCOLAR_TODOS_WEB(
    'N', 'S', '');
  COMMIT;
  SELECT 'Stock recalculado correctamente.' AS MENSAJE;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REMC_ANYADIR_EFECTO
DROP PROCEDURE IF EXISTS `PRC_REMC_ANYADIR_EFECTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REMC_ANYADIR_EFECTO`(
    IN  p_SERIE_REM  varchar(20),
    IN  p_NUMERO_REM varchar(20),
    IN  p_SERIE_FAC  varchar(20),
    IN  p_NUMERO_FAC varchar(20),
    IN  p_NUM_EFEC   int,
    IN  p_USUARIO    varchar(100),
    OUT p_RESULTADO  int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_rem  int DEFAULT 0;
  DECLARE v_efe  int DEFAULT 0;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  SELECT COUNT(*) INTO v_rem
    FROM fza_remesas_compra
   WHERE SERIE_REMC = p_SERIE_REM AND NUMERO_REMC = p_NUMERO_REM;
  SELECT COUNT(*) INTO v_efe
    FROM fza_efectos_compra
   WHERE SERIE_FACC_EFEC  = p_SERIE_FAC
     AND NUMERO_FACC_EFEC = p_NUMERO_FAC
     AND NUMERO_EFEC      = p_NUM_EFEC
     AND SERIE_REMC_EFEC IS NULL
     AND COALESCE(ESTADO_EFEC, '') NOT IN
         ('PAGADO', 'ANULADO', 'CONCILIADO')
     AND COALESCE(IMPORTE_PENDIENTE_EFEC, 0) > 0;
  IF v_rem > 0 AND v_efe > 0 THEN
    START TRANSACTION;
    UPDATE fza_efectos_compra
       SET SERIE_REMC_EFEC  = p_SERIE_REM,
           NUMERO_REMC_EFEC = p_NUMERO_REM,
           ESTADO_EFEC      = 'REMESADO',
           USUARIO_MODIF    = p_USUARIO
     WHERE SERIE_FACC_EFEC  = p_SERIE_FAC
       AND NUMERO_FACC_EFEC = p_NUMERO_FAC
       AND NUMERO_EFEC      = p_NUM_EFEC;
    CALL PRC_REMC_RECALCULAR(p_SERIE_REM, p_NUMERO_REM);
    SET p_RESULTADO = 1;
    COMMIT;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REMC_CREAR
DROP PROCEDURE IF EXISTS `PRC_REMC_CREAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REMC_CREAR`(
    IN  p_EMPRESA varchar(8),
    IN  p_IBAN    varchar(34),
    IN  p_USUARIO varchar(100),
    OUT p_SERIE_OUT  varchar(20),
    OUT p_NUMERO_OUT varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_nro   bigint DEFAULT 0;
  DECLARE v_serie varchar(3);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
  CALL PRC_FNC_GET_NEXT_NRO_DOC('RP', v_nro);
  CALL PRC_FNC_GET_SERIE_TIPODOC('RP', v_serie);
  SET p_NUMERO_OUT = LPAD(v_nro, 6, '0');
  SET p_SERIE_OUT  = v_serie;
  INSERT INTO fza_remesas_compra
    (NUMERO_REMC, SERIE_REMC, FECHA_REMC, ESTADO_REMC, CODIGO_EMP_REMC,
     IBAN_REMC, CONTADOR_EFECTOS_REMC, TOTAL_REMC,
     INSTANTE_ALTA, USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF)
  VALUES
    (p_NUMERO_OUT, p_SERIE_OUT, CURDATE(), 'ABIERTA', p_EMPRESA,
     p_IBAN, 0, 0, NOW(), p_USUARIO, NOW(), p_USUARIO);
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REMC_RECALCULAR
DROP PROCEDURE IF EXISTS `PRC_REMC_RECALCULAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REMC_RECALCULAR`(
    IN p_SERIE  varchar(20),
    IN p_NUMERO varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_n     int DEFAULT 0;
  DECLARE v_total decimal(18,6) DEFAULT 0;
  SELECT COUNT(*), COALESCE(SUM(COALESCE(IMPORTE_EFEC, 0)), 0)
    INTO v_n, v_total
    FROM fza_efectos_compra
   WHERE SERIE_REMC_EFEC  = p_SERIE
     AND NUMERO_REMC_EFEC = p_NUMERO;
  UPDATE fza_remesas_compra
     SET CONTADOR_EFECTOS_REMC = v_n,
         TOTAL_REMC            = v_total
   WHERE SERIE_REMC = p_SERIE AND NUMERO_REMC = p_NUMERO;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REMV_ANYADIR_EFECTO
DROP PROCEDURE IF EXISTS `PRC_REMV_ANYADIR_EFECTO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REMV_ANYADIR_EFECTO`(
    IN p_SERIE_REM varchar(20),
    IN p_NUMERO_REM varchar(20),
    IN p_SERIE_FAC varchar(20),
    IN p_NUMERO_FAC varchar(20),
    IN p_NUM_EFV int,
    IN p_USUARIO varchar(100),
    OUT p_RESULTADO int)
SQL SECURITY INVOKER
BEGIN
  DECLARE v_rem int DEFAULT 0;
  DECLARE v_efe int DEFAULT 0;
  DECLARE v_iban varchar(34);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_RESULTADO = -1;
    RESIGNAL;
  END;
  SET p_RESULTADO = 0;
  SELECT COUNT(*), MAX(IBAN_REMV)
    INTO v_rem, v_iban
    FROM fza_remesas_venta
   WHERE SERIE_REMV = p_SERIE_REM
     AND NUMERO_REMV = p_NUMERO_REM;
  SELECT COUNT(*)
    INTO v_efe
    FROM fza_efectos_venta
   WHERE SERIE_FAC_EFV = p_SERIE_FAC
     AND NUMERO_FAC_EFV = p_NUMERO_FAC
     AND NUMERO_EFV = p_NUM_EFV
     AND SERIE_REMV_EFV IS NULL
     AND COALESCE(ESTADO_EFV, '') NOT IN
         ('COBRADO', 'ANULADO', 'CONCILIADO')
     AND COALESCE(IMPORTE_PENDIENTE_EFV, 0) > 0;
  IF v_rem > 0 AND v_efe > 0 THEN
    START TRANSACTION;
    UPDATE fza_efectos_venta
       SET SERIE_REMV_EFV = p_SERIE_REM,
           NUMERO_REMV_EFV = p_NUMERO_REM,
           ESTADO_EFV = 'REMESADO',
           IBAN_EMP_EFV = COALESCE(NULLIF(v_iban, ''), IBAN_EMP_EFV),
           INSTANTE_MODIF = NOW(),
           USUARIO_MODIF = p_USUARIO
     WHERE SERIE_FAC_EFV = p_SERIE_FAC
       AND NUMERO_FAC_EFV = p_NUMERO_FAC
       AND NUMERO_EFV = p_NUM_EFV;
    CALL PRC_REMV_RECALCULAR(p_SERIE_REM, p_NUMERO_REM);
    SET p_RESULTADO = 1;
    COMMIT;
  END IF;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REMV_CREAR
DROP PROCEDURE IF EXISTS `PRC_REMV_CREAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REMV_CREAR`(
    IN p_EMPRESA varchar(8),
    IN p_IBAN varchar(34),
    IN p_USUARIO varchar(100),
    OUT p_SERIE_OUT varchar(20),
    OUT p_NUMERO_OUT varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_nro bigint DEFAULT 0;
  DECLARE v_serie varchar(3);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;
  START TRANSACTION;
  CALL PRC_FNC_GET_NEXT_NRO_DOC('RC', v_nro);
  CALL PRC_FNC_GET_SERIE_TIPODOC('RC', v_serie);
  SET p_NUMERO_OUT = LPAD(v_nro, 6, '0');
  SET p_SERIE_OUT = v_serie;
  INSERT INTO fza_remesas_venta
    (NUMERO_REMV, SERIE_REMV, FECHA_REMV, ESTADO_REMV, CODIGO_EMP_REMV,
     IBAN_REMV, CONTADOR_EFECTOS_REMV, TOTAL_REMV,
     INSTANTE_ALTA, USUARIO_ALTA, INSTANTE_MODIF, USUARIO_MODIF)
  VALUES
    (p_NUMERO_OUT, p_SERIE_OUT, CURDATE(), 'ABIERTA', p_EMPRESA,
     p_IBAN, 0, 0, NOW(), p_USUARIO, NOW(), p_USUARIO);
  COMMIT;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_REMV_RECALCULAR
DROP PROCEDURE IF EXISTS `PRC_REMV_RECALCULAR`;
DELIMITER ;;
CREATE PROCEDURE `PRC_REMV_RECALCULAR`(
    IN p_SERIE varchar(20),
    IN p_NUMERO varchar(20))
SQL SECURITY INVOKER
BEGIN
  DECLARE v_n int DEFAULT 0;
  DECLARE v_total decimal(18,6) DEFAULT 0;
  SELECT COUNT(*), COALESCE(SUM(COALESCE(IMPORTE_EFV, 0)), 0)
    INTO v_n, v_total
    FROM fza_efectos_venta
   WHERE SERIE_REMV_EFV = p_SERIE
     AND NUMERO_REMV_EFV = p_NUMERO;
  UPDATE fza_remesas_venta
     SET CONTADOR_EFECTOS_REMV = v_n,
         TOTAL_REMV = v_total,
         INSTANTE_MODIF = NOW()
   WHERE SERIE_REMV = p_SERIE
     AND NUMERO_REMV = p_NUMERO;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_SETPERFILFORMULARIO
DROP PROCEDURE IF EXISTS `PRC_SETPERFILFORMULARIO`;
DELIMITER ;;
CREATE PROCEDURE `PRC_SETPERFILFORMULARIO`(IN p_usuario_grupo  VARCHAR(200),
    IN p_formulario     VARCHAR(100),
    IN p_subkey         VARCHAR(100),
    IN p_value          VARCHAR(200))
SQL SECURITY INVOKER
BEGIN
    INSERT INTO fza_usuarios_perfiles 
        (USUARIO_GRUPO_USUPER, KEY_USUPER, SUBKEY_USUPER, 
         VALUE_USUPER, INSTANTE_MODIF, INSTANTE_ALTA, USUARIO_MODIF, USUARIO_ALTA)
    VALUES 
        (p_usuario_grupo, p_formulario, p_subkey, 
         p_value, NOW(), NOW(), p_usuario_grupo, p_usuario_grupo)
    ON DUPLICATE KEY UPDATE
        VALUE_USUPER  = p_value,
        INSTANTE_MODIF   = NOW(),
        USUARIO_MODIF    = p_usuario_grupo;
END ;;
DELIMITER ;

-- Procedimiento ausente: PRC_TMP_LIMPIAR_MOV_FAC_DUP
DROP PROCEDURE IF EXISTS `PRC_TMP_LIMPIAR_MOV_FAC_DUP`;
DELIMITER ;;
CREATE PROCEDURE `PRC_TMP_LIMPIAR_MOV_FAC_DUP`()
SQL SECURITY INVOKER
BEGIN
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_num VARCHAR(20);
    DECLARE cur CURSOR FOR
        SELECT m.NUMERO_MOV
          FROM fza_movimientos_almacen m
         WHERE m.TIPO_DOC_MOV = 'FC'
           AND m.TIPO_MOV = 'S'
           AND (EXISTS (SELECT 1 FROM fza_movimientos_almacen v
                         WHERE v.TIPO_DOC_MOV = 'VE'
                           AND v.TIPO_MOV = 'S'
                           AND v.SERIE_DOC_MOV     = m.SERIE_DOC_MOV
                           AND v.NUMERO_DOC_MOV    = m.NUMERO_DOC_MOV
                           AND v.LINEA_MOV         = m.LINEA_MOV
                           AND v.CODIGO_UNIDAD_MOV =
                               m.CODIGO_UNIDAD_MOV)
                OR m.NUMERO_MOV >
                   (SELECT MIN(f.NUMERO_MOV)
                      FROM fza_movimientos_almacen f
                     WHERE f.TIPO_DOC_MOV = 'FC'
                       AND f.TIPO_MOV = 'S'
                       AND f.SERIE_DOC_MOV     = m.SERIE_DOC_MOV
                       AND f.NUMERO_DOC_MOV    = m.NUMERO_DOC_MOV
                       AND f.LINEA_MOV         = m.LINEA_MOV
                       AND f.CODIGO_UNIDAD_MOV =
                           m.CODIGO_UNIDAD_MOV));
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    OPEN cur;
    bucle: LOOP
        FETCH cur INTO v_num;
        IF v_done THEN
            LEAVE bucle;
        END IF;
        CALL PRC_FZA_MOVIMIENTOS_ALMACEN_DELETE(v_num);
    END LOOP;
    CLOSE cur;
END ;;
DELIMITER ;

-- Procedimiento ausente: pr_demo_silenciosa
DROP PROCEDURE IF EXISTS `pr_demo_silenciosa`;
DELIMITER ;;
CREATE PROCEDURE `pr_demo_silenciosa`()
SQL SECURITY INVOKER
BEGIN
    SELECT 'Esta es una prueba exitosa' AS mensaje;
END ;;
DELIMITER ;

-- Procedimiento ausente: SP_RECALCULAR_PMP_LOTE_ALMACEN
DROP PROCEDURE IF EXISTS `SP_RECALCULAR_PMP_LOTE_ALMACEN`;
DELIMITER ;;
CREATE PROCEDURE `SP_RECALCULAR_PMP_LOTE_ALMACEN`(
  IN p_EMPRESA varchar(20),
  IN p_ALMACEN varchar(10)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  INSERT INTO tmp_movimientos_recalculo
    (empresa, almacen, sku, instante_desde)
  SELECT p_EMPRESA, p_ALMACEN, sku, '1000-01-01 00:00:00'
    FROM tmp_skus_recalc;
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

-- Procedimiento ausente: SP_RECALCULAR_PMP_SKU
DROP PROCEDURE IF EXISTS `SP_RECALCULAR_PMP_SKU`;
DELIMITER ;;
CREATE PROCEDURE `SP_RECALCULAR_PMP_SKU`(IN `p_CodigoEmpresa` VARCHAR(20),
    IN `p_CodigoSKU` VARCHAR(50),
    IN `p_FechaDesde` DATETIME)
SQL SECURITY INVOKER
BEGIN
    /* Variables para el bucle */
    DECLARE done INT DEFAULT FALSE;
    DECLARE vIdTipo VARCHAR(5);
    DECLARE vIdSerie VARCHAR(20);
    DECLARE vIdNro VARCHAR(20);
    DECLARE vIdLinea VARCHAR(4);
    
    DECLARE vTipoMov VARCHAR(1);
    DECLARE vCantidad DECIMAL(19,6);
    DECLARE vPrecioCoste DECIMAL(19,6);
    
    /* Variables para el cálculo acumulado */
    DECLARE vStockAcumulado DECIMAL(19,6) DEFAULT 0;
    DECLARE vPMP_Actual DECIMAL(19,6) DEFAULT 0;
    
    /* CURSOR: Seleccionamos TODOS los movimientos de ese SKU ordenados cronológicamente */
    /* Es vital incluir movimientos ANTERIORES a la fecha para coger el saldo inicial correcto */
    DECLARE curMovimientos CURSOR FOR 
        SELECT 
            TIPO_DOC_MOV, SERIE_DOC_MOV, NUMERO_DOC_MOV, LINEA_MOV,
            TIPO_MOV, CANTIDAD_MOV, PRECIO_COSTE_UNITARIO_MOV, FECHA_MOV
        FROM fza_movimientos_almacen
        WHERE CODIGO_EMP_MOV = p_CodigoEmpresa
          AND CODIGO_UNIDAD_MOV = p_CodigoSKU
        ORDER BY FECHA_MOV ASC, INSTANTE_ALTA ASC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    /* 1. Inicialización: Limpiamos variables */
    SET vStockAcumulado = 0;
    SET vPMP_Actual = 0;

    OPEN curMovimientos;

    read_loop: LOOP
        FETCH curMovimientos INTO vIdTipo, vIdSerie, vIdNro, vIdLinea, vTipoMov, vCantidad, vPrecioCoste, p_FechaDesde; /* Reusamos p_FechaDesde solo para leer fecha, no afecta lógica */
        IF done THEN
            LEAVE read_loop;
        END IF;

        /* --------------------------------------------------------- */
        /* LÓGICA DE CÁLCULO (Idéntica a la del Trigger, pero en bucle) */
        /* --------------------------------------------------------- */
        
        IF vTipoMov = 'E' THEN
            /* Es ENTRADA */
            /* Si el stock venía de negativo o cero, reiniciamos precio */
            IF vStockAcumulado <= 0 THEN
                SET vPMP_Actual = vPrecioCoste;
            ELSE
                /* Fórmula PMP */
                SET vPMP_Actual = (
                    (vStockAcumulado * vPMP_Actual) + (vCantidad * vPrecioCoste)
                ) / (vStockAcumulado + vCantidad);
            END IF;
            
            /* Actualizamos el Stock Acumulado sumando */
            SET vStockAcumulado = vStockAcumulado + vCantidad;
            
        ELSE
            /* Es SALIDA */
            /* El PMP no cambia, se mantiene el que traíamos */
            /* Pero el stock baja */
            SET vStockAcumulado = vStockAcumulado - vCantidad;
        END IF;

        /* --------------------------------------------------------- */
        /* ACTUALIZACIÓN DE LA FILA */
        /* --------------------------------------------------------- */
        /* Actualizamos el campo PRECIO_MEDIO_MOV de esta fila específica */
        /* Nota: Esto disparará el Trigger UPDATE. Para evitar bucles, */
        /* el trigger UPDATE debería detectar si el valor ya es igual para no hacer nada, */
        /* o deshabilitar triggers temporalmente si fuera necesario. */
        
        UPDATE fza_movimientos_almacen 
        SET PRECIO_MEDIO_MOV = vPMP_Actual
        WHERE TIPO_DOC_MOV = vIdTipo 
          AND SERIE_DOC_MOV = vIdSerie
          AND NUMERO_DOC_MOV = vIdNro
          AND LINEA_MOV = vIdLinea;
          
    END LOOP;

    CLOSE curMovimientos;
END ;;
DELIMITER ;

-- Procedimiento ausente: SP_RECALCULAR_PMP_SKU_ALMACEN
DROP PROCEDURE IF EXISTS `SP_RECALCULAR_PMP_SKU_ALMACEN`;
DELIMITER ;;
CREATE PROCEDURE `SP_RECALCULAR_PMP_SKU_ALMACEN`(
  IN p_EMPRESA varchar(20),
  IN p_SKU varchar(50),
  IN p_ALMACEN varchar(10)
)
SQL SECURITY INVOKER
BEGIN
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_PREPARAR();
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_MARCAR(
    p_EMPRESA, p_ALMACEN, p_SKU, '1000-01-01 00:00:00');
  CALL PRC_FZA_MOVIMIENTOS_RECALCULO_EJECUTAR();
END ;;
DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;
