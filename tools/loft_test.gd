extends SceneTree
## Test du Loft du Plateau : panneau devant la porte, entrée, marche dans le salon, lit, sortie.
##
##   godot --headless --path . -s res://tools/loft_test.gd

const MAIN := "res://scenes/main.tscn"


func _initialize() -> void:
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 120:
		await process_frame
	var main := current_scene
	main.get("hud")._intro.visible = false
	var gs = root.get_node("GameState")
	var housing = main.housing
	var it = main.interiors
	var d = housing._doors["loft_plateau"] if housing.get("_doors") is Dictionary and housing._doors.has("loft_plateau") else null
	print("LOFT propriété : %s, prix %s" % [housing.PROPERTIES["loft_plateau"]["name"], gs.fcfa(housing.PROPERTIES["loft_plateau"]["price"])])
	gs.home["owned"] = ["loft_plateau"]
	housing._refresh()
	housing.enter("loft_plateau")
	await create_timer(2.0).timeout
	var p = main.player
	var o: Vector3 = it._rooms["home_loft"]
	print("LOFT dedans=%s indice entrée=« %s » y=%.2f" % [it.inside, p.get_interaction_hint(), p.global_position.y - o.y])
	# Marche vers le lit
	p.global_position = o + Vector3(3.0, 0.3, 1.0)
	await create_timer(1.5).timeout
	print("LOFT près du lit : indice=« %s » posé au sol=%s" % [p.get_interaction_hint(), absf(p.global_position.y - o.y) < 0.4])
	# Marche dans le salon : ne traverse pas le canapé
	p.global_position = o + Vector3(-2.0, 0.3, 3.5)
	Input.action_press("move_forward")
	await create_timer(3.0).timeout
	Input.action_release("move_forward")
	print("LOFT marche vers le canapé : arrêté à z=%.2f (canapé vers z=-2)" % (p.global_position.z - o.z))
	p.global_position = o + Vector3(0, 0.3, 4.2)
	await create_timer(0.5).timeout
	print("LOFT porte : indice=« %s »" % p.get_interaction_hint())
	it.try_interact()
	await create_timer(2.0).timeout
	print("LOFT sorti : dedans=« %s » y=%.1f" % [it.inside, p.global_position.y])
	quit()
