extends Node
## Services de la ville en ligne, nœud « Ville » enfant de Net (même chemin sur le serveur et chez les joueurs).
## Un nœud à part, comme les émotes : les versions 1.19 et avant ne le connaissent pas, le serveur ne leur
## envoie rien tant qu'elles n'ont pas dit bonjour (rpc_hello).
## - Banque : virement d'un compte en banque vers celui d'un autre joueur, même absent (il le reçoit à sa
##   prochaine connexion).
## - Mairie : élection du maire tous les ELECTION_DAYS jours (une voix par compte, carte d'identité exigée
##   côté joueur), taxe sur la recette des commerces fixée par le maire, caisse de la ville qui paie le maire.
## - Mécanicien : un joueur mécanicien en service répare et remplit le réservoir du véhicule d'un autre joueur
##   (le serveur vérifie le métier et la distance ; le client servi paie le mécanicien).
## - PV : un policier joueur en service dresse une contravention à un joueur proche (montant plafonné) ;
##   le joueur paie l'amende, le policier touche une prime de faction.
## Tout est gardé dans user://server_city.json.

signal state_changed ## maire, taxe, candidats ou caisse reçus
signal bank_received(from: String, amount: int, note: String)
signal bank_answer(ok: bool, to: String, amount: int, message: String)
signal serviced(mechanic: String, mechanic_id: int)
signal ticketed(cop: String, reason: String, amount: int)

const PATH := "user://server_city.json"
const ELECTION_DAYS := 2.0 ## durée d'un mandat (jours réels)
const MAX_TAX := 20
const MAYOR_PAY := 3000 ## salaire du maire, pris dans la caisse de la ville à chaque paie
const PAY_EVERY := 120.0
const SERVICE_RANGE := 10.0
const MAX_TRANSFER := 5000000
## Contraventions : motif → montant
const TICKETS := {"Excès de vitesse": 5000, "Stationnement gênant": 3000, "Conduite sans permis": 10000,
	"Feu rouge grillé": 5000, "Tapage sur la voie publique": 2000}
const TICKET_RANGE := 8.0

var net
## État de la ville (copie chez les joueurs) : maire, taxe (%), fin du scrutin (heure Unix), candidats {pseudo: voix}, caisse
var state := {"mayor": "", "tax": 5, "end": 0.0, "candidates": {}, "treasury": 0}
var _voters := {} ## (serveur) pseudo → true : a déjà voté à ce scrutin
var _mailbox := {} ## (serveur) pseudo → [[de, montant, note]] : virements en attente
var _capable := {}
var _pay_t := PAY_EVERY
var _dirty := false
var _save_t := 10.0


func _ready() -> void:
	if "--server" in OS.get_cmdline_user_args():
		_load()
		if float(state["end"]) <= 0.0:
			state["end"] = Time.get_unix_time_from_system() + ELECTION_DAYS * 86400.0


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		return
	for k in state:
		if data.has(k):
			state[k] = data[k]
	_voters = data.get("voters", {}) if data.get("voters") is Dictionary else {}
	_mailbox = data.get("mailbox", {}) if data.get("mailbox") is Dictionary else {}


func _save() -> void:
	var data := state.duplicate()
	data["voters"] = _voters
	data["mailbox"] = _mailbox
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	_dirty = false


func hello() -> void:
	if net.online:
		rpc_hello.rpc_id(1)


func forget(id: int) -> void:
	_capable.erase(id)


func forget_account(who: String) -> void:
	_mailbox.erase(who)
	state["candidates"].erase(who)
	if state["mayor"] == who:
		state["mayor"] = ""
	_dirty = true


@rpc("any_peer", "reliable")
func rpc_hello() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "":
		return
	_capable[id] = true
	rpc_state.rpc_id(id, state)
	# Virements reçus pendant l'absence
	for m in _mailbox.get(who, []):
		rpc_bank_in.rpc_id(id, str(m[0]), int(m[1]), str(m[2]))
	if _mailbox.has(who):
		_mailbox.erase(who)
		_dirty = true


