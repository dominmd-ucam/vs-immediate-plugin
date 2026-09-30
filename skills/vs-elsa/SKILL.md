---
name: vs-elsa
description: Guía para depurar workflows y actividades de Elsa 3 (.NET) con vs-immediate - sondeo del contexto de ejecución, incidentes (excepciones capturadas por el motor), bookmarks, breakpoints por instancia, hilos y timeouts. Usar cuando el usuario depura un ElsaServer, una actividad personalizada, un workflow que falla o no avanza, o un bookmark que no se reanuda.
---

# vs-elsa

Complemento de `vs-immediate` y `vs-diagnose` para código de **Elsa 3**. Los scripts están en `..\vs-immediate\scripts`. Lee antes el `SKILL.md` de `vs-immediate` si no lo has hecho en esta conversación.

Los nombres de tipos y propiedades de Elsa 3 pueden variar entre versiones menores. Por eso hay un script que sondea el contexto y dice qué existe de verdad (`vs-elsa.ps1`), y todo lo demás de esta skill son puntos de partida que se verifican, no certezas. Confirma la versión en los `.csproj` (paquetes `Elsa.*`) si importa.

## Primer paso: sondear el contexto

Con el depurador parado dentro de una actividad (por ejemplo en `ExecuteAsync(ActivityExecutionContext context)`):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<base>\..\vs-immediate\scripts\vs-elsa.ps1"
```

- Por defecto usa `context` como raíz. Si el parámetro se llama distinto: `-Root <nombre>`.
- Devuelve, en una sola llamada: id de la actividad y de la instancia del workflow, correlación, estado y subestado, definición y versión, número de bookmarks, incidentes y contextos de actividad, y el detalle de los primeros incidentes y bookmarks.
- La lista `unavailable` dice qué nombres no existen en tu versión. Para descubrir el nombre real: `vs-eval.ps1 -Expression "<objeto>" -Members -Depth 2` (explora dos niveles; `-Private` añade miembros no públicos).
- `-Extra "expr1,,expr2"` evalúa expresiones adicionales de solo lectura en la misma llamada.

## Excepciones: Elsa 3 las captura

En Elsa 3 el motor captura las excepciones que lanzan las actividades y las registra como **incidentes** del workflow (la instancia pasa a estado de fallo). Consecuencias para depurar:

- Un fallo en una actividad **no siempre hace que el depurador pare** por "excepción no controlada": la excepción no llega a escapar del motor.
- Para ver la excepción original en el sitio donde se lanza: `vs-exceptions.ps1 -Action Break -Type <TipoDeExcepcion>` (parar al lanzarse) y repetir el caso; después `vs-exceptions.ps1 -Action Last` da mensaje, InnerException y pila. Si esa función experimental falla, se activa a mano en Visual Studio (Depurar > Ventanas > Configuración de excepciones). Al terminar, desactívala con `-Action NoBreak`.
- Alternativa sin cambiar la configuración: breakpoint dentro de la actividad, en el punto donde crees que falla, o en el `catch` de tu propio código.
- Para ver lo que el motor ya registró: `vs-elsa.ps1` muestra `incidents` (actividad, tipo, mensaje, excepción) cuando los hay.

## Dónde parar

- Dentro de la actividad personalizada: `ExecuteAsync(ActivityExecutionContext context)` (en actividades de código puede ser `Execute`). Ahí tienes el contexto completo.
- En el punto de tu código que lanza o reanuda workflows (servicio, endpoint, consumidor de mensajes que llama al runtime del motor).
- En el callback de reanudación de un bookmark, si el problema es "se queda esperando".
- **Acota por instancia** con un breakpoint condicional, para no parar con el resto del tráfico. Se necesita el id de la instancia (Elsa Studio lo muestra en el visor de instancias):

```
vs-control.ps1 -Action AddBreakpoint -File MiActividad.cs -Line 42 -Condition "context.WorkflowExecutionContext.Id == \"<id de la instancia>\""
```

(o por correlación: `context.WorkflowExecutionContext.CorrelationId == "..."`). Verifica esos nombres con `vs-elsa.ps1` antes de poner la condición.

## Entradas, salidas y variables

- Las propiedades `Input<T>` de una actividad son objetos con su expresión, no el valor ya resuelto. Para el valor hay que resolverlo con el contexto (por ejemplo `context.Get(Propiedad)`), que es una **llamada a método**: puede evaluar expresiones del workflow. Hazlo solo si hace falta y pidiendo confirmación al usuario; el hook de permisos no aprueba automáticamente las llamadas a métodos.
- Para explorar sin llamar a nada: `vs-eval.ps1 -Expression "this" -Members -Depth 2` y `-Expression "context.WorkflowExecutionContext" -Members -Depth 2` (variables, registro de memoria, entradas y propiedades aparecen como miembros; los nombres exactos, con `-Members`).
- El estado de la instancia se persiste en ciertos momentos (al suspender o terminar). Durante una pausa lo que ves es el estado en memoria, que puede diferir de lo que hay en la base de datos.

## Asincronía, hilos y tiempos

- Tras un `await` el código puede continuar en otro hilo: `vs-threads.ps1 -Action List` y `-Action Stack -ThreadId <n>` para ver dónde está cada cosa sin cambiar de hilo.
- Dos pausas consecutivas pueden ser de instancias distintas: comprueba el id de instancia en cada una (`vs-elsa.ps1`).
- Para seguir un valor a lo largo de varias ejecuciones: `vs-watch.ps1` con un breakpoint condicional por instancia.
- Mientras el depurador está en pausa, el servidor no atiende peticiones: pueden saltar timeouts de HTTP, de jobs en segundo plano y de bloqueos del motor. No dejes la pausa abierta mucho rato y avisa si vas a hacerlo.

## Precauciones

- No llames desde el evaluador a métodos del motor que avancen workflows reales (reanudar, despachar, ejecutar) sin permiso expreso del usuario.
- Evalúa preferentemente propiedades y campos simples; algunos getters pueden cargar datos o abrir conexiones.
- Si el entorno tiene datos reales o de cliente, no vuelques valores completos en la conversación más allá de lo necesario.

## Flujo "un workflow falla"

1. `vs-elsa.ps1` en la actividad que falla, o mira los incidentes de la instancia.
2. Si el motor se traga la excepción: `vs-exceptions.ps1 -Action Break -Type <T>`, reproduce el caso y lee `-Action Last`.
3. Con la pila y los valores en el punto de fallo, formula la hipótesis (dato que llega mal, dependencia sin inyectar, recurso ausente) y confírmala con `vs-eval`/`vs-types` (esto último, si es un problema de qué implementación hay detrás de una interfaz: skill `vs-di-inspect`).
4. Cierra como en `vs-diagnose`: quita lo que pusiste, desactiva la excepción con `NoBreak`, y no modifiques código sin permiso.

## Flujo "el workflow no avanza"

1. Confirma en el código qué actividad debería continuar y qué la reanuda (bookmark, evento, temporizador).
2. Breakpoint (condicional por instancia) al inicio de esa actividad y otro donde se reanuda.
3. Lanza el caso: si la reanudación nunca salta, el problema está antes (quién debería disparar el evento). Si salta, compara con `vs-elsa.ps1` los bookmarks pendientes (nombre, hash) con lo que se busca al reanudar.
4. Concluye con la evidencia y quita lo que pusiste.
