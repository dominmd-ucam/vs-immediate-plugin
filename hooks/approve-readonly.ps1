# approve-readonly.ps1 - Hook PreToolUse del plugin vs-immediate.
# Aprueba automaticamente (sin preguntar) las llamadas de SOLO LECTURA a los scripts del plugin.
# Todo lo demas (control de ejecucion, breakpoints, Execute, Command, cambios de hilo...) sigue pidiendo permiso.
# Si algo no encaja con seguridad, el hook no dice nada y Claude Code pregunta como siempre.
# Mantener este fichero en ASCII (Windows PowerShell 5.1). La version para WSL es approve-readonly.sh: mantener la
# misma logica en ambos (los casos de prueba son comunes).

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

# Metodos que se consideran de solo lectura dentro de una expresion (lista cerrada, distingue mayusculas).
# Pueden ejecutar consultas de lectura (p. ej. un IQueryable de EF al hacer Count() o ToList()), pero no cambian datos.
$script:AllowedMethods = @(
    'Where',`
    'Select',`
    'SelectMany',`
    'Count',`
    'LongCount',`
    'Any',`
    'All',`
    'First',`
    'FirstOrDefault',`
    'Last',`
    'LastOrDefault',`
    'Single',`
    'SingleOrDefault',`
    'ElementAt',`
    'ElementAtOrDefault',`
    'Take',`
    'Skip',`
    'TakeWhile',`
    'SkipWhile',`
    'OrderBy',`
    'OrderByDescending',`
    'ThenBy',`
    'ThenByDescending',`
    'Distinct',`
    'DistinctBy',`
    'GroupBy',`
    'Sum',`
    'Min',`
    'Max',`
    'Average',`
    'Contains',`
    'ContainsKey',`
    'ContainsValue',`
    'Cast',`
    'OfType',`
    'ToList',`
    'ToArray',`
    'ToDictionary',`
    'ToHashSet',`
    'Zip',`
    'Concat',`
    'Union',`
    'Intersect',`
    'Except',`
    'Join',`
    'Split',`
    'StartsWith',`
    'EndsWith',`
    'IndexOf',`
    'LastIndexOf',`
    'Substring',`
    'ToUpper',`
    'ToLower',`
    'ToUpperInvariant',`
    'ToLowerInvariant',`
    'Trim',`
    'TrimStart',`
    'TrimEnd',`
    'Equals',`
    'CompareTo',`
    'IsNullOrEmpty',`
    'IsNullOrWhiteSpace',`
    'ToString',`
    'GetType',`
    'GetHashCode',`
    'GetValueOrDefault',`
    'Format'
)

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

