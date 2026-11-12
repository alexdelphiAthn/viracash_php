# ViraCash PHP

Repositorio `viracash_php`, basado en la aplicación web de facturación de ViraCash (PHP 8.3).

Para configurar la conexión, copia `config_ejemplo.php` como `config.php` y rellena los datos de tu entorno. Las configuraciones locales, certificados y archivos de ejecución se excluyen de Git.

Web sencilla, pensada para el móvil (iPhone 7), que crea facturas de venta
mayor sobre la misma base de datos MariaDB/MySQL de ViraCash. Escribe los
datos exactamente como lo hace el programa de escritorio, de modo que
ViraCash puede conectarse en remoto para consultarlos o modificarlos.

## Pantallas

0. **Entrar**: usuario y contraseña de `fza_usuarios` (MD5, como el programa).
   Después, el **menú**: crear nueva factura, ver facturas existentes o
   continuar la factura en curso, y el panel **Verifactu** (modo SIN / PRE /
   PRO, certificado de la empresa, instalación SIF, cola; ver el apartado
   "Verifactu en la web").
   - **Facturas existentes**: las últimas 5, 10, 20 o 100 por fecha, con el
     estado (borrador, emitida sin Verifactu, Verifactu pendiente / enviada /
     con error), el PDF de cualquiera y, solo para las que siguen en borrador
     sin consolidar (como en el programa), **Emitir**, **Modificar** y
     **Borrar**. Al modificar no cambian la empresa, la serie ni el número:
     se revisan fecha, cliente y líneas, las líneas se renumeran desde 010 y
     se recalculan los totales. Al borrar se eliminan cabecera, líneas y
     pagos; el contador de la serie no retrocede.
1. **Empresa emisora**: NIF. Se propone la empresa por defecto del usuario
   (`EMPRESA_DEFECTO_USU`) o la única que exista. Si el NIF no existe, se
   crea una empresa nueva.
2. **Datos de la empresa**: se muestran siempre, se pueden corregir y se
   confirman.
3. **Fecha y serie**: fecha, serie (la de empresas → series de la empresa
   confirmada, editable) y número (a 0 para que lo asigne el contador
   automático de la serie al grabar).
4. **Cliente**: DNI/NIF. Si existe se cargan sus datos; si no, se pasa a la
   ficha para darlo de alta.
5. **Datos del cliente**: datos fiscales, retención de IRPF, tarifa (con o
   sin IVA incluido; un cliente nuevo nace con VENTA MAYOR, precios sin
   IVA), forma de pago y régimen de IVA.
6. **Líneas**: descripción, cantidad, unidad, precio (con IVA incluido o
   sin IVA según la tarifa del cliente) y descuento. Se puede buscar un
   artículo del catálogo para copiar descripción y precio, o escribir la
   línea a mano sin artículo (tipo SERVICIO).
7. **Totales**: base, IVA por tipo, recargo si procede, retención de IRPF y
   total, calculados como el programa. Al crear la factura se graban la
   cabecera, las líneas (numeradas con `PRC_FNC_GET_NEXT_LINEA_FACTURA`) y
   los totales, todo en borrador (tipo NORMAL, sin movimiento de stock).
8. **PDF**: `index.php?p=pdf&serie=…&numero=…` genera la factura en A4 con
   el formato de la factura impresa de ViraCash (emisor y receptor en cajas,
   líneas, desglose de IVA, retención, total y forma de pago; si la forma de
   pago tiene `ESVERBANCOEMPRESA_FORMA_PAGO_FP = 'S'`, a continuación va el
   IBAN: la cuenta de cobro asignada al cliente en `fza_empresas_bancos`, si
   no la de cobro por defecto de la empresa y si no `IBAN_EMP`). Se genera sin
   librerías externas (`privado/pdf_minimo.php`) y sirve para cualquier
   factura de la base de datos, no solo las creadas desde la web. Si la
   factura se emitió con Verifactu lleva en la esquina superior derecha el
   **QR tributario** (31 mm, URL de cotejo de la AEAT) con la leyenda
   "VERI*FACTU - Factura verificable en la sede electrónica de la AEAT"; el
   PDF no lleva ninguna nota de borrador salvo que se ponga
   `'pdf_nota_borrador' => true` en `config.php`.
9. **Emitir**: desde la confirmación de la factura o desde el histórico, un
   borrador se emite según el modo Verifactu de la web (ver más abajo).

El número visible sigue el "Formato documentos" de la empresa
(`FORMATO_DOCUMENTO_EMP`, tokens `Serie` y `NroDocumento`) y un número
escrito a mano se rellena con los ceros de `NUM_DIGITOS_CON` del contador.

### Cálculo (igual que el programa)

- Línea: descuento = precio × %dto; precio con/sin IVA según
  `ESIMP_INCL_TARIFA_CLIENTE_FAC`; totales de línea = precio × cantidad, con
  4 decimales (como `Currency` en `TLinFac.CalcularLinea`).
