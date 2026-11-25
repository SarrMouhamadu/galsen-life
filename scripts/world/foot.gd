extends Node3D
## Complexe de mini-foot, hors de la ville (comme l'Arène nationale) : on y va en taxi ou en car depuis la
## gare routière Petersen. Trois terrains fermés (bandes, grillage, buts avec filets, projecteurs) et un
## accueil où l'on loue un terrain pour un match à 4 contre 4 (gardiens compris) contre une équipe de quartier.
## « Le perdant paie le terrain » : gagner rembourse la location et rapporte la mise de l'autre équipe.
## Le match lui-même (conduite de balle, tirs, passes, feintes, tacles, ordinateur qui joue en équipe,
## gardiens) est dans scripts/world/foot_match.gd ; les matchs entre joueurs en ligne dans scripts/net/net_foot.gd.
## Les joueurs portent une vraie tenue : maillot, short, chaussettes et numéro (personnages « footballeur »).

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

const ORIGIN := Vector3(9000, 0, -1600)
const ZONE_RADIUS := 150.0
const NAME := "Complexe de mini-foot"
const MAST_H := 12.0 ## hauteur des pylônes d'éclairage
const PITCHES := [-26.0, 0.0, 26.0] ## décalage en z des trois terrains ; le match se joue au milieu
const L := 36.0 ## longueur d'un terrain (x)
const W := 20.0 ## largeur (z)
const GOAL_W := 3.0
const GOAL_H := 2.0
const RENT := 3000
const WIN_BONUS := 6000 ## l'équipe perdante paie le terrain et la mise
const TAXI_FARE := 4000
const CAR_FARE := 250
const MATCH_TIME := 240.0
const KICK_RANGE := 1.6
const TEAMS := ["Jeunes de Ouakam", "ASC Médina", "Étoiles de Grand-Yoff", "Navétanes de Pikine", "Lions de Yoff"]
const MODELS := ["homme_afro", "homme_ville"] ## tenues de ville (le modèle en tunique porte un grand boubou)
## Maillots (appli Sapé : haut, bas) : [joueurs, gardien] de ton équipe puis de l'équipe adverse
const KITS := [["jaune,noir", "vert,noir"], ["rouge,blanc", "ciel,bleu_nuit"]]

var main
var city
var player
var hud
var spots: Array = [] ## {id, pos, label}
var status := ""
var playing := false
var _opp := ""
var _spectators: Array = []
var _light: OmniLight3D ## lumière d'appoint au-dessus du terrain éclairé
var _spots: Array = [] ## projecteurs (SpotLight3D) des quatre pylônes du terrain éclairé
var _lamp_mat: StandardMaterial3D ## lampes des pylônes : allumées la nuit
var _lit := -2 ## terrain éclairé (index dans PITCHES), -1 : aucun
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_ground()
	for z in PITCHES:
		_build_pitch(_center(z))
	_build_reception()
	if Net.online and Net.foot:
		_net_ready()
	if city.places.has("Gare routière Petersen"):
		var info: Array = city.place_info["Gare routière Petersen"]
		var pos: Vector3 = city.places["Gare routière Petersen"] + Vector3(info[7], 0, info[8]) * 12.0
		spots.append({"id": "car_aller", "pos": pos, "label": "Car pour le complexe de mini-foot (%s)" % GameState.fcfa(CAR_FARE)})
		var ring := Mk.cyl(self, 1.4, 1.4, 0.06, pos + Vector3(0, 0.2, 0), Color("06d6a0"), false, 24)
		ring.material_override = Mk.mat(Color(0.02, 0.84, 0.63, 0.8), 1.2, true)
		Mk.label(self, "Cars pour le complexe\nde mini-foot — %s" % GameState.fcfa(CAR_FARE), pos + Vector3(0, 2.8, 0), Mk.SIGN_SIZE, Color.WHITE)


func contains(p: Vector3) -> bool:
	return in_zone(p)


static func in_zone(p: Vector3) -> bool:
	return Vector2(p.x - ORIGIN.x, p.z - ORIGIN.z).length() < ZONE_RADIUS


func _center(z: float) -> Vector3:
	return ORIGIN + Vector3(0, 0, z)


# --- Décor ---------------------------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ZONE_RADIUS * 2.0, 2.0, ZONE_RADIUS * 2.0)
	cs.shape = box
	cs.position = ORIGIN + Vector3(0, -1, 0)
	body.add_child(cs)
	Mk.box(self, Vector3(ZONE_RADIUS * 2.0, 0.05, ZONE_RADIUS * 2.0), ORIGIN, Color("c9b28a"))
	Mk.box(self, Vector3(40, 0.06, 26), ORIGIN + Vector3(-58, 0.03, 0), Color("3a3a3c")) # parking
	# Mur d'enceinte du complexe
	for k in 4:
		var a := k * TAU / 4.0
		var w := Mk.box(self, Vector3(ZONE_RADIUS * 1.6, 3, 0.5), ORIGIN + Vector3(cos(a), 0, sin(a)) * (ZONE_RADIUS * 0.8) + Vector3(0, 1.5, 0), Color("e9e2cf"), true)
		w.rotation.y = a + PI / 2.0
	_light = OmniLight3D.new()
	_light.omni_range = 34.0
	_light.omni_attenuation = 0.5
	_light.light_energy = 0.5
	_light.light_color = Color("f2f6ff")
	_light.visible = false
	add_child(_light)
	for k in 4:
		var sp := SpotLight3D.new()
		sp.spot_range = 46.0
		sp.spot_angle = 52.0
		sp.spot_attenuation = 0.35
		sp.spot_angle_attenuation = 0.6
		sp.light_energy = 3.0
		sp.light_color = Color("f4f7ff") # lumière blanche de stade
		sp.visible = false
		add_child(sp)
		_spots.append(sp)


