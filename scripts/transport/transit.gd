extends Node3D
## Transports en commun, comme passager et en payant :
## - lignes de bus avec abribus : attendre à l'arrêt, monter (200 FCFA), descendre au prochain arrêt ;
## - car rapide (150 FCFA) : on le hèle dans la rue, on descend quand on veut ;
## - taxi : on choisit sa destination, le prix dépend de la distance, le taxi t'y conduit.

const Mk = preload("res://scripts/util/mk.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")

const BUS_FARE := 200
const CAR_RAPIDE_FARE := 150
const LINES := [
	{"name": "Ligne 1", "type": "bus", "color": Color("f39200"), "buses": 2,
		"stops": ["Place de l'Indépendance", "Marché Sandaga", "Restaurant Maïga", "Gare routière Petersen", "Marché Tilène", "Grande Mosquée"]},
	{"name": "Ligne 2", "type": "coach", "color": Color("2f7fc0"), "buses": 2,
		"stops": ["Gare de Dakar", "Marché Kermel", "Hôpital Principal", "Assemblée nationale", "Cathédrale", "Porte du Millénaire"]},
	{"name": "SunuBRT Ligne 1", "type": "brt", "color": Color("00a896"), "buses": 2,
		"stops": ["Gare routière Petersen", "Marché Tilène", "Grande Mosquée", "Stade Iba Mar Diop", "Porte du Millénaire"]},
]
const TAXI_PLACES := ["Place de l'Indépendance", "Marché Sandaga", "Grande Mosquée", "Hôpital Principal", "Gare de Dakar",
	"Marché Kermel", "Marché Tilène", "Gare routière Petersen", "Cathédrale", "Assemblée nationale",
	"Porte du Millénaire", "Stade Iba Mar Diop", "Chez Adja", "Dibiterie", "Restaurant Maïga", "Café Touba"]

var city
var player
var hud
var arena
var foot ## complexe de mini-foot (scripts/world/foot.gd)
var stops: Array = [] ## {name, line, pos}
var buses: Array = []
var status := ""
var _waiting = null
var _ride = null
var _ride_kind := ""
var _want_stop := false
var _alight := false
var _taxi_dest := ""


func _ready() -> void:
	for line in LINES:
		_build_line(line)


# --- Lignes de bus -----------------------------------------------------------------

func _build_line(line: Dictionary) -> void:
	var names: Array = []
	for n in line["stops"]:
		if city.places.has(n):
			names.append(n)
	if names.size() < 2:
		return
	var pts := PackedVector3Array()
	var stop_idx := {}
	for k in names.size():
		var a: Vector3 = city.places[names[k]]
		var b: Vector3 = city.places[names[(k + 1) % names.size()]]
		var seg: PackedVector3Array = city.route(a, b, true)
		if seg.size() < 2:
			continue
		if pts.is_empty():
			pts.append_array(seg)
		else:
			pts.append_array(seg.slice(1))
		stop_idx[pts.size() - 1] = names[(k + 1) % names.size()]
	if pts.size() < 4:
		return
	for i in stop_idx:
		var d := pts[i] - pts[maxi(0, i - 1)]
		d.y = 0.0
		d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
		var right := Vector3(-d.z, 0, d.x)
		var pos := _stop_spot(pts[i], d, right)
		if pos == Vector3.INF:
			continue
		stops.append({"name": stop_idx[i], "line": line["name"], "pos": pos})
		_shelter(pos, d, line, stop_idx[i])
	# Bus répartis le long de la ligne
	var count: int = line["buses"]
	for b in count:
		# Départ entre deux arrêts (jamais sur un arrêt où des voitures sont garées)
		var start := 1 + int((float(b) + 0.5) / count * (pts.size() - 2))
		var v = Vehicle.new()
		v.vehicle_type = line["type"]
		add_child(v)
		v.ai_city = city
		v.line_name = line["name"]
		v.global_position = pts[start - 1] + Vector3(0, 0.3, 0)
		var dir := pts[start] - pts[start - 1]
		v.rotation.y = atan2(-dir.x, -dir.z)
		v.follow_route(pts, true, stop_idx)
		v.route_i = start
		v.reached_stop.connect(_on_bus_stop.bind(v))
		buses.append(v)


