extends Node
## Lutte en ligne, nœud « Lutte » enfant de Net : même chemin sur le serveur et chez les joueurs,
## donc les messages (RPC) existent des deux côtés. Toutes les règles sont vérifiées par le serveur.
## - Écuries de joueurs : fonder (frais), rejoindre, quitter, bilan des victoires et défaites.
##   Le chef d'écurie touche une commission de 10 % sur les cachets de ses lutteurs (versée par le serveur).
## - Journées de lutte entre joueurs : un promoteur annonce une journée dans un stade avec un cachet ;
##   il dépose la caution des cachets et primes, gardée par le serveur. Les joueurs s'inscrivent ;
##   au coup d'envoi, les combats s'enchaînent (mbapatt à manches, voir social.gd). Chaque lutteur
##   touche son cachet, le vainqueur une prime ; le promoteur récupère le reste de la caution et la
##   billetterie (spectateurs présents autour du stade).
## Côté joueur, scripts/net/net_lutte_ui.gd affiche ; l'application « Lutte » du téléphone sert de menu.

signal ecurie_changed
signal ecurie_list_received(list: Array)
signal journees_changed
signal journee_called(jid: int, pos: Vector3, side: int)
signal journee_bout(jid: int, winner: String, loser: String, forfeit: bool)
signal journee_ended(jid: int, text: String)

const ECURIES_PATH := "user://server_ecuries.json"
const CREATE_FEE := 25000
const MAX_MEMBERS := 12
const COMMISSION := 0.1
const PRIME := 0.5 ## prime de victoire : moitié du cachet
const CACHETS := [2000, 10000, 30000]
const SIZES := [2, 4, 8] ## lutteurs par journée
const OPEN_TIMEOUT := 1200.0 ## une journée non lancée est annulée (caution rendue) au bout de 20 minutes
const SPECTATOR_RANGE := 150.0
const TICKET := 1000 ## recette par spectateur présent
const VENUE_RANGE := 90.0 ## un lutteur doit être au stade quand on l'appelle
const COLORS := ["e63946", "2a9d8f", "f4a261", "8338ec", "3a86ff", "ffbe0b", "06d6a0", "ff006e"]

var net
# --- Côté joueur ---
var my_ecurie := ""
var my_members: Array = [] ## [pseudo, en ligne ?, chef ?]
var my_record := Vector2i.ZERO
var journees := {} ## jid → {promoter, venue, cachet, max, names: [pseudo], state, pos}
# --- Côté serveur ---
var _ecuries := {} ## nom → {owner, members: [pseudo], color, w, l}
var _journees := {} ## jid → journée
var _next_jid := 1
var _dirty := false
var _save_t := 30.0


static func escrow_for(cachet: int, size: int) -> int:
	# Par combat : deux cachets et une prime
	return int(ceil(cachet * (2.0 + PRIME) * size / 2.0))


# =====================================================================================
# Serveur : sauvegarde, connexions
# =====================================================================================

func load_ecuries() -> void:
	if not FileAccess.file_exists(ECURIES_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(ECURIES_PATH))
	if data is Dictionary:
		_ecuries = data


func save_ecuries() -> void:
	var f := FileAccess.open(ECURIES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_ecuries))
	_dirty = false


func ecurie_of(who: String) -> String:
	for n in _ecuries:
		if who in _ecuries[n]["members"]:
			return n
	return ""


func _id_of(who: String) -> int:
	return net.social._id_of(who)


## Verse de l'argent à un joueur ; hors ligne, il est ajouté à sa partie sauvegardée sur le serveur
func _pay(who: String, amount: int, reason: String) -> void:
	if amount <= 0 or who == "":
		return
	var id := _id_of(who)
	if id != -1:
		net.rpc_receive_money.rpc_id(id, "Serveur", amount, reason)
	elif net._accounts.has(who):
		var sv = net._accounts[who].get("save", {})
		if sv is Dictionary:
			sv["money"] = int(sv.get("money", 0)) + amount
			net._accounts[who]["save"] = sv
			net._dirty = true


func on_join(id: int, who: String) -> void:
	var e := ecurie_of(who)
	if e != "":
		_send_info(e)
	for jid in _journees:
		var j: Dictionary = _journees[jid]
		rpc_journee_info.rpc_id(id, jid, j["promoter"], j["venue"], j["cachet"], j["max"], j["wrestlers"], j["state"], j["pos"].x, j["pos"].z)


func on_leave(_id: int, who: String) -> void:
	var e := ecurie_of(who)
	if e != "":
		_send_info(e)
	for jid in _journees.keys():
		var j: Dictionary = _journees[jid]
		if j["state"] == "open":
			if j["promoter"] == who:
				_cancel(jid, "Le promoteur %s est parti : journée annulée." % who)
			elif who in j["wrestlers"]:
				j["wrestlers"].erase(who)
				_broadcast_info(jid)


