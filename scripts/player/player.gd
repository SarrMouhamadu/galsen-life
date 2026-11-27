extends CharacterBody3D
## Le joueur : marche, course, saut, monter/descendre des véhicules, parler aux passants.

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

const WALK_SPEED := 2.0 ## marche normale d'un humain
const RUN_SPEED := 6.5
const JUMP_VELOCITY := 5.5
const GRAVITY := 18.0
const MAX_STEP_HEIGHT := 0.25 ## hauteur max franchissable sans sauter (trottoirs 0.16m, bordures 0.14-0.20m)
const PUBLIC_TRANSPORTS := ["bus", "coach", "car_rapide", "ndiaga", "brt", "taxi"]

var camera_rig = null
var job_manager = null
var current_vehicle = null
var riding = null ## véhicule où l'on est passager (bus, car rapide, taxi)
var transit = null
var interior_door := Vector3.ZERO ## porte du bâtiment visité (Vector3.ZERO = dehors)
var providers: Array = [] ## autres lieux d'action : arène, entreprises, marché
var frozen := false ## immobilisé (combat de lutte)
var model: Node3D
var emote := "" ## geste en cours (menu GESTES) : s'arrête dès qu'on bouge
var _lean_roll := 0.0
var _lean_pitch := 0.0
var _squash_scale := Vector3.ONE
var _prev_on_floor := true
var _prev_fall_vy := 0.0
var _step_dist := 0.0
var _step_smooth_y := 0.0 ## lissage visuel du passage de bordure / trottoir
var is_sitting := false ## état assis (chaise ou geste au sol)
var sitting_chair: Node3D = null ## chaise occupée


func is_public_transport(v) -> bool:
	return v != null and v.vehicle_type in PUBLIC_TRANSPORTS


func can_drive_vehicle(v) -> bool:
	if v == null:
		return false
	if not is_public_transport(v):
		return true
	if v.get_meta("player_driver", false) == true:
		return true
	if v.get_meta("taxi_patron", false) == true:
		return true
	if v.get_meta("owned", false) == true:
		return true
	if v.has_meta("rental"):
		return true
	return false


func board_public_transport(v) -> void:
	if v == null:
		return
	if transit and transit.board_vehicle(v):
		return
	ride(v)
	v.set_passenger(self)


func start_emote(clip: String) -> void:
	if current_vehicle or riding or not model.has_method("play_clip"):
		return
	emote = clip
	if clip == "sit":
		is_sitting = true
	Net.emotes.send(clip)


func stop_emote() -> void:
	if emote != "" or is_sitting:
		emote = ""
		is_sitting = false
		sitting_chair = null
		Net.emotes.send("")


## S'asseoir confortablement sur une chaise, un fauteuil ou un banc
func sit_on_chair(chair: Node3D) -> void:
	if current_vehicle or riding:
		return
	is_sitting = true
	sitting_chair = chair
	start_emote("sit")
	if is_instance_valid(chair):
		global_position = chair.global_position + Vector3(0, 0.02, 0)
		model.rotation.y = chair.global_rotation.y
	velocity = Vector3.ZERO
	GameState.notify.emit("Tu t'assois confortablement (Énergie en régénération).")


## Se relever naturellement
func stand_up() -> void:
	if is_sitting or emote == "sit":
		stop_emote()
		GameState.notify.emit("Tu te relèves.")
var _walk_t := 0.0
var no_jump := false ## pendant un match de mini-foot, SAUT sert au dribble
var _anim_lock := 0.0 ## coup de poing ou coup reçu en cours : la marche n'écrase pas l'animation


func _ready() -> void:
	add_to_group("player")
	collision_layer = 4
	collision_mask = 1 | 2 | 16 | 32
	floor_snap_length = 0.32
	floor_constant_speed = true
	floor_max_angle = deg_to_rad(48.0)
	floor_stop_on_slope = true
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	# Le héros réaliste (MakeHuman) : polo crème, pantalon sombre, baskets, coupe courte
	model = RealCharacter.create(self, Net.avatar if Net.avatar != "" else RealCharacter.HERO)
	model.set_outfit(GameState.tenue)


