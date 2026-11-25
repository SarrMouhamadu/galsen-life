extends SceneTree
## Outil hors-jeu : liste tous les objets solides posés sur la chaussée (là où roulent les voitures).
##
##   godot --headless --path . -s res://tools/road_audit.gd
##
## Charge la partie (sauvegarde de test), attend que la ville et ses décors soient en place, puis parcourt
## chaque forme de collision qui n'est ni le sol, ni un bâtiment, ni un trottoir, ni un véhicule ou un personnage.

const MAIN := "res://scenes/main.tscn"


func _initialize() -> void:
	root.get_node("GameState").save_path = "user://test_save.json"
	change_scene_to_file.call_deferred(MAIN)
	_run.call_deferred()


func _run() -> void:
	for i in 240:
		await process_frame
	var main := current_scene
	var city = main.get("city")
	var cats := {}
	var total := 0
	for body in main.find_children("*", "CollisionObject3D", true, false):
		if body is CharacterBody3D or body is VehicleBody3D or body is RigidBody3D or body is Area3D:
			continue
		var path := str(main.get_path_to(body))
		if path.contains("Bloc_") or path.contains("SolCollision") or path.contains("Trottoirs") or path.contains("Pont"):
			continue
		for cs in body.find_children("*", "CollisionShape3D", true, false):
			if cs.disabled or cs.shape == null or cs.shape is ConcavePolygonShape3D or cs.shape is WorldBoundaryShape3D:
				continue
			var bb: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
			if bb.position.y > 2.0 or bb.size.x > 30.0 or bb.size.z > 30.0:
				continue
			total += 1
			if _on_road(city, cs.global_transform, cs.shape.get_debug_mesh().get_aabb()):
				_add(cats, "%s %s (%.1f×%.1f m)" % [_category(body), cs.shape.get_class(), bb.size.x, bb.size.z], bb.get_center())
	# Objets visibles (sans collision) : centre de la boîte englobante au ras du sol
	for mi in main.find_children("*", "GeometryInstance3D", true, false):
		var path := str(main.get_path_to(mi))
		if path.contains("Bloc_") or path.contains("Sol") or path.contains("Pietons") or path.contains("Traffic") or not mi.is_visible_in_tree():
			continue
		if _under_actor(mi):
			continue
		if mi is MultiMeshInstance3D:
			var mm: MultiMesh = mi.multimesh
			if mm == null:
				continue
			for k in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
				var q: Vector3 = mi.global_transform * mm.get_instance_transform(k).origin
				if q.y < 3.0 and city.in_roadway(q, -0.2):
					_add(cats, "[visuel] " + _category(mi), q)
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		var c := bb.get_center()
		if bb.position.y > 2.0 or bb.size.x > 30.0 or bb.size.z > 30.0:
			continue
		total += 1
		if _on_road(city, mi.global_transform, mi.get_aabb()):
			var mesh_name: String = (mi.mesh.get_class() if mi is MeshInstance3D and mi.mesh else mi.get_class())
			_add(cats, "[visuel] %s %s (%.1f×%.1f×%.1f m)" % [_category(mi), mesh_name, bb.size.x, bb.size.y, bb.size.z], c)
	print("AUDIT %d formes solides au sol" % total)
	for cat in cats:
		print("AUDIT %-40s %4d sur la chaussée, ex. %s" % [cat, cats[cat].size(), cats[cat].slice(0, 4)])
	if cats.is_empty():
		print("AUDIT aucune chaussée bloquée")
	quit()


## Nom lisible : script ou nom du nœud parent le plus parlant
func _category(n: Node) -> String:
	var parts: Array = []
	var cur := n
	for k in 4:
		if cur == null or cur == current_scene:
			break
		var s: Script = cur.get_script()
		parts.append(s.resource_path.get_file() if s != null else str(cur.name).rstrip("0123456789@_"))
		cur = cur.get_parent()
	return " < ".join(parts)


func _add(cats: Dictionary, cat: String, p: Vector3) -> void:
	if not cats.has(cat):
		cats[cat] = []
	cats[cat].append(Vector2i(int(p.x), int(p.z)))


## Véhicules, personnages : ils bougent, ce ne sont pas des obstacles fixes
func _under_actor(n: Node) -> bool:
	var cur := n.get_parent()
	while cur != null and cur != current_scene:
		if cur is VehicleBody3D or cur is CharacterBody3D or cur is RigidBody3D:
			return true
		cur = cur.get_parent()
	return false


## Un coin de l'emprise réelle (boîte locale transformée) ou son centre mord sur la chaussée d'au moins 25 cm
func _on_road(city, xf: Transform3D, box: AABB) -> bool:
	var e := box.end
	var o := box.position
	for q in [box.get_center(), Vector3(o.x, o.y, o.z), Vector3(e.x, o.y, o.z), Vector3(o.x, o.y, e.z), Vector3(e.x, o.y, e.z)]:
		var w: Vector3 = xf * q
		if city.in_roadway(Vector3(w.x, 0.0, w.z), -0.25):
			return true
	return false
