extends RefCounted
## Personnages stylisés façon film d'animation : grosse tête, grands yeux, sourire, tenues de Dakar.
## Chaque modèle est fusionné en 5 maillages (corps, 2 bras, 2 jambes) et mis en cache :
## les passants identiques partagent les mêmes maillages, ce qui reste léger sur mobile.
## Le personnage regarde vers -Z ; les pieds sont à y = 0.

static var _cache := {}
static var _mat: StandardMaterial3D
static var _unit_sphere: SphereMesh
static var _unit_box: BoxMesh

const SKINS := [Color("8d5534"), Color("6e3f26"), Color("a0663f"), Color("5a3320"), Color("7b4a2d")]
const TOPS := [Color("ebe5d6"), Color("1d4ed8"), Color("e11d48"), Color("f8fafc"), Color("10b981"), Color("f59e0b"), Color("7c3aed"), Color("0ea5e9")]
const STRIPES := [Color("1e1e1e"), Color("f8fafc"), Color("0f2a4a"), Color.TRANSPARENT, Color.TRANSPARENT]
const BOTTOMS := [Color("2b2f36"), Color("34445e"), Color("d8cbb0"), Color("1e1e1e"), Color("5b4636")]
const BOUBOUS := [Color("1d4ed8"), Color("f8fafc"), Color("6d28d9"), Color("0f766e"), Color("b45309"), Color("9f1239"), Color("e9d8a6")]
const WAX := [Color("e85d04"), Color("2a9d8f"), Color("d00000"), Color("ffb703"), Color("8338ec"), Color("06d6a0"), Color("1d4ed8")]
const WAX_DOTS := [Color("ffd166"), Color("111111"), Color("f8fafc"), Color("3a86ff"), Color("e63946")]


## Le héros : polo crème zippé à rayures noires, chaîne argentée, coupe dégradée.
static func hero_spec() -> Dictionary:
	return {"skin": Color("8d5534"), "outfit": "polo", "top": Color("ebe5d6"), "stripe": Color("1e1e1e"),
		"bottom": Color("2b2f36"), "hair": "fade", "accent": Color("c9ccd1"), "chain": true, "shoes": Color("f2f2f2")}


## Une tenue typique au hasard pour un passant.
static func random_spec(rng: RandomNumberGenerator) -> Dictionary:
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var female := rng.randf() < 0.5
	if female:
		var outfit := "robe" if rng.randf() < 0.7 else "tshirt"
		return {"skin": skin, "outfit": outfit, "top": WAX[rng.randi() % WAX.size()], "stripe": Color.TRANSPARENT,
			"bottom": WAX[rng.randi() % WAX.size()], "hair": "wrap" if rng.randf() < 0.65 else "bun",
			"accent": WAX_DOTS[rng.randi() % WAX_DOTS.size()], "chain": false, "shoes": Color("5b3a24")}
	var r := rng.randf()
	if r < 0.35:
		return {"skin": skin, "outfit": "boubou", "top": BOUBOUS[rng.randi() % BOUBOUS.size()], "stripe": Color.TRANSPARENT,
			"bottom": Color("e9e4d8"), "hair": "kufi" if rng.randf() < 0.7 else "fade", "accent": Color("d4af37"),
			"chain": false, "shoes": Color("5b3a24")}
	if r < 0.5:
		# Maillot des Lions de la Teranga
		return {"skin": skin, "outfit": "maillot", "top": Color("f8fafc"), "stripe": Color("00853f"),
			"bottom": Color("00853f"), "hair": "fade", "accent": Color("fdef42"), "chain": false, "shoes": Color("f2f2f2")}
	return {"skin": skin, "outfit": "polo" if rng.randf() < 0.6 else "tshirt", "top": TOPS[rng.randi() % TOPS.size()],
		"stripe": STRIPES[rng.randi() % STRIPES.size()], "bottom": BOTTOMS[rng.randi() % BOTTOMS.size()],
		"hair": "fade", "accent": Color("c9ccd1"), "chain": rng.randf() < 0.3, "shoes": Color("f2f2f2") if rng.randf() < 0.7 else Color("1e1e1e")}


