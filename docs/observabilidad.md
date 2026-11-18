# Observabilidad: prueba de la alerta, dashboard y logs (18/11/2026)

Prueba hecha sobre `quantumquack-dev` (revisión `quantumquack-dev-00004-52v`) en el proyecto `quantumquack-ucu`. Todo lo que se ve acá lo crea Terraform (`infra/modules/monitoring`); en la consola no se cambió nada a mano.

## Línea de tiempo

| Hora (UYT) | Qué pasó |
|---|---|
| 20:27:29 · 20:27:32 · 20:27:34 | 3 fotos subidas desde la app con el siniestro `test-luca` (las 3 respondieron "Listo. Foto recibida.") |
| 20:27:40 · 20:27:45 · 20:27:50 | 3 llamadas a `/api/boom`, las 3 devolvieron `500` |
| 20:31:39 | Cloud Monitoring abre el incidente "5xx > 0 en 1 minuto" con valor 3 |
| 20:31 | Llega el mail de alerta (incidente abierto) |
| 20:33:07 | El incidente se cierra solo (no hubo más 5xx) |
| 20:33:23 | Llega el mail de incidente resuelto |

**Dato para el guion de la demo:** el mail de alerta llega unos **4 minutos** después del primer `/api/boom`. Casi todo ese tiempo es la demora con la que Cloud Run publica la métrica `request_count`; el mail sale a los pocos segundos de abrirse el incidente. En la demo conviene llamar a `/api/boom` al principio y mostrar el mail al final.

## Por qué llegaron 2 mails y no 3

La alerta suma los 5xx de cada minuto (`ALIGN_SUM` en ventanas de 60 s). Las 3 llamadas cayeron en el mismo minuto, así que Monitoring abrió **un solo incidente** con valor 3. Por cada incidente llegan dos mails: uno cuando se abre y otro cuando se cierra. Para tener un mail de alerta por cada llamada habría que espaciarlas más de 1 minuto y esperar a que se cierre el incidente anterior.

## Retención de logs

El bucket `_Default` tiene retención de **7 días**, configurada por Terraform (`log_retention_days`). Se verificó en Logging → Almacenamiento de registros y no se tocó a mano para respetar la regla de "todo por código".

## Evidencias (`docs/evidencias/observabilidad/`)

| Archivo | Qué muestra |
|---|---|
| `alerta-incidente-abierto.png` | Incidente abierto con la métrica de 5xx y la documentación de la alerta |
| `alerta-incidente-cerrado.png` | Lista de alertas con el incidente de las 20:31 ya cerrado (y los de la tarde) |
| `dashboard-quantumquack.png` | Dashboard QuantumQuack con requests por código (2xx, 4xx, 5xx), latencia p95 y objetos/bytes del bucket |
| `logs-signed-url-issued.png` | Explorador de logs con el filtro `jsonPayload.msg="signed_url_issued"`: las 3 subidas de `test-luca` |
| `logs-retencion-buckets.png` | Buckets de logs `_Default` y `_Required` |
| `logs-retencion-7-dias.png` | Columna de retención: `_Default` en 7 días |

Pendiente: captura del mail de alerta (`mail-alerta.png`).
