extends Node
## Profils graphiques : Minimal (petits téléphones), Faible (téléphones modestes), Moyen (milieu de gamme),
## Élevé (téléphones puissants, PC). Les autres scripts lisent les réglages avec Graphics.get_value("cle")
## et se mettent à jour sur « changed ».
##
## Adaptation automatique au téléphone (tant que le joueur n'a pas choisi lui-même dans le menu pause) :
## - au lancement, selon la mémoire du téléphone (voir device_profile) ;
## - en jeu, si les images par seconde restent trop basses, on descend d'un cran ;
## - après une fermeture brutale du jeu (CrashReport), on descend aussi d'un cran.
## Une descente automatique est gardée dans user://graphics.cfg (clé "auto") : on ne remonte jamais seul.

signal changed

const PATH := "user://graphics.cfg"
const ORDER := ["minimal", "faible", "moyen", "eleve"]
const NAMES := {"minimal": "Minimal", "faible": "Faible", "moyen": "Moyen", "eleve": "Élevé"}
const PROFILES := {
	"minimal": {
		"scale": 0.55, "msaa": Viewport.MSAA_DISABLED, "shadows": false, "shadow_dist": 0.0, "shadow_size": 512,
		"view": 170.0, "peds": 6, "cars": 8, "lamp_lights": 0, "lamp_pools": 6, "rain": 150, "puddles": false,
		"reflections": false, "lod": 8.0, "char_range": 45.0, "car_range": 110.0, "window_lights": false,
		"glow": false, "ssao": false, "ssr": false, "vfog": false,
	},
	"faible": {
		"scale": 0.7, "msaa": Viewport.MSAA_DISABLED, "shadows": false, "shadow_dist": 0.0, "shadow_size": 1024,
		"view": 240.0, "peds": 14, "cars": 16, "lamp_lights": 0, "lamp_pools": 10, "rain": 500, "puddles": false,
		"reflections": false, "lod": 4.0, "char_range": 70.0, "car_range": 160.0, "window_lights": false,
		"glow": false, "ssao": false, "ssr": false, "vfog": false,
	},
	"moyen": {
		"scale": 0.95, "msaa": Viewport.MSAA_2X, "shadows": true, "shadow_dist": 65.0, "shadow_size": 2048,
		"view": 420.0, "peds": 22, "cars": 24, "lamp_lights": 4, "lamp_pools": 16, "rain": 1400, "puddles": true,
		"reflections": true, "lod": 2.0, "char_range": 110.0, "car_range": 250.0, "window_lights": true,
		"glow": true, "ssao": true, "ssr": false, "vfog": false,
	},
	"eleve": {
		"scale": 1.0, "msaa": Viewport.MSAA_2X, "shadows": true, "shadow_dist": 110.0, "shadow_size": 4096,
		"view": 650.0, "peds": 30, "cars": 32, "lamp_lights": 8, "lamp_pools": 24, "rain": 3000, "puddles": true,
		"reflections": true, "lod": 1.0, "char_range": 150.0, "car_range": 320.0, "window_lights": true,
		"glow": true, "ssao": true, "ssr": true, "vfog": true,
	},
}
const SLOW_FPS := 20.0 ## en dessous (moyenne sur FPS_WINDOW secondes, deux fois de suite) : on descend d'un cran
const FPS_WINDOW := 10.0

var profile := "moyen"
var chosen := false ## le joueur a choisi lui-même : plus d'adaptation automatique
var notice := "" ## message à afficher au joueur une fois en jeu (descente automatique)
var watch_fps := false ## activé par la ville une fois la première image affichée
var _fps_t := 0.0
var _fps_frames := 0
var _slow := 0


