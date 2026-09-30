# vs-common.ps1
# Funciones compartidas por los scripts vs-*.ps1. Se carga con: . "$PSScriptRoot\vs-common.ps1"
# IMPORTANTE: mantener este fichero en ASCII (Windows PowerShell 5.1 lo lee como ANSI si no tiene BOM).

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Acceso a la Running Object Table (ROT) para localizar instancias de VS ---------------------
if (-not ('VsRot' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class VsRot
{
    [DllImport("ole32.dll")]
    private static extern int GetRunningObjectTable(int reserved, out IRunningObjectTable rot);

    [DllImport("ole32.dll")]
    private static extern int CreateBindCtx(int reserved, out IBindCtx ctx);

    public class Entry
    {
        public string Name;
        public object Instance;
    }

    public static List<Entry> FindDte()
    {
        List<Entry> result = new List<Entry>();
        IRunningObjectTable rot;
        IEnumMoniker en;
        IBindCtx ctx;
        GetRunningObjectTable(0, out rot);
        CreateBindCtx(0, out ctx);
        rot.EnumRunning(out en);
        en.Reset();
        IMoniker[] m = new IMoniker[1];
        while (en.Next(1, m, IntPtr.Zero) == 0)
        {
            string name;
            try { m[0].GetDisplayName(ctx, null, out name); }
            catch { continue; }
            if (name != null && name.StartsWith("!VisualStudio.DTE.", StringComparison.OrdinalIgnoreCase))
            {
                object obj;
                try { rot.GetObject(m[0], out obj); }
                catch { continue; }
                Entry e = new Entry();
                e.Name = name;
                e.Instance = obj;
                result.Add(e);
            }
        }
        return result;
    }
}
"@
}

# --- Utilidades ---------------------------------------------------------------------------------
function Write-Json {
    param($Object)
    $Object | ConvertTo-Json -Depth 6
}

# Historial de expresiones evaluadas (una linea JSON por entrada). Nunca debe romper la consulta.
function Get-HistoryPath {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = [System.IO.Path]::GetTempPath() }
    return (Join-Path (Join-Path $base 'vs-immediate') 'history.jsonl')
}

function Write-History {
    param([string]$Kind, [string]$Expression, $Valid = $null, [string]$Value = '')
    try {
        if (-not $Expression) { return }
        $path = Get-HistoryPath
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $entry = [ordered]@{ time = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'); kind = $Kind; expression = $Expression }
        if ($null -ne $Valid) { $entry.valid = [bool]$Valid }
        if ($Value) { $entry.value = (Limit-Text $Value 80) }
        $line = ($entry | ConvertTo-Json -Compress)
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($path, $line + "`n", $utf8)
        # Recorte: si pasa de ~1 MB se queda con las ultimas 500 lineas.
        if ((Get-Item -LiteralPath $path).Length -gt 1048576) {
            $keep = @(Get-Content -LiteralPath $path -Encoding UTF8 | Select-Object -Last 500)
            [System.IO.File]::WriteAllText($path, (($keep -join "`n") + "`n"), $utf8)
        }
    }
    catch { }
}

# Contexto en el que se evalua una expresion: funcion del frame seleccionado e hilo actual.
function Get-EvalContext {
    param($Dbg)
    $fn = $null
    $frame = Try-Get { $Dbg.CurrentStackFrame }
    if ($frame) { $fn = [string]$frame.FunctionName }
    $tid = Try-Get { [int]$Dbg.CurrentThread.ID }
    return [pscustomobject]@{ function = $fn; threadId = $tid }
}

function Invoke-Main {
    param([scriptblock]$Body)
    try {
        & $Body
    }
    catch {
        Write-Json ([pscustomobject]@{ ok = $false; error = $_.Exception.Message })
        exit 1
    }
}

# Reintenta cuando VS esta ocupado (RPC_E_CALL_REJECTED / RPC_E_SERVERCALL_RETRYLATER).
function Invoke-Com {
    param([scriptblock]$Block, [int]$Retries = 6)
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            return (& $Block)
        }
        catch {
            $hr = 0
            $ex = $_.Exception
            if ($ex -is [System.Runtime.InteropServices.COMException]) { $hr = $ex.ErrorCode }
            elseif ($ex.InnerException -is [System.Runtime.InteropServices.COMException]) { $hr = $ex.InnerException.ErrorCode }
            if (($hr -eq -2147418111 -or $hr -eq -2147417846) -and $i -lt $Retries) {
                Start-Sleep -Milliseconds 400
                continue
            }
            throw
        }
    }
}

function Try-Get {
    param([scriptblock]$Block)
    try { return (Invoke-Com $Block) } catch { return $null }
}

function Get-ModeName {
    param($Mode)
    switch ([int]$Mode) {
        1 { 'design' }
        2 { 'break' }
        3 { 'run' }
        default { 'unknown' }
    }
}

