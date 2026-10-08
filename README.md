# vs-immediate

La Ventana Inmediato del depurador, pero para tu agente de IA.

vs-immediate es un plugin que deja a una IA (Claude Code, Codex) hacer lo que tu haces
en la Ventana Inmediato cuando depuras: evaluar expresiones, mirar variables locales,
la pila de llamadas, los hilos y la ultima excepcion, y controlar la ejecucion
(breakpoints, pasos, continuar). El resultado vuelve al agente como datos, asi que puede
razonar sobre el estado real de tu programa parado en un breakpoint en vez de adivinar.

Funciona con Visual Studio 2022 / 2026 y con JetBrains Rider, desde el CLI, la app de
escritorio o la extension de IDE de Claude y Codex, en Windows nativo y en WSL.

## Que puedes hacer

Con el depurador parado en un breakpoint, le dices al agente cosas como:

- "evalua `pedido.Lineas.Count` y dime que tipo real hay detras de `_writer`"
- "por que ha saltado esta excepcion? mira el estado y la pila"
- "sigue el valor de `contexto.Estado` durante las proximas tres pausas"
- "que hay en el frame 3 de la pila?" (`-Frame 3`, sin mover la seleccion de VS)
- "pon un breakpoint condicional aqui y continua"

## Donde funciona

| Agente \ IDE             | Visual Studio 2022 / 2026         | JetBrains Rider                     |
|--------------------------|-----------------------------------|-------------------------------------|
| Claude Code (CLI)        | Windows nativo y WSL              | skill rider-debug (por MCP)         |
| Claude Code (escritorio) | Windows nativo (sesion local)     | skill rider-debug (por MCP)         |
| Codex (CLI / app / IDE)  | Windows nativo y WSL              | skill instalable; el servidor MCP   |
|                          |                                   | de Rider se registra aparte         |

No funciona en sesiones en la nube (Cowork, Claude en la web): el depurador solo es
accesible desde la misma maquina Windows donde corre el IDE. VS Code y Linux/macOS sin
Windows no estan soportados.

Como llega el agente a cada IDE:

    Visual Studio:  agente --> scripts PowerShell 5.1 --> automatizacion COM (EnvDTE) --> Visual Studio
    WSL:            agente --> vs.sh --> powershell.exe (interop de WSL) --> el mismo camino
    Rider:          agente --> servidor MCP "Debugger MCP Server" de JetBrains --> Rider

Visual Studio no necesita nada instalado dentro: el plugin usa su automatizacion COM.
Rider no tiene COM, por eso usa el plugin de JetBrains Debugger MCP Server.

## Instalacion rapida

Claude Code (Windows nativo o dentro de WSL; en WSL se instala desde dentro de WSL, que tiene
su propio `~/.claude`):

    /plugin marketplace add dominmd-ucam/vs-immediate-plugin
    /plugin install vs-immediate@vs-immediate-plugin

Actualizar: `/plugin marketplace update vs-immediate-plugin` y recargar plugins.

Claude Code de escritorio: usa la misma configuracion de usuario que el CLI; hazlo desde una
sesion local con `/plugin`.

Codex en Windows: `.\install\install-codex.ps1`. Codex en WSL: `bash install/install-wsl.sh codex`.
Rider: ver la seccion Rider. Detalles de cada uno mas abajo.

## Primera prueba

- [ ] Abre Visual Studio con tu solucion (mismo nivel de permisos que la terminal)
- [ ] Pide al agente: "usa vs-immediate para listar las instancias de Visual Studio"
- [ ] Inicia la depuracion y deja que pare en un breakpoint
- [ ] Prueba `/vs-status`, `/vs-locals` y `/vs-eval miVariable`

Tambien puedes probar un script a mano:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File skills\vs-immediate\scripts\vs-list.ps1

## Que incluye

Skills (el agente las usa solo cuando encajan con lo que pides):

