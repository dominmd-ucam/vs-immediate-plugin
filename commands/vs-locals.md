---
description: Variables locales y argumentos del frame actual (depurador en pausa)
---

Muestra las variables locales y los argumentos del frame actual del depurador de Visual Studio.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-state.ps1" -What Locals
```

Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-state.ps1` con Glob dentro de `~/.claude/plugins`.

Preséntalos como una lista corta: nombre, tipo y valor (para interfaces, el tipo real entre llaves). Si el depurador no está en pausa, dilo y no hagas nada más. No evalúes ni cambies nada por tu cuenta.
