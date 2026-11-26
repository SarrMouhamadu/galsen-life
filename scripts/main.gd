extends Node3D
## Point d'entrée : charge le vrai Dakar, place le joueur, le trafic, les piétons et l'interface.

const Mk = preload("res://scripts/util/mk.gd")
const City = preload("res://scripts/world/dakar_city.gd")
const Player = preload("res://scripts/player/player.gd")
const CameraRig = preload("res://scripts/camera/camera_rig.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const Pedestrian = preload("res://scripts/npc/pedestrian.gd")
const JobManager = preload("res://scripts/jobs/job_manager.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const PoliceManager = preload("res://scripts/police/police_manager.gd")
const Transit = preload("res://scripts/transport/transit.gd")
const TrafficLights = preload("res://scripts/world/traffic_lights.gd")
const Market = preload("res://scripts/world/market.gd")
const Business = preload("res://scripts/jobs/business.gd")
const Gps = preload("res://scripts/ui/gps.gd")
const Arena = preload("res://scripts/world/arena.gd")
const Foot = preload("res://scripts/world/foot.gd")
const Lutte = preload("res://scripts/world/lutte.gd")
const StreetFight = preload("res://scripts/world/street_fight.gd")
const NetLutteUI = preload("res://scripts/net/net_lutte_ui.gd")
const RemotePlayers = preload("res://scripts/net/remote_players.gd")
const NetTraffic = preload("res://scripts/net/net_traffic.gd")
const NetInteract = preload("res://scripts/net/net_interact.gd")
const NetJobs = preload("res://scripts/net/net_jobs.gd")
const SocialUI = preload("res://scripts/net/social_ui.gd")
const TradeUI = preload("res://scripts/net/trade_ui.gd")
const Voice = preload("res://scripts/net/voice.gd")
const Weather = preload("res://scripts/world/weather.gd")
const StreetLamps = preload("res://scripts/world/street_lamps.gd")
const Ambience = preload("res://scripts/world/ambience.gd")
const Interiors = preload("res://scripts/world/interiors.gd")
const Employment = preload("res://scripts/jobs/employment.gd")
const Enterprises = preload("res://scripts/world/enterprises.gd")
const Housing = preload("res://scripts/world/housing.gd")
const Dealership = preload("res://scripts/vehicles/dealership.gd")
const Rental = preload("res://scripts/vehicles/rental.gd")
const Commerce = preload("res://scripts/world/commerce.gd")
const CityHall = preload("res://scripts/world/city_hall.gd")
const Prison = preload("res://scripts/police/prison.gd")
const Fishing = preload("res://scripts/world/fishing.gd")
const Cooking = preload("res://scripts/world/cooking.gd")
const Tutorial = preload("res://scripts/jobs/tutorial.gd")
const MissionManager = preload("res://scripts/jobs/mission_manager.gd")
const ShaderWarmup = preload("res://scripts/world/shader_warmup.gd")
const Stade = preload("res://scripts/world/stade.gd")
const Ter = preload("res://scripts/transport/ter.gd")

const TRAFFIC := [
	"taxi", "jakarta", "clando", "suv", "car_rapide", "grosse_moto", "charette",
	"taxi", "jakarta", "ndiaga", "clando", "police",
	"jakarta", "taxi", "car_rapide", "grosse_moto", "suv", "charette",
	"taxi", "jakarta", "ndiaga", "car_rapide", "police",
	"grosse_moto", "taxi", "jakarta", "clando", "suv", "car_rapide",
	"jakarta", "taxi", "grosse_moto", "ndiaga", "clando", "charette",
	"car_rapide", "jakarta", "taxi", "police", "grosse_moto",
	"suv", "clando", "jakarta", "taxi", "ndiaga", "car_rapide",
	"coach", "jakarta", "grosse_moto", "taxi", "clando", "charette",
	"car_rapide", "jakarta", "bus"
]
## Les voitures et piétons trop loin sont replacés près du joueur (comme dans GTA).
const PED_RECYCLE := 120.0
const ANIM_NEAR := 22.0 ## en deçà : personnages animés à chaque image
const ANIM_MID := 50.0 ## en deçà : 15 images/s, au-delà 8
const CAR_LOD := 70.0 ## au-delà : voitures du trafic calculées une image physique sur trois
const CAR_RECYCLE := 260.0

var city
var player
var camera_rig
var jobs
var police
var transit
var market
var business
var gps
var arena
var foot ## complexe de mini-foot, hors de la ville (scripts/world/foot.gd)
var stade ## stades Iba Mar Diop et Me Abdoulaye Wade (scripts/world/stade.gd)
var ter ## train express régional de Dakar (scripts/transport/ter.gd)
var street_fight ## bagarres de rue (scripts/world/street_fight.gd)
var lutte ## écuries et journées de lutte (scripts/world/lutte.gd)
var net_lutte_ui ## lutte entre joueurs (en ligne)
var remote_players
var net_jobs = null
var social_ui = null
var trade_ui = null ## fenêtre d'échange entre joueurs (mode en ligne)
var voice = null
var weather = null
var lamps = null
var interiors = null
var employment = null
var enterprises = null ## entreprises visitables (Jumbo, Jadida, Wave, Orange Money)
var housing = null
var dealership = null ## concession, véhicules à soi, essence
var rental = null ## location de véhicules
var commerce = null ## gestion des commerces achetés (employés, stock, prix)
var city_hall = null ## mairie, élections, banque en ligne
var prison = null ## garde à vue au commissariat
var fishing = null ## pêche à l'Anse Bernard
var tutorial = null ## guide des premiers pas (nouveaux joueurs)
var missions = null ## missions et quêtes de Dakar (mission_manager.gd)
var cooking = null ## cuisine à la maison
var hud
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var peds: Array = []
var traffic: Array = []
var parked: Array = [] ## voitures garées : physique endormie tant que personne n'y monte
var _patrols: Array = []
var _lod_t := 0.0
var _stuck_t := 1.0 ## prochaine vérification « coincé dans un bâtiment »


func _ready() -> void:
	# Coupure automatique de la musique d'accueil pour faire place aux sons de la ville et des véhicules
	Audio.stop_music()
	CrashReport.step("chargement de la ville")
	_build_environment()
	city = City.new()
	add_child(city)
	city.build()
	CrashReport.step("ville construite")
	# Textes de la ville (noms de lieux, panneaux) : cachés quand ils sont trop loin pour être lus
	for l in city.find_children("*", "Label3D", true, false):
		Mk.far_label(l)

	player = Player.new()
	add_child(player)
	player.global_position = city.spawn_point
	if GameState.has_saved_position:
		var saved: Vector3 = GameState.player_position
		# Une sauvegarde de l'ancienne ville peut tomber hors des rues : on revient alors au départ.
		if saved.distance_to(city.node_pos[city.nearest_node(saved, "walk")]) < 40.0:
			player.global_position = saved + Vector3(0, 1, 0)
	_spawn_vehicles()
	_spawn_pedestrians()
	CrashReport.step("voitures et passants")
	lamps = StreetLamps.new()
	lamps.main = self
	lamps.city = city
	add_child(lamps)

	# Feux tricolores
	var lights = TrafficLights.new()
	lights.city = city
	lights.player = player
	add_child(lights)
	city.lights = lights

	camera_rig = CameraRig.new()
	add_child(camera_rig)
	camera_rig.set_target(player)
	player.camera_rig = camera_rig

	jobs = JobManager.new()
	jobs.city = city
	jobs.player = player
	add_child(jobs)
	player.job_manager = jobs

	police = PoliceManager.new()
	police.main = self
	police.city = city
	police.player = player
	police.jobs = jobs
	add_child(police)
	for v in _patrols:
		police.register(v)

	hud = Hud.new()
	hud.main = self
	add_child(hud)

	# Bus, cars rapides et taxis comme passager
	transit = Transit.new()
	transit.city = city
	transit.player = player
	transit.hud = hud
	add_child(transit)
	player.transit = transit

	# Entreprises (Orange Money, Wave, Jadida, Jumbo) et marchés
	business = Business.new()
	business.city = city
	business.player = player
	business.jobs = jobs
	add_child(business)
	market = Market.new()
	market.city = city
	market.player = player
	market.hud = hud
	add_child(market)
	arena = Arena.new()
	arena.main = self
	arena.city = city
	arena.player = player
	arena.hud = hud
	add_child(arena)
	transit.arena = arena
	foot = Foot.new()
	foot.main = self
	foot.city = city
	foot.player = player
	foot.hud = hud
	add_child(foot)
	transit.foot = foot

	stade = Stade.new()
	stade.main = self
	stade.city = city
	stade.player = player
	stade.hud = hud
	add_child(stade)
	transit.stade = stade
	transit.main = self

	ter = Ter.new()
	ter.main = self
	ter.city = city
	ter.player = player
	ter.hud = hud
	add_child(ter)

	# Entreprises visitables : créées avant l'emploi (les patrons de ces entreprises sont dans leurs bureaux)
	enterprises = Enterprises.new()
	enterprises.main = self
	add_child(enterprises)
	employment = Employment.new()
	employment.main = self
	add_child(employment)
	jobs.employment = employment
	business.employment = employment
	player.providers = [enterprises, employment, arena, foot, stade, ter, business, market]
	# Mode en ligne : les autres joueurs
	remote_players = RemotePlayers.new()
	remote_players.main = self
	add_child(remote_players)
	var net_traffic = NetTraffic.new()
	net_traffic.name = "NetTraffic"
	net_traffic.city = city
	add_child(net_traffic)
	social_ui = SocialUI.new()
	social_ui.main = self
	add_child(social_ui)
	if Net.online:
		net_jobs = NetJobs.new()
		net_jobs.main = self
		add_child(net_jobs)
		trade_ui = TradeUI.new()
		trade_ui.main = self
		add_child(trade_ui)
		voice = Voice.new()
		voice.main = self
		add_child(voice)
		var ni = NetInteract.new()
		ni.main = self
		add_child(ni)
		player.providers.insert(0, ni)
		player.providers.insert(1, net_jobs)
		# Au mini-foot, « Tirer ! » et l'accueil passent avant les actions entre joueurs (joueurs collés au ballon)
		player.providers.erase(foot)
		player.providers.insert(0, foot)
	gps = Gps.new()
	gps.city = city
	gps.player = player
	add_child(gps)
	# Lutte : écuries de quartier et journées dans les stades (après le GPS et l'arène)
	lutte = Lutte.new()
	lutte.main = self
	add_child(lutte)
	player.providers.insert(player.providers.find(arena), lutte)
	if Net.online:
		net_lutte_ui = NetLutteUI.new()
		net_lutte_ui.main = self
		add_child(net_lutte_ui)
		Net.friend_joined.connect(_on_friend_joined)

	weather = Weather.new()
	weather.main = self
	add_child(weather)
	interiors = Interiors.new()
	interiors.main = self
	add_child(interiors)
	housing = Housing.new()
	housing.main = self
	add_child(housing)
	player.providers.append(housing)
	commerce = Commerce.new()
	commerce.main = self
	add_child(commerce)
	dealership = Dealership.new()
	dealership.main = self
	add_child(dealership)
	player.providers.append(dealership)
	rental = Rental.new()
	rental.main = self
	add_child(rental)
	player.providers.append(rental)
	city_hall = CityHall.new()
	city_hall.main = self
	add_child(city_hall)
	player.providers.append(city_hall)
	prison = Prison.new()
	prison.main = self
	add_child(prison)
	fishing = Fishing.new()
	fishing.main = self
	add_child(fishing)
	player.providers.append(fishing)
	cooking = Cooking.new()
	cooking.main = self
	add_child(cooking)
	tutorial = Tutorial.new()
	tutorial.main = self
	add_child(tutorial)
	missions = MissionManager.new()
	missions.main = self
	missions.city = city
	missions.player = player
	add_child(missions)
	player.providers.append(missions)
	player.providers.append(interiors)
	# Sans position sauvegardée, on se réveille chez soi
	if not GameState.has_saved_position and housing.home_position() != null:
		player.global_position = housing.home_position()
	var amb = Ambience.new()
	amb.main = self
	add_child(amb)
	_apply_graphics()
	Graphics.changed.connect(_apply_graphics)

	GameState.player_ref = player
	GameState.fainted.connect(_on_fainted)
	# Bagarres de rue (après les passants)
	street_fight = StreetFight.new()
	street_fight.main = self
	add_child(street_fight)
	_update_daylight()
	_maybe_screenshot()
	CrashReport.step("en jeu (%s)" % ("en ligne" if Net.online else "solo"))
	# Matériaux compilés quelques-uns par image derrière un écran de chargement
	var warmup := ShaderWarmup.new()
	add_child(warmup)
	await warmup.run(self)
	warmup.queue_free()
	await RenderingServer.frame_post_draw
	CrashReport.step("première image affichée")
	Graphics.watch_fps = true
	if Graphics.notice != "":
		GameState.notify.emit(Graphics.notice)
		Graphics.notice = ""
	if Net.online and Net.pending_friend_join_code != "":
		var fcode := Net.pending_friend_join_code
		Net.pending_friend_join_code = ""
		get_tree().create_timer(1.2).timeout.connect(func():
			Net.join_by_friend_code(fcode)
		)


func _on_friend_joined(ok: bool, message: String, friend_name: String, friend_pos: Vector3, friend_peer: int, _code: String) -> void:
	if not ok:
		GameState.notify.emit(message)
		return
	if is_instance_valid(player):
		player.leave_any_vehicle()
		if friend_pos != Vector3.ZERO:
			var offset := Vector3(randf_range(-2.5, 2.5), 0.5, randf_range(2.0, 3.5))
			player.global_position = friend_pos + offset
			player.velocity = Vector3.ZERO
			var ppos: Vector3 = player.global_position
			var dir := (friend_pos - ppos).normalized()
			if dir.length_squared() > 0.01:
				player.model.rotation.y = atan2(-dir.x, -dir.z)
			if gps:
				gps.set_waypoint(friend_pos, "Ami : " + friend_name)
		GameState.notify.emit("🤝 Tu as rejoint ton ami %s à Dakar !" % friend_name)
		Audio.play_sfx("coin", -6.0)
		if Net.social and friend_peer > 0:
			if Net.social.my_group == "":
				Net.social.rpc_group_invite.rpc_id(1, friend_peer)


func _process(delta: float) -> void:
	_update_daylight()
	_stuck_t -= delta
	if _stuck_t <= 0.0:
		_stuck_t = 2.0
		_unstick_player()
	_lod_t -= delta
	if _lod_t <= 0.0:
		_lod_t = 0.5
		var pp: Vector3 = player.get_world_position()
		if (arena and arena.contains(pp)) or (foot and foot.contains(pp)):
			return # à l'arène de Pikine ou au complexe de mini-foot : pas de recyclage en ville
		var cam := get_viewport().get_camera_3d()
		var cp: Vector3 = cam.global_position if cam else pp
		var char_range: float = Graphics.get_value("char_range")
		var car_range: float = Graphics.get_value("car_range")
		for p in peds:
			if _flat(p.position, pp) > PED_RECYCLE:
				_respawn_unseen(p, pp, cam, char_range)
			# Niveau de détail : les passants lointains ne sont plus dessinés ni animés
			var dcam := _flat(p.position, cp)
			var show := dcam < char_range
			if p.visible != show:
				p.visible = show
				p.process_mode = Node.PROCESS_MODE_INHERIT if show else Node.PROCESS_MODE_DISABLED
			# Animation : complète de près, 15 puis 8 images/s plus loin (le mouvement reste fluide)
			if show and p._model:
				p._model.set_anim_rate(0.0 if dcam < ANIM_NEAR else (15.0 if dcam < ANIM_MID else 8.0))
		for v in traffic:
			if is_instance_valid(v):
				var dv := _flat(v.global_position, cp)
				v.visible = dv < car_range
				v.lod_far = dv > CAR_LOD
		for v in parked:
			if is_instance_valid(v) and v.driver == null and not v.is_physics_processing():
				v.visible = _flat(v.global_position, cp) < car_range * 0.6
		for v in traffic:
			if is_instance_valid(v) and v.ai_enabled and v.driver == null and _flat(v.global_position, pp) > CAR_RECYCLE:
				v.respawn_in_traffic(city, pp, 120.0, 230.0)


## Profil graphique : ombres, distance d'affichage (+ brume qui cache le bord du monde)
func _apply_graphics() -> void:
	# Effets non gérés par le moteur de compatibilité (vieux téléphones) : désactivés là-bas
	var modern := RenderingServer.get_current_rendering_method() != "gl_compatibility"
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	env.glow_enabled = Graphics.get_value("glow")
	env.ssao_enabled = Graphics.get_value("ssao") and forward
	env.ssr_enabled = Graphics.get_value("ssr") and forward
	env.volumetric_fog_enabled = Graphics.get_value("vfog") and forward
	env.adjustment_enabled = modern or Graphics.ORDER.find(Graphics.profile) >= 2
	if not modern:
		# Vieux téléphones (OpenGL) : sans occlusion ni reflets, l'ACES écrase les ombres ; on garde l'ancien réglage
		env.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.tonemap_exposure = 0.95
	sun.shadow_enabled = Graphics.get_value("shadows")
	sun.directional_shadow_max_distance = maxf(Graphics.get_value("shadow_dist"), 1.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if Graphics.profile == "eleve" else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if Graphics.profile == "moyen" else DirectionalLight3D.SHADOW_ORTHOGONAL)
	sun.directional_shadow_blend_splits = true
	sun.shadow_normal_bias = 0.8
	if camera_rig and camera_rig.camera:
		camera_rig.camera.far = Graphics.get_value("view")
	# Ajustement dynamique du volume de trafic selon le profil graphique
	if not Net.online and is_instance_valid(city) and is_instance_valid(player):
		var target_cars: int = mini(TRAFFIC.size(), Graphics.get_value("cars"))
		var pp: Vector3 = player.global_position
		while traffic.size() < target_cars:
			var v = Vehicle.new()
			v.vehicle_type = TRAFFIC[traffic.size() % TRAFFIC.size()]
			add_child(v)
			v.respawn_in_traffic(city, pp, 40.0, 220.0)
			traffic.append(v)
			if v.vehicle_type == "police":
				v.is_patrol = true
				_patrols.append(v)
		while traffic.size() > target_cars:
			var v = traffic.pop_back()
			if is_instance_valid(v):
				if v in _patrols:
					_patrols.erase(v)
				v.queue_free()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _spawn_vehicles() -> void:
	for spot in city.parking_spots:
		var v = Vehicle.new()
		v.vehicle_type = spot["type"]
		add_child(v)
		v.global_position = spot["pos"]
		v.rotation.y = spot["yaw"]
		v.ai_city = city
		parked.append(v)
		# Pas de calcul de physique pour une voiture garée (elle se réveille quand on y monte)
		v.set_physics_process(false)
	# En ligne, le trafic vient du serveur (le même pour tous les joueurs)
	if Net.online:
		return
	var pp: Vector3 = player.global_position
	for k in mini(TRAFFIC.size(), Graphics.get_value("cars")):
		var v = Vehicle.new()
		v.vehicle_type = TRAFFIC[k]
		add_child(v)
		v.respawn_in_traffic(city, pp, 30.0, 220.0)
		traffic.append(v)
		if v.vehicle_type == "police":
			v.is_patrol = true
			_patrols.append(v)


## Replace un passant loin du joueur sans qu'on le voie apparaître : hors de la distance d'affichage,
## ou au moins hors du champ de la caméra
func _respawn_unseen(p, pp: Vector3, cam: Camera3D, char_range: float) -> void:
	var lo := minf(char_range + 5.0, PED_RECYCLE - 15.0)
	for k in 6:
		p.respawn(pp, lo, PED_RECYCLE - 5.0)
		if cam == null or _flat(p.position, cam.global_position) > char_range or not cam.is_position_in_frustum(p.position + Vector3(0, 1, 0)):
			return


func _spawn_pedestrians() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var holder := Node3D.new()
	holder.name = "Pietons"
	add_child(holder)
	for n in Graphics.get_value("peds"):
		var p = Pedestrian.new()
		holder.add_child(p)
		p.setup(city, rng, player.global_position)
		peds.append(p)

func _build_environment() -> void:
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2264c2")
	sky_mat.sky_horizon_color = Color("f4dcb0")
	sky_mat.ground_horizon_color = Color("d9c094")
	sky_mat.ground_bottom_color = Color("8c744e")
	sky_mat.sun_angle_max = 24.0
	sky_mat.sun_curve = 0.12
	sky_mat.energy_multiplier = 1.15
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Lumière ambiante naturelle issue du ciel et du rebond chaud du sol dakarois
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.5
	env.ambient_light_color = Color("fff1d6")
	env.ambient_light_energy = 0.85
	# Rendu « cinéma » ACES : contraste franc, couleurs chaudes et saturées
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 5.2
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15
	# Halo lumineux subtil (soleil sur carrosseries, vitrines, phares la nuit)
	env.glow_intensity = 0.6
	env.glow_strength = 0.95
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.05
	env.glow_hdr_scale = 1.6
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# Occlusion ambiante : creux, dessous de voitures et angles de façades
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.9
	env.ssao_power = 1.35
	env.ssao_detail = 0.55
	# Reflets à l'écran : routes mouillées, vitrines, carrosseries (profil Élevé)
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.4
	# Brouillard volumétrique léger : rayons de soleil dans la poussière (profil Élevé)
	env.volumetric_fog_density = 0.003
	env.volumetric_fog_albedo = Color("efe2c6")
	env.volumetric_fog_anisotropy = 0.65
	env.volumetric_fog_length = 130.0
	# Brume atmosphérique
	env.fog_enabled = true
	env.fog_light_color = Color("e8d3a8")
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.35 # ombres douces et réalistes
	sun.directional_shadow_max_distance = 80.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_normal_bias = 0.8
	sun.directional_shadow_fade_start = 0.85
	add_child(sun)


## Gain d'éclairage selon le renderer
func _sun_gain() -> float:
	return 1.25 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1.6


## Lumière ambiante selon le moteur pour déboucher les ombres naturellement
func _ambient_gain() -> float:
	match RenderingServer.get_current_rendering_method():
		"forward_plus":
			return 0.65
		"mobile":
			return 1.15
	return 1.35


## Soleil qui se lève à 6 h et se couche à 18 h ; la nuit, une lumière de lune bleutée.
func _update_daylight() -> void:
	var m: float = GameState.game_minutes
	var ang := (m - 360.0) / 1440.0 * TAU
	var elev := sin(ang)
	var day := clampf(elev * 2.0, 0.0, 1.0)
	if elev >= 0.0:
		sun.rotation = Vector3(-ang, deg_to_rad(30.0), 0.0)
		sun.light_energy = lerpf(0.3, 1.35, day) * _sun_gain()
		sun.light_color = Color("ffb36b").lerp(Color("fff4e0"), day)
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	else:
		sun.rotation = Vector3(-(ang - PI), deg_to_rad(30.0), 0.0)
		sun.light_energy = 0.3
		sun.light_color = Color("9fb4ff")
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	env.ambient_light_energy = 0.5 * _ambient_gain()
	# Lumière d'ambiance : chaude tant que le soleil est haut (sinon les ombres de fin d'après-midi virent au bleu)
	env.ambient_light_color = Color("6c7fb8").lerp(Color("fff1d6"), sqrt(day))
	env.fog_light_color = Color("1c2340").lerp(Color("e8d3a8"), day)
	sky_mat.sky_top_color = Color("0b1026").lerp(Color("3a7bd5"), day)
	sky_mat.sky_horizon_color = Color("27304f").lerp(Color("f1d9a8"), day)
	sky_mat.ground_horizon_color = Color("1c2340").lerp(Color("e0c89a"), day)
	# Lampadaires allumés de 18 h 30 à 6 h 30 environ ; nuages, pluie et harmattan
	var night := clampf(1.0 - (elev + 0.08) * 6.0, 0.0, 1.0)
	if weather:
		weather.apply_light(env, sky_mat, sun, day)
	if lamps:
		lamps.set_night(night)
	if interiors and interiors.inside != "":
		interiors.apply_light(env)


## Test réseau : affiche les joueurs vus et le chat reçu, puis quitte.
func _net_test() -> void:
	hud._intro.visible = false
	# Les joueurs du test se retrouvent sur la même place (zone d'intérêt de 300 m)
	player.global_position = city.places["Place de l'Indépendance"] + Vector3(randf_range(-4.0, 4.0), 0.5, randf_range(-4.0, 4.0))
	Net.chat_received.connect(func(f, t): print("NETTEST chat reçu de %s : %s" % [f, t]))
	GameState.notify.connect(func(t): print("NOTIFY %d ms : %s" % [Time.get_ticks_msec(), t]))
	# Réponses automatiques (installées dès le début : les invitations peuvent arriver tôt)
	var soc = Net.social
	var is_awa: bool = Net.pseudo.begins_with("Awa")
	if not is_awa:
		soc.group_invited.connect(func(n, _f): soc.rpc_group_accept.rpc_id(1, n))
		soc.duel_invited.connect(func(fid, _n, _st): soc.rpc_duel_accept.rpc_id(1, fid))
		soc.race_open.connect(func(rid, _h, _d, _f, _p): social_ui.join_race(rid))
	soc.duel_round.connect(func(_r, _t): soc.rpc_duel_choice.rpc_id(1, "charger" if is_awa else "crocheter"))
	soc.duel_end.connect(func(won, _st): print("NETTEST %s duel terminé : %s" % [Net.pseudo, "GAGNÉ" if won else "perdu"]))
	soc.race_result.connect(func(_rid, ranking): print("NETTEST %s résultat de la course : %s" % [Net.pseudo, ranking]))
	Net.bubble.connect(func(sid, t): print("NETTEST %s bulle de %d : %s" % [Net.pseudo, sid, t]))
	await get_tree().create_timer(4.0).timeout
	Net.send_chat("Salut de %s !" % Net.pseudo)
	await get_tree().create_timer(4.0).timeout
	var names: Array = []
	for id in Net.remote:
		names.append(Net.remote[id]["pseudo"])
	print("NETTEST %s en ligne=%s voit=%s avatars=%d argent=%d" % [Net.pseudo, Net.online, names, remote_players.count(), GameState.money])
	var nt = get_node_or_null("NetTraffic")
	if nt:
		var ids: Array = nt.cars.keys()
		ids.sort()
		var sample: Array = []
		for id in ids.slice(0, 4):
			var cp: Vector3 = nt.cars[id]["target"]
			sample.append("%d@%d,%d" % [id, roundi(cp.x), roundi(cp.z)])
		print("NETTEST %s trafic partagé=%d voitures %s" % [Net.pseudo, ids.size(), sample])
	if Net.pseudo.begins_with("Awa") and not Net.remote.is_empty():
		Net.give_money(Net.remote.keys()[0], 1000)
	await get_tree().create_timer(3.0).timeout
	print("NETTEST %s argent après don=%d" % [Net.pseudo, GameState.money])
	# Téléphone : Awa envoie un SMS et un virement Wave de 500 FCFA à Modou (frais 1 %)
	Net.sms_received.connect(func(f, t): print("NETTEST %s SMS reçu de %s : %s" % [Net.pseudo, f, t]))
	if Net.pseudo.begins_with("Awa") and not Net.remote.is_empty():
		var other: String = Net.remote[Net.remote.keys()[0]]["pseudo"]
		hud.phone._contact = other
		hud.phone._show("chat")
		hud.phone._entry.text = "Na nga def ?"
		hud.phone._send_sms()
		hud.phone._wallet = "wave"
		hud.phone._recipient = other
		hud.phone._show("send")
		hud.phone._entry.text = "500"
		hud.phone._transfer()
	await get_tree().create_timer(3.0).timeout
	print("NETTEST %s téléphone : argent=%d historique=%s sms=%s" % [Net.pseudo, GameState.money, hud.phone.history, hud.phone.convs.get("Awa", [])])
	# Métiers RP : Awa est policière, Modou est recherché, appelle la police puis se fait arrêter
	Net.job_target.connect(func(t, _p): print("NETTEST %s appel reçu : %s" % [Net.pseudo, t]))
	Net.arrested.connect(func(cop): print("NETTEST %s arrêté par %s" % [Net.pseudo, cop]))
	if Net.pseudo.begins_with("Awa"):
		GameState.clear_wanted()
		GameState.rp_job = "police"
	else:
		GameState.add_wanted(2, "test")
	await get_tree().create_timer(2.0).timeout
	if not Net.pseudo.begins_with("Awa") and not Net.remote.is_empty():
		var st: Dictionary = Net.remote[Net.remote.keys()[0]]["state"]
		player.global_position = Vector3(st["x"] + 2.0, st["y"] + 0.5, st["z"])
		Net.call_service("police")
		print("NETTEST Modou téléporté à %s étoiles=%d envoyé=%s" % [player.global_position, GameState.wanted, Net._last_sent])
	await get_tree().create_timer(3.0).timeout
	var money_before := GameState.money
	if Net.pseudo.begins_with("Awa") and not Net.remote.is_empty():
		print("NETTEST Awa indice : %s / statut : %s" % [ni_hint(), net_jobs.status])
		print("NETTEST Awa pos=%s modou_vu=%s" % [player.global_position, Net.remote[Net.remote.keys()[0]]["state"]])
		Net.arrest(Net.remote.keys()[0])
	await get_tree().create_timer(4.0).timeout
	print("NETTEST %s après arrestation : recherché=%d argent %d -> %d métier=%s" % [Net.pseudo, GameState.wanted, money_before, GameState.money, GameState.rp_job])
	await get_tree().create_timer(6.0).timeout
	print("NETTEST %s fin argent=%d" % [Net.pseudo, GameState.money])
	# --- Activités à plusieurs : groupe, chat de proximité, duel de lutte, course ---
	var s = Net.social
	var awa: bool = Net.pseudo.begins_with("Awa")
	var other_id: int = Net.remote.keys()[0] if not Net.remote.is_empty() else -1
	GameState.clear_wanted()
	player.frozen = false
	# Après l'arrestation, Modou est au commissariat : il revient à côté d'Awa
	await get_tree().create_timer(1.0).timeout
	if not awa and not Net.remote.is_empty():
		var st2: Dictionary = Net.remote[Net.remote.keys()[0]]["state"]
		player.global_position = Vector3(st2["x"] + 3.0, st2["y"] + 0.5, st2["z"])
	if awa:
		s.rpc_group_create.rpc_id(1, "Mbokk" + Net.pseudo.right(5)) # nom unique (le serveur garde les groupes)
		await get_tree().create_timer(3.0).timeout
		s.rpc_group_invite.rpc_id(1, other_id)
	await get_tree().create_timer(2.5).timeout
	print("NETTEST %s groupe=%s membres=%s étiquettes=%s" % [Net.pseudo, s.my_group, s.my_members.size(), s.tags.values()])
	if awa:
		Net.send_chat("Salamalekum les amis")
	await get_tree().create_timer(1.5).timeout
	# Modou se replace à côté d'Awa (duel à moins de 8 m, course à moins de 80 m)
	# L'autre joueur peut être loin (hors de la zone d'intérêt) : on le retrouve par son groupe
	if other_id < 0 and not social_ui.group_pos.is_empty():
		other_id = social_ui.group_pos.keys()[0]
	# Position d'Awa connue même de loin : elle est dans le même groupe
	if not awa and social_ui.group_pos.has(other_id):
		var st3: Vector3 = social_ui.group_pos[other_id]
		player.global_position = st3 + Vector3(3.0, 0.5, 0.0)
	await get_tree().create_timer(1.5).timeout
	# Duel : Awa charge à chaque manche, Modou croche → Awa gagne 3-0
	if awa:
		social_ui.challenge(other_id, 0)
	await get_tree().create_timer(12.0).timeout
	player.frozen = false
	# Position d'Awa connue même de loin : elle est dans le même groupe
	if not awa and social_ui.group_pos.has(other_id):
		var st4: Vector3 = social_ui.group_pos[other_id]
		player.global_position = st4 + Vector3(3.0, 0.5, 0.0)
	await get_tree().create_timer(1.0).timeout
	# Course : Awa ouvre une course vers la Grande Mosquée, Modou s'inscrit, départ, passage des points
	if awa:
		s.rpc_race_create.rpc_id(1, "Grande Mosquée", 0)
		await get_tree().create_timer(2.0).timeout
		s.rpc_race_start.rpc_id(1, social_ui.race_id)
	await get_tree().create_timer(5.5).timeout
	for k in 40:
		if not social_ui._race_running or social_ui._race_idx >= social_ui._race_cps.size():
			break
		player.global_position = social_ui._race_cps[social_ui._race_idx] + Vector3(0, 0.5, 0)
		await get_tree().create_timer(0.5 if awa else 0.8).timeout
	await get_tree().create_timer(3.0).timeout
	print("NETTEST %s fin des activités, statut=%s" % [Net.pseudo, social_ui.status])
	# --- Chat vocal : Awa parle (son synthétique de 2 s), Modou l'entend de près puis à la radio du groupe ---
	var heard := {"local": 0, "group": 0}
	Net.voice_received.connect(func(_sid, data, ch): heard[ch] += data.size())
	if not awa and social_ui.group_pos.has(other_id):
		player.global_position = social_ui.group_pos[other_id] + Vector3(5.0, 0.5, 0.0)
	await get_tree().create_timer(2.0).timeout
	if awa:
		for ch in ["local", "group"]:
			for k in 20:
				var frames := PackedVector2Array()
				for i in 4800:
					var sv := sin(TAU * 220.0 * (k * 4800 + i) / 48000.0) * 0.4
					frames.append(Vector2(sv, sv))
				Net.send_voice(voice.encode(frames, 48000.0), ch)
				await get_tree().create_timer(0.1).timeout
	await get_tree().create_timer(5.0).timeout
	print("NETTEST %s voix reçue : proximité %d octets, radio %d octets" % [Net.pseudo, heard["local"], heard["group"]])


func ni_hint() -> String:
	for pv in player.providers:
		var h: String = pv.get_hint()
		if h != "":
			return h
	return ""


func _on_fainted() -> void:
	player.leave_any_vehicle()
	jobs.cancel()
	# En ligne, avec des secouristes en service : on attend le SAMU sur place (net_jobs.gd)
	if net_jobs and net_jobs.go_down():
		return
	go_to_hospital()


func go_to_hospital() -> void:
	GameState.clear_wanted()
	police.reset_all()
	player.global_position = city.places["Hôpital Principal"]
	var fee: int = mini(3000, GameState.money)
	GameState.money -= fee
	GameState.revive()
	if GameState.faint_reason == "ko":
		GameState.notify.emit("Mis KO dans une bagarre... Tu te réveilles à l'Hôpital Principal : %s de soins." % GameState.fcfa(fee))
	elif GameState.faint_reason == "soif":
		GameState.notify.emit("Tu t'es évanoui de soif... Hôpital Principal : %s de soins. Bois de l'eau !" % GameState.fcfa(fee))
	else:
		GameState.notify.emit("Tu t'es évanoui de faim... Hôpital Principal : %s de soins. Mange un dibi !" % GameState.fcfa(fee))
	GameState.faint_reason = ""


## Outils de test :
##   godot -- --screenshot=capture.png   enregistre une capture puis quitte
##   godot -- --test-taxi                 démarre au volant d'un taxi, accélérateur enfoncé
##   godot -- --wanted=3 --delay=8        démarre recherché par la police, capture après 8 s
##   godot -- "--at=Garage Taxi"         démarre devant un lieu
func _maybe_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	var delay := 3.0
	for arg in args:
		if arg.begins_with("--hour="):
			GameState.game_minutes = float(arg.trim_prefix("--hour=")) * 60.0
		if arg.begins_with("--wanted="):
			GameState.wanted = int(arg.trim_prefix("--wanted="))
		if arg.begins_with("--at="):
			var at := arg.trim_prefix("--at=")
			if city.places.has(at):
				var info: Array = city.place_info[at]
				var f := Vector3(info[7], 0, info[8]) if info.size() > 8 else Vector3.FORWARD
				player.global_position = city.places[at] - f * 10.0 + Vector3(0, 0.5, 0)
				camera_rig.yaw = info[2] + 0.5
				camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		if arg.begins_with("--pos="):
			# Test : -- --pos=x,z (position du monde, ex. celle d'une sauvegarde)
			var xz := arg.trim_prefix("--pos=").split(",")
			player.global_position = Vector3(xz[0].to_float(), 0.5, xz[1].to_float())
			camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		if arg.begins_with("--latlon="):
			# Test : -- --latlon=14.6838,-17.4406 (vue sur un point réel de la carte)
			var ll := arg.trim_prefix("--latlon=").split(",")
			var lat := ll[0].to_float()
			var lon := ll[1].to_float()
			var px := (lon - (-17.44)) * 111320.0 * cos(deg_to_rad(14.675))
			var pz := -(lat - 14.675) * 110574.0
			var ni: int = city.nearest_node(Vector3(px, 0, pz), "drive")
			player.global_position = city.node_pos[ni] + Vector3(0, 1.0, 0)
			camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		if arg.begins_with("--cam-pitch="):
			camera_rig.pitch = deg_to_rad(arg.trim_prefix("--cam-pitch=").to_float())
		if arg.begins_with("--home="):
			# Test : -- --home=villa_cap_manuel (devient propriétaire et entre)
			var hid := arg.trim_prefix("--home=")
			if housing.PROPERTIES.has(hid):
				hud._intro.visible = false
				var lst: Array = GameState.home.get("owned", [])
				if not hid in lst:
					lst.append(hid)
				GameState.home["owned"] = lst
				housing._refresh()
				housing.enter(hid)
		if arg.begins_with("--talk="):
			# Test : -- --talk=livreur (devant le patron, dialogue ouvert)
			var tid := arg.trim_prefix("--talk=")
			if employment.bosses.has(tid):
				hud._intro.visible = false
				var bp: Vector3 = employment.bosses[tid]["pos"]
				player.global_position = bp + Vector3(2.0, 0.3, 2.0)
				camera_rig.yaw = atan2(2.0, 2.0)
				camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
				employment._talk(tid)
		if arg.begins_with("--office="):
			# Test : -- --office=jumbo|jadida|wave|om (dans les locaux) ; --office=jumbo:sit (assis face au patron)
			hud._intro.visible = false
			var spec := arg.trim_prefix("--office=").split(":")
			enterprises.test_visit(spec[0], spec.size() > 1 and spec[1] == "sit")
			if spec.size() > 1 and spec[1] in ["hall", "office"]:
				enterprises.test_spot(spec[1])
			if spec.size() > 1 and spec[1] == "door":
				# Test : devant la porte, l'action proposée doit être « Entrer »
				enterprises._leave_state()
				var dp: Vector3 = enterprises._entrances[spec[0]]["pos"]
				player.global_position = dp + Vector3(0, 0.3, 0)
				await get_tree().physics_frame
				print("PORTE %s : action = %s" % [spec[0], player.get_interaction_hint()])
			if spec.size() > 1 and spec[1] == "nego":
				# Test de la négociation : candidat expérimenté avec permis, demande +25 % en CDI
				GameState.inventory[employment.PERMIS_ITEM] = 1
				GameState.employment["_experience"] = 8
				for k in 3:
					employment._nego_answer(spec[0], "cdi", 0.10, 0.25, false)
					print("NEGO %s : embauché=%s contrat=%s paie×%.2f" % [spec[0], employment.is_hired(spec[0]), employment.contract_text(spec[0]), employment.pay_mult(spec[0])])
				GameState.employment["_experience"] = 0
				GameState.inventory.erase(employment.PERMIS_ITEM)
				employment.state(spec[0])["hired"] = false
				employment.state(spec[0])["shifts"] = 0
				employment.state(spec[0])["rep"] = 0
				employment._nego_answer(spec[0], "journalier", 0.0, 0.25, false)
				print("NEGO débutant demande +25 %% : embauché=%s (refus attendu, choix proposé)" % employment.is_hired(spec[0]))
		if arg.begins_with("--enter="):
			# Test : -- --enter=banque|restaurant|station|hopital|police|boutique
			hud._intro.visible = false
			interiors.enter_first(arg.trim_prefix("--enter="))
		if arg.begins_with("--cam-y="):
			camera_rig.yaw = deg_to_rad(arg.trim_prefix("--cam-y=").to_float())
		if arg.begins_with("--cam-d="):
			camera_rig.distance = arg.trim_prefix("--cam-d=").to_float()
			camera_rig.spring.spring_length = camera_rig.distance
		if arg.begins_with("--look="):
			var lk := arg.trim_prefix("--look=")
			if city.places.has(lk):
				var li: Array = city.place_info[lk]
				var ln := Vector3(li[3], 0, li[4])
				player.global_position = city.places[lk] - ln * 9.0 + Vector3(0, 0.5, 0)
				camera_rig.yaw = atan2(-ln.x, -ln.z)
				camera_rig.pitch = -0.18
				camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		if arg.begins_with("--overhead="):
			var oh := arg.trim_prefix("--overhead=")
			if city.places.has(oh):
				var oi: Array = city.place_info[oh]
				player.global_position = (Vector3(oi[9], 0, oi[10]) if oi.size() > 10 else city.places[oh]) + Vector3(0, 0.5, 0)
				camera_rig.pitch = -0.95
				camera_rig.distance = 45.0
				camera_rig.spring.spring_length = 45.0
				camera_rig.spring.collision_mask = 0
				camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		if arg.begins_with("--delay="):
			delay = float(arg.trim_prefix("--delay="))
	if "--portrait" in args:
		var RC = load("res://scripts/util/real_character.gd")
		var info: Array = city.place_info["Place de l'Indépendance"]
		var c := Vector3(info[9], 0.0, info[10] + 30.0)
		player.global_position = c + Vector3(0, 0.3, 0)
		var names := ["femme_robe", "homme_tunique", "femme_jupe", "homme_afro", "femme_ville", "homme_age"]
		for a in args:
			if a.begins_with("--models="):
				# Test : -- --portrait --models=homme_tunique,heros
				names = Array(a.trim_prefix("--models=").split(","))
				while names.size() < 6:
					names.append(names[names.size() % maxi(1, names.size())])
		var slots := [-3, -2, -1, 1, 2, 3]
		for k in slots.size():
			var fig: Node3D = RC.create(self, names[k], -1)
			fig.global_position = c + Vector3(slots[k] * 0.85, 0, 0.6 + absf(slots[k]) * 0.25)
			for ca in args:
				if ca.begins_with("--clip="):
					# Test : -- --portrait --clip=walk (animation jouée par tous les personnages)
					fig.play_clip(ca.trim_prefix("--clip="), 0.0)
		camera_rig.yaw = PI
		camera_rig.pitch = -0.04
		camera_rig.distance = 3.6
		camera_rig.spring.spring_length = 3.6
		camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		for a in args:
			if a.begins_with("--cam-yaw="):
				# Vue de profil : -- --portrait --cam-yaw=90
				camera_rig.yaw = deg_to_rad(a.trim_prefix("--cam-yaw=").to_float())
			if a.begins_with("--cam-dist="):
				# Gros plan : -- --portrait --cam-dist=1.2
				camera_rig.distance = a.trim_prefix("--cam-dist=").to_float()
				camera_rig.spring.spring_length = camera_rig.distance
	if "--at-stop" in args and not transit.stops.is_empty():
		var st: Dictionary = transit.stops[1]
		player.global_position = st["pos"] + Vector3(4, 0.5, 4)
		camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
	for a in args:
		if a.begins_with("--phone="):
			# Test : -- --phone=gps (home, messages, wave, om, gps, services, players)
			hud._intro.visible = false
			hud.phone.open()
			var app: String = a.trim_prefix("--phone=")
			if app == "messages":
				hud.phone._on_sms("Maman", "Doom, rentre avant la nuit !")
			if app != "home":
				hud.phone._show(app)
		if a.begins_with("--emote="):
			# Test : -- --emote=wave (le joueur fait ce geste, menu GESTES ouvert)
			hud._intro.visible = false
			hud.emote_menu.toggle()
			var clip := a.trim_prefix("--emote=")
			# en ligne : attendre que le serveur connaisse notre position
			get_tree().create_timer(4.0 if Net.online else 0.0).timeout.connect(func(): player.start_emote(clip))
		if a.begins_with("--outfit="):
			# Test : -- --phone=sape --outfit=vert,noir,casquette_rouge,afro,brun (achète et porte la tenue)
			GameState.money += 20000
			var p := a.trim_prefix("--outfit=").split(",")
			for i in mini(p.size(), 5):
				if p[i] != "":
					hud.phone._buy_or_wear(i, p[i])
	if "--map" in args:
		hud._intro.visible = false
		hud.map_screen.open()
		gps.set_waypoint(city.places["Grande Mosquée"], "Grande Mosquée")
	if "--crowd-test" in args:
		# Test : -- --crowd-test (passants qui se chevauchent : paires à moins de 45 cm, mesuré pendant 30 s)
		hud._intro.visible = false
		player.global_position = city.places["Marché Sandaga"] + Vector3(0, 0.5, 0)
		var worst := 0
		var total := 0
		for k in 30:
			await get_tree().create_timer(1.0).timeout
			var n := 0
			for i in peds.size():
				for j in range(i + 1, peds.size()):
					if peds[i].visible and peds[j].visible and peds[i].position.distance_to(peds[j].position) < 0.45:
						n += 1
			worst = maxi(worst, n)
			total += n
		print("CROWD chevauchements : moyenne %.1f, pire %d (sur %d passants)" % [total / 30.0, worst, peds.size()])
		get_tree().quit()
	if "--ads-test" in args:
		# Test : -- --ads-test (éditeur PC : fausse vidéo du module AdMob regardée jusqu'au bout, puis délai d'attente)
		hud._intro.visible = false
		var before := GameState.money
		Ads.start()
		for i in 20:
			if Ads.can_show():
				break
			await get_tree().create_timer(0.5).timeout
		print("ADS prête=%s raison='%s'" % [Ads.can_show(), Ads.why_not()])
		hud.phone.open()
		hud.phone._show("bonus")
		await get_tree().create_timer(1.0).timeout
		Ads.show_rewarded(func():
			var m := GameState.money
			GameState.add_money(Ads.REWARD, "Bonus vidéo")
			print("ADS récompense %d -> %d" % [m, GameState.money]))
		await get_tree().create_timer(9.0).timeout
		for arg in args:
			if arg.begins_with("--shot="):
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot="))
		var mock = load("res://addons/admob/internal/mock/mock_admob_factory.gd").get_mock_plugin("PoingGodotAdMobRewardedAd")
		mock._on_close_pressed()
		await get_tree().create_timer(1.0).timeout
		print("ADS argent %d -> %d, restantes=%d, ensuite='%s'" % [before, GameState.money, Ads.left_today(), Ads.why_not()])
		get_tree().quit()
	if "--fight-test" in args:
		# Test : -- --fight-test (frappe un passant jusqu'au KO, puis un fakhman attaque)
		hud._intro.visible = false
		await get_tree().create_timer(2.0).timeout
		await street_fight.self_test()
		get_tree().quit()
	if "--lutte-test" in args:
		# Test : -- --lutte-test (écurie, combat signé, calendrier, affiche d'un promoteur)
		hud._intro.visible = false
		await get_tree().create_timer(1.0).timeout
		lutte.self_test()
		get_tree().quit()
	if "--lutte-live" in args:
		# Test : -- --lutte-live [--lutte-fight] : journée de lutte en direct à l'Arène de la Médina (avec ton combat)
		hud._intro.visible = false
		GameState.game_minutes = Lutte.HOUR * 60.0 + 1.0
		var lj: Dictionary = lutte._npc_journee(GameState.day)
		lj["venue"] = "medina"
		if "--lutte-fight" in args:
			lutte.auto_press = true
			lj["bouts"].insert(0, ["joueur", lj["bouts"][0][1]])
			GameState.lutte["bout"] = {"day": GameState.day, "venue": "medina", "opp": lj["bouts"][0][1], "cachet": 7000}
		GameState.lutte["journees"] = [lj]
		var vc: Vector3 = lutte._venue_pos["medina"]
		var vd: Vector3 = lutte._venue_door["medina"]
		player.global_position = vc + vd * (Lutte.RING_R + 3.0) + Vector3(0, 0.5, 0)
		camera_rig.yaw = atan2(vd.x, vd.z)
		camera_rig.pitch = -0.3
		camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		lutte._start_live(lj)
		print("LUTTE journée en direct : %d combats" % lj["bouts"].size())
	for a in args:
		if a.begins_with("--lutte-base="):
			# Test : -- --lutte-base=ndakaaru (devant le lieu d'entraînement d'une écurie)
			await get_tree().create_timer(0.5).timeout
			var bb: Dictionary = lutte._bases.get(a.trim_prefix("--lutte-base="), {})
			if not bb.is_empty():
				var bn: Node3D = bb["node"]
				player.global_position = bn.global_transform * Vector3(0, 0.5, 6.0)
				camera_rig.yaw = bn.rotation.y
				camera_rig.pitch = -0.15
				camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
				lutte._update_bases()
	if "--arena" in args:
		hud._intro.visible = false
		player.global_position = arena.ORIGIN + Vector3(0, 0.5, 24)
		camera_rig.yaw = 0.0
		camera_rig.pitch = -0.25
		camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
		arena._has_ticket = true
		arena._start_combat()
	if "--fps-test" in args:
		# Mesure : images par seconde moyennes entre 6 et 12 s (sans synchro verticale), puis quitte
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		hud._intro.visible = false
		Input.action_press("move_forward")
		# Diagnostic : -- --fps-test --hide=labels|lamps|city
		for h in args:
			if h == "--hide=labels":
				for l in city.find_children("*", "Label3D", true, false):
					l.visible = false
			if h == "--hide=hud":
				hud.visible = false
				hud.process_mode = Node.PROCESS_MODE_DISABLED
			if h == "--hide=peds":
				for pd in peds:
					pd.visible = false
					pd.process_mode = Node.PROCESS_MODE_DISABLED
				peds = [] # (test seulement : le niveau de détail ne les réaffiche plus)
			if h == "--hide=cars":
				for v in traffic + parked:
					if is_instance_valid(v):
						v.visible = false
						v.process_mode = Node.PROCESS_MODE_DISABLED
				traffic = []
				parked = []
			if h == "--hide=lamps":
				lamps.visible = false
			if h == "--hide=city":
				for m in city.find_children("Bloc_*", "MeshInstance3D", true, false):
					m.visible = false
		await get_tree().create_timer(6.0).timeout
		var f0 := Engine.get_process_frames()
		var t0 := Time.get_ticks_msec()
		await get_tree().create_timer(6.0).timeout
		print("FPS %s : %.0f images/s" % [Graphics.profile, (Engine.get_process_frames() - f0) * 1000.0 / (Time.get_ticks_msec() - t0)])
		var rs := RenderingServer
		print("RENDU %s : appels de dessin=%d objets=%d triangles=%d mémoire vidéo=%d Mo | noeuds=%d | process %.2f ms physique %.2f ms" % [Graphics.profile,
			rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			rs.get_rendering_info(rs.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), rs.get_rendering_info(rs.RENDERING_INFO_VIDEO_MEM_USED) / 1048576,
			get_tree().get_node_count(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		get_tree().quit()
	if "--mem-test" in args:
		# Mesure : mémoire toutes les 10 s pendant 3 minutes (le joueur avance), puis quitte
		hud._intro.visible = false
		Input.action_press("move_forward")
		for i in 19:
			print("MEM %3d s : RAM %d Mo, vidéo %d Mo, textures %d Mo, noeuds %d, objets %d, ressources %d" % [i * 10,
				OS.get_static_memory_usage() / 1048576,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / 1048576,
				get_tree().get_node_count(), Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)])
			await get_tree().create_timer(10.0).timeout
		get_tree().quit()
	if "--perf-probe" in args:
		_perf_probe()
	if "--inside-test" in args:
		# Test : -- --pos=x,z --inside-test (le joueur est-il dans un bâtiment ?)
		await get_tree().create_timer(2.0).timeout
		print("INSIDE résultat : %s" % is_inside_building(player.global_position))
		get_tree().quit()
	if "--audit" in args:
		_audit()
	if "--touch-test" in args:
		_touch_test()
	if "--drive-test" in args:
		_drive_test()
	if "--no-hud" in args:
		# Images de la fiche Play Store : -- --no-hud (cache l'interface)
		hud.visible = false
	if "--net-test" in args:
		_net_test()
	if "--lutte-net" in args:
		_lutte_net_test()
	if "--fight-net" in args:
		_fight_net_test()
	if "--trade-net" in args:
		_trade_net_test()
	if "--trade-shot" in args:
		_trade_shot()
	if "--foot-test" in args:
		_foot_test()
	if "--touch-layout" in args:
		_touch_layout_test()
	if "--tuto-test" in args:
		_tuto_test()
	if "--foot-net" in args:
		_foot_net_test()
	if "--foot" in args:
		_foot_open()
	if "--foot-night" in args:
		_foot_night_shot()
	if "--faction-net" in args:
		_faction_net_test()
	if "--property-net" in args:
		_property_net_test()
	if "--dealer-test" in args:
		_dealer_test()
	if "--city-test" in args:
		_city_test()
	if "--city-net" in args:
		_city_net_test()
	if "--fish-test" in args:
		_fish_test()
	if "--rob-test" in args:
		_rob_test()
	if "--impound-test" in args:
		_impound_test()
	if "--cook-test" in args:
		_cook_test()
	if "--rental-test" in args:
		_rental_test()
	if "--biz-test" in args:
		_biz_test()
	if "--market-scan" in args:
		_market_scan()
	if "--market-test" in args:
		_market_test()
	if "--goods-shots" in args:
		_goods_shots()
	if "--hud-shot" in args:
		_hud_shot()
	if "--feet-test" in args:
		_feet_test()
	if "--rooms-shot" in args:
		_rooms_shot()
	if "--rooms-walk" in args:
		_rooms_walk()
	if "--ped-motion" in args:
		_ped_motion_test()
	if "--traffic-motion" in args:
		_traffic_motion_test()
	if "--pv-net" in args:
		_pv_net_test()
	if "--delete-test" in args:
		# Test : suppression du compte en ligne depuis le jeu
		Net.account_deleted.connect(func(): print("DELTEST compte supprimé par le serveur"))
		await get_tree().create_timer(3.0).timeout
		Net.delete_account()
	if "--walk" in args:
		Input.action_press("move_forward")
	if "--showcase" in args:
		var info: Array = city.place_info["Place de l'Indépendance"]
		var c := Vector3(info[9], 0.2, info[10])
		var types := ["taxi", "clando", "police", "army", "van", "car_rapide", "ndiaga", "jakarta", "grosse_moto"]
		for k in types.size():
			var v = Vehicle.new()
			v.vehicle_type = types[k]
			add_child(v)
			v.global_position = c + Vector3(-15.0 + k * 4.6, 0, 24.0)
			v.rotation.y = PI - 0.6
		for k in 2:
			var b = Vehicle.new()
			b.vehicle_type = ["bus", "coach"][k]
			add_child(b)
			b.global_position = c + Vector3(-10.0 + k * 9.0, 0, 12.0)
			b.rotation.y = PI / 2.0 + 0.3
		player.global_position = c + Vector3(-14, 0.5, 28.5)
		camera_rig.yaw = 0.0
		camera_rig.pitch = -0.12
		camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
	if "--test-taxi" in args:
		hud._intro.visible = false
		for v in get_tree().get_nodes_in_group("vehicles"):
			if v.vehicle_type == "taxi" and not v.ai_enabled:
				player.global_position = v.global_position
				player.enter_vehicle(v)
				break
		Input.action_press("move_forward")
		get_tree().create_timer(1.5).timeout.connect(func(): Input.action_release("move_forward"))
	for arg in args:
		if arg.begins_with("--screenshot="):
			var path := arg.trim_prefix("--screenshot=")
			hud._intro.visible = false
			await get_tree().create_timer(delay).timeout
			await RenderingServer.frame_post_draw
			print("FPS ", Engine.get_frames_per_second())
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()


## Diagnostic : -- --perf-probe — coupe tour à tour chaque famille de nœuds (regroupés par script)
## et mesure le temps de calcul gagné (process + physique), pour savoir quoi optimiser.
func _perf_probe() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	hud._intro.visible = false
	await get_tree().create_timer(6.0).timeout
	var groups := {}
	var nodes: Array = get_children() + city.get_children()
	for n in nodes.duplicate():
		if n.get_script() == null and n is Node3D:
			nodes.append_array(n.get_children()) # conteneurs : on regarde dedans
	for n in nodes:
		var key: String = n.get_script().resource_path.get_file() if n.get_script() else n.get_class()
		if n == city:
			continue
		if not groups.has(key):
			groups[key] = []
		groups[key].append(n)
	await _probe_time(4.0) # chauffe
	var results: Array = []
	for key in groups:
		var gain := 0.0
		for rep in 2:
			var on := await _probe_time(1.2)
			var saved: Array = []
			for n in groups[key]:
				saved.append(n.process_mode)
				n.process_mode = Node.PROCESS_MODE_DISABLED
			var off := await _probe_time(1.2)
			for k in groups[key].size():
				groups[key][k].process_mode = saved[k]
			gain += (on - off) / 2.0
		results.append([gain, key, groups[key].size()])
	results.sort_custom(func(x, y): return x[0] > y[0])
	for r in results:
		print("PROBE %-28s x%-4d %.2f ms" % [r[1], r[2], r[0]])
	get_tree().quit()


func _probe_time(seconds: float) -> float:
	await get_tree().create_timer(0.3).timeout
	var acc := 0.0
	var n := 0
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		acc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	return acc / maxf(1, n)


## Sécurité : si le joueur à pied se retrouve à l'intérieur d'un bâtiment (vieille sauvegarde,
## bousculade…), il est remis sur le trottoir le plus proche. De l'intérieur, les murs ne sont pas
## dessinés : on le détecte avec des rayons qui touchent l'envers des murs tout autour.
func _unstick_player() -> void:
	if player == null or player.current_vehicle != null or player.riding != null:
		return
	if player.interior_door != Vector3.ZERO or (arena and arena.contains(player.global_position)) or (foot and foot.contains(player.global_position)):
		return
	if not is_inside_building(player.global_position):
		return
	var from: Vector3 = player.global_position
	var n: int = city.nearest_node(from, "walk")
	var nb: PackedInt32Array = city.walk_neighbors(n)
	var dest: Vector3 = city.node_pos[n]
	for b in nb:
		for side in [1, -1]:
			var cand: Vector3 = city.sidewalk_point(n, b, 2.0, side)
			if not is_inside_building(cand):
				dest = cand
				break
	player.global_position = dest + Vector3(0, 0.4, 0)
	player.velocity = Vector3.ZERO
	camera_rig.global_position = player.global_position + Vector3(0, 1.6, 0)
	print("Joueur coincé dans un bâtiment en %s : replacé en %s" % [from, dest])
	GameState.notify.emit("Tu étais coincé dans un bâtiment : retour sur le trottoir.")


## Vrai si p est sous le toit d'un bâtiment (donc enfermé dedans) : rayon vertical vers les toits,
## qui ont une collision invisible sur la couche 8 (tools/bake_dakar.gd).
func is_inside_building(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p + Vector3(0, 90.0, 0), 8)
	q.hit_back_faces = true
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Audit : -- --audit — liste les objets posés sur la chaussée (panneaux, abribus, feux, lampadaires…).
func _audit() -> void:
	await get_tree().create_timer(1.0).timeout
	var cats := {}
	var add := func(cat: String, p: Vector3):
		if not cats.has(cat):
			cats[cat] = [0, 0, []]
		cats[cat][0] += 1
		if cat.ends_with("PLEINE VOIE") or city.in_roadway(p, 0.2):
			cats[cat][1] += 1
			if cats[cat][2].size() < 4:
				cats[cat][2].append(Vector2i(int(p.x), int(p.z)))
	for mi in city.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh is CylinderMesh and is_equal_approx((mi.mesh as CylinderMesh).top_radius, 0.04):
			var h: float = (mi.mesh as CylinderMesh).height
			add.call("poteau de panneau (%.1f m)" % h, mi.global_position)
	for s in transit.stops:
		add.call("abribus", s["pos"])
	for l in lamps.lamps:
		add.call("lampadaire", l[0])
	for n in city.lights.get_children():
		if n is Node3D and n.get_child_count() > 0:
			add.call("feu tricolore", n.global_position)
	for s in market.stalls:
		add.call("étal de marché", s["pos"])
	for k in city.places:
		add.call("lieu (trottoir)", city.places[k])
	for v in parked:
		if is_instance_valid(v):
			add.call("voiture garée", v.global_position)
			if city.in_roadway(v.global_position, -2.6):
				add.call("voiture garée EN PLEINE VOIE", v.global_position)
	for cat in cats:
		print("AUDIT %-28s %4d objets, %3d sur la chaussée %s" % [cat, cats[cat][0], cats[cat][1], cats[cat][2]])
	get_tree().quit()


## Test : -- --touch --touch-test — appuis tactiles simulés (joystick, puis GAZ / FREIN en voiture)
func _touch_test() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(2.0).timeout
	var tc = hud._touch
	var vp := get_viewport()
	var sz: Vector2 = tc.size
	var s: float = tc._scale()
	var touch := func(idx: int, pos: Vector2, down: bool):
		var ev := InputEventScreenTouch.new()
		ev.index = idx
		ev.position = pos
		ev.pressed = down
		vp.push_input(ev)
	var drag := func(idx: int, pos: Vector2, rel: Vector2):
		var ev := InputEventScreenDrag.new()
		ev.index = idx
		ev.position = pos
		ev.relative = rel
		vp.push_input(ev)
	# À pied : joystick poussé à fond vers le haut → le joueur avance en courant
	var p0: Vector3 = player.global_position
	var jc := Vector2(200, sz.y - 200)
	touch.call(0, jc, true)
	drag.call(0, jc + Vector2(0, -120.0 * s), Vector2(0, -120.0 * s))
	await get_tree().create_timer(1.5).timeout
	print("TOUCH à pied : touch_move=%s déplacement=%.1f m" % [GameState.touch_move, _flat(player.global_position, p0)])
	touch.call(0, jc, false)
	# Effleurement (zone morte) : rien ne bouge
	touch.call(0, jc, true)
	drag.call(0, jc + Vector2(6, 0), Vector2(6, 0))
	print("TOUCH effleurement : touch_move=%s" % GameState.touch_move)
	touch.call(0, jc, false)
	# En voiture : GAZ puis FREIN, volant au joystick
	var car = null
	for v in parked:
		if is_instance_valid(v) and v.driver == null:
			car = v
			break
	player.global_position = car.global_position + Vector3(0, 0.5, 0)
	player.enter_vehicle(car)
	tc.in_vehicle = true
	await get_tree().create_timer(0.3).timeout
	var gas: Vector2 = sz + tc.CAR[0]["offset"] * s
	var brake: Vector2 = sz + tc.CAR[1]["offset"] * s
	var yaw0: float = car.rotation.y
	touch.call(1, gas, true)
	touch.call(0, jc, true)
	drag.call(0, jc + Vector2(100.0 * s, 0), Vector2(100.0 * s, 0))
	await get_tree().create_timer(2.0).timeout
	print("TOUCH GAZ + volant : vitesse=%.1f km/h, virage=%.2f rad, touch_move=%s" % [car.speed * 3.6, absf(car.rotation.y - yaw0), GameState.touch_move])
	touch.call(1, gas, false)
	touch.call(0, jc, false)
	touch.call(2, brake, true)
	await get_tree().create_timer(2.5).timeout
	print("TOUCH FREIN : vitesse=%.1f km/h (freine puis recule)" % (car.speed * 3.6))
	touch.call(2, brake, false)
	get_tree().quit()


## Test : -- --drive-test [--shot=chemin] — accélère, braque fort avec le frein à main, freine, vue capot
func _drive_test() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(1.5).timeout
	var car = null
	for v in parked:
		if is_instance_valid(v) and v.driver == null and v.vehicle_type == "taxi":
			car = v
			break
	if car == null:
		car = parked[0]
	# Départ sur une grande avenue dégagée, dans l'axe de la rue
	var best := -1
	for i in city.node_pos.size():
		var nb: PackedInt32Array = city.drive_neighbors(i)
		if nb.size() == 1 or nb.is_empty():
			continue
		if city.edge_width(i, nb[0]) >= 12.0 and city.segment_length(i, nb[0]) > 80.0:
			best = i
			break
	if best != -1:
		var nb2: PackedInt32Array = city.drive_neighbors(best)
		var d: Vector3 = (city.node_pos[nb2[0]] - city.node_pos[best]).normalized()
		car.global_position = city.lane_point(nb2[0], best) - d * 60.0 + Vector3(0, 0.3, 0)
		car.rotation.y = atan2(-d.x, -d.z)
	player.global_position = car.global_position + Vector3(0, 0.5, 0)
	player.enter_vehicle(car)
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
	Input.action_press("move_forward")
	await get_tree().create_timer(3.0).timeout
	print("DRIVE vitesse=%.0f km/h fov=%.1f" % [car.speed * 3.6, camera_rig.camera.fov])
	Input.action_press("move_left")
	Input.action_press("jump")
	var max_slip := 0.0
	var max_roll := 0.0
	for k in 30:
		await get_tree().physics_frame
		max_slip = maxf(max_slip, absf(car.slip))
		if car._body:
			max_roll = maxf(max_roll, absf(car._body.rotation.z))
	print("DRIVE frein à main + virage : glisse max=%.2f rad, roulis max=%.3f rad, crissement=%s" % [max_slip, max_roll, Audio._screech.playing])
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot + "_glisse.png")
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_forward")
	Input.action_press("move_back")
	await get_tree().create_timer(0.4).timeout
	print("DRIVE freinage : feux stop=%.1f" % car._brake_mat.emission_energy_multiplier)
	await get_tree().create_timer(2.5).timeout
	print("DRIVE marche arrière : vitesse=%.0f km/h feux de recul=%.1f" % [car.speed * 3.6, car._reverse_mat.emission_energy_multiplier])
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot + "_frein.png")
	Input.action_release("move_back")
	# Appui sur X comme un vrai joueur (passe par la file des entrées)
	var ev := InputEventAction.new()
	ev.action = "camera_view"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = "camera_view"
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.action_press("move_forward")
	await get_tree().create_timer(2.0).timeout
	print("DRIVE vue capot=%s" % camera_rig.hood_view)
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot + "_capot.png")
	Input.action_release("move_forward")
	get_tree().quit()


## Test en ligne : -- --online=127.0.0.1 --pseudo=Pro... --lutte-net (promoteur) ; autres pseudos = lutteurs.
## Le promoteur fonde une écurie et annonce une journée à l'Arène de la Médina ; les lutteurs rejoignent
## l'écurie, s'inscrivent ; la journée se déroule (manches automatiques), on affiche l'argent de chacun.
func _lutte_net_test() -> void:
	hud._intro.visible = false
	var L = Net.lutte
	var pro: bool = Net.pseudo.begins_with("Pro")
	GameState.money = 200000
	var vc: Vector3 = lutte._venue_pos["medina"]
	player.global_position = vc + lutte._venue_door["medina"] * (Lutte.RING_R + 2.0) + Vector3(randf_range(-1.5, 1.5), 0.5, 0)
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	Net.social.duel_round.connect(func(_r, _t): Net.social.rpc_duel_choice.rpc_id(1, "charger" if Net.pseudo.begins_with("Lu1") else "crocheter"))
	L.ecurie_changed.connect(func(): print("LUTTENET %s écurie=%s membres=%d bilan=%s" % [Net.pseudo, L.my_ecurie, L.my_members.size(), L.my_record]))
	if not pro:
		L.journees_changed.connect(func():
			for jid in L.journees:
				var j: Dictionary = L.journees[jid]
				if j["state"] == "open" and not Net.pseudo in j["names"]:
					L.rpc_journee_register.rpc_id(1, jid, true))
	await get_tree().create_timer(3.0).timeout
	if pro:
		GameState.spend(L.CREATE_FEE)
		L.rpc_ecurie_create.rpc_id(1, "Teranga Test")
		await get_tree().create_timer(2.0).timeout
		print("LUTTENET %s annonce : %s" % [Net.pseudo, L.announce("medina", vc, 2000, 2)])
		var t := 0.0
		while t < 20.0:
			await get_tree().create_timer(1.0).timeout
			t += 1.0
			for jid in L.journees:
				if L.journees[jid]["promoter"] == Net.pseudo and L.journees[jid]["names"].size() >= 2 and L.journees[jid]["state"] == "open":
					print("LUTTENET %s lance la journée avec %s" % [Net.pseudo, L.journees[jid]["names"]])
					L.rpc_journee_start.rpc_id(1, jid)
	else:
		await get_tree().create_timer(2.5).timeout
		L.rpc_ecurie_join.rpc_id(1, "Teranga Test")
	await get_tree().create_timer(45.0 if pro else 65.0).timeout
	print("LUTTENET %s fin : argent=%d écurie=%s" % [Net.pseudo, GameState.money, L.my_ecurie])
	get_tree().quit()


## Test en ligne : -- --online=127.0.0.1 --pseudo=Fa... --fight-net (frappe) ; autre pseudo = victime
func _fight_net_test() -> void:
	hud._intro.visible = false
	GameState.revive()
	player.global_position = city.places["Place de l'Indépendance"] + Vector3(1.0 if Net.pseudo.begins_with("Fa") else -0.2, 0.5, 0)
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	await get_tree().create_timer(5.0).timeout
	if Net.pseudo.begins_with("Fa"):
		for k in 12:
			for id in Net.remote:
				Net.fight.punch(id)
			await get_tree().create_timer(0.45).timeout
	await get_tree().create_timer(8.0).timeout
	print("FIGHTNET %s santé=%d recherché=%d" % [Net.pseudo, int(GameState.health), GameState.wanted])
	get_tree().quit()


## Test en ligne : -- --online=127.0.0.1 --pseudo=Med... --faction-net (secouriste) ; autre pseudo = tombe à terre
func _faction_net_test() -> void:
	hud._intro.visible = false
	GameState.revive()
	var medic: bool = Net.pseudo.begins_with("Med")
	player.global_position = city.places["Place de l'Indépendance"] + Vector3(1.5 if medic else -1.5, 0.5, 0)
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	await get_tree().create_timer(4.0).timeout
	if medic:
		GameState.faction = {"id": "samu", "xp": 9}
		net_jobs._start_duty("samu")
		print("FACTIONNET %s tenue de service=%s véhicule=%s" % [Net.pseudo, GameState.tenue, net_jobs._car.vehicle_type if net_jobs._car else "aucun"])
	await get_tree().create_timer(3.0).timeout
	if not medic:
		GameState.health = 0.0
	await get_tree().create_timer(3.0).timeout
	print("FACTIONNET %s statut=%s patients=%s figé=%s" % [Net.pseudo, net_jobs.status, net_jobs.patients.keys(), player.frozen])
	if medic:
		for id in net_jobs.patients:
			print("FACTIONNET indice : %s" % ni_hint())
			player.providers[0].try_interact()
	await get_tree().create_timer(3.0).timeout
	print("FACTIONNET %s santé=%d figé=%s argent=%d faction=%s titre=%s" % [Net.pseudo, int(GameState.health), player.frozen, GameState.money, GameState.faction, net_jobs.faction_title()])
	if medic:
		net_jobs._stop(true)
		print("FACTIONNET %s tenue après service=%s" % [Net.pseudo, GameState.tenue])
	get_tree().quit()


## Test en ligne : -- --online=127.0.0.1 --pseudo=Pro... --property-net (achète puis revend) ; autre pseudo = essaie d'acheter
func _property_net_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	var buyer: bool = Net.pseudo.begins_with("Pro")
	GameState.money = 2000000
	await get_tree().create_timer(4.0 if buyer else 7.0).timeout
	housing._buy("boutique_sandaga", 630000)
	await get_tree().create_timer(2.0).timeout
	print("PROPNET %s propriétaire=%s possède=%s étiquette=%s argent=%d" % [Net.pseudo, Net.properties.owner_of("boutique_sandaga"), housing.owned("boutique_sandaga"), housing.doors["boutique_sandaga"]["label"].text.replace("\n", " | "), GameState.money])
	if buyer:
		GameState.new_day.emit()
		GameState.new_day.emit()
		print("PROPNET %s caisse après 2 jours=%d" % [Net.pseudo, housing.till("boutique_sandaga")])
		await get_tree().create_timer(4.0).timeout
		housing._sell("boutique_sandaga")
		await get_tree().create_timer(2.0).timeout
		print("PROPNET %s après revente : possède=%s argent=%d" % [Net.pseudo, housing.owned("boutique_sandaga"), GameState.money])
	else:
		await get_tree().create_timer(5.0).timeout
		print("PROPNET %s après revente de l'autre : propriétaire=%s étiquette=%s" % [Net.pseudo, Net.properties.owner_of("boutique_sandaga"), housing.doors["boutique_sandaga"]["label"].text.replace("\n", " | ")])
	get_tree().quit()


## Test : -- --rooms-walk (dans chaque salle meublée : l'entrée est libre et on atteint le comptoir à pied)
func _rooms_walk() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(2.0).timeout
	for k in ["home_chambre", "home_studio", "home_appartement", "home_villa", "banque", "restaurant", "station", "boutique", "hopital", "police"]:
		var o: Vector3 = interiors._room(k)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var start := Transform3D(Basis(), o + Vector3(0, 0.95, interiors.ROOM.z / 2.0 - 2.2))
		var blocked_spawn: bool = player.test_move(start, Vector3(0, 0.01, 0))
		var to_counter := Vector3(0, 0, (-interiors.ROOM.z / 2.0 + 2.6 + 1.0) - (interiors.ROOM.z / 2.0 - 2.2))
		var blocked_path: bool = player.test_move(start, to_counter)
		var to_exit: bool = player.test_move(start, Vector3(0, 0, 1.0))
		print("WALK %s entrée_bloquée=%s chemin_comptoir_bloqué=%s sortie_bloquée=%s" % [k, blocked_spawn, blocked_path, to_exit])
	get_tree().quit()


## Test : -- --rooms-shot (vitrine des meubles puis photo de chaque intérieur, dans user://rooms/)
func _rooms_shot() -> void:
	hud._intro.visible = false
	hud.visible = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://rooms"))
	var F = load("res://scripts/util/furniture.gd")
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	# Vitrine : tous les modèles en ligne, devant (+Z) vers la caméra
	var show := Node3D.new()
	add_child(show)
	show.position = Vector3(0, -300, 0)
	var floor_ := Mk.box(show, Vector3(40, 0.2, 10), Vector3(0, -0.1, 0), Color("cccccc"), true)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.4, 0)
	show.add_child(sun)
	var ids := ["Sofa_01", "sofa_02", "ArmChair_01", "CoffeeTable_01", "Television_01", "plastic_monobloc_chair_01", "painted_wooden_table", "round_wooden_table_01", "dining_chair_02", "ClassicNightstand_01", "steel_frame_shelves_01", "CashRegister_01", "metal_office_desk", "drawer_cabinet", "electric_stove"]
	var x := -17.0
	for id in ids:
		F.place(show, id, Vector3(x, 0, 0))
		Mk.label(show, id, Vector3(x, 2.4, 0), 20, Color.BLACK)
		x += 2.4
	F.flat_tv(show, Vector3(x, 0.8, 0), 0.0, 1.4)
	for half in [0, 1]:
		cam.global_position = show.position + Vector3(-9.0 + half * 18.0, 1.6, 9.0)
		cam.look_at(show.position + Vector3(-9.0 + half * 18.0, 0.6, 0))
		cam.make_current()
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("user://rooms/vitrine_%d.png" % half)
	show.queue_free()
	var kinds := ["home_chambre", "home_studio", "home_appartement", "home_villa", "banque", "restaurant", "station", "hopital", "police"]
	for k in kinds:
		var o: Vector3 = interiors._room(k)
		interiors.inside = k
		player.interior_door = city.spawn_point
		player.global_position = o + Vector3(0, 0.3, interiors.ROOM.z / 2.0 - 1.5)
		main_sun_off()
		cam.global_position = o + Vector3(0, 2.6, interiors.ROOM.z / 2.0 - 0.6)
		cam.look_at(o + Vector3(0, 0.7, -1.5))
		cam.make_current()
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("user://rooms/%s.png" % k)
		print("ROOMS %s pluie visible=%s émet=%s inside=%s y=%.1f proc=%s" % [k, weather._rain_fx.visible, weather._rain_fx.emitting, interiors.inside, player.global_position.y, weather.can_process()])
	get_tree().quit()


