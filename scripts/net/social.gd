extends Node
## Activités à plusieurs (mode en ligne), nœud « Social » enfant de Net :
## même chemin sur le serveur et chez les joueurs, donc les messages (RPC) se trouvent des deux côtés.
## - Groupes « Mbokk » (famille) : créer, inviter, quitter ; étiquette sous le pseudo ; positions des membres.
## - Courses de voitures : ouverte par un joueur vers un lieu de Dakar, avec mise ; points de passage
##   calculés par le serveur sur le vrai réseau routier ; classement ; la cagnotte va au vainqueur.
## - Duels de lutte (mbapatt) : défi entre deux joueurs proches avec mise ; manches à choix simultanés
##   (charger, esquiver, crocheter) ; le premier à 3 points gagne la mise des deux.
## Côté serveur, toutes les règles sont vérifiées ici ; côté joueur, social_ui.gd affiche.

signal group_changed(name: String, members: Array, color: String)
signal group_invited(name: String, from: String)
signal group_positions(data: PackedFloat64Array)
signal tags_changed
signal race_open(race_id: int, host: String, dest: String, fee: int, pos: Vector3)
signal race_lobby(race_id: int, names: Array, host_id: int)
signal race_go(race_id: int, cps: PackedVector3Array, delay: float)
signal race_progress(race_id: int, who: String, place: int, time: float)
signal race_result(race_id: int, ranking: Array)
signal duel_invited(from_id: int, from_name: String, stake: int)
signal duel_start(opponent_id: int, opponent_name: String, stake: int)
signal duel_round(round_no: int, seconds: float)
signal duel_outcome(my_choice: String, their_choice: String, won: int, my_score: int, their_score: int)
signal duel_end(won: bool, stake: int)

const GROUPS_PATH := "user://server_groups.json"
const GROUP_COLORS := ["e63946", "2a9d8f", "f4a261", "8338ec", "3a86ff", "ffbe0b", "06d6a0", "ff006e"]
const CHOICES := ["charger", "esquiver", "crocheter"]
## choix → ce qu'il bat
const BEATS := {"charger": "crocheter", "crocheter": "esquiver", "esquiver": "charger"}
const RACE_JOIN_RANGE := 80.0
const RACE_CP_RANGE := 30.0
const RACE_TIMEOUT := 300.0
const DUEL_RANGE := 8.0
const DUEL_ROUND := 7.0
const DUEL_POINTS := 3

var net
# --- Côté joueur ---
var tags := {} ## id de pair → nom du groupe
var my_group := ""
var my_members: Array = []
# --- Côté serveur ---
var _groups := {} ## nom → {owner, members: [pseudo], color}
var _invites := {} ## pseudo invité → nom du groupe
var _races := {} ## id → course
var _next_race := 1
var _duels := {} ## id → duel
var _duel_of := {} ## id de pair → id du duel
var _duel_invites := {} ## (défié, défiant) → mise
var _next_duel := 1
var _pos_t := 2.0
var _save_t := 30.0
var _groups_dirty := false


# =====================================================================================
# Serveur : général
# =====================================================================================

func load_groups() -> void:
	if FileAccess.file_exists(GROUPS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(GROUPS_PATH))
		if d is Dictionary:
			_groups = d


func save_groups() -> void:
	var f := FileAccess.open(GROUPS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_groups))
	_groups_dirty = false


func group_of(pseudo: String) -> String:
	for g in _groups:
		if pseudo in _groups[g]["members"]:
			return g
	return ""


func _id_of(pseudo: String) -> int:
	for id in net._sessions:
		if net._sessions[id] == pseudo:
			return id
	return -1


func on_join(id: int, who: String) -> void:
	# Étiquettes de groupe de tout le monde pour le nouveau ; la sienne pour les autres
	var full := {}
	for other in net._sessions:
		var g := group_of(net._sessions[other])
		if g != "":
			full[other] = g
	rpc_tags_full.rpc_id(id, full)
	var mine := group_of(who)
	if mine != "":
		for other in net._sessions:
			rpc_tag.rpc_id(other, id, mine)
		_send_group_info(mine)


