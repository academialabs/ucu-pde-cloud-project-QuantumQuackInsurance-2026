# Uso de IA en el proyecto

El proyecto se hizo con **desarrollo asistido por IA**. Este documento cuenta con honestidad qué herramientas usamos, para qué, ejemplos de los prompts y las reglas que seguimos para que el resultado fuera confiable.

## 1. Herramientas

| Herramienta | Quién | Para qué |
|---|---|---|
| **Claude (Anthropic)**, app de escritorio con acceso a la terminal y al navegador | Facundo | Código de la app, Terraform, workflows de GitHub Actions, depuración de errores, revisión de las entregas del equipo, organización del Trello, documentación y la presentación |
| _completar_ | Gastón | _completar (ej.: diagrama, matriz IAM, evidencias de seguridad)_ |
| **Claude (Anthropic)**, app con acceso a Google Sheets, al repo y al navegador | Luca | Armar la planilla FinOps (buscar los precios oficiales de Cloud Storage, fórmulas, gráficos y ajustes según la revisión del equipo), recorrer la consola en la prueba de observabilidad (subidas de prueba, `/api/boom`, capturas) y redactar `observabilidad.md`, el informe FinOps, la justificación de proveedor v2 y el guion de mis slides. Los datos del costo real, los tiempos de la alerta y la experiencia del equipo los aporté y revisé yo |
| Herramientas automáticas en CI (no son IA generativa) | Todos | Checkov, tflint, Trivy e Infracost revisan cada PR |

## 2. Qué hizo la IA y qué hicimos nosotros

**Lo generó mayormente la IA, revisado y ajustado por el equipo:**
- `app/server.js`, `app/public/index.html` y el `Dockerfile`.
- Los módulos de Terraform y el bootstrap.
- Los tres workflows.
- El README, `arquitectura.md`, `runbook.md` y este documento.
- La estructura y el texto de las slides.

**Lo decidimos o hicimos nosotros:**
- Las restricciones del proyecto (gasto USD 0, GCP, alcance).
- Crear y configurar la cuenta, el proyecto y el repo, y aplicar el bootstrap.
- Aprobar cada deploy y correr las pruebas de la demo.
- Las capturas y evidencias.
- El diagrama en draw.io, la matriz IAM, la planilla FinOps y la justificación del proveedor, con revisión de la IA.
- Defender cada decisión en la presentación.

**Errores de la IA que detectamos y corregimos** (prueba de que la revisión humana hizo falta):
- Usó `/healthz` como endpoint de salud y en Cloud Run devolvía 404, porque la plataforma reserva las rutas que terminan en `z`. Lo cambiamos a `/health`.
- Fijó `trivy-action` a un tag que ya no existía. Lo fijamos por SHA.
- La imagen base debian12 tenía CVEs que Trivy marcó. Pasamos a debian13.
- Un commit que tocaba el propio `deploy.yml` disparó un deploy innecesario, porque `paths-ignore` solo aplica si *todos* los archivos cambiados coinciden. Lo cancelamos.
- Dio por hecho una fecha (martes en vez de miércoles) y algunos datos del diagrama (presupuesto de USD 5, "prueba gratuita") que no coincidían con la realidad. Los corregimos.

## 3. Ejemplos de prompts

Resumidos, en el orden en que se usaron:

1. **Arranque:** "Revisá el documento que hizo mi compañero y el Trello con las tareas. Arranquemos con el proyecto. No queremos gastar nada de plata."
2. **Organización:** "Limpiá el Trello y ordená las tareas entre los tres de la forma más efectiva posible, con el paso a paso en cada tarjeta."
3. **Infraestructura:** "Quiero hacer el bootstrap con Terraform pero me da error" (con captura de la terminal).
4. **Depuración:** "Me devolvió 404 el curl a /healthz."
5. **Seguridad:** "Gastón encontró CVEs con Trivy en la imagen", con el reporte pegado.
6. **Revisión de entregas:** "Luca hizo la planilla FinOps, revisala y decime qué está mal para pasárselo."
7. **Documentación:** "Necesito explicarle al profe el estado del proyecto" / "Armá la estructura de la presentación y las slides."

## 4. Lineamientos que seguimos

1. **Ningún secreto a la IA.** Nunca le pasamos claves, tokens ni contraseñas. El ID de facturación y los mails reales viven solo en `terraform.tfvars` (en `.gitignore`), y el diseño evita las claves JSON (WIF y signBlob).
2. **Todo pasa por PR y CI.** El código generado no se aplica directo: pasa por fmt, tflint, Checkov, Trivy y `terraform plan` y, para desplegar, por la aprobación manual de un integrante.
3. **Verificar contra la documentación oficial.** Para precios, límites del free tier y comportamiento de los servicios usamos la documentación y la calculadora de Google Cloud, no la respuesta de la IA.
4. **Probar en la nube real.** Cada afirmación de la presentación tiene una evidencia: captura, resumen de Actions o mail de la alerta.
5. **Entender antes de defender.** Si no podemos explicar una decisión, no va. Por eso [`arquitectura.md`](arquitectura.md) documenta cada decisión con su alternativa descartada.
6. **Acciones sensibles por una persona.** Abrir la cuenta, la facturación, aprobar deploys, correr el destroy y gestionar permisos los hicimos nosotros.
7. **Transparencia.** Este documento existe porque el uso de IA es parte del proceso de desarrollo y tiene que poder auditarse.

## 5. Aprendizajes

- La IA acelera mucho la parte mecánica (Terraform, YAML, boilerplate), pero **no conoce el estado real del entorno**. Los errores aparecieron al chocar con la plataforma, no al escribir el código.
- Un **pipeline con chequeos automáticos** es lo que hace seguro usar código generado: Trivy y Checkov atraparon cosas que nadie había visto.
- Lo más valioso fue usarla como **revisor**: del diagrama, de la planilla y de las evidencias.
