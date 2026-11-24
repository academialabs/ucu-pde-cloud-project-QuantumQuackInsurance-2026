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

## Puesta en marcha (una sola vez)

### 1. Cuenta y proyecto de GCP
1. Uno del equipo pone la cuenta de facturación. Usamos una cuenta paga: todo queda dentro del free tier y el bootstrap crea un presupuesto de USD 1 (sin contar créditos) que avisa por mail si algo empieza a cobrar.
2. Crear el proyecto (ej. `quantumquack-ucu`) y vincularlo a esa cuenta de facturación.
3. IAM → dar acceso a los otros dos integrantes (rol `Editor` alcanza para el curso; la matriz IAM explica por qué la app y CI no lo usan).

### 2. Repo de GitHub
- Crearlo **público**: GitHub Actions es ilimitado y los *required reviewers* de environments son gratis en repos públicos.
- Settings → Environments → crear `dev` con *Required reviewers* = los 3 integrantes (es la aprobación manual del deploy).

### 3. Bootstrap (desde la compu de quien abrió la cuenta)
```bash
gcloud auth login
gcloud auth application-default login
gcloud auth application-default set-quota-project quantumquack-ucu

cd infra/bootstrap
cp terraform.tfvars.example terraform.tfvars   # completar
terraform init
terraform apply
```
Anotar los outputs.

### 4. Variables y secrets en GitHub
| Tipo | Nombre | Valor |
|---|---|---|
| Secret | `GCP_WIF_PROVIDER` | output `wif_provider` |
| Secret | `GCP_CI_SA` | output `ci_service_account` |
| Variable | `GCP_PROJECT_ID` | `quantumquack-ucu` |
| Variable | `ALERT_EMAILS` | `["a@x.com","b@x.com","c@x.com"]` |
| Variable | `ENABLE_LB` | `false` (poner `true` solo el día de la demo) |
| Secret (opcional) | `INFRACOST_API_KEY` | clave gratis de infracost.io |

Antes del primer commit: `terraform fmt -recursive infra`.

## Uso diario

- **PR a main** → `ci.yml`: fmt, validate, tflint, Checkov, Trivy sobre la imagen, plan como comentario e Infracost.
- **Merge a main** → `deploy.yml`: espera aprobación, crea el registry, build y push con tag del commit, `terraform apply`.
- **Destroy** → Actions → *Destroy* → *Run workflow* → escribir `destroy`.

## Día de la demo
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
