extends Node
## Préparation des graphismes à l'entrée en jeu (écran « Préparation de Dakar... »).
## Sur téléphone, chaque matériau est compilé par le pilote la première fois qu'il est dessiné.
## Dessiner toute la ville d'un coup figeait le jeu de longues secondes (44 s sur émulateur) et
## les petits téléphones (PowerVR, Mali) fermaient le jeu avant la première image.
## Ici, une caméra loin sous la ville montre une copie de chaque matériau, quelques-uns par image,
## derrière un écran de chargement ; le jeu est en pause pendant ce temps.
##
## Certains pilotes (puces PowerVR des petits téléphones) plantent en dessinant un matériau précis.
## Avant chaque image, les matériaux qu'elle montre pour la première fois sont notés dans PENDING_PATH.
## Si le jeu se ferme deux fois de suite sur le même matériau, il est mis de côté (AVOID_PATH) :
## les objets qui l'utilisent ne sont plus dessinés sur ce téléphone, et le jeu tient.
## Une seule fermeture ne suffit pas (le téléphone peut aussi fermer le jeu faute de mémoire), et les
## grands objets (la ville elle-même) ne sont jamais cachés : le jeu serait injouable.
##
## Les matériaux déjà préparés depuis le lancement ne le sont plus (retour du menu, partie recommencée).

const STAGE := Vector3(0.0, -3000.0, 0.0) ## sous la ville : rien d'autre n'est dans le champ
const SHOW_FRAMES := 2 ## images où chaque copie reste visible (passe d'ombre comprise)
const SLOW_FRAME := 0.25 ## image plus lente (s) : moins de nouveaux matériaux à la fois
const FAST_FRAME := 0.06 ## image rapide : davantage à la fois

const AVOID_PATH := "user://graphismes_evites_v2.cfg"
const OLD_AVOID_PATH := "user://graphismes_evites.cfg" ## 1.17 : mis de côté dès la première fermeture
const PENDING_PATH := "user://preparation_en_cours.json"
const CONFIRM := 2 ## fermetures sur le même matériau avant de le mettre de côté
const BIG := 40.0 ## m : objet trop grand pour être caché (ville, sol)

static var avoid := {} ## clé de matériau → nom lisible : matériaux qui ont fait planter ce téléphone
static var prepared := {} ## clés déjà préparées depuis le lancement du jeu

var total := 0
var done := 0
var one_by_one := false ## un seul nouveau matériau par image (PowerVR)


