#!/usr/bin/env bash
# approve-readonly.sh - Hook PreToolUse del plugin vs-immediate para WSL / Linux.
# Equivale a approve-readonly.ps1: aprueba sin preguntar las llamadas de SOLO LECTURA al puente vs.sh.
# Todo lo demas (control de ejecucion, breakpoints, -Execute, cambios de hilo...) sigue pidiendo permiso.
# Si algo no encaja con seguridad, el hook no dice nada (exit 0) y Claude Code pregunta como siempre.
# Necesita jq o python3 para leer el JSON de entrada; sin ninguno de los dos no aprueba nada.

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
shopt -s nocasematch

# Una sola linea, sin encadenar comandos, redirecciones ni sustituciones.
nl=$'\n'; cr=$'\r'
[[ "$cmd" == *"$nl"* || "$cmd" == *"$cr"* ]] && exit 0
bad='[;&|<>`]'
[[ "$cmd" =~ $bad ]] && exit 0
[[ "$cmd" == *'$('* || "$cmd" == *'${'* ]] && exit 0

# Debe ser exactamente: bash "<ruta>/vs-immediate/scripts/vs.sh" vs-xxx [argumentos]
re='^[[:space:]]*(bash|sh)[[:space:]]+("([^"]*)"|([^"[:space:]]+))[[:space:]]+(vs-[a-z]+)(\.ps1)?([[:space:]].*)?$'
[[ "$cmd" =~ $re ]] || exit 0
path="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
name="${BASH_REMATCH[5]}"
rest="${BASH_REMATCH[7]}"

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

word() { [[ "$1" =~ (^|[^[:alnum:]])($2)([^[:alnum:]]|$) ]]; }

case "$name" in
  vs-list) approve "vs-immediate: listar instancias de Visual Studio (solo lectura)" ;;
  vs-state) approve "vs-immediate: consulta de estado (solo lectura)" ;;
  vs-history) has_flag "$rest" clear 1 || approve "vs-immediate: historial de expresiones (solo lectura)" ;;
  vs-threads) word "$rest" 'switch' || approve "vs-immediate: hilos (solo lectura)" ;;
  vs-exceptions) word "$rest" 'break|nobreak' || approve "vs-immediate: excepciones (solo lectura)" ;;
  vs-eval)
    has_flag "$rest" execute 3 && exit 0
    has_flag "$rest" expressionfile 11 && exit 0
    simple "$rest" && approve "vs-immediate: evaluacion de expresion simple (sin llamadas ni asignaciones)"
    ;;
  vs-types | vs-elsa) simple "$rest" && approve "vs-immediate: consulta de solo lectura (expresiones simples)" ;;
esac

exit 0
