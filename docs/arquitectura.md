# Arquitectura y decisiones de diseño

Este documento explica **qué** construimos y, sobre todo, **por qué**: cada decisión tiene la alternativa que descartamos y el motivo. Los diagramas están en [`arquitectura-final.png`](arquitectura-final.png) (versión final) y [`arquitectura-v1.png`](arquitectura-v1.png) (primera versión).

## 1. Problema

QuantumQuack Insurance necesita que los asegurados suban fotos de un siniestro desde el navegador. Requisitos de la consigna y propios:

- Las fotos son datos sensibles: el bucket **no puede ser público**.
- Se acumulan muchas y casi nunca se vuelven a mirar después del primer mes: hay que **bajar el costo de almacenamiento con el tiempo**.
- Toda la infraestructura tiene que ser **reproducible** (IaC), desplegarse por **CI/CD** y tener **observabilidad**.
- Restricción del equipo: **gastar USD 0**.

## 2. Vista general

```
Asegurado (navegador)
   │ 1. POST /api/upload-url {contentType, size}
   ▼
[Load Balancer HTTP]  ← solo el día de la demo (enable_lb)
   ▼
Cloud Run "quantumquack-dev"  (Node 22, distroless, escala 0–2)
   │ 2. valida tipo y tamaño, firma URL V4 (5 min) con signBlob de su propia SA
   ▼
   ◀── URL firmada
   │ 3. PUT directo de la foto
   ▼
Cloud Storage privado  uploads/…  (30 d → Coldline, 365 d → Archive)

Cloud Monitoring: dashboard + alerta 5xx → mail     Cloud Logging: retención 7 días
GitHub Actions ──WIF (sin claves)──▶ SA de CI ──▶ Terraform (state en GCS versionado)
Presupuesto de facturación USD 1 (antes de créditos) → mail
```

Región única: `us-central1` (entra en el free tier de Cloud Run, Cloud Storage y Artifact Registry).

## 3. Decisiones de diseño

### D1. Proveedor: Google Cloud
- **Elegimos** GCP porque el free tier de Cloud Run, Cloud Storage y Artifact Registry cubre todo el tráfico de un proyecto académico, el ciclo de vida de Storage resuelve el requisito de clases de almacenamiento sin código, y Workload Identity Federation con GitHub es nativo.
- **Descartamos** AWS y Azure. La comparación completa está en [`justificacion-proveedor-v2.pdf`](justificacion-proveedor-v2.pdf).

### D2. Subida con URL firmada V4 (el contenedor nunca toca la foto)
- **Elegimos** que Cloud Run solo genere una URL firmada de 5 minutos y que el navegador haga `PUT` directo a Cloud Storage.
- **Descartamos** recibir la foto en el contenedor y reenviarla. Hubiera duplicado el tráfico, alargado los requests (más tiempo de CPU facturable) y obligado a manejar archivos de 10 MB en memoria.
- **Controles firmados dentro de la URL:** el `Content-Type` (solo JPG, PNG o WEBP) y el header `x-goog-content-length-range: 0,10485760`. Si el cliente cambia el tipo o manda más de 10 MB, **Cloud Storage responde 403**, aunque el servidor ya no intervenga.
- **Doble validación:** el servidor rechaza con 400 tipos o tamaños inválidos antes de firmar, así el usuario recibe un mensaje claro.

### D3. Firma sin claves JSON (signBlob)
- **Elegimos** que la SA del contenedor firme con la API `signBlob` sobre sí misma (`roles/iam.serviceAccountTokenCreator` sobre su propia SA).
- **Descartamos** una clave JSON en un secret. Una clave filtrada vale para siempre; signBlob usa credenciales de corta vida del metadata server.

### D4. Cómputo: Cloud Run con escala a cero
- **Elegimos** Cloud Run: escala de 0 a 2 instancias, `cpu_idle = true` (CPU solo mientras atiende) y 512 MiB.
- **Descartamos** GKE (el plano de control de un cluster cuesta aunque esté vacío) y Compute Engine (una VM prendida 24/7 y parches del sistema operativo a cargo nuestro). App Engine habría funcionado, pero Cloud Run usa un contenedor estándar y portable.
- El **tope de 2 instancias** es una defensa de costo: aunque alguien ataque el portal, no puede escalar sin límite.

### D5. Imagen distroless
- **Elegimos** una build en dos etapas: `node:22-alpine` para instalar y `gcr.io/distroless/nodejs22-debian13:nonroot` para ejecutar. No tiene shell ni gestor de paquetes y corre como usuario no root.
- **Por qué debian13:** Trivy encontró CVEs en la base debian12 y al pasar a debian13 desaparecieron.
- Imagen chica, entonces menos espacio en Artifact Registry (free tier de 0,5 GB) y menos superficie de ataque.

### D6. Bucket privado con ciclo de vida
- `public_access_prevention = enforced` y `uniform_bucket_level_access = true`: es imposible hacer público un objeto, aunque alguien se equivoque con un permiso.
- **Ciclo de vida:** a los 30 días pasa a Coldline y a los 365 a Archive. Los prefijos de prueba (`uploads/test-`, `uploads/sin-numero/`) se borran a los 7 días. Detalle en [`ciclo-de-vida.md`](ciclo-de-vida.md).
- **Descartamos** Autoclass. Mueve los objetos según el acceso, pero cobra un cargo de gestión por objeto y la consigna pedía reglas explícitas.
- **Cifrado:** claves administradas por Google. **Descartamos** CMEK (Cloud KMS) porque cobra por clave y por operación y no agrega valor para el alcance del curso.
- `force_destroy = true` para que el destroy no falle si quedaron fotos de prueba (aceptable en dev, no en producción).

