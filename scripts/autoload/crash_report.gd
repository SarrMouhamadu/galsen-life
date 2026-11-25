extends Node
## Rapports de plantage des testeurs.
## - Client : pendant la partie, un fichier témoin (user://en_cours.json) note la dernière étape atteinte
##   et la mémoire utilisée. Il est effacé quand le jeu passe en arrière-plan ou se ferme normalement.
##   S'il est encore là au lancement suivant, le jeu a planté (ou a été tué par le système) : on envoie
##   au serveur le modèle du téléphone, la mémoire, la version, la dernière étape et la fin du journal.
## - Serveur : écoute en TCP sur REPORT_PORT et range chaque rapport dans user://rapports/.
## Après un plantage, les graphismes descendent aussi d'un cran (Graphics.lower).
## Le journal de Godot (user://logs/) est activé sur téléphone dans project.godot.

const REPORT_PORT := 7778
const FLAG_PATH := "user://en_cours.json"
const PENDING_PATH := "user://rapport_en_attente.json"
const REPORTS_DIR := "user://rapports"
const LOG_TAIL := 12000 ## octets de fin de journal envoyés
const MAX_REPORT := 65536 ## taille maximale d'un rapport reçu par le serveur
const MAX_REPORTS := 500 ## rapports gardés sur le serveur

var _state := {} ## contenu du fichier témoin
var _alive_t := 0.0
var _background := false ## jeu en arrière-plan : le fichier témoin n'est plus écrit
# Envoi (client)
var _peer: StreamPeerTCP
var _payload := PackedByteArray()
var _send_t := 0.0
# Réception (serveur)
var _server: TCPServer
var _clients := [] ## {peer, data, t}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		_listen()
		return
	if DisplayServer.get_name() == "headless" or OS.has_feature("editor") and not "--crash-test" in args:
		set_process(false)
		return
	_check_previous()
	_state = {"version": version(), "debut": Time.get_datetime_string_from_system(), "etapes": []}
	step("lancement")


## Version du jeu (application/config/version)
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "?"))


## Étape atteinte (gardée dans le fichier témoin et dans le journal)
func step(what: String) -> void:
	if _state.is_empty():
		return
	print("[étape] ", what)
	var steps: Array = _state["etapes"]
	steps.append("%s %s" % [Time.get_time_string_from_system(), what])
	if steps.size() > 20:
		steps.pop_front()
	_write_flag()


func _process(delta: float) -> void:
	if _server:
		_serve(delta)
		return
	if _peer:
		_send_step(delta)
	if not _state.is_empty():
		_alive_t += delta
		if _alive_t >= 15.0:
			_alive_t = 0.0
			_write_flag() # met à jour la mémoire utilisée


func _notification(what: int) -> void:
	if _state.is_empty():
		return
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			# Android peut fermer un jeu en arrière-plan à tout moment : ce n'est pas un plantage
			_background = true
			DirAccess.remove_absolute(FLAG_PATH)
		NOTIFICATION_APPLICATION_RESUMED:
			_background = false
			_write_flag()
		NOTIFICATION_OS_MEMORY_WARNING:
			# Mémoire de l'appareil presque pleine : on le note et on allège les graphismes
			var free_kb := Graphics.proc_kb("/proc/meminfo", "MemAvailable:")
			if free_kb > 0:
				step("mémoire presque pleine (%d Mo libres)" % (free_kb / 1024))
			else:
				step("mémoire presque pleine")
			if Graphics.lower("mémoire presque pleine", true) and Graphics.notice != "":
				GameState.notify.emit(Graphics.notice)
				Graphics.notice = ""


func _write_flag() -> void:
	if _background:
		return
	# Mémoire réellement occupée par le jeu (Android : VmRSS du processus ; -1 si illisible)
	# /proc/<pid> et non /proc/self : si la lecture passe par la commande cat, « self » serait cat lui-même
	var rss := Graphics.proc_kb("/proc/%d/status" % OS.get_process_id(), "VmRSS:")
	_state["memoire_mo"] = rss / 1024 if rss > 0 else -1
	var free_mem := Graphics.proc_kb("/proc/meminfo", "MemAvailable:")
	_state["libre_mo"] = free_mem / 1024 if free_mem > 0 else -1
	_state["video_mo"] = RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576
	_state["graphismes"] = Graphics.profile
	_state["pseudo"] = Net.pseudo
	_state["duree_s"] = Time.get_ticks_msec() / 1000 ## temps de jeu au dernier signe de vie
	var f := FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_state))
		f.close()


# --- Client : rapport du lancement précédent ---

