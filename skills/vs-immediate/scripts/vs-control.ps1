# vs-control.ps1 - Controla el depurador y la solucion en Visual Studio.
#   Build             compila la solucion (solo en modo diseno)
#   Start             inicia la depuracion del proyecto de inicio (F5)
#   Continue          continua la ejecucion (F5 en pausa)
#   StepOver/StepInto/StepOut
#   Pause             pausa la ejecucion
#   Stop              detiene la depuracion
#   AddBreakpoint     -File <ruta o nombre> -Line <n> [-Condition <expr>]
#   RemoveBreakpoint  -File <ruta o nombre> -Line <n>
#   ClearBreakpoints  elimina todos los breakpoints
#   Command           -Command <Nombre.Comando.De.VS>  (DTE.ExecuteCommand)
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Build', 'Start', 'Continue', 'StepOver', 'StepInto', 'StepOut', 'Pause', 'Stop',
                 'AddBreakpoint', 'RemoveBreakpoint', 'ClearBreakpoints', 'Command')]
    [string]$Action,
    [string]$File,
    [int]$Line = 0,
    [string]$Condition = '',
    [string]$Command,
    [int]$WaitSeconds = 30,   # espera maxima a que la ejecucion vuelva a pausa/termine
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

# Espera a que el modo deje de ser "run". Devuelve el modo final (3 = sigue ejecutando).
function Wait-NotRunning {
    param($Dbg, [int]$Seconds)
    Start-Sleep -Milliseconds 700
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        $m = [int](Invoke-Com { $Dbg.CurrentMode })
        if ($m -ne 3) { return $m }
        Start-Sleep -Milliseconds 300
    }
    return 3
}

function Wait-Mode {
    param($Dbg, [int]$Target, [int]$Seconds)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        $m = [int](Invoke-Com { $Dbg.CurrentMode })
        if ($m -eq $Target) { return $m }
        Start-Sleep -Milliseconds 300
    }
    return [int](Invoke-Com { $Dbg.CurrentMode })
}

function Get-Brief {
    param($Vs, [string]$Action, [bool]$TimedOut = $false)
    $dbg = $Vs.Dte.Debugger
    $mode = [int](Invoke-Com { $dbg.CurrentMode })
    $res = [ordered]@{ ok = $true; action = $Action; debuggerMode = Get-ModeName $mode }
    if ($TimedOut) { $res.note = 'La ejecucion sigue en marcha (no ha vuelto a pausa dentro del tiempo de espera).' }
    if ($mode -eq 2) {
        $frame = Try-Get { $dbg.CurrentStackFrame }
        if ($frame) { $res.function = [string]$frame.FunctionName }
        $doc = Try-Get { $Vs.Dte.ActiveDocument }
        if ($doc) { $res.sourcePosition = [pscustomobject]@{ file = [string]$doc.FullName; line = [int]$doc.Selection.CurrentLine } }
    }
    return [pscustomobject]$res
}

# Acepta ruta completa o solo nombre de fichero (se busca dentro de la carpeta de la solucion).
function Resolve-SourceFile {
    param($Vs, [string]$Name)
    if (-not $Name) { throw 'Falta -File.' }
    if ([System.IO.Path]::IsPathRooted($Name)) { return $Name }
    $root = Split-Path -Parent $Vs.Solution
    if (-not $root) { throw 'No hay solucion abierta; indica la ruta completa en -File.' }
    $found = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter $Name -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
    if ($found.Count -eq 0) { throw "No se encuentra '$Name' dentro de $root." }
    if ($found.Count -gt 1) { throw ("Hay varios ficheros '$Name'; indica la ruta completa. Candidatos: " + (($found | Select-Object -First 5 | ForEach-Object { $_.FullName }) -join '; ')) }
    return $found[0].FullName
}

