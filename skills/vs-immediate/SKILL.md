---
name: vs-immediate
description: Evalua expresiones y controla el depurador de Visual Studio (Windows; el agente puede correr en Windows nativo o en WSL) desde la terminal, como la Ventana Inmediato. Usar cuando el usuario depura una solucion .NET en Visual Studio y hace falta ver valores en tiempo de ejecucion (variables, locales, pila de llamadas, excepciones, hilos, breakpoints, paso a paso, compilar) en vez de pedirle que los copie. Evaluate expressions and drive the Visual Studio debugger via DTE.
---

# vs-immediate

Puente entre el agente (Claude Code o Codex) y una instancia de Visual Studio en ejecucion, usando la automatizacion COM (EnvDTE). Equivale a lo que el usuario haria en la Ventana Inmediato, pero el resultado vuelve aqui.

Visual Studio es solo Windows. Los scripts se ejecutan siempre con Windows PowerShell 5.1 (`powershell.exe`), no con `pwsh`. El agente puede correr en Windows nativo o en WSL: en WSL se llama por el puente `vs.sh` (ver "Si el agente corre en WSL").

Skills relacionadas del mismo plugin (flujos completos que usan estos scripts): `vs-diagnose` (investigar un fallo), `vs-elsa` (workflows y actividades de Elsa 3), `vs-di-inspect` (que implementacion hay tras una interfaz), `vs-watch` (seguir valores entre pausas), `vs-repro` (dejar un fallo reproducible).

## Cuando usarla

- El usuario esta depurando en Visual Studio y necesitas el valor real de una variable, propiedad o expresion.
- Necesitas ver la pila de llamadas, los locales, la ultima excepcion, los hilos, los breakpoints o la salida de depuracion.
- Quieres poner un breakpoint, lanzar la depuracion, avanzar paso a paso o compilar sin pedirselo al usuario.

No la uses si no hay Visual Studio abierto con la solucion, o si el problema se resuelve leyendo el codigo. Si el usuario depura en JetBrains Rider (no en Visual Studio), no es esta skill: usa `rider-debug`.

## Como invocar los scripts

Los scripts estan en la carpeta `scripts/` junto a este fichero (usa la carpeta donde esta este SKILL.md; el agente indica su ruta al cargar la skill). Plantilla:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<base>\scripts\vs-eval.ps1" -Expression "miVariable.Count"
```

Todos devuelven JSON con `"ok": true/false`. Si `ok` es false, lee `error`: casi siempre explica que hacer.

Usa exactamente esta forma (con `-NoProfile -ExecutionPolicy Bypass -File` en ese orden, sin otras opciones delante): el hook de permisos solo reconoce la plantilla tal cual.

### Si el agente corre en WSL

Visual Studio sigue siendo el de Windows; solo cambia como se llama a los scripts. Si estas en WSL (existe la variable `WSL_DISTRO_NAME`, o `uname -r` contiene `microsoft`), llama SIEMPRE por el puente `vs.sh`; nunca con `powershell.exe` y una ruta de WSL, ni con `pwsh`:

```
bash "<base>/scripts/vs.sh" vs-state -What Status
bash "<base>/scripts/vs.sh" vs-eval -Expression 'miVariable.Count'
```

- El primer argumento es el nombre del script sin ruta (`vs-eval`, `vs-state`...; con `.ps1` tambien vale). El resto son los mismos parametros que en Windows, y todas las tablas de abajo valen igual.
- Misma regla de comillas (`~q~`, argumento entre comillas simples) y misma regla de una sola linea por llamada.
- Los argumentos viajan codificados, asi que simbolos y espacios llegan intactos al script.
- Los scripts se copian solos a `%LOCALAPPDATA%\vs-immediate\scripts` en Windows, y el historial (`vs-history`) es el mismo que usa el agente de Windows.
- Si responde que no encuentra `powershell.exe`, el interop de WSL esta desactivado. Para diagnosticarlo, el usuario puede ejecutar `bash install/install-wsl.sh check` desde el repositorio del plugin.

### Comillas dobles en las expresiones (regla de prioridad)

Las comillas dobles se pierden o parten el argumento al pasar por la linea de comandos: `"648000"` llega como el numero 648000 (error CS1503) o PowerShell da un error absurdo en otro parametro (por ejemplo `Depth`). Sigue SIEMPRE este orden:

1. **`~q~` (primera opcion, siempre).** En `-Expression`, `-Expressions`, `-Extra` escribe `~q~` en lugar de cada comilla doble, y rodea el argumento con comillas simples:
   `-Expression 'lista.Where(p => p.Id.StartsWith(~q~648000~q~)).Count()'`
   El script lo convierte en `"` antes de evaluar. Sustituye TODAS las comillas dobles de la expresion, tambien las de literales como `string.Join(~q~ | ~q~, ...)` o `~q~ -> ~q~`. **Antes de lanzar, comprueba que en la expresion no queda ninguna comilla doble real**: una sola suelta rompe el argumento. No uses `''` ni `\"` para esto.
