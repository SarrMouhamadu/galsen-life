extends Node3D
## Le TER (Train Express Régional de Dakar).
## Ligne ferroviaire moderne reliant la Gare historique de Dakar (Plateau) aux grands pôles :
## Colobane, Hann, Pikine (Arène Nationale) et Diamniadio (Stade Me Abdoulaye Wade).
## Comprend le quai de gare, les doubles voies ferrées, la rame Alstom Coradia Polyvalent
## aux couleurs officielles du TER Dakar (Bleu marine, Blanc et Orange solaire),
## et le voyage à bord haute vitesse.

const Mk = preload("res://scripts/util/mk.gd")

var city
var player
var hud
var main

var station_pos := Vector3(692.0, 0.2, -50.0)
var spots: Array = [] ## {id, pos, label}

# La rame du TER
var _train_node: Node3D
var _train_pos_t := 0.0 ## progression 0.0 à 1.0 le long des voies
var _train_speed := 0.0
var _train_state := "station" ## "station", "departing", "running", "arriving"
var _dwell_timer := 8.0
var _riding := false

# Points de rails (départ de la Gare de Dakar vers le Nord)
var _rail_pts := PackedVector3Array()


func _ready() -> void:
	if city and city.places.has("Gare de Dakar"):
		station_pos = city.places["Gare de Dakar"] + Vector3(12.0, 0, -5.0)

	_build_tracks()
	_build_station_platform()
	_build_train()


func _process(delta: float) -> void:
	if _rail_pts.size() < 2:
		return

	# Logique de circulation du TER
	match _train_state:
		"station":
			_dwell_timer -= delta
			_train_speed = 0.0
			if _dwell_timer <= 0.0:
				_train_state = "departing"
				Audio.play_sfx("alert")
				if _riding:
					GameState.notify.emit("🚆 TER Dakar : Fermeture automatique des portes... Attention au départ !")
		"departing":
			_train_speed = move_toward(_train_speed, 18.0, 6.0 * delta)
			_advance_train(delta)
			if _train_speed >= 18.0:
				_train_state = "running"
		"running":
			_train_speed = 28.0 # Grande vitesse
			_advance_train(delta)
			if _train_pos_t >= 0.85:
				_train_state = "arriving"
		"arriving":
			_train_speed = move_toward(_train_speed, 0.0, 8.0 * delta)
			_advance_train(delta)
			if _train_pos_t >= 1.0 or _train_speed <= 0.1:
				_train_state = "station"
				_dwell_timer = 12.0
				_train_pos_t = 0.0
				_update_train_transform()
				if _riding:
					GameState.notify.emit("🚆 TER Dakar : Terminus Gare de Dakar. Tout le monde descend !")
					_exit_train()


func _advance_train(delta: float) -> void:
	var total_len := 420.0 # Longueur de la ligne modélisée
	_train_pos_t += (_train_speed * delta) / total_len
	if _train_pos_t > 1.0:
		_train_pos_t = 1.0
	_update_train_transform()


func _update_train_transform() -> void:
	if _rail_pts.size() < 2 or not _train_node:
		return
	var idx := int(_train_pos_t * float(_rail_pts.size() - 2))
	var frac := fmod(_train_pos_t * float(_rail_pts.size() - 2), 1.0)
	var p1: Vector3 = _rail_pts[idx]
	var p2: Vector3 = _rail_pts[idx + 1]
	_train_node.global_position = p1.lerp(p2, frac) + Vector3(0, 0.45, 0)
	var dir := (p2 - p1).normalized()
	if dir.length() > 0.01:
		_train_node.rotation.y = atan2(-dir.x, -dir.z)

	# Si le joueur est à bord, la caméra et le joueur suivent le train
	if _riding and player:
		player.global_position = _train_node.global_position + Vector3(0, 1.2, 0)


# --- Construction des voies et du quai ---------------------------------------

