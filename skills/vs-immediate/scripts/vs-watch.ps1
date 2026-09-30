# vs-watch.ps1 - Sigue el valor de varias expresiones a lo largo de varias pausas.
# Toma una instantanea en la pausa actual, continua la ejecucion, espera a la siguiente pausa
# (breakpoint, normalmente condicional) y repite hasta -Iterations veces.
#   -Expressions "a;;b;;c.Count"   expresiones separadas por ;;
#   -Iterations 5                  numero de instantaneas (maximo 50)
#   -WaitSeconds 30                espera maxima a la siguiente pausa
# Requiere break mode al empezar. Deja el depurador en la ultima pausa (o en ejecucion si no volvio a parar).
param(
    [Parameter(Mandatory = $true)]
    [string]$Expressions,
    [int]$Iterations = 5,
    [int]$WaitSeconds = 30,
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

function Get-Snapshot {
    param($Vs, [string[]]$Exprs, [int]$Index)
    $dbg = $Vs.Dte.Debugger
    $frame = Try-Get { $dbg.CurrentStackFrame }
    $doc = Try-Get { $Vs.Dte.ActiveDocument }
    $vals = [ordered]@{}
    foreach ($e in $Exprs) {
        $v = Try-Get { $dbg.GetExpression($e, $false, 3000) }
        if ($v -and $v.IsValidValue) { $vals[$e] = Limit-Text ([string]$v.Value) 300 }
        elseif ($v) { $vals[$e] = '(no valida) ' + (Limit-Text ([string]$v.Value) 120) }
        else { $vals[$e] = '(sin resultado)' }
    }
    $fn = $null
    if ($frame) { $fn = [string]$frame.FunctionName }
    $line = $null
    if ($doc) { $line = Try-Get { [int]$doc.Selection.CurrentLine } }
    return [pscustomobject]@{ n = $Index; function = $fn; line = $line; values = [pscustomobject]$vals }
}

Invoke-Main {
    $exprs = @($Expressions -split ';;' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($exprs.Count -eq 0) { throw 'Falta al menos una expresion en -Expressions.' }
    if ($Iterations -lt 1) { $Iterations = 1 }
    if ($Iterations -gt 50) { $Iterations = 50 }

    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger

    $snaps = @()
    $note = $null
    $snaps += Get-Snapshot $vs $exprs 1
    for ($i = 2; $i -le $Iterations; $i++) {
        Invoke-Com { $dbg.Go($false) } | Out-Null
        $m = Wait-NotRunning $dbg $WaitSeconds
        if ($m -eq 3) { $note = "La ejecucion sigue en marcha: no hubo nueva pausa en $WaitSeconds s (iteracion $i)."; break }
        if ($m -eq 1) { $note = 'La sesion de depuracion termino.'; break }
        $snaps += Get-Snapshot $vs $exprs $i
    }
    $res = [ordered]@{ ok = $true; expressions = $exprs; snapshots = $snaps }
    if ($note) { $res.note = $note }
    Write-Json ([pscustomobject]$res)
}