## Emplacement de l'abribus : sur le trottoir de droite, un peu avant le carrefour (jamais sur la chaussée).
func _stop_spot(node: Vector3, d: Vector3, right: Vector3) -> Vector3:
	for back in [8.0, 12.0, 4.0, 16.0, 20.0, 0.0]:
		var base: Vector3 = node - d * back
		var r := 3.0
		while r <= 16.0:
			var p: Vector3 = base + right * r
			# Premier point du trottoir où l'abribus (1,8 m de large) ne déborde pas sur la chaussée
			if not city.in_roadway(p, 1.2):
				return p
			r += 0.5
	return Vector3.INF


## Abribus : toit aux couleurs de la ligne, banc, poteau et panneau.
func _shelter(pos: Vector3, dir: Vector3, line: Dictionary, stop_name: String) -> void:
	var h := Node3D.new()
	add_child(h)
	h.position = Vector3(pos.x, 0.07, pos.z)
	h.rotation.y = atan2(-dir.x, -dir.z)
	var col: Color = line["color"]
	Mk.box(h, Vector3(1.4, 0.1, 3.4), Vector3(0.2, 2.45, 0), col)
	for z in [-1.5, 1.5]:
		Mk.box(h, Vector3(0.08, 2.4, 0.08), Vector3(0.75, 1.2, z), Color("c9ccd1"))
	Mk.box(h, Vector3(0.04, 1.6, 3.0), Vector3(0.78, 1.4, 0), Color(0.7, 0.85, 0.95, 0.35))
	Mk.box(h, Vector3(0.45, 0.08, 2.6), Vector3(0.45, 0.5, 0), Color("6b4f3a"), true)
	Mk.cyl(h, 0.04, 0.04, 2.8, Vector3(-0.5, 1.4, 1.9), Color("c9ccd1"), false, 6)
	Mk.box(h, Vector3(0.05, 0.6, 0.6), Vector3(-0.5, 2.7, 1.9), col)
	if line.get("type", "") == "brt":
		Mk.label(h, "⚡ SUNUBRT (100% Électrique)\n%s — %s FCFA\nArrêt : %s" % [line["name"], BUS_FARE, stop_name], Vector3(0, 3.2, 0), Mk.SIGN_SIZE - 4, Color("00a896"))
	else:
		Mk.label(h, "BUS\n%s — %s FCFA\n%s" % [line["name"], BUS_FARE, stop_name], Vector3(0, 3.2, 0), Mk.SIGN_SIZE - 4, Color.WHITE)


func _on_bus_stop(stop_name: String, bus) -> void:
	if _ride == bus:
		if _want_stop:
			GameState.notify.emit("Arrêt %s. Bonne journée !" % stop_name)
			_end_ride()
		else:
			GameState.notify.emit("%s — arrêt : %s" % [bus.line_name, stop_name])
		return
	if _ride == null and _waiting != null and _waiting["name"] == stop_name and _waiting["line"] == bus.line_name:
		if player.global_position.distance_to(_waiting["pos"]) < 12.0:
			_board_bus(bus)


func _board_bus(bus) -> void:
	if not GameState.spend(BUS_FARE):
		GameState.notify.emit("Le receveur : « Il faut %s pour le bus ! »" % GameState.fcfa(BUS_FARE))
		_waiting = null
		return
	GameState.notify.emit("Tu montes dans le bus %s (-%s). [E] pour descendre au prochain arrêt." % [bus.line_name, GameState.fcfa(BUS_FARE)])
	_start_ride(bus, "bus")


# --- Monter, descendre --------------------------------------------------------------

