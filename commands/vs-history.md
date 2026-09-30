---
description: Lista las expresiones que se han evaluado con el plugin (historial)
---

Muestra el historial de expresiones evaluadas con vs-immediate, sin repetidas y listas para pegar en la Ventana Inmediato.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-history.ps1" -Unique -Last 30
```

Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-history.ps1` con Glob dentro de `~/.claude/plugins`.

Preséntalo como un bloque de código con una expresión por línea (usa el campo `lines`), y debajo, si aporta, cuántas veces se usó cada una. No evalúes nada nuevo. Si el usuario pide solo las de esta conversación o un tipo concreto, ajusta `-Last` o `-Kind`.
