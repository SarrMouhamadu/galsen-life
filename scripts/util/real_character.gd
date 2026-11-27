extends Node3D
## Personnage réaliste généré avec MakeHuman (tools/make_characters.py, ressources CC0).
## Charge le modèle glTF et l'anime de façon procédurale sur son squelette « game_engine » :
## bras baissés, marche (jambes, genoux, bras, coudes), léger balancement du buste.
## Le nœud regarde vers -Z comme le reste du jeu.

const Outfits = preload("res://scripts/util/outfits.gd")
const DIR := "res://characters/realistic/"
const HERO := "heros"
const MEN := ["homme_ville", "homme_age", "homme_afro", "homme_tunique"]
const WOMEN := ["femme_robe", "femme_jupe", "femme_maman", "femme_ville"]
## Teintes appliquées aux vêtements des passants pour varier les tenues
const CLOTH_TINTS := [Color(1, 1, 1), Color("ffd6a5"), Color("a0c4ff"), Color("caffbf"), Color("ffadad"),
	Color("bdb2ff"), Color("fdffb6"), Color("9bf6ff"), Color("e9c46a"), Color("f4a261")]
const SOLDIER := "soldat"
## Couleurs de grand boubou en bazin (la robe longue est teinte d'une couleur unie)
const BOUBOU := [Color("f2efe6"), Color("1f3a93"), Color("6b8fd4"), Color("2e7d5b"), Color("c9a227"), Color("7b2d8e"), Color("a83232")]
## Personnages créés par IA à partir des images du joueur (tools/rig_ai_character.py) : une seule pièce
## texturée, couleurs d'origine (pas de teinte aléatoire)
const AI_MODELS := ["jayden_carter", "femme_ville", "femme_robe", "femme_jupe", "femme_maman"]
## Footballeurs du complexe de mini-foot : maillot, short et chaussettes teints en couleur unie et brillante (polyester)
const FOOTBALLERS := ["footballeur1", "footballeur2", "footballeur3", "footballeuse", "gardien"]
const BODY_PARTS := ["male_generic", "female_generic", "low-poly", "eyebrow", "eyelashes"]
## Carrure : [largeur du buste, épaisseur des bras]. Les gens ordinaires gardent le corps naturel
## du modèle (tools/make_characters.py) ; seuls les lutteurs sont élargis.
const BUILD := {"lutteur1": [1.24, 1.22], "lutteur2": [1.26, 1.2]}
## Les semelles descendent de 1 à 2 cm sous l'origine des modèles (et l'animation d'attente pose l'avant
## du pied au ras du sol) : on relève le corps pour que les chaussures ne s'enfoncent pas dans le sol
const FOOT_LIFT := 0.025

static var _scenes := {}
static var _libs := {}

var skeleton: Skeleton3D
var _model: Node3D
var _order := PackedInt32Array()
var _parent := PackedInt32Array()
var _rest := [] ## Basis globale de repos par os
var _idx := {}
var _arm_lower := {} ## os → Basis qui baisse le bras depuis la pose en A
var _breath := 0.0
var _anim: AnimationPlayer ## animations en capture de mouvement (tools/bake_animations.gd)
var _current := ""
var _anim_step := 0.0 ## niveau de détail : 0 = animé à chaque image, sinon intervalle (s) entre deux mises à jour
var _anim_acc := 0.0
var _clothes := [] ## [pièce, partie (haut / bas / chapeau / ""), [matériaux d'origine]] : tenues (set_outfit)
var _hat: Node3D
var _outfit := ""
var _hairs := [] ## [pièce, [matériaux d'origine]] : cheveux du modèle (cachés par une coiffure du coiffeur)
var _new_hair: MeshInstance3D
var _female := false
var _sport := false
var _single := false ## modèle d'une seule pièce (AI_MODELS) : habits et cheveux non séparables
static var _hair_scenes := {}


static func create(parent: Node, model_name: String, tint_seed := -1) -> Node3D:
	var c = load("res://scripts/util/real_character.gd").new()
	parent.add_child(c)
	c._load(model_name, tint_seed)
	return c


static func random_ped_name(rng: RandomNumberGenerator) -> String:
	var pool: Array = MEN if rng.randf() < 0.5 else WOMEN
	return pool[rng.randi() % pool.size()]


