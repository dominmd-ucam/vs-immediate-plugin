---
description: Última excepción lanzada en el depurador (tipo, mensaje, InnerException, pila)
---

Muestra la última excepción por la que se ha parado el depurador de Visual Studio.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-exceptions.ps1" -Action Last
```

Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-exceptions.ps1` con Glob dentro de `~/.claude/plugins`.

Resume: tipo y mensaje de la excepción, la cadena de InnerException (la causa real suele ser la más interna) y las primeras líneas de la pila que pertenezcan al código de la aplicación. Si no hay excepción activa, dilo. No propongas arreglos sin que se pidan.
