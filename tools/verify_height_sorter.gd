extends SceneTree

const DURATION := 26.0
const SCENE := "res://demos/height_sorter/HeightSorter.tscn"

var _t := 0.0
var _next := 0.5
var _demo: Node3D
var _once := false


func _initialize() -> void:
	_demo = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_demo)
	Simulation.start()


func _diag() -> void:
	var s := _demo.get_node("Sorter")
	print("DIAG sorter.gate_presence = ", s.gate_presence)
	print("DIAG sorter.gate_height   = ", s.gate_height)
	print("DIAG sorter.divert_eye    = ", s.divert_eye)
	print("DIAG sorter.diverter      = ", s.diverter)
	print("DIAG Simulation.is_running=%s is_paused=%s" % [Simulation.is_running(), Simulation.is_paused()])
	for n: String in ["GatePresence", "GateHeight", "DivertEye"]:
		var q: Node3D = _demo.get_node(n)
		var st: Vector3 = q.global_transform.translated_local(Vector3(0, 0.25, 0.42)).origin
		var en: Vector3 = st + q.global_transform.basis.z.normalized() * q.max_range
		print("DIAG BEAM %-13s (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)" % [n, st.x, st.y, st.z, en.x, en.y, en.z])


func _process(delta: float) -> bool:
	_t += delta
	if not _once:
		_once = true
		_diag()
	if _t >= _next:
		_next += 0.5
		_snap()
	return _t >= DURATION


func _snap() -> void:
	var s := _demo.get_node("Sorter")
	var parts: Array[String] = []
	for b: Node3D in _boxes():
		var rb := b.get_node_or_null("RigidBody3D") as Node3D
		if rb:
			parts.append("h%.2f@%.1f,%.1f" % [b.size.y, rb.global_position.x, rb.global_position.z])
	print("t=%5.1f med=%d alt=%d baj=%d %s%s%s | %s" % [
		_t, s.counted, s.diverted, s.passed,
		"P" if _demo.get_node("GatePresence").detected else ".",
		"H" if _demo.get_node("GateHeight").detected else ".",
		"E" if _demo.get_node("DivertEye").detected else ".",
		"  ".join(parts)])


func _boxes() -> Array:
	var out: Array = []
	_collect(_demo, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Box:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