func main_sun_off() -> void:
	sun.visible = false
	_update_daylight()


## Test : -- --ped-motion (glissades des passants : vitesse image par image des passants proches pendant 20 s)
func _ped_motion_test() -> void:
	hud._intro.visible = false
	player.global_position = city.places["Marché Sandaga"] + Vector3(0, 0.5, 0)
	await get_tree().create_timer(3.0).timeout
	var last := {}
	var frames := 0
	var fast := 0
	var worst := 0.0
	var slide := 0 ## images où la vitesse change brutalement (> 2 m/s d'une image à l'autre)
	var prev_v := {}
	var t := 0.0
	var popped := 0
	var backward := 0
	var sideways := 0
	var seen := {}
	var cam := get_viewport().get_camera_3d()
	var nd: int = city.nearest_node(player.global_position, "walk")
	while t < 30.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		# Le joueur avance dans la ville (un pas de 25 m toutes les 2 s le long des rues)
		if fmod(t, 2.0) < dt:
			nd = city.next_node(nd, city.walk_neighbors(nd)[0], "walk") if not city.walk_neighbors(nd).is_empty() else nd
			player.global_position = city.node_pos[nd] + Vector3(0, 1.0, 0)
		for p in peds:
			var vis_now: bool = p.visible and cam.is_position_in_frustum(p.position + Vector3(0, 1, 0)) and _flat(p.position, cam.global_position) < 60.0
			if seen.has(p) and _flat(p.position, seen[p]) > 5.0 and vis_now:
				popped += 1
			seen[p] = p.position
			if not p.visible or p.knocked or p.mood != "" or _flat(p.position, player.global_position) > 30.0:
				last.erase(p)
				continue
			if last.has(p) and dt > 0.0:
				var v: float = _flat(p.position, last[p]) / dt
				frames += 1
				worst = maxf(worst, v)
				if v > 3.0:
					fast += 1
				if prev_v.has(p) and absf(v - prev_v[p]) > 2.0:
					slide += 1
				prev_v[p] = v
				# Marche à reculons : le déplacement va à l'opposé de là où regarde le modèle
				if v > 0.4:
					var mv: Vector3 = (p.position - last[p]).normalized()
					var ry: float = p._model.global_rotation.y
					var face := Vector3(-sin(ry), 0, -cos(ry))
					var c := mv.x * face.x + mv.z * face.z
					if c < -0.3:
						backward += 1
					elif c < 0.5:
						sideways += 1
			last[p] = p.position
	print("PEDMOTION mesures=%d trop_rapide=%d (%.2f %%) à-coups=%d vitesse_max=%.1f m/s apparitions_à_vue=%d à_reculons=%d de_côté=%d" % [frames, fast, 100.0 * fast / maxf(1, frames), slide, worst, popped, backward, sideways])
	get_tree().quit()


