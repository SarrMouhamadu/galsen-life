extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST RÉALISME MOUVEMENTS, DÉCORS (ARBRES, ROUTES) ET RETOUR VÉHICULE ---")

	# 1. Test génération des décors urbains (arbres, palmiers, baobabs, routes, marquages)
	var DakarCityScript = load("res://scripts/world/dakar_city.gd")
	var city = DakarCityScript.new()
	root.add_child(city)
	city.build_data_only()
	city._build_job_decor()

	var urban_decor: Node3D = city.get_node_or_null("UrbanDecor")
	assert(urban_decor != null, "Le nœud UrbanDecor doit être créé dans DakarCity")

	var decor_count: int = urban_decor.get_child_count()
	print("  [OK] Éléments de décor urbain instanciés : %d objets" % decor_count)
	assert(decor_count >= 15, "Au moins 15 ensembles de décors (arbres, palmiers, passages, bordures) doivent être présents")

	# 2. Test physique du joueur et réalisme des mouvements
	var PlayerScript = load("res://scripts/player/player.gd")
	var player = PlayerScript.new()
	root.add_child(player)
	player.global_position = Vector3(100, 2, 100)

	assert(player.get("_lean_roll") != null, "Propriété _lean_roll doit exister sur le joueur")
	assert(player.get("_lean_pitch") != null, "Propriété _lean_pitch doit exister sur le joueur")
	assert(player.get("_squash_scale") != null, "Propriété _squash_scale doit exister sur le joueur")

	# Test du retour au point de départ à pied
	player.return_to_start(city)
	assert(player.global_position.distance_to(city.spawn_point) < 2.0, "Le joueur doit être rapatrié au point de départ (Place de l'Indépendance)")
	print("  [OK] Rapatriement du joueur au point de départ validé")

	# 3. Test du véhicule et du retour au point de départ en voiture
	var VehicleScript = load("res://scripts/vehicles/vehicle.gd")
	var car = VehicleScript.new()
	car.vehicle_type = "taxi"
	root.add_child(car)
	car.global_position = Vector3(-800, 1.0, -800) # Au fin fond de la Médina
	car.speed = 15.0
	car.condition = 40.0
	car.fuel = 10.0

	# Monter le joueur dans la voiture
	player.enter_vehicle(car)
	assert(player.current_vehicle == car, "Le joueur doit être au volant du taxi")

	var game_state = root.get_node("GameState")

	# Test set_gps_to_start
	car.set_gps_to_start(city)
	assert(game_state.waypoint != null and game_state.waypoint.distance_to(city.spawn_point) < 2.0, "Le GPS doit pointer vers le point de départ")
	print("  [OK] Guidage GPS vers le point de départ validé")

	# Test return_to_start en voiture
	car.return_to_start(city)
	assert(car.global_position.distance_to(city.spawn_point) < 2.0, "La voiture doit être ramenée à la Place de l'Indépendance")
	assert(player.global_position.distance_to(city.spawn_point) < 2.0, "Le conducteur doit être avec sa voiture au point de départ")
	assert(car.speed == 0.0, "La voiture doit être à l'arrêt")
	assert(car.condition >= 85.0, "La voiture doit être réparée lors du rapatriement")
	assert(car.fuel >= 80.0, "La voiture doit être ravitaillée lors du rapatriement")
	print("  [OK] Rapatriement complet de la voiture et du joueur au point de départ validé")

	print("[PASS] Tous les tests de mouvements, décors (arbres, routes) et retour voiture sont validés avec succès !")
	quit()
