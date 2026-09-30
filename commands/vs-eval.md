---
description: Evalúa una expresión en el depurador de Visual Studio (como la Ventana Inmediato)
argument-hint: "<expresión C#>"
---

Evalúa esta expresión en el depurador de Visual Studio (debe estar en pausa): $ARGUMENTS

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-eval.ps1" -Expression "<expresión>"
```

Sustituye `<expresión>` por lo que pide el usuario, escapando bien las comillas (si lleva comillas o caracteres delicados, escríbela en un fichero temporal y usa `-ExpressionFile`). Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-eval.ps1` con Glob dentro de `~/.claude/plugins`.

Si el usuario no da expresión, pregúntale cuál. Si la expresión llama a métodos o asigna valores, avisa de que ejecutará código de la aplicación y confirma antes. Devuelve el tipo y el valor; si la expresión no es válida en ese contexto, explica por qué y sugiere una alternativa.
