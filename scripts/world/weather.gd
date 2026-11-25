extends Node3D
## Météo de Dakar : ciel dégagé, nuageux, harmattan (brume de poussière), pluie (hivernage) et orage.
## Le temps change toutes les BLOCK secondes, tiré au sort de façon déterministe à partir de l'horloge :
## en ligne, l'horloge commune du serveur donne la même météo à tous les joueurs.
## Effets : nuages (soleil voilé, ciel gris), brume, pluie (particules qui suivent la caméra), sol mouillé
## (routes et trottoirs plus sombres et brillants), flaques qui reflètent le ciel, éclairs et tonnerre,
## bruit de la pluie. Les fenêtres des immeubles s'allument la nuit.

const STATES := ["clair", "nuageux", "harmattan", "pluie", "orage"]
const WEIGHTS := [45, 25, 15, 12, 3]
const LABELS := {"clair": "Ciel dégagé", "nuageux": "Nuageux", "harmattan": "Harmattan", "pluie": "Pluie", "orage": "Orage"}
## état → [nuages, pluie, poussière]
const TARGETS := {"clair": [0.0, 0.0, 0.0], "nuageux": [0.7, 0.0, 0.0], "harmattan": [0.3, 0.0, 1.0],
	"pluie": [0.9, 0.65, 0.0], "orage": [1.0, 1.0, 0.0]}
const BLOCK := 480.0
const PUDDLE_RANGE := 90.0

var main
var state := "clair"
var cloud := 0.0
var rain := 0.0
var dust := 0.0
var wet := 0.0
var forced := ""
var _t := 0.0
var _rain_fx: CPUParticles3D
var _puddles: MultiMeshInstance3D
var _puddle_mat: ShaderMaterial
var _puddle_center := Vector3(INF, 0, INF)
var _ground_mats: Array = [] ## [matériau, rugosité, couleur]
var _window_mats: Array = []
var _rain_audio: AudioStreamPlayer
var _flash := 0.0
var _next_flash := 8.0
var _base_fog := 0.002


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather=") and a.trim_prefix("--weather=") in STATES:
			forced = a.trim_prefix("--weather=")
	# Départ : on reprend directement l'état courant, sans transition
	state = target_state()
	var tg: Array = TARGETS[state]
	cloud = tg[0]
	rain = tg[1]
	dust = tg[2]
	wet = 1.0 if rain > 0.3 else 0.0
	_base_fog = main.env.fog_density
	_collect_city_materials()
	_build_rain()
	_build_puddles()
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.volume_db = -60.0
	add_child(_rain_audio)
	Graphics.changed.connect(_on_graphics)


func label() -> String:
	return LABELS[state]


## Météo voulue pour la période en cours (identique pour tous les joueurs en ligne)
func target_state() -> String:
	if forced != "":
		return forced
	var clock: float = Net.clock() if Net.online else _t + 1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(floor(clock / BLOCK)) * 7919 + 13
	var r := rng.randi_range(0, 99)
	for i in STATES.size():
		r -= WEIGHTS[i]
		if r < 0:
			return STATES[i]
	return "clair"


func _process(delta: float) -> void:
	_t += delta
	var st := target_state()
	if st != state:
		state = st
		if st in ["pluie", "orage"]:
			GameState.notify.emit("Il commence à pleuvoir sur Dakar... (hivernage)")
		elif st == "harmattan":
			GameState.notify.emit("L'harmattan souffle : le ciel se voile de poussière.")
	var tg: Array = TARGETS[state]
	cloud = move_toward(cloud, tg[0], delta * 0.04)
	rain = move_toward(rain, tg[1], delta * 0.05)
	dust = move_toward(dust, tg[2], delta * 0.03)
	wet = move_toward(wet, 1.0 if rain > 0.15 else 0.0, delta * (0.06 if rain > 0.15 else 0.008))
	_update_rain(delta)
	_update_ground()
	_update_puddles()
	_update_storm(delta)


