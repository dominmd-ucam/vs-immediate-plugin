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
