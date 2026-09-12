@tool
class_name HeightGate
extends Node3D

## Ajuste mecanico de la estacion de medicion.
##
## Este nodo NO contiene logica de control: esa vive en el programa de PLC
## (Texto Estructurado, ver height_sorter.st). Lo unico que hace es ubicar el
## sensor de altura segun la altura de corte pedida, que es el equivalente a
## mover el soporte fisico del sensor en la linea real.

## Fotocelula alta de la estacion de medicion.
@export var gate_height: DiffuseSensor:
	set(value):
		gate_height = value
		_apply()

## Altura de corte, medida desde la superficie de la cinta.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var height_threshold: float = 0.35:
	set(value):
		height_threshold = value
		_apply()

## Altura de la superficie de la cinta en el espacio de la escena.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var belt_surface_y: float = 0.9:
	set(value):
		belt_surface_y = value
		_apply()

# El haz de un DiffuseSensor nace 0.25 m por encima del origen del nodo
# (ver DiffuseSensor._physics_process), asi que para poner el haz a la altura
# de corte hay que bajar el sensor esa misma cantidad.
const BEAM_RISE := 0.25


func _ready() -> void:
	_apply()


func _apply() -> void:
	if gate_height == null or not gate_height.is_inside_tree():
		return
	gate_height.position.y = belt_surface_y + height_threshold - BEAM_RISE
