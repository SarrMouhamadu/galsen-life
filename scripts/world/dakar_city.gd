extends Node3D
## Le vrai Dakar (Plateau + Médina) généré depuis OpenStreetMap par tools/bake_dakar.gd.
## Charge la ville pré-assemblée et fournit le réseau routier au trafic, aux piétons et à la police.
## Données © les contributeurs d'OpenStreetMap (ODbL).

const Mk = preload("res://scripts/util/mk.gd")
const SidewalkPlan = preload("res://scripts/world/sidewalk_plan.gd")
const CITY_SCENE := "res://world/dakar/city.scn"
const DATA := "res://world/dakar/data.json"
const MINIMAP := "res://world/dakar/minimap.png"

const ONEWAY := 1
const DRIVE := 2
const WALK := 4
## Trottoirs surélevés (mêmes cotes que tools/bake_dakar.gd) : la collision du sol est plate, on leur ajoute
## une collision invisible pour que le joueur marche dessus au lieu de s'y enfoncer
const SIDEWALK_Y := 0.16
const SIDEWALK_W := 1.8
const SIDEWALK_LAYER := 32 ## seul le joueur à pied la touche (voitures et passants ne la voient pas)
const SIDEWALKS := "res://world/dakar/sidewalks.res" ## tracé des trottoirs (tools/bake_dakar.gd)
const SIDEWALK_RAMP := 0.3 ## bord en pente douce : on monte sur le trottoir sans buter

var places := {} ## nom → Vector3 (trottoir devant le lieu)
var place_info := {} ## nom → Array brut (cap, normale, centre)
var street_stalls: Array = [] ## étals de vendeurs dans la rue : {type, pos, face (vers la rue)}
var parking_spots: Array = []
var spawn_point := Vector3.ZERO
var bounds := Rect2()
var map_res := 2.0
var minimap_texture: Texture2D
var signal_nodes := PackedInt32Array() ## carrefours à feux
var services := {} ## lieu → type de service avec intérieur (banque, restaurant, station, hôpital, police, garage)
var lights = null ## contrôleur des feux (traffic_lights.gd)
const RULE_STOP := 1
const RULE_YIELD := 2
var rules := {} ## Vector2i(depuis, carrefour) → RULE_STOP / RULE_YIELD (panneau pour qui arrive par là)
var zebras := {} ## Vector2i(branche, carrefour) → true : passage piéton sur cette branche
var _drive_in: Array = [] ## nœud → nœuds d'où une voiture peut y arriver

var node_pos := PackedVector3Array()
var _drive_next: Array = [] ## nœud → PackedInt32Array (sens autorisés, véhicules)
var _dead_end := {} ## Vector2i(a, b) : le tronçon a → b mène dans une impasse
var _walk_next: Array = [] ## nœud → PackedInt32Array (tous sens, piétons)
var _edge := {} ## Vector2i(a, b) → [largeur, drapeaux, nom]
var _names: Array = []
var _districts: Array = []
var _drive_nodes := PackedInt32Array()
var _walk_nodes := PackedInt32Array()
var _astar := AStar3D.new()
var _astar_drive := AStar3D.new() ## vraies routes seulement (bus, taxis)
var _hash := {} ## cellule de 50 m → nœuds routiers
var rng := RandomNumberGenerator.new()


## Outil de mesure (tools/perf_probe.gd) : charge une autre version de la ville
static var scene_override := ""


func build() -> void:
	var scene: PackedScene = load(scene_override if scene_override != "" else CITY_SCENE)
	add_child(scene.instantiate())
	minimap_texture = load(MINIMAP)
	build_data_only()
	_build_job_decor()
	_build_sidewalk_collision()


## Réseau routier, lieux et feux sans aucun graphisme (utilisé aussi par le serveur en ligne).
func build_data_only() -> void:
	rng.seed = 221
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	var b: Array = data["bounds"]
	bounds = Rect2(b[0], b[1], b[2] - b[0], b[3] - b[1])
	map_res = data["map_res"]
	_names = data["names"]
	for d in data["districts"]:
		_districts.append([d[0], Vector3(d[1], 0, d[2])])
	_load_graph(data["nodes"], data["edges"])
	# Ponts et rampes : hauteur des nœuds (les voitures et les piétons montent dessus)
	var hts: Array = data.get("heights", [])
	for k in range(0, hts.size(), 2):
		var ni: int = hts[k]
		node_pos[ni].y = hts[k + 1]
		_astar.set_point_position(ni, node_pos[ni])
		_astar_drive.set_point_position(ni, node_pos[ni])
	services = data.get("services", {})
	for k in data["places"]:
		var p: Array = data["places"][k]
		places[k] = Vector3(p[0], 0.3, p[1])
		place_info[k] = p
	for n in data.get("signals", []):
		signal_nodes.append(int(n))
	var rl: Array = data.get("rules", [])
	for k in range(0, rl.size(), 3):
		rules[Vector2i(int(rl[k]), int(rl[k + 1]))] = int(rl[k + 2])
	var zb: Array = data.get("zebras", [])
	for k in range(0, zb.size(), 2):
		zebras[Vector2i(int(zb[k]), int(zb[k + 1]))] = true
	for s in data.get("stalls", []):
		street_stalls.append({"type": s[2], "pos": Vector3(s[0], float(s[5]) if s.size() > 5 else 0.0, s[1]), "face": Vector3(s[3], 0, s[4])})
	for s in data["parking"]:
		parking_spots.append({"type": s["type"], "pos": Vector3(s["pos"][0], 0.2, s["pos"][1]), "yaw": s["yaw"]})
	spawn_point = places.get("Place de l'Indépendance", node_pos[0]) + Vector3(0, 0.5, 0)
	for required in ["Hôpital Principal", "Commissariat", "Café Touba", "Chez Adja", "Dibiterie", "Restaurant Maïga", "Place de l'Indépendance"]:
		if not places.has(required):
			places[required] = node_pos[_drive_nodes[0]]
			place_info[required] = [0, 0, 0.0, 1.0, 0.0]
	# Réseau de Fast-Foods Restaurants Maïga dans les grands quartiers de Dakar
	const MAIGA_HUBS := {
		"Restaurant Maïga (Médina)": [-835.0, -782.0, -2.34, -0.70, 0.72],
		"Restaurant Maïga (Petersen)": [-98.0, -122.0, -1.80, -0.22, 0.97],
		"Restaurant Maïga (Marché Sandaga)": [220.0, 563.0, 0.91, 0.61, -0.79],
		"Restaurant Maïga (Marché Tilène)": [-1051.0, -760.0, -0.78, 0.71, 0.70],
		"Restaurant Maïga (Gare de Dakar)": [692.0, -53.0, 0.61, 0.82, -0.57],
		"Restaurant Maïga (Fass Delorme)": [-1097.0, -1624.0, -2.41, -0.74, 0.67],
		"Restaurant Maïga (Rebeuss)": [-97.0, -502.0, -0.03, 1.00, 0.03],
		"Restaurant Maïga (Grande Mosquée)": [-240.0, -377.0, -2.43, -0.76, 0.65],
		"Restaurant Maïga (Stade Iba Mar Diop)": [-816.0, -601.0, -0.77, 0.72, 0.70],
		"Restaurant Maïga (Marché Kermel)": [1191.0, 465.0, -1.55, 0.02, 1.00],
	}
	for m_name in MAIGA_HUBS:
		var d: Array = MAIGA_HUBS[m_name]
		places[m_name] = Vector3(d[0], 0.3, d[1])
		place_info[m_name] = [d[0], d[1], d[2], d[3], d[4]]
	if not places.has("Stade Iba Mar Diop"):
		places["Stade Iba Mar Diop"] = Vector3(-730.0, 0.3, -532.0)
		place_info["Stade Iba Mar Diop"] = [-730.0, -532.0, 0.0, 1.0, 0.0]