## Un terrain fermé : gazon synthétique rayé, lignes, bandes, grillage, deux buts avec filets, projecteurs
func _build_pitch(c: Vector3) -> void:
	var g1 := Color("2f8f3a")
	var g2 := Color("287d33")
	var strips := 9
	for k in strips:
		Mk.box(self, Vector3(L / strips, 0.04, W), c + Vector3(-L / 2.0 + (k + 0.5) * L / strips, 0.05, 0), g1 if k % 2 == 0 else g2)
	var white := Color("f4f4f0")
	for s in [-1.0, 1.0]:
		Mk.box(self, Vector3(L, 0.012, 0.08), c + Vector3(0, 0.075, s * (W / 2.0 - 0.3)), white)
		Mk.box(self, Vector3(0.08, 0.012, W - 0.6), c + Vector3(s * (L / 2.0 - 0.3), 0.075, 0), white)
		# Surface de réparation (demi-cercle simplifié en rectangle)
		Mk.box(self, Vector3(0.08, 0.012, 8.0), c + Vector3(s * (L / 2.0 - 6.0), 0.075, 0), white)
		for t in [-1.0, 1.0]:
			Mk.box(self, Vector3(5.7, 0.012, 0.08), c + Vector3(s * (L / 2.0 - 3.15), 0.075, t * 4.0), white)
	Mk.box(self, Vector3(0.08, 0.012, W - 0.6), c + Vector3(0, 0.075, 0), white)
	for k in 32:
		var a := k * TAU / 32.0
		var seg := Mk.box(self, Vector3(0.62, 0.012, 0.08), c + Vector3(cos(a) * 3.0, 0.076, sin(a) * 3.0), white)
		seg.rotation.y = -a + PI / 2.0
	# Bandes (le ballon rebondit dessus) et grillage jusqu'à 4,5 m
	var board := Color("1d3557")
	var fence := _fence_mat()
	for s in [-1.0, 1.0]:
		Mk.box(self, Vector3(L + 0.8, 1.0, 0.3), c + Vector3(0, 0.5, s * (W / 2.0 + 0.15)), board, true)
		var f := Mk.box(self, Vector3(L + 0.8, 3.5, 0.06), c + Vector3(0, 2.75, s * (W / 2.0 + 0.15)), Color.WHITE, true)
		f.material_override = fence
		var side: float = (W - GOAL_W) / 2.0
		for t in [-1.0, 1.0]:
			Mk.box(self, Vector3(0.3, 1.0, side), c + Vector3(s * (L / 2.0 + 0.15), 0.5, t * (GOAL_W / 2.0 + side / 2.0)), board, true)
			var fe := Mk.box(self, Vector3(0.06, 3.5, side), c + Vector3(s * (L / 2.0 + 0.15), 2.75, t * (GOAL_W / 2.0 + side / 2.0)), Color.WHITE, true)
			fe.material_override = fence
		var top := Mk.box(self, Vector3(0.06, 2.5, GOAL_W), c + Vector3(s * (L / 2.0 + 0.15), GOAL_H + 1.25, 0), Color.WHITE, true)
		top.material_override = fence
		_build_goal(c, s)
	# Pylônes d'éclairage aux quatre coins : mât de 12 m, rampe de 6 projecteurs tournée vers le terrain
	if _lamp_mat == null:
		_lamp_mat = StandardMaterial3D.new()
		_lamp_mat.albedo_color = Color("dfe4ea")
		_lamp_mat.emission_enabled = true
		_lamp_mat.emission = Color("f4f7ff")
		_lamp_mat.emission_energy_multiplier = 0.0
	var steel := Color("9aa0a6")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := c + Vector3(sx * (L / 2.0 + 1.1), 0, sz * (W / 2.0 + 1.1))
			Mk.cyl(self, 0.6, 0.6, 0.4, p + Vector3(0, 0.2, 0), Color("b8b2a6"), true, 12) # socle en béton
			Mk.cyl(self, 0.11, 0.2, MAST_H, p + Vector3(0, MAST_H / 2.0, 0), steel, true, 10)
			var head := Node3D.new()
			add_child(head)
			head.position = p + Vector3(0, MAST_H + 0.3, 0)
			var to := c - p
			head.rotation = Vector3(-0.55, atan2(-to.x, -to.z), 0) # face au terrain, penchée vers le sol
			Mk.box(head, Vector3(2.6, 1.3, 0.12), Vector3(0, 0, 0.1), Color("6c7278"))
			for ix in 3:
				for iy in 2:
					var lamp := Mk.box(head, Vector3(0.7, 0.5, 0.16), Vector3((ix - 1) * 0.82, (iy - 0.5) * 0.6, -0.04), Color.WHITE, false, _lamp_mat)
					lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Échelle de maintenance
			Mk.box(self, Vector3(0.04, MAST_H - 1.0, 0.3), p + Vector3(0, MAST_H / 2.0, 0) + Vector3(-sx, 0, -sz).normalized() * 0.22, steel)


func _build_goal(c: Vector3, s: float) -> void:
	var x: float = s * L / 2.0
	var post := Color("f4f4f0")
	for t in [-1.0, 1.0]:
		Mk.cyl(self, 0.05, 0.05, GOAL_H, c + Vector3(x, GOAL_H / 2.0, t * GOAL_W / 2.0), post, true, 8)
	var bar := Mk.cyl(self, 0.05, 0.05, GOAL_W, c + Vector3(x, GOAL_H, 0), post, false, 8)
	bar.rotation.x = PI / 2.0
	# Filets : fond, côtés et toit (avec collision : le ballon reste dans le but)
	var net := _net_mat()
	var back := Mk.box(self, Vector3(0.05, GOAL_H, GOAL_W), c + Vector3(x + s * 1.1, GOAL_H / 2.0, 0), Color.WHITE, true)
	back.material_override = net
	for t in [-1.0, 1.0]:
		var sd := Mk.box(self, Vector3(1.1, GOAL_H, 0.05), c + Vector3(x + s * 0.55, GOAL_H / 2.0, t * GOAL_W / 2.0), Color.WHITE, true)
		sd.material_override = net
	var roof := Mk.box(self, Vector3(1.1, 0.05, GOAL_W), c + Vector3(x + s * 0.55, GOAL_H, 0), Color.WHITE, true)
	roof.material_override = net


static var _fence_tex: ImageTexture


