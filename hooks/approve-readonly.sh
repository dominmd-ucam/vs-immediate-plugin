#!/usr/bin/env bash
# approve-readonly.sh - Hook PreToolUse del plugin vs-immediate para WSL / Linux.
# Equivale a approve-readonly.ps1: aprueba sin preguntar las llamadas de SOLO LECTURA al puente vs.sh.
# Todo lo demas (control de ejecucion, breakpoints, -Execute, cambios de hilo...) sigue pidiendo permiso.
# Si algo no encaja con seguridad, el hook no dice nada (exit 0) y Claude Code pregunta como siempre.
# Necesita jq o python3 para leer el JSON de entrada; sin ninguno de los dos no aprueba nada.
# Mantener la misma logica que approve-readonly.ps1 (los casos de prueba son comunes).

raw="$(cat)"
cmd=""
if command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$raw" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  cmd="$(printf '%s' "$raw" | python3 -c 'import sys, json
try:
    print(json.load(sys.stdin).get("tool_input", {}).get("command", ""))
except Exception:
    pass' 2>/dev/null)"
fi
[ -n "$cmd" ] || exit 0

approve() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$1"
  exit 0
}

set -f

# Metodos que se consideran de solo lectura dentro de una expresion (lista cerrada, distingue mayusculas).
# Pueden ejecutar consultas de lectura (p. ej. un IQueryable de EF al hacer Count() o ToList()), pero no cambian datos.
ALLOWED_METHODS=" Where Select SelectMany Count LongCount Any All First FirstOrDefault Last LastOrDefault Single SingleOrDefault ElementAt ElementAtOrDefault Take Skip TakeWhile SkipWhile OrderBy OrderByDescending ThenBy ThenByDescending Distinct DistinctBy GroupBy Sum Min Max Average Contains ContainsKey ContainsValue Cast OfType ToList ToArray ToDictionary ToHashSet Zip Concat Union Intersect Except Join Split StartsWith EndsWith IndexOf LastIndexOf Substring ToUpper ToLower ToUpperInvariant ToLowerInvariant Trim TrimStart TrimEnd Equals CompareTo IsNullOrEmpty IsNullOrWhiteSpace ToString GetType GetHashCode GetValueOrDefault Format "

# Expresion "simple": sin llamadas a metodos (salvo GetType/ToString), sin asignaciones ni ++/--.
simple() {
  local t="$1"
  t="${t//'.GetType()'/}"
  t="${t//'.ToString()'/}"
  [[ "$t" == *"("* || "$t" == *")"* ]] && return 1
  t="${t//==/}"; t="${t//!=/}"; t="${t//<=/}"; t="${t//>=/}"
  [[ "$t" == *"="* ]] && return 1
  [[ "$t" == *"++"* || "$t" == *"--"* ]] && return 1
  return 0
}

# Expresion C# de solo lectura: solo caracteres de una lista blanca, sin asignaciones ni ++/--, sin "new", y cada
# llamada a metodo tiene que estar en la lista cerrada. Los literales de cadena se ignoran (son datos).
csharp_safe() {
  local s="${1//'~q~'/\"}" t m
  [[ "$s" == *'@"'* || "$s" == *'$"'* || "$s" == *'`'* || "$s" == *'$('* || "$s" == *'${'* ]] && return 1
  local lit='"([^"\\]|\\.)*"'
  while [[ "$s" =~ $lit ]]; do s="${s/"${BASH_REMATCH[0]}"/0}"; done
  [[ "$s" == *'"'* ]] && return 1
  local wl='^[]A-Za-z0-9_$.,()?:!=<>+*/%&|^[ -]*$'
  [[ "$s" =~ $wl ]] || return 1
  local kw='(^|[^A-Za-z0-9_])(new|await|ref|out|unsafe|stackalloc)([^A-Za-z0-9_]|$)'
  [[ "$s" =~ $kw ]] && return 1
  t="${s//==/}"; t="${t//!=/}"; t="${t//<=/}"; t="${t//>=/}"; t="${t//=>/}"
  [[ "$t" == *"="* ]] && return 1
  [[ "$s" == *"++"* || "$s" == *"--"* ]] && return 1
  local r1='[])][[:space:]]*\(' r2='[])A-Za-z0-9_][[:space:]]*![[:space:]]*\(' r3='[A-Za-z0-9_]>[[:space:]]*\('
  [[ "$s" =~ $r1 || "$s" =~ $r2 || "$s" =~ $r3 ]] && return 1
  local call='([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\('
  while [[ "$s" =~ $call ]]; do
    m="${BASH_REMATCH[1]}"
    [[ "$ALLOWED_METHODS" == *" $m "* ]] || return 1
    s="${s#*"${BASH_REMATCH[0]}"}"
  done
  return 0
}

