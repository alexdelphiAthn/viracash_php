<?php
declare(strict_types=1);

/*
 * Configuración de la web de facturación.
 * Datos de conexión a la base de datos de ViraCash.
 * Este fichero no debe publicarse dentro del directorio "publico".
 */
return [
    'bbdd' => [
        'host'     => '127.0.0.1',
        'puerto'   => 3306,
        'nombre'   => 'viracash',
        'usuario'  => 'usuario_bbdd',
        'password' => '',
    ],
    // Nombre que aparece en la cabecera de todas las pantallas.
    'titulo' => 'ViraCash',
    // Con true se muestra el detalle técnico de los errores (solo en pruebas).
    'depuracion' => false,
    // Con true el PDF de una factura en borrador lleva una nota al pie
    // (pensado para cuando empiece Verifactu).
    'pdf_nota_borrador' => false,
];
