---
name: vs-diagnose
description: Investiga un fallo en una solución .NET depurando en Visual Studio con vs-immediate, de forma ordenada y con el mínimo de breakpoints, y devuelve una hipótesis apoyada en valores observados. Usar cuando el usuario pide "depura esto", "averigua por qué falla" o "por qué llega este valor", y Visual Studio está abierto con la solución.
---

# vs-diagnose

Flujo para diagnosticar un fallo con el depurador de Visual Studio. Usa los scripts de la skill `vs-immediate`, que están en la carpeta hermana `..\vs-immediate\scripts` (mismo plugin). Lee primero el SKILL.md de `vs-immediate` si no lo has hecho en esta conversación: define cómo se invocan los scripts y las reglas de seguridad.

## Antes de tocar el depurador

1. Concreta el síntoma con el usuario: qué debería pasar, qué pasa, cómo se dispara (petición, workflow, test, arranque).
2. Lee el código con Grep/Read y formula 1 o 2 hipótesis concretas. Un breakpoint sin hipótesis es ruido.
3. `vs-list.ps1` y `vs-state.ps1 -What Status` para saber en qué modo está Visual Studio.

## Preparar la observación

- Pon como máximo 3 breakpoints, lo más cerca posible de donde la hipótesis se confirma o se descarta. Si el punto se ejecuta muchas veces, usa `-Condition` para acotar.
- Anota en tu respuesta cada breakpoint que pongas (fichero y línea). Los quitarás al final con `RemoveBreakpoint`.
- No uses `ClearBreakpoints`: borraría también los del usuario.
- Si el punto se pasa muchas veces y solo quieres ver un valor, un tracepoint (`AddTracepoint`) evita parar el servidor.
- Antes de `Start` o `Attach`, confirma con el usuario salvo que ya lo haya pedido. Si el usuario ya tiene la depuración en marcha, no la reinicies.

## Cuando pare

Recoge en este orden, sin pedir todo a la vez:

1. `vs-state.ps1 -What Status` (dónde estás).
2. Si se paró por una excepción: `vs-exceptions.ps1 -Action Last` (tipo, mensaje, InnerException, pila).
3. `vs-state.ps1 -What Stack` (quién te ha llamado).
4. `vs-state.ps1 -What Locals` y, si hace falta, `vs-eval.ps1 -Expression "<expr>"` con expresiones concretas y de solo lectura.
5. Si el problema huele a qué implementación hay detrás de una interfaz, usa `vs-types.ps1` (ver la skill `vs-di-inspect`).

Cada dato debe confirmar o descartar una hipótesis. Si ninguna se sostiene, formula otra con lo que has visto antes de seguir; no encadenes pasos a ciegas.

## Avanzar

- `StepOver` / `StepInto` con moderación (pocas veces por hipótesis).
- `Continue` cuando el breakpoint condicional volverá a saltar si el problema se repite.
- En código asíncrono, el hilo puede cambiar entre `await`s: `vs-threads.ps1 -Action List` ayuda a ver dónde está cada cosa.
- No dejes el proceso pausado mucho rato en servidores (ASP.NET, Elsa): hay timeouts y trabajos que se cancelan.

## Al terminar

1. Quita los breakpoints/tracepoints que pusiste tú.
2. Deja el depurador como estaba (si lo arrancaste tú y ya no hace falta, pregunta antes de `Stop`).
3. Responde con: hipótesis final, la evidencia (valores concretos que viste y dónde), lo que descartaste y, si procede, el arreglo propuesto. No modifiques código sin que el usuario lo pida.

Si no consigues reproducir el fallo o los datos no encajan con ninguna hipótesis, dilo con claridad y propone qué dato faltaría, en vez de forzar una conclusión.
