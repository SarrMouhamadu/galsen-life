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
		"stops": ["Gare de Dakar", "Marché Kermel", "Hôpital Principal", "Assemblée nationale", "Cathédrale", "Porte du Millénaire", "Monument de la Renaissance Africaine"]},
	{"name": "SunuBRT Ligne 1", "type": "brt", "color": Color("00a896"), "buses": 2,
		"stops": ["Gare routière Petersen", "Marché Tilène", "Grande Mosquée", "Stade Iba Mar Diop", "Porte du Millénaire"]},
]
const TAXI_CATEGORIES := [
	{
		"id": "sports",
		"icon": "⚽",
		"title": "Stades & Sports",
		"places": [
			{"name": "Stade Iba Mar Diop (Médina)", "place": "Stade Iba Mar Diop"},
			{"name": "Stade Me Abdoulaye Wade (Diamniadio)", "special": "wade", "fare": 2500},
			{"name": "Arène nationale de Lutte (Pikine)", "special": "arena", "fare": 1500},
			{"name": "Complexe de mini-foot", "special": "foot", "fare": 1200},
			{"name": "Terrain Camp Abdou Diassé", "place": "Terrain Camp Abdou Diassé"},
			{"name": "Terrain de foot", "place": "Terrain de foot"},
			{"name": "Terrain de basket", "place": "Terrain de basket"},
			{"name": "Courts de tennis", "place": "Courts de tennis"},
		]
	},
	{
		"id": "marches",
		"icon": "🛒",
		"title": "Marchés & Boutiques",
		"places": [
			{"name": "Marché Sandaga (Plateau)", "place": "Marché Sandaga"},
			{"name": "Marché Kermel", "place": "Marché Kermel"},
			{"name": "Marché Tilène (Médina)", "place": "Marché Tilène"},
			{"name": "Centre commercial SAHM", "place": "Centre commercial SAHM"},
			{"name": "Supermarché Auchan", "place": "Auchan"},
			{"name": "Boutique Wave / Orange Money", "place": "Wave"},
			{"name": "Boutique Jumbo / Jadida", "place": "Jumbo"},
			{"name": "Concession auto de prestige", "special": "dealership"},
		]
	},
	{
		"id": "monuments",
		"icon": "🏛️",
		"title": "Monuments & Quartiers",
		"places": [
			{"name": "Place de l'Indépendance (Plateau)", "place": "Place de l'Indépendance"},
			{"name": "Monument de la Renaissance Africaine", "place": "Monument de la Renaissance Africaine"},
			{"name": "Porte du Millénaire (Corniche Ouest)", "place": "Porte du Millénaire"},
			{"name": "Phare des Mamelles (Ouakam)", "place": "Phare des Mamelles"},
			{"name": "Grande Mosquée de Dakar", "place": "Grande Mosquée"},
			{"name": "Assemblée nationale", "place": "Assemblée nationale"},
			{"name": "Commissariat Central Plateau", "place": "Commissariat (Dakar-Plateau)"},
			{"name": "Commissariat de la Médina", "place": "Commissariat"},
			{"name": "Caserne des Pompiers", "place": "Caserne"},
		]
	},
	{
		"id": "sante",
		"icon": "🏥",
		"title": "Hôpitaux & Santé",
		"places": [
			{"name": "Hôpital Principal de Dakar", "place": "Hôpital Principal"},
			{"name": "Hôpital Aristide Le Dantec", "place": "Hôpital Aristide Le Dantec"},
			{"name": "Polyclinique de la Médina", "place": "Polyclinique de la Médina"},
			{"name": "Cabinet Médical Zénith", "place": "CABINET MEDICAL ZENITH"},
			{"name": "Centre médico-social fonction publique", "place": "Centre medico-social de la fonction publique"},
		]
	},
	{
		"id": "transports",
		"icon": "🚆",
		"title": "Gares, TER & BRT",
		"places": [
			{"name": "Gare de Dakar (TER & Train)", "place": "Gare de Dakar"},
			{"name": "Gare routière Petersen (Bus & BRT)", "place": "Gare routière Petersen"},
		]
	},
	{
		"id": "culte",
		"icon": "🕌",
		"title": "Mosquées & Lieux de culte",
		"places": [
			{"name": "Grande Mosquée de Dakar", "place": "Grande Mosquée"},
			{"name": "Cathédrale de Dakar", "place": "Cathédrale"},
			{"name": "Mosquée Seydou Nourou Tall", "place": "Mosquée Seydou Nourou Tall"},
			{"name": "Église Saint-Laurent", "place": "Église Saint-Laurent"},
		]
	},
	{
		"id": "resto",
		"icon": "🍽️",
		"title": "Restaurants & Dibiteries",
		"places": [
			{"name": "Chez Adja (Thiéboudienne)", "place": "Chez Adja"},
			{"name": "Chez Loutcha (Cuisine sénégalaise)", "place": "Chez Loutcha"},
			{"name": "Restaurant Maïga (Plateau)", "place": "Restaurant Maïga"},
			{"name": "Restaurant Maïga (Médina)", "place": "Restaurant Maïga (Médina)"},
			{"name": "Restaurant Maïga (Petersen)", "place": "Restaurant Maïga (Petersen)"},
			{"name": "Restaurant Maïga (Marché Sandaga)", "place": "Restaurant Maïga (Marché Sandaga)"},
			{"name": "Restaurant Maïga (Marché Tilène)", "place": "Restaurant Maïga (Marché Tilène)"},
			{"name": "Restaurant Maïga (Grande Mosquée)", "place": "Restaurant Maïga (Grande Mosquée)"},
			{"name": "Restaurant Maïga (Stade Iba Mar Diop)", "place": "Restaurant Maïga (Stade Iba Mar Diop)"},
			{"name": "Restaurant Maïga (Gare de Dakar)", "place": "Restaurant Maïga (Gare de Dakar)"},
			{"name": "Restaurant Maïga (Fass Delorme)", "place": "Restaurant Maïga (Fass Delorme)"},
			{"name": "Restaurant Maïga (Rebeuss)", "place": "Restaurant Maïga (Rebeuss)"},
			{"name": "Restaurant Maïga (Marché Kermel)", "place": "Restaurant Maïga (Marché Kermel)"},
			{"name": "Dibiterie (Viande d'agneau grillée)", "place": "Dibiterie"},
			{"name": "Café Touba traditionnel", "place": "Café Touba"},
			{"name": "Chez Ndioufa", "place": "Chez Ndioufa"},
			{"name": "Planet Kebab", "place": "Restaurant planet kebab"},
			{"name": "Maxi Food", "place": "Restaurant Maxi Food"},
			{"name": "Maxi food", "place": "Restaurant Maxi food"},
			{"name": "Restaurant La Médinoise", "place": "Restaurant la Médinoise"},
			{"name": "Brioche Dorée", "place": "Restaurant Brioche Dorée"},
		]
	},
	{
		"id": "plages",
		"icon": "🏖️",
		"title": "Plages & Corniche",
		"places": [
			{"name": "Plage de l'Anse Bernard", "place": "Plage de l'Anse Bernard"},
			{"name": "Porte du Millénaire & Corniche Ouest", "place": "Porte du Millénaire"},
		]
	}
]

