extends SceneTree
## Test de fumée : godot --headless --path . -s res://tests/smoke_test.gd
## Charge la ville et exerce chaque métier ; affiche OK / ÉCHEC pour chaque étape.

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool) -> void:
	print(("OK     " if ok else "ÉCHEC  ") + label)
	if not ok:
		_fails += 1


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	var gs = root.get_node("GameState")
	# Sauvegarde séparée : le test ne doit jamais effacer la partie du joueur.
	gs.save_path = "user://test_save.json"
	gs.new_game()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.5)
	var player = main.player
	var jobs = main.jobs
	var city = main.city
	_check("ville construite (%d lieux)" % city.places.size(), city.places.size() >= 10)
	_check("réseau routier (%d nœuds)" % city.node_pos.size(), city.node_pos.size() > 1000)
	_check("quartier au départ : %s" % city.district_at(player.global_position), city.district_at(player.global_position) != "Dakar")
	var addr: Dictionary = city.random_address(player.global_position, 100.0, 300.0)
	_check("vraie adresse : %s" % addr["name"], addr["name"] != "")
	var route: PackedVector3Array = city.route(city.places["Hôpital Principal"], city.places["Grande Mosquée"])
	_check("itinéraire Hôpital → Grande Mosquée (%d points)" % route.size(), route.size() > 5)
	var car = main.traffic[0]
	var car_start: Vector3 = car.global_position
	var ped0 = main.peds[0]
	var ped_start: Vector3 = ped0.position
	await _wait(3.0)
	_check("le trafic roule (%.0f m)" % car.global_position.distance_to(car_start), car.global_position.distance_to(car_start) > 5.0)
	_check("les piétons marchent (%.1f m)" % ped0.position.distance_to(ped_start), ped0.position.distance_to(ped_start) > 1.5)

	# Emploi : patrons qui recrutent
	var emp = main.employment
	_check("patrons sur place (%d)" % emp.bosses.size(), emp.bosses.size() >= 6)
	_check("Jadida exige de l'expérience", emp.missing("jadida") != "")
	_check("le taxi exige le permis", "permis" in emp.missing("taxi"))
	gs.game_minutes = 10.0 * 60.0
	player.global_position = city.places["Café Touba"] + Vector3(0, 0.5, 0)
	await _wait(0.2)
	jobs.try_interact()
	_check("pas de café sans embauche", jobs.job == "")
	emp.state("cafe")["hired"] = true
	emp.state("livreur")["hired"] = true

	# Café Touba (embauché par Serigne Mbaye : paie en fin de service)
	_check("indice café", jobs.get_hint() == "Vendre du café Touba")
	jobs.try_interact()
	var before: int = gs.money
	await _wait(4.5)
	_check("tasse vendue, paie à toucher (%d)" % emp._due, emp._due == 150 and gs.money == before)
	jobs.try_interact()
	_check("stand fermé, payé par le patron (+150)", jobs.job == "" and gs.money == before + 150)

	# Dibiterie
	gs.hunger = 10.0
	player.global_position = city.places["Dibiterie"] + Vector3(0, 0.5, 0)
	await _wait(0.2)
	before = gs.money
	jobs.try_interact()
	_check("dibi mangé (-1500, satiété 100)", gs.money == before - 1500 and gs.hunger == 100.0)

	# Livraison (embauché par Adja, horaires 11h-15h)
	gs.game_minutes = 12.0 * 60.0
	player.global_position = city.places["Chez Adja"] + Vector3(0, 0.5, 0)
	await _wait(0.2)
	jobs.try_interact()
	_check("livraison démarrée", jobs.job == "livraison" and jobs.has_target)
	before = gs.money
	player.global_position = jobs.target_pos + Vector3(0, 0.5, 0)
	await _wait(0.3)
	emp.end_shift("livreur", false)
	_check("livraison payée par Adja", jobs.job == "" and gs.money > before)

	# Taxi au versement : permis, embauche par Pape Diop, taxi du patron
	gs.add_item("Permis de conduire")
	emp.state("taxi")["hired"] = true
	gs.money += 10000
	emp._start_special("taxi")
	var taxi = emp._taxi
	_check("le patron confie son taxi", taxi != null and emp.shift == "taxi")
	player.global_position = taxi.global_position
	player.enter_vehicle(taxi)
	await _wait(0.2)
	_check("service taxi actif", jobs.job == "taxi" and jobs.has_target)
	taxi.global_position = jobs.target_pos + Vector3(0, 0.3, 0)
	await _wait(0.3)
	_check("client monté", jobs.stage == "course")
	before = gs.money
	taxi.global_position = jobs.target_pos + Vector3(0, 0.3, 0)
	await _wait(0.3)
	_check("course payée", gs.money > before and jobs.stage == "cherche")
	before = gs.money

	# Piéton renversé
	var ped = main.peds[0]
	ped.visible = true
	taxi.global_position = ped.global_position + Vector3(0, 0, 0)
	taxi.speed = 10.0
	await _wait(0.1)
	_check("piéton renversé", ped.knocked)
	_check("étoile de recherche", gs.wanted >= 1)
	player.exit_vehicle()
	await _wait(0.1)
	_check("descendu du taxi", player.current_vehicle == null and player.visible)

	# Police : arrestation
	var police = main.police
	_check("patrouilles de police", police.units.size() >= 2)
	gs.wanted = 1
	var cop = police.units[0]
	# Joueur et police sur la même rue, à 4 m l'un de l'autre
	var n0: int = city.nearest_node(player.global_position, "drive")
	var n1: int = city.drive_neighbors(n0)[0]
	var along: Vector3 = (city.node_pos[n1] - city.node_pos[n0]).normalized()
	player.global_position = city.node_pos[n0] + Vector3(0, 0.5, 0)
	cop.global_position = city.node_pos[n0] + along * 4.5 + Vector3(0, 0.3, 0)
	cop.speed = 0.0
	cop.hold = true # immobile pendant la vérification
	await _wait(2.8)
	var station: Vector3 = city.places["Commissariat"]
	_check("arrêté au commissariat", player.global_position.distance_to(station) < 3.0 and gs.wanted == 0)
	cop.hold = false

	# Police : renforts puis semer la poursuite
	player.global_position = city.places["Porte du Millénaire"] + Vector3(0, 0.5, 0)
	gs.wanted = 3
	await _wait(2.5)
	_check("renforts envoyés (%d voitures)" % police.units.size(), police.units.size() > 2)
	gs.wanted = 1
	for u in police.units:
		u.global_position = city.node_pos[city.random_node_around(player.global_position, 500.0, 1200.0)] + Vector3(0, 0.3, 0)
	police._lose_t = police.LOSE_TIME - 0.2
	await _wait(0.5)
	_check("police semée", gs.wanted == 0)

	# Transports en commun : lignes de bus
	var transit = main.transit
	gs.money = 20000
	_check("lignes de bus (%d arrêts, %d bus)" % [transit.stops.size(), transit.buses.size()], transit.stops.size() >= 8 and transit.buses.size() >= 4)
	var bus = transit.buses[0]
	player.global_position = city.places["Porte du Millénaire"] + Vector3(0, 0.5, 0) # hors du chemin du bus
	var bus_start: Vector3 = bus.global_position
	await _wait(3.0)
	_check("le bus roule sur sa ligne (%.0f m)" % bus.global_position.distance_to(bus_start), bus.global_position.distance_to(bus_start) > 5.0)
	# Attendre à un arrêt de la ligne du bus, puis le bus arrive
	var stop: Dictionary = {}
	for s in transit.stops:
		if s["line"] == bus.line_name:
			stop = s
			break
	player.global_position = stop["pos"] + Vector3(0, 0.5, 0)
	await _wait(0.2)
	_check("indice arrêt : %s" % transit.get_hint(), "Attendre le bus" in transit.get_hint())
	transit.try_interact()
	before = gs.money
	transit._on_bus_stop(stop["name"], bus)
	await _wait(0.2)
	_check("monté dans le bus (-200 FCFA)", player.riding == bus and gs.money == before - 200)
	transit.ride_interact()
	transit._on_bus_stop("arrêt suivant", bus)
	await _wait(0.2)
	_check("descendu au prochain arrêt", player.riding == null and player.visible)

	# Taxi : choisir une destination et payer
	var taxi_ai = null
	for v in main.traffic:
		if v.vehicle_type == "taxi" and v.ai_enabled:
			taxi_ai = v
			break
	before = gs.money
	var price: int = transit.taxi_price(player.global_position, city.places["Grande Mosquée"])
	transit.start_taxi_ride(taxi_ai, "Grande Mosquée")
	_check("taxi vers la Grande Mosquée (-%d FCFA)" % price, player.riding == taxi_ai and gs.money == before - price and taxi_ai.route_active)
	taxi_ai.route_finished.emit()
	await _wait(0.2)
	_check("arrivé et descendu du taxi", player.riding == null and taxi_ai.ai_enabled)

	# Car rapide : 150 FCFA, on descend quand on veut
	var cr = null
	for v in main.traffic:
		if v.vehicle_type == "car_rapide" and v.ai_enabled and v.passenger == null:
			cr = v
			break
	player.global_position = cr.global_position + Vector3(0, 0.5, 0)
	before = gs.money
	transit.try_interact()
	_check("monté dans le car rapide (-150 FCFA)", player.riding == cr and gs.money == before - 150)
	transit.ride_interact()
	cr.speed = 0.0
	await _wait(0.5)
	_check("« Descente ! »", player.riding == null)

	# Voler un taxi (touche G) reste possible
	gs.wanted = 0
	var taxi2 = null
	for v in main.traffic:
		if v.vehicle_type == "taxi" and v.ai_enabled and v.passenger == null:
			taxi2 = v
			break
	player.global_position = taxi2.global_position + Vector3(0, 0.5, 0)
	player.enter_vehicle(taxi2)
	_check("taxi volé (+1 étoile)", player.current_vehicle == taxi2 and gs.wanted == 1)
	player.exit_vehicle()

	# Armée : 4 étoiles et plus
	player.global_position = city.places["Porte du Millénaire"] + Vector3(0, 0.5, 0)
	gs.wanted = 4
	await _wait(5.0)
	var army := 0
	for u in police.units:
		if is_instance_valid(u) and u.vehicle_type == "army":
			army += 1
	_check("armée déployée (%d jeeps, %d soldats)" % [army, police.soldiers.size()], army >= 1 and police.soldiers.size() >= 1)
	var sol = police.soldiers[0]
	sol.global_position = player.global_position + Vector3(0.5, 0, 0)
	await _wait(0.2)
	_check("arrêté par un soldat", gs.wanted == 0 and player.global_position.distance_to(city.places["Commissariat"]) < 3.0)
	_check("gardes à la caserne", police.guards.size() == 2)
	gs.wanted = 0
	police._trespass_cd = 0.0
	player.global_position = police._base_center + Vector3(0, 0.5, 0)
	await _wait(0.2)
	_check("zone militaire interdite (+2 étoiles)", gs.wanted >= 2)
	gs.wanted = 0
	police.reset_all()

	# Nouveaux lieux réels
	for lieu in ["Plage de l'Anse Bernard", "Terrain de foot", "Courts de tennis", "Terrain de basket", "Église Saint-Laurent", "Orange Money", "Wave", "Jumbo", "Jadida"]:
		_check("lieu : %s" % lieu, city.places.has(lieu))

	# Feux tricolores
	var lights = city.lights
	_check("feux tricolores (%d carrefours)" % lights._signals.size(), lights._signals.size() >= 20)
	var sig: int = lights._signals.keys()[0]
	var s0: int = lights.state(sig, 0)
	var s1: int = lights.state(sig, 1)
	_check("les deux axes ne sont jamais verts ensemble", not (s0 == 0 and s1 == 0))
	lights._t += lights.GREEN + lights.YELLOW
	_check("le feu change de couleur", lights.state(sig, 0) != s0 or lights.state(sig, 1) != s1)

	# Marché : acheter à manger et un tissu
	var market = main.market
	_check("étals du marché (%d)" % market.stalls.size(), market.stalls.size() >= 16)
	gs.money = 20000
	gs.hunger = 40.0
	market._buy(["Mangue", 200, 12], 200)
	_check("mangue mangée (-200, satiété +12)", gs.money == 19800 and is_equal_approx(gs.hunger, 52.0))
	market._buy(["Tissu wax (6 yards)", 6000, 0], 6000)
	_check("tissu wax dans le sac", gs.inventory.get("Tissu wax (6 yards)", 0) == 1)
	var stall: Dictionary = market.stalls[0]
	player.global_position = stall["front"] + Vector3(0, 0.5, 0)
	await _wait(0.1)
	_check("indice étal : %s" % market.get_hint(), "Acheter" in market.get_hint())

	# Kiosque Wave : servir un client (embauché par Ousmane Ba)
	if player.current_vehicle:
		player.exit_vehicle()
	emp._end_taxi()
	_check("versement payé au patron du taxi", emp.shift == "")
	emp.state("wave")["hired"] = true
	emp.state("jumbo")["hired"] = true
	var biz = main.business
	var wave: Dictionary = {}
	for s in biz.spots:
		if s["kind"] == "wave":
			wave = s
	player.global_position = wave["pos"] + Vector3(0, 0.5, 0)
	await _wait(0.1)
	_check("indice Wave : %s" % biz.get_hint(), "Agent Wave" in biz.get_hint())
	biz.try_interact()
	await _wait(2.5)
	_check("un client arrive au kiosque", biz._customer != null)
	before = gs.money
	biz.try_interact()
	_check("client servi (commission à toucher : %d)" % emp._due, emp._due > 0 and biz._served == 1)
	biz._end_shift()
	_check("fin du service, commission payée", jobs.job == "" and gs.money > before)

	# Tournée Jumbo
	var jumbo: Dictionary = {}
	for s in biz.spots:
		if s["kind"] == "jumbo":
			jumbo = s
	player.global_position = jumbo["pos"] + Vector3(0, 0.5, 0)
	await _wait(0.1)
	biz.try_interact()
	_check("tournée Jumbo démarrée", jobs.job == "entreprise" and jobs.has_target)
	before = gs.money
	player.global_position = jobs.target_pos + Vector3(0, 0.5, 0)
	await _wait(0.2)
	_check("cartons livrés (paie à toucher : %d)" % emp._due, emp._due >= 1200)
	emp.end_shift("jumbo", false)
	jobs.cancel()
	_check("payé par le chef du dépôt", gs.money >= before + 1200)
	await _wait(0.1)

	# GPS
	main.gps.set_waypoint(city.places["Grande Mosquée"], "Grande Mosquée")
	_check("itinéraire GPS (%d points)" % main.gps.route.size(), main.gps.route.size() > 3)
	main.gps.clear()
	_check("GPS effacé", gs.waypoint == null)

	# Animations en capture de mouvement
	_check("animations du héros", player.model.has_animations())
	player.model.locomote(1.4)
	_check("marche → clip « walk »", player.model._current == "walk")
	player.model.locomote(6.5)
	_check("course → clip « sprint »", player.model._current == "sprint")
	player.model.locomote(0.0)
	_check("immobile → clip « idle »", player.model._current == "idle")

	# Arène nationale de Pikine
	var arena = main.arena
	gs.wanted = 0
	gs.money = 50000
	var car_spot: Dictionary = {}
	for s in arena.spots:
		if s["id"] == "car_aller":
			car_spot = s
	player.global_position = car_spot["pos"] + Vector3(0, 0.5, 0)
	await _wait(0.1)
	_check("car pour Pikine à Petersen : %s" % arena.get_hint(), "Pikine" in arena.get_hint())
	arena.try_interact()
	await _wait(1.5)
	_check("arrivé à l'Arène nationale (-300 FCFA)", arena.contains(player.global_position) and gs.money == 49700)
	for s in arena.spots:
		if s["id"] == "ticket":
			player.global_position = s["pos"] + Vector3(0, 0.5, 0)
	await _wait(0.1)
	arena.try_interact()
	_check("billet acheté (-2 000 FCFA)", arena._has_ticket and gs.money == 47700)
	arena._place_bet(0)
	_check("pari placé et combat lancé", arena._state == "bakk" and arena._bet_on == 0)
	arena._t = 100.0
	await _wait(0.1)
	arena._t = 100.0
	await _wait(0.1)
	arena._t = 100.0
	await _wait(0.1)
	_check("combat terminé : %s gagne" % arena.WRESTLERS[arena._winner][1], arena._state == "fin")
	_check("pari réglé", arena._bet_on == -1)
	arena._reset_wrestlers()
	before = gs.money
	arena._start_player_fight()
	for k in 3:
		arena._cursor = (arena._zone.x + arena._zone.y) / 2.0
		arena._press()
	_check("le joueur gagne son combat (+25 000 FCFA)", gs.money == before + 25000 and not arena._fight)
	await _wait(5.5)
	_check("le joueur peut de nouveau bouger", not player.frozen)
	for s in arena.spots:
		if s["id"] == "car_retour":
			player.global_position = s["pos"] + Vector3(0, 0.5, 0)
	await _wait(0.1)
	arena.try_interact()
	await _wait(1.5)
	_check("retour à Petersen", not arena.contains(player.global_position) and player.global_position.distance_to(city.places["Gare routière Petersen"]) < 3.0)

	# Son
	var waited := 0.0
	while not root.get_node("Audio").radio_ready() and waited < 8.0:
		await _wait(0.25)
		waited += 0.25
	_check("radio mbalax générée", root.get_node("Audio").radio_ready())

	# Apprenti de car rapide (Modou Ndiaye)
	var emp2 = main.employment
	gs.clear_wanted()
	gs.game_minutes = 9.0 * 60.0
	emp2.state("apprenti")["hired"] = true
	if player.current_vehicle:
		player.exit_vehicle()
	emp2._start_special("apprenti")
	_check("monté à l'arrière du car rapide", emp2.apprenti_riding())
	emp2._on_car_stop("Marché Sandaga")
	emp2.apprenti_action()
	_check("destination criée, part de la recette (%d)" % emp2._due, emp2._due > 0)
	var cash_before: int = gs.money
	emp2._stop_window = 0.0
	emp2.apprenti_action()
	_check("descendu, payé par Modou (+%d)" % (gs.money - cash_before), gs.money > cash_before and emp2.shift == "")

	# Logement : louer, payer le loyer, acheter, dormir, garage
	var hs = main.housing
	_check("logements à louer / vendre (%d)" % hs.doors.size(), hs.doors.size() >= 3)
	gs.money = 20000
	gs.home["rented"] = "chambre_medina"
	gs.home["unpaid"] = 0
	var m0: int = gs.money
	gs.game_minutes = 7.0 * 60.0 + 50.0
	gs.advance_time(20.0)
	_check("loyer payé le matin (-1 000)", gs.money == m0 - 1000)
	gs.money = 0
	gs.bank = 0
	for k in 3:
		gs.advance_time(1440.0)
	_check("expulsé après 3 jours d'impayés", hs.rented() == "")
	gs.bank = 300000
	hs._buy("studio_gueule_tapee", 262000)
	_check("studio acheté (banque débitée)", hs.owned("studio_gueule_tapee") and gs.bank == 38000)
	_check("on se réveille chez soi", hs.home_position() != null)
	gs.health = 40.0
	gs.game_minutes = 22.0 * 60.0
	hs._sleep(-1.0)
	await _wait(1.2)
	_check("dormi jusqu'au matin, santé 100 (%02d h)" % (int(gs.game_minutes) / 60), int(gs.game_minutes) / 60 == 7 and gs.health == 100.0)
	gs.home["owned"].append("appart_plateau")
	var my_car = load("res://scripts/vehicles/vehicle.gd").new()
	my_car.vehicle_type = "clando"
	main.add_child(my_car)
	my_car.global_position = hs.doors["appart_plateau"]["pos"] + Vector3(0, 0.3, 0)
	player.global_position = my_car.global_position
	player.enter_vehicle(my_car)
	hs._park("appart_plateau", my_car)
	await _wait(0.1)
	_check("voiture rangée au garage", gs.garage.get("appart_plateau", []).size() == 1 and player.current_vehicle == null)
	hs._unpark("appart_plateau", 0)
	_check("voiture ressortie, elle est à toi", player.current_vehicle != null and player.current_vehicle.has_meta("owned"))
	player.exit_vehicle()

	# Ville vivante : météo, lampadaires, ponts, services et intérieurs
	_check("météo : %s" % main.weather.label(), main.weather.state in main.weather.STATES)
	_check("lampadaires (%d)" % main.lamps.lamps.size(), main.lamps.lamps.size() > 200)
	var raised := 0
	for p3 in city.node_pos:
		if p3.y > 3.0:
			raised += 1
	_check("ponts surélevés (%d nœuds)" % raised, raised > 5)
	_check("services visitables (%d)" % city.services.size(), city.services.size() > 50)
	var bank_before: int = gs.bank
	gs.money += 5000
	main.interiors.inside = "banque"
	main.interiors._deposit(5000)
	_check("dépôt à la banque (+5 000 sur le compte)", gs.bank == bank_before + 5000)
	main.interiors._withdraw(5000)
	_check("retrait à la banque", gs.bank == bank_before)
	main.interiors.inside = ""
	var gfx = root.get_node("Graphics")
	_check("profil graphique : %s" % gfx.display_name(), gfx.PROFILES.has(gfx.profile))

	# Évanouissement → hôpital
	gs.health = 0.0
	await _wait(0.2)
	var hosp: Vector3 = city.places["Hôpital Principal"]
	_check("réveil à l'hôpital", player.global_position.distance_to(hosp) < 3.0 and gs.health == 100.0)

	# Sauvegarde
	gs.save_game()
	_check("sauvegarde écrite", FileAccess.file_exists(gs.save_path))
	gs.new_game()

	print("\n%s" % ("TOUT EST OK" if _fails == 0 else "%d ÉCHEC(S)" % _fails))
	quit(_fails)
