# vs-threads.ps1 - Hilos del proceso depurado (break mode).
#   -Action List                       lista los hilos (id, nombre, ubicacion actual); marca el hilo actual
#   -Action Stack [-ThreadId n]        pila de llamadas de un hilo (por defecto el actual) sin cambiar de hilo
#   -Action Switch -ThreadId n         cambia el hilo actual del depurador (afecta a Locals, Stack y Eval)
param(
    [ValidateSet('List', 'Stack', 'Switch')]
    [string]$Action = 'List',
    [int]$ThreadId = 0,
    [int]$Top = 30,
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

function Find-Thread {
    param($Dbg, [int]$Id)
    foreach ($t in $Dbg.CurrentProgram.Threads) {
        if ([int]$t.ID -eq $Id) { return $t }
    }
    throw "No existe el hilo $Id en el programa actual. Usa -Action List para ver los ids."
}

Invoke-Main {
    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger
    $currentId = [int](Invoke-Com { $dbg.CurrentThread.ID })

    switch ($Action) {
        'List' {
            $items = @()
            $n = 0
            foreach ($t in $dbg.CurrentProgram.Threads) {
                $n++
                if ($n -gt $Top) { break }
                $items += [pscustomobject]@{
                    id       = [int]$t.ID
                    current  = ([int]$t.ID -eq $currentId)
                    name     = (Try-Get { [string]$t.Name })
                    location = (Try-Get { [string]$t.Location })
                    frozen   = (Try-Get { [bool]$t.IsFrozen })
                    suspend  = (Try-Get { [int]$t.SuspendCount })
                }
            }
            Write-Json ([pscustomobject]@{ ok = $true; currentThreadId = $currentId; count = $items.Count; threads = $items })
        }
        'Stack' {
            $id = $ThreadId
            if ($id -eq 0) { $id = $currentId }
            $t = Find-Thread $dbg $id
            $frames = @()
            $n = 0
            foreach ($f in $t.StackFrames) {
                $n++
                if ($n -gt $Top) { break }
                $frames += [pscustomobject]@{ index = $n; function = [string]$f.FunctionName; module = [string]$f.Module }
            }
            Write-Json ([pscustomobject]@{ ok = $true; threadId = $id; frames = $frames })
        }
        'Switch' {
            if ($ThreadId -le 0) { throw 'Falta -ThreadId.' }
            $t = Find-Thread $dbg $ThreadId
            $dbg.CurrentThread = $t
            $fn = $null
            $frame = Try-Get { $dbg.CurrentStackFrame }
            if ($frame) { $fn = [string]$frame.FunctionName }
            if (-not $fn) {
                # El frame superior puede ser nativo/sin nombre: se toma el primero con nombre de la pila del hilo.
                foreach ($f in $t.StackFrames) {
                    $name = [string]$f.FunctionName
                    if ($name -and $name -notmatch '^\[') { $fn = $name; break }
                }
            }
            Write-Json ([pscustomobject]@{ ok = $true; action = 'Switch'; threadId = $ThreadId; function = $fn; currentThreadId = [int](Try-Get { $dbg.CurrentThread.ID }) })
        }
    }
}
