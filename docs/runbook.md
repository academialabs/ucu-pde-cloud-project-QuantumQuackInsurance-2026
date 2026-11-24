# Runbook · QuantumQuack Insurance

Cómo **desplegar desde cero, configurar, operar, validar y recuperar** la solución. Pensado para que cualquiera del equipo (o el docente) pueda reproducirla sin ayuda.

Valores del entorno actual:

| Dato | Valor |
|---|---|
| Proyecto GCP | `quantumquack-ucu` |
| Región | `us-central1` |
| Servicio Cloud Run | `quantumquack-dev` |
| Bucket de fotos | `quantumquack-ucu-quantumquack-dev-claims` |
| Bucket del state | `quantumquack-ucu-tfstate` (prefijo `envs/dev`) |
| Repositorio de imágenes | `us-central1-docker.pkg.dev/quantumquack-ucu/quantumquack/app` |

---

## 1. Requisitos

- Cuenta de GCP con facturación (usamos una cuenta paga; todo queda dentro del free tier).
- Rol **Owner** en el proyecto para quien corre el bootstrap (solo esa vez).
- En la compu local: `gcloud` y `terraform` ≥ 1.9 (CI usa 1.17.2).
- Repositorio en GitHub, **público** (Actions ilimitado y *required reviewers* gratis).

## 2. Despliegue desde cero

### 2.1 Proyecto
1. Crear el proyecto `quantumquack-ucu` y vincularlo a la cuenta de facturación.
2. IAM: dar acceso a los integrantes (para el curso alcanza con `Editor`; la app y CI no lo usan).

### 2.2 Bootstrap (una sola vez, a mano)
Crea las APIs, el bucket del state, WIF, la SA de CI, el presupuesto y los canales de mail.
```bash
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project quantumquack-ucu

cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
# completar: project_id, github_repo ("owner/repo"), billing_account, alert_emails, budget_usd = 1
terraform init
terraform apply
terraform output     # anotar wif_provider y ci_service_account
```
> `terraform.tfvars` está en `.gitignore`: tiene el ID de facturación y mails reales. **No se sube.**

### 2.3 Configuración en GitHub
**Settings → Environments → `dev`**: *Required reviewers* = los 3 integrantes.

**Settings → Secrets and variables → Actions:**

| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `GCP_WIF_PROVIDER` | output `wif_provider` |
| Secret | `GCP_CI_SA` | output `ci_service_account` |
| Variable | `GCP_PROJECT_ID` | `quantumquack-ucu` |
| Variable | `ALERT_EMAILS` | `["a@x.com","b@x.com","c@x.com"]` |
| Variable | `ENABLE_LB` | `false` |
| Secret (opcional) | `INFRACOST_API_KEY` | clave gratuita de infracost.io |

### 2.4 Primer deploy
1. Actions → **Deploy** → *Run workflow* (o hacer merge de cualquier cambio de código a `main`).
2. Aprobar el job en el environment `dev`.
3. El job crea el registry, construye y sube la imagen con el tag del commit y corre `terraform apply`.
4. El **resumen del job** muestra la URL de Cloud Run y la IP del LB, si está prendido.

Duración aproximada: 4–6 minutos (con el LB, unos 3 minutos más).

## 3. Operación diaria

| Acción | Cómo |
|---|---|
| Cambiar código o infraestructura | Rama → PR a `main` → `ci.yml` corre los chequeos y comenta el plan → revisión → merge → aprobar el deploy |
| Cambiar solo documentación | Push o PR normal; `deploy.yml` **no** corre (`paths-ignore`) |
| Prender el LB | Variable `ENABLE_LB=true` → correr *Deploy* a mano |
| Apagar el LB | Variable `ENABLE_LB=false` → correr *Deploy* a mano (o *Destroy*) |
| Borrar todo el entorno | Actions → **Destroy** → escribir `destroy` → aprobar |
| Ver logs | Consola → Logging → filtro `resource.type="cloud_run_revision"` |
| Ver métricas | Consola → Monitoring → Dashboards → **QuantumQuack** |
| Ver costo | Consola → Facturación → Informes (filtrar por el proyecto) |

**Reglas del equipo:**
- Nunca hacer `terraform apply` de `envs/dev` desde la compu: todo pasa por CI. Si es imprescindible, ver la sección 5.4.
- Nunca dejar el LB prendido sin una demo en curso.
- Nunca pegar claves, el ID de facturación o mails reales en el repo.