### D7. Mínimo privilegio en IAM
- La app tiene **su propia SA** (no la SA por defecto de Compute, que tiene rol Editor).
- La SA de la app solo tiene `storage.objectCreator` y **solo bajo `uploads/`** (condición IAM). No puede leer, listar ni borrar fotos.
- CI usa otra SA con roles acotados a lo que despliega. Matriz completa en [`matriz-iam.md`](matriz-iam.md).
- **Pendiente conocido:** la SA por defecto de Compute sigue teniendo Editor en el proyecto (lo crea Google al activar la API). Nadie la usa, pero la mejora es quitarle ese rol desde el bootstrap.

### D8. CI/CD con Workload Identity Federation
- **Elegimos** GitHub Actions + WIF: GitHub emite un token OIDC por job y GCP lo cambia por credenciales de la SA de CI, que duran una hora.
- El provider solo acepta tokens del repositorio `facusio/quantumquack` (`attribute_condition`). Un fork o cualquier otro repo no puede desplegar.
- **Descartamos** una clave JSON en los secrets de GitHub, por el mismo motivo que en D3.
- **Tres workflows:**
  - `ci.yml` (en cada PR): fmt, tflint, Checkov, validate, el plan como comentario, Infracost y Trivy sobre la imagen.
  - `deploy.yml` (merge a `main`): aprobación manual en el environment `dev`, registry, build y push con el tag del commit, y `terraform apply`.
  - `destroy.yml` (manual): hay que escribir `destroy`.
- Las acciones de terceros críticas van **fijadas por SHA**. `trivy-action` se fijó así después de un incidente de cadena de suministro con tags reescritos (CVE-2026-33634).
- `paths-ignore` evita desplegar cuando solo cambia documentación.

### D9. Terraform modular con state remoto
- **Bootstrap** (se aplica una sola vez, a mano): APIs, bucket del state (versionado), WIF, SA de CI, presupuesto y canales de mail.
- **Módulos** (`registry`, `bucket`, `container_service`, `lb`, `monitoring`), que se unen en `envs/dev`. Agregar un entorno `prod` es otra carpeta con otras variables.
- **State en GCS** con versionado: si se corrompe, se recupera una versión anterior (ver el runbook). El lock nativo del backend evita dos applies a la vez, y además los workflows comparten el grupo de `concurrency`.
- **Etiquetas obligatorias** en todos los recursos (`project`, `team`, `env`, `owner`) para poder atribuir costos.

### D10. Load balancer opcional
- El LB HTTP externo con NEG serverless **cobra por hora** (la forwarding rule). Por eso está detrás de `enable_lb` (por defecto `false`) y solo se crea el día de la demo.
- Sin LB, Cloud Run ya expone una URL HTTPS `*.run.app`.
- En la prueba del 18/11 el LB estuvo prendido unos 9 minutos y el costo fue de unos USD 0,004.

### D11. Observabilidad
- **Dashboard** "QuantumQuack" con requests por código, latencia p95, y cantidad de objetos y bytes en el bucket.
- **Alerta** ante cualquier 5xx en un minuto, que manda mail a los tres integrantes. `/api/boom` la dispara a propósito. Medimos unos 4 minutos desde el primer error hasta el mail, casi todo por la demora con que Cloud Run publica la métrica.
- **Logs** con retención de 7 días (más que suficiente y lejos de los 50 GiB gratis).
- Detalle en [`observabilidad.md`](observabilidad.md).

### D12. FinOps: presupuesto de USD 1 antes de créditos
- **Presupuesto de USD 1** con avisos al 50, 80 y 100 % y `EXCLUDE_ALL_CREDITS`: avisa por el gasto real **antes** de que lo cubran créditos. Si algo se sale del free tier, nos enteramos aunque la factura dé 0.
- Un presupuesto en GCP **avisa pero no corta**. El corte real lo dan el diseño (escala a cero, tope de instancias, LB apagado) y el destroy después de la demo.
- **Análisis de costos** en [`finops/`](finops/):
  - Con 1 TiB por mes durante 12 meses, guardar todo en Standard costaría USD 1.597; con el ciclo de vida baja a USD 593 (−62,9 %).
  - Costo real de noviembre: unos USD 0,004.

## 4. Seguridad (resumen)

| Amenaza | Control |
|---|---|
| Alguien lee las fotos | Bucket privado + prevención de acceso público; la SA de la app no tiene permiso de lectura |
| Subir un archivo no permitido o enorme | Validación en el servidor (400) + tipo y tamaño firmados (403 en Storage) |
| URL firmada filtrada | Vence en 5 minutos y solo permite escribir ese objeto, con ese tipo |
| Robo de credenciales de CI | No existen claves: WIF con tokens de corta vida, limitado a un repo |
| Vulnerabilidades en la imagen o el Terraform | Trivy y Checkov en cada PR |
| Costo descontrolado | Tope de 2 instancias, LB opcional, presupuesto de USD 1 con alertas |

Más detalle y evidencias en [`seguridad.md`](seguridad.md) y [`evidencias/seguridad/`](evidencias/seguridad/).

## 5. Qué cambiaríamos para producción

- **HTTPS en el LB** con certificado administrado y dominio propio, **Cloud Armor** (WAF y rate limiting) y un **CORS restringido** al dominio del portal (hoy es `*`).
- **Quitar el rol Editor** a la SA por defecto de Compute y aplicar políticas de organización.
- **Entorno `prod` separado** (otro proyecto) con `force_destroy = false` y retención de logs mayor.
- **Procesamiento posterior a la subida** (Eventarc → función que valida la imagen real, quita metadatos EXIF y asocia la foto al siniestro).
- **Proyección de costo en producción:** entre USD 614 y 1.314 por año según el volumen (ver la planilla FinOps).