## Test : -- --traffic-motion (conduite des voitures du trafic proches pendant 40 s : hors chaussée,
## mauvais côté, cap qui s'écarte de la rue, zigzags, marche arrière, voitures bloquées)
func _traffic_motion_test() -> void:
	hud._intro.visible = false
	var at := "Marché Sandaga"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--at="):
			at = arg.trim_prefix("--at=")
	await get_tree().create_timer(3.0).timeout
	var n := 0
	var off := 0
	var wrong := 0
	var heading := 0
	var zig := 0
	var reverse := 0
	var stuck := 0
	var prev_yaw := {}
	var prev_rate := {}
	var still := {}
	var samples := {}
	var t := 0.0
	while t < 40.0:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		for v in traffic:
			if not is_instance_valid(v) or not v.ai_enabled or v.driver != null or v.chasing or v.route_active:
				continue
			if _flat(v.global_position, player.global_position) > 90.0:
				prev_yaw.erase(v)
				continue
			n += 1
			var p: Vector3 = v.global_position
			var pa: Vector3 = city.node_pos[v.ai_from]
			var pb: Vector3 = city.node_pos[v.ai_to]
			var d := Vector2(pb.x - pa.x, pb.z - pa.z)
			var L := d.length()
			var kinds: Array = []
			if not city.in_roadway(p, 0.3):
				off += 1
				kinds.append("hors")
			if L > 6.0:
				d /= L
				var right := Vector2(-d.y, d.x)
				var lat := Vector2(p.x - pa.x, p.z - pa.z).dot(right)
				var along := Vector2(p.x - pa.x, p.z - pa.z).dot(d)
				var w: float = city.edge_width(v.ai_from, v.ai_to)
				# Au milieu du tronçon (loin des carrefours) : du bon côté et dans l'axe
				if along > 6.0 and along < L - 6.0:
					if not city.is_oneway(v.ai_from, v.ai_to) and lat < -0.2 and w >= 5.0:
						wrong += 1
						kinds.append("gauche")
					var f := Vector2(-sin(v.rotation.y), -cos(v.rotation.y))
					if absf(v.speed) > 2.0 and f.dot(d) < cos(deg_to_rad(25.0)):
						heading += 1
						kinds.append("cap")
			if v.speed < -0.3:
				reverse += 1
				kinds.append("recul")
			if prev_yaw.has(v) and dt > 0.0:
				var rate := angle_difference(prev_yaw[v], v.rotation.y) / dt
				if prev_rate.has(v) and absf(rate) > 0.35 and absf(prev_rate[v]) > 0.35 and signf(rate) != signf(prev_rate[v]):
					zig += 1
					kinds.append("zigzag")
				prev_rate[v] = rate
			prev_yaw[v] = v.rotation.y
			still[v] = (still.get(v, 0.0) + dt) if absf(v.speed) < 0.3 and v._sign_speed(0.0) > 0.5 and not v._ped_block else 0.0
			if still[v] > 12.0:
				stuck += 1
				kinds.append("bloquée")
			for k in kinds:
				if not samples.has(k) or (samples[k].size() < 6 and randf() < 0.01):
					if not samples.has(k):
						samples[k] = []
					var dd := Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
					var rel := Vector2(p.x - pa.x, p.z - pa.z)
					samples[k].append("%s (%.1f, %.1f) v=%.1f %d→%d L=%.0f w=%.1f sens_unique=%s lat=%.1f le_long=%.1f cap=%.0f° rue=%.0f° bloq=%.1f piéton=%s feu=%d panneau=%.1f maintien=%s" % [v.vehicle_type, p.x, p.z, v.speed, v.ai_from, v.ai_to, L, city.edge_width(v.ai_from, v.ai_to), city.is_oneway(v.ai_from, v.ai_to), rel.dot(Vector2(-dd.y, dd.x)), rel.dot(dd), rad_to_deg(v.rotation.y), rad_to_deg(atan2(-dd.x, -dd.y)), v._ai_blocked, v._ped_block, city.lights.state_for(v.ai_to, v.ai_from) if city.lights != null else -1, v._sign_speed(0.0), v.hold])
	print("TRAFFIC mesures=%d hors_chaussée=%d mauvais_côté=%d cap_écarté=%d zigzags=%d marche_arrière=%d bloquées=%d" % [n, off, wrong, heading, zig, reverse, stuck])
	for k in samples:
		print("TRAFFIC  exemple %s : %s" % [k, " | ".join(samples[k])])
	get_tree().quit()


