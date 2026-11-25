extends Node
## Échanges entre joueurs, nœud « Echanges » enfant de Net (même chemin sur le serveur et chez les joueurs).
## Un joueur propose un échange à un joueur proche ; s'il accepte, chacun compose son offre (argent liquide,
## objets du sac, véhicules, maisons et commerces avec leurs employés) et voit celle de l'autre en direct.
## Une maison ou un commerce change aussi de nom dans le registre du serveur (net_properties.gd). Toute modification annule les validations.
## Quand les deux ont validé, l'échange se fait en deux temps pour que rien ne se perde :
##   1. le serveur demande à chacun de mettre son offre de côté (rpc_escrow) : le joueur vérifie qu'il a
##      encore tout, le retire de sa partie et répond (rpc_escrowed) ;
##   2. si les deux ont pu, chacun reçoit l'offre de l'autre (rpc_complete) ; sinon, celui qui avait déjà
##      mis de côté récupère son offre (rpc_refund).
## Un nœud à part, comme les émotes : les versions 1.20 et avant ne le connaissent pas, le serveur ne leur
## propose rien tant qu'elles n'ont pas dit bonjour (rpc_hello).

signal invited(tid: int, from: String)
signal opened(tid: int, other: String)
signal their_offer_changed(offer: Dictionary)
signal locks_changed(mine: bool, theirs: bool)
signal closed(message: String)
signal mine_changed

const Dealership = preload("res://scripts/vehicles/dealership.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")

const RANGE := 6.0 ## pour proposer un échange
const BREAK_RANGE := 15.0 ## l'échange s'annule si les joueurs s'éloignent
const INVITE_TIMEOUT := 30.0
const MAX_MONEY := 10000000
const MAX_ITEMS := 12 ## sortes d'objets par offre
const MAX_VEHICLES := 2
const MAX_PROPERTIES := 2
const MAX_OWNED := 4 ## comme dealership.gd
const ESCROW_TIMEOUT := 10.0

var net
var main ## (joueur) donné par trade_ui.gd : logements (housing.gd) et concession
var trade_id := -1 ## (joueur) échange en cours
var other_name := ""
var my_offer := _empty() ## vehicles : indices dans GameState.vehicles ; properties : ids des biens
var their_offer := _empty() ## vehicles : fiches des véhicules ; properties : [{id, biz}]
var my_lock := false
var their_lock := false
var _escrowed := {} ## (joueur) offre retirée de la partie, en attente de la fin de l'échange
var _capable := {} ## (serveur) joueurs qui connaissent les échanges
var _trades := {} ## (serveur) tid → {a, b, open, offers {id: offre}, locks {id: bool}, escrow {id: bool}, t}
var _busy := {} ## (serveur) id → tid
var _next := 1
var _check_t := 1.0


static func _empty() -> Dictionary:
	return {"money": 0, "items": {}, "vehicles": [], "properties": []}


func hello() -> void:
	if net.online:
		rpc_hello.rpc_id(1)


@rpc("any_peer", "reliable")
func rpc_hello() -> void:
	if net.is_server:
		_capable[multiplayer.get_remote_sender_id()] = true


func forget(id: int, who := "") -> void:
	_capable.erase(id)
	if _busy.has(id):
		_cancel(int(_busy[id]), "%s s'est déconnecté : échange annulé." % (who if who != "" else "L'autre joueur"))


func in_trade() -> bool:
	return trade_id >= 0


# ---------------------------------------------------------------- joueur

## Proposer un échange au joueur proche (identifiant de pair)
func propose(target: int) -> void:
	if net.online and not in_trade():
		rpc_request.rpc_id(1, target)


func accept(tid: int) -> void:
	rpc_accept.rpc_id(1, tid)


func decline(tid: int) -> void:
	rpc_cancel.rpc_id(1, tid)


func cancel() -> void:
	if in_trade():
		rpc_cancel.rpc_id(1, trade_id)


