extends Node
## Émotes (saluer, danser, applaudir...), nœud « Emotes » enfant de Net (même chemin sur le serveur et chez
## les joueurs). Le joueur envoie son geste au serveur, qui le transmet aux joueurs proches. Un nœud à part :
## les versions qui ne l'ont pas (1.19 et avant) ne reçoivent rien, le serveur ne leur envoie que s'ils ont dit bonjour.

signal emote(id: int, clip: String)

## [nom affiché, animation] (tools/bake_animations.gd)
const LIST := [["Saluer", "wave"], ["Téléphoner", "phone"], ["Applaudir", "clap"], ["Bras croisés", "arms_crossed"],
	["Prière (dua)", "dua"], ["Danser", "dance"], ["S'accroupir", "crouch"], ["Discuter", "talk"]]
const RANGE := 80.0
const COOLDOWN_MS := 300

var net
var _capable := {} ## (serveur) joueurs qui connaissent les émotes
var _last := {} ## (serveur) id → dernier geste (ms)


static func valid(clip: String) -> bool:
	if clip == "":
		return true
	for e in LIST:
		if e[1] == clip:
			return true
	return false


## (joueur) à la connexion : le serveur sait qu'on peut recevoir les gestes des autres
func hello() -> void:
	if net.online:
		rpc_hello.rpc_id(1)


## (joueur) geste commencé ("" = arrêté)
func send(clip: String) -> void:
	if net.online:
		rpc_emote.rpc_id(1, clip)


func forget(id: int) -> void:
	_capable.erase(id)
	_last.erase(id)


@rpc("any_peer", "reliable")
func rpc_hello() -> void:
	if net.is_server:
		_capable[multiplayer.get_remote_sender_id()] = true


@rpc("any_peer", "reliable")
func rpc_emote(clip: String) -> void:
	if not net.is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if not net._sessions.has(id) or not valid(clip):
		return
	var now := Time.get_ticks_msec()
	if clip != "" and now - int(_last.get(id, 0)) < COOLDOWN_MS:
		return
	_last[id] = now
	var pa: Vector3 = net._pos.get(id, Vector3(INF, 0, INF))
	for pid in _capable:
		if pid == id or not net._sessions.has(pid):
			continue
		var pb: Vector3 = net._pos.get(pid, Vector3(-INF, 0, -INF))
		if Vector2(pa.x - pb.x, pa.z - pb.z).length() < RANGE:
			rpc_emote_fx.rpc_id(pid, id, clip)


@rpc("authority", "reliable")
func rpc_emote_fx(id: int, clip: String) -> void:
	if valid(clip):
		emote.emit(id, clip)