## Met à jour dynamiquement le modèle 3D et la tenue du joueur
func update_avatar(avatar_type: String = "", outfit: String = "") -> void:
	if avatar_type != "":
		Net.avatar = avatar_type
	if outfit != "":
		GameState.tenue = outfit
	if is_instance_valid(model):
		model.queue_free()
	model = RealCharacter.create(self, Net.avatar if Net.avatar != "" else RealCharacter.HERO)
	model.set_outfit(GameState.tenue)


func get_world_position() -> Vector3:
	# Dans un intérieur : on compte la position de la porte (sauvegarde, police, mini-carte)
	if interior_door != Vector3.ZERO:
		return interior_door
	if current_vehicle:
		return current_vehicle.global_position
	if riding:
		return riding.global_position
	return global_position


func _physics_process(delta: float) -> void:
	if riding:
		if not is_instance_valid(riding):
			end_ride()
		else:
			global_position = riding.global_position
			if Input.is_action_just_pressed("interact") and not GameState.typing:
				var emp = get_parent().get("employment")
				if emp != null and emp.apprenti_riding():
					emp.apprenti_action()
				elif transit and transit.is_riding():
					transit.ride_interact()
				else:
					# Passager dans la voiture d'un autre joueur
					end_ride()
					GameState.notify.emit("Tu descends de la voiture.")
			return
	if GameState.typing:
		pass
	elif Input.is_action_just_pressed("interact"):
		_interact()
	elif Input.is_action_just_pressed("steal") and current_vehicle == null:
		var sv = _nearest_vehicle(1.5)
		if sv:
			if is_public_transport(sv) and not can_drive_vehicle(sv):
				board_public_transport(sv)
			else:
				enter_vehicle(sv)
	if current_vehicle:
		global_position = current_vehicle.global_position
		return
	if frozen:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_action_just_pressed("jump") and not GameState.typing and not no_jump:
		velocity.y = JUMP_VELOCITY
		_squash_scale = Vector3(0.92, 1.14, 0.92) # Impulsion athlétique
		if is_sitting:
			stand_up()

	var inp: Vector2 = GameState.get_move_input()
	var yaw: float = camera_rig.yaw if camera_rig else 0.0
	var dir := Vector3(inp.x, 0.0, inp.y).rotated(Vector3.UP, yaw)
	if is_sitting and dir.length() > 0.05:
		stand_up()
	if is_sitting:
		GameState.energy = minf(1.0, GameState.energy + delta * 0.12) # Récupération assis

	var running := Input.is_action_pressed("sprint") or GameState.touch_move.length() > 0.92
	# Épuisé (énergie à zéro) : on ne peut plus courir
	var spd := RUN_SPEED if running and GameState.energy > 0.0 else WALK_SPEED
	if spd == RUN_SPEED and dir.length() > 0.3 and is_on_floor():
		GameState.energy = maxf(0.0, GameState.energy - delta * 0.12 * (1.0 - 0.07 * GameState.skill_level("endurance")))
		GameState.add_skill("endurance", delta / 30.0)

	# Accélération et décélération physique avec inertie réaliste
	var target_vx := dir.x * spd
	var target_vz := dir.z * spd
	var accel_rate: float
	if is_on_floor():
		if dir.length() > 0.08:
			accel_rate = 14.0 if running else 11.0
		else:
			accel_rate = 16.0 # Décélération progressive
	else:
		accel_rate = 3.5 # Inertie de l'air

	velocity.x = move_toward(velocity.x, target_vx, accel_rate * delta * maxf(spd, 3.2))
	velocity.z = move_toward(velocity.z, target_vz, accel_rate * delta * maxf(spd, 3.2))

	# Franchissement fluide et naturel des trottoirs et bordures (sans saut robotique)
	_step_climb(delta)

	move_and_slide()

	# Raccrochage immédiat au sol lors de la descente de trottoir
	if _prev_on_floor and not is_on_floor() and velocity.y <= 0.0:
		apply_floor_snap()

	# Réception au sol : amorti réaliste des genoux sur tout saut ou chute (squash naturel)
	var on_ground := is_on_floor()
	if not _prev_on_floor and on_ground and _prev_fall_vy < -2.0:
		var impact := clampf(-_prev_fall_vy / 18.0, 0.06, 0.24)
		_squash_scale = Vector3(1.0 + impact * 0.45, 1.0 - impact, 1.0 + impact * 0.45)
		Audio.play_sfx("thud", -12.0)
	_prev_on_floor = on_ground
	_prev_fall_vy = velocity.y
	_squash_scale = _squash_scale.lerp(Vector3.ONE, 1.0 - exp(-12.0 * delta))
	model.scale = _squash_scale

	# Amortissement visuel vertical soyeux lors du franchissement de marche ou trottoir
	_step_smooth_y = lerpf(_step_smooth_y, 0.0, 1.0 - exp(-18.0 * delta))
	model.position.y = _step_smooth_y

	var ground_speed := Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
	if dir.length() > 0.05:
		var target_yaw := atan2(-dir.x, -dir.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-11.0 * delta))
		# Roulis (roll) : le corps se penche vers l'intérieur du virage
		var yaw_diff := wrapf(target_yaw - model.rotation.y, -PI, PI)
		var target_roll := clampf(-yaw_diff * (ground_speed / RUN_SPEED) * 0.22, -0.18, 0.18)
		_lean_roll = lerpf(_lean_roll, target_roll, 1.0 - exp(-10.0 * delta))
		# Tangage (pitch) : le buste penche vers l'avant à l'effort de sprint
		var target_pitch := clampf((ground_speed / RUN_SPEED) * 0.12, 0.0, 0.14)
		_lean_pitch = lerpf(_lean_pitch, target_pitch, 1.0 - exp(-8.0 * delta))
	else:
		_lean_roll = lerpf(_lean_roll, 0.0, 1.0 - exp(-10.0 * delta))
		_lean_pitch = lerpf(_lean_pitch, 0.0, 1.0 - exp(-10.0 * delta))
	model.rotation.z = _lean_roll
	model.rotation.x = _lean_pitch

	# Bruitage discret des pas selon la cadence de marche
	if ground_speed > 0.6 and is_on_floor():
		_step_dist += ground_speed * delta
		var step_interval: float = 1.5 if running else 1.15
		if _step_dist >= step_interval:
			_step_dist = 0.0
			Audio.play_sfx("thud", -16.0)
	_anim_lock -= delta
	if emote != "" and (dir.length() > 0.05 or velocity.y > 0.5 or current_vehicle or riding):
		stop_emote()
	if model.has_method("locomote"):
		if _anim_lock <= 0.0:
			if not is_on_floor():
				# Animation aérienne réaliste : impulsion ascendante de saut ou descente de chute
				if velocity.y > 0.4:
					model.play_clip("jump", 0.15, 1.1)
				else:
					model.play_clip("fall", 0.2, 1.0)
			elif emote != "":
				model.play_clip(emote, 0.25)
			else:
				model.locomote(ground_speed)
	elif dir.length() > 0.05:
		_walk_t += delta * spd * 2.2
		Mk.animate_walk(model, _walk_t, 0.6)
	else:
		Mk.animate_walk(model, 0.0, 0.0)

	if global_position.y < -20.0 and interior_door == Vector3.ZERO:
		global_position = Vector3(0, 2, 0)


