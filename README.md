# Taller 1 — Clasificador de cajas por altura

Escena para [Open Industry Project](https://github.com/Open-Industry-Project/Open-Industry-Project):
una línea transportadora dentro de un almacén que genera cajas de altura aleatoria, las mide al
vuelo y expulsa hacia una línea de rechazo las que superan una altura de corte.

```
   spawner        estación de medición          desviador
      ↓            (2 fotocélulas)                  ↓
   ═══════════════════╪═══════════════════════════╪═══════►  cajas bajas
    x=1             x=5                         x=7.8        (despawn x=10.4)
                                                  │
                                                  ▼  cajas altas
                                             línea de rechazo
```

## Cómo discrimina

La discriminación **no** depende de temporizadores calibrados contra la velocidad de la cinta.

En la estación de medición hay dos fotocélulas (`DiffuseSensor`) en el mismo punto de la línea:

- **GatePresence** — haz a 6 cm sobre la cinta. La corta *toda* caja.
- **GateHeight** — haz a la altura de corte. Solo la cortan las que la superan.

Mientras una caja está frente a la estación, el controlador acumula el veredicto (basta con que
corte el haz alto en algún instante para marcarla como alta). Cuando la caja termina de pasar,
el veredicto entra en un **registro de desplazamiento FIFO**.

Aguas abajo, la fotocélula **DivertEye** está alineada con la paleta del desviador. Cuando detecta
una caja, saca el veredicto más viejo de la cola y decide si empuja. Es el esquema de una sortadora
real: podés cambiar la velocidad de la cinta o el caudal del spawner sin recalibrar nada.

## Parámetros

En el nodo **Sorter**:

| Propiedad | Default | Qué hace |
|---|---|---|
| `height_threshold` | 0.35 m | Altura de corte. Mueve el haz de `GateHeight` en vivo. |
| `belt_surface_y` | 0.9 m | Altura de la superficie de la cinta en el espacio de la escena. |
| `push_duration` | 1.1 s | Cuánto queda extendida la paleta. |
| `trigger_delay` | 0 s | Retardo entre el disparo de la fotocélula y el empuje. |

En **BoxSpawner**: `random_size_min.y` / `random_size_max.y` (rango de alturas, 0.15–0.55 m) y
`boxes_per_minute` (30). En **MainLine** / **RejectLine**: `speed` (1 m/s).

## Instalación

Copiar las carpetas dentro del proyecto de OIP, respetando las rutas:

```bash
cp -r demos tools /ruta/al/Open-Industry-Project/
```

Abrir `res://demos/height_sorter/HeightSorter.tscn` y darle al botón **Start** de la simulación de
OIP (la simulación corre dentro del editor, no con F5).

## Verificación

`tools/audit_height_sorter.gd` corre la simulación **headless** y audita cada caja: la sigue hasta
que desaparece, mira por dónde salió y lo contrasta con su altura real.

```bash
godot --headless --path /ruta/al/proyecto --script res://tools/audit_height_sorter.gd
```

Resultado sobre 120 s de simulación:

```
=========== AUDITORIA 120 s ===========
  medidas en la estacion : 58  (altas 20 / bajas 37)
  cajas que completaron el recorrido: 56
  clasificadas CORRECTAMENTE : 56
  clasificadas MAL           : 0
  perdidas (ni linea ni rechazo): 0
```

`tools/verify_height_sorter.gd` es una traza en vivo (posiciones de cajas y estado de los tres
sensores frame a frame), útil para depurar cambios de geometría.

## Notas de implementación

Tres cosas que fallan en silencio y costaron depuración:

1. **`Box` es `top_level`.** El nodo raíz de `parts/Box.tscn` tiene `top_level = true`, y
   `box_spawner.gd` hace `box.position = position` usando la posición **local** del spawner. O sea:
   las cajas nacen en la posición *local* del spawner interpretada como coordenada global. El
   `BoxSpawner` tiene que colgar **directo de la raíz** de la escena; con un nodo envoltorio en el
   medio las cajas aparecen en el lugar equivocado.

2. **Referencias a nodos exportadas necesitan `node_paths`.** Un `@export var foo: Node3D` no se
   resuelve solo con `foo = NodePath("../Foo")`: el tag del nodo tiene que declarar
   `node_paths=PackedStringArray("foo")`, si no la propiedad llega en `null` sin ningún error.

3. **La base de `Transform3D` se serializa por FILAS en los `.tscn`.** Los 9 primeros floats son
   `row0, row1, row2`, mientras que `basis.x`/`basis.y`/`basis.z` en GDScript son las COLUMNAS.
   Un giro de +90° en Y (local +X → mundo −Z) se escribe
   `Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, ox, oy, oz)`.

## Entorno

Desarrollado sobre Arch Linux + Hyprland corriendo el release Windows de OIP (v4.7-rc1, motor
`4.7.stable.custom_build.832a73af2`) bajo **wine** — no hay build oficial de Linux
([issue #228](https://github.com/Open-Industry-Project/Open-Industry-Project/issues/228),
[PR #232](https://github.com/Open-Industry-Project/Open-Industry-Project/pull/232), ambos abiertos).

`scripts/run-wine-editor.sh` es el lanzador que usé; **las rutas están hardcodeadas a mi máquina**,
ajustalas. Envuelve wine en `systemd-run --user --scope` a propósito: sin eso el proceso hereda
`oom_score_adj=200` del terminal y el OOM killer lo mata durante el import del proyecto.
