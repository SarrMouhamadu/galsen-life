extends Node
## Police et armée : étoiles de recherche, poursuites dans les rues, « semer » la police, arrestation.
##
## - Chaque étoile ajoute une voiture de police à la poursuite (jusqu'à 6), les renforts arrivent hors de vue.
## - À partir de 4 étoiles, l'armée s'en mêle : jeeps militaires et soldats à pied (5 étoiles : encore plus).
## - Rester hors de vue (loin, ou caché derrière les bâtiments) pendant LOSE_TIME fait perdre une étoile.
## - Rester arrêté près d'une voiture pendant BUST_TIME, ou se faire rattraper à pied par un soldat : arrestation.
## - La caserne est une zone militaire interdite, gardée par des soldats.
## Personne ne tire : c'est un jeu de rôle, pas un jeu de guerre.

const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const Soldier = preload("res://scripts/police/soldier.gd")

const SEE_DISTANCE := 70.0
const LOSE_TIME := 12.0
const BUST_DISTANCE := 6.5
const BUST_TIME := 2.0
const FINE_PER_STAR := 1000
const ARMY_STARS := 4

var main
var city
var player
var jobs
var units: Array = []
var soldiers: Array = [] ## soldats lancés à la poursuite
var guards: Array = []
var status := ""
var bust_progress := 0.0
var _lose_t := 0.0
var _bust_t := 0.0
var _spawn_cd := 0.0
var _soldier_cd := 0.0
var _trespass_cd := 0.0
var _base_center := Vector3.ZERO
var _has_base := false
var _trespass_r := 10.0 ## distance au centre en deçà de laquelle on a passé l'entrée


func register(v) -> void:
	units.append(v)


func _ready() -> void:
	# Gardes à l'entrée de la caserne
	if city.places.has("Caserne"):
		var info: Array = city.place_info["Caserne"]
		var curb: Vector3 = city.places["Caserne"]
		var n := Vector3(info[3], 0, info[4])
		var f := Vector3(info[7], 0, info[8])
		_base_center = Vector3(info[9], 0, info[10])
		_has_base = true
		_trespass_r = maxf(6.0, _flat(_base_center, curb) - 4.0)
		for side in [-1, 1]:
			var g = Soldier.new()
			main.add_child(g)
			g.setup(city, player, curb + n * 2.0 + f * (side * 3.2), true)
			guards.append(g)


func _player_speed() -> float:
	var veh = player.current_vehicle if player.current_vehicle else player.riding
	return absf(veh.speed) if veh else 0.0


func _physics_process(delta: float) -> void:
	units = units.filter(func(u): return is_instance_valid(u))
	soldiers = soldiers.filter(func(s): return is_instance_valid(s))
	var ppos: Vector3 = player.get_world_position()
	_check_base(delta, ppos)
	if GameState.wanted == 0:
		status = ""
		_lose_t = 0.0
		_bust_t = 0.0
		bust_progress = 0.0
		_stand_down(ppos)
		return

	var active: Array = units.filter(func(u): return u.driver == null)
	var want_police := mini(GameState.wanted + 1, 6)
	var want_army := 0 if GameState.wanted < ARMY_STARS else (2 if GameState.wanted == ARMY_STARS else 3)
	var n_army := active.filter(func(u): return u.vehicle_type == "army").size()
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		if n_army < want_army:
			active.append(_spawn(ppos, "army"))
			_spawn_cd = 2.0
			if n_army == 0:
				GameState.notify.emit("L'armée est déployée ! Des jeeps et des soldats te recherchent.")
		elif active.size() - n_army < want_police:
			active.append(_spawn(ppos, "police"))
			_spawn_cd = 2.0
	_update_soldiers(delta, ppos)

	var d_min := INF
	var seen := false
	for u in active:
		u.chasing = true
		u.ai_enabled = false
		var up: Vector3 = u.global_position
		var d := _flat(up, ppos)
		u.chase_point = _waypoint(u, up, ppos, delta)
		u.chase_player_dist = d
		d_min = minf(d_min, d)
		if d < SEE_DISTANCE and (d < 20.0 or _line_of_sight(up, ppos)):
			seen = true
	for s in soldiers:
		if s.player_distance() < 40.0:
			seen = true

	if seen:
		_lose_t = 0.0
	else:
		_lose_t += delta
		if _lose_t >= LOSE_TIME:
			_lose_t = 0.0
			GameState.lose_star()
			GameState.notify.emit("Tu les as semés... une étoile en moins." if GameState.wanted > 0 else "La police a perdu ta trace. Tranquille !")

	if d_min < BUST_DISTANCE and _player_speed() < 2.5:
		_bust_t += delta
	else:
		_bust_t = maxf(0.0, _bust_t - delta * 0.5)
	bust_progress = clampf(_bust_t / BUST_TIME, 0.0, 1.0)
	var army_txt := " L'armée est là !" if GameState.wanted >= ARMY_STARS else ""
	if _bust_t > 0.15:
		status = "ARRESTATION... %d %%  — Bouge vite !" % int(bust_progress * 100.0)
	elif seen:
		status = "On te poursuit !%s Sème-les : éloigne-toi ou cache-toi derrière les bâtiments." % army_txt
	else:
		status = "Hors de vue... encore %d s pour perdre une étoile" % ceili(LOSE_TIME - _lose_t)
	if _bust_t >= BUST_TIME:
		_bust(false)
		return
	# Un soldat qui rattrape le joueur à pied l'arrête aussitôt
	if player.current_vehicle == null and player.riding == null:
		for s in soldiers:
			if s.player_distance() < 1.8:
				_bust(true)
				return


