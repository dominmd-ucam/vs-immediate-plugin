# vs-types.ps1 - Tipo declarado frente a tipo real (en ejecucion) de variables e interfaces. Break mode.
# El depurador muestra las variables de tipo interfaz como "Ns.IFoo {Ns.Foo}": entre llaves va la clase real.
#   -This                          inspecciona los miembros (campos y propiedades, tambien privados) de "this"
#   -Expressions "a,,b"            inspecciona expresiones concretas (separadas por ,,)
#   -Filter texto                  con -This, solo los miembros cuyo nombre o tipo contengan el texto
# No llama a metodos de la aplicacion: solo lee lo que el depurador ya muestra.
param(
    [string]$Expressions,
    [switch]$This,
    [string]$Filter = '',
    [int]$Top = 40,
    [string]$Solution,
    [int]$ProcessId = 0
)

. "$PSScriptRoot\vs-common.ps1"

function Split-Type {
    param([string]$T)
    if ($T -match '^(.*?) \{(.*)\}$') { return @($Matches[1], $Matches[2]) }
    return @($T, '')
}

function ConvertTo-TypeItem {
    param($Name, $Type, $Value)
    $p = Split-Type ([string]$Type)
    return [pscustomobject]@{
        name         = [string]$Name
        declaredType = $p[0]
        runtimeType  = $(if ($p[1]) { $p[1] } else { $p[0] })
        sameAsDeclared = (-not $p[1])
        isNull       = ([string]$Value -eq 'null')
        value        = Limit-Text ([string]$Value) 200
    }
}

# Recorre los miembros; los grupos ("Non-Public members", "Miembros no publicos"...) se expanden un nivel.
function Get-MemberItems {
    param($Members, [string]$Filter, [int]$Max)
    $items = @()
    foreach ($m in $Members) {
        $name = [string]$m.Name
        if ($name -match '\s') {
            foreach ($inner in $m.DataMembers) {
                $item = ConvertTo-TypeItem $inner.Name $inner.Type $inner.Value
                if (-not $Filter -or $item.name -like "*$Filter*" -or $item.declaredType -like "*$Filter*" -or $item.runtimeType -like "*$Filter*") { $items += $item }
                if ($items.Count -ge $Max) { return $items }
            }
            continue
        }
        $item = ConvertTo-TypeItem $m.Name $m.Type $m.Value
        if (-not $Filter -or $item.name -like "*$Filter*" -or $item.declaredType -like "*$Filter*" -or $item.runtimeType -like "*$Filter*") { $items += $item }
        if ($items.Count -ge $Max) { return $items }
    }
    return $items
}

Invoke-Main {
    if (-not $This -and -not $Expressions) { throw 'Indica -This o -Expressions "a,,b".' }
    $vs = Get-Vs -Solution $Solution -ProcessId $ProcessId
    Assert-BreakMode $vs
    $dbg = $vs.Dte.Debugger
    $out = [ordered]@{ ok = $true }

    if ($This) {
        $r = Invoke-Com { $dbg.GetExpression('this', $false, 5000) }
        if (-not $r.IsValidValue) { throw 'No hay "this" en el frame actual (metodo estatico o sin contexto).' }
        $out.thisType = [string]$r.Type
        $out.members = @(Get-MemberItems $r.DataMembers $Filter $Top)
    }

    if ($Expressions) {
        $list = @()
        foreach ($e in ($Expressions -split ',,')) {
            $e = $e.Trim()
            if (-not $e) { continue }
            $r = Try-Get { $dbg.GetExpression($e, $false, 3000) }
            if ($r -and $r.IsValidValue) {
                $item = ConvertTo-TypeItem $e $r.Type $r.Value
            }
            else {
                $item = [pscustomobject]@{ name = $e; declaredType = ''; runtimeType = ''; isNull = $false; value = '(expresion no valida en este contexto)' }
            }
            $list += $item
        }
        $out.expressions = $list
    }
    Write-Json ([pscustomobject]$out)
}
