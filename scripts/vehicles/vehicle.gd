extends CharacterBody3D
## Véhicule arcade : conduit par le joueur, par l'IA (trafic) ou garé.

const Mk = preload("res://scripts/util/mk.gd")

const TYPES := {
	"taxi": {"name": "Taxi", "size": Vector3(1.84, 1.34, 4.3), "speed": 26.0, "accel": 9.0, "steer": 2.1, "cam": 7.0},
	"bus": {"name": "Autocar", "size": Vector3(2.55, 3.3, 12.0), "speed": 20.0, "accel": 4.0, "steer": 1.15, "cam": 15.0},
	"coach": {"name": "Car interurbain", "size": Vector3(2.55, 3.3, 12.0), "speed": 21.0, "accel": 4.0, "steer": 1.15, "cam": 15.0},
	"car_rapide": {"name": "Car rapide", "size": Vector3(2.5, 2.9, 6.2), "speed": 19.0, "accel": 5.5, "steer": 1.6, "cam": 10.0},
	"jakarta": {"name": "Jakarta", "size": Vector3(0.7, 1.1, 1.9), "speed": 25.0, "accel": 13.0, "steer": 2.8, "cam": 5.5},
	"grosse_moto": {"name": "Grosse moto", "size": Vector3(0.85, 1.25, 2.2), "speed": 36.0, "accel": 18.0, "steer": 3.0, "cam": 5.8},
	"clando": {"name": "Clando", "size": Vector3(1.95, 1.35, 4.45), "speed": 23.0, "accel": 8.0, "steer": 2.0, "cam": 7.5},
	"police": {"name": "Voiture de police", "size": Vector3(2.15, 1.5, 4.6), "speed": 27.0, "accel": 10.0, "steer": 2.2, "cam": 7.5},
	"van": {"name": "Camionnette Jumbo", "size": Vector3(2.6, 2.7, 5.4), "speed": 21.0, "accel": 6.5, "steer": 1.8, "cam": 9.0},
	"ndiaga": {"name": "Ndiaga Ndiaye", "size": Vector3(2.5, 2.6, 6.0), "speed": 19.0, "accel": 5.5, "steer": 1.7, "cam": 10.0},
	"army": {"name": "Jeep militaire", "size": Vector3(2.3, 1.7, 4.7), "speed": 28.0, "accel": 11.0, "steer": 2.1, "cam": 8.0},
	"brt": {"name": "SunuBRT 100% Électrique", "size": Vector3(2.65, 3.4, 14.5), "speed": 24.0, "accel": 6.0, "steer": 1.2, "cam": 16.0},
	"charette": {"name": "Charrette traditionnelle", "size": Vector3(1.6, 1.8, 4.4), "speed": 14.0, "accel": 5.0, "steer": 2.4, "cam": 6.5},
}
const FUEL_PER_M := 100.0 / 15000.0 ## % de réservoir par mètre parcouru
const RADIO_TYPES := ["taxi", "car_rapide", "clando", "police", "bus", "coach", "ndiaga", "brt"]
const ENGINE_PITCH := {"army": 0.6, "taxi": 0.75, "car_rapide": 0.55, "jakarta": 1.5, "grosse_moto": 0.85, "clando": 0.7, "police": 0.8, "bus": 0.42, "coach": 0.42, "ndiaga": 0.5, "brt": 0.35, "charette": 0.0}
## Les grands véhicules évitent les ruelles trop étroites.
const MIN_ROAD := {"bus": 8.0, "coach": 8.0, "car_rapide": 6.0, "ndiaga": 6.0, "brt": 9.0}
## Vrais modèles 3D : packs CC0 de Quaternius (tools/convert_vehicles.py) et modèles Sketchfab « sf_* »
## (tools/convert_sketchfab.py, auteurs crédités dans vehicles/CREDITS.md, gardent leurs propres couleurs).
## type → [fichiers possibles, {matériau: nouvelle couleur}]
const MODELS := {
	"taxi": [["taxi"], {"Yellow": Color("f2c40c")}],
	"clando": [["clando1", "clando2", "sf_bmw2002"], {}],
	"police": [["police", "sf_caprice", "sf_caprice78"], {"Black": Color("1d3557"), "WhiteLights": Color("ff1f3d")}],
	"army": [["suv"], {"White": Color("4b5320"), "Black": Color("2f3414")}],
	"bus": [["bus"], {"Top": Color("f39200"), "Bottom": Color("f39200"), "Material": Color("c46f00")}],
	"coach": [["sf_coach"], {}],
	"car_rapide": [["sf_car_rapide"], {}],
	"van": [["van"], {"Red": Color("c1121f")}],
	"ndiaga": [["sf_ndiaga"], {}],
	"jakarta": [["sf_dt125"], {}],
	"grosse_moto": [["sf_dt125"], {"plastico naranja": Color("0d0d0d"), "calcas": Color("e63946"), "aluminio": Color("1a1a1a"), "ALUMINIO NEGRO": Color("050505")}],
}
## Matériau de carrosserie de chaque modèle (repeint au garage, couleur des clandos)
const BODY := {"taxi": "Yellow", "clando1": "Blue", "clando2": "LightBlue", "police": "White", "suv": "White",
	"bus": "Top", "car_rapide": "Yellow", "van": "White", "sf_dt125": "plastico naranja"}
const CLANDO_COLORS := [Color("8d99ae"), Color("c9ada7"), Color("6d6875"), Color("a3b18a"), Color("bc6c25"), Color("e9edc9")]

@export var vehicle_type := "taxi"
var display_name := ""
var size := Vector3.ONE
var max_speed := 20.0
var accel := 8.0
var steer_speed := 2.0
var camera_distance := 7.0
var speed := 0.0
var driver = null
var condition := 100.0 ## état du moteur en % : les accidents l'abîment ; sous 35 %, il tire moins (garage, mécanicien)
var _broken_warned := false
var fuel := -1.0 ## réservoir en % (-1 : jamais conduit par le joueur ; rempli au hasard à la première conduite)
var _dry_warned := false
var ai_enabled := false
var ai_city = null
var ai_from := -1
var ai_to := -1
var is_patrol := false
var _ai_blocked := 0.0
var _turn_back := 0.0 ## manœuvre en marche arrière (demi-tour serré)
var _turn_dir := 0.0 ## sens de braquage de la manœuvre en cours (0 : aucune)
var _hit_cooldown := 0.0
var lod_far := false ## voiture du trafic loin de la caméra : physique allégée (main.gd)
# Conduite du joueur : volant progressif, adhérence, carrosserie, feux
var _steer_in := 0.0
var _motion_yaw := 0.0 ## direction réelle du déplacement (glisse quand elle diffère du cap)
var slip := 0.0
var _prev_speed := 0.0
var _crash_cd := 0.0
var _body: Node3D
var _brake_mat: StandardMaterial3D
var _reverse_mat: StandardMaterial3D
var _headlight: SpotLight3D
var _braking := false
var _honked := false
var _lod_acc := 0.0
var _lod_n := 0
var _wheels: Array = []
var _wheel_r := 0.35
var _wheel_axis := Vector3.UP
var _model_file := ""
var model_override := "" ## force un modèle précis (vitrine, tests)
var _siren_mats: Array = [] ## gyrophare des modèles 3D : [rouge, bleu]
static var _model_scenes := {}
static var _mat_cache := {}
var _rider: Node3D
var _horse_node: Node3D
var _horse_head: Node3D
var _horse_legs: Array = []
var _charette_trot_t := 0.0
var _trot_sfx_timer := 0.0
var _crime_cooldown := 0.0
var _light_check := 0.0
var _last_light := -1
var ai_next := -1 ## tronçon suivant déjà choisi (on voit le panneau du carrefour d'après)
var _next_for := -1
var _rules_done := {} ## panneaux déjà respectés (tronçon → true)
var _rule_key := Vector2i(-1, -1) ## panneau devant lequel on attend
var _rule_wait := 0.0
var _ped_t := 0.0
var _ped_block := false
var _stop_check := 0.0
var _last_stop_node := -1
var _slow_since := 0.0 ## temps depuis la dernière fois qu'on roulait au pas (STOP marqué ou non)

# Passager et itinéraire (bus de ligne, taxi vers une destination)
signal reached_stop(stop_name: String)
signal route_finished
var passenger = null
var hold := false ## immobilisé (le client choisit sa destination, montée...)
var route_active := false
var route_loop := false
var route_pts := PackedVector3Array()
var route_i := 1
var route_stops := {} ## indice du point → nom de l'arrêt
var line_name := ""
var _dwell := 0.0

# Police
var chasing := false
var chase_point := Vector3.ZERO
var chase_player_dist := 999.0
var _stuck_t := 0.0
var _reverse_t := 0.0
var _light_t := 0.0
var _lights: Array = []
var _siren: AudioStreamPlayer3D


func _ready() -> void:
	var t: Dictionary = TYPES.get(vehicle_type, TYPES["taxi"])
	display_name = t["name"]
	size = t["size"]
	max_speed = t["speed"]
	accel = t["accel"]
	steer_speed = t["steer"]
	camera_distance = t["cam"]
	add_to_group("vehicles")
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size.x, size.y + 0.4, size.z)
	cs.shape = sh
	cs.position.y = (size.y + 0.4) / 2.0
	add_child(cs)
	_build_model()
	_apply_paint()
	if vehicle_type == "police":
		_siren = Audio.make_siren_player()
		_siren.position.y = 1.5
		add_child(_siren)
	else:
		set_process(false)


func _process(delta: float) -> void:
	if driver != null:
		_update_lights()
	# Gyrophare et sirène (voitures de police uniquement) : les autres n'ont rien à faire ici
	if _siren_mats.is_empty() and _lights.size() < 2:
		if driver == null:
			set_process(false)
		return
	var on := chasing or driver != null
	if on:
		_light_t += delta
	var phase := int(_light_t * 5.0) % 2
	if not _siren_mats.is_empty():
		for k in _siren_mats.size():
			var m: StandardMaterial3D = _siren_mats[k]
			m.emission_enabled = on and phase == k % 2
			m.emission_energy_multiplier = 3.0
	elif _lights.size() >= 2:
		_lights[0].material_override = Mk.mat(Color("ff1f3d"), 3.0) if on and phase == 0 else Mk.mat(Color("5a1a22"))
		_lights[1].material_override = Mk.mat(Color("2f6bff"), 3.0) if on and phase == 1 else Mk.mat(Color("1a2a5a"))
	if on and not _siren.playing:
		_siren.play()
	elif not on and _siren.playing:
		_siren.stop()


# --- Apparence ---------------------------------------------------------------

## Garage : nouvelle couleur de carrosserie (les pièces de la couleur dominante changent)
func repaint(col: Color) -> void:
	set_meta("paint", col)
	if _model_file != "":
		_recolor_model({BODY.get(_model_file, ""): col})
		return
	var main_col := Color.TRANSPARENT
	var best := 0.0
	for mi in find_children("*", "MeshInstance3D", false, false):
		if mi.mesh is BoxMesh and mi.material_override is StandardMaterial3D:
			var s: Vector3 = mi.mesh.size
			if s.x * s.y * s.z > best and not mi.material_override.emission_enabled:
				best = s.x * s.y * s.z
				main_col = mi.material_override.albedo_color
	for mi in find_children("*", "MeshInstance3D", false, false):
		if mi.mesh is BoxMesh and mi.material_override is StandardMaterial3D and mi.material_override.albedo_color.is_equal_approx(main_col):
			mi.material_override = Mk.paint(col) if Graphics.get_value("reflections") else Mk.mat(col)


