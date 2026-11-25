extends Node3D
## Les Stades de Dakar :
## 1. Stade Iba Mar Diop (Médina) : Stade historique rénové pour les JOJ Dakar 2026.
##    Pelouse officielle, piste d'athlétisme olympique 8 couloirs, tribunes nationales (Vert-Jaune-Rouge),
##    pylônes d'éclairage, buts réglementaires, ballon jouable et chronomètre de sprint.
## 2. Stade Me Abdoulaye Wade (Diamniadio) : Le grand stade olympique national de 50 000 places,
##    accessible via le TER depuis la Gare de Dakar ou en car express depuis Petersen.

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

# Emplacement du Stade Me Abdoulaye Wade (Zone spéciale Diamniadio / TER)
const WADE_ORIGIN := Vector3(9000, 0, 1800)
const WADE_RADIUS := 300.0

var main
var city
var player
var hud

var iba_mar_diop_pos := Vector3(-730.0, 0.2, -532.0)
var spots: Array = [] ## {id, pos, label}
var status := ""

# Ballon interactif du stade Iba Mar Diop
var _ball: RigidBody3D
var _ball_start_pos := Vector3.ZERO
var _goal_scored_cooldown := 0.0

# Chronomètre 100m sprint JOJ
var _sprinting := false
var _sprint_time := 0.0
var _sprint_start_pos := Vector3.ZERO
var _sprint_best := 11.45

# Éclairage nocturne
var _floodlights: Array = []


func _ready() -> void:
	if city and city.places.has("Stade Iba Mar Diop"):
		var p_info: Array = city.place_info.get("Stade Iba Mar Diop", [])
		if p_info.size() >= 11:
			iba_mar_diop_pos = Vector3(p_info[9], 0.2, p_info[10])
		else:
			iba_mar_diop_pos = city.places["Stade Iba Mar Diop"] + Vector3(0, 0, 30.0)

	_build_iba_mar_diop()
	_build_wade_stadium()


func _process(delta: float) -> void:
	if _goal_scored_cooldown > 0.0:
		_goal_scored_cooldown -= delta

	# Gestion du sprint 100m
	if _sprinting and player:
		_sprint_time += delta
		var dist: float = player.global_position.distance_to(_sprint_start_pos)
		if dist >= 100.0:
			_finish_sprint()
		elif hud and hud._label:
			hud._label.text = "⏱️ SPRINT 100m JOJ DAKAR 2026 : %.2f s (%.0f / 100 m)" % [_sprint_time, dist]

	# Vérification but au stade
	if _ball and is_instance_valid(_ball):
		var bp := _ball.global_position
		# But Ouest et But Est
		var b_rel := bp - iba_mar_diop_pos
		if absf(b_rel.z) < 4.0 and (b_rel.x > 42.0 and b_rel.x < 46.0 or b_rel.x < -42.0 and b_rel.x > -46.0):
			if _goal_scored_cooldown <= 0.0:
				_on_goal_scored()


func _on_goal_scored() -> void:
	_goal_scored_cooldown = 4.0
	GameState.notify.emit("⚽ BUUUUUUT AU STADE IBA MAR DIOP ! 🎉")
	Audio.play_sfx("coin")
	if player:
		GameState.earn(500, "Prime de but au Stade")
	# Replacer le ballon au centre après 2 secondes
	get_tree().create_timer(2.0).timeout.connect(func():
		if _ball and is_instance_valid(_ball):
			_ball.linear_velocity = Vector3.ZERO
			_ball.angular_velocity = Vector3.ZERO
			_ball.global_position = _ball_start_pos + Vector3(0, 0.4, 0)
	)


# --- Construction Stade Iba Mar Diop (Médina, JOJ 2026) -----------------------

