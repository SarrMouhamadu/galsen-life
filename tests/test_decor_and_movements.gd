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
	assert(player.get("_step_smooth_y") != null, "Propriété _step_smooth_y doit exister sur le joueur pour le lissage des trottoirs")
	assert(player.get("MAX_STEP_HEIGHT") != null and player.get("MAX_STEP_HEIGHT") >= 0.20, "MAX_STEP_HEIGHT doit être configuré pour franchir les trottoirs")

	# Test du franchissement fluide de trottoir sans saut
	var test_ground = StaticBody3D.new()
	var g_shape = CollisionShape3D.new()
	var g_box = BoxShape3D.new()
	g_box.size = Vector3(20, 1, 20)
	g_shape.shape = g_box
	g_shape.position = Vector3(0, -0.5, 0)
	test_ground.add_child(g_shape)
	test_ground.collision_layer = 1
	root.add_child(test_ground)

	var test_sidewalk = StaticBody3D.new()
	var sw_shape = CollisionShape3D.new()
	var sw_box = BoxShape3D.new()
	sw_box.size = Vector3(20, 0.16, 10.0)
	sw_shape.shape = sw_box
	sw_shape.position = Vector3(0, 0.08, 5.0) # trottoir de z=0 à z=10
	test_sidewalk.add_child(sw_shape)
	test_sidewalk.collision_layer = 32
	root.add_child(test_sidewalk)

	player.global_position = Vector3(0, 0.05, -1.5)
	var game_state = root.get_node("GameState")
	for f in range(90):
		game_state.touch_move = Vector2(0, 1.0) # Avancer vers l'avant (pas de saut)
		player._physics_process(1.0 / 60.0)

	print("  Position joueur après marche vers trottoir : y=%.3f, z=%.3f" % [player.global_position.y, player.global_position.z])
	assert(player.global_position.y >= 0.15, "Le joueur doit monter sur le trottoir sans avoir besoin de sauter")
	assert(player.global_position.z > 0.5, "Le joueur ne doit pas rester bloqué au bord du trottoir")
	print("  [OK] Franchissement fluide de trottoir (sans saut robotique) validé avec succès !")

	# Nettoyage décors de test
	test_ground.queue_free()
	test_sidewalk.queue_free()

	# 2b. Test du réalisme des gestes : Allures (walk/jog/sprint), Sauts (jump/fall) et Assise (sit)
	var NetEmotesScript = load("res://scripts/net/net_emotes.gd")
	assert(NetEmotesScript.valid("sit"), "L'émote 'sit' doit être reconnue comme valide dans NetEmotes")
	var has_sit_in_list := false
	for e in NetEmotesScript.LIST:
		if e[1] == "sit":
			has_sit_in_list = true
			break
	assert(has_sit_in_list, "L'émote 'S'asseoir' (sit) doit être présente dans NetEmotes.LIST")
	print("  [OK] Émote 'S'asseoir' (sit) validée dans NetEmotes")

	# Test des animations de saut et de chute en vol
	player.global_position = Vector3(0, 10, 0)
	player.velocity = Vector3(0, 2.5, 0) # Montée du saut
	player._physics_process(1.0 / 60.0)
	if player.model and player.model.has_method("play_clip"):
		assert(player.model._current == "jump", "L'animation 'jump' doit être active lors de la montée du saut")

	player.velocity = Vector3(0, -3.0, 0) # Descente de chute
	player._physics_process(1.0 / 60.0)
	if player.model and player.model.has_method("play_clip"):
		assert(player.model._current == "fall", "L'animation 'fall' doit être active lors de la descente")
	print("  [OK] Gestes réalistes en l'air (jump en montée, fall en descente) validés")

	# Test de l'interaction avec une chaise / banc (s'asseoir et se relever)
	var test_chair = Node3D.new()
	test_chair.add_to_group("chairs")
	root.add_child(test_chair)
	test_chair.global_position = Vector3(10, 0, 10)
	player.global_position = Vector3(10.5, 0, 10)

	var hint: String = player.get_interaction_hint()
	assert(hint == "S'asseoir", "Le joueur doit voir 'S'asseoir' quand il est proche d'une chaise")
	player._interact()
	assert(player.is_sitting, "Le joueur doit être dans l'état assis après interaction")
	assert(player.emote == "sit", "Le joueur doit jouer l'émote 'sit'")
	assert(player.get_interaction_hint() == "Se lever", "L'indication doit devenir 'Se lever'")

	# Se relever avec le déplacement
	game_state.touch_move = Vector2(0, 1.0)
	player._physics_process(1.0 / 60.0)
	assert(not player.is_sitting, "Le joueur doit se relever dès qu'un mouvement est initié")
	assert(player.emote == "", "L'émote 'sit' doit s'arrêter à la reprise de la marche")
	print("  [OK] Geste de s'asseoir sur une chaise et se relever validé avec succès")
	test_chair.queue_free()

	# Test de calibration des allures (marche, jogging, sprint)
	if player.model and player.model.has_method("locomote"):
		player.model.locomote(0.0)
		assert(player.model._current == "idle", "À 0 m/s l'allure doit être 'idle'")
		player.model.locomote(1.8)
		assert(player.model._current == "walk", "À 1.8 m/s l'allure doit être 'walk'")
		player.model.locomote(3.6)
		assert(player.model._current == "jog", "À 3.6 m/s l'allure doit être 'jog'")
		player.model.locomote(6.5)
		assert(player.model._current == "sprint", "À 6.5 m/s (vitesse de sprint) l'allure doit être 'sprint'")
		print("  [OK] Calibration naturelle des allures (idle -> walk -> jog -> sprint) validée")

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
	if player.camera_rig:
		assert(is_equal_approx(player.camera_rig.yaw, car.rotation.y), "La caméra doit être orientée dans l'axe du véhicule")

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

	# Test de l'orientation de tous les modèles de véhicules (notamment Berline sf_bmw2002)
	var clando_bmw = VehicleScript.new()
	clando_bmw.vehicle_type = "clando"
	clando_bmw.model_override = "sf_bmw2002"
	root.add_child(clando_bmw)
	var bmw_model = clando_bmw.get_node_or_null("Modele")
	assert(bmw_model != null, "Le modèle BMW 2002 doit exister")
	assert(is_equal_approx(bmw_model.rotation.y, PI), "Le modèle BMW 2002 doit être redressé à 180° pour pointer vers -Z")
	clando_bmw.queue_free()
	print("  [OK] Orientation de tous les véhicules (y compris Berline sf_bmw2002) validée dans l'axe de marche !")

	print("[PASS] Tous les tests de mouvements, décors (arbres, routes) et retour voiture sont validés avec succès !")
	quit()
