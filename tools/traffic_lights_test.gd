extends SceneTree
## Test hors-jeu des feux tricolores : les voitures s'arrêtent-elles au rouge, les piétons attendent-ils le bonhomme vert ?
##
##   godot --headless --path . -s res://tools/traffic_lights_test.gd
##
## Place le joueur près de carrefours à feux et compte les voitures qui franchissent le carrefour : au vert,
## à l'orange, ou au rouge (rouge depuis plus de 2 s = feu grillé), plus les voitures bloquées.

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
	var lights = city.lights
	main.get("hud")._intro.visible = false
	Engine.time_scale = 2.0
	var sites: Array = []
	for n in city.signal_nodes:
		var p: Vector3 = city.node_pos[n]
		if p.length() > 1500.0:
			continue
		var far := true
		for q in sites:
			if q.distance_to(p) < 300.0:
				far = false
		if far:
			sites.append(p)
		if sites.size() >= SITES:
			break
	var green := 0
	var orange := 0
	var red := 0
	var stuck := 0
	var stopped := 0
	var seen := {} ## voiture → [tronçon, état du feu quand elle était à la ligne, temps de rouge écoulé]
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
				var rec: Array = seen.get(v, [key, -1, 0.0])
				if rec[0] != key:
					var old: Vector2i = rec[0]
					if old.x >= 0 and lights.has_lights(old.y) and int(rec[1]) >= 0:
						match int(rec[1]):
							0: green += 1
							1: orange += 1
							_:
								if float(rec[2]) > 2.0:
									red += 1
								else:
									orange += 1
					rec = [key, -1, 0.0]
				if lights.has_lights(v.ai_to):
					var np: Vector3 = city.node_pos[v.ai_to]
					var dn := Vector2(v.global_position.x - np.x, v.global_position.z - np.z).length()
					var line: float = city.stop_distance(v.ai_from, v.ai_to) + v.size.z / 2.0
					var s: int = lights.state_for(v.ai_to, v.ai_from)
					# État du feu au moment où l'avant de la voiture franchit la ligne
					if dn < line and int(rec[1]) < 0:
						rec[1] = s
					if s == 2:
						rec[2] = float(rec[2]) + dt
					else:
						rec[2] = 0.0
					if absf(v.speed) < 0.3 and dn < line + 12.0 and s == 2:
						stopped += 1 if float(still.get(v, 0.0)) == 0.0 else 0
				seen[v] = rec
				if absf(v.speed) < 0.3:
					still[v] = float(still.get(v, 0.0)) + dt
					if still[v] > 40.0 and still[v] - dt <= 40.0:
						stuck += 1
				else:
					still[v] = 0.0
	print("LIGHTS sites=%d passages vert=%d orange=%d rouge(grillé)=%d arrêts au rouge=%d bloquées>40s=%d" % [sites.size(), green, orange, red, stopped, stuck])
	quit()
