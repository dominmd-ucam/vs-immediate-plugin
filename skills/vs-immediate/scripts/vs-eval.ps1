# vs-eval.ps1 - Evalua una expresion (o ejecuta una sentencia) en el depurador de Visual Studio.
# Requiere que el depurador este en pausa (break mode).
#
# Ejemplos:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -Expression "pedido.Lineas.Count"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -Expression "cliente" -Members
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -ExpressionFile expr.txt
param(
    [string]$Expression,
    [string]$ExpressionFile,
    [switch]$Execute,      # ejecuta como sentencia (ExecuteStatement) en vez de evaluar
    [switch]$Members,      # incluye los miembros de primer nivel del resultado
    [int]$TimeoutMs = 5000,
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

Invoke-Main {
    if ($ExpressionFile) {
        $Expression = (Get-Content -LiteralPath $ExpressionFile -Raw -Encoding UTF8).Trim()
    }
    if (-not $Expression) { throw 'Falta -Expression o -ExpressionFile.' }

    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger

    if ($Execute) {
        Invoke-Com { $dbg.ExecuteStatement($Expression, $TimeoutMs, $false) } | Out-Null
        Write-Json ([pscustomobject]@{ ok = $true; executed = $Expression })
        return
    }

    $r = Invoke-Com { $dbg.GetExpression($Expression, $false, $TimeoutMs) }
    $valid = [bool]$r.IsValidValue
    $out = [ordered]@{
        ok         = $true
        expression = $Expression
        valid      = $valid
        type       = [string]$r.Type
        value      = Limit-Text ([string]$r.Value)
    }
    if (-not $valid) { $out.note = 'La expresion no es valida en este contexto; "value" contiene el mensaje del depurador.' }

    if ($Members -and $valid) {
        $items = @()
        $n = 0
        $total = 0
        try { $total = [int]$r.DataMembers.Count } catch {}
        foreach ($m in $r.DataMembers) {
            $n++
            if ($n -gt 50) { break }
            $items += [pscustomobject]@{ name = [string]$m.Name; type = [string]$m.Type; value = Limit-Text ([string]$m.Value) 500 }
        }
        $out.members = $items
        $out.membersTotal = $total
    }
    Write-Json ([pscustomobject]$out)
}
