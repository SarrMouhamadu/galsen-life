extends Node3D
## L'Arène nationale de lutte (Pikine). Elle est à une douzaine de kilomètres du Plateau, hors de la carte :
## c'est une zone à part, atteinte en taxi ou en car depuis la gare routière Petersen.
## Sur place : billet, combats de lutte avec bàkk, paris, et combat du joueur (mini-jeu de timing).

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

const ORIGIN := Vector3(9000, 0, 0)
const ZONE_RADIUS := 420.0
const RX := 52.0 ## demi-axes de l'ovale intérieur des tribunes
const RZ := 40.0
const TIERS := 14
const TICKET := 2000
const BET := 1000
const PRIZE := 25000
const TAXI_FARE := 4500
const CAR_FARE := 300
const WRESTLERS := [["lutteur1", "Tigre de Pikine"], ["lutteur2", "Lion de Guédiawaye"]]
const CHEERS := ["« Yaay boy ! » La foule chante !", "Les tam-tams du sabar résonnent dans l'arène !",
	"« Bàyyi ko ! » Le public est debout !", "Les griots chantent les louanges du lutteur !"]

var main
var city
var player
var hud
var spots: Array = [] ## {id, pos, label}
var status := ""
var _has_ticket := false
var lutte_busy := false ## une journée de lutte (scripts/world/lutte.gd) se déroule dans l'arène
var _state := ""
var _t := 0.0
var _w: Array = [] ## lutteurs
var _w_home: Array = []
var _winner := 0
var _bet_on := -1
var _fight := false
var _hits := 0
var _misses := 0
var _cursor := 0.0
var _cursor_dir := 1.0
var _zone := Vector2(0.4, 0.6)
var _bar: Control
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_ground()
	_build_stadium()
	_build_ring()
	_build_crowd()
	_build_plaza()
	for k in 2:
		var w = RealCharacter.create(self, WRESTLERS[k][0], -1)
		var home := ORIGIN + Vector3(-9.0 if k == 0 else 9.0, 0.3, 0)
		w.global_position = home
		w.rotation.y = -PI / 2.0 if k == 0 else PI / 2.0
		w.play_clip("idle", 0.0)
		Mk.label(w, WRESTLERS[k][1], Vector3(0, 2.2, 0), Mk.NAME_SIZE + 4, Color("ffd166"))
		_w.append(w)
		_w_home.append(home)
	# Départ du car pour Pikine à la gare routière Petersen
	if city.places.has("Gare routière Petersen"):
		var info: Array = city.place_info["Gare routière Petersen"]
		var pos: Vector3 = city.places["Gare routière Petersen"] + Vector3(info[7], 0, info[8]) * -12.0
		spots.append({"id": "car_aller", "pos": pos, "label": "Car pour Pikine — Arène nationale (%s)" % GameState.fcfa(CAR_FARE)})
		var ring := Mk.cyl(self, 1.4, 1.4, 0.06, pos + Vector3(0, 0.2, 0), Color("ffb703"), false, 24)
		ring.material_override = Mk.mat(Color(1, 0.72, 0.0, 0.8), 1.2, true)
		Mk.label(self, "Cars pour Pikine\nArène nationale — %s" % GameState.fcfa(CAR_FARE), pos + Vector3(0, 2.8, 0), Mk.SIGN_SIZE, Color.WHITE)


func contains(p: Vector3) -> bool:
	return Vector2(p.x - ORIGIN.x, p.z - ORIGIN.z).length() < ZONE_RADIUS


# --- Construction --------------------------------------------------------------------

