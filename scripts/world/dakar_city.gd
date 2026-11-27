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
	# Monuments et Infrastructures emblématiques de Dakar
	if not places.has("Monument de la Renaissance Africaine"):
		places["Monument de la Renaissance Africaine"] = Vector3(-1380.0, 16.0, -820.0)
		place_info["Monument de la Renaissance Africaine"] = [-1380.0, -820.0, 0.0, 1.0, 0.0]
	if not places.has("Phare des Mamelles"):
		places["Phare des Mamelles"] = Vector3(-1440.0, 24.0, -980.0)
		place_info["Phare des Mamelles"] = [-1440.0, -980.0, 0.0, 1.0, 0.0]


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

		# Coin thé Attaya sénégalais convivial
		_make_attaya_spot(decor, p_indep + Vector3(16.0, 0, 18.0), 0.5)

		# Grande Fontaine Centrale majestueuse de la Place de l'Indépendance
		_make_independance_fountain(decor, p_indep)

		# Grand Mât Officiel avec Drapeau National du Sénégal flottant
		_make_national_flagpole(decor, p_indep + Vector3(-9.0, 0, 8.0), 18.0)

		# Stèle Commémorative Officielle de l'Indépendance du 4 Avril 1960
		_make_independance_monument_stele(decor, p_indep + Vector3(9.0, 0, -8.0), 0.5)

		# Bancs publics en acajou (interactifs, assis) et lampadaires coloniaux doubles
		_make_plaza_benches_and_lamps(decor, p_indep)

		# Parterres floraux géométriques sénégalais (hibiscus et bougainvilliers)
		_make_geometric_flowerbeds(decor, p_indep)

		# Studio Officiel du Plateau (Héros Dakarois)
		_make_urban_studio(decor, p_indep + Vector3(-18.0, 0, 16.0), 0.2)

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
		# Étal de mangues et fruits locaux sénégalais
		_make_fruit_stall(decor, p_sand + Vector3(16.0, 0, 12.0), 0.3)
		_make_attaya_spot(decor, p_sand + Vector3(-12.0, 0, 16.0), -0.4)

	# 4. Marché Tilène & Médina
	if places.has("Marché Tilène"):
		var p_til: Vector3 = places["Marché Tilène"]
		_make_flamboyant_tree(decor, p_til + Vector3(18.0, 0, 14.0), 6.3)
		_make_neem_tree(decor, p_til + Vector3(-16.0, 0, 12.0), 5.6)
		_make_zebra_crossing(decor, p_til + Vector3(0, 0, 10.0), 0.0, 6.5)
		# Étal de fruits frais de la Médina
		_make_fruit_stall(decor, p_til + Vector3(14.0, 0, 8.0), -0.2)
		# Atelier de couture et confection de boubous
		_make_tailor_workshop(decor, p_til + Vector3(-26.0, 0, 10.0), 0.8)
		# Grande fresque murale Set Setal le long des murs
		_make_wall_mural(decor, p_til + Vector3(-18.0, 0, 32.0), 0.0, Vector2(8.5, 2.4), "res://textures/world/dakar_fresque_murale.jpg", "FRESQUE SET SETAL • STREET ART DAKAR")

	# 5. Gare de Dakar
	if places.has("Gare de Dakar"):
		var p_gare: Vector3 = places["Gare de Dakar"]
		for k in 6:
			_make_palm_tree(decor, p_gare + Vector3(-20.0 + k * 8.0, 0, 15.0), 8.0, 0.1 * k)
		_make_zebra_crossing(decor, p_gare + Vector3(0, 0, 12.0), 0.0, 8.0)

	# 6. Grande Mosquée de Dakar (Minaret andalou de 67m, croissant doré et architecture islamique)
	if places.has("Grande Mosquée"):
		var p_mosq: Vector3 = places["Grande Mosquée"]
		for k in 4:
			_make_palm_tree(decor, p_mosq + Vector3(-15.0 + k * 10.0, 0, 20.0), 7.6, 0.3)
		_make_flamboyant_tree(decor, p_mosq + Vector3(22.0, 0, -16.0), 6.5)
		_make_grande_mosquee_minaret(decor, p_mosq + Vector3(-8.0, 0, -6.0), 0.0)

	# 7. Porte du Millénaire (Les 3 arches courbées géantes, statue du joueur de kora et esplanade)
	if places.has("Porte du Millénaire"):
		var p_porte: Vector3 = places["Porte du Millénaire"]
		for k in 6:
			_make_palm_tree(decor, p_porte + Vector3(-25.0 + k * 10.0, 0, 16.0), 8.4, 0.2)
		_make_porte_du_millenaire(decor, p_porte, -PI * 0.25)
		# Studio des Lions de la Teranga & Athlètes
		_make_sports_studio(decor, p_porte + Vector3(16.0, 0, 24.0), 0.5)

	# 8. Stade Iba Mar Diop (Lutte sénégalaise & Sport populaire à la Médina)
	if places.has("Stade Iba Mar Diop"):
		var p_stade: Vector3 = places["Stade Iba Mar Diop"]
		_make_flamboyant_tree(decor, p_stade + Vector3(20.0, 0, 16.0), 6.6)
		_make_baobab_tree(decor, p_stade + Vector3(-24.0, 0, -18.0), 8.2)
		_make_zebra_crossing(decor, p_stade + Vector3(0, 0, 14.0), 0.0, 8.0)
		# Studio Arène de Lutte & Champions de Lamb
		_make_lamb_studio(decor, p_stade + Vector3(-22.0, 0, 20.0), -0.4)

	# 9. Monument de la Renaissance Africaine (Colosse de bronze de 52m, escalier et belvédère océan)
	if places.has("Monument de la Renaissance Africaine"):
		var p_ren: Vector3 = places["Monument de la Renaissance Africaine"]
		_make_african_renaissance_monument(decor, p_ren, 0.35)
		# Studio Loft Almadies & Business Tech
		_make_almadies_studio(decor, p_ren + Vector3(24.0, 0, -18.0), 0.3)

	# 10. Phare des Mamelles (Phare historique blanc de 1864 avec faisceau rotatif sur l'océan)
	if places.has("Phare des Mamelles"):
		var p_phare: Vector3 = places["Phare des Mamelles"]
		_make_phare_des_mamelles(decor, p_phare, 0.0)

	# 11. Grands panneaux photo réels de Dakar (Maisons, Architecture, Corniche, Rues authentiques)
	_build_photo_billboards(decor)


func _build_photo_billboards(parent: Node3D) -> void:
	# 1. Place de l'Indépendance : Architecture Dakar Plateau et Rues résidentielles
	if places.has("Place de l'Indépendance"):
		var p1: Vector3 = places["Place de l'Indépendance"] + Vector3(18.0, 0, -32.0)
		_make_photo_billboard(parent, p1, 0.0, "res://textures/world/dakar_immeubles_plateau.jpg", "DAKAR PLATEAU • ARCHITECTURE CAPITALE")
		var p2: Vector3 = places["Place de l'Indépendance"] + Vector3(-22.0, 0, 32.0)
		_make_photo_billboard(parent, p2, PI, "res://textures/world/dakar_maisons_rue.jpg", "TERANGA SÉNÉGAL • RUES & MAISONS DE DAKAR")

	# 2. Corniche Ouest / Porte du Millénaire : Vue route de la Corniche et Océan
	if places.has("Porte du Millénaire"):
		var p: Vector3 = places["Porte du Millénaire"] + Vector3(12.0, 0, 28.0)
		_make_photo_billboard(parent, p, -PI * 0.25, "res://textures/world/dakar_route_corniche.jpg", "ROUTE DE LA CORNICHE OUEST • DAKAR")

	# 3. Marché Sandaga : Façade historique néo-soudanaise et étalages
	if places.has("Marché Sandaga"):
		var p_sand1: Vector3 = places["Marché Sandaga"] + Vector3(26.0, 0, -18.0)
		_make_photo_billboard(parent, p_sand1, -PI * 0.5, "res://textures/world/dakar_marche_sandaga.jpg", "MARCHÉ SANDAGA • PATRIMOINE HISTORIQUE NÉO-SOUDANAIS")
		var p_sand2: Vector3 = places["Marché Sandaga"] + Vector3(-26.0, 0, -18.0)
		_make_photo_billboard(parent, p_sand2, PI * 0.5, "res://textures/world/dakar_etal_marche.jpg", "FRUITS DU SÉNÉGAL • MANGUES ET PRODUITS LOCAUX")

	# 4. Marché Tilène / Médina : Maisons populaires et ateliers de couture
	if places.has("Marché Tilène"):
		var p_til1: Vector3 = places["Marché Tilène"] + Vector3(-25.0, 0, 20.0)
		_make_photo_billboard(parent, p_til1, PI * 0.5, "res://textures/world/dakar_medina_maisons.jpg", "MÉDINA • MAISONS ET COMMERCES POPULAIRES")
		var p_til2: Vector3 = places["Marché Tilène"] + Vector3(28.0, 0, 20.0)
		_make_photo_billboard(parent, p_til2, -PI * 0.5, "res://textures/world/dakar_artisanat_medina.jpg", "ATELIER DE COUTURE & BAZIN • TALENT DAKAROIS")

	# 5. Stade Iba Mar Diop / Arène : Grande affiche officielle de Lamb
	if places.has("Stade Iba Mar Diop"):
		var p_stade: Vector3 = places["Stade Iba Mar Diop"] + Vector3(18.0, 0, 26.0)
		_make_photo_billboard(parent, p_stade, 0.0, "res://textures/world/dakar_lutte_senegalaise.jpg", "LAMB GALSEN • GRANDE SOIRÉE DE LUTTE SÉNÉGALAISE")


