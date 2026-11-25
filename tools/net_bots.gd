extends SceneTree
## Test de charge du serveur en ligne : connecte des centaines de faux joueurs qui marchent dans Dakar.
##
##   godot --headless --path . -s res://tools/net_bots.gd -- --bots=200 --host=127.0.0.1 --start=0 --duration=60
##
## Chaque bot a sa propre connexion (branche multijoueur séparée) et utilise le vrai code réseau du jeu
## (scripts/net/net.gd) : connexion avec création de compte, puis envoi de sa position 10 fois par seconde.
## Le serveur affiche ses statistiques (joueurs, temps de calcul, débit) toutes les 10 secondes.

## Zone de la ville où les bots se promènent (coordonnées du jeu, en mètres)
const AREA := Rect2(-900, -1500, 1900, 2600)

var bots: Array = [] ## {net, pos, dir}
var _t := 0.0
var _send := 0.0
var _duration := 60.0
var _snapshots := 0
var _report := 10.0
var _pending: Array = [] ## connexions à lancer (5 par image, pour ne pas tout envoyer d'un coup)


func _initialize() -> void:
	# Le script réseau dépend des modules du jeu (GameState...) : on le charge une fois ceux-ci prêts
	_start.call_deferred()


func _start() -> void:
	var NetScript = load("res://scripts/net/net.gd")
	var count := 100
	var host := "127.0.0.1"
	var start := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bots="):
			count = a.trim_prefix("--bots=").to_int()
		elif a.begins_with("--host="):
			host = a.trim_prefix("--host=")
		elif a.begins_with("--start="):
			start = a.trim_prefix("--start=").to_int()
		elif a.begins_with("--duration="):
			_duration = a.trim_prefix("--duration=").to_float()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + start
	for i in count:
		var holder := Node.new()
		holder.name = "Bot%d" % (start + i)
		root.add_child(holder)
		# Branche multijoueur propre à ce bot : le nœud « Net » a le même chemin relatif que sur le serveur
		set_multiplayer(SceneMultiplayer.new(), holder.get_path())
		var net: Node = NetScript.new()
		net.name = "Net"
		net.light = true
		holder.add_child(net)
		var who := "bot%04d" % (start + i)
		net.connection_changed.connect(func(s: String):
			if "Impossible" in s or "coupé" in s:
				print("BOT %s : %s" % [who, s]))
		_pending.append([net, host, who])
		# Compte déjà créé lors d'un test précédent : simple connexion
		net.login_result.connect(func(ok: bool, msg: String):
			if not ok and "pris" in msg:
				net.connect_and_login.call_deferred(host, who, "botpass", "heros", false))
		# Une partie des bots se regroupe sur la Place de l'Indépendance (foule), les autres partout
		var pos := Vector3(rng.randf_range(AREA.position.x, AREA.end.x), 0.0, rng.randf_range(AREA.position.y, AREA.end.y))
		if i % 4 == 0:
			pos = Vector3(780 + rng.randf_range(-60, 60), 0, 560 + rng.randf_range(-60, 60))
		bots.append({"net": net, "pos": pos, "dir": rng.randf() * TAU})
		net.traffic_received.connect(func(_c): pass)
	print("BOTS : %d bots lancés vers %s" % [count, host])


func _process(delta: float) -> bool:
	_t += delta
	for k in mini(5, _pending.size()):
		var pe: Array = _pending.pop_front()
		pe[0].connect_and_login(pe[1], pe[2], "botpass", "heros", true)
	_send -= delta
	if _send <= 0.0:
		_send = float(OS.get_environment("BOT_SEND")) if OS.get_environment("BOT_SEND") != "" else 0.1
		for b in bots:
			var net = b["net"]
			if not net.online:
				continue
			# Marche aléatoire à 1,4 m/s
			b["dir"] = float(b["dir"]) + randf_range(-0.3, 0.3)
			var p: Vector3 = b["pos"] + Vector3(cos(b["dir"]), 0, sin(b["dir"])) * 0.14
			b["pos"] = p
			net.send_state({"x": p.x, "y": 0.0, "z": p.z, "r": b["dir"], "sp": 1.4, "v": "", "w": 0, "wl": 0, "job": "", "pol": []})
	_report -= delta
	if _report <= 0.0:
		_report = 10.0
		var on := 0
		var seen := 0
		var roster := 0
		for b in bots:
			if b["net"].online:
				on += 1
				seen += b["net"].received
				roster = maxi(roster, b["net"].roster.size())
		print("BOTS connectés=%d/%d instantanés reçus par bot=%.0f liste complète=%d images/s du processus=%d" % [on, bots.size(), float(seen) / maxi(1, on), roster + 1, Engine.get_frames_per_second()])
	return _t > _duration
