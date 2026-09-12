@tool
extends Node3D

## Entrega el programa ST al Soft PLC de forma determinista.
##
## POR QUE EXISTE ESTE NODO
##
## SoftPlcBridge (el autoload de OIP, src/comms/soft_plc_bridge.gd) alimenta el
## PLC una sola vez: cuando se inicializa el grupo de tags, leyendo la escena
## que este abierta en el editor EN ESE INSTANTE. El grupo se inicializa al
## arrancar el editor, asi que si uno abre el proyecto primero y la escena
## despues, el bridge no encuentra la escena, no entrega nada, y el PLC queda
## sin programa: las cajas salen, las cintas andan, los haces se cortan, pero
## DivertCmd nunca se energiza y todo pasa de largo. Tampoco hay reenvio al
## apretar Start (Simulation.started solo hace set_sim_running(true)).
##
## Este nodo cierra ese hueco reenviando el programa en los tres momentos en que
## puede hacer falta: al abrirse/instanciarse la escena, al inicializarse el
## grupo de tags, y al arrancar la simulacion. set_soft_plc_program reemplaza el
## programa, asi que reenviar de mas es inofensivo.
##
## El programa vive en el metadato 'oip_st_program' de este mismo nodo (la raiz
## de la escena), que es de donde lo leen tanto OIP como el dock del ST Editor.
## La fuente legible es height_sorter.st; tools/sync_st_to_scene.py la embebe.

const GROUP := "ST"
const PROGRAM_META := "oip_st_program"


func _ready() -> void:
	_conectar()
	_entregar()


func _conectar() -> void:
	# Durante el primer escaneo del proyecto la GDExtension de comms todavia no
	# esta registrada y OIPComms existe sin sus signals. De ahi los dos guardas.
	if Engine.has_singleton("OIPComms") and OIPComms.has_signal("tag_group_initialized"):
		if not OIPComms.tag_group_initialized.is_connected(_al_inicializar_grupo):
			OIPComms.tag_group_initialized.connect(_al_inicializar_grupo)

	if Engine.has_singleton("Simulation"):
		var sim: Object = Engine.get_singleton("Simulation")
		if not sim.is_connected("started", _entregar):
			sim.connect("started", _entregar)


func _al_inicializar_grupo(group_name: String) -> void:
	if group_name == GROUP:
		_entregar()


func _entregar() -> void:
	if not Engine.has_singleton("OIPComms"):
		return
	if not has_meta(PROGRAM_META):
		push_warning("StProgramLoader: la raiz '%s' no tiene el metadato '%s'" % [name, PROGRAM_META])
		return
	var src := String(get_meta(PROGRAM_META))
	if src.is_empty():
		push_warning("StProgramLoader: el metadato '%s' esta vacio" % PROGRAM_META)
		return
	OIPComms.set_soft_plc_program(GROUP, src)
