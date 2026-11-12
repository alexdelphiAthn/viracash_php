<?php
declare(strict_types=1);
/*
 * Alias de tabla con distinta caja DENTRO DE LA MISMA SENTENCIA SQL.
 * Reconstruye las sentencias: en .dfm cada bloque "X.Strings = ( ... )";
 * en .pas/.inc/.dpr la concatenación de literales 'a' + 'b' hasta la línea
 * que no termina en "+". Un uso "x." es sospechoso si en la sentencia no hay
 * alias definido exactamente "x" pero sí uno que solo difiere en la caja.
 */
$raiz = 'C:/DISCO_DURO/proyectos/ViraCash/src';
$reales = json_decode(file_get_contents(__DIR__ . '/nombres_reales.json'), true);
$porMin = [];
foreach ($reales as $n => $t) { $porMin[strtolower($n)] = $n; }
$palabrasClave = ['where', 'on', 'set', 'left', 'right', 'inner', 'outer', 'cross', 'join', 'group', 'order', 'limit', 'having', 'union', 'select', 'values', 'straight_join', 'using', 'natural', 'for', 'lock', 'into', 'partition', 'force', 'use', 'ignore', 'as', 'and', 'or', 'not', 'in', 'like', 'if', 'then', 'else', 'end', 'begin', 'when', 'case', 'is', 'null', 'desc', 'asc', 'by'];
$excluir = ['/__history/', '/__recovery/', '/build/'];

function literales(string $linea): string
{
    /* Contenido de los literales Delphi de la línea, con '' -> ' */
    preg_match_all("/'((?:[^']|'')*)'/", $linea, $m);
    return implode(' ', array_map(fn($s) => str_replace("''", "'", $s), $m[1]));
}

function sentencias_pas(array $lineas): array
{
    $sentencias = []; $actual = ''; $inicio = 0;
    foreach ($lineas as $i => $linea) {
        $sinComentario = preg_replace('~//.*$~', '', $linea);
        $lit = literales($sinComentario);
        if ($lit !== '') {
            if ($actual === '') { $inicio = $i + 1; }
            $actual .= ' ' . $lit;
        }
        $continua = preg_match('/\+\s*$/', trim($sinComentario)) === 1 || preg_match('/^\s*\+/', $sinComentario) === 1 && $lit !== '';
        if (!$continua && $actual !== '') {
            /* la sentencia puede seguir en la línea siguiente si esta empieza por "+" */
            $siguiente = $lineas[$i + 1] ?? '';
            if (preg_match('/^\s*\+/', $siguiente)) { continue; }
            $sentencias[] = [$inicio, $actual];
            $actual = '';
        }
    }
    if ($actual !== '') { $sentencias[] = [$inicio, $actual]; }
    return $sentencias;
}

function sentencias_dfm(array $lineas): array
{
    $sentencias = []; $actual = ''; $inicio = 0; $dentro = false;
    foreach ($lineas as $i => $linea) {
        if (!$dentro && preg_match('/\.Strings = \($/', rtrim($linea))) { $dentro = true; $actual = ''; $inicio = $i + 1; continue; }
        if ($dentro) {
            $actual .= ' ' . literales($linea);
            if (preg_match('/\)\s*$/', $linea)) { $dentro = false; $sentencias[] = [$inicio, $actual]; }
        }
    }
    return $sentencias;
}

function analizar(string $sql, array $porMin, array $palabrasClave): array
{
    /* definiciones de alias: FROM/JOIN/UPDATE tabla [AS] alias  |  ) [AS] alias */
    $definidos = [];
    preg_match_all('/\b(?:FROM|JOIN|UPDATE|INTO)\s+`?([A-Za-z_][A-Za-z0-9_]*)`?\s+(?:AS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?/i', $sql, $m, PREG_SET_ORDER);
    foreach ($m as $a) {
        if (in_array(strtolower($a[2]), $palabrasClave, true)) { continue; }
        $definidos[$a[2]] = true;
    }
    preg_match_all('/\)\s*(?:AS\s+)?`?([A-Za-z_][A-Za-z0-9_]*)`?\s*(?=\bON\b|\bWHERE\b|\bJOIN\b|\bLEFT\b|\bRIGHT\b|\bINNER\b|\bCROSS\b|\bGROUP\b|\bORDER\b|\bLIMIT\b|\bUNION\b|,|\)|$)/i', $sql, $m2);
    foreach ($m2[1] as $a) { if (!in_array(strtolower($a), $palabrasClave, true)) { $definidos[$a] = true; } }
    /* usos: alias.columna */
    preg_match_all('/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*`?[A-Za-z_*]/', $sql, $mu);
    $malos = [];
    foreach (array_unique($mu[1]) as $u) {
        if (isset($definidos[$u])) { continue; }
        $min = strtolower($u);
        if (isset($porMin[$min]) || in_array($min, ['information_schema', 'mysql', 'performance_schema', 'sys'], true)) { continue; }
        foreach (array_keys($definidos) as $d) {
            if (strtolower($d) === $min) { $malos[] = "$u. (definido $d)"; }
        }
    }
    return array_unique($malos);
}

$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($raiz, FilesystemIterator::SKIP_DOTS));
$total = 0;
foreach ($it as $f) {
    $ruta = str_replace('\\', '/', $f->getPathname());
    $saltar = false;
    foreach ($excluir as $e) { if (str_contains($ruta, $e)) { $saltar = true; break; } }
    $ext = strtolower($f->getExtension());
    if ($saltar || !in_array($ext, ['pas', 'dfm', 'inc', 'dpr'], true)) { continue; }
    $texto = file_get_contents($ruta);
    if ($texto === false || $texto === '') { continue; }
    $lineas = preg_split('/\r\n|\r|\n/', $texto);
    $sentencias = $ext === 'dfm' ? sentencias_dfm($lineas) : sentencias_pas($lineas);
    $rel = substr($ruta, strlen($raiz) + 1);
    foreach ($sentencias as [$inicio, $sql]) {
        if (!preg_match('/\b(FROM|JOIN|UPDATE)\b/i', $sql)) { continue; }
        $malos = analizar($sql, $porMin, $palabrasClave);
        if ($malos !== []) {
            $total++;
            printf("%s:%d  %s\n      %s\n", $rel, $inicio, implode('; ', $malos), mb_substr(trim(preg_replace('/\s+/', ' ', $sql)), 0, 160));
        }
    }
}
echo "Sentencias sospechosas: $total\n";