@rpc("authority", "reliable")
func rpc_state(s: Dictionary) -> void:
	state = s
	state_changed.emit()


func _broadcast_state() -> void:
	for id in _capable:
		if net._sessions.has(id):
			rpc_state.rpc_id(id, state)
	_dirty = true


# --- Tour du serveur : fin du scrutin, salaire du maire, sauvegarde -------------------------

func server_tick(delta: float) -> void:
	if Time.get_unix_time_from_system() >= float(state["end"]):
		_close_election()
	_pay_t -= delta
	if _pay_t <= 0.0:
		_pay_t = PAY_EVERY
		var mayor: String = state["mayor"]
		var pay := mini(MAYOR_PAY, int(state["treasury"]))
		var id := _peer_of(mayor)
		if pay > 0 and id > 0:
			state["treasury"] = int(state["treasury"]) - pay
			net.rpc_receive_money.rpc_id(id, "Serveur", pay, "Salaire du maire (caisse de la ville)")
			_broadcast_state()
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = 10.0
		if _dirty:
			_save()


func _close_election() -> void:
	var best := ""
	var votes := 0
	var cands: Dictionary = state["candidates"]
	for c in cands:
		if int(cands[c]) > votes:
			votes = int(cands[c])
			best = c
	if best != "":
		state["mayor"] = best
		net._broadcast_chat("Mairie", "%s est élu maire de Dakar avec %d voix !" % [best, votes])
	state["candidates"] = {}
	_voters = {}
	state["end"] = Time.get_unix_time_from_system() + ELECTION_DAYS * 86400.0
	print("Mairie : scrutin clos, maire = %s" % state["mayor"])
	_broadcast_state()


func _peer_of(who: String) -> int:
	if who == "":
		return -1
	for id in net._sessions:
		if net._sessions[id] == who:
			return id
	return -1


# --- Banque --------------------------------------------------------------------------------

## (joueur) virement depuis son compte en banque (déjà débité ; remboursé si le serveur refuse)
func bank_transfer(to: String, amount: int, note: String) -> void:
	if net.online:
		rpc_bank_transfer.rpc_id(1, to, amount, note)