## Test : -- --feet-test (hauteur des pieds par rapport au sol : joueur et passants, à l'arrêt et en marche)
func _feet_test() -> void:
	hud._intro.visible = false
	weather.forced = "clair"
	GameState.game_minutes = 12.0 * 60.0
	# Sur un trottoir, près du joueur
	var nd: int = city.nearest_node(player.global_position, "walk")
	var nb: PackedInt32Array = city.walk_neighbors(nd)
	var sp: Vector3 = city.sidewalk_point(nd, nb[0], 6.0, 1)
	player.global_position = sp + Vector3(0, 1.0, 0)
	await get_tree().create_timer(3.0).timeout
	var space := get_world_3d().direct_space_state
	var report := func(who: String, ch: Node3D):
		var sk: Skeleton3D = ch.skeleton
		if sk == null:
			return
		var out := []
		for b in ["foot_l", "ball_l", "foot_r", "ball_r"]:
			var i := sk.find_bone(b)
			var p: Vector3 = sk.global_transform * sk.get_bone_global_pose(i).origin
			var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.5, 0), p + Vector3(0, -3, 0), 1 | 32)
			q.exclude = [player.get_rid()]
			var hit := space.intersect_ray(q)
			out.append("%s=%+.3f" % [b, p.y - hit.position.y if hit else 99.0])
		print("FEET %s racine=%.3f %s" % [who, ch.global_position.y, " ".join(out)])
	for k in 4:
		report.call("joueur(idle)", player.model)
		await get_tree().create_timer(0.37).timeout
	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout
	for k in 6:
		report.call("joueur(marche)", player.model)
		await get_tree().create_timer(0.23).timeout
	Input.action_release("move_forward")
	await get_tree().create_timer(0.8).timeout
	var cam0 := Camera3D.new()
	add_child(cam0)
	var mp: Vector3 = player.model.global_position
	cam0.global_position = mp + Vector3(1.6, 0.45, 0.6)
	cam0.look_at(mp + Vector3(0, 0.25, 0))
	cam0.make_current()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("user://feet_player.png")
	var near := peds.filter(func(p): return p.visible and not p.knocked)
	near.sort_custom(func(a, b): return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
	for p in near.slice(0, 4):
		for k in 4:
			report.call("passant", p._model)
			await get_tree().create_timer(0.19).timeout
	var cam := Camera3D.new()
	add_child(cam)
	var tp: Vector3 = near[0].global_position
	cam.global_position = tp + Vector3(2.2, 0.35, 0.0)
	cam.look_at(tp + Vector3(0, 0.4, 0))
	cam.make_current()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("user://feet_ped.png")
	get_tree().quit()


## Test : -- --cook-test (cuisine, revente au restaurant, compétences, appli Profil). Partie de test à part.
## Test : -- --market-test (grand marché : site, étals, vendeurs, achat, vue d'en haut et depuis l'entrée)
func _market_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	await get_tree().create_timer(3.0).timeout
	print("MARKET site=%s entrée=%s étals=%d" % [market.site, market.site_entrance, market.stalls.size()])
	var bad := 0
	for s in market.stalls:
		if is_inside_building(s["pos"]) or city.in_roadway(s["pos"], 0.5) or is_inside_building(s["front"]):
			bad += 1
	print("MARKET étals mal placés=%d" % bad)
	GameState.game_minutes = 10.0 * 60.0
	player.global_position = market.site_entrance + Vector3(0, 0.5, 0)
	var dk: Vector3 = market.site - player.global_position
	player.camera_rig.yaw = atan2(dk.x, dk.z) + PI
	await get_tree().create_timer(3.0).timeout
	print("MARKET vendeurs=%d" % market._vendors.size())
	get_viewport().get_texture().get_image().save_png("user://market_entree.png")
	# Marcher jusqu'au premier étal de l'allée et acheter
	var st: Dictionary = market.stalls[1]
	player.global_position = st["front"] + Vector3(0, 0.5, 0)
	await get_tree().create_timer(0.5).timeout
	print("MARKET indice=%s" % player.get_interaction_hint())
	GameState.money = 5000
	player._interact()
	await get_tree().create_timer(0.3).timeout
	hud.close_choices() if hud.has_method("close_choices") else null
	var dk2: Vector3 = st["pos"] - player.global_position
	player.camera_rig.yaw = atan2(dk2.x, dk2.z) + PI
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://market_allee.png")
	hud.visible = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.far = 2000.0
	cam.global_position = market.site + Vector3(0, 60, 45)
	cam.look_at(market.site)
	cam.make_current()
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png("user://market_haut.png")
	get_tree().quit()


## Outil : -- --market-scan (grands terrains libres, ni bâtiment ni chaussée, près des marchés)
func _market_scan() -> void:
	await get_tree().create_timer(2.0).timeout
	var found: Array = []
	var c: Vector3 = (city.places["Marché Sandaga"] + city.places["Marché Tilène"] + city.places["Marché Kermel"]) / 3.0
	var R := 900.0
	var step := 8.0
	var x := c.x - R
	while x <= c.x + R:
		var z := c.z - R
		while z <= c.z + R:
			var p := Vector3(x, 0, z)
			# Rectangle de 56 × 40 m (en grille de 4 m) entièrement libre
			var ok := true
			for gx in range(-7, 8):
				for gz in range(-5, 6):
					var q := p + Vector3(gx * 4.0, 0, gz * 4.0)
					if is_inside_building(q) or city.in_roadway(q, 1.5) or not city.bounds.has_point(Vector2(q.x, q.z)):
						ok = false
						break
				if not ok:
					break
			if ok:
				# une route à moins de 25 m pour y venir
				var near_road := false
				for k in 16:
					var q := p + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * 34.0
					if city.in_roadway(q, 0.5):
						near_road = true
				if near_road:
					found.append([p.distance_to(c), p])
			z += step
		x += step
	found.sort_custom(func(a1, b1): return a1[0] < b1[0])
	for i in mini(found.size(), 25):
		var p: Vector3 = found[i][1]
		var nearest := ""
		var nd := INF
		for pl in city.places:
			var d: float = Vector2(p.x - city.places[pl].x, p.z - city.places[pl].z).length()
			if d < nd:
				nd = d
				nearest = pl
		print("SCAN %.0f m du centre des marchés : (%.0f, %.0f) près de %s (%.0f m)" % [found[i][0], p.x, p.z, nearest, nd])
	print("SCAN total=%d" % found.size())
	var shot_at := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scan-shot="):
			shot_at = arg.trim_prefix("--scan-shot=")
	if shot_at != "":
		var xy := shot_at.split(",")
		var target := Vector3(float(xy[0]), 0, float(xy[1]))
		hud._intro.visible = false
		hud.visible = false
		player.global_position = target + Vector3(0, 0.5, 0)
		GameState.game_minutes = 11.0 * 60.0
		var cam := Camera3D.new()
		add_child(cam)
		cam.far = 2000.0
		cam.global_position = target + Vector3(0, 70, 55)
		cam.look_at(target)
		cam.make_current()
		await get_tree().create_timer(4.0).timeout
		get_viewport().get_texture().get_image().save_png("user://scan_site.png")
	get_tree().quit()


## Test : -- --biz-test (ancien commerce repris, embauche, stock, prix, journées, vol, impayés, démission)
func _biz_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	await get_tree().create_timer(2.0).timeout
	var id := "dibiterie_gueule_tapee"
	GameState.home["owned"] = [id]
	GameState.home.erase("biz")
	GameState.home["till"] = {}
	commerce._migrate()
	print("BIZ repris : %s" % [commerce.biz(id)])
	var c: Array = commerce.candidates(id)
	print("BIZ candidats=%s" % [c.map(func(x): return "%s %d★ %d %s h=%.2f" % [x["name"], x["skill"], x["wage"], x["hint"], x["honesty"]])])
	for x in c:
		commerce.hire(id, x)
	GameState.money = 200000
	commerce.order_stock(id, 7)
	for d in 10:
		GameState.new_day.emit()
		var b: Dictionary = commerce.biz(id)
		print("BIZ jour %d : %s rep=%d stock=%.1f équipe=%d caisse=%d" % [d, commerce.report_text(id), int(b["rep"]), b["stock"], b["staff"].size(), housing.till(id)])
	commerce.biz(id)["price"] = "eleve"
	commerce.order_stock(id, 7)
	for d in 3:
		GameState.new_day.emit()
	print("BIZ prix élevés : %s rep=%d" % [commerce.report_text(id), int(commerce.biz(id)["rep"])])
	commerce.biz(id)["stock"] = 0.0
	GameState.home["till"] = {}
	GameState.bank = 0
	for d in 3:
		GameState.new_day.emit()
	print("BIZ sans stock ni argent : équipe=%d rep=%d" % [commerce.biz(id)["staff"].size(), int(commerce.biz(id)["rep"])])
	# Employés visibles devant le commerce
	commerce.biz(id)["staff"] = []
	for x in commerce.candidates(id):
		commerce.hire(id, x)
	GameState.game_minutes = 12.0 * 60.0
	var dd: Dictionary = housing.doors[id]
	player.global_position = dd["pos"] - dd["n"] * 7.0 + Vector3(0, 0.5, 0)
	var dk: Vector3 = dd["pos"] - player.global_position
	player.camera_rig.yaw = atan2(dk.x, dk.z) + PI
	await get_tree().create_timer(4.0).timeout
	print("BIZ affiché=%s" % [commerce._shown.keys()])
	get_viewport().get_texture().get_image().save_png("user://biz_devanture.png")
	hud.phone.open()
	hud.phone._show("biz")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://biz_appli.png")
	get_tree().quit()


## Test : -- --rental-test (louer, rouler, rendre en retard avec dégâts ; permis ; arrestation ; sauvegarde)
func _rental_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	await get_tree().create_timer(2.0).timeout
	print("RENT agences=%s" % [rental.agencies])
	GameState.money = 100000
	GameState.inventory.erase("Permis de conduire")
	player.global_position = rental.agencies[0][1] + Vector3(0, 0.5, 1.5)
	await get_tree().physics_frame
	print("RENT indice=%s" % player.get_interaction_hint())
	print("RENT berline sans permis=%s" % rental.rent("clando", 6))
	print("RENT moto=%s argent=%d" % [rental.rent("jakarta", 6), GameState.money])
	await get_tree().create_timer(1.0).timeout
	var kp: Vector3 = rental.agencies[0][1]
	var rp: Vector3 = rental.agencies[0][2]
	player.global_position = rp + (rp - kp).normalized() * 3.0 + Vector3(0, 0.5, 0)
	var dk: Vector3 = kp - player.global_position
	player.camera_rig.yaw = atan2(dk.x, dk.z) + PI
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://rental_agence.png")
	var car = rental.car
	print("RENT véhicule=%s à %.1f m de l'agence" % [car.vehicle_type, car.global_position.distance_to(rental.agencies[0][1])])
	print("RENT location=%s" % [GameState.rental])
	player.enter_vehicle(car)
	await get_tree().create_timer(0.5).timeout
	car.fuel = 70.0
	car.condition = 80.0
	GameState.advance_time(7.0 * 60.0)
	await get_tree().create_timer(2.5).timeout
	print("RENT reste=%.1f h indice=%s dist parking=%.1f au volant=%s" % [rental.hours_left(), player.get_interaction_hint(), car.global_position.distance_to(rental.agencies[0][2]), player.current_vehicle == car])
	var before := GameState.money
	player._interact()
	print("RENT rendu : +%d actif=%s véhicule=%s" % [GameState.money - before, rental.active(), player.current_vehicle])
	rental.rent("jakarta", 12)
	before = GameState.money
	police.arrested_by("Test")
	print("RENT arrestation : +%d actif=%s" % [GameState.money - before, rental.active()])
	GameState.jail = 0.0
	interiors._exit()
	await get_tree().create_timer(1.0).timeout
	rental.rent("jakarta", 6)
	GameState.advance_time(31.0 * 60.0)
	await get_tree().create_timer(2.5).timeout
	print("RENT plainte : actif=%s étoiles=%d" % [rental.active(), GameState.wanted])
	get_tree().quit()


func _cook_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.inventory = {"Sac de riz (5 kg)": 1, "Thiof": 1, "Yaboy (sardinelle)": 2, "Huile (1 L)": 2, "Poulpe": 1, "Capitaine": 1}
	await get_tree().create_timer(2.0).timeout
	for r in cooking.RECIPES:
		cooking.cook(r)
	cooking.cook("Thiéboudienne")
	print("COOK sac=%s cuisine niv=%d" % [GameState.inventory, GameState.skill_level("cuisine")])
	GameState.add_skill("conduite", 50.0)
	interiors.enter_first("restaurant")
	await get_tree().create_timer(2.0).timeout
	print("COOK rachat=%s" % [cooking.resale_total()])
	cooking.sell_dishes()
	print("COOK argent=%d sac=%s" % [GameState.money, GameState.inventory])
	interiors._exit()
	await get_tree().create_timer(2.0).timeout
	hud.phone.open()
	hud.phone._show("profile")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://profile.png")
	get_tree().quit()


## Test : -- --impound-test (arrêté avec son véhicule dehors : fourrière, puis récupération). Partie de test à part.
func _impound_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.money = 50000
	GameState.vehicles = [{"type": "jakarta", "color": "c1121f", "fuel": 80.0}]
	await get_tree().create_timer(2.0).timeout
	dealership.bring(0)
	await get_tree().create_timer(1.0).timeout
	GameState.wanted = 1
	police._bust(false)
	await get_tree().create_timer(1.0).timeout
	print("IMPOUND véhicules=%s dehors=%s" % [GameState.vehicles, dealership.out])
	main_prison_free()
	dealership.bring(0)
	print("IMPOUND à récupérer=%s" % [dealership.impounded()])
	dealership.release(0)
	print("IMPOUND après sortie : véhicules=%s argent=%d" % [GameState.vehicles, GameState.money])
	# Assurance : réparation gratuite au garage
	interiors._exit()
	await get_tree().create_timer(2.0).timeout
	dealership._insure(0)
	dealership.bring(0)
	await get_tree().create_timer(1.0).timeout
	var v = dealership.out
	v.condition = 0.0
	player.global_position = v.global_position
	player.enter_vehicle(v)
	await get_tree().create_timer(0.5).timeout
	print("IMPOUND assuré=%s argent=%d" % [dealership.out_insured(v), GameState.money])
	var gpos := Vector3.ZERO
	for d in interiors._doors:
		if d[1] == "garage":
			gpos = d[2]
			break
	v.global_position = gpos + Vector3(0, 0.5, 0)
	await get_tree().create_timer(0.5).timeout
	interiors.try_interact()
	print("IMPOUND menu garage : %s" % hud.choices_open())
	for b in hud._choices.find_children("*", "Button", true, false):
		print("IMPOUND bouton : %s" % b.text)
		b.pressed.emit()
		break
	print("IMPOUND après garage : état=%d argent=%d" % [int(v.condition), GameState.money])
	get_tree().quit()


func main_prison_free() -> void:
	GameState.jail = 0.0


## Test en ligne : -- --pv-net (PolA policier en service dresse un PV à PolB)
func _pv_net_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	var cop: bool = Net.pseudo == "PolA"
	GameState.money = 2000
	GameState.bank = 10000
	player.global_position = city_hall.pos + Vector3(2.0 if cop else -1.0, 0.5, 0)
	if cop:
		GameState.rp_job = "police"
	await get_tree().create_timer(8.0).timeout
	if cop:
		var o = remote_players.nearest(player.global_position, 8.0)
		print("PVNET indice : %s" % ni_hint())
		if o != null:
			Net.city.ticket(o["id"], "Conduite sans permis")
			Net.city.ticket(o["id"], "Motif inventé")
	await get_tree().create_timer(4.0).timeout
	print("PVNET %s fin : argent=%d compte=%d relevé=%s" % [Net.pseudo, GameState.money, GameState.bank, GameState.bank_log])
	get_tree().quit()


## Test : -- --rob-test (braquage d'une station : alarme, butin, recherché). Partie de test à part.
func _rob_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.money = 1000
	await get_tree().create_timer(2.0).timeout
	interiors.enter_first("station")
	await get_tree().create_timer(2.0).timeout
	var o: Vector3 = interiors._rooms[interiors.inside]
	player.global_position = o + Vector3(0, 0.3, -interiors.ROOM.z / 2.0 + 2.8)
	await get_tree().create_timer(0.5).timeout
	print("ROB intérieur=%s indice=%s" % [interiors.inside, ni_hint()])
	interiors._start_robbery()
	await get_tree().create_timer(5.0).timeout
	print("ROB statut=%s étoiles=%d" % [interiors.robbery_status, GameState.wanted])
	await get_tree().create_timer(11.5).timeout
	print("ROB fin : argent=%d étoiles=%d" % [GameState.money, GameState.wanted])
	interiors._start_robbery()
	get_tree().quit()


## Test : -- --fish-test (canne, lancer, ferrer, vente). Partie de test à part.
func _fish_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.money = 10000
	GameState.energy = 100.0
	player.global_position = fishing.stall + Vector3(0, 0.5, 0)
	await get_tree().create_timer(2.0).timeout
	print("FISH indice mareyeuse : %s" % ni_hint())
	fishing._buy_rod()
	player.global_position = fishing.shore + Vector3(0, 0.5, 0)
	await get_tree().create_timer(1.5).timeout
	print("FISH indice plage : %s (sol y=%.1f)" % [ni_hint(), player.global_position.y])
	get_viewport().get_texture().get_image().save_png("user://fish_shore.png")
	for i in 3:
		fishing.try_interact()
		while fishing._state != "touche":
			await get_tree().process_frame
		print("FISH indice : %s / statut : %s" % [ni_hint(), fishing.status])
		fishing.try_interact()
	player.global_position = fishing.stall + Vector3(0, 0.5, 0)
	await get_tree().create_timer(1.0).timeout
	print("FISH sac=%s" % GameState.inventory)
	fishing._sell()
	print("FISH argent=%d sac=%s" % [GameState.money, GameState.inventory])
	get_tree().quit()


## Test en ligne : -- --city-net (deux joueurs CitA et CitB : élection, virement, mécanicien, radio)
func _city_net_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	Net.chat_received.connect(func(w, t): print("CHAT %s <- %s : %s" % [Net.pseudo, w, t]))
	var a: bool = Net.pseudo == "CitA"
	GameState.money = 100000
	GameState.bank = 20000
	player.global_position = city_hall.pos + Vector3(2.0 if a else -1.0, 0.5, 0)
	await get_tree().create_timer(5.0).timeout
	city_hall._make_id()
	if a:
		city_hall._run()
	await get_tree().create_timer(3.0).timeout
	if not a:
		city_hall._vote("CitA")
	await get_tree().create_timer(2.0).timeout
	print("CITYNET %s état=%s" % [Net.pseudo, Net.city.state])
	if a:
		city_hall.bank_transfer("CitB", 5000)
		city_hall.bank_transfer("PersonneXYZ", 1000)
		var v = Vehicle.new()
		v.vehicle_type = "clando"
		add_child(v)
		v.global_position = player.global_position
		player.enter_vehicle(v)
		v.condition = 20.0
		v.fuel = 10.0
	else:
		net_jobs._start_mechanic()
		Net.send_chat("/f allo la radio")
	await get_tree().create_timer(4.0).timeout
	if not a:
		var o = remote_players.nearest(player.global_position, 8.0)
		print("CITYNET %s indice près de CitA : %s" % [Net.pseudo, ni_hint()])
		if o != null:
			Net.city.service(o["id"])
	await get_tree().create_timer(4.0).timeout
	var cv = player.current_vehicle
	print("CITYNET %s fin : compte=%d argent=%d relevé=%s véhicule=%s" % [Net.pseudo, GameState.bank, GameState.money, GameState.bank_log,
		("état %d essence %d" % [int(cv.condition), int(cv.fuel)]) if cv else "aucun"])
	get_tree().quit()


## Test : -- --city-test (mairie, garde à vue et caution, garage, relevé de banque). Partie de test à part.
func _city_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.money = 100000
	player.global_position = city_hall.pos + Vector3(0, 0.5, 0)
	await get_tree().create_timer(2.0).timeout
	print("CITY indice mairie : %s" % ni_hint())
	city_hall._make_id()
	print("CITY carte=%s argent=%d taxe hors ligne=%d" % [city_hall.has_id(), GameState.money, city_hall.tax_rate()])
	# Arrestation : 2 étoiles → cellule
	GameState.wanted = 2
	police._bust(false)
	await get_tree().create_timer(3.0).timeout
	print("CITY en cellule=%s intérieur=%s peine=%d statut=%s" % [prison.jailed(), interiors.inside, int(GameState.jail), prison.status])
	print("CITY indice en cellule : %s" % ni_hint())
	get_viewport().get_texture().get_image().save_png("user://city_test.png")
	var before := GameState.money
	prison.pay_bail()
	print("CITY après caution : en cellule=%s caution payée=%d" % [prison.jailed(), before - GameState.money])
	interiors._exit()
	await get_tree().create_timer(2.0).timeout
	# Banque
	GameState.money = 50000
	interiors._deposit(10000)
	interiors._withdraw(4000)
	print("CITY relevé=%s compte=%d" % [GameState.bank_log, GameState.bank])
	# Véhicule abîmé : réparation au garage
	var v = Vehicle.new()
	v.vehicle_type = "clando"
	add_child(v)
	v.condition = 30.0
	var gpos := Vector3.ZERO
	for d in interiors._doors:
		if d[1] == "garage":
			gpos = d[2]
			break
	v.global_position = gpos + Vector3(0, 0.5, 0)
	player.global_position = v.global_position
	player.enter_vehicle(v)
	await get_tree().create_timer(1.0).timeout
	print("CITY indice garage : %s" % ni_hint())
	interiors.try_interact()
	await get_tree().create_timer(0.5).timeout
	print("CITY menu garage ouvert=%s" % hud.choices_open())
	get_tree().quit()


## Test : -- --dealer-test (achat à la concession, véhicule amené, plein d'essence, revente). Partie de test à part.
func _dealer_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.money = 3000000
	GameState.add_item("Permis de conduire")
	player.global_position = dealership.pos + Vector3(0, 0.5, 0)
	await get_tree().create_timer(2.0).timeout
	print("DEALER indice à la concession : %s" % ni_hint())
	get_viewport().get_texture().get_image().save_png("user://dealer_test.png")
	dealership._buy("clando", "Rouge")
	await get_tree().create_timer(1.0).timeout
	var v = dealership.out
	print("DEALER véhicules=%s sorti=%s essence=%s argent=%d" % [GameState.vehicles, v.vehicle_type if v else "aucun", v.fuel if v else -1, GameState.money])
	# Station : le véhicule à moitié vide, le joueur au volant près d'une station
	var st: Vector3 = dealership.stations[0]
	v.global_position = st + Vector3(0, 0.5, 0)
	player.global_position = v.global_position
	player.enter_vehicle(v)
	v.fuel = 40.0
	await get_tree().create_timer(1.0).timeout
	print("DEALER indice à la station : %s" % ni_hint())
	for pv in player.providers:
		if pv == dealership:
			pv.try_interact()
	print("DEALER après le plein : essence=%d argent=%d" % [int(v.fuel), GameState.money])
	# Panne sèche : plus d'accélération
	v.fuel = 0.0
	await get_tree().create_timer(1.0).timeout
	dealership.store()
	print("DEALER rangé : véhicules=%s sorti=%s" % [GameState.vehicles, dealership.out])
	dealership._sell(0)
	print("DEALER après revente : véhicules=%s argent=%d" % [GameState.vehicles, GameState.money])
	get_tree().quit()


## Test : -- --goods-shots (photo de près d'un étal de chaque type : vrais fruits, légumes et marchandises)
func _goods_shots() -> void:
	hud._intro.visible = false
	hud.visible = false
	GameState.game_minutes = 11.0 * 60.0
	await get_tree().create_timer(3.0).timeout
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 55.0
	var done := {}
	for s in market.stalls:
		if done.has(s["type"]):
			continue
		done[s["type"]] = true
		var d: Vector3 = (s["front"] - s["pos"]).normalized()
		player.global_position = s["front"] + d * 3.0 + Vector3(0, 0.5, 0)
		cam.global_position = s["pos"] + d * 2.1 + Vector3(0, 1.75, 0)
		cam.look_at(s["pos"] + Vector3(0, 0.8, 0))
		cam.current = true
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png("user://goods_%s.png" % s["type"])
		print("SHOT %s" % s["type"])
	get_tree().quit()


## Test : -- --touch --hud-shot (HUD au format téléphone avec les boutons du mode en ligne et une notification)
func _hud_shot() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(4.0).timeout
	hud.preview_online = true
	hud._online.text = "En ligne : 12 joueur(s) — Moustapha"
	GameState.notify.emit("Tu as acheté : Banane (100 FCFA). Satiété +8.")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://hud_shot.png")
	get_tree().quit()


## Test en ligne : -- --online=127.0.0.1 --pseudo=Ven... --trade-net (propose et donne argent, bananes, une
## voiture) ; autre pseudo = accepte et donne une mangue. Les deux valident, puis on vérifie les parties.
func _trade_net_test() -> void:
	hud._intro.visible = false
	var seller: bool = Net.pseudo.begins_with("Ven")
	player.global_position = city.places["Place de l'Indépendance"] + Vector3(1.0 if seller else -1.0, 0.5, 0)
	GameState.notify.connect(func(t): print("NOTIFY %s : %s" % [Net.pseudo, t]))
	GameState.money = 5000
	GameState.inventory = {"Banane": 3} if seller else {"Mangue": 1}
	GameState.vehicles = [{"type": "jakarta", "color": "c1121f", "fuel": 70.0}] if seller else []
	# Le vendeur cède aussi sa boutique de Sandaga avec ses employés
	GameState.home = {"owned": ["boutique_sandaga"] if seller else [], "biz": {}}
	if seller:
		Net.properties.claim("boutique_sandaga")
		commerce.biz("boutique_sandaga")["staff"] = [{"name": "Test", "wage": 1000}]
	var t = Net.trade
	t.invited.connect(func(tid, _f): t.accept(tid))
	t.opened.connect(func(_tid, other):
		print("TRADENET %s fenêtre ouverte avec %s (affichée=%s)" % [Net.pseudo, other, trade_ui.is_open()])
		await get_tree().create_timer(1.0).timeout
		if seller:
			t.set_money(2000)
			t.add_item("Banane", 1)
			t.add_item("Banane", 1)
			t.toggle_vehicle(0)
			t.toggle_property("boutique_sandaga")
		else:
			t.add_item("Mangue", 1)
		await get_tree().create_timer(1.5).timeout
		print("TRADENET %s voit l'offre : %s" % [Net.pseudo, t.their_offer])
		t.lock())
	await get_tree().create_timer(4.0).timeout
	if seller and not Net.remote.is_empty():
		t.propose(Net.remote.keys()[0])
	await get_tree().create_timer(9.0).timeout
	print("TRADENET %s après : argent=%d sac=%s véhicules=%s fenêtre=%s biens=%s employés=%s registre=%s" % [Net.pseudo, GameState.money, GameState.inventory, GameState.vehicles, trade_ui.is_open(), GameState.home.get("owned"), GameState.home.get("biz", {}).get("boutique_sandaga", {}).get("staff"), Net.properties.owner_of("boutique_sandaga")])
	get_tree().quit()


## Test : -- --trade-shot (fenêtre d'échange hors ligne, avec une offre de l'autre joueur simulée)
func _trade_shot() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(3.0).timeout
	GameState.money = 25000
	GameState.inventory = {"Banane": 3, "Masque en bois": 1, "Thiof (poisson)": 2}
	GameState.vehicles = [{"type": "jakarta", "color": "c1121f", "fuel": 70.0}]
	if trade_ui == null:
		trade_ui = TradeUI.new()
		trade_ui.main = self
		add_child(trade_ui)
	Net.trade.rpc_open(1, "Fatou")
	Net.trade.my_offer = {"money": 5000, "items": {"Banane": 2}, "vehicles": [0]}
	Net.trade.rpc_their_offer({"money": 0, "items": {"Bazin riche": 1, "Café Touba": 3}, "vehicles": []})
	Net.trade.rpc_locks(false, true)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://trade_shot.png")
	get_tree().quit()


## -- --foot : ouvre le jeu directement à l'accueil du complexe de mini-foot (de jour, de quoi louer un terrain)
func _foot_open() -> void:
	await get_tree().create_timer(1.0).timeout
	GameState.money = maxi(GameState.money, 20000)
	GameState.energy = 100.0
	GameState.game_minutes = 16.0 * 60.0
	foot.travel_to_complex("taxi")
	await get_tree().create_timer(2.5).timeout
	if "--night" in OS.get_cmdline_user_args():
		GameState.game_minutes = 21.0 * 60.0
	player.global_position = foot.ORIGIN + Vector3(-26.5, 0.5, 0)
	player.camera_rig.yaw = PI / 2.0


## Test : -- --foot-night (match de nuit sous les projecteurs : photos vue d'ensemble et au ras du terrain)
func _foot_night_shot() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(3.0).timeout
	GameState.money = 20000
	GameState.game_minutes = 22.0 * 60.0
	foot.travel_to_complex("taxi")
	await get_tree().create_timer(2.5).timeout
	GameState.game_minutes = 22.0 * 60.0
	player.global_position = foot.ORIGIN + Vector3(-27.4, 0.5, 0)
	await get_tree().create_timer(0.5).timeout
	player._interact()
	await get_tree().create_timer(6.0).timeout
	player.camera_rig.yaw = PI / 2.0
	await get_tree().create_timer(0.6).timeout
	_foot_shot("user://foot_nuit.png")
	player.camera_rig.yaw = PI
	await get_tree().create_timer(0.6).timeout
	_foot_shot("user://foot_nuit2.png")
	var cam: Camera3D = get_viewport().get_camera_3d()
	var c: Vector3 = foot._c()
	cam.global_position = c + Vector3(-26, 16, 20)
	cam.look_at(c, Vector3.UP)
	await get_tree().process_frame
	cam.global_position = c + Vector3(-26, 16, 20)
	cam.look_at(c, Vector3.UP)
	await RenderingServer.frame_post_draw
	_foot_shot("user://foot_nuit3.png")
	get_tree().quit()


## Test : -- --tuto-test (guide des premiers pas joué du début à la fin, comme un nouveau joueur)
func _tuto_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	GameState.tuto = {}
	GameState.game_minutes = 9.0 * 60.0
	tutorial._step = -1
	await get_tree().create_timer(4.0).timeout
	print("TUTO 0 : %s | gps=%s" % [tutorial.objective, gps.label])
	employment.state("cafe")["hired"] = true
	await get_tree().create_timer(0.5).timeout
	print("TUTO 1 : %s" % tutorial.objective)
	player.global_position = city.places["Café Touba"] + Vector3(0, 0.5, 0)
	await get_tree().create_timer(0.5).timeout
	print("TUTO indice=%s" % player.get_interaction_hint())
	jobs.try_interact()
	await get_tree().create_timer(13.5).timeout
	print("TUTO 2 : %s" % tutorial.objective)
	jobs.try_interact()
	await get_tree().create_timer(0.5).timeout
	print("TUTO 3 : %s | gps=%s" % [tutorial.objective, gps.label])
	player.global_position = city.places["Dibiterie"] + Vector3(0, 0.5, 0)
	await get_tree().create_timer(0.5).timeout
	jobs.try_interact()
	await get_tree().create_timer(0.5).timeout
	print("TUTO 4 : %s" % tutorial.objective)
	var before := GameState.money
	hud.phone.open()
	await get_tree().create_timer(1.0).timeout
	print("TUTO fin : actif=%s prime=%d tuto=%s" % [tutorial.active(), GameState.money - before, GameState.tuto])
	get_tree().quit()


## Test : -- --foot-test (taxi vers le complexe, location, match : le joueur conduit le ballon vers le but,
## passe, feinte, tire ; photos du coup d'envoi, du match et d'un arrêt du gardien)
func _foot_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("NOTIFY : %s" % t))
	await get_tree().create_timer(3.0).timeout
	GameState.money = 20000
	GameState.game_minutes = 16.0 * 60.0
	print("FOOT taxi=%s" % foot.travel_to_complex("taxi"))
	await get_tree().create_timer(2.5).timeout
	player.global_position = foot.ORIGIN + Vector3(-27.4, 0.5, 0)
	await get_tree().create_timer(0.5).timeout
	print("FOOT indice accueil=%s" % player.get_interaction_hint())
	player._interact()
	await get_tree().create_timer(4.0).timeout
	var m = foot._match
	print("FOOT match=%s joueurs=%d statut=%s modèle=%s" % [foot.playing, m.men.size() if m else 0, foot.status, player.model._sport])
	_foot_shot("user://foot_coup_envoi.png")
	var acts := {"tir": 0, "passe": 0, "feinte": 0, "tacle": 0}
	var top_speed := 0.0
	var t := 0.0
	var shot_photo := false
	while t < 45.0 and foot.playing:
		var dt := 0.05
		var me: Vector2 = m.pos(0)
		var b: Vector3 = m.ball.p
		var goal := Vector2(m.HL, 0.0)
		var dir := Vector2.ZERO
		if m.player_can_kick():
			var to_goal := goal - me
			if to_goal.length() < 11.0:
				acts["tir"] += 1
				foot._do_shoot(0.75, randf_range(-0.8, 0.8))
				shot_photo = true
			elif acts["passe"] <= acts["feinte"] and randf() < 0.04:
				acts["passe"] += 1
				foot._do_pass(Vector2(0.3, 1.0 if me.y < 0 else -1.0), randf() < 0.3)
			elif randf() < 0.03 and m._nearest_opp(0, me) >= 0 and m.pos(m._nearest_opp(0, me)).distance_to(me) < 3.0:
				if foot._skill_cd <= 0.0:
					acts["feinte"] += 1
					foot._do_skill(Vector2(0, 1))
			dir = to_goal.normalized()
		else:
			var to_b := Vector2(b.x, b.z) - me
			dir = to_b.normalized() if to_b.length() > 0.3 else Vector2.ZERO
			if m.carrier > 0 and m.men[m.carrier]["team"] == 1 and to_b.length() < m.TACKLE and randf() < 0.1:
				acts["tacle"] += 1
				foot._do_tackle()
		if not player.frozen and foot._dash <= 0.0:
			var v := dir * 5.5
			player.velocity = Vector3(v.x, 0, v.y)
			player.global_position += Vector3(v.x, 0, v.y) * dt
			if v.length() > 0.1:
				player.model.rotation.y = atan2(-v.x, -v.y)
		top_speed = maxf(top_speed, m.ball.v.length())
		await get_tree().create_timer(dt).timeout
		t += dt
		if shot_photo and m.ball.v.length() > 8.0:
			shot_photo = false
			if not FileAccess.file_exists("user://foot_tir.png") or t > 20.0:
				player.camera_rig.yaw = PI / 2.0
				await get_tree().create_timer(0.25).timeout
				_foot_shot("user://foot_tir.png")
		if is_equal_approx(snappedf(t, 0.05), 6.0):
			player.camera_rig.yaw = PI
			await get_tree().create_timer(0.2).timeout
			_foot_shot("user://foot_match.png")
			print("FOOT anim=%s numéros=%d porteur=%d" % [player.model._current, foot._numbers.size(), m.carrier])
	print("FOOT gestes=%s ballon max=%.1f m/s score=%s statut=%s" % [acts, top_speed, m.score, foot.status])
	m.time = 0.5
	await get_tree().create_timer(3.0).timeout
	print("FOOT fin : match=%s modèle=%s argent=%d énergie=%d" % [foot.playing, player.model._sport, GameState.money, int(GameState.energy)])
	get_tree().quit()