## Grillage en losanges (texture dessinée, transparente)
func _fence_mat() -> StandardMaterial3D:
	if _fence_tex == null:
		var n := 32
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for i in n:
			for d in [0, 1]:
				img.set_pixel(i, (i + d) % n, Color(0.75, 0.77, 0.8, 1))
				img.set_pixel(i, (n - 1 - i + d) % n, Color(0.75, 0.77, 0.8, 1))
		_fence_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _fence_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.uv1_scale = Vector3(8, 8, 1)
	m.uv1_triplanar = true
	m.metallic = 0.4
	m.roughness = 0.5
	return m


func _net_mat() -> StandardMaterial3D:
	var m := _fence_mat()
	m.albedo_color = Color(1, 1, 1)
	m.uv1_scale = Vector3(16, 16, 1)
	m.metallic = 0.0
	return m


## Accueil : guichet de location, bancs, panneau du complexe, arrêt du taxi et du car
func _build_reception() -> void:
	var r := ORIGIN + Vector3(-30, 0, 0)
	var hut := Mk.box(self, Vector3(6, 3, 4), r + Vector3(-2, 1.5, 0), Color("f1e3c6"), true)
	hut.material_override = Mk.mat(Color("f1e3c6"))
	Mk.box(self, Vector3(6.6, 0.25, 4.6), r + Vector3(-2, 3.1, 0), Color("2a9d8f"))
	Mk.box(self, Vector3(0.6, 1.1, 2.6), r + Vector3(1.3, 0.55, 0), Color("6f4518"), true) # comptoir
	var sign := Mk.label(self, NAME.to_upper(), r + Vector3(1.05, 2.4, 0), 56, Color("fdef42"), false)
	sign.rotation.y = PI / 2.0
	for k in 3:
		Mk.box(self, Vector3(0.5, 0.45, 3.0), ORIGIN + Vector3(-L / 2.0 - 3.0, 0.22, PITCHES[k] + 3.5), Color("8d5524"), true)
	var lbl := "Louer un terrain : match à 4 contre 4 (%s, le perdant paie)" % GameState.fcfa(RENT)
	spots.append({"id": "rent", "pos": r + Vector3(2.6, 0, 0), "label": lbl})
	if Net.online:
		spots.append({"id": "online", "pos": r + Vector3(2.6, 0, -4.5), "label": "Matchs entre joueurs en ligne (créer ou rejoindre)"})
	spots.append({"id": "taxi_retour", "pos": ORIGIN + Vector3(-52, 0, -8), "label": "Taxi pour Dakar (%s)" % GameState.fcfa(TAXI_FARE)})
	spots.append({"id": "car_retour", "pos": ORIGIN + Vector3(-52, 0, 8), "label": "Car pour Petersen (%s)" % GameState.fcfa(CAR_FARE)})
	for s in spots:
		if s["id"] != "car_aller":
			var ring := Mk.cyl(self, 1.2, 1.2, 0.06, s["pos"] + Vector3(0, 0.2, 0), Color("ffd166"), false, 24)
			ring.material_override = Mk.mat(Color(1, 0.82, 0.4, 0.8), 1.2, true)


# --- Voyages ---------------------------------------------------------------------------------------

func travel_to_complex(by: String) -> bool:
	if GameState.wanted > 0:
		GameState.notify.emit("Les chauffeurs refusent : la police te recherche !")
		return false
	var fare := CAR_FARE if by == "car" else TAXI_FARE
	if not GameState.spend(fare):
		GameState.notify.emit("Il te faut %s pour aller au complexe de mini-foot." % GameState.fcfa(fare))
		return false
	hud.fade_through(func():
		player.leave_any_vehicle()
		player.global_position = ORIGIN + Vector3(-50, 0.5, 0)
		GameState.game_minutes = fmod(GameState.game_minutes + 30.0, 1440.0)
		GameState.notify.emit("Après 30 minutes de route... Bienvenue au complexe de mini-foot ! Loue un terrain à l'accueil."))
	return true


func _travel_back(fare: int, dest: Vector3, msg: String) -> void:
	if not GameState.spend(fare):
		GameState.notify.emit("Il te faut %s pour rentrer." % GameState.fcfa(fare))
		return
	hud.fade_through(func():
		player.global_position = dest + Vector3(0, 0.5, 0)
		GameState.game_minutes = fmod(GameState.game_minutes + 30.0, 1440.0)
		GameState.notify.emit(msg))


# --- Interactions ------------------------------------------------------------------------------

func _spot_near(pp: Vector3) -> Variant:
	for s in spots:
		if Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length() < 2.8:
			return s
	return null


func get_hint() -> String:
	if in_match():
		var touch: bool = GameState.touch_ui
		if _has_ball():
			return "TIR (maintenir : puissance) · PASSE (maintenir : lobée) · FEINTE" if touch else "Tir : maintiens [E] et vise · [F] passe (maintenir : lobée) · [Espace] feinte"
		if (playing and _match and _match.carrier >= 0 and _match.men[_match.carrier]["team"] == 1 and _match.pos(0).distance_to(_match.pos(_match.carrier)) < _match.TACKLE) or (online_playing and _online_opp_carrier() > 0):
			return "TACLE !" if touch else "Tacle (par derrière : faute !)"
		if playing and _match and _match.carrier > 0 and _match.men[_match.carrier]["team"] == 0:
			return "APPEL : demander le ballon" if touch else "[F] : demander le ballon"
		return ""
	if player.current_vehicle != null or player.riding != null:
		return ""
	var s = _spot_near(player.global_position)
	return "" if s == null else s["label"]


func try_interact() -> bool:
	if in_match():
		return true # TIR et TACLE sont gérés dans _controls (appui long)
	if player.current_vehicle != null or player.riding != null:
		return false
	var s = _spot_near(player.global_position)
	if s == null:
		return false
	match s["id"]:
		"car_aller":
			travel_to_complex("car")
		"taxi_retour":
			_travel_back(TAXI_FARE, city.places["Place de l'Indépendance"], "Le taxi te ramène au Plateau.")
		"car_retour":
			_travel_back(CAR_FARE, city.places["Gare routière Petersen"], "Le car te dépose à la gare routière Petersen.")
		"rent":
			if not Net.online or Net.foot.my_lobby.is_empty():
				_rent()
			else:
				GameState.notify.emit("Tu es inscrit à un match entre joueurs : quitte-le d'abord.")
		"online":
			_online_menu()
	return true


