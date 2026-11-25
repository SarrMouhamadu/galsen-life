extends Node3D
## Affichage des activités à plusieurs (mode en ligne) : bulles de discussion, groupes (Mbokk),
## courses de voitures (points de passage, compte à rebours, classement) et duels de lutte.
## La logique et les vérifications sont sur le serveur (scripts/net/social.gd).

const Mk = preload("res://scripts/util/mk.gd")
const CP_RANGE := 14.0
const BUBBLE_TIME := 6.0

var main
var status := ""
var group_pos := {} ## id → Vector3 (membres de mon groupe, même loin)
var open_races := {} ## id → {host, dest, fee, pos, t}
var race_id := -1 ## course où je suis inscrit
var race_names: Array = []
var race_host := -1
var _race_cps := PackedVector3Array()
var _race_idx := 0
var _race_t := 0.0
var _race_running := false
var _race_fee := 0
var _beam: Node3D
var _beam_mesh: MeshInstance3D
var duel_with := -1
var duel_name := ""
var _duel_score := [0, 0]
var _duel_deadline := 0.0
var _bubble_self: Label3D


func _ready() -> void:
	var s = Net.social
	Net.bubble.connect(_on_bubble)
	s.group_invited.connect(_on_group_invited)
	s.group_positions.connect(_on_group_positions)
	s.group_changed.connect(func(n, _m, _c):
		if n == "":
			group_pos.clear())
	s.race_open.connect(_on_race_open)
	s.race_lobby.connect(_on_race_lobby)
	s.race_go.connect(_on_race_go)
	s.race_progress.connect(_on_race_progress)
	s.race_result.connect(_on_race_result)
	s.duel_invited.connect(_on_duel_invited)
	s.duel_start.connect(_on_duel_start)
	s.duel_round.connect(_on_duel_round)
	s.duel_outcome.connect(_on_duel_outcome)
	s.duel_end.connect(_on_duel_end)
	# Balise du prochain point de passage
	_beam = Node3D.new()
	add_child(_beam)
	_beam_mesh = Mk.cyl(_beam, 4.0, 4.0, 40.0, Vector3(0, 20, 0), Color(1.0, 0.45, 0.1, 0.35), false, 16)
	_beam_mesh.material_override = Mk.mat(Color(1.0, 0.45, 0.1, 0.35), 0.0, true)
	_beam.visible = false


# --- Bulles de discussion ------------------------------------------------------------

func _on_bubble(sender: int, text: String) -> void:
	if not Net.online or (multiplayer.has_multiplayer_peer() and sender == multiplayer.get_unique_id()):
		if _bubble_self != null and is_instance_valid(_bubble_self):
			_bubble_self.queue_free()
		_bubble_self = _make_bubble(main.player, text, 2.5)
	elif main and main.remote_players:
		main.remote_players.show_bubble(sender, text)


static func _make_bubble(parent: Node3D, text: String, height: float) -> Label3D:
	var l := Mk.label(parent, "💬 " + text.left(80), Vector3(0, height, 0), Mk.NAME_SIZE + 6, Color.WHITE)
	l.no_depth_test = true
	l.outline_size = 12
	l.outline_modulate = Color(0.04, 0.08, 0.12, 0.95)
	l.width = 600.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tw := l.create_tween()
	tw.tween_interval(BUBBLE_TIME)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	return l


# --- Groupes --------------------------------------------------------------------------

func _on_group_invited(name: String, from: String) -> void:
	main.hud.show_choices("%s t'invite dans son groupe « %s »" % [from, name], [
		["Rejoindre le groupe", func(): Net.social.rpc_group_accept.rpc_id(1, name)],
		["Refuser", func(): pass]], func(): pass)


func _on_group_positions(data: PackedFloat64Array) -> void:
	group_pos.clear()
	var me := multiplayer.get_unique_id()
	for k in range(0, data.size() - 2, 3):
		var id := int(data[k])
		if id != me:
			group_pos[id] = Vector3(data[k + 1], 0, data[k + 2])


# --- Courses ----------------------------------------------------------------------------

