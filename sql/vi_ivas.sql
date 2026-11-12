-- Recrea la vista vi_ivas (fza_ivas + fza_ivas_grupos), idéntica a la del
-- volcado de ViraCash. Idempotente. Después, "SELECT * FROM vi_ivas" debe
-- devolver una fila por cada fila de fza_ivas cuyo grupo exista en
-- fza_ivas_grupos.
CREATE OR REPLACE ALGORITHM = UNDEFINED VIEW `vi_ivas` AS
SELECT `fza_ivas`.`CODIGO_IVA` AS `CODIGO_IVA`,
       `fza_ivas`.`IVA_IVAGRP` AS `IVA_IVAGRP`,
       `fza_ivas`.`DESCRIPCION_IVA_IVAGRP` AS `DESCRIPCION_IVA_IVAGRP`,
       `fza_ivas`.`PORCENTAJE_EXENTO_IVA` AS `PORCENTAJE_EXENTO_IVA`,
       `fza_ivas`.`PORCENTAJE_EXENTO_RE_IVA` AS `PORCENTAJE_EXENTO_RE_IVA`,
       `fza_ivas`.`PORCENTAJE_NORMAL_IVA` AS `PORCENTAJE_NORMAL_IVA`,
       `fza_ivas`.`PORCENTAJE_NORMAL_RE_IVA` AS `PORCENTAJE_NORMAL_RE_IVA`,
       `fza_ivas`.`PORCENTAJE_REDUCIDO_IVA` AS `PORCENTAJE_REDUCIDO_IVA`,
       `fza_ivas`.`PORCENTAJE_REDUCIDO_RE_IVA` AS `PORCENTAJE_REDUCIDO_RE_IVA`,
       `fza_ivas`.`PORCENTAJE_SUPERREDUCIDO_IVA` AS `PORCENTAJE_SUPERREDUCIDO_IVA`,
       `fza_ivas`.`PORCENTAJE_SUPERREDUCIDO_RE_IVA` AS `PORCENTAJE_SUPERREDUCIDO_RE_IVA`,
       `fza_ivas`.`FECHA_DESDE_IVA` AS `FECHA_DESDE_IVA`,
       `fza_ivas`.`FECHA_HASTA_IVA` AS `FECHA_HASTA_IVA`,
       `fza_ivas`.`INSTANTE_MODIF` AS `INSTANTE_MODIF`,
       `fza_ivas`.`INSTANTE_ALTA` AS `INSTANTE_ALTA`,
       `fza_ivas`.`USUARIO_ALTA` AS `USUARIO_ALTA`,
       `fza_ivas`.`USUARIO_MODIF` AS `USUARIO_MODIF`,
       `fza_ivas_grupos`.`ESAPLICA_RE_IVA_IVAGRP` AS `ESAPLICA_RE_IVA_IVAGRP`,
       `fza_ivas_grupos`.`ESIVAAGRICOLA_IVA_IVAGRP` AS `ESIVAAGRICOLA_IVA_IVAGRP`,
       `fza_ivas_grupos`.`ESDEFAULT_IVA_IVAGRP` AS `ESDEFAULT_IVA_IVAGRP`,
       `fza_ivas_grupos`.`ESIRPF_IMP_INCL_IVA_IVAGRP` AS `ESIRPF_IMP_INCL_IVA_IVAGRP`,
       `fza_ivas_grupos`.`PALABRA_REPORTS_IVA_IVAGRP` AS `PALABRA_REPORTS_IVA_IVAGRP`
  FROM `fza_ivas`
  JOIN `fza_ivas_grupos` ON `fza_ivas`.`IVA_IVAGRP` = `fza_ivas_grupos`.`IVA_IVAGRP`;

SELECT IVA_IVAGRP, PORCENTAJE_NORMAL_IVA, FECHA_DESDE_IVA, FECHA_HASTA_IVA FROM vi_ivas;