func _rent() -> void:
	if GameState.energy < 25.0:
		GameState.notify.emit("Tu es trop fatigué pour jouer : va dormir d'abord.")
		return
	if not GameState.spend(RENT):
		GameState.notify.emit("La location coûte %s." % GameState.fcfa(RENT))
		return
	_opp = TEAMS[_rng.randi() % TEAMS.size()]
	GameState.notify.emit("Terrain loué ! Ton équipe (maillots jaunes) contre « %s » (rouges). Le perdant paie le terrain." % _opp)
	hud.fade_through(_start_match)


# --- Match contre l'ordinateur (moteur : scripts/world/foot_match.gd) -------------------------------

const FootMatch = preload("res://scripts/world/foot_match.gd")
const FootBall = preload("res://scripts/world/foot_ball.gd")
const TEAM_NAMES := ["jaunes", "rouges"]
const NUMBERS := [10, 7, 9, 8, 11, 4, 6]
const CHARGE_TIME := 1.0 ## appui long sur TIR : puissance maximale
const LOB_HOLD := 0.3 ## appui sur PASSE plus long que ça : passe lobée
var _match = null
var _charge := -1.0 ## durée d'appui sur TIR (-1 : pas d'appui)
var _pcharge := -1.0 ## durée d'appui sur PASSE
var _skill_cd := 0.0
var _dash := 0.0 ## petite accélération pendant une feinte
var _dash_dir := Vector2.ZERO
var _bar: Control ## barre de puissance
var _bar_fill: ColorRect
var _bar_label: Label


func _c() -> Vector3:
	return _center(PITCHES[1])


## Éclairage de nuit : les lampes de tous les pylônes s'allument ; les vrais projecteurs (lumières)
## éclairent le terrain du match, ou celui le plus proche du joueur
func _update_lights(pp: Vector3) -> void:
	var night := _is_night() and _flat(pp, ORIGIN) < ZONE_RADIUS + 40.0
	var want := -1
	if night:
		if online_playing:
			want = _on_pitch
		elif playing:
			want = 1
		else:
			var best := INF
			for k in PITCHES.size():
				var d := _flat(pp, _center(PITCHES[k]))
				if d < best:
					best = d
					want = k
	if want == _lit:
		return
	_lit = want
	_lamp_mat.emission_energy_multiplier = 4.0 if night else 0.0
	_light.visible = want >= 0
	for sp in _spots:
		sp.visible = want >= 0
	if want < 0:
		return
	var c := _center(PITCHES[want])
	_light.global_position = c + Vector3(0, 15, 0)
	var k := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var sp: SpotLight3D = _spots[k]
			k += 1
			sp.global_position = c + Vector3(sx * (L / 2.0 + 1.1), MAST_H + 0.3, sz * (W / 2.0 + 1.1))
			# Chaque pylône vise la moitié opposée du terrain : les faisceaux se croisent, pas de zone d'ombre
			sp.look_at(c + Vector3(-sx * L * 0.12, 0, -sz * W * 0.1), Vector3.UP)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _is_night() -> bool:
	var h := GameState.game_minutes / 60.0
	return h >= 19.0 or h < 7.0


func in_match() -> bool:
	return playing or online_playing


## Position du ballon dans le monde (Vector3.INF sans match) : mini-carte, tests
func ball_world() -> Vector3:
	if playing and _match:
		return _c() + _match.ball.p
	if online_playing and _oball:
		return _oball.global_position
	return Vector3.INF


func _start_match() -> void:
	playing = true
	_wear_kit(KITS[0][0], 10)
	_match = FootMatch.new()
	_match.foot = self
	add_child(_match)
	_match.start(_opp)
	Audio.play_sfx("coin", -12.0)


func _end_match() -> void:
	playing = false
	var sc: Array = _match.score
	var msg: String
	if sc[0] > sc[1]:
		GameState.add_money(RENT + WIN_BONUS, "Victoire au mini-foot : « %s » paie le terrain" % _opp)
		msg = "Victoire %d - %d ! « %s » paie le terrain et la mise." % [sc[0], sc[1], _opp]
	elif sc[0] == sc[1]:
		GameState.add_money(RENT / 2, "Match nul au mini-foot : terrain partagé")
		msg = "Match nul %d - %d : on partage le prix du terrain." % [sc[0], sc[1]]
	else:
		msg = "Défaite %d - %d... Ton équipe paie le terrain. Revanche ?" % [sc[0], sc[1]]
	GameState.energy = maxf(0.0, GameState.energy - 20.0)
	GameState.thirst = maxf(0.0, GameState.thirst - 15.0)
	GameState.hunger = maxf(0.0, GameState.hunger - 10.0)
	status = ""
	hud.fade_through(func():
		_clear_match()
		player.global_position = ORIGIN + Vector3(-27, 0.5, 2)
		GameState.notify.emit(msg))


func _clear_match() -> void:
	if _match:
		_match.clear()
		_match.queue_free()
	_match = null
	_take_off_kit()
	playing = false
	player.frozen = false
	_charge = -1.0
	_pcharge = -1.0


func _process(delta: float) -> void:
	var pp: Vector3 = player.get_world_position() if player else Vector3.ZERO
	_update_spectators(contains(pp) and not in_match())
	_update_lights(pp)
	player.no_jump = in_match()
	_skill_cd -= delta
	if in_match():
		_controls(delta)
		_dash_step(delta)
	else:
		_charge = -1.0
		_pcharge = -1.0
	_update_bar()
	if online_playing:
		_online_process(delta)
		return
	if Net.online and Net.foot and not Net.foot.my_lobby.is_empty():
		if not contains(pp):
			Net.foot.leave() # parti du complexe : on quitte le salon (mise rendue)
		else:
			status = _lobby_status(Net.foot.my_lobby)
		return
	if not playing:
		status = "%s — loue un terrain à l'accueil" % NAME.to_upper() if contains(pp) else ""
		return
	_match.update(delta)
	var t: float = maxf(_match.time, 0.0)
	status = "MINI-FOOT — Ton équipe %d - %d %s — %d:%02d" % [_match.score[0], _match.score[1], _opp, int(ceil(t)) / 60, int(ceil(t)) % 60]
	if _match.time <= 0.0:
		_end_match()


