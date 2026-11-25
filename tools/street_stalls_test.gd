extends SceneTree
## Test hors-jeu des étals de rue : vendeur affiché, action « Acheter » proposée, achat d'un ataya.
##
##   godot --headless --path . -s res://tools/street_stalls_test.gd

const MAIN := "res://scenes/main.tscn"


func _initialize() -> void:
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 120:
		await process_frame
	var main := current_scene
	var city = main.get("city")
	var market = main.get("market")
	var gs = root.get_node("GameState")
	main.get("hud")._intro.visible = false
	var tea := -1
	for i in city.street_stalls.size():
		if city.street_stalls[i]["type"] == "the":
			tea = i
			break
	var st: Dictionary = city.street_stalls[tea]
	main.player.global_position = st["pos"] + st["face"] * 1.0 + Vector3(0, 0.5, 0)
	for i in 90:
		await physics_frame
	var vendors := 0
	for k in market._street_vendors:
		if is_instance_valid(market._street_vendors[k]):
			vendors += 1
	print("STALLS étals=%d vendeurs affichés=%d action=« %s »" % [city.street_stalls.size(), vendors, main.player.get_interaction_hint()])
	gs.money = 1000
	gs.thirst = 40.0
	gs.energy = 40.0
	var s = market._stall_near(main.player.global_position)
	market._buy(market.STREET["the"][1][0], 150)
	print("STALLS achat ataya : argent=%d soif=%.0f énergie=%.0f étal trouvé=%s" % [gs.money, gs.thirst, gs.energy, s != null])
	# Tenir l'étal : location, ventes aux passants, fermeture
	gs.money = 5000
	market._start_keeping(tea)
	var jm = main.player.job_manager
	print("STALLS étal loué : métier=%s argent=%d vendeur retiré=%s" % [jm.job, gs.money, not market._street_vendors.has(tea)])
	await create_timer(40.0).timeout
	print("STALLS après ~40 s : ventes=%d gagné=%d objectif=« %s »" % [market._keep_sold, market._keep_earned, jm.objective])
	print("STALLS action=« %s »" % main.player.get_interaction_hint())
	market.try_interact()
	print("STALLS fermé : étal=%d métier=« %s »" % [market._keep, jm.job])
	# Loin de tout étal : plus de vendeur
	main.player.global_position = Vector3(5000, 0.5, 5000)
	for i in 90:
		await physics_frame
	print("STALLS loin : vendeurs=%d" % market._street_vendors.size())
	quit()