static func build(parent: Node, spec: Dictionary) -> Node3D:
	var key := var_to_str(spec)
	if not _cache.has(key):
		_cache[key] = _make(spec)
	var parts: Dictionary = _cache[key]
	var root := Node3D.new()
	parent.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = parts["body"]
	body.material_override = _material()
	root.add_child(body)
	var legs: Array = []
	var arms: Array = []
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(0.1 * side, 0.8, 0)
		root.add_child(hip)
		var leg := MeshInstance3D.new()
		leg.mesh = parts["leg"]
		leg.material_override = _material()
		hip.add_child(leg)
		legs.append(hip)
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.27 * side, 1.32, 0)
		root.add_child(shoulder)
		var arm := MeshInstance3D.new()
		arm.mesh = parts["arm"]
		arm.material_override = _material()
		shoulder.add_child(arm)
		arms.append(shoulder)
	root.set_meta("legs", legs)
	root.set_meta("arms", arms)
	return root


static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.65
		_mat.metallic_specular = 0.35
	return _mat


# --- Assemblage ------------------------------------------------------------------

class Merger:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(mesh: Mesh, xf: Transform3D, col: Color) -> void:
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(col)
		for i in ind:
			idx.append(base + i)

	func to_mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _xf(pos: Vector3, scale: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos)


static func _sph(m: Merger, r: float, pos: Vector3, col: Color, scale := Vector3.ONE, rot := Vector3.ZERO) -> void:
	if _unit_sphere == null:
		_unit_sphere = SphereMesh.new()
		_unit_sphere.radius = 1.0
		_unit_sphere.height = 2.0
		_unit_sphere.radial_segments = 14
		_unit_sphere.rings = 8
	m.add(_unit_sphere, _xf(pos, scale * r, rot), col)


