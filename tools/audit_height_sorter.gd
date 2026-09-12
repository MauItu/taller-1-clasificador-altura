extends SceneTree

const DURATION := 120.0
const THRESHOLD := 0.35
const GROUP := "ST"

var _t := 0.0
var _demo: Node3D
var _last := {}
var _alive := {}
var _ok := 0
var _bad := 0
var _lost := 0
var _started := false


func _process(delta: float) -> bool:
	_t += delta
	if not _started:
		if _t < 0.5:
			return false
		_demo = (load("res://demos/height_sorter/HeightSorter.tscn") as PackedScene).instantiate()
		root.add_child(_demo)
		# SoftPlcBridge busca el programa ST en la raiz de la escena actual.
		current_scene = _demo
		OIPComms.set_soft_plc_watch_enabled(GROUP, true)
		Simulation.start()
		_started = true
		_t = 0.0
		return false

	var now := {}
	for b: Node3D in _boxes():
		var rb := b.get_node_or_null("RigidBody3D") as Node3D
		if rb == null:
			continue
		var id := b.get_instance_id()
		now[id] = true
		_alive[id] = true
		_last[id] = [b.size.y, rb.global_position]
	for id: int in _alive.keys():
		if not now.has(id):
			_alive.erase(id)
			_judge(_last[id])
	if _t >= DURATION:
		_summary()
		return true
	return false


func _judge(d: Array) -> void:
	var h: float = d[0]
	var p: Vector3 = d[1]
	var tall := h > THRESHOLD
	var exited_reject := p.z < -1.0
	var exited_main := p.x > 9.0 and p.z > -1.0
	if not exited_reject and not exited_main:
		_lost += 1
		print("  ! caja h=%.2f perdida en (%.2f, %.2f, %.2f)" % [h, p.x, p.y, p.z])
		return
	if (tall and exited_reject) or (not tall and exited_main):
		_ok += 1
	else:
		_bad += 1
		print("  X caja h=%.2f (%s) salio por %s" % [
			h, "ALTA" if tall else "baja", "RECHAZO" if exited_reject else "LINEA"])


func _summary() -> void:
	var w: Dictionary = OIPComms.get_soft_plc_watch(GROUP)
	print("=========== AUDITORIA %.0f s ===========" % DURATION)
	print("-- contadores internos del PLC (programa ST) --")
	for k: String in ["Counted", "Diverted", "Passed", "Pending"]:
		print("   %-9s = %s" % [k, w.get(k, "(sin dato)")])
	print("-- destino real de las cajas (fisica de la escena) --")
	print("   clasificadas CORRECTAMENTE : %d" % _ok)
	print("   clasificadas MAL           : %d" % _bad)
	print("   perdidas                   : %d" % _lost)
	if w.is_empty():
		print("   ADVERTENCIA: el watch del PLC vino vacio")


func _boxes() -> Array:
	var out: Array = []
	_collect(_demo, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Box:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
