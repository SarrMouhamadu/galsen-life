extends SceneTree
## Vérifie chaque vrai modèle de véhicule en jeu : le joueur monte, accélère, tourne ; puis le même
## véhicule roule seul dans le trafic. Affiche une ligne CHECK par modèle (et des captures avec --shots=dossier).
##
##   godot --path . -s res://tools/vehicle_check.gd -- [--shots=C:/dossier]

const MAIN := "res://scenes/main.tscn"
const MODELS := [["taxi", "taxi"], ["clando", "clando1"], ["clando", "sf_bmw2002"], ["police", "police"], ["police", "sf_caprice"],
	["police", "sf_caprice78"], ["jakarta", "sf_dt125"], ["grosse_moto", "sf_dt125"], ["car_rapide", "sf_car_rapide"], ["ndiaga", "sf_ndiaga"],
	["bus", "bus"], ["coach", "sf_coach"], ["army", "suv"], ["van", "van"]]


func _initialize() -> void:
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 90:
		await process_frame
	var main := current_scene
	main.get("hud")._intro.visible = false
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	var Vehicle = load("res://scripts/vehicles/vehicle.gd")
	var city = main.city
	var player = main.player
	# Une longue ligne droite : départ sur un nœud de route, cap vers son voisin le plus éloigné
	var start: Vector3 = city.places["Place de l'Indépendance"]
	var bad := 0
	for m in MODELS:
		var v = Vehicle.new()
		v.vehicle_type = m[0]
		v.model_override = m[1]
		main.add_child(v)
		v.respawn_in_traffic(city, start, 20.0, 80.0)
		v.ai_enabled = false
		v.speed = 0.0
		await physics_frame
		var p0: Vector3 = v.global_position
		player.global_position = p0
		player.enter_vehicle(v)
		var wheels: int = v._wheels.size()
		var w0: Basis = v._wheels[0].transform.basis if wheels > 0 else Basis()
		Input.action_press("move_forward")
		await create_timer(2.5).timeout
		var top: float = v.speed
		Input.action_press("move_left")
		await create_timer(0.8).timeout
		Input.action_release("move_left")
		Input.action_release("move_forward")
		var spun: bool = wheels > 0 and not v._wheels[0].transform.basis.is_equal_approx(w0)
		var moved: float = Vector2(v.global_position.x - p0.x, v.global_position.z - p0.z).length()
		var ground_ok: bool = absf(v.global_position.y - p0.y) < 1.5
		var tilt: float = rad_to_deg(acos(clampf(v.global_transform.basis.y.dot(Vector3.UP), -1.0, 1.0)))
		var aabb := AABB()
		for mi in v.get_node("Modele").find_children("*", "MeshInstance3D", true, false):
			var b: AABB = v.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			aabb = b if aabb.size == Vector3.ZERO else aabb.merge(b)
		if shots != "":
			var cam: Camera3D = root.get_viewport().get_camera_3d()
			await create_timer(0.6).timeout
			await RenderingServer.frame_post_draw
			root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, m[1]])
		player.exit_vehicle()
		await create_timer(0.3).timeout
		# Le même véhicule, conduit par l'IA
		v.respawn_in_traffic(city, start, 20.0, 80.0)
		v.ai_enabled = true
		var a0: Vector3 = v.global_position
		await create_timer(4.0).timeout
		var ai_moved: float = Vector2(v.global_position.x - a0.x, v.global_position.z - a0.z).length()
		var ok: bool = top > 3.0 and moved > 4.0 and ground_ok and tilt < 20.0 and (wheels == 0 or spun) and aabb.size.z > aabb.size.x
		if not ok:
			bad += 1
		print("CHECK %-6s %-11s %-14s vitesse=%4.1f m/s parcours=%5.1f m roues=%d tournent=%s inclinaison=%4.1f° modèle=%.1fx%.1fx%.1f taille=%.1fx%.1fx%.1f IA=%5.1f m" % [
			"OK" if ok else "ÉCHEC", m[0], m[1], top, moved, wheels, spun, tilt, aabb.size.x, aabb.size.y, aabb.size.z,
			v.size.x, v.size.y, v.size.z, ai_moved])
		v.queue_free()
		await create_timer(0.2).timeout
	print("CHECK fini : %d échec(s)" % bad)
	quit()