- Factura: motor fiscal de venta con redondeo por línea a 2 decimales, IVA
  incluido calculado por diferencia, recargo de equivalencia solo si la zona
  lo aplica y el cliente lo tiene, retención sobre la base (o base más
  impuestos si la zona lo indica) sin redondear, cliente intracomunitario o
  exento a tipo exento.

## Cómo escribe en la base de datos

| Acción | Igual que el programa |
| --- | --- |
| Entrar | `fza_usuarios` (MD5 mayúsculas) y `ULTIMO_LOGIN_USU`. |
| Código de empresa / cliente nuevo | `CALL PRC_GET_NEXT_CONT('EM' / 'CL', usuario, @salida)`. |
| Guardar empresa | `CALL PRC_CREAR_ACTUALIZAR_EMPRESA(...)`. |
| Guardar cliente | `CALL PRC_CREAR_ACTUALIZAR_CLIENTE(...)` (+ `CODIGO_FP_CLI` con auditoría). |
| Número de factura | `CALL PRC_GET_NEXT_CONT_FACT_SERIE(serie, 'FC', empresa, usuario, @salida)`. |
| Cabecera | `INSERT INTO fza_facturas` con los valores de `fza_valores_defecto`, la copia de empresa, zona de IVA (`vi_ivas`), retención (`fza_empresas_retenciones`) y cliente, fase `BORRADOR`, tipo `NORMAL`, sin movimiento de stock. |
| Líneas | `CALL PRC_FNC_GET_NEXT_LINEA_FACTURA(numero, serie, @salida)` e `INSERT INTO fza_facturas_lineas` con los mismos campos que el editor de líneas del programa. |
| Totales | `UPDATE fza_facturas` con las mismas columnas que `ActualizarTotalesEnDataSet`. |

No crea tablas, vistas ni procedimientos: usa los que ya existen.

## Verifactu en la web

El menú incluye **Declaración responsable del SIF**, también accesible en modo
SIN para consultarla antes de activar VeriFactu. Permite elegir empresa, leer
el documento y descargarlo como HTML imprimible. Consulta `sif/declaracion.php`
del servicio configurado en `appApiUrl`, con `appApiToken`, `appApiReferencia`
y la versión de instalación registrada en la empresa. Comprueba SIF, versión
y SHA-256; conserva una copia en `privado/declaraciones_sif_cache` para fallos
del servicio. Si falta configuración o no hay documento, informa del error;
no sustituye la declaración por la de otra versión. El productor debe mantener
en su servicio la declaración aplicable al producto y versión distribuidos.

El histórico ofrece **Cancelar Verifactu** para altas aceptadas. La confirmación
explica la diferencia entre anulación y rectificación y enlaza al BOE y a la AEAT.
Requiere motivo, certificado vigente de la empresa y el mismo entorno PRE/PRO del
alta. Crea una operación ANULACION en la cola compartida con Delphi; conserva el
alta original y su QR. La factura solo cambia a anulada tras la aceptación de la
AEAT. Los errores de anulación permanecen en la cola sin convertir el alta en
borrador. Un duplicado genérico no se considera prueba de anulación aceptada.

La comprobación local del certificado verifica disponibilidad y vigencia; no
compara actualmente su NIF con el del emisor ni verifica apoderamientos.

Prueba local sin envíos a la AEAT: `php tests/pruebas_verifactu_anulacion.php`
(desde viracash_web; utiliza tablas temporales sobre viracashphp_local).

La web aplica Verifactu con **las mismas tablas, parámetros, huellas y
transiciones que ViraCash** (unidades `inLibVerifactu*`, `UniDataVerifactu*`
e `inLibEmisionFiscal` del programa), de modo que lo que emite la web lo ve el
programa y viceversa: `fza_verifactu_cola` (cola de envíos),
`fza_verifactu_eventos` (log de eventos encadenado por SHA-256),
`fza_verifactu_cadena` (último eslabón por NIF emisor),
`fza_facturas_consolidaciones` (respuesta de la AEAT, URL y PNG del QR, XML
del registro) y `FASE_FAC` de `fza_facturas`.

### Modo: SIN, PRE o PRO

El modo se cambia desde el menú (solo usuarios de un grupo administrador,
como los parámetros `appVerifactu*` del programa) y se guarda en
`fza_usuarios_perfiles` con `PRC_SETPERFILFORMULARIO`, formulario
`frmMtoAppParam`, **en el ámbito del usuario** (que tiene prioridad sobre el
grupo y sobre "Todos", igual que en ViraCash):

| Modo | Parámetros | Qué hace al emitir |
|------|------------|--------------------|
| SIN  | `appVerifactuActivo = False` | La factura pasa a `SIN_VERIFACTU`, consolidada, sin cola ni QR. |
| PRE  | `appVerifactuActivo = True`, `appVerifactuModo = VERIFACTU`, `appVerifactuEntorno = PRE` | Cola + envío al entorno de pruebas (`prewww1.aeat.es`). |
| PRO  | ídem con `appVerifactuEntorno = PRO` | Cola + envío a producción (`www1.agenciatributaria.gob.es`). |