func _load_graph(nodes: Array, edges: Array) -> void:
	var n := nodes.size() / 2
	node_pos.resize(n)
	_drive_next.resize(n)
	_walk_next.resize(n)
	_drive_in.resize(n)
	for i in n:
		node_pos[i] = Vector3(nodes[i * 2], 0.0, nodes[i * 2 + 1])
		_drive_next[i] = PackedInt32Array()
		_walk_next[i] = PackedInt32Array()
		_drive_in[i] = PackedInt32Array()
		_astar.add_point(i, node_pos[i])
		_astar_drive.add_point(i, node_pos[i])
	var is_drive := {}
	var is_walk := {}
	for k in range(0, edges.size(), 5):
		var a: int = edges[k]
		var b: int = edges[k + 1]
		var w: float = edges[k + 2]
		var flags: int = edges[k + 3]
		var name_idx: int = edges[k + 4]
		_edge[Vector2i(a, b)] = [w, flags, name_idx]
		_edge[Vector2i(b, a)] = [w, flags, name_idx]
		if (flags & WALK) != 0:
			_walk_next[a].append(b)
			_walk_next[b].append(a)
			is_walk[a] = true
			is_walk[b] = true
		# La police emprunte toutes les rues ; le trafic ordinaire seulement les vraies routes.
		var oneway := (flags & ONEWAY) != 0
		_astar.connect_points(a, b, not oneway)
		if (flags & DRIVE) != 0:
			_astar_drive.connect_points(a, b, not oneway)
			_drive_next[a].append(b)
			_drive_in[b].append(a)
			is_drive[a] = true
			if not oneway:
				_drive_next[b].append(a)
				_drive_in[a].append(b)
				is_drive[b] = true
	for i in n:
		if is_drive.has(i):
			_drive_nodes.append(i)
		if is_walk.has(i):
			_walk_nodes.append(i)
		var cell := _cell_of(node_pos[i])
		if not _hash.has(cell):
			_hash[cell] = PackedInt32Array()
		_hash[cell].append(i)
	_mark_dead_ends()


## Tronçons qui mènent dans une impasse (on y entre en a → b) : les voitures du trafic les évitent,
## sinon elles doivent y faire demi-tour (impossible pour un car dans une ruelle)
func _mark_dead_ends() -> void:
	var nbs := func(i: int) -> Array:
		var out := {}
		for o in _drive_next[i]:
			out[o] = true
		for o in _drive_in[i]:
			out[o] = true
		return out.keys()
	for i in _drive_nodes:
		var nb: Array = nbs.call(i)
		if nb.size() != 1:
			continue
		var cur: int = i
		var prev: int = nb[0]
		for step in 60:
			_dead_end[Vector2i(prev, cur)] = true
			var pn: Array = nbs.call(prev)
			if pn.size() != 2:
				break
			var nxt: int = pn[0] if pn[1] == cur else pn[1]
			cur = prev
			prev = nxt


# --- Chaussée : un objet (panneau, abribus, feu, lampadaire) ne doit jamais s'y trouver ---

const ROAD_CELL := 25.0
var _road_grid := {} ## cellule de 25 m → PackedInt32Array de paires de nœuds (a, b) des tronçons carrossables


func _build_road_grid() -> void:
	_road_grid.clear()
	for key in _edge:
		if key.x > key.y:
			continue
		var info: Array = _edge[key]
		if (int(info[1]) & DRIVE) == 0:
			continue
		var pa := node_pos[key.x]
		var pb := node_pos[key.y]
		var r: float = float(info[0]) / 2.0 + 1.0
		var x0 := floori((minf(pa.x, pb.x) - r) / ROAD_CELL)
		var x1 := floori((maxf(pa.x, pb.x) + r) / ROAD_CELL)
		var z0 := floori((minf(pa.z, pb.z) - r) / ROAD_CELL)
		var z1 := floori((maxf(pa.z, pb.z) + r) / ROAD_CELL)
		for gx in range(x0, x1 + 1):
			for gz in range(z0, z1 + 1):
				var cell := Vector2i(gx, gz)
				if not _road_grid.has(cell):
					_road_grid[cell] = PackedInt32Array()
				_road_grid[cell].append(key.x)
				_road_grid[cell].append(key.y)


