extends RefCounted
## Petites fonctions pour construire le monde avec des formes simples (aucun asset requis).

static var _mats := {}
static var _window_tex: ImageTexture


## Peinture de carrosserie : plus lisse, avec des reflets du ciel (profils Moyen et Élevé)
static func paint(color: Color, glass := false) -> StandardMaterial3D:
	var key := "paint|%s|%s" % [color.to_html(), glass]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.08 if glass else 0.3
	m.metallic = 0.0 if glass else 0.35
	m.metallic_specular = 0.9 if glass else 0.6
	_mats[key] = m
	return m


static func mat(color: Color, emission := 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), emission, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic_specular = 0.2
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


## Matériau photo (bois, tissu…) teinté, projeté en triplanaire dans le monde (pas d'UV à faire)
static func textured(path: String, color: Color, scale := 1.0, roughness := 0.85) -> StandardMaterial3D:
	var key := "tex|%s|%s|%s" % [path, color.to_html(), scale]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = load(path)
	m.roughness = roughness
	m.metallic_specular = 0.25
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / scale
	_mats[key] = m
	return m


## Matériau de façade : fenêtres projetées en triplanaire (un étage = 3,2 m).
static func facade_mat(color: Color) -> StandardMaterial3D:
	var key := "facade|" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _windows()
	m.roughness = 0.95
	m.metallic_specular = 0.2
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 3.2
	_mats[key] = m
	return m


static func _windows() -> ImageTexture:
	if _window_tex:
		return _window_tex
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	img.fill_rect(Rect2i(20, 14, 24, 30), Color(0.25, 0.3, 0.36))
	img.fill_rect(Rect2i(18, 44, 28, 3), Color(0.8, 0.8, 0.8))
	img.generate_mipmaps()
	_window_tex = ImageTexture.create_from_image(img)
	return _window_tex


static func box(parent: Node, size: Vector3, pos: Vector3, color: Color, collide := false, material: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = material if material else mat(color)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		_add_body(mi, shape)
	return mi


static func cyl(parent: Node, top_r: float, bottom_r: float, height: float, pos: Vector3, color: Color, collide := false, segments := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = segments
	mesh.rings = 1
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	parent.add_child(mi)
	if collide:
		var shape: Shape3D
		if is_equal_approx(top_r, bottom_r):
			var c := CylinderShape3D.new()
			c.radius = top_r
			c.height = height
			shape = c
		else:
			shape = mesh.create_convex_shape()
		_add_body(mi, shape)
	return mi


static func sphere(parent: Node, radius: float, pos: Vector3, color: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


## Taille des textes flottants (police, à 1 cm par point) : noms des personnes, panneaux des lieux
const NAME_SIZE := 22
const SIGN_SIZE := 30


static func label(parent: Node, text: String, pos: Vector3, font_size := 48, color := Color.WHITE, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.85)
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Collé à la caméra, un texte flottant cacherait l'écran : il s'efface de près
		l.visibility_range_begin = 3.0
		l.visibility_range_begin_margin = 0.5
	l.position = pos
	far_label(l)
	parent.add_child(l)
	return l


## Les textes flottants ne sont plus dessinés au-delà de la distance où on peut les lire
static func far_label(l: Label3D) -> void:
	if l.visibility_range_end <= 0.0:
		l.visibility_range_end = clampf(l.font_size * 1.6, 40.0, 320.0)
		l.visibility_range_end_margin = 8.0


static func _add_body(mi: Node3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)


## Un personnage (voir character_builder.gd) : boubou + kufi, ou robe en wax + moussor. Regarde vers -Z.
static func person(parent: Node, cloth: Color, skin: Color, accent: Color, female := false) -> Node3D:
	var CB = load("res://scripts/util/character_builder.gd")
	var spec := {"skin": skin, "outfit": "robe" if female else "boubou", "top": cloth, "stripe": Color.TRANSPARENT,
		"bottom": accent if not female else cloth, "hair": "wrap" if female else "kufi", "accent": accent,
		"chain": false, "shoes": Color("5b3a24")}
	return CB.build(parent, spec)


static func animate_walk(person_root: Node3D, t: float, amount: float) -> void:
	if person_root.has_method("animate"):
		person_root.animate(t, amount)
		return
	var legs: Array = person_root.get_meta("legs", [])
	if legs.size() < 2:
		return
	var a := sin(t) * amount
	legs[0].rotation.x = a
	legs[1].rotation.x = -a
	var arms: Array = person_root.get_meta("arms", [])
	if arms.size() == 2:
		arms[0].rotation.x = -a * 0.8
		arms[1].rotation.x = a * 0.8