class Mesher:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	func tri(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		if (b - a).cross(d - a).dot(nrm) > 0.0:
			var t := b
			b = d
			d = t
		v.append_array(PackedVector3Array([a, b, d]))
		n.append_array(PackedVector3Array([nrm, nrm, nrm]))
		c.append_array(PackedColorArray([col, col, col]))

	## Pavé de centre p, demi-tailles he, tourné de yaw autour de Y
	func box(p: Vector3, he: Vector3, yaw: float, col: Color) -> void:
		var bs := Basis(Vector3.UP, yaw)
		var axes := [bs.x * he.x, Vector3.UP * he.y, bs.z * he.z]
		for i in 3:
			for s in [-1.0, 1.0]:
				var f: Vector3 = axes[i] * s
				var u: Vector3 = axes[(i + 1) % 3]
				var w: Vector3 = axes[(i + 2) % 3]
				var fc: Vector3 = p + f
				tri(fc - u - w, fc + u - w, fc + u + w, f.normalized(), col)
				tri(fc - u - w, fc + u + w, fc - u + w, f.normalized(), col)

	func build(parent: Node3D, collide: bool) -> void:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 0.9
		mesh.surface_set_material(0, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		parent.add_child(mi)
		if collide:
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(v)
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)


func _ellipse(a: float, rx: float, rz: float) -> Vector3:
	return ORIGIN + Vector3(cos(a) * rx, 0, sin(a) * rz)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ZONE_RADIUS * 2.0, 2.0, ZONE_RADIUS * 2.0)
	cs.shape = box
	cs.position = ORIGIN + Vector3(0, -1, 0)
	body.add_child(cs)
	Mk.box(self, Vector3(ZONE_RADIUS * 2.0, 0.05, ZONE_RADIUS * 2.0), ORIGIN + Vector3(0, 0.0, 0), Color("cdb68a"))
	Mk.box(self, Vector3(60, 0.06, 40), ORIGIN + Vector3(0, 0.03, RZ + 60), Color("3a3a3c")) # parking
	for k in 4:
		var a := k * TAU / 4.0
		var w := Mk.box(self, Vector3(ZONE_RADIUS * 2.0, 6, 2), ORIGIN + Vector3(cos(a), 0, sin(a)) * (ZONE_RADIUS - 5.0) + Vector3(0, 3, 0), Color("d8d2c0"), true)
		w.rotation.y = a + PI / 2.0


func _build_stadium() -> void:
	var m := Mesher.new()
	var seg := 72
	var colors := [Color("00853f"), Color("fdef42"), Color("e31b23")]
	for k in TIERS:
		var rx := RX + 1.5 + k * 1.25
		var rz := RZ + 1.5 + k * 1.25
		var y := 0.6 + k * 0.75
		for s in seg:
			var a0 := s * TAU / seg
			var a1 := (s + 1) * TAU / seg
			var am := (a0 + a1) / 2.0
			# Allée d'entrée au sud (côté +Z)
			if absf(wrapf(am - PI / 2.0, -PI, PI)) < 0.16:
				continue
			var p0 := _ellipse(a0, rx, rz)
			var p1 := _ellipse(a1, rx, rz)
			var mid := (p0 + p1) / 2.0
			var d := p1 - p0
			var col: Color = colors[int(am / TAU * 3.0) % 3]
			if k % 4 == 3:
				col = Color("e9e4d8") # escaliers et allées
			m.box(Vector3(mid.x, y / 2.0, mid.z), Vector3(d.length() / 2.0 + 0.05, y / 2.0, 0.65), -atan2(d.z, d.x), col.darkened(0.1 * (k % 2)))
	# Façade extérieure avec arcades et bandeau vert
	var orx := RX + 1.5 + TIERS * 1.25 + 1.5
	var orz := RZ + 1.5 + TIERS * 1.25 + 1.5
	var h := 0.6 + TIERS * 0.75 + 3.0
	for s in seg:
		var a0 := s * TAU / seg
		var a1 := (s + 1) * TAU / seg
		var am := (a0 + a1) / 2.0
		if absf(wrapf(am - PI / 2.0, -PI, PI)) < 0.12:
			continue
		var p0 := _ellipse(a0, orx, orz)
		var p1 := _ellipse(a1, orx, orz)
		var mid := (p0 + p1) / 2.0
		var d := p1 - p0
		var yaw := -atan2(d.z, d.x)
		m.box(Vector3(mid.x, h / 2.0, mid.z), Vector3(d.length() / 2.0 + 0.05, h / 2.0, 0.6), yaw, Color("efeae0"))
		m.box(Vector3(mid.x, h - 1.2, mid.z), Vector3(d.length() / 2.0 + 0.1, 0.6, 0.7), yaw, Color("00853f"))
		if s % 2 == 0:
			var out := (mid - ORIGIN).normalized()
			m.box(Vector3(mid.x, 2.2, mid.z) + out * 0.62, Vector3(1.0, 2.0, 0.05), yaw, Color("3a3f48")) # arcade
	# Auvent au-dessus de la tribune nord
	for s in 18:
		var a := PI * 1.25 + s * (PI * 0.5 / 18.0)
		var p := _ellipse(a, orx - 6.0, orz - 6.0)
		m.box(Vector3(p.x, h + 2.0, p.z), Vector3(3.2, 0.25, 7.0), -a + PI / 2.0, Color("bfc5cc"))
	m.build(self, true)
	# Pylônes d'éclairage
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var p := _ellipse(a, orx + 4.0, orz + 4.0)
		Mk.cyl(self, 0.4, 0.6, 34.0, p + Vector3(0, 17, 0), Color("8d9196"), true, 8)
		var lamp := Mk.box(self, Vector3(4, 2.2, 0.8), p + Vector3(0, 34.5, 0), Color("fff8dc"), false, Mk.mat(Color("fff8dc"), 2.5))
		lamp.look_at(ORIGIN + Vector3(0, 0, 0.01), Vector3.UP)
	var light := OmniLight3D.new()
	light.omni_range = 90.0
	light.light_energy = 1.4
	light.position = ORIGIN + Vector3(0, 30, 0)
	add_child(light)


