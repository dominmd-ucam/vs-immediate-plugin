#!/usr/bin/env bash
# vs.sh - Puente WSL -> Visual Studio (Windows) para vs-immediate.
#
#   bash vs.sh <script> [argumentos...]
#   bash vs.sh vs-state -What Status
#   bash vs.sh vs-eval -Expression 'lista.Count'
#
# Los scripts vs-*.ps1 usan la automatizacion COM de Visual Studio, asi que tienen que ejecutarse con Windows
# PowerShell (powershell.exe) en tu sesion de Windows. Desde WSL se llega a el por el interop de WSL.
# Este puente:
#   1. copia los scripts a %LOCALAPPDATA%\vs-immediate\scripts (solo si han cambiado) para que Windows los lea
#      desde una ruta normal en vez de la ruta \\wsl.localhost\...
#   2. pasa los argumentos en base64 por una variable de entorno (WSLENV), asi las comillas, espacios y simbolos
#      llegan intactos al script
#   3. devuelve el JSON del script limpio (sin retornos de carro ni BOM) y con su mismo codigo de salida.
# Las comillas dobles en las expresiones siguen la misma regla que en Windows: ~q~.
set -u

fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit 1; }

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

name="${1:-}"
[ -n "$name" ] || fail "Uso: bash vs.sh <script> [argumentos]. Ejemplo: bash vs.sh vs-state -What Status"
shift
name="${name%.ps1}"
[[ "$name" =~ ^vs-[a-z]+$ ]] || fail "Nombre de script no valido."
{ [ "$name" != "vs-common" ] && [ "$name" != "vs-run" ]; } || fail "Ese no es un script de consulta."
[ -f "$here/$name.ps1" ] || fail "No existe $name.ps1 junto a vs.sh."

if ! grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && [ -z "${WSL_DISTRO_NAME:-}" ]; then
  fail "Este puente es para WSL. En Windows nativo usa powershell.exe -NoProfile -ExecutionPolicy Bypass -File vs-xxx.ps1."
fi

ps="$(command -v powershell.exe 2>/dev/null || true)"
if [ -z "$ps" ] && [ -x /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]; then
  ps=/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe
fi
[ -n "$ps" ] || fail "No se encuentra powershell.exe. Comprueba que el interop de WSL esta activo (wsl.conf: [interop] enabled=true y appendWindowsPath=true) y reinicia WSL."

# Carpeta de trabajo en Windows (cacheada).
cache="${XDG_CACHE_HOME:-$HOME/.cache}/vs-immediate"
mkdir -p "$cache" 2>/dev/null
root=""
[ -f "$cache/winroot" ] && root="$(cat "$cache/winroot")"
if [ -z "$root" ] || [ ! -d "$root" ]; then
  win="$( cd /mnt/c 2>/dev/null || cd /; "$ps" -NoProfile -NonInteractive -Command '$env:LOCALAPPDATA' </dev/null 2>/dev/null | tr -d '\r' )"
  [ -n "$win" ] || fail "No se pudo leer LOCALAPPDATA de Windows a traves de powershell.exe."
  root="$(wslpath -u "$win")/vs-immediate"
  mkdir -p "$root/scripts" 2>/dev/null || fail "No se pudo crear la carpeta de Windows para los scripts."
  printf '%s' "$root" > "$cache/winroot"
fi
dest="$root/scripts"

# Sincroniza los scripts con la copia de Windows si han cambiado.
stamp="$(cat "$here"/*.ps1 | sha256sum | cut -d' ' -f1)"
if [ "$(cat "$dest/.stamp" 2>/dev/null)" != "$stamp" ]; then
  mkdir -p "$dest" 2>/dev/null || fail "No se pudo crear la carpeta de scripts en Windows."
  (
    command -v flock >/dev/null 2>&1 && flock -w 20 9
    if [ "$(cat "$dest/.stamp" 2>/dev/null)" != "$stamp" ]; then
      for f in "$dest"/*.ps1; do
        [ -e "$f" ] && [ ! -e "$here/$(basename "$f")" ] && rm -f "$f"
      done
      cp -f "$here"/*.ps1 "$dest"/ && printf '%s' "$stamp" > "$dest/.stamp"
    fi
  ) 9>"$cache/sync.lock" || fail "No se pudieron copiar los scripts a la carpeta de Windows."
fi

# Argumentos: cada uno en base64 (un argumento vacio se escribe "="), separados por comas.
args=""
for a in "$@"; do
  if [ -z "$a" ]; then e="="; else e="$(printf '%s' "$a" | base64 -w0)"; fi
  args="${args:+$args,}$e"
done
[ "${#args}" -le 30000 ] || fail "Argumentos demasiado largos para pasarlos por el entorno de Windows."
export VS_IMMEDIATE_ARGS="$args"
export WSLENV="VS_IMMEDIATE_ARGS${WSLENV:+:$WSLENV}"

winrun="$(wslpath -w "$dest/vs-run.ps1")"
cd /mnt/c 2>/dev/null || cd /
"$ps" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$winrun" "$name" </dev/null | sed -e 's/\r$//' -e '1s/^\xEF\xBB\xBF//'
exit "${PIPESTATUS[0]}"