func forget(who: String) -> void:
	var e := ecurie_of(who)
	if e != "":
		_remove_member(e, who)


func server_tick(delta: float) -> void:
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 30.0
		if _dirty:
			save_ecuries()
	for jid in _journees.keys():
		var j: Dictionary = _journees[jid]
		j["t"] = float(j["t"]) + delta
		if j["state"] == "open" and float(j["t"]) > OPEN_TIMEOUT:
			_cancel(jid, "Journée de %s annulée : pas lancée à temps (caution rendue)." % j["promoter"])
		elif j["state"] == "running" and float(j.get("wait", -1.0)) >= 0.0:
			j["wait"] = float(j["wait"]) - delta
			if float(j["wait"]) < 0.0:
				j["wait"] = -1.0
				_next_bout(jid)


# =====================================================================================
# Écuries
# =====================================================================================

@rpc("any_peer", "reliable")
func rpc_ecurie_create(ename: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "":
		return
	ename = ename.strip_edges().left(24)
	var taken := false
	for n in _ecuries:
		if String(n).to_lower() == ename.to_lower():
			taken = true
	if ecurie_of(who) != "" or ename.length() < 3 or taken:
		_pay(who, CREATE_FEE, "Frais d'écurie remboursés")
		net.rpc_notice.rpc_id(id, "Impossible de fonder cette écurie (nom pris, trop court, ou tu es déjà dans une écurie).")
		return
	_ecuries[ename] = {"owner": who, "members": [who], "color": COLORS[_ecuries.size() % COLORS.size()], "w": 0, "l": 0}
	_dirty = true
	_send_info(ename)
	for other in net._sessions:
		net.rpc_notice.rpc_id(other, "%s fonde l'écurie de lutte « %s » !" % [who, ename])


@rpc("any_peer", "reliable")
func rpc_ecurie_join(ename: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "" or not _ecuries.has(ename) or ecurie_of(who) != "":
		return
	var e: Dictionary = _ecuries[ename]
	if e["members"].size() >= MAX_MEMBERS:
		net.rpc_notice.rpc_id(id, "L'écurie « %s » est complète." % ename)
		return
	e["members"].append(who)
	_dirty = true
	_send_info(ename)
	var owner_id := _id_of(e["owner"])
	if owner_id != -1 and owner_id != id:
		net.rpc_notice.rpc_id(owner_id, "%s rejoint ton écurie « %s »." % [who, ename])


@rpc("any_peer", "reliable")
func rpc_ecurie_leave() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	var e := ecurie_of(who)
	if e == "":
		return
	_remove_member(e, who)
	rpc_ecurie_info.rpc_id(id, "", [], 0, 0)


func _remove_member(e: String, who: String) -> void:
	var ec: Dictionary = _ecuries[e]
	ec["members"].erase(who)
	if ec["members"].is_empty():
		_ecuries.erase(e)
	else:
		if ec["owner"] == who:
			ec["owner"] = ec["members"][0] # le plus ancien membre devient chef
		_send_info(e)
	_dirty = true


@rpc("any_peer", "reliable")
func rpc_ecurie_list_req() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var list: Array = []
	for n in _ecuries:
		var e: Dictionary = _ecuries[n]
		list.append([n, e["owner"], e["members"].size(), int(e["w"]), int(e["l"])])
	list.sort_custom(func(a, b): return a[3] > b[3])
	rpc_ecurie_list.rpc_id(id, list.slice(0, 30))


func _send_info(e: String) -> void:
	if not _ecuries.has(e):
		return
	var ec: Dictionary = _ecuries[e]
	var members: Array = []
	for m in ec["members"]:
		members.append([m, _id_of(m) != -1, m == ec["owner"]])
	for m in ec["members"]:
		var mid := _id_of(m)
		if mid != -1:
			rpc_ecurie_info.rpc_id(mid, e, members, int(ec["w"]), int(ec["l"]))


@rpc("authority", "reliable")
func rpc_ecurie_info(ename: String, members: Array, w: int, l: int) -> void:
	my_ecurie = ename
	my_members = members
	my_record = Vector2i(w, l)
	ecurie_changed.emit()


@rpc("authority", "reliable")
func rpc_ecurie_list(list: Array) -> void:
	ecurie_list_received.emit(list)


# =====================================================================================
# Journées de lutte entre joueurs
# =====================================================================================

## (joueur) Annonce une journée : la caution est payée ici, le serveur la garde
func announce(venue: String, pos: Vector3, cachet: int, size: int) -> bool:
	var escrow := escrow_for(cachet, size)
	if not net.online or not GameState.spend(escrow):
		return false
	rpc_journee_announce.rpc_id(1, venue, pos.x, pos.z, cachet, size)
	return true


@rpc("any_peer", "reliable")
func rpc_journee_announce(venue: String, x: float, z: float, cachet: int, size: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "":
		return
	var busy := false
	for jid in _journees:
		if _journees[jid]["promoter"] == who:
			busy = true
	if busy or not venue in ["medina", "arene"] or not cachet in CACHETS or not size in SIZES:
		_pay(who, escrow_for(cachet, size) if cachet in CACHETS and size in SIZES else 0, "Caution de journée remboursée")
		net.rpc_notice.rpc_id(id, "Tu organises déjà une journée (ou réglages invalides).")
		return
	var jid := _next_jid
	_next_jid += 1
	_journees[jid] = {"promoter": who, "venue": venue, "pos": Vector3(x, 0, z), "cachet": cachet, "max": size,
		"escrow": escrow_for(cachet, size), "wrestlers": [], "state": "open", "t": 0.0, "queue": [], "paid": 0,
		"bouts": 0, "spectators": 0, "wait": -1.0}
	_broadcast_info(jid)
	for other in net._sessions:
		if other != id:
			net.rpc_notice.rpc_id(other, "%s organise une journée de lutte (cachet %d FCFA). Inscris-toi : téléphone → Lutte." % [who, cachet])


@rpc("any_peer", "reliable")
func rpc_journee_register(jid: int, on: bool) -> void:
	if not net.is_server or not _journees.has(jid):
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	var j: Dictionary = _journees[jid]
	if who == "" or j["state"] != "open" or who == j["promoter"]:
		return
	if on and not who in j["wrestlers"] and j["wrestlers"].size() < int(j["max"]):
		j["wrestlers"].append(who)
		var pid := _id_of(j["promoter"])
		if pid != -1:
			net.rpc_notice.rpc_id(pid, "%s s'inscrit à ta journée de lutte (%d/%d)." % [who, j["wrestlers"].size(), j["max"]])
	elif not on:
		j["wrestlers"].erase(who)
	_broadcast_info(jid)


@rpc("any_peer", "reliable")
func rpc_journee_cancel(jid: int) -> void:
	if not net.is_server or not _journees.has(jid):
		return
	var who: String = net._sessions.get(multiplayer.get_remote_sender_id(), "")
	var j: Dictionary = _journees[jid]
	if who == j["promoter"] and j["state"] == "open":
		_cancel(jid, "%s annule sa journée de lutte." % who)


func _cancel(jid: int, text: String) -> void:
	var j: Dictionary = _journees[jid]
	_pay(j["promoter"], int(j["escrow"]), "Caution de journée de lutte rendue")
	_journees.erase(jid)
	for other in net._sessions:
		rpc_journee_end.rpc_id(other, jid, text)


@rpc("any_peer", "reliable")
func rpc_journee_start(jid: int) -> void:
	if not net.is_server or not _journees.has(jid):
		return
	var id := multiplayer.get_remote_sender_id()
	var j: Dictionary = _journees[jid]
	if net._sessions.get(id, "") != j["promoter"] or j["state"] != "open":
		return
	if j["wrestlers"].size() < 2:
		net.rpc_notice.rpc_id(id, "Il faut au moins deux lutteurs inscrits.")
		return
	j["state"] = "running"
	var w: Array = j["wrestlers"].duplicate()
	var queue: Array = []
	for k in range(0, w.size() - 1, 2):
		queue.append([w[k], w[k + 1]])
	j["queue"] = queue
	# Spectateurs : les joueurs présents autour du stade (hors lutteurs et promoteur)
	var n := 0
	for pid in net._sessions:
		var who: String = net._sessions[pid]
		if who in w or who == j["promoter"]:
			continue
		var p: Vector3 = net._pos.get(pid, Vector3(INF, 0, INF))
		if Vector2(p.x - j["pos"].x, p.z - j["pos"].z).length() < SPECTATOR_RANGE:
			n += 1
	j["spectators"] = n
	_broadcast_info(jid)
	_next_bout(jid)


func _near_venue(id: int, j: Dictionary) -> bool:
	var p: Vector3 = net._pos.get(id, Vector3(INF, 0, INF))
	return Vector2(p.x - j["pos"].x, p.z - j["pos"].z).length() < VENUE_RANGE


func _next_bout(jid: int) -> void:
	if not _journees.has(jid):
		return
	var j: Dictionary = _journees[jid]
	while not j["queue"].is_empty():
		var pair: Array = j["queue"].pop_front()
		var ia := _id_of(pair[0])
		var ib := _id_of(pair[1])
		var a_ok: bool = ia != -1 and _near_venue(ia, j) and not net.social._duel_of.has(ia)
		var b_ok: bool = ib != -1 and _near_venue(ib, j) and not net.social._duel_of.has(ib)
		if a_ok and b_ok:
			rpc_journee_call.rpc_id(ia, jid, j["pos"].x, j["pos"].z, 0)
			rpc_journee_call.rpc_id(ib, jid, j["pos"].x, j["pos"].z, 1)
			net.social.start_bout(ia, ib, jid)
			return
		if a_ok != b_ok:
			# L'autre n'est pas au stade : victoire par forfait
			_settle(jid, pair[0] if a_ok else pair[1], pair[1] if a_ok else pair[0], true)
	_end_journee(jid)


## Appelé par social.gd à la fin d'un combat de journée
func on_bout_end(jid: int, winner: String, loser: String) -> void:
	if not _journees.has(jid):
		return
	_settle(jid, winner, loser, false)
	_journees[jid]["wait"] = 5.0 # le temps de se relever, puis combat suivant


func _settle(jid: int, winner: String, loser: String, forfeit: bool) -> void:
	var j: Dictionary = _journees[jid]
	var cachet: int = j["cachet"]
	var win_pay := cachet + int(cachet * PRIME)
	var lose_pay := 0 if forfeit else cachet
	_pay(winner, win_pay, "Cachet + prime de victoire (journée de %s)" % j["promoter"])
	_pay(loser, lose_pay, "Cachet de lutte (journée de %s)" % j["promoter"])
	j["paid"] = int(j["paid"]) + win_pay + lose_pay
	j["bouts"] = int(j["bouts"]) + 1
	# Écuries : bilan et commission du chef (versée en plus par le serveur)
	for pair in [[winner, win_pay, true], [loser, lose_pay, false]]:
		var e := ecurie_of(pair[0])
		if e == "":
			continue
		var ec: Dictionary = _ecuries[e]
		ec["w" if pair[2] else "l"] = int(ec["w" if pair[2] else "l"]) + 1
		if ec["owner"] != pair[0]:
			_pay(ec["owner"], int(pair[1] * COMMISSION), "Commission d'écurie sur le cachet de %s" % pair[0])
		_dirty = true
		_send_info(e)
	for pid in net._sessions:
		var p: Vector3 = net._pos.get(pid, Vector3(INF, 0, INF))
		var who: String = net._sessions[pid]
		if who == j["promoter"] or who == winner or who == loser or Vector2(p.x - j["pos"].x, p.z - j["pos"].z).length() < 400.0:
			rpc_journee_result.rpc_id(pid, jid, winner, loser, forfeit)


func _end_journee(jid: int) -> void:
	var j: Dictionary = _journees[jid]
	var rest: int = maxi(0, int(j["escrow"]) - int(j["paid"]))
	var gate: int = int(j["spectators"]) * TICKET + int(j["bouts"]) * 2000
	_pay(j["promoter"], rest + gate, "Bilan de ta journée : caution restante + billetterie")
	var text := "Fin de la journée de lutte de %s : %d combat(s), %d spectateur(s)." % [j["promoter"], j["bouts"], j["spectators"]]
	_journees.erase(jid)
	for other in net._sessions:
		rpc_journee_end.rpc_id(other, jid, text)


func _broadcast_info(jid: int) -> void:
	var j: Dictionary = _journees[jid]
	for other in net._sessions:
		rpc_journee_info.rpc_id(other, jid, j["promoter"], j["venue"], j["cachet"], j["max"], j["wrestlers"], j["state"], j["pos"].x, j["pos"].z)


@rpc("authority", "reliable")
func rpc_journee_info(jid: int, promoter: String, venue: String, cachet: int, size: int, names: Array, state: String, x: float, z: float) -> void:
	journees[jid] = {"promoter": promoter, "venue": venue, "cachet": cachet, "max": size, "names": names, "state": state, "pos": Vector3(x, 0, z)}
	journees_changed.emit()


@rpc("authority", "reliable")
func rpc_journee_call(jid: int, x: float, z: float, side: int) -> void:
	journee_called.emit(jid, Vector3(x, 0, z), side)


@rpc("authority", "reliable")
func rpc_journee_result(jid: int, winner: String, loser: String, forfeit: bool) -> void:
	journee_bout.emit(jid, winner, loser, forfeit)


@rpc("authority", "reliable")
func rpc_journee_end(jid: int, text: String) -> void:
	journees.erase(jid)
	journees_changed.emit()
	journee_ended.emit(jid, text)