func _build_ring() -> void:
	Mk.cyl(self, 14.0, 14.5, 0.35, ORIGIN + Vector3(0, 0.17, 0), Color("e6cc8f"), true, 40)
	for k in 40:
		var a := k * TAU / 40.0
		var bag := Mk.box(self, Vector3(2.2, 0.5, 0.7), ORIGIN + Vector3(cos(a) * 14.6, 0.45, sin(a) * 14.6), Color("c8a96a"), true)
		bag.rotation.y = -a + PI / 2.0
	Mk.label(self, "ARÈNE NATIONALE", ORIGIN + Vector3(0, 16, -(RZ + 12)), 400, Color("fdef42"))


## Foule : silhouettes colorées sur les gradins (un seul maillage multiple)
func _build_crowd() -> void:
	var cols := [Color("1d4ed8"), Color("f59e0b"), Color("10b981"), Color("e11d48"), Color("f8fafc"), Color("7c3aed"), Color("fdef42"), Color("00853f")]
	var xforms: Array = []
	var colors: Array = []
	for k in TIERS:
		if k % 4 == 3:
			continue
		var rx := RX + 1.5 + k * 1.25
		var rz := RZ + 1.5 + k * 1.25
		var y := 0.6 + k * 0.75
		var n := int(TAU * sqrt((rx * rx + rz * rz) / 2.0) / 0.8)
		for s in n:
			if _rng.randf() < 0.18:
				continue
			var a := s * TAU / n
			if absf(wrapf(a - PI / 2.0, -PI, PI)) < 0.18:
				continue
			var p := _ellipse(a, rx, rz) + Vector3(0, y + 0.55, 0)
			var t := Transform3D(Basis(Vector3.UP, -a - PI / 2.0).scaled(Vector3.ONE * _rng.randf_range(0.9, 1.1)), p)
			xforms.append(t)
			colors.append(cols[_rng.randi() % cols.size()])
	var cap := CapsuleMesh.new()
	cap.radius = 0.23
	cap.height = 1.1
	cap.radial_segments = 6
	cap.rings = 2
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cap
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mmi.material_override = mat
	add_child(mmi)


