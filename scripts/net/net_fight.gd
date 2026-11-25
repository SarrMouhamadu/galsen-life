extends Node
## Bagarres de rue entre joueurs, nœud « Bagarre » enfant de Net (même chemin sur le serveur et chez les joueurs).
## Le joueur qui frappe envoie le coup au serveur ; celui-ci vérifie la distance et la cadence, puis
## transmet les dégâts à la victime et l'animation aux joueurs proches. Côté joueur : street_fight.gd.

signal hit(attacker: int, attacker_name: String, dmg: int)
signal fx(id: int, clip: String)
signal ko_given(victim: String)

const RANGE := 3.5 ## tolérance du serveur (positions envoyées 10 fois par seconde)
const COOLDOWN_MS := 350
const FX_RANGE := 60.0
const DAMAGE := Vector2i(10, 16)

var net
var _last := {} ## (serveur) id → dernier coup (ms)


func punch(target: int) -> void:
	if net.online:
		rpc_punch.rpc_id(1, target)


func report_ko(attacker: int) -> void:
	if net.online:
		rpc_ko.rpc_id(1, attacker)


func _near(a: int, b: int, r: float) -> bool:
	var pa: Vector3 = net._pos.get(a, Vector3(INF, 0, INF))
	var pb: Vector3 = net._pos.get(b, Vector3(-INF, 0, -INF))
	return Vector2(pa.x - pb.x, pa.z - pb.z).length() < r


func _fx_around(center: int, id: int, clip: String, skip: int) -> void:
	for pid in net._sessions:
		if pid != skip and _near(pid, center, FX_RANGE):
			rpc_fx.rpc_id(pid, id, clip)


@rpc("any_peer", "reliable")
func rpc_punch(target: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if id == target or not net._sessions.has(id) or not net._sessions.has(target) or net.social._duel_of.has(target):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(id, 0)) < COOLDOWN_MS or not _near(id, target, RANGE):
		return
	_last[id] = now
	rpc_hit.rpc_id(target, id, net._sessions[id], randi_range(DAMAGE.x, DAMAGE.y))
	_fx_around(id, id, "punch", id)
	_fx_around(target, target, "hit", target)


@rpc("any_peer", "reliable")
func rpc_ko(attacker: int) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id):
		return
	_fx_around(id, id, "fall", id)
	if net._sessions.has(attacker):
		rpc_ko_given.rpc_id(attacker, net._sessions[id])


@rpc("authority", "reliable")
func rpc_hit(attacker: int, attacker_name: String, dmg: int) -> void:
	hit.emit(attacker, attacker_name, dmg)


@rpc("authority", "reliable")
func rpc_fx(id: int, clip: String) -> void:
	fx.emit(id, clip)


@rpc("authority", "reliable")
func rpc_ko_given(victim: String) -> void:
	ko_given.emit(victim)