## Quelques jeunes qui attendent leur tour près des bancs (seulement quand le joueur est au complexe)
func _update_spectators(show: bool) -> void:
	if show and _spectators.is_empty():
		for k in 3:
			var n = RealCharacter.create(self, MODELS[k % MODELS.size()], 70 + k)
			n.global_position = ORIGIN + Vector3(-L / 2.0 - 2.2, 0, PITCHES[k] + 3.5 + (k - 1) * 0.8)
			n.rotation.y = -PI / 2.0 # tournés vers les terrains
			n.play_clip("talk" if k == 1 else "idle", 0.0)
			_spectators.append(n)
	elif not show and not _spectators.is_empty():
		for n in _spectators:
			if is_instance_valid(n):
				n.queue_free()
		_spectators.clear()


# --- Commandes pendant un match (les deux modes) --------------------------------------------------------
## TIR (E / ACTION) : maintenir pour la puissance, viser avec le joystick ; sans le ballon : TACLE.
## PASSE (F / clic / COUP) : appui court à ras de terre, long : lobée ; sans le ballon : demander le ballon.
## DRIBBLE (Espace / SAUT) : feinte ou crochet. COURIR : on pousse le ballon devant soi.

func _controls(delta: float) -> void:
	if GameState.typing or hud.choices_open() or get_tree().paused:
		_charge = -1.0
		_pcharge = -1.0
		return
	var has := _has_ball()
	var stick := _stick()
	if Input.is_action_just_pressed("interact"):
		if has:
			_charge = 0.0
		else:
			_do_tackle()
	if _charge >= 0.0:
		_charge += delta
		if not Input.is_action_pressed("interact") or _charge >= CHARGE_TIME * 1.15:
			_do_shoot(clampf(_charge / CHARGE_TIME, 0.08, 1.0), _aim(stick))
			_charge = -1.0
	if Input.is_action_just_pressed("attack"):
		if has:
			_pcharge = 0.0
		else:
			_do_call()
	if _pcharge >= 0.0:
		_pcharge += delta
		if not Input.is_action_pressed("attack") or _pcharge >= 0.7:
			_do_pass(stick if stick.length() > 0.3 else _facing2(), _pcharge >= LOB_HOLD)
			_pcharge = -1.0
	if Input.is_action_just_pressed("jump") and _skill_cd <= 0.0 and has:
		_do_skill(stick)
	hud._touch.foot_labels = {"interact": "TIR" if has else "TACLE", "attack": "PASSE" if has else "APPEL", "jump": "FEINTE"}


## Direction du joystick dans le plan du terrain (comme le déplacement du joueur)
func _stick() -> Vector2:
	var inp: Vector2 = GameState.get_move_input()
	var yaw: float = player.camera_rig.yaw if player.camera_rig else 0.0
	var d := Vector3(inp.x, 0.0, inp.y).rotated(Vector3.UP, yaw)
	return Vector2(d.x, d.z)


func _attack_dir() -> float:
	return 1.0 if not online_playing or _on_team == 0 else -1.0


## Visée dans la largeur du but : joystick vers la droite ou la gauche ; sans joystick, petit filet opposé
func _aim(stick: Vector2) -> float:
	var a := _attack_dir()
	if stick.length() > 0.3:
		return clampf(stick.normalized().y * a * 1.4, -1.0, 1.0)
	var bz: float = _ball_local().z
	return -signf(bz + 0.01) * a * 0.7


func _ball_local() -> Vector3:
	if playing and _match:
		return _match.ball.p
	if online_playing:
		return _online_ball_local()
	return Vector3.ZERO


## Direction du regard du joueur dans le plan (sens de la course, sinon celui du personnage)
func _facing2() -> Vector2:
	var v := Vector2(player.velocity.x, player.velocity.z)
	if v.length() > 0.5:
		return v.normalized()
	var f: Vector3 = -player.model.global_transform.basis.z
	var f2 := Vector2(f.x, f.z)
	return f2.normalized() if f2.length() > 0.01 else Vector2(_attack_dir(), 0)


func _me2() -> Vector2:
	var c := _pc() if online_playing else _c()
	return Vector2(player.global_position.x - c.x, player.global_position.z - c.z)


func _has_ball() -> bool:
	if playing and _match:
		return _match.player_can_kick()
	if online_playing:
		return _online_has_ball()
	return false


func _do_shoot(power: float, aim: float) -> void:
	if playing:
		_match.player_shoot(power, aim)
	elif online_playing and _online_has_ball():
		var from := _online_ball_local()
		var r: Array = FootBall.shot(from, _attack_dir(), aim, power, _online_pressure() * 0.06, _rng)
		_player_anim(1.1)
		Net.foot.strike(from, r[0], r[1], true)


func _do_pass(dir: Vector2, lobbed: bool) -> void:
	if playing:
		_match.player_pass(dir.normalized(), lobbed)
	elif online_playing and _online_has_ball():
		var from := _online_ball_local()
		var f2 := Vector2(from.x, from.z)
		var to := f2 + dir.normalized() * 11.0
		var best := -INF
		for m in _online_others(true):
			var d: Vector2 = m - f2
			if d.length() < 2.0:
				continue
			var align := d.normalized().dot(dir.normalized())
			var s := align * 3.0 - d.length() / 12.0
			if align > 0.35 and s > best:
				best = s
				to = m + dir.normalized() * (1.5 if lobbed else 0.6)
		to = Vector2(clampf(to.x, -L / 2.0 + 0.8, L / 2.0 - 0.8), clampf(to.y, -W / 2.0 + 0.8, W / 2.0 - 0.8))
		var v: Vector3 = FootBall.lob(f2, to) if lobbed else FootBall.ground_pass(f2, to)
		_player_anim(1.15)
		Net.foot.strike(from, v, 0.0, false)


func _do_tackle() -> void:
	if playing:
		_match.player_tackle()
	elif online_playing:
		var o := _online_opp_carrier()
		if o > 0:
			_player_anim(1.4)
			Net.foot.tackle()


func _do_call() -> void:
	if playing:
		_match.player_call()