func on_leave(id: int, who: String) -> void:
	for rid in _races.keys():
		var r: Dictionary = _races[rid]
		r["entrants"].erase(id)
		if r["host"] == id and r["state"] == "lobby":
			_races.erase(rid)
	if _duel_of.has(id):
		var did: int = _duel_of[id]
		var d: Dictionary = _duels[did]
		var other: int = d["b"] if d["a"] == id else d["a"]
		_end_duel(did, other)
	var g := group_of(who)
	if g != "":
		_send_group_info(g)


func server_tick(delta: float) -> void:
	_pos_t -= delta
	if _pos_t <= 0.0:
		_pos_t = 2.0
		_send_group_positions()
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 30.0
		if _groups_dirty:
			save_groups()
	_tick_races(delta)
	_tick_duels(delta)


# =====================================================================================
# Groupes (Mbokk)
# =====================================================================================

@rpc("any_peer", "reliable")
func rpc_group_create(name: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id):
		return
	var who: String = net._sessions[id]
	name = name.strip_edges().left(20)
	if name.length() < 3:
		net.rpc_notice.rpc_id(id, "Le nom du groupe doit faire au moins 3 lettres.")
	elif group_of(who) != "":
		net.rpc_notice.rpc_id(id, "Tu as déjà un groupe. Quitte-le d'abord.")
	elif _groups.has(name):
		net.rpc_notice.rpc_id(id, "Ce nom de groupe est déjà pris.")
	else:
		_groups[name] = {"owner": who, "members": [who], "color": GROUP_COLORS[_groups.size() % GROUP_COLORS.size()]}
		_groups_dirty = true
		net.rpc_notice.rpc_id(id, "Groupe « %s » créé ! Invite tes amis depuis le téléphone (Mbokk)." % name)
		for other in net._sessions:
			rpc_tag.rpc_id(other, id, name)
		_send_group_info(name)


@rpc("any_peer", "reliable")
func rpc_group_invite(target: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id) or not net._sessions.has(target):
		return
	var g := group_of(net._sessions[id])
	if g == "":
		return
	if group_of(net._sessions[target]) != "":
		net.rpc_notice.rpc_id(id, "%s a déjà un groupe." % net._sessions[target])
		return
	_invites[net._sessions[target]] = g
	rpc_group_invited.rpc_id(target, g, net._sessions[id])
	net.rpc_notice.rpc_id(id, "Invitation envoyée à %s." % net._sessions[target])


@rpc("any_peer", "reliable")
func rpc_group_accept(name: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id):
		return
	var who: String = net._sessions[id]
	if _invites.get(who, "") != name or not _groups.has(name) or group_of(who) != "":
		return
	_invites.erase(who)
	_groups[name]["members"].append(who)
	_groups_dirty = true
	for other in net._sessions:
		rpc_tag.rpc_id(other, id, name)
	_send_group_info(name)


## Compte supprimé : le joueur disparaît de son groupe (serveur)
func forget(who: String) -> void:
	var g := group_of(who)
	if g == "":
		return
	var grp: Dictionary = _groups[g]
	grp["members"].erase(who)
	if grp["members"].is_empty():
		_groups.erase(g)
	elif grp["owner"] == who:
		grp["owner"] = grp["members"][0]
	_groups_dirty = true
	if _groups.has(g):
		_send_group_info(g)


@rpc("any_peer", "reliable")
func rpc_group_leave() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id):
		return
	var who: String = net._sessions[id]
	var g := group_of(who)
	if g == "":
		return
	var grp: Dictionary = _groups[g]
	grp["members"].erase(who)
	if grp["members"].is_empty():
		_groups.erase(g)
	elif grp["owner"] == who:
		grp["owner"] = grp["members"][0]
	_groups_dirty = true
	for other in net._sessions:
		rpc_tag.rpc_id(other, id, "")
	rpc_group_info.rpc_id(id, "", [], "")
	if _groups.has(g):
		_send_group_info(g)


