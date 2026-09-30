# vs-trace.ps1 - Rastro de una evaluacion: que funciones de tu codigo se ejecutan al evaluar una expresion. (experimental)
# Pone breakpoints de solo conteo (nunca paran) en las funciones indicadas, evalua la expresion, lee cuantas veces
# se ha ejecutado cada una y elimina esos breakpoints (siempre, incluso si la evaluacion falla).
#
#   -Expression "cliente.LocalizacionesEnvio[0].OriginId"   expresion a evaluar
#   -Functions "Ns.Clase.Metodo,,Ns.Clase.Propiedad.get"    funciones a vigilar, separadas por ,, (sintaxis de breakpoint de funcion de VS)
#
# Solo detecta las funciones que se indican: elige candidatas leyendo el codigo (getters, constructores, metodos que
# la expresion puede llamar). Un 0 significa que no se ejecuto, o que el breakpoint no llego a enlazar (nombre mal escrito).
# Modifica temporalmente los breakpoints y ejecuta codigo de la aplicacion: pide confirmacion al usuario.
param(
    [Parameter(Mandatory = $true)]
    [string]$Expression,
    [Parameter(Mandatory = $true)]
    [string]$Functions,
    [int]$TimeoutMs = 10000,
    [switch]$UseStatement,   # evalua con ExecuteStatement (semantica de la Ventana Inmediato) en vez de GetExpression
    [int]$SettleMs = 500,    # espera tras crear los breakpoints, para que el depurador los enlace
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

Invoke-Main {
    $Expression = Convert-QuoteEscapes $Expression
    $names = @($Functions -split ',,' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($names.Count -eq 0) { throw 'Falta al menos una funcion en -Functions.' }
    if ($names.Count -gt 15) { throw 'Maximo 15 funciones por rastro.' }

    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger

    # Breakpoints que ya existian: no se tocan.
    $before = @()
    foreach ($b in $dbg.Breakpoints) { $before += [string]$b.FunctionName + '|' + [string]$b.File + '|' + [string]$b.FileLine }

    $mine = @()
    $rows = @()
    $result = $null
    try {
        foreach ($n in $names) {
            $row = [ordered]@{ function = $n; created = $false; hits = $null }
            try {
                # Contador puro: HitCount enorme con tipo "mayor o igual" (3) para que nunca pare la ejecucion.
                Invoke-Com { $dbg.Breakpoints.Add($n, '', 1, 1, '', 1, 'C#', '', 1, '', 1000000000, 3) } | Out-Null
                $row.created = $true
            }
            catch { $row.error = $_.Exception.Message }
            $rows += $row
        }

        # Localiza los breakpoints creados (los que no estaban antes).
        $created = @()
        foreach ($b in $dbg.Breakpoints) {
            $key = [string]$b.FunctionName + '|' + [string]$b.File + '|' + [string]$b.FileLine
            if ($before -notcontains $key) { $created += $b }
        }
        $mine = $created

        $startHits = @{}
        foreach ($b in $mine) { $startHits[[string]$b.FunctionName] = [int](Try-Get { $b.CurrentHits }) }

        if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }

        # Diagnostico de cada breakpoint tal como lo ve el depurador (para distinguir enlazados de no enlazados).
        $diag = @()
        foreach ($b in $mine) {
            $diag += [pscustomobject]@{
                reportedName = [string](Try-Get { $b.FunctionName })
                enabled      = (Try-Get { [bool]$b.Enabled })
                hitCountType = (Try-Get { [int]$b.HitCountType })
                hitCountTarget = (Try-Get { [int]$b.HitCountTarget })
                children     = (Try-Get { [int]$b.Children.Count })
                hitsBefore   = (Try-Get { [int]$b.CurrentHits })
            }
        }

        if ($UseStatement) {
            # ExecuteStatement no devuelve valor ni informa de errores: se compensa mirando el modo despues.
            Invoke-Com { $dbg.ExecuteStatement($Expression, $TimeoutMs, $true) } | Out-Null
            Write-History 'trace' $Expression $null ''
            $result = [pscustomobject]@{ valid = $null; type = ''; value = '(ExecuteStatement no devuelve el valor)' }
        }
        else {
            $r = Invoke-Com { $dbg.GetExpression($Expression, $false, $TimeoutMs) }
            Write-History 'trace' $Expression ([bool]$r.IsValidValue) ([string]$r.Value)
            $result = [pscustomobject]@{ valid = [bool]$r.IsValidValue; type = [string]$r.Type; value = (Limit-Text ([string]$r.Value) 400) }
        }

        foreach ($row in $rows) {
            if (-not $row.created) { continue }
            $hit = $null
            foreach ($b in $mine) {
                $fn = [string]$b.FunctionName
                if ($fn -ieq $row.function -or $fn -like ("*" + $row.function) -or $row.function -like ("*" + $fn)) {
                    $end = [int](Try-Get { $b.CurrentHits })
                    $start = 0
                    if ($startHits.ContainsKey($fn)) { $start = $startHits[$fn] }
                    $hit = $end - $start
                    break
                }
            }
            $row.hits = $hit
        }
    }
    finally {
        # Limpieza: solo los breakpoints creados aqui.
        foreach ($b in $mine) { try { $b.Delete() } catch {} }
    }

    $ran = @($rows | Where-Object { $_.hits -gt 0 })
    $conclusive = ($ran.Count -gt 0)
    $verdict = $null
    if (-not $conclusive) {
        $verdict = 'NO CONCLUYENTE: ninguna funcion registro aciertos. No significa que no se ejecutaran: las evaluaciones tipo Inspeccion/Locales (GetExpression) ignoran los breakpoints y los nombres sin enlazar tampoco avisan. Prueba con -UseStatement o deduce el rastro leyendo el codigo. No presentes los 0 como "no se ejecuto".'
    }
    $res = [ordered]@{
        ok         = $true
        expression = $Expression
        result     = $result
        ran        = @($ran | ForEach-Object { [pscustomobject]@{ function = $_.function; hits = $_.hits } })
        notRan     = @($rows | Where-Object { $_.created -and $_.hits -eq 0 } | ForEach-Object { $_.function })
        unknown    = @($rows | Where-Object { $_.created -and $null -eq $_.hits } | ForEach-Object { $_.function })
        notCreated = @($rows | Where-Object { -not $_.created } | ForEach-Object { [pscustomobject]@{ function = $_.function; error = $_.error } })
        conclusive = $conclusive
        verdict    = $verdict
        paste      = ('? ' + $Expression)
        breakpointDiagnostics = $diag
        method     = $(if ($UseStatement) { 'ExecuteStatement' } else { 'GetExpression' })
        cleanedUp  = $mine.Count
        note       = 'Solo se vigilan las funciones indicadas. hits = veces que se ejecuto durante esta evaluacion. 0 puede ser "no se ejecuto" o "el breakpoint no enlazo" (revisa el nombre; sintaxis: Ns.Clase.Metodo o Ns.Clase.Propiedad.get).'
    }
    Write-Json ([pscustomobject]$res)
}