func _build_plaza() -> void:
	var gate := ORIGIN + Vector3(0, 0, RZ + 1.5 + TIERS * 1.25 + 6.0)
	Mk.label(self, "ARÈNE NATIONALE — Pikine", gate + Vector3(0, 14, 0), 260, Color.WHITE)
	# Guichet
	var g := gate + Vector3(10, 0, 4)
	Mk.box(self, Vector3(3, 2.6, 2), g + Vector3(0, 1.3, 0), Color("00853f"), true)
	Mk.label(self, "Guichet\nBillet : %s" % GameState.fcfa(TICKET), g + Vector3(0, 3.4, 0), 60, Color("fdef42"))
	spots.append({"id": "ticket", "pos": g + Vector3(0, 0, 1.8), "label": "Acheter un billet (%s)" % GameState.fcfa(TICKET)})
	spots.append({"id": "taxi_retour", "pos": gate + Vector3(-12, 0, 18), "label": "Taxi pour Dakar (%s)" % GameState.fcfa(TAXI_FARE)})
	spots.append({"id": "car_retour", "pos": gate + Vector3(8, 0, 22), "label": "Car pour Petersen (%s)" % GameState.fcfa(CAR_FARE)})
	Mk.label(self, "Taxis pour Dakar", gate + Vector3(-12, 3, 18), 60, Color("ffc300"))
	Mk.label(self, "Cars pour Petersen", gate + Vector3(8, 3, 22), 60, Color("ffb703"))
	# Dans l'arène : regarder, parier, combattre
	spots.append({"id": "watch", "pos": ORIGIN + Vector3(0, 0, 17.5), "label": "Regarder un combat"})
	spots.append({"id": "bet", "pos": ORIGIN + Vector3(-6, 0, 17.5), "label": "Parier %s sur un lutteur" % GameState.fcfa(BET)})
	spots.append({"id": "fight", "pos": ORIGIN + Vector3(6, 0, 17.5), "label": "Combattre (prime %s)" % GameState.fcfa(PRIZE)})
	for s in spots:
		if s["id"] in ["watch", "bet", "fight", "ticket", "taxi_retour", "car_retour"]:
			var ring := Mk.cyl(self, 1.2, 1.2, 0.06, s["pos"] + Vector3(0, 0.2, 0), Color("ffd166"), false, 24)
			ring.material_override = Mk.mat(Color(1, 0.82, 0.4, 0.8), 1.2, true)


# --- Interactions ----------------------------------------------------------------------

func _spot_near(pp: Vector3) -> Variant:
	for s in spots:
		if Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length() < 2.8:
			return s
	return null


func get_hint() -> String:
	if _fight:
		return "Placer ta prise !"
	if player.current_vehicle != null or player.riding != null:
		return ""
	var s = _spot_near(player.global_position)
	if s == null:
		return ""
	if s["id"] in ["watch", "bet", "fight"] and not _has_ticket:
		return "Il faut un billet (guichet à l'entrée)"
	if s["id"] in ["watch", "bet", "fight"] and (_state != "" or lutte_busy):
		return ""
	return s["label"]


func try_interact() -> bool:
	if _fight:
		_press()
		return true
	if player.current_vehicle != null or player.riding != null:
		return false
	var s = _spot_near(player.global_position)
	if s == null:
		return false
	match s["id"]:
		"car_aller":
			travel_to_arena("car")
		"ticket":
			if _has_ticket:
				GameState.notify.emit("Tu as déjà ton billet.")
			elif GameState.spend(TICKET):
				_has_ticket = true
				GameState.notify.emit("Billet acheté (-%s). Bon combat !" % GameState.fcfa(TICKET))
			else:
				GameState.notify.emit("Il te faut %s pour entrer." % GameState.fcfa(TICKET))
		"taxi_retour":
			_travel_back(TAXI_FARE, city.places["Place de l'Indépendance"], "Le taxi te ramène au Plateau par l'autoroute.")
		"car_retour":
			_travel_back(CAR_FARE, city.places["Gare routière Petersen"], "Le car te dépose à la gare routière Petersen.")
		"watch", "bet", "fight":
			if not _has_ticket:
				GameState.notify.emit("Achète d'abord un billet au guichet.")
			elif _state != "" or lutte_busy:
				GameState.notify.emit("Un combat est déjà en cours !")
			elif s["id"] == "watch":
				_start_combat()
			elif s["id"] == "bet":
				hud.show_choices("Parier %s — qui va gagner ?" % GameState.fcfa(BET), [
					[WRESTLERS[0][1], _place_bet.bind(0)], [WRESTLERS[1][1], _place_bet.bind(1)]], func(): pass)
			else:
				_start_player_fight()
	return true


func _place_bet(k: int) -> void:
	if not GameState.spend(BET):
		GameState.notify.emit("Il te faut %s pour parier." % GameState.fcfa(BET))
		return
	_bet_on = k
	GameState.notify.emit("Pari de %s sur %s. Le combat commence !" % [GameState.fcfa(BET), WRESTLERS[k][1]])
	_start_combat()