# Separa los argumentos entre comillas simples (palabras completas) del resto. Las comillas simples son literales en
# bash y en PowerShell, asi que ahi dentro los simbolos ; & | < > no tienen efecto en la linea de comandos.
# Deja los segmentos en SEGS y el resto en OUTSIDE; falla si queda alguna comilla simple suelta o pegada a otro texto.
split_single_quoted() {
  SEGS=(); OUTSIDE="$1"
  local re="(^|[[:space:]])'([^']*)'([[:space:]]|\$)"
  while [[ "$OUTSIDE" =~ $re ]]; do
    SEGS+=("${BASH_REMATCH[2]}")
    OUTSIDE="${OUTSIDE/"${BASH_REMATCH[0]}"/ }"
  done
  [[ "$OUTSIDE" == *"'"* ]] && return 1
  return 0
}

# PowerShell admite abreviar los nombres de parametro (-Exec, -ExpressionF, -Cl...): se detectan por prefijo.
has_flag() {  # $1 = texto, $2 = nombre completo en minusculas, $3 = longitud minima de la abreviatura
  local tok n full="$2"
  for tok in ${1//[\"\']/}; do
    [[ "$tok" == -* ]] || continue
    n="${tok#-}"; n="${n%%[:=]*}"; n="${n,,}"
    [ "${#n}" -ge "$3" ] && [[ "$full" == "$n"* ]] && return 0
  done
  return 1
}

word() { [[ "${1,,}" =~ (^|[^[:alnum:]])($2)([^[:alnum:]]|$) ]]; }

# Una sola linea.
nl=$'\n'; cr=$'\r'
[[ "$cmd" == *"$nl"* || "$cmd" == *"$cr"* ]] && exit 0

# Debe ser exactamente: bash "<ruta>/vs-immediate/scripts/vs.sh" vs-xxx [argumentos]
re='^[[:space:]]*(bash|sh)[[:space:]]+("([^"]*)"|([^"[:space:]]+))[[:space:]]+(vs-[a-z]+)(\.ps1)?([[:space:]].*)?$'
[[ "$cmd" =~ $re ]] || exit 0
path="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
name="${BASH_REMATCH[5]}"
rest="${BASH_REMATCH[7]}"
prefix="${cmd:0:$(( ${#cmd} - ${#rest} ))}"

# La ruta tiene que ser el vs.sh de este plugin o de una instalacion de skills del usuario.
path="${path/#\$HOME/$HOME}"
path="${path/#\~/$HOME}"
[[ "$path" == *".."* ]] && exit 0
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
case "$path" in
  "$root/skills/vs-immediate/scripts/vs.sh") ;;
  "$HOME/.agents/skills/vs-immediate/scripts/vs.sh") ;;
  "$HOME/.claude/skills/vs-immediate/scripts/vs.sh") ;;
  *) exit 0 ;;
esac

# Solo vs-eval, vs-types y vs-elsa admiten expresiones: sus argumentos entre comillas simples se analizan aparte.
SEGS=(); OUTSIDE="$rest"
case "$name" in
  vs-eval | vs-types | vs-elsa) split_single_quoted "$rest" || exit 0 ;;
esac

# Fuera de las comillas simples: sin encadenar comandos, redirecciones ni sustituciones.
scan="$prefix$OUTSIDE"
bad='[;&|<>`]'
[[ "$scan" =~ $bad ]] && exit 0
[[ "$scan" == *'$('* || "$scan" == *'${'* ]] && exit 0

expression_args() {
  simple "$OUTSIDE" || return 1
  local seg
  for seg in "${SEGS[@]}"; do csharp_safe "$seg" || return 1; done
  return 0
}

case "$name" in
  vs-list) approve "vs-immediate: listar instancias de Visual Studio (solo lectura)" ;;
  vs-state) approve "vs-immediate: consulta de estado (solo lectura)" ;;
  vs-history) has_flag "$rest" clear 1 || approve "vs-immediate: historial de expresiones (solo lectura)" ;;
  vs-threads) word "$rest" 'switch' || approve "vs-immediate: hilos (solo lectura)" ;;
  vs-exceptions) word "$rest" 'break|nobreak' || approve "vs-immediate: excepciones (solo lectura)" ;;
  vs-eval)
    has_flag "$rest" execute 3 && exit 0
    has_flag "$rest" expressionfile 11 && exit 0
    expression_args && approve "vs-immediate: evaluacion de expresion de solo lectura (lista cerrada de metodos, sin asignaciones)"
    ;;
  vs-types) expression_args && approve "vs-immediate: tipos declarados y reales (solo lectura)" ;;
  vs-elsa) expression_args && approve "vs-immediate: sondeo del contexto de Elsa (solo lectura)" ;;
esac

exit 0