func _send_group_info(g: String) -> void:
	if not _groups.has(g):
		return
	var grp: Dictionary = _groups[g]
	var members: Array = []
	for m in grp["members"]:
		var mid := _id_of(m)
		members.append([m, mid, m == grp["owner"]])
	for m in grp["members"]:
		var mid := _id_of(m)
		if mid > 0:
			rpc_group_info.rpc_id(mid, g, members, grp["color"])


## Positions des membres en ligne (même loin) : [id, x, z] à plat
func _send_group_positions() -> void:
	for g in _groups:
		var ids: Array = []
		for m in _groups[g]["members"]:
			var mid := _id_of(m)
			if mid > 0 and net._pos.has(mid):
				ids.append(mid)
		if ids.size() < 2:
			continue
		var data := PackedFloat64Array()
		for mid in ids:
			var p: Vector3 = net._pos[mid]
			data.append_array([mid, p.x, p.z])
		for mid in ids:
			rpc_group_pos.rpc_id(mid, data)


@rpc("authority", "reliable")
func rpc_group_info(name: String, members: Array, color: String) -> void:
	my_group = name
	my_members = members
	group_changed.emit(name, members, color)


@rpc("authority", "reliable")
func rpc_group_invited(name: String, from: String) -> void:
	group_invited.emit(name, from)


@rpc("authority", "unreliable_ordered")
func rpc_group_pos(data: PackedFloat64Array) -> void:
	group_positions.emit(data)


@rpc("authority", "reliable")
func rpc_tags_full(full: Dictionary) -> void:
	tags.clear()
	for id in full:
		tags[int(id)] = full[id]
	tags_changed.emit()


@rpc("authority", "reliable")
func rpc_tag(id: int, name: String) -> void:
	if name == "":
		tags.erase(id)
	else:
		tags[id] = name
	tags_changed.emit()


# =====================================================================================
# Courses de voitures
# =====================================================================================

@rpc("any_peer", "reliable")
func rpc_race_create(dest: String, fee: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id) or not net._pos.has(id) or net._traffic == null:
		return
	var city = net._traffic.city
	if not city.places.has(dest):
		return
	for rid in _races:
		if _races[rid]["host"] == id:
			net.rpc_notice.rpc_id(id, "Tu as déjà une course ouverte.")
			return
	var start: Vector3 = net._pos[id]
	var route: PackedVector3Array = city.route(start, city.places[dest], true)
	if route.size() < 3:
		net.rpc_notice.rpc_id(id, "Pas d'itinéraire jusqu'à %s." % dest)
		return
	# Points de passage tous les ~150 m le long de l'itinéraire, arrivée comprise
	var cps := PackedVector3Array()
	var acc := 0.0
	for i in range(1, route.size()):
		acc += route[i - 1].distance_to(route[i])
		if acc >= 150.0:
			cps.append(route[i])
			acc = 0.0
	if cps.is_empty() or cps[cps.size() - 1].distance_to(route[route.size() - 1]) > 30.0:
		cps.append(route[route.size() - 1])
	fee = clampi(fee, 0, 100000)
	var rid := _next_race
	_next_race += 1
	_races[rid] = {"host": id, "dest": dest, "fee": fee, "start": start, "cps": cps, "state": "lobby", "t": 0.0,
		"entrants": {id: {"cp": 0, "time": -1.0}}, "finished": []}
	# Annonce aux joueurs proches (400 m)
	for other in net._sessions:
		var p: Vector3 = net._pos.get(other, Vector3(INF, 0, INF))
		if Vector2(p.x - start.x, p.z - start.z).length() < 400.0:
			rpc_race_open.rpc_id(other, rid, net._sessions[id], dest, fee, start.x, start.z)
	_send_lobby(rid)


