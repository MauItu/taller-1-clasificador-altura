extends SceneTree

## Traza en vivo del clasificador, headless.
##
## Cada 0.5 s imprime una linea con: los contadores internos del PLC, el estado
## de las tres fotocelulas, el comando al desviador y la posicion de cada caja
## en la cinta. Sirve para depurar cambios de geometria (ver si un haz queda mal
## alineado, si el desviador dispara tarde, etc.).
##
##   godot --headless --path /ruta/al/proyecto --script res://tools/verify_height_sorter.gd

const DURATION := 30.0
const SCENE := "res://demos/height_sorter/HeightSorter.tscn"
const GROUP := "ST"

var _t := 0.0
var _next := 0.5
var _demo: Node3D
var _started := false


func _process(delta: float) -> bool:
	_t += delta
	if not _started:
		# Se espera medio segundo a que los autoloads registren el grupo de tags
		# antes de instanciar la escena, si no SoftPlcBridge no encuentra el programa.
		if _t < 0.5:
			return false
		_demo = (load(SCENE) as PackedScene).instantiate()
		root.add_child(_demo)
		current_scene = _demo
		OIPComms.set_soft_plc_watch_enabled(GROUP, true)
		Simulation.start()
		_started = true
		_t = 0.0
		_geometria()
		return false

	if _t >= _next:
		_next += 0.5
		_snap()
	return _t >= DURATION


func _geometria() -> void:
	print("--- geometria de los haces (origen -> fin) ---")
	for n: String in ["GatePresence", "GateHeight", "DivertEye"]:
		var q: Node3D = _demo.get_node(n)
		# El rayo de un DiffuseSensor nace en (0, 0.25, 0.42) local y va hacia +Z local.
		var st: Vector3 = q.global_transform.translated_local(Vector3(0, 0.25, 0.42)).origin
		var en: Vector3 = st + q.global_transform.basis.z.normalized() * q.max_range
		print("   %-13s (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)" % [
			n, st.x, st.y, st.z, en.x, en.y, en.z])
	print("--- t | contadores del PLC | P=presencia H=alto E=disparo D=empuje | cajas (altura@x,z) ---")


func _snap() -> void:
	var w: Dictionary = OIPComms.get_soft_plc_watch(GROUP)
	var cajas: Array[String] = []
	for b: Node3D in _boxes():
		var rb := b.get_node_or_null("RigidBody3D") as Node3D
		if rb:
			cajas.append("h%.2f@%.1f,%.1f" % [b.size.y, rb.global_position.x, rb.global_position.z])
	print("t=%5.1f med=%s alt=%s baj=%s cola=%s %s%s%s%s | %s" % [
		_t,
		w.get("Counted", "?"), w.get("Diverted", "?"),
		w.get("Passed", "?"), w.get("Pending", "?"),
		"P" if _demo.get_node("GatePresence").detected else ".",
		"H" if _demo.get_node("GateHeight").detected else ".",
		"E" if _demo.get_node("DivertEye").detected else ".",
		"D" if _es_verdadero(w.get("DivertCmd")) else ".",
		"  ".join(cajas)])


func _es_verdadero(v: Variant) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return float(v) != 0.0
	return String(v) == "true"


func _boxes() -> Array:
	var out: Array = []
	_collect(_demo, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Box:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
