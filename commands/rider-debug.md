---
description: Comprueba la conexión con el depurador de Rider (plugin Debugger MCP Server) y muestra su estado
---

Comprueba si Claude Code puede controlar el depurador de JetBrains Rider por MCP y muestra el estado.

1. Mira si están disponibles las herramientas `mcp__rider-debugger__*` (por ejemplo `list_debug_sessions`). Si no están, no inventes: explica que falta la preparación de la skill `rider-debug` (plugin Debugger MCP Server en Rider, `claude mcp add --transport http rider-debugger http://127.0.0.1:29202/debugger-mcp/streamable-http --scope user` y abrir una sesión nueva) y para.
2. Si están, llama a `list_debug_sessions` (con `project_path` si Rider tiene varias soluciones abiertas). Si hay una sesión activa, `get_debug_session_status` y resume: estado (en ejecución o parada), archivo y línea actuales, y las primeras variables relevantes.
3. Si no hay sesión, di que Rider está conectado y sin depuración en marcha, y ofrece listar los breakpoints (`list_breakpoints`).

No cambies nada: no pongas breakpoints, no avances ni evalúes expresiones con efectos. Para trabajar de verdad sigue la skill `rider-debug`.