func create_race(dest: String, fee: int) -> void:
	if main.player.current_vehicle == null:
		GameState.notify.emit("Il faut être au volant pour ouvrir une course.")
		return
	if GameState.money < fee:
		GameState.notify.emit("Il te faut %s pour miser." % GameState.fcfa(fee))
		return
	_race_fee = fee
	Net.social.rpc_race_create.rpc_id(1, dest, fee)


func join_race(rid: int) -> void:
	var r: Dictionary = open_races.get(rid, {})
	if r.is_empty():
		return
	if GameState.money < int(r["fee"]):
		GameState.notify.emit("Il te faut %s pour la mise." % GameState.fcfa(r["fee"]))
		return
	_race_fee = r["fee"]
	Net.social.rpc_race_join.rpc_id(1, rid)


func _on_race_open(rid: int, host: String, dest: String, fee: int, pos: Vector3) -> void:
	open_races[rid] = {"host": host, "dest": dest, "fee": fee, "pos": pos, "t": Time.get_ticks_msec()}
	if host != Net.pseudo:
		GameState.notify.emit("COURSE : %s part vers %s (mise %s). Téléphone → Défis pour t'inscrire !" % [host, dest, GameState.fcfa(fee)])


func _on_race_lobby(rid: int, names: Array, host_id: int) -> void:
	race_id = rid
	race_names = names
	race_host = host_id
	status = "COURSE — inscrits : %s%s" % [", ".join(names), " — téléphone → Défis pour lancer" if host_id == multiplayer.get_unique_id() else " — en attente du départ"]


func _on_race_go(rid: int, cps: PackedVector3Array, delay: float) -> void:
	race_id = rid
	_race_cps = cps
	_race_idx = 0
	_race_t = -delay
	_race_running = true
	open_races.erase(rid)
	if _race_fee > 0:
		GameState.spend(_race_fee)
	GameState.waypoint = cps[cps.size() - 1]
	for k in int(delay):
		get_tree().create_timer(float(k)).timeout.connect(func(): GameState.notify.emit("Départ dans %d..." % (int(delay) - k)))
	get_tree().create_timer(delay).timeout.connect(func():
		GameState.notify.emit("PARTEZ ! Dem, dem !")
		Audio.play_sfx("horn", -4.0))


func _on_race_progress(_rid: int, who: String, place: int, time: float) -> void:
	GameState.notify.emit("%s arrive %s en %s" % [who, "1er" if place == 1 else "%de" % place, _fmt(time)])


func _on_race_result(_rid: int, ranking: Array) -> void:
	_race_running = false
	race_id = -1
	race_names = []
	_beam.visible = false
	status = ""
	var lines: Array = []
	for k in ranking.size():
		lines.append("%d. %s — %s" % [k + 1, ranking[k][0], _fmt(ranking[k][1])])
	if lines.is_empty():
		lines.append("Personne n'a fini la course.")
	main.hud.show_choices("Résultats de la course\n" + "\n".join(lines), [["OK", func(): pass]], func(): pass)


