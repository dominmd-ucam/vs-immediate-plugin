# approve-readonly.ps1 - Hook PreToolUse del plugin vs-immediate.
# Aprueba automaticamente (sin preguntar) las llamadas de SOLO LECTURA a los scripts del plugin.
# Todo lo demas (control de ejecucion, breakpoints, Execute, Command, cambios de hilo...) sigue pidiendo permiso.
# Si algo no encaja con seguridad, el hook no dice nada y Claude Code pregunta como siempre.
# Mantener este fichero en ASCII (Windows PowerShell 5.1).

$ErrorActionPreference = 'Stop'

try {
    $raw = [Console]::In.ReadToEnd()
    $data = $raw | ConvertFrom-Json
    $cmd = [string]$data.tool_input.command
}
catch {
    exit 0
}

function Approve {
    param([string]$Reason)
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'allow'
            permissionDecisionReason = $Reason
        }
    }
    Write-Output ($out | ConvertTo-Json -Depth 4 -Compress)
    exit 0
}

# Expresion "simple": sin llamadas a metodos (salvo GetType/ToString), sin asignaciones ni ++/--.
function Test-SimpleExpression {
    param([string]$Text)
    $t = $Text -replace '\.GetType\(\)', '' -replace '\.ToString\(\)', ''
    if ($t -match '[()]') { return $false }
    $t = $t -replace '==|!=|<=|>=', ''
    if ($t -match '=') { return $false }
    if ($t -match '\+\+|--') { return $false }
    return $true
}

if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# Debe ser una unica llamada a powershell, sin encadenar comandos ni redirecciones.
if ($cmd -notmatch '^\s*powershell(\.exe)?\s') { exit 0 }
if ($cmd -match '[;&|<>`]' -or $cmd -match '\$\(' -or $cmd -match "[\r\n]") { exit 0 }

# Debe ejecutar un script del propio plugin.
if ($cmd -notmatch '-File\s+"?[^"]*vs-immediate[\\/]scripts[\\/](vs-[a-z]+)\.ps1"?(\s|$)') { exit 0 }
$name = $Matches[1]

switch ($name) {
    'vs-list' { Approve 'vs-immediate: listar instancias de Visual Studio (solo lectura)' }
    'vs-state' { Approve 'vs-immediate: consulta de estado (solo lectura)' }
    'vs-threads' {
        if ($cmd -notmatch '-Action\s+"?Switch\b') { Approve 'vs-immediate: hilos (solo lectura)' }
    }
    'vs-exceptions' {
        if ($cmd -notmatch '-Action\s+"?(Break|NoBreak)\b') { Approve 'vs-immediate: excepciones (solo lectura)' }
    }
    'vs-eval' {
        if ($cmd -notmatch '-Execute\b' -and (Test-SimpleExpression $cmd)) { Approve 'vs-immediate: evaluacion de expresion simple (sin llamadas ni asignaciones)' }
    }
    'vs-types' {
        if (Test-SimpleExpression $cmd) { Approve 'vs-immediate: tipos declarados y reales (solo lectura)' }
    }
}

exit 0