var city
var player
var hud
var arena
var foot ## complexe de mini-foot (scripts/world/foot.gd)
var stade ## stades Iba Mar Diop et Me Abdoulaye Wade (scripts/world/stade.gd)
var main
var stops: Array = [] ## {name, line, pos}
var buses: Array = []
var status := ""
var _waiting = null
var _ride = null
var _ride_kind := ""
var _want_stop := false
var _alight := false
var _taxi_dest := ""
var _taxi_dest_pos := Vector3.ZERO


func _ready() -> void:
	if not city:
		return
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
		Mk.label(h, "⚡ SUNUBRT (100%% Électrique)\n%s — %s FCFA\nArrêt : %s" % [line["name"], BUS_FARE, stop_name], Vector3(0, 3.2, 0), Mk.SIGN_SIZE - 4, Color("00a896"))
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
	var bus_label: String = bus.line_name if bus.line_name != "" else bus.display_name
	GameState.notify.emit("Tu montes dans le %s (-%s). [E] pour descendre." % [bus_label, GameState.fcfa(BUS_FARE)])
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
	elif _ride_kind == "car_rapide" or _ride_kind == "bus":
		v.hold = false
		if not v.route_active and v.ai_city != null:
			v.resume_traffic()


## Le joueur appuie sur ACTION pendant le trajet.
func ride_interact() -> void:
	match _ride_kind:
		"bus":
			if _ride != null and _ride.route_active:
				_want_stop = true
				GameState.notify.emit("Tu descendras au prochain arrêt.")
			else:
				if _ride != null:
					_ride.hold = true
					_ride.route_active = false
				_alight = true
				GameState.notify.emit("« Arrêt chauffeur ! » Tu descends du bus.")
		_:
			if _ride != null:
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
		if v.get_meta("taxi_patron", false) or v.get_meta("owned", false) or v.has_meta("rental") or v.get_meta("player_driver", false):
			continue
		var reach: float = maxf(v.size.z * 0.5 + 3.0, 5.2)
		var d_horiz := Vector2(pp.x - v.global_position.x, pp.z - v.global_position.z).length()
		if d_horiz > reach or absf(pp.y - v.global_position.y) > 3.5:
			continue
		if v.vehicle_type in ["taxi", "car_rapide", "ndiaga", "bus", "coach", "brt"]:
			return v
	return null


