---
name: rider-debug
description: Depura una solucion .NET en JetBrains Rider controlando su depurador por MCP (plugin "Debugger MCP Server", herramientas mcp__rider-debugger__*) - breakpoints, pausas, variables, pila, evaluacion de expresiones y paso a paso. Usar cuando el usuario depura en Rider (no en Visual Studio) y hace falta ver valores en tiempo de ejecucion. Para Visual Studio usa la skill vs-immediate.
---

# rider-debug

Rider no tiene la automatizacion COM de Visual Studio, asi que `vs-immediate` no puede hablar con el. Para Rider se usa el plugin de JetBrains **Debugger MCP Server** (autor hechtcarmel, github.com/hechtcarmel/jetbrains-debugger-mcp-plugin), que expone el depurador como herramientas MCP. Aqui se recoge como configurarlo y como trabajar con el.

Si el usuario depura en Visual Studio, esta no es la skill: usa `vs-immediate`.

## Cuando usarla

- El usuario depura en Rider y necesitas el valor real de una variable, la pila, los hilos o el resultado de una expresion.
- Quieres poner breakpoints, lanzar la depuracion, avanzar paso a paso o esperar a que pare, sin pedirselo al usuario a cada paso.

Si las herramientas `mcp__rider-debugger__*` no aparecen en la sesion, falta la preparacion de abajo (o hay que abrir una sesion nueva de Claude Code despues de registrar el servidor).

## Preparacion (una sola vez por equipo)

1. Plugin: en Rider, Settings > Plugins > Marketplace > instalar **Debugger MCP Server** (pagina plugins.jetbrains.com/plugin/29233). Requiere un JetBrains IDE 2025.2 o posterior. Aceptar el aviso de plugin de terceros y reiniciar Rider.
2. Settings > Tools > Debugger MCP Server: comprobar host `127.0.0.1` y puerto (en Rider es `29202`). Safety mode **Unrestricted** si hay que poder llamar a metodos al evaluar expresiones (en Read-only se rechazan las llamadas a metodos no probadamente de solo lectura, las asignaciones y los constructores).
3. Settings > Build, Execution, Deployment > Debugger:
   - marcar "Allow property evaluations and other implicit function calls"
   - Evaluation timeout = 5000 ms (con 1000 ms las consultas grandes fallan y Rider bloquea las evaluaciones hasta la siguiente parada)
4. Registrar el servidor en Claude Code a nivel de usuario:
   `claude mcp add --transport http rider-debugger http://127.0.0.1:29202/debugger-mcp/streamable-http --scope user`
   Si el comando `claude` no existe en la terminal, usa el ejecutable de la app de escritorio (`%APPDATA%\Claude\claude-code\<version>\claude.exe`). Comprobar con `claude mcp get rider-debugger` que sale "Connected" y abrir una sesion nueva de Claude Code para que carguen las herramientas.

Nota de fiabilidad: el README del plugin lista Rider (puerto 29202) pero solo declara pruebas automaticas en IntelliJ IDEA, PyCharm, WebStorm y GoLand, y no documenta limitaciones de .NET. Los ajustes de arriba salen de uso real con .NET en Rider; si algo se comporta distinto, dilo al usuario en vez de insistir.

## Herramientas (nombres exactos, prefijo `mcp__rider-debugger__`)

| Grupo | Herramientas |
| --- | --- |
| Configuraciones | `list_run_configurations`, `execute_run_configuration` |
| Sesion | `list_debug_sessions`, `start_debug_session`, `stop_debug_session`, `get_debug_session_status` (variables, pila y fuente en una sola llamada) |
| Breakpoints | `list_breakpoints`, `set_breakpoint` (admite condicion, mensaje de log y politica de suspension), `remove_breakpoint` |
| Ejecucion | `resume_execution`, `pause_execution`, `step_over`, `step_into`, `step_out`, `run_to_line`, `wait_for_pause` (bloquea hasta que para y devuelve el estado) |
| Pila e hilos | `get_stack_trace`, `select_stack_frame`, `list_threads` |
| Variables | `get_variables`, `set_variable` |
| Codigo | `get_source_context` |
| Evaluacion | `evaluate_expression` |