func _start_ride(v, kind: String) -> void:
	_ride = v
	_ride_kind = kind
	_want_stop = false
	_alight = false
	_waiting = null
	player.ride(v)
	v.set_passenger(player)


func _end_ride() -> void:
	var v = _ride
	if v == null:
		return
	_ride = null
	_alight = false
	player.end_ride()
	v.set_passenger(null)
	if _ride_kind == "taxi":
		v.resume_traffic()
	elif _ride_kind == "car_rapide":
		v.hold = false


## Le joueur appuie sur ACTION pendant le trajet.
func ride_interact() -> void:
	match _ride_kind:
		"bus":
			_want_stop = true
			GameState.notify.emit("Tu descendras au prochain arrêt.")
		_:
			_ride.hold = true
			_ride.route_active = false
			_alight = true


## Quitte le véhicule tout de suite (arrestation, évanouissement...).
func cancel_ride() -> void:
	if _ride != null:
		_end_ride()
	_waiting = null


func is_riding() -> bool:
	return _ride != null


func _public_vehicle_near(pp: Vector3) -> Variant:
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.driver != null or v.passenger != null or v.chasing:
			continue
		var reach: float = maxf(v.size.z * 0.5 + 2.8, 5.0)
		var d_horiz := Vector2(pp.x - v.global_position.x, pp.z - v.global_position.z).length()
		if d_horiz > reach or absf(pp.y - v.global_position.y) > 3.0:
			continue
		if v.vehicle_type in ["taxi", "car_rapide", "ndiaga"] and (v.ai_enabled or v.has_meta("net_id")):
			return v
		if v.line_name != "" and absf(v.speed) < 2.0:
			return v
	return null


func _stop_near(pp: Vector3) -> Variant:
	for s in stops:
		if Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length() < 3.5:
			return s
	return null


func try_interact() -> bool:
	if _ride != null or player.current_vehicle != null:
		return false
	var pp: Vector3 = player.global_position
	var s = _stop_near(pp)
	if s != null:
		if _waiting == s:
			_waiting = null
			GameState.notify.emit("Tu ne prends plus le bus.")
		else:
			_waiting = s
			GameState.notify.emit("Tu attends le bus %s à l'arrêt %s." % [s["line"], s["name"]])
		return true
	var v = _public_vehicle_near(pp)
	if v == null:
		return false
	if v.has_meta("net_id"):
		v.get_meta("net_owner").convert(v) # le taxi quitte le trafic partagé
	if v.line_name != "":
		_board_bus(v)
	elif v.vehicle_type in ["car_rapide", "ndiaga"]:
		if GameState.spend(CAR_RAPIDE_FARE):
			if v.vehicle_type == "ndiaga":
				GameState.notify.emit("Tu montes dans le Ndiaga Ndiaye (-%s). L'apprenti tape sur la carrosserie : « Colobane, Grand-Yoff ! »" % GameState.fcfa(CAR_RAPIDE_FARE))
			else:
				GameState.notify.emit("Tu montes dans le car rapide (-%s). L'apprenti crie : « Petersen, Sandaga, Médina ! »" % GameState.fcfa(CAR_RAPIDE_FARE))
			_start_ride(v, "car_rapide")
		else:
			GameState.notify.emit("L'apprenti : « C'est %s, grand ! »" % GameState.fcfa(CAR_RAPIDE_FARE))
	else:
		_hail_taxi(v)
	return true


func get_hint() -> String:
	if _ride != null or player.current_vehicle != null:
		return ""
	var pp: Vector3 = player.global_position
	var s = _stop_near(pp)
	if s != null:
		return "Ne plus attendre le bus" if _waiting == s else "Attendre le bus %s (%s)" % [s["line"], GameState.fcfa(BUS_FARE)]
	var v = _public_vehicle_near(pp)
	if v != null:
		var price := "" if v.vehicle_type == "taxi" else " (%s)" % GameState.fcfa(BUS_FARE if v.line_name != "" else CAR_RAPIDE_FARE)
		return "Monter comme passager : %s%s   •   [G] Conduire" % [v.display_name, price]
	return ""


