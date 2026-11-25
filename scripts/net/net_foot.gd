extends Node
## Matchs de mini-foot entre joueurs en ligne, nœud « Foot » enfant de Net (même chemin sur le serveur et
## chez les joueurs). Au complexe de mini-foot (scripts/world/foot.gd), un joueur crée un match (avec ou sans
## mise), les autres choisissent une équipe (jaunes ou rouges), le créateur lance la partie.
## Le serveur simule le ballon (scripts/world/foot_ball.gd, la même physique qu'en solo), la possession (le
## porteur garde le ballon dans les pieds), les tacles et fautes, et un gardien automatique dans chaque but ;
## les joueurs lui envoient leurs frappes (tir, passe, lob : calculées chez eux comme en solo), leurs tacles et
## leurs feintes, qu'il vérifie (possession, distance).
## Il compte les buts et le temps, puis partage la cagnotte entre les gagnants (match nul : chacun récupère sa mise).
## Un nœud à part : les versions 1.20 et avant ne le connaissent pas, le serveur ne leur envoie rien.

signal lobbies_changed(list: Array)
signal lobby_changed(data: Dictionary) ## {} : on n'est plus dans un salon
signal match_started(mid: int, pitch: int, team: int, roster: Dictionary, duration: float)
signal kickoff(team: int)
signal score_changed(score: Array, time_left: float)
signal match_ended(message: String, outcome: int) ## 1 victoire, 0 nul, -1 défaite
signal fx(id: int, clip: String) ## geste d'un autre joueur du match (frappe)

## Mesures du complexe, recopiées de scripts/world/foot.gd (le précharger ici ferait une boucle avec Net)
class Foot:
	const ORIGIN := Vector3(9000, 0, -1600)
	const ZONE_RADIUS := 150.0
	const PITCHES := [-26.0, 0.0, 26.0]
	const L := 36.0
	const W := 20.0
	const GOAL_W := 3.0
	const GOAL_H := 2.0

	static func in_zone(p: Vector3) -> bool:
		return Vector2(p.x - ORIGIN.x, p.z - ORIGIN.z).length() < ZONE_RADIUS
const MAX_TEAM := 5
const DURATION := 300.0
const STAKES := [0, 1000, 5000]
const TICK := 1.0 / 30.0
const SEND_EVERY := 1.0 / 15.0
const FootBall = preload("res://scripts/world/foot_ball.gd")
const HL := 18.0
const HW := 10.0
const PICK := 1.1 ## distance de contrôle (positions reçues 10 fois par seconde : plus large qu'en solo)
const KICK_REACH := 2.4 ## frappe d'un ballon libre (reprise), avec la latence
const TACKLE_REACH := 2.1
const ONLINE_PITCHES := [0, 2] ## le terrain du milieu reste aux matchs contre l'ordinateur

var net
## (joueur)
var lobbies: Array = [] ## [{mid, host, stake, teams [[pseudos], [pseudos]], started}]
var my_lobby := {}
var mid := -1 ## match en cours
var ball_pos := Vector3.ZERO ## repère du terrain (centre au sol)
var ball_vel := Vector3.ZERO
var ball_t := 0.0 ## heure (s) de la dernière position reçue
var carrier := -1 ## porteur : id du joueur, -2 / -3 : gardien des jaunes / des rouges, -1 : ballon libre
var keepers := [Vector3.ZERO, Vector3.ZERO] ## gardiens : (x, z, plongeon : côté ou 0) dans le repère du terrain
var _predict_until := 0.0 ## juste après une frappe : on garde la trajectoire prévue chez soi
## (serveur)
var _capable := {}
var _matches := {} ## mid → {host, stake, teams [[ids], [ids]], started, pitch, p, v, score, time, pause, cd {id: t}, last}
var _member := {} ## id → mid
var _next := 1
var _acc := 0.0
var _send_acc := 0.0


func hello() -> void:
	if net.online:
		rpc_hello.rpc_id(1)


@rpc("any_peer", "reliable")
func rpc_hello() -> void:
	if net.is_server:
		var id := multiplayer.get_remote_sender_id()
		_capable[id] = true
		rpc_lobbies.rpc_id(id, _lobby_list())


