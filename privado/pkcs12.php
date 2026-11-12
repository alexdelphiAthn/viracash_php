<?php
declare(strict_types=1);

/*
 * Lector de ficheros PKCS#12 (.pfx / .p12) en PHP puro, para cuando
 * openssl_pkcs12_read() no puede abrirlos: los certificados exportados desde
 * el almacén de Windows (FNMT y similares) cifran con RC2-40 y 3DES, que
 * OpenSSL 3 relega al proveedor "legacy" y PHP no carga. Se parsea el DER,
 * se comprueba el MAC con la contraseña y se descifran los bolsos con las
 * derivaciones de clave de PKCS#12 (RFC 7292), RC2 (RFC 2268), 3DES y PBES2.
 * Devuelve el certificado, la clave privada (PKCS#8 en PEM) y la cadena.
 */

final class LectorPkcs12
{
    private const OID_DATA = '1.2.840.113549.1.7.1';
    private const OID_ENCRYPTED_DATA = '1.2.840.113549.1.7.6';
    private const OID_CERT_BAG = '1.2.840.113549.1.12.10.1.3';
    private const OID_KEY_BAG = '1.2.840.113549.1.12.10.1.1';
    private const OID_SHROUDED_KEY_BAG = '1.2.840.113549.1.12.10.1.2';
    private const OID_X509_CERT = '1.2.840.113549.1.9.22.1';
    private const OID_PBE_SHA1_RC2_128 = '1.2.840.113549.1.12.1.5';
    private const OID_PBE_SHA1_RC2_40 = '1.2.840.113549.1.12.1.6';
    private const OID_PBE_SHA1_3DES = '1.2.840.113549.1.12.1.3';
    private const OID_PBE_SHA1_2DES = '1.2.840.113549.1.12.1.4';
    private const OID_PBES2 = '1.2.840.113549.1.5.13';
    private const OID_PBKDF2 = '1.2.840.113549.1.5.12';
    private const OID_SHA1 = '1.3.14.3.2.26';
    private const OID_SHA256 = '2.16.840.1.101.3.4.2.1';
    private const OID_SHA384 = '2.16.840.1.101.3.4.2.2';
    private const OID_SHA512 = '2.16.840.1.101.3.4.2.3';
    private const CIFRADOS_PBES2 = [
        '2.16.840.1.101.3.4.1.2'  => ['aes-128-cbc', 16],
        '2.16.840.1.101.3.4.1.22' => ['aes-192-cbc', 24],
        '2.16.840.1.101.3.4.1.42' => ['aes-256-cbc', 32],
        '1.2.840.113549.3.7'      => ['des-ede3-cbc', 24],
    ];
    private const PRF_PBKDF2 = [
        '1.2.840.113549.2.7'  => 'sha1',
        '1.2.840.113549.2.8'  => 'sha224',
        '1.2.840.113549.2.9'  => 'sha256',
        '1.2.840.113549.2.10' => 'sha384',
        '1.2.840.113549.2.11' => 'sha512',
    ];