## Reflets : carrosserie lisse et vitres brillantes (les roues et les phares ne changent pas)
func _apply_paint() -> void:
	if not Graphics.get_value("reflections"):
		return
	for mi in find_children("*", "MeshInstance3D", false, false):
		if not (mi.mesh is BoxMesh) or not (mi.material_override is StandardMaterial3D):
			continue
		var m: StandardMaterial3D = mi.material_override
		if m.emission_enabled or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var c := m.albedo_color
		var dark := c.v < 0.12
		mi.material_override = Mk.paint(c, dark)


## Charge le vrai modèle 3D du véhicule, repeint selon le type (taxi jaune, police bleu nuit...)
func _build_real_model() -> void:
	var files: Array = MODELS[vehicle_type][0]
	_model_file = model_override if model_override != "" else files[get_instance_id() % files.size()]
	if not _model_scenes.has(_model_file):
		_model_scenes[_model_file] = load("res://vehicles/%s.glb" % _model_file)
	var inst: Node3D = _model_scenes[_model_file].instantiate()
	inst.name = "Modele"
	add_child(inst)
	var sketchfab := _model_file.begins_with("sf_")
	var colors: Dictionary = MODELS[vehicle_type][1].duplicate() if (not sketchfab or vehicle_type == "grosse_moto") else {}
	if vehicle_type == "clando" and BODY.has(_model_file):
		colors[BODY[_model_file]] = CLANDO_COLORS[get_instance_id() % CLANDO_COLORS.size()]
	_recolor_model(colors)
	if vehicle_type == "grosse_moto":
		inst.scale = Vector3(1.18, 1.15, 1.15)
	# Roues : elles tournent autour de leur axe (X)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		if "wheel" in String(mi.name).to_lower():
			_wheels.append(mi)
			_wheel_r = maxf(0.2, mi.get_aabb().size.y / 2.0)
	_wheel_axis = Vector3.RIGHT
	# Inscriptions sur les flancs
	var words := {"van": ["JUMBO", Color("c1121f"), 1.7, 90], "police": ["POLICE", Color.WHITE, 0.78, 44], "ndiaga": ["ALHAMDOULILLAH", Color("1e5aa8"), 1.75, 46]}
	if words.has(vehicle_type) and not sketchfab:
		var w: Array = words[vehicle_type]
		for sx in [-1, 1]:
			var t := Mk.label(self, w[0], Vector3(sx * (size.x / 2.0 + 0.03), w[2], 0.2), w[3], w[1], false)
			t.rotation.y = sx * PI / 2.0
			t.outline_size = 0
	if vehicle_type == "ndiaga" and not sketchfab:
		_ndiaga_rack()
	if vehicle_type == "police" and sketchfab:
		# Gyrophare rouge et bleu sur le toit (clignote pendant les poursuites)
		var top: float = 0.0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			top = maxf(top, (mi.transform * mi.get_aabb()).end.y)
		for sx in [-1, 1]:
			_lights.append(Mk.box(self, Vector3(0.42, 0.13, 0.24), Vector3(sx * 0.23, top + 0.05, 0.25), Color("5a1a22")))
	if vehicle_type in ["jakarta", "grosse_moto"]:
		_add_rider()
		# Phare avant
		if vehicle_type == "grosse_moto":
			for sx in [-0.11, 0.11]:
				Mk.box(self, Vector3(0.09, 0.08, 0.04), Vector3(sx, 1.05, -0.9), Color("ffffff"), false, Mk.mat(Color("ffffff"), 2.2))
		else:
			Mk.box(self, Vector3(0.14, 0.1, 0.04), Vector3(0, 1.0, -0.85), Color("fff3b0"), false, Mk.mat(Color("fff3b0"), 1.5))


## Conducteur de la moto (visible quand elle roule dans le trafic ou que le joueur la conduit)
func _add_rider() -> void:
	_rider = load("res://scripts/util/real_character.gd").create(self, "homme_afro", 3)
	_rider.position = Vector3(0, 0.12 if vehicle_type == "grosse_moto" else 0.1, 0.25)
	_rider.play_clip("drive", 0.0)
	_rider.scale = Vector3.ONE * (1.02 if vehicle_type == "grosse_moto" else 0.95)
	_rider.visible = false


## Ndiaga Ndiaye : galerie sur le toit, chargée de sacs, de bidons et d'une valise ficelés
func _ndiaga_rack() -> void:
	var top := size.y + 0.05
	var grey := Color("9aa0a6")
	Mk.box(self, Vector3(size.x * 0.86, 0.05, size.z * 0.72), Vector3(0, top, 0.1), grey)
	for sx in [-1, 1]:
		Mk.box(self, Vector3(0.05, 0.2, size.z * 0.72), Vector3(sx * size.x * 0.43, top + 0.1, 0.1), grey)
	for sz in [-1, 1]:
		Mk.box(self, Vector3(size.x * 0.86, 0.2, 0.05), Vector3(0, top + 0.1, 0.1 + sz * size.z * 0.36), grey)
	var load_cols := [Color("c1121f"), Color("2a9d8f"), Color("e9c46a"), Color("6a4c93"), Color("3d405b"), Color("f4a261")]
	var sd := get_instance_id()
	for k in 6:
		var c: Color = load_cols[(sd + k * 7) % load_cols.size()]
		var w := 0.5 + float((sd >> k) % 3) * 0.15
		var h := 0.4 + float((sd >> (k + 2)) % 3) * 0.15
		var px := (float(k % 2) - 0.5) * size.x * 0.4
		var pz := 0.1 + (float(k / 2) - 1.0) * size.z * 0.22
		Mk.box(self, Vector3(w, h, w * 1.2), Vector3(px, top + 0.03 + h / 2.0, pz), c)


func _recolor_model(colors: Dictionary) -> void:
	var glossy: bool = Graphics.get_value("reflections")
	var model := get_node_or_null("Modele")
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var base = mi.mesh.surface_get_material(s)
			if not (base is StandardMaterial3D):
				continue
			var nm: String = base.resource_name
			var cur = mi.get_surface_override_material(s)
			# Gyrophare de police : matériaux propres à chaque voiture (ils clignotent)
			if vehicle_type == "police" and nm in ["WhiteLights", "BlueLights"]:
				if cur == null:
					var sm: StandardMaterial3D = _opaque(base.duplicate())
					if colors.has(nm):
						sm.albedo_color = colors[nm]
					sm.emission = sm.albedo_color
					mi.set_surface_override_material(s, sm)
					_siren_mats.append(sm)
				continue
			if cur != null and not colors.has(nm):
				continue
			var col: Color = colors.get(nm, base.albedo_color)
			var key := "%s|%s|%s|%s" % [_model_file, nm, col.to_html(), glossy]
			if not _mat_cache.has(key):
				var m: StandardMaterial3D = _opaque(base.duplicate())
				m.albedo_color = Color(col.r, col.g, col.b, 1.0)
				var low := nm.to_lower()
				if low == "windows":
					m.roughness = 0.06 if glossy else 0.4
					m.metallic_specular = 0.9
				elif "light" in low:
					# Phares et feux légèrement lumineux
					m.emission_enabled = true
					m.emission = col
					m.emission_energy_multiplier = 0.8
				elif nm == BODY.get(_model_file, "") or colors.has(nm):
					m.roughness = 0.3 if glossy else 0.6
					m.metallic = 0.35 if glossy else 0.0
					m.metallic_specular = 0.6
				_mat_cache[key] = m
			mi.set_surface_override_material(s, _mat_cache[key])
	# Le gyrophare rouge en premier, le bleu ensuite
	if _siren_mats.size() >= 2 and _siren_mats[0].albedo_color.b > _siren_mats[0].albedo_color.r:
		_siren_mats.reverse()


## Les FBX importés arrivent transparents (alpha nul) : on rend les matériaux opaques
static func _opaque(m: StandardMaterial3D) -> StandardMaterial3D:
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	m.albedo_color.a = 1.0
	return m


