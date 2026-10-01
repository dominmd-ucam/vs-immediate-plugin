# vs-run.ps1 - Lanzador para WSL (lo usa vs.sh; no hace falta llamarlo a mano).
# Recibe el nombre del script (vs-eval, vs-state...) y los argumentos en la variable de entorno VS_IMMEDIATE_ARGS:
# cada argumento en base64 (UTF-8), separados por comas; un argumento vacio se escribe "=". Asi ninguna capa de
# comillas (bash, WSL, linea de comandos de Windows) puede alterarlos. Los vincula por nombre a los parametros
# del script y lo ejecuta.
# Mantener este fichero en ASCII (Windows PowerShell 5.1).
param(
    [Parameter(Mandatory = $true)]
    [string]$Name
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

function Write-Fail {
    param([string]$Message)
    Write-Output (([ordered]@{ ok = $false; error = $Message }) | ConvertTo-Json -Compress)
    exit 1
}

function Resolve-ParamName {
    param([string]$Raw, $Meta)
    $n = $Raw.TrimStart('-')
    foreach ($k in $Meta.Keys) { if ($k -ieq $n) { return $k } }
    $cands = @($Meta.Keys | Where-Object { $_.StartsWith($n, [System.StringComparison]::OrdinalIgnoreCase) })
    if ($cands.Count -eq 1) { return $cands[0] }
    return $null
}

$Name = $Name -replace '\.ps1$', ''
if ($Name -notmatch '^vs-[a-z]+$' -or $Name -eq 'vs-common' -or $Name -eq 'vs-run') { Write-Fail 'Nombre de script no valido.' }
$path = Join-Path $PSScriptRoot ($Name + '.ps1')
if (-not (Test-Path -LiteralPath $path)) { Write-Fail ('No existe el script ' + $Name + '.ps1') }

$tokens = @()
$raw = $env:VS_IMMEDIATE_ARGS
if (-not [string]::IsNullOrEmpty($raw)) {
    foreach ($b in $raw.Split(',')) {
        if ($b -eq '=') { $tokens += '' }
        else {
            try { $tokens += [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) }
            catch { Write-Fail 'Argumentos mal codificados (VS_IMMEDIATE_ARGS).' }
        }
    }
}

$meta = (Get-Command -Name $path).Parameters
$splat = @{}
$i = 0
while ($i -lt $tokens.Count) {
    $t = $tokens[$i]
    if ($t -notmatch '^-[A-Za-z]') { Write-Fail ('Argumento inesperado (se esperaba un parametro tipo -Nombre): ' + $t) }
    $key = Resolve-ParamName $t $meta
    if (-not $key) { Write-Fail ('Parametro desconocido o ambiguo: ' + $t) }
    $i++
    if ($meta[$key].SwitchParameter) { $splat[$key] = $true; continue }
    if ($i -ge $tokens.Count) { Write-Fail ('Falta el valor de ' + $t) }
    $splat[$key] = $tokens[$i]
    $i++
}

try {
    & $path @splat
}
catch {
    Write-Fail $_.Exception.Message
}
if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
