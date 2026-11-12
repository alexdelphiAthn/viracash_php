<?php
declare(strict_types=1);
/*
 * Comprueba en el servidor remoto (solo lecturas y una tabla temporal de
 * sesión) qué distingue mayúsculas: tablas, alias, temporales,
 * INFORMATION_SCHEMA, SHOW TABLES LIKE. Guarda los nombres reales en
 * nombres_reales.json para el análisis del código Delphi.
 */
$config = require __DIR__ . '/../config.php';
$c = $config['bbdd'];
$pdo = new PDO(sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $c['host'], $c['puerto'], $c['nombre']), $c['usuario'], $c['password'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 20, PDO::ATTR_EMULATE_PREPARES => false]);

function prueba(PDO $pdo, string $titulo, string $sql): void
{
    try {
        $filas = $pdo->query($sql)->fetchAll(PDO::FETCH_NUM);
        $texto = $filas === [] ? '(sin filas)' : implode(' | ', array_map(fn($f) => implode(',', array_map(fn($v) => (string)$v, $f)), array_slice($filas, 0, 5)));
        printf("%-58s OK  %s\n", $titulo, $texto);
    } catch (PDOException $e) {
        printf("%-58s ERR %s\n", $titulo, $e->errorInfo[2] ?? $e->getMessage());
    }
}

prueba($pdo, 'Servidor', 'SELECT @@version, @@version_compile_os, @@lower_case_table_names, @@collation_database');
prueba($pdo, 'Plugin de autenticación por defecto', 'SELECT @@default_authentication_plugin');
prueba($pdo, 'Tablas/vistas reales con alguna mayúscula', "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND CAST(TABLE_NAME AS BINARY) <> CAST(LOWER(TABLE_NAME) AS BINARY)");
prueba($pdo, 'Tabla en mayúsculas (FZA_FACTURAS)', 'SELECT COUNT(*) FROM FZA_FACTURAS');
prueba($pdo, 'Tabla mixta (fza_EMPRESAs)', 'SELECT COUNT(*) FROM fza_EMPRESAs');
prueba($pdo, 'Vista en mayúsculas (VI_USUARIOS)', 'SELECT COUNT(*) FROM VI_USUARIOS');
prueba($pdo, 'Alias distinto (F / f.)', 'SELECT f.NUMERO_FAC FROM fza_facturas F LIMIT 1');
prueba($pdo, 'Alias igual (F / F.)', 'SELECT F.NUMERO_FAC FROM fza_facturas F LIMIT 1');
prueba($pdo, 'information_schema.columns en minúsculas', "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = 'fza_facturas'");
prueba($pdo, 'INFORMATION_SCHEMA.COLUMNS en mayúsculas', "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'fza_facturas'");
prueba($pdo, "TABLE_NAME = 'FZA_FACTURAS' (literal en mayúsculas)", "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'FZA_FACTURAS'");
prueba($pdo, "SHOW TABLES LIKE 'FZA_FACT%'", "SHOW TABLES LIKE 'FZA_FACT%'");
prueba($pdo, "SHOW TABLES LIKE 'fza_fact%'", "SHOW TABLES LIKE 'fza_fact%'");
prueba($pdo, 'Nombre de procedimiento en minúsculas', "SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'prc_get_next_cont'");
prueba($pdo, 'Crear temporal tmp_prueba_caso', 'CREATE TEMPORARY TABLE tmp_prueba_caso (a INT)');
prueba($pdo, 'Leer temporal como TMP_PRUEBA_CASO', 'SELECT COUNT(*) FROM TMP_PRUEBA_CASO');
prueba($pdo, 'Leer temporal como tmp_prueba_caso', 'SELECT COUNT(*) FROM tmp_prueba_caso');
prueba($pdo, 'Borrar temporal', 'DROP TEMPORARY TABLE tmp_prueba_caso');
prueba($pdo, 'Columna en otra caja (numero_fac)', 'SELECT numero_fac FROM fza_facturas LIMIT 1');
// Usa la base configurada para probar mayúsculas sin fijar un nombre de instalación.
$baseMayusculas = '`' . str_replace('`', '``', strtoupper((string)$c['nombre'])) . '`';
prueba($pdo, 'Base de datos en otra caja', 'SELECT COUNT(*) FROM ' . $baseMayusculas . '.fza_facturas');

$reales = $pdo->query("SELECT TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME")->fetchAll(PDO::FETCH_KEY_PAIR);
file_put_contents(__DIR__ . '/nombres_reales.json', json_encode($reales, JSON_PRETTY_PRINT));
echo "\nNombres reales guardados: ", count($reales), " (tablas + vistas)\n";

/* Rutinas del remoto: referencias a tablas en otra caja y temporales usadas con distinta caja. */
$porMin = [];
foreach ($reales as $n => $t) { $porMin[strtolower($n)] = $n; }
$rutinas = $pdo->query("SELECT ROUTINE_NAME, ROUTINE_DEFINITION FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE()")->fetchAll(PDO::FETCH_KEY_PAIR);
echo "\n== Rutinas remotas (", count($rutinas), ") con tablas/vistas en otra caja ==\n";
$n = 0;
foreach ($rutinas as $nombre => $def) {
    preg_match_all('/\b[A-Za-z_][A-Za-z0-9_]*\b/', (string)$def, $m);
    $malas = [];
    foreach (array_unique($m[0]) as $tok) {
        $min = strtolower($tok);
        if (isset($porMin[$min]) && $porMin[$min] !== $tok) { $malas[] = $tok . ' -> ' . $porMin[$min]; }
    }
    if ($malas !== []) { $n++; printf("  %-45s %s\n", $nombre, implode(', ', $malas)); }
}
echo "Rutinas afectadas: $n\n";

echo "\n== Temporales en rutinas remotas usadas con distinta caja ==\n";
$n = 0;
foreach ($rutinas as $nombre => $def) {
    preg_match_all('/CREATE\s+TEMPORARY\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?/i', (string)$def, $m);
    $temporales = array_unique($m[1]);
    if ($temporales === []) { continue; }
    preg_match_all('/\b[A-Za-z_][A-Za-z0-9_]*\b/', (string)$def, $t);
    $malas = [];
    foreach ($temporales as $tmp) {
        foreach (array_unique($t[0]) as $tok) {
            if (strtolower($tok) === strtolower($tmp) && $tok !== $tmp) { $malas[] = "$tok <> $tmp"; }
        }
    }
    if ($malas !== []) { $n++; printf("  %-45s %s\n", $nombre, implode(', ', array_unique($malas))); }
}
echo "Rutinas afectadas: $n\n";