    /** Tabla PITABLE de RC2 (RFC 2268). */
    private const RC2_PITABLE = [
        0xd9, 0x78, 0xf9, 0xc4, 0x19, 0xdd, 0xb5, 0xed, 0x28, 0xe9, 0xfd, 0x79, 0x4a, 0xa0, 0xd8, 0x9d,
        0xc6, 0x7e, 0x37, 0x83, 0x2b, 0x76, 0x53, 0x8e, 0x62, 0x4c, 0x64, 0x88, 0x44, 0x8b, 0xfb, 0xa2,
        0x17, 0x9a, 0x59, 0xf5, 0x87, 0xb3, 0x4f, 0x13, 0x61, 0x45, 0x6d, 0x8d, 0x09, 0x81, 0x7d, 0x32,
        0xbd, 0x8f, 0x40, 0xeb, 0x86, 0xb7, 0x7b, 0x0b, 0xf0, 0x95, 0x21, 0x22, 0x5c, 0x6b, 0x4e, 0x82,
        0x54, 0xd6, 0x65, 0x93, 0xce, 0x60, 0xb2, 0x1c, 0x73, 0x56, 0xc0, 0x14, 0xa7, 0x8c, 0xf1, 0xdc,
        0x12, 0x75, 0xca, 0x1f, 0x3b, 0xbe, 0xe4, 0xd1, 0x42, 0x3d, 0xd4, 0x30, 0xa3, 0x3c, 0xb6, 0x26,
        0x6f, 0xbf, 0x0e, 0xda, 0x46, 0x69, 0x07, 0x57, 0x27, 0xf2, 0x1d, 0x9b, 0xbc, 0x94, 0x43, 0x03,
        0xf8, 0x11, 0xc7, 0xf6, 0x90, 0xef, 0x3e, 0xe7, 0x06, 0xc3, 0xd5, 0x2f, 0xc8, 0x66, 0x1e, 0xd7,
        0x08, 0xe8, 0xea, 0xde, 0x80, 0x52, 0xee, 0xf7, 0x84, 0xaa, 0x72, 0xac, 0x35, 0x4d, 0x6a, 0x2a,
        0x96, 0x1a, 0xd2, 0x71, 0x5a, 0x15, 0x49, 0x74, 0x4b, 0x9f, 0xd0, 0x5e, 0x04, 0x18, 0xa4, 0xec,
        0xc2, 0xe0, 0x41, 0x6e, 0x0f, 0x51, 0xcb, 0xcc, 0x24, 0x91, 0xaf, 0x50, 0xa1, 0xf4, 0x70, 0x39,
        0x99, 0x7c, 0x3a, 0x85, 0x23, 0xb8, 0xb4, 0x7a, 0xfc, 0x02, 0x36, 0x5b, 0x25, 0x55, 0x97, 0x31,
        0x2d, 0x5d, 0xfa, 0x98, 0xe3, 0x8a, 0x92, 0xae, 0x05, 0xdf, 0x29, 0x10, 0x67, 0x6c, 0xba, 0xc9,
        0xd3, 0x00, 0xe6, 0xcf, 0xe1, 0x9e, 0xa8, 0x2c, 0x63, 0x16, 0x01, 0x3f, 0x58, 0xe2, 0x89, 0xa9,
        0x0d, 0x38, 0x34, 0x1b, 0xab, 0x33, 0xff, 0xb0, 0xbb, 0x48, 0x0c, 0x5f, 0xb9, 0xb1, 0xcd, 0x2e,
        0xc5, 0xf3, 0xdb, 0x47, 0xe5, 0xa5, 0x9c, 0x77, 0x0a, 0xa6, 0x20, 0x68, 0xfe, 0x7f, 0xc1, 0xad,
    ];

    /**
     * Lee un PKCS#12. Devuelve ['cert' => PEM, 'pkey' => PEM PKCS#8,
     * 'extracerts' => [PEM...]] como openssl_pkcs12_read(). Lanza excepción
     * con un mensaje en castellano si la contraseña no es válida o el
     * formato no se reconoce.
     */
    public static function leer(string $datos, string $contrasena): array
    {
        $pfx = self::decodificar($datos);
        self::exigir($pfx['tag'] === 0x30 && count($pfx['hijos']) >= 2, 'El fichero no es un PKCS#12.');
        $authSafe = $pfx['hijos'][1];
        self::exigir(self::oid($authSafe['hijos'][0]) === self::OID_DATA,
            'El PKCS#12 no lleva los datos en claro (solo se admite authSafe de tipo data).');
        $contenidoAuthSafe = self::octetos($authSafe['hijos'][1]['hijos'][0]);
        if (isset($pfx['hijos'][2])) {
            self::comprobarMac($pfx['hijos'][2], $contenidoAuthSafe, $contrasena);
        }
        $certificados = [];
        $claves = [];
        $autenticado = self::decodificar($contenidoAuthSafe);
        foreach ($autenticado['hijos'] as $contentInfo) {
            $tipo = self::oid($contentInfo['hijos'][0]);
            if ($tipo === self::OID_DATA) {
                $safeContents = self::octetos($contentInfo['hijos'][1]['hijos'][0]);
            } elseif ($tipo === self::OID_ENCRYPTED_DATA) {
                $encryptedData = $contentInfo['hijos'][1]['hijos'][0];
                $info = $encryptedData['hijos'][1];
                $algoritmo = $info['hijos'][1];
                $cifrado = self::contenido($info['hijos'][2]);
                $safeContents = self::descifrar($algoritmo, $cifrado, $contrasena);
            } else {
                continue;
            }
            self::leerBolsos(self::decodificar($safeContents), $contrasena, $certificados, $claves);
        }
        self::exigir($claves !== [], 'El PKCS#12 no contiene ninguna clave privada.');
        self::exigir($certificados !== [], 'El PKCS#12 no contiene ningún certificado.');
        $clavePem = self::pem('PRIVATE KEY', $claves[0]);
        $clave = openssl_pkey_get_private($clavePem);
        self::exigir($clave !== false, 'La clave privada del PKCS#12 no se ha podido interpretar.');
        $principal = null;
        $resto = [];
        foreach ($certificados as $der) {
            $certPem = self::pem('CERTIFICATE', $der);
            if ($principal === null && openssl_x509_check_private_key($certPem, $clave)) {
                $principal = $certPem;
            } else {
                $resto[] = $certPem;
            }
        }
        self::exigir($principal !== null, 'Ningún certificado del PKCS#12 corresponde a la clave privada.');
        return ['cert' => $principal, 'pkey' => $clavePem, 'extracerts' => $resto];
    }