func _check_previous() -> void:
	var report = null
	if FileAccess.file_exists(FLAG_PATH):
		var last = JSON.parse_string(FileAccess.get_file_as_string(FLAG_PATH))
		DirAccess.remove_absolute(FLAG_PATH)
		report = _build_report(last if last is Dictionary else {})
		# Le téléphone n'a pas tenu : graphismes un cran plus bas (choix du joueur gardé s'il est raisonnable)
		report["graphismes_abaisses"] = Graphics.lower("le jeu s'était fermé", true)
		var f := FileAccess.open(PENDING_PATH, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(report))
			f.close()
	elif FileAccess.file_exists(PENDING_PATH):
		report = JSON.parse_string(FileAccess.get_file_as_string(PENDING_PATH))
	if report is Dictionary:
		_payload = (JSON.stringify(report) + "\n").to_utf8_buffer()
		_peer = StreamPeerTCP.new()
		var host := Net.DEFAULT_HOST
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--report-host="):
				host = a.trim_prefix("--report-host=")
		if _peer.connect_to_host(host, REPORT_PORT) != OK:
			_peer = null


func _build_report(last: Dictionary) -> Dictionary:
	return {
		"precedent": last,
		"version_actuelle": version(),
		"modele": OS.get_model_name(),
		"systeme": "%s %s" % [OS.get_name(), OS.get_version()],
		"ram_mo": Graphics.ram_bytes() / 1048576,
		"processeur": OS.get_processor_name(),
		"carte_graphique": RenderingServer.get_video_adapter_name(),
		"pilote": RenderingServer.get_video_adapter_api_version(),
		"journal": _previous_log_tail(),
	}


## Fin du journal du lancement précédent (Godot renomme l'ancien godot.log au démarrage)
func _previous_log_tail() -> String:
	var dir := "user://logs"
	var files := Array(DirAccess.get_files_at(dir)).filter(func(n: String) -> bool: return n.ends_with(".log") and n != "godot.log")
	if files.is_empty():
		return ""
	files.sort()
	var f := FileAccess.open(dir.path_join(files[-1]), FileAccess.READ)
	if f == null:
		return ""
	var size := f.get_length()
	f.seek(maxi(0, size - LOG_TAIL))
	return f.get_buffer(mini(size, LOG_TAIL)).get_string_from_utf8()


func _send_step(delta: float) -> void:
	_send_t += delta
	_peer.poll()
	var st := _peer.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTED and not _payload.is_empty():
		var res := _peer.put_partial_data(_payload)
		if res[0] == OK:
			_payload = _payload.slice(res[1])
		if _payload.is_empty():
			DirAccess.remove_absolute(PENDING_PATH)
			print("Rapport de plantage envoyé.")
			_peer.disconnect_from_host()
			_peer = null
			return
	if st == StreamPeerTCP.STATUS_ERROR or _send_t > 15.0:
		_peer = null # réessai au prochain lancement (le rapport reste en attente)


# --- Serveur : réception ---

func _listen() -> void:
	_server = TCPServer.new()
	var err := _server.listen(REPORT_PORT)
	if err != OK:
		printerr("Rapports de plantage : port TCP %d indisponible (erreur %d)" % [REPORT_PORT, err])
		_server = null
		set_process(false)
		return
	DirAccess.make_dir_recursive_absolute(REPORTS_DIR)
	print("Rapports de plantage : écoute sur le port TCP %d" % REPORT_PORT)


func _serve(delta: float) -> void:
	while _server.is_connection_available() and _clients.size() < 20:
		_clients.append({"peer": _server.take_connection(), "data": PackedByteArray(), "t": 0.0})
	for c in _clients.duplicate():
		var p: StreamPeerTCP = c["peer"]
		p.poll()
		c["t"] += delta
		var n := p.get_available_bytes()
		if n > 0:
			var res := p.get_partial_data(mini(n, MAX_REPORT))
			if res[0] == OK:
				c["data"].append_array(res[1])
		var data: PackedByteArray = c["data"]
		var done := data.size() > 0 and data[data.size() - 1] == 10
		if done or data.size() >= MAX_REPORT or c["t"] > 10.0 or p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			if done:
				_store(data.get_string_from_utf8())
			p.disconnect_from_host()
			_clients.erase(c)


func _store(text: String) -> void:
	var r = JSON.parse_string(text)
	if not r is Dictionary:
		return
	var files := DirAccess.get_files_at(REPORTS_DIR)
	if files.size() >= MAX_REPORTS:
		return
	var fname := "%s-%d.json" % [Time.get_datetime_string_from_system().replace(":", "-"), files.size()]
	var f := FileAccess.open(REPORTS_DIR.path_join(fname), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(r, "\t"))
	f.close()
	var last: Dictionary = r.get("precedent", {}) if r.get("precedent") is Dictionary else {}
	var steps: Array = last.get("etapes", []) if last.get("etapes") is Array else []
	print("RAPPORT PLANTAGE %s : %s (%s), %s Mo de RAM, version %s, graphismes %s, dernière étape « %s », mémoire %s Mo / vidéo %s Mo, vivant %s s" % [
		fname, r.get("modele", "?"), last.get("pseudo", ""), int(r.get("ram_mo", -1)), last.get("version", "?"), last.get("graphismes", "?"),
		steps[-1] if not steps.is_empty() else "?", int(last.get("memoire_mo", -1)), int(last.get("video_mo", -1)), int(last.get("duree_s", -1))])
