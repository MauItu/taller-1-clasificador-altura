#!/usr/bin/env bash
# Abre el proyecto de Open Industry Project en Linux, bajo wine.
#
# OIP no publica build de Linux: los releases son binarios de Windows. Este
# lanzador corre el .exe del editor bajo wine. En Windows no hace falta nada de
# esto — se ejecuta el .exe directamente (ver README).
#
#   ./scripts/run-wine-editor.sh
#   ./scripts/run-wine-editor.sh res://demos/height_sorter/HeightSorter.tscn
#   ./scripts/run-wine-editor.sh --headless --script res://tools/audit_height_sorter.gd
#
# Configuracion por variables de entorno (los defaults son los de mi maquina):
#
#   OIP_PROYECTO   carpeta del proyecto de OIP (la que tiene project.godot)
#   OIP_EDITOR     ruta al .exe del editor
#   WINEPREFIX     prefijo de wine a usar
#
# El scope de systemd evita que el proceso herede oom_score_adj=200 del
# terminal, que hacia que el OOM killer lo matara durante el import inicial.

set -euo pipefail

PROYECTO="${OIP_PROYECTO:-$HOME/dev/oip/default_project}"
EDITOR="${OIP_EDITOR:-$HOME/dev/oip/release/OIP_v4.7-rc1.exe}"

export WINEPREFIX="${WINEPREFIX:-$HOME/dev/oip/wineprefix}"
export WINEDLLOVERRIDES="mscoree,mshtml="
export WINEDEBUG="${WINEDEBUG:-fixme-all}"

if [[ ! -f "$PROYECTO/project.godot" ]]; then
  echo "error: no encuentro project.godot en '$PROYECTO'." >&2
  echo "       exporta OIP_PROYECTO apuntando al proyecto de OIP." >&2
  exit 1
fi
if [[ ! -f "$EDITOR" ]]; then
  echo "error: no encuentro el editor en '$EDITOR'." >&2
  echo "       exporta OIP_EDITOR apuntando al .exe del release de OIP." >&2
  exit 1
fi

# wine espera una ruta de Windows; el drive Z: mapea la raiz del sistema.
WPATH="$(printf 'Z:%s' "$PROYECTO" | tr '/' '\\')"

# Si se pide --headless o --script no hay que abrir el editor grafico.
MODO=(--editor)
for arg in "$@"; do
  case "$arg" in
    --headless|--script) MODO=() ;;
  esac
done

exec systemd-run --user --scope --quiet --collect -- \
  wine "$EDITOR" --path "$WPATH" "${MODO[@]}" "$@"