Invoke-Main {
    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    $dte = $vs.Dte
    $dbg = $dte.Debugger
    $mode = [int](Invoke-Com { $dbg.CurrentMode })

    switch ($Action) {
        'Build' {
            if ($mode -ne 1) { throw 'Solo se puede compilar en modo diseno (detiene la depuracion primero).' }
            $sb = $dte.Solution.SolutionBuild
            Invoke-Com { $sb.Build($true) } | Out-Null
            $failed = [int](Invoke-Com { $sb.LastBuildInfo })
            $errors = @()
            try {
                $items = $dte.ToolWindows.ErrorList.ErrorItems
                $n = 0
                for ($i = 1; $i -le $items.Count; $i++) {
                    $it = $items.Item($i)
                    if ([int]$it.ErrorLevel -eq 1) {
                        $n++
                        if ($n -gt 30) { break }
                        $errors += [pscustomobject]@{ file = [string]$it.FileName; line = [int]$it.Line; message = [string]$it.Description }
                    }
                }
            } catch {}
            Write-Json ([pscustomobject]@{ ok = ($failed -eq 0); action = 'Build'; failedProjects = $failed; errors = $errors })
        }
        'Start' {
            if ($mode -ne 1) { throw 'Ya hay una sesion de depuracion en curso.' }
            Invoke-Com { $dbg.Go($false) } | Out-Null
            $m = Wait-NotRunning $dbg $WaitSeconds
            Write-Json (Get-Brief $vs 'Start' ($m -eq 3))
        }
        'Continue' {
            Assert-BreakMode $vs
            Invoke-Com { $dbg.Go($false) } | Out-Null
            $m = Wait-NotRunning $dbg $WaitSeconds
            Write-Json (Get-Brief $vs 'Continue' ($m -eq 3))
        }
        'StepOver' {
            Assert-BreakMode $vs
            Invoke-Com { $dbg.StepOver($false) } | Out-Null
            $m = Wait-NotRunning $dbg $WaitSeconds
            Write-Json (Get-Brief $vs 'StepOver' ($m -eq 3))
        }
        'StepInto' {
            Assert-BreakMode $vs
            Invoke-Com { $dbg.StepInto($false) } | Out-Null
            $m = Wait-NotRunning $dbg $WaitSeconds
            Write-Json (Get-Brief $vs 'StepInto' ($m -eq 3))
        }
        'StepOut' {
            Assert-BreakMode $vs
            Invoke-Com { $dbg.StepOut($false) } | Out-Null
            $m = Wait-NotRunning $dbg $WaitSeconds
            Write-Json (Get-Brief $vs 'StepOut' ($m -eq 3))
        }
        'Pause' {
            if ($mode -ne 3) { throw 'La aplicacion no esta en ejecucion.' }
            Invoke-Com { $dbg.Break($false) } | Out-Null
            $m = Wait-Mode $dbg 2 $WaitSeconds
            Write-Json (Get-Brief $vs 'Pause' ($m -ne 2))
        }
        'Stop' {
            if ($mode -eq 1) { throw 'No hay sesion de depuracion activa.' }
            Invoke-Com { $dbg.Stop($false) } | Out-Null
            $m = Wait-Mode $dbg 1 $WaitSeconds
            Write-Json (Get-Brief $vs 'Stop' ($m -ne 1))
        }
        'AddBreakpoint' {
            if ($Line -lt 1) { throw 'Falta -Line (numero de linea, empezando en 1).' }
            $path = Resolve-SourceFile $vs $File
            Invoke-Com { $dbg.Breakpoints.Add('', $path, $Line, 1, $Condition, 1, '', '', 1, '', 0, 1) } | Out-Null
            Write-Json ([pscustomobject]@{ ok = $true; action = 'AddBreakpoint'; file = $path; line = $Line; condition = $Condition })
        }
        'RemoveBreakpoint' {
            if ($Line -lt 1) { throw 'Falta -Line.' }
            $path = Resolve-SourceFile $vs $File
            $targets = @()
            foreach ($b in $dbg.Breakpoints) {
                if (([string]$b.File) -ieq $path -and [int]$b.FileLine -eq $Line) { $targets += $b }
            }
            foreach ($b in $targets) { $b.Delete() }
            Write-Json ([pscustomobject]@{ ok = $true; action = 'RemoveBreakpoint'; file = $path; line = $Line; removed = $targets.Count })
        }
        'ClearBreakpoints' {
            $targets = @()
            foreach ($b in $dbg.Breakpoints) { $targets += $b }
            foreach ($b in $targets) { $b.Delete() }
            Write-Json ([pscustomobject]@{ ok = $true; action = 'ClearBreakpoints'; removed = $targets.Count })
        }
        'Command' {
            if (-not $Command) { throw 'Falta -Command.' }
            Invoke-Com { $dte.ExecuteCommand($Command) } | Out-Null
            Write-Json ([pscustomobject]@{ ok = $true; action = 'Command'; command = $Command })
        }
    }
}