## Test : -- --foot-net (deux joueurs en ligne, Foot1… crée un match avec mise, l'autre le rejoint ; ils jouent 30 s,
## puis Foot1… quitte : l'autre gagne par forfait et touche la cagnotte)
func _foot_net_test() -> void:
	hud._intro.visible = false
	GameState.notify.connect(func(t): print("FOOTNET %s NOTIFY : %s" % [Net.pseudo, t]))
	await get_tree().create_timer(4.0).timeout
	GameState.money = 20000
	GameState.energy = 100.0
	var host: bool = Net.pseudo.begins_with("Foot1")
	player.global_position = foot.ORIGIN + Vector3(-27.4, 0.5, -4.5)
	await get_tree().create_timer(2.0).timeout
	if host:
		Net.foot.create(1000)
	else:
		await get_tree().create_timer(2.0).timeout
		if not Net.foot.lobbies.is_empty():
			Net.foot.join(int(Net.foot.lobbies[0]["mid"]), 1, int(Net.foot.lobbies[0]["stake"]))
	var wait := 0.0
	while wait < 15.0 and (Net.foot.my_lobby.is_empty() or Net.foot.my_lobby["teams"][1].is_empty()):
		await get_tree().create_timer(0.5).timeout
		wait += 0.5
	print("FOOTNET %s salon=%s argent=%d" % [Net.pseudo, Net.foot.my_lobby, GameState.money])
	if host:
		Net.foot.start()
	await get_tree().create_timer(5.0).timeout
	print("FOOTNET %s en match=%s statut=%s modèle=%s" % [Net.pseudo, foot.online_playing, foot.status, player.model._sport])
	var t := 0.0
	var acts := {"tir": 0, "passe": 0, "feinte": 0, "tacle": 0, "possession": 0}
	var cd := 0.0
	while t < 30.0 and foot.online_playing:
		var dt := 0.05
		var c: Vector3 = foot._pc()
		var me := Vector2(player.global_position.x - c.x, player.global_position.z - c.z)
		var b: Vector3 = Net.foot.ball_now()
		var goal := Vector2(foot._attack_dir() * foot.L / 2.0, 0.0)
		var dir := Vector2.ZERO
		cd -= dt
		if foot._has_ball():
			acts["possession"] += 1
			dir = (goal - me).normalized()
			if cd <= 0.0:
				if (goal - me).length() < 11.0:
					acts["tir"] += 1
					foot._do_shoot(0.7, randf_range(-0.7, 0.7))
					cd = 1.0
				elif randf() < 0.03:
					acts["passe"] += 1
					foot._do_pass(Vector2(0.4, 1.0), false)
					cd = 1.0
				elif randf() < 0.03:
					acts["feinte"] += 1
					foot._do_skill(Vector2(0, 1))
					cd = 1.0
		else:
			var to_b := Vector2(b.x, b.z) - me
			dir = to_b.normalized() if to_b.length() > 0.3 else Vector2.ZERO
			if foot._online_opp_carrier() > 0 and cd <= 0.0 and randf() < 0.1:
				acts["tacle"] += 1
				foot._do_tackle()
				cd = 1.0
		if not player.frozen and foot._dash <= 0.0:
			var v := dir * 5.0
			player.velocity = Vector3(v.x, 0, v.y)
			player.global_position += Vector3(v.x, 0, v.y) * dt
		await get_tree().create_timer(dt).timeout
		t += dt
		if is_equal_approx(snappedf(t, 0.05), 8.0) and DisplayServer.get_name() != "headless":
			_foot_shot("user://foot_net.png")
	print("FOOTNET %s gestes=%s ballon=%s statut=%s numéros=%d modèles_autres=%s" % [Net.pseudo, acts, Net.foot.ball_now(), foot.status, foot._numbers.size(), remote_players.model_override])
	if host:
		Net.foot.leave()
	await get_tree().create_timer(4.0).timeout
	print("FOOTNET %s fin : en match=%s argent=%d modèle=%s" % [Net.pseudo, foot.online_playing, GameState.money, player.model._sport])
	get_tree().quit()


