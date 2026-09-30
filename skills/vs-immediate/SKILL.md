---
name: vs-immediate
description: Evalua expresiones y controla el depurador de Visual Studio (Windows) desde la terminal, como la Ventana Inmediato. Usar cuando el usuario depura una solucion .NET en Visual Studio y hace falta ver valores en tiempo de ejecucion (variables, locales, pila de llamadas, excepciones, hilos, breakpoints, paso a paso, compilar) en vez de pedirle que los copie. Evaluate expressions and drive the Visual Studio debugger via DTE.
---

# vs-immediate

Puente entre Claude Code y una instancia de Visual Studio en ejecucion, usando la automatizacion COM (EnvDTE). Equivale a lo que el usuario haria en la Ventana Inmediato, pero el resultado vuelve aqui.

Solo Windows. Se ejecuta siempre con Windows PowerShell 5.1 (`powershell.exe`), no con `pwsh`.

Skills relacionadas del mismo plugin (flujos completos que usan estos scripts): `vs-diagnose` (investigar un fallo), `vs-elsa` (workflows y actividades de Elsa 3), `vs-di-inspect` (que implementacion hay tras una interfaz), `vs-watch` (seguir valores entre pausas), `vs-repro` (dejar un fallo reproducible).

## Cuando usarla

- El usuario esta depurando en Visual Studio y necesitas el valor real de una variable, propiedad o expresion.
- Necesitas ver la pila de llamadas, los locales, la ultima excepcion, los hilos, los breakpoints o la salida de depuracion.
- Quieres poner un breakpoint, lanzar la depuracion, avanzar paso a paso o compilar sin pedirselo al usuario.

No la uses si no hay Visual Studio abierto con la solucion, o si el problema se resuelve leyendo el codigo.

## Como invocar los scripts