## Soldats à pied (4 étoiles et plus)
func _update_soldiers(delta: float, ppos: Vector3) -> void:
	var want := 0 if GameState.wanted < ARMY_STARS else (3 if GameState.wanted == ARMY_STARS else 5)
	_soldier_cd -= delta
	if soldiers.size() < want and _soldier_cd <= 0.0:
		_soldier_cd = 1.5
		var node: int = city.random_node_around(ppos, 40.0, 80.0, "walk")
		var s = Soldier.new()
		main.add_child(s)
		s.setup(city, player, city.node_pos[node] + Vector3(0, 0.07, 0))
		if randf() < 0.5:
			s.say("Halte ! Armée sénégalaise !")
		soldiers.append(s)
	# Les soldats trop loin sont rappelés
	for s in soldiers.duplicate():
		if s.player_distance() > 160.0:
			soldiers.erase(s)
			s.queue_free()


## Zone militaire : la caserne est interdite.
func _check_base(delta: float, ppos: Vector3) -> void:
	if not _has_base:
		return
	_trespass_cd -= delta
	var d := _flat(ppos, _base_center)
	if d < 18.0:
		for g in guards:
			if g.player_distance() < 15.0 and randf() < 0.01:
				g.say("Halte ! Zone militaire !")
	if d < _trespass_r and _trespass_cd <= 0.0:
		_trespass_cd = 25.0
		GameState.add_wanted(2, "Zone militaire interdite ! Les soldats te prennent en chasse.")
		for g in guards:
			g.say("Halte ! Arrêtez-le !")


## Fin de poursuite : les patrouilles retournent sur leur circuit, les renforts repartent.
## On attend qu'ils soient loin du joueur pour ne pas les voir disparaître.
func _stand_down(ppos: Vector3) -> void:
	for u in units.duplicate():
		if u.driver != null or u.ai_enabled:
			continue
		u.chasing = false
		if _flat(u.global_position, ppos) < 80.0:
			continue
		if not u.is_patrol:
			units.erase(u)
			u.queue_free()
		else:
			u.resume_patrol(ppos)
	for s in soldiers.duplicate():
		if s.player_distance() > 50.0:
			soldiers.erase(s)
			s.queue_free()


func reset_all() -> void:
	var ppos: Vector3 = player.get_world_position()
	_bust_t = 0.0
	_lose_t = 0.0
	bust_progress = 0.0
	status = ""
	for u in units.duplicate():
		if u.driver != null:
			continue
		if not u.is_patrol:
			units.erase(u)
			u.queue_free()
		else:
			u.resume_patrol(ppos)
	for s in soldiers:
		s.queue_free()
	soldiers.clear()


func _bust(by_army: bool) -> void:
	var stars: int = GameState.wanted
	player.leave_any_vehicle()
	jobs.cancel()
	player.global_position = city.places["Commissariat"]
	GameState.clear_wanted()
	reset_all()
	Audio.play_sfx("busted", -2.0)
	GameState.fine(FINE_PER_STAR * stars, ("Arrêté par l'armée !" if by_army else "Arrêté par la police !") + " Amende")
	GameState.notify.emit("« Dafa doy ! » (ça suffit !) Direction la cellule du commissariat.")
	if main.dealership:
		main.dealership.impound()
	if main.rental:
		main.rental.on_arrest()
	if main.prison:
		main.prison.lock_up(stars)


## Arrêté par un joueur policier (mode en ligne)
func arrested_by(cop: String) -> void:
	var stars: int = maxi(GameState.wanted, 1)
	player.leave_any_vehicle()
	jobs.cancel()
	player.global_position = city.places["Commissariat"]
	GameState.clear_wanted()
	reset_all()
	Audio.play_sfx("busted", -2.0)
	GameState.fine(FINE_PER_STAR * stars, "Arrêté par l'agent %s ! Amende" % cop)
	GameState.notify.emit("L'agent %s t'a passé les menottes. Direction la cellule." % cop)
	if main.dealership:
		main.dealership.impound()
	if main.rental:
		main.rental.on_arrest()
	if main.prison:
		main.prison.lock_up(stars)


func _spawn(ppos: Vector3, type := "police") -> Variant:
	var v = Vehicle.new()
	v.vehicle_type = type
	main.add_child(v)
	v.respawn_in_traffic(city, ppos, 100.0, 170.0)
	v.ai_enabled = false
	units.append(v)
	return v


## Prochain point de passage : on suit l'itinéraire dans les rues (A*), recalculé régulièrement ;
## tout près, on fonce droit sur le joueur.
func _waypoint(u, p: Vector3, q: Vector3, delta: float) -> Vector3:
	if _flat(p, q) < 30.0:
		return q
	var t: float = u.get_meta("route_t", 0.0) - delta
	var path: PackedVector3Array = u.get_meta("route", PackedVector3Array())
	if t <= 0.0 or path.size() < 2:
		path = city.route(p, q)
		t = 0.7
		u.set_meta("route", path)
	u.set_meta("route_t", t)
	if path.size() < 2:
		return q
	# Premier point de l'itinéraire encore devant la voiture (à plus de 6 m)
	for i in range(1, path.size()):
		if _flat(path[i], p) > 6.0:
			return path[i]
	return q


func _line_of_sight(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.5, 0), b + Vector3(0, 1.5, 0), 1)
	return main.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