func _build_tracks() -> void:
	var origin := station_pos + Vector3(4.0, 0, 0)
	# Tracé de la ligne ferroviaire longeant la zone portuaire vers le nord
	_rail_pts.append(origin)
	_rail_pts.append(origin + Vector3(0, 0, -80.0))
	_rail_pts.append(origin + Vector3(-25.0, 0, -180.0))
	_rail_pts.append(origin + Vector3(-60.0, 0, -290.0))
	_rail_pts.append(origin + Vector3(-85.0, 0, -420.0))

	# Ballast, traverses et doubles rails
	for i in range(_rail_pts.size() - 1):
		var a: Vector3 = _rail_pts[i]
		var b: Vector3 = _rail_pts[i + 1]
		var dist := a.distance_to(b)
		var center := (a + b) / 2.0
		var dir := (b - a).normalized()
		var yaw := atan2(-dir.x, -dir.z)

		# 1. Lit de ballast (gravier sombre)
		var bal := Mk.box(self, Vector3(5.5, 0.15, dist), center + Vector3(0, 0.08, 0), Color("3d405b"))
		bal.rotation.y = yaw

		# 2. Traverses en béton (tous les 2 mètres)
		var count := int(dist / 2.2)
		for k in count:
			var tp := a.lerp(b, float(k) / count) + Vector3(0, 0.18, 0)
			var tie := Mk.box(self, Vector3(3.2, 0.12, 0.28), tp, Color("6c757d"))
			tie.rotation.y = yaw

		# 3. Deux rails d'acier
		for side in [-1.0, 1.0]:
			var r_center: Vector3 = center + Vector3(-dir.z, 0, dir.x) * (float(side) * 0.95) + Vector3(0, 0.26, 0)
			var rail := Mk.box(self, Vector3(0.08, 0.14, dist), r_center, Color("ced4da"))
			rail.rotation.y = yaw

		# 4. Poteaux caténaires électriques (tous les 35 mètres)
		if i % 2 == 0:
			var mast_p := a + Vector3(-dir.z, 0, dir.x) * 3.4 + Vector3(0, 3.2, 0)
			Mk.cyl(self, 0.14, 0.14, 6.4, mast_p, Color("495057"), false, 8)
			# Bras de suspension
			Mk.box(self, Vector3(2.8, 0.08, 0.08), mast_p + Vector3(dir.z, 0, -dir.x) * 1.4 + Vector3(0, 3.0, 0), Color("495057"))


func _build_station_platform() -> void:
	var q_pos := station_pos + Vector3(-2.0, 0, -25.0)

	# Quai surélevé pavé moderne (longueur 60 m, largeur 6 m)
	Mk.box(self, Vector3(6.5, 0.65, 62.0), q_pos + Vector3(0, 0.325, 0), Color("adb5bd"))
	# Bordure tactile de sécurité jaune
	Mk.box(self, Vector3(0.4, 0.67, 62.0), q_pos + Vector3(3.1, 0.335, 0), Color("fdef42"))

	# Abris de quai modernes avec vitres et toiture bleu nuit
	for z in [-18.0, 0.0, 18.0]:
		var sh_pos := q_pos + Vector3(0, 0.65, z)
		# Toit
		Mk.box(self, Vector3(5.0, 0.2, 12.0), sh_pos + Vector3(0, 3.4, 0), Color("0b2545"))
		# Poteaux
		for sx in [-1.8, 1.8]:
			Mk.cyl(self, 0.08, 0.08, 3.4, sh_pos + Vector3(sx, 1.7, 0), Color("ced4da"), false, 8)
		# Bancs en bois
		Mk.box(self, Vector3(0.6, 0.45, 2.4), sh_pos + Vector3(0, 0.25, 0), Color("8d6748"))

	# Grand panneau d'affichage LED de la gare
	var board_pos := q_pos + Vector3(0, 4.2, 0)
	Mk.box(self, Vector3(0.2, 1.8, 8.5), board_pos, Color("111111"))
	Mk.label(self, "🚆 TER DAKAR — QUAI 1\nEXPRESS DIAMNIADIO / STADE WADE — 160 KM/H", board_pos + Vector3(-0.15, 0, 0), 42, Color("ff7b00"))

	# Point d'interaction pour monter à bord du TER
	var board_spot := q_pos + Vector3(1.2, 0.65, 0)
	spots.append({"id": "ter_monter", "pos": board_spot, "label": "Prendre le TER Dakar (Express Diamniadio — 500 FCFA)"})
	var ring := Mk.cyl(self, 1.4, 1.4, 0.05, board_spot + Vector3(0, 0.05, 0), Color("ff7b00"), false, 24)
	Mk.label(self, "🚆 Accès Voyageurs TER", board_spot + Vector3(0, 2.2, 0), Mk.NAME_SIZE, Color("ff7b00"))


# --- Rame Alstom Coradia Polyvalent TER Dakar ---------------------------------

