extends Node3D
## Entreprises visitables (Jumbo, Jadida, Wave, Orange Money) : une vraie entrée sur le trottoir,
## puis un intérieur à plusieurs salles construit sous la ville :
##  - l'accueil (réceptionniste, chaises d'attente),
##  - la salle de travail : usine de production (Jumbo), entrepôt (Jadida) ou open-space (Wave, Orange Money)
##    avec le personnel à son poste,
##  - le bureau du patron : on s'assoit face à lui pour passer l'entretien et négocier son contrat
##    (journalier, CDD ou CDI, salaire). Voir employment.gd (_negotiate).

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

const ENTERPRISES := {
	"jumbo": {"title": "Usine Jumbo", "sub": "Bouillons et assaisonnements", "kind": "usine", "col": Color("d62828")},
	"jadida": {"title": "Jadida — siège et entrepôt", "sub": "Supermarchés", "kind": "entrepot", "col": Color("2a9d8f")},
	"wave": {"title": "Wave Sénégal", "sub": "Transferts d'argent", "kind": "bureau", "col": Color("1dc3f3")},
	"om": {"title": "Orange Money", "sub": "Agence régionale", "kind": "bureau", "col": Color("ff7900")},
}
const BASE := Vector3(0, -220, 0)
const W := 36.0 ## largeur intérieure (x : -18 → 18)
const D := 28.0 ## profondeur (z : -14 → 14 ; l'entrée est en z = +14)
const H := 5.5
const EXIT := Vector3(-10, 0, 12.6)
const CHAIR := Vector3(11, 0, 11.0) ## chaise du visiteur, face au patron
const BOSS_SEAT := Vector3(11, 0, 7.9)
const DESK_COUNTER := Vector3(-10, 0, 8.0) ## comptoir de l'accueil
const TALK := {
	"usine": ["« On produit des milliers de cubes par jour ! »", "« Casque obligatoire dans l'atelier, hein. »", "« Le patron est exigeant mais juste. »", "« Pause thé à 16 h, ataya pour tout le monde ! »"],
	"entrepot": ["« Les camions partent à 7 h pour livrer les supermarchés. »", "« Attention au chariot élévateur ! »", "« L'inventaire, c'est tous les vendredis. »"],
	"bureau": ["« Le réseau d'agents grandit chaque semaine. »", "« Ici on vérifie chaque transaction. »", "« Jamais de code secret au téléphone, c'est la règle ! »"],
}

var main
var inside_id := "" ## entreprise visitée ("" = dehors)
var _entrances := {} ## id → {pos, n, f}
var _sites := {} ## id → {root, origin, staff: [[pos, nom]], cubes: [Node3D]}
var _sitting := false


func handles(id: String) -> bool:
	return ENTERPRISES.has(id)


const FACADES := {"jumbo": Color("efe6d2"), "jadida": Color("f4f1ea"), "wave": Color("e8f1f6"), "om": Color("f6eee4")}


## Appelé par employment.gd : construit le siège de l'entreprise derrière le trottoir (n : vers l'intérieur
## du pâté de maisons) et renvoie la position de l'entrée (sur le trottoir, devant la porte).
func add_entrance(id: String, pos: Vector3, n: Vector3, f: Vector3) -> Vector3:
	n.y = 0.0
	n = n.normalized()
	f = Vector3(-n.z, 0, n.x)
	var basis := Basis(f, Vector3.UP, -n) # x : le long de la rue, -z : vers l'intérieur
	var front := Vector3(pos.x, 0.0, pos.z) + n * 0.8
	# Place libre : on essaie plusieurs tailles et décalages le long de la rue
	var pick := []
	for size in [Vector2(12, 9), Vector2(10, 8), Vector2(8, 7), Vector2(7, 6)]:
		for shift in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0]:
			var fr: Vector3 = front + f * shift
			var center: Vector3 = fr + n * (size.y / 2.0 + 0.1) + Vector3(0, 3.6, 0)
			if _free(center, basis, Vector3(size.x - 0.4, 6.4, size.y - 0.2)) and _off_street(fr, n, f, size):
				pick = [fr, size]
				break
		if not pick.is_empty():
			break
	if pick.is_empty():
		pick = [front, Vector2(7, 6)]
	var fr2: Vector3 = pick[0]
	var sz: Vector2 = pick[1]
	_build_house(id, fr2, n, f, sz.x, sz.y)
	var entrance: Vector3 = fr2 - n * 0.8 + Vector3(0, pos.y, 0)
	_entrances[id] = {"pos": entrance, "n": n, "f": f}
	return entrance


