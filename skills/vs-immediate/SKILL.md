---
name: vs-immediate
description: Evalua expresiones y controla el depurador de Visual Studio (Windows) desde la terminal, como la Ventana Inmediato. Usar cuando el usuario depura una solucion .NET en Visual Studio y hace falta ver valores en tiempo de ejecucion (variables, locales, pila de llamadas, breakpoints, paso a paso, compilar) en vez de pedirle que los copie. Evaluate expressions and drive the Visual Studio debugger via DTE.
---

# vs-immediate

Puente entre Claude Code y una instancia de Visual Studio en ejecucion, usando la automatizacion COM (EnvDTE). Equivale a lo que el usuario haria en la Ventana Inmediato, pero el resultado vuelve aqui.

Solo Windows. Se ejecuta siempre con Windows PowerShell 5.1 (`powershell.exe`), no con `pwsh`.

## Cuando usarla

- El usuario esta depurando en Visual Studio y necesitas el valor real de una variable, propiedad o expresion.
- Necesitas ver la pila de llamadas, los locales, los breakpoints o la salida de depuracion.
- Quieres poner un breakpoint, lanzar la depuracion, avanzar paso a paso o compilar sin pedirselo al usuario.

No la uses si no hay Visual Studio abierto con la solucion, o si el problema se resuelve leyendo el codigo.

## Como invocar los scripts

Los scripts estan en la carpeta `scripts/` junto a este fichero (usa el "base directory" que indica Claude Code al cargar la skill). Plantilla:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<base>\scripts\vs-eval.ps1" -Expression "miVariable.Count"
```

Todos devuelven JSON con `"ok": true/false`. Si `ok` es false, lee `error`: casi siempre explica que hacer.

Si la expresion lleva comillas o caracteres que el shell puede estropear, escribela en un fichero temporal y usa `-ExpressionFile <ruta>`.

## Scripts

| Script | Para que |
| --- | --- |
| `vs-list.ps1` | Lista instancias de VS abiertas (solucion, PID, modo). Primera prueba de conexion. |
| `vs-state.ps1 -What Status` | Modo del depurador, proceso y frame actual. |
| `vs-state.ps1 -What Locals` | Locales y argumentos del frame actual. |
| `vs-state.ps1 -What Stack -Top 20` | Pila de llamadas. |
| `vs-state.ps1 -What Breakpoints` | Breakpoints definidos. |
| `vs-state.ps1 -What Output -Pane Debug -Tail 50` | Ultimas lineas de la ventana Output. |
| `vs-eval.ps1 -Expression "<expr>"` | Evalua una expresion. `-Members` lista sus miembros. `-Execute` la ejecuta como sentencia. |
| `vs-control.ps1 -Action Build` | Compila la solucion (modo diseno). |
| `vs-control.ps1 -Action Start` | Inicia la depuracion (F5). |
| `vs-control.ps1 -Action Continue / StepOver / StepInto / StepOut / Pause / Stop` | Control de ejecucion. |
| `vs-control.ps1 -Action AddBreakpoint -File Foo.cs -Line 42 [-Condition "x > 3"]` | Pone un breakpoint. |
| `vs-control.ps1 -Action RemoveBreakpoint -File Foo.cs -Line 42` | Quita un breakpoint. |
| `vs-control.ps1 -Action ClearBreakpoints` | Quita todos. |
| `vs-control.ps1 -Action Command -Command "Debug.Start"` | Cualquier comando de VS (DTE.ExecuteCommand). |

Opciones comunes: `-Solution <texto de la ruta>` o `-ProcessId <pid>` para elegir instancia si hay varias (tambien vale la variable de entorno `VS_IMMEDIATE_SOLUTION`).

## Flujo recomendado

1. `vs-list.ps1` para confirmar que se ve la instancia correcta.
2. `vs-state.ps1 -What Status` para saber en que modo esta (`design`, `run`, `break`).
3. Evaluar expresiones y locales solo en modo `break`. Si esta en `run`, pon un breakpoint o haz `Pause`.
4. Tras cada accion de control (`Continue`, `Step*`), el resultado indica el nuevo modo y la funcion actual; si dice que sigue en ejecucion, no asumas que se ha parado.
5. Razona con lo obtenido antes de pedir el siguiente dato. Pide pocos datos por llamada y con expresiones concretas.

## Reglas de seguridad

- Evaluar una expresion puede ejecutar codigo de la aplicacion (llamar a metodos, getters con efectos, asignaciones). Prefiere expresiones de solo lectura. No modifiques estado ni llames a metodos con efectos laterales (escrituras, envios, borrados) sin que el usuario lo haya pedido.
- Antes de `Stop`, `ClearBreakpoints` o `Command` sobre algo destructivo, confirma con el usuario si no lo ha pedido explicitamente.
- No compiles ni inicies la depuracion por iniciativa propia si el usuario puede estar en mitad de otra tarea; pregunta.
- Con proyectos ELSA / ASP.NET, una pausa larga puede provocar timeouts en peticiones o workflows en curso. Avisa si vas a dejar la ejecucion en pausa mucho tiempo.

## Problemas frecuentes

- "No se encuentra ninguna instancia": VS cerrado, o VS y la terminal con distintos permisos (uno como administrador y otro no).
- "Hay varias instancias": usa `-Solution` o `-ProcessId`.
- "El depurador no esta en pausa": hace falta break mode para evaluar.
- Errores de COM tipo "llamada rechazada": VS esta ocupado (compilando, cargando); el script reintenta solo, si persiste espera unos segundos.
- Los valores que devuelve son los del evaluador del depurador; expresiones que en la Ventana Inmediato dependen de sintaxis especial (`?`, `>` comandos) se hacen con `vs-eval.ps1` y `vs-control.ps1 -Action Command` respectivamente.
- No se lee ni se escribe el texto de la Ventana Inmediato en si; es el mismo evaluador, no la ventana.
