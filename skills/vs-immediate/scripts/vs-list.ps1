# vs-list.ps1 - Lista las instancias de Visual Studio abiertas (sirve tambien como prueba de conexion).
. "$PSScriptRoot\vs-common.ps1"

Invoke-Main {
    $items = @(Get-VsInstances | ForEach-Object {
        [pscustomobject]@{
            moniker      = $_.Name
            processId    = $_.ProcessId
            solution     = $_.Solution
            debuggerMode = $_.Mode
        }
    })
    Write-Json ([pscustomobject]@{ ok = $true; count = $items.Count; instances = $items })
}