## Offre à envoyer : les véhicules partent en fiches (type, couleur, essence...) pour que l'autre les voie
func _wire_offer() -> Dictionary:
	var vh: Array = []
	for i in my_offer["vehicles"]:
		if i < GameState.vehicles.size():
			vh.append(GameState.vehicles[i])
	var props: Array = []
	for pid in my_offer["properties"]:
		props.append({"id": pid, "biz": GameState.home.get("biz", {}).get(pid, {})})
	return {"money": my_offer["money"], "items": my_offer["items"], "vehicles": vh, "properties": props}


func set_money(amount: int) -> void:
	my_offer["money"] = clampi(amount, 0, mini(GameState.money, MAX_MONEY))
	_push()


func add_item(item: String, delta: int) -> void:
	var have := int(GameState.inventory.get(item, 0))
	var n := clampi(int(my_offer["items"].get(item, 0)) + delta, 0, have)
	if n == 0:
		my_offer["items"].erase(item)
	elif my_offer["items"].has(item) or my_offer["items"].size() < MAX_ITEMS:
		my_offer["items"][item] = n
	_push()


func toggle_vehicle(idx: int) -> void:
	if idx in my_offer["vehicles"]:
		my_offer["vehicles"].erase(idx)
	elif my_offer["vehicles"].size() < MAX_VEHICLES:
		my_offer["vehicles"].append(idx)
	_push()


func toggle_property(pid: String) -> void:
	if pid in my_offer["properties"]:
		my_offer["properties"].erase(pid)
	elif my_offer["properties"].size() < MAX_PROPERTIES:
		my_offer["properties"].append(pid)
	_push()


func _push() -> void:
	mine_changed.emit()
	if in_trade():
		rpc_offer.rpc_id(1, trade_id, _wire_offer())


func lock() -> void:
	if in_trade():
		rpc_lock.rpc_id(1, trade_id)


## Véhicule utilisable dans un échange : ni en fourrière, ni sorti en ville, ni en location
func vehicle_tradable(idx: int, main) -> bool:
	if idx < 0 or idx >= GameState.vehicles.size():
		return false
	var v: Dictionary = GameState.vehicles[idx]
	if v.get("impound", false):
		return false
	return not (main.dealership.out != null and is_instance_valid(main.dealership.out) and main.dealership._out_idx == idx)


@rpc("authority", "reliable")
func rpc_invited(tid: int, from: String) -> void:
	invited.emit(tid, from)


@rpc("authority", "reliable")
func rpc_open(tid: int, other: String) -> void:
	trade_id = tid
	other_name = other
	my_offer = _empty()
	their_offer = _empty()
	my_lock = false
	their_lock = false
	opened.emit(tid, other)


@rpc("authority", "reliable")
func rpc_their_offer(offer: Dictionary) -> void:
	their_offer = offer
	their_offer_changed.emit(offer)


@rpc("authority", "reliable")
func rpc_locks(mine: bool, theirs: bool) -> void:
	my_lock = mine
	their_lock = theirs
	locks_changed.emit(mine, theirs)


## Étape 1 : mettre son offre de côté (vérifiée une dernière fois)
@rpc("authority", "reliable")
func rpc_escrow(tid: int, incoming_vehicles: int) -> void:
	if tid != trade_id:
		return
	var ok: bool = int(my_offer["money"]) <= GameState.money
	for item in my_offer["items"]:
		if int(GameState.inventory.get(item, 0)) < int(my_offer["items"][item]):
			ok = false
	for i in my_offer["vehicles"]:
		if i >= GameState.vehicles.size():
			ok = false
	for pid in my_offer["properties"]:
		if main == null or main.housing == null or main.housing.trade_block(pid) != "":
			ok = false
	var after: int = GameState.vehicles.size() - my_offer["vehicles"].size() + incoming_vehicles
	var full: bool = incoming_vehicles > 0 and after > MAX_OWNED
	if not ok or full:
		rpc_escrowed.rpc_id(1, tid, false, "pas de place au garage (4 véhicules au plus)" if full else "")
		return
	var give := _wire_offer().duplicate(true)
	GameState.money -= int(give["money"])
	for item in give["items"]:
		GameState.inventory[item] = int(GameState.inventory[item]) - int(give["items"][item])
		if GameState.inventory[item] <= 0:
			GameState.inventory.erase(item)
	var idx: Array = my_offer["vehicles"].duplicate()
	idx.sort()
	idx.reverse()
	for i in idx:
		GameState.vehicles.remove_at(i)
	for p in give["properties"]:
		p["biz"] = main.housing.give_away(p["id"])
	_escrowed = give
	rpc_escrowed.rpc_id(1, tid, true, "")