func _ready() -> void:
	profile = device_profile()
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var p: String = cfg.get_value("graphics", "profile", profile)
		# Sans clé "auto", le profil enregistré vient du menu pause (choix du joueur)
		chosen = not cfg.has_section_key("graphics", "auto")
		if PROFILES.has(p):
			profile = p if chosen else _lowest(p, profile)
	# Test : -- --graphics=minimal|faible|moyen|eleve
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--graphics=") and PROFILES.has(a.trim_prefix("--graphics=")):
			profile = a.trim_prefix("--graphics=")
			chosen = true
	# Test : -- --ram-test=dossier (lit meminfo_*.txt et status.txt : profil choisi pour chaque mémoire)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ram-test="):
			var dir := a.trim_prefix("--ram-test=")
			for n in DirAccess.get_files_at(dir):
				if n.begins_with("meminfo_"):
					var kb := proc_kb(dir.path_join(n), "MemTotal:")
					print("RAM %s : %d kB -> %s" % [n, kb, profile_for_ram(kb * 1024.0 / 1073741824.0)])
			print("RAM VmRSS : %d kB ; absent : %d ; inconnue -> %s" % [proc_kb(dir.path_join("status.txt"), "VmRSS:"),
				proc_kb(dir.path_join("absent"), "MemTotal:"), profile_for_ram(-1.0)])
			get_tree().quit()
	# Test : -- --slow-test (PC bridé à 12 images/s : la descente automatique doit se déclencher)
	if "--slow-test" in OS.get_cmdline_user_args():
		Engine.max_fps = 12
	print("Mémoire du téléphone : %d Mo, graphismes %s%s" % [ram_bytes() / 1048576, profile, " (choisis)" if chosen else ""])
	apply_viewport()


## Profil de départ selon l'appareil : la mémoire décide (sur téléphone elle sert aussi à l'affichage)
static func device_profile() -> String:
	if not OS.has_feature("mobile"):
		return "eleve"
	return profile_for_ram(float(ram_bytes()) / (1024.0 * 1024.0 * 1024.0))


## Profil pour une mémoire donnée (Go ; le système en annonce un peu moins que la mémoire vendue).
## Depuis 1.23 : Moyen seulement à partir de 12 Go et jamais Élevé sur téléphone. En 1.22, les téléphones
## de 8 Go en Moyen ou Élevé montaient à ~3,5 Go de mémoire et se fermaient après quelques minutes
## (pilote graphique Mali à court de mémoire : TECNO CG8, Redmi 23108RN04Y), contre ~0,8 Go en Faible.
static func profile_for_ram(gb: float) -> String:
	if gb <= 0.0:
		return "faible" # mémoire inconnue : prudence
	if OS.has_feature("ios"):
		# Sur iOS : adaptation fine à la mémoire des différentes générations d'iPhone/iPad
		if gb < 2.5:
			return "minimal" # iPhone 6s, 7, 8 (2 Go) : ultra-léger et fluide
		elif gb < 3.5:
			return "faible" # iPhone 7+, 8+, X, XR (3 Go)
		elif gb < 5.5:
			return "moyen" # iPhone 11, 12, 13 (4 Go)
		return "eleve" # iPhone 13 Pro, 14, 15, 16 et iPad Pro / Air récents (6 Go+)
	if gb < 3.2: # téléphones de 2 et 3 Go (annoncés ~1,8 et ~2,7)
		return "minimal"
	if gb < 10.0: # 4, 6 et 8 Go (~3,6, ~5,4 et ~7,3)
		return "faible"
	return "moyen"


## Mémoire totale de l'appareil en octets (-1 si inconnue). Godot ne la donne pas sur Android :
## on la lit alors dans /proc/meminfo (MemTotal).
static func ram_bytes() -> int:
	var phys := int(OS.get_memory_info().get("physical", -1))
	if phys > 0:
		return phys
	var kb := proc_kb("/proc/meminfo", "MemTotal:")
	return kb * 1024 if kb > 0 else -1


## Valeur en kilo-octets d'une ligne « Clé:   1234 kB » d'un fichier /proc (-1 si absente)
static func proc_kb(path: String, key: String) -> int:
	for line in proc_text(path).split("\n"):
		if line.begins_with(key):
			return line.trim_prefix(key).strip_edges().split(" ")[0].to_int()
	return -1


