extends Node
## Trafic partagé du mode en ligne, simulé par le serveur sur le vrai réseau routier (sans physique) :
## tous les joueurs voient les mêmes voitures aux mêmes endroits. Les voitures roulent à droite,
## s'arrêtent aux feux rouges (même horloge que les joueurs) et gardent leurs distances.
##
## Conçu pour des centaines de joueurs :
## - densité locale : ~LOCAL_TARGET voitures autour de chaque groupe de joueurs (et non 14 par joueur) ;
## - simulation à SIM_HZ par seconde, tronçon de chaque voiture calculé une seule fois ;
## - grilles (voitures, joueurs, tronçons) pour ne jamais parcourir toute la ville ;
## - instantané compact : les 30 voitures les plus proches, coordonnées en entiers.

const DakarCity = preload("res://scripts/world/dakar_city.gd")
const TrafficLights = preload("res://scripts/world/traffic_lights.gd")

## Types envoyés sous forme d'indice (le client a la même liste)
const TYPE_NAMES := ["taxi", "clando", "car_rapide", "police", "coach", "bus", "jakarta", "ndiaga", "grosse_moto"]
const MIX := [0, 6, 1, 2, 8, 0, 6, 7, 1, 3, 6, 0, 2, 8, 1, 6, 7, 0, 8, 2, 4, 6, 1, 5, 8, 0, 6, 2]
const CRUISE := {
	"car_rapide": 8.5, "bus": 8.0, "coach": 8.5, "police": 11.0,
	"jakarta": 12.5, "grosse_moto": 16.0, "ndiaga": 8.5, "taxi": 11.0, "clando": 12.5
}
const MIN_ROAD := {"bus": 8.0, "coach": 8.0, "car_rapide": 6.0, "ndiaga": 6.0}
const LOCAL_TARGET := 24 ## voitures voulues autour d'un joueur
const LOCAL_RANGE := 250.0
const MAX_CARS := 900
const CAR_CELL := 125.0
const KEEP_RANGE := 320.0
const SEND_RANGE := 260.0
const SEND_MAX := 32
const STRIDE := 7 ## entiers par voiture dans un instantané
const SIM_HZ := 10.0

var city
var lights
var cars := {} ## id → {type, from, to, start, end, L, t, speed, pos, yaw}
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var _car_grid := {} ## cellule → identifiants des voitures
var _lanes := {} ## Vector2i(de, vers) → voitures sur ce tronçon
var _clean_t := 0.0
var _player_cells := {}
var _acc := 0.0
var _snap_cache := {} ## cellule → instantané partagé (vidé à chaque envoi)
var _rings: Array = [] ## décalages de cellules, du plus proche au plus loin
var _enc := {} ## id → voiture encodée


func _ready() -> void:
	_rng.randomize()
	city = DakarCity.new()
	add_child(city)
	city.build_data_only()
	lights = TrafficLights.new()
	lights.city = city
	lights.visuals = false
	add_child(lights)
	city.lights = lights
	print("Trafic partagé : %d nœuds routiers, %d carrefours à feux" % [city.node_pos.size(), city.signal_nodes.size()])


func tick(delta: float, players: Array) -> void:
	if players.is_empty():
		cars.clear()
		return
	_acc += delta
	var step := 1.0 / SIM_HZ
	if _acc < step:
		return
	var dt := minf(_acc, 0.25)
	_acc = 0.0
	# Cellules occupées par des joueurs (pour savoir vite si une voiture est loin de tout le monde)
	_player_cells.clear()
	for p in players:
		_player_cells[Vector2i(floori(p.x / KEEP_RANGE), floori(p.z / KEEP_RANGE))] = true
	_clean_t -= dt
	if _clean_t <= 0.0:
		_clean_t = 1.0
		for id in cars.keys():
			if not _near_players(cars[id]["pos"]):
				cars.erase(id)
		rebuild_grid()
	# Apparitions là où il manque des voitures (densité locale)
	var budget := 4 + players.size() / 40
	var tries := budget * 3
	while budget > 0 and tries > 0 and cars.size() < MAX_CARS:
		tries -= 1
		var near: Vector3 = players[_rng.randi() % players.size()]
		if _count_near(near) >= LOCAL_TARGET:
			continue
		if _spawn(near, players):
			budget -= 1
	# Voitures par tronçon : le véhicule de devant se trouve sans parcourir toute la ville
	_lanes.clear()
	for id in cars:
		var c: Dictionary = cars[id]
		var k := Vector2i(c["from"], c["to"])
		if not _lanes.has(k):
			_lanes[k] = []
		_lanes[k].append(c)
	for id in cars:
		_move(cars[id], dt)