func forget(id: int, who := "") -> void:
	_capable.erase(id)
	if _member.has(id):
		_leave(id, "%s s'est déconnecté." % (who if who != "" else "Un joueur"))


# ---------------------------------------------------------------- joueur

func create(stake: int) -> void:
	if stake > 0 and not GameState.spend(stake):
		GameState.notify.emit("Il te faut %s pour la mise." % GameState.fcfa(stake))
		return
	rpc_create.rpc_id(1, stake)


func join(m: int, team: int, stake: int) -> void:
	if stake > 0 and not GameState.spend(stake):
		GameState.notify.emit("Il te faut %s pour la mise." % GameState.fcfa(stake))
		return
	rpc_join.rpc_id(1, m, team)


func switch_team(team: int) -> void:
	rpc_switch.rpc_id(1, team)


func leave() -> void:
	rpc_leave.rpc_id(1)


func start() -> void:
	rpc_launch.rpc_id(1)


## Frappe (tir, passe, lob) calculée chez le joueur avec FootBall ; le ballon part tout de suite chez lui
func strike(from: Vector3, vel: Vector3, spin: float, is_shot: bool) -> void:
	if mid < 0:
		return
	rpc_strike.rpc_id(1, vel, spin, is_shot)
	ball_pos = from
	ball_vel = vel
	ball_t = Time.get_ticks_msec() / 1000.0
	carrier = -1
	_predict_until = ball_t + 0.45


func tackle() -> void:
	if mid >= 0:
		rpc_tackle.rpc_id(1)


func skill(dir: Vector2) -> void:
	if mid >= 0:
		rpc_skill.rpc_id(1, dir.normalized())


func my_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0


## Position du ballon prévue maintenant (dernière position reçue + trajectoire)
func ball_now() -> Vector3:
	var dt := clampf(Time.get_ticks_msec() / 1000.0 - ball_t, 0.0, 0.5)
	var p := ball_pos + ball_vel * dt
	if ball_pos.y > 0.2 or ball_vel.y > 0.5:
		p.y = ball_pos.y + ball_vel.y * dt - 4.9 * dt * dt
	p.y = maxf(FootBall.R, p.y)
	p.x = clampf(p.x, -HL - FootBall.GOAL_DEPTH, HL + FootBall.GOAL_DEPTH)
	p.z = clampf(p.z, -HW + FootBall.R, HW - FootBall.R)
	return p


@rpc("authority", "reliable")
func rpc_lobbies(list: Array) -> void:
	lobbies = list
	lobbies_changed.emit(list)


@rpc("authority", "reliable")
func rpc_lobby(data: Dictionary) -> void:
	my_lobby = data
	lobby_changed.emit(data)


@rpc("authority", "reliable")
func rpc_start(m: int, pitch: int, team: int, roster: Dictionary, duration: float) -> void:
	mid = m
	ball_pos = Vector3(0, 0.11, 0)
	ball_vel = Vector3.ZERO
	ball_t = Time.get_ticks_msec() / 1000.0
	match_started.emit(m, pitch, team, roster, duration)


@rpc("authority", "unreliable_ordered")
func rpc_ball(m: int, s: PackedFloat32Array, own: int) -> void:
	if m != mid or s.size() < 12:
		return
	var now := Time.get_ticks_msec() / 1000.0
	keepers = [Vector3(s[6], s[7], s[8]), Vector3(s[9], s[10], s[11])]
	if now < _predict_until:
		return # le serveur n'a pas encore reçu notre frappe
	ball_pos = Vector3(s[0], s[1], s[2])
	ball_vel = Vector3(s[3], s[4], s[5])
	ball_t = now
	carrier = own


@rpc("authority", "unreliable")
func rpc_fx(m: int, id: int, clip: String) -> void:
	if m == mid:
		fx.emit(id, clip)


@rpc("authority", "reliable")
func rpc_kickoff(m: int, team: int) -> void:
	if m == mid:
		carrier = -1
		_predict_until = 0.0
		ball_pos = Vector3(0, 0.11, 0)
		ball_vel = Vector3.ZERO
		ball_t = Time.get_ticks_msec() / 1000.0
		kickoff.emit(team)