    /* ===================== Bolsos ===================== */

    private static function leerBolsos(array $safeContents, string $contrasena, array &$certificados, array &$claves): void
    {
        foreach ($safeContents['hijos'] as $bolso) {
            $tipo = self::oid($bolso['hijos'][0]);
            $valor = $bolso['hijos'][1]['hijos'][0];
            if ($tipo === self::OID_CERT_BAG) {
                if (self::oid($valor['hijos'][0]) === self::OID_X509_CERT) {
                    $certificados[] = self::octetos($valor['hijos'][1]['hijos'][0]);
                }
            } elseif ($tipo === self::OID_KEY_BAG) {
                $claves[] = self::der($valor);
            } elseif ($tipo === self::OID_SHROUDED_KEY_BAG) {
                $claves[] = self::descifrar($valor['hijos'][0], self::octetos($valor['hijos'][1]), $contrasena);
            }
        }
    }

    /* ===================== Cifrados ===================== */

    private static function descifrar(array $algoritmo, string $cifrado, string $contrasena): string
    {
        $oid = self::oid($algoritmo['hijos'][0]);
        $parametros = $algoritmo['hijos'][1] ?? null;
        switch ($oid) {
            case self::OID_PBE_SHA1_RC2_40:
            case self::OID_PBE_SHA1_RC2_128:
                [$sal, $iteraciones] = self::parametrosPbe($parametros);
                $bits = $oid === self::OID_PBE_SHA1_RC2_40 ? 40 : 128;
                $clave = self::kdfPkcs12($contrasena, $sal, $iteraciones, 1, intdiv($bits, 8), 'sha1');
                $iv = self::kdfPkcs12($contrasena, $sal, $iteraciones, 2, 8, 'sha1');
                return self::quitarRelleno(self::rc2Cbc($cifrado, $clave, $bits, $iv));
            case self::OID_PBE_SHA1_3DES:
            case self::OID_PBE_SHA1_2DES:
                [$sal, $iteraciones] = self::parametrosPbe($parametros);
                $longitud = $oid === self::OID_PBE_SHA1_3DES ? 24 : 16;
                $clave = self::kdfPkcs12($contrasena, $sal, $iteraciones, 1, $longitud, 'sha1');
                if ($longitud === 16) {
                    $clave .= substr($clave, 0, 8);
                }
                $iv = self::kdfPkcs12($contrasena, $sal, $iteraciones, 2, 8, 'sha1');
                $claro = openssl_decrypt($cifrado, 'des-ede3-cbc', $clave, OPENSSL_RAW_DATA, $iv);
                self::exigir($claro !== false, 'Contraseña incorrecta (3DES).');
                return $claro;
            case self::OID_PBES2:
                return self::descifrarPbes2($parametros, $cifrado, $contrasena);
        }
        throw new RuntimeException("Algoritmo de cifrado del PKCS#12 no soportado ($oid).");
    }

    private static function parametrosPbe(?array $parametros): array
    {
        self::exigir($parametros !== null && count($parametros['hijos']) >= 2, 'Parámetros PBE incompletos.');
        return [self::octetos($parametros['hijos'][0]), self::entero($parametros['hijos'][1])];
    }

