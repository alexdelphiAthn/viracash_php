<?php
declare(strict_types=1);

/*
 * Codificador de códigos QR (ISO/IEC 18004) sin dependencias: modo byte,
 * nivel de corrección M, versiones 1 a 40, elección de máscara por penalización
 * y salida como matriz de módulos o como PNG (RGB, sin GD). Reproduce lo que
 * hace DelphiZXIngQRCode en el programa: nivel M, UTF-8 sin BOM, zona de
 * silencio de 4 módulos y escala 4.
 */

final class CodigoQR
{
    /**
     * Bloques de corrección de errores por versión para el nivel M:
     * [codewords de corrección por bloque, [[bloques, codewords de datos], ...]].
     */
    private const BLOQUES_M = [
        1  => [10, [[1, 16]]],
        2  => [16, [[1, 28]]],
        3  => [26, [[1, 44]]],
        4  => [18, [[2, 32]]],
        5  => [24, [[2, 43]]],
        6  => [16, [[4, 27]]],
        7  => [18, [[4, 31]]],
        8  => [22, [[2, 38], [2, 39]]],
        9  => [22, [[3, 36], [2, 37]]],
        10 => [26, [[4, 43], [1, 44]]],
        11 => [30, [[1, 50], [4, 51]]],
        12 => [22, [[6, 36], [2, 37]]],
        13 => [22, [[8, 37], [1, 38]]],
        14 => [24, [[4, 40], [5, 41]]],
        15 => [24, [[5, 41], [5, 42]]],
        16 => [28, [[7, 45], [3, 46]]],
        17 => [28, [[10, 46], [1, 47]]],
        18 => [26, [[9, 43], [4, 44]]],
        19 => [26, [[3, 44], [11, 45]]],
        20 => [26, [[3, 41], [13, 42]]],
        21 => [26, [[17, 42]]],
        22 => [28, [[17, 46]]],
        23 => [28, [[4, 47], [14, 48]]],
        24 => [28, [[6, 45], [14, 46]]],
        25 => [28, [[8, 47], [13, 48]]],
        26 => [28, [[19, 46], [4, 47]]],
        27 => [28, [[22, 45], [3, 46]]],
        28 => [28, [[3, 45], [23, 46]]],
        29 => [28, [[21, 45], [7, 46]]],
        30 => [28, [[19, 47], [10, 48]]],
        31 => [28, [[2, 46], [29, 47]]],
        32 => [28, [[10, 46], [23, 47]]],
        33 => [28, [[14, 46], [21, 47]]],
        34 => [28, [[14, 46], [23, 47]]],
        35 => [28, [[12, 47], [26, 48]]],
        36 => [28, [[6, 47], [34, 48]]],
        37 => [28, [[29, 46], [14, 47]]],
        38 => [28, [[13, 46], [32, 47]]],
        39 => [28, [[40, 47], [7, 48]]],
        40 => [28, [[18, 47], [31, 48]]],
    ];

    /** Posiciones de los patrones de alineamiento por versión. */
    private const ALINEAMIENTO = [
        2 => [6, 18], 3 => [6, 22], 4 => [6, 26], 5 => [6, 30], 6 => [6, 34],
        7 => [6, 22, 38], 8 => [6, 24, 42], 9 => [6, 26, 46], 10 => [6, 28, 50],
        11 => [6, 30, 54], 12 => [6, 32, 58], 13 => [6, 34, 62], 14 => [6, 26, 46, 66],
        15 => [6, 26, 48, 70], 16 => [6, 26, 50, 74], 17 => [6, 30, 54, 78],
        18 => [6, 30, 56, 82], 19 => [6, 30, 58, 86], 20 => [6, 34, 62, 90],
        21 => [6, 28, 50, 72, 94], 22 => [6, 26, 50, 74, 98], 23 => [6, 30, 54, 78, 102],
        24 => [6, 28, 54, 80, 106], 25 => [6, 32, 58, 84, 110], 26 => [6, 30, 58, 86, 114],
        27 => [6, 34, 62, 90, 118], 28 => [6, 26, 50, 74, 98, 122],
        29 => [6, 30, 54, 78, 102, 126], 30 => [6, 26, 52, 78, 104, 130],
        31 => [6, 30, 56, 82, 108, 134], 32 => [6, 34, 60, 86, 112, 138],
        33 => [6, 30, 58, 86, 114, 142], 34 => [6, 34, 62, 90, 118, 146],
        35 => [6, 30, 54, 78, 102, 126, 150], 36 => [6, 24, 50, 76, 102, 128, 154],
        37 => [6, 28, 54, 80, 106, 132, 158], 38 => [6, 32, 58, 84, 110, 136, 162],
        39 => [6, 26, 54, 82, 110, 138, 166], 40 => [6, 30, 58, 86, 114, 142, 170],
    ];