## Contenu d'un fichier /proc. Ces fichiers annoncent une taille nulle : sur Android, get_line()
## se croyait déjà à la fin et ne lisait rien (mémoire du téléphone « inconnue » jusqu'en 1.15).
## On lit donc un bloc, puis on se rabat sur la commande cat.
static func proc_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var text := f.get_buffer(65536).get_string_from_utf8()
		if text == "":
			text = f.get_as_text()
		if text != "":
			return text
	var out := []
	if OS.has_feature("mobile") and OS.execute("cat", [path], out) == 0 and not out.is_empty():
		return str(out[0])
	return ""


static func _lowest(a: String, b: String) -> String:
	return a if ORDER.find(a) < ORDER.find(b) else b


## Descente automatique d'un cran (lenteur, plantage). Renvoie false si on est déjà au plus bas
## ou si le joueur a choisi son profil lui-même. Exception (forced : plantage, mémoire pleine) : même un
## profil choisi descend, directement au profil conseillé s'il était au-dessus ; sans cela, un téléphone
## de 2 Go réglé sur Élevé se fermait à chaque partie (TECNO KE5, 1.21), et un téléphone réglé sur le
## profil conseillé replantait à chaque partie sans jamais descendre (Redmi 23108RN04Y en Moyen, 1.22).
func lower(reason: String, forced := false) -> bool:
	var i := ORDER.find(profile)
	var advised := device_profile()
	if i <= 0 or chosen and not forced:
		return false
	if chosen and i > ORDER.find(advised):
		profile = advised
	else:
		profile = ORDER[i - 1]
	chosen = false
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "profile", profile)
	cfg.set_value("graphics", "auto", true)
	cfg.save(PATH)
	apply_viewport()
	changed.emit()
	notice = "Graphismes réglés sur %s (%s). Tu peux les changer dans le menu pause." % [display_name(), reason]
	print("Graphismes abaissés : %s (%s)" % [profile, reason])
	return true


func _process(delta: float) -> void:
	if not watch_fps or chosen or not OS.has_feature("mobile") and not "--slow-test" in OS.get_cmdline_user_args():
		return
	_fps_t += delta
	_fps_frames += 1
	if _fps_t < FPS_WINDOW:
		return
	var fps := _fps_frames / _fps_t
	_fps_t = 0.0
	_fps_frames = 0
	_slow = _slow + 1 if fps < SLOW_FPS else 0
	if _slow >= 2:
		_slow = -1 # une fenêtre de répit après le changement
		if lower("le jeu était lent : %d images/s" % roundi(fps)) and notice != "":
			GameState.notify.emit(notice)
			notice = ""


func get_value(key: String) -> Variant:
	return PROFILES[profile][key]


func set_profile(p: String) -> void:
	if not PROFILES.has(p) or p == profile:
		return
	profile = p
	chosen = true
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "profile", p)
	cfg.save(PATH)
	apply_viewport()
	changed.emit()


## Brume plus dense quand la distance d'affichage est courte (cache le bord du monde)
func fog_factor() -> float:
	return 400.0 / float(get_value("view"))


func display_name() -> String:
	return NAMES[profile]


## Résolution de rendu 3D, anticrénelage, taille des ombres, niveau de détail des maillages
func apply_viewport() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := get_viewport()
	# Mise à l'échelle FSR (FidelityFX Super Resolution) pour un rendu 3D haute netteté
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.fsr_sharpness = 0.2
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_scale = get_value("scale")
	vp.msaa_3d = get_value("msaa")
	vp.mesh_lod_threshold = get_value("lod")
	RenderingServer.directional_shadow_atlas_set_size(get_value("shadow_size"), true)
	# Relief des textures de la ville (cartes de normales) : coupé sur le profil Faible
	RenderingServer.global_shader_parameter_set("city_detail", 0.0 if profile == "faible" else 1.0)
