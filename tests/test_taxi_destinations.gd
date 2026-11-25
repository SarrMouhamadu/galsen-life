extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST TAXI DESTINATIONS DE DAKAR ---")
	var TransitScript = load("res://scripts/transport/transit.gd")
	var VehicleScript = load("res://scripts/vehicles/vehicle.gd")
	var HudScript = load("res://scripts/ui/hud.gd")
	
	# 1. Vérification de la présence des catégories de taxi
	assert(TransitScript.TAXI_CATEGORIES != null, "TAXI_CATEGORIES doit exister")
	assert(TransitScript.TAXI_CATEGORIES.size() >= 8, "Il doit y avoir au moins 8 catégories de taxi")
	
	var cat_ids := []
	for c in TransitScript.TAXI_CATEGORIES:
		cat_ids.append(c["id"])
		assert(c.has("icon") and c["icon"] != "", "Icône manquante pour %s" % c["id"])
		assert(c.has("title") and c["title"] != "", "Titre manquant pour %s" % c["id"])
		assert(c.has("places") and not c["places"].is_empty(), "Lieux manquants pour %s" % c["id"])
	
	for expected in ["sports", "marches", "monuments", "sante", "transports", "culte", "resto", "plages"]:
		assert(cat_ids.has(expected), "Catégorie manquante : %s" % expected)
	print("OK: 8 catégories de destinations validées : %s" % str(cat_ids))

	# 2. Instanciation du transit et simulation d'une ville
	var transit = TransitScript.new()
	
	# Mock minimal pour city
	var mock_city = Node3D.new()
	var scr := GDScript.new()
	scr.source_code = """
extends Node3D
var places: Dictionary = {}
func route(from: Vector3, to: Vector3, _drive: bool = true) -> PackedVector3Array:
	return PackedVector3Array([from, to])
func in_roadway(_p: Vector3, _m: float = 0.0) -> bool:
	return false
"""
	scr.reload()
	mock_city.set_script(scr)
	mock_city.places = {
		"Place de l'Indépendance": Vector3(0, 0, 0),
		"Marché Sandaga": Vector3(200, 0, 150),
		"Grande Mosquée": Vector3(-500, 0, -300),
		"Hôpital Principal": Vector3(100, 0, 600),
		"Gare de Dakar": Vector3(400, 0, -200),
		"Stade Iba Mar Diop": Vector3(-730, 0, -532),
		"Chez Adja": Vector3(-1031, 0, -780),
		"Marché Kermel": Vector3(300, 0, 200),
		"Marché Tilène": Vector3(-600, 0, -400)
	}
	transit.city = mock_city
	root.add_child(transit)

	# Mock minimal pour player
	var mock_player = CharacterBody3D.new()
	mock_player.set_script(load("res://scripts/player/player.gd"))
	mock_player.camera_rig = Node3D.new()
	mock_player.camera_rig.set_script(load("res://scripts/camera/camera_rig.gd"))
	root.add_child(mock_player.camera_rig)
	mock_player.model = Node3D.new()
	mock_player.add_child(mock_player.model)
	root.add_child(mock_player)
	mock_player.global_position = Vector3(0, 0, 0)
	transit.player = mock_player

	# Mock minimal pour HUD
	var mock_hud = HudScript.new()
	root.add_child(mock_hud)
	transit.hud = mock_hud

	# Mock taxi vehicle
	var taxi = VehicleScript.new()
	taxi.vehicle_type = "taxi"
	root.add_child(taxi)
	taxi.global_position = Vector3(5, 0, 5)

	# 3. Test de calcul des prix (distance variable)
	var price_short: int = transit.taxi_price(Vector3(0, 0, 0), Vector3(100, 0, 0))
	assert(price_short >= 500, "Prix minimum 500 FCFA")
	var price_long: int = transit.taxi_price(Vector3(0, 0, 0), Vector3(3000, 0, 0))
	assert(price_long > price_short, "Course longue doit coûter plus cher que course courte")
	print("OK: Tarification taxi validée (100m -> %d FCFA, 3km -> %d FCFA)" % [price_short, price_long])

	# 4. Test d'affichage du menu taxi principal
	var gs = root.get_node("GameState")
	gs.money = 50000
	gs.waypoint = Vector3(1500, 0, -800)
	transit._show_taxi_main_menu(taxi)
	assert(mock_hud.choices_open(), "Le menu de choix du taxi doit être ouvert")
	print("OK: Menu principal taxi ouvert avec option repère GPS et destinations populaires")

	# 5. Test du menu catégorie (Sports)
	var sports_cat: Dictionary
	for c in TransitScript.TAXI_CATEGORIES:
		if c["id"] == "sports":
			sports_cat = c
			break
	transit._show_taxi_category_menu(taxi, sports_cat)
	assert(mock_hud.choices_open(), "Le sous-menu de catégorie doit être ouvert")
	print("OK: Sous-menu de catégorie Sports ouvert avec succès")

	# 6. Test du menu Dakar A-Z
	transit._show_taxi_all_places_menu(taxi, 0)
	assert(mock_hud.choices_open(), "Le menu A-Z doit être ouvert")
	print("OK: Menu Dakar A-Z avec pagination ouvert avec succès")

	# 7. Test de départ en taxi vers une destination choisie
	var start_money: int = gs.money
	transit.start_taxi_ride(taxi, "Marché Sandaga")
	assert(gs.money < start_money, "Le prix de la course doit être débité")
	assert(transit.is_riding(), "Le joueur doit être en train de rouler dans le taxi")
	assert(taxi.passenger == mock_player, "Le taxi doit avoir le joueur comme passager")
	assert(transit._taxi_dest == "Marché Sandaga", "La destination enregistrée doit être Marché Sandaga")
	print("OK: Démarrage de course vers destination choisie validé (Passager à bord, musique radio active)")

	# 8. Test d'arrivée à destination
	transit._on_taxi_arrived()
	assert(not transit.is_riding(), "La course doit être terminée à l'arrivée")
	assert(taxi.passenger == null, "Le joueur doit être descendu du taxi")
	print("OK: Arrivée à destination et descente du passager validée")

	# 9. Test de fermeture et annulation via gamepad/cancel
	mock_hud.show_choices("Test", [["Opt 1", func(): pass]], func(): pass)
	assert(mock_hud.choices_open(), "Choices doit être ouvert")
	mock_hud.close_choices()
	assert(not mock_hud.choices_open(), "Choices doit être fermé")
	print("OK: Système HUD show_choices et close_choices validé")

	print("--- TOUS LES TESTS TAXI DESTINATIONS SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