# --- Voyages -------------------------------------------------------------------------------

func travel_to_arena(by: String) -> bool:
	if GameState.wanted > 0:
		GameState.notify.emit("Les chauffeurs refusent : la police te recherche !")
		return false
	var fare := CAR_FARE if by == "car" else TAXI_FARE
	if not GameState.spend(fare):
		GameState.notify.emit("Il te faut %s pour aller à Pikine." % GameState.fcfa(fare))
		return false
	hud.fade_through(func():
		player.leave_any_vehicle()
		player.global_position = ORIGIN + Vector3(-4, 0.5, RZ + 1.5 + TIERS * 1.25 + 22.0)
		GameState.game_minutes = fmod(GameState.game_minutes + 40.0, 1440.0)
		GameState.notify.emit("Après 40 minutes de route vers Pikine... Bienvenue à l'Arène nationale !"))
	return true


func _travel_back(fare: int, dest: Vector3, msg: String) -> void:
	if not GameState.spend(fare):
		GameState.notify.emit("Il te faut %s pour rentrer." % GameState.fcfa(fare))
		return
	_has_ticket = false
	hud.fade_through(func():
		player.global_position = dest + Vector3(0, 0.5, 0)
		GameState.game_minutes = fmod(GameState.game_minutes + 40.0, 1440.0)
		GameState.notify.emit(msg))


# --- Combats ---------------------------------------------------------------------------------

func _start_combat() -> void:
	_state = "bakk"
	_t = 0.0
	_winner = _rng.randi() % 2
	for k in 2:
		_w[k].global_position = _w_home[k]
		_w[k].play_clip("dance", 0.3)
	Audio.set_radio_track(4)
	Audio.set_radio(true)
	GameState.notify.emit("Les lutteurs font leur bàkk au son du sabar !")


func _process(delta: float) -> void:
	if _fight:
		_update_fight(delta)
		return
	if _state == "":
		status = "PIKINE — Arène nationale%s" % ("" if _has_ticket else " — achète ton billet au guichet") if contains(player.get_world_position()) else ""
		return
	_t += delta
	match _state:
		"bakk":
			status = "BÀKK — les lutteurs dansent et défient leur adversaire"
			if _t > 7.0:
				_state = "approche"
				_t = 0.0
				for k in 2:
					_w[k].play_clip("walk", 0.3, 0.9)
		"approche":
			status = "Les lutteurs s'avancent au centre de l'arène..."
			for k in 2:
				var target := ORIGIN + Vector3(-0.55 if k == 0 else 0.55, 0.3, 0)
				_w[k].global_position = _w[k].global_position.move_toward(target, delta * 1.4)
			if _t > 6.0:
				_state = "corps"
				_t = 0.0
				for k in 2:
					_w[k].play_clip("push", 0.3)
				GameState.notify.emit("Empoignade ! " + CHEERS.pick_random())
		"corps":
			status = "CORPS À CORPS — %s contre %s" % [WRESTLERS[0][1], WRESTLERS[1][1]]
			var sway := sin(_t * 1.7) * 0.25
			_w[0].global_position = ORIGIN + Vector3(-0.55 + sway, 0.3, 0)
			_w[1].global_position = ORIGIN + Vector3(0.55 + sway, 0.3, 0)
			if fmod(_t, 3.0) < delta:
				GameState.notify.emit(CHEERS.pick_random())
			if _t > 8.0:
				_state = "fin"
				_t = 0.0
				var loser := 1 - _winner
				_w[loser].play_clip("fall", 0.15)
				_w[_winner].play_clip("dance", 0.3)
				GameState.notify.emit("« Daanu na ! » %s est à terre : victoire de %s !" % [WRESTLERS[loser][1], WRESTLERS[_winner][1]])
				if _bet_on != -1:
					if _bet_on == _winner:
						GameState.add_money(BET * 2, "Pari gagné sur %s" % WRESTLERS[_winner][1])
					else:
						GameState.notify.emit("Pari perdu... Ce sera pour la prochaine fois !")
					_bet_on = -1
		"fin":
			status = "Victoire de %s ! La foule exulte." % WRESTLERS[_winner][1]
			if _t > 7.0:
				_reset_wrestlers()