## Bloque la marche/attente le temps d'une animation (coup de poing, coup reçu)
func lock_anim(t: float) -> void:
	_anim_lock = maxf(_anim_lock, t)


## Franchissement fluide et naturel des trottoirs, bordures et marches sans saut
func _step_climb(delta: float) -> void:
	if not is_on_floor():
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() < 0.01:
		return
	var test_step := horiz * delta
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, test_step, col):
		return # Aucun obstacle devant, avance libre

	# Si l'obstacle a déjà une pente douce marchable (< 45°), move_and_slide s'en charge
	if col.get_normal().y >= 0.7:
		return

	# L'obstacle est vertical (bordure de trottoir, marche, ralentisseur).
	# 1. Vérifier que l'espace au-dessus est libre (hauteur max de marche)
	var up := Vector3(0.0, MAX_STEP_HEIGHT, 0.0)
	if test_move(global_transform, up):
		return # Plafond bas ou obstacle trop haut

	var up_xform: Transform3D = global_transform.translated(up)
	# 2. Vérifier si on peut avancer au niveau supérieur au-dessus de la bordure
	var forward := test_step.normalized() * maxf(test_step.length(), 0.08)
	if test_move(up_xform, forward):
		return # Obstacle haut (mur de maison, muret, véhicule, etc.)

	# 3. Sonde vers le bas pour trouver la surface exacte du trottoir ou de la marche
	var fwd_xform: Transform3D = up_xform.translated(forward)
	var down_col := KinematicCollision3D.new()
	var down := Vector3(0.0, -(MAX_STEP_HEIGHT + 0.08), 0.0)
	if test_move(fwd_xform, down, down_col):
		if down_col.get_normal().y >= 0.65:
			var step_h: float = MAX_STEP_HEIGHT + down_col.get_travel().y
			if step_h > 0.01 and step_h <= MAX_STEP_HEIGHT:
				# Franchissement réussi : montée naturelle du corps avec compensation visuelle fluide
				global_position.y += step_h + 0.005
				global_position += forward
				_step_smooth_y -= (step_h + 0.005)