func _load(model_name: String, tint_seed: int) -> void:
	if not _scenes.has(model_name):
		_scenes[model_name] = load(DIR + model_name + ".glb")
	var scene: PackedScene = _scenes[model_name]
	_model = Node3D.new()
	# Les modèles Blender regardent vers +Z une fois exportés ; le jeu attend -Z.
	_model.rotation.y = PI
	_model.position.y = FOOT_LIFT
	add_child(_model)
	var inst := scene.instantiate()
	_model.add_child(inst)
	# Animations en capture de mouvement adaptées à ce personnage
	var lib_path := "res://characters/anims/%s.res" % model_name
	if not _libs.has(model_name) and ResourceLoader.exists(lib_path):
		_libs[model_name] = load(lib_path)
	if _libs.has(model_name):
		_anim = AnimationPlayer.new()
		inst.add_child(_anim)
		_anim.root_node = NodePath("..")
		_anim.add_animation_library("", _libs[model_name])
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	skeleton = found[0]
	var n := skeleton.get_bone_count()
	_parent.resize(n)
	_rest.resize(n)
	for i in n:
		_idx[skeleton.get_bone_name(i)] = i
		_parent[i] = skeleton.get_bone_parent(i)
		_rest[i] = skeleton.get_bone_global_rest(i).basis
	# Ordre parent → enfant
	var done := {}
	while _order.size() < n:
		for i in n:
			if not done.has(i) and (_parent[i] == -1 or done.has(_parent[i])):
				done[i] = true
				_order.append(i)
	for side in ["l", "r"]:
		var up := _bone("upperarm_" + side)
		var low := _bone("lowerarm_" + side)
		if up == -1 or low == -1:
			continue
		var dir := (skeleton.get_bone_global_rest(low).origin - skeleton.get_bone_global_rest(up).origin).normalized()
		var axis := dir.cross(Vector3.DOWN)
		if axis.length() > 0.001:
			_arm_lower[up] = Basis(axis.normalized(), dir.angle_to(Vector3.DOWN) - 0.12)
	if _anim and not _libs[model_name].has_animation("kick"):
		var kick := _make_kick(_libs[model_name].get_animation("idle"))
		if kick:
			_libs[model_name].add_animation("kick", kick)
	_apply_build(model_name)
	_style(model_name, tint_seed)
	if model_name == SOLDIER:
		_add_helmet()
	if _anim:
		play_clip("idle", 0.0)
		_anim.seek(randf() * 2.0, true)
	else:
		animate(0.0, 0.0)


## Carrure : élargit le haut du buste (et donc les épaules) et épaissit les bras par l'échelle des os ;
## la tête garde sa taille (échelle inverse sur la nuque). Les animations ne touchent pas à l'échelle.
func _apply_build(model_name: String) -> void:
	var b: Array = BUILD.get(model_name, [1.0, 1.0])
	var wide: float = b[0]
	var arm: float = b[1]
	if wide == 1.0 and arm == 1.0:
		return
	var lat := Vector3.RIGHT
	var tl := _bone("thigh_l")
	var tr := _bone("thigh_r")
	if tl != -1 and tr != -1:
		lat = (skeleton.get_bone_global_rest(tl).origin - skeleton.get_bone_global_rest(tr).origin).normalized()
	var chest := _bone("spine_03")
	var neck := _bone("neck_01")
	if chest != -1:
		var s := _axis_scale(chest, lat, wide, 1.0, (wide + 1.0) / 2.0)
		skeleton.set_bone_pose_scale(chest, s)
		if neck != -1:
			skeleton.set_bone_pose_scale(neck, Vector3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z))
	for side in ["l", "r"]:
		var up := _bone("upperarm_" + side)
		if up != -1:
			# Épaisseur seulement : la longueur du bras (axe Y de l'os) ne change pas
			skeleton.set_bone_pose_scale(up, Vector3(arm, 1.0, arm))
			var low := _bone("lowerarm_" + side)
			if low != -1:
				var t := (1.0 + arm) / 2.0 / arm # avant-bras un peu moins épais que le haut du bras
				skeleton.set_bone_pose_scale(low, Vector3(t, 1.0, t))


