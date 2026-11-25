# Cierre del proyecto · 25/11/2026

Después de la defensa se destruyó todo el entorno `dev`.

| Evidencia | Resultado |
|---|---|
| Deploy #11 (día de la defensa, con load balancer) | OK. Lo corrió y aprobó Luca |
| Destroy #2 (después de la defensa) | OK en 2 min 24 s. **Total: 0** recursos en el state → [captura](destroy-final-25-11.png) |
| Facturación 1–25 de noviembre | **USD 0,00**, previsto para el mes USD 0,01 → [captura](costo-final-25-11.png) |

El único costo del mes fue el load balancer mientras estuvo prendido (la prueba del 18/11 y el día de la defensa). Siguen en pie solo los recursos del bootstrap (bucket del state, WIF, SA de CI y presupuesto), que no tienen costo, para poder volver a desplegar con *Run workflow → Deploy*.
