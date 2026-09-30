# vs-state.ps1 - Consulta el estado del depurador de Visual Studio (solo lectura).
#   -What Status       modo del depurador, solucion, proceso, frame actual
#   -What Locals       variables locales y argumentos del frame actual (break mode)
#   -What Stack        pila de llamadas del hilo actual (break mode)
#   -What Breakpoints  breakpoints definidos
#   -What Output       ultimas lineas de un panel de la ventana Output (por defecto "Debug")
#   -What Errors       Lista de errores de VS (errores/avisos del ultimo build); -Level Error|Warning|All
#   -What Processes    procesos locales que se pueden depurar; -Filter <texto del nombre>
param(
    [ValidateSet('Status', 'Locals', 'Stack', 'Breakpoints', 'Output', 'Errors', 'Processes')]
    [string]$What = 'Status',
    [int]$Top = 30,        # maximo de elementos para Locals / Stack / Breakpoints / Errors / Processes
    [int]$Tail = 50,       # lineas finales para Output
    [string]$Pane = 'Debug',
    [ValidateSet('Error', 'Warning', 'All')]
    [string]$Level = 'Error',
    [string]$Filter = '',
    [switch]$SyncCaret,    # con -What Status: sincroniza el caret con la sentencia actual antes de leer la linea
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

function ConvertTo-ExprItems {
    param($Collection, [int]$Max)
    $items = @()
    $n = 0
    foreach ($e in $Collection) {
        $n++
        if ($n -gt $Max) { break }
        $items += [pscustomobject]@{ name = [string]$e.Name; type = [string]$e.Type; value = Limit-Text ([string]$e.Value) 500 }
    }
    return $items
}

Invoke-Main {
    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    $dbg = $vs.Dte.Debugger
    $mode = [int](Invoke-Com { $dbg.CurrentMode })

    switch ($What) {
        'Status' {
            $res = [ordered]@{
                ok           = $true
                solution     = $vs.Solution
                processId    = $vs.ProcessId
                debuggerMode = Get-ModeName $mode
            }
            if ($mode -ne 1) {
                $proc = Try-Get { $dbg.CurrentProcess }
                if ($proc) { $res.debuggee = [pscustomobject]@{ name = [string]$proc.Name; processId = [int]$proc.ProcessID } }
            }
            if ($mode -eq 2) {
                $frame = Try-Get { $dbg.CurrentStackFrame }
                if ($frame) {
                    $res.frame = [pscustomobject]@{ function = [string]$frame.FunctionName; module = [string]$frame.Module; language = [string]$frame.Language }
                }
                $sp = Get-SourcePosition $vs ([bool]$SyncCaret)
                if ($sp) { $res.sourcePosition = $sp }
            }
            Write-Json ([pscustomobject]$res)
        }
        'Locals' {
            Assert-BreakMode $vs
            $frame = Invoke-Com { $dbg.CurrentStackFrame }
            $locals = ConvertTo-ExprItems $frame.Locals $Top
            $frameArgs = ConvertTo-ExprItems $frame.Arguments $Top
            Write-Json ([pscustomobject]@{ ok = $true; function = [string]$frame.FunctionName; arguments = $frameArgs; locals = $locals })
        }
        'Stack' {
            Assert-BreakMode $vs
            $thread = Invoke-Com { $dbg.CurrentThread }
            $frames = @()
            $n = 0
            foreach ($f in $thread.StackFrames) {
                $n++
                if ($n -gt $Top) { break }
                $frames += [pscustomobject]@{ index = $n; function = [string]$f.FunctionName; module = [string]$f.Module; language = [string]$f.Language }
            }
            Write-Json ([pscustomobject]@{ ok = $true; threadId = [int]$thread.ID; frames = $frames })
        }
        'Breakpoints' {
            $items = @()
            $n = 0
            foreach ($b in $dbg.Breakpoints) {
                $n++
                if ($n -gt $Top) { break }
                $items += [pscustomobject]@{
                    file      = [string]$b.File
                    line      = [int]$b.FileLine
                    enabled   = [bool]$b.Enabled
                    condition = [string]$b.Condition
                    function  = [string]$b.FunctionName
                }
            }
            Write-Json ([pscustomobject]@{ ok = $true; count = $items.Count; breakpoints = $items })
        }
        'Output' {
            $panes = $vs.Dte.ToolWindows.OutputWindow.OutputWindowPanes
            $p = $null
            $names = @()
            foreach ($x in $panes) {
                $names += [string]$x.Name
                if ($x.Name -eq $Pane) { $p = $x }
            }
            if (-not $p) {
                # Los paneles integrados a veces no aparecen al enumerar: se prueba por nombre y por GUID (independiente del idioma).
                $guids = @{ 'debug' = '{FC076020-078A-11D1-A7DF-00A0C9110051}'; 'depurar' = '{FC076020-078A-11D1-A7DF-00A0C9110051}'; 'depuracion' = '{FC076020-078A-11D1-A7DF-00A0C9110051}'; 'build' = '{1BD8A850-02D1-11D1-BEE7-00A0C913D1F8}'; 'compilar' = '{1BD8A850-02D1-11D1-BEE7-00A0C913D1F8}' }
                $p = Try-Get { $panes.Item($Pane) }
                if (-not $p -and $guids.ContainsKey($Pane.ToLower())) { $p = Try-Get { $panes.Item($guids[$Pane.ToLower()]) } }
            }
            if (-not $p) { throw ("No se pudo abrir el panel '$Pane'. Paneles enumerados: [" + ($names -join ', ') + "]. En algunas versiones de VS el panel de depuracion no es accesible por DTE; mira la ventana Output de VS.") }
            $doc = $p.TextDocument
            $text = $doc.StartPoint.CreateEditPoint().GetText($doc.EndPoint)
            $lines = @($text -split "\r?\n")
            if ($lines.Count -gt $Tail) { $lines = $lines[($lines.Count - $Tail)..($lines.Count - 1)] }
            Write-Json ([pscustomobject]@{ ok = $true; pane = $Pane; lines = $lines })
        }
        'Errors' {
            $items = $vs.Dte.ToolWindows.ErrorList.ErrorItems
            $total = [int]$items.Count
            $found = @()
            for ($i = 1; $i -le $total; $i++) {
                $it = $items.Item($i)
                $lvl = [int]$it.ErrorLevel
                if ($Level -eq 'Error' -and $lvl -ne 1) { continue }
                if ($Level -eq 'Warning' -and $lvl -ne 2) { continue }
                $name = switch ($lvl) { 1 { 'error' } 2 { 'warning' } default { 'message' } }
                $found += [pscustomobject]@{ level = $name; file = [string]$it.FileName; line = [int]$it.Line; project = [string]$it.Project; message = Limit-Text ([string]$it.Description) 400 }
                if ($found.Count -ge $Top) { break }
            }
            Write-Json ([pscustomobject]@{ ok = $true; totalInList = $total; shown = $found.Count; items = $found; note = 'La Lista de errores refleja el ultimo build/analisis de VS; puede estar desactualizada.' })
        }
        'Processes' {
            $found = @()
            foreach ($p in $dbg.LocalProcesses) {
                $nm = [string]$p.Name
                if ($Filter -and $nm -notlike "*$Filter*") { continue }
                $found += [pscustomobject]@{ pid = [int]$p.ProcessID; name = $nm }
                if ($found.Count -ge $Top) { break }
            }
            Write-Json ([pscustomobject]@{ ok = $true; count = $found.Count; processes = $found })
        }
    }
}
