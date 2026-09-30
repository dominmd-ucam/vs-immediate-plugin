# install-codex.ps1 - Instala vs-immediate para Codex en Windows (CLI, app de escritorio e IDE).
# Copia las skills a $HOME\.agents\skills (donde las lee Codex en todas sus superficies) y genera las reglas de
# permisos en $HOME\.codex\rules para que los scripts se ejecuten FUERA del sandbox (necesario para llegar por COM
# al Visual Studio que corre con tu usuario).
#
#   .\install\install-codex.ps1               instala o actualiza (vuelve a ejecutarlo tras cada git pull)
#   .\install\install-codex.ps1 -Uninstall    lo quita
#   .\install\install-codex.ps1 -SkipRules    solo copia las skills
param(
    [string]$SkillsDir = (Join-Path $env:USERPROFILE '.agents\skills'),
    [string]$RulesDir = (Join-Path $env:USERPROFILE '.codex\rules'),
    [switch]$SkipRules,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo 'skills'
$rulesFile = Join-Path $RulesDir 'vs-immediate.rules'
$names = @(Get-ChildItem -LiteralPath $src -Directory | ForEach-Object { $_.Name })

if ($Uninstall) {
    foreach ($n in $names) {
        $d = Join-Path $SkillsDir $n
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force; Write-Host "Quitada: $d" }
    }
    if (Test-Path -LiteralPath $rulesFile) { Remove-Item -LiteralPath $rulesFile -Force; Write-Host "Quitado: $rulesFile" }
    return
}

New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
foreach ($n in $names) {
    $d = Join-Path $SkillsDir $n
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
    Copy-Item -LiteralPath (Join-Path $src $n) -Destination $d -Recurse -Force
    Write-Host "Skill instalada: $d"
}

if ($SkipRules) { Write-Host 'Reglas omitidas (-SkipRules).'; return }

# Reglas de Codex: prefix_rule sobre el comando exacto. Los .ps1 de solo lectura se permiten; el resto pide aprobacion.
# En ambos casos el comando se ejecuta fuera del sandbox.
$scriptsBack = Join-Path (Join-Path $SkillsDir 'vs-immediate') 'scripts'
$scriptsFwd = $scriptsBack.Replace('\', '/')

function ConvertTo-Star {
    param([string]$Text)
    return '"' + $Text.Replace('\', '\\').Replace('"', '\"') + '"'
}

function New-Rule {
    param([string]$Script, [string]$Decision, [string]$Why)
    $a = ConvertTo-Star ($scriptsBack + '\' + $Script)
    $b = ConvertTo-Star ($scriptsFwd + '/' + $Script)
    return @"
prefix_rule(
    pattern = [["powershell.exe", "powershell"], "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", [$a, $b]],
    decision = "$Decision",
    justification = "$Why",
)

"@
}

$allow = @(
    @('vs-state.ps1', 'vs-immediate: consulta de estado de Visual Studio (solo lectura)'),
    @('vs-list.ps1', 'vs-immediate: lista instancias de Visual Studio (solo lectura)'),
    @('vs-history.ps1', 'vs-immediate: historial de expresiones evaluadas')
)
$ask = @(
    @('vs-eval.ps1', 'vs-immediate: evalua una expresion en el depurador (puede ejecutar codigo de la aplicacion)'),
    @('vs-types.ps1', 'vs-immediate: tipos declarados y reales'),
    @('vs-elsa.ps1', 'vs-immediate: sondeo del contexto de Elsa'),
    @('vs-threads.ps1', 'vs-immediate: hilos del proceso depurado (Switch cambia el hilo actual)'),
    @('vs-exceptions.ps1', 'vs-immediate: excepciones del depurador'),
    @('vs-trace.ps1', 'vs-immediate: rastro de una evaluacion (toca breakpoints)'),
    @('vs-watch.ps1', 'vs-immediate: sigue valores entre pausas (continua la ejecucion)'),
    @('vs-control.ps1', 'vs-immediate: controla el depurador (continuar, pasos, breakpoints, adjuntar)')
)

$text = "# Generado por install-codex.ps1. No lo edites a mano: vuelve a ejecutar el instalador.`n"
$text += "# allow = se ejecuta sin preguntar, fuera del sandbox. prompt = pide aprobacion y se ejecuta fuera del sandbox.`n`n"
foreach ($r in $allow) { $text += New-Rule $r[0] 'allow' $r[1] }
foreach ($r in $ask) { $text += New-Rule $r[0] 'prompt' $r[1] }

New-Item -ItemType Directory -Path $RulesDir -Force | Out-Null
[System.IO.File]::WriteAllText($rulesFile, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Reglas escritas: $rulesFile"
Write-Host ''
Write-Host ('Comprobacion (opcional): codex execpolicy check --pretty --rules "' + $rulesFile + '" -- powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $scriptsBack + '\vs-state.ps1"')
Write-Host 'Reinicia Codex para que cargue las skills y las reglas.'
