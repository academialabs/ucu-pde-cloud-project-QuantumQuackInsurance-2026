# QuantumQuack Insurance · Proyecto Integrador Cloud Computing (UCU 2026)

Portal para que los asegurados suban fotos de un siniestro. El contenedor **nunca recibe la foto**: genera una URL firmada V4 de 5 minutos y el navegador hace `PUT` directo a Cloud Storage.

```
Navegador ──POST /api/upload-url──▶ Cloud Run (escala a 0)
    │                                   │ firma con su SA (signBlob, sin clave JSON)
    │◀────────── URL firmada (5 min, solo image/*, ≤10 MB) ─┘
    └──PUT directo──▶ Cloud Storage (privado, uploads/, lifecycle 30d→Coldline, 365d→Archive)
```

Todo en `us-central1` para quedar dentro del free tier. **Objetivo: USD 0 de gasto real.**

## Estructura

```
app/                      Node 22 + Express, imagen distroless
infra/bootstrap/          Lo único que se aplica a mano: state, WIF, SA de CI, presupuesto
infra/modules/            registry · bucket · container_service · lb · monitoring
infra/envs/dev/           Une los módulos
.github/workflows/        ci.yml (PR) · deploy.yml (main) · destroy.yml (manual)
docs/                     Diagramas, decisiones, runbook, seguridad, FinOps, uso de IA
```

**Documentación:** [Arquitectura y decisiones](docs/arquitectura.md) · [Runbook y recuperación ante fallos](docs/runbook.md) · [Seguridad](docs/seguridad.md) · [Matriz IAM](docs/matriz-iam.md) · [Observabilidad](docs/observabilidad.md) · [Ciclo de vida](docs/ciclo-de-vida.md) · [FinOps](docs/finops/) · [Uso de IA](docs/uso-de-ia.md) · [Presentación](docs/presentacion/)

## Integraciones

| Integración | Para qué | Cómo se autentica | Dónde está |
|---|---|---|---|
| GitHub Actions → Google Cloud | Deploy y destroy con Terraform | Workload Identity Federation (OIDC, sin claves), restringido a este repo | `infra/bootstrap/main.tf`, `.github/workflows/` |
| GitHub Actions → Artifact Registry | Subir la imagen con el tag del commit (se guardan 3 versiones) | Mismo token de WIF (`gcloud auth configure-docker`) | `.github/workflows/deploy.yml`, `infra/modules/registry/main.tf` |
| Terraform → Cloud Storage (state) | State remoto con lock y versionado | SA de CI vía WIF | `infra/envs/dev/backend.tf`, `infra/bootstrap/main.tf` |
| GitHub Environments | Aprobación manual antes de cada deploy y destroy | *Required reviewers* del environment `dev` | `.github/workflows/deploy.yml`, `destroy.yml` |
| Cloud Run → Cloud Storage | Firmar URLs V4 de subida | SA propia + `signBlob` sobre sí misma (sin clave JSON) | `infra/modules/container_service/main.tf`, `app/server.js` |
| Navegador → Cloud Storage | `PUT` directo de la foto | URL firmada de 5 min con tipo y tamaño firmados; CORS en el bucket | `infra/modules/bucket/main.tf` |
| Load balancer → Cloud Run | Entrada HTTP para la demo | NEG serverless (`enable_lb`) | `infra/modules/lb/main.tf` |
| Cloud Run → Cloud Logging | Logs de la app y de las requests (retención 7 días) | Automático (SA del servicio) | `infra/modules/monitoring/main.tf` |
| Cloud Monitoring → mail | Alerta de 5xx | Canales de email | `infra/modules/monitoring/main.tf` |
| Facturación → mail | Presupuesto de USD 1 (50/80/100 %) | Canales de email | `infra/bootstrap/main.tf` |
| Checkov, tflint, Trivy | Seguridad de Terraform y de la imagen en cada PR | Acciones de GitHub (Trivy fijada por SHA) | `.github/workflows/ci.yml` |
| Infracost | Costo estimado del cambio en el PR | Secret `INFRACOST_API_KEY` (opcional) | `.github/workflows/ci.yml` |

Detalle de cada decisión en [docs/arquitectura.md](docs/arquitectura.md) y operación en [docs/runbook.md](docs/runbook.md).

## ¿Quién puede hacer la demo?