- vs-immediate: los scripts base (evaluar, estado, control) y sus reglas de seguridad
- vs-diagnose: investigar un fallo con pocos breakpoints y una hipotesis apoyada en valores
- vs-elsa: depurar workflows y actividades de Elsa 3 (contexto, incidentes, bookmarks, breakpoints por instancia, timeouts)
- vs-di-inspect: que implementacion real hay tras cada interfaz inyectada
- vs-watch: seguir valores a lo largo de varias pausas
- vs-repro: dejar un fallo como receta repetible
- rider-debug: depurar en JetBrains Rider por MCP (no en Visual Studio)

Comandos rapidos (Claude Code): `/vs-status`, `/vs-locals`, `/vs-stack`, `/vs-eval <expr>`,
`/vs-exception`, `/vs-threads`, `/vs-breakpoints`, `/vs-elsa`, `/vs-history`, `/rider-debug`.

Agente: `vs-debugger`, para delegar investigaciones largas de depuracion.

Opciones utiles de los scripts:

- `-Frame <n>` en vs-eval, vs-types, vs-elsa y `vs-state -What Locals`: evalua en otro frame de la
  pila (indices de `vs-state -What Stack`, 1 = superior) y restaura el frame al acabar.
- `-Solution` / `-ProcessId`: eligen instancia de VS cuando hay varias abiertas.
- `vs-history`: lista las expresiones evaluadas (persistente entre sesiones), listas para pegar en
  la Ventana Inmediato.

## Permisos y seguridad

Evaluar una expresion puede cambiar el estado del programa (una llamada a un metodo, una
asignacion), asi que el plugin separa lo que solo mira de lo que modifica:

- Se aprueba solo (sin preguntar): estado, locales, pila, hilos, ultima excepcion, tipos, y expresiones
  de solo lectura: acceso a miembros, comparaciones, ternarios y llamadas a una lista cerrada de
  metodos seguros de LINQ y cadenas (Where, Count, Any, Select, First, ToList, Substring...).
- Siempre pide permiso: cualquier otro metodo (Add, Remove, Clear, Delete...), `new`, asignaciones,
  `++`/`--`, control de ejecucion (pasos, continuar, breakpoints), `-Execute` y `-ExpressionFile`.

El hook que decide esto es `approve-readonly.ps1` en Windows y `approve-readonly.sh` en WSL (necesita
`jq` o `python3`; sin ellos no aprueba nada y se pide permiso en cada llamada). Valida por nombre de
metodo, no por tipo: una clase propia con un `Count()` que tenga efectos secundarios se aprobaria.
Detalles y limites en `skills/vs-immediate/SKILL.md`.

## Scripts

    skills/vs-immediate/scripts/
        vs-common.ps1                  conexion a VS, reintentos, utilidades
        vs-list.ps1                    lista instancias de VS
        vs-eval.ps1                    evalua expresiones
        vs-history.ps1                 historial de expresiones evaluadas (persistente)
        vs-trace.ps1                   rastro de una evaluacion: que funciones se ejecutan (experimental)
        vs-state.ps1                   estado, locales, pila, breakpoints, Output, Errores, Procesos
        vs-types.ps1                   tipo declarado y tipo real
        vs-exceptions.ps1              ultima excepcion y configuracion de excepciones
        vs-threads.ps1                 hilos
        vs-watch.ps1                   valores a lo largo de varias pausas
        vs-elsa.ps1                    sondeo del contexto de Elsa 3
        vs-control.ps1                 compilar, iniciar, pasos, breakpoints, tracepoints, attach
        vs.sh                          puente para WSL: llama a cualquiera de los anteriores en Windows
        vs-run.ps1                     lanzador que usa vs.sh (no se llama a mano)

## Rider

Rider no tiene la automatizacion COM de Visual Studio, asi que los scripts `vs-*` no sirven. Para Rider el plugin
incluye la skill `rider-debug`, que trabaja con el plugin de JetBrains **Debugger MCP Server**
(plugins.jetbrains.com/plugin/29233): expone el depurador de Rider como herramientas MCP (breakpoints, pausas,
variables, pila, evaluacion, paso a paso) y el agente las usa con el mismo estilo de trabajo que con Visual Studio.