func _build_train() -> void:
	_train_node = Node3D.new()
	_train_node.name = "TER_Train"
	add_child(_train_node)

	# 2 Voitures articulées de 14 mètres chacune (total 28 mètres)
	var col_blue := Color("0b2545") # Bleu nuit TER officiel
	var col_white := Color("f4f6f8") # Blanc nacré
	var col_orange := Color("ff7b00") # Orange solaire signature
	var col_glass := Color(0.1, 0.15, 0.22, 0.85)

	for car_idx in 2:
		var z_offset := -7.5 if car_idx == 0 else 7.5
		var car := Node3D.new()
		car.position.z = z_offset
		_train_node.add_child(car)

		# 1. Châssis inférieur bleu marine
		Mk.box(car, Vector3(2.9, 0.9, 13.5), Vector3(0, 0.45, 0), col_blue)

		# 2. Corps de caisse blanc avec baies vitrées
		Mk.box(car, Vector3(2.85, 2.2, 13.5), Vector3(0, 2.0, 0), col_white)

		# 3. Bande vitrée panoramique continue teintée
		Mk.box(car, Vector3(2.92, 0.85, 12.0), Vector3(0, 2.15, 0), col_glass)

		# 4. Liseré dynamique orange le long des flancs et des portes
		for side in [-1.0, 1.0]:
			Mk.box(car, Vector3(0.04, 0.18, 13.0), Vector3(side * 1.45, 1.0, 0), col_orange)
			# Double portes automatiques avec encadrement orange
			Mk.box(car, Vector3(0.05, 1.9, 1.6), Vector3(side * 1.45, 1.85, -2.5), col_orange)
			Mk.box(car, Vector3(0.05, 1.9, 1.6), Vector3(side * 1.45, 1.85, 2.5), col_orange)

		# 5. Nez profilé aérodynamique sur la voiture de tête (voiture 0)
		if car_idx == 0:
			# Masque avant orange fuselé
			Mk.box(car, Vector3(2.8, 2.6, 2.2), Vector3(0, 1.7, -7.5), col_orange)
			# Pare-brise panoramique incliné
			Mk.box(car, Vector3(2.5, 1.1, 1.2), Vector3(0, 2.2, -7.8), col_glass)
			# Phares avant LED à haute luminosité
			for sx in [-0.9, 0.9]:
				Mk.box(car, Vector3(0.28, 0.16, 0.08), Vector3(sx, 1.1, -8.6), Color.WHITE, false, Mk.mat(Color.WHITE, 3.0))
			# Afficheur de destination frontal
			Mk.box(car, Vector3(1.6, 0.35, 0.05), Vector3(0, 2.85, -7.9), Color("111111"))
			Mk.label(car, "TER DAKAR — EXPRESS AIBD", Vector3(0, 2.85, -7.95), 28, Color("ff7b00"))

		# 6. Équipements de toiture et pantographe
		Mk.box(car, Vector3(2.2, 0.35, 11.0), Vector3(0, 3.25, 0), Color("8d99ae"))
		if car_idx == 1:
			# Pantographe articulé
			Mk.box(car, Vector3(1.4, 0.08, 1.6), Vector3(0, 3.8, -3.0), Color("2b2d42"))
			Mk.cyl(car, 0.04, 0.04, 1.1, Vector3(0, 3.5, -3.0), Color("2b2d42"), false, 6)

		# 7. Bogies / Roues ferroviaires sous chaque voiture
		for bz in [-4.5, 4.5]:
			var bogie := Mk.box(car, Vector3(2.5, 0.3, 2.2), Vector3(0, 0.35, bz), Color("212529"))
			for bx in [-1.15, 1.15]:
				for rz in [-0.7, 0.7]:
					var wheel := Mk.cyl(car, 0.45, 0.45, 0.15, Vector3(bx, 0.45, bz + rz), Color("adb5bd"), false, 14)
					wheel.rotation.z = PI / 2.0

	# Soufflet d'intercirculation flexible entre les deux voitures
	Mk.box(_train_node, Vector3(2.6, 2.5, 1.8), Vector3(0, 2.0, 0), Color("1b1b1b"))

	_update_train_transform()


# --- Interactions -------------------------------------------------------------

func interact(id: String) -> void:
	match id:
		"ter_monter":
			if _riding:
				_exit_train()
				return
			if not GameState.spend(500):
				GameState.notify.emit("Il te faut 500 FCFA pour le ticket de TER.")
				return
			_enter_train()


func _enter_train() -> void:
	_riding = true
	Audio.play_sfx("coin")
	GameState.notify.emit("🚆 Bienvenue à bord du TER Dakar ! Prochains arrêts : Colobane, Pikine, Diamniadio.")
	if player:
		player.visible = false
		player.global_position = _train_node.global_position + Vector3(0, 1.5, 0)
	
	# Option de voyage express vers le Stade Abdoulaye Wade
	get_tree().create_timer(3.0).timeout.connect(func():
		if _riding:
			GameState.notify.emit("🚆 Destination atteinte : Gare TER Diamniadio — Stade Abdoulaye Wade !")
			_exit_train()
			if player and main and main.stade:
				player.global_position = main.stade.WADE_ORIGIN + Vector3(-85.0, 0.5, 0)
	)


func _exit_train() -> void:
	_riding = false
	if player:
		player.visible = true
		player.global_position = station_pos + Vector3(-2.0, 0.8, -10.0)


func contains(p: Vector3) -> bool:
	return p.distance_to(station_pos) < 90.0


func get_hint() -> String:
	if not player:
		return ""
	if _riding:
		return "Descendre du TER"
	if player.current_vehicle != null or player.riding != null:
		return ""
	var s = _spot_near(player.global_position)
	if s != null:
		return s["label"]
	return ""


func try_interact() -> bool:
	if not player:
		return false
	if _riding:
		_exit_train()
		return true
	if player.current_vehicle != null or player.riding != null:
		return false
	var s = _spot_near(player.global_position)
	if s != null:
		interact(s["id"])
		return true
	return false


func _spot_near(p: Vector3):
	for s in spots:
		if p.distance_to(s["pos"]) < 4.0:
			return s
	return null
