<?php
declare(strict_types=1);

/*
 * Declaración responsable del SIF (documento del productor, se muestra tal
 * cual lo entrega el servicio, en castellano).
 */

$usuario = exigir_usuario();
$pdo = bbdd();
$empresas = empresas_listar($pdo);
$codigo = (string)($_GET['empresa'] ?? ($empresas[0]['CODIGO_EMP_EMP'] ?? ''));
$sif = sif_estado_empresa($pdo, $codigo);
$errores = [];
$documento = null;
try {
    if ($sif === null || $sif['sif'] !== 'FZ') {
        throw new RuntimeException(t('Selecciona una empresa con instalación SIF FZ registrada.'));
    }
    $documento = sif_obtener_declaracion($pdo, $usuario, $sif['version']);
} catch (Throwable $e) {
    $errores[] = $e->getMessage();
}
if ($documento !== null) {
    header('Content-Type: text/html; charset=utf-8');
    if (isset($_GET['descargar'])) {
        header('Content-Disposition: attachment; filename="declaracion-responsable.html"');
    }
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    header("Content-Security-Policy: sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:; frame-ancestors 'self'");
    echo sif_declaracion_solo_documento($documento['html']);
    exit;
}
ob_start();
?>
<form method="get">
<input type="hidden" name="p" value="declaracion">
<label for="empresa"><?= h(t('Empresa')) ?></label>
<select name="empresa" id="empresa">
<?php foreach ($empresas as $empresa): ?>
<option value="<?= h($empresa['CODIGO_EMP_EMP']) ?>" <?= $codigo === (string)$empresa['CODIGO_EMP_EMP'] ? 'selected' : '' ?>><?= h($empresa['RAZON_SOCIAL_EMP']) ?></option>
<?php endforeach; ?>
</select><button type="submit"><?= h(t('Consultar declaración')) ?></button>
</form>
<p><a href="<?= h(url('menu')) ?>"><?= h(t('Volver al menú')) ?></a></p>
<?php
pagina(t('Declaración responsable'), (string)ob_get_clean(), ['errores'=>$errores]);
