extends SceneTree

var _t := 0.0

func _process(delta: float) -> bool:
	_t += delta
	if _t < 0.5:
		return false
	print("tag groups registrados: ", OIPComms.get_tag_groups())
	print("enable_comms global: ", OIPComms.get_enable_comms())
	var src := FileAccess.get_file_as_string("res://demos/height_sorter/height_sorter.st")
	var err := String(OIPComms.compile_soft_plc("ST", src))
	if err.is_empty():
		print("RESULTADO: el programa ST compila correctamente")
	else:
		print("RESULTADO: ERROR -> " + err)
	return true
