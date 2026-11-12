<?php
declare(strict_types=1);
/*
 * Rastrea todo el repositorio ViraCash (pas, dfm, inc, dpr, fr3, sql, ini,
 * txt) buscando:
 *  1. cualquier identificador que coincida con una tabla/vista real salvo por
 *     mayúsculas (en cualquier posición: FROM, INTO, tabla.columna,
 *     UpdatingTable, etc.);
 *  2. alias de tabla usados con distinta caja dentro del mismo fichero;
 *  3. tablas temporales creadas en el código y usadas con distinta caja.
 * Nombres reales: nombres_reales.json (generado por probar_caso_remoto.php).
 */
$raiz = 'C:/DISCO_DURO/proyectos/ViraCash';
$reales = json_decode(file_get_contents(__DIR__ . '/nombres_reales.json'), true);
$porMin = [];
foreach ($reales as $n => $t) { $porMin[strtolower($n)] = $n; }

$extensiones = ['pas', 'dfm', 'inc', 'dpr', 'dpk', 'fr3', 'sql', 'ini', 'txt', 'py', 'ps1'];
$excluir = ['/.git/', '/build/', '/Win64/', '/Win32/', '/__history/', '/__recovery/', '/dcus/', '/node_modules/'];
$palabrasClave = ['where', 'on', 'set', 'left', 'right', 'inner', 'outer', 'cross', 'join', 'group', 'order', 'limit', 'having', 'union', 'select', 'values', 'straight_join', 'using', 'natural', 'for', 'lock', 'into', 'partition', 'force', 'use', 'ignore', 'as', 'and', 'or', 'not', 'in', 'like', 'if', 'then', 'else', 'end', 'begin'];

$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($raiz, FilesystemIterator::SKIP_DOTS));
$hallazgos = []; $alias = []; $temporales = []; $ficheros = 0;
foreach ($it as $f) {
    $ruta = str_replace('\\', '/', $f->getPathname());
    $saltar = false;
    foreach ($excluir as $e) { if (str_contains($ruta, $e)) { $saltar = true; break; } }
    if ($saltar || !in_array(strtolower($f->getExtension()), $extensiones, true)) { continue; }
    $ficheros++;
    $texto = file_get_contents($ruta);
    if ($texto === false || $texto === '') { continue; }
    $rel = substr($ruta, strlen($raiz) + 1);
    $lineas = preg_split('/\r\n|\r|\n/', $texto);

    /* 1. tablas/vistas en otra caja, con número de línea */
    foreach ($lineas as $i => $linea) {
        if (!preg_match_all('/\b[A-Za-z_][A-Za-z0-9_]*\b/', $linea, $m)) { continue; }
        foreach ($m[0] as $tok) {
            $min = strtolower($tok);
            if (isset($porMin[$min]) && $porMin[$min] !== $tok) {
                $hallazgos[] = [$rel, $i + 1, $tok, $porMin[$min], trim($linea)];
            }
        }
    }

    /* 2. alias: definición "FROM/JOIN/UPDATE tabla [AS] alias" y usos "alias." */
    preg_match_all('/\b(?:FROM|JOIN|UPDATE)\s+`?([A-Za-z_][A-Za-z0-9_]*)`?\s+(?:AS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?/i', $texto, $ma, PREG_SET_ORDER);
    $definidos = [];
    foreach ($ma as $a) {
        if (in_array(strtolower($a[2]), $palabrasClave, true)) { continue; }
        if (!isset($porMin[strtolower($a[1])]) && !preg_match('/^(tmp|temp)_/i', $a[1])) { continue; }
        $definidos[strtolower($a[2])][$a[2]] = true;
    }
    if ($definidos !== []) {
        preg_match_all('/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*`?[A-Za-z_]/', $texto, $mu);
        $usados = [];
        foreach ($mu[1] as $u) { $usados[strtolower($u)][$u] = true; }
        foreach ($definidos as $min => $formas) {
            $todas = array_keys($formas + ($usados[$min] ?? []));
            if (count($todas) > 1) { $alias[$rel][] = implode(' / ', $todas); }
        }
    }

    /* 3. temporales creadas en el fichero y usadas con otra caja */
    preg_match_all('/CREATE\s+TEMPORARY\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?/i', $texto, $mt);
    foreach (array_unique($mt[1]) as $tmp) {
        preg_match_all('/\b' . preg_quote($tmp, '/') . '\b/i', $texto, $mx);
        $formas = array_unique($mx[0]);
        if (count($formas) > 1) { $temporales[$rel][] = implode(' / ', $formas); }
    }
}

echo "Ficheros revisados: $ficheros\n";
echo "\n== 1. Tablas/vistas escritas con otra caja (fichero:línea  escrito -> real) ==\n";
$porFichero = [];
foreach ($hallazgos as [$rel, $linea, $tok, $real, $contexto]) {
    $porFichero[$rel][] = [$linea, $tok, $real, $contexto];
}
ksort($porFichero);
foreach ($porFichero as $rel => $lista) {
    echo "$rel\n";
    foreach ($lista as [$linea, $tok, $real, $contexto]) {
        printf("  %5d  %-32s -> %-32s %s\n", $linea, $tok, $real, mb_substr($contexto, 0, 90));
    }
}
echo 'Total: ', count($hallazgos), ' referencias en ', count($porFichero), " ficheros\n";
file_put_contents(__DIR__ . '/delphi_caso.json', json_encode($porFichero, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));

echo "\n== 2. Alias de tabla con distinta caja en el mismo fichero (revisar a mano) ==\n";
ksort($alias);
foreach ($alias as $rel => $lista) { echo "$rel: ", implode('; ', array_unique($lista)), "\n"; }
echo 'Ficheros: ', count($alias), "\n";

echo "\n== 3. Tablas temporales usadas con distinta caja ==\n";
ksort($temporales);
foreach ($temporales as $rel => $lista) { echo "$rel: ", implode('; ', $lista), "\n"; }
echo 'Ficheros: ', count($temporales), "\n";