## 4. Validación (smoke tests)

Reemplazar `$URL` por la URL de Cloud Run o `http://<IP del LB>`.

| # | Prueba | Comando | Resultado esperado |
|---|---|---|---|
| 1 | Salud | `curl -s $URL/health` | `ok` |
| 2 | Pedir una URL válida | `curl -s -X POST $URL/api/upload-url -H 'Content-Type: application/json' -d '{"contentType":"image/jpeg","size":1000,"claimId":"test-smoke"}'` | JSON con `url` y `expiresInSeconds: 300` |
| 3 | Tipo no permitido | lo mismo con `"contentType":"application/pdf"` | **400** |
| 4 | Archivo grande | lo mismo con `"size":20000000` | **400** |
| 5 | Subir la foto | `curl -X PUT -H 'Content-Type: image/jpeg' -H 'x-goog-content-length-range: 0,10485760' --data-binary @foto.jpg "<url del paso 2>"` | **200** |
| 6 | Content-Type manipulado | el PUT anterior con `Content-Type: image/png` | **403** (el tipo está firmado) |
| 7 | Bucket no público | `curl -I https://storage.googleapis.com/<bucket>/uploads/<objeto>` | **403** |
| 8 | Alerta | abrir `$URL/api/boom` 2 o 3 veces | **500** y mail de alerta a los ~4 min |
| 9 | Destroy | correr *Destroy* | Resumen: *Total: 0* |

> Los pasos 2, 5 y 6 también se pueden probar desde el formulario del portal. Con `claimId` empezando en `test-`, el objeto queda en `uploads/test-…/` y se borra solo a los 7 días.

Evidencias de estas pruebas: [`evidencias/`](evidencias/).

## 5. Recuperación ante fallos

### 5.1 Una versión nueva de la app rompe el portal
**Síntoma:** errores 5xx en el dashboard o alerta por mail después de un deploy.

**Mitigación inmediata (segundos): volver a la revisión anterior de Cloud Run.**
```bash
gcloud run revisions list --service quantumquack-dev --region us-central1
gcloud run services update-traffic quantumquack-dev --region us-central1 \
  --to-revisions <REVISION_ANTERIOR>=100
```
**Arreglo definitivo:** `git revert <commit>` → PR → merge → deploy. El próximo `terraform apply` manda el tráfico a la revisión nueva, así que el rollback manual dura solo hasta el siguiente deploy.

> Artifact Registry conserva las **3 imágenes más recientes**, así que se puede volver hasta 3 versiones atrás.

### 5.2 Falla el job de Deploy
| Paso que falla | Causa probable | Qué hacer |
|---|---|---|
| `auth` | Secret mal copiado, o el repo no coincide con `github_repo` del bootstrap (`attribute_condition`) | Revisar los secrets. Si se renombró o movió el repo: ver 5.5 |
| `terraform init` | Variable `GCP_PROJECT_ID` vacía o falta el bucket del state | Revisar la variable; si se borró el bucket, ver 5.3 |
| `Build y push` | Error de compilación o de permisos sobre el registry | Ver el log del paso; probar `docker build app` local |
| `terraform apply` con *Error acquiring the state lock* | Otro job quedó cortado a la mitad | Ver 5.4 |
| `terraform apply` con *403 / permission denied* | Falta un rol en la SA de CI | Agregarlo en `infra/bootstrap/main.tf` y aplicar el bootstrap |
| El LB responde 404 o 502 | Todavía está propagando | Esperar 5–10 minutos |

Un deploy fallido **no deja caído el servicio**: Cloud Run sigue sirviendo la última revisión sana hasta que una nueva pasa el *startup probe* (`/health`).

### 5.3 El state se corrompió o se perdió
El bucket `quantumquack-ucu-tfstate` tiene **versionado**.
```bash
gcloud storage ls -a gs://quantumquack-ucu-tfstate/envs/dev/default.tfstate
gcloud storage cp "gs://quantumquack-ucu-tfstate/envs/dev/default.tfstate#<GENERATION>" \
  gs://quantumquack-ucu-tfstate/envs/dev/default.tfstate
```
Si se perdió todo el bucket: volver a aplicar el bootstrap y después usar `terraform import` sobre los recursos existentes, o (en dev) borrarlos desde la consola y desplegar de nuevo.