    private static function descifrarPbes2(?array $parametros, string $cifrado, string $contrasena): string
    {
        self::exigir($parametros !== null, 'Parámetros PBES2 ausentes.');
        $kdf = $parametros['hijos'][0];
        $esquema = $parametros['hijos'][1];
        self::exigir(self::oid($kdf['hijos'][0]) === self::OID_PBKDF2, 'PBES2 sin PBKDF2.');
        $kdfParametros = $kdf['hijos'][1];
        $sal = self::octetos($kdfParametros['hijos'][0]);
        $iteraciones = self::entero($kdfParametros['hijos'][1]);
        $prf = 'sha1';
        foreach (array_slice($kdfParametros['hijos'], 2) as $extra) {
            if ($extra['tag'] === 0x30) {
                $prf = self::PRF_PBKDF2[self::oid($extra['hijos'][0])] ?? 'sha1';
            }
        }
        $oidCifrado = self::oid($esquema['hijos'][0]);
        self::exigir(isset(self::CIFRADOS_PBES2[$oidCifrado]), "Cifrado PBES2 no soportado ($oidCifrado).");
        [$metodo, $longitud] = self::CIFRADOS_PBES2[$oidCifrado];
        $iv = self::octetos($esquema['hijos'][1]);
        $clave = hash_pbkdf2($prf, $contrasena, $sal, $iteraciones, $longitud, true);
        $claro = openssl_decrypt($cifrado, $metodo, $clave, OPENSSL_RAW_DATA, $iv);
        self::exigir($claro !== false, 'Contraseña incorrecta (PBES2).');
        return $claro;
    }

    private static function quitarRelleno(string $datos): string
    {
        $n = strlen($datos);
        self::exigir($n > 0, 'Contraseña incorrecta (bloque vacío).');
        $relleno = ord($datos[$n - 1]);
        self::exigir($relleno >= 1 && $relleno <= 8 && $relleno <= $n &&
            substr($datos, -$relleno) === str_repeat(chr($relleno), $relleno),
            'Contraseña incorrecta (relleno no válido).');
        return substr($datos, 0, $n - $relleno);
    }

    /* ===================== MAC ===================== */

    private static function comprobarMac(array $macData, string $contenido, string $contrasena): void
    {
        $digestInfo = $macData['hijos'][0];
        $oidHash = self::oid($digestInfo['hijos'][0]['hijos'][0]);
        $hash = match ($oidHash) {
            self::OID_SHA1 => 'sha1',
            self::OID_SHA256 => 'sha256',
            self::OID_SHA384 => 'sha384',
            self::OID_SHA512 => 'sha512',
            default => null,
        };
        if ($hash === null) {
            return; /* Algoritmo de MAC desconocido: se confía en el descifrado. */
        }
        $esperado = self::octetos($digestInfo['hijos'][1]);
        $sal = self::octetos($macData['hijos'][1]);
        $iteraciones = isset($macData['hijos'][2]) ? self::entero($macData['hijos'][2]) : 1;
        $longitud = strlen(hash($hash, '', true));
        $clave = self::kdfPkcs12($contrasena, $sal, $iteraciones, 3, $longitud, $hash);
        $mac = hash_hmac($hash, $contenido, $clave, true);
        self::exigir(hash_equals($esperado, $mac), 'La contraseña del certificado no es correcta.');
    }

    /* ===================== Derivación de clave PKCS#12 (RFC 7292 B.2) ===================== */

    private static function kdfPkcs12(string $contrasena, string $sal, int $iteraciones, int $id, int $longitud, string $hash): string
    {
        $u = strlen(hash($hash, '', true));
        $v = in_array($hash, ['sha384', 'sha512'], true) ? 128 : 64;
        /* La contraseña va como BMPString: UTF-16BE con terminador nulo. */
        $utf16 = $contrasena === '' ? '' : mb_convert_encoding($contrasena, 'UTF-16BE', 'UTF-8') . "\x00\x00";
        $d = str_repeat(chr($id), $v);
        $s = self::extender($sal, $v);
        $p = self::extender($utf16, $v);
        $i = $s . $p;
        $resultado = '';
        $bloquesI = intdiv(strlen($i), $v);
        while (strlen($resultado) < $longitud) {
            $a = hash($hash, $d . $i, true);
            for ($k = 1; $k < $iteraciones; $k++) {
                $a = hash($hash, $a, true);
            }
            $resultado .= $a;
            if (strlen($resultado) >= $longitud) {
                break;
            }
            $b = self::extender($a, $v);
            for ($j = 0; $j < $bloquesI; $j++) {
                $bloque = substr($i, $j * $v, $v);
                $suma = self::sumarGrande($bloque, $b);
                $i = substr_replace($i, $suma, $j * $v, $v);
            }
        }
        return substr($resultado, 0, $longitud);
    }