## Aucun coin ni milieu de côté du bâtiment sur la chaussée (les rues n'ont pas de collision)
func _off_street(fr: Vector3, n: Vector3, f: Vector3, size: Vector2) -> bool:
	for gx in [-0.5, 0.0, 0.5]:
		for gz in [0.0, 0.5, 1.0]:
			if main.city.in_roadway(fr + f * size.x * gx + n * size.y * gz, 0.2):
				return false
	return true


func _free(center: Vector3, basis: Basis, size: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	b.size = size
	q.shape = b
	q.transform = Transform3D(basis, center)
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Siège de l'entreprise : deux étages comme les maisons de la ville (façade enduite et fenêtres dessinées
## par le shader de la ville), toit-terrasse avec acrotère, bandeau aux couleurs de l'entreprise avec son nom,
## porte vitrée au centre.
func _build_house(id: String, front: Vector3, n: Vector3, f: Vector3, w: float, d: float) -> void:
	var e: Dictionary = ENTERPRISES[id]
	var col: Color = FACADES[id]
	var hgt := 6.4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var A := front - f * (w / 2.0)
	var B := front + f * (w / 2.0)
	var C := B + n * d
	var D := A + n * d
	var dirt := col.darkened(0.25)
	# Murs (alpha 1 : le shader dessine les fenêtres), bas sali comme les autres maisons
	for wall in [[A, B, -n], [B, C, f], [C, D, n], [D, A, -f]]:
		_wall(st, wall[0], wall[1], hgt, wall[2], dirt, col)
	# Acrotère (sans fenêtres)
	var par := Color(col.lightened(0.05), 0.5)
	for wall in [[A, B, -n], [B, C, f], [C, D, n], [D, A, -f]]:
		var up := Vector3(0, hgt, 0)
		_wall(st, wall[0] + up, wall[1] + up, 0.9, wall[2], par, par)
	var walls := st.commit()
	walls.surface_set_material(0, _mat(true))
	var roof_st := SurfaceTool.new()
	roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rc := Color(col.darkened(0.18), 0.5) # toit-terrasse en béton
	var up2 := Vector3(0, hgt, 0)
	_tri(roof_st, A + up2, B + up2, C + up2, Vector3.UP, rc)
	_tri(roof_st, A + up2, C + up2, D + up2, Vector3.UP, rc)
	var roof := roof_st.commit()
	roof.surface_set_material(0, _mat(false))
	for m in [walls, roof]:
		var mi := MeshInstance3D.new()
		mi.mesh = m
		add_child(mi)
	# Collision du bâtiment
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, hgt + 0.9, d)
	cs.shape = bs
	body.add_child(cs)
	body.global_transform = Transform3D(Basis(f, Vector3.UP, -n), front + n * (d / 2.0) + Vector3(0, (hgt + 0.9) / 2.0, 0))
	# Façade : porte vitrée, marquise, bandeau avec le nom (repère local : +Z vers la rue)
	var h := Node3D.new()
	add_child(h)
	h.global_position = front
	h.rotation.y = atan2(-n.x, -n.z)
	var brand: Color = e["col"]
	Mk.box(h, Vector3(2.6, 2.7, 0.12), Vector3(0, 1.35, 0.06), Color("343a40"))
	for s in [-0.62, 0.62]:
		Mk.box(h, Vector3(1.15, 2.5, 0.04), Vector3(s, 1.27, 0.13), Color(0.72, 0.86, 0.95, 0.55))
	Mk.box(h, Vector3(3.4, 0.12, 1.2), Vector3(0, 2.95, 0.6), brand)
	Mk.box(h, Vector3(3.6, 0.16, 1.6), Vector3(0, 0.08, 0.8), Color("bdb5a6"), true) # marche
	Mk.box(h, Vector3(w * 0.86, 1.0, 0.18), Vector3(0, 3.75, 0.1), brand)
	# Taille du texte : tient sur le bandeau (≈ 0,55 × taille × 1 cm par lettre)
	var title: String = e["title"].to_upper()
	var fit := int(w * 0.8 / (maxf(8.0, title.length()) * 0.0058))
	var name_lbl := Mk.label(h, title, Vector3(0, 3.82, 0.21), clampi(mini(fit, int(w * 7.5)), 30, 90), Color.WHITE, false)
	name_lbl.double_sided = false
	name_lbl.outline_size = 6
	var sub := Mk.label(h, e["sub"], Vector3(0, 3.42, 0.21), 22, Color(1, 1, 1, 0.92), false)
	sub.double_sided = false
	sub.outline_size = 0


