extends SceneTree
## Test hors-jeu : les voitures respectent-elles les panneaux, les piétons traversent-ils sans être bloqués ?
##
##   godot --headless --path . -s res://tools/traffic_rules_test.gd
##
## Place le joueur (à pied) près de carrefours à STOP, laisse rouler la circulation, puis compte :
## arrêts marqués aux STOP, STOP franchis sans arrêt, voitures restées bloquées, piétons qui attendent trop.

const MAIN := "res://scenes/main.tscn"
const SITES := 4
const SECONDS_PER_SITE := 60.0


func _initialize() -> void:
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 120:
		await process_frame
	var main := current_scene
	var city = main.get("city")
	main.get("hud")._intro.visible = false
	Engine.time_scale = 2.0
	# Carrefours à STOP proches du centre, bien séparés
	var sites: Array = []
	for k in city.rules:
		if city.rules[k] != city.RULE_STOP:
			continue
		var p: Vector3 = city.node_pos[k.y]
		if p.length() > 900.0:
			continue
		var far := true
		for q in sites:
			if q.distance_to(p) < 300.0:
				far = false
		if far:
			sites.append(p)
		if sites.size() >= SITES:
			break
	var stops := 0
	var run_through := 0
	var yields := 0
	var stuck := 0
	var ped_long := 0
	var seen := {} ## voiture → [clé du tronçon, s'est arrêtée]
	for site in sites:
		main.player.global_position = site + Vector3(6, 0.5, 6)
		var t := 0.0
		var still := {}
		while t < SECONDS_PER_SITE:
			await physics_frame
			var dt: float = (1.0 / Engine.physics_ticks_per_second) * Engine.time_scale
			t += dt
			for v in main.get("traffic"):
				if not is_instance_valid(v) or v.ai_city == null or v.ai_to < 0:
					continue
				var key := Vector2i(v.ai_from, v.ai_to)
				var np: Vector3 = city.node_pos[v.ai_to]
				var dn := Vector2(v.global_position.x - np.x, v.global_position.z - np.z).length()
				# [tronçon, arrêtée près de la ligne, dernière position]
				var rec: Array = seen.get(v, [key, false, v.global_position])
				if rec[0] != key:
					# La voiture vient de quitter le tronçon précédent : si c'était l'arrivée d'un STOP, a-t-elle marqué l'arrêt ?
					var teleport: bool = (rec[2] as Vector3).distance_to(v.global_position) > 15.0
					var old: Vector2i = rec[0]
					if not teleport and old.x >= 0 and city.rule(old.x, old.y) != 0:
						if city.rule(old.x, old.y) == city.RULE_STOP:
							if rec[1]:
								stops += 1
							else:
								run_through += 1
						else:
							yields += 1
					rec = [key, false, v.global_position]
				if absf(v.speed) < 0.5 and dn < city.stop_distance(v.ai_from, v.ai_to) + v.size.z + 4.0:
					rec[1] = true
				# Le tronçon d'avant le carrefour est parfois très court : un arrêt juste avant compte aussi
				if absf(v.speed) < 0.5 and v.ai_next >= 0 and city.rule(v.ai_to, v.ai_next) == city.RULE_STOP:
					rec[1] = true
				rec[2] = v.global_position
				seen[v] = rec
				# Bloquée : à l'arrêt plus de 25 s sans feu rouge
				if absf(v.speed) < 0.3:
					still[v] = float(still.get(v, 0.0)) + dt
					if still[v] > 25.0 and still[v] - dt <= 25.0:
						stuck += 1
				else:
					still[v] = 0.0
			for p in get_nodes_in_group("pedestrians"):
				if p.get("_cross_wait") != null and p._cross_wait > 20.0 and p._cross_wait - dt <= 20.0:
					ped_long += 1
	print("RULES sites=%d STOP marqués=%d STOP grillés=%d cédez franchis=%d voitures bloquées>25s=%d piétons attente>20s=%d" % [sites.size(), stops, run_through, yields, stuck, ped_long])
	quit()
