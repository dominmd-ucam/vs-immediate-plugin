---
name: vs-repro
description: Convierte un fallo que se acaba de diagnosticar en Visual Studio en una receta repetible (breakpoints condicionales, cómo dispararlo, qué expresiones comprobar y qué resultado esperar) para poder volver a lanzarla o compartirla. Usar cuando el usuario dice "déjame esto reproducible", "cómo lo vuelvo a probar" o al cerrar una sesión de depuración.
---

# vs-repro

Deja por escrito, en la propia respuesta, cómo reproducir y comprobar un fallo con el depurador. Usa los scripts de `..\vs-immediate\scripts`. **No crees ningún fichero salvo que el usuario lo pida** (si lo pide, sugiere guardarlo en el repo, por ejemplo como nota en `docs/` o en la descripción de la incidencia).

## Qué debe contener la receta

1. **Precondiciones**: solución abierta, configuración (Debug), base de datos/datos necesarios, proyecto de inicio, variables de entorno o `appsettings` que importen.
2. **Cómo dispararlo**: la petición, el workflow, el test o el comando exacto, con el dato de entrada mínimo que provoca el fallo.
3. **Puntos de observación**: para cada breakpoint, fichero y línea (o método), condición si la hay, y por qué está ahí. Preferir condiciones que aíslen el caso (por id, por valor) para no parar con el resto del tráfico.
4. **Qué comprobar en cada parada**: las expresiones concretas (`vs-eval.ps1 -Expression ...`), y qué valor confirma el fallo frente a cuál indica que está bien.
5. **Resultado esperado vs observado**: una línea cada uno.
6. **Limpieza**: qué breakpoints quitar y cómo dejar el entorno.

## Cómo obtener los datos

- Breakpoints actuales: `vs-state.ps1 -What Breakpoints` (fichero, línea, condición, activo).
- Los que puso Claude en esta sesión: los de su lista de `vs-diagnose`; no incluyas breakpoints ajenos al caso.
- Valores clave: los que se vieron durante el diagnóstico; indica cuáles eran constantes y cuáles dependen de datos concretos.
- Si el fallo depende de datos reales, sustitúyelos por marcadores (`<id de pedido afectado>`) en lugar de copiar valores de clientes.

## Volver a ejecutarla

Si el usuario pide relanzar la receta, sigue los pasos con los mismos scripts: pon los breakpoints (`AddBreakpoint` con `-Condition`), confirma antes de `Start`/`Attach`, recoge los valores con `vs-eval`/`vs-state`, y compara con lo esperado. Para seguir un valor a lo largo de varias pausas usa `vs-watch.ps1`.

## Formato

Lista numerada breve, sin adornos. Si el fallo es de tipo "a veces pasa", dilo y describe qué condición lo dispara según la evidencia; no lo presentes como determinista si no lo es.