    /** @var int[] */
    private static array $exp = [];
    /** @var int[] */
    private static array $log = [];
    /** Máscara elegida en la última llamada a matriz() (para pruebas). */
    public static int $ultimaMascara = -1;
    /** Secuencia final de codewords de la última llamada (para pruebas). */
    public static array $ultimaSecuencia = [];

    /**
     * Matriz de módulos del QR (filas de 0/1, sin zona de silencio) para un
     * texto UTF-8, en modo byte y nivel M.
     */
    public static function matriz(string $texto, ?int $mascaraForzada = null): array
    {
        $datos = $texto;
        $longitud = strlen($datos);
        $version = self::versionMinima($longitud);
        [$ecPorBloque, $grupos] = self::BLOQUES_M[$version];
        $totalDatos = 0;
        foreach ($grupos as [$bloques, $codewords]) {
            $totalDatos += $bloques * $codewords;
        }

        /* Flujo de bits: modo byte, longitud, datos, terminador y relleno. */
        $bits = '0100';
        $bitsLongitud = $version <= 9 ? 8 : 16;
        $bits .= str_pad(decbin($longitud), $bitsLongitud, '0', STR_PAD_LEFT);
        for ($i = 0; $i < $longitud; $i++) {
            $bits .= str_pad(decbin(ord($datos[$i])), 8, '0', STR_PAD_LEFT);
        }
        $capacidadBits = $totalDatos * 8;
        $bits .= str_repeat('0', min(4, $capacidadBits - strlen($bits)));
        if (strlen($bits) % 8 !== 0) {
            $bits .= str_repeat('0', 8 - strlen($bits) % 8);
        }
        $relleno = [0xEC, 0x11];
        for ($i = 0; strlen($bits) < $capacidadBits; $i++) {
            $bits .= str_pad(decbin($relleno[$i % 2]), 8, '0', STR_PAD_LEFT);
        }
        $codewords = [];
        for ($i = 0; $i < $totalDatos; $i++) {
            $codewords[] = bindec(substr($bits, $i * 8, 8));
        }

        /* Bloques de datos y de corrección, intercalados. */
        $bloquesDatos = [];
        $bloquesEc = [];
        $pos = 0;
        $generador = self::generador($ecPorBloque);
        foreach ($grupos as [$bloques, $numCodewords]) {
            for ($b = 0; $b < $bloques; $b++) {
                $bloque = array_slice($codewords, $pos, $numCodewords);
                $pos += $numCodewords;
                $bloquesDatos[] = $bloque;
                $bloquesEc[] = self::codigosCorreccion($bloque, $generador, $ecPorBloque);
            }
        }
        $secuencia = [];
        $maxDatos = 0;
        foreach ($bloquesDatos as $bloque) {
            $maxDatos = max($maxDatos, count($bloque));
        }
        for ($i = 0; $i < $maxDatos; $i++) {
            foreach ($bloquesDatos as $bloque) {
                if (isset($bloque[$i])) {
                    $secuencia[] = $bloque[$i];
                }
            }
        }
        for ($i = 0; $i < $ecPorBloque; $i++) {
            foreach ($bloquesEc as $bloque) {
                $secuencia[] = $bloque[$i];
            }
        }

        self::$ultimaSecuencia = $secuencia;

        /* Matriz: patrones fijos, datos y máscara con menor penalización. */
        $lado = $version * 4 + 17;
        [$base, $reservado] = self::patronesFijos($version, $lado);
        self::colocarDatos($base, $reservado, $secuencia, $lado);
        $mejor = null;
        $mejorPenalizacion = PHP_INT_MAX;
        for ($mascara = 0; $mascara < 8; $mascara++) {
            if ($mascaraForzada !== null && $mascara !== $mascaraForzada) {
                continue;
            }
            $candidata = self::aplicarMascara($base, $reservado, $mascara, $lado);
            self::escribirFormato($candidata, $mascara, $lado);
            if ($version >= 7) {
                self::escribirVersion($candidata, $version, $lado);
            }
            $penalizacion = self::penalizacion($candidata, $lado);
            if ($penalizacion < $mejorPenalizacion) {
                $mejorPenalizacion = $penalizacion;
                $mejor = $candidata;
                self::$ultimaMascara = $mascara;
            }
        }
        return $mejor;
    }

