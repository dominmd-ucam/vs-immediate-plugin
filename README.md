# vs-immediate

Plugin para Claude Code que permite evaluar expresiones y controlar el depurador
de Visual Studio (2022 / 2026) desde la terminal, con el mismo efecto que usar
la Ventana Inmediato. Solo Windows.

Funciona con la automatizacion COM de Visual Studio (EnvDTE) a traves de
scripts de Windows PowerShell 5.1. No instala nada en Visual Studio.

## Instalacion

    /plugin marketplace add dominmd-ucam/vs-immediate-plugin
    /plugin install vs-immediate@vs-immediate-plugin

Actualizar: `/plugin marketplace update vs-immediate-plugin` y recargar plugins.

Para probar una rama o una copia local antes de fusionarla:

    /plugin marketplace add dominmd-ucam/vs-immediate-plugin#v0.2
    /plugin marketplace add C:\Repos\vs-immediate-plugin

(Los nombres exactos de los comandos pueden variar segun la version de
Claude Code; `/plugin` muestra las opciones.)

## Que incluye

Skills (Claude las usa solo cuando encajan con lo que pides):

- vs-immediate: los scripts base (evaluar, estado, control) y sus reglas de seguridad
- vs-diagnose: investigar un fallo con pocos breakpoints y una hipotesis apoyada en valores
- vs-elsa: depurar workflows y actividades de Elsa 3 (sondeo del contexto, incidentes, bookmarks, breakpoints por instancia, timeouts)
- vs-di-inspect: que implementacion real hay tras cada interfaz inyectada
- vs-watch: seguir valores a lo largo de varias pausas
- vs-repro: dejar un fallo como receta repetible

Comandos rapidos: `/vs-status`, `/vs-locals`, `/vs-stack`, `/vs-eval <expr>`,
`/vs-exception`, `/vs-threads`, `/vs-breakpoints`, `/vs-elsa`.

Agente: `vs-debugger`, para delegar investigaciones largas de depuracion.

Hook de permisos: aprueba sin preguntar las consultas de solo lectura a los
scripts (estado, locales, pila, hilos, ultima excepcion, tipos y expresiones
simples). Todo lo que cambia algo sigue pidiendo permiso. Detalles y limites en
`skills/vs-immediate/SKILL.md`.

## Scripts

    skills/vs-immediate/scripts/
        vs-common.ps1                  conexion a VS, reintentos, utilidades
        vs-list.ps1                    lista instancias de VS
        vs-eval.ps1                    evalua expresiones
        vs-state.ps1                   estado, locales, pila, breakpoints, Output, Errores, Procesos
        vs-types.ps1                   tipo declarado y tipo real
        vs-exceptions.ps1              ultima excepcion y configuracion de excepciones
        vs-threads.ps1                 hilos
        vs-watch.ps1                   valores a lo largo de varias pausas
        vs-elsa.ps1                    sondeo del contexto de Elsa 3
        vs-control.ps1                 compilar, iniciar, pasos, breakpoints, tracepoints, attach

## Primera prueba

- [ ] Abre Visual Studio con tu solucion (mismo nivel de permisos que la terminal)
- [ ] Pide a Claude: "usa vs-immediate para listar las instancias de Visual Studio"
- [ ] Inicia la depuracion, deja que pare en un breakpoint
- [ ] Prueba `/vs-status`, `/vs-locals` y `/vs-eval miVariable`

Tambien puedes probar un script a mano:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File skills\vs-immediate\scripts\vs-list.ps1

## Limites conocidos

- Evaluar expresiones requiere el depurador en pausa.
- No escribe texto en la ventana Inmediato; usa su mismo evaluador.
- VS y la terminal deben tener el mismo nivel de permisos.
- Con varias instancias de VS abiertas hay que indicar `-Solution` o `-ProcessId`.
- Marcadas como experimentales: configuracion de excepciones (`vs-exceptions`
  List/Break/NoBreak) y tracepoints (`AddTracepoint`); dependen de partes de la
  API de VS que cambian entre versiones.
- Estado: el hook y la logica de los scripts nuevos se probaron con un Visual
  Studio simulado, no contra Visual Studio 2026. Puede necesitar ajustes en la
  primera ejecucion real.

## Desarrollo

    git clone https://github.com/dominmd-ucam/vs-immediate-plugin