2. **Si falla, reintenta una vez con `~q~`** revisando que no quede ninguna `"` suelta (es el fallo mas habitual).
3. **Solo si `~q~` ha fallado dos veces**, escribe la expresion en un fichero temporal de una sola linea y usa `-ExpressionFile <ruta>`. Esas llamadas siempre piden permiso al usuario.

No empieces por el fichero temporal.

Cuando un parametro admite varias expresiones (`vs-types`, `vs-watch`), van separadas por `,,` dentro de un unico argumento.

## Scripts

Solo lectura (el plugin las aprueba automaticamente si se llaman de forma simple, ver "Permisos"):

| Script | Para que |
| --- | --- |
| `vs-list.ps1` | Lista instancias de VS abiertas (solucion, PID, modo). Primera prueba de conexion. |
| `vs-state.ps1 -What Status` | Modo del depurador, proceso y frame actual. |
| `vs-state.ps1 -What Locals` | Locales y argumentos del frame actual. |
| `vs-state.ps1 -What Stack -Top 20` | Pila de llamadas (indices 1, 2, 3...: sirven para `-Frame`). |
| `vs-state.ps1 -What Locals -Frame 2` | Locales y argumentos del frame 2 de la pila. |
| `vs-state.ps1 -What Breakpoints` | Breakpoints definidos. |
| `vs-state.ps1 -What Output -Pane Debug -Tail 50` | Ultimas lineas de la ventana Output. En VS 2026 DTE puede devolver cero paneles (limite de VS, verificado): entonces falla con un mensaje claro; prueba `-Pane Active` o pide al usuario que mire la ventana Output. No lo intentes por otras vias. |
| `vs-state.ps1 -What Errors [-Level Error\|Warning\|All]` | Lista de errores de VS (ultimo build/analisis). |
| `vs-state.ps1 -What Processes -Filter <texto>` | Procesos locales a los que se puede enganchar el depurador. |
| `vs-history.ps1 [-Unique] [-Last 20] [-Kind eval]` | Lista las expresiones evaluadas con el plugin (persistente entre sesiones). Campo `lines`: listo para pegar. `-Clear` lo borra (pide permiso). |
| `vs-eval.ps1 -Expression "<expr>"` | Evalua una expresion. `-Members` lista sus miembros; `-Depth 2` o `3` explora en profundidad; `-Private` incluye miembros no publicos. `-Frame n` evalua en el frame n de la pila (numeracion de `vs-state -What Stack`, 1 = superior). |
| `vs-types.ps1 -This` / `-Expressions "a,,b"` | Tipo declarado y tipo real (implementacion tras una interfaz). No ejecuta metodos. |
| `vs-exceptions.ps1 -Action Last` | Ultima excepcion: tipo, mensaje, cadena de InnerException, pila. |
| `vs-exceptions.ps1 -Action List [-Group g -Type texto]` | Grupos de excepciones y su configuracion (experimental). |
| `vs-threads.ps1 -Action List` / `-Action Stack -ThreadId n` | Hilos y su ubicacion; pila de otro hilo sin cambiar de hilo. |
| `vs-elsa.ps1 [-Root context]` | Sondeo del contexto de Elsa 3: instancia, estado, correlacion, bookmarks, incidentes. Dice que nombres existen en tu version. |

Modifican algo (piden permiso salvo que el usuario ya lo haya pedido):