func _stop_near(pp: Vector3) -> Variant:
	for s in stops:
		if Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length() < 3.5:
			return s
	return null


## Fait monter le joueur comme passager dans un transport en commun.
func board_vehicle(v) -> bool:
	if v == null or _ride != null or player.current_vehicle != null:
		return false
	if v.has_meta("net_id"):
		v.get_meta("net_owner").convert(v)
	if v.vehicle_type == "taxi":
		_hail_taxi(v)
		return true
	elif v.line_name != "" or v.vehicle_type in ["bus", "coach", "brt"]:
		_board_bus(v)
		return true
	elif v.vehicle_type in ["car_rapide", "ndiaga"]:
		if GameState.spend(CAR_RAPIDE_FARE):
			if v.vehicle_type == "ndiaga":
				GameState.notify.emit("Tu montes dans le Ndiaga Ndiaye (-%s). L'apprenti tape sur la carrosserie : « Colobane, Grand-Yoff ! »" % GameState.fcfa(CAR_RAPIDE_FARE))
			else:
				GameState.notify.emit("Tu montes dans le car rapide (-%s). L'apprenti crie : « Petersen, Sandaga, Médina ! »" % GameState.fcfa(CAR_RAPIDE_FARE))
			_start_ride(v, "car_rapide")
		else:
			GameState.notify.emit("L'apprenti : « C'est %s, grand ! »" % GameState.fcfa(CAR_RAPIDE_FARE))
		return true
	return false


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
	return board_vehicle(v)


func get_hint() -> String:
	if _ride != null or player.current_vehicle != null:
		return ""
	var pp: Vector3 = player.global_position
	var s = _stop_near(pp)
	if s != null:
		return "Ne plus attendre le bus" if _waiting == s else "Attendre le bus %s (%s)" % [s["line"], GameState.fcfa(BUS_FARE)]
	var v = _public_vehicle_near(pp)
	if v != null:
		var price := "" if v.vehicle_type == "taxi" else " (%s)" % GameState.fcfa(BUS_FARE if (v.line_name != "" or v.vehicle_type in ["bus", "coach", "brt"]) else CAR_RAPIDE_FARE)
		return "Monter comme passager : %s%s" % [v.display_name, price]
	return ""


# --- Taxi : choisir sa destination ------------------------------------------------

func taxi_price(from: Vector3, to: Vector3) -> int:
	var d := Vector2(from.x - to.x, from.z - to.z).length()
	# Tarif réaliste à Dakar : prise en charge + environ 400 FCFA par kilomètre (3 km ≈ 1 700 FCFA)
	return maxi(500, int(round((500.0 + d * 0.4) / 50.0)) * 50)


func _dest_info(pos: Vector3, from_pos: Vector3) -> String:
	var d := Vector2(from_pos.x - pos.x, from_pos.z - pos.z).length()
	var dist_str := ("%d m" % int(d)) if d < 1000.0 else ("%.1f km" % (d / 1000.0))
	var price := taxi_price(from_pos, pos)
	return "%s (%s)" % [GameState.fcfa(price), dist_str]


func _hail_taxi(v) -> void:
	v.hold = true
	_show_taxi_main_menu(v)