    /**
     * PNG RGB de 8 bits con la matriz (módulo negro = 0,0,0), zona de silencio
     * de $margen módulos y $escala píxeles por módulo, sin usar GD.
     */
    public static function png(array $matriz, int $escala = 4, int $margen = 4): string
    {
        $lado = count($matriz);
        $pixeles = ($lado + 2 * $margen) * $escala;
        $negro = "\x00\x00\x00";
        $blanco = "\xFF\xFF\xFF";
        $filas = '';
        $filaBlanca = "\x00" . str_repeat($blanco, $pixeles);
        for ($i = 0; $i < $margen * $escala; $i++) {
            $filas .= $filaBlanca;
        }
        foreach ($matriz as $fila) {
            $linea = "\x00" . str_repeat($blanco, $margen * $escala);
            foreach ($fila as $modulo) {
                $linea .= str_repeat($modulo ? $negro : $blanco, $escala);
            }
            $linea .= str_repeat($blanco, $margen * $escala);
            for ($i = 0; $i < $escala; $i++) {
                $filas .= $linea;
            }
        }
        for ($i = 0; $i < $margen * $escala; $i++) {
            $filas .= $filaBlanca;
        }
        $ihdr = pack('NNCCCCC', $pixeles, $pixeles, 8, 2, 0, 0, 0);
        return "\x89PNG\r\n\x1a\n" .
            self::trozoPng('IHDR', $ihdr) .
            self::trozoPng('IDAT', (string)gzcompress($filas, 6)) .
            self::trozoPng('IEND', '');
    }

    private static function trozoPng(string $tipo, string $datos): string
    {
        return pack('N', strlen($datos)) . $tipo . $datos . pack('N', crc32($tipo . $datos));
    }

    private static function versionMinima(int $bytes): int
    {
        for ($version = 1; $version <= 40; $version++) {
            $capacidad = 0;
            foreach (self::BLOQUES_M[$version][1] as [$bloques, $codewords]) {
                $capacidad += $bloques * $codewords;
            }
            $cabecera = 4 + ($version <= 9 ? 8 : 16);
            if ($bytes * 8 + $cabecera <= $capacidad * 8) {
                return $version;
            }
        }
        throw new RuntimeException('Texto demasiado largo para un código QR.');
    }

    /* ----- Reed-Solomon en GF(256), polinomio 0x11D ----- */

    private static function prepararGaloise(): void
    {
        if (self::$exp !== []) {
            return;
        }
        $x = 1;
        for ($i = 0; $i < 255; $i++) {
            self::$exp[$i] = $x;
            self::$log[$x] = $i;
            $x <<= 1;
            if ($x & 0x100) {
                $x ^= 0x11D;
            }
        }
        for ($i = 255; $i < 512; $i++) {
            self::$exp[$i] = self::$exp[$i - 255];
        }
    }

    private static function multiplicar(int $a, int $b): int
    {
        if ($a === 0 || $b === 0) {
            return 0;
        }
        return self::$exp[self::$log[$a] + self::$log[$b]];
    }

    /** Polinomio generador de grado $grado (coeficientes de mayor a menor). */
    private static function generador(int $grado): array
    {
        self::prepararGaloise();
        $g = [1];
        for ($i = 0; $i < $grado; $i++) {
            $nuevo = array_fill(0, count($g) + 1, 0);
            foreach ($g as $j => $coeficiente) {
                $nuevo[$j] ^= $coeficiente;
                $nuevo[$j + 1] ^= self::multiplicar($coeficiente, self::$exp[$i]);
            }
            $g = $nuevo;
        }
        return $g;
    }

    private static function codigosCorreccion(array $bloque, array $generador, int $grado): array
    {
        $resto = array_merge($bloque, array_fill(0, $grado, 0));
        $n = count($bloque);
        for ($i = 0; $i < $n; $i++) {
            $factor = $resto[$i];
            if ($factor === 0) {
                continue;
            }
            foreach ($generador as $j => $coeficiente) {
                $resto[$i + $j] ^= self::multiplicar($coeficiente, $factor);
            }
        }
        return array_slice($resto, $n);
    }

    /* ----- Construcción de la matriz ----- */

