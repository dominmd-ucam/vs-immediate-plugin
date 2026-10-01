#!/usr/bin/env bash
# install-wsl.sh - vs-immediate en WSL: comprobacion del entorno e instalacion para Codex.
#
#   bash install/install-wsl.sh check             comprueba que WSL llega a tu Visual Studio de Windows
#   bash install/install-wsl.sh codex             instala las skills y las reglas de permisos para Codex (en WSL)
#   bash install/install-wsl.sh codex --uninstall lo quita
#
# Claude Code en WSL no necesita este instalador: se instala como plugin desde dentro de WSL
#   /plugin marketplace add dominmd-ucam/vs-immediate-plugin
#   /plugin install vs-immediate@vs-immediate-plugin
# (el Claude Code de WSL usa su propio ~/.claude, separado del de Windows).
#
# Los scripts hablan con Visual Studio (Windows) a traves de powershell.exe y el interop de WSL;
# ver skills/vs-immediate/scripts/vs.sh.
set -u

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scripts="$repo/skills/vs-immediate/scripts"
mark_ok() { printf '[x] %s\n' "$1"; }
mark_no() { printf '[ ] %s\n' "$1"; }

is_wsl() { grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; }

cmd_check() {
  local bad=0
  if is_wsl; then mark_ok "Estas en WSL (${WSL_DISTRO_NAME:-distribucion no indicada})"; else mark_no "Esto no parece WSL. En Windows nativo usa powershell.exe directamente."; return 1; fi

  local ps
  ps="$(command -v powershell.exe 2>/dev/null || true)"
  if [ -n "$ps" ]; then mark_ok "powershell.exe accesible: $ps"; else
    mark_no "powershell.exe no se encuentra: activa el interop en /etc/wsl.conf ([interop] enabled=true, appendWindowsPath=true) y ejecuta 'wsl --shutdown' desde Windows"
    return 1
  fi

  if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    mark_ok "jq o python3 disponible (necesario para el hook de permisos de Claude Code)"
  else
    mark_no "Falta jq o python3: el hook no aprobara nada solo y Claude pedira permiso en cada consulta (sudo apt install jq)"
    bad=1
  fi
  for t in base64 sha256sum sed wslpath; do
    if command -v "$t" >/dev/null 2>&1; then :; else mark_no "Falta el comando $t"; bad=1; fi
  done

  echo
  echo "Probando el puente con vs-list (Visual Studio debe estar abierto en Windows)..."
  local out rc
  out="$(bash "$scripts/vs.sh" vs-list 2>&1)"; rc=$?
  printf '%s\n' "$out"
  echo
  if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"ok": *true'; then
    mark_ok "WSL llega a Visual Studio por COM"
  else
    mark_no "El puente no obtuvo respuesta de Visual Studio (mensaje arriba). Si dice que no hay instancias: abre VS con una solucion, con el mismo nivel de permisos que WSL (no como administrador si WSL no lo es)."
    bad=1
  fi
  return $bad
}

cmd_codex() {
  local skills_dir="$HOME/.agents/skills" rules_dir="$HOME/.codex/rules"
  local rules_file="$rules_dir/vs-immediate.rules"
  local target="$skills_dir/vs-immediate/scripts/vs.sh"

  if [ "${1:-}" = "--uninstall" ]; then
    local d
    for d in "$repo"/skills/*/; do
      d="$skills_dir/$(basename "$d")"
      [ -d "$d" ] && rm -rf "$d" && echo "Quitada: $d"
    done
    [ -f "$rules_file" ] && rm -f "$rules_file" && echo "Quitado: $rules_file"
    return 0
  fi

  is_wsl || { echo "Esto no parece WSL."; return 1; }
  mkdir -p "$skills_dir" "$rules_dir" || return 1
  local d n
  for d in "$repo"/skills/*/; do
    n="$(basename "$d")"
    rm -rf "$skills_dir/$n"
    cp -r "$d" "$skills_dir/$n" && echo "Skill instalada: $skills_dir/$n"
  done

  # Reglas de Codex (prefix_rule): allow = sin preguntar, prompt = pide aprobacion; en ambos casos el comando se
  # ejecuta fuera del sandbox (necesario para usar el interop de WSL y llegar a Visual Studio).
  local esc="${target//\\/\\\\}"; esc="${esc//\"/\\\"}"
  {
    echo "# Generado por install-wsl.sh. No lo edites a mano: vuelve a ejecutar el instalador."
    echo "# allow = se ejecuta sin preguntar, fuera del sandbox. prompt = pide aprobacion y se ejecuta fuera del sandbox."
    echo
    local pair dec why names
    for pair in \
      "allow|vs-state vs-list vs-history|vs-immediate: consultas de solo lectura sobre Visual Studio" \
      "prompt|vs-eval vs-types vs-elsa vs-threads vs-exceptions vs-trace vs-watch vs-control|vs-immediate: evalua o controla el depurador (puede ejecutar codigo de la aplicacion o cambiar su estado)"; do
      dec="${pair%%|*}"; pair="${pair#*|}"; names="${pair%%|*}"; why="${pair#*|}"
      local alts="" s
      for s in $names; do alts="${alts:+$alts, }\"$s\", \"$s.ps1\""; done
      cat <<RULE
prefix_rule(
    pattern = ["bash", "$esc", [$alts]],
    decision = "$dec",
    justification = "$why",
)

RULE
    done
  } > "$rules_file"
  echo "Reglas escritas: $rules_file"
  echo
  echo "Comprobacion (opcional): codex execpolicy check --pretty --rules \"$rules_file\" -- bash \"$target\" vs-state -What Status"
  echo "Reinicia Codex para que cargue las skills y las reglas. Antes, 'bash install/install-wsl.sh check' para validar el entorno."
}

case "${1:-}" in
  check) cmd_check ;;
  codex) shift; cmd_codex "$@" ;;
  *) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
