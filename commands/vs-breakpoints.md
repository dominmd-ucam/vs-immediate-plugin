---
description: Breakpoints definidos en Visual Studio (fichero, línea, condición, activo)
---

Lista los breakpoints definidos en Visual Studio.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-state.ps1" -What Breakpoints
```

Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-state.ps1` con Glob dentro de `~/.claude/plugins`.

Preséntalos en una lista corta: fichero y línea, condición si la tiene, y si está activo. Solo lectura: no añadas ni quites ninguno.
