extends SceneTree
## Outil : silhouette d'un personnage du jeu, pistolet levé (pose d'affiche), sur fond transparent, pour le logo
## (tools/make_icon.py la pose devant le soleil).
##   godot --path . --resolution 1024x1536 -s res://tools/pose_shot.gd -- --model=heros --out=C:/chemin/silhouette.png
## --couleur : personnage en couleur (visage, habits) éclairé comme la nuit en ville, au lieu de la silhouette

const INK := Color8(28, 12, 30)

var _f := 0
var _c
var _skel: Skeleton3D
var _gun: Node3D
var _out := "user://silhouette.png"
var _model := "heros"
var _color := false
var _close := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			_model = a.substr(8)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--couleur":
			_color = true
		elif a == "--gros-plan":
			_close = true  # caméra sur la main et le pistolet (pour régler la prise en main)
	root.transparent_bg = true
	var h := Node3D.new()
	root.add_child(h)
	_c = load("res://scripts/util/real_character.gd").create(h, _model, -1)
	_skel = _c.skeleton
	var cam := Camera3D.new()
	cam.fov = 26
	# De face (il regarde -Z) : le bras armé tendu sur le côté (sa droite = +X) montre le pistolet de profil
	cam.position = Vector3(-0.35, 1.05, -4.8)
	root.add_child(cam)
	cam.current = true
	_cam = cam
	_gun = _make_gun()
	root.add_child(_gun)
	if _color:
		_lights()


## Éclairage de nuit en ville : lumière chaude de face (lampadaire), contre-jour rouge, ciel bleu nuit
func _lights() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.32, 0.5)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.82, 0.6)
	key.light_energy = 1.25
	key.rotation = Vector3(-0.45, PI + 0.55, 0)  # de face, en haut à gauche de l'image
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.3, 0.15)
	rim.light_energy = 2.2
	rim.rotation = Vector3(-0.2, -0.6, 0)  # de derrière, côté droit
	root.add_child(rim)
	var rim2 := DirectionalLight3D.new()
	rim2.light_color = Color(1.0, 0.4, 0.2)
	rim2.light_energy = 1.6
	rim2.rotation = Vector3(-0.2, 0.7, 0)  # de derrière, côté gauche
	root.add_child(rim2)


var _cam: Camera3D