func _build_iba_mar_diop() -> void:
	var c := iba_mar_diop_pos

	# 1. Piste olympique en tartan rouge 8 couloirs (110m x 75m)
	var track_mat := Mk.mat(Color("b33927"), 0.0) # Tartan rouge brique
	Mk.box(self, Vector3(114.0, 0.08, 76.0), c + Vector3(0, 0.04, 0), Color("b33927"))
	# Lignes blanches de couloirs
	for r in [72.0, 68.0, 64.0, 60.0]:
		Mk.box(self, Vector3(112.0, 0.09, 0.2), c + Vector3(0, 0.05, r / 2.0), Color("f4f4f0"))
		Mk.box(self, Vector3(112.0, 0.09, 0.2), c + Vector3(0, 0.05, -r / 2.0), Color("f4f4f0"))

	# 2. Pelouse centrale de football (88m x 54m)
	var g1 := Color("237a2e")
	var g2 := Color("2a8f37")
	var strips := 11
	var pw := 88.0
	var ph := 54.0
	for k in strips:
		var x_pos := -pw / 2.0 + (k + 0.5) * (pw / strips)
		Mk.box(self, Vector3(pw / strips, 0.1, ph), c + Vector3(x_pos, 0.06, 0), g1 if k % 2 == 0 else g2)

	# Lignes blanches réglementaires du terrain
	var line_col := Color("ffffff")
	Mk.box(self, Vector3(pw, 0.11, 0.3), c + Vector3(0, 0.07, ph / 2.0), line_col)
	Mk.box(self, Vector3(pw, 0.11, 0.3), c + Vector3(0, 0.07, -ph / 2.0), line_col)
	Mk.box(self, Vector3(0.3, 0.11, ph), c + Vector3(pw / 2.0, 0.07, 0), line_col)
	Mk.box(self, Vector3(0.3, 0.11, ph), c + Vector3(-pw / 2.0, 0.07, 0), line_col)
	Mk.box(self, Vector3(0.3, 0.11, ph), c + Vector3(0, 0.07, 0), line_col) # Ligne médiane
	# Rond central
	var center_circle := Mk.cyl(self, 8.0, 8.0, 0.11, c + Vector3(0, 0.07, 0), line_col, false, 28)

	# 3. Deux buts officiels avec filets
	for sx in [-1.0, 1.0]:
		var gx: float = float(c.x) + float(sx) * (pw / 2.0)
		var gz := c.z
		# Poteaux et transversale
		Mk.cyl(self, 0.08, 0.08, 2.5, Vector3(gx, 1.25, gz - 3.66), Color.WHITE, false, 8)
		Mk.cyl(self, 0.08, 0.08, 2.5, Vector3(gx, 1.25, gz + 3.66), Color.WHITE, false, 8)
		var crossbar := Mk.box(self, Vector3(0.16, 0.16, 7.4), Vector3(gx, 2.5, gz), Color.WHITE)
		# Filet blanc
		var net := Mk.box(self, Vector3(1.4, 2.4, 7.3), Vector3(gx + float(sx) * 0.7, 1.25, gz), Color(0.9, 0.9, 0.9, 0.45))

	# 4. Tribunes autour du terrain (aux couleurs Vert - Jaune - Rouge du Sénégal)
	var senegal_colors := [Color("00853f"), Color("fdef42"), Color("e31b23")]
	# Tribunes Nord et Sud (latérales, 96 m de long)
	for side in [-1.0, 1.0]:
		var tz: float = float(c.z) + float(side) * 44.0
		for step in 8:
			var sy := 0.6 + step * 0.75
			var sz: float = float(tz) + float(side) * (step * 1.5)
			var col: Color = senegal_colors[step % 3]
			Mk.box(self, Vector3(98.0, 0.7, 1.6), Vector3(c.x, sy, sz), col)
		# Toit de la tribune d'honneur au Sud
		if side > 0:
			Mk.box(self, Vector3(104.0, 0.4, 16.0), Vector3(c.x, 9.5, tz + 7.0), Color("2b2d42"))
			# Piliers de toit
			for px in [-45.0, -15.0, 15.0, 45.0]:
				Mk.cyl(self, 0.3, 0.3, 9.0, Vector3(c.x + px, 4.5, tz + 14.0), Color("8d99ae"), false, 8)

	# 5. Tribunes Virages Est et Ouest
	for side in [-1.0, 1.0]:
		var tx: float = float(c.x) + float(side) * 62.0
		for step in 6:
			var sy := 0.6 + step * 0.75
			var sx: float = float(tx) + float(side) * (step * 1.5)
			var col: Color = senegal_colors[(step + 1) % 3]
			Mk.box(self, Vector3(1.6, 0.7, 68.0), Vector3(sx, sy, c.z), col)

	# 6. Pylônes d'éclairage de stade (4 grands mâts aux angles)
	for px in [-1.0, 1.0]:
		for pz in [-1.0, 1.0]:
			var mast_pos: Vector3 = c + Vector3(float(px) * 58.0, 0, float(pz) * 48.0)
			# Pylône métallique blanc
			Mk.cyl(self, 0.6, 0.35, 18.0, mast_pos + Vector3(0, 9.0, 0), Color("e0e1dd"), false, 8)
			# Panneau de projecteurs
			Mk.box(self, Vector3(4.0, 2.0, 0.8), mast_pos + Vector3(0, 18.0, 0), Color("1b263b"))
			# Projecteur orienté vers le centre du terrain
			var spot := SpotLight3D.new()
			spot.position = mast_pos + Vector3(0, 18.0, 0)
			spot.light_energy = 4.0
			spot.light_color = Color("f8f9fa")
			spot.spot_range = 95.0
			spot.spot_angle = 50.0
			spot.look_at(c + Vector3(0, 1.0, 0))
			add_child(spot)
			_floodlights.append(spot)

	# 7. Grand Panneau Officiel JOJ Dakar 2026
	var sign_pos := c + Vector3(0, 8.5, -45.0)
	Mk.box(self, Vector3(36.0, 3.2, 0.4), sign_pos, Color("1d3557"))
	var sign_label := Mk.label(self, "🏅 DAKAR 2026 — STADE IBA MAR DIOP\nJEUX OLYMPIQUES DE LA JEUNESSE", sign_pos + Vector3(0, 0, 0.25), 48, Color("fdef42"))

	# 8. Ballon de football officiel au point central
	_ball_start_pos = c + Vector3(0, 0.4, 0)
	_build_soccer_ball(_ball_start_pos)

	# 9. Points d'interaction
	# Départ du sprint 100m
	var sprint_spot := c + Vector3(-50.0, 0.1, 31.0)
	spots.append({"id": "sprint_100m", "pos": sprint_spot, "label": "Chronométrer le 100 m sprint JOJ 2026"})
	var ring_sprint := Mk.cyl(self, 1.3, 1.3, 0.05, sprint_spot, Color("fdef42"), false, 20)
	Mk.label(self, "🏃 Départ 100 m Sprint JOJ", sprint_spot + Vector3(0, 2.2, 0), Mk.NAME_SIZE, Color("fdef42"))

	# Tribune d'honneur / Podium
	var podium_spot := c + Vector3(0, 1.2, 40.0)
	spots.append({"id": "podium_joj", "pos": podium_spot, "label": "Podium Olympique JOJ Dakar 2026"})
	Mk.box(self, Vector3(3.0, 0.8, 1.5), podium_spot + Vector3(0, 0.4, 0), Color("ffd166")) # Or (1er)
	Mk.box(self, Vector3(2.2, 0.5, 1.5), podium_spot + Vector3(-2.6, 0.25, 0), Color("e0e1dd")) # Argent (2e)
	Mk.box(self, Vector3(2.2, 0.35, 1.5), podium_spot + Vector3(2.6, 0.175, 0), Color("cd7f32")) # Bronze (3e)
	Mk.label(self, "🥇 1er", podium_spot + Vector3(0, 1.2, 0), Mk.NAME_SIZE, Color("ffd166"))

	# Entrée du stade / Navette pour le Stade Abdoulaye Wade
	var entry_spot := c + Vector3(-65.0, 0.3, 0)
	spots.append({"id": "aller_wade", "pos": entry_spot, "label": "Navette Express pour le Stade Abdoulaye Wade (500 FCFA)"})
	var ring_wade := Mk.cyl(self, 1.5, 1.5, 0.06, entry_spot, Color("00853f"), false, 24)
	Mk.label(self, "🚌 Navette Express\nStade Abdoulaye Wade (Diamniadio)", entry_spot + Vector3(0, 2.5, 0), Mk.SIGN_SIZE, Color.WHITE)


