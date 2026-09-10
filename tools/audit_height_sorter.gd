extends SceneTree

const DURATION := 120.0
const THRESHOLD := 0.35

var _t := 0.0
var _demo: Node3D
var _last := {}
var _alive := {}
var _ok := 0
var _bad := 0
var _lost := 0


func _initialize() -> void:
	_demo = (load("res://demos/height_sorter/HeightSorter.tscn") as PackedScene).instantiate()
	root.add_child(_demo)
	Simulation.start()


func _process(delta: float) -> bool:
	_t += delta
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
	var correct := (tall and exited_reject) or (not tall and exited_main)
	if correct:
		_ok += 1
	else:
		_bad += 1
		print("  X caja h=%.2f (%s) salio por %s" % [
			h, "ALTA" if tall else "baja", "RECHAZO" if exited_reject else "LINEA"])


func _summary() -> void:
	var s := _demo.get_node("Sorter")
	print("=========== AUDITORIA %.0f s ===========" % DURATION)
	print("  medidas en la estacion : %d  (altas %d / bajas %d)" % [s.counted, s.diverted, s.passed])
	print("  cajas que completaron el recorrido: %d" % (_ok + _bad + _lost))
	print("  clasificadas CORRECTAMENTE : %d" % _ok)
	print("  clasificadas MAL           : %d" % _bad)
	print("  perdidas (ni linea ni rechazo): %d" % _lost)


func _boxes() -> Array:
	var out: Array = []
	_collect(_demo, out)
	return out


func _collect(n: Node, out: Array) -> void:
	if n is Box:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)