func _wall(st: SurfaceTool, a: Vector3, b: Vector3, hgt: float, nrm: Vector3, bottom: Color, top: Color) -> void:
	var up := Vector3(0, hgt, 0)
	_tri_c(st, a, b, b + up, nrm, bottom, bottom, top)
	_tri_c(st, a, b + up, a + up, nrm, bottom, top, top)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
	_tri_c(st, a, b, c, nrm, col, col, col)


## Triangle orienté vers nrm (Godot : faces avant dans le sens horaire), une couleur par sommet
func _tri_c(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	if (b - a).cross(c - a).dot(nrm) > 0.0:
		var t := b
		b = c
		c = t
		var tc := cb
		cb = cc
		cc = tc
	for v in [[a, ca], [b, cb], [c, cc]]:
		st.set_color(v[1])
		st.set_normal(nrm)
		st.add_vertex(v[0])


static var _mats := {}


## Mêmes matériaux que la ville (textures photo, fenêtres, pluie, fenêtres allumées la nuit)
func _mat(facade: bool) -> ShaderMaterial:
	if _mats.has(facade):
		return _mats[facade]
	var m := ShaderMaterial.new()
	m.shader = load("res://world/shaders/city_facade.gdshader" if facade else "res://world/shaders/city_ground.gdshader")
	m.set_shader_parameter("detail_tex", load("res://world/textures/city_albedo.png"))
	m.set_shader_parameter("normal_tex", load("res://world/textures/city_normal.png"))
	_mats[facade] = m
	return m


func _process(delta: float) -> void:
	if inside_id == "":
		return
	# Ramené dehors sans passer par la porte (arrestation…) : on referme l'entreprise
	if main.interiors.inside != "ent_" + inside_id:
		_leave_state()
		return
	for cube in _sites[inside_id]["cubes"]:
		cube.position.x += 1.4 * delta
		if cube.position.x > 9.5:
			cube.position.x = -13.5


# --- Actions du joueur -----------------------------------------------------------------

func get_hint() -> String:
	var p = main.player
	if p.current_vehicle != null or p.riding != null:
		return ""
	if inside_id == "":
		var id := _near_entrance()
		return ("Entrer : " + ENTERPRISES[id]["title"]) if id != "" else ""
	if _sitting:
		return "Se lever"
	var o: Vector3 = _sites[inside_id]["origin"]
	var lp: Vector3 = p.global_position - o
	if Vector2(lp.x - EXIT.x, lp.z - EXIT.z).length() < 2.0:
		return "Sortir"
	if Vector2(lp.x - CHAIR.x, lp.z - CHAIR.z).length() < 1.6:
		return "S'asseoir face à %s (contrat de travail)" % main.employment.EMPLOYERS[inside_id]["name"]
	if Vector2(lp.x - DESK_COUNTER.x, lp.z - (DESK_COUNTER.z + 1.0)).length() < 2.2:
		return "Parler à l'accueil"
	for st in _sites[inside_id]["staff"]:
		if Vector2(lp.x - st[0].x, lp.z - st[0].z).length() < 1.9:
			return "Parler à %s" % st[1]
	return ""


func try_interact() -> bool:
	var h := get_hint()
	if h == "":
		return false
	if h.begins_with("Entrer"):
		_enter(_near_entrance())
	elif h == "Sortir":
		_exit()
	elif h == "Se lever":
		_stand_up()
	elif h.begins_with("S'asseoir"):
		_sit()
	elif h == "Parler à l'accueil":
		var boss: String = main.employment.EMPLOYERS[inside_id]["name"]
		GameState.notify.emit("Réceptionniste : « Bienvenue ! %s vous reçoit dans son bureau, au fond à droite. Asseyez-vous face à lui. »" % boss)
	else:
		GameState.notify.emit("%s : %s" % [h.trim_prefix("Parler à "), TALK[ENTERPRISES[inside_id]["kind"]].pick_random()])
	return true


func _near_entrance() -> String:
	var pp: Vector3 = main.player.global_position
	for id in _entrances:
		var d: Vector3 = _entrances[id]["pos"]
		if Vector2(pp.x - d.x, pp.z - d.z).length() < 2.6 and absf(pp.y - d.y) < 3.0:
			return id
	return ""


func _enter(id: String) -> void:
	var emp = main.employment
	if not emp.is_open(id):
		GameState.notify.emit("Le gardien : « C'est fermé. Revenez pendant les heures d'ouverture (%s). »" % emp.hours_text(id))
		return
	var door: Dictionary = _entrances[id]
	main.hud.fade_through(func():
		var site := _site(id)
		site["root"].visible = true
		site["root"].process_mode = Node.PROCESS_MODE_INHERIT
		inside_id = id
		main.interiors.inside = "ent_" + id
		main.player.interior_door = door["pos"] - door["n"] * 0.8
		main.player.global_position = site["origin"] + EXIT + Vector3(0, 0.3, -1.0)
		main.player.velocity = Vector3.ZERO
		main.player.model.rotation.y = 0.0
		main.camera_rig.yaw = 0.0
		main.camera_rig.global_position = main.player.global_position + Vector3(0, 1.6, 0)
		main.sun.visible = false
		GameState.notify.emit("Bienvenue : %s. L'accueil est à gauche, le bureau du patron au fond à droite." % ENTERPRISES[id]["title"]))


func _exit() -> void:
	var door: Dictionary = _entrances[inside_id]
	main.hud.fade_through(func():
		_leave_state()
		var out: Vector3 = door["pos"] - door["n"] * 0.8
		main.player.global_position = Vector3(out.x, 0.3, out.z)
		main.camera_rig.yaw = atan2(door["n"].x, door["n"].z)
		main.player.model.rotation.y = main.camera_rig.yaw
		main.camera_rig.global_position = main.player.global_position + Vector3(0, 1.6, 0))


func _leave_state() -> void:
	if inside_id != "" and _sites.has(inside_id):
		_sites[inside_id]["root"].visible = false
		_sites[inside_id]["root"].process_mode = Node.PROCESS_MODE_DISABLED
	if _sitting:
		_sitting = false
		main.player.frozen = false
	if main.interiors.inside.begins_with("ent_"):
		main.interiors.inside = ""
	main.player.interior_door = Vector3.ZERO
	main.sun.visible = true
	inside_id = ""


## S'asseoir face au patron : entretien, contrat, renégociation (employment._talk)
func _sit() -> void:
	var o: Vector3 = _sites[inside_id]["origin"]
	var p = main.player
	_sitting = true
	p.frozen = true
	p.velocity = Vector3.ZERO
	p.global_position = o + CHAIR + Vector3(0, 0.05, 0.1)
	p.model.rotation.y = 0.0 # regarde vers -Z : le patron
	if p.model.has_method("play_clip"):
		p.model.play_clip("sit", 0.3)
	main.camera_rig.yaw = deg_to_rad(35.0)
	main.employment._talk(inside_id)


## Test : -- --office=jumbo (dans les locaux, assis face au patron si sit)
func test_visit(id: String, sit: bool) -> void:
	var site := _site(id)
	site["root"].visible = true
	inside_id = id
	main.interiors.inside = "ent_" + id
	main.player.interior_door = _entrances[id]["pos"]
	main.player.global_position = site["origin"] + EXIT + Vector3(0, 0.3, -1.0)
	main.camera_rig.global_position = main.player.global_position + Vector3(0, 1.6, 0)
	main.sun.visible = false
	if sit:
		_sit()


## Test : place le joueur dans l'atelier (hall) ou devant le bureau du patron (office)
func test_spot(where: String) -> void:
	var o: Vector3 = _sites[inside_id]["origin"]
	if where == "hall":
		main.player.global_position = o + Vector3(-1.0, 0.3, 3.5)
	elif where == "office":
		main.player.global_position = o + Vector3(8.0, 0.3, 12.5)
	main.camera_rig.global_position = main.player.global_position + Vector3(0, 1.6, 0)


func _stand_up() -> void:
	var p = main.player
	_sitting = false
	p.frozen = false
	p.global_position += Vector3(0, 0.2, 0.9)
	if p.model.has_method("play_clip"):
		p.model.play_clip("idle", 0.3)


# --- Construction des locaux (à la première visite) ----------------------------------

func _site(id: String) -> Dictionary:
	if _sites.has(id):
		return _sites[id]
	var o := BASE + Vector3(ENTERPRISES.keys().find(id) * 60.0, 0, 0)
	var root := Node3D.new()
	root.position = o
	add_child(root)
	var site := {"root": root, "origin": o, "staff": [], "cubes": []}
	_sites[id] = site
	var e: Dictionary = ENTERPRISES[id]
	var col: Color = e["col"]
	var kind: String = e["kind"]
	var floor_col := Color("9a9a96") if kind != "bureau" else Color("cfc8bb")
	var wall := Color("eceae4")
	# Sol, plafond, murs extérieurs
	Mk.box(root, Vector3(W, 0.2, D), Vector3(0, -0.1, 0), floor_col, true)
	Mk.box(root, Vector3(W, 0.2, D), Vector3(0, H + 0.1, 0), Color("f4f4f0"), true)
	Mk.box(root, Vector3(W, H, 0.3), Vector3(0, H / 2.0, -D / 2.0), wall, true)
	Mk.box(root, Vector3(W, H, 0.3), Vector3(0, H / 2.0, D / 2.0), wall, true)
	Mk.box(root, Vector3(0.3, H, D), Vector3(-W / 2.0, H / 2.0, 0), wall.darkened(0.04), true)
	Mk.box(root, Vector3(0.3, H, D), Vector3(W / 2.0, H / 2.0, 0), wall.darkened(0.04), true)
	# Cloison accueil/bureau ↔ salle de travail (z = 6) : porte côté accueil, baie vitrée côté bureau
	Mk.box(root, Vector3(9.5, H, 0.2), Vector3(-13.25, H / 2.0, 6), wall, true)
	Mk.box(root, Vector3(10.5, H, 0.2), Vector3(-0.75, H / 2.0, 6), wall, true)
	Mk.box(root, Vector3(1.6, H, 0.2), Vector3(5.2, H / 2.0, 6), wall, true)
	Mk.box(root, Vector3(10.0, 1.0, 0.2), Vector3(11.0, 0.5, 6), wall, true)
	Mk.box(root, Vector3(10.0, 2.2, 0.06), Vector3(11.0, 2.1, 6), Color(0.7, 0.85, 0.95, 0.3), true)
	Mk.box(root, Vector3(10.0, H - 3.2, 0.2), Vector3(11.0, 3.2 + (H - 3.2) / 2.0, 6), wall, true)
	Mk.box(root, Vector3(2.0, H, 0.2), Vector3(17.0, H / 2.0, 6), wall, true)
	# Cloison accueil ↔ bureau (x = 4), porte en z 8 → 10
	Mk.box(root, Vector3(0.2, H, 2.0), Vector3(4, H / 2.0, 7.0), wall, true)
	Mk.box(root, Vector3(0.2, H, 4.0), Vector3(4, H / 2.0, 12.0), wall, true)
	Mk.box(root, Vector3(0.2, H - 2.4, 2.0), Vector3(4, 2.4 + (H - 2.4) / 2.0, 9.0), wall, true)
	# Porte de sortie
	Mk.box(root, Vector3(1.8, 2.5, 0.08), EXIT + Vector3(0, 1.25, 1.2), Color("343a40"))
	Mk.label(root, "SORTIE", EXIT + Vector3(0, 2.8, 1.1), 36, Color("2dc653"))
	_lights(root, kind)
	_reception(root, site, e, col)
	_office(root, site, id, col)
	match kind:
		"usine":
			_factory_floor(root, site, col)
		"entrepot":
			_warehouse_floor(root, site, col)
		"bureau":
			_open_space(root, site, col)
	return site


func _lights(root: Node3D, kind: String) -> void:
	for x in [-10.0, 0.0, 10.0]:
		for z in [-8.0, 0.0]:
			Mk.box(root, Vector3(3.0, 0.06, 0.4), Vector3(x, H - 0.05, z), Color.WHITE, false, Mk.mat(Color("fffbea"), 2.0))
	for lp in [Vector3(-9, H - 0.8, -4), Vector3(9, H - 0.8, -4), Vector3(-8, H - 1.0, 10), Vector3(11, H - 1.0, 10)]:
		var l := OmniLight3D.new()
		l.position = lp
		l.omni_range = 16.0 if lp.z < 0 else 9.0
		l.light_energy = 1.3
		l.light_color = Color("f3f6ff") if kind != "bureau" else Color("fff4e0")
		root.add_child(l)


func _staff(root: Node3D, site: Dictionary, model: String, pos: Vector3, yaw: float, clip: String, who: String) -> void:
	var h := Node3D.new()
	root.add_child(h)
	h.position = pos
	var c = RealCharacter.create(h, model, randi() % 997)
	c.rotation.y = yaw
	c.play_clip(clip, 0.0)
	site["staff"].append([pos, who])


func _reception(root: Node3D, site: Dictionary, e: Dictionary, col: Color) -> void:
	# Comptoir, réceptionniste, chaises d'attente, plantes, mur aux couleurs de l'entreprise
	Mk.box(root, Vector3(4.0, 1.1, 0.8), DESK_COUNTER + Vector3(0, 0.55, 0), Color("6b4f3a"), true)
	Mk.box(root, Vector3(4.1, 0.06, 0.9), DESK_COUNTER + Vector3(0, 1.13, 0), Color("e9ecef"))
	_staff(root, site, "femme_ville", DESK_COUNTER + Vector3(0, 0, -1.0), 0.0, "talk", "la réceptionniste")
	site["staff"].pop_back() # (on lui parle par « Parler à l'accueil »)
	Mk.box(root, Vector3(8.0, 2.2, 0.08), Vector3(-10, 2.6, 6.15), col)
	var t := Mk.label(root, e["title"].to_upper(), Vector3(-10, 3.0, 6.22), 60, Color.WHITE, false)
	t.double_sided = false
	var s := Mk.label(root, e["sub"], Vector3(-10, 2.2, 6.22), 30, Color(1, 1, 1, 0.9), false)
	s.double_sided = false
	for k in 4:
		Mk.box(root, Vector3(0.6, 0.45, 0.6), Vector3(-16.8, 0.23, 8.0 + k * 1.2), Color("1d3557"), true)
		Mk.box(root, Vector3(0.1, 0.5, 0.6), Vector3(-17.15, 0.7, 8.0 + k * 1.2), Color("1d3557"))
	for pp in [Vector3(-17, 0, 13), Vector3(3, 0, 13)]:
		Mk.cyl(root, 0.35, 0.28, 0.6, pp + Vector3(0, 0.3, 0), Color("bc6c25"), true, 10)
		Mk.sphere(root, 0.6, pp + Vector3(0, 1.2, 0), Color("2d6a4f"), Vector3(1, 1.3, 1))


func _office(root: Node3D, site: Dictionary, id: String, col: Color) -> void:
	var emp = main.employment
	var be: Dictionary = emp.EMPLOYERS[id]
	# Bureau en bois, fauteuil du patron, chaise du visiteur, bibliothèque, drapeau, ventilateur
	Mk.box(root, Vector3(2.6, 0.08, 1.2), Vector3(11, 0.78, 9.4), Color("5c4033"), true)
	Mk.box(root, Vector3(2.5, 0.74, 0.08), Vector3(11, 0.37, 9.95), Color("4a3326"))
	for s in [-1.0, 1.0]:
		Mk.box(root, Vector3(0.08, 0.74, 1.1), Vector3(11 + s * 1.2, 0.37, 9.4), Color("4a3326"))
	Mk.box(root, Vector3(0.55, 0.35, 0.05), Vector3(10.4, 1.0, 9.2), Color("111111"))
	Mk.box(root, Vector3(0.5, 0.3, 0.02), Vector3(10.4, 1.0, 9.23), Color.WHITE, false, Mk.mat(Color("9bd3ff"), 1.0))
	Mk.box(root, Vector3(0.4, 0.02, 0.3), Vector3(11.6, 0.83, 9.4), Color("f8f9fa"))
	Mk.box(root, Vector3(0.7, 1.2, 0.7), BOSS_SEAT + Vector3(0, 0.6, -0.35), Color("212529"))
	# Chaise du visiteur
	Mk.box(root, Vector3(0.55, 0.08, 0.55), CHAIR + Vector3(0, 0.45, 0), Color("6c757d"), true)
	Mk.box(root, Vector3(0.55, 0.6, 0.06), CHAIR + Vector3(0, 0.8, 0.28), Color("6c757d"))
	Mk.box(root, Vector3(0.5, 3.0, 2.8), Vector3(17.6, 1.5, 9.8), Color("6b4f3a"), true)
	for k in 4:
		Mk.box(root, Vector3(0.45, 0.4, 2.6), Vector3(17.5, 0.5 + k * 0.7, 9.8), [Color("1d3557"), Color("e63946"), Color("ffb703"), Color("2a9d8f")][k])
	Mk.cyl(root, 0.03, 0.03, 2.4, Vector3(16.6, 1.2, 7.0), Color("adb5bd"), false, 6)
	for k in 3:
		Mk.box(root, Vector3(0.03, 0.75, 0.38), Vector3(16.62, 2.0, 7.2 + k * 0.38), [Color("00853f"), Color("fdef42"), Color("e31b23")][k])
	Mk.box(root, Vector3(1.6, 1.0, 0.05), Vector3(11, 2.6, 13.8), col)
	var plate := Mk.label(root, "%s\n%s" % [be["name"], be["role"]], Vector3(11, 2.6, 13.75), 26, Color.WHITE, false)
	plate.rotation.y = PI
	plate.double_sided = false
	# Le patron, assis à son bureau, face à la chaise du visiteur
	var h := Node3D.new()
	root.add_child(h)
	h.position = BOSS_SEAT
	var boss = RealCharacter.create(h, be["model"], hash(id) % 997)
	boss.rotation.y = PI # regarde vers +Z (le visiteur)
	boss.play_clip("sit", 0.0)


## Usine Jumbo : cuves, tapis roulant avec les cubes qui défilent, machine d'emballage, palettes de cartons,
## chariot élévateur, consignes de sécurité, ouvriers à leur poste.
func _factory_floor(root: Node3D, site: Dictionary, col: Color) -> void:
	var steel := Color("aab4bd")
	for k in 3:
		var x := -13.0 + k * 5.0
		Mk.cyl(root, 1.4, 1.4, 4.0, Vector3(x, 2.2, -10.5), steel, true, 18)
		Mk.cyl(root, 1.45, 1.45, 0.2, Vector3(x, 4.25, -10.5), Color("8d99ae"), false, 18)
		Mk.box(root, Vector3(0.2, 0.2, 4.0), Vector3(x, 4.6, -8.5), Color("6c757d"))
		Mk.box(root, Vector3(0.6, 0.4, 0.05), Vector3(x, 1.8, -9.08), col)
	# Tapis roulant
	Mk.box(root, Vector3(24.0, 0.85, 1.1), Vector3(-2.0, 0.42, -3.0), Color("495057"), true)
	Mk.box(root, Vector3(24.0, 0.05, 0.95), Vector3(-2.0, 0.88, -3.0), Color("212529"))
	for k in 16:
		var cube := Mk.box(root, Vector3(0.28, 0.22, 0.28), Vector3(-13.5 + k * 1.45, 1.02, -3.0), col if k % 2 == 0 else Color("ffd60a"))
		site["cubes"].append(cube)
	Mk.box(root, Vector3(2.6, 2.2, 2.2), Vector3(11.5, 1.1, -3.0), Color("dee2e6"), true)
	Mk.label(root, "EMBALLAGE", Vector3(11.5, 2.5, -1.85), 30, Color("1d3557"), false)
	# Palettes de cartons prêts à livrer
	for px in [8.5, 11.5, 14.5]:
		for pz in [-12.0, -9.5]:
			Mk.box(root, Vector3(1.3, 0.15, 1.3), Vector3(px, 0.08, pz), Color("b08968"), true)
			for ly in 3:
				var crt := Mk.box(root, Vector3(1.2, 0.5, 1.2), Vector3(px, 0.42 + ly * 0.52, pz), Color("c9a37a"), true)
				Mk.box(crt, Vector3(1.22, 0.12, 1.22), Vector3.ZERO, col)
	# Chariot élévateur
	Mk.box(root, Vector3(1.2, 1.1, 2.0), Vector3(3.0, 0.75, -10.0), Color("f77f00"), true)
	Mk.box(root, Vector3(1.1, 0.08, 1.0), Vector3(3.0, 2.0, -10.4), Color("212529"))
	Mk.box(root, Vector3(0.12, 2.6, 0.12), Vector3(2.6, 1.3, -11.05), Color("343a40"))
	Mk.box(root, Vector3(0.12, 2.6, 0.12), Vector3(3.4, 1.3, -11.05), Color("343a40"))
	Mk.box(root, Vector3(0.9, 0.06, 1.0), Vector3(3.0, 0.3, -11.6), Color("6c757d"))
	# Lignes de sécurité jaunes et consignes
	for z in [-1.6, -4.4]:
		Mk.box(root, Vector3(26.0, 0.02, 0.12), Vector3(-2.0, 0.02, z), Color("ffd60a"))
	Mk.box(root, Vector3(4.5, 1.0, 0.05), Vector3(-6.0, 3.6, -13.8), Color("ffd60a"))
	Mk.label(root, "CASQUE ET BLOUSE OBLIGATOIRES", Vector3(-6.0, 3.6, -13.75), 22, Color("111111"), false)
	# Ouvriers
	_staff(root, site, "homme_ville", Vector3(-9.0, 0, -1.9), 0.0, "idle", "un ouvrier")
	_staff(root, site, "femme_jupe", Vector3(-4.0, 0, -1.9), 0.0, "talk", "une ouvrière")
	_staff(root, site, "homme_afro", Vector3(1.0, 0, -1.9), 0.0, "idle", "un ouvrier")
	_staff(root, site, "femme_robe", Vector3(6.0, 0, -1.9), 0.0, "idle", "une ouvrière")
	_staff(root, site, "homme_age", Vector3(-8.0, 0, -7.5), PI, "talk", "le chef d'atelier")
	_staff(root, site, "homme_tunique", Vector3(10.0, 0, -7.0), PI / 2.0, "idle", "un magasinier")


## Entrepôt Jadida : rayonnages hauts, palettes, chariot élévateur, magasiniers.
func _warehouse_floor(root: Node3D, site: Dictionary, col: Color) -> void:
	for rx in [-14.0, -8.0, -2.0, 4.0]:
		for side in [-1.0, 1.0]:
			Mk.box(root, Vector3(0.1, 4.2, 0.1), Vector3(rx + side * 1.9, 2.1, -12.5), Color("1d3557"), true)
			Mk.box(root, Vector3(0.1, 4.2, 0.1), Vector3(rx + side * 1.9, 2.1, -1.5), Color("1d3557"), true)
		for ly in 4:
			Mk.box(root, Vector3(3.9, 0.08, 11.0), Vector3(rx, 0.3 + ly * 1.25, -7.0), Color("f77f00"))
			for k in 6:
				var cc: Color = [Color("c9a37a"), col, Color("e9c46a"), Color("bde0fe")][(k + ly) % 4]
				Mk.box(root, Vector3(1.6, 0.8, 1.4), Vector3(rx + (k % 2) * 1.8 - 0.9, 0.75 + ly * 1.25, -11.0 + int(k / 2) * 3.8), cc)
	Mk.box(root, Vector3(1.2, 1.1, 2.0), Vector3(11.0, 0.75, -6.0), Color("ffd60a"), true)
	Mk.box(root, Vector3(0.12, 2.6, 0.12), Vector3(10.6, 1.3, -7.05), Color("343a40"))
	Mk.box(root, Vector3(0.12, 2.6, 0.12), Vector3(11.4, 1.3, -7.05), Color("343a40"))
	for pz in [-12.0, -9.0, -6.0]:
		Mk.box(root, Vector3(1.3, 0.15, 1.3), Vector3(15.5, 0.08, pz), Color("b08968"), true)
		Mk.box(root, Vector3(1.2, 1.0, 1.2), Vector3(15.5, 0.66, pz), Color("c9a37a"), true)
	_staff(root, site, "homme_afro", Vector3(-5.0, 0, -0.8), PI, "idle", "un magasinier")
	_staff(root, site, "homme_ville", Vector3(1.0, 0, -0.5), PI, "talk", "le chef d'équipe")
	_staff(root, site, "femme_jupe", Vector3(13.0, 0, -2.0), -PI / 2.0, "talk", "la responsable des stocks")


## Bureaux Wave / Orange Money : open-space, écrans aux couleurs de l'entreprise, salle de réunion, employés.
func _open_space(root: Node3D, site: Dictionary, col: Color) -> void:
	var models := ["homme_ville", "femme_ville", "homme_afro", "femme_robe", "homme_age", "femme_jupe"]
	var n := 0
	for row in 3:
		for k in 4:
			var dp := Vector3(-14.0 + k * 5.0, 0, -11.0 + row * 4.5)
			Mk.box(root, Vector3(2.2, 0.06, 1.0), dp + Vector3(0, 0.76, 0), Color("e9ecef"), true)
			Mk.box(root, Vector3(2.1, 0.74, 0.05), dp + Vector3(0, 0.37, -0.45), Color("adb5bd"))
			Mk.box(root, Vector3(0.6, 0.38, 0.04), dp + Vector3(0, 1.05, -0.3), Color("111111"))
			Mk.box(root, Vector3(0.55, 0.33, 0.02), dp + Vector3(0, 1.05, -0.27), Color.WHITE, false, Mk.mat(col.lightened(0.3), 0.9))
			Mk.box(root, Vector3(0.5, 0.45, 0.5), dp + Vector3(0, 0.23, 0.75), Color("343a40"))
			if (row + k) % 2 == 0 and n < 6:
				var h := Node3D.new()
				root.add_child(h)
				h.position = dp + Vector3(0, 0, 0.75)
				var c = RealCharacter.create(h, models[n], 300 + n)
				c.rotation.y = 0.0
				c.play_clip("sit", 0.0)
				site["staff"].append([dp + Vector3(0, 0, 1.3), ["une employée", "un employé"][n % 2]])
				n += 1
	# Salle de réunion vitrée
	Mk.box(root, Vector3(0.08, 2.6, 6.0), Vector3(9.0, 1.3, -10.0), Color(0.7, 0.85, 0.95, 0.3), true)
	Mk.box(root, Vector3(3.6, 0.08, 1.6), Vector3(13.5, 0.76, -10.0), Color("5c4033"), true)
	for s in [-1.0, 1.0]:
		for k in 3:
			Mk.box(root, Vector3(0.5, 0.45, 0.5), Vector3(12.3 + k * 1.2, 0.23, -10.0 + s * 1.2), Color("1d3557"))
	Mk.box(root, Vector3(3.0, 1.6, 0.05), Vector3(13.5, 2.0, -13.8), Color("f8f9fa"))
	Mk.label(root, "Objectif du mois :\n+15 % d'agents", Vector3(13.5, 2.0, -13.75), 24, col.darkened(0.3), false)
	Mk.cyl(root, 0.25, 0.25, 1.1, Vector3(-16.5, 0.55, -1.0), Color("dee2e6"), true, 10)
	Mk.cyl(root, 0.18, 0.18, 0.45, Vector3(-16.5, 1.35, -1.0), Color(0.6, 0.8, 1.0, 0.6), false, 10)
