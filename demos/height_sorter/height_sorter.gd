@tool
class_name HeightSorter
extends Node3D

## Clasificador de cajas por altura.
##
## Estación de medición (dos fotocélulas a distinta altura) + desviador aguas
## abajo. La fotocélula baja detecta el paso de cualquier caja; la alta solo la
## corta si la caja supera el umbral. El veredicto viaja en un registro de
## desplazamiento (FIFO) hasta que la fotocélula del desviador dispara el empuje,
## así que la clasificación no depende de la velocidad de la cinta.

## Fotocélula baja de la estación de medición: ve todas las cajas.
@export var gate_presence: DiffuseSensor
## Fotocélula alta de la estación: solo la cortan las cajas altas.
@export var gate_height: DiffuseSensor
## Fotocélula que dispara el empuje, alineada con la paleta del desviador.
@export var divert_eye: DiffuseSensor
## Desviador que expulsa las cajas altas.
@export var diverter: Diverter

@export_group("Discriminacion")
## Altura de corte, medida desde la superficie de la cinta. Las cajas mas altas
## que este valor cortan el haz alto y se expulsan.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var height_threshold: float = 0.35:
	set(value):
		height_threshold = value
		_apply_threshold()
## Altura de la superficie de la cinta en el espacio de la escena.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var belt_surface_y: float = 0.0:
	set(value):
		belt_surface_y = value
		_apply_threshold()

## Tiempo que la paleta permanece extendida antes de retraerse.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var push_duration: float = 1.1
## Retardo entre el disparo de la fotocélula y la extensión de la paleta.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var trigger_delay: float = 0.0
## Imprime cada caja clasificada en la consola de salida.
@export var log_events: bool = true

## Cajas medidas desde el arranque (solo lectura).
@export var counted: int = 0
## Cajas clasificadas como altas (solo lectura).
@export var diverted: int = 0
## Cajas clasificadas como bajas (solo lectura).
@export var passed: int = 0

# Veredictos pendientes entre la estación de medición y el desviador.
var _verdicts: Array[bool] = []
var _gate_prev: bool = false
var _gate_tall: bool = false
var _eye_prev: bool = false
var _delay_left: float = -1.0
var _push_left: float = -1.0
var _was_running: bool = false


func _validate_property(property: Dictionary) -> void:
	if property.name in ["counted", "diverted", "passed"]:
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


# El haz de un DiffuseSensor nace 0.25 m por encima del origen del nodo
# (ver DiffuseSensor._physics_process), asi que para poner el haz a la altura
# de corte hay que bajar el sensor esa misma cantidad.
const BEAM_RISE := 0.25


func _ready() -> void:
	_apply_threshold()
	_reset()


func _apply_threshold() -> void:
	if gate_height == null or not gate_height.is_inside_tree():
		return
	gate_height.position.y = belt_surface_y + height_threshold - BEAM_RISE


func _reset() -> void:
	_verdicts.clear()
	_gate_prev = false
	_gate_tall = false
	_eye_prev = false
	_delay_left = -1.0
	_push_left = -1.0
	counted = 0
	diverted = 0
	passed = 0
	_set_divert(false)


func _physics_process(delta: float) -> void:
	var running: bool = Simulation.is_running()
	if running != _was_running:
		_was_running = running
		_reset()
	if not running or Simulation.is_paused():
		return
	if gate_presence == null or gate_height == null or divert_eye == null or diverter == null:
		return

	_read_gate()
	_read_eye()
	_run_pusher(delta)


# La caja se mide durante toda su ventana frente a la estación: basta con que
# corte el haz alto en algún instante para que cuente como alta. El veredicto se
# encola cuando la caja termina de pasar.
func _read_gate() -> void:
	var present: bool = gate_presence.detected
	if present and not _gate_prev:
		_gate_tall = false
	if present and gate_height.detected:
		_gate_tall = true
	if not present and _gate_prev:
		_verdicts.push_back(_gate_tall)
		counted += 1
		if log_events:
			print("[HeightSorter] caja #%d medida: %s" % [counted, "ALTA" if _gate_tall else "baja"])
	_gate_prev = present


func _read_eye() -> void:
	var eye: bool = divert_eye.detected
	if eye and not _eye_prev:
		var tall: bool = _verdicts.pop_front() if not _verdicts.is_empty() else false
		if tall:
			diverted += 1
			_delay_left = trigger_delay
			if log_events:
				print("[HeightSorter] expulsando caja alta (total altas: %d)" % diverted)
		else:
			passed += 1
	_eye_prev = eye


func _run_pusher(delta: float) -> void:
	if _delay_left >= 0.0:
		_delay_left -= delta
		if _delay_left < 0.0:
			_set_divert(true)
			_push_left = push_duration
	elif _push_left >= 0.0:
		_push_left -= delta
		if _push_left < 0.0:
			_set_divert(false)


func _set_divert(state: bool) -> void:
	if diverter == null:
		return
	if diverter._diverted != state:
		diverter.toggle_divert()
