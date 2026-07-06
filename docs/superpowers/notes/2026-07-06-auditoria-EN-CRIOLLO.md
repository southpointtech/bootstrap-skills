# Qué encontró la auditoría — en criollo

> Versión sin jerga del backlog técnico (`2026-07-06-auditoria-mejoras-scaffold.md`).
> Idea: revisé **todos tus proyectos** (15 repos entre personales y de Southpoint) para ver qué buenas prácticas fueron apareciendo sueltas en algún proyecto y convendría meter en el "molde base" (el scaffold) para que **todos los proyectos nuevos las tengan de arranque**.

## La foto de fondo

Tu "molde base" ya está bastante maduro: el flujo de trabajo de 8 pasos se propagó bien a casi todos los proyectos. Así que no encontré reglas nuevas que falten en el corazón del molde. Lo que encontré son **mejoras puntuales** que ya existen en algún proyecto y valdría estandarizar, más **un par de cosas para arreglar**.

Nada de esto lo toqué todavía: son decisiones tuyas. Abajo va de lo más importante/urgente a lo más "cuando tengas ganas".

---

## 🔴 Lo urgente: contraseñas a la vista

En **dos proyectos** encontré contraseñas/claves de acceso escritas directamente en un archivo que queda guardado en el historial del proyecto (o sea, cualquiera con acceso al repo las ve):

- **Linkedin** — la clave secreta de la app de LinkedIn.
- **Project Management Migration** — una clave de API con pinta de estar activa.

El resto de tus proyectos lo hace bien (guardan la clave aparte y el proyecto solo la "referencia"). 

**Qué conviene hacer:** (1) dar de baja/rotar esas dos claves cuanto antes —una clave que estuvo expuesta hay que asumir que se filtró—, y (2) sumar una regla al molde base: "las claves nunca se escriben directo, siempre se referencian aparte". Es baratísimo y evita que vuelva a pasar.

---

## 🟡 Mejoras que rinden mucho y cuestan poco

Aparecieron en **los dos árboles de proyectos a la vez** (personales y Southpoint), lo cual es la mejor señal de que conviene estandarizarlas:

1. **Conectar Firebase de fábrica.** Varios proyectos ya usan Firebase, pero el molde base solo trae configurado el conector de Zoho. Falta dejar Firebase como opción lista para elegir. (En la versión pública que armamos hoy ya está; falta sumarlo a las tuyas.)

2. **Una regla de "qué significa realmente 'probado'".** Un proyecto (Customer Portal) tiene una lista que aclara que "el código compila" NO es lo mismo que "está probado". Vale sumarla al checklist de calidad para que el agente no cante victoria antes de tiempo.

3. **Una nota de cómo se rastrean las 'skills' de terceros.** Dos proyectos ya llevan un registrito de qué skills externas usan y de dónde salieron. Falta explicarlo en el molde.

---

## 🟢 Dos "disciplinas" que ya usás y convendría que vengan de fábrica

Son dos formas de trabajar que ya tenés como skills, pero sueltas (no vienen con cada proyecto nuevo):

- **"Verificá que la cosa llegó a destino."** Antes de decir "listo, se envió / se publicó / se sincronizó", ir a mirar el destino final y confirmarlo, en vez de confiar en que "dio OK". Evita el clásico "estaba seguro de que se había mandado".
- **"Cuando algo no aparece, empezá por el origen."** Para bugs del tipo "no llegó el mail" / "no figura el pedido": revisar primero la fuente de datos y avanzar desde ahí, en vez de asumir dónde está el problema.

Ambas son genéricas y útiles para cualquier proyecto. Solo hay que limpiarles unas referencias específicas a DOMO antes de meterlas al molde.

---

## 📄 Plantillas de documentos que valdría tener listas

Cosas que armaste bien en un proyecto y sirven de plantilla para todos:

- **Guion de puesta en producción con roles claros:** cada paso marcado como "lo hace el agente" o "lo hago yo" (logins, 2FA, cosas sensibles), y un "no avanzo a la fase siguiente si la anterior no quedó verificada". (De *Finanzas*.)
- **Lista de decisiones de negocio pendientes:** una cola de preguntas que dependen de vos o del cliente (no técnicas), que se van tachando con la fecha cuando se resuelven. Hoy el molde solo maneja el trabajo técnico, no estas decisiones. (De *Flash Audit*.)
- **Guía de estimación:** los multiplicadores que ya usás para calcular esfuerzo (chico/mediano/grande, +25% por testing, etc.). Ojo: los originales están llenos de nombres de clientes/proyectos, hay que copiar solo la estructura. (De *KBS/Contractors*.)
- **Prompt maestro de rediseño:** para pasarle un rediseño visual a una herramienta externa sin que toque la lógica del negocio. (De *Personal Catalog*.)

---

## 🔧 Una cosa técnica para arreglar (te la explico igual)

Hay un detalle interno del sistema de actualización de proyectos (el `upgrade-bootstrap`) que, por cómo Windows maneja los finales de línea de los archivos, puede hacer que un tercero que baje la versión pública vea "todos los archivos como modificados" cuando en realidad no cambió nada. No rompe nada grave y **no afecta a nadie hoy** (todavía no hay repo público), pero conviene arreglarlo antes de publicar en serio. Ya dejé documentado el arreglo exacto; es una tarea chica con su prueba.

---

## 🗂️ Además: varios de tus proyectos están "atrasados"

La mayoría de tus proyectos personales viejos (*Flash Audit*, *Planify AI*, *Santi demo*, *Personal Catalog*, *Mate OS*) están en una versión antigua del molde — por ejemplo, les falta el "freno" que te ofrece alinear antes de codear. Se ponen al día pasándoles el `upgrade-bootstrap`. Solo *Finanzas* está 100% al día.

---

## En una línea

Lo más importante: **rotar las 2 claves expuestas**. Lo que más rinde: **la regla de secretos + Firebase de fábrica + las dos disciplinas de verificación**. El resto son plantillas y puestas al día que podemos ir metiendo de a poco, cada una pasando por tu flujo normal de grillearme → PRD → slices.
