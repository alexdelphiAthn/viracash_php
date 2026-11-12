-- Reversion de alinear_estructura_remoto.sql: deja la estructura como estaba en
-- la copia del remoto del 11/09/2026 06:03 (viracash_mysqllinux.sql).
-- ATENCION: borra las tablas y columnas nuevas con los datos que contengan, y
-- la clave primaria de fza_articulos_fotos vuelve a (CODIGO_ART_FOT,
-- CODIGO_UNIDAD_FOT): fallara si hay varias fotos por unidad (ORDEN_FOT > 1).
-- Generado el 2026-09-11 13:54. Idempotente. Revisar antes de ejecutar.

SET NAMES utf8mb4 COLLATE utf8mb4_spanish_ci;

-- ---------------------------------------------------------------------
-- 0. Indices anadidos en tablas que ya existian
-- ---------------------------------------------------------------------
-- Indice fza_albaranes.IDX_ALB_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_albaranes' AND INDEX_NAME = 'IDX_ALB_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_albaranes` DROP INDEX `IDX_ALB_EMP_INSTANTE`',
  'SELECT "fza_albaranes.IDX_ALB_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_albaranes_compra.IDX_ALBC_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_albaranes_compra' AND INDEX_NAME = 'IDX_ALBC_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_albaranes_compra` DROP INDEX `IDX_ALBC_EMP_INSTANTE`',
  'SELECT "fza_albaranes_compra.IDX_ALBC_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_articulos.CODIGO
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos' AND INDEX_NAME = 'CODIGO') > 0,
  'ALTER TABLE `fza_articulos` DROP INDEX `CODIGO`',
  'SELECT "fza_articulos.CODIGO no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_articulos.IDX_ARTICULOS_FAMILIA
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos' AND INDEX_NAME = 'IDX_ARTICULOS_FAMILIA') > 0,
  'ALTER TABLE `fza_articulos` DROP INDEX `IDX_ARTICULOS_FAMILIA`',
  'SELECT "fza_articulos.IDX_ARTICULOS_FAMILIA no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_articulos.IDX_ARTICULOS_FAMILIA_STAT
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos' AND INDEX_NAME = 'IDX_ARTICULOS_FAMILIA_STAT') > 0,
  'ALTER TABLE `fza_articulos` DROP INDEX `IDX_ARTICULOS_FAMILIA_STAT`',
  'SELECT "fza_articulos.IDX_ARTICULOS_FAMILIA_STAT no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_articulos.IDX_ART_ESWEB
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos' AND INDEX_NAME = 'IDX_ART_ESWEB') > 0,
  'ALTER TABLE `fza_articulos` DROP INDEX `IDX_ART_ESWEB`',
  'SELECT "fza_articulos.IDX_ART_ESWEB no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_articulos.TIPO_VARIACION_ART
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos' AND INDEX_NAME = 'TIPO_VARIACION_ART') > 0,
  'ALTER TABLE `fza_articulos` DROP INDEX `TIPO_VARIACION_ART`',
  'SELECT "fza_articulos.TIPO_VARIACION_ART no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_caja_operaciones.IDX_OPCAJA_EMP_ALM_TIPO_FECHA
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_caja_operaciones' AND INDEX_NAME = 'IDX_OPCAJA_EMP_ALM_TIPO_FECHA') > 0,
  'ALTER TABLE `fza_caja_operaciones` DROP INDEX `IDX_OPCAJA_EMP_ALM_TIPO_FECHA`',
  'SELECT "fza_caja_operaciones.IDX_OPCAJA_EMP_ALM_TIPO_FECHA no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_caja_operaciones.IDX_OPCAJA_EMP_TIPO_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_caja_operaciones' AND INDEX_NAME = 'IDX_OPCAJA_EMP_TIPO_INSTANTE') > 0,
  'ALTER TABLE `fza_caja_operaciones` DROP INDEX `IDX_OPCAJA_EMP_TIPO_INSTANTE`',
  'SELECT "fza_caja_operaciones.IDX_OPCAJA_EMP_TIPO_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_compras_sesiones.IDX_SES_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_compras_sesiones' AND INDEX_NAME = 'IDX_SES_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_compras_sesiones` DROP INDEX `IDX_SES_EMP_INSTANTE`',
  'SELECT "fza_compras_sesiones.IDX_SES_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_devoluciones_compra.IDX_DEVC_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_devoluciones_compra' AND INDEX_NAME = 'IDX_DEVC_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_devoluciones_compra` DROP INDEX `IDX_DEVC_EMP_INSTANTE`',
  'SELECT "fza_devoluciones_compra.IDX_DEVC_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_documentos_trabajo_lineas.UQ_DTL_DTR_ORIGEN
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_documentos_trabajo_lineas' AND INDEX_NAME = 'UQ_DTL_DTR_ORIGEN') > 0,
  'ALTER TABLE `fza_documentos_trabajo_lineas` DROP INDEX `UQ_DTL_DTR_ORIGEN`',
  'SELECT "fza_documentos_trabajo_lineas.UQ_DTL_DTR_ORIGEN no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_facturas.IDX_FAC_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_facturas' AND INDEX_NAME = 'IDX_FAC_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_facturas` DROP INDEX `IDX_FAC_EMP_INSTANTE`',
  'SELECT "fza_facturas.IDX_FAC_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_facturas_compra.IDX_FACC_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_facturas_compra' AND INDEX_NAME = 'IDX_FACC_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_facturas_compra` DROP INDEX `IDX_FACC_EMP_INSTANTE`',
  'SELECT "fza_facturas_compra.IDX_FACC_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_inventarios.IDX_INV_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_inventarios' AND INDEX_NAME = 'IDX_INV_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_inventarios` DROP INDEX `IDX_INV_EMP_INSTANTE`',
  'SELECT "fza_inventarios.IDX_INV_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_movimientos_almacen.IDX_MOV_ALM_UNIDAD_ACTIVO_FECHA
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_movimientos_almacen' AND INDEX_NAME = 'IDX_MOV_ALM_UNIDAD_ACTIVO_FECHA') > 0,
  'ALTER TABLE `fza_movimientos_almacen` DROP INDEX `IDX_MOV_ALM_UNIDAD_ACTIVO_FECHA`',
  'SELECT "fza_movimientos_almacen.IDX_MOV_ALM_UNIDAD_ACTIVO_FECHA no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_movimientos_almacen.IDX_MOV_SERIE_DOC_NUMERO_DOC_TIPO_DOC_LINEA
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_movimientos_almacen' AND INDEX_NAME = 'IDX_MOV_SERIE_DOC_NUMERO_DOC_TIPO_DOC_LINEA') > 0,
  'ALTER TABLE `fza_movimientos_almacen` DROP INDEX `IDX_MOV_SERIE_DOC_NUMERO_DOC_TIPO_DOC_LINEA`',
  'SELECT "fza_movimientos_almacen.IDX_MOV_SERIE_DOC_NUMERO_DOC_TIPO_DOC_LINEA no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_pedidos.IDX_PED_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_pedidos' AND INDEX_NAME = 'IDX_PED_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_pedidos` DROP INDEX `IDX_PED_EMP_INSTANTE`',
  'SELECT "fza_pedidos.IDX_PED_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_pedidos_compra.IDX_PEDC_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_pedidos_compra' AND INDEX_NAME = 'IDX_PEDC_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_pedidos_compra` DROP INDEX `IDX_PEDC_EMP_INSTANTE`',
  'SELECT "fza_pedidos_compra.IDX_PEDC_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_tarifas_cambios.IDX_TARC_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_tarifas_cambios' AND INDEX_NAME = 'IDX_TARC_INSTANTE') > 0,
  'ALTER TABLE `fza_tarifas_cambios` DROP INDEX `IDX_TARC_INSTANTE`',
  'SELECT "fza_tarifas_cambios.IDX_TARC_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_traspasos_solicitudes.IDX_TRSOL_EMP_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes' AND INDEX_NAME = 'IDX_TRSOL_EMP_INSTANTE') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes` DROP INDEX `IDX_TRSOL_EMP_INSTANTE`',
  'SELECT "fza_traspasos_solicitudes.IDX_TRSOL_EMP_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Indice fza_traspasos_solicitudes.IDX_TRSOL_TIPO_INSTANTE
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes' AND INDEX_NAME = 'IDX_TRSOL_TIPO_INSTANTE') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes` DROP INDEX `IDX_TRSOL_TIPO_INSTANTE`',
  'SELECT "fza_traspasos_solicitudes.IDX_TRSOL_TIPO_INSTANTE no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;


