extends SceneTree
## Test hors-jeu du trafic du serveur en ligne (sans réseau) : les voitures respectent-elles STOP et cédez ?
##
##   godot --headless --path . -s res://tools/server_traffic_test.gd [-- --sans-regles]
##
## Simule 10 minutes de trafic autour de quelques joueurs immobiles et compte, à chaque fois qu'une voiture
## quitte l'arrivée d'un STOP, si elle s'est arrêtée avant ; plus les voitures restées bloquées.

func _initialize() -> void:
	_run.call_deferred()


## Chargé après le démarrage : les scripts du trafic utilisent les singletons du jeu (Net…)
func _run() -> void:
	await process_frame
	var city = load("res://scripts/world/dakar_city.gd").new()
	root.add_child(city)
	city.build_data_only()
	var tr = load("res://scripts/net/server_traffic.gd").new()
	tr.city = city
	root.add_child(tr)
	await process_frame
	var players: Array = []
	for k in city.rules:
		if city.rules[k] == city.RULE_STOP and players.size() < 6:
			var p: Vector3 = city.node_pos[k.y]
			var far := true
			for q in players:
				if q.distance_to(p) < 300.0:
					far = false
			if far:
				players.append(p)
	var all_rules: Dictionary = city.rules.duplicate()
	if "--sans-regles" in OS.get_cmdline_user_args():
		city.rules.clear() # comparaison : trafic d'avant les panneaux
	var seen := {} ## id → [clé, arrêtée]
	var still := {}
	var stops := 0
	var run := 0
	var stuck := 0
	var stuck_lights := 0
	var dt := 0.1
	for step in 6000:
		tr.lights._t += dt # la boucle ne laisse pas passer d'image : on fait avancer l'horloge des feux à la main
		tr.tick(dt, players)
		for id in tr.cars:
			var c: Dictionary = tr.cars[id]
			var key := Vector2i(c["from"], c["to"])
			var rec: Array = seen.get(id, [key, false])
			if rec[0] != key:
				var old: Vector2i = rec[0]
				if all_rules.get(old, 0) == city.RULE_STOP:
					if rec[1]:
						stops += 1
					else:
						run += 1
				rec = [key, false]
			var near_line: bool = float(c["L"]) - float(c["t"]) < city.stop_distance(c["from"], c["to"]) + 6.0
			var next_stop: bool = int(c.get("next", -1)) >= 0 and city.rule(c["to"], c["next"]) == city.RULE_STOP
			if float(c["speed"]) < 0.5 and (near_line or next_stop):
				rec[1] = true
			seen[id] = rec
			if float(c["speed"]) < 0.3:
				still[id] = float(still.get(id, 0.0)) + dt
				if still[id] > 25.0 and still[id] - dt <= 25.0:
					stuck += 1
					if tr.lights.has_lights(c["to"]):
						stuck_lights += 1
						if stuck_lights <= 5:
							print("  bloquée au feu : reste %.1f m, ligne %.1f m, état %d, file %d" % [float(c["L"]) - float(c["t"]), city.stop_distance(c["from"], c["to"]), tr.lights.state_for(c["to"], c["from"]), (tr._lanes.get(Vector2i(c["from"], c["to"]), []) as Array).size()])
			else:
				still[id] = 0.0
	print("SERVER_RULES joueurs=%d voitures=%d STOP marqués=%d STOP grillés=%d bloquées>25s=%d (dont aux feux %d)" % [players.size(), tr.cars.size(), stops, run, stuck, stuck_lights])
	quit()
