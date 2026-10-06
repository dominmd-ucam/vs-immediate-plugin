# vs-eval.ps1 - Evalua una expresion (o ejecuta una sentencia) en el depurador de Visual Studio.
# Requiere que el depurador este en pausa (break mode).
#
# Ejemplos:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -Expression "pedido.Lineas.Count"
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -Expression "cliente" -Members
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -Expression 'lista.Where(p => p.Id == ~q~648000~q~).Count()'   (~q~ = comilla doble)
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -Expression "context.Id" -Frame 2   (evalua en el frame 2 de la pila; ver vs-state -What Stack)
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-eval.ps1 -ExpressionFile expr.txt   (ultimo recurso)
param(
    [string]$Expression,
    [string]$ExpressionFile,
    [switch]$Execute,      # ejecuta como sentencia (ExecuteStatement) en vez de evaluar
    [switch]$Members,      # incluye los miembros del resultado
    [ValidateRange(1, 3)]
    [int]$Depth = 1,       # con -Members: niveles a explorar (1 = solo primer nivel; maximo 3)
    [switch]$Private,      # con -Members: incluye tambien los miembros no publicos
    [int]$TimeoutMs = 5000,
    [ValidateRange(0, 500)]
    [int]$Frame = 0,       # evalua en el frame n de la pila (numeracion de vs-state -What Stack: 1 = superior); 0 = el seleccionado
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

# Tipos simples que no se expanden al explorar en profundidad.
$script:SimpleType = '^(int|uint|long|ulong|short|ushort|byte|sbyte|bool|char|string|double|float|decimal|object|System\.(Int|UInt|String|Boolean|Guid|DateTime|TimeSpan|Decimal|Double|Single|Byte)\w*)\b'

# Recorre los miembros hasta $Depth niveles (maximo $Max elementos en total).
# Los grupos del depurador ("Non-Public members", "Raw View"...) solo se expanden con -Private.
function Get-MemberTree {
    param($Members, [int]$Depth, [string]$Prefix, [ref]$Count, [int]$Max, [bool]$IncludePrivate)
    $items = @()
    foreach ($m in $Members) {
        if ($Count.Value -ge $Max) { break }
        $name = [string]$m.Name
        if ($name -match '\s') {
            if ($IncludePrivate) { $items += Get-MemberTree $m.DataMembers $Depth $Prefix $Count $Max $IncludePrivate }
            continue
        }
        $Count.Value++
        $type = [string]$m.Type
        $value = [string]$m.Value
        $items += [pscustomobject]@{ name = ($Prefix + $name); type = $type; value = (Limit-Text $value 300) }
        if ($Depth -gt 1 -and $value -ne 'null' -and $type -notmatch $script:SimpleType) {
            $kids = $null
            try { $kids = $m.DataMembers } catch {}
            if ($kids) { $items += Get-MemberTree $kids ($Depth - 1) ($Prefix + $name + '.') $Count $Max $IncludePrivate }
        }
    }
    return $items
}

Invoke-Main {
    if ($ExpressionFile) {
        $Expression = (Get-Content -LiteralPath $ExpressionFile -Raw -Encoding UTF8).Trim()
    }
    else {
        $Expression = Convert-QuoteEscapes $Expression
    }
    if (-not $Expression) { throw 'Falta -Expression o -ExpressionFile.' }

    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger
    Enter-Frame $dbg $Frame

    if ($Execute) {
        # ExecuteStatement no informa de errores (devuelve sin excepcion aunque no haya hecho nada),
        # asi que se ejecuta como expresion con efectos (asignaciones, llamadas void) y se comprueba el resultado.
        $r = Invoke-Com { $dbg.GetExpression($Expression, $false, $TimeoutMs) }
        if (-not [bool]$r.IsValidValue) {
            throw ("No se ejecuto: el depurador rechazo la sentencia. Mensaje: " + (Limit-Text ([string]$r.Value) 300) + " (no se admiten declaraciones de variables ni variables del depurador como `$x; usa asignaciones a campos u objetos vivos, o una sola expresion).")
        }
        Write-History 'execute' $Expression $true ([string]$r.Value)
        $res = [ordered]@{ ok = $true; executed = $Expression; paste = $Expression; type = [string]$r.Type; value = (Limit-Text ([string]$r.Value)); verified = $true; context = (Get-EvalContext $dbg) }
        if ($Frame -gt 0) { $res.frame = $Frame }
        Write-Json ([pscustomobject]$res)
        return
    }

    $r = Invoke-Com { $dbg.GetExpression($Expression, $false, $TimeoutMs) }
    $valid = [bool]$r.IsValidValue
    Write-History 'eval' $Expression $valid ([string]$r.Value)
    $out = [ordered]@{
        ok         = $valid
        expression = $Expression
        paste      = ('? ' + $Expression)
        context    = (Get-EvalContext $dbg)
        valid      = $valid
        type       = [string]$r.Type
        value      = Limit-Text ([string]$r.Value)
    }
    if ($Frame -gt 0) { $out.frame = $Frame }
    if ($ExpressionFile) { $out.tip = 'El fichero es el ultimo recurso. Primera opcion siempre: -Expression con ~q~ en lugar de CADA comilla doble (p.ej. StartsWith(~q~648000~q~)), sin ninguna comilla doble real dentro, y el argumento entre comillas simples.' }
    if (-not $valid -and $Expression -match "'") { $out.hint = 'La expresion lleva comillas simples: si querias comillas dobles de C#, escribe ~q~ en su lugar (p.ej. StartsWith(~q~648000~q~)); las comillas se pierden o cambian al pasar por la linea de comandos.' }
    if (-not $valid) { $out.error = 'La expresion no se pudo evaluar: ' + (Limit-Text ([string]$r.Value) 300) }
    if (-not $valid) { $out.note = 'La expresion no es valida en este contexto; "value" contiene el mensaje del depurador.' }

    if ($Members -and $valid) {
        $total = 0
        try { $total = [int]$r.DataMembers.Count } catch {}
        $max = 50
        if ($Depth -gt 1) { $max = 150 }
        $count = 0
        $out.members = @(Get-MemberTree $r.DataMembers $Depth '' ([ref]$count) $max ([bool]$Private))
        $out.membersTotalTopLevel = $total
        if ($count -ge $max) { $out.note = "Lista recortada a $max elementos; afina la expresion o usa -Depth menor." }
    }
    Write-Json ([pscustomobject]$out)
}