static func _box(m: Merger, size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	if _unit_box == null:
		_unit_box = BoxMesh.new()
	m.add(_unit_box, _xf(pos, size, rot), col)


static func _cap(m: Merger, r: float, h: float, pos: Vector3, col: Color, scale := Vector3.ONE, rot := Vector3.ZERO) -> void:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	m.add(c, _xf(pos, scale, rot), col)


static func _cyl(m: Merger, top: float, bottom: float, h: float, pos: Vector3, col: Color, scale := Vector3.ONE) -> void:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 14
	c.rings = 1
	m.add(c, _xf(pos, scale), col)


static func _torus(m: Merger, inner: float, outer: float, pos: Vector3, col: Color, rot: Vector3) -> void:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 16
	t.ring_segments = 6
	m.add(t, _xf(pos, Vector3.ONE, rot), col)


static func _make(spec: Dictionary) -> Dictionary:
	var skin: Color = spec["skin"]
	var top: Color = spec["top"]
	var stripe: Color = spec["stripe"]
	var bottom: Color = spec["bottom"]
	var accent: Color = spec["accent"]
	var outfit: String = spec["outfit"]
	var body := Merger.new()
	_head(body, spec)
	_cyl(body, 0.055, 0.06, 0.14, Vector3(0, 1.39, 0), skin) # cou
	match outfit:
		"boubou":
			_cyl(body, 0.26, 0.46, 1.05, Vector3(0, 0.88, 0), top)
			_cap(body, 0.24, 0.5, Vector3(0, 1.28, 0), top, Vector3(1.15, 0.7, 0.8))
			_box(body, Vector3(0.14, 0.24, 0.01), Vector3(0, 1.18, -0.2), accent) # broderie
			_box(body, Vector3(0.05, 0.1, 0.012), Vector3(0, 1.31, -0.19), skin.darkened(0.25))
		"robe":
			_cyl(body, 0.2, 0.42, 1.05, Vector3(0, 0.78, 0), top)
			_cap(body, 0.19, 0.5, Vector3(0, 1.12, 0), top, Vector3(1.05, 1.0, 0.72))
			_box(body, Vector3(0.36, 0.05, 0.3), Vector3(0, 0.96, 0), accent) # ceinture
			# Motifs du wax
			var rng := RandomNumberGenerator.new()
			rng.seed = int(top.to_rgba32()) ^ int(accent.to_rgba32())
			for k in 16:
				var a := rng.randf() * TAU
				var y := rng.randf_range(0.35, 1.2)
				var rad := lerpf(0.42, 0.2, (y - 0.3) / 0.95) * (0.74 if y > 0.96 else 1.0)
				_sph(body, 0.035, Vector3(cos(a) * rad, y, sin(a) * rad), accent)
		_:
			_cap(body, 0.21, 0.62, Vector3(0, 1.08, 0), top, Vector3(1.08, 1.0, 0.72))
			_cap(body, 0.17, 0.34, Vector3(0, 0.84, 0), bottom, Vector3(1.05, 1.0, 0.8))
			if outfit == "polo":
				for side in [-1, 1]:
					_box(body, Vector3(0.1, 0.035, 0.06), Vector3(0.055 * side, 1.37, -0.1), top.lightened(0.06), Vector3(0.5, 0, 0.55 * side))
				_box(body, Vector3(0.2, 0.05, 0.05), Vector3(0, 1.37, 0.07), top.lightened(0.06))
				_box(body, Vector3(0.014, 0.2, 0.012), Vector3(0, 1.26, -0.157), Color("2a2a2a")) # fermeture éclair
			else:
				_torus(body, 0.06, 0.075, Vector3(0, 1.36, -0.01), top.darkened(0.15), Vector3.ZERO) # col rond
			if stripe.a > 0.0:
				# Rayures verticales devant et derrière
				for x in [-0.15, -0.115, 0.115, 0.15]:
					var zf := 0.72 * sqrt(maxf(0.0, 0.21 * 0.21 - pow(x / 1.08, 2.0)))
					_box(body, Vector3(0.018, 0.56, 0.012), Vector3(x, 1.08, -zf), stripe)
					_box(body, Vector3(0.018, 0.56, 0.012), Vector3(x, 1.08, zf), stripe)
			if outfit == "maillot":
				# Petit drapeau du Sénégal sur la poitrine
				for k in 3:
					_box(body, Vector3(0.025, 0.05, 0.01), Vector3(-0.1 + k * 0.025, 1.2, -0.155), [Color("00853f"), Color("fdef42"), Color("e31b23")][k])
			if spec.get("chain", false):
				_torus(body, 0.072, 0.08, Vector3(0, 1.33, -0.04), Color("c9ccd1"), Vector3(0.55, 0, 0))

	# Bras (repère de l'épaule, pendant vers le bas)
	var arm := Merger.new()
	if outfit == "boubou":
		_cap(arm, 0.11, 0.55, Vector3(0, -0.24, 0), top)
	else:
		_cap(arm, 0.075, 0.28, Vector3(0, -0.1, 0), top)
		_cap(arm, 0.052, 0.36, Vector3(0, -0.36, 0), skin)
	_sph(arm, 0.058, Vector3(0, -0.56, 0), skin, Vector3(0.9, 1.1, 0.8))

	# Jambes (repère de la hanche)
	var leg := Merger.new()
	var legs_col := bottom if outfit in ["polo", "tshirt", "maillot"] else (skin if outfit == "robe" else bottom)
	_cap(leg, 0.085, 0.74, Vector3(0, -0.37, 0), legs_col)
	var shoes: Color = spec.get("shoes", Color("1e1e1e"))
	_box(leg, Vector3(0.12, 0.08, 0.25), Vector3(0, -0.76, -0.04), shoes)
	_box(leg, Vector3(0.125, 0.025, 0.255), Vector3(0, -0.79, -0.04), shoes.darkened(0.4))
	return {"body": body.to_mesh(), "arm": arm.to_mesh(), "leg": leg.to_mesh()}


## Tête façon film d'animation : grands yeux, sourcils marqués, sourire.
static func _head(m: Merger, spec: Dictionary) -> void:
	var skin: Color = spec["skin"]
	var H := Vector3(0, 1.57, 0)
	_sph(m, 0.165, H, skin, Vector3(1.0, 1.08, 1.0))
	_sph(m, 0.13, H + Vector3(0, -0.07, -0.03), skin, Vector3(1.0, 0.8, 1.0)) # joues et menton
	for side in [-1, 1]:
		var e := H + Vector3(0.062 * side, 0.015, -0.132)
		_sph(m, 0.04, e, Color("f8f5f0"), Vector3(1.0, 1.12, 0.7)) # blanc de l'œil
		_sph(m, 0.027, e + Vector3(0, -0.002, -0.02), Color("5a2a17")) # iris
		_sph(m, 0.015, e + Vector3(0, -0.002, -0.036), Color("0d0806")) # pupille
		_sph(m, 0.007, e + Vector3(0.008, 0.012, -0.045), Color.WHITE) # reflet
		_box(m, Vector3(0.075, 0.018, 0.022), H + Vector3(0.064 * side, 0.068, -0.153), Color("1c1410"), Vector3(0, 0, -0.18 * side)) # sourcil
		_sph(m, 0.042, H + Vector3(0.163 * side, -0.005, 0.01), skin, Vector3(0.45, 1.0, 0.75)) # oreille
		_box(m, Vector3(0.022, 0.011, 0.014), H + Vector3(0.036 * side, -0.083, -0.148), Color("5c2a22"), Vector3(0, 0, 0.5 * side)) # coin du sourire
	_sph(m, 0.032, H + Vector3(0, -0.03, -0.165), skin.darkened(0.06), Vector3(1.15, 0.9, 0.9)) # nez
	_box(m, Vector3(0.052, 0.012, 0.016), H + Vector3(0, -0.09, -0.15), Color("5c2a22")) # bouche
	_sph(m, 0.026, H + Vector3(0, -0.105, -0.142), skin.darkened(0.12), Vector3(1.4, 0.6, 0.6)) # lèvre inférieure
	var accent: Color = spec["accent"]
	match spec["hair"]:
		"kufi":
			_sph(m, 0.168, H + Vector3(0, 0.1, 0.012), Color("161210"), Vector3(1.0, 0.48, 1.02))
			_cyl(m, 0.155, 0.165, 0.11, H + Vector3(0, 0.15, 0.01), spec["bottom"])
		"wrap":
			_sph(m, 0.2, H + Vector3(0, 0.12, 0.03), spec["top"], Vector3(1.1, 0.85, 1.1)) # moussor
			_sph(m, 0.075, H + Vector3(0, 0.27, -0.03), spec["top"].darkened(0.1))
			_sph(m, 0.055, H + Vector3(0.07, 0.24, -0.08), accent)
		"bun":
			_sph(m, 0.17, H + Vector3(0, 0.1, 0.012), Color("161210"), Vector3(1.0, 0.52, 1.02))
			_sph(m, 0.08, H + Vector3(0, 0.15, 0.14), Color("161210"))
		_:
			# Coupe courte dégradée, cheveux crépus sur le dessus
			_sph(m, 0.172, H + Vector3(0, 0.105, 0.012), Color("161210"), Vector3(1.0, 0.5, 1.02))
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for k in 14:
				var a := rng.randf() * TAU
				var rr := rng.randf_range(0.0, 0.12)
				_sph(m, 0.045, H + Vector3(cos(a) * rr, 0.165 - rr * 0.3, sin(a) * rr + 0.01), Color("1a1512"))
			_sph(m, 0.168, H + Vector3(0, 0.05, 0.06), Color("2a221d"), Vector3(1.02, 0.6, 0.9)) # côtés et nuque dégradés