@rpc("any_peer", "reliable")
func rpc_race_join(rid: int) -> void:
	if not net.is_server or not _races.has(rid):
		return
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _races[rid]
	var p: Vector3 = net._pos.get(id, Vector3(INF, 0, INF))
	var s: Vector3 = r["start"]
	if r["state"] != "lobby":
		net.rpc_notice.rpc_id(id, "La course est déjà partie.")
	elif r["entrants"].size() >= 8:
		net.rpc_notice.rpc_id(id, "La course est complète (8 pilotes).")
	elif Vector2(p.x - s.x, p.z - s.z).length() > RACE_JOIN_RANGE:
		net.rpc_notice.rpc_id(id, "Rejoins la ligne de départ (moins de %d m) pour t'inscrire." % int(RACE_JOIN_RANGE))
	else:
		r["entrants"][id] = {"cp": 0, "time": -1.0}
		_send_lobby(rid)


@rpc("any_peer", "reliable")
func rpc_race_start(rid: int) -> void:
	if not net.is_server or not _races.has(rid):
		return
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _races[rid]
	if r["host"] != id or r["state"] != "lobby":
		return
	r["state"] = "running"
	r["t"] = -5.0 # compte à rebours de 5 s
	for e in r["entrants"]:
		rpc_race_go.rpc_id(e, rid, r["cps"], 5.0)


@rpc("any_peer", "reliable")
func rpc_race_cp(rid: int, idx: int, x: float, z: float) -> void:
	if not net.is_server or not _races.has(rid):
		return
	var id := multiplayer.get_remote_sender_id()
	var r: Dictionary = _races[rid]
	if r["state"] != "running" or float(r["t"]) < 0.0 or not r["entrants"].has(id):
		if OS.has_environment("NET_DEBUG"):
			print("DEBUG point refusé : état %s t=%.1f inscrit=%s" % [r["state"], float(r["t"]), r["entrants"].has(id)])
		return
	var e: Dictionary = r["entrants"][id]
	var cps: PackedVector3Array = r["cps"]
	if idx != int(e["cp"]) or idx >= cps.size():
		return
	# Position annoncée près du point, et cohérente avec la dernière position connue du serveur
	var p: Vector3 = net._pos.get(id, Vector3(INF, 0, INF))
	if Vector2(x - cps[idx].x, z - cps[idx].z).length() > RACE_CP_RANGE or Vector2(p.x - x, p.z - z).length() > 250.0:
		if OS.has_environment("NET_DEBUG"):
			print("DEBUG point %d refusé : annoncé %s, point %s, serveur %s" % [idx, Vector2(x, z), cps[idx], p])
		return # position incohérente : point non validé
	e["cp"] = idx + 1
	if e["cp"] >= cps.size():
		e["time"] = r["t"]
		r["finished"].append(id)
		var place: int = r["finished"].size()
		for other in r["entrants"]:
			rpc_race_progress.rpc_id(other, rid, net._sessions[id], place, float(r["t"]))
		if r["finished"].size() >= r["entrants"].size():
			_finish_race(rid)


func _tick_races(delta: float) -> void:
	for rid in _races.keys():
		var r: Dictionary = _races[rid]
		if r["state"] == "running":
			r["t"] = float(r["t"]) + delta
			if float(r["t"]) > RACE_TIMEOUT:
				_finish_race(rid)


func _finish_race(rid: int) -> void:
	var r: Dictionary = _races[rid]
	var ranking: Array = []
	for id in r["finished"]:
		if net._sessions.has(id):
			ranking.append([net._sessions[id], snappedf(float(r["entrants"][id]["time"]), 0.01)])
	var pot: int = int(r["fee"]) * r["entrants"].size()
	if not r["finished"].is_empty() and pot > 0:
		var winner: int = r["finished"][0]
		if net._sessions.has(winner):
			net.rpc_receive_money.rpc_id(winner, "Serveur", pot, "Cagnotte de la course vers %s" % r["dest"])
	for e in r["entrants"]:
		if net._sessions.has(e):
			rpc_race_result.rpc_id(e, rid, ranking)
	_races.erase(rid)