func _do_skill(stick: Vector2) -> void:
	_skill_cd = 0.8
	var nd := Vector2.ZERO
	if playing:
		if not _match.player_skill(stick):
			return
		nd = _match.men[0]["skill_dir"]
	elif online_playing:
		var face := _facing2()
		nd = stick.normalized() if stick.length() > 0.3 and stick.normalized().dot(face) < 0.8 else face.rotated((1.0 if _rng.randf() < 0.5 else -1.0) * 1.25)
		Net.foot.skill(nd)
	_dash = 0.35
	_dash_dir = nd
	_player_anim(1.8)


func _dash_step(delta: float) -> void:
	if _dash <= 0.0:
		return
	_dash -= delta
	var c := _pc() if online_playing else _c()
	var p: Vector3 = player.global_position + Vector3(_dash_dir.x, 0, _dash_dir.y) * 4.0 * delta
	if absf(p.x - c.x) < L / 2.0 - 0.6 and absf(p.z - c.z) < W / 2.0 - 0.6:
		player.global_position = p
	player.model.rotation.y = atan2(-_dash_dir.x, -_dash_dir.y)


func _player_anim(speed: float) -> void:
	if player.model and player.model.has_method("play_clip"):
		player.model.play_clip("kick", 0.05, speed)
		player.lock_anim(0.6 / speed)


## Barre de puissance du tir (et indication de la passe lobée)
func _update_bar() -> void:
	if _bar == null:
		var layer := CanvasLayer.new()
		layer.layer = 5
		add_child(layer)
		_bar = Control.new()
		_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_bar.position = Vector2(-130, -150)
		_bar.size = Vector2(260, 34)
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_bar)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0, 0.55)
		bg.size = Vector2(260, 16)
		bg.position = Vector2(0, 18)
		_bar.add_child(bg)
		_bar_fill = ColorRect.new()
		_bar_fill.position = Vector2(2, 20)
		_bar_fill.size = Vector2(0, 12)
		_bar.add_child(_bar_fill)
		_bar_label = Label.new()
		_bar_label.add_theme_font_size_override("font_size", 14)
		_bar_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_bar_label.add_theme_constant_override("outline_size", 4)
		_bar.add_child(_bar_label)
	_bar.visible = _charge >= 0.0 or _pcharge >= 0.0
	if not _bar.visible:
		return
	if _charge >= 0.0:
		var k := clampf(_charge / CHARGE_TIME, 0.0, 1.0)
		_bar_fill.size.x = 256.0 * k
		_bar_fill.color = Color("06d6a0").lerp(Color("ef476f"), clampf((k - 0.55) / 0.45, 0.0, 1.0))
		_bar_label.text = "Puissance du tir" + (" — trop fort, gare au-dessus !" if k > 0.85 else "")
	else:
		var k := clampf(_pcharge / 0.7, 0.0, 1.0)
		_bar_fill.size.x = 256.0 * k
		_bar_fill.color = Color("ffd166") if _pcharge >= LOB_HOLD else Color("a0c4ff")
		_bar_label.text = "Passe lobée" if _pcharge >= LOB_HOLD else "Passe à ras de terre"


# --- Tenues : maillot, short, chaussettes, numéro ---------------------------------------------------

var _city_model: Node3D = null ## le personnage habituel du joueur, caché pendant un match
var _numbers: Array = [] ## numéros (Label3D)
var _dressed := {} ## (en ligne) id → personnage déjà habillé


## Footballeur (scripts/util/real_character.gd FOOTBALLERS) qui ressemble au personnage choisi
static func footballer_for(avatar: String) -> String:
	if avatar.begins_with("femme"):
		return "footballeuse"
	match avatar:
		"homme_afro":
			return "footballeur2"
		"homme_age", "homme_tunique":
			return "footballeur3"
	return "footballeur1"


## Le joueur enfile la tenue de son équipe : son personnage est remplacé par un footballeur le temps du match
func _wear_kit(kit: String, number: int) -> void:
	if _city_model == null:
		_city_model = player.model
		var fm = RealCharacter.create(player, footballer_for(Net.avatar if Net.online else RealCharacter.HERO))
		fm.transform = _city_model.transform
		_city_model.visible = false
		player.model = fm
	_dress(player.model, kit, number)


func _take_off_kit() -> void:
	for l in _numbers:
		if is_instance_valid(l):
			l.queue_free()
	_numbers.clear()
	_dressed.clear()
	if main and main.remote_players:
		main.remote_players.outfit_override.clear()
		main.remote_players.model_override.clear()
	if _city_model != null and is_instance_valid(_city_model):
		var fm: Node3D = player.model
		_city_model.transform = fm.transform
		_city_model.visible = true
		player.model = _city_model
		fm.queue_free()
	_city_model = null


## Couleurs de l'équipe (maillot ; short et chaussettes) et numéro dans le dos (petit numéro sur la poitrine)
func _dress(model: Node3D, kit: String, number: int) -> void:
	if model == null:
		return
	if model.has_method("set_outfit"):
		model.set_outfit(kit)
	var y := 1.3
	var sk: Skeleton3D = model.get("skeleton")
	if sk:
		var bi := sk.find_bone("spine_03")
		if bi >= 0:
			y = (sk.global_transform * sk.get_bone_global_rest(bi)).origin.y - model.global_position.y
	var col := Color("151515") if kit.begins_with("jaune") or kit.begins_with("ciel") or kit.begins_with("blanc") else Color.WHITE
	for front in [false, true]:
		var l := Label3D.new()
		l.text = str(number)
		l.font_size = 40 if front else 76
		l.pixel_size = 0.0035
		l.outline_size = 0
		l.double_sided = false # lisible d'un seul côté
		l.modulate = col
		l.position = Vector3(0.07 if front else 0.0, y + (0.04 if front else -0.05), -0.155 if front else 0.165)
		if front:
			l.rotation.y = PI
		model.add_child(l)
		_numbers.append(l)


func _online_number(pseudo: String) -> int:
	var mates: Array = []
	for p in _roster:
		if int(_roster[p]) == int(_roster.get(pseudo, 0)):
			mates.append(p)
	mates.sort()
	return NUMBERS[maxi(0, mates.find(pseudo)) % NUMBERS.size()]


# --- Matchs entre joueurs en ligne (serveur : scripts/net/net_foot.gd) ------------------------------