## Étape 2 : l'échange est fait, on reçoit l'offre de l'autre
@rpc("authority", "reliable")
func rpc_complete(tid: int, got: Dictionary) -> void:
	if tid != trade_id:
		return
	_escrowed = {}
	var parts: Array = []
	var money := clampi(int(got.get("money", 0)), 0, MAX_MONEY)
	if money > 0:
		GameState.money += money
		parts.append(GameState.fcfa(money))
	var items = got.get("items", {})
	if items is Dictionary:
		for item in items:
			var n := clampi(int(items[item]), 0, 999)
			if n > 0:
				GameState.add_item(str(item).left(48), n)
				parts.append("%d × %s" % [n, item])
	var vh = got.get("vehicles", [])
	if vh is Array:
		for v in vh.slice(0, MAX_VEHICLES):
			if v is Dictionary and str(v.get("type", "")) != "":
				var car: Dictionary = v.duplicate()
				car.erase("impound")
				GameState.vehicles.append(car)
				var vt := str(car.get("type", ""))
				parts.append((Dealership.CATALOG[vt][0] if Dealership.CATALOG.has(vt) else Vehicle.TYPES.get(vt, {"name": vt})["name"]).to_lower())
	var props = got.get("properties", [])
	if props is Array and main and main.housing:
		for p in props.slice(0, MAX_PROPERTIES):
			if p is Dictionary and main.housing.PROPERTIES.has(str(p.get("id", ""))):
				var b = p.get("biz", {})
				main.housing.take(str(p["id"]), b if b is Dictionary else {})
				parts.append(main.housing.PROPERTIES[str(p["id"])]["name"])
	_end()
	GameState.save_game()
	Audio.play_sfx("coin", -8.0)
	closed.emit("Échange fait avec %s. Tu reçois : %s." % [other_name, ", ".join(parts) if not parts.is_empty() else "rien"])


## L'échange n'a pas pu se faire : on récupère ce qu'on avait mis de côté
@rpc("authority", "reliable")
func rpc_refund(tid: int, message: String) -> void:
	if trade_id >= 0 and tid != trade_id:
		return
	_restore()
	_end()
	closed.emit(message)


func _restore() -> void:
	if _escrowed.is_empty():
		return
	GameState.money += int(_escrowed["money"])
	for item in _escrowed["items"]:
		GameState.add_item(item, int(_escrowed["items"][item]))
	for v in _escrowed["vehicles"]:
		GameState.vehicles.append(v)
	for p in _escrowed.get("properties", []):
		if main and main.housing:
			main.housing.take(p["id"], p["biz"])
	_escrowed = {}
	GameState.save_game()


func _end() -> void:
	trade_id = -1
	my_lock = false
	their_lock = false


# ---------------------------------------------------------------- serveur

func _other(t: Dictionary, id: int) -> int:
	return int(t["b"]) if id == int(t["a"]) else int(t["a"])


func _near(a: int, b: int, dist: float) -> bool:
	return net._pos.has(a) and net._pos.has(b) and Vector3(net._pos[a]).distance_to(net._pos[b]) <= dist