func _make_photo_billboard(parent: Node3D, pos: Vector3, yaw: float, tex_path: String, label_text: String, board_w: float = 5.0, board_h: float = 3.0) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# Deux montants verticaux en acier galvanisé
	var col_steel := Color("334155")
	var post_span: float = board_w * 0.44
	Mk.cyl(root, 0.12, 0.14, 5.2, Vector3(-post_span, 2.6, 0), col_steel, true, 8)
	Mk.cyl(root, 0.12, 0.14, 5.2, Vector3(post_span, 2.6, 0), col_steel, true, 8)

	# Cadre et panneau structurel arrière
	Mk.box(root, Vector3(board_w, board_h, 0.16), Vector3(0, 2.3 + board_h * 0.5, 0), Color("1e293b"), true)

	# Face avant avec la photo réelle du Sénégal
	var tex: Texture2D = Mk.load_texture(tex_path)
	if tex != null:
		var mat_photo := StandardMaterial3D.new()
		mat_photo.albedo_texture = tex
		mat_photo.roughness = 0.4
		mat_photo.metallic_specular = 0.5
		Mk.box(root, Vector3(board_w - 0.2, board_h - 0.4, 0.05), Vector3(0, 2.3 + board_h * 0.5, 0.1), Color.WHITE, false, mat_photo)

	# Bandeau inférieur d'information
	var l := Label3D.new()
	l.text = label_text
	l.font_size = 28
	l.outline_size = 8
	l.modulate = Color("facc15")
	l.position = Vector3(0, 2.35, 0.12)
	root.add_child(l)


## Grande fresque murale artistique sénégalaise (Set Setal, street art de Dakar)
func _make_wall_mural(parent: Node3D, pos: Vector3, yaw: float, size: Vector2, tex_path: String, label_text: String = "") -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	var tex: Texture2D = Mk.load_texture(tex_path)
	if tex != null:
		var quad := QuadMesh.new()
		quad.size = size
		var mat_mural := StandardMaterial3D.new()
		mat_mural.albedo_texture = tex
		mat_mural.roughness = 0.7
		mat_mural.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat_mural
		mi.position = Vector3(0, size.y * 0.5, 0.05)
		root.add_child(mi)

	# Encadrement maçonnerie peinte
	Mk.box(root, Vector3(size.x + 0.2, 0.12, 0.14), Vector3(0, size.y + 0.06, 0.05), Color("1e293b"))
	Mk.box(root, Vector3(size.x + 0.2, 0.12, 0.14), Vector3(0, 0.06, 0.05), Color("1e293b"))

	if label_text != "":
		var l := Label3D.new()
		l.text = label_text
		l.font_size = 26
		l.outline_size = 6
		l.modulate = Color("fefae0")
		l.position = Vector3(0, size.y + 0.32, 0.08)
		root.add_child(l)