func _build_model() -> void:
	var s := size
	if MODELS.has(vehicle_type):
		_build_real_model()
		return
	match vehicle_type:
		"taxi":
			_build_taxi(s)
		"bus":
			# Autocar orange, vitres noires
			_build_coach(s, Color("f39200"), Color("f39200"), [[1.62, 0.05, Color("c46f00")]])
		"coach":
			# Car interurbain blanc, face avant noire, filets bleus et liseré rouge
			_build_coach(s, Color("f4f6f8"), Color("161a20"), [[1.5, 0.07, Color("5aa7e0")], [1.64, 0.05, Color("2f7fc0")], [0.55, 0.03, Color("d64545")]])
		"car_rapide":
			# Le car rapide : jaune et bleu, peint à la main.
			Mk.box(self, Vector3(s.x, s.y * 0.45, s.z), Vector3(0, 0.4 + s.y * 0.225, 0), Color("f6c90e"))
			Mk.box(self, Vector3(s.x, s.y * 0.55, s.z), Vector3(0, 0.4 + s.y * 0.725, 0), Color("1e5aa8"))
			Mk.box(self, Vector3(s.x + 0.02, s.y * 0.22, s.z * 0.8), Vector3(0, 0.4 + s.y * 0.72, 0.3), Color("10151c"))
			Mk.box(self, Vector3(s.x * 0.9, 0.08, s.z * 0.7), Vector3(0, 0.55 + s.y, 0.3), Color("e5e5e5"))
			for k in 4:
				Mk.box(self, Vector3(0.06, 0.25, s.z * 0.7), Vector3(-s.x * 0.45 + k * s.x * 0.3, 0.68 + s.y, 0.3), Color("e5e5e5"))
			Mk.box(self, Vector3(0.6, s.y * 0.9, 0.06), Vector3(0, 0.4 + s.y * 0.5, s.z / 2.0 + 0.05), Color("dddddd"))
			var side_l := Mk.label(self, "Touba — Dakar", Vector3(-s.x / 2.0 - 0.02, 0.4 + s.y * 0.25, 0), 48, Color("c1121f"), false)
			side_l.rotation.y = -PI / 2.0
			var side_r := Mk.label(self, "Touba — Dakar", Vector3(s.x / 2.0 + 0.02, 0.4 + s.y * 0.25, 0), 48, Color("c1121f"), false)
			side_r.rotation.y = PI / 2.0
		"jakarta":
			Mk.box(self, Vector3(0.35, 0.4, 1.5), Vector3(0, 0.6, 0), Color("c1121f"))
			Mk.box(self, Vector3(0.4, 0.15, 0.7), Vector3(0, 0.85, 0.25), Color("111111"))
			Mk.box(self, Vector3(0.7, 0.06, 0.06), Vector3(0, 1.15, -0.6), Color("888888"))
			Mk.cyl(self, 0.04, 0.04, 0.5, Vector3(0, 0.9, -0.6), Color("888888"), false, 4)
			_add_rider()
		"grosse_moto":
			# Grosse moto sportive (Superbike / T-MAX) : châssis renforcé, réservoir profilé, double échappement sport
			Mk.box(self, Vector3(0.5, 0.5, 1.8), Vector3(0, 0.65, 0), Color("111111"))
			Mk.box(self, Vector3(0.55, 0.35, 0.8), Vector3(0, 0.85, -0.2), Color("e63946"))
			Mk.box(self, Vector3(0.42, 0.18, 0.8), Vector3(0, 0.92, 0.35), Color("1a1a1a"))
			Mk.box(self, Vector3(0.76, 0.07, 0.07), Vector3(0, 1.18, -0.65), Color("222222"))
			Mk.cyl(self, 0.05, 0.05, 0.6, Vector3(0, 0.95, -0.65), Color("222222"), false, 6)
			Mk.cyl(self, 0.06, 0.05, 0.7, Vector3(0.28, 0.5, 0.5), Color("444444"), false, 8)
			Mk.cyl(self, 0.06, 0.05, 0.7, Vector3(-0.28, 0.5, 0.5), Color("444444"), false, 8)
			_add_rider()
		"army":
			_build_army(s)
		"van":
			_build_van(s)
		"police":
			# Police nationale : bleu nuit et blanc, gyrophare rouge et bleu.
			Mk.box(self, Vector3(s.x, s.y * 0.5, s.z), Vector3(0, 0.4 + s.y * 0.25, 0), Color("f1f5f9"))
			Mk.box(self, Vector3(s.x + 0.02, 0.22, s.z * 0.98), Vector3(0, 0.4 + s.y * 0.3, 0), Color("1d3557"))
			Mk.box(self, Vector3(s.x * 0.9, s.y * 0.45, s.z * 0.5), Vector3(0, 0.4 + s.y * 0.72, 0.15), Color("1d3557"))
			Mk.box(self, Vector3(s.x * 0.92, s.y * 0.3, s.z * 0.46), Vector3(0, 0.4 + s.y * 0.7, 0.15), Color("10151c"))
			for sx in [-1, 1]:
				_lights.append(Mk.box(self, Vector3(0.55, 0.16, 0.3), Vector3(sx * 0.3, 0.5 + s.y, 0.15), Color("5a1a22")))
			for sx in [-1, 1]:
				var txt := Mk.label(self, "POLICE", Vector3(sx * (s.x / 2.0 + 0.02), 0.4 + s.y * 0.3, 0), 44, Color.WHITE, false)
				txt.rotation.y = sx * PI / 2.0
		"brt":
			_build_brt(s)
		"charette":
			_build_charette(s)
		_:
			var col: Color = CLANDO_COLORS[get_instance_id() % CLANDO_COLORS.size()]
			Mk.box(self, Vector3(s.x, s.y * 0.5, s.z), Vector3(0, 0.4 + s.y * 0.25, 0), col)
			Mk.box(self, Vector3(s.x * 0.9, s.y * 0.45, s.z * 0.5), Vector3(0, 0.4 + s.y * 0.72, 0.15), col.darkened(0.25))
			Mk.box(self, Vector3(s.x * 0.92, s.y * 0.3, s.z * 0.46), Vector3(0, 0.4 + s.y * 0.7, 0.15), Color("10151c"))
	# Phares (les modèles détaillés ont les leurs)
	if vehicle_type in ["car_rapide", "clando", "police", "army", "van"]:
		for sx in [-1, 1]:
			Mk.box(self, Vector3(0.3, 0.15, 0.05), Vector3(sx * (s.x / 2.0 - 0.3), 0.75, -s.z / 2.0 - 0.01), Color("fff3b0"), false, Mk.mat(Color("fff3b0"), 1.5))
	elif vehicle_type == "jakarta":
		Mk.box(self, Vector3(0.18, 0.12, 0.05), Vector3(0, 0.95, -0.8), Color("fff3b0"), false, Mk.mat(Color("fff3b0"), 1.5))
	elif vehicle_type == "grosse_moto":
		for sx in [-0.12, 0.12]:
			Mk.box(self, Vector3(0.1, 0.09, 0.05), Vector3(sx, 1.05, -s.z / 2.0 - 0.01), Color("ffffff"), false, Mk.mat(Color("ffffff"), 2.2))
	# Roues
	var wheel_pos: Array = []
	if vehicle_type in ["jakarta", "grosse_moto"]:
		_wheel_r = 0.38 if vehicle_type == "grosse_moto" else 0.35
		wheel_pos = [Vector3(0, _wheel_r, -0.75 if vehicle_type == "grosse_moto" else -0.7), Vector3(0, _wheel_r, 0.75 if vehicle_type == "grosse_moto" else 0.7)]
	elif vehicle_type in ["bus", "coach"]:
		_wheel_r = 0.52
		for sx in [-1, 1]:
			for z in [-s.z / 2.0 + 2.4, s.z / 2.0 - 3.3, s.z / 2.0 - 1.95]:
				wheel_pos.append(Vector3(sx * (s.x / 2.0 - 0.2), _wheel_r, z))
	elif vehicle_type == "brt":
		_wheel_r = 0.52
		for sx in [-1, 1]:
			for z in [-s.z / 2.0 + 2.5, 0.1, s.z / 2.0 - 2.2]:
				wheel_pos.append(Vector3(sx * (s.x / 2.0 - 0.15), _wheel_r, z))
	elif vehicle_type == "charette":
		_wheel_r = 0.58
		for sx in [-1, 1]:
			wheel_pos.append(Vector3(sx * (s.x / 2.0 + 0.1), _wheel_r, 0.6))
	else:
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				wheel_pos.append(Vector3(sx * s.x / 2.0, 0.35, sz * (s.z / 2.0 - 0.8)))
	for wp in wheel_pos:
		if vehicle_type == "charette":
			var w := Mk.cyl(self, _wheel_r, _wheel_r, 0.08, wp, Color("2b2b2b"), false, 18)
			w.rotation.z = PI / 2.0
			Mk.cyl(w, _wheel_r * 0.94, _wheel_r * 0.94, 0.1, Vector3.ZERO, Color("7c5335"), false, 18)
			Mk.cyl(w, 0.14, 0.14, 0.2, Vector3.ZERO, Color("4a3525"), false, 10)
			for spk in 4:
				var spk_mesh := Mk.box(w, Vector3(_wheel_r * 1.8, 0.04, 0.04), Vector3.ZERO, Color("8d6748"))
				spk_mesh.rotation.y = float(spk) * (PI / 4.0)
			_wheels.append(w)
		else:
			var w := Mk.cyl(self, _wheel_r, _wheel_r, 0.28, wp, Color("111111"), false, 14)
			w.rotation.z = PI / 2.0
			# Jante métallisée
			Mk.cyl(w, _wheel_r * 0.62, _wheel_r * 0.62, 0.3, Vector3.ZERO, Color("c9ccd1"), false, 10)
			_wheels.append(w)


## Bus électrique à haut niveau de service SunuBRT (articulé, livrée turquoise et blanche).
func _build_brt(s: Vector3) -> void:
	var turquoise := Color("00a896")
	var white := Color("f8f9fa")
	var dark := Color("121820")
	var W := s.x
	var L := s.z
	var base := 0.45

	# 1. Section avant (Caisse motrice)
	var front_len := 6.6
	var front_z := -L / 2.0 + front_len / 2.0 + 0.3
	Mk.box(self, Vector3(W, 1.4, front_len), Vector3(0, base + 0.7, front_z), turquoise)
	Mk.box(self, Vector3(W + 0.02, 1.25, front_len - 0.6), Vector3(0, base + 1.95, front_z + 0.2), dark)
	Mk.box(self, Vector3(W, 0.45, front_len), Vector3(0, base + 2.75, front_z), white)

	# 2. Section arrière (Remorque articulée)
	var rear_len := 5.8
	var rear_z := L / 2.0 - rear_len / 2.0
	Mk.box(self, Vector3(W, 1.4, rear_len), Vector3(0, base + 0.7, rear_z), turquoise)
	Mk.box(self, Vector3(W + 0.02, 1.25, rear_len - 0.4), Vector3(0, base + 1.95, rear_z - 0.1), dark)
	Mk.box(self, Vector3(W, 0.45, rear_len), Vector3(0, base + 2.75, rear_z), white)

	# 3. Soufflet d'articulation central (accordéon noir plissé)
	Mk.box(self, Vector3(W - 0.08, 2.75, 1.6), Vector3(0, base + 1.4, -0.1), Color("1a1a1a"))
	for k in 5:
		Mk.box(self, Vector3(W - 0.04, 2.78, 0.08), Vector3(0, base + 1.4, -0.8 + k * 0.35), Color("2b2b2b"))

	# 4. Face avant profilée et futuriste
	var nose_z := -L / 2.0
	var ws := Mk.box(self, Vector3(W - 0.12, 1.7, 0.08), Vector3(0, base + 1.85, nose_z + 0.15), dark)
	ws.rotation.x = -0.12
	Mk.box(self, Vector3(W - 0.1, 0.5, 0.3), Vector3(0, base + 2.85, nose_z + 0.2), turquoise)
	Mk.box(self, Vector3(W - 0.2, 0.38, 0.15), Vector3(0, base + 0.4, nose_z - 0.05), Color("111111"))

	for sx in [-0.95, 0.95]:
		Mk.box(self, Vector3(0.35, 0.12, 0.08), Vector3(sx, base + 0.65, nose_z - 0.06), Color.WHITE, false, Mk.mat(Color.WHITE, 2.8))
		Mk.box(self, Vector3(0.18, 0.08, 0.06), Vector3(sx * 0.75, base + 0.35, nose_z - 0.07), Color.WHITE, false, Mk.mat(Color.WHITE, 2.0))

	# Girouette LED SunuBRT
	Mk.box(self, Vector3(2.1, 0.36, 0.06), Vector3(0, base + 2.85, nose_z + 0.08), Color("111111"))
	var front_sign := Mk.label(self, "SUNUBRT — 100% ÉLECTRIQUE", Vector3(0, base + 2.85, nose_z + 0.03), 32, Color("ffd166"), false)
	front_sign.outline_size = 0

	# 5. Inscriptions latérales et portes vitrées
	for side in [-1, 1]:
		var x: float = float(side) * (W / 2.0 + 0.02)
		var lbl := Mk.label(self, "SunuBRT", Vector3(x, base + 0.85, front_z), 54, Color.WHITE, false)
		lbl.rotation.y = float(side) * PI / 2.0
		var lbl_sub := Mk.label(self, "Dakar Mobilité · 100% Électrique", Vector3(x, base + 0.48, front_z), 26, Color("ffd166"), false)
		lbl_sub.rotation.y = float(side) * PI / 2.0
		Mk.box(self, Vector3(0.12, 0.12, 0.45), Vector3(float(side) * (W / 2.0 + 0.15), base + 2.7, nose_z + 0.4), turquoise)
		Mk.box(self, Vector3(0.08, 0.28, 0.12), Vector3(float(side) * (W / 2.0 + 0.25), base + 2.65, nose_z + 0.15), dark)

	for pz in [front_z + 1.2, rear_z - 1.2, rear_z + 1.6]:
		Mk.box(self, Vector3(0.04, 2.1, 1.4), Vector3(W / 2.0 + 0.015, base + 1.15, float(pz)), Color("00853f"))
		Mk.box(self, Vector3(0.05, 1.2, 1.1), Vector3(W / 2.0 + 0.02, base + 1.45, float(pz)), dark)

	# 6. Coffres batteries électriques sur le toit
	Mk.box(self, Vector3(W - 0.4, 0.42, front_len * 0.75), Vector3(0, base + 3.12, front_z), white)
	Mk.box(self, Vector3(W - 0.4, 0.42, rear_len * 0.75), Vector3(0, base + 3.12, rear_z), white)

	# 7. Face arrière
	var back_z := L / 2.0
	Mk.box(self, Vector3(W - 0.15, 1.1, 0.06), Vector3(0, base + 2.0, back_z - 0.02), dark)
	for sx in [-0.95, 0.95]:
		Mk.box(self, Vector3(0.18, 0.7, 0.06), Vector3(sx, base + 1.3, back_z + 0.01), Color("d00000"), false, Mk.mat(Color("d00000"), 2.0))
	var back_sign := Mk.label(self, "LIGNE 1 — PETERSEN / GUÉDIAWAYE", Vector3(0, base + 2.75, back_z + 0.02), 26, Color("ffd166"), false)
	back_sign.outline_size = 0