Los scripts estan en la carpeta `scripts/` junto a este fichero (usa el "base directory" que indica Claude Code al cargar la skill). Plantilla:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<base>\scripts\vs-eval.ps1" -Expression "miVariable.Count"
```

Todos devuelven JSON con `"ok": true/false`. Si `ok` es false, lee `error`: casi siempre explica que hacer.

Si la expresion lleva comillas o caracteres que el shell puede estropear, escribela en un fichero temporal y usa `-ExpressionFile <ruta>`.

Cuando un parametro admite varias expresiones (`vs-types`, `vs-watch`), van separadas por `,,` dentro de un unico argumento.

## Scripts

Solo lectura (el plugin las aprueba automaticamente si se llaman de forma simple, ver "Permisos"):

| Script | Para que |
| --- | --- |
| `vs-list.ps1` | Lista instancias de VS abiertas (solucion, PID, modo). Primera prueba de conexion. |
| `vs-state.ps1 -What Status` | Modo del depurador, proceso y frame actual. |
| `vs-state.ps1 -What Locals` | Locales y argumentos del frame actual. |
| `vs-state.ps1 -What Stack -Top 20` | Pila de llamadas. |
| `vs-state.ps1 -What Breakpoints` | Breakpoints definidos. |
| `vs-state.ps1 -What Output -Pane Debug -Tail 50` | Ultimas lineas de la ventana Output. |
| `vs-state.ps1 -What Errors [-Level Error\|Warning\|All]` | Lista de errores de VS (ultimo build/analisis). |
| `vs-state.ps1 -What Processes -Filter <texto>` | Procesos locales a los que se puede enganchar el depurador. |
| `vs-eval.ps1 -Expression "<expr>"` | Evalua una expresion. `-Members` lista sus miembros; `-Depth 2` o `3` explora en profundidad; `-Private` incluye miembros no publicos. |
| `vs-types.ps1 -This` / `-Expressions "a,,b"` | Tipo declarado y tipo real (implementacion tras una interfaz). No ejecuta metodos. |
| `vs-exceptions.ps1 -Action Last` | Ultima excepcion: tipo, mensaje, cadena de InnerException, pila. |
| `vs-exceptions.ps1 -Action List [-Group g -Type texto]` | Grupos de excepciones y su configuracion (experimental). |
| `vs-threads.ps1 -Action List` / `-Action Stack -ThreadId n` | Hilos y su ubicacion; pila de otro hilo sin cambiar de hilo. |
| `vs-elsa.ps1 [-Root context]` | Sondeo del contexto de Elsa 3: instancia, estado, correlacion, bookmarks, incidentes. Dice que nombres existen en tu version. |

Modifican algo (piden permiso salvo que el usuario ya lo haya pedido):

| Script | Para que |
| --- | --- |
| `vs-eval.ps1 -Expression "<sentencia>" -Execute` | Ejecuta una asignacion o llamada void como expresion con efectos y comprueba el resultado (falla con error si el depurador la rechaza). No admite declaraciones (`int x = 1`) ni variables del depurador (`$x`), que no persisten entre llamadas. Cambia el estado de la aplicacion. |
| `vs-threads.ps1 -Action Switch -ThreadId n` | Cambia el hilo actual del depurador. |
| `vs-exceptions.ps1 -Action Break\|NoBreak -Type <T>` | Activa o desactiva "parar al lanzarse" para un tipo de excepcion (experimental). |
| `vs-watch.ps1 -Expressions "a,,b" -Iterations 5` | Instantaneas de varias expresiones a lo largo de varias pausas (continua la ejecucion). |
| `vs-control.ps1 -Action Build` | Compila la solucion (modo diseno). |
| `vs-control.ps1 -Action Start` | Inicia la depuracion (F5). |
| `vs-control.ps1 -Action Attach -TargetName <texto>` / `-TargetPid n` | Se engancha a un proceso ya en marcha. `Detach` se desengancha. |
| `vs-control.ps1 -Action Continue / StepOver / StepInto / StepOut / Pause / Stop` | Control de ejecucion. |
| `vs-control.ps1 -Action AddBreakpoint -File Foo.cs -Line 42 [-Condition "x > 3"]` | Pone un breakpoint. |
| `vs-control.ps1 -Action AddTracepoint -File Foo.cs -Line 42 -Message "x={x}"` | Breakpoint que escribe en Output y no para (experimental). |
| `vs-control.ps1 -Action RemoveBreakpoint -File Foo.cs -Line 42` | Quita un breakpoint. |
| `vs-control.ps1 -Action ClearBreakpoints` | Quita todos (incluye los del usuario: mejor no). |
| `vs-control.ps1 -Action Command -Command "Debug.Start"` | Cualquier comando de VS (DTE.ExecuteCommand). |

Opciones comunes: `-Solution <texto de la ruta>` o `-ProcessId <pid>` para elegir instancia de VS si hay varias (tambien vale la variable de entorno `VS_IMMEDIATE_SOLUTION`).

## Flujo recomendado

1. `vs-list.ps1` para confirmar que se ve la instancia correcta.
2. `vs-state.ps1 -What Status` para saber en que modo esta (`design`, `run`, `break`).
3. Evaluar expresiones y locales solo en modo `break`. Si esta en `run`, pon un breakpoint o haz `Pause`.
4. Tras cada accion de control (`Continue`, `Step*`), el resultado indica el nuevo modo y la funcion actual; si dice que sigue en ejecucion, no asumas que se ha parado.
5. Razona con lo obtenido antes de pedir el siguiente dato. Pide pocos datos por llamada y con expresiones concretas.
6. Para investigaciones largas de varios ciclos, usa la skill `vs-diagnose` o delega en el agente `vs-debugger`.

## Reglas de seguridad

- Evaluar una expresion puede ejecutar codigo de la aplicacion (llamar a metodos, getters con efectos, asignaciones). Prefiere expresiones de solo lectura. No modifiques estado ni llames a metodos con efectos laterales (escrituras, envios, borrados) sin que el usuario lo haya pedido.
- Antes de `Stop`, `ClearBreakpoints` o `Command` sobre algo destructivo, confirma con el usuario si no lo ha pedido explicitamente.
- No compiles ni inicies la depuracion ni te enganches a procesos por iniciativa propia si el usuario puede estar en mitad de otra tarea; pregunta.
- Los breakpoints que pongas tu, quitalos tu al terminar con `RemoveBreakpoint`. No borres los del usuario.
- Con proyectos ELSA / ASP.NET, una pausa larga puede provocar timeouts en peticiones o workflows en curso. Avisa si vas a dejar la ejecucion en pausa mucho tiempo.

## Permisos

El plugin incluye un hook que aprueba sin preguntar las llamadas de solo lectura a estos scripts: `vs-list`, `vs-state`, `vs-threads` (List/Stack), `vs-exceptions` (Last/List), y `vs-eval`/`vs-types`/`vs-elsa` cuando la expresion es simple (sin llamadas a metodos salvo `GetType()`/`ToString()`, sin asignaciones ni `++`/`--`). Todo lo demas sigue pidiendo permiso. Para que el hook pueda aprobarlo, llama al script en un unico comando, sin encadenar (`;`, `&&`, `|`) ni redirigir (`>`).

## Problemas frecuentes

- "No se encuentra ninguna instancia": VS cerrado, o VS y la terminal con distintos permisos (uno como administrador y otro no).
- "Hay varias instancias": usa `-Solution` o `-ProcessId`.
- "El depurador no esta en pausa": hace falta break mode para evaluar.
- Errores de COM tipo "llamada rechazada": VS esta ocupado (compilando, cargando); el script reintenta solo, si persiste espera unos segundos.
- Los valores que devuelve son los del evaluador del depurador; expresiones que en la Ventana Inmediato dependen de sintaxis especial (`?`, `>` comandos) se hacen con `vs-eval.ps1` y `vs-control.ps1 -Action Command` respectivamente.
- No se lee ni se escribe el texto de la Ventana Inmediato en si; es el mismo evaluador, no la ventana.
- Las funciones marcadas como experimentales dependen de partes de la API de VS que cambian entre versiones; si fallan, el error lo dice y se puede hacer a mano en Visual Studio.