## Échelle locale d'un os : « wide » le long de l'axe local le plus proche de la direction latérale du corps,
## « along » le long de l'os (Y), « other » sur le dernier axe.
func _axis_scale(bone: int, lateral: Vector3, wide: float, along: float, other: float) -> Vector3:
	var bs := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var dx := absf(bs.x.dot(lateral))
	var dz := absf(bs.z.dot(lateral))
	return Vector3(wide, along, other) if dx >= dz else Vector3(other, along, wide)


## Casque kaki fixé à l'os de la tête.
func _add_helmet() -> void:
	var head := _bone("head")
	if head == -1:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = head
	skeleton.add_child(att)
	var mesh := SphereMesh.new()
	mesh.radius = 0.135
	mesh.height = 0.135
	mesh.is_hemisphere = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4b5320")
	mat.roughness = 0.8
	mi.material_override = mat
	# L'os de la tête part de la nuque : le casque est posé un peu plus haut.
	var rest := skeleton.get_bone_global_rest(head)
	mi.global_transform = Transform3D(Basis(), Vector3.ZERO)
	att.add_child(mi)
	mi.transform = Transform3D(rest.basis.inverse(), rest.basis.inverse() * Vector3(0, 0.115, 0.005))
	var brim := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.15
	bm.bottom_radius = 0.15
	bm.height = 0.012
	brim.mesh = bm
	brim.material_override = mat
	att.add_child(brim)
	brim.transform = Transform3D(rest.basis.inverse(), rest.basis.inverse() * Vector3(0, 0.115, 0.005))


func _bone(bone_name: String) -> int:
	return _idx.get(bone_name, -1)


## Matériaux réalistes : peau (shader dédié), yeux brillants, cils et cheveux avec transparence propre,
## tissus mats. Teintes : polo crème et cheveux noirs pour le héros, couleurs variées pour les passants.
func _style(model_name: String, tint_seed: int) -> void:
	_female = model_name in WOMEN or model_name.begins_with("femme") or model_name == "footballeuse"
	_sport = model_name in FOOTBALLERS
	_single = model_name in AI_MODELS
	var rng := RandomNumberGenerator.new()
	rng.seed = tint_seed
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		# Nom de la pièce sans le nom du personnage (« homme_afro_afro01 » → « _afro01 »)
		var mname := String(mi.name).to_lower().replace(model_name, "")
		var kind := _part_kind(mname)
		var tint := Color(1, 1, 1)
		if model_name in AI_MODELS:
			kind = "ai"
		elif kind == "hair":
			tint = Color(0.34, 0.3, 0.28)
		elif kind == "cloth":
			if model_name == SOLDIER and not ("short" in mname):
				# Treillis kaki uni (le relief du tissu est conservé)
				tint = Color("4b5320") if "pants" in mname else (Color("5b6334") if "sweater" in mname else Color("2a2a22"))
			elif "kimono" in mname:
				tint = BOUBOU[maxi(tint_seed, 0) % BOUBOU.size()]
			elif model_name == HERO and "polo" in mname:
				tint = Color("f3ead6")
			elif tint_seed >= 0:
				tint = CLOTH_TINTS[rng.randi() % CLOTH_TINTS.size()]
		var base := []
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D:
				var solid: bool = (model_name == SOLDIER and kind == "cloth" and not ("short" in mname)) or "kimono" in mname
				mi.set_surface_override_material(s, _material_for(m, kind, tint, solid))
			base.append(mi.get_surface_override_material(s))
		if kind == "cloth":
			_clothes.append([mi, _cloth_part(mname), base])
		elif kind == "hair":
			_hairs.append([mi, base])


## Partie de la tenue que couvre un vêtement (chaussures : aucune)
static func _cloth_part(mname: String) -> String:
	for w in ["shoe", "boot", "flats", "sandal"]:
		if w in mname:
			return ""
	if "socks" in mname:
		return "chaussettes"
	if "cap" in mname or "hat" in mname:
		return "chapeau"
	for w in ["pants", "jean", "skirt", "trouser"]:
		if w in mname:
			return "bas"
	return "haut"