## Étal de fruits frais typique des marchés de Dakar (mangues, pastèques, agrumes)
func _make_fruit_stall(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "FruitStall"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# Table en bois brut sur tréteaux
	Mk.box(root, Vector3(2.6, 0.75, 1.2), Vector3(0, 0.38, 0), Color("8d6748"), true)
	Mk.box(root, Vector3(2.8, 0.06, 1.3), Vector3(0, 0.78, 0), Color("a47551"), true)

	# Caisses inclinées de fruits sénégalais
	# Caisse 1 : Mangues mûres dorées et vertes
	Mk.box(root, Vector3(0.8, 0.15, 0.5), Vector3(-0.8, 0.9, -0.2), Color("c49a6c"))
	for mx in [-0.2, 0.0, 0.2]:
		for mz in [-0.1, 0.1]:
			var m_col: Color = Color("f39c12") if (mx + mz) > 0 else Color("27ae60")
			Mk.sphere(root, 0.08, Vector3(-0.8 + mx, 1.02, -0.2 + mz), m_col)

	# Caisse 2 : Pastèques du Sénégal
	Mk.box(root, Vector3(0.8, 0.15, 0.5), Vector3(0.0, 0.9, -0.2), Color("c49a6c"))
	Mk.sphere(root, 0.13, Vector3(-0.15, 1.05, -0.2), Color("1b4332"))
	Mk.sphere(root, 0.12, Vector3(0.15, 1.05, -0.2), Color("2d6a4f"))

	# Caisse 3 : Papayes et agrumes
	Mk.box(root, Vector3(0.8, 0.15, 0.5), Vector3(0.8, 0.9, -0.2), Color("c49a6c"))
	for px in [-0.2, 0.0, 0.2]:
		Mk.sphere(root, 0.07, Vector3(0.8 + px, 1.02, -0.2), Color("e67e22"))

	# Parasol coloré au-dessus de l'étal
	Mk.cyl(root, 0.04, 0.04, 2.6, Vector3(0, 1.3, -0.5), Color("444444"), false, 6)
	Mk.cyl(root, 1.6, 0.06, 0.4, Vector3(0, 2.6, -0.5), Color("e76f51"), false, 10)


## Coin thé Attaya sénégalais (théière émaillée, verres à thé moussants, fourneau)
func _make_attaya_spot(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "AttayaSpot"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# Petite table basse traditionnelle
	Mk.box(root, Vector3(0.9, 0.35, 0.6), Vector3(0, 0.18, 0), Color("5c4033"), true)
	# Tabouret en bois
	Mk.box(root, Vector3(0.35, 0.25, 0.35), Vector3(0.6, 0.13, 0), Color("8b5a2b"), true)
	# Fourneau à braises
	Mk.cyl(root, 0.12, 0.10, 0.18, Vector3(-0.25, 0.44, 0), Color("222222"), false, 8)
	# Théière émaillée bleue d'Attaya (Barada)
	Mk.cyl(root, 0.07, 0.09, 0.16, Vector3(-0.25, 0.58, 0), Color("0077b6"), false, 8)
	# Petits verres à thé avec mousse blanche
	Mk.cyl(root, 0.03, 0.03, 0.07, Vector3(0.12, 0.39, -0.1), Color("f1f5f9"), false, 6)
	Mk.cyl(root, 0.03, 0.03, 0.07, Vector3(0.22, 0.39, 0.05), Color("f1f5f9"), false, 6)


## Atelier de couture & tailleur traditionnel de la Médina
func _make_tailor_workshop(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "TailorWorkshop"
	root.position = pos
	root.rotation.y = yaw
	root.add_to_group("studio_spots")
	root.set_meta("studio_name", "Salon & Studio de Mode de la Médina")
	root.set_meta("character_id", "linguere")
	parent.add_child(root)

	# Enseigne élégante Studio & Stylisme de Dakar
	var sign_mesh := QuadMesh.new()
	sign_mesh.size = Vector2(2.6, 0.5)
	var sign_node := MeshInstance3D.new()
	sign_node.mesh = sign_mesh
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color("1e293b")
	sign_mat.emission_enabled = true
	sign_mat.emission = Color("ffd166")
	sign_mat.emission_energy_multiplier = 0.8
	sign_node.material_override = sign_mat
	sign_node.position = Vector3(0, 2.7, 0.9)
	root.add_child(sign_node)

	# Table de coupe en bois
	Mk.box(root, Vector3(2.4, 0.85, 1.2), Vector3(0, 0.43, 0), Color("78350f"), true)
	# Machine à coudre vintage Singer (noire et dorée)
	Mk.box(root, Vector3(0.45, 0.25, 0.2), Vector3(-0.4, 0.98, 0), Color("0f172a"), true)
	Mk.cyl(root, 0.02, 0.02, 0.14, Vector3(-0.25, 1.0, 0), Color("f59e0b"), false, 6)
	# Rouleaux de tissus Bazin et Wax empilés
	var fabric_cols := [Color("0284c7"), Color("f59e0b"), Color("10b981"), Color("8b5cf6")]
	for i in 4:
		Mk.cyl(root, 0.06, 0.06, 0.8, Vector3(0.4, 0.92 + i * 0.07, -0.25 + i * 0.12), fabric_cols[i], false, 8)
	# Auvent en tôle ondulée
	for sx in [-1, 1]:
		Mk.cyl(root, 0.04, 0.04, 2.5, Vector3(sx * 1.3, 1.25, 0.6), Color("64748b"), false, 6)
	Mk.box(root, Vector3(2.8, 0.05, 1.6), Vector3(0, 2.45, 0.1), Color("94a3b8"))


## Studio Urbain Officiel du Plateau (Modou Fall / Héros Dakarois)
func _make_urban_studio(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "UrbanStudioPlateau"
	root.position = pos
	root.rotation.y = yaw
	root.add_to_group("studio_spots")
	root.set_meta("studio_name", "Studio Officiel du Plateau")
	root.set_meta("character_id", "heros")
	parent.add_child(root)

	# Podium terrazzo dakarois
	Mk.cyl(root, 1.6, 1.7, 0.18, Vector3(0, 0.09, 0), Color("1e293b"), true, 16)
	# Anneau doré d'éclairage
	Mk.cyl(root, 1.72, 1.72, 0.04, Vector3(0, 0.11, 0), Color("ffd166"), false, 16)
	# Mâts de projecteurs studio
	for sx in [-1.5, 1.5]:
		Mk.cyl(root, 0.04, 0.04, 3.2, Vector3(sx, 1.6, -1.2), Color("475569"), true, 8)
		Mk.box(root, Vector3(0.35, 0.25, 0.2), Vector3(sx, 3.2, -1.1), Color("f8fafc"))
	# Enseigne lumineuse Studio Plateau
	Mk.label(root, "🎨 STUDIO DAKAR • LE HÉROS DAKAROIS", Vector3(0, 3.5, -1.0), Mk.SIGN_SIZE, Color("ffd166"))


## Studio Arène de Lutte & Champions de Lamb (Balla Ndiaye / Bombardier)
func _make_lamb_studio(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "LambStudioIbaMarDiop"
	root.position = pos
	root.rotation.y = yaw
	root.add_to_group("studio_spots")
	root.set_meta("studio_name", "Studio des Champions de Lamb")
	root.set_meta("character_id", "lutteur")
	parent.add_child(root)

	# Cercle de sable de l'arène (sable ocre chaud)
	Mk.cyl(root, 1.7, 1.8, 0.15, Vector3(0, 0.075, 0), Color("b06c3b"), true, 16)
	# Cordeau traditionnel d'arène
	Mk.cyl(root, 1.82, 1.82, 0.05, Vector3(0, 0.10, 0), Color("ffaa5e"), false, 16)
	# Tam-tams traditionnels (sabars)
	for i in [-0.8, 0.8]:
		Mk.cyl(root, 0.16, 0.12, 0.55, Vector3(i, 0.28, -1.2), Color("5c2c10"), true, 8)
		Mk.cyl(root, 0.17, 0.17, 0.04, Vector3(i, 0.56, -1.2), Color("fef08a"), false, 8)
	# Mâts aux drapeaux sénégalais
	for sx in [-1.6, 1.6]:
		Mk.cyl(root, 0.04, 0.04, 3.4, Vector3(sx, 1.7, -1.2), Color("64748b"), true, 8)
	Mk.label(root, "🤼 STUDIO LAMB • LES ROIS DES ARÈNES", Vector3(0, 3.6, -1.0), Mk.SIGN_SIZE, Color("ffb703"))


## Studio des Lions de la Teranga & Sports (Sadio Diatta / Aïssatou Sow)
func _make_sports_studio(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "SportsStudioTeranga"
	root.position = pos
	root.rotation.y = yaw
	root.add_to_group("studio_spots")
	root.set_meta("studio_name", "Studio des Lions de la Teranga")
	root.set_meta("character_id", "footballeur")
	parent.add_child(root)

	# Cercle de pelouse verte de stade
	Mk.cyl(root, 1.7, 1.8, 0.16, Vector3(0, 0.08, 0), Color("196f3d"), true, 16)
	# Ligne blanche de terrain
	Mk.cyl(root, 1.82, 1.82, 0.04, Vector3(0, 0.10, 0), Color.WHITE, false, 16)
	# Ballon de football officiel
	Mk.sphere(root, 0.15, Vector3(0.6, 0.25, 0.6), Color.WHITE)
	# Projecteurs de stade inclinés
	for sx in [-1.5, 1.5]:
		Mk.cyl(root, 0.05, 0.05, 3.5, Vector3(sx, 1.75, -1.3), Color("334155"), true, 8)
		Mk.box(root, Vector3(0.4, 0.25, 0.2), Vector3(sx, 3.5, -1.2), Color("22c55e"))
	Mk.label(root, "⚽ STUDIO LIONS • GAÏNDÉS DU SÉNÉGAL", Vector3(0, 3.7, -1.0), Mk.SIGN_SIZE, Color("4ade80"))


## Studio Loft Tech Almadies (Ibrahima Cissé / Entrepreneur)
func _make_almadies_studio(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "AlmadiesLoftStudio"
	root.position = pos
	root.rotation.y = yaw
	root.add_to_group("studio_spots")
	root.set_meta("studio_name", "Studio Loft des Almadies")
	root.set_meta("character_id", "entrepreneur")
	parent.add_child(root)

	# Parquet teck vitrifié
	Mk.box(root, Vector3(3.2, 0.16, 2.6), Vector3(0, 0.08, 0), Color("1e2c3a"), true)
	# Bordure néon cyan
	Mk.box(root, Vector3(3.3, 0.04, 2.7), Vector3(0, 0.10, 0), Color("0ea5e9"))
	# Bureau design en verre
	Mk.box(root, Vector3(1.6, 0.75, 0.7), Vector3(0, 0.45, -0.7), Color("0f172a"), true)
	Mk.box(root, Vector3(1.7, 0.04, 0.75), Vector3(0, 0.84, -0.7), Color("38bdf8"))
	# Ordinateur portable ouvert
	Mk.box(root, Vector3(0.35, 0.02, 0.24), Vector3(0, 0.87, -0.7), Color("e2e8f0"))
	Mk.box(root, Vector3(0.35, 0.22, 0.02), Vector3(0, 0.98, -0.82), Color("0f172a"))
	Mk.label(root, "💼 STUDIO LOFT • ALMADIES TECH INNOVATION", Vector3(0, 3.4, -1.0), Mk.SIGN_SIZE, Color("38bdf8"))


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
	var mat_white: Material = Mk.concrete_pbr(Color(0.96, 0.96, 0.98, 0.95))
	for k in num_stripes:
		var x_pos: float = -half_w + (k + 0.5) * (width / float(num_stripes))
		Mk.box(cross_root, Vector3(0.55, 0.02, 3.2), Vector3(x_pos, 0, 0), Color(0.96, 0.96, 0.98, 0.95), false, mat_white)


func _make_curb_ring(parent: Node3D, center: Vector3, radius: float, col1: Color, col2: Color) -> void:
	var ring_root := Node3D.new()
	ring_root.position = center + Vector3(0, 0.12, 0)
	parent.add_child(ring_root)

	var segments := 24
	var mat1: Material = Mk.concrete_pbr(col1)
	var mat2: Material = Mk.concrete_pbr(col2)
	for k in segments:
		var ang: float = k * TAU / float(segments)
		var p := Vector3(cos(ang) * radius, 0, sin(ang) * radius)
		var c := col1 if k % 2 == 0 else col2
		var m := mat1 if k % 2 == 0 else mat2
		var curb := Mk.box(ring_root, Vector3(radius * (TAU / float(segments)) * 0.95, 0.14, 0.25), p, c, false, m)
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
	var mat_line: Material = Mk.concrete_pbr(Color(0.98, 0.98, 0.98, 0.9))

	while cur_dist + dash_len <= total_len:
		var mid := p_start + dir * (cur_dist + dash_len * 0.5) + Vector3(0, 0.08, 0)
		var dash := Mk.box(line_root, Vector3(0.18, 0.02, dash_len), mid, Color(0.98, 0.98, 0.98, 0.9), false, mat_line)
		dash.look_at_from_position(mid, mid + dir, Vector3.UP)
		cur_dist += step


func _make_speed_bump(parent: Node3D, center: Vector3, road_yaw: float, width: float = 6.5) -> void:
	var bump_root := Node3D.new()
	bump_root.position = center + Vector3(0, 0.09, 0)
	bump_root.rotation.y = road_yaw
	parent.add_child(bump_root)

	# Dos d'âne bicolore jaune et noir en béton PBR avec usure réaliste
	var num_sections := int(width / 0.8)
	var half_w: float = width * 0.5
	var mat_yel: Material = Mk.concrete_pbr(Color("facc15"))
	var mat_dark: Material = Mk.concrete_pbr(Color("1e293b"))
	for k in num_sections:
		var x_pos: float = -half_w + (k + 0.5) * (width / float(num_sections))
		var col: Color = Color("facc15") if k % 2 == 0 else Color("1e293b")
		var m: Material = mat_yel if k % 2 == 0 else mat_dark
		Mk.box(bump_root, Vector3(0.75, 0.07, 1.2), Vector3(x_pos, 0, 0), col, false, m)


# --- Infrastructures & Monuments Emblématiques du Sénégal ----------------------------

## Grande Fontaine centrale majestueuse de la Place de l'Indépendance
func _make_independance_fountain(parent: Node3D, pos: Vector3) -> void:
	var root := Node3D.new()
	root.name = "IndependanceFountain"
	root.position = pos
	parent.add_child(root)

	# Bassin extérieur circulaire en marbre blanc (diamètre 12m, margelle protectrice)
	var mat_marble: Material = Mk.concrete_pbr(Color("f8fafc"))
	var rim_segments := 24
	var outer_radius := 6.0
	for k in rim_segments:
		var ang: float = k * TAU / float(rim_segments)
		var p := Vector3(cos(ang) * outer_radius, 0.4, sin(ang) * outer_radius)
		var rim_block := Mk.box(root, Vector3(outer_radius * (TAU / float(rim_segments)) * 1.05, 0.8, 0.6), p, Color("f1f5f9"), true, mat_marble)
		rim_block.rotation.y = -ang + PI * 0.5

	# Dalle de fond du bassin
	Mk.cyl(root, outer_radius - 0.2, outer_radius - 0.2, 0.2, Vector3(0, 0.1, 0), Color("94a3b8"), true, 20)

	# Nappe d'eau turquoise translucide avec reflets
	var mat_water := StandardMaterial3D.new()
	mat_water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_water.albedo_color = Color(0.12, 0.68, 0.82, 0.75)
	mat_water.roughness = 0.04
	mat_water.metallic_specular = 0.95
	var water_mi := Mk.cyl(root, outer_radius - 0.35, outer_radius - 0.35, 0.05, Vector3(0, 0.65, 0), Color.WHITE, false, 20)
	water_mi.material_override = mat_water

	# Bassin intermédiaire surélevé (diamètre 6m, hauteur 1.4m)
	Mk.cyl(root, 3.0, 3.2, 0.7, Vector3(0, 0.75, 0), Color("e2e8f0"), true, 16)
	var water_mid := Mk.cyl(root, 2.7, 2.7, 0.05, Vector3(0, 1.15, 0), Color.WHITE, false, 16)
	water_mid.material_override = mat_water

	# Piédestal central orné et coupe supérieure en bronze sculpté
	Mk.cyl(root, 0.9, 1.2, 1.6, Vector3(0, 1.9, 0), Color("cbd5e1"), true, 12)
	Mk.cyl(root, 1.6, 0.5, 0.5, Vector3(0, 2.9, 0), Color("78350f"), true, 12)

	# Jets d'eau verticaux et arqués
	# 1. Grand geyser central vertical montant à 5.2 mètres
	var mat_jet := StandardMaterial3D.new()
	mat_jet.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_jet.albedo_color = Color(0.9, 0.98, 1.0, 0.55)
	mat_jet.roughness = 0.1
	mat_jet.emission_enabled = true
	mat_jet.emission = Color(0.6, 0.9, 1.0)
	mat_jet.emission_energy_multiplier = 0.4
	var jet_center := Mk.cyl(root, 0.18, 0.35, 3.2, Vector3(0, 4.7, 0), Color.WHITE, false, 8)
	jet_center.material_override = mat_jet
	var jet_top := Mk.cyl(root, 0.04, 0.22, 1.6, Vector3(0, 6.7, 0), Color.WHITE, false, 8)
	jet_top.material_override = mat_jet

	# 2. Huit jets d'eau périphériques inclinés vers le centre
	for k in 8:
		var ang: float = k * TAU / 8.0
		var j_pos := Vector3(cos(ang) * 4.2, 0.7, sin(ang) * 4.2)
		var jet_sub := Mk.cyl(root, 0.06, 0.12, 1.6, j_pos + Vector3(0, 0.7, 0), Color.WHITE, false, 6)
		jet_sub.material_override = mat_jet
		jet_sub.rotation.x = sin(ang) * 0.35
		jet_sub.rotation.z = -cos(ang) * 0.35

	# Éclairage subaquatique féerique nocturne
	var light := OmniLight3D.new()
	light.light_color = Color("38bdf8")
	light.light_energy = 2.4
	light.omni_range = 14.0
	light.position = Vector3(0, 1.2, 0)
	root.add_child(light)

	# Panneau nominatif de la fontaine
	Mk.label(root, "FONTAINE DE LA PLACE DE L'INDÉPENDANCE", Vector3(0, 3.4, 0), 32, Color("38bdf8"))


## Grand Mât officiel avec Drapeau National du Sénégal flottant au vent
func _make_national_flagpole(parent: Node3D, pos: Vector3, h: float = 18.0) -> void:
	var root := Node3D.new()
	root.name = "NationalFlagpole"
	root.position = pos
	parent.add_child(root)

	# Base monumentale en granit poli biseauté
	Mk.box(root, Vector3(2.4, 0.4, 2.4), Vector3(0, 0.2, 0), Color("0f172a"), true)
	Mk.box(root, Vector3(1.8, 0.4, 1.8), Vector3(0, 0.6, 0), Color("1e293b"), true)
	# Anneau de fixation en bronze doré
	Mk.cyl(root, 0.45, 0.55, 0.4, Vector3(0, 1.0, 0), Color("f59e0b"), true, 10)

	# Mât télescopique en acier chromé inoxydable brillant
	var mat_chrome := StandardMaterial3D.new()
	mat_chrome.albedo_color = Color("f1f5f9")
	mat_chrome.metallic = 0.95
	mat_chrome.roughness = 0.12
	mat_chrome.clearcoat_enabled = true
	mat_chrome.clearcoat = 0.9
	var mast := Mk.cyl(root, 0.10, 0.22, h, Vector3(0, 1.0 + h * 0.5, 0), Color.WHITE, true, 10)
	mast.material_override = mat_chrome

	# Flèche supérieure : Sphère dorée (pommeau du drapeau national)
	var mat_gold := StandardMaterial3D.new()
	mat_gold.albedo_color = Color("fbbf24")
	mat_gold.metallic = 0.9
	mat_gold.roughness = 0.15
	var finial := Mk.sphere(root, 0.32, Vector3(0, 1.0 + h + 0.32, 0), Color("fbbf24"))
	finial.material_override = mat_gold

	# Drapeau National du Sénégal flottant au vent (Vert, Jaune avec Étoile Verte, Rouge)
	var flag_tex: Texture2D = Mk.load_texture("res://textures/world/flag_senegal.svg")
	var flag_w := 3.8
	var flag_h := 2.4
	var flag_mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(flag_w, flag_h)
	flag_mi.mesh = quad
	var flag_mat := StandardMaterial3D.new()
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if flag_tex != null:
		flag_mat.albedo_texture = flag_tex
	else:
		flag_mat.albedo_color = Color("15803d")
	flag_mat.roughness = 0.75
	flag_mat.rim_enabled = true
	flag_mat.rim = 0.3
	flag_mat.rim_tint = 0.4
	flag_mi.material_override = flag_mat
	# Positionné au sommet du mât, orienté vers la brise d'alizé (flottement vers l'Est)
	flag_mi.position = Vector3(flag_w * 0.5 + 0.12, 1.0 + h - flag_h * 0.5 - 0.2, 0)
	flag_mi.rotation.y = -0.15
	flag_mi.rotation.z = 0.05
	root.add_child(flag_mi)

	# Projecteur architectural nocturne illuminant le drapeau national
	var spot := SpotLight3D.new()
	spot.light_color = Color("fffbeb")
	spot.light_energy = 3.5
	spot.spot_range = h + 6.0
	spot.spot_angle = 18.0
	spot.position = Vector3(0.5, 0.8, 0.5)
	spot.rotation.x = -PI * 0.46
	root.add_child(spot)

	Mk.label(root, "DRAPEAU NATIONAL DU SÉNÉGAL", Vector3(0, 2.2, 0), 28, Color("fbbf24"))


## Stèle Commémorative Officielle de l'Indépendance du Sénégal (4 Avril 1960)
func _make_independance_monument_stele(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "IndependanceStele"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# Socle double en granit noir poli
	var mat_granite := StandardMaterial3D.new()
	mat_granite.albedo_color = Color("0f172a")
	mat_granite.roughness = 0.25
	mat_granite.metallic = 0.2
	var b1 := Mk.box(root, Vector3(3.2, 0.45, 2.2), Vector3(0, 0.225, 0), Color.WHITE, true, mat_granite)
	var b2 := Mk.box(root, Vector3(2.6, 0.45, 1.8), Vector3(0, 0.675, 0), Color.WHITE, true, mat_granite)

	# Stèle verticale monolithique sculptée
	var stele := Mk.box(root, Vector3(1.6, 4.2, 0.7), Vector3(0, 3.0, 0), Color.WHITE, true, mat_granite)

	# Étoile nationale à 5 branches dorée en relief
	var star := Mk.cyl(root, 0.35, 0.35, 0.08, Vector3(0, 4.4, 0.38), Color("fbbf24"), false, 5)
	star.rotation.x = PI * 0.5

	# Gravure officielle commémorative en lettres d'or
	var l_rep := Label3D.new()
	l_rep.text = "RÉPUBLIQUE DU SÉNÉGAL"
	l_rep.font_size = 30
	l_rep.outline_size = 8
	l_rep.modulate = Color("fbbf24")
	l_rep.position = Vector3(0, 3.8, 0.38)
	root.add_child(l_rep)

	var l_date := Label3D.new()
	l_date.text = "4 AVRIL 1960 • INDÉPENDANCE"
	l_date.font_size = 26
	l_date.outline_size = 6
	l_date.modulate = Color("ffffff")
	l_date.position = Vector3(0, 3.2, 0.38)
	root.add_child(l_date)

	var l_devise := Label3D.new()
	l_devise.text = "« UN PEUPLE • UN BUT • UNE FOI »"
	l_devise.font_size = 24
	l_devise.outline_size = 6
	l_devise.modulate = Color("f59e0b")
	l_devise.position = Vector3(0, 2.6, 0.38)
	root.add_child(l_devise)

	# Deux urnes cérémonielles en bronze flanquant la stèle
	for sx in [-1.5, 1.5]:
		Mk.cyl(root, 0.28, 0.18, 0.65, Vector3(sx, 0.75, 0), Color("b45309"), true, 8)
		Mk.sphere(root, 0.22, Vector3(sx, 1.15, 0), Color("f59e0b"))


## Bancs publics de repos en acajou et lampadaires coloniaux doubles de la Place
func _make_plaza_benches_and_lamps(parent: Node3D, center: Vector3) -> void:
	# 8 bancs publics disposés en cercle de détente
	var bench_radius := 16.5
	for k in 8:
		var ang: float = k * TAU / 8.0 + (PI / 8.0)
		var b_pos := center + Vector3(cos(ang) * bench_radius, 0, sin(ang) * bench_radius)
		_make_plaza_bench(parent, b_pos, -ang + PI * 0.5)

	# 4 lampadaires coloniaux doubles de prestige aux 4 diagonales
	var lamp_radius := 19.5
	for k in 4:
		var ang: float = k * TAU / 4.0 + (PI / 4.0)
		var l_pos := center + Vector3(cos(ang) * lamp_radius, 0, sin(ang) * lamp_radius)
		_make_colonial_dual_lamp(parent, l_pos)


func _make_plaza_bench(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var bench := Node3D.new()
	bench.name = "PlazaBench"
	bench.position = pos
	bench.rotation.y = yaw
	# Ajout au groupe 'chairs' pour que le joueur puisse s'asseoir dessus avec réalisme !
	bench.add_to_group("chairs")
	parent.add_child(bench)

	# Piètements en fonte verte travaillée
	var mat_iron := StandardMaterial3D.new()
	mat_iron.albedo_color = Color("14532d")
	mat_iron.roughness = 0.4
	mat_iron.metallic = 0.7
	for sx in [-0.9, 0.9]:
		Mk.box(bench, Vector3(0.08, 0.45, 0.6), Vector3(sx, 0.225, 0), Color.WHITE, true, mat_iron)
		Mk.box(bench, Vector3(0.08, 0.5, 0.08), Vector3(sx, 0.65, -0.26), Color.WHITE, true, mat_iron)

	# Lattes en bois d'acajou verni chaud
	var mat_wood := StandardMaterial3D.new()
	mat_wood.albedo_color = Color("78350f")
	mat_wood.roughness = 0.35
	mat_wood.clearcoat_enabled = true
	mat_wood.clearcoat = 0.5
	# Assise (3 lattes)
	for i in 3:
		Mk.box(bench, Vector3(2.0, 0.04, 0.16), Vector3(0, 0.46, -0.18 + i * 0.18), Color.WHITE, false, mat_wood)
	# Dossier (2 lattes)
	for i in 2:
		Mk.box(bench, Vector3(2.0, 0.16, 0.04), Vector3(0, 0.62 + i * 0.18, -0.28), Color.WHITE, false, mat_wood)


func _make_colonial_dual_lamp(parent: Node3D, pos: Vector3) -> void:
	var lamp := Node3D.new()
	lamp.name = "ColonialLamp"
	lamp.position = pos
	parent.add_child(lamp)

	var mat_pole := StandardMaterial3D.new()
	mat_pole.albedo_color = Color("1e293b")
	mat_pole.metallic = 0.8
	mat_pole.roughness = 0.3

	# Fût cannelé en fonte et socle ouvragé
	Mk.cyl(lamp, 0.3, 0.4, 0.6, Vector3(0, 0.3, 0), Color.WHITE, true, 8)
	var pole := Mk.cyl(lamp, 0.1, 0.16, 4.6, Vector3(0, 2.9, 0), Color.WHITE, true, 8)
	pole.material_override = mat_pole

	# Traverse cintrée à double volute
	Mk.box(lamp, Vector3(1.6, 0.1, 0.1), Vector3(0, 4.8, 0), Color.WHITE, false, mat_pole)

	# Deux lanternes hexagonales pendantes avec ampoules chaudes
	var mat_glass := StandardMaterial3D.new()
	mat_glass.albedo_color = Color(1.0, 0.9, 0.6, 0.6)
	mat_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_glass.roughness = 0.1
	mat_glass.emission_enabled = true
	mat_glass.emission = Color("fde047")
	mat_glass.emission_energy_multiplier = 0.8

	for sx in [-0.7, 0.7]:
		var lant := Mk.cyl(lamp, 0.24, 0.16, 0.45, Vector3(sx, 4.5, 0), Color.WHITE, false, 6)
		lant.material_override = mat_glass
		Mk.cyl(lamp, 0.02, 0.26, 0.15, Vector3(sx, 4.8, 0), Color("1e293b"), false, 6)

	# Lumière chaleureuse des lampadaires
	var omni := OmniLight3D.new()
	omni.light_color = Color("fef08a")
	omni.light_energy = 1.9
	omni.omni_range = 13.0
	omni.position = Vector3(0, 4.4, 0)
	lamp.add_child(omni)


## Parterres floraux géométriques sénégalais (Hibiscus et Bougainvilliers)
func _make_geometric_flowerbeds(parent: Node3D, center: Vector3) -> void:
	var mat_soil: Material = Mk.grass(Color("166534"), 0.85)

	var offsets: Array[Vector3] = [
		Vector3(14.0, 0, 14.0),
		Vector3(-14.0, 0, 14.0),
		Vector3(14.0, 0, -14.0),
		Vector3(-14.0, 0, -14.0),
	]

	for i in offsets.size():
		var fb_pos: Vector3 = center + offsets[i]
		var fb := Node3D.new()
		fb.name = "FlowerBed_%d" % i
		fb.position = fb_pos
		parent.add_child(fb)

		# Bordure en béton blanc
		Mk.cyl(fb, 3.4, 3.5, 0.25, Vector3(0, 0.12, 0), Color.WHITE, true, 16)
		# Terreau et gazon
		var grass_bed := Mk.cyl(fb, 3.2, 3.2, 0.05, Vector3(0, 0.22, 0), Color.WHITE, false, 16)
		grass_bed.material_override = mat_soil

		# Arbustes à fleurs tropicales du Sénégal (Hibiscus rouges et Bougainvilliers)
		var flower_cols := [Color("dc2626"), Color("db2777"), Color("ea580c"), Color("eab308")]
		for k in 6:
			var ang: float = k * TAU / 6.0
			var b_pos := Vector3(cos(ang) * 1.8, 0.55, sin(ang) * 1.8)
			# Feuillage vert
			Mk.sphere(fb, 0.5, b_pos, Color("15803d"), Vector3(1.1, 0.9, 1.1))
			# Fleurs éclatantes
			Mk.sphere(fb, 0.22, b_pos + Vector3(0, 0.25, 0), flower_cols[k % flower_cols.size()])
		# Buisson central fleuri
		Mk.sphere(fb, 0.7, Vector3(0, 0.65, 0), Color("166534"))
		Mk.sphere(fb, 0.35, Vector3(0, 1.05, 0), Color("dc2626"))


## Monument de la Renaissance Africaine (Colosse de 52m de bronze sur la colline de Ouakam)
func _make_african_renaissance_monument(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "MonumentRenaissanceAfricaine"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# 1. Colline volcanique étagée en basalte sombre (plateforme rocheuse des Mamelles)
	var mat_volcano := StandardMaterial3D.new()
	mat_volcano.albedo_color = Color("292524")
	mat_volcano.roughness = 0.9
	mat_volcano.uv1_triplanar = true

	# Terrasses rocheuses étagées
	var t1 := Mk.cyl(root, 36.0, 44.0, 5.0, Vector3(0, 2.5, 0), Color.WHITE, true, 16)
	t1.material_override = mat_volcano
	var t2 := Mk.cyl(root, 28.0, 36.0, 5.0, Vector3(0, 7.5, 0), Color.WHITE, true, 16)
	t2.material_override = mat_volcano
	var t3 := Mk.cyl(root, 22.0, 28.0, 5.0, Vector3(0, 12.5, 0), Color.WHITE, true, 16)
	t3.material_override = mat_volcano

	# 2. Grand escalier monumental de 198 marches
	var mat_stairs: Material = Mk.concrete_pbr(Color("d6d3d1"))
	for step in 12:
		var sy: float = step * 1.25
		var sz: float = 38.0 - step * 2.5
		Mk.box(root, Vector3(14.0, 1.3, 3.2), Vector3(0, sy + 0.65, sz), Color.WHITE, true, mat_stairs)
		# Garde-corps en pierre sur les côtés de l'escalier
		Mk.box(root, Vector3(0.5, 1.0, 3.2), Vector3(-7.25, sy + 1.8, sz), Color("57534e"), true)
		Mk.box(root, Vector3(0.5, 1.0, 3.2), Vector3(7.25, sy + 1.8, sz), Color("57534e"), true)

	# 3. Grande Esplanade / Belvédère sommital avec vue panoramique sur l'océan
	Mk.cyl(root, 20.0, 22.0, 1.2, Vector3(0, 15.6, 0), Color("e7e5e4"), true, 24)
	# Balustrade panoramique circulaire
	for k in 24:
		var ang: float = k * TAU / 24.0
		var p_b := Vector3(cos(ang) * 19.5, 16.7, sin(ang) * 19.5)
		var post := Mk.box(root, Vector3(0.35, 1.1, 0.35), p_b, Color("44403c"), true)
		post.rotation.y = -ang

	# 4. Le Colosse de Bronze Majestueux (52 mètres de hauteur !)
	var mat_bronze := StandardMaterial3D.new()
	mat_bronze.albedo_color = Color("78350f")
	mat_bronze.metallic = 0.88
	mat_bronze.roughness = 0.32
	mat_bronze.metallic_specular = 0.75

	var statue_base := Vector3(0, 16.2, 0)

	# Socle rocheux sculpté d'où jaillit la famille africaine
	var pedestal := Mk.cyl(root, 7.5, 9.5, 7.0, statue_base + Vector3(0, 3.5, 0), Color.WHITE, true, 12)
	pedestal.material_override = mat_volcano

	# L'Homme Africain (Le père athlétique jaillissant du volcan vers l'avenir)
	# Jambes puissantes
	var l_leg := Mk.cyl(root, 1.4, 1.8, 11.0, statue_base + Vector3(-2.2, 12.5, 1.2), Color.WHITE, true, 8)
	l_leg.material_override = mat_bronze
	l_leg.rotation.x = -0.15
	var r_leg := Mk.cyl(root, 1.4, 1.8, 11.0, statue_base + Vector3(2.2, 12.5, -1.2), Color.WHITE, true, 8)
	r_leg.material_override = mat_bronze
	r_leg.rotation.x = 0.15

	# Torse et buste colossal musclé
	var torso := Mk.box(root, Vector3(6.5, 12.0, 4.2), statue_base + Vector3(0, 23.5, 0), Color.WHITE, true, mat_bronze)
	torso.rotation.x = -0.08
	# Épaules et cou
	Mk.box(root, Vector3(8.5, 3.5, 4.5), statue_base + Vector3(0, 29.5, -0.4), Color.WHITE, true, mat_bronze)
	var neck := Mk.cyl(root, 1.3, 1.5, 3.0, statue_base + Vector3(0, 32.0, -0.4), Color.WHITE, true, 8)
	neck.material_override = mat_bronze

	# Tête altière du père regardant vers l'horizon
	var head := Mk.sphere(root, 2.2, statue_base + Vector3(0, 34.5, -0.4), Color.WHITE, Vector3(0.9, 1.2, 1.0))
	head.material_override = mat_bronze

	# Bras gauche portant triomphalement l'enfant vers les cieux
	var l_arm := Mk.cyl(root, 1.0, 1.3, 9.5, statue_base + Vector3(-4.8, 33.0, 0), Color.WHITE, true, 8)
	l_arm.material_override = mat_bronze
	l_arm.rotation.z = -0.45

	# L'Enfant porté sur l'épaule gauche
	var child_pos := statue_base + Vector3(-5.8, 38.0, 0.2)
	Mk.box(root, Vector3(2.0, 4.2, 1.6), child_pos, Color.WHITE, true, mat_bronze)
	var child_head := Mk.sphere(root, 1.1, child_pos + Vector3(0, 3.0, 0), Color.WHITE)
	child_head.material_override = mat_bronze
	# Bras de l'enfant tendu vers l'Ouest (indiquant l'océan et l'avenir)
	var point_arm := Mk.cyl(root, 0.35, 0.45, 4.8, child_pos + Vector3(-1.8, 3.2, 2.0), Color.WHITE, false, 6)
	point_arm.material_override = mat_bronze
	point_arm.rotation.x = PI * 0.45
	point_arm.rotation.y = -0.35

	# La Femme Africaine (La mère drapée se tenant gracieusement aux côtés de son époux)
	var mat_veil := StandardMaterial3D.new()
	mat_veil.albedo_color = Color("92400e")
	mat_veil.metallic = 0.82
	mat_veil.roughness = 0.4
	mat_veil.rim_enabled = true
	mat_veil.rim = 0.5

	var woman_pos := statue_base + Vector3(4.8, 16.0, 1.8)
	var w_torso := Mk.box(root, Vector3(3.6, 8.5, 2.8), woman_pos + Vector3(0, 4.25, 0), Color.WHITE, true, mat_bronze)
	w_torso.rotation.z = 0.15
	var w_head := Mk.sphere(root, 1.5, woman_pos + Vector3(0.6, 9.5, 0), Color.WHITE, Vector3(0.9, 1.1, 1.0))
	w_head.material_override = mat_bronze
	# Grand voile flottant en bronze sculpté dans le vent marin
	var veil := Mk.box(root, Vector3(4.2, 12.0, 0.6), woman_pos + Vector3(2.6, 3.5, -1.8), Color.WHITE, false, mat_veil)
	veil.rotation.y = 0.35
	veil.rotation.x = -0.2

	# 5. Grande Stèle commémorative au bas de l'escalier avec la photo réelle
	var plaque_pos := Vector3(0, 0.5, 46.0)
	var plaque_w := 7.0
	var plaque_h := 4.2
	Mk.box(root, Vector3(plaque_w + 0.6, plaque_h + 0.8, 0.4), plaque_pos + Vector3(0, plaque_h * 0.5, 0), Color("1c1917"), true)
	var tex_photo: Texture2D = Mk.load_texture("res://textures/world/renaissance_monument.jpg")
	if tex_photo != null:
		var mat_p := StandardMaterial3D.new()
		mat_p.albedo_texture = tex_photo
		mat_p.roughness = 0.35
		mat_p.metallic_specular = 0.6
		Mk.box(root, Vector3(plaque_w, plaque_h, 0.08), plaque_pos + Vector3(0, plaque_h * 0.5, 0.22), Color.WHITE, false, mat_p)

	# Inscription monumentale
	var l1 := Label3D.new()
	l1.text = "MONUMENT DE LA RENAISSANCE AFRICAINE • DAKAR"
	l1.font_size = 36
	l1.outline_size = 10
	l1.modulate = Color("f59e0b")
	l1.position = plaque_pos + Vector3(0, plaque_h + 0.85, 0.25)
	root.add_child(l1)

	var l2 := Label3D.new()
	l2.text = "Plus haut monument d'Afrique (52 Mètres de Bronze) • Ouakam, Dakar"
	l2.font_size = 24
	l2.outline_size = 6
	l2.modulate = Color("fef08a")
	l2.position = plaque_pos + Vector3(0, plaque_h + 0.45, 0.25)
	root.add_child(l2)

	# 6. Faisceaux lumineux nocturnes (Projecteurs haute puissance vers le ciel)
	var spot_angles: Array[float] = [-0.6, 0.6, -1.8, 1.8]
	for sa: float in spot_angles:
		var spot := SpotLight3D.new()
		spot.light_color = Color("fde047")
		spot.light_energy = 5.0
		spot.spot_range = 95.0
		spot.spot_angle = 24.0
		spot.position = statue_base + Vector3(sin(sa) * 16.0, 1.5, cos(sa) * 16.0)
		spot.rotation.x = -PI * 0.38
		spot.rotation.y = sa
		root.add_child(spot)

	Mk.label(root, "MONUMENT DE LA RENAISSANCE AFRICAINE (52m)", statue_base + Vector3(0, 52.0, 0), 48, Color("fbbf24"))


## Porte du Troisième Millénaire (Corniche Ouest de Dakar)
func _make_porte_du_millenaire(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "PorteDuMillenaire"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# 1. Grande esplanade côtière pavée en pierre claire
	var mat_esplanade: Material = Mk.concrete_pbr(Color("f8fafc"))
	Mk.box(root, Vector3(32.0, 0.5, 24.0), Vector3(0, 0.25, 0), Color.WHITE, true, mat_esplanade)
	# Balustrade maritime le long de la Corniche
	Mk.box(root, Vector3(32.0, 1.0, 0.3), Vector3(0, 1.0, -11.8), Color("334155"), true)

	# 2. Les Trois Arches / Piliers Courbés Monumentaux (16 mètres de haut)
	var mat_pylons := StandardMaterial3D.new()
	mat_pylons.albedo_color = Color("ffffff")
	mat_pylons.roughness = 0.25
	mat_pylons.metallic = 0.05
	mat_pylons.clearcoat_enabled = true
	mat_pylons.clearcoat = 0.6

	# Arche 1 (Centrale, la plus haute, 16.5m)
	var pylon_c1 := Mk.box(root, Vector3(1.4, 16.5, 1.2), Vector3(-4.0, 8.25, 0), Color.WHITE, true, mat_pylons)
	pylon_c1.rotation.z = -0.08
	var pylon_c2 := Mk.box(root, Vector3(1.4, 16.5, 1.2), Vector3(4.0, 8.25, 0), Color.WHITE, true, mat_pylons)
	pylon_c2.rotation.z = 0.08
	# Lintel courbe au sommet
	Mk.box(root, Vector3(9.2, 1.2, 1.4), Vector3(0, 16.2, 0), Color.WHITE, true, mat_pylons)

	# Arche 2 (Avant, 13.5m)
	var pylon_f1 := Mk.box(root, Vector3(1.2, 13.5, 1.0), Vector3(-7.5, 6.75, 4.0), Color.WHITE, true, mat_pylons)
	pylon_f1.rotation.z = -0.12
	var pylon_f2 := Mk.box(root, Vector3(1.2, 13.5, 1.0), Vector3(7.5, 6.75, 4.0), Color.WHITE, true, mat_pylons)
	pylon_f2.rotation.z = 0.12
	Mk.box(root, Vector3(14.0, 1.0, 1.2), Vector3(0, 13.2, 4.0), Color.WHITE, true, mat_pylons)

	# Arche 3 (Arrière, 11.0m)
	var pylon_b1 := Mk.box(root, Vector3(1.0, 11.0, 0.9), Vector3(-10.0, 5.5, -4.0), Color.WHITE, true, mat_pylons)
	pylon_b1.rotation.z = -0.15
	var pylon_b2 := Mk.box(root, Vector3(1.0, 11.0, 0.9), Vector3(10.0, 5.5, -4.0), Color.WHITE, true, mat_pylons)
	pylon_b2.rotation.z = 0.15
	Mk.box(root, Vector3(18.0, 0.9, 1.0), Vector3(0, 10.8, -4.0), Color.WHITE, true, mat_pylons)

	# Fissures décoratives et ouvertures contemporaines
	for i in 5:
		var hy: float = 4.0 + i * 2.2
		Mk.box(root, Vector3(7.0, 0.35, 0.4), Vector3(0, hy, 0), Color("0284c7"))

	# 3. Statue en bronze du Joueur de Kora / Flûte traditionnel
	var statue_base := Vector3(0, 0.5, 0)
	Mk.cyl(root, 1.6, 1.9, 1.4, statue_base + Vector3(0, 0.7, 0), Color("334155"), true, 12)
	var mat_musician := StandardMaterial3D.new()
	mat_musician.albedo_color = Color("78350f")
	mat_musician.metallic = 0.85
	mat_musician.roughness = 0.35

	# Corps du musicien assis en tailleur
	Mk.box(root, Vector3(1.4, 0.8, 1.2), statue_base + Vector3(0, 1.8, 0), Color.WHITE, true, mat_musician)
	Mk.box(root, Vector3(0.9, 1.4, 0.8), statue_base + Vector3(0, 2.8, 0), Color.WHITE, true, mat_musician)
	var m_head := Mk.sphere(root, 0.38, statue_base + Vector3(0, 3.8, 0), Color.WHITE)
	m_head.material_override = mat_musician

	# La Kora traditionnelle (calebasse hémisphérique, manche en bois, cordes)
	Mk.sphere(root, 0.55, statue_base + Vector3(0.35, 2.4, 0.4), Color("b45309"), Vector3(1.0, 0.9, 0.8))
	Mk.cyl(root, 0.05, 0.05, 1.9, statue_base + Vector3(0.35, 3.1, 0.4), Color("d97706"), false, 6)

	# 4. Éclairage architectural nocturne bleu océan et or
	var light_blue := OmniLight3D.new()
	light_blue.light_color = Color("38bdf8")
	light_blue.light_energy = 3.0
	light_blue.omni_range = 18.0
	light_blue.position = Vector3(0, 3.0, 0)
	root.add_child(light_blue)

	# Titre officiel
	Mk.label(root, "PORTE DU TROISIÈME MILLÉNAIRE • DAKAR", Vector3(0, 18.0, 0), 40, Color("f8fafc"))


## Grande Mosquée de Dakar (Minaret hispano-mauresque de 67m, Allée Pape Gueye Fall)
func _make_grande_mosquee_minaret(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "GrandeMosqueeMinaret"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# Matériaux du minaret hispano-mauresque
	var mat_stone: Material = Mk.concrete_pbr(Color("fef08a")) # Grès ocre saharien
	var mat_white: Material = Mk.concrete_pbr(Color("f8fafc")) # Enduit blanc
	var mat_green := StandardMaterial3D.new() # Cuivre patiné vert émeraude
	mat_green.albedo_color = Color("047857")
	mat_green.roughness = 0.45
	var mat_gold := StandardMaterial3D.new() # Laiton doré des croissants
	mat_gold.albedo_color = Color("fbbf24")
	mat_gold.metallic = 0.92
	mat_gold.roughness = 0.15

	# Socle carré monumental
	Mk.box(root, Vector3(8.5, 3.0, 8.5), Vector3(0, 1.5, 0), Color.WHITE, true, mat_stone)

	# Tour principale carrée de 67 mètres
	var shaft_w := 6.6
	for level in 6:
		var ly: float = 3.0 + level * 8.0
		var m: Material = mat_stone if level % 2 == 0 else mat_white
		Mk.box(root, Vector3(shaft_w, 8.0, shaft_w), Vector3(0, ly + 4.0, 0), Color.WHITE, true, m)

		# Moucharabiehs / Fenêtres géométriques polylobées sur les 4 faces
		for face in 4:
			var ang: float = face * TAU / 4.0
			var w_pos := Vector3(cos(ang) * (shaft_w * 0.5 + 0.05), ly + 4.2, sin(ang) * (shaft_w * 0.5 + 0.05))
			var arch := Mk.box(root, Vector3(1.2, 3.2, 0.1), w_pos, Color("14532d"))
			arch.rotation.y = -ang + PI * 0.5
			# Grille géométrique islamique dorée
			Mk.box(root, Vector3(0.9, 2.8, 0.04), w_pos + Vector3(0, 0, 0.02), Color("fbbf24"))

	# Balcon supérieur du Muezzin à 51m
	var balc_y := 51.0
	Mk.box(root, Vector3(shaft_w + 1.6, 1.2, shaft_w + 1.6), Vector3(0, balc_y, 0), Color.WHITE, true, mat_stone)
	# Garde-corps ajouré en marbre blanc
	Mk.box(root, Vector3(shaft_w + 1.6, 1.1, 0.2), Vector3(0, balc_y + 1.1, (shaft_w + 1.6) * 0.5), Color.WHITE, true, mat_white)
	Mk.box(root, Vector3(shaft_w + 1.6, 1.1, 0.2), Vector3(0, balc_y + 1.1, -(shaft_w + 1.6) * 0.5), Color.WHITE, true, mat_white)
	Mk.box(root, Vector3(0.2, 1.1, shaft_w + 1.6), Vector3((shaft_w + 1.6) * 0.5, balc_y + 1.1, 0), Color.WHITE, true, mat_white)
	Mk.box(root, Vector3(0.2, 1.1, shaft_w + 1.6), Vector3(-(shaft_w + 1.6) * 0.5, balc_y + 1.1, 0), Color.WHITE, true, mat_white)

	# Touron supérieur (Lanternon carré, 3.8m x 3.8m x 9m)
	var lantern_y := balc_y + 1.2
	Mk.box(root, Vector3(3.8, 8.5, 3.8), Vector3(0, lantern_y + 4.25, 0), Color.WHITE, true, mat_stone)
	for face in 4:
		var ang: float = face * TAU / 4.0
		var arch2 := Mk.box(root, Vector3(0.8, 2.2, 0.1), Vector3(cos(ang) * 1.95, lantern_y + 4.2, sin(ang) * 1.95), Color("047857"))
		arch2.rotation.y = -ang + PI * 0.5

	# Dôme pyramidal vert émeraude traditionnel
	var dome_y := lantern_y + 8.5
	var dome := Mk.cyl(root, 0.1, 2.6, 4.5, Vector3(0, dome_y + 2.25, 0), Color.WHITE, true, 4)
	dome.material_override = mat_green
	dome.rotation.y = PI * 0.25

	# Spire et Jamour doré (Les 3 sphères sacrées en laiton surmontées du Croissant)
	var spire_base := dome_y + 4.5
	var spire_pole := Mk.cyl(root, 0.08, 0.08, 3.5, Vector3(0, spire_base + 1.75, 0), Color.WHITE, false, 8)
	spire_pole.material_override = mat_gold
	var sp1 := Mk.sphere(root, 0.42, Vector3(0, spire_base + 1.0, 0), Color.WHITE)
	sp1.material_override = mat_gold
	var sp2 := Mk.sphere(root, 0.30, Vector3(0, spire_base + 2.0, 0), Color.WHITE)
	sp2.material_override = mat_gold
	var sp3 := Mk.sphere(root, 0.20, Vector3(0, spire_base + 2.8, 0), Color.WHITE)
	sp3.material_override = mat_gold
	# Croissant de lune au sommet du minaret
	var crescent := Mk.cyl(root, 0.35, 0.35, 0.06, Vector3(0, spire_base + 3.6, 0), Color.WHITE, false, 8)
	crescent.material_override = mat_gold
	crescent.rotation.x = PI * 0.5

	# Éclairage nocturne vert islamique solennel
	var green_omni := OmniLight3D.new()
	green_omni.light_color = Color("10b981")
	green_omni.light_energy = 3.5
	green_omni.omni_range = 25.0
	green_omni.position = Vector3(0, 20.0, 0)
	root.add_child(green_omni)

	Mk.label(root, "GRANDE MOSQUÉE DE DAKAR (MINARET 67m)", Vector3(0, 67.0, 0), 44, Color("10b981"))


## Phare des Mamelles (Phare historique de 1864, Cap Manuel / Mamelles, Ouakam)
func _make_phare_des_mamelles(parent: Node3D, pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.name = "PhareDesMamelles"
	root.position = pos
	root.rotation.y = yaw
	parent.add_child(root)

	# Bâtiment de garde colonial à la base (toit de tuiles rouges)
	Mk.box(root, Vector3(12.0, 4.0, 10.0), Vector3(0, 2.0, 0), Color("f8fafc"), true)
	Mk.box(root, Vector3(12.8, 0.8, 10.8), Vector3(0, 4.4, 0), Color("c2410c"), true)

	# Tour cylindrique blanche conique du phare (1864, 21m)
	var mat_tower := StandardMaterial3D.new()
	mat_tower.albedo_color = Color("ffffff")
	mat_tower.roughness = 0.2
	var tower := Mk.cyl(root, 2.0, 2.8, 18.0, Vector3(0, 13.0, 0), Color.WHITE, true, 16)
	tower.material_override = mat_tower

	# Fenêtres hublots sur la tour
	for wy in [8.0, 12.0, 16.0]:
		Mk.box(root, Vector3(0.5, 0.9, 0.3), Vector3(0, wy, 2.4 - (wy - 8.0) * 0.05), Color("0f172a"))

	# Galerie de ronde et passerelle panoramique
	var gal_y := 22.0
	Mk.cyl(root, 3.2, 3.2, 0.4, Vector3(0, gal_y, 0), Color("1e293b"), true, 16)
	# Balustrade en fer forgé noir
	for k in 16:
		var ang: float = k * TAU / 16.0
		var p_b := Vector3(cos(ang) * 3.0, gal_y + 0.6, sin(ang) * 3.0)
		Mk.box(root, Vector3(0.08, 0.9, 0.08), p_b, Color("0f172a"), false)

	# Chambre de la lanterne (vitrée avec montants en fonte)
	var mat_lantern_glass := StandardMaterial3D.new()
	mat_lantern_glass.albedo_color = Color(1.0, 0.95, 0.7, 0.4)
	mat_lantern_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_lantern_glass.emission_enabled = true
	mat_lantern_glass.emission = Color("fef08a")
	mat_lantern_glass.emission_energy_multiplier = 1.5

	var lantern_room := Mk.cyl(root, 1.8, 1.8, 2.6, Vector3(0, gal_y + 1.5, 0), Color.WHITE, true, 12)
	lantern_room.material_override = mat_lantern_glass

	# Coupole rouge écarlate et paratonnerre
	Mk.sphere(root, 1.9, Vector3(0, gal_y + 2.8, 0), Color("b91c1c"), Vector3(1.0, 0.6, 1.0))
	Mk.cyl(root, 0.04, 0.04, 1.8, Vector3(0, gal_y + 4.5, 0), Color("fbbf24"), false, 6)

	# Faisceau rotatif puissant du phare balayant l'océan
	var beacon := SpotLight3D.new()
	beacon.name = "PhareBeacon"
	beacon.light_color = Color("fffbeb")
	beacon.light_energy = 6.5
	beacon.spot_range = 140.0
	beacon.spot_angle = 15.0
	beacon.position = Vector3(0, gal_y + 1.5, 0)
	beacon.rotation.x = -0.05
	root.add_child(beacon)

	Mk.label(root, "PHARE DES MAMELLES (1864) • DAKAR", Vector3(0, 28.0, 0), 40, Color("fef08a"))