# Expresion C# de solo lectura: solo caracteres de una lista blanca, sin asignaciones ni ++/--, sin "new", y cada
# llamada a metodo tiene que estar en la lista cerrada. Los literales de cadena se ignoran (son datos).
function Test-CSharpSafe {
    param([string]$Text)
    $s = $Text.Replace('~q~', '"')
    if ($s.Contains('@"') -or $s.Contains('$"') -or $s.Contains('`') -or $s.Contains('$(') -or $s.Contains('${')) { return $false }
    $s = [regex]::Replace($s, '"(?:\\.|[^"\\])*"', '0')
    if ($s -notmatch '^[A-Za-z0-9_$.,()\[\]?:!=<>+*/%&|^ -]*$') { return $false }
    if ($s -match '(?<![A-Za-z0-9_])(?:new|await|ref|out|unsafe|stackalloc)(?![A-Za-z0-9_])') { return $false }
    $t = $s -replace '==|!=|<=|>=|=>', ''
    if ($t.Contains('=')) { return $false }
    if ($s.Contains('++') -or $s.Contains('--')) { return $false }
    if ($s -match '[)\]]\s*\(' -or $s -match '[A-Za-z0-9_\])]\s*!\s*\(' -or $s -match '[A-Za-z0-9_]>\s*\(') { return $false }
    foreach ($m in [regex]::Matches($s, '([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
        if ($script:AllowedMethods -cnotcontains $m.Groups[1].Value) { return $false }
    }
    return $true
}

# Separa los argumentos entre comillas simples (palabras completas) del resto. Las comillas simples son literales en
# bash y en PowerShell, asi que ahi dentro los simbolos ; & | < > no tienen efecto en la linea de comandos.
# Si queda alguna comilla simple suelta (o pegada a otro texto), se devuelve $null: no se aprueba.
function Split-SingleQuoted {
    param([string]$Text)
    $segments = @()
    $outside = $Text
    $rx = [regex]"(?:^|\s)'([^']*)'(?=\s|$)"
    while ($true) {
        $m = $rx.Match($outside)
        if (-not $m.Success) { break }
        $segments += $m.Groups[1].Value
        $outside = $outside.Substring(0, $m.Index) + ' ' + $outside.Substring($m.Index + $m.Length)
    }
    if ($outside.Contains("'")) { return $null }
    return [pscustomobject]@{ Outside = $outside; Segments = $segments }
}

# PowerShell admite abreviar los nombres de parametro (-Exec, -ExpressionF, -Cl...): se detectan por prefijo.
function Test-FlagPrefix {
    param([string]$Text, [string]$Full, [int]$MinLen)
    foreach ($m in [regex]::Matches($Text, '(?:^|[\s"''])-([A-Za-z]+)')) {
        $n = $m.Groups[1].Value
        if ($n.Length -ge $MinLen -and $Full.StartsWith($n, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# Una sola linea, empezando por powershell.
if ($cmd -notmatch '^\s*powershell(\.exe)?\s') { exit 0 }
if ($cmd -match "[\r\n]") { exit 0 }

# Debe tener exactamente la forma de la plantilla (sin -Command ni otras opciones antes de -File) y ejecutar un
# script del propio plugin. La ruta sin comillas no puede llevar espacios (si no, podria colarse otro fichero).
$tpl = '^\s*powershell(?:\.exe)?\s+-NoProfile\s+-ExecutionPolicy\s+Bypass\s+-File\s+(?:"[^"]*|[^"\s]*)vs-immediate[\\/]scripts[\\/](vs-[a-z]+)\.ps1"?(?:\s|$)'
$tm = [regex]::Match($cmd, $tpl)
if (-not $tm.Success) { exit 0 }
$name = $tm.Groups[1].Value
$prefix = $cmd.Substring(0, $tm.Length)
$rest = $cmd.Substring($tm.Length)

# Solo vs-eval, vs-types y vs-elsa admiten expresiones: sus argumentos entre comillas simples se analizan aparte.
$outside = $rest
$segments = @()
if ($name -in @('vs-eval', 'vs-types', 'vs-elsa')) {
    $sp = Split-SingleQuoted $rest
    if (-not $sp) { exit 0 }
    $outside = $sp.Outside
    $segments = @($sp.Segments)
}

# Fuera de las comillas simples: sin encadenar comandos, redirecciones ni sustituciones.
$scan = $prefix + $outside
if ($scan -match '[;&|<>`]' -or $scan -match '\$\(' -or $scan -match '\$\{') { exit 0 }

function Test-ExpressionArgs {
    if (-not (Test-SimpleExpression $outside)) { return $false }
    foreach ($seg in $segments) { if (-not (Test-CSharpSafe $seg)) { return $false } }
    return $true
}

switch ($name) {
    'vs-list' { Approve 'vs-immediate: listar instancias de Visual Studio (solo lectura)' }
    'vs-state' { Approve 'vs-immediate: consulta de estado (solo lectura)' }
    'vs-history' {
        if (-not (Test-FlagPrefix $rest 'Clear' 1)) { Approve 'vs-immediate: historial de expresiones (solo lectura)' }
    }
    'vs-threads' {
        if ($rest -notmatch '\bSwitch\b') { Approve 'vs-immediate: hilos (solo lectura)' }
    }
    'vs-exceptions' {
        if ($rest -notmatch '\b(Break|NoBreak)\b') { Approve 'vs-immediate: excepciones (solo lectura)' }
    }
    'vs-eval' {
        # Con -ExpressionFile el contenido esta en un fichero que el hook no ve: no se aprueba solo.
        if (-not (Test-FlagPrefix $rest 'Execute' 3) -and -not (Test-FlagPrefix $rest 'ExpressionFile' 11) -and (Test-ExpressionArgs)) { Approve 'vs-immediate: evaluacion de expresion de solo lectura (lista cerrada de metodos, sin asignaciones)' }
    }
    'vs-types' {
        if (Test-ExpressionArgs) { Approve 'vs-immediate: tipos declarados y reales (solo lectura)' }
    }
    'vs-elsa' {
        if (Test-ExpressionArgs) { Approve 'vs-immediate: sondeo del contexto de Elsa (solo lectura)' }
    }
}

exit 0
