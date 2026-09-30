# vs-immediate

Plugin para Claude Code que permite evaluar expresiones y controlar el depurador
de Visual Studio (2022 / 2026) desde la terminal, con el mismo efecto que usar
la Ventana Inmediato. Solo Windows.

Funciona con la automatizacion COM de Visual Studio (EnvDTE) a traves de
scripts de Windows PowerShell 5.1. No instala nada en Visual Studio.

## Instalacion

Desde Claude Code, con el repo en GitHub:

    /plugin marketplace add dominmd-ucam/vs-immediate-plugin
    /plugin install vs-immediate@vs-immediate-plugin

Para probar en local antes de publicar:

    /plugin marketplace add C:\Repos\vs-immediate-plugin
    /plugin install vs-immediate@vs-immediate-plugin

Actualizar: `/plugin marketplace update vs-immediate-plugin`

(Los nombres exactos de los comandos pueden variar segun la version de
Claude Code; `/plugin` muestra las opciones.)

## Primera prueba

- [ ] Abre Visual Studio con tu solucion (mismo nivel de permisos que la terminal)
- [ ] Pide a Claude: "usa vs-immediate para listar las instancias de Visual Studio"
- [ ] Inicia la depuracion, deja que pare en un breakpoint
- [ ] Pide: "evalua `miVariable` en el depurador" o "muestrame los locales"

Tambien puedes probar un script a mano:

    powershell.exe -NoProfile -ExecutionPolicy Bypass -File skills\vs-immediate\scripts\vs-list.ps1

## Que incluye

    .claude-plugin/plugin.json         datos del plugin
    .claude-plugin/marketplace.json    permite anadir este repo como marketplace
    skills/vs-immediate/SKILL.md       instrucciones que lee Claude
    skills/vs-immediate/scripts/
        vs-common.ps1                  conexion a VS, reintentos, utilidades
        vs-list.ps1                    lista instancias de VS
        vs-eval.ps1                    evalua expresiones
        vs-state.ps1                   estado, locales, pila, breakpoints, Output
        vs-control.ps1                 compilar, iniciar, pasos, breakpoints

## Limites conocidos

- Evaluar expresiones requiere el depurador en pausa.
- No escribe texto en la ventana Inmediato; usa su mismo evaluador.
- VS y la terminal deben tener el mismo nivel de permisos.
- Con varias instancias de VS abiertas hay que indicar `-Solution` o `-ProcessId`.
- Estado inicial: version 0.1.0, escrita sin poder probarla contra Visual Studio 2026.
  Puede necesitar ajustes en la primera ejecucion real.

## Subir a GitHub

    cd C:\Repos\vs-immediate-plugin
    git init
    git add .
    git commit -m "Version inicial del plugin vs-immediate"
    git branch -M main
    git remote add origin https://github.com/dominmd-ucam/vs-immediate-plugin.git
    git push -u origin main