func _send_lobby(rid: int) -> void:
	var r: Dictionary = _races[rid]
	var names: Array = []
	for e in r["entrants"]:
		names.append(net._sessions.get(e, "?"))
	for e in r["entrants"]:
		rpc_race_lobby.rpc_id(e, rid, names, r["host"])


@rpc("authority", "reliable")
func rpc_race_open(rid: int, host: String, dest: String, fee: int, x: float, z: float) -> void:
	race_open.emit(rid, host, dest, fee, Vector3(x, 0, z))


@rpc("authority", "reliable")
func rpc_race_lobby(rid: int, names: Array, host_id: int) -> void:
	race_lobby.emit(rid, names, host_id)


@rpc("authority", "reliable")
func rpc_race_go(rid: int, cps: PackedVector3Array, delay: float) -> void:
	race_go.emit(rid, cps, delay)


@rpc("authority", "reliable")
func rpc_race_progress(rid: int, who: String, place: int, time: float) -> void:
	race_progress.emit(rid, who, place, time)


@rpc("authority", "reliable")
func rpc_race_result(rid: int, ranking: Array) -> void:
	race_result.emit(rid, ranking)


# =====================================================================================
# Duels de lutte (mbapatt)
# =====================================================================================

@rpc("any_peer", "reliable")
func rpc_duel_challenge(target: int, stake: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id) or not net._sessions.has(target) or _duel_of.has(id) or _duel_of.has(target):
		return
	var a: Vector3 = net._pos.get(id, Vector3.ZERO)
	var b: Vector3 = net._pos.get(target, Vector3(INF, 0, INF))
	if Vector2(a.x - b.x, a.z - b.z).length() > DUEL_RANGE:
		net.rpc_notice.rpc_id(id, "Approche-toi pour lancer le défi.")
		return
	stake = clampi(stake, 0, 100000)
	_duel_invites[Vector2i(target, id)] = stake
	rpc_duel_invited.rpc_id(target, id, net._sessions[id], stake)
	net.rpc_notice.rpc_id(id, "Défi envoyé à %s (mise %d FCFA)." % [net._sessions[target], stake])


