# Uso de IA en el proyecto

El proyecto se hizo con **desarrollo asistido por IA**. Este documento cuenta con honestidad qué herramientas usamos, para qué, ejemplos de los prompts y las reglas que seguimos para que el resultado fuera confiable.

## 1. Herramientas

| Herramienta | Quién | Para qué |
|---|---|---|
| **Claude (Anthropic)**, app de escritorio con acceso a la terminal y al navegador | Facundo | Código de la app, Terraform, workflows de GitHub Actions, depuración de errores, revisión de las entregas del equipo, organización del Trello, documentación y la presentación |
| **Claude (Anthropic)**, con acceso a GitHub, Chrome y Cloud Shell | Gastón | Entender las consignas de las tarjetas del Trello y armar el paso a paso de cada tarea. Además, bajo mi supervisión, generó el diagrama en draw.io (v1 y final), la matriz IAM, `seguridad.md`, `ciclo-de-vida.md` y las evidencias de seguridad: corrió las pruebas en Cloud Shell y sacó las capturas. Yo revisé cada entrega, pedí correcciones y decidí qué se subía a main. |
| **Claude (Anthropic)**, app con acceso a Google Sheets, al repo y al navegador | Luca | Armar la planilla FinOps (buscar los precios oficiales de Cloud Storage, fórmulas, gráficos y ajustes según la revisión del equipo), recorrer la consola en la prueba de observabilidad (subidas de prueba, `/api/boom`, capturas) y redactar `observabilidad.md`, el informe FinOps, la justificación de proveedor v2 y el guion de mis slides. Los datos del costo real, los tiempos de la alerta y la experiencia del equipo los aporté y revisé yo |
| Herramientas automáticas en CI (no son IA generativa) | Todos | Checkov, tflint, Trivy e Infracost revisan cada PR |

## 2. Qué hizo la IA y qué hicimos nosotros

**Lo generó mayormente la IA, revisado y ajustado por el equipo:**
- `app/server.js`, `app/public/index.html` y el `Dockerfile`.
- Los módulos de Terraform y el bootstrap.
- Los tres workflows.
- El README, `arquitectura.md`, `runbook.md` y este documento.
- La estructura y el texto de las slides.
- El diagrama en draw.io, la matriz IAM, `seguridad.md`, `ciclo-de-vida.md`, `observabilidad.md`, la planilla e informe FinOps y la justificación de proveedor, cada uno bajo la supervisión del integrante responsable.

**Lo decidimos o hicimos nosotros:**
- Las restricciones del proyecto (gasto USD 0, GCP, alcance).
- Crear y configurar la cuenta, el proyecto y el repo, y aplicar el bootstrap.
- Aprobar cada deploy y supervisar las pruebas en la nube real (subidas, alertas, accesos denegados).
- Aportar los datos reales: costo de noviembre, tiempos de la alerta, experiencia del equipo.
- Revisar cada entrega, pedir correcciones y decidir qué se subía a `main`.
- Defender cada decisión en la presentación.

**Errores de la IA que detectamos y corregimos** (prueba de que la revisión humana hizo falta):
- Usó `/healthz` como endpoint de salud y en Cloud Run devolvía 404, porque la plataforma reserva las rutas que terminan en `z`. Lo cambiamos a `/health`.
- Fijó `trivy-action` a un tag que ya no existía. Lo fijamos por SHA.
- La imagen base debian12 tenía CVEs que Trivy marcó. Pasamos a debian13.
- Un commit que tocaba el propio `deploy.yml` disparó un deploy innecesario, porque `paths-ignore` solo aplica si *todos* los archivos cambiados coinciden. Lo cancelamos.
- Dio por hecho una fecha (martes en vez de miércoles) y algunos datos del diagrama (presupuesto de USD 5, "prueba gratuita") que no coincidían con la realidad. Los corregimos.

## 3. Prompts utilizados

Prompts reales, en el orden en que se usaron, agrupados por integrante. Los textos entre comillas están copiados tal cual, con la ortografía corregida; entre paréntesis se aclara el material que se adjuntó.

### Facundo (Claude, app de escritorio)

