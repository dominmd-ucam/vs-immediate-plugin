---
description: Hilos del proceso depurado y dónde está cada uno (depurador en pausa)
---

Lista los hilos del proceso que se está depurando en Visual Studio.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-threads.ps1" -Action List
```

Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-threads.ps1` con Glob dentro de `~/.claude/plugins`.

Presenta una tabla corta: id, nombre, ubicación actual, y marca el hilo actual. Destaca los hilos cuya ubicación sea código de la aplicación. No cambies de hilo (`Switch`) sin que el usuario lo pida.