func _interact() -> void:
	if is_sitting:
		stand_up()
		return
	if job_manager and job_manager.try_interact():
		return
	for pv in providers:
		if pv.try_interact():
			return
	if current_vehicle:
		exit_vehicle()
		return
	# Studio de personnalisation ou atelier de stylisme
	var st := _nearest_studio_spot()
	if st:
		open_character_studio(st.get_meta("character_id", ""))
		return
	# S'asseoir sur une chaise ou un banc à proximité
	var ch := _nearest_chair()
	if ch:
		sit_on_chair(ch)
		return
	# Si un transport en commun est à portée, monter en tant que passager
	if transit and transit.try_interact():
		return
	# Si une moto ou une charrette est à portée, monter directement dessus
	var v = _nearest_vehicle()
	if v and v.vehicle_type in ["jakarta", "grosse_moto", "charette"]:
		enter_vehicle(v)
		return
	if v:
		if is_public_transport(v) and not can_drive_vehicle(v):
			board_public_transport(v)
			return
		enter_vehicle(v)
		return
	var p = _nearest_ped()
	if p:
		if p.get("is_vendor") == true:
			p.buy(self)
		else:
			p.talk()


func get_interaction_hint() -> String:
	if is_sitting:
		return "Se lever"
	if job_manager:
		var h: String = job_manager.get_hint()
		if h != "":
			return h
	if riding:
		return ""
	for pv in providers:
		var ph: String = pv.get_hint()
		if ph != "":
			return ph
	if current_vehicle:
		return "Descendre"
	if transit:
		var th: String = transit.get_hint()
		if th != "":
			return th
	var ch := _nearest_chair()
	if ch:
		return "S'asseoir"
	var st := _nearest_studio_spot()
	if st:
		var sname: String = str(st.get_meta("studio_name", "Studio Personnage"))
		return "Entrer dans le " + sname
	var v = _nearest_vehicle()
	if v:
		if is_public_transport(v) and not can_drive_vehicle(v):
			return "Monter comme passager : " + v.display_name
		var stolen: bool = v.ai_enabled or v.route_active or v.vehicle_type in ["police", "army"]
		if v.vehicle_type in ["jakarta", "grosse_moto"]:
			return "Monter sur la moto : " + v.display_name
		elif v.vehicle_type == "charette":
			return "Monter sur la charrette"
		elif stolen:
			return "Prendre le volant : " + v.display_name
		else:
			return "Conduire : " + v.display_name
	var np = _nearest_ped()
	if np:
		if np.get("is_vendor") == true:
			return "Acheter : %s (%s)" % [np.get("vendor_item"), GameState.fcfa(np.get("vendor_price"))]
		return "Parler au passant"
	return ""