1. **Arranque:** "Recordás el trabajo que teníamos que hacer para Cloud, que era sobre QuantumQuack? Bueno, tenemos que ponernos a hacer eso. Adjunto tenés el documento que hizo uno de mis compañeros. Revisalo y arranquemos con esto. Acá tenés el Trello con las tareas. No queremos gastar nada de plata." (Con el documento y el link del Trello.)
2. **Organización:** "Vamos a limpiar el Trello. Qué podemos ir haciendo después entre Facundo Banchero, Gastón Puyares y Luca Benenati? Ordená las tareas de la forma más efectiva posible. Ponete en rol de organizador de talla mundial."
3. **Infraestructura:** "Quiero hacerlo con Terraform, pero me da error." (Con capturas de la terminal del bootstrap.)
4. **Cuenta de GCP:** "Luca no pudo con ninguna de las cuentas, le da error en la facturación, bloqueo de Google antifraude (OR_BACR2_59). Cómo podemos resolver esto?"
5. **Depuración:** "Me devolvió 404 el curl a /healthz." (Con la salida del comando.)
6. **Seguridad:** el mensaje de Gastón con los CVE que encontró Trivy en la imagen, pegado tal cual.
7. **Revisión de entregas:** "Luca hizo la planilla FinOps, revisala. En caso de que haya cosas que están mal, avisame cuáles son y se las paso."
8. **Seguimiento:** "Necesito que me des las actualizaciones y avances del proyecto, porque le tengo que contar al profe."
9. **Presentación:** "Vamos directo a la estructura de la presentación, las slides y ta. Lo que sí necesito es que ellos hagan el resto del trabajo."
10. **Entrega:** el mensaje del profe con los requisitos del repositorio, pegado tal cual.
11. **Demo:** "Dame todo lo que necesite la persona que vaya a hacer la demo en vivo. Ellos dos tienen Windows."

### Gastón (Claude, con acceso a GitHub, Chrome y Cloud Shell)

Su forma de trabajo fue enviarle a Claude **la captura del mensaje de WhatsApp con la tarea asignada, sin texto adicional**, y seguir el paso a paso que devolvía. Las capturas correspondían a estos pedidos:

1. **Diagrama v1:** armar el diagrama de arquitectura en draw.io a partir de la tarjeta del Trello.
2. **Correcciones del diagrama:** el mensaje con los errores a corregir (presupuesto de USD 1 en vez de USD 5 y cuenta paga en vez de prueba gratuita) y subirlo con una PR, con el PNG en `docs/`.
3. **Escaneo de la imagen:** correr Trivy sobre la imagen y reportar lo que encontrara (de ahí salieron los CVE de OpenSSL).
4. **Matriz IAM:** documentar qué puede y qué no puede cada identidad.
5. **Evidencias de seguridad:** probar en Cloud Shell el bucket privado, el rechazo del PDF, el Content-Type manipulado y la prevención de acceso público, y sacar las capturas.
6. **Experiencia del equipo:** pasarle a Luca sus líneas de experiencia para la justificación del proveedor.
7. **Uso de IA:** completar su fila en este documento.

### Luca (Claude, con acceso a Google Sheets, al repo y al navegador)

1. **Planificación:** "Tengo que hacer esto, ayudame a hacerlo." (Con la lista de tareas que le pasó Facundo: planilla FinOps, observabilidad, justificación e informe.)
2. **Planilla FinOps:** el pedido de comparar todo en Standard contra el ciclo de vida (30 días a Coldline, 365 a Archive) con 1 TB nuevo por mes. La IA buscó los precios en la página oficial de Cloud Storage y armó las fórmulas y el gráfico.
3. **Ajuste:** "Agregá el acumulado, pero en el Google Sheets."
4. **Corrección por revisión:** "Me dieron este feedback." (Con las 3 correcciones del equipo: objetos de 3 MB en vez de 10, TiB en vez de TB y el mismo divisor de días para Coldline y Archive.)
5. **Prerrequisitos:** "Ahora tengo que hacer esto. Si hay algún prerrequisito, avisame así le pido a los demás que me habiliten."
6. **Repositorio:** "Tenemos que subir la planilla al repo del proyecto" y "Tenés que hacer el merge a main."
7. **Prueba de observabilidad:** "Ya puse el proyecto en Google Cloud, ¿ahora qué?" La IA recorrió la consola, subió las fotos de prueba, llamó a `/api/boom` y sacó las capturas.
8. **Interpretar resultados:** "Me llegaron solo dos mails, el tercero nunca llegó." La IA explicó que las 3 llamadas cayeron en el mismo minuto y generaron un solo incidente (un mail al abrirse y otro al cerrarse).
9. **Informe y justificación:** el mensaje de Facundo con lo que pedía el informe FinOps (costo real, estimado contra real, proyección y medidas de ahorro) y la justificación v2, pegado tal cual.
10. **Entender la consigna:** "La experiencia que se nos pedía, ¿era acerca de nuestra experiencia haciendo el proyecto o qué era?"
11. **Presentación:** "Esta es la presentación, decime qué es lo que tengo que decir cuando me toca a mí."

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
