SET NAMES utf8mb4 COLLATE utf8mb4_spanish_ci;
SET SESSION sql_mode = 'NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION';
SET FOREIGN_KEY_CHECKS = 0;

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

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_TEMP
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_TEMP`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_TEMP`(
  IN p_ES_PRECIO varchar(1),
  IN p_ES_STOCK varchar(1),
  IN p_USUARIO varchar(200),
  IN p_CODIGO_ALM_EVENTO varchar(10)
)
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

-- Procedimiento ausente: PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD
DROP PROCEDURE IF EXISTS `PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD`;
DELIMITER ;;
CREATE PROCEDURE `PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD`(
  IN p_CODIGO_ART varchar(20),
  IN p_ACCION varchar(1),
  IN p_USUARIO varchar(200)
)
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

SET FOREIGN_KEY_CHECKS = 1;