Preparacion, una sola vez por equipo (el detalle y los porques estan en `skills/rider-debug/SKILL.md`):

- [ ] En Rider: instalar el plugin Debugger MCP Server y reiniciar (JetBrains IDE 2025.2 o posterior)
- [ ] Settings > Tools > Debugger MCP Server: puerto 29202 en Rider; safety mode Unrestricted si hay que llamar metodos al evaluar
- [ ] Settings > Build, Execution, Deployment > Debugger: marcar "Allow property evaluations and other implicit function calls" y Evaluation timeout = 5000 ms
- [ ] Registrar el servidor en Claude Code y abrir una sesion nueva:

      claude mcp add --transport http rider-debugger http://127.0.0.1:29202/debugger-mcp/streamable-http --scope user
      claude mcp get rider-debugger

Comprobacion: `/rider-debug` (con Rider abierto) lista las sesiones de depuracion y dice si esta conectado.

El servidor MCP no se instala con el plugin a proposito: apunta a un Rider local, y registrarlo para todos los
usuarios del plugin solo daria errores de conexion a quien no use Rider.

Permisos opcionales: para no aprobar cada consulta de solo lectura, anade a `~/.claude/settings.json` algo como
esto, y deja sin aprobar `evaluate_expression`, `set_variable`, los pasos, `resume_execution` y los breakpoints:

    {
      "permissions": {
        "allow": [
          "mcp__rider-debugger__list_debug_sessions",
          "mcp__rider-debugger__get_debug_session_status",
          "mcp__rider-debugger__list_breakpoints",
          "mcp__rider-debugger__get_variables",
          "mcp__rider-debugger__get_stack_trace",
          "mcp__rider-debugger__get_source_context",
          "mcp__rider-debugger__list_threads",
          "mcp__rider-debugger__list_run_configurations"
        ]
      }
    }

Estado: el README del plugin de JetBrains lista Rider pero solo declara pruebas automaticas en IntelliJ IDEA,
PyCharm, WebStorm y GoLand. La skill recoge ajustes sacados de uso real con .NET en Rider; no se ha probado aqui
contra un Rider real. En Codex, el registro de un servidor MCP HTTP no esta verificado: la skill se instala con
el instalador de Codex, pero el servidor habria que anadirlo con el mecanismo de MCP de Codex.

## WSL

Visual Studio corre en Windows; el agente puede correr dentro de WSL. Los scripts se ejecutan igualmente con
`powershell.exe` de Windows, al que WSL llega por su interop, asi que ven tu Visual Studio abierto. El puente es
`skills/vs-immediate/scripts/vs.sh`:

    bash skills/vs-immediate/scripts/vs.sh vs-state -What Status
    bash skills/vs-immediate/scripts/vs.sh vs-eval -Expression 'lista.Count'

Los parametros son los mismos que en Windows. El puente copia los scripts a `%LOCALAPPDATA%\vs-immediate\scripts`
(solo cuando cambian), pasa los argumentos codificados en base64 (las comillas, espacios y simbolos llegan
intactos) y devuelve el JSON limpio. El historial de expresiones es el mismo que el del agente de Windows.

Requisitos: interop de WSL activo (por defecto lo esta; en `/etc/wsl.conf` `[interop] enabled=true` y
`appendWindowsPath=true`), y Visual Studio y WSL con el mismo nivel de permisos.

Comprobar el entorno:

    git clone https://github.com/dominmd-ucam/vs-immediate-plugin
    cd vs-immediate-plugin
    bash install/install-wsl.sh check

Con Visual Studio abierto debe terminar con "WSL llega a Visual Studio por COM".

Claude Code en WSL: se instala como plugin desde dentro de WSL (ver Instalacion rapida). En Windows y en WSL
conviven los dos hooks en el mismo `hooks.json`, cada uno filtrado por el tipo de comando (campo `if`).

Codex en WSL:

    bash install/install-wsl.sh codex

