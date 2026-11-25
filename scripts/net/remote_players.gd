extends Node3D
## Les autres joueurs en ligne : leur personnage (ou leur véhicule s'ils conduisent), avec leur pseudo.
## Envoie aussi l'état du joueur local au serveur 10 fois par seconde.

const RealCharacter = preload("res://scripts/util/real_character.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const Mk = preload("res://scripts/util/mk.gd")

var main
var _avatars := {} ## id → {model, label, vehicle, vtype, avatar}
var _send_t := 0.0


func _ready() -> void:
	Net.emotes.emote.connect(set_emote)


func _process(delta: float) -> void:
	if not Net.online:
		for id in _avatars.keys():
			_remove(id)
		return
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = Net.SEND_RATE
		Net.send_state(_local_state())
	for id in Net.remote:
		_update(id, Net.remote[id], delta)
	for id in _avatars.keys():
		if not Net.remote.has(id):
			_remove(id)


func _local_state() -> Dictionary:
	var p = main.player
	var pos: Vector3 = p.get_world_position()
	var carrier = p.current_vehicle if p.current_vehicle else p.riding
	var spd := 0.0
	if carrier:
		spd = absf(carrier.speed)
	else:
		spd = Vector2(p.velocity.x, p.velocity.z).length()
	return {
		"x": snappedf(pos.x, 0.01), "y": snappedf(pos.y, 0.01), "z": snappedf(pos.z, 0.01),
		"r": snappedf(carrier.rotation.y if carrier else p.model.rotation.y, 0.01),
		"sp": snappedf(spd, 0.1),
		"v": p.current_vehicle.vehicle_type if p.current_vehicle else "",
		"w": 1 if p.riding else 0,
		"wl": GameState.wanted,
		"job": GameState.rp_job,
		"pol": _chasers(pos),
	}


## Policiers qui poursuivent le joueur local : les autres joueurs les voient aussi.
func _chasers(pos: Vector3) -> Array:
	var out: Array = []
	if main.police == null or GameState.wanted == 0:
		return out
	for u in main.police.units:
		if out.size() >= 6:
			break
		if is_instance_valid(u) and u.chasing and u.global_position.distance_to(pos) < 200.0:
			out.append([u.vehicle_type, snappedf(u.global_position.x, 0.01), snappedf(u.global_position.z, 0.01), snappedf(u.rotation.y, 0.01)])
	return out


func _update(id: int, info: Dictionary, delta: float) -> void:
	var st: Dictionary = info["state"]
	var want: String = model_override.get(id, info["avatar"])
	if not _avatars.has(id) or _avatars[id]["avatar"] != want:
		if _avatars.has(id):
			_remove(id)
		var holder := Node3D.new()
		add_child(holder)
		var model = RealCharacter.create(holder, want if (want in Net.AVATARS or want in RealCharacter.FOOTBALLERS) else "heros", -1)
		var label := Mk.label(holder, info["pseudo"], Vector3(0, 2.1, 0), Mk.NAME_SIZE, Color("7cfc9a"))
		label.no_depth_test = true
		holder.global_position = Vector3(st["x"], st["y"], st["z"])
		_avatars[id] = {"holder": holder, "model": model, "label": label, "vehicle": null, "vtype": "", "avatar": want, "cops": [], "pseudo": info["pseudo"], "job": "", "wl": 0}
	var a: Dictionary = _avatars[id]
	a["model"].set_outfit(outfit_override.get(id, info.get("tenue", ""))) # ne fait rien si elle n'a pas changé
	var target := Vector3(st["x"], st["y"], st["z"])
	var yaw: float = st["r"]
	var sp: float = float(st.get("sp", 0.0))
	var vtype: String = st.get("v", "")

	# Dead reckoning / Anticipation prédictive : compense la latence mobile pour une fluidité 60/120 FPS
	var forward := -Vector3(sin(yaw), 0, cos(yaw)) * sp
	var predicted := target + forward * 0.075 if sp > 0.3 else target

	# Véhicule conduit par ce joueur : un véhicule « fantôme » sans physique
	if vtype != a["vtype"]:
		if a["vehicle"] != null:
			a["vehicle"].queue_free()
			a["vehicle"] = null
		if vtype != "":
			var v = Vehicle.new()
			v.vehicle_type = vtype
			add_child(v)
			v.remove_from_group("vehicles")
			v.set_physics_process(false)
			v.collision_layer = 0
			v.collision_mask = 0
			v.global_position = target
			v.rotation.y = yaw
			a["vehicle"] = v
		a["vtype"] = vtype
	var holder: Node3D = a["holder"]
	var k := 1.0 - exp(-12.0 * delta)
	var wl: int = int(st.get("wl", 0))
	var job: String = st.get("job", "")
	a["job"] = job
	a["wl"] = wl
	var grp: String = Net.social.tags.get(id, "")
	var talk := ""
	if Time.get_ticks_msec() < int(a.get("talk_until", 0)):
		talk = "\n📻 EN DIRECT (radio)" if a.get("talk_channel", "") == "group" else "\n🎙️ EN DIRECT (voix)"
	a["label"].text = a["pseudo"] + (("\n« %s »" % grp) if grp != "" else "") + ("\n" + Net.JOBS[job] if Net.JOBS.has(job) else "") + ("\nRECHERCHÉ " + "*".repeat(wl) if wl > 0 else "") + talk
	a["label"].modulate = Color("ff5a4a") if wl > 0 else Color("7cfc9a")
	_update_cops(a, st.get("pol", []), k)
	if a["vehicle"] != null:
		var v: Node3D = a["vehicle"]
		if v.global_position.distance_to(target) > 16.0:
			v.global_position = target
		else:
			v.global_position = v.global_position.lerp(predicted, k)
		v.rotation.y = lerp_angle(v.rotation.y, yaw, k)
		v.speed = sp
		holder.visible = true
		a["model"].visible = false
		holder.global_position = v.global_position + Vector3(0, 1.4, 0)
	else:
		a["model"].visible = int(st.get("w", 0)) == 0
		if holder.global_position.distance_to(target) > 16.0:
			holder.global_position = target
		else:
			holder.global_position = holder.global_position.lerp(predicted, k)
		a["model"].rotation.y = lerp_angle(a["model"].rotation.y, yaw, k)
		# Animation imposée (duel de lutte...) : elle passe avant la marche
		if Time.get_ticks_msec() > int(a.get("clip_until", 0)):
			# le geste reste jusqu'à ce que son joueur l'arrête (il envoie "" en bougeant)
			if a.get("emote", "") != "" and sp <= 0.3:
				a["model"].play_clip(a["emote"], 0.25)
			else:
				a["model"].locomote(sp)


## Voitures de police qui poursuivent ce joueur (fantômes, sirène allumée)
func _update_cops(a: Dictionary, list: Array, k: float) -> void:
	var cops: Array = a["cops"]
	while cops.size() > list.size():
		cops.pop_back().queue_free()
	for i in list.size():
		var e: Array = list[i]
		var target := Vector3(e[1], 0.2, e[2])
		if i >= cops.size() or cops[i].vehicle_type != e[0]:
			if i < cops.size():
				cops[i].queue_free()
			var v = Vehicle.new()
			v.vehicle_type = e[0]
			add_child(v)
			v.remove_from_group("vehicles")
			v.set_physics_process(false)
			v.collision_layer = 0
			v.collision_mask = 0
			v.chasing = true
			v.global_position = target
			v.rotation.y = e[3]
			if i < cops.size():
				cops[i] = v
			else:
				cops.append(v)
		var c: Node3D = cops[i]
		c.global_position = c.global_position.lerp(target, k)
		c.rotation.y = lerp_angle(c.rotation.y, e[3], k)


func _remove(id: int) -> void:
	var a: Dictionary = _avatars[id]
	for c in a["cops"]:
		c.queue_free()
	if a["vehicle"] != null:
		a["vehicle"].queue_free()
	a["holder"].queue_free()
	_avatars.erase(id)


## Autre joueur le plus proche : {id, pseudo, vehicle (fantôme ou null), pos}
func nearest(pos: Vector3, max_dist: float) -> Variant:
	var best = null
	var bd := max_dist
	for id in _avatars:
		var a: Dictionary = _avatars[id]
		var p: Vector3 = a["vehicle"].global_position if a["vehicle"] != null else a["holder"].global_position
		var d := p.distance_to(pos)
		if d < bd:
			bd = d
			best = {"id": id, "pseudo": a["pseudo"], "vehicle": a["vehicle"], "pos": p, "job": a["job"], "wl": a["wl"]}
	return best


## Nœud de l'avatar (pour y attacher sa voix)
## Tenue imposée à un joueur (maillot de son équipe pendant un match de mini-foot) : id → code de tenue
var outfit_override := {}
## Personnage imposé (footballeur pendant un match) : id → modèle
var model_override := {}


func avatar_of(id: int) -> String:
	return _avatars[id]["avatar"] if _avatars.has(id) else ""


func holder_of(id: int) -> Node3D:
	return _avatars[id]["holder"] if _avatars.has(id) else null


## Ce joueur est en train de parler (affiché sous son pseudo)
func set_talking(id: int, channel: String) -> void:
	if _avatars.has(id):
		_avatars[id]["talk_until"] = Time.get_ticks_msec() + 600
		_avatars[id]["talk_channel"] = channel


## Bulle de discussion au-dessus d'un autre joueur
func show_bubble(id: int, text: String) -> void:
	if not _avatars.has(id):
		return
	var a: Dictionary = _avatars[id]
	if a.get("bubble") != null and is_instance_valid(a["bubble"]):
		a["bubble"].queue_free()
	a["bubble"] = load("res://scripts/net/social_ui.gd")._make_bubble(a["holder"], text, 2.9)


## Geste d'un autre joueur (menu GESTES) : joué jusqu'à ce qu'il bouge ou l'arrête
func set_emote(id: int, clip: String) -> void:
	if _avatars.has(id):
		_avatars[id]["emote"] = clip


## Joue une animation sur l'avatar d'un autre joueur (coup, chute...), pendant ~1,5 s
func play_remote(id: int, clip: String, ms := 0) -> void:
	if not _avatars.has(id):
		return
	var a: Dictionary = _avatars[id]
	a["model"].play_clip(clip, 0.1)
	a["clip_until"] = Time.get_ticks_msec() + (ms if ms > 0 else (3000 if clip in ["fall", "dance"] else 1500))


func model_of(id: int) -> Node3D:
	return _avatars[id]["model"] if _avatars.has(id) else null


## Joueur recherché le plus proche (pour les policiers en service)
func nearest_wanted(pos: Vector3) -> Variant:
	var best = null
	var bd := INF
	for id in _avatars:
		var a: Dictionary = _avatars[id]
		if a["wl"] <= 0:
			continue
		var p: Vector3 = a["vehicle"].global_position if a["vehicle"] != null else a["holder"].global_position
		if p.distance_to(pos) < bd:
			bd = p.distance_to(pos)
			best = {"id": id, "pseudo": a["pseudo"], "pos": p, "wl": a["wl"]}
	return best


func count() -> int:
	return _avatars.size()