| Script | Para que |
| --- | --- |
| `vs-eval.ps1 -Expression "<sentencia>" -Execute` | Ejecuta una asignacion o llamada void como expresion con efectos y comprueba el resultado (falla con error si el depurador la rechaza). No admite declaraciones (`int x = 1`) ni variables del depurador (`$x`), que no persisten entre llamadas. Cambia el estado de la aplicacion. |
| `vs-trace.ps1 -Expression "<expr>" -Functions "Ns.Clase.Metodo,,Ns.Clase.Prop.get"` | Rastro de una evaluacion (experimental): pone breakpoints que solo cuentan, evalua la expresion, dice que funciones vigiladas se ejecutaron y cuantas veces, y los borra. Elige las funciones candidatas leyendo el codigo (getters, metodos que la expresion puede llamar). Ejecuta codigo de la app y toca breakpoints temporalmente: pide confirmacion. ATENCION: en VS 2026 ha dado falsos 0 (verificado: GetExpression ignora los breakpoints). Si `conclusive` es false, no digas que una funcion no se ejecuto; prueba `-UseStatement` y, si sigue en 0, deduce el rastro leyendo el codigo. |
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

## Mostrar lo que se ha consultado

Tras cada consulta que evalue expresiones (`vs-eval`, `vs-types`, `vs-elsa`, `vs-trace`, `vs-watch`), muestra al usuario, ademas del resultado, lo que se ha evaluado, en un bloque de codigo listo para pegar en la Ventana Inmediato de Visual Studio:

- Una linea por expresion, con el prefijo `?` para las que devuelven un valor (`? clientes.Count`) y sin prefijo para las sentencias (`sinEmail.Add(x)`).
- La expresion exacta que se envio al depurador, no una version resumida. Si se adapto (por ejemplo se quito un `;` o se cambio el separador `,,` por lineas separadas), muestra la version adaptada, que es la que funciona en la ventana.
- Indica el contexto en el que se evaluo: funcion del frame actual y hilo, porque la Ventana Inmediato evalua en el frame seleccionado. `vs-eval` ya lo devuelve en `context` (function, threadId) y la linea lista para pegar en `paste`: usalos, no lances consultas extra de pila.
- Con `vs-elsa` y `vs-types` muestra las expresiones principales que se evaluaron (por ejemplo `? context.WorkflowExecutionContext.Id`), no la lista completa de sondeo.
- Con `vs-state` (locales, pila, hilos) no hace falta: no son expresiones.

Si la expresion modifica estado, dilo antes de mostrarla.

Si el usuario pregunta que expresiones se han usado ("que has evaluado", "dame el listado"), no lo reconstruyas de memoria: ejecuta `vs-history.ps1 -Unique` (o con `-Last N`, `-Kind`) y muestra el campo `lines` en un bloque de codigo, una por linea, como `? clientes.Count`. Cada consulta con vs-eval, vs-types, vs-elsa, vs-trace o vs-watch queda registrada automaticamente, tambien las de sesiones anteriores.

## Reglas de seguridad

- Evaluar una expresion puede ejecutar codigo de la aplicacion (llamar a metodos, getters con efectos, asignaciones). Prefiere expresiones de solo lectura. No modifiques estado ni llames a metodos con efectos laterales (escrituras, envios, borrados) sin que el usuario lo haya pedido.
- Antes de `Stop`, `ClearBreakpoints` o `Command` sobre algo destructivo, confirma con el usuario si no lo ha pedido explicitamente.
- No compiles ni inicies la depuracion ni te enganches a procesos por iniciativa propia si el usuario puede estar en mitad de otra tarea; pregunta.
- Los breakpoints que pongas tu, quitalos tu al terminar con `RemoveBreakpoint`. No borres los del usuario.
- Con proyectos ELSA / ASP.NET, una pausa larga puede provocar timeouts en peticiones o workflows en curso. Avisa si vas a dejar la ejecucion en pausa mucho tiempo.

## Permisos