Copia las skills a `~/.agents/skills` y escribe `~/.codex/rules/vs-immediate.rules` (`vs-state`, `vs-list` y
`vs-history` sin preguntar; el resto pide aprobacion; en ambos casos fuera del sandbox, que es lo que permite usar el
interop). Para actualizar: `git pull` y volver a ejecutarlo. Para quitarlo: `bash install/install-wsl.sh codex --uninstall`.
Reinicia Codex despues. Las reglas de Codex solo miran el principio del comando, asi que `vs-eval` siempre pide
aprobacion en Codex.

## Codex (Windows nativo)

Las mismas skills y scripts sirven para Codex. Se instalan como skills sueltas en `~/.agents/skills`, que es lo que
leen el CLI, la app de escritorio y la extension de IDE (la extension de IDE no soporta plugins, por eso no se usa
el plugin como via principal).

    git clone https://github.com/dominmd-ucam/vs-immediate-plugin
    cd vs-immediate-plugin
    .\install\install-codex.ps1

Para actualizar: `git pull` y volver a ejecutar `.\install\install-codex.ps1`. Para quitarlo:
`.\install\install-codex.ps1 -Uninstall`. Reinicia Codex despues.

El instalador tambien genera `~/.codex/rules/vs-immediate.rules`. Los scripts tienen que ejecutarse fuera del
sandbox de Codex (el sandbox usa otro usuario y no ve tu Visual Studio por COM). Con las reglas, `vs-state`,
`vs-list` y `vs-history` se ejecutan sin preguntar y el resto pide aprobacion. Las reglas de Codex solo miran el
principio del comando, no el contenido de la expresion, asi que `vs-eval` siempre pide aprobacion en Codex.

Tambien hay un plugin de Codex (`plugin.json` y `.agents/plugins/marketplace.json`), opcional:
`codex plugin marketplace add dominmd-ucam/vs-immediate-plugin`.

Comprobacion en Codex (primera vez):

1. Abre Visual Studio con una solucion, en modo depuracion y en pausa.
2. En Codex: "usa vs-immediate: lista las instancias de Visual Studio" (debe encontrar tu VS sin pedir permiso).
3. "Evalua `1+1` con vs-eval" (pedira aprobacion).
4. Si no encuentra Visual Studio, el sandbox esta bloqueando COM: comprueba que las reglas se han cargado y que el
   comando se ejecuta fuera del sandbox.

## Limites conocidos

- Evaluar expresiones requiere el depurador en pausa.
- No escribe texto en la ventana Inmediato; usa su mismo evaluador.
- VS y la terminal (o WSL) deben tener el mismo nivel de permisos.
- Con varias instancias de VS abiertas hay que indicar `-Solution` o `-ProcessId`.
- Sesiones en la nube: no sirven (ver "Donde funciona").
- Marcadas como experimentales: configuracion de excepciones (`vs-exceptions` List/Break/NoBreak),
  tracepoints (`AddTracepoint`) y `vs-trace`; dependen de partes de la API de VS que cambian entre versiones.
- Estado de las pruebas: hooks, scripts y el puente de WSL se probaron con un Visual Studio y un WSL simulados, y el
  hook ademas con Claude Code real. No se han probado contra Visual Studio 2026, WSL real, Rider real ni Codex.
  Puede necesitar ajustes en la primera ejecucion real.

## Hoja de ruta

- [ ] Servidor MCP local para Visual Studio (el equivalente al de Rider), pensado para clientes que usan MCP
- [ ] Validar en entornos reales: Visual Studio 2026, WSL, Rider y Codex

## Desarrollo

    git clone https://github.com/dominmd-ucam/vs-immediate-plugin

Para probar una rama o una copia local antes de fusionarla:

    /plugin marketplace add dominmd-ucam/vs-immediate-plugin#v0.2
    /plugin marketplace add C:\Repos\vs-immediate-plugin

(Los nombres exactos de los comandos pueden variar segun la version de Claude Code; `/plugin` muestra las opciones.)
