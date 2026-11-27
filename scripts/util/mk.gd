extends RefCounted
## Petites fonctions pour construire le monde avec des formes et matériaux PBR réalistes.

static var _mats := {}
static var _window_tex: ImageTexture
static var _asphalt_pbr_mat: StandardMaterial3D = null


## Matériau PBR Asphalte haute fidélité (Albedo, NormalGL, Roughness CC0) avec projection triplanaire
static func asphalt_pbr() -> StandardMaterial3D:
	if _asphalt_pbr_mat != null:
		return _asphalt_pbr_mat
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists("res://textures/pbr/asphalt_albedo.jpg"):
		m.albedo_texture = load("res://textures/pbr/asphalt_albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load("res://textures/pbr/asphalt_normal.jpg")
		m.roughness_texture = load("res://textures/pbr/asphalt_roughness.jpg")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.35, 0.35, 0.35)
	else:
		m.albedo_color = Color(0.2, 0.2, 0.22)
		m.roughness = 0.88
	_asphalt_pbr_mat = m
	return m


## Matériau PBR Béton haute fidélité (bordures, ralentisseurs, dalles)
static func concrete_pbr(tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "concrete_pbr|%s" % tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if ResourceLoader.exists("res://textures/pbr/concrete_albedo.jpg"):
		m.albedo_color = tint
		m.albedo_texture = load("res://textures/pbr/concrete_albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = load("res://textures/pbr/concrete_normal.jpg")
		m.roughness_texture = load("res://textures/pbr/concrete_roughness.jpg")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	else:
		m.albedo_color = Color(0.72, 0.7, 0.68) * tint
		m.roughness = 0.75
	_mats[key] = m
	return m


## Peinture de carrosserie : vernis automobile brillant (clearcoat), reflets du ciel et du soleil
static func paint(color: Color, glass := false) -> StandardMaterial3D:
	var key := "paint|%s|%s" % [color.to_html(), glass]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if glass:
		m.roughness = 0.04
		m.metallic = 0.05
		m.metallic_specular = 0.95
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.roughness = 0.16
		m.metallic = 0.42
		m.metallic_specular = 0.75
		m.clearcoat_enabled = true
		m.clearcoat = 0.85
		m.clearcoat_roughness = 0.12
	_mats[key] = m
	return m


## Matériau PBR physique avec détection intelligente (métal, tissu, verre, maçonnerie)
static func mat(color: Color, emission := 0.0, unshaded := false, roughness := -1.0, metallic := -1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [color.to_html(), emission, unshaded, roughness, metallic]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission

	if roughness >= 0.0:
		m.roughness = roughness
		m.metallic = maxf(metallic, 0.0)
		m.metallic_specular = 0.5
	else:
		# Détection automatique réaliste selon la couleur et l'opacité
		if color.a < 0.95:
			# Verre / surface transparente
			m.roughness = 0.06
			m.metallic_specular = 0.95
		elif _is_metallic(color):
			# Métaux (acier, fer, aluminium, chrome, or)
			m.metallic = 0.75
			m.roughness = 0.26
			m.metallic_specular = 0.8
		elif _is_fabric(color):
			# Tissus, bâches, sièges, canopées (effet velouté rim light)
			m.roughness = 0.78
			m.metallic_specular = 0.3
			m.rim_enabled = true
			m.rim = 0.32
			m.rim_tint = 0.45
		else:
			# Maçonnerie, béton, enduit, plastique, bois mat
			m.roughness = 0.65
			m.metallic = 0.02
			m.metallic_specular = 0.38

	_mats[key] = m
	return m


static func _is_metallic(c: Color) -> bool:
	var max_diff: float = maxf(absf(c.r - c.g), maxf(absf(c.g - c.b), absf(c.r - c.b)))
	# Teintes grises/acier (différence minime entre canaux)
	if max_diff < 0.08 and c.r > 0.2 and c.r < 0.88:
		return true
	# Or / laiton (jaune doré soutenu)
	if c.r > 0.7 and c.g > 0.5 and c.b < 0.35:
		return true
	return false


static func _is_fabric(c: Color) -> bool:
	var s: float = c.s
	var v: float = c.v
	# Couleurs vives saturées des boubous, parasols et étals de marché
	return s > 0.45 and v > 0.4 and c.a >= 0.95


## Matériaux spécifiques pour enrichir les scènes
static func metal(color := Color("c9ccd1"), roughness := 0.22, metallic := 0.85) -> StandardMaterial3D:
	return mat(color, 0.0, false, roughness, metallic)


static func glass(color := Color(0.7, 0.85, 0.95, 0.35), roughness := 0.04) -> StandardMaterial3D:
	return mat(color, 0.0, false, roughness, 0.05)


static func wood(color := Color("6b4f3a"), roughness := 0.58) -> StandardMaterial3D:
	return mat(color, 0.0, false, roughness, 0.0)


static func fabric(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var m := mat(color, 0.0, false, roughness, 0.0)
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.5
	return m


static func grass(color := Color("237a2e"), roughness := 0.85) -> StandardMaterial3D:
	var m := mat(color, 0.0, false, roughness, 0.0)
	m.metallic_specular = 0.2
	m.rim_enabled = true
	m.rim = 0.22
	m.rim_tint = 0.35
	return m


## Matériau photo (bois, tissu…) teinté, projeté en triplanaire dans le monde
static func textured(path: String, color: Color, scale := 1.0, roughness := 0.75) -> StandardMaterial3D:
	var key := "tex|%s|%s|%s" % [path, color.to_html(), scale]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = load(path)
	m.roughness = roughness
	m.metallic_specular = 0.35
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / scale
	_mats[key] = m
	return m


## Matériau de façade haute définition : fenêtres architecturales avec appui, montants et reflets
static func facade_mat(color: Color) -> StandardMaterial3D:
	var key := "facade|" + color.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _windows()
	m.roughness = 0.68
	m.metallic_specular = 0.35
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 3.2
	_mats[key] = m
	return m


static func _windows() -> ImageTexture:
	if _window_tex:
		return _window_tex
	# Texture architecturale 128x128 : enduit clair, cadre sombre, double vitrage avec ciel et stores
	var img := Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	# 1. Mur en enduit calcaire avec micro-variation
	img.fill(Color(0.96, 0.95, 0.93))
	for y in 128:
		for x in 128:
			var n: float = sin(float(x) * 0.4) * cos(float(y) * 0.4) * 0.02
			var base_c := Color(0.96 + n, 0.95 + n, 0.93 + n)
			img.set_pixel(x, y, base_c)

	# 2. Encadrement architectural et ombre portée de linteau
	img.fill_rect(Rect2i(28, 16, 72, 88), Color(0.22, 0.24, 0.28))
	img.fill_rect(Rect2i(30, 18, 68, 84), Color(0.12, 0.14, 0.18))

	# 3. Vitres avec dégradé de ciel et réflexion réaliste
	for vy in range(22, 96):
		var t: float = float(vy - 22) / 74.0
		var glass_c := Color(0.24, 0.40, 0.55).lerp(Color(0.14, 0.22, 0.32), t)
		for vx in range(34, 94):
			# Séparation centrale (meneau)
			if vx == 63 or vx == 64:
				img.set_pixel(vx, vy, Color(0.28, 0.30, 0.34))
			# Traverse horizontale à mi-hauteur
			elif vy == 58:
				img.set_pixel(vx, vy, Color(0.28, 0.30, 0.34))
			else:
				# Stores vénitiens subtils derrière le vitrage
				var blind: float = 0.04 if (vy % 6 < 2) else 0.0
				img.set_pixel(vx, vy, glass_c + Color(blind, blind, blind, 0.0))

	# 4. Appui de fenêtre (rebord saillant en béton blanc)
	img.fill_rect(Rect2i(24, 102, 80, 8), Color(0.88, 0.89, 0.91))
	# Ombre portée sous l'appui
	img.fill_rect(Rect2i(26, 110, 76, 5), Color(0.55, 0.54, 0.52))

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