-- ---------------------------------------------------------------------
-- 1. Claves primarias como estaban
-- ---------------------------------------------------------------------
-- fza_articulos_fotos
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos_fotos' AND INDEX_NAME = 'PRIMARY' AND COLUMN_NAME = 'ORDEN_FOT' AND SEQ_IN_INDEX = 3) > 0,
  'ALTER TABLE `fza_articulos_fotos` DROP PRIMARY KEY, ADD PRIMARY KEY (`CODIGO_ART_FOT`,`CODIGO_UNIDAD_FOT`)',
  'SELECT "fza_articulos_fotos: clave primaria ya sin ORDEN_FOT"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- fza_contadores
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_contadores' AND INDEX_NAME = 'PRIMARY' AND COLUMN_NAME = 'SERIE_CON' AND SEQ_IN_INDEX = 2) = 0,
  'ALTER TABLE `fza_contadores` DROP PRIMARY KEY, ADD PRIMARY KEY (`TIPO_DOC_CON`,`SERIE_CON`,`EMPRESA_CON`)',
  'SELECT "fza_contadores: clave primaria ya en el orden anterior"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ---------------------------------------------------------------------
-- 2. Columnas modificadas: definicion anterior del remoto
-- ---------------------------------------------------------------------
ALTER TABLE `fza_traspasos_solicitudes` MODIFY COLUMN `FECHA_TRSOL` date NULL DEFAULT NULL;
ALTER TABLE `fza_traspasos_solicitudes` MODIFY COLUMN `ESTADO_TRSOL` varchar(20) NOT NULL DEFAULT 'PENDIENTE' COMMENT 'PENDIENTE, PARCIAL, ATENDIDA, RECHAZADA, CANCELADA';

