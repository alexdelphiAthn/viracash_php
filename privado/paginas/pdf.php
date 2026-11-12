<?php
declare(strict_types=1);

/*
 * PDF de una factura (por serie y número) leído de fza_facturas y
 * fza_facturas_lineas, con el formato de la factura impresa del programa y,
 * si se emitió con Verifactu, el QR tributario con su leyenda. El idioma del
 * documento es castellano o catalán: el parámetro "idioma" (es/ca) o, si no
 * viene, el idioma de factura guardado en la web.
 *
 * Las facturas simplificadas salen como ticket de 80 mm (ticket_pdf.php),
 * igual que la caja del programa; con "formato" (ticket / a4) se puede pedir
 * el otro formato para cualquier factura.
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$serie = trim((string)($_GET['serie'] ?? ''));
$numero = trim((string)($_GET['numero'] ?? ''));
$idioma = idioma_factura(isset($_GET['idioma']) ? (string)$_GET['idioma'] : null);
$factura = $serie !== '' && $numero !== '' ? factura_leer($pdo, $serie, $numero) : null;
if ($factura === null) {
    pagina(
        t('Factura no encontrada'),
        '<p class="ayuda">' . h(t('No existe la factura {serie} {numero}.', ['serie' => $serie, 'numero' => $numero])) . '</p>' .
        '<a class="boton principal" href="' . h(url('empresa')) . '">' . h(t('Volver')) . '</a>',
        ['errores' => [t('Factura no encontrada.')]]
    );
}
$lineas = factura_lineas($pdo, $serie, $numero);
$empresa = empresa_por_codigo($pdo, (string)$factura['CODIGO_EMP_FAC']);
$formaPago = forma_pago_leer($pdo, (string)$factura['FORMA_PAGO_FAC']);
$numeroFormateado = numero_documento_formateado($empresa, $serie, $numero);
/* La cuenta bancaria solo se imprime si la forma de pago lo pide (ESVERBANCOEMPRESA_FORMA_PAGO_FP). */
$iban = $formaPago['ver_banco']
    ? iban_factura($pdo, (string)$factura['CODIGO_EMP_FAC'], (string)$factura['CODIGO_CLI_FAC'])
    : '';
/* QR tributario solo en facturas emitidas con Verifactu (URL guardada en la consolidación o calculada). */
$qr = factura_qr_verifactu($pdo, $usuario, $factura);

/* Formato: ticket para las simplificadas (como en el programa) salvo que se
   pida otro con ?formato=ticket|a4. */
$simplificada = strcasecmp(trim((string)$factura['TIPO_FAC']), 'SIMPLIFICADA') === 0;
$formato = strtolower(trim((string)($_GET['formato'] ?? '')));
if (!in_array($formato, ['ticket', 'a4'], true)) {
    $formato = $simplificada ? 'ticket' : 'a4';
}

if ($formato === 'ticket') {
    $contenido = ticket_pdf_generar($factura, $lineas, $numeroFormateado, [
        'qr'         => $qr,
        'forma_pago' => $formaPago['descripcion'],
        'empleado'   => empleado_diminutivo_ticket($pdo, (string)($factura['CODIGO_CAJERO_FAC'] ?? '')),
        'pie'        => empresa_pie_ticket($pdo, (string)$factura['CODIGO_EMP_FAC']),
    ]);
} else {
    $contenido = factura_pdf_generar($factura, $lineas, $numeroFormateado, $formaPago['descripcion'], $iban, $qr, $idioma);
}
$nombreFichero = ($formato === 'ticket' ? 'Ticket_' : 'Factura_') .
    preg_replace('/[^A-Za-z0-9._-]+/', '_', $numeroFormateado) . '.pdf';

header('Content-Type: application/pdf');
header('Content-Length: ' . strlen($contenido));
header('Content-Disposition: inline; filename="' . $nombreFichero . '"');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
echo $contenido;
exit;