@rpc("any_peer", "reliable")
func rpc_bank_transfer(to: String, amount: int, note: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "":
		return
	to = to.strip_edges()
	note = note.strip_edges().left(40)
	if amount <= 0 or amount > MAX_TRANSFER:
		rpc_bank_ack.rpc_id(id, false, to, amount, "Montant refusé.")
		return
	if to == who or not net._accounts.has(to):
		rpc_bank_ack.rpc_id(id, false, to, amount, "Aucun compte « %s »." % to)
		return
	var pid := _peer_of(to)
	if pid > 0 and _capable.has(pid):
		rpc_bank_in.rpc_id(pid, who, amount, note)
	else:
		var box: Array = _mailbox.get(to, [])
		box.append([who, amount, note])
		_mailbox[to] = box
		_dirty = true
	rpc_bank_ack.rpc_id(id, true, to, amount, "")
	print("Banque : %s → %s, %d FCFA" % [who, to, amount])


@rpc("authority", "reliable")
func rpc_bank_ack(ok: bool, to: String, amount: int, message: String) -> void:
	bank_answer.emit(ok, to, amount, message)


@rpc("authority", "reliable")
func rpc_bank_in(from: String, amount: int, note: String) -> void:
	bank_received.emit(from, amount, note)


# --- Mairie --------------------------------------------------------------------------------

func run_for_mayor() -> void:
	if net.online:
		rpc_candidate.rpc_id(1)


func vote(candidate: String) -> void:
	if net.online:
		rpc_vote.rpc_id(1, candidate)


func set_tax(rate: int) -> void:
	if net.online:
		rpc_set_tax.rpc_id(1, rate)


## (joueur) taxe payée sur la recette d'un commerce : elle va dans la caisse de la ville
func pay_tax(amount: int) -> void:
	if net.online and amount > 0:
		rpc_pay_tax.rpc_id(1, amount)


@rpc("any_peer", "reliable")
func rpc_candidate() -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "" or state["candidates"].has(who):
		return
	state["candidates"][who] = 0
	net._broadcast_chat("Mairie", "%s se présente à l'élection du maire !" % who)
	_broadcast_state()


@rpc("any_peer", "reliable")
func rpc_vote(candidate: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	var who: String = net._sessions.get(id, "")
	if who == "" or not state["candidates"].has(candidate):
		return
	if _voters.has(who):
		net.rpc_notice.rpc_id(id, "Tu as déjà voté à cette élection.")
		return
	_voters[who] = true
	state["candidates"][candidate] = int(state["candidates"][candidate]) + 1
	net.rpc_notice.rpc_id(id, "A voté ! Ta voix va à %s." % candidate)
	_broadcast_state()


@rpc("any_peer", "reliable")
func rpc_set_tax(rate: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if net._sessions.get(id, "") != state["mayor"] or state["mayor"] == "":
		return
	state["tax"] = clampi(rate, 0, MAX_TAX)
	net._broadcast_chat("Mairie", "Le maire %s fixe la taxe des commerces à %d %%." % [state["mayor"], state["tax"]])
	_broadcast_state()


@rpc("any_peer", "reliable")
func rpc_pay_tax(amount: int) -> void:
	if not net.is_server:
		return
	if net._sessions.has(multiplayer.get_remote_sender_id()) and amount > 0 and amount <= 100000:
		state["treasury"] = int(state["treasury"]) + amount
		_dirty = true


# --- Mécanicien ----------------------------------------------------------------------------

## (mécanicien en service) répare le véhicule d'un joueur proche
func service(target: int) -> void:
	if net.online:
		rpc_service.rpc_id(1, target)


@rpc("any_peer", "reliable")
func rpc_service(target: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._states.has(id) or not net._pos.has(target) or not _capable.has(target):
		return
	var a: Vector3 = net._pos[id]
	var b: Vector3 = net._pos[target]
	if net._states[id].get("job", "") != "mecanicien" or Vector2(a.x - b.x, a.z - b.z).length() > SERVICE_RANGE:
		net.rpc_notice.rpc_id(id, "Trop loin pour réparer.")
		return
	rpc_serviced.rpc_id(target, net._sessions[id], id)


func ticket(target: int, reason: String) -> void:
	if net.online:
		rpc_ticket.rpc_id(1, target, reason)


@rpc("any_peer", "reliable")
func rpc_ticket(target: int, reason: String) -> void:
	if not net.is_server or not TICKETS.has(reason):
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._states.has(id) or not net._pos.has(id) or not net._pos.has(target) or not _capable.has(target):
		return
	var a: Vector3 = net._pos[id]
	var b: Vector3 = net._pos[target]
	if net._states[id].get("job", "") != "police" or Vector2(a.x - b.x, a.z - b.z).length() > TICKET_RANGE:
		net.rpc_notice.rpc_id(id, "Trop loin pour dresser un PV.")
		return
	var amount: int = TICKETS[reason]
	rpc_ticketed.rpc_id(target, net._sessions[id], reason, amount)
	net.factions.reward(id, 1, amount / 5, "PV dressé à %s (%s)" % [net._sessions.get(target, "?"), reason.to_lower()])


@rpc("authority", "reliable")
func rpc_ticketed(cop: String, reason: String, amount: int) -> void:
	ticketed.emit(cop, reason, amount)


@rpc("authority", "reliable")
func rpc_serviced(mechanic: String, mechanic_id: int) -> void:
	serviced.emit(mechanic, mechanic_id)