## Tenue choisie dans l'appli « Sapé » (scripts/util/outfits.gd) : couleur unie du haut et du bas,
## chapeau sur la tête. Une partie vide remet le vêtement d'origine.
func set_outfit(code: String) -> void:
	if code == _outfit: # appelé à chaque image pour les autres joueurs
		return
	_outfit = code
	var p := Outfits.parse(code)
	for c in _clothes:
		var mi: MeshInstance3D = c[0]
		var part: String = c[1]
		if part == "chapeau":
			mi.visible = p[2] == "" # le chapeau choisi remplace celui du personnage
			continue
		var color_id: String = p[0] if part == "haut" else (p[1] if part == "bas" or part == "chaussettes" else "")
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			if color_id == "" or not m is StandardMaterial3D:
				mi.set_surface_override_material(s, c[2][s])
			else:
				mi.set_surface_override_material(s, _material_for(m, "dye", Outfits.COLORS[color_id][1], color_id == "bazin_or" or _sport))
	if _hat:
		_hat.queue_free()
		_hat = null
	if p[2] != "":
		_hat = _make_hat(Outfits.HATS[p[2]][1], Outfits.HATS[p[2]][2])
	_set_hair(p[3], p[4])


## Coiffure du coiffeur (characters/hair, tools/make_hair.py) rattachée à notre squelette par le nom
## des os, et couleur des cheveux. Coiffure vide : cheveux d'origine du modèle.
func _set_hair(style: String, color_id: String) -> void:
	if _new_hair:
		_new_hair.queue_free()
		_new_hair = null
	if _single:
		return # les cheveux d'origine ne peuvent pas être cachés : une coupe passerait au travers
	var file: String = Outfits.HAIRS[style][1] if style != "" else ""
	for h in _hairs:
		h[0].visible = style == ""
	if file != "":
		var path := "res://characters/hair/%s_%s.glb" % ["femme" if _female else "homme", file]
		if not _hair_scenes.has(path):
			_hair_scenes[path] = load(path)
		var inst: Node = _hair_scenes[path].instantiate()
		var src := inst.find_child("coiffure", true, false) as MeshInstance3D
		if src:
			src.get_parent().remove_child(src)
			skeleton.add_child(src)
			src.transform = Transform3D.IDENTITY
			src.skeleton = NodePath("..")
			_new_hair = src
		inst.free()
	# Couleur : multiplie la texture (au-delà de 1 pour éclaircir)
	var tint: Color = Outfits.HAIR_COLORS[color_id][1] if color_id != "" else Color(0.34, 0.3, 0.28)
	var targets := []
	if _new_hair:
		targets.append(_new_hair)
	elif style == "":
		for h in _hairs:
			targets.append(h[0])
	for mi in targets:
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			if m is StandardMaterial3D:
				mi.set_surface_override_material(s, _material_for(m, "hair", tint, false))


func _make_hat(shape: String, color: Color) -> Node3D:
	var head := _bone("head")
	if head == -1:
		return null
	var att := BoneAttachment3D.new()
	att.bone_idx = head
	skeleton.add_child(att)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8 if shape != "kufi" else 0.6
	# Même repère que le casque du soldat : posé au-dessus de la nuque, droit dans le repère du modèle
	var rest := skeleton.get_bone_global_rest(head)
	var inv := rest.basis.inverse()
	var top := Vector3(0, 0.115, 0.005)
	match shape:
		"casquette":
			var dome := SphereMesh.new()
			dome.radius = 0.122
			dome.height = 0.11
			dome.is_hemisphere = true
			_hat_piece(att, dome, mat, inv, top + Vector3(0, -0.012, 0))
			var visor := BoxMesh.new()
			visor.size = Vector3(0.17, 0.01, 0.1)
			_hat_piece(att, visor, mat, inv, top + Vector3(0, -0.008, 0.15))
		"kufi":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.105
			cyl.bottom_radius = 0.115
			cyl.height = 0.08
			_hat_piece(att, cyl, mat, inv, top + Vector3(0, 0.012, 0))
		"paille":
			var dome := SphereMesh.new()
			dome.radius = 0.12
			dome.height = 0.12
			dome.is_hemisphere = true
			_hat_piece(att, dome, mat, inv, top)
			var brim := CylinderMesh.new()
			brim.top_radius = 0.22
			brim.bottom_radius = 0.22
			brim.height = 0.01
			_hat_piece(att, brim, mat, inv, top + Vector3(0, 0.005, 0))
	return att