El plugin incluye un hook que aprueba sin preguntar las llamadas de solo lectura a estos scripts: `vs-list`, `vs-state`, `vs-threads` (List/Stack), `vs-exceptions` (Last/List), y `vs-eval`/`vs-types`/`vs-elsa` cuando la expresion es de solo lectura: acceso a miembros, comparaciones, ternarios, `?.`, literales de texto y llamadas a una lista cerrada de metodos seguros (LINQ y cadenas): Where, Select, SelectMany, Count, Any, All, First/Last/Single (y OrDefault), ElementAt, Take, Skip, OrderBy/ThenBy (y Descending), Distinct, GroupBy, Sum, Min, Max, Average, Contains, ContainsKey, ContainsValue, Cast, OfType, ToList, ToArray, ToDictionary, ToHashSet, Zip, Concat, Union, Intersect, Except, Join, Split, StartsWith, EndsWith, IndexOf, Substring, ToUpper/ToLower, Trim, Equals, CompareTo, IsNullOrEmpty, IsNullOrWhiteSpace, ToString, GetType, GetHashCode, GetValueOrDefault, Format. Piden permiso siempre: cualquier otro metodo (Add, Remove, Clear, Delete, ForEach, TryGetValue...), `new`, `typeof`, genericos, lambdas con bloque `{}`, asignaciones, `++`/`--`, `;`, cadenas verbatim o interpoladas, y los parametros `-Execute` y `-ExpressionFile`. Limite conocido: el hook valida por nombre, no por tipo; si una clase propia del usuario tuviera un metodo llamado, p. ej., `Count()` o `Where()` con efectos secundarios, el hook lo aprobaria igual. Para que el hook pueda aprobarlo, llama al script en un unico comando de una sola linea, sin encadenar (`;`, `&&`, `|`), sin redirigir (`>`), sin saltos de linea y sin asignar variables de PowerShell (`$v = ...`) ni usar `$(...)`: si se compone un script con varias sentencias, el hook no aplica y todo pedira permiso. Un comando por llamada. Para comillas dobles en las expresiones, sigue la regla de prioridad de la seccion "Como invocar los scripts" (`~q~` primero; el fichero temporal solo como ultimo recurso, y esas llamadas siempre piden permiso porque el hook no puede ver su contenido).

## Evaluar en otro frame de la pila

`vs-eval`, `vs-types`, `vs-elsa` y `vs-state -What Locals` aceptan `-Frame n`. Primero `vs-state -What Stack` para ver los indices (1 = frame superior, el valor por defecto 0 usa el frame seleccionado en VS). El frame se selecciona solo durante la llamada y se restaura al terminar, tambien si hay error; si el frame no existe devuelve un error con el numero de frames del hilo. Util para ver variables del metodo que llamo al actual sin tocar la seleccion del usuario.

En WSL el hook equivalente es `hooks/approve-readonly.sh` (necesita `jq` o `python3`) y las llamadas deben tener la forma `bash "<ruta>/vs.sh" vs-xxx ...`, tambien en una sola linea. En Windows el hook solo aprueba la plantilla exacta `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<ruta>\vs-xxx.ps1" ...`; cualquier otra forma pide permiso.

La linea de `sourcePosition` sale del cursor del editor, no de la flecha amarilla: si importa la linea exacta, usa `vs-state.ps1 -What Status -SyncCaret`.

## Problemas frecuentes

- "No se encuentra ninguna instancia": VS cerrado, o VS y la terminal con distintos permisos (uno como administrador y otro no).
- En WSL, `"No se encuentra powershell.exe"`: interop desactivado en `/etc/wsl.conf` (`[interop] enabled=true`, `appendWindowsPath=true`; luego `wsl --shutdown` desde Windows). Mismo caso de permisos que arriba: WSL y Visual Studio con el mismo nivel de permisos.
- "Hay varias instancias": usa `-Solution` o `-ProcessId`.
- "El depurador no esta en pausa": hace falta break mode para evaluar.
- Errores de COM tipo "llamada rechazada": VS esta ocupado (compilando, cargando); el script reintenta solo, si persiste espera unos segundos.
- Los valores que devuelve son los del evaluador del depurador; expresiones que en la Ventana Inmediato dependen de sintaxis especial (`?`, `>` comandos) se hacen con `vs-eval.ps1` y `vs-control.ps1 -Action Command` respectivamente.
- No se lee ni se escribe el texto de la Ventana Inmediato en si; es el mismo evaluador, no la ventana.
- Las funciones marcadas como experimentales dependen de partes de la API de VS que cambian entre versiones; si fallan, el error lo dice y se puede hacer a mano en Visual Studio.
