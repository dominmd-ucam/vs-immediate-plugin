---
name: vs-elsa
description: Guía para depurar workflows y actividades de Elsa (ELSA Workflows, .NET) con vs-immediate - dónde parar, qué inspeccionar del contexto de ejecución, hilos y timeouts. Usar cuando el usuario depura un ElsaServer, una actividad personalizada, un workflow que no avanza o un bookmark que no se reanuda.
---

# vs-elsa

Complemento de `vs-immediate` y `vs-diagnose` para código de Elsa. Los scripts están en `..\vs-immediate\scripts`.

Importante: los nombres exactos de tipos y propiedades cambian entre Elsa 2 y Elsa 3. Lo que sigue son puntos de partida habituales; **verifica siempre con `vs-eval.ps1 -Expression "<obj>" -Members`** qué existe en la versión del usuario antes de asumir un nombre, y confirma la versión mirando los `.csproj` (paquetes `Elsa.*`).

## Dónde parar

- Dentro de la actividad personalizada, en su método de ejecución (en Elsa 3 suele ser `ExecuteAsync(ActivityExecutionContext context)`; en Elsa 2 `OnExecuteAsync`). Es donde tienes el contexto completo.
- En el punto donde se dispara el workflow (endpoint HTTP, servicio que lo lanza, consumidor de mensajes).
- Donde se reanuda por un bookmark/evento, si el problema es que "se queda esperando".
- Acota con condición sobre la instancia: por ejemplo un breakpoint condicional por id de workflow o de instancia, para no parar con el resto del tráfico. Busca el nombre real de esa propiedad con `-Members`.

## Qué mirar (verificando nombres)

Desde el contexto de la actividad (`context` u homólogo):

- Identidad: id de la instancia y de la definición del workflow.
- Estado: estado y subestado de la instancia (por qué está suspendida, finalizada o con fallo).
- Variables y entradas/salidas de la actividad: sus valores actuales.
- Bookmarks pendientes: qué está esperando el workflow y con qué hash o payload.
- Registro de ejecución / journal: qué actividades ya se ejecutaron y en qué orden.
- Excepción y estado de fallo si la actividad falló: `vs-exceptions.ps1 -Action Last` si se paró por excepción.

Servicios inyectados en la actividad o en el handler: `vs-types.ps1 -This` muestra qué implementación real hay detrás de cada interfaz (ver `vs-di-inspect`).

## Asincronía e hilos

Elsa es muy asíncrono: tras un `await` el código puede seguir en otro hilo y el estado puede cambiar entre pausas.

- `vs-threads.ps1 -Action List` para ver dónde está cada hilo; `-Action Stack -ThreadId <n>` para ver la pila de otro sin cambiar de hilo.
- No asumas que dos pausas consecutivas son del mismo workflow: comprueba el id de instancia cada vez.
- Para seguir una variable a lo largo de varias ejecuciones usa `vs-watch.ps1` con un breakpoint condicional.

## Precauciones específicas

- Mientras el depurador está en pausa, el servidor no atiende peticiones: pueden saltar timeouts de HTTP, de jobs en segundo plano y de bloqueos distribuidos del motor de workflows. No dejes la pausa abierta mucho rato y avisa al usuario si vas a hacerlo.
- Evaluar expresiones puede disparar getters con efectos (carga perezosa de entidades, acceso a base de datos). Prefiere leer campos y propiedades simples; no llames a métodos del motor (`Resume`, `Dispatch`, `Execute`...) desde el evaluador sin permiso expreso, porque avanzarían workflows reales.
- Si el entorno tiene datos reales o de cliente, no vuelques valores completos en la conversación más allá de lo necesario para el diagnóstico.

## Flujo típico "el workflow no avanza"

1. Confirma en el código qué actividad debería continuar y qué la reanuda (bookmark, evento, temporizador).
2. Breakpoint (condicional por instancia) al inicio de esa actividad y otro en el punto de reanudación.
3. Lanza el caso y observa si llegan a ejecutarse. Si el de reanudación nunca salta, el problema está antes (quién debería disparar el evento).
4. Si salta, compara los bookmarks pendientes con lo que se busca al reanudar (hash/payload/nombre).
5. Concluye con la evidencia, siguiendo el cierre de `vs-diagnose` (quitar breakpoints, no modificar código sin permiso).