### 5.4 State bloqueado
**Síntoma:** *Error acquiring the state lock*, después de que un job se canceló a la mitad.
1. Confirmar en Actions que **no hay otro Deploy o Destroy corriendo**.
2. Con credenciales de un integrante:
   ```bash
   cd infra/envs/dev
   terraform init -backend-config="bucket=quantumquack-ucu-tfstate"
   terraform force-unlock <LOCK_ID>   # el ID aparece en el mensaje de error
   ```
3. Volver a correr el workflow.

### 5.5 CI no puede autenticarse (WIF)
**Causas:**
- el repo cambió de nombre o de dueño (el provider solo acepta `facusio/quantumquack`);
- se borró o deshabilitó el pool o el provider;
- los secrets están mal.

**Qué hacer:**
1. En `infra/bootstrap/terraform.tfvars`, poner `github_repo = "<owner>/<repo nuevo>"` y correr `terraform apply` en el bootstrap.
2. Volver a cargar `GCP_WIF_PROVIDER` y `GCP_CI_SA` en el repo nuevo, recrear el environment `dev` con sus reviewers y las variables.
3. Correr *Deploy* a mano para verificar.

> Un pool de WIF borrado queda 30 días en estado *deleted* y su ID no se puede reutilizar. Se puede restaurar con `gcloud iam workload-identity-pools undelete github-pool --location global`.

### 5.6 Llega una alerta de presupuesto
El presupuesto es de **USD 1 sin contar créditos**: si llega el aviso del 50 %, algo se salió del free tier.
1. Facturación → Informes → agrupar por **SKU** para ver qué está cobrando.
2. Causas probables, por orden:
   1. **el LB quedó prendido** → `ENABLE_LB=false` + Deploy, o *Destroy*;
   2. demasiadas imágenes en el registry → revisar la política de limpieza;
   3. tráfico anómalo en Cloud Run → revisar logs y considerar bajar `max_instances`.
3. Si no se identifica la causa y el gasto sigue: **Destroy** del entorno dev. En último caso, desvincular la facturación del proyecto (detiene todos los servicios).

### 5.7 Llega una alerta de errores 5xx
1. Dashboard → *Requests por código*: ¿es un pico aislado o sostenido?
2. Logging → filtrar `severity>=ERROR`. Si aparece `sign_failed`, a la SA le falta `serviceAccountTokenCreator` sobre sí misma: correr *Deploy* para que Terraform la recree.
3. Si empezó con un deploy: ver 5.1.
4. Si fue `/api/boom`: es la prueba de la demo; el incidente se cierra solo a los 30 minutos.

### 5.8 El usuario no puede subir la foto
| Síntoma en el navegador | Causa | Solución |
|---|---|---|
| 400 al pedir la URL | Tipo no permitido o más de 10 MB | Esperado: usar JPG, PNG o WEBP de menos de 10 MB |
| 403 en el PUT | URL vencida (5 min) o Content-Type distinto al firmado | Volver a pedir la URL |
| Error de CORS | Falta `x-goog-content-length-range` en el `response_header` del bucket | Revisar el módulo `bucket` y desplegar |

### 5.9 Recrear todo desde cero
Si el proyecto quedó en un estado irrecuperable:
1. Actions → *Destroy* (o borrar los recursos desde la consola).
2. Si hace falta, crear un proyecto nuevo y repetir la sección 2 completa con el nuevo `project_id`.
3. Validar con la sección 4.

Tiempo estimado: 20–30 minutos.

## 6. Día de la demo (checklist)

**2 horas antes:**
- [ ] `ENABLE_LB=true` → *Deploy* → aprobar → anotar la IP del LB.
- [ ] Smoke test 1 contra la IP.

**Durante la demo:**
1. Abrir `<IP>/api/boom` 2 o 3 veces (el mail llega a los ~4 min).
2. Subir una foto con siniestro `test-demo`.
3. Probar un PDF → 400. Manipular el Content-Type → 403.
4. `curl` al objeto sin firma → 403.
5. Mostrar el dashboard.
6. Mostrar el mail de la alerta.

**Después:**
- [ ] `ENABLE_LB=false` → *Destroy* → captura del resumen (*Total: 0*).
- [ ] Captura de Facturación.
- [ ] Guardar las capturas en `docs/evidencias/`.

**Plan B** si el LB o GCP fallan en vivo: usar la URL `*.run.app` (no depende del LB) y, si tampoco responde, el video de respaldo grabado en el ensayo.
