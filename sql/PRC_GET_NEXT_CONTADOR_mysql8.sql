-- ============================================================================
-- PRC_GET_NEXT_CONTADOR compatible con MySQL 8 (y MariaDB).
--
-- La versión de viracash_original.sql usa la variable @@in_transaction, que
-- solo existe en MariaDB: en MySQL 8 el CREATE PROCEDURE falla y la carga del
-- volcado se detiene ahí, dejando sin contador a PRC_GET_NEXT_CONT (códigos
-- de clientes, empresas, artículos...).
--
-- Esta versión reserva el número con la técnica atómica LAST_INSERT_ID(expr),
-- la misma que ya usa PRC_GET_NEXT_CONT_FACT_SERIE, por lo que no necesita
-- abrir ni detectar transacciones y devuelve exactamente lo mismo que la
-- original: el valor actual del contador (mínimo 1) y deja guardado el
-- siguiente.
--
-- Idempotente: se puede ejecutar tantas veces como haga falta.
-- Ejecutar sobre la base de datos de la web (viracashphp) con un cliente
-- que admita DELIMITER (phpMyAdmin, HeidiSQL, mysql).
-- ============================================================================

DROP PROCEDURE IF EXISTS PRC_GET_NEXT_CONTADOR;

DELIMITER $$

CREATE PROCEDURE PRC_GET_NEXT_CONTADOR(
  IN pTipoDoc varchar(2),
  IN pEmpresa varchar(10),
  IN pSerie varchar(12),
  IN pUsuario varchar(100),
  OUT pContador varchar(20)
)
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
END$$

DELIMITER ;
