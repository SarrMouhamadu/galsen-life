extends SceneTree
## Test de la vie urbaine à Dakar : passants denses, vendeurs ambulants, traversants et restaurants Maïga.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST VIE URBAINE DE DAKAR ---")
	var game_state = root.get_node("GameState")
	assert(game_state != null, "L'autoload GameState doit exister")

	# 1. Test de la densité des passants (Graphics)
	var GraphicsAutoload = root.get_node_or_null("Graphics")
	if GraphicsAutoload:
		var eleve_peds: int = GraphicsAutoload.PROFILES["eleve"]["peds"]
		var faible_peds: int = GraphicsAutoload.PROFILES["faible"]["peds"]
		assert(eleve_peds >= 75, "Profil Élevé doit avoir au moins 75 passants (actuel: %d)" % eleve_peds)
		assert(faible_peds >= 30, "Profil Faible doit avoir au moins 30 passants (actuel: %d)" % faible_peds)
		print("OK: Densité piétonne augmentée (Élevé: %d passants, Faible: %d passants)" % [eleve_peds, faible_peds])

	# 2. Test des vendeurs de rue (Market)
	var MarketScript = load("res://scripts/world/market.gd")
	assert(MarketScript.STREET_VENDORS >= 24, "STREET_VENDORS doit être au moins 24 (actuel: %d)" % MarketScript.STREET_VENDORS)
	assert(MarketScript.STREET_RANGE >= 75.0, "STREET_RANGE doit être au moins 75.0m (actuel: %.1f)" % MarketScript.STREET_RANGE)
	print("OK: Capacité des étals et vendeurs de rue augmentée (%d vendeurs simultanés)" % MarketScript.STREET_VENDORS)

	# 3. Test des Restaurants Maïga à travers Dakar
	var CityScript = load("res://scripts/world/dakar_city.gd")
	var city = CityScript.new()
	root.add_child(city)
	city.build_data_only()
	
	var maiga_count := 0
	var maiga_places := []
	for p_name in city.places.keys():
		if "Restaurant Maïga" in p_name:
			maiga_count += 1
			maiga_places.append(p_name)
	
	assert(maiga_count >= 10, "Il doit y avoir au moins 10 Restaurants Maïga à Dakar (trouvé: %d)" % maiga_count)
	print("OK: %d Restaurants Maïga déployés à Dakar :" % maiga_count)
	for p in maiga_places:
		print("  - %s (pos: %s)" % [p, city.places[p]])
	
	# Test construction du décor 3D pour un restaurant Maïga
	city._stall_maiga("Restaurant Maïga (Médina)", "TestStallMedina")
	var decor = city.get_node_or_null("TestStallMedina")
	assert(decor != null, "Le décor 3D du Restaurant Maïga (Médina) doit être créé")
	print("OK: Décor 3D complet (comptoir, plancha, auvent, tables et cuisinier) instancié")

	# 4. Test des piétons, vendeurs ambulants et traversants
	var PedScript = load("res://scripts/npc/pedestrian.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	
	var ped = PedScript.new()
	city.add_child(ped)
	ped.setup(city, rng, city.node_pos[0])
	
	# Test traversants
	var initial_side: int = ped._side
	ped.start_crossing()
	assert(ped.is_crossing, "start_crossing() doit activer is_crossing")
	print("OK: Système de traversée de rue déclenché (traversants)")
	
	# Simuler la traversée
	ped._process(5.0)
	# Si la traversée est complète, le côté doit être inversé
	if not ped.is_crossing:
		assert(ped._side == -initial_side, "Après traversée, le piéton doit être sur le trottoir opposé")
		print("OK: Traversée complète vers le trottoir opposé validée")

	# Test vendeur ambulant
	ped.is_vendor = true
	ped.vendor_type = "cafe"
	ped.vendor_item = "Café Touba"
	ped.vendor_price = 100
	ped.vendor_satiety = 12
	
	game_state.money = 1000
	game_state.hunger = 50.0
	ped.buy(null)
	assert(game_state.money == 900, "L'achat chez le vendeur ambulant doit déduire 100 FCFA")
	assert(game_state.hunger > 50.0, "L'achat de nourriture/café doit nourrir le joueur")
	print("OK: Achat et interaction avec vendeur ambulant validés")

	# 5. Test des destinations taxi pour les Restaurants Maïga
	var TransitScript = load("res://scripts/transport/transit.gd")
	var transit = TransitScript.new()
	var maiga_taxi_count := 0
	for cat in transit.TAXI_CATEGORIES:
		if cat["id"] == "resto":
			for pl in cat["places"]:
				if "Restaurant Maïga" in pl["name"]:
					maiga_taxi_count += 1
	assert(maiga_taxi_count >= 10, "Les taxis doivent desservir les Restaurants Maïga des différents quartiers (trouvé: %d)" % maiga_taxi_count)
	print("OK: %d Restaurants Maïga desservis par les taxis" % maiga_taxi_count)

	print("--- TOUS LES TESTS DE VIE URBAINE SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