## Vrai si p est sur une chaussée (à moins de `margin` mètres du bord), carrefours compris.
func in_roadway(p: Vector3, margin := 0.3) -> bool:
	if _road_grid.is_empty():
		_build_road_grid()
	var cell := Vector2i(floori(p.x / ROAD_CELL), floori(p.z / ROAD_CELL))
	var list: PackedInt32Array = _road_grid.get(cell, PackedInt32Array())
	var q := Vector2(p.x, p.z)
	for k in range(0, list.size(), 2):
		var a := node_pos[list[k]]
		var b := node_pos[list[k + 1]]
		var half: float = edge_width(list[k], list[k + 1]) / 2.0 + margin
		var pt := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if pt.distance_to(q) < half:
			return true
	# Carrefours : disque de la largeur de la plus grande rue
	for k in range(0, list.size(), 2):
		for ni: int in [list[k], list[k + 1]]:
			var np: Vector3 = node_pos[ni]
			if Vector2(np.x, np.z).distance_to(q) < _node_radius(ni) + margin:
				return true
	return false


func _node_radius(n: int) -> float:
	var r := 0.0
	for o in _drive_next[n]:
		r = maxf(r, edge_width(n, o) / 2.0)
	for o in _walk_next[n]:
		if _edge.has(Vector2i(n, o)) and (int(_edge[Vector2i(n, o)][1]) & DRIVE) != 0:
			r = maxf(r, edge_width(n, o) / 2.0)
	return r


## Le point le plus proche de p, le long de la direction `along`, qui n'est pas sur la chaussée
## (essais tous les mètres jusqu'à max_shift). Vector3.INF si aucun.
func clear_of_road(p: Vector3, along: Vector3, max_shift := 15.0, margin := 0.3) -> Vector3:
	if not in_roadway(p, margin):
		return p
	along.y = 0.0
	along = along.normalized() if along.length() > 0.01 else Vector3.RIGHT
	var s := 1.0
	while s <= max_shift:
		for sg: float in [1.0, -1.0]:
			var c: Vector3 = p + along * s * sg
			if not in_roadway(c, margin):
				return c
		s += 1.0
	return Vector3.INF


## Recule un objet posé au bord de la rue (emprise de rayon r) pour qu'il ne morde plus sur la chaussée :
## d'abord vers les façades (n), puis le long du trottoir. Rend p tel quel s'il est déjà dégagé.
func off_road(p: Vector3, n: Vector3, r: float) -> Vector3:
	if not in_roadway(p, r):
		return p
	n.y = 0.0
	if n.length() > 0.01:
		n = n.normalized()
		var s := 0.5
		while s <= 5.0:
			if not in_roadway(p + n * s, r):
				return p + n * s
			s += 0.5
	var along := Vector3(-n.z, 0, n.x) if n.length() > 0.01 else Vector3.RIGHT
	var c := clear_of_road(p, along, 12.0, r)
	return p if c == Vector3.INF else c


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / 50.0), floori(p.z / 50.0))


# --- Requêtes sur le réseau ------------------------------------------------------

func edge_width(a: int, b: int) -> float:
	var e = _edge.get(Vector2i(a, b))
	return e[0] if e != null else 6.0


func is_oneway(a: int, b: int) -> bool:
	var e = _edge.get(Vector2i(a, b))
	return e != null and (e[1] & ONEWAY) != 0


func street_name(a: int, b: int) -> String:
	var e = _edge.get(Vector2i(a, b))
	if e == null or e[2] < 0:
		return ""
	return _names[e[2]]


func nearest_node(p: Vector3, mode := "drive") -> int:
	var c := _cell_of(p)
	var best := -1
	var bd := INF
	for r in 3:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var key := c + Vector2i(dx, dz)
				if not _hash.has(key):
					continue
				for i in _hash[key]:
					if mode == "drive" and _drive_next[i].is_empty():
						continue
					if mode == "walk" and _walk_next[i].is_empty():
						continue
					var d := node_pos[i].distance_squared_to(p)
					if d < bd:
						bd = d
						best = i
		if best != -1:
			return best
	return _drive_nodes[0] if mode == "drive" else _walk_nodes[0]


## Un nœud au hasard entre min_d et max_d mètres de p.
func random_node_around(p: Vector3, min_d: float, max_d: float, mode := "drive") -> int:
	var pool := _drive_nodes if mode == "drive" else _walk_nodes
	for attempt in 80:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(min_d, max_d)
		var guess := p + Vector3(cos(ang), 0, sin(ang)) * dist
		if not bounds.has_point(Vector2(guess.x, guess.z)):
			continue
		var i := nearest_node(guess, mode)
		var d := _flat(node_pos[i], p)
		if d >= min_d and d <= max_d:
			return i
	return pool[rng.randi() % pool.size()]


## Tronçon suivant au hasard (sans demi-tour sauf impasse). min_width évite les rues trop étroites.
func next_node(from: int, to: int, mode: String, min_width := 0.0) -> int:
	var options: PackedInt32Array = _drive_next[to] if mode == "drive" else _walk_next[to]
	if options.is_empty():
		return from
	var good := PackedInt32Array()
	var wide := PackedInt32Array()
	var open := PackedInt32Array() ## véhicules : pas dans une impasse
	for o in options:
		if o == from:
			continue
		good.append(o)
		if mode == "drive" and not _dead_end.has(Vector2i(to, o)):
			open.append(o)
		if edge_width(to, o) >= min_width:
			wide.append(o)
	if mode == "drive" and not open.is_empty():
		var open_wide := PackedInt32Array()
		for o in open:
			if edge_width(to, o) >= min_width:
				open_wide.append(o)
		var pick := open_wide if not open_wide.is_empty() else open
		return pick[rng.randi() % pick.size()]
	if not wide.is_empty():
		return wide[rng.randi() % wide.size()]
	if not good.is_empty():
		return good[rng.randi() % good.size()]
	return options[0]

func is_dead_end(a: int, b: int) -> bool:
	return _dead_end.has(Vector2i(a, b))


func drive_neighbors(i: int) -> PackedInt32Array:
	return _drive_next[i]