## Charrette sénégalaise traditionnelle : plateau en planches de bois, brancards,
## cheval harnaché avec licol, rênes et gris-gris, mené par le charretier.
func _build_charette(s: Vector3) -> void:
	var wood := Color("7c5335")
	var dark_wood := Color("523621")
	var plank_wood := Color("8d633f")
	var iron := Color("2b2b2b")
	var horse_col := Color("5a3825")
	var horse_dark := Color("1f130b")

	var bed_z := 0.6
	var bed_w := s.x
	var bed_l := 2.2
	var bed_y := 0.65

	Mk.box(self, Vector3(bed_w * 0.9, 0.08, bed_l), Vector3(0, bed_y - 0.06, bed_z), iron)
	var axle := Mk.cyl(self, 0.05, 0.05, bed_w + 0.35, Vector3(0, 0.58, bed_z), iron, false, 8)
	axle.rotation.z = PI / 2.0

	for k in 9:
		var pz := bed_z - bed_l / 2.0 + 0.12 + k * 0.24
		var c: Color = plank_wood if k % 2 == 0 else wood
		Mk.box(self, Vector3(bed_w * 0.92, 0.04, 0.2), Vector3(0, bed_y, pz), c)

	for side in [-1, 1]:
		var x: float = float(side) * (bed_w / 2.0 - 0.04)
		Mk.box(self, Vector3(0.05, 0.06, bed_l), Vector3(x, bed_y + 0.32, bed_z), dark_wood)
		Mk.box(self, Vector3(0.05, 0.06, bed_l), Vector3(x, bed_y + 0.16, bed_z), wood)
		for k in 5:
			var pz := bed_z - bed_l / 2.0 + 0.15 + k * 0.46
			Mk.box(self, Vector3(0.06, 0.38, 0.06), Vector3(x, bed_y + 0.18, pz), dark_wood)
	Mk.box(self, Vector3(bed_w * 0.9, 0.28, 0.05), Vector3(0, bed_y + 0.16, bed_z + bed_l / 2.0), dark_wood)

	var bench_z := bed_z - bed_l / 2.0 + 0.2
	Mk.box(self, Vector3(bed_w * 0.85, 0.28, 0.35), Vector3(0, bed_y + 0.15, bench_z), wood)
	Mk.box(self, Vector3(bed_w * 0.8, 0.08, 0.32), Vector3(0, bed_y + 0.32, bench_z), Color("c4a482"))

	for side in [-1, 1]:
		var x_horse: float = float(side) * 0.32
		var shaft := Mk.box(self, Vector3(0.07, 0.07, 2.5), Vector3(x_horse, bed_y + 0.05, -0.65), dark_wood)
		shaft.rotation.y = float(side) * -0.04

	var lantern_pos := Vector3(-bed_w / 2.0 - 0.08, bed_y + 0.35, bench_z)
	Mk.cyl(self, 0.01, 0.01, 0.16, lantern_pos + Vector3(0, 0.1, 0), iron, false, 4)
	Mk.cyl(self, 0.06, 0.08, 0.18, lantern_pos, Color("222222"), false, 6)
	Mk.cyl(self, 0.045, 0.045, 0.12, lantern_pos, Color("ffe066"), false, 6)
	var l_lamp := OmniLight3D.new()
	l_lamp.light_color = Color("ffcc66")
	l_lamp.light_energy = 0.8
	l_lamp.omni_range = 6.0
	l_lamp.position = lantern_pos
	add_child(l_lamp)

	_horse_node = Node3D.new()
	_horse_node.name = "Cheval"
	_horse_node.position = Vector3(0, 0, -2.0)
	add_child(_horse_node)

	Mk.box(_horse_node, Vector3(0.56, 0.62, 1.3), Vector3(0, 0.88, 0.0), horse_col)
	Mk.box(_horse_node, Vector3(0.54, 0.58, 0.45), Vector3(0, 0.9, 0.55), horse_col)
	Mk.box(_horse_node, Vector3(0.54, 0.64, 0.45), Vector3(0, 0.88, -0.5), horse_col)

	var neck := Mk.box(_horse_node, Vector3(0.3, 0.62, 0.5), Vector3(0, 1.25, -0.75), horse_col)
	neck.rotation.x = 0.42
	var mane := Mk.box(_horse_node, Vector3(0.08, 0.65, 0.45), Vector3(0, 1.32, -0.7), horse_dark)
	mane.rotation.x = 0.42

	_horse_head = Node3D.new()
	_horse_head.name = "TeteCheval"
	_horse_head.position = Vector3(0, 1.52, -1.05)
	_horse_node.add_child(_horse_head)

	Mk.box(_horse_head, Vector3(0.28, 0.32, 0.48), Vector3(0, 0, -0.05), horse_col).rotation.x = -0.35
	Mk.box(_horse_head, Vector3(0.22, 0.22, 0.3), Vector3(0, -0.15, -0.32), horse_col).rotation.x = -0.1
	Mk.box(_horse_head, Vector3(0.2, 0.1, 0.06), Vector3(0, -0.18, -0.47), horse_dark)
	for side in [-1, 1]:
		Mk.box(_horse_head, Vector3(0.04, 0.06, 0.06), Vector3(side * 0.14, 0.05, -0.12), horse_dark)
		var ear := Mk.box(_horse_head, Vector3(0.06, 0.16, 0.06), Vector3(side * 0.09, 0.22, 0.1), horse_col)
		ear.rotation.z = side * -0.15
		ear.rotation.x = -0.15

	var tail := Mk.box(_horse_node, Vector3(0.12, 0.65, 0.15), Vector3(0, 0.72, 0.85), horse_dark)
	tail.rotation.x = -0.22

	_horse_legs.clear()
	var leg_defs := [
		Vector3(-0.2, 0.45, -0.42),
		Vector3(0.2, 0.45, -0.42),
		Vector3(-0.2, 0.45, 0.5),
		Vector3(0.2, 0.45, 0.5),
	]
	for idx in leg_defs.size():
		var lp: Vector3 = leg_defs[idx]
		var leg_pivot := Node3D.new()
		leg_pivot.name = "Patte_%d" % idx
		leg_pivot.position = Vector3(lp.x, 0.8, lp.z)
		_horse_node.add_child(leg_pivot)
		Mk.box(leg_pivot, Vector3(0.15, 0.52, 0.16), Vector3(0, -0.26, 0), horse_col)
		Mk.cyl(leg_pivot, 0.08, 0.08, 0.12, Vector3(0, -0.52, 0), Color("151515"), false, 8)
		_horse_legs.append(leg_pivot)

	Mk.box(_horse_node, Vector3(0.58, 0.1, 0.08), Vector3(0, 0.95, -0.72), Color("8b2500"))
	Mk.box(_horse_node, Vector3(0.58, 0.1, 0.18), Vector3(0, 1.1, 0.0), Color("8b2500"))
	for k in 3:
		var c: Color = [Color("00853f"), Color("fdef42"), Color("e31b23")][k]
		Mk.box(_horse_node, Vector3(0.08, 0.08, 0.04), Vector3(-0.16 + k * 0.16, 0.82, -0.76), c)

	for side in [-1, 1]:
		var r_mesh := Mk.box(self, Vector3(0.02, 0.02, 1.8), Vector3(float(side) * 0.22, 1.05, -1.0), Color("4a2205"))
		r_mesh.rotation.y = float(side) * 0.04

	_add_charretier(Vector3(0, bed_y + 0.35, bench_z))


func _add_charretier(pos: Vector3) -> void:
	_rider = load("res://scripts/util/real_character.gd").create(self, "homme_tunique", 1)
	_rider.position = pos
	_rider.play_clip("sit", 0.0)
	_rider.scale = Vector3.ONE * 0.95
	_rider.visible = true
	var hat := Mk.cyl(_rider, 0.32, 0.15, 0.12, Vector3(0, 1.52, 0), Color("d4a373"), false, 12)
	Mk.cyl(hat, 0.48, 0.48, 0.02, Vector3(0, -0.05, 0), Color("c49363"), false, 16)


func _update_horse_animation(delta: float) -> void:
	var moving := absf(speed) > 0.15
	if moving:
		_charette_trot_t += delta * (absf(speed) * 2.2)
		if _horse_head:
			_horse_head.rotation.x = sin(_charette_trot_t * 2.0) * 0.12
		for idx in _horse_legs.size():
			var leg: Node3D = _horse_legs[idx]
			var phase := float(idx % 2) * PI
			if idx >= 2:
				phase += PI * 0.5
			leg.rotation.x = sin(_charette_trot_t + phase) * 0.4
		if driver:
			_trot_sfx_timer -= delta
			if _trot_sfx_timer <= 0.0:
				_trot_sfx_timer = clampf(0.55 / maxf(1.0, absf(speed)), 0.18, 0.5)
				Audio.play_sfx("coin", -26.0)
	else:
		if _horse_head:
			_horse_head.rotation.x = lerpf(_horse_head.rotation.x, 0.0, 5.0 * delta)
		for leg in _horse_legs:
			leg.rotation.x = lerpf(leg.rotation.x, 0.0, 5.0 * delta)


## Camionnette de livraison Jumbo : caisse blanche, bandeaux rouge et jaune.
func _build_van(s: Vector3) -> void:
	Mk.box(self, Vector3(s.x, 0.9, 1.4), Vector3(0, 0.85, -s.z / 2.0 + 0.7), Color("c1121f")) # cabine
	var ws := Mk.box(self, Vector3(s.x - 0.12, 0.6, 0.06), Vector3(0, 1.55, -s.z / 2.0 + 0.55), _glass())
	ws.rotation.x = 0.35
	Mk.box(self, Vector3(s.x - 0.04, 0.5, 1.2), Vector3(0, 1.55, -s.z / 2.0 + 1.0), Color("c1121f"))
	Mk.box(self, Vector3(s.x, s.y, s.z - 1.5), Vector3(0, 0.4 + s.y / 2.0, 0.75), Color("f8f9fa")) # caisse
	for k in 2:
		Mk.box(self, Vector3(s.x + 0.02, 0.18, s.z - 1.6), Vector3(0, 0.75 + k * 0.25, 0.75), [Color("c1121f"), Color("ffc300")][k])
	for side in [-1, 1]:
		var t := Mk.label(self, "JUMBO", Vector3(side * (s.x / 2.0 + 0.03), 1.75, 0.75), 90, Color("c1121f"), false)
		t.rotation.y = side * PI / 2.0
		t.outline_modulate = Color.WHITE