| Situación | Qué hace falta | Cómo |
|---|---|---|
| **Integrante con acceso a este repo** | Nada que instalar: navegador, `curl` y aprobar el deploy | Sección [Día de la demo](#día-de-la-demo) y guía paso a paso en [docs/runbook.md](docs/runbook.md#6-día-de-la-demo-checklist) |
| **Cualquier otra persona** (incluida la copia en academialabs) | Cuenta de GCP con facturación, `gcloud`, `terraform` ≥ 1.9 y un repo propio en GitHub (fork o copia) | Seguir **Puesta en marcha** completa en su propia cuenta (~30 min). Todo queda dentro del free tier, salvo el LB mientras está prendido |

> La conexión entre GitHub y GCP (Workload Identity Federation) solo acepta el repo indicado en `github_repo` del bootstrap. Por eso una copia del repo no puede desplegar en nuestro proyecto: cada uno despliega en el suyo.
>
> La app no corre sola en la compu: necesita un bucket real y una service account para firmar las URLs. Lo que se reproduce en cualquier máquina es el **despliegue completo** con Terraform y GitHub Actions.

## Puesta en marcha (una sola vez)

En los comandos, reemplazar `<PROJECT_ID>` por el ID de tu proyecto (el nuestro es `quantumquack-ucu`; los IDs de GCP son únicos en todo el mundo, así que hay que elegir uno propio).

### 1. Cuenta y proyecto de GCP
1. Uno del equipo pone la cuenta de facturación. Usamos una cuenta paga: todo queda dentro del free tier y el bootstrap crea un presupuesto de USD 1 (sin contar créditos) que avisa por mail si algo empieza a cobrar.
2. Crear el proyecto (`<PROJECT_ID>`) y vincularlo a esa cuenta de facturación. Quien corre el bootstrap necesita rol **Owner** en el proyecto y permiso para crear presupuestos en la cuenta de facturación.
3. IAM → dar acceso a los otros dos integrantes (rol `Editor` alcanza para el curso; la matriz IAM explica por qué la app y CI no lo usan).

### 2. Repo de GitHub
- Crearlo **público**: GitHub Actions es ilimitado y los *required reviewers* de environments son gratis en repos públicos.
- Settings → Environments → crear `dev` con *Required reviewers* = los 3 integrantes (es la aprobación manual del deploy).

### 3. Bootstrap (desde la compu de quien abrió la cuenta)
```bash
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project <PROJECT_ID>

cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars
# completar: project_id, github_repo ("usuario/repo" desde el que corre Actions),
#            billing_account, alert_emails, budget_usd
terraform init
terraform apply
```
Anotar los outputs.

### 4. Variables y secrets en GitHub
| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `GCP_WIF_PROVIDER` | output `wif_provider` |
| Secret | `GCP_CI_SA` | output `ci_service_account` |
| Variable | `GCP_PROJECT_ID` | `<PROJECT_ID>` |
| Variable | `ALERT_EMAILS` | `["a@x.com","b@x.com","c@x.com"]` |
| Variable | `ENABLE_LB` | `false` (poner `true` solo el día de la demo) |
| Secret (opcional) | `INFRACOST_API_KEY` | clave gratis de infracost.io |

Antes del primer commit: `terraform fmt -recursive infra`.

### 5. Primer deploy y validación
Actions → **Deploy** → *Run workflow* → aprobar en el environment `dev`. El resumen del job muestra la URL. Validar con las pruebas de [docs/runbook.md](docs/runbook.md#4-validación-smoke-tests).

## Uso diario

- **PR a main** → `ci.yml`: fmt, validate, tflint, Checkov, Trivy sobre la imagen, plan como comentario e Infracost.
- **Merge a main** → `deploy.yml`: espera aprobación, crea el registry, build y push con tag del commit, `terraform apply`.
- **Destroy** → Actions → *Destroy* → *Run workflow* → escribir `destroy`.

## Día de la demo
> Guía completa para quien presenta, con comandos de PowerShell (Windows), qué decir en cada paso y qué hacer si algo falla: **[docs/demo-en-vivo.md](docs/demo-en-vivo.md)**.

1. Variable `ENABLE_LB=true` y correr *Deploy* a mano: crea el LB en ~3 min y la IP sale en el resumen del job.
2. **Al principio de la demo**, abrir `<url>/api/boom` un par de veces para disparar la alerta. El mail llega unos **4 minutos** después del primer `/api/boom` (medido el 18/11): casi todo ese tiempo es la demora con la que Cloud Run publica la métrica, y el mail sale a los pocos segundos de abrirse el incidente.
3. Subir una foto con número de siniestro `test-demo` (se borra sola a los 7 días).
4. Probar un PDF: el servidor lo rechaza. Si se manipula el `Content-Type`, Cloud Storage responde 403 porque el tipo está firmado.
5. `curl https://storage.googleapis.com/<bucket>/uploads/...` → 403 (bucket no público).
6. Mostrar el dashboard *QuantumQuack* en Cloud Monitoring.
7. **Al final**, mostrar el mail de la alerta que se disparó en el paso 2.
8. Después: `ENABLE_LB=false` y correr *Destroy*. Captura del resumen (0 recursos) y de Facturación.

## Si algo falla
| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `auth` falla en Actions | Secret mal copiado o repo distinto al de `github_repo` | Revisar secrets y el `attribute_condition` del provider |
| 403 al subir la foto | Content-Type distinto al firmado o URL vencida (5 min) | Volver a pedir la URL |
| Error CORS en el navegador | Falta `x-goog-content-length-range` en `response_header` | Revisar módulo `bucket` |
| `sign_failed` en los logs | Falta `serviceAccountTokenCreator` de la SA sobre sí misma | `terraform apply` de nuevo |
| El LB responde 404/502 | Todavía propagando | Esperar 5–10 min |
| Destroy deja recursos | Lock del state | `terraform force-unlock <id>` y reintentar |

## Costos (por qué da USD 0)
| Recurso | Cómo se mantiene en 0 |
|---|---|
| Cloud Run | Escala a 0, tope de 2 instancias; tráfico de demo muy por debajo del free tier |
| Artifact Registry | Imagen distroless (menos de 100 MB) y se guardan solo 3 versiones → menos de 0,5 GB gratis |
| Cloud Storage | `us-central1` Standard, MB de datos; se borra antes de los 30 días (no llega a Coldline) |
| Logging | Retención 7 días, muy por debajo de los 50 GiB gratis |
| Monitoring, WIF, IAM, presupuestos | Sin costo |
| Load balancer | **Único recurso con costo por hora**. Solo existe unas horas el día de la demo (9 min de prueba el 18/11 ≈ USD 0,004) |
