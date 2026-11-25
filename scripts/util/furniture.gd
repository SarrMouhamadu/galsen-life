extends RefCounted
## Meubles réalistes (modèles Poly Haven, licence CC0 : world/furniture/<id>/) pour les intérieurs.
## place() charge le modèle (une fois par partie), le pose sur le sol à la bonne échelle et lui donne
## une collision en boîte (on ne traverse plus les tables et les canapés).

const DIR := "res://world/furniture/"
## id → échelle (les modèles sont en mètres, sauf l'étagère modélisée en décimètres ; les tables trop hautes
## sont ramenées à 75 cm)
const SCALE := {"steel_frame_shelves_01": 0.1, "painted_wooden_table": 0.8, "round_wooden_table_01": 0.75}

static var _scenes := {}
static var _sizes := {} ## id → AABB du modèle à l'échelle 1


static func _scene(id: String) -> PackedScene:
	if not _scenes.has(id):
		# « goods/<id> » : marchandises du marché (world/goods/, Poly Haven CC0 aussi)
		if id.begins_with("goods/"):
			var g := id.trim_prefix("goods/")
			_scenes[id] = load("res://world/goods/%s/%s_1k.gltf" % [g, g])
		elif id.begins_with("shop/"):
			# « shop/<id> » : rayons de supermarché (world/shop/, tools/extract_shop.py)
			_scenes[id] = load("res://world/shop/%s.glb" % id.trim_prefix("shop/"))
		else:
			_scenes[id] = load("%s%s/%s_1k.gltf" % [DIR, id, id])
	return _scenes[id]


## Boîte englobante du modèle (repère du modèle, échelle 1)
static func size_of(id: String) -> AABB:
	if not _sizes.has(id):
		var inst := _scene(id).instantiate()
		var ab := AABB()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = _local_xf(mi, inst) * mi.get_aabb()
			ab = b if first else ab.merge(b)
			first = false
		inst.free()
		_sizes[id] = ab
	return _sizes[id]


## Transformation d'un maillage dans le repère racine du modèle instancié
static func _local_xf(mi: Node, inst: Node) -> Transform3D:
	var t := Transform3D()
	var n: Node = mi
	while n != null and n != inst.get_parent():
		if n is Node3D:
			t = n.transform * t
		n = n.get_parent()
	return t


## Tas de fruits ou de légumes : count exemplaires du modèle en couches qui se resserrent (un petit dôme),
## dessinés en un seul MultiMesh par maillage (un appel de dessin au lieu de dizaines). center = bas du tas.
## lay : couche les modèles debout (patates douces, avocats) sur le côté.
static func pile(parent: Node3D, id: String, center: Vector3, area: Vector2, count: int, layers := 2, scale := 1.0, rseed := 0, lay := false) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rseed
	var ab := size_of(id)
	var lay_b := Basis(Vector3.RIGHT, PI / 2.0) if lay else Basis()
	var lift: float = (ab.size.z / 2.0 if lay else -ab.position.y) * scale
	var step: float = (ab.size.z if lay else ab.size.y) * scale * 0.7
	var xforms: Array[Transform3D] = []
	var left := count
	for l in layers:
		var shrink: float = 1.0 - float(l) / float(layers + 1)
		var n: int = left if l == layers - 1 else int(ceil(float(count) * shrink / float(layers) * 1.3))
		n = mini(n, left)
		left -= n
		# Grille secouée : les fruits se touchent sans trop se traverser
		var cols: int = maxi(1, int(round(sqrt(float(n) * area.x / maxf(area.y, 0.01)))))
		var rows: int = maxi(1, int(ceil(float(n) / float(cols))))
		for k in n:
			var cx: float = (float(k % cols) + 0.5) / float(cols) - 0.5
			var cz: float = (float(k / cols) + 0.5) / float(rows) - 0.5
			var p := Vector3((cx + rng.randf_range(-0.12, 0.12) / cols) * area.x * shrink, lift + l * step, (cz + rng.randf_range(-0.12, 0.12) / rows) * area.y * shrink)
			var bs := Basis(Vector3.UP, rng.randf_range(-PI, PI)) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)) * lay_b
			xforms.append(Transform3D(bs.scaled(Vector3.ONE * scale), center + p))
	var holder := Node3D.new()
	parent.add_child(holder)
	var inst := _scene(id).instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var t := _local_xf(mi, inst)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			mm.set_instance_transform(i, xforms[i] * t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.get_surface_override_material_count() > 0 and mi.get_surface_override_material(0) != null:
			mmi.material_override = mi.get_surface_override_material(0)
		holder.add_child(mmi)
	inst.free()
	return holder


## Pose un meuble : pos = point au sol (centre), yaw = rotation (le devant du modèle regarde +Z à yaw 0).
## collide : boîte de collision sur la couche 1 (murs et décor).
static func place(parent: Node3D, id: String, pos: Vector3, yaw := 0.0, collide := true, scale := -1.0) -> Node3D:
	var s: float = scale if scale > 0.0 else float(SCALE.get(id, 1.0))
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	holder.rotation.y = yaw
	var inst := _scene(id).instantiate()
	inst.scale = Vector3.ONE * s
	holder.add_child(inst)
	if collide:
		var ab := size_of(id)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = ab.size * s
		cs.shape = box
		cs.position = (ab.position + ab.size / 2.0) * s
		body.add_child(cs)
		holder.add_child(body)
	return holder


## Téléviseur à écran plat (aucun modèle libre réaliste n'existe) : cadre noir fin, écran allumé avec une image
static func flat_tv(parent: Node3D, pos: Vector3, yaw: float, width: float) -> Node3D:
	var h := Node3D.new()
	parent.add_child(h)
	h.position = pos
	h.rotation.y = yaw
	var hgt := width * 0.5625
	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, hgt, 0.05)
	frame.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("0d0d0f")
	fm.roughness = 0.25
	fm.metallic = 0.3
	frame.material_override = fm
	frame.position.y = hgt / 2.0
	h.add_child(frame)
	var screen := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(width - 0.04, hgt - 0.04)
	screen.mesh = qm
	screen.position = Vector3(0, hgt / 2.0, 0.026)
	var sm := StandardMaterial3D.new()
	sm.albedo_texture = _screen_texture()
	sm.emission_enabled = true
	sm.emission_texture = sm.albedo_texture
	sm.emission_energy_multiplier = 0.9
	sm.roughness = 0.1
	screen.material_override = sm
	h.add_child(screen)
	# Pied central
	var foot := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(width * 0.3, 0.02, 0.22)
	foot.mesh = fb
	foot.material_override = fm
	foot.position = Vector3(0, -0.04, 0)
	h.add_child(foot)
	var neck := MeshInstance3D.new()
	var nb := BoxMesh.new()
	nb.size = Vector3(0.06, 0.08, 0.04)
	neck.mesh = nb
	neck.material_override = fm
	neck.position = Vector3(0, -0.01, -0.01)
	h.add_child(neck)
	return h