    /** Devuelve [matriz con patrones fijos, matriz de módulos reservados]. */
    private static function patronesFijos(int $version, int $lado): array
    {
        $m = array_fill(0, $lado, array_fill(0, $lado, 0));
        $r = array_fill(0, $lado, array_fill(0, $lado, false));
        $finder = static function (int $fila, int $col) use (&$m, &$r, $lado): void {
            for ($i = -1; $i <= 7; $i++) {
                for ($j = -1; $j <= 7; $j++) {
                    $y = $fila + $i;
                    $x = $col + $j;
                    if ($y < 0 || $x < 0 || $y >= $lado || $x >= $lado) {
                        continue;
                    }
                    $dentro = $i >= 0 && $i <= 6 && $j >= 0 && $j <= 6;
                    $negro = $dentro && (
                        $i === 0 || $i === 6 || $j === 0 || $j === 6 ||
                        ($i >= 2 && $i <= 4 && $j >= 2 && $j <= 4)
                    );
                    $m[$y][$x] = $negro ? 1 : 0;
                    $r[$y][$x] = true;
                }
            }
        };
        $finder(0, 0);
        $finder(0, $lado - 7);
        $finder($lado - 7, 0);
        /* Patrones de temporización. */
        for ($i = 8; $i < $lado - 8; $i++) {
            $m[6][$i] = $m[$i][6] = ($i % 2 === 0) ? 1 : 0;
            $r[6][$i] = $r[$i][6] = true;
        }
        /* Alineamiento. */
        $posiciones = self::ALINEAMIENTO[$version] ?? [];
        foreach ($posiciones as $fila) {
            foreach ($posiciones as $col) {
                /* Se omiten solo los tres que caerían sobre los patrones de
                   posición; los que cruzan la temporización sí se dibujan. */
                if (($fila <= 8 && $col <= 8) || ($fila <= 8 && $col >= $lado - 9) ||
                    ($fila >= $lado - 9 && $col <= 8)) {
                    continue;
                }
                for ($i = -2; $i <= 2; $i++) {
                    for ($j = -2; $j <= 2; $j++) {
                        $negro = max(abs($i), abs($j)) !== 1;
                        $m[$fila + $i][$col + $j] = $negro ? 1 : 0;
                        $r[$fila + $i][$col + $j] = true;
                    }
                }
            }
        }
        /* Zonas de formato (se rellenan después), módulo oscuro y versión. */
        for ($i = 0; $i < 9; $i++) {
            $r[8][$i] = true;
            $r[$i][8] = true;
        }
        for ($i = 0; $i < 8; $i++) {
            $r[8][$lado - 1 - $i] = true;
            $r[$lado - 1 - $i][8] = true;
        }
        $m[$lado - 8][8] = 1;
        if ($version >= 7) {
            for ($i = 0; $i < 6; $i++) {
                for ($j = 0; $j < 3; $j++) {
                    $r[$i][$lado - 11 + $j] = true;
                    $r[$lado - 11 + $j][$i] = true;
                }
            }
        }
        return [$m, $r];
    }

    private static function colocarDatos(array &$m, array $r, array $codewords, int $lado): void
    {
        $bits = '';
        foreach ($codewords as $codeword) {
            $bits .= str_pad(decbin($codeword), 8, '0', STR_PAD_LEFT);
        }
        $total = strlen($bits);
        $indice = 0;
        $haciaArriba = true;
        for ($col = $lado - 1; $col > 0; $col -= 2) {
            if ($col === 6) {
                $col--;
            }
            for ($paso = 0; $paso < $lado; $paso++) {
                $fila = $haciaArriba ? $lado - 1 - $paso : $paso;
                for ($c = 0; $c < 2; $c++) {
                    $x = $col - $c;
                    if ($r[$fila][$x]) {
                        continue;
                    }
                    $m[$fila][$x] = ($indice < $total && $bits[$indice] === '1') ? 1 : 0;
                    $indice++;
                }
            }
            $haciaArriba = !$haciaArriba;
        }
    }

    private static function aplicarMascara(array $m, array $r, int $mascara, int $lado): array
    {
        for ($i = 0; $i < $lado; $i++) {
            for ($j = 0; $j < $lado; $j++) {
                if ($r[$i][$j]) {
                    continue;
                }
                $invertir = match ($mascara) {
                    0 => ($i + $j) % 2 === 0,
                    1 => $i % 2 === 0,
                    2 => $j % 3 === 0,
                    3 => ($i + $j) % 3 === 0,
                    4 => (intdiv($i, 2) + intdiv($j, 3)) % 2 === 0,
                    5 => (($i * $j) % 2) + (($i * $j) % 3) === 0,
                    6 => ((($i * $j) % 2) + (($i * $j) % 3)) % 2 === 0,
                    default => ((($i + $j) % 2) + (($i * $j) % 3)) % 2 === 0,
                };
                if ($invertir) {
                    $m[$i][$j] ^= 1;
                }
            }
        }
        return $m;
    }

