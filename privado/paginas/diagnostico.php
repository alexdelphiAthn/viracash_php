<?php
declare(strict_types=1);

/*
 * Diagnóstico de la conexión: cuenta con la que entra la web, permisos,
 * definers de las vistas y una prueba de cada consulta que usa la aplicación.
 */

exigir_usuario();
$pdo = bbdd();

function prueba(PDO $pdo, string $titulo, string $sql, array $parametros = []): array
{
    try {
        $consulta = $pdo->prepare($sql);
        $consulta->execute($parametros);
        $filas = $consulta->fetchAll();
        $consulta->closeCursor();
        return [$titulo, 'OK (' . count($filas) . ' filas)', $filas];
    } catch (Throwable $error) {
        return [$titulo, 'ERROR: ' . $error->getMessage(), []];
    }
}

$hoy = date('Y-m-d');
$resultados = [
    prueba($pdo, 'Cuenta y base', 'SELECT CURRENT_USER() AS cuenta_mysql, USER() AS conexion, DATABASE() AS base, @@hostname AS servidor'),
    prueba($pdo, 'Permisos de la cuenta', 'SHOW GRANTS'),
    prueba($pdo, 'Tabla fza_empresas', 'SELECT CODIGO_EMP_EMP, GRUPO_ZONA_IVA_EMP FROM fza_empresas LIMIT 3'),
    prueba($pdo, 'Tabla fza_contadores (FC)', 'SELECT EMPRESA_CON, SERIE_CON, CON FROM fza_contadores WHERE TIPO_DOC_CON = \'FC\' LIMIT 5'),
    prueba($pdo, 'Vista vi_empresas_series', 'SELECT CODIGO_EMP_EMPSER, EMPSER, TIPO_DOC_EMPSER FROM vi_empresas_series LIMIT 3'),
    prueba($pdo, 'Vista vi_ivas', 'SELECT IVA_IVAGRP, PORCENTAJE_NORMAL_IVA FROM vi_ivas LIMIT 3'),
    prueba($pdo, 'Vista vi_clientes', 'SELECT CODIGO_CLI_CLI FROM vi_clientes LIMIT 1'),
    prueba($pdo, 'Definers de las vistas', 'SELECT TABLE_NAME, DEFINER, SECURITY_TYPE FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME LIMIT 200'),
    prueba($pdo, 'Definers de los procedimientos', 'SELECT ROUTINE_NAME, DEFINER, SECURITY_TYPE FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME IN (\'PRC_GET_NEXT_CONT\',\'PRC_GET_NEXT_CONTADOR\',\'PRC_GET_NEXT_CONT_FACT_SERIE\',\'PRC_FNC_GET_NEXT_LINEA_FACTURA\',\'PRC_CREAR_ACTUALIZAR_EMPRESA\',\'PRC_CREAR_ACTUALIZAR_CLIENTE\')'),
    prueba($pdo, 'Series de la primera empresa', 'SELECT EMPSER FROM vi_empresas_series WHERE CODIGO_EMP_EMPSER = (SELECT MIN(CODIGO_EMP_EMP) FROM fza_empresas) AND TIPO_DOC_EMPSER = \'FC\''),
    prueba($pdo, 'IVA vigente grupo 1 (tablas)', 'SELECT I.PORCENTAJE_NORMAL_IVA FROM fza_ivas I LEFT JOIN fza_ivas_grupos G ON G.IVA_IVAGRP = I.IVA_IVAGRP WHERE I.IVA_IVAGRP = ? AND I.FECHA_DESDE_IVA <= ? AND (I.FECHA_HASTA_IVA >= ? OR I.FECHA_HASTA_IVA IS NULL)', ['1', $hoy, $hoy]),
];

ob_start();
?>
<p class="ayuda"><?= h(t('Cada bloque es una consulta que usa la web. Si alguna da ERROR, ese es el punto que falla.')) ?></p>
<?php foreach ($resultados as [$titulo, $estado, $filas]): ?>
<section class="tarjeta">
  <h2><?= h($titulo) ?></h2>
  <p class="<?= str_starts_with($estado, 'OK') ? 'ayuda' : 'mensaje error' ?>"><?= h($estado) ?></p>
  <?php if ($filas !== []): ?>
  <div class="tabla-envoltorio"><table class="tabla">
    <thead><tr><?php foreach (array_keys($filas[0]) as $columna): ?><th><?= h((string)$columna) ?></th><?php endforeach; ?></tr></thead>
    <tbody>
    <?php foreach (array_slice($filas, 0, 25) as $fila): ?>
    <tr><?php foreach ($fila as $valor): ?><td><?= h(mb_substr((string)$valor, 0, 120)) ?></td><?php endforeach; ?></tr>
    <?php endforeach; ?>
    </tbody>
  </table></div>
  <?php if (count($filas) > 25): ?><p class="ayuda"><?= h(t('… y {n} más', ['n' => count($filas) - 25])) ?></p><?php endif; ?>
  <?php endif; ?>
</section>
<?php endforeach; ?>
<p class="pie-enlaces"><a href="<?= h(url('menu')) ?>"><?= h(t('‹ Volver al menú')) ?></a></p>
<?php
pagina(t('Diagnóstico'), (string)ob_get_clean());
