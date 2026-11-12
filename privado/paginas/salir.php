<?php
declare(strict_types=1);

/* Cierre de sesión (solo por POST para evitar cierres involuntarios). */

if (es_post() && usuario_actual() !== null) {
    comprobar_csrf();
    cerrar_sesion_usuario();
}
redirigir('login');
