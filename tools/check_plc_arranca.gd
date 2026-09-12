extends SceneTree

## Verifica que el PLC recibe el programa ST aunque SoftPlcBridge no encuentre
## la escena.
##
## QUE REPRODUCE
##
## SoftPlcBridge (el autoload de OIP) entrega el programa una sola vez, al
## inicializarse el grupo de tags, leyendo la escena abierta EN ESE INSTANTE.
## Abrir el proyecto primero y la escena despues deja al PLC sin programa: la
## escena parece viva pero el desviador nunca sale y todas las cajas altas se
## van por la linea principal.
##
## Este test instancia la escena SIN setear current_scene, que es la forma
## headless de provocar exactamente esa condicion (SoftPlcBridge emite
## "no scene root" y no entrega nada). Si el nodo raiz hace bien su trabajo
## —st_program_loader.gd— el PLC igual recibe el programa y los contadores
## avanzan.
##
##   godot --headless --path /ruta/al/proyecto --script res://tools/check_plc_arranca.gd
##
## Sale con codigo 1 si el PLC no arranco.

const DURATION := 30.0
const SCENE := "res://demos/height_sorter/HeightSorter.tscn"
const GROUP := "ST"

var _t := 0.0
var _demo: Node3D
var _started := false


func _process(delta: float) -> bool:
	_t += delta
	if not _started:
		if _t < 0.5:
			return false
		_demo = (load(SCENE) as PackedScene).instantiate()
		root.add_child(_demo)
		# A PROPOSITO no se setea current_scene: es lo que deja a SoftPlcBridge
		# sin escena, igual que al abrir el proyecto antes que la escena.
		OIPComms.set_soft_plc_watch_enabled(GROUP, true)
		Simulation.start()
		_started = true
		_t = 0.0
		return false

	if _t < DURATION:
		return false

	_resultado()
	return true


func _resultado() -> void:
	var w: Dictionary = OIPComms.get_soft_plc_watch(GROUP)
	print("=== el PLC arranca sin ayuda de SoftPlcBridge? ===")
	if w.is_empty():
		print("RESULTADO: FALLA - el watch del PLC vino vacio, el programa no se cargo")
		quit(1)
		return
	var counted := float(w.get("Counted", 0))
	var diverted := float(w.get("Diverted", 0))
	var passed := float(w.get("Passed", 0))
	print("   Counted = %s   Diverted = %s   Passed = %s" % [counted, diverted, passed])
	if counted <= 0.0:
		print("RESULTADO: FALLA - el PLC no conto ninguna caja, no recibio el programa")
		quit(1)
		return
	if diverted <= 0.0:
		print("RESULTADO: FALLA - el PLC no desvio ninguna caja en %.0f s" % DURATION)
		quit(1)
		return
	print("RESULTADO: OK - el PLC recibio el programa y esta clasificando")
