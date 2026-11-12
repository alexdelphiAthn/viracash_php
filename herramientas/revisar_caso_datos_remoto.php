<?php
declare(strict_types=1);
/*
 * Busca en los DATOS del remoto (solo lectura) columnas de texto que guarden
 * SQL con nombres de tablas/vistas en otra caja (perfiles de usuario,
 * generador de procesos, etc.). Imprime tabla, columna, clave y el
 * identificador mal escrito, y genera un UPDATE por fila en
 * corregir_caso_datos.sql (sin ejecutarlo).
 */
$config = require __DIR__ . '/../config.php';
$c = $config['bbdd'];
$pdo = new PDO(sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $c['host'], $c['puerto'], $c['nombre']), $c['usuario'], $c['password'],
    [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION, PDO::ATTR_TIMEOUT => 20, PDO::ATTR_EMULATE_PREPARES => false]);
$reales = json_decode(file_get_contents(__DIR__ . '/nombres_reales.json'), true);
$porMin = [];
foreach ($reales as $n => $t) { $porMin[strtolower($n)] = $n; }

$columnas = $pdo->query("SELECT C.TABLE_NAME, C.COLUMN_NAME, C.DATA_TYPE, C.CHARACTER_MAXIMUM_LENGTH
    FROM INFORMATION_SCHEMA.COLUMNS C JOIN INFORMATION_SCHEMA.TABLES T ON T.TABLE_SCHEMA = C.TABLE_SCHEMA AND T.TABLE_NAME = C.TABLE_NAME
    WHERE C.TABLE_SCHEMA = DATABASE() AND T.TABLE_TYPE = 'BASE TABLE'
      AND (C.DATA_TYPE IN ('text','mediumtext','longtext','tinytext') OR (C.DATA_TYPE = 'varchar' AND C.CHARACTER_MAXIMUM_LENGTH >= 60))
    ORDER BY C.TABLE_NAME, C.ORDINAL_POSITION")->fetchAll(PDO::FETCH_ASSOC);
echo 'Columnas de texto revisadas: ', count($columnas), "\n";

$claves = [];
foreach ($pdo->query("SELECT TABLE_NAME, COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE() AND CONSTRAINT_NAME = 'PRIMARY' ORDER BY TABLE_NAME, ORDINAL_POSITION") as $k) {
    $claves[$k['TABLE_NAME']][] = $k['COLUMN_NAME'];
}

$sqlSalida = "-- Corrige nombres de tablas/vistas escritos con otra caja dentro de datos (SQL guardado en tablas).\n-- Generado el " . date('Y-m-d H:i') . ". Revisar antes de ejecutar.\n";
$hallazgos = 0; $filasAfectadas = 0;
foreach ($columnas as $col) {
    $t = $col['TABLE_NAME']; $c = $col['COLUMN_NAME'];
    $pk = $claves[$t] ?? [];
    $selectPk = $pk === [] ? '' : ', ' . implode(', ', array_map(fn($p) => "`$p`", $pk));
    $sql = "SELECT `$c` AS VALOR$selectPk FROM `$t` WHERE `$c` LIKE '%fza\\_%' OR `$c` LIKE '%vi\\_%' OR `$c` LIKE '%fzaest\\_%'";
    try {
        $filas = $pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC);
    } catch (PDOException $e) {
        echo "  (no se pudo leer $t.$c: ", $e->errorInfo[2] ?? $e->getMessage(), ")\n";
        continue;
    }
    foreach ($filas as $fila) {
        $valor = (string)$fila['VALOR'];
        preg_match_all('/\b[A-Za-z_][A-Za-z0-9_]*\b/', $valor, $m);
        $malas = [];
        foreach (array_unique($m[0]) as $tok) {
            $min = strtolower($tok);
            if (isset($porMin[$min]) && $porMin[$min] !== $tok) { $malas[$tok] = $porMin[$min]; }
        }
        if ($malas === []) { continue; }
        $filasAfectadas++;
        $hallazgos += count($malas);
        $clave = [];
        foreach ($pk as $p) { $clave[] = "$p=" . $fila[$p]; }
        printf("%s.%s [%s]: %s\n", $t, $c, implode(', ', $clave), implode(', ', array_map(fn($k, $v) => "$k -> $v", array_keys($malas), $malas)));
        $nuevo = $valor;
        foreach ($malas as $k => $v) { $nuevo = preg_replace('/\b' . preg_quote($k, '/') . '\b/', $v, $nuevo); }
        if ($pk !== []) {
            $where = implode(' AND ', array_map(fn($p) => "`$p` = " . $pdo->quote((string)$fila[$p]), $pk));
            $sqlSalida .= "UPDATE `$t` SET `$c` = " . $pdo->quote($nuevo) . " WHERE $where AND `$c` = " . $pdo->quote($valor) . ";\n";
            $sqlReversion = ($sqlReversion ?? "-- Reversión: deja las filas como estaban antes de corregir_caso_datos.sql.\n") .
                "UPDATE `$t` SET `$c` = " . $pdo->quote($valor) . " WHERE $where AND `$c` = " . $pdo->quote($nuevo) . ";\n";
        } else {
            $sqlSalida .= "-- $t.$c sin clave primaria: UPDATE `$t` SET `$c` = " . $pdo->quote($nuevo) . " WHERE `$c` = " . $pdo->quote($valor) . ";\n";
        }
    }
}
file_put_contents(__DIR__ . '/corregir_caso_datos.sql', $sqlSalida);
file_put_contents(__DIR__ . '/corregir_caso_datos_reversion.sql', $sqlReversion ?? "-- Nada que revertir.
");
echo "Filas afectadas: $filasAfectadas; identificadores: $hallazgos. Script: corregir_caso_datos.sql\n";