func walk_neighbors(i: int) -> PackedInt32Array:
	return _walk_next[i]


## Nœuds d'où une voiture peut arriver au nœud i
func drive_incoming(i: int) -> PackedInt32Array:
	return _drive_in[i]


## Panneau pour qui arrive au carrefour `to` en venant de `from` : 0 (prioritaire), RULE_STOP, RULE_YIELD
func rule(from: int, to: int) -> int:
	return rules.get(Vector2i(from, to), 0)


## Distance entre le centre du carrefour et la ligne d'arrêt (derrière le passage piéton s'il y en a un)
func stop_distance(from: int, to: int) -> float:
	return _node_radius(to) + (3.9 if zebras.has(Vector2i(from, to)) else 0.5)


## Rayon du carrefour (demi-largeur de la plus grande rue qui y arrive)
func junction_radius(n: int) -> float:
	return _node_radius(n)


## Point visé par un véhicule sur le tronçon a → b : voie de droite si la rue est à double sens.
func lane_point(a: int, b: int) -> Vector3:
	var pa := node_pos[a]
	var pb := node_pos[b]
	if is_oneway(a, b):
		return pb
	var d := (pb - pa)
	d.y = 0.0
	if d.length() < 0.01:
		return pb
	d = d.normalized()
	return pb + Vector3(-d.z, 0, d.x) * (edge_width(a, b) * 0.25)


## Point sur le trottoir (côté `side` = 1 droite, -1 gauche) à la distance t du nœud a.
func sidewalk_point(a: int, b: int, t: float, side: int) -> Vector3:
	var pa := node_pos[a]
	var pb := node_pos[b]
	var d := pb - pa
	var L := maxf(d.length(), 0.01)
	d /= L
	# Sur un pont il n'y a pas de trottoir : on marche sur le bord du tablier
	var raised := pa.y > 0.5 or pb.y > 0.5
	var off := edge_width(a, b) * 0.5 + (-0.4 if raised else 0.9)
	return pa + d * clampf(t, 0.0, L) + Vector3(-d.z, 0, d.x) * side * off + Vector3(0, 0.07 if raised else 0.16, 0)


func segment_length(a: int, b: int) -> float:
	return node_pos[a].distance_to(node_pos[b])


## Itinéraire (positions) entre deux points, en suivant les rues.
## drive_only : uniquement les vraies routes (pas les ruelles de service ni les rues piétonnes).
func route(from: Vector3, to: Vector3, drive_only := false) -> PackedVector3Array:
	if drive_only:
		return _astar_drive.get_point_path(nearest_node(from, "drive"), nearest_node(to, "drive"))
	return _astar.get_point_path(nearest_node(from, "any"), nearest_node(to, "any"))


func district_at(p: Vector3) -> String:
	var best := "Dakar"
	var bd := INF
	for d in _districts:
		var dd := _flat(p, d[1])
		if dd < bd:
			bd = dd
			best = d[0]
	if p.x < bounds.position.x or p.z < bounds.position.y or p.x > bounds.end.x or p.z > bounds.end.y:
		return "Dakar"
	return best


## Une vraie adresse (rue nommée ou lieu connu) entre min_d et max_d mètres.
func random_address(near: Vector3, min_d: float, max_d: float) -> Dictionary:
	for attempt in 60:
		if rng.randf() < 0.3:
			var keys := places.keys()
			var k: String = keys[rng.randi() % keys.size()]
			var pp: Vector3 = places[k]
			var dd := _flat(pp, near)
			if dd >= min_d and dd <= max_d:
				return {"name": k, "pos": pp}
			continue
		var a := random_node_around(near, min_d, max_d, "drive")
		var nb: PackedInt32Array = _drive_next[a]
		if nb.is_empty():
			continue
		var b: int = nb[0]
		var street := street_name(a, b)
		if street == "":
			continue
		var pos := sidewalk_point(a, b, segment_length(a, b) * 0.5, 1)
		return {"name": "%s, %s" % [street, district_at(pos)], "pos": pos}
	return {"name": "Place de l'Indépendance", "pos": places["Place de l'Indépendance"]}


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Collision des trottoirs : dessus à SIDEWALK_Y, bords en pente vers la chaussée et aux carrefours
func _build_sidewalk_collision() -> void:
	# Tracé enregistré par le baker (le même que les trottoirs qu'on voit) ; sinon recalculé ici
	var pl: Dictionary = SidewalkPlan.load_saved(SIDEWALKS)
	if pl.is_empty():
		pl = _plan_sidewalks()
	var faces := PackedVector3Array()
	_add_sidewalk_faces(pl, faces)
	if faces.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "TrottoirsCollision"
	body.collision_layer = SIDEWALK_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _plan_sidewalks() -> Dictionary:
	var segs: Array = []
	for key in _edge:
		if key.x > key.y:
			continue
		var info: Array = _edge[key]
		var f := int(info[1])
		segs.append([key.x, key.y, float(info[0]), (f & DRIVE) != 0 and (f & WALK) != 0, (f & DRIVE) != 0,
			node_pos[key.x].y <= 0.01 and node_pos[key.y].y <= 0.01])
	var nodes := PackedVector2Array()
	nodes.resize(node_pos.size())
	for k in node_pos.size():
		nodes[k] = Vector2(node_pos[k].x, node_pos[k].z)
	return SidewalkPlan.plan(nodes, segs)


