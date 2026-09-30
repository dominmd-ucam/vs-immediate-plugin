---
description: Sondeo del contexto de Elsa 3 en el punto de pausa (instancia, estado, bookmarks, incidentes)
argument-hint: "[expresión raíz, por defecto context]"
---

Sondea el contexto de ejecución de Elsa 3 en el punto donde está parado el depurador de Visual Studio. Raíz: $ARGUMENTS (si está vacío, `context`).

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/skills/vs-immediate/scripts/vs-elsa.ps1" -Root context
```

Ajusta `-Root` si el usuario indicó otro nombre. Si `${CLAUDE_PLUGIN_ROOT}` aparece sin sustituir, localiza `vs-elsa.ps1` con Glob dentro de `~/.claude/plugins`.

Resume en pocas líneas: id de la instancia y de la actividad, estado y subestado, correlación, número de bookmarks e incidentes y, si los hay, el detalle de los incidentes (actividad, mensaje, excepción) y los bookmarks pendientes. Menciona qué nombres no existen (`unavailable`) solo si impiden responder. Solo lectura: no llames a métodos del motor.
