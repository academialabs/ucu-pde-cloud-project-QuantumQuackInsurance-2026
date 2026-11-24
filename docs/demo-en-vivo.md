# Demo en vivo · guía para quien la presenta (Windows)

Todo lo necesario para hacer la demo de 5 minutos sin haber armado la infraestructura. Los comandos son para **PowerShell en Windows**; los equivalentes para Mac/Linux están en [`runbook.md`](runbook.md#4-validación-smoke-tests).

## Quién hace qué

| Tarea | Quién | Por qué |
|---|---|---|
| Prender el load balancer (`ENABLE_LB=true`) 2 horas antes | **Facundo** | En un repo personal solo el dueño puede cambiar las Variables de GitHub |
| Aprobar el deploy y pasar la IP del LB | Cualquiera del equipo (reviewer del environment `dev`) | |
| **La demo en vivo** (los 8 pasos de abajo) | **Quien presenta** | |
| Volver `ENABLE_LB=false` y capturar Facturación después de la defensa | **Facundo** | Variables y facturación son del dueño |

## Checklist del día anterior (quien presenta)

- [ ] Puedo entrar a **github.com/facusio/quantumquack** → *Actions* y veo el workflow **Destroy** con el botón *Run workflow*. Si no aparece, Facundo tiene que darme permiso de escritura.
- [ ] Estoy en **Settings → Environments → dev → Required reviewers** (lo verifica Facundo). Si no, no puedo aprobar el Destroy.
- [ ] Entro a **console.cloud.google.com** con el proyecto **quantumquack-ucu** y veo *Monitoring → Dashboards → QuantumQuack*.
- [ ] Me llegan los mails de alerta (estoy en `ALERT_EMAILS`).
- [ ] En PowerShell, `curl.exe --version` responde (viene con Windows 10 y 11).
- [ ] Carpeta `C:\demo` con:
  - `foto.jpg`: una foto JPG de menos de 10 MB.
  - `prueba.pdf`: cualquier PDF.
- [ ] Hice la demo completa al menos una vez en el ensayo.

## 15 minutos antes: preparar la pantalla

1. Facundo me pasa la **IP del load balancer** (sale en el resumen del job *Deploy*).
2. Abrir estas pestañas, en este orden:
   1. `http://<IP>` (el portal)
   2. Cloud Monitoring → Dashboards → **QuantumQuack**
   3. GitHub → Actions → **Destroy**
   4. El mail
3. Abrir **PowerShell**, ir a la carpeta y cargar la dirección:
   ```powershell
   cd C:\demo
   $URL = "http://<IP>"
   curl.exe -s "$URL/health"
   ```
   Tiene que responder `ok`. Si no responde, ver [Si algo falla](#si-algo-falla).
4. Agrandar la letra de PowerShell (Ctrl + rueda del mouse) para que se lea en el proyector.

## La demo (5 minutos)

### 0:00 · Disparar la alerta
Abrir `http://<IP>/api/boom` en el navegador y recargar **2 o 3 veces**. Se ve un error 500.
> "Esto simula una falla. Al final vamos a ver que la alerta nos llegó por mail."

Va primero porque el mail tarda unos 4 minutos.

### 0:30 · Subir una foto
En el portal: **Número de siniestro** `test-demo` → elegir `foto.jpg` → **Subir foto** → *Listo. Foto recibida.*
> "El contenedor solo firmó una URL de 5 minutos; la foto fue directo del navegador a Cloud Storage."

### 1:30 · Un PDF no se acepta → 400
```powershell
$body = @{ contentType = "application/pdf"; size = (Get-Item .\prueba.pdf).Length; claimId = "test-demo" } | ConvertTo-Json
try { Invoke-RestMethod -Method Post -Uri "$URL/api/upload-url" -ContentType "application/json" -Body $body }
catch { $_.Exception.Response.StatusCode.value__; $_.ErrorDetails.Message }
```
Resultado: `400` y *Tipo de archivo no permitido. Solo JPG, PNG o WEBP.*
> "El servidor valida el tipo antes de firmar."

### 2:00 · Cambiar el Content-Type → 403
Primero se pide una URL firmada para un JPG; después se intenta subir diciendo que es PNG.
```powershell
$body = @{ contentType = "image/jpeg"; size = (Get-Item .\foto.jpg).Length; claimId = "test-demo" } | ConvertTo-Json
$SIGNED = (Invoke-RestMethod -Method Post -Uri "$URL/api/upload-url" -ContentType "application/json" -Body $body).url
curl.exe -s -o NUL -w "%{http_code}`n" -X PUT -H "Content-Type: image/png" -H "x-goog-content-length-range: 0,10485760" --data-binary "@foto.jpg" $SIGNED
```
Resultado: `403`.
> "El tipo va firmado dentro de la URL. Si alguien lo cambia, Cloud Storage la rechaza aunque nuestro servidor ya no intervenga."

### 2:30 · Leer el bucket sin firma → 403
```powershell
curl.exe -s -o NUL -w "%{http_code}`n" $SIGNED.Split('?')[0]
```
Resultado: `403`.
> "Es la misma dirección pero sin firma. El bucket es privado con prevención de acceso público, y la app ni siquiera tiene permiso de lectura."

### 3:00 · Dashboard
Pestaña de Cloud Monitoring → **QuantumQuack**. Mostrar:
- **Requests por código:** se ven los 500 del primer paso y las respuestas correctas.
- **Latencia p95.**
- **Objetos en el bucket:** aumentó con la foto.

Los gráficos pueden tardar 1 o 2 minutos en actualizarse; si todavía no aparecen, volver a esta pestaña después del mail.

### 4:00 · El mail de la alerta
Abrir el mail: **"quantumquack-dev - errores 5xx en Cloud Run"**.
Si todavía no llegó: *Monitoring → Alerting* → el incidente aparece abierto. Es la misma evidencia.

### 4:30 · Destroy → 0 recursos
GitHub → Actions → **Destroy** → *Run workflow* → escribir `destroy` → *Run* → **Review deployments → Approve**. Tarda unos 40 segundos; abrir el resumen del job: **Total: 0**.
> "Toda la infraestructura se borra con un clic y se vuelve a crear desde el código en unos minutos. Así no pagamos nada fuera de la demo."

## Si algo falla

| Síntoma | Qué hacer |
|---|---|
| `http://<IP>` no carga o da 404/502 | El LB tarda 5–10 min en propagar. Pedirle a Facundo la **URL de Cloud Run** (también está en el resumen del Deploy) y usar `$URL = "https://quantumquack-dev-....run.app"`. La demo es idéntica. |
| PowerShell dice que `curl.exe` no existe | Usar Git Bash o pedir la compu de Facundo; o mostrar solo los pasos del navegador. |
| El paso 2:00 da `200` en vez de `403` | Revisar que el header sea `Content-Type: image/png` (distinto del firmado). |
| El paso 2:00 da error al pedir `$SIGNED` | La IP cambió o el servicio está frío: volver a correr `curl.exe -s "$URL/health"` y repetir. |
| La subida del portal dice *Cloud Storage rechazó la subida* | La URL venció o el archivo no es JPG/PNG/WEBP: subir de nuevo. |
| *Destroy* queda en *Waiting* | Falta aprobar: *Review deployments → Approve*. |
| No aparece el botón *Run workflow* | No tengo permiso de escritura: que lo corra Facundo desde su compu. |

## Prompt para el asistente de IA (opcional)

Para ensayar con ayuda, pegar esto en Claude (o el asistente que usen) y seguirlo paso a paso:

```text
Sos mi copiloto para la demo en vivo de QuantumQuack Insurance (proyecto de Cloud Computing, UCU). Estoy en Windows con PowerShell. Seguí exactamente la guía docs/demo-en-vivo.md del repo github.com/facusio/quantumquack (te la pego abajo). Dame UN paso por vez, decime qué tengo que ver en pantalla y qué decir, y esperá mi confirmación antes de seguir. Si algo no da el resultado esperado, usá la tabla "Si algo falla". Respuestas cortas: estoy presentando.

[pegar acá el contenido de docs/demo-en-vivo.md]
```
