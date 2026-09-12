# Taller 1 — Clasificador de cajas por altura

Gemelo digital de una línea de sortación, hecho en
[Open Industry Project](https://github.com/Open-Industry-Project/Open-Industry-Project) (OIP):
una cinta transportadora dentro de un almacén genera cajas de altura aleatoria, las mide al vuelo
y expulsa hacia una línea de rechazo las que superan una altura de corte.

El control **no** está embebido en el simulador: lo ejecuta un **PLC** programado en
**Texto Estructurado (IEC 61131-3)**, que se comunica con la escena por tags. La escena es la
planta; el PLC es el control.

```
   spawner        estación de medición          desviador
      ↓            (2 fotocélulas)                  ↓
   ═══════════════════╪═══════════════════════════╪═══════►  cajas bajas
    x=1             x=5                         x=7.8        (despawn x=10.4)
                                                  │
                                                  ▼  cajas altas
                                             línea de rechazo
```

> **[Documentación completa → `EXPLICACION.md`](EXPLICACION.md)** — cómo funciona el PLC línea por
> línea, cómo está armada la escena, la geometría, cómo se verificó y cómo sustentarlo.

---

## 1. Qué hay en este repo (y qué no)

Este repo contiene **solo los archivos propios del taller**. **No** contiene el proyecto de
Open Industry Project, que pesa ~550 MB y no es nuestro. Los archivos se **superponen** sobre el
proyecto de OIP respetando las rutas:

```
demos/height_sorter/
    HeightSorter.tscn     la escena (planta) + el programa ST embebido como metadato
    height_sorter.st      el programa de PLC, fuente legible y versionable
    height_gate.gd        ajuste mecánico de la altura del sensor (no es lógica de control)
oip_data/
    tag_groups.cfg        define el grupo de tags "ST" (protocolo soft_plc)
    comms_settings.cfg    habilitador global de comunicaciones
tools/
    audit_height_sorter.gd    auditoría headless de 120 s (la verificación principal)
    verify_height_sorter.gd   traza en vivo, para depurar geometría
    check_st.gd               compila el programa ST sin ejecutarlo
    sync_st_to_scene.py       embebe el .st dentro del .tscn
scripts/
    instalar.ps1 / instalar.sh   copian lo anterior dentro del proyecto de OIP
    run-wine-editor.sh           lanzador para Linux (OIP no tiene build nativo)
```

---

## 2. Requisitos

| | |
|---|---|
| **Windows 10/11 x64** | plataforma soportada por OIP. Es el camino directo. |
| **Linux** | funciona, pero hay que correr el release de Windows bajo `wine` (ver §5). |
| **Open Industry Project v4.7-rc1** | [release](https://github.com/Open-Industry-Project/Open-Industry-Project/releases/tag/v4.7-rc1) → `OIP_v4.7-rc1.zip` (~700 MB) |
| **Git** | para clonar este repo. |
| Python 3 *(opcional)* | solo si vas a editar el `.st` y re-sincronizarlo. |

No hace falta instalar Godot aparte: el release de OIP **es** un fork del editor de Godot 4.7.

---

## 3. Instalación en Windows

### 3.1 Bajar y descomprimir OIP

Descargá `OIP_v4.7-rc1.zip` del release y descomprimilo. Adentro hay **dos** cosas:

| Archivo | Qué es |
|---|---|
| `OIP_v4.7-rc1.exe` | el **editor** (Godot 4.7 forkeado, ~174 MB) |
| `default_project.zip` | el **proyecto** con todos los componentes de OIP (~558 MB) |

Descomprimí también `default_project.zip`. Queda una carpeta `default_project\` que contiene
`project.godot` — **esa** es la carpeta del proyecto. Por ejemplo:

```
C:\OIP\
    OIP_v4.7-rc1.exe
    default_project\
        project.godot
        parts\
        src\
        ...
```

### 3.2 Clonar este repo

```powershell
git clone https://github.com/MauItu/taller-1-clasificador-altura.git
cd taller-1-clasificador-altura
```

### 3.3 Copiar los archivos dentro del proyecto

```powershell
.\scripts\instalar.ps1 -Proyecto C:\OIP\default_project
```

El script valida que la ruta sea realmente un proyecto de OIP, copia `demos\`, `tools\` y
`oip_data\`, y se puede volver a correr sin problema. A mano, la primera vez, equivale a:

```powershell
Copy-Item demos,tools,oip_data -Destination C:\OIP\default_project -Recurse -Force
```

(usá el script si vas a re-copiar: `Copy-Item` anida `demos\demos\` cuando el destino ya existe).

> `oip_data\` es obligatorio: sin él no existe el grupo de tags `ST` y el PLC no arranca.

### 3.4 Abrir el proyecto

```powershell
C:\OIP\OIP_v4.7-rc1.exe --path C:\OIP\default_project --editor
```

(o ejecutar el `.exe` a mano y elegir la carpeta en el Project Manager).

La **primera** apertura importa ~550 MB de assets y tarda varios minutos. Si en ese primer arranque
aparecen errores del addon `oip_comms`, cerrá y volvé a abrir: se resuelven solos en la segunda
pasada, cuando la GDExtension ya está registrada.

### 3.5 Abrir la escena y arrancar

1. En el panel **FileSystem**, doble clic en `demos/height_sorter/HeightSorter.tscn`.
2. En el árbol de nodos, clic en `MainLine` y con el mouse sobre el viewport 3D apretá **F** para
   encuadrar la cámara.
3. Botón **Start** de la barra de simulación de OIP (arriba). **La simulación corre dentro del
   editor, no con F5.**

Deberías ver cajas de distinta altura apareciendo, los dos haces de la estación de medición
poniéndose rojos al cortarse, y el desviador sacando las cajas altas.

El programa de PLC que está gobernando todo se ve en el dock del **ST Editor**.

---

## 4. Verificación (headless, sin ventana)

La comprobación objetiva de que funciona. Corre 120 s de simulación sin GPU, sigue cada caja hasta
que desaparece, mira por dónde salió y lo contrasta con su altura real; además lee los contadores
internos del PLC.

```powershell
C:\OIP\OIP_v4.7-rc1.exe --headless --path C:\OIP\default_project ^
    --script res://tools/audit_height_sorter.gd
```

Salida de una corrida real (las alturas son aleatorias, así que los números varían):

```
SoftPlcBridge: feeding ST program (3666 chars) to soft_plc group 'ST'
=========== AUDITORIA 120 s ===========
-- contadores internos del PLC (programa ST) --
   Counted   = 58.0
   Diverted  = 27.0
   Passed    = 30.0
   Pending   = 1.0
-- destino real de las cajas (fisica de la escena) --
   clasificadas CORRECTAMENTE : 57
   clasificadas MAL           : 0
   perdidas                   : 0
```

Los contadores del PLC cierran con la física: 27 desviadas + 30 pasadas + 1 en tránsito = 58 medidas.

Las otras dos herramientas:

```powershell
:: compila el programa ST sin ejecutarlo (2 s) — para validar sintaxis
... --script res://tools/check_st.gd

:: traza en vivo, 30 s: contadores del PLC + estado de los 3 sensores + posición de cada caja
... --script res://tools/verify_height_sorter.gd
```

---

## 5. Instalación en Linux

OIP no publica build de Linux — los releases son binarios de Windows
([issue #228](https://github.com/Open-Industry-Project/Open-Industry-Project/issues/228),
[PR #232](https://github.com/Open-Industry-Project/Open-Industry-Project/pull/232), ambos abiertos).
El release de Windows corre bien bajo `wine`, con aceleración Vulkan nativa.

```bash
# 1. descomprimir OIP (el .zip trae el .exe y default_project.zip)
unzip OIP_v4.7-rc1.zip -d ~/dev/oip/release
unzip ~/dev/oip/release/default_project.zip -d ~/dev/oip

# 2. copiar los archivos del taller
git clone https://github.com/MauItu/taller-1-clasificador-altura.git
cd taller-1-clasificador-altura
./scripts/instalar.sh ~/dev/oip/default_project

# 3. abrir el editor
export OIP_PROYECTO=~/dev/oip/default_project
export OIP_EDITOR=~/dev/oip/release/OIP_v4.7-rc1.exe
./scripts/run-wine-editor.sh

# 4. o correr la auditoría headless
./scripts/run-wine-editor.sh --headless --script res://tools/audit_height_sorter.gd
```

El lanzador envuelve `wine` en `systemd-run --user --scope` a propósito: sin eso el proceso hereda
`oom_score_adj=200` del terminal y el OOM killer lo mata durante el import inicial del proyecto.

---

## 6. Control por PLC, en corto

El programa vive en [`demos/height_sorter/height_sorter.st`](demos/height_sorter/height_sorter.st)
y corre en el **Soft PLC** integrado de OIP (`oip-plc.js`, runtime IEC 61131-3). La escena y el PLC
se comunican por un grupo de tags llamado `ST`, definido en `oip_data/tag_groups.cfg`.

| Tag | Dirección | Elemento de la escena | Variable en el PLC |
|---|---|---|---|
| `GatePresence` | escena → PLC | fotocélula baja de la estación | `VAR_INPUT` |
| `GateHeight` | escena → PLC | fotocélula alta de la estación | `VAR_INPUT` |
| `DivertEye` | escena → PLC | fotocélula de disparo | `VAR_INPUT` |
| `DivertCmd` | PLC → escena | desviador | `VAR_OUTPUT` |

Usa bloques de función estándar: `R_TRIG` / `F_TRIG` para los flancos de las fotocélulas, `TON`
para la duración del empuje, y un `ARRAY [0..7] OF BOOL` como registro de desplazamiento.

**Cómo discrimina.** En la estación hay dos fotocélulas en el mismo punto de la línea: `GatePresence`
con el haz a 6 cm (la corta toda caja) y `GateHeight` a la altura de corte (solo la cortan las
altas). El haz bajo aporta el *evento* y el haz alto el *atributo*. El veredicto se acumula mientras
la caja pasa y, al salir, entra en un **FIFO**. Aguas abajo, `DivertEye` desencola el veredicto más
viejo cuando llega una caja. Por eso se puede cambiar la velocidad de la cinta o el caudal del
spawner sin recalibrar nada: **no hay ningún tiempo calibrado en el sistema**.

El detalle completo — por qué dos sensores, por qué FIFO y no temporizador, de dónde salen las
coordenadas — está en [`EXPLICACION.md`](EXPLICACION.md).

---

## 7. Parámetros que se pueden tocar

| Dónde | Parámetro | Default | Qué hace |
|---|---|---|---|
| `GateSetup` (Inspector) | `height_threshold` | 0.35 m | Altura de corte. Mueve el haz de `GateHeight` **en vivo**. |
| `GateSetup` (Inspector) | `belt_surface_y` | 0.9 m | Altura de la superficie de la cinta. |
| `BoxSpawner` | `random_size_min.y` / `max.y` | 0.15 / 0.55 m | Rango de alturas de las cajas. |
| `BoxSpawner` | `boxes_per_minute` | 30 | Caudal. |
| `MainLine` / `RejectLine` | `speed` | 1 m/s | Velocidad de las cintas. |
| `height_sorter.st` | `PushTimer` `PT` | `T#1100ms` | Duración del empuje. |

---

## 8. Editar el programa ST

OIP ejecuta el ST desde el metadato `oip_st_program` de la raíz de la escena, **no** desde el
archivo `.st`. El `.st` es la fuente legible y versionable; el `.tscn` es lo que se ejecuta.

- Editaste el `.st` → `python3 tools/sync_st_to_scene.py` para embeberlo en la escena.
- Editaste desde el dock del ST Editor → el que cambió es el `.tscn`; hay que copiar a mano al `.st`.

---

## 9. Problemas conocidos

| Síntoma | Causa / solución |
|---|---|
| Errores de `oip_comms` / `tag_group_initialized` en el primer arranque | La GDExtension todavía no está registrada durante el primer escaneo. Cerrá y volvé a abrir. |
| `SoftPlcBridge: scene root has no 'oip_st_program' metadata` | Falta copiar `demos/` o se abrió otra escena. |
| El PLC no arranca / no hay grupo `ST` | Falta copiar `oip_data/`. Verificalo con `--script res://tools/check_st.gd`. |
| Las cajas caen al vacío al aparecer | `BoxSpawner` tiene que colgar **directo de la raíz** de la escena (ver §16.1 de `EXPLICACION.md`). |

---

## 10. Entorno de desarrollo

Desarrollado sobre Arch Linux + Hyprland corriendo el release de Windows de OIP (v4.7-rc1, motor
`4.7.stable.custom_build.832a73af2`) bajo wine. La auditoría de este README se corrió en ese mismo
entorno, sobre un `default_project` recién descomprimido.
