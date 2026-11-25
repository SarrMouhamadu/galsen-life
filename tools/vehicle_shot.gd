extends SceneTree
## Vitrine des véhicules 3D : aligne chaque modèle (types × variantes) et prend une capture.
##
##   godot --path . -s res://tools/vehicle_shot.gd -- --out=C:/chemin/vitrine.png [--side]

const MAIN := "res://scenes/main.tscn"
const SHOW := [["clando", "sf_bmw2002"], ["police", "sf_caprice"], ["police", "sf_caprice78"], ["jakarta", "sf_dt125"],
	["car_rapide", "sf_car_rapide"], ["ndiaga", "sf_ndiaga"], ["coach", "sf_coach"]]


func _initialize() -> void:
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 90:
		await process_frame
	var main := current_scene
	main.get("hud")._intro.visible = false
	var out := "user://vitrine.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var side := "--side" in OS.get_cmdline_user_args()
	var info: Array = main.city.place_info["Place de l'Indépendance"]
	var c := Vector3(info[9], 0.2, info[10])
	var Vehicle = load("res://scripts/vehicles/vehicle.gd")
	var x := -16.0
	for s in SHOW:
		var v = Vehicle.new()
		v.vehicle_type = s[0]
		v.model_override = s[1]
		var w: float = 13.0 if s[0] == "coach" else 4.2
		main.add_child(v)
		v.global_position = c + Vector3(x + w / 2.0, 0, 20.0)
		v.rotation.y = PI / 2.0 if side else PI - 0.5
		if v._rider:
			v._rider.visible = true
		x += w if not side else maxf(w, 6.0)
	main.player.global_position = c + Vector3(0, 0.5, 34.0)
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	for i in 30:
		await process_frame
	cam = root.get_viewport().get_camera_3d()
	main.set_process(false)
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	cam.global_position = c + Vector3(4.0, 5.0, 36.0)
	cam.look_at(c + Vector3(4.0, 0.8, 20.0))
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("SHOT ", out)
	quit()
