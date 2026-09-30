---
description: Pila de llamadas del hilo actual (depurador en pausa)
argument-hint: "[número de frames, por defecto 20]"
---

Muestra la pila de llamadas del hilo actual en el depurador de Visual Studio. Frames a mostrar: $ARGUMENTS (si está vacío, 20).

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-state.ps1" -What Stack -Top 20
```

Ajusta `-Top` al número pedido. Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-state.ps1` con Glob dentro de `~/.claude/plugins`.

Preséntala de arriba (frame actual) hacia abajo, una línea por frame, y señala los frames que parecen código de la aplicación frente a los de framework. Si no está en pausa, dilo y no hagas nada más.
