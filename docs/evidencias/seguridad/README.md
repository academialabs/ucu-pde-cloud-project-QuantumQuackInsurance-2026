# Evidencias de seguridad

Pruebas hechas el 23/11/2026 desde Cloud Shell (terminal) y Chrome (navegador y consola) contra `quantumquack-dev` y el bucket `quantumquack-ucu-quantumquack-dev-claims`. Las fotos de prueba usan `claimId` = `test-evidencia`, así que la regla de TTL las borra a los 7 días.

| # | Prueba | Esperado | Resultado | Captura |
|---|--------|----------|-----------|---------|
| 1 | Subir una foto por la API (URL firmada) y leerla sin firma | PUT 200, GET 403 | PUT **200**, GET **403** `AccessDenied` ("Anonymous caller does not have storage.objects.get") | [01](01-bucket-privado-403.png) |
| 2 | Pedir URL para `image/png` y subir con `Content-Type: image/jpeg` | 403 | **403** `SignatureDoesNotMatch`: el Content-Type es parte de la firma | [02](02-content-type-distinto-403.png) |
| 3 | Pedir URL para un PDF | 400 de la app | **400** "Tipo de archivo no permitido. Solo JPG, PNG o WEBP." en terminal y en el formulario | [03a terminal](03a-pdf-400-terminal.png) · [03b navegador](03b-pdf-rechazado-navegador.png) |
| 4 | Prevención de acceso público del bucket | Aplicada | **Habilitada** mediante el parámetro de configuración del bucket. Control de acceso Uniforme, estado "No público" | [04](04-prevencion-acceso-publico.png) |
| 5 | Ninguna SA con Owner o Editor | Sin SAs con roles básicos | Ver nota | [05](05-iam-cuentas-de-servicio.png) |

## Notas

- **Prueba 3 (navegador):** el input del formulario ya filtra con `accept="image/jpeg,image/png,image/webp"`. Para probar la validación del servidor se cargó un PDF salteando ese filtro, como haría un atacante. La app lo rechazó igual.
- **Prueba 4:** la captura es de la pestaña *Configuración* del bucket. La pestaña *Permisos* requiere `storage.buckets.getIamPolicy`, que el rol Viewer no tiene. El dato es el mismo.
- **Prueba 5:** las SAs que crea Terraform **no** tienen Owner ni Editor. `sa-ci-github` tiene solo roles predefinidos por servicio, y la SA de la app (`sa-quantumquack-dev`) no aparece a nivel proyecto porque sus permisos están sobre el bucket y sobre sí misma. **Sí aparece** la SA por defecto de Compute (`<n>-compute@developer.gserviceaccount.com`) con **Editor**. Google se la asigna automáticamente al habilitar la API de Compute Engine, que el proyecto habilita para el load balancer opcional. La app no la usa: Cloud Run corre con su propia SA. Para cerrarlo del todo, un Owner puede quitarle Editor (`gcloud projects remove-iam-policy-binding quantumquack-ucu --member=serviceAccount:<n>-compute@developer.gserviceaccount.com --role=roles/editor`) o deshabilitar esa SA, después de confirmar que nada del proyecto la usa.
- En la captura 5 se taparon los mails personales del equipo porque el repo es público.
