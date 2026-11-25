extends Node3D
## Feux tricolores des carrefours de Dakar (ceux d'OpenStreetMap et tous les croisements de grandes rues).
## Chaque carrefour alterne deux axes : vert 12 s, orange 3 s, tout rouge 1,5 s (le carrefour se vide), puis
## l'autre axe. Les voitures s'arrêtent à la ligne au rouge et à l'orange ; les feux piétons passent au vert
## quand les voitures de la rue à traverser ont le rouge.
## Pour les téléphones : les poteaux et les lampes ne sont construits qu'autour du joueur.

const Mk = preload("res://scripts/util/mk.gd")
const GREEN := 12.0
const YELLOW := 3.0
const ALL_RED := 1.5
const CYCLE := (GREEN + YELLOW + ALL_RED) * 2.0

var city
var player
var visuals := true ## false sur le serveur : seulement la logique des feux
var _signals := {} ## nœud → {offset, axis: Vector3, arms: [[position, direction, axe]], heads: [] ou [[axe, rouge, orange, vert, piéton rouge, piéton vert, racine]]}
var _t := 0.0
var _refresh := 0.0
var _mat := {}
var _body_mesh: ArrayMesh ## poteau, caisson, visières, feu piéton : un seul maillage partagé
var _range := 160.0
var _stop_signs: Array = [] ## [{pos, dir, node}]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for n in city.signal_nodes:
		var pos: Vector3 = city.node_pos[n]
		var arms: PackedInt32Array = city.drive_incoming(n) if city.has_method("drive_incoming") else city.drive_neighbors(n)
		if arms.is_empty():
			arms = city.walk_neighbors(n)
		if arms.is_empty():
			continue
		var axis := _dir(n, arms[0])
		var info := {"offset": rng.randf() * CYCLE, "axis": axis, "arms": [], "heads": []}
		if visuals:
			for nb in arms:
				var d := _dir(n, nb)
				var w: float = city.edge_width(n, nb)
				var right := Vector3(-d.z, 0, d.x)
				# Au coin, sur le trottoir à droite des voitures qui arrivent, juste avant la ligne d'arrêt
				var back: float = city.stop_distance(nb, n) + 0.8 if city.has_method("stop_distance") else w / 2.0 + 2.0
				var p := pos + d * back - right * (w / 2.0 + 0.7)
				p = city.clear_of_road(p, d, 14.0, 0.3)
				if p == Vector3.INF:
					continue
				info["arms"].append([p, d, _axis_of(info, d)])
		_signals[n] = info
		# Panneaux STOP (arrêts)
		if visuals and city.has_method("rule"):
			for key in city.rules:
				if city.rules[key] == city.RULE_STOP:
					var from_node: int = key.x
					var to_node: int = key.y
					if city.signal_nodes.has(to_node):
						continue
					var d := _dir(to_node, from_node)
					var w: float = city.edge_width(from_node, to_node)
					var right := Vector3(-d.z, 0, d.x)
					var back: float = city.stop_distance(from_node, to_node) + 0.5
					var p: Vector3 = city.node_pos[to_node] + d * back - right * (w / 2.0 + 0.6)
					p = city.clear_of_road(p, d, 12.0, 0.3)
					if p != Vector3.INF:
						_stop_signs.append({"pos": p, "dir": d, "node": null})
	if visuals:
		_mat = {
			"red": Mk.mat(Color("ff2020"), 4.0), "red_off": Mk.mat(Color("3a0d0d")),
			"yellow": Mk.mat(Color("ffb000"), 4.0), "yellow_off": Mk.mat(Color("3a2a05")),
			"green": Mk.mat(Color("22ff55"), 4.0), "green_off": Mk.mat(Color("0b2a12")),
		}
		_body_mesh = _make_body()
		_range = clampf(float(Graphics.get_value("car_range")) * 0.95, 120.0, 260.0)


func _dir(a: int, b: int) -> Vector3:
	var d: Vector3 = city.node_pos[b] - city.node_pos[a]
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else Vector3.FORWARD


func _axis_of(info: Dictionary, d: Vector3) -> int:
	var axis: Vector3 = info["axis"]
	return 0 if absf(d.dot(axis)) > 0.7071 else 1


## Poteau, caisson noir à fond jaune et visières, feu piéton sur le côté : un seul maillage, couleurs par sommet
func _make_body() -> ArrayMesh:
	var parts := [
		[Vector3(0, 1.6, 0), Vector3(0.12, 3.2, 0.12), Color("2b2b2b")],
		[Vector3(0, 3.1, 0), Vector3(0.36, 1.0, 0.28), Color("161616")],
		[Vector3(0, 3.1, -0.16), Vector3(0.52, 1.2, 0.04), Color("e8b800")],
		[Vector3(0.24, 2.3, 0), Vector3(0.2, 0.6, 0.24), Color("161616")],
	]
	for k in 3:
		parts.append([Vector3(0, 3.54 - k * 0.32, 0.2), Vector3(0.28, 0.03, 0.14), Color("101010")])
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for part in parts:
		var bm := BoxMesh.new()
		bm.size = part[1]
		var arr := bm.get_mesh_arrays()
		var base := verts.size()
		for v in arr[Mesh.ARRAY_VERTEX]:
			verts.append(v + part[0])
			cols.append(part[2])
		norms.append_array(arr[Mesh.ARRAY_NORMAL])
		for i in arr[Mesh.ARRAY_INDEX]:
			idx.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.6
	mesh.surface_set_material(0, m)
	return mesh