-- ---------------------------------------------------------------------
-- 3. Columnas anadidas (se pierde su contenido)
-- ---------------------------------------------------------------------
-- Columna fza_articulos_fotos.ORDEN_FOT
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_articulos_fotos' AND COLUMN_NAME = 'ORDEN_FOT') > 0,
  'ALTER TABLE `fza_articulos_fotos` DROP COLUMN `ORDEN_FOT`',
  'SELECT "fza_articulos_fotos.ORDEN_FOT no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_compras_sesiones.ESCOPIAR_DESCRIPCION_FAM_SES
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_compras_sesiones' AND COLUMN_NAME = 'ESCOPIAR_DESCRIPCION_FAM_SES') > 0,
  'ALTER TABLE `fza_compras_sesiones` DROP COLUMN `ESCOPIAR_DESCRIPCION_FAM_SES`',
  'SELECT "fza_compras_sesiones.ESCOPIAR_DESCRIPCION_FAM_SES no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_documentos_trabajo_lineas.CODIGO_EMP_ORIGEN_DTL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_documentos_trabajo_lineas' AND COLUMN_NAME = 'CODIGO_EMP_ORIGEN_DTL') > 0,
  'ALTER TABLE `fza_documentos_trabajo_lineas` DROP COLUMN `CODIGO_EMP_ORIGEN_DTL`',
  'SELECT "fza_documentos_trabajo_lineas.CODIGO_EMP_ORIGEN_DTL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_documentos_trabajo_lineas.TIPO_DOCUMENTO_ORIGEN_DTL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_documentos_trabajo_lineas' AND COLUMN_NAME = 'TIPO_DOCUMENTO_ORIGEN_DTL') > 0,
  'ALTER TABLE `fza_documentos_trabajo_lineas` DROP COLUMN `TIPO_DOCUMENTO_ORIGEN_DTL`',
  'SELECT "fza_documentos_trabajo_lineas.TIPO_DOCUMENTO_ORIGEN_DTL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_documentos_trabajo_lineas.SERIE_DOCUMENTO_ORIGEN_DTL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_documentos_trabajo_lineas' AND COLUMN_NAME = 'SERIE_DOCUMENTO_ORIGEN_DTL') > 0,
  'ALTER TABLE `fza_documentos_trabajo_lineas` DROP COLUMN `SERIE_DOCUMENTO_ORIGEN_DTL`',
  'SELECT "fza_documentos_trabajo_lineas.SERIE_DOCUMENTO_ORIGEN_DTL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_documentos_trabajo_lineas.NUMERO_DOCUMENTO_ORIGEN_DTL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_documentos_trabajo_lineas' AND COLUMN_NAME = 'NUMERO_DOCUMENTO_ORIGEN_DTL') > 0,
  'ALTER TABLE `fza_documentos_trabajo_lineas` DROP COLUMN `NUMERO_DOCUMENTO_ORIGEN_DTL`',
  'SELECT "fza_documentos_trabajo_lineas.NUMERO_DOCUMENTO_ORIGEN_DTL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_documentos_trabajo_lineas.LINEA_DOCUMENTO_ORIGEN_DTL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_documentos_trabajo_lineas' AND COLUMN_NAME = 'LINEA_DOCUMENTO_ORIGEN_DTL') > 0,
  'ALTER TABLE `fza_documentos_trabajo_lineas` DROP COLUMN `LINEA_DOCUMENTO_ORIGEN_DTL`',
  'SELECT "fza_documentos_trabajo_lineas.LINEA_DOCUMENTO_ORIGEN_DTL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_inventarios_recuentos.INSTANTE_RECUENTO_UTC_INVREC
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_inventarios_recuentos' AND COLUMN_NAME = 'INSTANTE_RECUENTO_UTC_INVREC') > 0,
  'ALTER TABLE `fza_inventarios_recuentos` DROP COLUMN `INSTANTE_RECUENTO_UTC_INVREC`',
  'SELECT "fza_inventarios_recuentos.INSTANTE_RECUENTO_UTC_INVREC no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_traspasos_solicitudes.TIPO_TRSOL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes' AND COLUMN_NAME = 'TIPO_TRSOL') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes` DROP COLUMN `TIPO_TRSOL`',
  'SELECT "fza_traspasos_solicitudes.TIPO_TRSOL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_traspasos_solicitudes.INSTANTE_VENTAS_DESDE_TRSOL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes' AND COLUMN_NAME = 'INSTANTE_VENTAS_DESDE_TRSOL') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes` DROP COLUMN `INSTANTE_VENTAS_DESDE_TRSOL`',
  'SELECT "fza_traspasos_solicitudes.INSTANTE_VENTAS_DESDE_TRSOL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_traspasos_solicitudes.INSTANTE_VENTAS_HASTA_TRSOL
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes' AND COLUMN_NAME = 'INSTANTE_VENTAS_HASTA_TRSOL') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes` DROP COLUMN `INSTANTE_VENTAS_HASTA_TRSOL`',
  'SELECT "fza_traspasos_solicitudes.INSTANTE_VENTAS_HASTA_TRSOL no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_traspasos_solicitudes_lineas.CODIGO_PRV_TRSOLLIN
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes_lineas' AND COLUMN_NAME = 'CODIGO_PRV_TRSOLLIN') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes_lineas` DROP COLUMN `CODIGO_PRV_TRSOLLIN`',
  'SELECT "fza_traspasos_solicitudes_lineas.CODIGO_PRV_TRSOLLIN no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- Columna fza_traspasos_solicitudes_lineas.RAZON_SOCIAL_PRV_TRSOLLIN
SET @sql := IF((SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_traspasos_solicitudes_lineas' AND COLUMN_NAME = 'RAZON_SOCIAL_PRV_TRSOLLIN') > 0,
  'ALTER TABLE `fza_traspasos_solicitudes_lineas` DROP COLUMN `RAZON_SOCIAL_PRV_TRSOLLIN`',
  'SELECT "fza_traspasos_solicitudes_lineas.RAZON_SOCIAL_PRV_TRSOLLIN no existe"');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

-- ---------------------------------------------------------------------
-- 4. Tablas nuevas (se pierden sus datos)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS `fza_movimientos_recalculos_pendientes`;
DROP TABLE IF EXISTS `fza_prestashop_cola_eventos`;
DROP TABLE IF EXISTS `fza_tarifas_descuento_condiciones`;
DROP TABLE IF EXISTS `fza_tarifas_descuento_valores`;
DROP TABLE IF EXISTS `fza_ventas_ws_cola_intentos`;