@rpc("any_peer", "reliable")
func rpc_request(target: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id) or not net._sessions.has(target) or id == target:
		return
	if not _capable.has(target):
		net.rpc_notice.rpc_id(id, "%s doit mettre à jour le jeu pour faire des échanges." % net._sessions[target])
		return
	if _busy.has(id) or _busy.has(target):
		net.rpc_notice.rpc_id(id, "%s est déjà en train d'échanger." % net._sessions[target])
		return
	if not _near(id, target, RANGE):
		net.rpc_notice.rpc_id(id, "Rapproche-toi de %s pour échanger." % net._sessions[target])
		return
	var tid := _next
	_next += 1
	_trades[tid] = {"a": id, "b": target, "open": false, "offers": {}, "locks": {}, "escrow": {}, "t": 0.0}
	_busy[id] = tid
	_busy[target] = tid
	rpc_invited.rpc_id(target, tid, net._sessions[id])
	net.rpc_notice.rpc_id(id, "Proposition d'échange envoyée à %s..." % net._sessions[target])


@rpc("any_peer", "reliable")
func rpc_accept(tid: int) -> void:
	if not net.is_server or not _trades.has(tid):
		return
	var t: Dictionary = _trades[tid]
	var id := multiplayer.get_remote_sender_id()
	if id != int(t["b"]) or t["open"]:
		return
	t["open"] = true
	var a := int(t["a"])
	var b := int(t["b"])
	t["offers"] = {a: _empty(), b: _empty()}
	t["locks"] = {a: false, b: false}
	rpc_open.rpc_id(a, tid, net._sessions[b])
	rpc_open.rpc_id(b, tid, net._sessions[a])


@rpc("any_peer", "reliable")
func rpc_cancel(tid: int) -> void:
	if not net.is_server or not _trades.has(tid):
		return
	var t: Dictionary = _trades[tid]
	var id := multiplayer.get_remote_sender_id()
	if id != int(t["a"]) and id != int(t["b"]):
		return
	if not t["escrow"].is_empty():
		return # l'échange est déjà en cours d'exécution
	_cancel(tid, "%s a annulé l'échange." % net._sessions.get(id, "L'autre joueur"))


## Offre reçue : nettoyée, gardée, envoyée à l'autre ; les validations sont remises à zéro
@rpc("any_peer", "reliable")
func rpc_offer(tid: int, offer: Dictionary) -> void:
	if not net.is_server or not _trades.has(tid):
		return
	var t: Dictionary = _trades[tid]
	var id := multiplayer.get_remote_sender_id()
	if (id != int(t["a"]) and id != int(t["b"])) or not t["open"] or not t["escrow"].is_empty():
		return
	var clean := _empty()
	clean["money"] = clampi(int(offer.get("money", 0)), 0, MAX_MONEY)
	var items = offer.get("items", {})
	if items is Dictionary:
		for item in items:
			if clean["items"].size() < MAX_ITEMS:
				var n := clampi(int(items[item]), 0, 999)
				if n > 0:
					clean["items"][str(item).left(48)] = n
	var vh = offer.get("vehicles", [])
	if vh is Array:
		for v in vh.slice(0, MAX_VEHICLES):
			if v is Dictionary:
				var car := {}
				for k in v:
					if str(k).length() <= 16 and (v[k] is String or v[k] is float or v[k] is int or v[k] is bool):
						car[str(k)] = v[k] if not v[k] is String else str(v[k]).left(32)
				clean["vehicles"].append(car)
	# Maisons et commerces : seulement ceux que le registre du serveur donne à ce joueur
	var props = offer.get("properties", [])
	if props is Array:
		for p in props.slice(0, MAX_PROPERTIES):
			if p is Dictionary:
				var pid := str(p.get("id", ""))
				var b = p.get("biz", {})
				if net.properties.exclusive(pid) and net.properties.owner_of(pid) == net._sessions[id] and (not b is Dictionary or JSON.stringify(b).length() < 8000):
					clean["properties"].append({"id": pid, "biz": b if b is Dictionary else {}})
	t["offers"][id] = clean
	t["locks"] = {int(t["a"]): false, int(t["b"]): false}
	rpc_their_offer.rpc_id(_other(t, id), clean)
	_send_locks(t)


