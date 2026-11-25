extends Node
## Propriétés en ligne, nœud « Proprietes » enfant de Net (même chemin sur le serveur et chez les joueurs).
## Chaque maison ou commerce à vendre (housing.gd) n'a qu'un seul propriétaire dans tout Dakar :
## le serveur tient le registre (id → pseudo), l'enregistre dans user://server_properties.json
## et l'envoie aux joueurs ; les panneaux affichent « PROPRIÉTÉ DE ... ».
## Les chambres en location ne sont pas exclusives (maison familiale à plusieurs locataires).
## Un nœud à part, comme les émotes : les versions 1.19 et avant ne le connaissent pas.

signal changed ## registre reçu ou modifié
signal claim_result(pid: String, ok: bool, owner: String)

const PATH := "user://server_properties.json"
const Housing = preload("res://scripts/world/housing.gd")

var net
var owners := {} ## id de propriété → pseudo du propriétaire
var _capable := {} ## (serveur) joueurs qui connaissent les propriétés


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		_load()


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary:
		for pid in data:
			if Housing.PROPERTIES.has(pid):
				owners[pid] = str(data[pid])


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(owners))


static func exclusive(pid: String) -> bool:
	return Housing.PROPERTIES.has(pid) and int(Housing.PROPERTIES[pid]["price"]) > 0


func owner_of(pid: String) -> String:
	return str(owners.get(pid, ""))


## (joueur) à la connexion : les propriétés déjà achetées sont inscrites au registre si elles sont libres
func hello() -> void:
	if net.online:
		rpc_hello.rpc_id(1, GameState.home.get("owned", []))


func forget(id: int) -> void:
	_capable.erase(id)


## (serveur) compte supprimé : ses propriétés redeviennent à vendre
func forget_account(who: String) -> void:
	for pid in owners.keys():
		if owners[pid] == who:
			owners.erase(pid)
			_broadcast(pid, "")
	_save()


@rpc("any_peer", "reliable")
func rpc_hello(owned: Array) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "":
		return
	_capable[id] = true
	var dirty := false
	for pid in owned.slice(0, 20):
		pid = str(pid)
		if exclusive(pid) and not owners.has(pid):
			owners[pid] = who
			_broadcast(pid, who)
			dirty = true
	if dirty:
		_save()
	rpc_owners.rpc_id(id, owners)


## (joueur) demande d'achat : le serveur réserve la propriété si elle est libre
func claim(pid: String) -> void:
	if net.online:
		rpc_claim.rpc_id(1, pid)


## (joueur) revente : la propriété redevient à vendre
func release(pid: String) -> void:
	if net.online:
		rpc_release.rpc_id(1, pid)


@rpc("any_peer", "reliable")
func rpc_claim(pid: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "" or not exclusive(pid):
		return
	var cur := owner_of(pid)
	if cur != "" and cur != who:
		rpc_claim_answer.rpc_id(id, pid, false, cur)
		return
	owners[pid] = who
	_save()
	_broadcast(pid, who)
	rpc_claim_answer.rpc_id(id, pid, true, who)
	print("Propriété : %s achetée par %s" % [pid, who])


@rpc("any_peer", "reliable")
func rpc_release(pid: String) -> void:
	if not net.is_server:
		return
	var who: String = net._sessions.get(multiplayer.get_remote_sender_id(), "")
	if who != "" and owner_of(pid) == who:
		owners.erase(pid)
		_save()
		_broadcast(pid, "")


## (serveur) échange entre joueurs : le bien passe à un autre propriétaire
func transfer(pid: String, who: String) -> void:
	if exclusive(pid):
		owners[pid] = who
		_save()
		_broadcast(pid, who)
		print("Propriété : %s cédée à %s" % [pid, who])


func _broadcast(pid: String, who: String) -> void:
	for other in _capable:
		if net._sessions.has(other):
			rpc_owner.rpc_id(other, pid, who)


@rpc("authority", "reliable")
func rpc_owners(full: Dictionary) -> void:
	owners = full
	changed.emit()


@rpc("authority", "reliable")
func rpc_owner(pid: String, who: String) -> void:
	if who == "":
		owners.erase(pid)
	else:
		owners[pid] = who
	changed.emit()


@rpc("authority", "reliable")
func rpc_claim_answer(pid: String, ok: bool, who: String) -> void:
	if ok:
		owners[pid] = who
	claim_result.emit(pid, ok, who)
