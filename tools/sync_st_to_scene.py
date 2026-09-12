#!/usr/bin/env python3
"""Embebe demos/height_sorter/height_sorter.st como metadato de la escena.

OIP ejecuta el programa ST desde el metadato `oip_st_program` de la raiz de la
escena (lo lee SoftPlcBridge). El archivo .st es la fuente legible y versionable;
este script lo copia al .tscn. Correr despues de editar el .st.

OJO: si editas el programa desde el dock del ST Editor dentro de Godot, el que
cambia es el .tscn y NO el .st. En ese caso hay que copiar en sentido inverso.
"""
import pathlib, re, sys

base = pathlib.Path(__file__).resolve().parent.parent / "demos" / "height_sorter"
st = (base / "height_sorter.st").read_text()
scene_path = base / "HeightSorter.tscn"
scene = scene_path.read_text()

esc = st.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
new = 'metadata/oip_st_program = "%s"' % esc

if "metadata/oip_st_program" in scene:
    scene = re.sub(r'metadata/oip_st_program = "(?:[^"\\]|\\.)*"', lambda _: new, scene, count=1)
else:
    scene = scene.replace('[node name="HeightSorter" type="Node3D"]\n',
                          '[node name="HeightSorter" type="Node3D"]\n%s\n' % new, 1)

scene_path.write_text(scene)
print("Embebido %d caracteres de ST en %s" % (len(st), scene_path.name))