func _add_sidewalk_faces(pl: Dictionary, faces: PackedVector3Array) -> void:
	for r in pl["runs"]:
		var sa: Vector2 = r["a"]
		var sb: Vector2 = r["b"]
		var d: Vector2 = r["d"]
		var n: Vector2 = r["n"]
		var w: float = r["w"]
		var side: int = r["side"]
		var inner: Vector2 = n * side * (w / 2.0) # bord côté chaussée
		var outer: Vector2 = n * side * (w / 2.0 + SIDEWALK_W)
		var rr: Vector2 = n * side * -SIDEWALK_RAMP
		var e := d * SIDEWALK_RAMP
		var p0 := _v3(sa + inner, SIDEWALK_Y)
		var p1 := _v3(sb + inner, SIDEWALK_Y)
		var p2 := _v3(sb + outer, SIDEWALK_Y)
		var p3 := _v3(sa + outer, SIDEWALK_Y)
		_quad(faces, p0, p1, p2, p3)
		# Pente côté chaussée et aux deux bouts
		_quad(faces, _v3(sa + inner + rr, 0.0), _v3(sb + inner + rr, 0.0), p1, p0)
		_quad(faces, _v3(sa + inner - e, 0.0), p0, p3, _v3(sa + outer - e, 0.0))
		_quad(faces, p1, _v3(sb + inner + e, 0.0), _v3(sb + outer + e, 0.0), p2)
	# Coins des carrefours : dessus et pente côté chaussée
	for c in pl["corners"]:
		var poly: PackedVector2Array = c["poly"]
		var idx := Geometry2D.triangulate_polygon(poly)
		for k in range(0, idx.size(), 3):
			faces.append_array([_v3(poly[idx[k]], SIDEWALK_Y), _v3(poly[idx[k + 1]], SIDEWALK_Y), _v3(poly[idx[k + 2]], SIDEWALK_Y)])
		var cen := (poly[0] + poly[1] + poly[2] + poly[3] + poly[4] + poly[5]) / 6.0
		for k in 2:
			var q0: Vector2 = poly[k]
			var q1: Vector2 = poly[k + 1]
			var out0: Vector2 = (q0 - cen).normalized() * SIDEWALK_RAMP
			var out1: Vector2 = (q1 - cen).normalized() * SIDEWALK_RAMP
			_quad(faces, _v3(q0 + out0, 0.0), _v3(q1 + out1, 0.0), _v3(q1, SIDEWALK_Y), _v3(q0, SIDEWALK_Y))