## Appelé par main._update_daylight() : nuages, brume et éclairs modifient le ciel et la lumière.
func apply_light(env: Environment, sky_mat: ProceduralSkyMaterial, sun: DirectionalLight3D, day: float) -> void:
	var grey := Color(0.55, 0.57, 0.6).lerp(Color(0.12, 0.13, 0.16), 1.0 - day)
	var ochre := Color("c9a46a").lerp(Color("3a3226"), 1.0 - day)
	sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(grey, cloud * 0.85).lerp(ochre, dust * 0.6)
	sky_mat.sky_horizon_color = sky_mat.sky_horizon_color.lerp(grey, cloud * 0.7).lerp(ochre, dust * 0.8)
	sky_mat.ground_horizon_color = sky_mat.ground_horizon_color.lerp(grey, cloud * 0.6)
	sun.light_energy *= 1.0 - cloud * 0.6 - dust * 0.25
	sun.shadow_opacity = 1.0 - cloud * 0.55
	env.fog_density = _base_fog * (1.0 + dust * 4.0 + rain * 2.5) * Graphics.fog_factor()
	env.fog_light_color = env.fog_light_color.lerp(grey, cloud * 0.6).lerp(ochre, dust * 0.7)
	env.ambient_light_energy *= 1.0 - cloud * 0.2
	if _flash > 0.0:
		env.ambient_light_energy += _flash * 2.5
		sky_mat.sky_top_color = sky_mat.sky_top_color.lerp(Color(0.8, 0.85, 1.0), _flash * 0.7)
	_puddle_mat.set_shader_parameter("sky_color", sky_mat.sky_horizon_color.lerp(sky_mat.sky_top_color, 0.4))
	# Fenêtres allumées la nuit
	var night := 1.0 - day
	for m in _window_mats:
		m.emission_energy_multiplier = night * 1.2 if Graphics.get_value("window_lights") else 0.0
	# Façades de la ville (city_facade.gdshader) : fenêtres allumées
	RenderingServer.global_shader_parameter_set("city_night", smoothstep(0.35, 0.8, night) if Graphics.get_value("window_lights") else 0.0)


# --- Pluie -------------------------------------------------------------------------------

func _build_rain() -> void:
	_rain_fx = CPUParticles3D.new()
	_rain_fx.top_level = true
	_rain_fx.emitting = false
	_rain_fx.lifetime = 0.9
	_rain_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain_fx.emission_box_extents = Vector3(22, 1, 22)
	_rain_fx.direction = Vector3(0.08, -1, 0.03)
	_rain_fx.spread = 2.0
	_rain_fx.gravity = Vector3.ZERO
	_rain_fx.initial_velocity_min = 20.0
	_rain_fx.initial_velocity_max = 24.0
	_rain_fx.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.65)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.82, 0.9, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	_rain_fx.mesh = q
	_rain_fx.amount = Graphics.get_value("rain")
	add_child(_rain_fx)