    /** Repite $datos hasta cubrir un múltiplo de $v bytes (vacío si $datos vacío). */
    private static function extender(string $datos, int $v): string
    {
        if ($datos === '') {
            return '';
        }
        $bloques = (int)ceil(strlen($datos) / $v);
        return substr(str_repeat($datos, (int)ceil($bloques * $v / strlen($datos))), 0, $bloques * $v);
    }

    /** ($a + $b + 1) módulo 2^(8·v), con $a y $b de la misma longitud. */
    private static function sumarGrande(string $a, string $b): string
    {
        $n = strlen($a);
        $resultado = str_repeat("\x00", $n);
        $acarreo = 1;
        for ($k = $n - 1; $k >= 0; $k--) {
            $suma = ord($a[$k]) + ord($b[$k]) + $acarreo;
            $resultado[$k] = chr($suma & 0xFF);
            $acarreo = $suma >> 8;
        }
        return $resultado;
    }

    /* ===================== RC2 (RFC 2268) ===================== */

    private static function rc2ExpandirClave(string $clave, int $bitsEfectivos): array
    {
        $t = strlen($clave);
        $l = array_values(unpack('C*', $clave));
        $t8 = intdiv($bitsEfectivos + 7, 8);
        $tm = 0xFF >> (8 * $t8 - $bitsEfectivos);
        for ($i = $t; $i < 128; $i++) {
            $l[$i] = self::RC2_PITABLE[($l[$i - 1] + $l[$i - $t]) & 0xFF];
        }
        $l[128 - $t8] = self::RC2_PITABLE[$l[128 - $t8] & $tm];
        for ($i = 127 - $t8; $i >= 0; $i--) {
            $l[$i] = self::RC2_PITABLE[$l[$i + 1] ^ $l[$i + $t8]];
        }
        $k = [];
        for ($i = 0; $i < 64; $i++) {
            $k[$i] = $l[2 * $i] + 256 * $l[2 * $i + 1];
        }
        return $k;
    }

    private static function rc2DescifrarBloque(string $bloque, array $k): string
    {
        $r = array_values(unpack('v4', $bloque));
        $s = [1, 2, 3, 5];
        $j = 63;
        $rMezcla = function () use (&$r, &$j, $k, $s): void {
            for ($i = 3; $i >= 0; $i--) {
                $r[$i] = (($r[$i] >> $s[$i]) | ($r[$i] << (16 - $s[$i]))) & 0xFFFF;
                $r[$i] = ($r[$i] - $k[$j] - ($r[($i + 3) % 4] & $r[($i + 2) % 4]) -
                    ((~$r[($i + 3) % 4]) & $r[($i + 1) % 4])) & 0xFFFF;
                $j--;
            }
        };
        $rMachaque = function () use (&$r, $k): void {
            for ($i = 3; $i >= 0; $i--) {
                $r[$i] = ($r[$i] - $k[$r[($i + 3) % 4] & 63]) & 0xFFFF;
            }
        };
        for ($n = 0; $n < 5; $n++) {
            $rMezcla();
        }
        $rMachaque();
        for ($n = 0; $n < 6; $n++) {
            $rMezcla();
        }
        $rMachaque();
        for ($n = 0; $n < 5; $n++) {
            $rMezcla();
        }
        return pack('v4', ...$r);
    }

    private static function rc2Cbc(string $cifrado, string $clave, int $bitsEfectivos, string $iv): string
    {
        self::exigir(strlen($cifrado) % 8 === 0, 'Datos RC2 con longitud no válida.');
        $k = self::rc2ExpandirClave($clave, $bitsEfectivos);
        $anterior = $iv;
        $claro = '';
        for ($pos = 0; $pos < strlen($cifrado); $pos += 8) {
            $bloque = substr($cifrado, $pos, 8);
            $claro .= self::rc2DescifrarBloque($bloque, $k) ^ $anterior;
            $anterior = $bloque;
        }
        return $claro;
    }