func _nearest_chair(max_d := 1.8) -> Node3D:
	var closest: Node3D = null
	var min_d := max_d
	var nodes := get_tree().get_nodes_in_group("chairs")
	for n in nodes:
		if not n is Node3D or not is_instance_valid(n):
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d < min_d:
			min_d = d
			closest = n
	return closest


func _nearest_studio_spot(max_d := 2.5) -> Node3D:
	var closest: Node3D = null
	var min_d := max_d
	var spots := get_tree().get_nodes_in_group("studio_spots")
	for s in spots:
		if not s is Node3D or not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to(s.global_position)
		if d < min_d:
			min_d = d
			closest = s
	return closest


func open_character_studio(initial_char_id: String = "") -> void:
	var CharacterStudioScript = load("res://scripts/ui/character_studio.gd")
	var studio = CharacterStudioScript.new(initial_char_id)
	var root_node = get_tree().root
	root_node.add_child(studio)
	studio.closed.connect(func(_saved: bool):
		if model and model.has_method("set_outfit"):
			model.set_outfit(GameState.tenue)
	)


func enter_vehicle(v, force_driver: bool = false) -> void:
	if v == null:
		return
	# Les transports en commun ne sont jamais conduits par le joueur (sauf patron taxi ou propriétaire)
	if not force_driver and is_public_transport(v) and not can_drive_vehicle(v):
		board_public_transport(v)
		return
	stop_emote()
	# Voiture du trafic partagé (en ligne) : elle devient une voiture locale, volée
	if v.has_meta("net_id"):
		v.get_meta("net_owner").convert(v)
	if v.vehicle_type == "army":
		GameState.add_wanted(3, "Tu voles une jeep de l'armée ! Les militaires sont à tes trousses.")
	elif v.vehicle_type == "police" and GameState.rp_job == "police":
		pass # policier en service : sa voiture de patrouille
	elif v.vehicle_type == "police":
		GameState.add_wanted(2, "Tu voles une voiture de police ! Toute la ville te recherche.")
	elif v.vehicle_type == "charette":
		GameState.notify.emit("« Allez, avance ! » Tu prends les rênes de la charrette.")
	elif v.ai_enabled or v.route_active:
		GameState.add_wanted(1, "« Ndeysaan, sama oto bi ! » Le chauffeur s'enfuit et appelle la police...")
	v.route_active = false
	v.hold = false
	v.set_physics_process(true)
	v.visible = true
	current_vehicle = v
	v.set_driver(self)
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_target(v)
	if v.vehicle_type in ["jakarta", "grosse_moto"]:
		GameState.notify.emit("Tu es sur la %s ! Accélère." % v.display_name)
	elif not (v.vehicle_type in ["police", "army"]):
		GameState.notify.emit("Tu es au volant du %s." % v.display_name)


## Monter comme passager : le véhicule continue de rouler tout seul.
func ride(v) -> void:
	stop_emote()
	riding = v
	visible = false
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	if camera_rig:
		camera_rig.set_target(v)
	if v.vehicle_type == "taxi":
		GameState.notify.emit("Tu es assis dans le taxi. Le taximan met la radio et démarre.")
	elif v.vehicle_type in ["car_rapide", "ndiaga"]:
		GameState.notify.emit("Tu es installé dans le transport. [E] pour demander l'arrêt.")
	elif v.line_name != "":
		GameState.notify.emit("Tu es à bord du bus %s. [E] pour descendre au prochain arrêt." % v.line_name)