## Jeep militaire kaki avec bâche à l'arrière, roue de secours et inscription ARMÉE.
func _build_army(s: Vector3) -> void:
	var olive := Color("4b5320")
	var dark := Color("2f3414")
	Mk.box(self, Vector3(s.x, 0.7, s.z), Vector3(0, 0.75, 0), olive)
	Mk.box(self, Vector3(s.x - 0.1, 0.12, 1.5), Vector3(0, 1.15, -s.z / 2.0 + 0.8), olive.darkened(0.1)) # capot
	var ws := Mk.box(self, Vector3(s.x - 0.2, 0.6, 0.06), Vector3(0, 1.45, -0.6), _glass())
	ws.rotation.x = 0.3
	Mk.box(self, Vector3(s.x - 0.1, 0.9, 2.4), Vector3(0, 1.55, 0.95), dark) # bâche
	for k in 3:
		Mk.box(self, Vector3(s.x - 0.05, 0.06, 0.08), Vector3(0, 2.02, 0.0 + k * 0.95), olive) # arceaux
	var spare := Mk.cyl(self, 0.36, 0.36, 0.22, Vector3(0, 1.0, s.z / 2.0 + 0.12), Color("111111"), false, 12)
	spare.rotation.x = PI / 2.0
	Mk.box(self, Vector3(s.x + 0.02, 0.1, s.z + 0.02), Vector3(0, 0.42, 0), Color("1e2210")) # bas de caisse
	for side in [-1, 1]:
		var t := Mk.label(self, "ARMÉE", Vector3(side * (s.x / 2.0 + 0.02), 0.85, -0.6), 40, Color("e9e4d8"), false)
		t.rotation.y = side * PI / 2.0
	var star := Mk.cyl(self, 0.22, 0.22, 0.02, Vector3(0, 1.22, -s.z / 2.0 + 0.8), Color("e9e4d8"), false, 5)
	star.rotation.x = 0.1


func _glass() -> Color:
	return Color("161c24")


## Taxi à hayon jaune, damier noir sur les flancs et enseigne TAXI.
func _build_taxi(s: Vector3) -> void:
	var yellow := Color("f5c400")
	var glass := _glass()
	var L := s.z
	Mk.box(self, Vector3(s.x, 0.62, L), Vector3(0, 0.66, 0), yellow)
	var hood := Mk.box(self, Vector3(s.x - 0.06, 0.14, 1.3), Vector3(0, 0.98, -L / 2.0 + 0.72), yellow)
	hood.rotation.x = -0.1
	Mk.box(self, Vector3(s.x - 0.14, 0.5, 1.95), Vector3(0, 1.22, 0.4), glass)
	Mk.box(self, Vector3(s.x - 0.18, 0.07, 1.8), Vector3(0, 1.5, 0.45), yellow)
	var ws := Mk.box(self, Vector3(s.x - 0.16, 0.74, 0.05), Vector3(0, 1.18, -0.78), glass)
	ws.rotation.x = 0.95
	var hatch := Mk.box(self, Vector3(s.x - 0.16, 0.6, 0.05), Vector3(0, 1.17, 1.48), glass)
	hatch.rotation.x = -0.5
	for side in [-1, 1]:
		var x: float = side * (s.x - 0.14) / 2.0
		Mk.box(self, Vector3(0.05, 0.5, 0.12), Vector3(x, 1.22, 0.3), yellow) # montant central
		Mk.box(self, Vector3(0.18, 0.1, 0.09), Vector3(side * (s.x / 2.0 + 0.08), 1.05, -0.6), yellow) # rétroviseur
		# Damier noir et jaune
		for k in 14:
			for row in 2:
				if (k + row) % 2 == 0:
					Mk.box(self, Vector3(0.02, 0.12, 0.12), Vector3(side * (s.x / 2.0 + 0.005), 0.78 + row * 0.12, -0.95 + k * 0.12), Color("111111"))
	# Face avant : calandre, phares, pare-chocs
	Mk.box(self, Vector3(0.8, 0.22, 0.05), Vector3(0, 0.72, -L / 2.0 - 0.01), Color("151515"))
	for side in [-1, 1]:
		Mk.box(self, Vector3(0.4, 0.12, 0.05), Vector3(side * 0.6, 0.88, -L / 2.0 - 0.01), Color("fff3b0"), false, Mk.mat(Color("fff3b0"), 1.5))
		Mk.box(self, Vector3(0.3, 0.12, 0.05), Vector3(side * 0.62, 0.88, L / 2.0 + 0.01), Color("d00000"), false, Mk.mat(Color("d00000"), 1.2))
	Mk.box(self, Vector3(s.x + 0.02, 0.18, 0.14), Vector3(0, 0.44, -L / 2.0), Color("2a2a2a"))
	Mk.box(self, Vector3(s.x + 0.02, 0.18, 0.14), Vector3(0, 0.44, L / 2.0), Color("2a2a2a"))
	# Enseigne lumineuse
	Mk.box(self, Vector3(0.75, 0.22, 0.28), Vector3(0, 1.66, 0.45), yellow, false, Mk.mat(yellow, 0.4))
	for face in [-1, 1]:
		var t := Mk.label(self, "TAXI", Vector3(0, 1.66, 0.45 + face * 0.15), 30, Color("111111"), false)
		t.outline_size = 0
		t.rotation.y = 0.0 if face > 0 else PI
	Mk.cyl(self, 0.01, 0.01, 0.6, Vector3(0, 1.82, 1.2), Color("222222"), false, 4) # antenne


## Autocar : grand pare-brise, bandeau de vitres, rétroviseurs en « antennes », deux essieux arrière.
## stripes : [[hauteur, épaisseur, couleur], ...]
func _build_coach(s: Vector3, body: Color, cap: Color, stripes: Array) -> void:
	var glass := _glass()
	var W := s.x
	var L := s.z
	var base := 0.45
	Mk.box(self, Vector3(W, 1.35, L), Vector3(0, base + 0.675, 0), body) # caisse et soutes
	Mk.box(self, Vector3(W + 0.02, 1.1, L - 1.7), Vector3(0, base + 1.9, 0.65), glass) # vitres latérales
	Mk.box(self, Vector3(W, 0.5, L - 0.25), Vector3(0, base + 2.7, 0.12), body) # toit
	Mk.box(self, Vector3(W - 0.4, 0.22, L * 0.4), Vector3(0, base + 3.05, 1.2), body.darkened(0.06)) # climatisation
	# Montants entre les vitres
	for k in 6:
		for side in [-1, 1]:
			Mk.box(self, Vector3(0.03, 1.1, 0.12), Vector3(side * (W / 2.0 + 0.012), base + 1.9, -3.6 + k * 1.75), glass.lightened(0.15))
	# Face avant
	var ws := Mk.box(self, Vector3(W - 0.1, 1.85, 0.08), Vector3(0, base + 1.95, -L / 2.0 + 0.12), glass)
	ws.rotation.x = -0.08
	Mk.box(self, Vector3(W - 0.04, 0.42, 0.14), Vector3(0, base + 3.0, -L / 2.0 + 0.06), cap) # visière
	Mk.box(self, Vector3(W - 0.3, 0.32, 0.06), Vector3(0, base + 0.95, -L / 2.0 - 0.01), Color("111111")) # bandeau
	Mk.box(self, Vector3(W - 0.6, 0.06, 0.06), Vector3(0, base + 0.7, -L / 2.0 - 0.01), Color("c9ccd1")) # baguette chromée
	for side in [-1, 1]:
		Mk.box(self, Vector3(0.55, 0.14, 0.06), Vector3(side * 0.85, base + 0.78, -L / 2.0 - 0.02), Color("fff3b0"), false, Mk.mat(Color("fff3b0"), 1.5))
		Mk.box(self, Vector3(0.25, 0.5, 0.06), Vector3(side * (W / 2.0 - 0.2), base + 1.2, L / 2.0 + 0.01), Color("d00000"), false, Mk.mat(Color("d00000"), 1.2))
		# Rétroviseur « antenne » : bras vers l'avant puis vers le bas
		Mk.box(self, Vector3(0.12, 0.12, 0.75), Vector3(side * (W / 2.0 + 0.06), base + 2.95, -L / 2.0 - 0.3), body)
		Mk.box(self, Vector3(0.14, 0.6, 0.16), Vector3(side * (W / 2.0 + 0.06), base + 2.62, -L / 2.0 - 0.62), body)
		# Portes de soute et grille moteur
		for k in 4:
			Mk.box(self, Vector3(0.02, 0.85, 0.04), Vector3(side * (W / 2.0 + 0.01), base + 0.72, -2.4 + k * 1.9), body.darkened(0.35))
		Mk.box(self, Vector3(0.02, 0.7, 0.8), Vector3(side * (W / 2.0 + 0.01), base + 1.0, L / 2.0 - 0.7), Color("2a2a2a"))
		# Passages de roues
		for z in [-L / 2.0 + 2.4, L / 2.0 - 2.62]:
			Mk.box(self, Vector3(0.02, 0.62, 1.25 if z < 0.0 else 2.5), Vector3(side * (W / 2.0 + 0.008), base + 0.18, z), Color("1a1a1a"))
	for st in stripes:
		Mk.box(self, Vector3(W + 0.03, st[1], L - 0.9), Vector3(0, base + float(st[0]), 0.25), st[2])
	for x in [-0.6, 0.6]:
		Mk.cyl(self, 0.015, 0.015, 0.7, Vector3(x, base + 3.25, -L / 2.0 + 1.2), Color("222222"), false, 4) # antennes


# --- Conduite ----------------------------------------------------------------

func set_driver(d) -> void:
	driver = d
	if d:
		if fuel < 0.0:
			fuel = randf_range(30.0, 85.0)
		ai_enabled = false
		chasing = false
		_motion_yaw = rotation.y
		_steer_in = 0.0
		# Prise en main en douceur : vitesse contrôlée dès qu'on monte
		speed = clampf(speed * 0.4, 0.0, 3.5)
		_make_lights()
		set_process(true)
		if vehicle_type in RADIO_TYPES:
			Audio.set_radio(true)
	else:
		Audio.set_engine(false)
		Audio.set_radio(false)
		Audio.set_screech(0.0)
		if _brake_mat:
			_brake_mat.emission_energy_multiplier = 0.0
			_reverse_mat.emission_energy_multiplier = 0.0
		if _headlight:
			_headlight.visible = false
		if _body:
			_body.rotation = Vector3.ZERO
	if _rider:
		_rider.visible = (d == null) if vehicle_type == "charette" else (d != null)


## Fait rouler le véhicule dans la circulation, à partir du tronçon from → to du réseau routier.
func start_traffic(city, from: int, to: int) -> void:
	ai_city = city
	ai_from = from
	ai_to = to
	ai_enabled = true
	chasing = false
	var a: Vector3 = city.node_pos[from]
	var target: Vector3 = city.lane_point(from, to)
	global_position = a.lerp(target, 0.3) + Vector3(0, 0.2, 0)
	var d := target - global_position
	rotation.y = atan2(-d.x, -d.z)
	speed = 6.0
	_ai_blocked = 0.0
	if _rider:
		_rider.visible = true # moto du trafic : son conducteur