func _reset_wrestlers() -> void:
	_state = ""
	Audio.set_radio(false)
	for k in 2:
		_w[k].visible = true
		_w[k].global_position = _w_home[k]
		_w[k].play_clip("idle", 0.3)


# --- Combat du joueur : mini-jeu de timing ------------------------------------------------

func _start_player_fight() -> void:
	_fight = true
	_state = "joueur"
	_hits = 0
	_misses = 0
	_cursor = 0.0
	_new_zone()
	player.frozen = true
	player.global_position = ORIGIN + Vector3(-0.6, 0.3, 0)
	player.model.rotation.y = -PI / 2.0
	player.model.play_clip("push", 0.3)
	_w[1].global_position = ORIGIN + Vector3(0.6, 0.3, 0)
	_w[1].play_clip("push", 0.3)
	_w[0].visible = false
	Audio.set_radio_track(4)
	Audio.set_radio(true)
	_build_bar()
	GameState.notify.emit("Combat contre %s ! Appuie sur ACTION quand le curseur est dans la zone verte. 3 prises pour gagner !" % WRESTLERS[1][1])


func _new_zone() -> void:
	var w := _rng.randf_range(0.12, 0.2) - _hits * 0.02
	var c := _rng.randf_range(0.2, 0.8)
	_zone = Vector2(c - w / 2.0, c + w / 2.0)


func _build_bar() -> void:
	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.custom_minimum_size = Vector2(520, 60)
	_bar.position = Vector2(-260, -260)
	_bar.draw.connect(_draw_bar)
	hud._root.add_child(_bar)


func _draw_bar() -> void:
	var w := 520.0
	_bar.draw_rect(Rect2(0, 0, w, 40), Color(0, 0, 0, 0.6))
	_bar.draw_rect(Rect2(_zone.x * w, 0, (_zone.y - _zone.x) * w, 40), Color("2dc653"))
	_bar.draw_rect(Rect2(_cursor * w - 3, -6, 6, 52), Color.WHITE)
	_bar.draw_string(_bar.get_theme_default_font(), Vector2(0, 62), "Prises : %d / 3      Ratés : %d / 3" % [_hits, _misses], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


func _update_fight(delta: float) -> void:
	_cursor += _cursor_dir * delta * (0.9 + _hits * 0.25)
	if _cursor > 1.0:
		_cursor = 1.0
		_cursor_dir = -1.0
	elif _cursor < 0.0:
		_cursor = 0.0
		_cursor_dir = 1.0
	status = "COMBAT — %s : prends-le au bon moment !" % WRESTLERS[1][1]
	if _bar:
		_bar.queue_redraw()


func _press() -> void:
	if _cursor >= _zone.x and _cursor <= _zone.y:
		_hits += 1
		_w[1].play_clip("hit", 0.1)
		GameState.notify.emit("Belle prise ! " + CHEERS.pick_random())
		if _hits >= 3:
			_end_player_fight(true)
			return
		_new_zone()
		_w[1].play_clip("push", 0.4)
	else:
		_misses += 1
		player.model.play_clip("hit", 0.1)
		GameState.notify.emit("Raté ! %s te bouscule." % WRESTLERS[1][1])
		if _misses >= 3:
			_end_player_fight(false)
			return
		player.model.play_clip("push", 0.4)


func _end_player_fight(won: bool) -> void:
	_fight = false
	if _bar:
		_bar.queue_free()
		_bar = null
	if won:
		_w[1].play_clip("fall", 0.15)
		player.model.play_clip("dance", 0.3)
		GameState.add_money(PRIZE, "Victoire à l'Arène nationale !")
		GameState.notify.emit("« Daanu na ! » Tu as fait tomber %s ! La foule t'acclame !" % WRESTLERS[1][1])
	else:
		player.model.play_clip("fall", 0.15)
		_w[1].play_clip("dance", 0.3)
		GameState.damage(15.0, "« Dama daanu... » Tu es tombé. Il faudra t'entraîner !")
	_state = "fin_joueur"
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		player.frozen = false
		player.global_position = ORIGIN + Vector3(0, 0.5, 18.0)
		_reset_wrestlers())