Por defecto la web está en SIN (`appVerifactuActivo` vacío o `False`) y **no
deja pasar a PRE ni a PRO hasta que haya un certificado cargado**. El modo
`NO_VERIFACTU` del programa (registros firmados XAdES sin envío) no está
disponible en la web. Cada cambio de modo, de certificado, de parámetros o de
instalación SIF se anota en el log con el evento 103 (cambio de
configuración), como hace el programa.

### Certificado de la empresa

Se sube desde el menú (o en el momento de emitir, si falta) como fichero
`.pfx`/`.p12` con su contraseña, con dos opciones:

- **Solo para esta sesión**: se guarda en la sesión PHP y se descarta al
  salir o al caducar; hay que volver a cargarlo la próxima vez.
- **Guardar en el servidor**: certificado en PEM y clave privada cifrada
  (AES-256, secreto propio del servidor) en `privado/certificados/`, carpeta
  fuera de `publico` y con `.htaccess` de denegación. El secreto es
  `config.php` → `'verifactu' => ['clave_certificados' => '...']` o, si no
  existe, `privado/certificados/clave.txt` generado al azar la primera vez.
  Se borra desde el menú cuando se quiera.

Al cargarlo se anotan en `fza_empresas` los mismos campos que Empresas →
Certificados del programa (`CODIGO_CERTIFICADO_EMP` = número de serie,
titular, tipo y fechas). Los `.pfx` exportados desde Windows (FNMT) cifran
con RC2-40 y 3DES, que OpenSSL 3 ya no abre: `privado/pkcs12.php` los lee en
PHP puro (MAC, derivación de clave PKCS#12, RC2, 3DES y PBES2) cuando
`openssl_pkcs12_read()` falla. El envío usa cURL con el certificado de
cliente en memoria (`CURLOPT_SSLCERT_BLOB`; con un cURL antiguo, ficheros
temporales en la carpeta privada que se borran al terminar). El servidor de
la AEAT se verifica con las raíces del sistema; si PHP no tiene
`curl.cainfo` (PHP para Windows), indicar el fichero en `config.php`:
`'verifactu' => ['ca_bundle' => 'C:/ruta/cacert.pem']`.

### Emisión y cola

Al pulsar **Emitir** en PRE/PRO la web hace lo mismo que Consolidar en
Borradores del programa y, a continuación, lo que haría el hilo de la cola:

1. Valida los requisitos fiscales (NIF de la empresa, `appVerifactuSifNif`,
   instalación SIF de la empresa, certificado vigente y NIF del cliente para
   F1).
2. Inserta en `fza_verifactu_cola` (ALTA, PENDIENTE), pone `FASE_FAC =
   VERIFACTU_PENDIENTE` y registra el evento 2 (encolado).
3. Reclama la fila (PROCESANDO), abre una transacción, bloquea la cadena del
   emisor (`fza_verifactu_cadena` con `FOR UPDATE`), compone el
   `RegistroAlta` con la huella SHA-256 encadenada, lo envía por SOAP
   (`RegFactuSistemaFacturacion`) y persiste el resultado: cadena avanzada,
   fila en `fza_facturas_consolidaciones` (CSV, estado, URL y PNG del QR,
   petición y respuesta completas), `FASE_FAC = VERIFACTU_OK`,
   `ESCONSOLIDADA_FAC = 'S'`, cola ENVIADA y evento 3.
4. Si la AEAT rechaza el registro: cola PENDIENTE con espera exponencial
   (60 s × 2^intentos, tope 32 min), evento 4 y, agotados
   `appVerifactuMaxIntentos`, ERROR y `FASE_FAC = VERIFACTU_ERROR`. Un fallo de
   conexión no consume el intento (evento 1, 5 minutos de espera).

No hay hilo en segundo plano: la cola se procesa al emitir y con el botón
"Procesar la cola ahora" del panel Verifactu (menú → "Cola y registro de
eventos"), que también muestra las filas de la cola y los últimos eventos.
Las facturas emitidas con Verifactu ya no se pueden modificar ni borrar.

### Parámetros e instalación SIF

Menú → "Parámetros e instalación SIF" (administradores) edita los
parámetros de Verifactu (productor del software, URLs de la AEAT,
reintentos, descripción de la operación...) y los de **Servicios web**
(`appApiUrl`, `appApiToken`, `appApiReferencia`) de la tabla de perfiles del
usuario, guardando solo los que cambian en el ámbito elegido. En la misma
pantalla se pide el **número de instalación SIF** de cada empresa al servicio
de asignación de SIF (`appApiUrl` + `sif/instalacion.php`, cabecera
`X-API-Key`), como Archivo → Empresas del programa, y se guarda en
`NUMERO_INSTALACION_EMP` / `VERSION_INSTALACION_EMP` /
`CODIGO_SIF_INSTALACION_EMP`. La web se identifica ante la AEAT con la
versión registrada en la empresa (no comprueba, como el programa, que
coincida con la del ejecutable).

### Diferencias conocidas con el programa

- XML y QR usan `TOTAL_BASES_FAC + TOTAL_IMPUESTOS_FAC`, también en
  ViraCash (informes, Excel y tickets). El IRPF no suma ni resta en
  VeriFactu; únicamente reduce el importe a pagar de la factura.
- La sesión MySQL de la web fija `time_zone` a la hora de Madrid
  (`SET time_zone = '+02:00'` / `'+01:00'`) para que `NOW()` no vaya en la hora
  del servidor de DreamHost (Pacífico).
- Los eventos y registros se firman solo con la huella (sin XAdES): la web no
  implementa el modo NO VERI*FACTU.

Pruebas: `qr.php` validado con OpenCV y zxing-cpp (versiones 1 a 24),
`pkcs12.php` con los vectores RC2 del RFC 2268 y ficheros `.pfx` generados
con `openssl pkcs12 -export -legacy` (RC2-40, 3DES, 2DES, AES, MAC SHA-256),
y `verifactu_registro.php` contra el XML de ejemplo de
`delphiverifactu/docs/envio_verifactu.md` (idéntico byte a byte).
## Idiomas de la web (14/09/2026)

Las pantallas están en castellano, catalán, inglés y chino simplificado. El
selector va al pie de todas las páginas, también en la de entrada, y la
elección se guarda en un fichero de la propia web,
`privado/idioma.json` (no en los parámetros de la aplicación), común a todos
los usuarios; sin fichero la web arranca en castellano.

- Los textos del código siguen escritos en castellano y pasan por `t()`
  (`privado/idiomas.php`), que los busca en `privado/idiomas/ca.php`,
  `en.php` y `zh.php`; si falta una traducción se muestra el castellano. Los
  marcadores `{clave}` se sustituyen por los valores de cada mensaje.
- Lo que se guarda en la base de datos (log de eventos Verifactu, mensajes de
  error de la cola, XML) se anota siempre en castellano, igual que hace
  ViraCash.
- La factura en PDF y los textos legales (pantalla de anulación, leyenda del
  QR fijada por la AEAT, declaración responsable) van en castellano. El
  catalán es lengua cooficial y la factura puede expedirse en él: solo con la
  web en catalán aparece, junto al PDF, el enlace "PDF · CA"
  (`index.php?p=pdf&...&idioma=ca`); en inglés y chino la factura es siempre
  en castellano.
- Con retención de IRPF el PDF imprime "Total factura" (base más impuestos, el
  importe del registro y del QR Verifactu), la retención y "Total a pagar",
  como recomienda la AEAT en sus aclaraciones a desarrolladores.
- `php ../tests/comprobar_idiomas.php` comprueba que los tres diccionarios
  cubren todos los textos del código con los mismos marcadores y etiquetas.

## Instalación

Requisitos: PHP 8.3 (o superior) con `pdo_mysql` y `mbstring`, y acceso a la
base de datos de ViraCash.

1. Sube la carpeta completa al servidor **manteniendo la estructura**:

   ```
   viracash_php/
     .htaccess            (solo se usa en la opción B)
     config.php           (conexión: host, base de datos, usuario, contraseña)
     README.md
     privado/             (código PHP; nunca accesible por web)
     publico/             (lo único que ve el navegador)
       index.php
       estilos.css
       app.js
   ```

   - **Opción A (recomendada)**: el directorio público del dominio o
     subdominio (`public_html`, `httpdocs`, "document root") apunta a
     `viracash_php/publico`. Así `config.php` y `privado` quedan fuera del
     alcance del navegador.
   - **Opción B**: si el directorio público tiene que ser la propia carpeta
     `viracash_php`, no hay que cambiar nada más: el `.htaccess` de la raíz
     bloquea `config.php` y `privado` y sirve la web desde `publico`.

2. Edita `config.php` con el host, la base de datos, el usuario y la
   contraseña.
3. Sirve la web por HTTPS (la cookie de sesión se marca segura cuando detecta
   HTTPS).
4. El usuario de la base de datos necesita SELECT, INSERT y UPDATE sobre las
   tablas `fza_*`, SELECT sobre las vistas `vi_*` y EXECUTE sobre los
   procedimientos `PRC_*`.

Para probar en casa con el servidor interno de PHP y abrirla desde el iPhone
en la misma red Wi-Fi:

```bash
php -S 0.0.0.0:8080 -t publico
```

y en el móvil `http://<ip-del-pc>:8080/`.

## Si la base de datos es MySQL 8 (no MariaDB)

El volcado `viracash_original.sql` está hecho para MariaDB. En MySQL 8 el
procedimiento `PRC_GET_NEXT_CONTADOR` no se crea porque usa la variable
`@@in_transaction`, que solo existe en MariaDB, y la carga se detiene en ese
punto. Sin él fallan los códigos automáticos de clientes y empresas
(`PRC_GET_NEXT_CONT`).

Solución: ejecutar `sql/PRC_GET_NEXT_CONTADOR_mysql8.sql` sobre la base de
datos (con phpMyAdmin, HeidiSQL o el cliente `mysql`) y continuar la carga del
volcado a partir del procedimiento siguiente (`PRC_GET_NEXT_CONT_FACT_SERIE`).
Para comprobar que están todos los que necesita la web:

```sql
SELECT ROUTINE_NAME FROM INFORMATION_SCHEMA.ROUTINES
 WHERE ROUTINE_SCHEMA = DATABASE()
   AND ROUTINE_NAME IN ('PRC_GET_NEXT_CONT', 'PRC_GET_NEXT_CONTADOR',
                        'PRC_GET_NEXT_CONT_FACT_SERIE',
                        'PRC_CREAR_ACTUALIZAR_EMPRESA',
                        'PRC_CREAR_ACTUALIZAR_CLIENTE');
```

Deben salir los cinco.

### Conversión automática: `DBComparer --mysql841` (11/09/2026)

Los apaños anteriores se hicieron a mano. Desde el 11/09/2026 DBComparer
(`C:\DISCO_DURO\proyectos\dbcomparer`) convierte de una vez cualquier copia
de seguridad de ViraCash (`FZAM_COPIA_SEGURIDAD_SQL`, hecha en MariaDB) en un
script cargable en MySQL 8.0.41 sobre Linux:

```bash
DBComparer --mysql841 viracash_original.sql viracash_mysqllinux.sql
```

Lo que cambia (y solo eso; datos y comentarios se conservan byte a byte):

- `ALTER DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci` tras
  `SET NAMES`, para que los parámetros de los procedimientos hereden la
  intercalación correcta.
- Tablas: `current_timestamp()` → `CURRENT_TIMESTAMP`, `int(11)` → `int`
  (salvo `tinyint(1)` y `zerofill`), `text ... DEFAULT 'x'` →
  `DEFAULT ('x')`.
- Vistas y procedimientos sin `DEFINER` y con `SQL SECURITY INVOKER`
  (dejan de depender de la cuenta que los creó).
- `CREATE OR REPLACE PROCEDURE` → `DROP ... IF EXISTS` + `CREATE`;
  `CREATE OR REPLACE [TEMPORARY] TABLE` dentro de procedimientos →
  `DROP ... IF EXISTS` + `CREATE`.
- `DECLARE`/parámetros con `COLLATE` sin `CHARACTER SET` → se añade
  (MySQL 8 da el error 1235 si falta). Desde el 11/09/2026 por la tarde
  también cuando la declaración ocupa dos líneas (el tipo en una y
  `COLLATE` en la siguiente): antes se escapaban dos `DECLARE` de
  `PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD` y `PRC_PRESTASHOP_ENCOLAR_TEMP`.
- `@@in_transaction` (solo MariaDB) → variable local rellenada por el
  procedimiento `PRC_FZA_EN_TRANSACCION`, que el conversor añade al principio
  de la sección de procedimientos (sonda con `SAVEPOINT`/`RELEASE SAVEPOINT`:
  fuera de una transacción `RELEASE` da el error 1305 y la sonda devuelve 0).
- Nombres de tablas y vistas con la caja declarada, en el código y en el SQL
  guardado en `fza_usuarios_perfiles` y `fza_informes_guias`.

Al terminar imprime un resumen con los recuentos y los avisos; devuelve 2 si
hay construcciones sin equivalente automático (`EXECUTE IMMEDIATE`,
`BEGIN NOT ATOMIC`, `ADD COLUMN IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`,
`FOR ... DO`, `RETURNING`), que hay que revisar a mano. Los scripts de
migración guardados como datos en `fza_generadorprocesos` se dejan tal cual
(siguen en dialecto MariaDB). Verificado cargando el resultado en una MariaDB
desechable creada en `utf8mb4_general_ci` (158 tablas, 98 vistas y 134
rutinas con INVOKER, contadores correctos dentro y fuera de transacción). El
11/09/2026 se cargaron en el MySQL 8 real (`viracashphp`) las secciones de
vistas y procedimientos del script convertido: entraron 95 vistas y las 134
rutinas menos una. Fallaron `vi_articulos_fotos` (la tabla del servidor no
tenía `ORDEN_FOT`: diferencia de estructura, no de conversión; ver el
apartado siguiente), `viest_movimientos_dia` y `viest_dia` (sin causa en la
estructura; su SELECT funciona) y `PRC_PRESTASHOP_ENCOLAR_VISIBILIDAD` (el
`COLLATE` en dos líneas, ya corregido en el conversor). Pruebas DUnitX en
`viracash_web\tests\PruebasConversionMySQL841.pas` (13 casos).

### Alinear la estructura del servidor con desarrollo (11/09/2026)

La base `viracashphp` se montó el 10/09 a partir de una copia anterior, así que
su estructura va por detrás de `viracash_original.sql` aunque las vistas y los
procedimientos convertidos ya estén cargados. Comparadas la copia de desarrollo
y la base viva (INFORMATION_SCHEMA, dialecto normalizado), faltan en el
servidor 5 tablas (`fza_movimientos_recalculos_pendientes`,
`fza_prestashop_cola_eventos`, `fza_tarifas_descuento_condiciones`,
`fza_tarifas_descuento_valores`, `fza_ventas_ws_cola_intentos`), 13 columnas
en 6 tablas (entre ellas `fza_articulos_fotos.ORDEN_FOT`, por la que falla la
vista `vi_articulos_fotos`), 22 índices secundarios en tablas existentes, la
clave primaria de `fza_articulos_fotos` (debe incluir `ORDEN_FOT`) y el orden
de columnas de la de `fza_contadores`, y dos columnas de
`fza_traspasos_solicitudes` con otra definición (`FECHA_TRSOL`, `ESTADO_TRSOL`).
Los datos de las columnas comunes ya coinciden en tipo, nulos, valores por
defecto e intercalación.

`sql/alinear_estructura_remoto.sql` corrige todo eso **sin tocar datos**:
tablas nuevas vacías (`CREATE TABLE IF NOT EXISTS`), columnas en su posición de
desarrollo, claves primarias en una sola sentencia e índices, cada paso con
comprobación previa en INFORMATION_SCHEMA (`PREPARE`/`EXECUTE`, porque MySQL 8
no admite `IF NOT EXISTS` en `ADD COLUMN` ni `ADD INDEX`), así que se puede
repetir. `sql/alinear_estructura_remoto_reversion.sql` deshace los cambios
(borra las tablas y columnas nuevas con lo que contengan). La lista de
diferencias sale del modo de comparación de DBComparer entre dos MariaDB
locales, una con `viracash_original.sql` y otra con la copia del servidor
`viracash_mysqllinux.sql` (así no hay ruido de dialecto):

```bash
DBComparer 127.0.0.1:34123\viracash root\ 127.0.0.1:34123\viracashphp root\ --nodelete --output=diferencias.sql
```

De ese script solo se aprovechan tablas, columnas, claves e índices: las 135
`MODIFY COLUMN` con `DEFAULT ''` son un artefacto (la copia de seguridad hecha
desde MySQL 8 no escribe ese `DEFAULT ''`, pero el servidor sí lo tiene) y las
vistas y procedimientos que recrea van en dialecto MariaDB. Ambos scripts se
probaron sobre la copia local del servidor: tras alinear, DBComparer no
encuentra ninguna diferencia de tablas, columnas o índices, se crean las tres
vistas y el procedimiento que faltaban, la segunda pasada no cambia nada y la
reversión devuelve exactamente las diferencias iniciales.

Pasos en el servidor, en este orden (todo con HeidiSQL o el cliente `mysql`):

1. `sql/alinear_estructura_remoto.sql`.
2. Regenerar el script convertido con el DBComparer actual
   (`DBComparer --mysql841 viracash_original.sql prueba.sql`) y ejecutar de
   nuevo su bloque de vistas (desde `-- Limpieza de vistas` hasta
   `-- PROCEDIMIENTOS ALMACENADOS`) y el de procedimientos, empezando siempre
   por la línea `SET NAMES utf8mb4 COLLATE utf8mb4_spanish_ci;` de la cabecera.
   Sin ella la sesión de HeidiSQL trabaja en `utf8mb4_0900_ai_ci` y las columnas
   de las vistas que salen de un literal (`ORIGEN_PRECIO`, `TIENE_SKU`,
   `ROL_EN_OPERACION`, `FUENTE_ATB`...) se crean con esa intercalación: es lo
   que pasó el 11/09 con 9 columnas de vistas, y puede dar "Illegal mix of
   collations" al compararlas con columnas de tablas.
3. Comprobar: 158 tablas, 98 vistas y 134 rutinas propias (el servidor conserva
   además `PRC_GET_CAJA_STOCK_PIVOTADO_ANT` y `pr_demo_silenciosa`, que no
   existen en desarrollo). Las 5 tablas nuevas quedan vacías: si alguna
   necesita datos de desarrollo, cargarlos aparte.
### Script con todo lo que faltaba en el servidor (10/09/2026)

`sql/esquema_faltante_mysql8.sql` se generó comparando la copia de seguridad
`copiaseguridad_10_09_2026_16_59_18.sql` (base Alexzam) con la base
`viracashphp` del servidor. Contiene **solo estructura**, ningún dato:

- `CREATE TABLE IF NOT EXISTS fza_articulos` (la tabla no existía; la copia
  tenía 1 artículo que no se incluye).
- Los 80 procedimientos que faltaban, con `CREATE OR REPLACE TABLE` cambiado
  a `CREATE TABLE`, `PRC_GET_NEXT_CONTADOR` en su versión compatible y
  `CHARACTER SET utf8mb4` añadido delante de `COLLATE` en parámetros y
  `DECLARE` (MySQL 8 lo exige; afectaba a los seis `PRC_PRESTASHOP_*`).
- No toca ningún objeto que ya exista en el servidor.
- Quedan fuera, para adaptar a mano porque usan `@@in_transaction`:
  `PRC_FZA_FUSION_RECALCULAR_PMP`, `PRC_FZA_MOVIMIENTOS_ALMACEN_DELETE_DOC`
  y `PRC_FZA_MOVIMIENTOS_ALMACEN_INSERT`.

**Estado**: ambos scripts (`esquema_faltante_mysql8.sql` y
`esquema_faltante_mysql8_parte2.sql`, este último solo con los seis
`PRC_PRESTASHOP_*` corregidos) ya se ejecutaron en `viracashphp` el
10/09/2026: 153 tablas, 98 vistas y 112 procedimientos (todos los de la
copia salvo los tres pendientes).

### Intercalación de la base de datos

La base `viracashphp` se creó con intercalación por defecto
`utf8mb4_general_ci`, mientras que todas las tablas usan
`utf8mb4_spanish_ci`. Los parámetros y variables de los procedimientos
toman la intercalación de la base **en el momento de crearse**, así que
comparaciones como `CODIGO_CLI_CLI = pCODIGO_CLIENTE` fallaban con
"Illegal mix of collations". Corregido el 10/09/2026 con:

```sql
ALTER DATABASE viracashphp CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci;
```

y volviendo a crear los 112 procedimientos con
`sql/procedimientos_mysql8.sql` (todos los de la copia, adaptados a MySQL 8,
menos los tres con `@@in_transaction`). Si en el futuro se cargan
procedimientos a mano, hacerlo siempre con la base ya en `utf8mb4_spanish_ci`.

### Hosts permitidos del usuario MySQL y "definer"

Las vistas y los procedimientos se guardan con la cuenta que los creó
(`DEFINER`, por ejemplo `anamalillos@%`). Si después se restringen los hosts
permitidos del usuario y esa cuenta deja de existir, todo lo que pasa por
vistas o procedimientos falla con "Access denied for user ..." aunque las
consultas directas a tablas sigan funcionando. Para poder restringir los
hosts sin ese problema, recrear los objetos con `SQL SECURITY INVOKER`:
`sql/vistas_invoker.sql` y `sql/procedimientos_invoker.sql` (mismas
definiciones que los otros scripts, sin dependencia del definer).

### Mayúsculas y minúsculas en nombres de tablas

El servidor es Linux con `lower_case_table_names = 0`: los nombres de
tablas y vistas distinguen mayúsculas (en la MariaDB de Windows no). En
MySQL 8 ese ajuste solo puede fijarse al inicializar el servidor, así que en
un alojamiento no se puede cambiar. Convención de la base: todas las tablas
y vistas (251) están en minúsculas.

Comprobado sobre el servidor real (11/09/2026) qué distingue y qué no:

| Distingue mayúsculas | No las distingue |
|---|---|
| nombres de tablas y vistas (`FZA_FACTURAS` no existe) | nombres de columnas |
| tablas temporales (`TMP_X` ≠ `tmp_x`) | nombres de procedimientos y funciones |
| alias de tabla (`FROM fza_facturas F ... f.X` → "Unknown column") | `information_schema.columns` y `INFORMATION_SCHEMA.COLUMNS` |
| nombre de la base de datos | |
| `TABLE_NAME = 'FZA_X'` en INFORMATION_SCHEMA y `SHOW TABLES LIKE 'FZA%'` | |

Lo que se hizo:

- `sql/procedimientos_mysql8.sql` ya normaliza los nombres a los reales
  (`fza_EMPRESAs` → `fza_empresas` en `PRC_CREAR_ACTUALIZAR_EMPRESA`,
  `FZA_FACTURAS_LINEAS` → `fza_facturas_lineas` en
  `PRC_CALCULAR_FACTURA_NETOS`) y está cargado en el servidor. Las 112
  rutinas del servidor no tienen ninguna referencia en otra caja.
- La web solo usa nombres en minúsculas.
- ViraCash (escritorio) corregido el 11/09/2026: 45 referencias en 9
  ficheros pasadas al nombre real (`UniDataArticulos.dfm`,
  `UniDataClientes.dfm`, `UniDataComprasSesiones.dfm`, `UniDataEmpresas.dfm`,
  `UniDataFacturas.dfm`, `UniDataFormasdePago.dfm`,
  `UniDataInformeFacturaRepositorio.pas`, `UniDataLogonRepositorio.pas` y
  `inLibDBStructure.pas`, cuya lista `REQUIRED_VIEWS` decía `VI_USUARIOS` y
  la comprobación de estructura habría dado la vista por ausente). Incluye
  tres consultas sobre `vi_fac_busquedas` que definían el alias `f` y lo
  usaban como `F.`. La prueba `PruebasDatasets` de viracash_web espera ahora
  `Vista: vi_usuarios`. Compila (compilar.ps1 Release Win64).
- Los datos también guardan SQL: `fza_usuarios_perfiles` conserva por
  perfil el SQL de los datasets (`VALUE_TEXT_USUPER`, clave `dmFacturas`) y
  ese texto sustituye al del `.dfm` al arrancar. En el servidor hay 7 filas
  del perfil `Administrador` con `VI_IVAS`, `VI_FACTURAS_PRINT`,
  `fza_CONTADORES`, etc. `sql/corregir_caso_perfiles.sql` las corrige (cada
  `UPDATE` exige el valor antiguo, así que es seguro repetirlo) y
  `sql/corregir_caso_perfiles_reversion.sql` las deja como estaban.
- No se tocaron `viracash_demo.sql` (raíz del repositorio de ViraCash) ni
  los volcados históricos de `src/utilnormbbdd`: siguen con nombres mixtos
  en dos procedimientos, filas de perfiles y un script del generador de
  procesos. Si alguna vez se cargan en un MySQL de Linux, aplicar lo mismo.
- Para volver a comprobarlo tras nuevos desarrollos: `herramientas/`
  contiene los rastreadores (`probar_caso_remoto.php` genera
  `nombres_reales.json` desde el servidor y prueba los comportamientos de la
  tabla anterior; `revisar_caso_delphi.php` busca en el código cualquier
  identificador igual a una tabla o vista salvo por la caja;
  `revisar_alias_delphi.php` busca alias con distinta caja en la misma
  sentencia; `revisar_caso_datos_remoto.php` revisa el SQL guardado en las
  tablas y genera los dos scripts de perfiles).

Para volver a cargarlos en otro servidor sirve cualquier cliente que
entienda `DELIMITER`, por ejemplo:

```bash
mysql -h viracashphp.centroganesha.net -u anamalillos -p --default-character-set=utf8mb4 --force viracashphp < sql/esquema_faltante_mysql8.sql
```

`--force` sigue adelante si algún procedimiento no compila en MySQL 8 y
muestra el error con el número de línea; cada bloque va precedido de un
comentario `-- Procedimiento ausente: NOMBRE` para localizarlo.

Al cargar la copia de seguridad a mano en MySQL 8 conviene ejecutar antes
`SET SESSION sql_mode = 'NO_AUTO_VALUE_ON_ZERO,NO_ENGINE_SUBSTITUTION';`
para que acepte los `DEFAULT '0000-00-00 00:00:00'` de las tablas.

## Estructura

```
config.php                 conexión y opciones
publico/index.php          punto de entrada (enrutador)
publico/estilos.css        estilos móvil
publico/app.js             mejoras opcionales (funciona sin JavaScript)
privado/arranque.php       sesión, PDO y utilidades
privado/autenticacion.php  login contra fza_usuarios
privado/repositorio.php    consultas y procedimientos almacenados
privado/factura_borrador.php  factura en curso y alta (cabecera, líneas, totales)
privado/facturas_calculo.php  cálculo de líneas y totales como el programa
privado/pdf_minimo.php     generador de PDF sin dependencias
privado/factura_pdf.php    maquetación de la factura en PDF (con QR Verifactu)
privado/qr.php             codificador QR (byte, nivel M, PNG sin GD)
privado/pkcs12.php         lector PKCS#12 en PHP puro (RC2-40 / 3DES de Windows)
privado/verifactu_parametros.php  parámetros appVerifactu* / appApi* (fza_usuarios_perfiles)
privado/verifactu_registro.php    huella, RegistroAlta, desglose, SOAP, URL del QR, respuesta AEAT
privado/verifactu_certificado.php certificado de la empresa (sesión o servidor)
privado/verifactu_eventos.php     log fza_verifactu_eventos encadenado
privado/verifactu_cola.php        emisión, cola fza_verifactu_cola y envío a la AEAT
privado/sii_registro.php          registro del SII (alta A0/A1, baja, SOAP, respuesta), igual que ViraCash
privado/verifactu_sif.php         número de instalación SIF (servicio web)
privado/certificados/      certificados guardados en el servidor (fuera de publico)
privado/paginas/*.php      una pantalla por fichero
privado/vistas/plantilla.php  plantilla HTML común
privado/vistas/verifactu_vistas.php  fragmentos HTML de Verifactu (modo, certificado, QR)
privado/idiomas.php        idioma de la web (privado/idioma.json), t() y selector del pie
privado/idiomas/*.php      diccionarios castellano => catalán, inglés y chino
privado/paginas/idioma.php cambio de idioma desde el selector (POST)
sql/                       scripts de adaptación a MySQL 8
```

## Entorno local preparado (13/09/2026)

- URL: http://127.0.0.1:8088/ (Apache, acceso solo desde este equipo).
- Base local: `viracashphp_local`, cargada desde `viracash_mysqllinux.sql`.
- Conserva los usuarios del volcado; inicia con modo SIN.
- Configuración local privada: `C:/Apache24/conf/viracashphp-local.php`.
  Apache la selecciona mediante `FZA_CONFIG`; no cambia `config.php` remoto.
- Para arrancar tras reiniciar Windows:
  `powershell -File ../scripts/iniciar_viracash_php_local.ps1`
- Prueba de regresión: `php ../tests/pruebas_verifactu_importe.php`.
- Comprobado: XML, huella y QR sin efecto de IRPF, pantallas autenticadas y PDF.
  Un envío real a AEAT requiere cargar un certificado válido y probar en PRE.

Criterio fiscal: [AEAT, registros de alta y retenciones](https://sede.agenciatributaria.gob.es/Sede/iva/sistemas-informaticos-facturacion-verifactu/preguntas-frecuentes/registros-facturacion-alta.html).
