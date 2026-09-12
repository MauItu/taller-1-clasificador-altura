# Clasificador de cajas por altura — documentación completa

Todo lo necesario para entender el sistema y sustentarlo: qué se construyó, cómo funciona el PLC
línea por línea, cómo está armada la escena, de dónde salen los números, cómo se verificó y qué
responder a las preguntas previsibles.

Para instalarlo y correrlo, ver [`README.md`](README.md).

**Índice**

1. [En una frase](#1-en-una-frase)
2. [El problema industrial](#2-el-problema-industrial)
3. [Arquitectura: planta / control / cableado](#3-arquitectura-planta--control--cableado)
4. [La escena, nodo por nodo](#4-la-escena-nodo-por-nodo)
5. [La geometría: de dónde sale cada número](#5-la-geometría-de-dónde-sale-cada-número)
6. [El PLC, línea por línea](#6-el-plc-línea-por-línea)
7. [Por qué DOS fotocélulas](#7-por-qué-dos-fotocélulas-en-la-estación-de-medición)
8. [Por qué un FIFO y no un temporizador](#8-por-qué-un-fifo-y-no-un-temporizador)
9. [El único script propio de la escena](#9-el-único-script-propio-de-la-escena)
10. [Cómo se construyó](#10-cómo-se-construyó)
11. [Cómo se verificó](#11-cómo-se-verificó)
12. [El bug que vale la pena contar](#12-el-bug-que-vale-la-pena-contar)
13. [Guion de la sustentación](#13-guion-de-la-sustentación)
14. [Preguntas probables](#14-preguntas-probables-y-cómo-responderlas)
15. [Limitaciones honestas](#15-limitaciones-honestas)
16. [Apéndice: trampas del motor](#16-apéndice-trampas-del-motor)

---

## 1. En una frase

Un **gemelo digital de una línea de sortación por altura** controlado por un **PLC**: una cinta
transportadora dentro de un almacén recibe cajas de altura variable, tres fotocélulas las miden sin
detenerlas, y un programa en **Texto Estructurado (IEC 61131-3)** decide cuáles expulsar hacia una
línea de rechazo.

La separación es la que corresponde a un gemelo digital:

- **La escena** es la planta física — cintas, sensores, actuador, cajas, gravedad, colisiones.
- **El PLC** es el control — no sabe nada de geometría, solo lee bits y energiza una salida.
- **Los tags** son el cableado entre ambos.

---

## 2. El problema industrial

En un centro de distribución real esto es cotidiano:

- Cajas que exceden la altura libre de un túnel de escaneo o de un equipo aguas abajo.
- Producto mal armado o mal paletizado que hay que sacar antes de que atasque una máquina.
- Separación por formato para rutas de empaque distintas.

La restricción clave: **no se puede detener la línea para medir**. La medición ocurre con la caja en
movimiento, y la decisión se ejecuta metros más adelante, cuando esa caja específica llega al
actuador. Ese desfase entre *dónde se mide* y *dónde se actúa* es el corazón técnico del problema, y
es lo que resuelve la sección [8](#8-por-qué-un-fifo-y-no-un-temporizador).

---

## 3. Arquitectura: planta / control / cableado

Open Industry Project está hecho para ser manejado por un PLC externo. Cada componente tiene una
sección **Communications** en el Inspector (`enable_comms`, `tag_group_name`, `tag_name`). Los
sensores **escriben** su estado a un tag; los actuadores **leen** su comando de un tag.

OIP soporta ocho protocolos: EtherNet/IP (Allen-Bradley), Modbus TCP, OPC UA, S7 (Siemens),
ADS (Beckhoff), RTDE (Universal Robots), MQTT y un **Soft PLC** integrado. Usamos el último: es un
runtime IEC 61131-3 completo (`oip-plc.js`) que corre dentro de OIP, así que el programa es PLC de
verdad — mismo lenguaje, mismos bloques de función estándar — sin depender de software externo.

### El cableado

```
   ESCENA (planta)                  TAGS            PLC (control)
   ─────────────────                ────            ─────────────
   GatePresence  ──── escribe ───►  BOOL  ────────► VAR_INPUT  GatePresence
   GateHeight    ──── escribe ───►  BOOL  ────────► VAR_INPUT  GateHeight
   DivertEye     ──── escribe ───►  BOOL  ────────► VAR_INPUT  DivertEye

   Diverter      ◄─── lee ────────  BOOL  ◄──────── VAR_OUTPUT DivertCmd
```

| Tag | Dirección | Elemento de la escena | Variable en el PLC |
|---|---|---|---|
| `GatePresence` | escena → PLC | fotocélula baja de la estación | `VAR_INPUT` |
| `GateHeight` | escena → PLC | fotocélula alta de la estación | `VAR_INPUT` |
| `DivertEye` | escena → PLC | fotocélula de disparo | `VAR_INPUT` |
| `DivertCmd` | PLC → escena | desviador | `VAR_OUTPUT` |

### Cómo se declara el grupo de tags

`oip_data/tag_groups.cfg`:

```ini
[info]
group_count=1

[group_0]
name="ST"
polling_rate="50"
protocol="7"
gateway="res://oip-plc.js"
```

`protocol="7"` es `soft_plc` (la tabla de traducción está en `src/comms/oip_comms_service.gd`).
`polling_rate="50"` es el ciclo de sondeo en ms — el equivalente al tiempo de scan del PLC.
`gateway` apunta al runtime IEC 61131-3.

`oip_data/comms_settings.cfg` trae `enable_comms=true`, el habilitador global. Sin estos dos
archivos el grupo `ST` no existe, los tags no se registran y el PLC no arranca.

### Cómo llega el programa al runtime

El autoload `SoftPlcBridge` (`src/comms/soft_plc_bridge.gd`) escucha la señal
`OIPComms.tag_group_initialized`. Cuando se inicializa el grupo `ST`, lee el metadato
`oip_st_program` de la **raíz de la escena** y se lo pasa al runtime:

```gdscript
var src := String(root.get_meta("oip_st_program"))
print("SoftPlcBridge: feeding ST program (%d chars) to soft_plc group '%s'" % [src.length(), group_name])
OIPComms.set_soft_plc_program(SOFT_PLC_GROUP, src)
```

Por eso en el log de arranque aparece:

```
SoftPlcBridge: feeding ST program (3666 chars) to soft_plc group 'ST'
```

Esa línea es la confirmación de que el PLC recibió el programa. Si no aparece, no hay control.

> **Consecuencia práctica:** lo que se ejecuta es el metadato del `.tscn`, **no** el archivo `.st`.
> El `.st` es la fuente legible y versionable. `tools/sync_st_to_scene.py` copia uno al otro.

**Por qué importa esta separación:** el PLC no sabe dónde están los sensores, ni a qué velocidad va
la cinta, ni cuánto mide una caja. Solo ve tres bits entrando y energiza uno saliendo. Ese mismo
programa, sin cambiar una línea, se podría cargar en un PLC físico conectado a fotocélulas reales.

---

## 4. La escena, nodo por nodo

`demos/height_sorter/HeightSorter.tscn`. Todos los nodos salvo `GateSetup` son componentes que
**ya trae Open Industry Project**.

| Nodo | Tipo OIP | Posición (x, y, z) | Función | Parámetros clave |
|---|---|---|---|---|
| `HeightSorter` | Node3D | — | raíz; lleva el metadato `oip_st_program` | — |
| `Warehouse` | Building | (5, 0, 0) | el galpón: piso, paredes, techo, luz | 3 × 2 secciones = 30 × 20 m |
| `MainLine` | BeltConveyor | (0, 0.9, 0) | línea principal | 10 m × 0.8 m, 1 m/s |
| `BoxSpawner` | BoxSpawner | (1, 1.22, 0) | genera las cajas | 30 cajas/min, alto 0.15–0.55 m |
| `GatePresence` | DiffuseSensor | (5, 0.71, 0.84) | fotocélula de presencia | haz a 6 cm; tag `GatePresence` |
| `GateHeight` | DiffuseSensor | (5, 1.00, 0.84) | fotocélula de altura | haz a la altura de corte; tag `GateHeight` |
| `DivertEye` | DiffuseSensor | (8.05, 0.71, 0.84) | fotocélula de disparo | haz a 6 cm; tag `DivertEye` |
| `Diverter` | Diverter | (7.8, 0.7, 1.5135) | actuador que expulsa | carrera 1.0 m en 0.3 s; tag `DivertCmd` |
| `RejectLine` | BeltConveyor | (7.8, 0.9, −0.4) | línea de rechazo, girada 90° | 2.5 m, 1 m/s |
| `DespawnMain` | Despawner | (10.4, 1.2, 0) | retira las cajas que pasaron | escalado 2× en X y Z |
| `DespawnReject` | Despawner | (7.8, 1.2, −2.8) | retira las cajas rechazadas | escalado 2× en X y Z |
| `GateSetup` | *(script propio)* | — | ajuste mecánico del sensor de altura | `height_threshold` |

Notas sobre nodos concretos:

- **`MainLine`** corre sobre el eje X, de x=0 a x=10, con la superficie a y=0.9. Los `side_guards`
  están desactivados: con guardas laterales el desviador no podría sacar la caja.
- **`BoxSpawner`** tiene `random_size = true` con `random_size_min = (0.5, 0.15, 0.35)` y
  `random_size_max = (0.5, 0.55, 0.35)`. O sea: largo y ancho fijos, **solo varía la altura**. Eso
  aísla la variable que el sistema tiene que discriminar.
- **Los tres `DiffuseSensor`** tienen `max_range = 1.0` y están rotados 180° sobre Y — en el `.tscn`
  eso es `Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, ...)` — para que su +Z local apunte hacia −Z
  global y el haz cruce la cinta a lo ancho.
- **`RejectLine`** está girada +90° sobre Y, que en el `.tscn` se escribe
  `Transform3D(0, 0, 1, 0, 1, 0, -1, 0, 0, 7.8, 0.9, -0.4)`. Su +X local apunta a −Z global, así que
  transporta las cajas alejándolas de la línea principal.

---

## 5. La geometría: de dónde sale cada número

Las posiciones no son a ojo: salen de leer el código fuente de los componentes de OIP.

### 5.1 Altura de los haces

Un `DiffuseSensor` **no emite desde su origen**. En `src/DiffuseSensor/diffuse_sensor.gd`:

```gdscript
func _physics_process(_delta: float) -> void:
	var start_pos := global_transform.translated_local(Vector3(0, 0.25, 0.42)).origin
	...
	_ray_query.collision_mask = 8
```

El rayo nace en `(0, 0.25, 0.42)` en coordenadas locales del nodo y viaja hacia su **+Z local**.
El `collision_mask = 8` es la capa 4, `Box` — el sensor solo ve cajas, no la cinta ni el galpón.

Entonces, para poner un haz a una altura `H` sobre la superficie de la cinta:

```
posición_y_del_sensor = altura_de_la_cinta + H − 0.25
```

Verificación con los valores del `.tscn`:

| Sensor | y del nodo | Altura del haz sobre la cinta |
|---|---|---|
| `GatePresence` | 0.71 | 0.71 + 0.25 − 0.9 = **0.06 m** |
| `GateHeight` | 1.00 | 1.00 + 0.25 − 0.9 = **0.35 m** ← la altura de corte |
| `DivertEye` | 0.71 | **0.06 m** |

La traza de `tools/verify_height_sorter.gd` lo confirma midiendo en vivo:

```
--- geometria de los haces (origen -> fin) ---
   GatePresence  (5.00, 0.96, 0.42) -> (5.00, 0.96, -0.58)
   GateHeight    (5.00, 1.25, 0.42) -> (5.00, 1.25, -0.58)
   DivertEye     (8.05, 0.96, 0.42) -> (8.05, 0.96, -0.58)
```

0.96 − 0.9 = 0.06 y 1.25 − 0.9 = 0.35. Y en z los haces van de +0.42 a −0.58, o sea que cruzan
completo el ancho de la cinta (que va de −0.4 a +0.4).

### 5.2 Montaje del desviador

- **En Z:** `borde_de_la_cinta (0.4) + mitad_del_cuerpo (1.0635) + separación (0.05) = 1.5135`
- **En Y:** `altura_de_la_cinta (0.9) − 0.2 = 0.7`, donde 0.2 es la constante
  `ConveyorSnapFeatures.DIVERTER_Y_OFFSET` que OIP usa para encajar un desviador contra una cinta.

Con eso la paleta en reposo queda justo en el borde de la cinta (z ≈ 0.41) y con una carrera de
1.0 m llega a z ≈ −0.59, pasando el borde opuesto (−0.4). O sea: **barre todo el ancho de la cinta**,
que es lo que hace falta para que la caja salga completa y no quede trabada en el borde.

### 5.3 Alineación de la fotocélula de disparo

`DivertEye` está en x = 8.05: el centro de la paleta (7.797) más media caja (0.25).

Así, cuando el **borde delantero** de la caja corta el haz, la caja queda **centrada frente a la
paleta** y se puede empujar sin ningún retardo adicional. Ese es el motivo de que el actuador no
necesite un `TON` de espera antes de salir — solo uno para retraerse.

### 5.4 Por qué la separación entre la estación y el desviador importa

Hay **3.05 m** entre la estación de medición (x=5) y el disparo (x=8.05). A 1 m/s con cajas cada 2 s,
o sea cada 2 m, **siempre hay entre una y dos cajas viajando** entre el punto de medición y el punto
de actuación. Por eso hace falta una cola y no una sola variable. Se ve en la traza: la columna
`cola=` oscila entre 1 y 2.

---

## 6. El PLC, línea por línea

Archivo: [`demos/height_sorter/height_sorter.st`](demos/height_sorter/height_sorter.st). 3666
caracteres, Texto Estructurado IEC 61131-3.

### 6.1 Interfaz

```pascal
VAR_INPUT
    GatePresence : BOOL;    (* haz bajo  - lo corta toda caja       *)
    GateHeight   : BOOL;    (* haz alto  - solo lo cortan las altas *)
    DivertEye    : BOOL;    (* fotocelula de disparo del desviador  *)
END_VAR

VAR_OUTPUT
    DivertCmd : BOOL;       (* TRUE = paleta extendida *)
END_VAR
```

Tres entradas digitales, una salida digital. Los nombres coinciden exactamente con los `tag_name`
de la escena: así es como el runtime enlaza variable ↔ tag.

### 6.2 Estado interno

```pascal
VAR
    GateRise  : R_TRIG;     (* flanco: entra caja a la estacion *)
    GateFall  : F_TRIG;     (* flanco: sale caja de la estacion *)
    EyeRise   : R_TRIG;     (* flanco: llega caja al desviador  *)
    PushTimer : TON;        (* duracion del empuje              *)

    TallLatch : BOOL;                   (* la caja actual corto el haz alto *)
    Armed     : BOOL;                   (* hay una caja en curso en la estacion *)
    Fifo      : ARRAY [0..7] OF BOOL;   (* registro de desplazamiento       *)
    Pending   : INT;                    (* veredictos en transito           *)
    Verdict   : BOOL;                   (* veredicto desencolado este scan  *)
    i         : INT;

    Counted   : INT;        (* estadisticas para el monitor ST *)
    Diverted  : INT;
    Passed    : INT;
END_VAR
```

Todo bloque de función usado es **estándar IEC 61131-3**: `R_TRIG` (flanco de subida), `F_TRIG`
(flanco de bajada), `TON` (temporizador a la conexión). Nada propietario, nada inventado.

`Counted` / `Diverted` / `Passed` no participan del control: son contadores de producción, lo que en
un PLC real iría a un HMI. Acá se leen desde el monitor del ST Editor y desde la auditoría headless.

### 6.3 Detección de flancos

```pascal
GateRise(CLK := GatePresence);
GateFall(CLK := GatePresence);
EyeRise(CLK := DivertEye);
```

Se llaman **al principio del scan y siempre**, de forma incondicional. Es una regla básica de PLC:
un bloque de función con memoria debe llamarse una vez por scan, si no su estado interno se
desincroniza. `GateRise` y `GateFall` observan la misma señal: uno detecta que la caja **entra** a la
estación, el otro que **sale**.

### 6.4 Estación de medición

```pascal
IF GateRise.Q THEN
    TallLatch := FALSE;
    Armed := TRUE;
END_IF;
```

Entra una caja: se limpia el veredicto anterior y se arma la estación.

```pascal
IF GatePresence AND GateHeight THEN
    TallLatch := TRUE;
END_IF;
```

Este es el **enclavamiento (latch)** del veredicto. No se evalúa en un instante puntual sino durante
**toda la ventana** en que la caja está frente a la estación: basta con que corte el haz alto en
algún momento para quedar marcada como alta. Eso la hace inmune a rebotes de la caja sobre la cinta y
a que el haz se recupere un scan por vibración.

La condición pide `GatePresence AND GateHeight` y no solo `GateHeight` por robustez: se exige que
haya una caja presente para aceptar la lectura de altura.

```pascal
IF GateFall.Q AND Armed THEN
    Armed := FALSE;
    IF Pending < 8 THEN
        Fifo[Pending] := TallLatch;
        Pending := Pending + 1;
        Counted := Counted + 1;
    END_IF;
END_IF;
```

La caja terminó de pasar: el veredicto entra **al final de la cola**. Dos detalles:

- **`AND Armed`** exige haber visto antes el flanco de entrada. Es la guarda contra el flanco
  espurio del `F_TRIG` de este runtime — ver la sección [12](#12-el-bug-que-vale-la-pena-contar) —
  y además es buena práctica: un evento de "producto completo" debería exigir haber visto el
  producto entrar **y** salir, no solo salir.
- **`IF Pending < 8`** protege el `ARRAY [0..7]` contra desbordamiento. Si la cola se llenara — más
  de 8 cajas entre la medición y el desvío — el programa descarta en vez de escribir fuera de rango.

### 6.5 Desviador

```pascal
Verdict := FALSE;

IF EyeRise.Q THEN
    IF Pending > 0 THEN
        Verdict := Fifo[0];
        FOR i := 0 TO 6 DO
            Fifo[i] := Fifo[i + 1];
        END_FOR;
        Pending := Pending - 1;
        IF Verdict THEN
            Diverted := Diverted + 1;
        ELSE
            Passed := Passed + 1;
        END_IF;
    END_IF;
END_IF;
```

`Verdict := FALSE` al principio: es una variable de **un solo scan**, se reconstruye cada ciclo. Ese
patrón — limpiar y recalcular — evita que un valor viejo quede pegado.

Al llegar una caja al desviador se **desencola el veredicto más viejo** (`Fifo[0]`), se corre toda la
cola una posición y se decrementa `Pending`. Como las cajas no se adelantan entre sí en una cinta,
ese veredicto es siempre el suyo.

`IF Pending > 0` evita desencolar de una cola vacía (por ejemplo si alguien arranca la simulación con
cajas ya en la línea).

### 6.6 Actuador

```pascal
PushTimer(IN := DivertCmd, PT := T#1100ms);

IF Verdict THEN
    DivertCmd := TRUE;
ELSIF PushTimer.Q THEN
    DivertCmd := FALSE;
END_IF;
```

Un **temporizador de retracción**: la paleta sale al desencolar una caja alta y se retrae sola 1100 ms
después. El `TON` se alimenta de la propia salida (`IN := DivertCmd`), así que empieza a contar
cuando la paleta sale y se resetea solo cuando se retrae.

El `ELSIF` da prioridad a la orden de salir sobre la de retraerse: si llega otra caja alta mientras
la paleta está afuera, la salida se mantiene y el temporizador se recarga.

1100 ms es el único número con unidad de tiempo del programa, y conviene ser preciso sobre qué es:
**no es un tiempo de vuelo calibrado contra la distancia entre sensores** — eso es justamente lo que
el FIFO evita (§8). Es un **tiempo de permanencia del actuador**: cuánto se queda afuera la paleta.

Tiene que ser mayor que la carrera (0.3 s, el `divert_time` del `Diverter`) más lo que tarda la caja
en terminar de salir de la cinta, y menor que el intervalo entre cajas (2 s a 30 cajas/min) para que
la paleta esté retraída cuando llegue la siguiente. 1100 ms queda cómodo en esa ventana. Es un
parámetro mecánico del actuador, del mismo tipo que la carrera o la velocidad del cilindro, y se
ajustó empíricamente verificando con la auditoría que no queden cajas trabadas (`perdidas = 0`).

### 6.7 El ciclo completo, en una tabla

| Momento | Evento | Qué hace el PLC |
|---|---|---|
| caja entra a x=5 | `GatePresence` ↑ | `TallLatch := FALSE`, `Armed := TRUE` |
| mientras pasa | `GateHeight` = 1 en algún scan | `TallLatch := TRUE` |
| caja sale de x=5 | `GatePresence` ↓ | `Fifo[Pending] := TallLatch`, `Pending++`, `Counted++` |
| 3 s de viaje | — | nada; el veredicto espera en la cola |
| caja llega a x=8.05 | `DivertEye` ↑ | `Verdict := Fifo[0]`, corre la cola, `Pending--` |
| mismo scan | `Verdict = TRUE` | `DivertCmd := TRUE` → la paleta sale |
| +1100 ms | `PushTimer.Q` | `DivertCmd := FALSE` → la paleta vuelve |

---

## 7. Por qué DOS fotocélulas en la estación de medición

Una fotocélula difusa es un sensor **binario**: dice "hay algo en el haz" o "no hay nada". No mide
distancia ni altura.

Si pusiéramos **solo el haz alto** a 0.35 m, tendríamos esta ambigüedad:

| Situación real | Lectura del haz alto |
|---|---|
| No pasa ninguna caja | apagado |
| Pasa una caja **baja** | apagado |
| Pasa una caja **alta** | encendido |

Las dos primeras filas son indistinguibles. El PLC **no sabría que pasó una caja baja** y no podría
registrar su veredicto en la cola. Se perdería la correspondencia entre cajas y decisiones, y el
desviador terminaría empujando la caja equivocada.

Con las dos fotocélulas la tabla se vuelve completa:

| Haz bajo | Haz alto | Interpretación |
|---|---|---|
| apagado | apagado | no hay caja |
| **encendido** | apagado | caja **baja** |
| **encendido** | **encendido** | caja **alta** |

El haz bajo aporta el **evento** ("pasó una caja") y el haz alto el **atributo** ("y era alta"). Es
exactamente el rol que cumplen un *photo-eye* de presencia y un *height detector* en una sortadora
real.

Y es la clave de por qué esto **es medición y no adivinanza visible a simple vista**: en la escena se
ven los dos haces, y el bajo se pone rojo con toda caja mientras que el alto solo con las altas.

---

## 8. Por qué un FIFO y no un temporizador

La decisión de diseño más importante.

### El enfoque ingenuo

> "Cuando el sensor detecta una caja alta, esperá N segundos y empujá."

Con la línea a 1 m/s y 3.05 m entre la estación y el desviador, N = 3.05 s. Funciona… hasta que algo
cambia:

- Si alguien toca la velocidad de la cinta, **todos** los tiempos quedan mal.
- Si la cinta arranca y para, el cálculo se desfasa.
- Si las cajas vienen más juntas, hay **varias en tránsito a la vez** y un solo temporizador no
  alcanza. Acá pasa: siempre hay entre una y dos cajas entre la medición y el desvío (§5.4).

### El enfoque implementado

Separamos **qué se decidió** de **cuándo se ejecuta**:

```
   estación de medición                    desviador
          │                                    │
          ▼                                    ▼
     [ mide y encola ]  ──── FIFO ────►  [ desencola y actúa ]

     cola: [ alta ] [ baja ] [ alta ]
             ↑                    ↑
      la más nueva          la próxima en salir
```

La cola preserva el orden. Como las cajas no se adelantan entre sí en una cinta, el veredicto que
sale de la cola siempre corresponde a la caja que está llegando.

### Por qué esto es lo correcto

**No hay ningún tiempo de vuelo calibrado en el sistema.** El desfase entre medición y actuación lo
resuelve la física: la caja tarda lo que tarda, y el evento que dispara la acción es la llegada real
de la caja, no un cronómetro. Por eso se puede cambiar la velocidad de la cinta o el caudal en pleno
funcionamiento y sigue clasificando bien.

Esto es exactamente un **registro de desplazamiento** (*shift register*), el patrón estándar en PLCs
para seguimiento de producto en líneas de sortación.

### Se ve en la traza

De `tools/verify_height_sorter.gd` (`med`=medidas, `alt`=desviadas, `baj`=pasadas, `cola`=`Pending`;
`P`/`H`/`E` = sensores, `D` = paleta afuera):

```
t=  8.0 med=2.0 alt=0.0 baj=1.0 cola=1.0 PH.. | h0.28@8.8  h0.39@6.8  h0.49@4.9  h0.34@2.8
t=  8.5 med=3.0 alt=0.0 baj=1.0 cola=2.0 .... | h0.39@7.3  h0.49@5.3  h0.34@3.3  h0.30@1.3
t=  9.0 med=3.0 alt=0.0 baj=1.0 cola=2.0 ..E. | h0.39@7.8  h0.49@5.9  h0.34@3.8  h0.30@1.8
t=  9.5 med=3.0 alt=1.0 baj=1.0 cola=1.0 ...D | h0.39@8.0,-1.2 ...
```

- En **t=8.0** la caja de 0.49 m está llegando a x≈5 y corta los dos haces (`PH`) — es alta.
- En **t=8.5** terminó de pasar: `med` sube a 3 y `cola` a 2. Hay dos veredictos en tránsito.
- En **t=9.0** la caja de 0.39 m llega al desviador y corta `DivertEye` (`E`).
- En **t=9.5** se desencoló su veredicto (alta): `alt` sube a 1, `cola` baja a 1, la paleta está
  afuera (`D`) y la caja ya está en z = −1.2, fuera de la línea principal.

---

## 9. El único script propio de la escena

`demos/height_sorter/height_gate.gd`, montado en el nodo `GateSetup`. Tiene 40 líneas y **no contiene
lógica de control**:

```gdscript
func _apply() -> void:
	if gate_height == null or not gate_height.is_inside_tree():
		return
	gate_height.position.y = belt_surface_y + height_threshold - BEAM_RISE
```

Lo único que hace es aplicar la fórmula de §5.1 para ubicar el sensor de altura. Es el equivalente a
**aflojar el soporte del sensor y subirlo** en la línea real: ajuste mecánico, no control. El PLC no
se entera de nada, sigue leyendo el mismo bit.

Está hecho así a propósito para que la altura de corte sea un parámetro visible y modificable **en
vivo** desde el Inspector, sin tocar ni la escena ni el programa.

> Por qué `@tool` y por qué los `set`: el script corre también en el editor, así que mover el slider
> del Inspector reubica el sensor inmediatamente, sin necesidad de reiniciar la simulación.

---

## 10. Cómo se construyó

El orden en que se armó, que es también el orden en que conviene contarlo.

1. **Elegir los componentes de OIP.** `BeltConveyor`, `BoxSpawner`, `DiffuseSensor`, `Diverter`,
   `Despawner`, `Building`. Todos vienen en `parts/` del proyecto base.
2. **Leer el código fuente de cada componente** para saber dónde nace el haz de un sensor
   (`(0, 0.25, 0.42)` local), qué capa de colisión mira (`8` = cajas), cuál es el offset de montaje
   del desviador (`DIVERTER_Y_OFFSET = 0.2`). De ahí salen todas las coordenadas de §5.
3. **Armar la escena** con las cintas, el spawner y los despawners; verificar que las cajas nacen,
   viajan y desaparecen.
4. **Colocar los sensores** y comprobar con una traza headless que los haces cruzan la cinta a la
   altura correcta.
5. **Escribir el programa ST** y declarar el grupo de tags en `oip_data/tag_groups.cfg`.
6. **Cablear**: poner `enable_comms = true`, `tag_group_name = "ST"` y el `tag_name` correspondiente
   en cada uno de los cuatro componentes.
7. **Auditar** con `tools/audit_height_sorter.gd` y corregir. Acá apareció el bug del `F_TRIG`
   (§12), que la auditoría detectó como 34 errores sobre 56 cajas.
8. **Iterar** hasta 0 errores.

### Una decisión que se revirtió

La primera versión tenía la lógica en un script de GDScript (`height_sorter.gd`, un nodo `Sorter` en
la escena) con exactamente el mismo algoritmo. Funcionaba, pero **no es un gemelo digital**: si el
control vive dentro del simulador, no hay nada que transferir a una planta real.

Se reescribió el algoritmo en Texto Estructurado, se movió al Soft PLC y se borró el script. La
escena quedó siendo solo planta. Ese cambio es el que justifica el ejercicio.

### Herramienta auxiliar: `sync_st_to_scene.py`

Como el runtime ejecuta el metadato del `.tscn` y no el archivo `.st`, hace falta sincronizarlos.
El script escapa el texto del `.st` y lo inserta como
`metadata/oip_st_program = "..."` en la raíz de la escena:

```bash
python3 tools/sync_st_to_scene.py
# Embebido 3666 caracteres de ST en HeightSorter.tscn
```

Se corre **después** de editar el `.st`. En el sentido inverso (editar desde el dock del ST Editor)
hay que copiar a mano al `.st`.

---

## 11. Cómo se verificó

El sistema **no se validó mirando la pantalla**.

### 11.1 La auditoría

`tools/audit_height_sorter.gd` corre la simulación **headless** —sin ventana ni GPU— y audita en dos
niveles a la vez:

1. **La física:** recorre el árbol buscando nodos `Box`, sigue cada uno individualmente, y cuando
   desaparece registra por dónde salió (`z < −1.0` = rechazo, `x > 9.0` = línea principal) y lo
   contrasta contra la **altura real** de esa caja (`b.size.y`).
2. **El PLC:** lee los contadores internos del programa ST (`Counted`, `Diverted`, `Passed`,
   `Pending`) por la API de monitoreo del Soft PLC (`OIPComms.get_soft_plc_watch("ST")`).

```bash
# Windows
OIP_v4.7-rc1.exe --headless --path C:\OIP\default_project --script res://tools/audit_height_sorter.gd
```

Resultado sobre 120 segundos:

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

**Las dos mitades cierran entre sí:** el PLC midió 58 cajas, decidió 27 desvíos y 30 pasadas, y dejó
1 en tránsito (27 + 30 + 1 = 58). La física confirma 57 cajas con destino correcto y ninguna mal (la
diferencia con 58 es la caja que todavía estaba viajando cuando terminó la corrida).

Es una verificación **objetiva y reproducible**: cualquiera puede correr el comando. Las alturas son
aleatorias, así que los números exactos varían entre corridas; lo que no varía es
`clasificadas MAL = 0`.

### 11.2 Las otras dos herramientas

| Herramienta | Qué hace | Cuándo usarla |
|---|---|---|
| `tools/check_st.gd` | Compila el programa ST sin ejecutarlo, e imprime los grupos de tags registrados y el estado global de comms. | Después de tocar el `.st`, o para diagnosticar "el PLC no arranca". 2 s. |
| `tools/verify_height_sorter.gd` | Traza en vivo de 30 s: geometría de los haces + una línea cada 0.5 s con contadores del PLC, estado de los 3 sensores, comando al desviador y posición de cada caja. | Después de mover algo en la escena, para ver si un haz quedó mal alineado o el desviador dispara tarde. |

---

## 12. El bug que vale la pena contar

Durante la puesta en marcha, la clasificación salía **sistemáticamente invertida**: las cajas altas
seguían de largo y las bajas se rechazaban. 34 errores sobre 56 cajas.

La causa estaba en el bloque `F_TRIG` de este runtime (`oip-plc.js`):

```js
var FTrig = class {
    Q = false;
    #prev = true;        // <-- arranca en TRUE
    call(a) {
        const clk = bool$1(a.CLK ?? false);
        this.Q = !clk && this.#prev;
        this.#prev = clk;
    }
};
```

Comparado con `R_TRIG`, que arranca en `false`:

```js
var RTrig = class {
    Q = false;
    #prev = false;
    call(a) { ... this.Q = clk && !this.#prev; ... }
};
```

Con `CLK` en `FALSE` y `#prev` en `TRUE`, la **primera llamada al `F_TRIG` devuelve `Q = TRUE`**: un
flanco de bajada que nunca ocurrió. Eso encolaba un veredicto fantasma antes de que pasara la primera
caja, y a partir de ahí **cada caja recibía el veredicto de la anterior** — un corrimiento permanente
de una posición en el FIFO. Como las alturas son aleatorias, eso da ~50 % de error, que es
exactamente lo que medía la auditoría.

La solución es la guarda `Armed`: solo se acepta el flanco de salida si antes se vio el de entrada.

```pascal
IF GateRise.Q THEN
    TallLatch := FALSE;
    Armed := TRUE;
END_IF;

IF GateFall.Q AND Armed THEN
    Armed := FALSE;
    (* ... encolar ... *)
END_IF;
```

Dos cosas que decir sobre esto:

- **Es buena práctica de PLC más allá de este runtime.** Un evento de "producto completo" debería
  exigir haber visto el producto entrar **y** salir, no solo salir. La guarda también protege contra
  arrancar la simulación con una caja ya tapando el sensor.
- **Lo encontró la auditoría, no el ojo.** Mirando la escena a 1 m/s con cajas de altura parecida, un
  corrimiento de una posición es prácticamente invisible. Ese es el argumento a favor de verificar
  con un script en vez de con la vista.

---

## 13. Guion de la sustentación

Un orden que funciona, de ~8 minutos.

**1. El problema (1 min).** Línea de distribución, hay que sacar las cajas que exceden una altura, sin
detener la línea. Se mide en un lado y se actúa metros más adelante.

**2. La arquitectura (1 min).** Mostrar el diagrama de §3. Escena = planta, PLC = control, tags =
cableado. Recalcar: **el control no está en el simulador**.

**3. La escena corriendo (2 min).** Abrir `HeightSorter.tscn`, encuadrar `MainLine` con **F**, darle
**Start**. Señalar en orden:

| Dónde | Qué señalar |
|---|---|
| x=1, spawner | cajas de altura visiblemente distinta, una cada 2 s |
| x=5, estación | **dos haces**: verdes sin detección, rojos al cortarse |
| haz bajo | se pone rojo con **toda** caja |
| haz alto | se pone rojo **solo con las altas** ← esta es la discriminación, a simple vista |
| x≈7.8, desviador | la paleta sale y empuja; la lámpara verde se enciende mientras está extendida |
| línea de rechazo | las cajas altas se van por la cinta perpendicular |
| x=10.4 | las bajas siguen de largo y desaparecen |

**4. El programa de PLC (2 min).** Abrir el dock del **ST Editor**: ahí está el programa gobernando
la escena en ese momento. Señalar `VAR_INPUT` (las tres fotocélulas), `VAR_OUTPUT` (el comando), y
los bloques estándar `R_TRIG` / `F_TRIG` / `TON`. Después explicar el FIFO con el diagrama de §8.

**5. Demostrar que es configurable (1 min).** *El mejor momento de la demo.* Con la simulación
corriendo:

1. Clic en el nodo **GateSetup**.
2. En el Inspector, cambiar **`height_threshold`** de `0.35` a `0.25`.
3. El haz alto **baja en vivo** y de inmediato empiezan a rechazarse cajas que antes pasaban.

Aclarar el matiz antes de que lo pregunten: `GateSetup` **no es lógica de control**, es ajuste
mecánico (§9). También se puede tocar `speed` en `MainLine` o `boxes_per_minute` en `BoxSpawner` — y
la clasificación sigue siendo correcta, por lo de §8.

**6. La verificación (1 min).** Mostrar la salida de la auditoría headless (§11) y el bug del `F_TRIG`
(§12) como ejemplo de por qué se verifica con script y no con la vista.

---

## 14. Preguntas probables y cómo responderlas

**¿Dónde está la lógica de control?**
En `demos/height_sorter/height_sorter.st`, ejecutándose en el Soft PLC de OIP. La escena no tiene
lógica: los sensores publican bits y el desviador obedece un bit. El único script propio en la escena
(`GateSetup`) posiciona un sensor, que es ajuste mecánico, no control.

**¿Es realmente un PLC o es un "como si"?**
Es un runtime IEC 61131-3 completo. El programa está en Texto Estructurado estándar y usa solo
bloques de función estándar. Se compila y se ejecuta cíclicamente con un tiempo de scan de 50 ms.
Lo que no hay es hardware ni red industrial.

**¿Por qué no medís la altura con un sensor que dé el valor numérico?**
Porque no es lo que se usa en una línea real para esta tarea. Una fotocélula a altura fija es más
barata, más rápida y más robusta que un sensor de distancia, y para una decisión binaria es
suficiente. Si hiciera falta clasificar en tres o más rangos, se agregan más haces a distintas
alturas — el diseño escala sin cambiar la arquitectura.

**¿Por qué dos sensores en la estación y no uno?**
Ver §7. Con uno solo no se puede distinguir "pasó una caja baja" de "no pasó nada", y sin ese evento
no se puede llevar la cuenta.

**¿Por qué una cola y no un temporizador?**
Ver §8. Porque siempre hay más de una caja en tránsito entre la medición y el desvío, y porque un
temporizador ata la lógica a la velocidad de la cinta.

**¿Qué pasa si dos cajas van pegadas?**
El haz bajo no se apaga entre ellas, así que se registrarían como una sola. Es una limitación real y
conocida de este esquema; en una línea de verdad se resuelve con separación mecánica aguas arriba
(*singulator*). Acá el caudal está fijado en 30 cajas/min, que da 2 m de separación entre cajas de
0.5 m.

**¿Qué pasa si la cola se llena?**
El programa descarta (`IF Pending < 8`) en vez de escribir fuera del array. Con 3.05 m entre la
medición y el desvío harían falta más de 8 cajas en ese tramo para llegar ahí, o sea menos de 38 cm
entre cajas de 50 cm — físicamente imposible.

**¿Qué pasa con una caja justo en el límite de altura?**
Roza el haz y el resultado es indeterminado. Lo detectamos en una auditoría: una caja de 0.3500 m con
el haz a 0.350 m salió por la línea principal. No es un defecto de la lógica sino la física de
cualquier detector en su umbral. En producción se resuelve con una banda muerta o eligiendo un corte
que no coincida con ninguna medida nominal de producto.

**¿Esto funcionaría con un PLC real?**
Sí, y es el paso natural siguiente. Para migrarlo habría que cambiar el protocolo del grupo de tags
de `soft_plc` a Modbus TCP u OPC UA y apuntar al PLC real; el programa se carga en el PLC y la escena
queda como banco de pruebas *hardware-in-the-loop*. El programa no cambia.

**¿Cómo sabés que funciona y no es casualidad?**
Por la auditoría de §11: 120 s de simulación, cada caja seguida individualmente, 0 mal clasificadas,
y los contadores del PLC cerrando con la física. Además es reproducible con un comando.

**¿Por qué corre bajo wine?**
Open Industry Project no publica build de Linux; los releases son binarios de Windows. El soporte
está pedido en el issue #228 y hay un PR abierto (#232), ambos sin resolver. Verificamos que el
release de Windows corre bajo wine con aceleración Vulkan nativa, lo cual evitó tener que compilar el
motor entero desde fuente. **En Windows nada de esto hace falta**: se ejecuta el `.exe` directamente.

---

## 15. Limitaciones honestas

- **Clasificación binaria.** Un solo desviador, dos destinos. Para más categorías harían falta más
  haces y más desviadores en cascada.
- **Largo de caja fijo.** La alineación de `DivertEye` (§5.3) asume cajas de 0.5 m de largo. Si el
  largo variara, habría que reubicar el sensor o agregar un retardo proporcional.
- **Cajas pegadas.** El esquema no separa dos cajas que se toquen; las cuenta como una.
- **Soft PLC, no PLC físico.** El programa es IEC 61131-3 real, pero corre en el runtime integrado de
  OIP. No hay hardware ni red industrial de por medio.
- **Sin manejo de fallas.** No hay detección de atascos, ni caja caída, ni confirmación de que el
  empuje efectivamente sacó la caja. Un control de producción tendría un sensor de confirmación en la
  línea de rechazo y una alarma por discrepancia.
- **Sin HMI.** Los contadores viven dentro del PLC y se ven por el monitor del ST Editor o por la
  auditoría; no hay pantalla de operador.
- **Sin arranque/parada ni condiciones de seguridad.** Un PLC de producción tendría una cadena de
  paro de emergencia, permisivos de arranque y un modo manual.

---

## 16. Apéndice: trampas del motor

Cuatro cosas que fallan **en silencio** —sin error, sin warning— y costaron depuración. Van acá por
si alguien retoma la escena o arma una parecida.

### 16.1 `Box` es `top_level`

El nodo raíz de `parts/Box.tscn` tiene `top_level = true`, y `box_spawner.gd` hace
`box.position = position` usando la posición **local** del spawner. O sea: las cajas nacen en la
posición *local* del spawner interpretada como coordenada *global*.

Consecuencia: **el `BoxSpawner` tiene que colgar directo de la raíz de la escena.** Si se lo mete
dentro de otro nodo con transform, las cajas aparecen en un lugar que no tiene nada que ver — o caen
al vacío.

### 16.2 Las referencias a nodos exportadas necesitan `node_paths`

Un `@export var foo: Node3D` **no** se resuelve solo con `foo = NodePath("../Foo")` en el `.tscn`.
El tag del nodo tiene que declarar el array:

```gdscript
[node name="GateSetup" type="Node3D" parent="." node_paths=PackedStringArray("gate_height")]
script = ExtResource("6_gate")
gate_height = NodePath("../GateHeight")
```

Sin el `node_paths`, la propiedad llega en `null` **sin ningún error**. Lo mismo aplica al
`conveyor` del `BoxSpawner`.

### 16.3 La base de `Transform3D` se serializa por FILAS

Los 9 primeros floats de un `Transform3D(...)` en un `.tscn` son `row0, row1, row2`, mientras que
`basis.x` / `basis.y` / `basis.z` en GDScript son las **columnas**. Son transpuestos entre sí.

Un giro de +90° en Y (local +X → mundo −Z) se escribe:

```gdscript
Transform3D(0, 0, 1,  0, 1, 0,  -1, 0, 0,  ox, oy, oz)
```

Que es lo que tiene `RejectLine`. Escribirlo "como columnas" da el giro al revés y la cinta de
rechazo transporta hacia la línea principal en vez de alejarse.

### 16.4 El primer arranque del proyecto tira errores del addon de comms

Al importar el proyecto por primera vez, la GDExtension `oip_comms` todavía no está registrada
durante el escaneo inicial del filesystem, y aparecen cosas como:

```
ERROR: Failed to load library '.../~libOIP-COMMS.windows.template_debug.x86_64.dll'.
SCRIPT ERROR: Invalid access to property or key 'tag_group_initialized' on a base object of type 'OIPComms'.
   at: _ready (res://src/comms/soft_plc_bridge.gd:9)
```

**No es un problema de esta escena.** Se resuelve solo en la segunda apertura, cuando la extensión ya
quedó registrada. Si persiste después de reabrir, ahí sí hay algo mal.