func _near_players(p: Vector3) -> bool:
	var c := Vector2i(floori(p.x / KEEP_RANGE), floori(p.z / KEEP_RANGE))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if _player_cells.has(c + Vector2i(dx, dz)):
				return true
	return false


## Nombre de voitures autour d'un point (grille ; peut dater d'une seconde, c'est suffisant)
func _count_near(p: Vector3) -> int:
	var k0 := Vector2i(floori(p.x / CAR_CELL), floori(p.z / CAR_CELL))
	var r := int(ceil(LOCAL_RANGE / CAR_CELL))
	var n := 0
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			n += _car_grid.get(k0 + Vector2i(dx, dz), []).size()
	return n


func _spawn(near: Vector3, players: Array) -> bool:
	var a: int = city.random_node_around(near, 90.0, 250.0, "drive")
	var nb: PackedInt32Array = city.drive_neighbors(a)
	if nb.is_empty():
		return false
	var start: Vector3 = city.node_pos[a]
	if players.size() < 40:
		for q in players:
			if Vector2(start.x - q.x, start.z - q.z).length() < 70.0:
				return false # pas d'apparition sous les yeux d'un joueur
	var type: String = TYPE_NAMES[MIX[_rng.randi() % MIX.size()]]
	var to := nb[_rng.randi() % nb.size()]
	var c := {"type": type, "from": a, "to": to, "start": start, "t": 0.0, "speed": 6.0, "pos": start, "yaw": 0.0}
	_set_segment(c)
	var d: Vector3 = c["end"] - start
	c["yaw"] = atan2(-d.x, -d.z)
	cars[_next_id] = c
	var k := Vector2i(floori(start.x / CAR_CELL), floori(start.z / CAR_CELL))
	if not _car_grid.has(k):
		_car_grid[k] = []
	_car_grid[k].append(_next_id)
	_next_id += 1
	return true


## Fin du tronçon courant (calculée une seule fois par tronçon)
func _set_segment(c: Dictionary) -> void:
	var end: Vector3 = city.lane_point(c["from"], c["to"])
	c["end"] = end
	c["L"] = maxf((c["start"] as Vector3).distance_to(end), 0.01)


func _move(c: Dictionary, delta: float) -> void:
	var L: float = c["L"]
	var t: float = c["t"]
	var remaining := L - t
	var tgt: float = CRUISE.get(c["type"], 10.0)
	# Feu rouge au prochain carrefour : arrêt net et respect des feux
	var light: int = lights.state_for(c["to"], c["from"])
	if light != 0:
		var line: float = city.stop_distance(c["from"], c["to"]) + 2.0
		var j_rad: float = city.junction_radius(c["to"])
		if remaining < line + 28.0 and remaining > j_rad * 0.6:
			if light == 2 or remaining > line + 6.0:
				tgt = minf(tgt, maxf(0.0, (remaining - line) * 0.85))
				if remaining <= line + 0.4:
					tgt = 0.0
	tgt = minf(tgt, _sign_speed(c, remaining, delta))
	# Véhicule juste devant sur la même rue
	var lane: Array = _lanes.get(Vector2i(c["from"], c["to"]), [])
	if lane.size() > 1:
		for other in lane:
			if other == c:
				continue
			var gap: float = float(other["t"]) - t
			if gap > 0.0 and gap < 9.0:
				tgt = minf(tgt, maxf(0.0, (gap - 5.0) * 1.5))
	var sp: float = c["speed"]
	sp = move_toward(sp, tgt, (5.0 if tgt > sp else 12.0) * delta)
	c["speed"] = sp
	t += sp * delta
	if t >= L:
		c["t"] = t - L
		var nxt: int = c["next"] if int(c.get("next", -1)) >= 0 else city.next_node(c["from"], c["to"], "drive", MIN_ROAD.get(c["type"], 0.0))
		c["from"] = c["to"]
		c["to"] = nxt
		c["next"] = -1
		c["start"] = c["end"]
		_set_segment(c)
		t = c["t"]
		L = c["L"]
	else:
		c["t"] = t
	var start: Vector3 = c["start"]
	var end: Vector3 = c["end"]
	c["pos"] = start.lerp(end, clampf(t / L, 0.0, 1.0))
	var dx := end.x - start.x
	var dz := end.z - start.z
	if dx * dx + dz * dz > 0.01:
		c["yaw"] = lerp_angle(c["yaw"], atan2(-dx, -dz), 1.0 - exp(-6.0 * delta))