func _build_soccer_ball(pos: Vector3) -> void:
	_ball = RigidBody3D.new()
	_ball.name = "StadeBall"
	_ball.mass = 0.45 # Poids officiel ballon de foot
	_ball.gravity_scale = 1.0
	_ball.collision_layer = 4
	_ball.collision_mask = 1 | 2 | 4
	
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.32
	col.shape = sphere
	_ball.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	var s_mesh := SphereMesh.new()
	s_mesh.radius = 0.32
	s_mesh.height = 0.64
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffffff")
	mat.roughness = 0.3
	mat.metallic = 0.1
	s_mesh.material = mat
	mesh_inst.mesh = s_mesh
	_ball.add_child(mesh_inst)

	# Motifs pentagones noirs de ballon de foot
	for r in [Vector3(0.2, 0.15, 0), Vector3(-0.2, 0.15, 0), Vector3(0, -0.22, 0.15), Vector3(0, 0.22, -0.15)]:
		Mk.box(_ball, Vector3(0.12, 0.12, 0.04), r, Color("111111"))

	add_child(_ball)
	_ball.global_position = pos
	_ball_start_pos = pos


# --- Construction Stade Me Abdoulaye Wade (Diamniadio) ------------------------

func _build_wade_stadium() -> void:
	var c := WADE_ORIGIN

	# 1. Sol d'esplanade moderne
	Mk.box(self, Vector3(280.0, 0.2, 220.0), c, Color("343a40"))

	# 2. Pelouse hybride internationale (105m x 68m)
	var pw := 105.0
	var ph := 68.0
	Mk.box(self, Vector3(pw, 0.12, ph), c + Vector3(0, 0.15, 0), Color("1e6f28"))
	# Lignes blanches
	Mk.box(self, Vector3(pw, 0.14, 0.35), c + Vector3(0, 0.16, ph / 2.0), Color.WHITE)
	Mk.box(self, Vector3(pw, 0.14, 0.35), c + Vector3(0, 0.16, -ph / 2.0), Color.WHITE)
	Mk.box(self, Vector3(0.35, 0.14, ph), c + Vector3(pw / 2.0, 0.16, 0), Color.WHITE)
	Mk.box(self, Vector3(0.35, 0.14, ph), c + Vector3(-pw / 2.0, 0.16, 0), Color.WHITE)
	Mk.box(self, Vector3(0.35, 0.14, ph), c + Vector3(0, 0.16, 0), Color.WHITE)
	Mk.cyl(self, 9.15, 9.15, 0.14, c + Vector3(0, 0.16, 0), Color.WHITE, false, 32)

	# 3. Buts
	for sx in [-1.0, 1.0]:
		var gx: float = float(c.x) + float(sx) * (pw / 2.0)
		Mk.cyl(self, 0.08, 0.08, 2.5, Vector3(gx, 1.25, c.z - 3.66), Color.WHITE, false, 8)
		Mk.cyl(self, 0.08, 0.08, 2.5, Vector3(gx, 1.25, c.z + 3.66), Color.WHITE, false, 8)
		Mk.box(self, Vector3(0.16, 0.16, 7.4), Vector3(gx, 2.5, c.z), Color.WHITE)
		Mk.box(self, Vector3(1.5, 2.4, 7.3), Vector3(gx + float(sx) * 0.75, 1.25, c.z), Color(0.9, 0.9, 0.9, 0.4))

	# 4. Immenses tribunes 50 000 places (Double anneau étagé)
	var wade_colors := [Color("00853f"), Color("00853f"), Color("fdef42"), Color("e31b23"), Color("e31b23")]
	for side in [-1.0, 1.0]:
		var tz: float = float(c.z) + float(side) * 48.0
		for step in 14:
			var sy := 0.8 + step * 0.95
			var sz: float = float(tz) + float(side) * (step * 1.8)
			var col: Color = wade_colors[step % wade_colors.size()]
			Mk.box(self, Vector3(125.0, 0.9, 1.9), Vector3(c.x, sy, sz), col)
		# Toit géant en auvent blanc tendu
		Mk.box(self, Vector3(135.0, 0.6, 26.0), Vector3(c.x, 17.5, tz + float(side) * 14.0), Color("f8f9fa"))

	for side in [-1.0, 1.0]:
		var tx: float = float(c.x) + float(side) * 70.0
		for step in 12:
			var sy := 0.8 + step * 0.95
			var sx: float = float(tx) + float(side) * (step * 1.8)
			var col: Color = wade_colors[step % wade_colors.size()]
			Mk.box(self, Vector3(1.9, 0.9, 82.0), Vector3(sx, sy, c.z), col)

	# 5. Grand Enseigne "STADE ME ABDOULAYE WADE — DIAMNIADIO"
	var sign_wade := c + Vector3(0, 19.5, -65.0)
	Mk.box(self, Vector3(45.0, 3.8, 0.5), sign_wade, Color("0b2545"))
	Mk.label(self, "🇸🇳 STADE ME ABDOULAYE WADE — DIAMNIADIO\nREPAIRE DES LIONS DE LA TERANGA", sign_wade + Vector3(0, 0, 0.3), 52, Color("ffd166"))

	# 6. Quai du TER et retour à Dakar
	var ter_station_spot := c + Vector3(-95.0, 0.3, 0)
	spots.append({"id": "retour_dakar_ter", "pos": ter_station_spot, "label": "Gare TER Diamniadio — Retour à Dakar (Plateau) [Gratuit]"})
	var ring_ret := Mk.cyl(self, 1.8, 1.8, 0.06, ter_station_spot, Color("00a896"), false, 24)
	Mk.label(self, "🚆 GARE TER DIAMNIADIO\nRetour direct Gare de Dakar (Plateau)", ter_station_spot + Vector3(0, 2.6, 0), Mk.SIGN_SIZE, Color.WHITE)