func _show_taxi_main_menu(v) -> void:
	var pp: Vector3 = player.global_position
	var choices: Array = []

	# 1. Repère GPS personnalisé s'il existe
	if GameState.waypoint != null:
		var wp: Vector3 = GameState.waypoint
		var wp_label: String = "Repère GPS"
		if hud and hud.main and hud.main.gps and hud.main.gps.label != "":
			wp_label = hud.main.gps.label
		var info_str := _dest_info(wp, pp)
		choices.append(["📍 Repère GPS : %s — %s" % [wp_label, info_str], func():
			start_taxi_ride_custom(v, wp, "Repère GPS (%s)" % wp_label)
		])

	# 2. Destinations directes populaires les plus proches
	var popular_places := ["Place de l'Indépendance", "Monument de la Renaissance Africaine", "Marché Sandaga", "Grande Mosquée", "Porte du Millénaire", "Phare des Mamelles", "Hôpital Principal", "Gare de Dakar", "Stade Iba Mar Diop", "Chez Adja", "Marché Kermel", "Marché Tilène"]
	var quick_options: Array = []
	for p_name in popular_places:
		if not city.places.has(p_name):
			continue
		var p_pos: Vector3 = city.places[p_name]
		var d := Vector2(pp.x - p_pos.x, pp.z - p_pos.z).length()
		if d < 60.0:
			continue
		var price := taxi_price(pp, p_pos)
		quick_options.append([d, p_name, p_pos, price])
	quick_options.sort_custom(func(a, b): return a[0] < b[0])
	for qo in quick_options.slice(0, 4):
		var dist_str := ("%d m" % int(qo[0])) if qo[0] < 1000.0 else ("%.1f km" % (qo[0] / 1000.0))
		choices.append(["🚕 %s — %s (%s)" % [qo[1], GameState.fcfa(qo[3]), dist_str], func():
			start_taxi_ride(v, qo[1])
		])

	# 3. Catégories
	for cat in TAXI_CATEGORIES:
		var count: int = cat["places"].size()
		choices.append(["%s %s (%d) ▶" % [cat["icon"], cat["title"], count], func():
			_show_taxi_category_menu(v, cat)
		])

	# 4. Tous les lieux de Dakar (A-Z)
	choices.append(["🔍 Tous les lieux de Dakar (A-Z) ▶", func():
		_show_taxi_all_places_menu(v, 0)
	])

	hud.show_choices("Taxi — « Où on va, grand ? »", choices, func():
		v.hold = false
	)


func _show_taxi_category_menu(v, cat: Dictionary) -> void:
	var pp: Vector3 = player.global_position
	var choices: Array = []
	for p_item in cat["places"]:
		var p_name: String = p_item["name"]
		if p_item.get("special", "") == "wade":
			var fare: int = p_item.get("fare", 2500)
			choices.append(["⭐ %s — %s (Autoroute)" % [p_name, GameState.fcfa(fare)], func():
				travel_to_wade_stadium(v, fare)
			])
		elif p_item.get("special", "") == "arena":
			var fare: int = arena.TAXI_FARE if arena else 1500
			choices.append(["⭐ %s — %s (Pikine)" % [p_name, GameState.fcfa(fare)], func():
				v.hold = false
				if arena:
					arena.travel_to_arena("taxi")
				else:
					GameState.notify.emit("Arène non disponible.")
			])
		elif p_item.get("special", "") == "foot":
			var fare: int = foot.TAXI_FARE if foot else 1200
			choices.append(["⭐ %s — %s (Complexe)" % [p_name, GameState.fcfa(fare)], func():
				v.hold = false
				if foot:
					foot.travel_to_complex("taxi")
				else:
					GameState.notify.emit("Complexe non disponible.")
			])
		elif p_item.get("special", "") == "dealership":
			var d_pos := Vector3.ZERO
			if main and main.dealership and main.dealership.pos != Vector3.ZERO:
				d_pos = main.dealership.pos
			elif hud and hud.main and hud.main.dealership and hud.main.dealership.pos != Vector3.ZERO:
				d_pos = hud.main.dealership.pos
			elif city.places.has("Place de l'Indépendance"):
				d_pos = city.places["Place de l'Indépendance"]
			if d_pos != Vector3.ZERO:
				var info_str := _dest_info(d_pos, pp)
				choices.append(["🚗 %s — %s" % [p_name, info_str], func():
					start_taxi_ride_custom(v, d_pos, p_name)
				])
		elif p_item.has("place") and city.places.has(p_item["place"]):
			var place_key: String = p_item["place"]
			var pos: Vector3 = city.places[place_key]
			var info_str := _dest_info(pos, pp)
			choices.append(["%s — %s" % [p_name, info_str], func():
				start_taxi_ride(v, place_key)
			])

	# Bouton Retour
	choices.append(["« ↩ Retour au menu principal", func():
		_show_taxi_main_menu(v)
	])

	hud.show_choices("Taxi — %s" % cat["title"], choices, func():
		_show_taxi_main_menu(v)
	)