## Replace le véhicule dans la circulation entre min_d et max_d mètres de `near` (hors de vue).
func respawn_in_traffic(city, near: Vector3, min_d: float, max_d: float) -> void:
	var a: int = city.random_node_around(near, min_d, max_d, "drive")
	var nb: PackedInt32Array = city.drive_neighbors(a)
	if nb.is_empty():
		return
	# Jamais au départ d'une impasse (on n'en ressortirait qu'en demi-tour)
	var open: Array = []
	for o in nb:
		if not city.is_dead_end(a, o):
			open.append(o)
	if open.is_empty():
		for k in 4:
			a = city.random_node_around(near, min_d, max_d, "drive")
			nb = city.drive_neighbors(a)
			for o in nb:
				if not city.is_dead_end(a, o):
					open.append(o)
			if not open.is_empty():
				break
	if open.is_empty():
		if nb.is_empty():
			return
		open = Array(nb)
	start_traffic(city, a, open[city.rng.randi() % open.size()])


## Suit un itinéraire (positions) ; loop = ligne de bus en boucle. stops : indice → nom d'arrêt.
func follow_route(points: PackedVector3Array, loop: bool, stops := {}) -> void:
	if points.size() < 2:
		return
	route_pts = points
	route_loop = loop
	route_stops = stops
	route_i = 1
	route_active = true
	ai_enabled = false
	chasing = false
	_dwell = 0.0


## Reprend la circulation normale depuis l'endroit où se trouve le véhicule.
func resume_traffic() -> void:
	route_active = false
	hold = false
	if ai_city == null:
		return
	var a: int = ai_city.nearest_node(global_position, "drive")
	var nb: PackedInt32Array = ai_city.drive_neighbors(a)
	if nb.is_empty():
		return
	ai_from = a
	ai_to = nb[ai_city.rng.randi() % nb.size()]
	ai_enabled = true


func set_passenger(p) -> void:
	passenger = p
	if vehicle_type in RADIO_TYPES and p != null:
		Audio.set_radio(true)
	elif p == null and driver == null:
		Audio.set_radio(false)


## Point visé sur l'itinéraire, décalé sur la voie de droite.
func _route_target() -> Vector3:
	var prev := route_pts[route_i - 1]
	var target := route_pts[route_i]
	var seg := target - prev
	seg.y = 0.0
	if seg.length() > 0.1:
		var d := seg.normalized()
		target += Vector3(-d.z, 0, d.x) * 2.3
	return target


func _route_drive(delta: float) -> Vector2:
	if _dwell > 0.0:
		_dwell -= delta
		return Vector2.ZERO
	# Coincé contre un obstacle : petite marche arrière pour se dégager
	if _reverse_t > 0.0:
		_reverse_t -= delta
		return Vector2(0.6, -5.0)
	if absf(speed) > 3.0 and get_real_velocity().length() < 0.5:
		_stuck_t += delta
		if _stuck_t > 2.0:
			_stuck_t = 0.0
			_reverse_t = 1.2
	else:
		_stuck_t = 0.0
	var target := _route_target()
	var to := target - global_position
	to.y = 0.0
	# Les points OSM peuvent être très rapprochés : on avance jusqu'au premier point assez loin.
	var guard := 0
	while to.length() < 4.5 and guard < 8:
		guard += 1
		if route_stops.has(route_i):
			_dwell = 5.0
			reached_stop.emit(route_stops[route_i])
		route_i += 1
		if route_i >= route_pts.size():
			if route_loop:
				route_i = 1
			else:
				route_active = false
				route_finished.emit()
				return Vector2.ZERO
		if _dwell > 0.0:
			return Vector2.ZERO
		target = _route_target()
		to = target - global_position
		to.y = 0.0
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - rotation.y, -PI, PI)
	var steer := clampf(diff * 2.5, -1.0, 1.0)
	var tgt := minf(max_speed * 0.55, 12.0)
	if absf(diff) > 0.3:
		tgt = 7.0 if absf(diff) < 0.8 else 4.0
	# Ralentir à l'approche d'un arrêt de bus
	for k in range(route_i, mini(route_i + 3, route_pts.size())):
		if route_stops.has(k):
			var d_stop := global_position.distance_to(route_pts[k])
			if d_stop < 24.0:
				tgt = minf(tgt, maxf(1.8, d_stop * 0.25))
	# Feux de circulation pour les bus de ligne
	if ai_city and ai_city.lights:
		var n_sig: int = ai_city.lights.nearest_signal(global_position, 34.0)
		if n_sig >= 0:
			var d_sig: Vector3 = ai_city.node_pos[n_sig] - global_position
			d_sig.y = 0.0
			var fwd := -global_transform.basis.z
			if d_sig.normalized().dot(fwd) > 0.35:
				var dist_sig := d_sig.length()
				var j_rad: float = ai_city.junction_radius(n_sig)
				if ai_city.lights.is_red_dir(n_sig, -fwd):
					if dist_sig < j_rad + 24.0 and dist_sig > j_rad * 0.5:
						tgt = minf(tgt, maxf(0.0, (dist_sig - j_rad - 2.0) * 0.85))
						if dist_sig <= j_rad + 2.5:
							tgt = 0.0 # Le bus s'arrête au feu rouge
	if _obstacle_ahead():
		_ai_blocked += delta
		if _ai_blocked < 4.0:
			tgt = 0.0
		elif _ai_blocked > 6.0:
			_ai_blocked = 0.0
		# Bloqué : un coup de klaxon, comme à Dakar (seulement près de la caméra)
		if _ai_blocked > 1.5 and not _honked:
			_honked = true
			_honk()
	else:
		_ai_blocked = 0.0
		_honked = false
	return Vector2(steer, tgt)


func _honk() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_to(global_position) > 45.0 or randf() < 0.4:
		return
	var p := Audio.make_3d("horn", -4.0, 50.0)
	p.position.y = 1.0
	p.pitch_scale = randf_range(0.85, 1.2)
	add_child(p)
	p.finished.connect(p.queue_free)


## Fin de poursuite : la patrouille reprend sa ronde ailleurs, hors de vue du joueur.
func resume_patrol(near: Vector3) -> void:
	chasing = false
	if ai_city == null:
		return
	respawn_in_traffic(ai_city, near, 150.0, 300.0)


func _physics_process(delta: float) -> void:
	# Loin de la caméra, une voiture du trafic n'est calculée qu'une image physique sur trois
	# (avec le temps cumulé) : même trajet, trois fois moins de calcul.
	var lod_mult := 1.0
	if lod_far and driver == null and not chasing and not route_active and not hold:
		_lod_acc += delta
		_lod_n += 1
		if _lod_n % 3 != 0:
			return
		lod_mult = _lod_acc / delta
		delta = _lod_acc
		_lod_acc = 0.0
	elif _lod_acc > 0.0:
		_lod_acc = 0.0
	_hit_cooldown -= delta
	_crime_cooldown -= delta
	var steer := 0.0
	if driver:
		if Input.is_action_just_pressed("horn"):
			Audio.play_sfx("horn")
		if Input.is_action_just_pressed("radio") and vehicle_type in RADIO_TYPES:
			Audio.toggle_radio()
		var inp: Vector2 = GameState.get_move_input()
		var throttle := -inp.y
		# Essence : environ 15 km pour un réservoir plein ; à sec, le moteur ne tire plus
		fuel = maxf(0.0, fuel - absf(speed) * delta * FUEL_PER_M)
		GameState.add_skill("conduite", absf(speed) * delta / 400.0)
		if fuel <= 0.0:
			throttle = minf(throttle, 0.0)
			if not _dry_warned:
				_dry_warned = true
				GameState.notify.emit("Panne d'essence ! Pousse jusqu'à une station-service ou fais venir un autre véhicule.")
		else:
			_dry_warned = false
		# Moteur cassé (accidents) : plus rien ne tire, il faut un mécanicien ou une dépanneuse
		if condition <= 0.0:
			throttle = minf(throttle, 0.0)
			if not _broken_warned:
				_broken_warned = true
				GameState.notify.emit("Moteur cassé ! Appelle un mécanicien (Services) ou fais venir un autre véhicule.")
		else:
			_broken_warned = false
		# Volant progressif : on tourne et on recentre en douceur (clavier comme écran tactile)
		var want := -inp.x
		_steer_in = move_toward(_steer_in, want, delta * (4.5 if absf(want) > absf(_steer_in) else 7.0))
		steer = _steer_in
		_braking = (throttle < -0.05 and speed > 0.5) or (throttle > 0.05 and speed < -0.5) or Input.is_action_pressed("jump")
		var target_speed := 0.0
		var rate := accel
		if throttle > 0.05:
			target_speed = max_speed * throttle * (0.55 if condition < 35.0 else 1.0)
		elif throttle < -0.05:
			if speed > 0.5:
				rate = 22.0
			else:
				target_speed = max_speed * 0.35 * throttle
		else:
			rate = 4.0
		if Input.is_action_pressed("jump"):
			target_speed = 0.0
			rate = 30.0
		speed = move_toward(speed, target_speed, rate * delta)
		# Moteur : le régime monte puis retombe à chaque passage de vitesse (5 rapports)
		var r := clampf(absf(speed) / max_speed, 0.0, 1.0)
		var gear := mini(int(r * 5.0), 4)
		var in_gear := r * 5.0 - gear
		if vehicle_type == "charette":
			Audio.set_engine(false)
		elif vehicle_type == "brt":
			Audio.set_engine(true, 0.28 + r * 0.35)
			Audio.set_engine_load(absf(throttle) * 0.4)
		else:
			Audio.set_engine(true, ENGINE_PITCH.get(vehicle_type, 0.75) + 0.25 + in_gear * 0.85 + gear * 0.1)
			Audio.set_engine_load(absf(throttle))
	elif hold:
		speed = move_toward(speed, 0.0, 14.0 * delta)
	elif route_active:
		var r := _route_drive(delta)
		steer = r.x
		speed = move_toward(speed, r.y, (accel if r.y > speed else 14.0) * delta)
	elif chasing:
		var r := _chase_drive(delta)
		steer = r.x
		speed = move_toward(speed, r.y, (accel if absf(r.y) > absf(speed) else 18.0) * delta)
	elif ai_enabled:
		var r := _ai_drive(delta)
		steer = r.x
		speed = move_toward(speed, r.y, (accel if r.y > speed else 14.0) * delta)
	else:
		speed = move_toward(speed, 0.0, 6.0 * delta)

	var steer_factor := clampf(absf(speed) / 5.0, 0.0, 1.0) * lerpf(1.0, 0.6, absf(speed) / max_speed)
	rotation.y += steer * steer_speed * steer_factor * delta * signf(speed)

	var fwd := -global_transform.basis.z
	if driver:
		# Adhérence : à haute vitesse (et au frein à main) la voiture glisse un peu dans les virages
		var grip := lerpf(10.0, 3.0, clampf(absf(speed) / max_speed, 0.0, 1.0))
		if Input.is_action_pressed("jump"):
			grip *= 0.3
		_motion_yaw = lerp_angle(_motion_yaw, rotation.y, 1.0 - exp(-grip * delta))
		slip = angle_difference(rotation.y, _motion_yaw)
		speed *= 1.0 - minf(absf(slip) * 0.5 * delta, 0.05)
		fwd = Vector3(-sin(_motion_yaw), 0.0, -cos(_motion_yaw))
		_drive_feel(delta, steer)
	else:
		_motion_yaw = rotation.y
		slip = 0.0
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= 25.0 * delta
	var pre := velocity
	if lod_mult > 1.0:
		velocity *= lod_mult # move_and_slide avance d'une image physique : on couvre le temps cumulé
	move_and_slide()
	if lod_mult > 1.0:
		velocity /= lod_mult
	_handle_collisions(pre)
	if driver:
		_check_pedestrians()
		_check_red_light(delta)
		_check_stop_sign(delta)
	for w in _wheels:
		w.rotate_object_local(_wheel_axis, -speed * delta / _wheel_r)
	if vehicle_type == "charette":
		_update_horse_animation(delta)