    /** Cifra un bloque RC2 (solo para las pruebas con los vectores del RFC). */
    public static function rc2CifrarBloque(string $bloque, string $clave, int $bitsEfectivos): string
    {
        $k = self::rc2ExpandirClave($clave, $bitsEfectivos);
        $r = array_values(unpack('v4', $bloque));
        $s = [1, 2, 3, 5];
        $j = 0;
        $mezcla = function () use (&$r, &$j, $k, $s): void {
            for ($i = 0; $i < 4; $i++) {
                $r[$i] = ($r[$i] + $k[$j] + ($r[($i + 3) % 4] & $r[($i + 2) % 4]) +
                    ((~$r[($i + 3) % 4]) & $r[($i + 1) % 4])) & 0xFFFF;
                $j++;
                $r[$i] = (($r[$i] << $s[$i]) | ($r[$i] >> (16 - $s[$i]))) & 0xFFFF;
            }
        };
        $machaque = function () use (&$r, $k): void {
            for ($i = 0; $i < 4; $i++) {
                $r[$i] = ($r[$i] + $k[$r[($i + 3) % 4] & 63]) & 0xFFFF;
            }
        };
        for ($n = 0; $n < 5; $n++) {
            $mezcla();
        }
        $machaque();
        for ($n = 0; $n < 6; $n++) {
            $mezcla();
        }
        $machaque();
        for ($n = 0; $n < 5; $n++) {
            $mezcla();
        }
        return pack('v4', ...$r);
    }

    /* ===================== ASN.1 DER ===================== */

    /**
     * Decodifica un elemento DER: ['tag', 'contenido', 'hijos', 'bruto'].
     * Los constructores (SEQUENCE, SET, [n] explícitos) llevan 'hijos'.
     */
    private static function decodificar(string $datos, int &$pos = 0): array
    {
        self::exigir($pos < strlen($datos), 'DER truncado.');
        $inicio = $pos;
        $tag = ord($datos[$pos++]);
        self::exigir(($tag & 0x1F) !== 0x1F, 'Etiqueta DER de varios bytes no soportada.');
        $longitud = ord($datos[$pos++]);
        if ($longitud & 0x80) {
            $bytes = $longitud & 0x7F;
            self::exigir($bytes >= 1 && $bytes <= 4, 'Longitud DER no válida.');
            $longitud = 0;
            for ($i = 0; $i < $bytes; $i++) {
                $longitud = ($longitud << 8) | ord($datos[$pos++]);
            }
        }
        self::exigir($pos + $longitud <= strlen($datos), 'DER truncado.');
        $contenido = substr($datos, $pos, $longitud);
        $pos += $longitud;
        $elemento = [
            'tag' => $tag,
            'contenido' => $contenido,
            'hijos' => [],
            'bruto' => substr($datos, $inicio, $pos - $inicio),
        ];
        if ($tag & 0x20) {
            $sub = 0;
            while ($sub < $longitud) {
                $elemento['hijos'][] = self::decodificar($contenido, $sub);
            }
        }
        return $elemento;
    }

    private static function oid(array $elemento): string
    {
        self::exigir($elemento['tag'] === 0x06, 'Se esperaba un OID.');
        $bytes = array_values(unpack('C*', $elemento['contenido']));
        $primero = $bytes[0];
        $partes = [intdiv($primero, 40), $primero % 40];
        if ($primero >= 80) {
            $partes = [2, $primero - 80];
        }
        $valor = 0;
        for ($i = 1, $n = count($bytes); $i < $n; $i++) {
            $valor = ($valor << 7) | ($bytes[$i] & 0x7F);
            if (($bytes[$i] & 0x80) === 0) {
                $partes[] = $valor;
                $valor = 0;
            }
        }
        return implode('.', $partes);
    }

    private static function octetos(array $elemento): string
    {
        self::exigir($elemento['tag'] === 0x04, 'Se esperaba un OCTET STRING.');
        return $elemento['contenido'];
    }

    /** Contenido de un OCTET STRING o de un [0] IMPLICIT (encryptedContent). */
    private static function contenido(array $elemento): string
    {
        if ($elemento['tag'] === 0xA0) {
            $salida = '';
            foreach ($elemento['hijos'] as $hijo) {
                $salida .= $hijo['contenido'];
            }
            return $salida;
        }
        return $elemento['contenido'];
    }

    private static function entero(array $elemento): int
    {
        self::exigir($elemento['tag'] === 0x02, 'Se esperaba un INTEGER.');
        $valor = 0;
        foreach (array_values(unpack('C*', $elemento['contenido'])) as $byte) {
            $valor = ($valor << 8) | $byte;
        }
        return $valor;
    }

    private static function der(array $elemento): string
    {
        return $elemento['bruto'];
    }

    private static function pem(string $tipo, string $der): string
    {
        return "-----BEGIN $tipo-----\n" . chunk_split(base64_encode($der), 64, "\n") . "-----END $tipo-----\n";
    }

    private static function exigir(bool $condicion, string $mensaje): void
    {
        if (!$condicion) {
            throw new RuntimeException($mensaje);
        }
    }
}