@rpc("any_peer", "reliable")
func rpc_lock(tid: int) -> void:
	if not net.is_server or not _trades.has(tid):
		return
	var t: Dictionary = _trades[tid]
	var id := multiplayer.get_remote_sender_id()
	if (id != int(t["a"]) and id != int(t["b"])) or not t["open"] or not t["escrow"].is_empty():
		return
	t["locks"][id] = true
	_send_locks(t)
	if t["locks"][int(t["a"])] and t["locks"][int(t["b"])]:
		# Étape 1 : chacun met son offre de côté
		for p in [int(t["a"]), int(t["b"])]:
			var incoming: int = t["offers"][_other(t, p)]["vehicles"].size()
			rpc_escrow.rpc_id(p, tid, incoming)
		t["escrow"] = {"pending": true}
		t["t"] = 0.0


@rpc("any_peer", "reliable")
func rpc_escrowed(tid: int, ok: bool, why: String) -> void:
	if not net.is_server or not _trades.has(tid):
		return
	var t: Dictionary = _trades[tid]
	var id := multiplayer.get_remote_sender_id()
	if id != int(t["a"]) and id != int(t["b"]):
		return
	t["escrow"].erase("pending")
	t["escrow"][id] = ok
	if not ok:
		var who: String = net._sessions.get(id, "?")
		_cancel(tid, "Échange impossible : %s." % (("%s n'a %s" % [who, why]) if why != "" else "%s n'a plus tout ce qu'il proposait" % who))
		return
	if t["escrow"].has(int(t["a"])) and t["escrow"].has(int(t["b"])):
		# Étape 2 : chacun reçoit l'offre de l'autre
		var a := int(t["a"])
		var b := int(t["b"])
		for p in [a, b]:
			for prop in t["offers"][p]["properties"]:
				net.properties.transfer(prop["id"], net._sessions.get(_other(t, p), ""))
		rpc_complete.rpc_id(a, tid, t["offers"][b])
		rpc_complete.rpc_id(b, tid, t["offers"][a])
		print("Échange : %s ↔ %s (%s / %s)" % [net._sessions.get(a, "?"), net._sessions.get(b, "?"), JSON.stringify(t["offers"][a]).left(200), JSON.stringify(t["offers"][b]).left(200)])
		_close(tid)


func _send_locks(t: Dictionary) -> void:
	var a := int(t["a"])
	var b := int(t["b"])
	rpc_locks.rpc_id(a, t["locks"].get(a, false), t["locks"].get(b, false))
	rpc_locks.rpc_id(b, t["locks"].get(b, false), t["locks"].get(a, false))


## Annule : ceux qui avaient déjà mis de côté récupèrent leur offre (rpc_refund le fait chez tous)
func _cancel(tid: int, message: String) -> void:
	var t: Dictionary = _trades.get(tid, {})
	for p in [int(t.get("a", -1)), int(t.get("b", -1))]:
		if net._sessions.has(p):
			rpc_refund.rpc_id(p, tid, message)
	_close(tid)


func _close(tid: int) -> void:
	var t: Dictionary = _trades.get(tid, {})
	_busy.erase(int(t.get("a", -1)))
	_busy.erase(int(t.get("b", -1)))
	_trades.erase(tid)


func _process(delta: float) -> void:
	if net == null or not net.is_server or _trades.is_empty():
		return
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 1.0
	for tid in _trades.keys():
		var t: Dictionary = _trades[tid]
		t["t"] = float(t["t"]) + 1.0
		if not t["open"] and t["t"] > INVITE_TIMEOUT:
			_cancel(tid, "Pas de réponse : proposition d'échange annulée.")
		elif t["escrow"].is_empty() and not _near(int(t["a"]), int(t["b"]), BREAK_RANGE):
			_cancel(tid, "Vous vous êtes éloignés : échange annulé.")
		elif not t["escrow"].is_empty() and t["t"] > ESCROW_TIMEOUT:
			_cancel(tid, "L'échange n'a pas abouti : chacun récupère son offre.")
