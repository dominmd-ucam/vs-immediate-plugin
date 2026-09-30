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
#   AddTracepoint     -File <ruta o nombre> -Line <n> -Message "texto {expr}" [-Condition <expr>]
#                     (breakpoint que escribe un mensaje en la ventana Output y NO para la ejecucion)
#   Attach            -TargetName <texto> | -TargetPid <n>   se engancha a un proceso ya en marcha
#   Detach            se desengancha de todos los procesos sin cerrarlos
#   Command           -Command <Nombre.Comando.De.VS>  (DTE.ExecuteCommand)
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Build', 'Start', 'Continue', 'StepOver', 'StepInto', 'StepOut', 'Pause', 'Stop',
                 'AddBreakpoint', 'RemoveBreakpoint', 'ClearBreakpoints', 'AddTracepoint',
                 'Attach', 'Detach', 'Command')]
    [string]$Action,
    [string]$File,
    [int]$Line = 0,
    [string]$Condition = '',
    [string]$Message = '',
    [string]$TargetName = '',
    [int]$TargetPid = 0,
    [string]$Command,
    [int]$WaitSeconds = 30,   # espera maxima a que la ejecucion vuelva a pausa/termine
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"


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
        'AddTracepoint' {
            if ($Line -lt 1) { throw 'Falta -Line.' }
            if (-not $Message) { throw 'Falta -Message (puedes usar {expresion} para interpolar valores).' }
            $path = Resolve-SourceFile $vs $File
            Invoke-Com { $dbg.Breakpoints.Add('', $path, $Line, 1, $Condition, 1, '', '', 1, '', 0, 1) } | Out-Null
            $bp = $null
            foreach ($b in $dbg.Breakpoints) {
                if (([string]$b.File) -ieq $path -and [int]$b.FileLine -eq $Line) { $bp = $b }
            }
            if (-not $bp) { throw 'No se pudo localizar el breakpoint recien creado.' }
            try {
                $bp.Message = $Message
                $bp.BreakWhenHit = $false
            }
            catch {
                try { $bp.Delete() } catch {}
                throw ('Esta version de Visual Studio no permitio configurar el tracepoint por DTE (' + $_.Exception.Message + '). Se elimino el breakpoint creado.')
            }
            Write-Json ([pscustomobject]@{ ok = $true; action = 'AddTracepoint'; file = $path; line = $Line; message = $Message; condition = $Condition; note = 'Los mensajes aparecen en la ventana Output (panel Debug).' })
        }
        'Attach' {
            if ($TargetPid -le 0 -and -not $TargetName) { throw 'Indica -TargetName <texto> o -TargetPid <n>.' }
            if ($mode -ne 1) { throw 'Ya hay una sesion de depuracion en curso; detenla o desenganchate primero.' }
            $cands = @()
            foreach ($p in $dbg.LocalProcesses) {
                if ($TargetPid -gt 0) { if ([int]$p.ProcessID -eq $TargetPid) { $cands += $p } }
                elseif (([string]$p.Name) -like "*$TargetName*") { $cands += $p }
            }
            if ($cands.Count -eq 0) { throw 'Ningun proceso coincide. Usa vs-state.ps1 -What Processes -Filter <texto> para verlos (si VS no es administrador, no ve procesos elevados).' }
            if ($cands.Count -gt 1) { throw ('Varios procesos coinciden; usa -TargetPid. Candidatos: ' + (($cands | Select-Object -First 8 | ForEach-Object { '[' + $_.ProcessID + '] ' + $_.Name }) -join '; ')) }
            $target = $cands[0]
            $targetLabel = '[' + [string]$target.ProcessID + '] ' + [string]$target.Name
            Invoke-Com { $target.Attach() } | Out-Null
            Wait-Mode $dbg 3 $WaitSeconds | Out-Null
            $brief = Get-Brief $vs 'Attach' $false
            $brief | Add-Member -NotePropertyName attachedTo -NotePropertyValue $targetLabel
            Write-Json $brief
        }
        'Detach' {
            if ($mode -eq 1) { throw 'No hay sesion de depuracion activa.' }
            Invoke-Com { $dbg.DetachAll() } | Out-Null
            $m = Wait-Mode $dbg 1 $WaitSeconds
            Write-Json (Get-Brief $vs 'Detach' ($m -ne 1))
        }
        'Command' {
            if (-not $Command) { throw 'Falta -Command.' }
            Invoke-Com { $dte.ExecuteCommand($Command) } | Out-Null
            Write-Json ([pscustomobject]@{ ok = $true; action = 'Command'; command = $Command })
        }
    }
}