@rpc("authority", "reliable")
func rpc_score(m: int, s0: int, s1: int, left: float) -> void:
	if m == mid:
		score_changed.emit([s0, s1], left)


@rpc("authority", "reliable")
func rpc_end(m: int, message: String, outcome: int) -> void:
	if m == mid:
		mid = -1
		my_lobby = {}
		match_ended.emit(message, outcome)


# ---------------------------------------------------------------- serveur

func _in_complex(id: int) -> bool:
	return net._pos.has(id) and Foot.in_zone(net._pos[id])


func _pay(id: int, amount: int, reason: String) -> void:
	if amount > 0 and net._sessions.has(id):
		net.rpc_receive_money.rpc_id(id, "Serveur", amount, reason)


func _lobby_list() -> Array:
	var out: Array = []
	for m in _matches:
		var t: Dictionary = _matches[m]
		out.append({"mid": m, "host": net._sessions.get(t["host"], "?"), "stake": t["stake"], "teams": _names(t), "started": t["started"]})
	return out


func _names(t: Dictionary) -> Array:
	var out := [[], []]
	for k in 2:
		for id in t["teams"][k]:
			out[k].append(net._sessions.get(id, "?"))
	return out


func _broadcast_lobbies() -> void:
	var list := _lobby_list()
	for id in _capable:
		if net._sessions.has(id):
			rpc_lobbies.rpc_id(id, list)


func _send_lobby(m: int) -> void:
	var t: Dictionary = _matches[m]
	var data := {"mid": m, "host": net._sessions.get(t["host"], "?"), "stake": t["stake"], "teams": _names(t), "started": t["started"]}
	for k in 2:
		for id in t["teams"][k]:
			rpc_lobby.rpc_id(id, data)


@rpc("any_peer", "reliable")
func rpc_create(stake: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id) or not stake in STAKES:
		return
	if _member.has(id) or not _in_complex(id):
		_pay(id, stake, "Mise rendue")
		net.rpc_notice.rpc_id(id, "Tu es déjà dans un match, ou pas au complexe de mini-foot.")
		return
	var m := _next
	_next += 1
	_matches[m] = {"host": id, "stake": stake, "teams": [[id], []], "started": false, "pitch": -1,
		"p": Vector3(0, 0.11, 0), "v": Vector3.ZERO, "score": [0, 0], "time": DURATION, "pause": 0.0, "cd": {}, "last": -1}
	_member[id] = m
	_send_lobby(m)
	_broadcast_lobbies()


@rpc("any_peer", "reliable")
func rpc_join(m: int, team: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id):
		return
	var t: Dictionary = _matches.get(m, {})
	var stake: int = int(t.get("stake", 0))
	if t.is_empty() or t["started"] or _member.has(id) or team < 0 or team > 1 or t["teams"][team].size() >= MAX_TEAM or not _in_complex(id):
		# La mise a déjà été prise chez le joueur : on la rend
		var st: int = stake if not t.is_empty() else 0
		_pay(id, st, "Mise rendue")
		net.rpc_notice.rpc_id(id, "Impossible de rejoindre ce match (complet, commencé, ou tu n'es pas au complexe).")
		return
	t["teams"][team].append(id)
	_member[id] = m
	_send_lobby(m)
	_broadcast_lobbies()


