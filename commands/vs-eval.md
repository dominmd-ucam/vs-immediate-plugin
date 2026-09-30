---
description: Evalúa una expresión en el depurador de Visual Studio (como la Ventana Inmediato)
argument-hint: "<expresión C#>"
---

Evalúa esta expresión en el depurador de Visual Studio (debe estar en pausa): $ARGUMENTS

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-eval.ps1" -Expression "<expresión>"
```

Sustituye `<expresión>` por lo que pide el usuario, sustituyendo CADA comilla doble por `~q~` (p. ej. `StartsWith(~q~648000~q~)`) y rodeando el argumento con comillas simples: no dejes ninguna `"` real dentro. Solo si `~q~` falla dos veces, usa un fichero temporal con `-ExpressionFile`. Detalles en la skill vs-immediate, sección "Comillas dobles en las expresiones". Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-eval.ps1` con Glob dentro de `~/.claude/plugins`.

Si el usuario no da expresión, pregúntale cuál. Si la expresión llama a métodos o asigna valores, avisa de que ejecutará código de la aplicación y confirma antes. Devuelve el tipo y el valor; si la expresión no es válida en ese contexto, explica por qué y sugiere una alternativa.
