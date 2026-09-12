#!/usr/bin/env bash
# Copia los archivos del taller dentro del proyecto de Open Industry Project.
#
#   ./scripts/instalar.sh /ruta/al/default_project
#
# El repo no contiene el proyecto de OIP (pesa ~550 MB y no es nuestro): solo
# los archivos propios, que se superponen sobre el proyecto base respetando las
# rutas demos/, tools/ y oip_data/.

set -euo pipefail

PROYECTO="${1:-}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "$PROYECTO" ]]; then
  echo "uso: $0 /ruta/al/proyecto-de-oip" >&2
  exit 1
fi
if [[ ! -f "$PROYECTO/project.godot" ]]; then
  echo "error: no encuentro project.godot en '$PROYECTO'" >&2
  exit 1
fi
if [[ ! -f "$PROYECTO/parts/BeltConveyor.tscn" ]]; then
  echo "error: '$PROYECTO' no parece el proyecto de Open Industry Project" >&2
  exit 1
fi

for carpeta in demos tools oip_data; do
  cp -r "$REPO/$carpeta" "$PROYECTO/"
  echo "  copiado  $carpeta/"
done

echo
echo "Listo. Abri el proyecto con el editor de OIP y despues la escena"
echo "res://demos/height_sorter/HeightSorter.tscn"