static var _screen_tex: Texture2D
static var _paint_tex: Texture2D


## Cadre accroché au mur (devant vers +Z à yaw 0) avec une peinture : baobab au coucher du soleil
static func picture(parent: Node3D, pos: Vector3, yaw: float, scale := 1.0) -> Node3D:
	var h := place(parent, "hanging_picture_frame_01", pos, yaw, false, scale)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.74) * scale
	q.mesh = qm
	q.position = Vector3(0, 0, 0.018 * scale)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _painting()
	m.roughness = 0.8
	q.material_override = m
	h.add_child(q)
	return h


static func _painting() -> Texture2D:
	if _paint_tex != null:
		return _paint_tex
	var w := 50
	var hh := 74
	var img := Image.create(w, hh, false, Image.FORMAT_RGB8)
	for y in hh:
		for x in w:
			var t := float(y) / hh
			var c := Color("f9c74f").lerp(Color("f3722c"), t * 1.6) if y < 46 else Color("bc6c25").darkened(float(y - 46) / 60.0)
			if y < 46 and Vector2(x - 34, y - 30).length() < 6.0:
				c = Color("fff3b0")
			img.set_pixel(x, y, c)
	# Baobab : tronc épais et branches
	for y in range(22, 50):
		var half := 3 + (y - 22) / 6
		for x in range(16 - half, 16 + half):
			img.set_pixel(x, y, Color("3d2b1f"))
	for b in [[-1, 0], [1, 0], [-1, 1], [1, 1]]:
		for k in 9:
			var px: int = 16 + b[0] * (2 + k)
			var py: int = 22 - k / 2 - b[1] * 3
			for d in 2:
				img.set_pixel(clampi(px, 0, w - 1), clampi(py + d, 0, hh - 1), Color("3d2b1f"))
	for p in [[6, 15], [26, 15], [9, 12], [23, 11], [16, 13]]:
		for y in range(p[1] - 3, p[1] + 3):
			for x in range(p[0] - 4, p[0] + 4):
				if Vector2(x - p[0], (y - p[1]) * 1.5).length() < 4.0:
					img.set_pixel(clampi(x, 0, w - 1), clampi(y, 0, hh - 1), Color("4f772d"))
	_paint_tex = ImageTexture.create_from_image(img)
	return _paint_tex


## Image à l'écran : un match de lutte au coucher du soleil (dégradé, arène, deux silhouettes)
static func _screen_texture() -> Texture2D:
	if _screen_tex != null:
		return _screen_tex
	var w := 128
	var hh := 72
	var img := Image.create(w, hh, false, Image.FORMAT_RGB8)
	for y in hh:
		var t := float(y) / hh
		var sky := Color("ff9e40").lerp(Color("5a189a"), 1.0 - t)
		for x in w:
			img.set_pixel(x, y, sky if y < 44 else Color("d9b98a").darkened(0.15 * float(y - 44) / 28.0))
	# Public (gradins) et deux lutteurs
	for x in w:
		for y in range(36, 44):
			if (x * 7 + y * 13) % 5 < 3:
				img.set_pixel(x, y, Color.from_hsv(float((x * 37) % 100) / 100.0, 0.6, 0.55))
	for f in [[52, Color("1b1b1b")], [70, Color("3a2416")]]:
		for y in range(30, 58):
			for x in range(f[0] - 4 + (1 if y > 46 else 0), f[0] + 5):
				img.set_pixel(x, y, f[1])
		for y in range(24, 30):
			for x in range(f[0] - 2, f[0] + 3):
				img.set_pixel(x, y, f[1])
	_screen_tex = ImageTexture.create_from_image(img)
	return _screen_tex
