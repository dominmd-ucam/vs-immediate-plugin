# vs-elsa.ps1 - Sondeo del contexto de ejecucion de Elsa 3 en el punto de pausa actual (solo lectura).
# Evalua de una vez los campos habituales de ActivityExecutionContext y WorkflowExecutionContext,
# y separa los que existen (con su valor) de los que no existen en tu version (para descubrir nombres reales).
#
#   -Root context          expresion del contexto (por defecto "context"): dentro de ExecuteAsync(ActivityExecutionContext context)
#   -Kind Auto|Activity|Workflow   Auto lo detecta por el tipo de la expresion
#   -Extra "expr1,,expr2"  expresiones adicionales que evaluar tal cual (separadas por ,,)
#
# Solo lee propiedades y colecciones por su ruta; no llama a metodos del motor de workflows.
param(
    [string]$Root = 'context',
    [ValidateSet('Auto', 'Activity', 'Workflow')]
    [string]$Kind = 'Auto',
    [string]$Extra = '',
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

# Rutas relativas a ActivityExecutionContext.
$ActivityPaths = @(
    'Id',
    'Status',
    'Activity.Id',
    'Activity.Type',
    'Activity.Name',
    'Activity.Version',
    'ParentActivityExecutionContext.Activity.Type',
    'ParentActivityExecutionContext.Activity.Id'
)

# Rutas relativas a WorkflowExecutionContext.
$WorkflowPaths = @(
    'Id',
    'CorrelationId',
    'Status',
    'SubStatus',
    'Workflow.Identity.DefinitionId',
    'Workflow.Identity.Id',
    'Workflow.Identity.Version',
    'Workflow.WorkflowMetadata.Name',
    'ParentWorkflowInstanceId',
    'TriggerActivityId',
    'Bookmarks.Count',
    'Incidents.Count',
    'ActivityExecutionContexts.Count',
    'ExecutionLog.Count',
    'Input.Count',
    'Properties.Count'
)

function Test-Valid {
    param($Dbg, [string]$Expr)
    return (Eval-Value $Dbg $Expr)
}

Invoke-Main {
    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger

    $r = Try-Get { $dbg.GetExpression($Root, $false, 3000) }
    if (-not $r -or -not $r.IsValidValue) {
        throw ("La expresion '$Root' no es valida en este punto. Usa -Root con el nombre real del contexto (por ejemplo el parametro de ExecuteAsync) o para en un punto donde exista.")
    }
    $rootType = [string]$r.Type

    $kind = $Kind
    if ($kind -eq 'Auto') {
        if ($rootType -match 'ActivityExecutionContext') { $kind = 'Activity' }
        elseif ($rootType -match 'WorkflowExecutionContext') { $kind = 'Workflow' }
        elseif (Test-Valid $dbg "$Root.WorkflowExecutionContext.Id") { $kind = 'Activity' }
        elseif (Test-Valid $dbg "$Root.CorrelationId") { $kind = 'Workflow' }
        else { throw ("'$Root' es de tipo '$rootType', que no parece un contexto de Elsa. Usa vs-eval.ps1 -Expression $Root -Members para ver que tiene.") }
    }

    if ($kind -eq 'Activity') { $wfRoot = "$Root.WorkflowExecutionContext" } else { $wfRoot = $Root }

    $values = [ordered]@{}
    $missing = @()

    if ($kind -eq 'Activity') {
        foreach ($p in $ActivityPaths) {
            $v = Eval-Value $dbg "$Root.$p"
            if ($null -ne $v) { $values["activity.$p"] = Limit-Text (Unquote-Text $v) 200 } else { $missing += "activity.$p" }
        }
    }
    foreach ($p in $WorkflowPaths) {
        $v = Eval-Value $dbg "$wfRoot.$p"
        if ($null -ne $v) { $values["workflow.$p"] = Limit-Text (Unquote-Text $v) 200 } else { $missing += "workflow.$p" }
    }

    # Detalle de incidentes (fallos capturados por el motor) y bookmarks pendientes, si los hay.
    $incidentCount = 0
    if ($values.Contains('workflow.Incidents.Count')) { [void][int]::TryParse([string]$values['workflow.Incidents.Count'], [ref]$incidentCount) }
    $incidents = @()
    for ($i = 0; $i -lt [Math]::Min($incidentCount, 3); $i++) {
        $row = [ordered]@{ index = $i }
        foreach ($f in 'ActivityId', 'ActivityType', 'Message', 'Exception.Type', 'Exception.Message') {
            $v = Eval-Value $dbg "$wfRoot.Incidents[$i].$f"
            if ($null -ne $v) { $row[$f] = Limit-Text (Unquote-Text $v) 300 }
        }
        $incidents += [pscustomobject]$row
    }

    $bookmarkCount = 0
    if ($values.Contains('workflow.Bookmarks.Count')) { [void][int]::TryParse([string]$values['workflow.Bookmarks.Count'], [ref]$bookmarkCount) }
    $bookmarks = @()
    for ($i = 0; $i -lt [Math]::Min($bookmarkCount, 5); $i++) {
        $row = [ordered]@{ index = $i }
        foreach ($f in 'Name', 'Hash', 'ActivityNodeId') {
            $v = Eval-Value $dbg "$wfRoot.Bookmarks[$i].$f"
            if ($null -ne $v) { $row[$f] = Limit-Text (Unquote-Text $v) 200 }
        }
        $bookmarks += [pscustomobject]$row
    }

    $extraValues = [ordered]@{}
    foreach ($e in ($Extra -split ',,')) {
        $e = $e.Trim()
        if (-not $e) { continue }
        $v = Eval-Value $dbg $e
        if ($null -ne $v) { $extraValues[$e] = Limit-Text (Unquote-Text $v) 300 } else { $extraValues[$e] = '(no valida en este contexto)' }
    }

    $res = [ordered]@{
        ok          = $true
        root        = $Root
        rootType    = $rootType
        kind        = $kind
        values      = [pscustomobject]$values
        incidents   = $incidents
        bookmarks   = $bookmarks
        unavailable = $missing
        hint        = 'Lo que aparece en "unavailable" no existe con ese nombre en tu version o no es accesible desde este punto. Para descubrir los nombres reales: vs-eval.ps1 -Expression <objeto> -Members -Depth 2.'
    }
    if ($extraValues.Count -gt 0) { $res.extra = [pscustomobject]$extraValues }
    Write-Json ([pscustomobject]$res)
}