@rpc("any_peer", "reliable")
func rpc_duel_accept(challenger: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var key := Vector2i(id, challenger)
	if not _duel_invites.has(key) or _duel_of.has(id) or _duel_of.has(challenger) or not net._sessions.has(challenger):
		return
	var stake: int = _duel_invites[key]
	_duel_invites.erase(key)
	var did := _next_duel
	_next_duel += 1
	_duels[did] = {"a": challenger, "b": id, "score": {challenger: 0, id: 0}, "round": 0, "choices": {}, "t": 2.5, "stake": stake}
	_duel_of[challenger] = did
	_duel_of[id] = did
	rpc_duel_start.rpc_id(challenger, id, net._sessions[id], stake)
	rpc_duel_start.rpc_id(id, challenger, net._sessions[challenger], stake)


@rpc("any_peer", "reliable")
func rpc_duel_choice(choice: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _duel_of.has(id) or not choice in CHOICES:
		return
	var d: Dictionary = _duels[_duel_of[id]]
	if int(d["round"]) > 0 and not d["choices"].has(id):
		d["choices"][id] = choice


func _tick_duels(delta: float) -> void:
	for did in _duels.keys():
		var d: Dictionary = _duels[did]
		d["t"] = float(d["t"]) - delta
		var both: bool = d["choices"].size() >= 2
		if int(d["round"]) > 0 and (both or float(d["t"]) <= 0.0):
			_resolve_round(did)
		elif int(d["round"]) == 0 and float(d["t"]) <= 0.0:
			_next_round(did)


func _next_round(did: int) -> void:
	var d: Dictionary = _duels[did]
	d["round"] = int(d["round"]) + 1
	d["choices"] = {}
	d["t"] = DUEL_ROUND
	for p in [d["a"], d["b"]]:
		rpc_duel_round.rpc_id(p, d["round"], DUEL_ROUND)


func _resolve_round(did: int) -> void:
	var d: Dictionary = _duels[did]
	var a: int = d["a"]
	var b: int = d["b"]
	# Pas de choix à temps : on part au hasard (on hésite !)
	var ca: String = d["choices"].get(a, CHOICES.pick_random())
	var cb: String = d["choices"].get(b, CHOICES.pick_random())
	var winner := 0
	if BEATS[ca] == cb:
		winner = a
	elif BEATS[cb] == ca:
		winner = b
	if winner != 0:
		d["score"][winner] = int(d["score"][winner]) + 1
	var sa: int = d["score"][a]
	var sb: int = d["score"][b]
	rpc_duel_outcome.rpc_id(a, ca, cb, 1 if winner == a else (-1 if winner == b else 0), sa, sb)
	rpc_duel_outcome.rpc_id(b, cb, ca, 1 if winner == b else (-1 if winner == a else 0), sb, sa)
	if sa >= DUEL_POINTS:
		_end_duel(did, a)
	elif sb >= DUEL_POINTS:
		_end_duel(did, b)
	else:
		d["round"] = 0
		d["t"] = 2.0 # petite pause avant la manche suivante


## Combat d'une journée de lutte (net_lutte.gd) : même déroulé qu'un duel, sans mise
func start_bout(a: int, b: int, jid: int) -> void:
	var did := _next_duel
	_next_duel += 1
	_duels[did] = {"a": a, "b": b, "score": {a: 0, b: 0}, "round": 0, "choices": {}, "t": 4.0, "stake": 0, "journee": jid,
		"names": {a: net._sessions[a], b: net._sessions[b]}}
	_duel_of[a] = did
	_duel_of[b] = did
	rpc_duel_start.rpc_id(a, b, net._sessions[b], 0)
	rpc_duel_start.rpc_id(b, a, net._sessions[a], 0)


func _end_duel(did: int, winner: int) -> void:
	var d: Dictionary = _duels[did]
	var stake: int = d["stake"]
	if d.has("journee"):
		var loser: int = d["b"] if winner == d["a"] else d["a"]
		# Noms gardés au début du combat : un joueur qui se déconnecte n'est plus dans les sessions
		net.lutte.on_bout_end(d["journee"], d["names"][winner], d["names"][loser])
	for p in [d["a"], d["b"]]:
		_duel_of.erase(p)
		if net._sessions.has(p):
			rpc_duel_end.rpc_id(p, p == winner, stake)
	# Chacun a misé en début de duel : le vainqueur reçoit les deux mises
	if stake > 0 and net._sessions.has(winner):
		net.rpc_receive_money.rpc_id(winner, "Serveur", stake * 2, "Mise du duel de lutte gagné")
	_duels.erase(did)


@rpc("authority", "reliable")
func rpc_duel_invited(from_id: int, from_name: String, stake: int) -> void:
	duel_invited.emit(from_id, from_name, stake)


@rpc("authority", "reliable")
func rpc_duel_start(opponent: int, opponent_name: String, stake: int) -> void:
	duel_start.emit(opponent, opponent_name, stake)


@rpc("authority", "reliable")
func rpc_duel_round(round_no: int, seconds: float) -> void:
	duel_round.emit(round_no, seconds)


@rpc("authority", "reliable")
func rpc_duel_outcome(mine: String, theirs: String, won: int, my_score: int, their_score: int) -> void:
	duel_outcome.emit(mine, theirs, won, my_score, their_score)


@rpc("authority", "reliable")
func rpc_duel_end(won: bool, stake: int) -> void:
	duel_end.emit(won, stake)
