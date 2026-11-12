<?php
declare(strict_types=1);

/*
 * Generador de PDF mínimo sin dependencias: fuentes estándar Helvetica y
 * Helvetica-Bold (o Courier y Courier-Bold, para los tickets) con
 * codificación WinAnsi (acentos, ñ y €), texto alineado, ajuste de línea,
 * rectángulos y líneas.
 * El tamaño de página se fija al construir el documento: A4 por defecto
 * (595 x 842) o el que se indique, como el papel continuo de 80 mm del
 * ticket. Las coordenadas públicas se dan desde la esquina superior
 * izquierda en puntos (1 punto = 1/72 pulgada).
 */

final class PdfMinimo
{
    public const ANCHO = 595.28;
    public const ALTO = 841.89;

    /** Anchos de Helvetica (WinAnsi, códigos 32..255) en milésimas de em. */
    private const ANCHOS_NORMAL = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584, 350,
        556, 350, 222, 556, 333, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,
        350, 222, 222, 333, 333, 350, 556, 1000, 333, 1000, 500, 333, 944, 350, 500, 667,
        278, 333, 556, 556, 556, 556, 260, 556, 333, 737, 370, 556, 584, 333, 737, 333,
        400, 584, 333, 333, 333, 556, 537, 278, 333, 333, 365, 556, 834, 834, 834, 611,
        667, 667, 667, 667, 667, 667, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
        722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
        556, 556, 556, 556, 556, 556, 889, 500, 556, 556, 556, 556, 278, 278, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 584, 611, 556, 556, 556, 556, 500, 556, 500,
    ];

    /** Anchos de Helvetica-Bold (WinAnsi, códigos 32..255). */
    private const ANCHOS_NEGRITA = [
        278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
        975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
        333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
        611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584, 350,
        556, 350, 278, 556, 500, 1000, 556, 556, 333, 1000, 667, 333, 1000, 350, 611, 350,
        350, 278, 278, 500, 500, 350, 556, 1000, 333, 1000, 556, 333, 944, 350, 500, 667,
        278, 333, 556, 556, 556, 556, 280, 556, 333, 737, 370, 556, 584, 333, 737, 333,
        400, 584, 333, 333, 333, 611, 556, 278, 333, 333, 365, 556, 834, 834, 834, 611,
        722, 722, 722, 722, 722, 722, 1000, 722, 667, 667, 667, 667, 278, 278, 278, 278,
        722, 722, 778, 778, 778, 778, 778, 584, 778, 722, 722, 722, 722, 667, 667, 611,
        556, 556, 556, 556, 556, 556, 889, 556, 556, 556, 556, 556, 278, 278, 278, 278,
        611, 611, 611, 611, 611, 611, 611, 584, 611, 611, 611, 611, 611, 556, 611, 556,
    ];

    /** Courier y Courier-Bold son monoespaciadas: 600 milésimas de em. */
    private const ANCHO_MONOESPACIADO = 600;

    /** Fuentes estándar de cada familia: [normal, negrita]. */
    private const FAMILIAS = [
        'helvetica' => ['Helvetica', 'Helvetica-Bold'],
        'courier'   => ['Courier', 'Courier-Bold'],
    ];

    /** @var string[] contenido de cada página */
    private array $paginas = [];
    private string $actual = '';
    private string $fuente = 'F1';
    private float $tamano = 10.0;
    private float $ancho;
    private float $alto;
    private string $familia;

    /**
     * $familia: 'helvetica' (facturas A4) o 'courier' (tickets, donde las
     * columnas se cuadran contando caracteres como en la impresora térmica).
     */
    public function __construct(
        float $ancho = self::ANCHO,
        float $alto = self::ALTO,
        string $familia = 'helvetica'
    ) {
        $this->ancho = $ancho;
        $this->alto = $alto;
        $this->familia = isset(self::FAMILIAS[$familia]) ? $familia : 'helvetica';
    }

    public function anchoPagina(): float
    {
        return $this->ancho;
    }

    public function altoPagina(): float
    {
        return $this->alto;
    }

    public function nuevaPagina(): void
    {
        if ($this->actual !== '' || $this->paginas === []) {
            if ($this->actual !== '') {
                $this->paginas[] = $this->actual;
            }
        }
        $this->actual = '';
        $this->fuente = 'F1';
        $this->tamano = 10.0;
    }

    public function numeroPagina(): int
    {
        return count($this->paginas) + 1;
    }

    public function fuente(bool $negrita, float $tamano): void
    {
        $this->fuente = $negrita ? 'F2' : 'F1';
        $this->tamano = $tamano;
        $this->actual .= sprintf("BT /%s %s Tf ET\n", $this->fuente, self::num($tamano));
    }

    /** Ancho en puntos de un texto con la fuente y tamaño actuales. */
    public function anchoTexto(string $texto, ?bool $negrita = null, ?float $tamano = null): float
    {
        $negrita ??= $this->fuente === 'F2';
        $tamano ??= $this->tamano;
        $bytes = self::codificar($texto);
        if ($this->familia === 'courier') {
            return strlen($bytes) * self::ANCHO_MONOESPACIADO * $tamano / 1000;
        }
        $anchos = $negrita ? self::ANCHOS_NEGRITA : self::ANCHOS_NORMAL;
        $total = 0;
        $largo = strlen($bytes);
        for ($i = 0; $i < $largo; $i++) {
            $codigo = ord($bytes[$i]);
            $total += $anchos[max(0, $codigo - 32)] ?? 556;
        }
        return $total * $tamano / 1000;
    }

    /**
     * Escribe texto en (x, y) medido desde arriba. $alineacion: 'I', 'D' o 'C'.
     * Devuelve el ancho del texto.
     */
    public function texto(float $x, float $y, string $texto, string $alineacion = 'I', ?float $ancho = null): float
    {
        $anchoTexto = $this->anchoTexto($texto);
        if ($alineacion === 'D') {
            $x = $x + ($ancho ?? 0) - $anchoTexto;
        } elseif ($alineacion === 'C') {
            $x = $x + (($ancho ?? 0) - $anchoTexto) / 2;
        }
        $this->actual .= sprintf(
            "BT /%s %s Tf %s %s Td (%s) Tj ET\n",
            $this->fuente,
            self::num($this->tamano),
            self::num($x),
            self::num($this->alto - $y),
            self::escapar(self::codificar($texto))
        );
        return $anchoTexto;
    }

    /** Parte un texto en líneas que quepan en $ancho (por palabras). */
    public function partirTexto(string $texto, float $ancho): array
    {
        $lineas = [];
        foreach (preg_split('/\r\n|\r|\n/', $texto) as $parrafo) {
            $palabras = preg_split('/\s+/', trim($parrafo)) ?: [];
            $lineaActual = '';
            foreach ($palabras as $palabra) {
                if ($palabra === '') {
                    continue;
                }
                $candidata = $lineaActual === '' ? $palabra : $lineaActual . ' ' . $palabra;
                if ($this->anchoTexto($candidata) <= $ancho) {
                    $lineaActual = $candidata;
                    continue;
                }
                if ($lineaActual !== '') {
                    $lineas[] = $lineaActual;
                }
                /* Palabra más larga que el ancho: se trocea por caracteres. */
                $lineaActual = '';
                $trozo = '';
                foreach (preg_split('//u', $palabra, -1, PREG_SPLIT_NO_EMPTY) as $caracter) {
                    if ($this->anchoTexto($trozo . $caracter) > $ancho && $trozo !== '') {
                        $lineas[] = $trozo;
                        $trozo = '';
                    }
                    $trozo .= $caracter;
                }
                $lineaActual = $trozo;
            }
            $lineas[] = $lineaActual;
        }
        return $lineas === [] ? [''] : $lineas;
    }

    /** Texto multilínea; devuelve el número de líneas escritas. */
    public function parrafo(float $x, float $y, float $ancho, string $texto, float $interlineado): int
    {
        $lineas = $this->partirTexto($texto, $ancho);
        foreach ($lineas as $i => $linea) {
            $this->texto($x, $y + $i * $interlineado, $linea);
        }
        return count($lineas);
    }

    public function rectangulo(float $x, float $y, float $ancho, float $alto, float $grosor = 0.6): void
    {
        $this->actual .= sprintf(
            "%s w %s %s %s %s re S\n",
            self::num($grosor),
            self::num($x),
            self::num($this->alto - $y - $alto),
            self::num($ancho),
            self::num($alto)
        );
    }

    /**
     * Dibuja una matriz de módulos (código QR: filas de 0/1) rellena de negro
     * en un cuadrado de $lado puntos cuya esquina superior izquierda es (x, y).
     * Los módulos contiguos de cada fila se agrupan en un solo rectángulo.
     */
    public function qr(float $x, float $y, float $lado, array $matriz): void
    {
        $n = count($matriz);
        if ($n === 0) {
            return;
        }
        $modulo = $lado / $n;
        $operaciones = "q 0 g\n";
        foreach ($matriz as $i => $fila) {
            $j = 0;
            while ($j < $n) {
                if (empty($fila[$j])) {
                    $j++;
                    continue;
                }
                $inicio = $j;
                while ($j < $n && !empty($fila[$j])) {
                    $j++;
                }
                $operaciones .= sprintf(
                    "%s %s %s %s re f\n",
                    self::num($x + $inicio * $modulo),
                    self::num($this->alto - $y - ($i + 1) * $modulo),
                    self::num(($j - $inicio) * $modulo),
                    self::num($modulo * 1.02)
                );
            }
        }
        $this->actual .= $operaciones . "Q\n";
    }

    public function linea(float $x1, float $y1, float $x2, float $y2, float $grosor = 0.6): void
    {
        $this->actual .= sprintf(
            "%s w %s %s m %s %s l S\n",
            self::num($grosor),
            self::num($x1),
            self::num($this->alto - $y1),
            self::num($x2),
            self::num($this->alto - $y2)
        );
    }

    /** Devuelve el fichero PDF completo. */
    public function generar(string $titulo = ''): string
    {
        if ($this->actual !== '' || $this->paginas === []) {
            $this->paginas[] = $this->actual;
            $this->actual = '';
        }
        $objetos = [];
        $objetos[] = '<< /Type /Catalog /Pages 2 0 R >>';
        $numPaginas = count($this->paginas);
        $refs = [];
        for ($i = 0; $i < $numPaginas; $i++) {
            $refs[] = (5 + $i * 2) . ' 0 R';
        }
        $objetos[] = '<< /Type /Pages /Kids [' . implode(' ', $refs) . '] /Count ' . $numPaginas . ' >>';
        [$normal, $negrita] = self::FAMILIAS[$this->familia];
        $objetos[] = '<< /Type /Font /Subtype /Type1 /BaseFont /' . $normal . ' /Encoding /WinAnsiEncoding >>';
        $objetos[] = '<< /Type /Font /Subtype /Type1 /BaseFont /' . $negrita . ' /Encoding /WinAnsiEncoding >>';
        foreach ($this->paginas as $i => $contenido) {
            $numContenido = 6 + $i * 2;
            $objetos[] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' . self::num($this->ancho) . ' ' .
                self::num($this->alto) . '] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ' .
                $numContenido . ' 0 R >>';
            $flujo = $contenido;
            $filtro = '';
            if (function_exists('gzcompress')) {
                $flujo = gzcompress($contenido, 6);
                $filtro = ' /Filter /FlateDecode';
            }
            $objetos[] = '<< /Length ' . strlen($flujo) . $filtro . " >>\nstream\n" . $flujo . "\nendstream";
        }
        $info = '<< /Producer (ViraCash facturacion web) /Creator (ViraCash)';
        if ($titulo !== '') {
            $info .= ' /Title (' . self::escapar(self::codificar($titulo)) . ')';
        }
        $info .= ' /CreationDate (D:' . date('YmdHis') . ') >>';
        $objetos[] = $info;

        $salida = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
        $posiciones = [];
        foreach ($objetos as $indice => $objeto) {
            $posiciones[] = strlen($salida);
            $salida .= ($indice + 1) . " 0 obj\n" . $objeto . "\nendobj\n";
        }
        $xref = strlen($salida);
        $salida .= 'xref' . "\n0 " . (count($objetos) + 1) . "\n0000000000 65535 f \n";
        foreach ($posiciones as $posicion) {
            $salida .= sprintf("%010d 00000 n \n", $posicion);
        }
        $salida .= "trailer\n<< /Size " . (count($objetos) + 1) . ' /Root 1 0 R /Info ' . count($objetos) .
            " 0 R >>\nstartxref\n" . $xref . "\n%%EOF\n";
        return $salida;
    }

    private static function num(float $valor): string
    {
        return rtrim(rtrim(number_format($valor, 3, '.', ''), '0'), '.');
    }

    private static function codificar(string $texto): string
    {
        $convertido = @iconv('UTF-8', 'Windows-1252//TRANSLIT', $texto);
        if ($convertido === false) {
            $convertido = @iconv('UTF-8', 'Windows-1252//IGNORE', $texto);
        }
        return $convertido === false ? preg_replace('/[^\x20-\x7E]/', '?', $texto) ?? '' : $convertido;
    }

    private static function escapar(string $bytes): string
    {
        return str_replace(['\\', '(', ')', "\r", "\n"], ['\\\\', '\\(', '\\)', '\\r', '\\n'], $bytes);
    }
}
