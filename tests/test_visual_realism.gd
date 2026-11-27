extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST RÉALISME VISUEL ET TEXTURES DE DAKAR ---")

	var textures_to_check := [
		"res://textures/ui/dakar_corniche.jpg",
		"res://textures/ui/dakar_bg.jpg",
		"res://textures/ui/mic_on.svg",
		"res://textures/ui/mic_muted.svg",
		"res://textures/world/renaissance_monument.jpg",
		"res://textures/world/car_rapide_dakar.jpg",
		"res://textures/world/car_rapide_yellow.jpg",
		"res://textures/world/maiga_banner.svg",
		"res://textures/world/wave_kiosk.svg",
		"res://textures/world/orange_money.svg",
		"res://textures/world/road_sign.svg",
		"res://textures/world/car_rapide_side.svg",
		"res://textures/world/flag_senegal.svg",
		"res://textures/world/dakar_maisons_rue.jpg",
		"res://textures/world/dakar_route_corniche.jpg",
		"res://textures/world/dakar_immeubles_plateau.jpg",
		"res://textures/world/dakar_medina_maisons.jpg",
		"res://textures/world/dakar_marche_sandaga.jpg",
		"res://textures/world/dakar_lutte_senegalaise.jpg",
		"res://textures/world/dakar_fresque_murale.jpg",
		"res://textures/world/dakar_etal_marche.jpg",
		"res://textures/world/dakar_artisanat_medina.jpg",
		"res://textures/ui/dakar_maisons_rue.jpg",
		"res://textures/ui/dakar_route_corniche.jpg"
	]

	var Mk = load("res://scripts/util/mk.gd")
	for tex_path in textures_to_check:
		assert(FileAccess.file_exists(tex_path) or ResourceLoader.exists(tex_path), "Texture manquante : %s" % tex_path)
		var res = Mk.load_texture(tex_path)
		assert(res != null, "Impossible de charger la ressource : %s" % tex_path)
		print("  [OK] Texture chargée avec succès : %s" % tex_path)

	print("[PASS] Toutes les textures haute résolution et vectorielles sont valides !")

	# Test des décors de ville DakarCity (Kiosques Wave, Orange Money, Panneaux JOJ 2026, Maïga, Étalages, Attaya)
	var DakarCityScript = load("res://scripts/world/dakar_city.gd")
	var city = DakarCityScript.new()
	root.add_child(city)
	city.build_data_only()
	city._build_job_decor()

	var has_wave_kiosk := false
	var has_orange_kiosk := false
	var has_road_sign := false
	var has_maiga_banner := false

	for child in city.get_children():
		if "Kiosk_wave" in child.name:
			has_wave_kiosk = true
		elif "Kiosk_orange" in child.name:
			has_orange_kiosk = true
		elif "RoadSign" in child.name:
			has_road_sign = true
		elif "StallMaiga" in child.name:
			for sub in child.get_children():
				if sub is MeshInstance3D and sub.mesh is QuadMesh:
					has_maiga_banner = true

	assert(has_wave_kiosk, "Kiosque Wave doit être présent dans la ville")
	assert(has_orange_kiosk, "Kiosque Orange Money doit être présent dans la ville")
	assert(has_road_sign, "Panneaux routiers Dakar / JOJ 2026 doivent être présents")
	assert(has_maiga_banner, "Bannière réaliste Maïga texturée doit être présente")

	var urban_decor: Node3D = city.get_node_or_null("UrbanDecor")
	assert(urban_decor != null, "UrbanDecor doit exister")
	var has_fruit_stall := false
	var has_attaya_spot := false
	var has_tailor := false
	var has_indep_fountain := false
	var has_flagpole := false
	var has_indep_stele := false
	var has_plaza_bench := false
	var has_flowerbed := false
	var has_renaissance_monument := false
	var has_porte_millenaire := false
	var has_mosquee_minaret := false
	var has_phare := false

	for decor_child in urban_decor.get_children():
		var n: String = decor_child.name
		if "FruitStall" in n:
			has_fruit_stall = true
		elif "AttayaSpot" in n:
			has_attaya_spot = true
		elif "TailorWorkshop" in n:
			has_tailor = true
		elif "IndependanceFountain" in n:
			has_indep_fountain = true
		elif "NationalFlagpole" in n:
			has_flagpole = true
		elif "IndependanceStele" in n:
			has_indep_stele = true
		elif "PlazaBench" in n:
			has_plaza_bench = true
			assert(decor_child.is_in_group("chairs"), "Les bancs de la place doivent être dans le groupe 'chairs' pour s'asseoir")
		elif "FlowerBed" in n:
			has_flowerbed = true
		elif "MonumentRenaissanceAfricaine" in n:
			has_renaissance_monument = true
		elif "PorteDuMillenaire" in n:
			has_porte_millenaire = true
		elif "GrandeMosqueeMinaret" in n:
			has_mosquee_minaret = true
		elif "PhareDesMamelles" in n:
			has_phare = true

	assert(has_fruit_stall, "Étal de fruits sénégalais doit être présent")
	assert(has_attaya_spot, "Coin thé Attaya sénégalais doit être présent")
	assert(has_tailor, "Atelier de tailleur/couture de la Médina doit être présent")
	assert(has_indep_fountain, "Grande Fontaine de la Place de l'Indépendance doit être présente")
	assert(has_flagpole, "Mât officiel avec drapeau national du Sénégal doit être présent")
	assert(has_indep_stele, "Stèle commémorative du 4 Avril 1960 doit être présente")
	assert(has_plaza_bench, "Bancs publics en acajou (groupe chairs) doivent être présents")
	assert(has_flowerbed, "Parterres floraux géométriques doivent être présents")
	assert(has_renaissance_monument, "Monument colossal de la Renaissance Africaine (52m) doit être présent")
	assert(has_porte_millenaire, "Porte du Troisième Millénaire doit être présente")
	assert(has_mosquee_minaret, "Minaret hispano-mauresque de 67m de la Grande Mosquée doit être présent")
	assert(has_phare, "Phare des Mamelles historique de 1864 doit être présent")

	print("  [OK] Éléments culturels urbains (Fruits locaux, Thé Attaya, Tailleur Médina) validés !")
	print("  [OK] Infrastructures et Monuments du Sénégal (Fontaine Indépendance, Mât & Drapeau, Stèle 1960, Renaissance Africaine 52m, Porte du Millénaire, Minaret 67m, Phare Mamelles) validés !")
	print("[PASS] Éléments urbains réalistes (Wave, Orange Money, Panneaux Dakar 2026, Maïga, Étalages) validés !")
	city.queue_free()

	# Validation des routes, transports et destinations de navigation
	var TransitScript = load("res://scripts/transport/transit.gd")
	assert(TransitScript != null, "TransitScript doit exister")
	var mon_cat_found := false
	for cat in TransitScript.TAXI_CATEGORIES:
		if cat["id"] == "monuments":
			mon_cat_found = true
			var place_keys: Array = []
			for p in cat["places"]:
				place_keys.append(p.get("place", ""))
			assert(place_keys.has("Monument de la Renaissance Africaine"), "Monument Renaissance dans les taxis")
			assert(place_keys.has("Porte du Millénaire"), "Porte du Millénaire dans les taxis")
			assert(place_keys.has("Place de l'Indépendance"), "Place de l'Indépendance dans les taxis")
			assert(place_keys.has("Phare des Mamelles"), "Phare des Mamelles dans les taxis")
			assert(place_keys.has("Grande Mosquée"), "Grande Mosquée dans les taxis")
	assert(mon_cat_found, "Catégorie monuments trouvée dans les taxis")
	print("  [OK] Intégration GPS, Taxis et Transports pour tous les monuments validée !")

	print("--- TOUS LES TESTS DE RÉALISME VISUEL SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
