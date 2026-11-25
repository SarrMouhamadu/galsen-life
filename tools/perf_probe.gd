extends SceneTree
## Mesure de performance de la ville : mémoire, mémoire vidéo, appels de dessin, images par seconde.
##
##   godot --path . --resolution 1280x720 -s res://tools/perf_probe.gd -- --graphics=faible [--scn=res://chemin/city.scn]
##
## Va à quelques endroits typiques (Plateau aux tours, Médina, grand carrefour, banlieue) et affiche une ligne par endroit.

const MAIN := "res://scenes/main.tscn"
const SPOTS := {"plateau": Vector3(219, 0.5, 849.5), "medina": Vector3(-1176.9, 0.5, -606.7), "rebeuss": Vector3(-273.8, 0.5, 112.3), "carrefour": Vector3(165.5, 0.5, -137.9), "banlieue": Vector3(-1031, 0.5, -780)}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scn="):
			load("res://scripts/world/dakar_city.gd").scene_override = a.trim_prefix("--scn=")
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 60:
		await process_frame
	var main := current_scene
	main.get("hud")._intro.visible = false
	print("PERF textures=%d Mo tampons=%d Mo" % [Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576])
	print("PERF profil=%s mémoire après chargement=%d Mo vidéo=%d Mo" % [root.get_node("Graphics").profile,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	for spot in SPOTS:
		main.player.global_position = SPOTS[spot]
		for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
			main.camera_rig.yaw = yaw
			for i in 30:
				await process_frame
		var frames := 0
		var t0 := Time.get_ticks_usec()
		var draws := 0.0
		var prims := 0.0
		var worst := 0.0
		var last := t0
		for yaw in [0.0, PI * 0.5, PI, PI * 1.5]:
			main.camera_rig.yaw = yaw
			for i in 60:
				await process_frame
				var now := Time.get_ticks_usec()
				worst = maxf(worst, (now - last) / 1000.0)
				last = now
				frames += 1
				draws = maxf(draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				prims = maxf(prims, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if "--detail" in OS.get_cmdline_user_args():
			_detail(main)
		var secs := (Time.get_ticks_usec() - t0) / 1000000.0
		print("PERF %-9s ips=%5.1f pire image=%5.1f ms appels max=%4d triangles max=%7d objets=%d mémoire=%d Mo vidéo=%d Mo" % [spot, frames / secs, worst, draws, prims,
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	quit()


## Triangles des objets visibles à portée de vue, par catégorie (script ou nom du parent)
func _detail(main: Node) -> void:
	var cam: Camera3D = root.get_viewport().get_camera_3d()
	var cats := {}
	for mi in main.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var d: float = mi.global_position.distance_to(cam.global_position)
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if not cam.is_position_in_frustum(aabb.get_center()) and aabb.size.length() < 200.0:
			continue
		if mi.visibility_range_end > 0.0 and d > mi.visibility_range_end:
			continue
		var tris := 0
		for si in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(si)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var owner_node: Node = mi
		var cat := ""
		while owner_node != null and owner_node != main:
			if owner_node.get_script() != null:
				cat = (owner_node.get_script() as Script).resource_path.get_file()
				break
			owner_node = owner_node.get_parent()
		if cat == "":
			cat = mi.get_parent().name
		var c: Array = cats.get(cat, [0, 0])
		c[0] += tris
		c[1] += 1
		cats[cat] = c
	var keys := cats.keys()
	keys.sort_custom(func(a, b): return cats[a][0] > cats[b][0])
	for k in keys.slice(0, 10):
		print("    %-28s %8d triangles  %4d objets" % [k, cats[k][0], cats[k][1]])