func _update_rain(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var indoors: bool = main.interiors != null and main.interiors.inside != ""
	var on := rain > 0.08 and not indoors
	if on != _rain_fx.emitting:
		_rain_fx.emitting = on
	_rain_fx.visible = not indoors # gouttes déjà lancées : on ne les voit pas tomber dans la salle
	_rain_fx.global_position = cam.global_position + Vector3(0, 11, 0) - cam.global_transform.basis.z * 8.0
	(_rain_fx.mesh.material as StandardMaterial3D).albedo_color.a = 0.12 + rain * 0.28
	if _rain_audio.stream == null:
		_rain_audio.stream = Audio.stream("rain")
		if _rain_audio.stream == null:
			return
	var vol := -60.0 if rain < 0.02 else lerpf(-26.0, -8.0, rain) - (14.0 if indoors else 0.0)
	_rain_audio.volume_db = vol
	if rain >= 0.02 and not _rain_audio.playing:
		_rain_audio.play()
	elif rain < 0.02 and _rain_audio.playing:
		_rain_audio.stop()


func _update_storm(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 4.0)
	if state != "orage" or rain < 0.5:
		return
	_next_flash -= delta
	if _next_flash <= 0.0:
		_next_flash = randf_range(7.0, 18.0)
		_flash = 1.0
		get_tree().create_timer(randf_range(0.6, 2.5)).timeout.connect(func(): Audio.play_sfx("thunder", -4.0))


# --- Sol mouillé et fenêtres -------------------------------------------------------------

func _collect_city_materials() -> void:
	var seen := {}
	var city_root: Node = main.city.get_node_or_null("Dakar")
	if city_root == null:
		city_root = main.city
	var lit := _lit_windows_texture()
	for mi in city_root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var m = mi.mesh.surface_get_material(s)
			if not (m is StandardMaterial3D) or seen.has(m):
				continue
			seen[m] = true
			var sm: StandardMaterial3D = m
			if sm.albedo_texture != null and sm.uv1_triplanar:
				# Murs avec fenêtres : motif de 4 x 4 fenêtres dont certaines s'allument la nuit
				sm.albedo_texture = _windows_4x4()
				sm.uv1_scale = sm.uv1_scale / 4.0
				sm.emission_enabled = true
				# Couleur chaude × masque des fenêtres allumées
				sm.emission = Color(1.0, 0.68, 0.36)
				sm.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
				sm.emission_texture = lit
				sm.emission_energy_multiplier = 0.0
				_window_mats.append(sm)
			elif sm.vertex_color_use_as_albedo and sm.albedo_texture == null:
				_ground_mats.append([sm, sm.roughness, sm.albedo_color, sm.metallic_specular])


func _update_ground() -> void:
	# Sols et façades de la ville (shaders city_ground / city_facade)
	RenderingServer.global_shader_parameter_set("city_wet", wet)
	for e in _ground_mats:
		var m: StandardMaterial3D = e[0]
		m.roughness = lerpf(e[1], 0.22, wet)
		m.metallic_specular = lerpf(e[3], 0.6, wet)
		m.albedo_color = (e[2] as Color) * lerpf(1.0, 0.72, wet)


static var _win4: ImageTexture
static var _winlit: ImageTexture


static func _windows_4x4() -> ImageTexture:
	if _win4:
		return _win4
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	for cx in 4:
		for cy in 4:
			img.fill_rect(Rect2i(cx * 64 + 20, cy * 64 + 14, 24, 30), Color(0.25, 0.3, 0.36))
			img.fill_rect(Rect2i(cx * 64 + 18, cy * 64 + 44, 28, 3), Color(0.8, 0.8, 0.8))
	img.generate_mipmaps()
	_win4 = ImageTexture.create_from_image(img)
	return _win4


static func _lit_windows_texture() -> ImageTexture:
	if _winlit:
		return _winlit
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLACK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2025
	var warm := [Color(1.0, 1.0, 1.0), Color(0.75, 0.75, 0.75), Color(0.5, 0.5, 0.5)]
	for cx in 4:
		for cy in 4:
			if rng.randf() < 0.4:
				img.fill_rect(Rect2i(cx * 64 + 20, cy * 64 + 14, 24, 30), warm[rng.randi() % warm.size()])
	img.generate_mipmaps()
	_winlit = ImageTexture.create_from_image(img)
	return _winlit


# --- Flaques -----------------------------------------------------------------------------

func _build_puddles() -> void:
	_puddle_mat = ShaderMaterial.new()
	_puddle_mat.shader = load("res://scripts/world/puddle.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	plane.material = _puddle_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = 70
	mm.visible_instance_count = 0
	_puddles = MultiMeshInstance3D.new()
	_puddles.multimesh = mm
	_puddles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puddles)


func _update_puddles() -> void:
	var count: int = 0
	if Graphics.get_value("puddles") and wet > 0.05:
		count = 40 if Graphics.profile == "moyen" else 70
	var mm := _puddles.multimesh
	_puddle_mat.set_shader_parameter("wet", wet)
	if count == 0:
		mm.visible_instance_count = 0
		return
	var pp: Vector3 = main.player.get_world_position()
	if mm.visible_instance_count == count and Vector2(pp.x - _puddle_center.x, pp.z - _puddle_center.z).length() < 35.0:
		return
	_puddle_center = pp
	var city = main.city
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pp.x / 35.0) * 92821 + int(pp.z / 35.0)
	for i in count:
		var a: int = city.random_node_around(pp, 4.0, PUDDLE_RANGE, "drive")
		var nb: PackedInt32Array = city.drive_neighbors(a)
		var p: Vector3 = city.node_pos[a]
		if not nb.is_empty():
			var b: int = nb[rng.randi() % nb.size()]
			p = p.lerp(city.node_pos[b], rng.randf_range(0.15, 0.85))
			p += Vector3(rng.randf_range(-2.0, 2.0), 0, rng.randf_range(-2.0, 2.0))
		var s := rng.randf_range(1.4, 4.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, 1.0, s * rng.randf_range(0.5, 1.0)))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, 0.085, p.z)))
	mm.visible_instance_count = count


func _on_graphics() -> void:
	_rain_fx.amount = Graphics.get_value("rain")
	_puddle_center = Vector3(INF, 0, INF)
