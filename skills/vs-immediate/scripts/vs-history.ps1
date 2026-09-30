# vs-history.ps1 - Historial de expresiones que se han evaluado con el plugin (no necesita Visual Studio).
#   -Last 20      ultimas N entradas (por defecto 20)
#   -Unique       lista sin repetidas: cada expresion una vez, con cuantas veces se uso y la ultima vez
#   -Kind texto   solo un tipo: eval, execute, types, elsa, trace, watch
#   -Clear        borra el historial
# El historial vive en %LOCALAPPDATA%\vs-immediate\history.jsonl y se conserva entre sesiones.
param(
    [int]$Last = 20,
    [switch]$Unique,
    [string]$Kind = '',
    [switch]$Clear
)

. "$PSScriptRoot\vs-common.ps1"

Invoke-Main {
    $path = Get-HistoryPath
    if ($Clear) {
        $existed = Test-Path -LiteralPath $path
        if ($existed) { Remove-Item -LiteralPath $path -Force }
        Write-Json ([pscustomobject]@{ ok = $true; action = 'Clear'; cleared = $existed })
        return
    }
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Json ([pscustomobject]@{ ok = $true; count = 0; note = 'Todavia no hay historial.'; lines = @() })
        return
    }
    $entries = @()
    foreach ($l in (Get-Content -LiteralPath $path -Encoding UTF8)) {
        if (-not $l.Trim()) { continue }
        try { $entries += ($l | ConvertFrom-Json) } catch { }
    }
    if ($Kind) { $entries = @($entries | Where-Object { $_.kind -eq $Kind }) }

    if ($Unique) {
        $groups = @{}
        $order = @()
        foreach ($e in $entries) {
            $k = [string]$e.expression
            if (-not $groups.ContainsKey($k)) { $groups[$k] = [ordered]@{ expression = $k; uses = 0; last = ''; kind = ''; value = '' }; $order += $k }
            $g = $groups[$k]
            $g.uses++
            $g.last = [string]$e.time
            $g.kind = [string]$e.kind
            if ($e.value) { $g.value = [string]$e.value }
        }
        $items = @($order | ForEach-Object { [pscustomobject]$groups[$_] })
        if ($items.Count -gt $Last) { $items = @($items | Select-Object -Last $Last) }
        $lines = @($items | ForEach-Object { if ($_.kind -eq 'execute') { $_.expression } else { '? ' + $_.expression } })
        Write-Json ([pscustomobject]@{ ok = $true; unique = $true; count = $items.Count; items = $items; lines = $lines })
        return
    }

    if ($entries.Count -gt $Last) { $entries = @($entries | Select-Object -Last $Last) }
    $lines = @($entries | ForEach-Object { if ($_.kind -eq 'execute') { $_.expression } else { '? ' + $_.expression } })
    Write-Json ([pscustomobject]@{ ok = $true; unique = $false; count = $entries.Count; items = $entries; lines = $lines })
}