## Prépare tous les matériaux visibles sous `root`. À attendre (await) avant la première image.
func run(root: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_avoid()
	var items := _collect(root)
	total = items.size()
	var keys := [] # lus maintenant : chaque copie est libérée après avoir été montrée
	for c in items:
		keys.append_array(c.get_meta("keys", []))
	if total == 0 or DisplayServer.get_name() == "headless":
		for c in items:
			c.free()
		return
	# PowerVR : un seul nouveau matériau par image, pour savoir exactement lequel ferait planter
	one_by_one = "PowerVR" in RenderingServer.get_video_adapter_name()
	var max_batch := 1 if one_by_one else 12
	var t0 := Time.get_ticks_msec()
	var tree := get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var overlay := _overlay()
	var label: Label = overlay.get_meta("label")
	var stage := Node3D.new()
	stage.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(stage)
	stage.global_position = STAGE
	var cam := Camera3D.new()
	cam.far = 30.0
	stage.add_child(cam)
	var previous := root.get_viewport().get_camera_3d()
	cam.current = true
	var shown: Array = [] ## [copie, images restantes]
	var batch := mini(2, max_batch)
	var last := Time.get_ticks_usec()
	var slot := 0
	var logged := 0
	var first := true # première image : l'écran de chargement seul, pour qu'il s'affiche tout de suite
	while done < total or not shown.is_empty():
		var start := done
		for i in (0 if first else batch):
			if done >= total:
				break
			var copy: Node3D = items[done]
			done += 1
			# Grille de 5 x 3 devant la caméra, chaque copie réduite à ~1 m
			var col := slot % 5
			var row := (slot / 5) % 3
			slot += 1
			stage.add_child(copy)
			# Le centre de la copie (et non son origine, parfois loin du maillage) devant la caméra
			copy.position = Vector3((col - 2) * 1.3, (row - 1) * 1.3, -6.0) - copy.get_meta("center", Vector3.ZERO)
			shown.append([copy, SHOW_FRAMES])
		first = false
		if done > start:
			_write_pending(items.slice(start, done))
		label.text = "Préparation de Dakar... %d %%" % roundi(100.0 * done / total)
		await RenderingServer.frame_post_draw
		for s in shown.duplicate():
			s[1] -= 1
			if s[1] <= 0:
				s[0].queue_free()
				shown.erase(s)
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000000.0
		last = now
		if OS.is_debug_build():
			print("préparation : %d/%d, image de %.2f s" % [done, total, dt])
		batch = maxi(1, batch / 2) if dt > SLOW_FRAME else (mini(batch + 1, max_batch) if dt < FAST_FRAME else batch)
		if done != logged and (done - logged >= 10 or done == total):
			logged = done
			CrashReport.step("graphismes préparés %d/%d" % [done, total])
	if is_instance_valid(previous):
		previous.current = true
	stage.queue_free()
	DirAccess.remove_absolute(PENDING_PATH)
	for key in keys:
		prepared[key] = true
	_clear_suspects()
	tree.paused = was_paused
	print("Graphismes préparés : %d matériaux en %.1f s" % [total, (Time.get_ticks_msec() - t0) / 1000.0])
	# L'écran de chargement reste une image de plus (le temps que la vraie vue s'affiche)
	await RenderingServer.frame_post_draw
	overlay.queue_free()


## Une copie réduite par combinaison matériau / format de maillage encore jamais vue
func _collect(root: Node) -> Array:
	var seen := {}
	var out := []
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		# Les objets cachés (intérieurs...) aussi : sinon leur première apparition ferait un à-coup
		var g := n as GeometryInstance3D
		if hide_avoided(g):
			continue
		var fresh := []
		for key in node_keys(g):
			if not seen.has(key) and not prepared.has(key):
				seen[key] = true
				fresh.append(key)
		if fresh.is_empty():
			continue
		var copy: Node3D = null
		if g is MeshInstance3D:
			copy = _mesh_copy(g)
		elif g is MultiMeshInstance3D:
			copy = _multimesh_copy(g)
		else:
			copy = g.duplicate(0) as Node3D
			for c in copy.get_children():
				copy.remove_child(c)
				c.free()
			copy.set_script(null)
		copy.process_mode = Node.PROCESS_MODE_ALWAYS
		copy.set_meta("keys", fresh)
		copy.set_meta("label", _label(g))
		copy.set_meta("big", g.get_aabb().get_longest_axis_size() * g.global_basis.get_scale().abs().x > BIG)
		_fit(copy)
		out.append(copy)
	return out


func _mesh_copy(mi: MeshInstance3D) -> MeshInstance3D:
	var mesh := mi.mesh
	var c := MeshInstance3D.new()
	c.mesh = mesh
	for s in mesh.get_surface_count():
		c.set_surface_override_material(s, mi.get_active_material(s))
	c.material_overlay = mi.material_overlay
	c.cast_shadow = mi.cast_shadow
	c.transparency = mi.transparency
	return c


func _multimesh_copy(mmi: MultiMeshInstance3D) -> MultiMeshInstance3D:
	var mm := mmi.multimesh
	var copy := MultiMesh.new()
	copy.transform_format = mm.transform_format
	copy.use_colors = mm.use_colors
	copy.use_custom_data = mm.use_custom_data
	copy.mesh = mm.mesh
	copy.instance_count = 1
	copy.set_instance_transform(0, Transform3D.IDENTITY)
	var c := MultiMeshInstance3D.new()
	c.multimesh = copy
	c.material_override = mmi.material_override
	c.material_overlay = mmi.material_overlay
	c.cast_shadow = mmi.cast_shadow
	return c


## Clés des programmes que l'objet fait compiler (une par surface ; aucune s'il n'a rien à dessiner)
static func node_keys(g: GeometryInstance3D) -> Array:
	var keys := []
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				keys.append(_surface_key(mi.mesh, s, mi.get_active_material(s), mi.material_overlay, "mi"))
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			for s in mm.mesh.get_surface_count():
				var mat := g.material_override if g.material_override else mm.mesh.surface_get_material(s)
				keys.append(_surface_key(mm.mesh, s, mat, g.material_overlay, "mm%d%d%d" % [mm.transform_format, int(mm.use_colors), int(mm.use_custom_data)]))
	elif g is Label3D or g is SpriteBase3D or g is CPUParticles3D or g is GPUParticles3D:
		keys.append(_node_key(g))
	return keys


static func _surface_key(mesh: Mesh, s: int, mat: Material, overlay: Material, kind: String) -> String:
	# Format des sommets : seuls les attributs présents comptent (pas la compression ni les tailles)
	var fmt := 0
	if mesh is ArrayMesh:
		fmt = (mesh as ArrayMesh).surface_get_format(s) & ((1 << Mesh.ARRAY_MAX) - 1)
	return "%s:%s:%d:%s" % [kind, _mat_key(mat), fmt, _mat_key(overlay)]


## Ce qui change le programme compilé d'un matériau. Des milliers de matériaux standard ne diffèrent
## que par leurs couleurs : ils partagent le même programme et ne comptent qu'une fois.
static func _mat_key(mat: Material) -> String:
	if mat == null:
		return "-"
	if mat is ShaderMaterial:
		var sh := (mat as ShaderMaterial).shader
		# Chemin ou contenu du shader (pas son numéro d'instance, qui change à chaque lancement)
		return "sh%s" % ((sh.resource_path if sh.resource_path != "" else str(sh.code.hash())) if sh else "-")
	if mat is BaseMaterial3D:
		var m := mat as BaseMaterial3D
		var k := [m.transparency, m.shading_mode, m.cull_mode, m.depth_draw_mode, m.billboard_mode, m.texture_filter,
			int(m.vertex_color_use_as_albedo), int(m.no_depth_test), int(m.use_point_size), int(m.uv1_triplanar),
			int(m.albedo_texture != null), int(m.normal_enabled), int(m.emission_enabled), int(m.rim_enabled),
			int(m.clearcoat_enabled), int(m.ao_enabled), int(m.heightmap_enabled), int(m.refraction_enabled),
			int(m.detail_enabled), int(m.roughness_texture != null), int(m.metallic_texture != null),
			int(m.disable_receive_shadows), int(m.fixed_size), int(m.proximity_fade_enabled), m.distance_fade_mode,
			m.diffuse_mode, m.specular_mode, int(m.disable_fog), int(m.disable_ambient_light),
			int(m.grow), int(m.backlight_enabled), int(m.subsurf_scatter_enabled)]
		var s := "bm%s" % mat.get_class()
		for v in k:
			s += ",%d" % v
		return s + _mat_key(m.next_pass)
	return "%s%s" % [mat.get_class(), mat.resource_path]


static func _node_key(g: GeometryInstance3D) -> String:
	var key := "%s:%s" % [g.get_class(), _mat_key(g.material_override)]
	if g is Label3D:
		var l := g as Label3D
		key += ":%d:%d:%d:%d" % [l.billboard, int(l.no_depth_test), int(l.shaded), int(l.fixed_size)]
	elif g is SpriteBase3D:
		var sp := g as SpriteBase3D
		key += ":%d:%d:%d:%d" % [sp.billboard, sp.alpha_cut, int(sp.shaded), int(sp.no_depth_test)]
	return key


## Réduit la copie à environ un mètre (un immeuble entier tiendrait mal dans le champ)
static func _fit(n: Node3D) -> void:
	var box := AABB(Vector3.ZERO, Vector3.ONE)
	if n is VisualInstance3D:
		box = (n as VisualInstance3D).get_aabb()
	var k := clampf(1.0 / maxf(0.001, box.get_longest_axis_size()), 0.001, 100.0)
	n.scale = Vector3.ONE * k
	n.set_meta("center", box.get_center() * k)


# --- Matériaux qui ont fait planter ce téléphone ------------------------------------------

## Objet dont un matériau a fait planter ce téléphone : il n'est plus dessiné (aucun calque)
static func hide_avoided(g: GeometryInstance3D) -> bool:
	if avoid.is_empty() or not is_instance_valid(g):
		return false
	for key in node_keys(g):
		if avoid.has(key):
			g.layers = 0
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return true
	return false


## Objets créés plus tard (pluie, repères de mission...) : vérifiés une fois leur matériau posé
static func _on_node_added(n: Node) -> void:
	if n is GeometryInstance3D:
		hide_avoided.call_deferred(n)


## Lancement précédent fermé pendant la préparation : ses matériaux en cours deviennent suspects ;
## un suspect qui refait fermer le jeu est mis de côté. Une préparation réussie efface les suspects.
func _load_avoid() -> void:
	DirAccess.remove_absolute(OLD_AVOID_PATH) # 1.17 cachait parfois la ville après une seule fermeture
	var cfg := ConfigFile.new()
	cfg.load(AVOID_PATH)
	if FileAccess.file_exists(PENDING_PATH):
		var pending = JSON.parse_string(FileAccess.get_file_as_string(PENDING_PATH))
		DirAccess.remove_absolute(PENDING_PATH)
		if pending is Dictionary:
			for key in pending:
				var entry = pending[key]
				if not entry is Dictionary or entry.get("big", false):
					continue
				var n: int = cfg.get_value("suspects", str(key), 0) + 1
				cfg.set_value("suspects", str(key), n)
				if n >= CONFIRM:
					cfg.set_value("evites", str(key), str(entry.get("label", "?")))
			cfg.save(AVOID_PATH)
	avoid.clear()
	if cfg.has_section("evites"):
		for key in cfg.get_section_keys("evites"):
			avoid[key] = cfg.get_value("evites", key)
	if avoid.is_empty():
		return
	CrashReport.step("graphismes évités : %s" % ", ".join(PackedStringArray(avoid.values())))
	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


func _clear_suspects() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AVOID_PATH) == OK and cfg.has_section("suspects"):
		cfg.erase_section("suspects")
		cfg.save(AVOID_PATH)