func _build_head(p: Vector3, facing: Vector3, axis: int) -> Array:
	var holder := Node3D.new()
	add_child(holder)
	holder.position = p + Vector3(0, 0.16, 0)
	holder.rotation.y = atan2(facing.x, facing.z)
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	holder.add_child(body)
	var lamps: Array = [axis]
	for k in 3:
		lamps.append(Mk.sphere(holder, 0.1, Vector3(0, 3.42 - k * 0.32, 0.15), Color("333333")))
	# Feu piéton : face au passage (sur le côté du poteau)
	for k in 2:
		var l := Mk.box(holder, Vector3(0.02, 0.2, 0.16), Vector3(0.35, 2.44 - k * 0.27, 0), Color("333333"))
		lamps.append(l)
	lamps.append(holder)
	return lamps


## 0 = vert, 1 = orange, 2 = rouge
func state(node: int, axis: int) -> int:
	var info = _signals.get(node)
	if info == null:
		return 0
	var t := fmod(_t + float(info["offset"]), CYCLE)
	if axis == 1:
		t = fmod(t + GREEN + YELLOW + ALL_RED, CYCLE)
	if t < GREEN:
		return 0
	if t < GREEN + YELLOW:
		return 1
	return 2


## État du feu pour un véhicule qui arrive au nœud `node` depuis `from_node` (0 vert, 1 orange, 2 rouge)
func state_for(node: int, from_node: int) -> int:
	if not _signals.has(node):
		return 0
	return state(node, _axis_of(_signals[node], _dir(node, from_node)))


func has_lights(node: int) -> bool:
	return _signals.has(node)


## Le feu est-il rouge (ou orange) pour un véhicule qui arrive au nœud `node` depuis `from_node` ?
func is_red_for(node: int, from_node: int) -> bool:
	if not _signals.has(node):
		return false
	return state(node, _axis_of(_signals[node], _dir(node, from_node))) != 0


## Variante avec une direction : d = vers l'endroit d'où vient le véhicule.
func is_red_dir(node: int, d: Vector3) -> bool:
	if not _signals.has(node):
		return false
	d.y = 0.0
	return state(node, _axis_of(_signals[node], d.normalized())) == 2


func nearest_signal(p: Vector3, max_dist: float) -> int:
	var best := -1
	var bd := max_dist
	for n in _signals:
		var d: float = Vector2(p.x - city.node_pos[n].x, p.z - city.node_pos[n].z).length()
		if d < bd:
			bd = d
			best = n
	return best


func _process(delta: float) -> void:
	# En ligne, tous les joueurs (et le serveur) partagent la même horloge : mêmes feux au même moment
	if Net.online or Net.is_server:
		_t = Net.clock()
	else:
		_t += delta
	_refresh -= delta
	if _refresh > 0.0 or not visuals or player == null:
		return
	_refresh = 0.25
	var pp: Vector3 = player.get_world_position()
	for n in _signals:
		var info: Dictionary = _signals[n]
		var dist: float = city.node_pos[n].distance_to(pp)
		var heads: Array = info["heads"]
		if dist > _range + 40.0:
			if not heads.is_empty():
				for head in heads:
					head[6].queue_free()
				heads.clear()
			continue
		if dist > _range:
			continue
		if heads.is_empty():
			for arm in info["arms"]:
				heads.append(_build_head(arm[0], arm[1], arm[2]))
		for head in heads:
			var s := state(n, head[0])
			head[1].material_override = _mat["red"] if s == 2 else _mat["red_off"]
			head[2].material_override = _mat["yellow"] if s == 1 else _mat["yellow_off"]
			head[3].material_override = _mat["green"] if s == 0 else _mat["green_off"]
			# Piétons : vert quand les voitures de cette rue ont le rouge (sauf les 2 dernières secondes)
			var walk: bool = s == 2 and _red_left(n, head[0]) > 2.0
			head[4].material_override = _mat["red_off"] if walk else _mat["red"]
			head[5].material_override = _mat["green"] if walk else _mat["green_off"]
	for sign_item in _stop_signs:
		var d_sign: float = (sign_item["pos"] as Vector3).distance_to(pp)
		if d_sign > _range + 30.0:
			if sign_item["node"] != null:
				sign_item["node"].queue_free()
				sign_item["node"] = null
		elif d_sign <= _range:
			if sign_item["node"] == null:
				sign_item["node"] = _build_stop_sign(sign_item["pos"], sign_item["dir"])


func _build_stop_sign(pos: Vector3, dir: Vector3) -> Node3D:
	var h := Node3D.new()
	add_child(h)
	h.position = pos + Vector3(0, 0.15, 0)
	h.rotation.y = atan2(dir.x, dir.z)
	Mk.cyl(h, 0.04, 0.04, 2.4, Vector3(0, 1.2, 0), Color("8d99ae"), false, 6)
	Mk.box(h, Vector3(0.65, 0.65, 0.03), Vector3(0, 2.4, 0), Color("d90429"))
	Mk.label(h, "STOP", Vector3(0, 2.4, 0.025), 16, Color.WHITE)
	return h


## Secondes de rouge qui restent pour l'axe donné
func _red_left(node: int, axis: int) -> float:
	var info = _signals.get(node)
	if info == null:
		return 0.0
	var t := fmod(_t + float(info["offset"]), CYCLE)
	if axis == 1:
		t = fmod(t + GREEN + YELLOW + ALL_RED, CYCLE)
	return CYCLE - t if t >= GREEN + YELLOW else 0.0


## Feu piéton vert pour traverser la rue dont les voitures roulent selon d (au carrefour node)
func walk_green(node: int, d: Vector3) -> bool:
	if not _signals.has(node):
		return true
	d.y = 0.0
	var axis := _axis_of(_signals[node], d.normalized())
	return state(node, axis) == 2 and _red_left(node, axis) > 2.0