# --- Taxi : choisir sa destination ------------------------------------------------

func taxi_price(from: Vector3, to: Vector3) -> int:
	var d := Vector2(from.x - to.x, from.z - to.z).length()
	# Tarif réaliste à Dakar : prise en charge + environ 400 FCFA par kilomètre (3 km ≈ 1 700 FCFA)
	return maxi(500, int(round((500.0 + d * 0.4) / 50.0)) * 50)


func _hail_taxi(v) -> void:
	v.hold = true
	var pp: Vector3 = player.global_position
	var options: Array = []
	for place_name in TAXI_PLACES:
		if not city.places.has(place_name):
			continue
		var pos: Vector3 = city.places[place_name]
		if pos.distance_to(pp) < 60.0:
			continue
		var price := taxi_price(pp, pos)
		options.append([price, place_name])
	options.sort_custom(func(a, b): return a[0] < b[0])
	var choices: Array = []
	for o in options.slice(0, 8):
		choices.append(["%s — %s" % [o[1], GameState.fcfa(o[0])], start_taxi_ride.bind(v, o[1])])
	if arena:
		choices.append(["Arène nationale (Pikine) — %s" % GameState.fcfa(arena.TAXI_FARE), func():
			v.hold = false
			arena.travel_to_arena("taxi")])
	if foot:
		choices.append(["Complexe de mini-foot — %s" % GameState.fcfa(foot.TAXI_FARE), func():
			v.hold = false
			foot.travel_to_complex("taxi")])
	hud.show_choices("Taxi — « Où on va, grand ? »", choices, func(): v.hold = false)


func start_taxi_ride(v, dest: String) -> void:
	var price := taxi_price(player.global_position, city.places[dest])
	if not GameState.spend(price):
		GameState.notify.emit("Le taximan : « C'est %s, tu n'as pas assez ! »" % GameState.fcfa(price))
		v.hold = false
		return
	_taxi_dest = dest
	_start_ride(v, "taxi")
	v.hold = false
	v.follow_route(city.route(v.global_position, city.places[dest], true), false)
	if not v.route_finished.is_connected(_on_taxi_arrived):
		v.route_finished.connect(_on_taxi_arrived)
	GameState.notify.emit("« Waaw, dem nañu ! » (allons-y) — %s pour %s." % [GameState.fcfa(price), dest])


func _on_taxi_arrived() -> void:
	if _ride_kind != "taxi" or _ride == null:
		return
	GameState.notify.emit("Arrivé : %s. « Jërëjëf, ba beneen yoon ! »" % _taxi_dest)
	_end_ride()


# --- Suivi --------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _ride != null:
		if not is_instance_valid(_ride):
			_ride = null
			player.end_ride()
			return
		if _alight and absf(_ride.speed) < 1.0:
			_end_ride()
			return
		match _ride_kind:
			"bus":
				status = "BUS %s — %s" % [_ride.line_name, "tu descends au prochain arrêt" if _want_stop else "[E] descendre au prochain arrêt"]
			"taxi":
				status = "TAXI vers %s (%d m) — [E] descendre ici" % [_taxi_dest, int(player.get_world_position().distance_to(city.places[_taxi_dest]))]
			_:
				status = "%s — [E] « Descente ! »" % _ride.display_name.to_upper()
		return
	if _waiting != null:
		if player.global_position.distance_to(_waiting["pos"]) > 10.0 or player.current_vehicle != null:
			_waiting = null
			status = ""
			return
		var best := INF
		for b in buses:
			if b.line_name == _waiting["line"]:
				best = minf(best, b.global_position.distance_to(_waiting["pos"]))
		status = "Tu attends le bus %s à l'arrêt %s — prochain bus à ~%d m" % [_waiting["line"], _waiting["name"], int(best)]
		return
	status = ""