# --- Interactions & Mini-Jeux -------------------------------------------------

func interact(id: String) -> void:
	match id:
		"sprint_100m":
			_start_sprint()
		"podium_joj":
			GameState.notify.emit("🏅 Félicitations ! Champion JOJ Dakar 2026 !")
			Audio.play_sfx("coin")
			GameState.earn(1000, "Prime Médaille d'Or JOJ")
		"aller_wade":
			if GameState.spend(500):
				GameState.notify.emit("🚌 En route pour le Stade Abdoulaye Wade...")
				if player:
					player.global_position = WADE_ORIGIN + Vector3(-85.0, 0.5, 0)
			else:
				GameState.notify.emit("Il te faut 500 FCFA pour le trajet.")
		"retour_dakar_ter":
			GameState.notify.emit("🚆 TER Dakar : Voyage express retour vers le Plateau...")
			if player and city and city.places.has("Gare de Dakar"):
				player.global_position = city.places["Gare de Dakar"] + Vector3(0, 0.5, 4.0)
			elif player:
				player.global_position = iba_mar_diop_pos + Vector3(-60.0, 0.5, 0)


func _start_sprint() -> void:
	if _sprinting:
		return
	_sprinting = true
	_sprint_time = 0.0
	if player:
		_sprint_start_pos = player.global_position
	GameState.notify.emit("🏁 PRÊT ? PARTEZ ! Cours tout droit sur 100 mètres !")
	Audio.play_sfx("alert")