## Panneaux : STOP (arrêt complet, on repart quand le carrefour est libre), cédez le passage (on ralentit et
## on laisse passer les voitures prioritaires). Même logique que l'IA des voitures du jeu (vehicle.gd), y compris
## le coup d'œil au carrefour d'après.
func _sign_speed(c: Dictionary, remaining: float, delta: float) -> float:
	if int(c.get("next", -1)) < 0:
		c["next"] = city.next_node(c["from"], c["to"], "drive", MIN_ROAD.get(c["type"], 0.0))
	var v := _rule_target(c, c["from"], c["to"], remaining, delta)
	if remaining < 30.0 and c["next"] != c["from"]:
		v = minf(v, _rule_target(c, c["to"], c["next"], remaining + city.segment_length(c["to"], c["next"]), delta))
	return v


func _rule_target(c: Dictionary, from: int, to: int, dist: float, delta: float) -> float:
	var rule: int = city.rule(from, to)
	var key: int = from * 100003 + to
	if rule == 0 or c.get("done", -1) == key or c.get("done2", -1) == key:
		return INF
	var line: float = city.stop_distance(from, to) + 2.5
	if dist > line + 18.0:
		return INF
	if c.get("rule_key", -1) != key:
		c["rule_key"] = key
		c["rule_wait"] = 0.0
	if rule == DakarCity.RULE_STOP:
		if dist < line + 2.0 and float(c["speed"]) < 0.6:
			c["rule_wait"] = float(c["rule_wait"]) + delta
			if (c["rule_wait"] > 1.2 and _junction_clear(from, to)) or c["rule_wait"] > 7.0:
				_done(c, key)
				return INF
		return maxf(0.0, (dist - line) * 0.9)
	if dist < line - 0.5:
		_done(c, key)
		return INF
	if not _junction_clear(from, to):
		c["rule_wait"] = float(c["rule_wait"]) + delta
		if c["rule_wait"] < 7.0:
			return maxf(0.0, (dist - line) * 0.9)
	return 5.5


func _done(c: Dictionary, key: int) -> void:
	c["done2"] = c.get("done", -1)
	c["done"] = key


## Aucune voiture d'une autre branche n'arrive au carrefour (à moins de 14 m de son bord, en roulant)
func _junction_clear(from: int, to: int) -> bool:
	var near: float = city.junction_radius(to) + 14.0
	for o in city.drive_incoming(to):
		if o == from:
			continue
		for other in _lanes.get(Vector2i(o, to), []):
			if float(other["speed"]) > 1.0 and float(other["L"]) - float(other["t"]) < near:
				return false
	return true


## Grille des voitures
func rebuild_grid() -> void:
	_car_grid.clear()
	for id in cars:
		var p: Vector3 = cars[id]["pos"]
		var k := Vector2i(floori(p.x / CAR_CELL), floori(p.z / CAR_CELL))
		if not _car_grid.has(k):
			_car_grid[k] = []
		_car_grid[k].append(id)


## Début d'un envoi : chaque voiture est encodée une seule fois
func begin_send() -> void:
	_snap_cache.clear()
	_enc.clear()
	for id in cars:
		var c: Dictionary = cars[id]
		var pos: Vector3 = c["pos"]
		_enc[id] = PackedInt32Array([id, TYPE_NAMES.find(c["type"]), roundi(pos.x * 10.0), roundi(pos.z * 10.0),
			roundi(float(c["yaw"]) * 100.0), roundi(float(c["speed"]) * 10.0), roundi(pos.y * 10.0)])


## Les voitures les plus proches de la cellule du joueur, en entiers :
## STRIDE par voiture : id, type (indice), x*10, z*10, cap*100, vitesse*10, y*10.
## Le même instantané sert à tous les joueurs de la cellule.
func snapshot_for(p: Vector3) -> PackedInt32Array:
	var k0 := Vector2i(floori(p.x / CAR_CELL), floori(p.z / CAR_CELL))
	if _snap_cache.has(k0):
		return _snap_cache[k0]
	if _rings.is_empty():
		# Cellules à moins de SEND_RANGE, triées de la plus proche à la plus lointaine (calculé une fois)
		var r := int(ceil(SEND_RANGE / CAR_CELL))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var d := Vector2(dx, dz).length() * CAR_CELL
				if d <= SEND_RANGE + CAR_CELL * 0.5:
					_rings.append([d, Vector2i(dx, dz)])
		_rings.sort_custom(func(a, b): return a[0] < b[0])
	# On prend les voitures des cellules les plus proches d'abord, jusqu'à SEND_MAX (pas de tri)
	var out := PackedInt32Array()
	var n := 0
	for ring in _rings:
		for id in _car_grid.get(k0 + ring[1], []):
			if _enc.has(id):
				out.append_array(_enc[id])
				n += 1
				if n >= SEND_MAX:
					_snap_cache[k0] = out
					return out
	_snap_cache[k0] = out
	return out


## Un joueur s'empare d'une voiture (vol ou taxi hélé) : elle quitte le trafic partagé.
func claim(id: int) -> void:
	cars.erase(id)