    private static function bch(int $valor, int $polinomio, int $bitsDatos, int $bitsTotal): int
    {
        $resto = $valor << ($bitsTotal - $bitsDatos);
        $gradoPolinomio = (int)floor(log($polinomio, 2));
        for ($i = $bitsTotal - 1; $i >= $bitsTotal - $bitsDatos; $i--) {
            if ($resto & (1 << $i)) {
                $resto ^= $polinomio << ($i - $gradoPolinomio);
            }
        }
        return ($valor << ($bitsTotal - $bitsDatos)) | $resto;
    }

    private static function escribirFormato(array &$m, int $mascara, int $lado): void
    {
        /* Nivel M = 00. */
        $formato = self::bch($mascara, 0x537, 5, 15) ^ 0x5412;
        for ($i = 0; $i < 15; $i++) {
            $bit = ($formato >> $i) & 1;
            /* Columna 8 (vertical): junto al patrón superior izquierdo y,
               para los bits altos, junto al inferior izquierdo. */
            if ($i < 6) {
                $m[$i][8] = $bit;
            } elseif ($i < 8) {
                $m[$i + 1][8] = $bit;
            } else {
                $m[$lado - 15 + $i][8] = $bit;
            }
            /* Fila 8 (horizontal): junto al patrón superior derecho y,
               para los bits altos, junto al superior izquierdo (salta la
               columna 6 del patrón de temporización). */
            if ($i < 8) {
                $m[8][$lado - 1 - $i] = $bit;
            } elseif ($i === 8) {
                $m[8][7] = $bit;
            } else {
                $m[8][14 - $i] = $bit;
            }
        }
        $m[$lado - 8][8] = 1;
    }

    private static function escribirVersion(array &$m, int $version, int $lado): void
    {
        $info = self::bch($version, 0x1F25, 6, 18);
        for ($i = 0; $i < 18; $i++) {
            $bit = ($info >> $i) & 1;
            $m[intdiv($i, 3)][$lado - 11 + $i % 3] = $bit;
            $m[$lado - 11 + $i % 3][intdiv($i, 3)] = $bit;
        }
    }

    private static function penalizacion(array $m, int $lado): int
    {
        $total = 0;
        /* Regla 1: rachas de 5 o más módulos iguales en filas y columnas. */
        for ($i = 0; $i < $lado; $i++) {
            foreach ([true, false] as $porFilas) {
                $racha = 0;
                $anterior = -1;
                for ($j = 0; $j < $lado; $j++) {
                    $valor = $porFilas ? $m[$i][$j] : $m[$j][$i];
                    if ($valor === $anterior) {
                        $racha++;
                    } else {
                        if ($racha >= 5) {
                            $total += 3 + $racha - 5;
                        }
                        $racha = 1;
                        $anterior = $valor;
                    }
                }
                if ($racha >= 5) {
                    $total += 3 + $racha - 5;
                }
            }
        }
        /* Regla 2: bloques 2x2 del mismo color. */
        for ($i = 0; $i < $lado - 1; $i++) {
            for ($j = 0; $j < $lado - 1; $j++) {
                $v = $m[$i][$j];
                if ($v === $m[$i][$j + 1] && $v === $m[$i + 1][$j] && $v === $m[$i + 1][$j + 1]) {
                    $total += 3;
                }
            }
        }
        /* Regla 3: patrones 1011101 con 4 blancos a un lado. */
        $patronA = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
        $patronB = [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1];
        for ($i = 0; $i < $lado; $i++) {
            for ($j = 0; $j <= $lado - 11; $j++) {
                $coincideA = $coincideB = $coincideC = $coincideD = true;
                for ($k = 0; $k < 11 && ($coincideA || $coincideB || $coincideC || $coincideD); $k++) {
                    $fila = $m[$i][$j + $k];
                    $columna = $m[$j + $k][$i];
                    $coincideA = $coincideA && $fila === $patronA[$k];
                    $coincideB = $coincideB && $fila === $patronB[$k];
                    $coincideC = $coincideC && $columna === $patronA[$k];
                    $coincideD = $coincideD && $columna === $patronB[$k];
                }
                $total += 40 * ((int)$coincideA + (int)$coincideB + (int)$coincideC + (int)$coincideD);
            }
        }
        /* Regla 4: proporción de módulos oscuros. */
        $oscuros = 0;
        foreach ($m as $fila) {
            $oscuros += array_sum($fila);
        }
        $porcentaje = $oscuros * 100 / ($lado * $lado);
        $total += 10 * (int)floor(abs($porcentaje - 50) / 5);
        return $total;
    }
}