## Descendre côté trottoir (à droite du véhicule).
func end_ride() -> void:
	var v = riding
	riding = null
	collision_layer = 4
	collision_mask = 1 | 2 | 16 | 32
	visible = true
	if camera_rig:
		camera_rig.set_target(self)
	if v == null or not is_instance_valid(v):
		return
	var side: Vector3 = v.global_transform.basis.x
	var base: Vector3 = v.global_position
	var exit_pos: Vector3 = base + side * (v.size.x * 0.5 + 0.9)
	if _blocked(base + Vector3.UP, exit_pos + Vector3.UP):
		exit_pos = base - side * (v.size.x * 0.5 + 0.9)
	global_position = exit_pos + Vector3(0, 0.1, 0)
	model.rotation.y = v.rotation.y


## Quitte n'importe quel véhicule (arrestation, évanouissement).
func leave_any_vehicle() -> void:
	if current_vehicle:
		exit_vehicle()
	if riding and transit:
		transit.cancel_ride()
	elif riding:
		end_ride()


func exit_vehicle() -> void:
	var v = current_vehicle
	if v == null:
		return
	var side: Vector3 = v.global_transform.basis.x
	var base: Vector3 = v.global_position
	var offset: float = v.size.x * 0.5 + 0.8
	var exit_pos := base - side * offset
	if _blocked(base + Vector3.UP, exit_pos + Vector3.UP):
		exit_pos = base + side * offset
	if _blocked(base + Vector3.UP, exit_pos + Vector3.UP):
		exit_pos = base + Vector3(0, v.size.y + 0.8, 0)
	v.set_driver(null)
	current_vehicle = null
	collision_layer = 4
	collision_mask = 1 | 2 | 16 | 32
	global_position = exit_pos + Vector3(0, 0.1, 0)
	model.rotation.y = v.rotation.y
	visible = true
	if camera_rig:
		camera_rig.set_target(self)


func _blocked(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _nearest_vehicle(extra_range: float = 0.0) -> Variant:
	var best = null
	var best_d := INF
	var pp: Vector3 = global_position
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not is_instance_valid(v) or v == current_vehicle:
			continue
		var vp: Vector3 = v.global_position
		# Tolérance verticale (dénivelé, trottoir, bord de route)
		if absf(pp.y - vp.y) > 3.2:
			continue
		var d_horiz := Vector2(pp.x - vp.x, pp.z - vp.z).length()
		# Portée étendue : motos et voitures très faciles à attraper et monter
		var base_reach: float = 5.0 if v.vehicle_type in ["jakarta", "grosse_moto"] else maxf(v.size.z * 0.5 + 3.0, 5.2)
		var reach: float = base_reach + extra_range
		if d_horiz < reach and d_horiz < best_d:
			best = v
			best_d = d_horiz
	return best


func _nearest_ped() -> Variant:
	for p in get_tree().get_nodes_in_group("pedestrians"):
		if p.visible and not p.knocked and global_position.distance_to(p.global_position) < 2.2:
			return p
	return null


## Rapatrie le joueur (et sa voiture s'il en conduit une) au point de départ initial (Place de l'Indépendance)
func return_to_start(city_ref = null) -> void:
	if current_vehicle and is_instance_valid(current_vehicle):
		current_vehicle.return_to_start(city_ref)
		return
	var c = city_ref if city_ref else (get_parent().get("city") if get_parent() else null)
	var dest: Vector3 = c.spawn_point if (c != null and c.get("spawn_point") != null) else Vector3(0, 0.5, 0)
	global_position = dest
	velocity = Vector3.ZERO
	if camera_rig and is_instance_valid(camera_rig):
		camera_rig.global_position = dest + Vector3(0, 1.6, 0)
	Audio.play_sfx("horn", -10.0)
	GameState.notify.emit("📍 Retour réussi au point de départ (Place de l'Indépendance) !")