func _hat_piece(att: Node3D, mesh: Mesh, mat: Material, inv: Basis, offset: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	att.add_child(mi)
	mi.transform = Transform3D(inv, inv * offset)


static func _part_kind(mname: String) -> String:
	if "male_generic" in mname or "female_generic" in mname or "muscle_" in mname:
		return "skin"
	if "low-poly" in mname or "high-poly" in mname or "low_poly" in mname or "high_poly" in mname:
		return "eye"
	if "eyebrow" in mname or "eyelash" in mname:
		return "lash"
	for h in ["short0", "afro", "braid", "ponytail", "bun", "bob", "long0"]:
		if h in mname and not "shorts" in mname:
			return "hair"
	return "cloth"


static var _skin_shader: Shader
static var _skin_nrm: Texture2D
static var _skin_spec: Texture2D
static var _mat_cache := {}


func _material_for(m: StandardMaterial3D, kind: String, tint: Color, solid: bool) -> Material:
	var key := "%s|%s|%s|%s" % [m.get_rid().get_id(), kind, tint.to_html(), solid]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Material
	if kind == "skin":
		if _skin_shader == null:
			_skin_shader = load("res://characters/skin/skin.gdshader")
			_skin_nrm = load("res://characters/skin/skin_nrm.png")
			_skin_spec = load("res://characters/skin/skin_spec.png")
		var sm := ShaderMaterial.new()
		sm.shader = _skin_shader
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
		sm.set_shader_parameter("tint", m.albedo_color)
		sm.set_shader_parameter("normal_tex", _skin_nrm)
		sm.set_shader_parameter("spec_tex", _skin_spec)
		out = sm
	else:
		var d: StandardMaterial3D = m.duplicate()
		d.albedo_color = m.albedo_color * tint
		d.metallic = 0.0
		# Certains modèles Sketchfab ont une carte d'émission : le personnage brillerait la nuit
		d.emission_enabled = false
		match kind:
			"eye":
				# Œil humide : très brillant
				# Globe de l'œil : la couche transparente de la cornée est découpée
				d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				d.alpha_scissor_threshold = 0.5
				d.roughness = 0.12
				d.metallic_specular = 0.5
			"lash", "hair":
				# Cartes de cheveux / cils : découpe nette, lissée par le MSAA, visibles des deux côtés
				d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				d.alpha_scissor_threshold = 0.35 if kind == "hair" else 0.25
				d.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
				# Cheveux crépus : mats, presque sans reflet
				d.roughness = 0.9 if kind == "hair" else 0.8
				d.metallic_specular = 0.12 if kind == "hair" else 0.3
			"dye":
				# Tenue teinte : couleur unie, le relief du tissu (carte de normales) est gardé
				d.albedo_texture = null
				d.albedo_color = tint
				if d.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					d.alpha_scissor_threshold = 0.3
				d.roughness = 0.36 if solid else 0.76
				d.metallic_specular = 0.62 if solid else 0.35
				d.rim_enabled = true
				d.rim = 0.35
				d.rim_tint = 0.45
			_:
				if solid:
					d.albedo_texture = null
					d.albedo_color = tint
				# Tissu : découpe nette si la texture a des trous, éclairage de contour (rim)
				if d.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					d.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					d.alpha_scissor_threshold = 0.3
				d.roughness = 0.76
				d.metallic_specular = 0.35
				if solid and kind == "cloth" and tint in BOUBOU:
					# Bazin riche : tissu damassé lustré et brillant
					d.roughness = 0.35
					d.metallic_specular = 0.65
					d.rim_enabled = true
					d.rim = 0.45
					d.rim_tint = 0.55
				else:
					d.rim_enabled = true
					d.rim = 0.32
					d.rim_tint = 0.45
		out = d
	_mat_cache[key] = out
	return out


## Niveau de détail de l'animation (téléphones) : les personnages lointains sont animés
## moins souvent (hz = mises à jour par seconde ; 0 = à chaque image). La pose du squelette
## coûte cher au processeur : c'est le plus gros gain sur les téléphones modestes.
func set_anim_rate(hz: float) -> void:
	if _anim == null:
		return
	var step := 0.0 if hz <= 0.0 else 1.0 / hz
	if is_equal_approx(step, _anim_step):
		return
	_anim_step = step
	_anim_acc = randf() * step # désynchronise les passants (pas tous à la même image)
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE if step == 0.0 else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	set_process(step > 0.0)


func _process(delta: float) -> void:
	if _anim_step <= 0.0:
		set_process(false)
		return
	_anim_acc += delta
	if _anim_acc >= _anim_step:
		_anim.advance(_anim_acc)
		_anim_acc = 0.0


## Joue une animation (idle, walk, jog, sprint, talk, sit, dance, drive, punch, push, hit, fall, jump).
func play_clip(clip: String, blend := 0.25, speed := 1.0) -> void:
	if _anim == null:
		return
	if _current != clip or not _anim.is_playing():
		_anim.play(clip, blend)
		_current = clip
	_anim.speed_scale = speed


## Choisit l'allure selon la vitesse (m/s) : attente, marche, jogging ou sprint, à la bonne cadence.
func locomote(speed: float) -> void:
	if _anim == null:
		animate(speed * 2.0, clampf(speed / 1.5, 0.0, 1.0) * 0.6)
		return
	# Cadence = vitesse / vitesse au sol de l'allure (mesurée au bake) : le pied d'appui ne glisse pas
	if speed < 0.15:
		play_clip("idle", 0.3)
	elif speed < 2.4:
		play_clip("walk", 0.25, clampf(speed / _ground_speed("walk", 1.55), 0.6, 1.6))
	elif speed < 4.8:
		play_clip("jog", 0.2, clampf(speed / _ground_speed("jog", 3.8), 0.65, 1.35))
	else:
		play_clip("sprint", 0.2, clampf(speed / _ground_speed("sprint", 6.2), 0.75, 1.35))


## Vitesse (m/s) à laquelle le pied d'appui recule dans l'allure (tools/bake_animations.gd)
func _ground_speed(clip: String, fallback: float) -> float:
	if not _anim.has_animation(clip):
		return fallback
	var v: float = _anim.get_animation(clip).get_meta("ground_speed", fallback)
	return v if v > 0.3 else fallback


func has_animations() -> bool:
	return _anim != null


## t : phase de la marche ; amount : 0 (immobile) à 1 (marche franche).
func animate(t: float, amount: float) -> void:
	if skeleton == null or _anim != null:
		return
	_breath += 0.03
	var s := sin(t) * amount
	var delta := {}
	# Jambes : vers l'avant = rotation négative autour de X (le squelette regarde +Z)
	_put(delta, "thigh_l", Basis(Vector3.RIGHT, -s * 0.55))
	_put(delta, "thigh_r", Basis(Vector3.RIGHT, s * 0.55))
	_put(delta, "calf_l", Basis(Vector3.RIGHT, maxf(0.0, sin(t + 1.3)) * amount * 0.9))
	_put(delta, "calf_r", Basis(Vector3.RIGHT, maxf(0.0, sin(t + 1.3 + PI)) * amount * 0.9))
	_put(delta, "foot_l", Basis(Vector3.RIGHT, -maxf(0.0, sin(t + 1.3)) * amount * 0.3))
	_put(delta, "foot_r", Basis(Vector3.RIGHT, -maxf(0.0, sin(t + 1.3 + PI)) * amount * 0.3))
	# Bras baissés, balancés à l'opposé des jambes, coudes légèrement pliés
	for side in ["l", "r"]:
		var up := _bone("upperarm_" + side)
		var swing := s * 0.45 if side == "l" else -s * 0.45
		var lower: Basis = _arm_lower.get(up, Basis())
		if up != -1:
			delta[up] = Basis(Vector3.RIGHT, swing) * lower
		_put(delta, "lowerarm_" + side, Basis(Vector3.RIGHT, -0.25 - amount * 0.25))
	# Buste : léger roulis et respiration
	_put(delta, "spine_01", Basis(Vector3.UP, s * 0.08))
	_put(delta, "spine_02", Basis(Vector3.RIGHT, sin(_breath) * 0.015))
	_apply(delta)
	# Petit rebond du corps à chaque pas
	_model.position.y = FOOT_LIFT - absf(sin(t)) * amount * 0.035


func _put(delta: Dictionary, bone_name: String, b: Basis) -> void:
	var i := _bone(bone_name)
	if i != -1:
		delta[i] = b


## Applique des rotations exprimées dans l'espace du modèle, en respectant la hiérarchie.
func _apply(delta: Dictionary) -> void:
	var cum := []
	cum.resize(_rest.size())
	var posed := []
	posed.resize(_rest.size())
	for i in _order:
		var p := _parent[i]
		var d: Basis = delta.get(i, Basis())
		var c: Basis = (cum[p] * d) if p != -1 else d
		cum[i] = c
		posed[i] = c * _rest[i]
		if delta.has(i) or (p != -1 and cum[p] != Basis()):
			var local: Basis = (posed[p].inverse() * posed[i]) if p != -1 else posed[i]
			skeleton.set_bone_pose_rotation(i, local.get_rotation_quaternion())


## Frappe du pied droit (mini-foot) : la bibliothèque de capture de mouvement n'en a pas. On part de la
## pose d'attente et on fait pivoter cuisse et jambe droites : armer en arrière, frapper, accompagner, revenir.
## Fabriquée une fois par modèle, ajoutée à sa bibliothèque d'animations partagée.
func _make_kick(idle: Animation) -> Animation:
	var thigh := _bone("thigh_r")
	var calf := _bone("calf_r")
	var foot := _bone("foot_r")
	if idle == null or thigh == -1 or calf == -1 or foot == -1:
		return null
	var n := skeleton.get_bone_count()
	var track := {}
	for i in idle.get_track_count():
		var path := idle.track_get_path(i)
		if idle.track_get_type(i) == Animation.TYPE_ROTATION_3D and _idx.has(String(path.get_subname(0))):
			track[_idx[String(path.get_subname(0))]] = i
	if not track.has(thigh) or not track.has(calf):
		return null
	# Pose d'attente au début du clip, en repère du squelette
	var gl := []
	gl.resize(n)
	for b in _order:
		var lq: Quaternion = skeleton.get_bone_rest(b).basis.get_rotation_quaternion()
		if track.has(b):
			lq = idle.rotation_track_interpolate(track[b], 0.0)
		gl[b] = (gl[_parent[b]] * Basis(lq)) if _parent[b] != -1 else Basis(lq)
	var L := (skeleton.get_bone_global_rest(_bone("thigh_l")).origin - skeleton.get_bone_global_rest(thigh).origin).normalized()
	var U := Vector3.UP
	var F := L.cross(U) ## devant le personnage
	var rg_t := skeleton.get_bone_global_rest(thigh).basis.orthonormalized()
	var rg_c := skeleton.get_bone_global_rest(calf).basis.orthonormalized()
	var du := rg_t.inverse() * (skeleton.get_bone_global_rest(calf).origin - skeleton.get_bone_global_rest(thigh).origin).normalized()
	var dl := rg_c.inverse() * (skeleton.get_bone_global_rest(foot).origin - skeleton.get_bone_global_rest(calf).origin).normalized()
	var out := Animation.new()
	out.length = 0.6
	out.loop_mode = Animation.LOOP_NONE
	# Instants et directions voulues [cuisse, jambe] (null : pose d'attente)
	var keys := [[0.0, null], [0.16, [-U - F * 0.45, -U - F * 1.4]], [0.27, [-U * 0.8 + F * 0.95, -U * 0.55 + F * 1.0]],
		[0.4, [-U * 0.55 + F * 1.0, -U * 0.4 + F * 1.0]], [0.6, null]]
	for i in idle.get_track_count():
		var ty := idle.track_get_type(i)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		var tr := out.add_track(ty)
		out.track_set_path(tr, idle.track_get_path(i))
		var bone: int = _idx.get(String(idle.track_get_path(i).get_subname(0)), -1)
		for k in keys:
			var t: float = k[0]
			if ty == Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(tr, t, idle.position_track_interpolate(i, 0.0))
				continue
			var q := idle.rotation_track_interpolate(i, 0.0)
			if k[1] != null and (bone == thigh or bone == calf):
				var want: Array = k[1]
				var gt: Basis = gl[thigh]
				var gt2 := Basis(Quaternion((gt * du).normalized(), (want[0] as Vector3).normalized())) * gt
				if bone == thigh:
					var par: int = _parent[thigh]
					q = (((gl[par] as Basis).inverse() * gt2) if par != -1 else gt2).get_rotation_quaternion()
				else:
					var gc: Basis = gt2 * (gt.inverse() * (gl[calf] as Basis))
					var gc2 := Basis(Quaternion((gc * dl).normalized(), (want[1] as Vector3).normalized())) * gc
					q = (gt2.inverse() * gc2).get_rotation_quaternion()
			out.rotation_track_insert_key(tr, t, q)
	return out