## Matériaux montrés pour la première fois dans l'image qui va être dessinée
func _write_pending(copies: Array) -> void:
	var pending := {}
	var names := []
	for c in copies:
		for key in c.get_meta("keys", []):
			pending[key] = {"label": c.get_meta("label", "?"), "big": c.get_meta("big", false)}
		names.append(c.get_meta("label", "?"))
	var f := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(pending))
		f.close()
	if one_by_one: # le rapport de plantage dira exactement quel objet était en cours
		CrashReport.step("graphismes %d/%d : %s" % [done, total, ", ".join(PackedStringArray(names))])
	# Test : -- --warmup-crash=N (plantage simulé quand le N-ième matériau va être dessiné)
	for a in OS.get_cmdline_user_args():
		var n := a.trim_prefix("--warmup-crash=").to_int() if a.begins_with("--warmup-crash=") else 0
		if n > 0 and done >= n and done - copies.size() < n:
			print("Plantage simulé : ", names)
			OS.crash("test de préparation")


## Jeu mis en arrière-plan ou fermé pendant la préparation : ce n'est pas un plantage
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		DirAccess.remove_absolute(PENDING_PATH)


## Nom lisible : script le plus proche et type d'objet (ex. « gps MeshInstance3D »)
static func _label(g: Node) -> String:
	var o := g
	while o and o.get_script() == null:
		o = o.get_parent()
	var script_name: String = o.get_script().resource_path.get_file().get_basename() if o else "?"
	return "%s %s" % [script_name, g.get_class()]


func _overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.text = "Préparation de Dakar..."
	bg.add_child(label)
	layer.set_meta("label", label)
	add_child(layer)
	return layer
