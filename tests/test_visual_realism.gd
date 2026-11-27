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
		"res://textures/ui/dakar_maisons_rue.jpg",
		"res://textures/ui/dakar_route_corniche.jpg"
	]

	for tex_path in textures_to_check:
		assert(ResourceLoader.exists(tex_path), "Texture manquante : %s" % tex_path)
		var res = load(tex_path)
		assert(res != null, "Impossible de charger la ressource : %s" % tex_path)
		print("  [OK] Texture chargée avec succès : %s" % tex_path)

	print("[PASS] Toutes les textures haute résolution et vectorielles sont valides !")

	# Test des décors de ville DakarCity (Kiosques Wave, Orange Money, Panneaux JOJ 2026, Maïga)
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
	print("[PASS] Éléments urbains réalistes (Wave, Orange Money, Panneaux Dakar 2026, Maïga) validés !")
	city.queue_free()

	print("--- TOUS LES TESTS DE RÉALISME VISUEL SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