## Sensations de conduite du joueur : carrosserie qui penche et plonge, crissement des pneus
func _drive_feel(delta: float, steer: float) -> void:
	_crash_cd -= delta
	var acc := (speed - _prev_speed) / maxf(delta, 0.001)
	_prev_speed = speed
	var r := clampf(absf(speed) / max_speed, 0.0, 1.0)
	if _body:
		var roll := clampf(-steer * r * 0.07 + slip * 0.18, -0.12, 0.12) # vers l'extérieur du virage
		var dive := clampf(acc * 0.006, -0.06, 0.05)
		_body.rotation.z = lerpf(_body.rotation.z, roll, 1.0 - exp(-6.0 * delta))
		_body.rotation.x = lerpf(_body.rotation.x, dive, 1.0 - exp(-6.0 * delta))
	var skid := 0.0
	if absf(speed) > 6.0:
		skid = maxf((absf(slip) - 0.1) * 4.0, 0.0)
		if _braking and acc < -12.0:
			skid = maxf(skid, 0.6)
	Audio.set_screech(skid)


## Feux stop, feux de recul et phares (voiture du joueur seulement)
func _make_lights() -> void:
	if _brake_mat != null:
		return
	_body = get_node_or_null("Modele")
	_brake_mat = StandardMaterial3D.new()
	_brake_mat.albedo_color = Color("5a0b0b")
	_brake_mat.emission_enabled = true
	_brake_mat.emission = Color("ff1a1a")
	_reverse_mat = StandardMaterial3D.new()
	_reverse_mat.albedo_color = Color("cccccc")
	_reverse_mat.emission_enabled = true
	_reverse_mat.emission = Color("fff8e0")
	var parent: Node3D = _body if _body else self
	for sx in [-1.0, 1.0]:
		Mk.box(parent, Vector3(size.x * 0.16, size.y * 0.07, 0.05), Vector3(sx * size.x * 0.36, size.y * 0.5, size.z / 2.0 + 0.02), Color.WHITE, false, _brake_mat)
		Mk.box(parent, Vector3(size.x * 0.08, size.y * 0.05, 0.05), Vector3(sx * size.x * 0.2, size.y * 0.42, size.z / 2.0 + 0.02), Color.WHITE, false, _reverse_mat)
	if Graphics.get_value("lamp_lights") > 0:
		_headlight = SpotLight3D.new()
		_headlight.position = Vector3(0, size.y * 0.45, -size.z / 2.0 - 0.1)
		_headlight.rotation.x = -0.08
		_headlight.spot_range = 32.0
		_headlight.spot_angle = 38.0
		_headlight.light_energy = 2.2
		_headlight.light_color = Color("fff4dc")
		_headlight.visible = false
		parent.add_child(_headlight)


func _update_lights() -> void:
	if _brake_mat == null:
		return
	var h := GameState.game_minutes / 60.0
	var night := h < 6.8 or h > 19.2
	_brake_mat.emission_energy_multiplier = 4.0 if _braking else (0.8 if night else 0.0)
	_reverse_mat.emission_energy_multiplier = 3.0 if speed < -0.5 else 0.0
	if _headlight:
		_headlight.visible = night


func _handle_collisions(pre: Vector3) -> void:
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) > 0.7:
			continue
		var impact := -n.dot(Vector3(pre.x, 0, pre.z))
		var other = col.get_collider()
		if driver and impact > 5.0 and _crime_cooldown <= 0.0 and other != null and other.get("vehicle_type") == "police":
			_crime_cooldown = 3.0
			GameState.add_wanted(1, "Tu as percuté une voiture de police !")
		if impact > 4.0:
			speed *= 0.35
			if driver and impact > 5.0 and _crash_cd <= 0.0:
				_crash_cd = 0.8
				Audio.play_sfx("crash", clampf(-16.0 + impact, -14.0, 0.0))
			if driver and impact > 8.0 and _crash_cd > 0.75:
				var before := condition
				condition = maxf(0.0, condition - impact * 1.2 * (1.0 - 0.05 * GameState.skill_level("conduite")))
				if before >= 35.0 and condition < 35.0:
					GameState.notify.emit("Le moteur fume ! Il tire moins : passe au garage ou appelle un mécanicien.")
			if driver and impact > 14.0 and _hit_cooldown <= 0.0:
				_hit_cooldown = 1.0
				GameState.damage(8.0, "Aïe ! Accident à %d km/h." % int(impact * 3.6))


## Feu rouge grillé : une étoile si la police ou l'armée est à moins de 60 m.
func _check_red_light(delta: float) -> void:
	_light_check -= delta
	if _light_check > 0.0 or ai_city == null or ai_city.lights == null:
		return
	_light_check = 0.2
	var n: int = ai_city.lights.nearest_signal(global_position, 6.0)
	if n == -1:
		_last_light = -1
		return
	if n == _last_light or absf(speed) < 6.0:
		return
	_last_light = n
	if not ai_city.lights.is_red_dir(n, global_transform.basis.z * signf(speed)):
		return
	var seen := false
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v != self and v.vehicle_type in ["police", "army"] and v.global_position.distance_to(global_position) < 60.0:
			seen = true
			break
	if seen:
		GameState.add_wanted(1, "Feu rouge grillé devant la police !")
	else:
		GameState.notify.emit("Tu as grillé un feu rouge...")


func _check_pedestrians() -> void:
	if absf(speed) < 3.0:
		return
	for p in get_tree().get_nodes_in_group("pedestrians"):
		if p.knocked or not p.visible:
			continue
		var local := to_local(p.global_position)
		if absf(local.x) < size.x / 2.0 + 0.4 and absf(local.z) < size.z / 2.0 + 0.5 and local.y > -1.0 and local.y < 2.5:
			p.hit_by_vehicle()
			Audio.play_sfx("thud")
			GameState.add_wanted(1, "Passant renversé ! La police te recherche.")


func _ai_drive(delta: float) -> Vector2:
	if ai_city == null:
		return Vector2.ZERO
	# Suivi de voie : on vise un point de SA voie quelques mètres devant (et non le bout de la rue,
	# qui faisait couper les virages et rouler à gauche ou sur le trottoir)
	var pos2 := Vector2(global_position.x, global_position.z)
	var ln := _lane_line(ai_from, ai_to)
	var along: float = (pos2 - ln[0]).dot(ln[1])
	# Écartée de son tronçon (poussée, choc, reprise après une ligne) : on repart de la rue la plus proche,
	# dans le sens où l'on regarde
	var closest := Geometry2D.get_closest_point_to_segment(pos2, ln[0], ln[0] + ln[1] * float(ln[2]))
	if pos2.distance_to(closest) > 12.0:
		_reacquire()
		ln = _lane_line(ai_from, ai_to)
		along = (pos2 - ln[0]).dot(ln[1])
	var end_p: Vector2 = ln[0] + ln[1] * float(ln[2])
	if ai_next < 0 or _next_for != ai_to:
		ai_next = ai_city.next_node(ai_from, ai_to, "drive", MIN_ROAD.get(vehicle_type, 0.0))
		_next_for = ai_to
	# Déjà engagée sur la rue suivante (virage pris à la corde) : on passe au tronçon suivant
	var on_next := false
	if ai_next >= 0 and ai_next != ai_from and along > float(ln[2]) * 0.5:
		var lnn := _lane_line(ai_to, ai_next)
		var along_n: float = (pos2 - lnn[0]).dot(lnn[1])
		var cn := Geometry2D.get_closest_point_to_segment(pos2, lnn[0], lnn[0] + lnn[1] * float(lnn[2]))
		on_next = along_n > 0.5 and pos2.distance_to(cn) < pos2.distance_to(closest)
	if on_next or (along >= float(ln[2]) - 0.5 and pos2.distance_to(end_p) < 12.0):
		var nxt0: int = ai_next
		ai_from = ai_to
		ai_to = nxt0
		ai_next = -1
		ln = _lane_line(ai_from, ai_to)
		along = (pos2 - ln[0]).dot(ln[1])
	if ai_next < 0 or _next_for != ai_to:
		ai_next = ai_city.next_node(ai_from, ai_to, "drive", MIN_ROAD.get(vehicle_type, 0.0))
		_next_for = ai_to
	var L: float = ln[2]
	var look := clampf(4.0 + absf(speed) * 0.6, 5.0, 12.0)
	var target2: Vector2
	var turn := 0.0
	if ai_next >= 0 and ai_next != ai_to:
		var ln2 := _lane_line(ai_to, ai_next)
		turn = absf((ln[1] as Vector2).angle_to(ln2[1]))
	if along + look <= L or ai_next < 0:
		target2 = ln[0] + ln[1] * clampf(along + look, 0.0, L)
	elif ai_next == ai_from:
		# Demi-tour : on vise loin sur la voie d'en face (un point trop proche fait tourner en rond)
		var ln2 := _lane_line(ai_to, ai_next)
		target2 = ln2[0] + ln2[1] * minf(maxf(L - along, 0.0) + 10.0, ln2[2])
	else:
		var ln2 := _lane_line(ai_to, ai_next)
		target2 = ln2[0] + ln2[1] * minf(along + look - L, ln2[2])
	var to := Vector3(target2.x - global_position.x, 0.0, target2.y - global_position.z)
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - rotation.y, -PI, PI)
	var steer := clampf(diff * 2.5, -1.0, 1.0)
	# Demi-tour (cul-de-sac) ou voie trop serrée pour le rayon de braquage : manœuvre en marche arrière,
	# braquée à l'opposé, puis on repart en avant (au lieu de tourner en rond)
	# Sens de la manœuvre choisi une fois pour toutes (cible juste derrière : à gauche, comme un vrai demi-tour)
	if absf(diff) < 1.2:
		_turn_dir = 0.0
	elif _turn_dir == 0.0 and absf(diff) > 1.75:
		_turn_dir = signf(diff) if absf(diff) < 2.8 else 1.0
	if _turn_back > 0.0:
		_turn_back -= delta
		return Vector2(-_turn_dir, -2.5)
	if absf(diff) > 1.75:
		# Point dans le cercle de braquage (inatteignable en avançant) : marche arrière ; sinon on braque à fond
		var r_turn := 5.0 / maxf(steer_speed, 0.1)
		var left := Vector2(-cos(rotation.y), sin(rotation.y))
		var centre := pos2 + left * r_turn * _turn_dir
		if centre.distance_to(target2) > r_turn * 1.1:
			return Vector2(_turn_dir, 3.0)
		if absf(speed) < 0.6:
			_turn_back = 1.6
		return Vector2(_turn_dir, 0.0)
	if _turn_dir != 0.0:
		return Vector2(_turn_dir, 3.0) # on finit de tourner en avançant doucement
	var cruise := minf(max_speed * 0.5, 12.0)
	var tgt := cruise if absf(diff) < 0.3 else (7.0 if absf(diff) < 0.8 else 4.0)
	# On ralentit AVANT un virage (plus il est serré, plus on ralentit), pas une fois dedans
	if turn > 0.35:
		var v_turn := lerpf(9.0, 4.0, clampf((turn - 0.35) / 1.2, 0.0, 1.0))
		tgt = minf(tgt, v_turn + maxf(0.0, L - along - 4.0) * 0.45)
	# Feu tricolore : arrêt net et propre avant le carrefour
	var light: int = ai_city.lights.state_for(ai_to, ai_from) if ai_city.lights != null else 0
	if light != 0:
		var lnp: Vector3 = ai_city.node_pos[ai_to]
		var dn := Vector2(global_position.x - lnp.x, global_position.z - lnp.z).length()
		var line: float = ai_city.stop_distance(ai_from, ai_to) + size.z / 2.0 + 0.4
		var j_rad: float = ai_city.junction_radius(ai_to)
		# Freinage anticipé et arrêt complet tant que le feu est rouge/orange
		if dn < line + 28.0 and dn > j_rad * 0.6:
			if light == 2 or dn > line + 6.0:
				tgt = minf(tgt, maxf(0.0, (dn - line) * 0.85))
				if dn <= line + 0.4:
					tgt = 0.0 # Arrêt complet à la ligne au feu rouge
	tgt = minf(tgt, _sign_speed(delta))
	# Piéton sur la chaussée devant (passage piéton ou traversée) : on le laisse passer
	_ped_t -= delta
	if _ped_t <= 0.0:
		_ped_t = 0.15
		_ped_block = _pedestrian_ahead()
	if _ped_block:
		tgt = 0.0
	# Si le joueur est à pied tout près, ralentir pour faciliter la prise en main de l'auto ou de la moto
	var pl = GameState.player_ref
	if pl and is_instance_valid(pl) and pl.current_vehicle == null:
		var d_pl := Vector2(global_position.x - pl.global_position.x, global_position.z - pl.global_position.z).length()
		if d_pl < 6.8 and absf(global_position.y - pl.global_position.y) < 2.8:
			tgt = minf(tgt, 1.8)
	if _obstacle_ahead():
		_ai_blocked += delta
		if _ai_blocked < 4.0:
			tgt = 0.0
		elif _ai_blocked > 6.0:
			_ai_blocked = 0.0
	else:
		_ai_blocked = 0.0
	return Vector2(steer, tgt)