const TEAM_COLORS := [Color(1.0, 0.82, 0.4, 0.85), Color(0.94, 0.28, 0.44, 0.85)]
var online_playing := false
var _on_pitch := 0
var _on_team := 0
var _roster := {} ## pseudo → équipe
var _on_score := [0, 0]
var _on_left := 0.0
var _oball: MeshInstance3D
var _markers := {} ## pseudo → anneau de couleur sous le joueur
var _keepers: Array = [] ## gardiens automatiques (personnages) : jaunes, rouges
var _keeper_dive := [0.0, 0.0]


func _net_ready() -> void:
	var nf = Net.foot
	nf.match_started.connect(_on_net_start)
	nf.kickoff.connect(_on_net_kickoff)
	nf.score_changed.connect(_on_net_score)
	nf.match_ended.connect(_on_net_end)
	nf.fx.connect(func(id, clip): main.remote_players.play_remote(id, clip, 600))


func _lobby_status(lob: Dictionary) -> String:
	var teams: Array = lob.get("teams", [[], []])
	return "MATCH EN LIGNE (mise %s) — jaunes : %s — rouges : %s — %s" % [GameState.fcfa(int(lob.get("stake", 0))),
		", ".join(teams[0]) if not teams[0].is_empty() else "personne", ", ".join(teams[1]) if not teams[1].is_empty() else "personne",
		"à toi de lancer à l'accueil" if lob.get("host", "") == Net.pseudo else "en attente de %s" % lob.get("host", "?")]


func _online_menu() -> void:
	var nf = Net.foot
	var opts: Array = []
	var lob: Dictionary = nf.my_lobby
	if not lob.is_empty():
		var teams: Array = lob["teams"]
		if lob["host"] == Net.pseudo:
			opts.append(["Lancer le match", func(): nf.start()])
		var other: int = 1 if Net.pseudo in teams[0] else 0
		opts.append(["Passer chez les %s" % TEAM_NAMES[other], func(): nf.switch_team(other)])
		opts.append(["Quitter le match (mise rendue)", func(): nf.leave()])
		hud.show_choices(_lobby_status(lob), opts, func(): pass)
		return
	if playing:
		return
	if GameState.energy < 25.0:
		GameState.notify.emit("Tu es trop fatigué pour jouer : va dormir d'abord.")
		return
	for l in nf.lobbies:
		var lb: Dictionary = l
		if lb["started"]:
			continue
		var t: Array = lb["teams"]
		opts.append(["Rejoindre le match de %s (mise %s) — %d jaunes, %d rouges" % [lb["host"], GameState.fcfa(int(lb["stake"])), t[0].size(), t[1].size()], func(): _join_menu(lb)])
	for st in nf.STAKES:
		var stake: int = st
		opts.append(["Créer un match " + ("amical (sans mise)" if stake == 0 else "avec mise de %s par joueur" % GameState.fcfa(stake)), func(): nf.create(stake)])
	hud.show_choices("Matchs entre joueurs — les gagnants se partagent les mises", opts, func(): pass)


func _join_menu(lb: Dictionary) -> void:
	var opts: Array = []
	for k in 2:
		var team: int = k
		opts.append(["Jouer chez les %s (%d joueurs)" % [TEAM_NAMES[team], lb["teams"][team].size()], func(): Net.foot.join(int(lb["mid"]), team, int(lb["stake"]))])
	hud.show_choices("Match de %s" % lb["host"], opts, func(): pass)


func _pc() -> Vector3:
	return _center(PITCHES[_on_pitch])


func _on_net_start(_mid: int, pitch: int, team: int, roster: Dictionary, duration: float) -> void:
	if playing:
		_clear_match()
	_on_pitch = pitch
	_on_team = team
	_roster = roster
	_on_score = [0, 0]
	_on_left = duration
	online_playing = true
	_oball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = FootBall.R
	sm.height = FootBall.R * 2.0
	_oball.mesh = sm
	_oball.material_override = FootMatch.ball_material()
	add_child(_oball)
	_oball.global_position = _pc() + Vector3(0, FootBall.R, 0)
	for pseudo in roster:
		var ring := Mk.cyl(self, 0.55, 0.55, 0.03, Vector3.ZERO, Color.WHITE, false, 20)
		ring.material_override = Mk.mat(TEAM_COLORS[int(roster[pseudo])], 1.0, true)
		_markers[pseudo] = ring
	for k in 2:
		var g = RealCharacter.create(self, "gardien", 60 + k)
		_dress(g, KITS[k][1], 1)
		g.global_position = _pc() + Vector3((-1.0 if k == 0 else 1.0) * (L / 2.0 - 0.8), 0, 0)
		_keepers.append(g)
	_wear_kit(KITS[team][0], _online_number(Net.pseudo))
	GameState.notify.emit("Match lancé ! Tu joues chez les %s : %s." % [TEAM_NAMES[team], "attaque vers la droite" if team == 0 else "attaque vers la gauche"])
	hud.fade_through(func(): _on_net_kickoff(0))


func _on_net_kickoff(_team: int) -> void:
	if not online_playing:
		return
	# Chacun dans sa moitié, les coéquipiers écartés
	var mates: Array = []
	for p in _roster:
		if int(_roster[p]) == _on_team:
			mates.append(p)
	mates.sort()
	var i: int = maxi(0, mates.find(Net.pseudo))
	var side := -1.0 if _on_team == 0 else 1.0
	var spots_z := [0.0, -4.0, 4.0, -7.0, 7.0]
	player.leave_any_vehicle()
	player.global_position = _pc() + Vector3(side * (1.5 + 3.0 * (i % 2)), 0.5, spots_z[i % spots_z.size()])
	player.velocity = Vector3.ZERO
	player.camera_rig.yaw = -PI / 2.0 if _on_team == 0 else PI / 2.0
	player.model.rotation.y = -PI / 2.0 if _on_team == 0 else PI / 2.0


func _on_net_score(score: Array, left: float) -> void:
	_on_score = score
	_on_left = left