func _finish_sprint() -> void:
	_sprinting = false
	var time_str := "%.2f" % _sprint_time
	if _sprint_time < _sprint_best:
		_sprint_best = _sprint_time
		GameState.notify.emit("🥇 NOUVEAU RECORD DU 100m JOJ : %s s ! (+2 000 FCFA)" % time_str)
		GameState.earn(2000, "Record 100m JOJ")
		Audio.play_sfx("coin")
	else:
		GameState.notify.emit("🏁 100m terminé en %s s ! (Record : %.2f s)" % [time_str, _sprint_best])


func contains(p: Vector3) -> bool:
	return p.distance_to(iba_mar_diop_pos) < 140.0 or p.distance_to(WADE_ORIGIN) < WADE_RADIUS


func get_hint() -> String:
	if not player or player.current_vehicle != null or player.riding != null:
		return ""
	var p: Vector3 = player.global_position
	if _ball and is_instance_valid(_ball) and p.distance_to(_ball.global_position) < 3.0:
		return "Tirer dans le ballon"
	var s = _spot_near(p)
	if s != null:
		return s["label"]
	return ""


func try_interact() -> bool:
	if not player or player.current_vehicle != null or player.riding != null:
		return false
	var p: Vector3 = player.global_position
	if _ball and is_instance_valid(_ball) and p.distance_to(_ball.global_position) < 3.0:
		_kick_ball()
		return true
	var s = _spot_near(p)
	if s != null:
		interact(s["id"])
		return true
	return false


func _kick_ball() -> void:
	if not _ball or not is_instance_valid(_ball) or not player:
		return
	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.25
	fwd = fwd.normalized()
	_ball.linear_velocity = fwd * 22.0
	Audio.play_sfx("coin", -6.0)
	GameState.notify.emit("⚽ Belle frappe !")


func _spot_near(p: Vector3):
	for s in spots:
		if p.distance_to(s["pos"]) < 4.0:
			return s
	return null
