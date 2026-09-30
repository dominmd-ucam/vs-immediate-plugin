# vs-exceptions.ps1 - Excepciones en el depurador de Visual Studio.
#   -Action Last                 ultima excepcion lanzada (tipo, mensaje, cadena de InnerException, pila). Break mode.
#   -Action List [-Type texto]   grupos de excepciones, o excepciones de un grupo que contengan el texto
#   -Action Break   -Type <T>    activa "parar al lanzarse" para el tipo T (p. ej. System.NullReferenceException)
#   -Action NoBreak -Type <T>    lo desactiva
# List / Break / NoBreak usan la API de excepciones de DTE (experimental: puede variar entre versiones de VS).
param(
    [ValidateSet('Last', 'List', 'Break', 'NoBreak')]
    [string]$Action = 'Last',
    [string]$Type,
    [string]$Group = 'Common Language Runtime Exceptions',
    [int]$Top = 40,
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

Invoke-Main {
    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    $dbg = $vs.Dte.Debugger

    switch ($Action) {
        'Last' {
            Assert-BreakMode $vs
            $r = Try-Get { $dbg.GetExpression('$exception', $false, 3000) }
            if (-not $r -or -not $r.IsValidValue) {
                Write-Json ([pscustomobject]@{ ok = $true; hasException = $false; note = 'No hay excepcion activa en este punto de pausa (no se paro por una excepcion).' })
                return
            }
            $chain = @()
            $expr = '$exception'
            for ($i = 0; $i -lt 6; $i++) {
                $t = Eval-Value $dbg ($expr + '.GetType().FullName')
                if (-not $t) { break }
                $m = Eval-Value $dbg ($expr + '.Message')
                $chain += [pscustomobject]@{ depth = $i; type = (Unquote-Text $t); message = (Unquote-Text $m) }
                $expr += '.InnerException'
            }
            $st = Eval-Value $dbg '$exception.StackTrace'
            if ($st) { $st = (Unquote-Text $st) -replace '\\r\\n', "`n" -replace '\\n', "`n" }
            Write-Json ([pscustomobject]@{
                ok           = $true
                hasException = $true
                summary      = Limit-Text ([string]$r.Value) 300
                chain        = $chain
                stackTrace   = Limit-Text $st 3000
            })
        }
        'List' {
            if (-not $Type) {
                $groups = @()
                foreach ($g in $dbg.ExceptionGroups) { $groups += [pscustomobject]@{ name = [string]$g.Name } }
                Write-Json ([pscustomobject]@{ ok = $true; groups = $groups; note = 'Usa -Group <nombre> -Type <texto> para buscar excepciones dentro de un grupo.' })
                return
            }
            $grp = $dbg.ExceptionGroups.Item($Group)
            $found = @()
            foreach ($e in $grp) {
                $name = [string]$e.Name
                if ($name -like "*$Type*") {
                    $found += [pscustomobject]@{ name = $name; code = (Try-Get { [int]$e.Code }); state = (Try-Get { [string]$e.State }) }
                    if ($found.Count -ge $Top) { break }
                }
            }
            Write-Json ([pscustomobject]@{ ok = $true; group = $Group; count = $found.Count; exceptions = $found })
        }
        { $_ -in 'Break', 'NoBreak' } {
            if (-not $Type) { throw 'Falta -Type (nombre completo de la excepcion, p. ej. System.NullReferenceException).' }
            $grp = $dbg.ExceptionGroups.Item($Group)
            $setting = $null
            try { $setting = $grp.Item($Type) } catch {}
            if (-not $setting) { $setting = $grp.NewException($Type, 0) }
            $enable = ($Action -eq 'Break')
            $grp.SetBreakWhenThrown($enable, $setting)
            Write-Json ([pscustomobject]@{ ok = $true; action = $Action; group = $Group; type = $Type; breakWhenThrown = $enable })
        }
    }
}