Equivalencias con los scripts de Visual Studio, por si el usuario ya conoce `vs-immediate`: `vs-state Status` = `get_debug_session_status`; `Locals` = `get_variables`; `Stack` = `get_stack_trace`; `Breakpoints` = `list_breakpoints`; `vs-eval` = `evaluate_expression`; `vs-threads` = `list_threads`; `vs-control` Continue/Step/AddBreakpoint/Start/Stop = `resume_execution`/`step_*`/`set_breakpoint`/`start_debug_session`/`stop_debug_session`. No hay equivalente de `vs-history`, `vs-trace`, `vs-types` ni de la ultima excepcion; usa `evaluate_expression` con lo que haga falta.

## Como trabajar en cada depuracion

- Si Rider tiene varias soluciones abiertas, pasa siempre `project_path` (con barras `/`, por ejemplo `C:/ruta/MiSolucion`). Si solo hay una, no hace falta.
- Antes de empezar, lee el codigo y propon los breakpoints: archivo:linea y que consultaras en cada uno. Si el usuario no ha pedido que actues sin preguntar, espera su visto bueno antes de poner nada.
- Orden habitual: comprobar conexion (`list_debug_sessions`) > `set_breakpoint` (guarda los IDs) > `start_debug_session` o `execute_run_configuration` > el usuario dispara el caso (peticion, workflow, boton) > `wait_for_pause` (si admite filtrar por breakpoints, filtra por los IDs que pusiste tu; mira el esquema de la herramienta) > `get_debug_session_status` y, para datos concretos, `evaluate_expression` > `step_*` o `resume_execution`.
- Pocos breakpoints y bien elegidos; condicionales si el punto se repite. Cada dato debe confirmar o descartar una hipotesis.
- Si cambias codigo, comprueba que Rider ha recompilado (fecha del .dll en `bin/Debug`) antes de relanzar. Si no, para la sesion y ejecuta `dotnet build` del proyecto. Al anadir o quitar lineas de un archivo, revisa y recoloca los breakpoints de ese archivo: se desplazan.
- Las cargas largas (miles de registros, importaciones) tardan: vigila el log en segundo plano en vez de esperar a ciegas.

## Evaluar expresiones

- El depurador corta una evaluacion a los 5 s (segun el timeout configurado) y no serializa objetos grandes. Para recuentos o analisis de miles de registros, no los evalues en el depurador: saca los datos a fichero (o usa el JSON que ya genere la aplicacion) y analizalos con un script; en el depurador consulta solo ejemplos concretos (`lista[0].Propiedad`).
- Si aparece "Implicit evaluation is disabled" tras un timeout, avanza una linea (`step_over`) para que Rider vuelva a permitir evaluar.
- Evaluar puede ejecutar codigo de la aplicacion (getters con efectos, llamadas, asignaciones). Prefiere expresiones de solo lectura y avisa antes de cualquiera que cambie estado.

## Seguridad

- Antes de dejar avanzar un flujo que escribe en sistemas externos (tienda online, base de datos, API de terceros), confirma con el usuario contra que entorno esta configurado y que es de pruebas. Muestrale cuantos elementos se van a crear, actualizar y eliminar antes de seguir. Si algo no cuadra (duplicados, borrados inesperados), para la sesion antes de esa escritura.
- No modifiques codigo sin proponerlo antes. Los breakpoints que pongas tu, quitalos tu al terminar; no borres los del usuario. Al acabar, pregunta si quitas los breakpoints y paras la sesion.
- Una pausa larga puede provocar timeouts en peticiones o workflows en curso. Avisa si vas a dejar la ejecucion parada mucho tiempo.
- Las llamadas de solo lectura se pueden pre-aprobar en los permisos de Claude Code (ver el README, seccion Rider). `evaluate_expression`, `set_variable`, `step_*`, `resume_execution` y los breakpoints deben seguir pidiendo permiso salvo que el usuario diga otra cosa.

## Al terminar

Resumen por etapas del flujo depurado, con los valores relevantes que viste, los errores y lo que queda pendiente.

## Limites

- Depende del plugin de terceros y de que Rider este abierto con la solucion y el servidor activo. Es un servidor HTTP en `127.0.0.1`: si Claude corre en WSL y Rider en Windows, el `127.0.0.1` de WSL no es el de Windows salvo configuracion de red espejo (no verificado aqui).
- Para Elsa 3, las expresiones de la skill `vs-elsa` (contexto de ejecucion, incidentes, bookmarks) sirven tambien con `evaluate_expression`; solo cambia como se lanzan.