## Reprend la circulation depuis le nœud le plus proche, vers la rue la mieux alignée avec le capot
func _reacquire() -> void:
	var a: int = ai_city.nearest_node(global_position, "drive")
	var fwd := Vector2(-sin(rotation.y), -cos(rotation.y))
	var best := -1
	var best_dot := -INF
	for o in ai_city.drive_neighbors(a):
		var d := Vector2(ai_city.node_pos[o].x - ai_city.node_pos[a].x, ai_city.node_pos[o].z - ai_city.node_pos[a].z).normalized()
		var score := d.dot(fwd) - (1.5 if ai_city.is_dead_end(a, o) else 0.0)
		if score > best_dot:
			best_dot = score
			best = o
	if best >= 0:
		ai_from = a
		ai_to = best
		ai_next = -1


## Ligne de la voie de droite du tronçon a → b : [départ (2D), direction, longueur] (au centre si sens unique)
func _lane_line(a: int, b: int) -> Array:
	var pa: Vector3 = ai_city.node_pos[a]
	var pb: Vector3 = ai_city.node_pos[b]
	var d := Vector2(pb.x - pa.x, pb.z - pa.z)
	var L := d.length()
	if L < 0.01:
		return [Vector2(pa.x, pa.z), Vector2.UP, 0.0]
	d /= L
	var off: Vector2 = Vector2.ZERO if ai_city.is_oneway(a, b) else Vector2(-d.y, d.x) * (ai_city.edge_width(a, b) * 0.25)
	return [Vector2(pa.x, pa.z) + off, d, L]


## Panneaux : STOP (arrêt complet à la ligne, puis on repart quand le carrefour est libre),
## cédez le passage (on ralentit, on ne s'arrête que si une voiture prioritaire arrive). Vitesse maximale permise.
## On regarde aussi le carrefour d'après : les rues sont découpées en petits tronçons juste avant les carrefours.
func _sign_speed(delta: float) -> float:
	if ai_next < 0 or _next_for != ai_to:
		ai_next = ai_city.next_node(ai_from, ai_to, "drive", MIN_ROAD.get(vehicle_type, 0.0))
		_next_for = ai_to
	var np: Vector3 = ai_city.node_pos[ai_to]
	var dn := Vector2(global_position.x - np.x, global_position.z - np.z).length()
	var v := _rule_target(ai_from, ai_to, dn, delta)
	if dn < 30.0 and ai_next != ai_from:
		v = minf(v, _rule_target(ai_to, ai_next, dn + ai_city.segment_length(ai_to, ai_next), delta))
	return v


func _rule_target(from: int, to: int, dist: float, delta: float) -> float:
	var rule: int = ai_city.rule(from, to)
	var key := Vector2i(from, to)
	if rule == 0 or _rules_done.has(key):
		return INF
	var line: float = ai_city.stop_distance(from, to) + size.z / 2.0 + 0.3
	if dist > line + 18.0:
		return INF
	if key != _rule_key:
		_rule_key = key
		_rule_wait = 0.0
	if rule == ai_city.RULE_STOP:
		if dist < line + 2.0 and absf(speed) < 1.0:
			_rule_wait += delta
			if (_rule_wait > 1.2 and _junction_clear(to, from)) or _rule_wait > 7.0:
				_done(key)
				return INF
		return maxf(0.0, (dist - line) * 0.9)
	if dist < line - 0.5:
		_done(key)
		return INF
	if not _junction_clear(to, from):
		_rule_wait += delta
		if _rule_wait < 7.0:
			return maxf(0.0, (dist - line) * 0.9)
	return 5.5


func _done(key: Vector2i) -> void:
	if _rules_done.size() > 6:
		_rules_done.clear()
	_rules_done[key] = true


## Aucune autre voiture ne s'engage dans le carrefour (à moins de 14 m de son bord et qui roule vers lui)
func _junction_clear(node: int, from: int) -> bool:
	var np: Vector3 = ai_city.node_pos[node]
	var r: float = ai_city.junction_radius(node) + 14.0
	var mine := Vector2(ai_city.node_pos[from].x - np.x, ai_city.node_pos[from].z - np.z).normalized()
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == self or absf(v.speed) < 1.5:
			continue
		var rel: Vector3 = v.global_position - np
		rel.y = 0.0
		if rel.length() > r:
			continue
		var fwd: Vector3 = -v.global_transform.basis.z * signf(v.speed)
		if fwd.dot(-rel) <= 0.0 and rel.length() > 4.0:
			continue # elle s'éloigne
		if Vector2(rel.x, rel.z).normalized().dot(mine) > 0.9 and rel.length() > 4.0:
			continue # derrière nous, sur notre propre branche
		return false
	return true


## Piéton (ou joueur à pied) sur la chaussée, dans notre couloir, à moins de 9 m devant
func _pedestrian_ahead() -> bool:
	if ai_city == null:
		return false
	var who: Array = get_tree().get_nodes_in_group("pedestrians")
	var pl = GameState.player_ref
	if pl and pl.current_vehicle == null:
		who.append(pl)
	for p in who:
		if not p.visible or p.get("knocked") == true:
			continue
		var local := to_local(p.global_position)
		if local.z > -size.z / 2.0 or local.z < -size.z / 2.0 - 9.0 or absf(local.x) > size.x / 2.0 + 0.9:
			continue
		if ai_city.in_roadway(p.global_position, -0.3):
			return true
	return false


## STOP grillé par le joueur : franchir la ligne d'un STOP sans s'être arrêté. Une étoile si la police voit.
func _check_stop_sign(delta: float) -> void:
	_slow_since = 0.0 if absf(speed) < 1.5 else _slow_since + delta
	_stop_check -= delta
	if _stop_check > 0.0 or ai_city == null:
		return
	_stop_check = 0.2
	var n: int = ai_city.nearest_node(global_position, "drive")
	if n < 0:
		return
	var np: Vector3 = ai_city.node_pos[n]
	var dn := Vector2(global_position.x - np.x, global_position.z - np.z).length()
	if dn > ai_city.junction_radius(n) + 1.0:
		if dn > ai_city.junction_radius(n) + 10.0:
			_last_stop_node = -1
		return
	if n == _last_stop_node or absf(speed) < 4.0:
		return
	_last_stop_node = n
	# Branche par laquelle on arrive : celle qui est derrière nous
	var back: Vector3 = global_transform.basis.z * signf(speed)
	var from := -1
	var best := 0.5
	for o in ai_city.drive_incoming(n):
		var d: Vector3 = ai_city.node_pos[o] - np
		d.y = 0.0
		var dot := d.normalized().dot(back)
		if dot > best:
			best = dot
			from = o
	if from == -1 or ai_city.rule(from, n) != ai_city.RULE_STOP or _slow_since < 4.0:
		return
	var seen := false
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v != self and v.vehicle_type in ["police", "army"] and v.global_position.distance_to(global_position) < 60.0:
			seen = true
			break
	if seen:
		GameState.add_wanted(1, "STOP grillé devant la police !")
	else:
		GameState.notify.emit("Tu n'as pas marqué l'arrêt au STOP...")


## Poursuite : fonce vers `chase_point` (fourni par la police), ralentit près du joueur,
## recule quand elle est coincée contre un mur.
func _chase_drive(delta: float) -> Vector2:
	var to := chase_point - global_position
	to.y = 0.0
	var desired := atan2(-to.x, -to.z)
	var diff := wrapf(desired - rotation.y, -PI, PI)
	var steer := clampf(diff * 2.5, -1.0, 1.0)
	if _reverse_t > 0.0:
		_reverse_t -= delta
		return Vector2(-steer, -7.0)
	var tgt := max_speed * 0.92
	if absf(diff) > 0.7:
		tgt = 9.0
	if chase_player_dist < 14.0:
		tgt = minf(tgt, chase_player_dist * 0.7)
	if chase_player_dist < 4.5:
		tgt = 0.0
	if tgt > 3.0 and absf(speed) < 1.0:
		_stuck_t += delta
	else:
		_stuck_t = 0.0
	if _stuck_t > 1.2:
		_stuck_t = 0.0
		_reverse_t = 1.0
	return Vector2(steer, tgt)


func _obstacle_ahead() -> bool:
	var fwd := -global_transform.basis.z
	var from := global_position + Vector3(0, 0.8, 0) + fwd * (size.z / 2.0 + 0.2)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 6.0, 2 | 4, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