static func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _quad(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	faces.append_array([a, b, c, a, c, d])


# --- Petits décors des métiers ---------------------------------------------------

func _build_job_decor() -> void:
	_stall("Café Touba", Color("6f4518"))
	_stall("Chez Adja", Color("e76f51"))
	_stall("Dibiterie", Color("9d0208"))
	_stall_maiga("Restaurant Maïga", "StallMaiga")
	var idx := 1
	for p_name in places.keys():
		if "Restaurant Maïga" in p_name and p_name != "Restaurant Maïga":
			_stall_maiga(p_name, "StallMaiga_%d" % idx)
			idx += 1
	_build_kiosks_and_signs()
	_build_urban_decor()


func _build_kiosks_and_signs() -> void:
	# Kiosques Wave & Orange Money dans les carrefours clés de Dakar
	if places.has("Place de l'Indépendance"):
		var p_indep: Vector3 = places["Place de l'Indépendance"]
		_kiosk(p_indep + Vector3(8.0, 0, 12.0), 0.4, "wave")
		_kiosk(p_indep + Vector3(-10.0, 0, 12.0), -0.3, "orange")
		_road_sign(p_indep + Vector3(18.0, 0, -8.0), 0.0)

	if places.has("Restaurant Maïga (Médina)"):
		var p_medina: Vector3 = places["Restaurant Maïga (Médina)"]
		_kiosk(p_medina + Vector3(10.0, 0, 6.0), 1.2, "wave")
		_kiosk(p_medina + Vector3(-8.0, 0, -6.0), -1.1, "orange")

	if places.has("Hôpital Principal"):
		var p_hopital: Vector3 = places["Hôpital Principal"]
		_kiosk(p_hopital + Vector3(12.0, 0, -10.0), 0.8, "orange")
		_road_sign(p_hopital + Vector3(-14.0, 0, 8.0), PI / 2.0)


func _stall_maiga(place_name: String = "Restaurant Maïga", holder_name: String = "StallMaiga") -> void:
	if not place_info.has(place_name):
		return
	var info: Array = place_info[place_name]
	var n := Vector3(info[3], 0, info[4])
	var pos: Vector3 = off_road(places[place_name] + n * 2.2, n, 1.5)
	var holder := Node3D.new()
	holder.name = holder_name
	add_child(holder)
	holder.position = Vector3(pos.x, 0.07, pos.z)
	holder.rotation.y = info[2]
	# Comptoir Maïga : structure bois & carrelage
	Mk.box(holder, Vector3(3.2, 0.9, 1.4), Vector3(0, 0.45, 0), Color("c87d55"), true)
	Mk.box(holder, Vector3(3.3, 0.06, 1.45), Vector3(0, 0.93, 0), Color("f8f9fa"), true)
	# Plancha chaude & bacs spaghetti / brochettes
	Mk.box(holder, Vector3(1.1, 0.15, 0.6), Vector3(-0.8, 1.03, 0.1), Color("2b2b2b"), true)
	Mk.box(holder, Vector3(0.5, 0.12, 0.4), Vector3(0.2, 1.01, 0.2), Color("e9c46a"))
	Mk.box(holder, Vector3(0.5, 0.12, 0.4), Vector3(0.8, 1.01, 0.2), Color("8b0000"))
	# Poteaux et auvent jaune & orange
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Mk.cyl(holder, 0.05, 0.05, 2.5, Vector3(sx * 1.6, 1.25, sz * 0.8), Color("333333"), false, 4)
	Mk.box(holder, Vector3(3.6, 0.08, 2.1), Vector3(0, 2.5, 0), Color("e67e22"))

	# Bannière réaliste texturée FAST FOOD MAÏGA
	if ResourceLoader.exists("res://textures/world/maiga_banner.svg"):
		var banner_mesh := QuadMesh.new()
		banner_mesh.size = Vector2(3.5, 0.88)
		var banner_mat := StandardMaterial3D.new()
		banner_mat.albedo_texture = load("res://textures/world/maiga_banner.svg")
		banner_mat.roughness = 0.35
		banner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var banner_front := MeshInstance3D.new()
		banner_front.mesh = banner_mesh
		banner_front.material_override = banner_mat
		banner_front.position = Vector3(0, 2.25, 1.06)
		holder.add_child(banner_front)
	else:
		var sign_front := Mk.label(holder, "RESTAURANT MAÏGA — FAST FOOD", Vector3(0, 2.2, 1.08), 38, Color("fefae0"), false)
		sign_front.outline_size = 8
		sign_front.outline_modulate = Color("111111")

	# Éclairage d'ambiance nocturne réaliste (lumière dorée du réchaud/comptoir)
	var omni := OmniLight3D.new()
	omni.light_color = Color("ffba08")
	omni.light_energy = 1.2
	omni.omni_range = 6.0
	omni.position = Vector3(0, 2.1, 0.2)
	holder.add_child(omni)

	# Tables et chaises pour les clients
	var Furn = load("res://scripts/util/furniture.gd")
	Furn.place(holder, "painted_wooden_table", Vector3(2.4, 0, 1.8), 0.0, true, 0.6)
	for x in [1.7, 3.1]:
		Furn.place(holder, "plastic_monobloc_chair_01", Vector3(x, 0, 2.6), PI)
	# Cuisinier Maïga derrière le comptoir
	var cook = load("res://scripts/util/real_character.gd").create(holder, "homme_tunique", hash(place_name))
	cook.position = Vector3(0, 0.0, -0.3)
	cook.rotation.y = 0.0
	cook.play_clip("idle", 0.0)


func _kiosk(pos: Vector3, yaw: float, type: String) -> void:
	var holder := Node3D.new()
	holder.name = "Kiosk_" + type
	add_child(holder)
	holder.position = Vector3(pos.x, 0.05, pos.z)
	holder.rotation.y = yaw

	var is_wave := (type == "wave")
	var body_col := Color("0ea5e9") if is_wave else Color("18181b")
	var roof_col := Color("0284c7") if is_wave else Color("ea580c")
	var tex_path := "res://textures/world/wave_kiosk.svg" if is_wave else "res://textures/world/orange_money.svg"

	# Structure du kiosque
	Mk.box(holder, Vector3(2.0, 2.2, 1.8), Vector3(0, 1.1, 0), body_col, true)
	Mk.box(holder, Vector3(1.4, 0.9, 0.2), Vector3(0, 0.45, 0.85), Color("334155"), true)
	Mk.box(holder, Vector3(2.4, 0.15, 2.2), Vector3(0, 2.25, 0), roof_col)

	# Panneau enseigne texturé
	if ResourceLoader.exists(tex_path):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(tex_path)
		mat.roughness = 0.3
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		var mesh := QuadMesh.new()
		mesh.size = Vector2(1.2, 1.2)

		var sign := MeshInstance3D.new()
		sign.mesh = mesh
		sign.material_override = mat
		sign.position = Vector3(0, 1.5, 0.92)
		holder.add_child(sign)

	# Agent dans le kiosque
	var agent_model := "femme_ville" if is_wave else "homme_ville"
	var agent = load("res://scripts/util/real_character.gd").create(holder, agent_model, hash(pos))
	agent.position = Vector3(0, 0, 0)
	agent.play_clip("idle", 0.0)


func _road_sign(pos: Vector3, yaw: float) -> void:
	if not ResourceLoader.exists("res://textures/world/road_sign.svg"):
		return
	var holder := Node3D.new()
	holder.name = "RoadSign"
	add_child(holder)
	holder.position = Vector3(pos.x, 0.05, pos.z)
	holder.rotation.y = yaw

	# Deux poteaux métalliques
	Mk.cyl(holder, 0.08, 0.08, 4.0, Vector3(-1.4, 2.0, 0), Color("64748b"), false, 6)
	Mk.cyl(holder, 0.08, 0.08, 4.0, Vector3(1.4, 2.0, 0), Color("64748b"), false, 6)

	# Grand panneau routier double-face
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://textures/world/road_sign.svg")
	mat.roughness = 0.4
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := QuadMesh.new()
	mesh.size = Vector2(3.6, 1.8)

	var panel := MeshInstance3D.new()
	panel.mesh = mesh
	panel.material_override = mat
	panel.position = Vector3(0, 3.2, 0)
	holder.add_child(panel)


func _stall(place: String, color: Color) -> void:
	var info: Array = place_info[place]
	var n := Vector3(info[3], 0, info[4])
	var pos: Vector3 = off_road(places[place] + n * 2.2, n, 1.5)
	var holder := Node3D.new()
	add_child(holder)
	holder.position = Vector3(pos.x, 0.07, pos.z)
	holder.rotation.y = info[2]
	Mk.box(holder, Vector3(3, 0.9, 1.4), Vector3(0, 0.45, 0), Color("8d6748"), true)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Mk.cyl(holder, 0.05, 0.05, 2.4, Vector3(sx * 1.5, 1.2, sz * 0.8), Color("444444"), false, 4)
	Mk.box(holder, Vector3(3.4, 0.08, 2.0), Vector3(0, 2.4, 0), color)


# --- Végétation réaliste & Marquages routiers de Dakar ---------------------------

func _build_urban_decor() -> void:
	var decor := Node3D.new()
	decor.name = "UrbanDecor"
	add_child(decor)

	# 1. Place de l'Indépendance (Point de départ central du jeu)
	if places.has("Place de l'Indépendance"):
		var p_indep: Vector3 = places["Place de l'Indépendance"]
		# Cercle de 8 superbes palmiers royaux
		for k in 8:
			var ang: float = k * TAU / 8.0
			var p_palm := p_indep + Vector3(cos(ang) * 22.0, 0, sin(ang) * 22.0)
			_make_palm_tree(decor, p_palm, 7.8, ang)

		# 4 Flamboyants d'Afrique aux 4 angles
		_make_flamboyant_tree(decor, p_indep + Vector3(30.0, 0, 26.0), 6.5)
		_make_flamboyant_tree(decor, p_indep + Vector3(-30.0, 0, 26.0), 6.2)
		_make_flamboyant_tree(decor, p_indep + Vector3(30.0, 0, -26.0), 6.8)
		_make_flamboyant_tree(decor, p_indep + Vector3(-30.0, 0, -26.0), 6.4)

		# 2 Baobabs majestueux sénégalais sur les espaces verts
		_make_baobab_tree(decor, p_indep + Vector3(42.0, 0, 8.0), 8.5)
		_make_baobab_tree(decor, p_indep + Vector3(-42.0, 0, -8.0), 8.2)

		# Passages piétons zébrés blancs aux 4 abords de la Place
		_make_zebra_crossing(decor, p_indep + Vector3(0, 0, 24.0), 0.0, 8.0)
		_make_zebra_crossing(decor, p_indep + Vector3(0, 0, -24.0), 0.0, 8.0)
		_make_zebra_crossing(decor, p_indep + Vector3(24.0, 0, 0), PI * 0.5, 8.0)
		_make_zebra_crossing(decor, p_indep + Vector3(-24.0, 0, 0), PI * 0.5, 8.0)

		# Bordures de trottoir bicolores peintes jaune et noir (style Dakar)
		_make_curb_ring(decor, p_indep, 24.5, Color("facc15"), Color("1e293b"))

		# Lignes blanches axiales de guidage
		_make_road_centerline(decor, p_indep + Vector3(0, 0, 28.0), p_indep + Vector3(0, 0, 55.0))
		_make_road_centerline(decor, p_indep + Vector3(0, 0, -28.0), p_indep + Vector3(0, 0, -55.0))

	# 2. Hôpital Principal de Dakar
	if places.has("Hôpital Principal"):
		var p_hosp: Vector3 = places["Hôpital Principal"]
		for k in 5:
			_make_palm_tree(decor, p_hosp + Vector3(-18.0 + k * 8.0, 0, 16.0), 7.2, 0.2 * k)
		_make_neem_tree(decor, p_hosp + Vector3(22.0, 0, -12.0), 5.8)
		_make_neem_tree(decor, p_hosp + Vector3(-22.0, 0, -12.0), 5.5)
		_make_zebra_crossing(decor, p_hosp + Vector3(0, 0, 14.0), 0.0, 7.5)

	# 3. Marché Sandaga
	if places.has("Marché Sandaga"):
		var p_sand: Vector3 = places["Marché Sandaga"]
		_make_baobab_tree(decor, p_sand + Vector3(25.0, 0, 18.0), 8.8)
		_make_flamboyant_tree(decor, p_sand + Vector3(-20.0, 0, 15.0), 6.0)
		_make_neem_tree(decor, p_sand + Vector3(-15.0, 0, -18.0), 5.4)
		_make_zebra_crossing(decor, p_sand + Vector3(0, 0, 12.0), PI * 0.5, 7.0)
		_make_speed_bump(decor, p_sand + Vector3(0, 0, 20.0), 0.0, 6.5)

	# 4. Marché Tilène & Médina
	if places.has("Marché Tilène"):
		var p_til: Vector3 = places["Marché Tilène"]
		_make_flamboyant_tree(decor, p_til + Vector3(18.0, 0, 14.0), 6.3)
		_make_neem_tree(decor, p_til + Vector3(-16.0, 0, 12.0), 5.6)
		_make_zebra_crossing(decor, p_til + Vector3(0, 0, 10.0), 0.0, 6.5)

	# 5. Gare de Dakar
	if places.has("Gare de Dakar"):
		var p_gare: Vector3 = places["Gare de Dakar"]
		for k in 6:
			_make_palm_tree(decor, p_gare + Vector3(-20.0 + k * 8.0, 0, 15.0), 8.0, 0.1 * k)
		_make_zebra_crossing(decor, p_gare + Vector3(0, 0, 12.0), 0.0, 8.0)

	# 6. Grande Mosquée de Dakar
	if places.has("Grande Mosquée"):
		var p_mosq: Vector3 = places["Grande Mosquée"]
		for k in 4:
			_make_palm_tree(decor, p_mosq + Vector3(-15.0 + k * 10.0, 0, 20.0), 7.6, 0.3)
		_make_flamboyant_tree(decor, p_mosq + Vector3(22.0, 0, -16.0), 6.5)

	# 7. Porte du Millénaire (Corniche)
	if places.has("Porte du Millénaire"):
		var p_porte: Vector3 = places["Porte du Millénaire"]
		for k in 6:
			_make_palm_tree(decor, p_porte + Vector3(-25.0 + k * 10.0, 0, 16.0), 8.4, 0.2)


func _make_palm_tree(parent: Node3D, pos: Vector3, h: float, _seed_offset: float = 0.0) -> void:
	var tree_root := Node3D.new()
	tree_root.position = pos
	parent.add_child(tree_root)

	# Tronc annelé élancé en bois chaud
	Mk.cyl(tree_root, 0.22, 0.32, h, Vector3(0, h * 0.5, 0), Color("785d43"), true, 8)
	# Manchon foliaire vert émeraude au sommet
	Mk.cyl(tree_root, 0.26, 0.22, 0.7, Vector3(0, h + 0.35, 0), Color("2e7d32"), false, 8)

	# Couronne de 8 palmes retombantes en éventail
	var top := Vector3(0, h + 0.6, 0)
	for k in 8:
		var ang: float = k * TAU / 8.0
		var fdir := Vector3(cos(ang), -0.25, sin(ang)).normalized()
		var pmid := top + fdir * 1.8 + Vector3(0, 0.25, 0)
		var ptip := top + fdir * 3.4 + Vector3(0, -0.65, 0)
		var col_palm: Color = Color("2e7d32") if k % 2 == 0 else Color("388e3c")
		var frond_mid := Mk.box(tree_root, Vector3(0.55, 0.05, 1.8), (top + pmid) * 0.5, col_palm, false)
		frond_mid.look_at_from_position((top + pmid) * 0.5, pmid, Vector3.UP)
		var frond_tip := Mk.box(tree_root, Vector3(0.42, 0.04, 1.6), (pmid + ptip) * 0.5, col_palm.lightened(0.08), false)
		frond_tip.look_at_from_position((pmid + ptip) * 0.5, ptip, Vector3.UP)


func _make_baobab_tree(parent: Node3D, pos: Vector3, h: float) -> void:
	var tree_root := Node3D.new()
	tree_root.position = pos
	parent.add_child(tree_root)

	# Tronc conique massif caractéristique du baobab sénégalais
	Mk.cyl(tree_root, 1.3, 2.3, h * 0.65, Vector3(0, h * 0.325, 0), Color("5c4d3c"), true, 10)
	# Branches maîtresses obliques puissantes
	for k in 4:
		var ang: float = k * TAU / 4.0 + 0.35
		var b_dir := Vector3(cos(ang) * 1.8, h * 0.22, sin(ang) * 1.8)
		Mk.cyl(tree_root, 0.45, 0.75, 2.2, Vector3(0, h * 0.62, 0) + b_dir * 0.5, Color("5c4d3c"), false, 6)

	# Houppier parasol en dômes vert savane étalé
	Mk.sphere(tree_root, 2.8, Vector3(0, h + 0.3, 0), Color("4a7c36"), Vector3(1.5, 0.65, 1.5))
	Mk.sphere(tree_root, 2.0, Vector3(1.6, h - 0.2, 1.2), Color("3b6b28"), Vector3(1.2, 0.6, 1.2))
	Mk.sphere(tree_root, 2.0, Vector3(-1.5, h - 0.1, -1.3), Color("558b2f"), Vector3(1.2, 0.6, 1.2))


func _make_flamboyant_tree(parent: Node3D, pos: Vector3, h: float) -> void:
	var tree_root := Node3D.new()
	tree_root.position = pos
	parent.add_child(tree_root)

	# Tronc brun d'arbre d'ombrage
	Mk.cyl(tree_root, 0.28, 0.45, h * 0.7, Vector3(0, h * 0.35, 0), Color("4e3629"), true, 8)
	# Houppier parasol vert frais
	Mk.sphere(tree_root, 2.8, Vector3(0, h + 0.3, 0), Color("558b2f"), Vector3(1.6, 0.55, 1.6))
	# Fleurs écarlates / orange flamboyant typiques de Dakar
	Mk.sphere(tree_root, 1.4, Vector3(0.9, h + 0.65, 0.7), Color("dc2626"), Vector3(1.2, 0.5, 1.2))
	Mk.sphere(tree_root, 1.3, Vector3(-1.0, h + 0.55, -0.8), Color("ea580c"), Vector3(1.1, 0.5, 1.1))
	Mk.sphere(tree_root, 1.2, Vector3(-0.6, h + 0.65, 0.9), Color("ef4444"), Vector3(1.1, 0.5, 1.1))


func _make_neem_tree(parent: Node3D, pos: Vector3, h: float) -> void:
	var tree_root := Node3D.new()
	tree_root.position = pos
	parent.add_child(tree_root)

	# Tronc de margousier
	Mk.cyl(tree_root, 0.22, 0.32, h * 0.6, Vector3(0, h * 0.3, 0), Color("5d4037"), true, 8)
	# Dôme feuillu dense vert intense procurant de l'ombre
	Mk.sphere(tree_root, 2.2, Vector3(0, h + 0.5, 0), Color("2e7d32"), Vector3(1.1, 1.0, 1.1))
	Mk.sphere(tree_root, 1.7, Vector3(0.6, h + 0.8, -0.4), Color("388e3c"), Vector3(1.0, 0.9, 1.0))


func _make_zebra_crossing(parent: Node3D, center: Vector3, road_yaw: float, width: float = 7.0) -> void:
	var cross_root := Node3D.new()
	cross_root.position = center + Vector3(0, 0.08, 0)
	cross_root.rotation.y = road_yaw
	parent.add_child(cross_root)

	var num_stripes := int(width / 1.0)
	var half_w: float = width * 0.5
	for k in num_stripes:
		var x_pos: float = -half_w + (k + 0.5) * (width / float(num_stripes))
		Mk.box(cross_root, Vector3(0.55, 0.02, 3.2), Vector3(x_pos, 0, 0), Color(0.96, 0.96, 0.98, 0.95), false)


func _make_curb_ring(parent: Node3D, center: Vector3, radius: float, col1: Color, col2: Color) -> void:
	var ring_root := Node3D.new()
	ring_root.position = center + Vector3(0, 0.12, 0)
	parent.add_child(ring_root)

	var segments := 24
	for k in segments:
		var ang: float = k * TAU / float(segments)
		var p := Vector3(cos(ang) * radius, 0, sin(ang) * radius)
		var c := col1 if k % 2 == 0 else col2
		var curb := Mk.box(ring_root, Vector3(radius * (TAU / float(segments)) * 0.95, 0.14, 0.25), p, c, false)
		curb.rotation.y = -ang + PI * 0.5


func _make_road_centerline(parent: Node3D, p_start: Vector3, p_end: Vector3) -> void:
	var line_root := Node3D.new()
	parent.add_child(line_root)

	var diff := p_end - p_start
	var total_len := diff.length()
	if total_len < 4.0:
		return
	var dir := diff.normalized()
	var dash_len := 3.0
	var gap_len := 3.0
	var step := dash_len + gap_len
	var cur_dist := 0.0

	while cur_dist + dash_len <= total_len:
		var mid := p_start + dir * (cur_dist + dash_len * 0.5) + Vector3(0, 0.08, 0)
		var dash := Mk.box(line_root, Vector3(0.18, 0.02, dash_len), mid, Color(0.98, 0.98, 0.98, 0.9), false)
		dash.look_at_from_position(mid, mid + dir, Vector3.UP)
		cur_dist += step


func _make_speed_bump(parent: Node3D, center: Vector3, road_yaw: float, width: float = 6.5) -> void:
	var bump_root := Node3D.new()
	bump_root.position = center + Vector3(0, 0.09, 0)
	bump_root.rotation.y = road_yaw
	parent.add_child(bump_root)

	# Dos d'âne bicolore jaune et noir
	var num_sections := int(width / 0.8)
	var half_w: float = width * 0.5
	for k in num_sections:
		var x_pos: float = -half_w + (k + 0.5) * (width / float(num_sections))
		var col: Color = Color("facc15") if k % 2 == 0 else Color("1e293b")
		Mk.box(bump_root, Vector3(0.75, 0.07, 1.2), Vector3(x_pos, 0, 0), col, false)