function Get-VsInstances {
    foreach ($e in [VsRot]::FindDte()) {
        $dte = $e.Instance
        $sol = ''
        $mode = 'unknown'
        $procId = $null
        try { $sol = [string](Invoke-Com { $dte.Solution.FullName }) } catch {}
        try { $mode = Get-ModeName (Invoke-Com { $dte.Debugger.CurrentMode }) } catch {}
        if ($e.Name -match ':(\d+)$') { $procId = [int]$Matches[1] }
        [pscustomobject]@{ Name = $e.Name; ProcessId = $procId; Solution = $sol; Mode = $mode; Dte = $dte }
    }
}

function Format-VsList {
    param($Instances)
    (@($Instances) | ForEach-Object { "[pid $($_.ProcessId)] $($_.Solution) ($($_.Mode))" }) -join '; '
}

# Elige la instancia de VS: por -ProcessId, por -Solution (texto contenido en la ruta) o la unica abierta.
function Get-Vs {
    param([string]$Solution, [int]$ProcessId = 0)
    if (-not $Solution -and $env:VS_IMMEDIATE_SOLUTION) { $Solution = $env:VS_IMMEDIATE_SOLUTION }
    $all = @(Get-VsInstances)
    if ($all.Count -eq 0) {
        throw 'No se encuentra ninguna instancia de Visual Studio. Comprueba que esta abierto y que la terminal se ejecuta con el mismo nivel de permisos (si VS esta como administrador, la terminal tambien).'
    }
    $sel = $all
    if ($ProcessId -gt 0) { $sel = @($all | Where-Object { $_.ProcessId -eq $ProcessId }) }
    elseif ($Solution) { $sel = @($all | Where-Object { $_.Solution -like "*$Solution*" }) }
    if ($sel.Count -eq 0) { throw ('Ninguna instancia coincide con el filtro. Instancias abiertas: ' + (Format-VsList $all)) }
    if ($sel.Count -gt 1) { throw ('Hay varias instancias de Visual Studio; usa -Solution <texto> o -ProcessId <pid>. Instancias: ' + (Format-VsList $sel)) }
    return $sel[0]
}

function Assert-BreakMode {
    param($Vs)
    $m = Invoke-Com { $Vs.Dte.Debugger.CurrentMode }
    if ([int]$m -ne 2) {
        throw ('El depurador no esta en pausa (modo actual: ' + (Get-ModeName $m) + '). Hace falta un breakpoint alcanzado o una pausa.')
    }
}

function Limit-Text {
    param([string]$Text, [int]$Max = 8000)
    if ($Text -and $Text.Length -gt $Max) { return $Text.Substring(0, $Max) + '...[truncado]' }
    return $Text
}

# --- Esperas y resumen tras acciones de control -------------------------------------------------
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

# Posicion en el codigo fuente. DTE no expone la linea de la flecha amarilla: se lee el caret del editor,
# que puede no coincidir si el usuario ha movido el cursor. Con -Sync se ejecuta antes Debug.ShowNextStatement
# (mueve el caret a la sentencia actual, como Alt+Num*).
function Get-SourcePosition {
    param($Vs, [bool]$Sync = $false)
    if ($Sync) { Try-Get { $Vs.Dte.ExecuteCommand('Debug.ShowNextStatement') } | Out-Null }
    $doc = Try-Get { $Vs.Dte.ActiveDocument }
    if (-not $doc) { return $null }
    $pos = [ordered]@{ file = [string]$doc.FullName; line = [int]$doc.Selection.CurrentLine }
    if ($Sync) { $pos.lineSource = 'sentencia actual (Debug.ShowNextStatement)' }
    else { $pos.lineSource = 'caret del editor: puede no coincidir con la flecha amarilla; usa -SyncCaret en vs-state para sincronizarlo' }
    return [pscustomobject]$pos
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
        $sp = Get-SourcePosition $Vs $false
        if ($sp) { $res.sourcePosition = $sp }
    }
    return [pscustomobject]$res
}

# --- Evaluacion de expresiones ------------------------------------------------------------------
# Devuelve el valor (texto) de una expresion, o $null si no es valida en este contexto.
function Eval-Value {
    param($Dbg, [string]$Expr, [int]$TimeoutMs = 3000)
    try {
        $r = Invoke-Com { $Dbg.GetExpression($Expr, $false, $TimeoutMs) }
        if ($r.IsValidValue) { return [string]$r.Value }
    } catch {}
    return $null
}

# Quita las comillas externas de un valor de tipo string tal como lo devuelve el depurador.
function Unquote-Text {
    param([string]$Text)
    if ($null -eq $Text) { return $null }
    $t = $Text.Trim()
    if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
    return $t
}