func _show_taxi_all_places_menu(v, page: int = 0) -> void:
	var pp: Vector3 = player.global_position
	var all_keys: Array = city.places.keys()
	all_keys.sort()
	var per_page := 8
	var total_pages := maxi(1, int(ceil(float(all_keys.size()) / float(per_page))))
	page = clampi(page, 0, total_pages - 1)
	var start_idx := page * per_page
	var end_idx := mini(start_idx + per_page, all_keys.size())

	var choices: Array = []
	for i in range(start_idx, end_idx):
		var k: String = all_keys[i]
		var pos: Vector3 = city.places[k]
		var info_str := _dest_info(pos, pp)
		choices.append(["%s — %s" % [k, info_str], func():
			start_taxi_ride(v, k)
		])

	if page < total_pages - 1:
		choices.append(["▶ Page suivante (%d/%d)" % [page + 2, total_pages], func():
			_show_taxi_all_places_menu(v, page + 1)
		])
	if page > 0:
		choices.append(["◀ Page précédente (%d/%d)" % [page, total_pages], func():
			_show_taxi_all_places_menu(v, page - 1)
		])
	choices.append(["« ↩ Retour au menu principal", func():
		_show_taxi_main_menu(v)
	])

	hud.show_choices("Taxi — Dakar A-Z (%d/%d)" % [page + 1, total_pages], choices, func():
		_show_taxi_main_menu(v)
	)


func start_taxi_ride(v, dest: String) -> void:
	if not city.places.has(dest):
		GameState.notify.emit("Destination inconnue.")
		v.hold = false
		return
	start_taxi_ride_custom(v, city.places[dest], dest)


func start_taxi_ride_custom(v, target_pos: Vector3, dest_name: String) -> void:
	var price := taxi_price(player.global_position, target_pos)
	if not GameState.spend(price):
		GameState.notify.emit("Le taximan : « C'est %s, tu n'as pas assez ! »" % GameState.fcfa(price))
		v.hold = false
		return
	_taxi_dest = dest_name
	_taxi_dest_pos = target_pos
	_start_ride(v, "taxi")
	v.hold = false
	var route: PackedVector3Array = city.route(v.global_position, target_pos, true)
	if route.is_empty() or route.size() < 2:
		route = PackedVector3Array([v.global_position, target_pos])
	v.follow_route(route, false)
	if not v.route_finished.is_connected(_on_taxi_arrived):
		v.route_finished.connect(_on_taxi_arrived)
	GameState.notify.emit("« Waaw, dem nañu ! » (allons-y) — %s pour %s." % [GameState.fcfa(price), dest_name])


func travel_to_wade_stadium(v, fare: int = 2500) -> void:
	if not GameState.spend(fare):
		GameState.notify.emit("Le taximan : « C'est %s pour l'autoroute vers Diamniadio ! »" % GameState.fcfa(fare))
		v.hold = false
		return
	v.hold = false
	hud.fade_through(func():
		player.leave_any_vehicle()
		var target := Vector3(9000 - 85.0, 0.5, 1800)
		if stade:
			target = stade.WADE_ORIGIN + Vector3(-85.0, 0.5, 0)
		elif main and main.stade:
			target = main.stade.WADE_ORIGIN + Vector3(-85.0, 0.5, 0)
		player.global_position = target
		GameState.game_minutes = fmod(GameState.game_minutes + 35.0, 1440.0)
		GameState.notify.emit("Après 35 minutes sur l'autoroute à péage... Bienvenue au Stade Me Abdoulaye Wade !"))


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
				var d_rem: int = 0
				if _taxi_dest_pos != Vector3.ZERO:
					d_rem = int(player.get_world_position().distance_to(_taxi_dest_pos))
				elif city and city.places.has(_taxi_dest):
					d_rem = int(player.get_world_position().distance_to(city.places[_taxi_dest]))
				status = "TAXI vers %s (%d m) — [E] descendre ici" % [_taxi_dest, d_rem]
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