static func _fmt(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


# --- Duels de lutte ---------------------------------------------------------------------

func challenge(target: int, stake: int) -> void:
	if GameState.money < stake:
		GameState.notify.emit("Il te faut %s pour cette mise." % GameState.fcfa(stake))
		return
	Net.social.rpc_duel_challenge.rpc_id(1, target, stake)


func _on_duel_invited(from_id: int, from_name: String, stake: int) -> void:
	main.hud.show_choices("%s te défie à la lutte ! Mise : %s chacun" % [from_name, GameState.fcfa(stake)], [
		["Accepter le combat", func():
			if GameState.money < stake:
				GameState.notify.emit("Tu n'as pas de quoi miser %s." % GameState.fcfa(stake))
			else:
				Net.social.rpc_duel_accept.rpc_id(1, from_id)],
		["Refuser", func(): pass]], func(): pass)


func _on_duel_start(opponent: int, opponent_name: String, stake: int) -> void:
	duel_with = opponent
	duel_name = opponent_name
	_duel_score = [0, 0]
	if stake > 0:
		GameState.spend(stake)
	var p = main.player
	if p.current_vehicle:
		p.exit_vehicle()
	p.frozen = true
	_face_opponent()
	status = "LUTTE contre %s — 0 / 0 (premier à 3)" % opponent_name
	GameState.notify.emit("Mbapatt contre %s ! Charger bat crocheter, crocheter bat esquiver, esquiver bat charger." % opponent_name)


func _face_opponent() -> void:
	if not Net.remote.has(duel_with):
		return
	var st: Dictionary = Net.remote[duel_with]["state"]
	var d: Vector3 = Vector3(st["x"], 0, st["z"]) - main.player.global_position
	main.player.model.rotation.y = atan2(-d.x, -d.z)


func _on_duel_round(round_no: int, seconds: float) -> void:
	_duel_deadline = seconds
	_face_opponent()
	var labels := {"charger": "Charger (foncer sur lui)", "esquiver": "Esquiver (se dégager)", "crocheter": "Crocheter (le faire tomber)"}
	var choices: Array = []
	for c in ["charger", "esquiver", "crocheter"]:
		var ch: String = c
		choices.append([labels[ch], func(): Net.social.rpc_duel_choice.rpc_id(1, ch)])
	main.hud.show_choices("Manche %d contre %s — %d s pour choisir" % [round_no, duel_name, int(seconds)], choices, func(): pass)


func _on_duel_outcome(mine: String, theirs: String, won: int, my_score: int, their_score: int) -> void:
	main.hud.close_choices()
	_duel_score = [my_score, their_score]
	var me = main.player.model
	var verbs := {"charger": "charges", "esquiver": "esquives", "crocheter": "croches"}
	var verbs3 := {"charger": "charge", "esquiver": "esquive", "crocheter": "croche"}
	var txt := "Tu %s, %s %s : " % [verbs[mine], duel_name, verbs3[theirs]]
	if won > 0:
		txt += "point pour toi !"
		me.play_clip("punch" if mine == "charger" else "push", 0.1)
		main.remote_players.play_remote(duel_with, "hit")
	elif won < 0:
		txt += "point pour %s." % duel_name
		me.play_clip("hit", 0.1)
		main.remote_players.play_remote(duel_with, "punch" if theirs == "charger" else "push")
	else:
		txt += "égalité, personne ne tombe."
	GameState.notify.emit("%s (%d - %d)" % [txt, my_score, their_score])
	status = "LUTTE contre %s — %d / %d (premier à 3)" % [duel_name, my_score, their_score]


func _on_duel_end(won: bool, stake: int) -> void:
	main.hud.close_choices()
	main.player.frozen = false
	if won:
		main.player.model.play_clip("dance", 0.2)
		GameState.notify.emit("VICTOIRE ! %s est à terre. %s" % [duel_name, ("Tu gagnes %s." % GameState.fcfa(stake * 2)) if stake > 0 else ""])
	else:
		main.player.model.play_clip("fall", 0.1)
		GameState.notify.emit("Défaite... %s t'a mis à terre." % duel_name)
	if duel_with > 0:
		main.remote_players.play_remote(duel_with, "fall" if won else "dance")
	duel_with = -1
	status = ""


# --- Chaque image -----------------------------------------------------------------------

func _process(delta: float) -> void:
	# Courses ouvertes trop vieilles (3 min) : oubliées
	var now := Time.get_ticks_msec()
	for rid in open_races.keys():
		if now - int(open_races[rid]["t"]) > 180000:
			open_races.erase(rid)
	if not _race_running:
		return
	_race_t += delta
	if _race_idx >= _race_cps.size():
		_beam.visible = false
		status = "COURSE — arrivé ! En attente des autres (%s)" % _fmt(_race_t)
		return
	var cp: Vector3 = _race_cps[_race_idx]
	_beam.visible = true
	_beam.global_position = cp
	var pos: Vector3 = main.player.get_world_position()
	var d := Vector2(pos.x - cp.x, pos.z - cp.z).length()
	status = "COURSE — point %d/%d (%d m) — %s" % [_race_idx + 1, _race_cps.size(), int(d), _fmt(maxf(_race_t, 0.0))]
	if _race_t >= 0.0 and d < CP_RANGE:
		Net.social.rpc_race_cp.rpc_id(1, race_id, _race_idx, pos.x, pos.z)
		_race_idx += 1
		Audio.play_sfx("coin", -10.0)
		if _race_idx < _race_cps.size():
			GameState.waypoint = _race_cps[mini(_race_idx, _race_cps.size() - 1)]
