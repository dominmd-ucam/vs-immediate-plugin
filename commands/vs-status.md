---
description: Estado del depurador de Visual Studio (modo, solución, función actual)
---

Muestra el estado del depurador de Visual Studio con el plugin vs-immediate.

Ejecuta `vs-state.ps1 -What Status` con Windows PowerShell 5.1:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-state.ps1" -What Status
```

Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-state.ps1` con Glob dentro de `~/.claude/plugins` y usa esa ruta.

Resume el resultado en pocas líneas: solución abierta, modo (`design`, `run` o `break`) y, si está en pausa, función y línea actuales. Si hay varias instancias de Visual Studio o falla la conexión, explica qué hacer según el mensaje de error. No ejecutes nada más.