func _foot_shot(path: String) -> void:
	if DisplayServer.get_name() != "headless":
		get_viewport().get_texture().get_image().save_png(path)


## Placer les boutons : SAUT déplacé au doigt, puis il répond à sa nouvelle place ; réglages du joueur remis
func _touch_layout_test() -> void:
	hud._intro.visible = false
	await get_tree().create_timer(2.0).timeout
	var TC = hud.TouchControls
	var saved := [TC.layout.duplicate(), TC.opacity_pref]
	var tc = hud._touch
	var vp := get_viewport()
	var ev_touch := func(idx: int, pos: Vector2, down: bool):
		var ev := InputEventScreenTouch.new()
		ev.index = idx
		ev.position = pos
		ev.pressed = down
		vp.push_input(ev)
	var ev_drag := func(idx: int, pos: Vector2):
		var ev := InputEventScreenDrag.new()
		ev.index = idx
		ev.position = pos
		vp.push_input(ev)
	TC.reset_layout()
	hud.toggle_pause()
	hud._show_touch_menu(true)
	print("LAYOUT sous-menu : principal=%s tactile=%s" % [hud._pause_main.visible, hud._touch_menu.visible])
	hud._layout_mode(true)
	var s: float = tc._scale()
	var jump: Dictionary = tc.FOOT[1]
	var from: Vector2 = tc._center(jump, s)
	var to := Vector2(tc.size.x * 0.5, tc.size.y * 0.6)
	ev_touch.call(0, from, true)
	ev_drag.call(0, to)
	ev_touch.call(0, to, false)
	print("LAYOUT déplacé : de %s à %s (attendu %s), pause visible=%s" % [from, tc._center(jump, s), to, hud._pause.visible])
	var joy0: Vector2 = tc._joy_home(s)
	ev_touch.call(1, joy0, true)
	ev_drag.call(1, joy0 + Vector2(60, -40))
	ev_touch.call(1, joy0 + Vector2(60, -40), false)
	print("LAYOUT joystick : %s -> %s" % [joy0, tc._joy_home(s)])
	print("LAYOUT %s" % TC.cycle_opacity())
	tc.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	vp.get_texture().get_image().save_png("user://touch_layout.png")
	hud.toggle_pause() # Retour : sort du placement
	print("LAYOUT retour : placement=%s pause=%s" % [tc.editing, get_tree().paused])
	hud.toggle_pause()
	await get_tree().process_frame
	ev_touch.call(2, to, true)
	await get_tree().process_frame
	print("LAYOUT appui à la nouvelle place : saut=%s" % Input.is_action_pressed("jump"))
	ev_touch.call(2, to, false)
	ev_touch.call(3, from, true)
	print("LAYOUT appui à l'ancienne place : saut=%s" % Input.is_action_pressed("jump"))
	ev_touch.call(3, from, false)
	TC.layout = saved[0]
	TC.opacity_pref = saved[1]
	TC.save_settings()
	get_tree().quit()