@rpc("any_peer", "reliable")
func rpc_switch(team: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _member.has(id) or team < 0 or team > 1:
		return
	var t: Dictionary = _matches[_member[id]]
	if t["started"] or id in t["teams"][team] or t["teams"][team].size() >= MAX_TEAM:
		return
	t["teams"][1 - team].erase(id)
	t["teams"][team].append(id)
	_send_lobby(_member[id])
	_broadcast_lobbies()


@rpc("any_peer", "reliable")
func rpc_leave() -> void:
	if net.is_server:
		var id := multiplayer.get_remote_sender_id()
		if _member.has(id):
			_leave(id, "%s a quitté le match." % net._sessions.get(id, "Un joueur"))


func _leave(id: int, message: String) -> void:
	var m: int = _member[id]
	var t: Dictionary = _matches[m]
	_member.erase(id)
	for k in 2:
		t["teams"][k].erase(id)
	if t["started"]:
		t["left_stakes"] = int(t.get("left_stakes", 0)) + 1 # sa mise reste dans la cagnotte
	if net._sessions.has(id):
		if not t["started"]:
			_pay(id, int(t["stake"]), "Mise rendue (match quitté)")
		rpc_lobby.rpc_id(id, {})
		if t["started"]:
			rpc_end.rpc_id(id, m, "Tu as quitté le match : ta mise reste dans la cagnotte.", -1)
	var everyone: Array = t["teams"][0] + t["teams"][1]
	if everyone.is_empty():
		_matches.erase(m)
	elif t["started"] and (t["teams"][0].is_empty() or t["teams"][1].is_empty()):
		# Une équipe est vide : l'autre gagne par forfait
		_finish(m, 0 if t["teams"][1].is_empty() else 1, "forfait")
	else:
		if t["host"] == id:
			t["host"] = everyone[0]
		for p in everyone:
			net.rpc_notice.rpc_id(p, message)
		_send_lobby(m)
	_broadcast_lobbies()


@rpc("any_peer", "reliable")
func rpc_launch() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _member.has(id):
		return
	var m: int = _member[id]
	var t: Dictionary = _matches[m]
	if t["host"] != id or t["started"]:
		return
	if t["teams"][0].is_empty() or t["teams"][1].is_empty():
		net.rpc_notice.rpc_id(id, "Il faut au moins un joueur dans chaque équipe.")
		return
	var used: Array = []
	for o in _matches.values():
		if o["started"]:
			used.append(o["pitch"])
	var pitch := -1
	for p in ONLINE_PITCHES:
		if not p in used:
			pitch = p
			break
	if pitch < 0:
		net.rpc_notice.rpc_id(id, "Les deux terrains sont occupés : attendez la fin d'un match.")
		return
	t["started"] = true
	t["pitch"] = pitch
	t["time"] = DURATION
	t["ball"] = FootBall.new()
	t["owner"] = -1
	t["nopick"] = {}
	t["stun"] = {}
	t["knock"] = {}
	t["skill"] = {}
	t["pl"] = {} ## id → position (repère du terrain)
	t["vel"] = {}
	t["face"] = {}
	t["seen"] = {} ## id → [position, heure] de la dernière position reçue
	t["shot"] = false
	t["shot_team"] = -1
	t["restart"] = {}
	t["keep"] = [_keeper(0), _keeper(1)]
	var roster := {}
	for k in 2:
		for p in t["teams"][k]:
			roster[net._sessions.get(p, "?")] = k
	for k in 2:
		for p in t["teams"][k]:
			rpc_start.rpc_id(p, m, pitch, k, roster, DURATION)
	_kickoff(m, 0)
	_broadcast_lobbies()
	print("Mini-foot : match %d lancé (%s)" % [m, JSON.stringify(roster)])


func _keeper(team: int) -> Dictionary:
	return {"x": -_attack(team) * (HL - 0.8), "z": 0.0, "dive": 0.0, "side": 0.0, "save": false, "tried": false, "hold": 0.0}


func _attack(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func _everyone(t: Dictionary) -> Array:
	return t["teams"][0] + t["teams"][1]


func _notice_all(t: Dictionary, text: String) -> void:
	for id in _everyone(t):
		net.rpc_notice.rpc_id(id, text)


func _who(id: int) -> String:
	return net._sessions.get(id, "?")


## Coup d'envoi : ballon au centre ; après la pause, le joueur de « team » le plus proche l'a
func _kickoff(m: int, team: int) -> void:
	var t: Dictionary = _matches[m]
	t["ball"].reset()
	t["owner"] = -1
	t["shot"] = false
	t["pause"] = 3.0
	t["last"] = team
	t["restart"] = {"team": team, "at": Vector2.ZERO}
	for k in 2:
		t["keep"][k] = _keeper(k)
	for p in _everyone(t):
		rpc_kickoff.rpc_id(p, m, team)
		rpc_score.rpc_id(p, m, t["score"][0], t["score"][1], t["time"])


## Remise en jeu (sortie, faute) : ballon posé, l'équipe « team » le reprend après une courte pause
func _set_restart(m: int, team: int, at: Vector2) -> void:
	var t: Dictionary = _matches[m]
	t["ball"].reset(at)
	t["owner"] = -1
	t["shot"] = false
	t["pause"] = 1.4
	t["restart"] = {"team": team, "at": at}


func _resume(t: Dictionary) -> void:
	var team: int = int(t["restart"].get("team", 0))
	var at: Vector2 = t["restart"].get("at", Vector2.ZERO)
	t["restart"] = {}
	var best := -1
	var bd := INF
	for id in t["teams"][team]:
		if t["pl"].has(id):
			var d: float = (t["pl"][id] as Vector2).distance_to(at)
			if d < bd:
				bd = d
				best = id
	if best > 0:
		t["owner"] = best
		t["last"] = team


func _local_of(t: Dictionary, id: int) -> Vector3:
	var w: Vector3 = net._pos.get(id, Vector3.INF)
	return w - (Foot.ORIGIN + Vector3(0, 0, Foot.PITCHES[t["pitch"]]))


func _team_of(t: Dictionary, id: int) -> int:
	return 0 if id in t["teams"][0] else 1


func _active(id: int) -> Dictionary:
	if not _member.has(id):
		return {}
	var t: Dictionary = _matches[_member[id]]
	return t if t["started"] and t.has("ball") else {}


@rpc("any_peer", "reliable")
func rpc_strike(vel: Vector3, spin: float, is_shot: bool) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var t := _active(id)
	if t.is_empty() or t["pause"] > 0.0 or not t["pl"].has(id):
		return
	var b = t["ball"]
	var me: Vector2 = t["pl"][id]
	var free_ball: bool = t["owner"] == -1 and me.distance_to(b.flat()) < KICK_REACH and b.p.y < 1.6
	if t["owner"] != id and not free_ball:
		return
	t["owner"] = -1
	b.v = vel.limit_length(30.0)
	b.spin = clampf(spin, -3.0, 3.0)
	b.p.y = maxf(b.p.y, FootBall.R)
	t["nopick"][id] = 0.3
	t["last"] = _team_of(t, id)
	t["shot"] = is_shot
	t["shot_team"] = _team_of(t, id)
	for k in 2:
		t["keep"][k]["tried"] = false
	for p in _everyone(t):
		if p != id:
			rpc_fx.rpc_id(p, _member[id], id, "kick")


@rpc("any_peer", "reliable")
func rpc_tackle() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var t := _active(id)
	var o: int = int(t.get("owner", -1)) if not t.is_empty() else -1
	if t.is_empty() or o <= 0 or _team_of(t, o) == _team_of(t, id) or float(t["stun"].get(id, 0.0)) > 0.0:
		return
	if not t["pl"].has(id) or not t["pl"].has(o):
		return
	var d: Vector2 = t["pl"][id] - t["pl"][o]
	if d.length() > TACKLE_REACH:
		return
	for p in _everyone(t):
		if p != id:
			rpc_fx.rpc_id(p, _member[id], id, "kick")
	var behind: bool = d.normalized().dot(t["face"].get(o, Vector2.ZERO)) < -0.3
	if randf() < (0.4 if behind else 0.6):
		if behind and randf() < 0.4:
			_notice_all(t, "Faute de %s sur %s ! Coup franc." % [_who(id), _who(o)])
			_set_restart(_member[id], _team_of(t, o), t["ball"].flat())
			return
		var b = t["ball"]
		t["owner"] = -1
		var away: Vector2 = (b.flat() - t["pl"][o]).normalized() if b.flat().distance_to(t["pl"][o]) > 0.05 else -d.normalized()
		b.v = Vector3(away.x, 0.0, away.y) * 3.0
		t["nopick"][o] = 0.7
		t["stun"][o] = 0.45
		net.rpc_notice.rpc_id(o, "%s te prend le ballon !" % _who(id))
	else:
		t["stun"][id] = 0.5
		net.rpc_notice.rpc_id(id, "Tacle raté !")


@rpc("any_peer", "reliable")
func rpc_skill(dir: Vector2) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var t := _active(id)
	if not t.is_empty() and t["owner"] == id and dir.length() > 0.1:
		t["skill"][id] = [0.4, dir.normalized()]


func _process(delta: float) -> void:
	if net == null or not net.is_server or _matches.is_empty():
		return
	_acc += delta
	_send_acc += delta
	var send := _send_acc >= SEND_EVERY
	if send:
		_send_acc = 0.0
	while _acc >= TICK:
		_acc -= TICK
		for m in _matches.keys():
			if _matches.has(m) and _matches[m]["started"] and _matches[m].has("ball"):
				_step(m, TICK)
	if send:
		for m in _matches:
			var t: Dictionary = _matches[m]
			if not t["started"] or not t.has("ball"):
				continue
			var b = t["ball"]
			var k0: Dictionary = t["keep"][0]
			var k1: Dictionary = t["keep"][1]
			var s := PackedFloat32Array([b.p.x, b.p.y, b.p.z, b.v.x, b.v.y, b.v.z,
				k0["x"], k0["z"], k0["side"] if k0["dive"] > 0.0 else 0.0, k1["x"], k1["z"], k1["side"] if k1["dive"] > 0.0 else 0.0])
			for id in _everyone(t):
				rpc_ball.rpc_id(id, m, s, int(t["owner"]))


## Un pas de jeu (30 par seconde) dans le repère du terrain (x : longueur, z : largeur)
func _step(m: int, dt: float) -> void:
	var t: Dictionary = _matches[m]
	var now := Time.get_ticks_msec() / 1000.0
	# Positions, vitesses et directions des joueurs (reçues 10 fois par seconde)
	for id in _everyone(t):
		var w := _local_of(t, id)
		if not w.is_finite():
			t["pl"].erase(id)
			continue
		var p2 := Vector2(w.x, w.z)
		var seen: Array = t["seen"].get(id, [p2, now])
		if p2 != seen[0]:
			var v: Vector2 = (p2 - seen[0]) / maxf(0.03, now - float(seen[1]))
			t["vel"][id] = (t["vel"].get(id, Vector2.ZERO) as Vector2).lerp(v.limit_length(9.0), 0.6)
			t["seen"][id] = [p2, now]
		elif now - float(seen[1]) > 0.3:
			t["vel"][id] = Vector2.ZERO
		# Position prolongée jusqu'à maintenant
		t["pl"][id] = p2 + (t["vel"].get(id, Vector2.ZERO) as Vector2) * clampf(now - float(t["seen"].get(id, [p2, now])[1]), 0.0, 0.15)
		var vv: Vector2 = t["vel"].get(id, Vector2.ZERO)
		if vv.length() > 0.6:
			t["face"][id] = vv.normalized()
		var sk: Array = t["skill"].get(id, [])
		if not sk.is_empty():
			sk[0] = float(sk[0]) - dt
			if sk[0] > 0.0:
				t["face"][id] = sk[1]
			else:
				t["skill"].erase(id)
	for dct in [t["nopick"], t["stun"], t["knock"]]:
		for id in dct.keys():
			dct[id] = float(dct[id]) - dt
	if t["pause"] > 0.0:
		t["pause"] = float(t["pause"]) - dt
		if t["pause"] <= 0.0:
			_resume(t)
		return
	t["time"] = float(t["time"]) - dt
	if t["time"] <= 0.0:
		var sc: Array = t["score"]
		_finish(m, 0 if sc[0] > sc[1] else (1 if sc[1] > sc[0] else -1), "")
		return
	var b = t["ball"]
	var o: int = int(t["owner"])
	if o > 0 and not t["pl"].has(o):
		t["owner"] = -1
		o = -1
	if o > 0:
		# Conduite de balle : le ballon reste devant le pied du porteur
		var me: Vector2 = t["pl"][o]
		var face: Vector2 = t["face"].get(o, Vector2(_attack(_team_of(t, o)), 0))
		var vel: Vector2 = t["vel"].get(o, Vector2.ZERO)
		var target := me + face * (0.42 + vel.length() * 0.06)
		target = Vector2(clampf(target.x, -HL + 0.2, HL - 0.2), clampf(target.y, -HW + 0.2, HW - 0.2))
		var cur: Vector2 = b.flat().lerp(target, 1.0 - exp(-14.0 * dt))
		b.p = Vector3(cur.x, FootBall.R, cur.y)
		b.v = Vector3(vel.x, 0.0, vel.y)
		if vel.length() > 5.6 and float(t["knock"].get(o, 0.0)) <= 0.0:
			# En sprint, il pousse le ballon devant lui
			t["knock"][o] = 0.6
			t["owner"] = -1
			t["nopick"][o] = 0.2
			b.v = Vector3(face.x, 0.0, face.y) * vel.length() * 1.45
	elif o <= -2:
		# Dans les mains d'un gardien : il relance vers le joueur de son équipe le plus proche
		var k := -o - 2
		var kp: Dictionary = t["keep"][k]
		var a := _attack(k)
		b.p = Vector3(kp["x"] + a * 0.35, 1.05, kp["z"])
		b.v = Vector3.ZERO
		kp["hold"] = float(kp["hold"]) + dt
		if kp["hold"] > 1.3:
			var from := Vector2(b.p.x, b.p.z)
			var to := Vector2(0, randf_range(-5.0, 5.0))
			var bd := INF
			for id in t["teams"][k]:
				if t["pl"].has(id) and (t["pl"][id] as Vector2).distance_to(from) < bd:
					bd = (t["pl"][id] as Vector2).distance_to(from)
					to = t["pl"][id]
			b.v = FootBall.ground_pass(from, to) if from.distance_to(to) < 15.0 else FootBall.lob(from, to)
			b.p.y = 0.6
			t["owner"] = -1
			t["last"] = k
			t["shot"] = false
	else:
		var ev: String = b.step(dt)
		match ev:
			"goal+":
				_goal(m, 0)
				return
			"goal-":
				_goal(m, 1)
				return
			"post":
				_notice_all(t, "Poteau !")
			"out":
				_set_restart(m, 1 - maxi(int(t["last"]), 0), Vector2(clampf(b.p.x, -HL + 2.0, HL - 2.0), signf(b.p.z) * (HW - 0.6)))
				return
		if b.in_goal == 0:
			_pickup(t)
	_keepers(t, dt)
	# Chaque seconde, le score et le temps
	if int(float(t["time"]) + dt) != int(t["time"]):
		for id in _everyone(t):
			rpc_score.rpc_id(id, m, t["score"][0], t["score"][1], t["time"])


## Ballon libre : le joueur le plus proche à portée le contrôle (sauf frappe trop forte : il rebondit)
func _pickup(t: Dictionary) -> void:
	var b = t["ball"]
	if b.p.y > 0.9:
		return
	var best := -1
	var bd := PICK
	for id in t["pl"]:
		if float(t["nopick"].get(id, 0.0)) > 0.0 or float(t["stun"].get(id, 0.0)) > 0.0:
			continue
		var d: float = (t["pl"][id] as Vector2).distance_to(b.flat())
		if d < bd:
			bd = d
			best = id
	if best < 0:
		return
	if Vector2(b.v.x, b.v.z).length() > 15.0:
		b.v = Vector3(-b.v.x * 0.25 + randf_range(-2, 2), 1.5, -b.v.z * 0.25 + randf_range(-2, 2))
		t["nopick"][best] = 0.35
		return
	t["owner"] = best
	t["last"] = _team_of(t, best)
	t["shot"] = false
	b.spin = 0.0


## Gardiens automatiques : placement, plongeon, arrêt (capté ou repoussé)
func _keepers(t: Dictionary, dt: float) -> void:
	var b = t["ball"]
	for k in 2:
		var kp: Dictionary = t["keep"][k]
		var a := _attack(k)
		var own_x := -a * HL
		if t["owner"] == -2 - k:
			continue
		var kpos := Vector2(kp["x"], kp["z"])
		if kp["dive"] > 0.0:
			kp["dive"] = float(kp["dive"]) - dt
			if kp["dive"] > 0.45:
				kp["z"] = clampf(float(kp["z"]) + float(kp["side"]) * 4.5 * dt, -2.1, 2.1)
		else:
			var dist: float = b.flat().distance_to(Vector2(own_x, 0))
			var tx := own_x + a * clampf(0.6 + dist * 0.04, 0.6, 1.8)
			var tz := clampf(b.p.z * 0.5, -1.3, 1.3)
			kpos = kpos.move_toward(Vector2(tx, tz), 5.0 * dt)
			kp["x"] = kpos.x
			kp["z"] = kpos.y
		# Tir qui arrive : il décide une fois s'il l'arrête, et plonge si besoin
		if t["shot"] and t["shot_team"] != k and not kp["tried"] and b.v.x * a < -1.0:
			var tc: float = (own_x - b.p.x) / b.v.x
			if tc > 0.0 and tc < 1.4:
				kp["tried"] = true
				var zc: float = b.p.z + b.v.z * tc
				var yc: float = maxf(FootBall.R, b.p.y + b.v.y * tc - 0.5 * FootBall.G * tc * tc)
				if absf(zc) < FootBall.GOAL_W / 2.0 + 0.25 and yc < FootBall.GOAL_H + 0.3:
					var dz: float = zc - float(kp["z"])
					var sp: float = b.v.length()
					var chance := clampf(0.92 - sp * 0.021 - maxf(0.0, absf(dz) - 0.5) * 0.28 - (0.12 if yc > 1.4 else 0.0), 0.08, 0.85)
					kp["save"] = randf() < chance
					if absf(dz) > 0.55:
						kp["dive"] = 0.9
						kp["side"] = signf(dz)
		if kp["save"] and t["shot"] and Vector2(kp["x"], kp["z"]).distance_to(b.flat()) < (1.7 if kp["dive"] > 0.0 else 1.1) and b.p.y < 2.4:
			kp["save"] = false
			t["shot"] = false
			if b.v.length() < 17.0 and b.p.y < 1.7 and kp["dive"] <= 0.0:
				t["owner"] = -2 - k
				kp["hold"] = 0.0
				_notice_all(t, "Le gardien des %s capte le ballon !" % ("jaunes" if k == 0 else "rouges"))
			else:
				b.v = Vector3(a * randf_range(3.0, 6.0), randf_range(2.0, 4.5), signf(b.p.z + 0.01) * randf_range(4.0, 8.0))
				b.spin = 0.0
				t["last"] = k
				_notice_all(t, "Parade du gardien des %s !" % ("jaunes" if k == 0 else "rouges"))
		# Ballon libre et lent dans ses pieds : il le ramasse
		if t["owner"] == -1 and not t["shot"] and absf(b.p.x - own_x) < 2.5 and Vector2(kp["x"], kp["z"]).distance_to(b.flat()) < 0.8 and b.p.y < 2.0:
			t["owner"] = -2 - k
			kp["hold"] = 0.0


func _goal(m: int, team: int) -> void:
	var t: Dictionary = _matches[m]
	t["score"][team] += 1
	_notice_all(t, "BUUUT ! %s marquent : %d - %d" % ["Les jaunes" if team == 0 else "Les rouges", t["score"][0], t["score"][1]])
	_kickoff(m, 1 - team)
	t["pause"] = 3.5


## Fin du match : winner 0/1, -1 nul ; la cagnotte va aux gagnants, à parts égales
func _finish(m: int, winner: int, why: String) -> void:
	var t: Dictionary = _matches[m]
	var everyone: Array = t["teams"][0] + t["teams"][1]
	var stake: int = int(t["stake"])
	var pot: int = stake * (everyone.size() + int(t.get("left_stakes", 0)))
	var s: Array = t["score"]
	for id in everyone:
		var team := _team_of(t, id)
		var outcome := 0 if winner < 0 else (1 if team == winner else -1)
		var msg: String
		if outcome == 0:
			msg = "Match nul %d - %d." % [s[0], s[1]]
			_pay(id, stake, "Mini-foot : mise rendue (match nul)")
		elif outcome == 1:
			msg = "Victoire %s%d - %d !" % ["par forfait, " if why == "forfait" else "", s[team], s[1 - team]]
			_pay(id, pot / maxi(1, t["teams"][winner].size()), "Mini-foot : cagnotte des vainqueurs")
		else:
			msg = "Défaite %d - %d." % [s[team], s[1 - team]]
		rpc_end.rpc_id(id, m, msg, outcome)
		_member.erase(id)
	print("Mini-foot : match %d terminé %d - %d" % [m, s[0], s[1]])
	_matches.erase(m)
	_broadcast_lobbies()