func _mat(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if _color:
		m.albedo_color = col
		m.metallic = metal
		m.roughness = rough
	else:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = INK
	return m


## Pièce plate du pistolet : profil (plan XY, en mètres) extrudé sur l'épaisseur voulue, centré en Z
func _part(g: Node3D, profile: PackedVector2Array, depth: float, m: Material, z := 0.0) -> CSGPolygon3D:
	var p := CSGPolygon3D.new()
	p.polygon = profile
	p.depth = depth
	p.position.z = z + depth / 2.0
	p.material = m
	g.add_child(p)
	return p


## Pistolet semi-automatique (genre Glock) en profil : culasse métal, carcasse et crosse en polymère,
## pontet ajouré, détente, organes de visée. Repère : canon vers +X, haut +Y, origine en haut de la crosse
## (là où se loge le creux entre pouce et index).
func _make_gun() -> Node3D:
	var g := Node3D.new()
	var steel := _mat(Color(0.1, 0.1, 0.11), 0.85, 0.3)
	var poly := _mat(Color(0.03, 0.032, 0.04), 0.35, 0.45)
	# Culasse : chanfrein à l'avant, rainures à l'arrière, fenêtre d'éjection
	_part(g, PackedVector2Array([Vector2(-0.03, 0.012), Vector2(0.158, 0.012), Vector2(0.162, 0.03),
		Vector2(0.155, 0.044), Vector2(-0.024, 0.044), Vector2(-0.032, 0.036)]), 0.026, steel)
	for k in 6:
		_part(g, PackedVector2Array([Vector2(-0.022 + k * 0.006, 0.016), Vector2(-0.019 + k * 0.006, 0.016),
			Vector2(-0.019 + k * 0.006, 0.04), Vector2(-0.022 + k * 0.006, 0.04)]), 0.028, poly, -0.001)
	_part(g, PackedVector2Array([Vector2(0.03, 0.03), Vector2(0.07, 0.03), Vector2(0.07, 0.043), Vector2(0.03, 0.043)]), 0.027, poly, -0.0005)
	# Bouche du canon
	_part(g, PackedVector2Array([Vector2(0.157, 0.02), Vector2(0.165, 0.02), Vector2(0.165, 0.032), Vector2(0.157, 0.032)]), 0.012, steel, 0.007)
	# Organes de visée
	_part(g, PackedVector2Array([Vector2(0.142, 0.044), Vector2(0.15, 0.044), Vector2(0.149, 0.05), Vector2(0.144, 0.05)]), 0.006, steel, 0.01)
	_part(g, PackedVector2Array([Vector2(-0.02, 0.044), Vector2(-0.006, 0.044), Vector2(-0.006, 0.051), Vector2(-0.02, 0.051)]), 0.016, steel, 0.005)
	# Carcasse : rail sous le canon, pontet ajouré, crosse inclinée de 20° avec appui de la main
	var frame := _part(g, PackedVector2Array([Vector2(-0.034, 0.012), Vector2(0.15, 0.012), Vector2(0.15, -0.004),
		Vector2(0.075, -0.006), Vector2(0.07, -0.03), Vector2(0.056, -0.04), Vector2(0.016, -0.04),
		Vector2(0.008, -0.012), Vector2(0.004, -0.02), Vector2(-0.012, -0.1), Vector2(-0.016, -0.106),
		Vector2(-0.056, -0.106), Vector2(-0.058, -0.1), Vector2(-0.04, -0.012), Vector2(-0.048, -0.002)]), 0.028, poly, -0.001)
	var hole := CSGPolygon3D.new()
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.polygon = PackedVector2Array([Vector2(0.016, -0.008), Vector2(0.064, -0.008), Vector2(0.062, -0.028),
		Vector2(0.052, -0.034), Vector2(0.022, -0.034)])
	hole.depth = 0.04
	hole.position.z = -0.006
	frame.add_child(hole)
	# Détente
	_part(g, PackedVector2Array([Vector2(0.03, -0.008), Vector2(0.037, -0.008), Vector2(0.036, -0.02),
		Vector2(0.032, -0.027), Vector2(0.03, -0.022), Vector2(0.032, -0.016)]), 0.006, steel, 0.011)
	# Chargeur visible sous la crosse
	_part(g, PackedVector2Array([Vector2(-0.054, -0.106), Vector2(-0.018, -0.106), Vector2(-0.019, -0.112), Vector2(-0.055, -0.112)]), 0.026, steel)
	return g


## Ferme les doigts de la main droite sur la crosse (axe de flexion : y du repère du pistolet)
func _curl(finger: String, angles: Array, axis: Vector3) -> void:
	for i in 3:
		var b := _skel.find_bone("%s_0%d_r" % [finger, i + 1])
		var g := _skel.get_bone_global_pose(b)
		_skel.set_bone_global_pose(b, Transform3D(Basis(axis, angles[i]) * g.basis, g.origin))


## Rotation qui oriente la main comme sur une crosse : doigts dans la direction fwd, rangée des jointures (auriculaire -> index)
## selon up (incliné comme la crosse)
func _grip_rot(fwd: Vector3, up: Vector3) -> Quaternion:
	var hb := _skel.find_bone("hand_r")
	var g := _skel.get_bone_global_pose(hb)
	var f := (_skel.get_bone_global_pose(_skel.find_bone("middle_01_r")).origin - g.origin).normalized()
	var sd := (_skel.get_bone_global_pose(_skel.find_bone("index_01_r")).origin - _skel.get_bone_global_pose(_skel.find_bone("pinky_01_r")).origin)
	sd = (sd - f * sd.dot(f)).normalized()
	var cur := Basis(f, sd, f.cross(sd))
	var u := (up - fwd * up.dot(fwd)).normalized()
	var tgt := Basis(fwd.normalized(), u, fwd.normalized().cross(u))
	return Quaternion(tgt * cur.inverse())


## Silhouette : tout en encre, sans lumière ; les cheveux et cils gardent leur transparence (découpe)
func _ink(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for s in mi.mesh.get_surface_count() if mi.mesh else 0:
			var orig = mi.get_active_material(s)
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = INK
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			if orig is BaseMaterial3D and (orig as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				m.albedo_texture = (orig as BaseMaterial3D).albedo_texture
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				m.alpha_scissor_threshold = 0.5
			mi.set_surface_override_material(s, m)
	for ch in n.get_children():
		_ink(ch)


func _bone_pos(name: String) -> Vector3:
	return (_skel.global_transform * _skel.get_bone_global_pose(_skel.find_bone(name))).origin


## Oriente un os (dans le repère du squelette) pour que son enfant soit dans la direction voulue
func _aim(bone: String, child: String, dir: Vector3) -> void:
	var b := _skel.find_bone(bone)
	var c := _skel.find_bone(child)
	var g := _skel.get_bone_global_pose(b)
	var cur := (_skel.get_bone_global_pose(c).origin - g.origin).normalized()
	var q := Quaternion(cur, dir.normalized())
	_skel.set_bone_global_pose(b, Transform3D(Basis(q) * g.basis, g.origin))


func _process(_d: float) -> bool:
	_f += 1
	var ap: AnimationPlayer = _c._anim
	if _f == 2:
		ap.play("idle", 0.0)
		ap.seek(0.6, true)
		ap.active = false
		if not _color:
			_ink(_c)
	if _f == 3:
		# Bras droit tendu sur le côté, à hauteur d'épaule : il vise
		_aim("upperarm_r", "lowerarm_r", Vector3(1.0, 0.04, -0.12))
		_aim("lowerarm_r", "hand_r", Vector3(1.0, 0.04, -0.12))
		# Tête tournée vers la cible (en couleur : à moitié seulement, pour qu'on voie le visage)
		var hb := _skel.find_bone("head")
		var hg := _skel.get_bone_global_pose(hb)
		_skel.set_bone_global_pose(hb, Transform3D(Basis(Vector3.UP, 0.4 if _color else 0.9) * hg.basis, hg.origin))
	if _f == 4:
		# Repère du pistolet dans le squelette : canon le long de l'avant-bras, crosse inclinée de 20°
		var fore := (_skel.get_bone_global_pose(_skel.find_bone("hand_r")).origin - _skel.get_bone_global_pose(_skel.find_bone("lowerarm_r")).origin).normalized()
		var gx := fore
		var gz := gx.cross(Vector3.UP).normalized()  # côté droit du pistolet (vers l'arrière du personnage)
		var gy := gz.cross(gx)
		var grip_up := (gy * cos(0.35) + gx * sin(0.35)).normalized()  # axe de la crosse, vers le haut
		var hfwd := gx * cos(0.35) - gy * sin(0.35)
		# La rotation de l'avant-bras sur lui-même (pronation) est répartie entre bras et avant-bras,
		# sinon tout se tord au poignet ; le reste (flexion du poignet) va à la main
		var q := _grip_rot(hfwd, grip_up)
		var t := gx * Vector3(q.x, q.y, q.z).dot(gx)
		var twist := Quaternion(t.x, t.y, t.z, q.w).normalized()
		for bn in ["upperarm_r", "lowerarm_r"]:
			var b := _skel.find_bone(bn)
			var bg := _skel.get_bone_global_pose(b)
			_skel.set_bone_global_pose(b, Transform3D(Basis(Quaternion.IDENTITY.slerp(twist, 0.5)) * bg.basis, bg.origin))
		var hb2 := _skel.find_bone("hand_r")
		var hg2 := _skel.get_bone_global_pose(hb2)
		_skel.set_bone_global_pose(hb2, Transform3D(Basis(_grip_rot(hfwd, grip_up)) * hg2.basis, hg2.origin))
		# Index sur la détente, les trois autres doigts refermés autour de la crosse, pouce le long du côté gauche
		_curl("index", [0.3, 0.55, 0.3], gy)
		for fn in ["middle", "ring", "pinky"]:
			_curl(fn, [1.45, 1.35, 0.7], gy)
		_curl("thumb", [0.25, 0.35, 0.2], gz)
	if _f == 5:
		var gx := (_bone_pos("hand_r") - _bone_pos("lowerarm_r")).normalized()
		var gz := gx.cross(Vector3.UP).normalized()
		var gy := gz.cross(gx)
		var hand := _bone_pos("hand_r")
		var web := _bone_pos("index_01_r")
		# Haut de la crosse dans le creux de la main, juste au-dessus de la jointure de l'index
		_gun.basis = Basis(gx, gy, gz).scaled(Vector3.ONE * (1.2 if not _close else 1.0))  # un peu grossi : lisible sur l icône
		_gun.global_position = web.lerp(hand, 0.35) + gy * 0.018 + gx * 0.022
		_cam.look_at(Vector3(-0.35, 1.0, 0), Vector3.UP)
		if _close:
			_cam.fov = 12
			_cam.position = hand + Vector3(-0.1, 0.05, -1.4)
			_cam.look_at(hand + gx * 0.08, Vector3.UP)
	if _f < 30:
		return false
	var img: Image = root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(_out)
	print("silhouette : ", _out)
	return true