func _on_net_end(message: String, outcome: int) -> void:
	var was := online_playing
	online_playing = false
	if is_instance_valid(_oball):
		_oball.queue_free()
	_oball = null
	for p in _markers:
		if is_instance_valid(_markers[p]):
			_markers[p].queue_free()
	_markers.clear()
	for g in _keepers:
		if is_instance_valid(g):
			g.queue_free()
	_keepers.clear()
	_take_off_kit()
	status = ""
	_charge = -1.0
	_pcharge = -1.0
	GameState.notify.emit("Fin du match entre joueurs : " + message)
	if outcome == 1:
		Audio.play_sfx("coin", -8.0)
	if was:
		GameState.energy = maxf(0.0, GameState.energy - 15.0)
		hud.fade_through(func(): player.global_position = ORIGIN + Vector3(-27, 0.5, 2))


## Le ballon dans le repère du terrain : à nos pieds quand on l'a (sans attendre le serveur), sinon prévu
func _online_ball_local() -> Vector3:
	var nf = Net.foot
	if nf.carrier == nf.my_id() and nf.carrier > 0:
		var me := _me2()
		var f := _facing2()
		var sp := Vector2(player.velocity.x, player.velocity.z).length()
		var t := me + f * (0.42 + sp * 0.06)
		return Vector3(t.x, FootBall.R, t.y)
	return nf.ball_now()


func _online_has_ball() -> bool:
	var nf = Net.foot
	if nf.carrier == nf.my_id() and nf.carrier > 0:
		return true
	var b: Vector3 = nf.ball_now()
	return nf.carrier == -1 and Vector2(b.x, b.z).distance_to(_me2()) < 1.3 and b.y < 1.4


## Positions (repère du terrain) des coéquipiers ou adversaires en ligne
func _online_others(mates: bool) -> Array:
	var out: Array = []
	var c := _pc()
	for id in Net.remote:
		var ps := str(Net.remote[id]["pseudo"])
		if not _roster.has(ps) or ps == Net.pseudo or (int(_roster[ps]) == _on_team) != mates:
			continue
		var h = main.remote_players.holder_of(id)
		if h != null:
			out.append(Vector2(h.global_position.x - c.x, h.global_position.z - c.z))
	return out


func _online_pressure() -> float:
	var best := INF
	for o in _online_others(false):
		best = minf(best, (o as Vector2).distance_to(_me2()))
	return clampf((2.0 - best) / 2.0, 0.0, 1.0)


## Porteur adverse à portée de tacle (id), 0 sinon
func _online_opp_carrier() -> int:
	var nf = Net.foot
	var o: int = nf.carrier
	if o <= 0 or not Net.remote.has(o):
		return 0
	var ps := str(Net.remote[o]["pseudo"])
	if not _roster.has(ps) or int(_roster[ps]) == _on_team:
		return 0
	var h = main.remote_players.holder_of(o)
	if h == null or _flat(h.global_position, player.global_position) > 2.2:
		return 0
	return o


func _online_process(delta: float) -> void:
	var nf = Net.foot
	var b := _online_ball_local()
	var prev: Vector3 = _oball.global_position
	_oball.global_position = _pc() + b
	var mv := _oball.global_position - prev
	if Vector2(mv.x, mv.z).length() > 0.001:
		_oball.rotate(Vector3(mv.z, 0, -mv.x).normalized(), -Vector2(mv.x, mv.z).length() / FootBall.R)
	var m := int(ceil(_on_left)) / 60
	var s := int(ceil(_on_left)) % 60
	status = "MATCH EN LIGNE — jaunes %d - %d rouges — tu es chez les %s — %d:%02d" % [_on_score[0], _on_score[1], TEAM_NAMES[_on_team], m, s]
	# Les autres joueurs du match en footballeurs, aux couleurs de leur équipe (dès que leur personnage apparaît)
	for id in Net.remote:
		var ps := str(Net.remote[id]["pseudo"])
		if not _roster.has(ps):
			continue
		var kit: String = KITS[int(_roster[ps])][0]
		main.remote_players.model_override[id] = footballer_for(str(Net.remote[id].get("avatar", "")))
		main.remote_players.outfit_override[id] = kit
		var mdl = main.remote_players.model_of(id)
		if mdl != null and _dressed.get(id) != mdl and RealCharacter.FOOTBALLERS.has(main.remote_players.avatar_of(id)):
			_dressed[id] = mdl
			_dress(mdl, kit, _online_number(ps))
	# Anneaux de couleur sous chaque joueur du match
	var where := {Net.pseudo: player.global_position}
	for id in Net.remote:
		var h = main.remote_players.holder_of(id) if main.remote_players else null
		if h != null:
			where[str(Net.remote[id]["pseudo"])] = h.global_position
	for p in _markers:
		var ring: Node3D = _markers[p]
		ring.visible = where.has(p)
		if ring.visible:
			var w: Vector3 = where[p]
			ring.global_position = Vector3(w.x, _pc().y + 0.1, w.z)
	# Gardiens automatiques (simulés par le serveur)
	for k in mini(2, _keepers.size()):
		var g: Node3D = _keepers[k]
		var kp: Vector3 = nf.keepers[k]
		var a := 1.0 if k == 0 else -1.0
		var target := _pc() + Vector3(kp.x if kp.x != 0.0 else -a * (L / 2.0 - 0.8), 0, kp.y)
		var step := Vector2(target.x - g.global_position.x, target.z - g.global_position.z)
		g.global_position = g.global_position.lerp(target, 1.0 - exp(-12.0 * delta))
		var tb := Vector2(_pc().x + b.x - g.global_position.x, _pc().z + b.z - g.global_position.z)
		if tb.length() > 0.1:
			g.rotation.y = lerp_angle(g.rotation.y, atan2(-tb.x, -tb.y), 1.0 - exp(-10.0 * delta))
		if kp.z != 0.0:
			if _keeper_dive[k] <= 0.0:
				g.play_clip("jump", 0.05, 1.3)
			_keeper_dive[k] = 0.9
		_keeper_dive[k] -= delta
		var dive_k := clampf(_keeper_dive[k] / 0.9, 0.0, 1.0)
		g.rotation.z = lerp_angle(g.rotation.z, (signf(kp.z) * a * 1.25) if _keeper_dive[k] > 0.2 else 0.0, 1.0 - exp(-10.0 * delta))
		if dive_k <= 0.0:
			g.locomote(step.length() / maxf(delta, 0.001) * 0.1)
	if player.global_position.y < -5.0 or not contains(player.global_position):
		_on_net_kickoff(_on_team)
