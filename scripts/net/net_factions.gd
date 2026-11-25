extends Node
## Factions en ligne côté réseau, nœud « Factions » enfant de Net (même chemin sur le serveur et chez
## les joueurs). Un nœud à part, comme les émotes : les versions 1.19 et avant ne l'ont pas, le serveur
## ne leur envoie rien tant qu'elles n'ont pas dit bonjour (rpc_hello).
## - Récompenses de faction (expérience pour le grade + argent) : arrestations, soins.
## - SAMU : un joueur tombé à terre (faim, bagarre) le signale ; les secouristes en service le voient
##   sur leur GPS et le relèvent sur place (le serveur vérifie le métier et la distance).
## Les règles des factions (grades, salaires) sont dans factions.gd.

signal patient(id: int, who: String, pos: Vector3, down: bool) ## (SAMU en service) joueur à terre ou relevé
signal healed(medic: String) ## (joueur à terre) relevé par un secouriste
signal reward_received(xp: int, amount: int, reason: String)

const HEAL_RANGE := 8.0
const HEAL_PAY := 1500

var net
var _capable := {} ## (serveur) joueurs qui connaissent les factions
var _down := {} ## (serveur) joueurs à terre : id → horloge de la chute


## (joueur) à la connexion
func hello() -> void:
	if net.online:
		rpc_hello.rpc_id(1)


func forget(id: int) -> void:
	_capable.erase(id)
	if _down.has(id):
		_set_down(id, false)


@rpc("any_peer", "reliable")
func rpc_hello() -> void:
	if net.is_server:
		_capable[multiplayer.get_remote_sender_id()] = true


# --- Récompenses ---------------------------------------------------------------------------

## (serveur) expérience et argent ; un ancien client ne reçoit que l'argent
func reward(id: int, xp: int, amount: int, reason: String) -> void:
	if _capable.has(id):
		rpc_reward.rpc_id(id, xp, amount, reason)
	else:
		net.rpc_receive_money.rpc_id(id, "Serveur", amount, reason)


@rpc("authority", "reliable")
func rpc_reward(xp: int, amount: int, reason: String) -> void:
	reward_received.emit(xp, amount, reason)


# --- SAMU : joueurs à terre ----------------------------------------------------------------

## (joueur) tombé à terre, ou relevé / parti à l'hôpital
func set_down(on: bool) -> void:
	if net.online:
		rpc_down.rpc_id(1, on)


## (secouriste) relever un joueur à terre
func heal(target: int) -> void:
	if net.online:
		rpc_heal.rpc_id(1, target)


@rpc("any_peer", "reliable")
func rpc_down(on: bool) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if net._sessions.has(id) and on != _down.has(id):
		_set_down(id, on)


func _set_down(id: int, on: bool) -> void:
	if on:
		_down[id] = net.clock()
	else:
		_down.erase(id)
	var p: Vector3 = net._pos.get(id, Vector3.ZERO)
	for other in net._states:
		if other != id and _capable.has(other) and net._states[other].get("job", "") == "samu":
			rpc_patient.rpc_id(other, id, net._sessions.get(id, "?"), p.x, p.z, on)


## (serveur) un secouriste prend son service : il reçoit les joueurs déjà à terre
func on_samu_duty(id: int) -> void:
	if not _capable.has(id):
		return
	for d in _down:
		var p: Vector3 = net._pos.get(d, Vector3.ZERO)
		rpc_patient.rpc_id(id, d, net._sessions.get(d, "?"), p.x, p.z, true)


@rpc("any_peer", "reliable")
func rpc_heal(target: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._states.has(id) or not net._sessions.has(target) or not net._pos.has(target):
		return
	var a: Vector3 = net._pos[id]
	var b: Vector3 = net._pos[target]
	var d := Vector2(a.x - b.x, a.z - b.z).length()
	if net._states[id].get("job", "") != "samu" or not _down.has(target) or d > HEAL_RANGE:
		net.rpc_notice.rpc_id(id, "%s n'a pas besoin de soins (ou est trop loin)." % net._sessions[target])
		return
	_set_down(target, false)
	rpc_healed.rpc_id(target, net._sessions[id])
	reward(id, 2, HEAL_PAY, "Soins à %s" % net._sessions[target])
	print("SAMU : %s relevé par %s" % [net._sessions[target], net._sessions[id]])


@rpc("authority", "reliable")
func rpc_patient(pid: int, who: String, x: float, z: float, on: bool) -> void:
	patient.emit(pid, who, Vector3(x, 0, z), on)


@rpc("authority", "reliable")
func rpc_healed(medic: String) -> void:
	healed.emit(medic)
