extends Node
## État global : argent (FCFA), santé, besoins (satiété, soif, énergie), heure, statistiques, sauvegarde et contrôles.

signal notify(text: String)
signal fainted
signal new_day ## chaque matin à 8 h (loyers)

const Items = preload("res://scripts/util/items.gd")
const SAVE_PATH := "user://galsen_life_save.json"
## Fichier réellement utilisé (le test automatique en prend un autre pour ne jamais toucher ta partie).
var save_path := SAVE_PATH
const START_MONEY := 10000
## 1 seconde réelle = 1 minute de jeu → une journée dure 24 minutes.
const MINUTES_PER_SECOND := 1.0

var money := START_MONEY
var bank := 0 ## compte en banque (à l'abri des amendes)
var bank_log := [] ## relevé de compte : dernières opérations (texte)
var jail := 0.0 ## garde à vue : secondes de cellule restantes (scripts/police/prison.gd)
var home := {} ## logement : {owned: [ids], rented: id, unpaid: jours, safe: argent du coffre}
var garage := {} ## logement → voitures rangées [{type, color}]
var day := 1
var lutte := {} ## lutte : force, bilan, popularité, écurie, calendrier des journées (scripts/world/lutte.gd)
var employment := {} ## patrons : id → {hired, rep, shifts, promoted, fired_at} ; "_experience" = services faits
var health := 100.0
var hunger := 100.0 ## 100 = rassasié, 0 = affamé
var thirst := 100.0 ## 100 = désaltéré, 0 = déshydraté (la santé baisse)
var energy := 100.0 ## 100 = reposé, 0 = épuisé (on ne peut plus courir) ; dormir la remet à 100
var game_minutes := 8.0 * 60.0
var player_position := Vector3.ZERO
var has_saved_position := false
var stats := {"courses_taxi": 0, "livraisons": 0, "cafes_vendus": 0}
## Compétences (expérience) : elles montent en pratiquant, niveau 1 à 10 (skill_level)
const SKILLS := {"conduite": "Conduite", "endurance": "Endurance", "peche": "Pêche", "cuisine": "Cuisine"}
var skills := {}
## Sac : objets achetés (nom → quantité)
var inventory := {}
## Tenue portée (scripts/util/outfits.gd : « haut,bas,chapeau ») et vêtements achetés (« haut:vert » → true)
var tenue := ""
var garde_robe := {}
## Véhicules à soi (concession, scripts/vehicles/dealership.gd) : [{type, color, fuel}]
var vehicles := []
## Location en cours (scripts/vehicles/rental.gd) : {type, until, deposit, rate, agency, fuel, condition}
var rental := {}
## Faction en ligne (scripts/net/factions.gd) : {id, xp, civil (tenue de ville pendant le service)}
var faction := {}
var tuto := {} ## guide des premiers pas (scripts/jobs/tutorial.gd) : {step, done}
## Point GPS posé sur la carte (null = aucun)
var waypoint = null
## Niveau de recherche de la police (0 à 5 étoiles). Non sauvegardé.
var wanted := 0

var touch_ui := false
var touch_move := Vector2.ZERO
var touch_look := Vector2.ZERO
var player_ref = null
var rp_job := "" ## métier RP en ligne en cours (taxi, vendeur, ou service de faction : police, samu, gang)
var typing := false ## le joueur écrit dans le chat : pas de déplacement
var _is_fainted := false
var faint_reason := "" ## "ko" : mis KO dans une bagarre, "soif" (sinon : faim)
var _warned := {} ## besoins déjà signalés au joueur (soif, fatigue)


func _ready() -> void:
	touch_ui = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()
	_setup_input()
	load_game()
	# Quitter proprement : en ligne, la sauvegarde doit avoir le temps de partir vers le serveur
	get_tree().auto_accept_quit = false
	var t := Timer.new()
	t.wait_time = 30.0
	t.autostart = true
	t.timeout.connect(save_game)
	add_child(t)


func _process(delta: float) -> void:
	advance_time(delta * MINUTES_PER_SECOND)
	hunger = maxf(hunger - delta * 0.15, 0.0)
	thirst = maxf(thirst - delta * 0.2, 0.0)
	energy = maxf(energy - delta * 0.05, 0.0)
	if hunger <= 0.0:
		health = maxf(health - delta * 0.5, 0.0)
	if thirst <= 0.0:
		health = maxf(health - delta * 0.6, 0.0)
		if health <= 0.0 and hunger > 0.0:
			faint_reason = "soif"
	_warn("soif", thirst < 20.0, "Tu as soif... Bois un jus de bissap ou une bouteille d'eau.")
	_warn("fatigue", energy < 15.0, "Tu es épuisé : tu ne peux plus courir. Dors chez toi ou prends un café Touba.")
	if health <= 0.0 and not _is_fainted:
		_is_fainted = true
		fainted.emit()


## Niveau d'une compétence (1 à 10) selon l'expérience : 5 → 2, 20 → 3, 45 → 4... 405 → 10
func skill_level(id: String) -> int:
	return mini(10, 1 + int(sqrt(float(skills.get(id, 0.0)) / 5.0)))


## Expérience gagnée dans une compétence (annonce le passage de niveau)
func add_skill(id: String, xp: float) -> void:
	var before := skill_level(id)
	skills[id] = float(skills.get(id, 0.0)) + xp
	var after := skill_level(id)
	if after > before:
		notify.emit("Compétence %s : niveau %d !" % [SKILLS.get(id, id), after])
		Audio.play_sfx("coin", -12.0)


## Prévient une fois quand un besoin devient pressant (et de nouveau après qu'il a été satisfait)
func _warn(key: String, low: bool, text: String) -> void:
	if low and not _warned.has(key):
		_warned[key] = true
		notify.emit(text)
	elif not low and _warned.has(key):
		_warned.erase(key)


## Manger ou boire un produit (catalogue scripts/util/items.gd ; food : satiété donnée par la boutique)
func consume(item: String, food := -1) -> void:
	var e: Array = Items.effects(item, food)
	hunger = minf(100.0, hunger + e[0])
	thirst = minf(100.0, thirst + e[1])
	energy = minf(100.0, energy + e[2])


## Produit acheté qui se mange ou se boit : consommé tout de suite si on en a besoin, sinon rangé
## dans le sac (s'il reste de la place). Renvoie true s'il a été consommé.
func take_food(item: String, food := -1) -> bool:
	if Items.needed(item, food) or bag_count() >= Items.BAG_MAX:
		consume(item, food)
		return true
	add_item(item)
	return false


func bag_count() -> int:
	var n := 0
	for k in inventory:
		n += int(inventory[k])
	return n


## Utilise un produit du sac (appli « Sac » du téléphone)
func use_item(item: String) -> bool:
	if int(inventory.get(item, 0)) <= 0 or not Items.is_consumable(item):
		return false
	inventory[item] = int(inventory[item]) - 1
	if inventory[item] <= 0:
		inventory.erase(item)
	consume(item)
	return true


## Fait avancer l'horloge (sommeil compris) : nouveau jour chaque matin à 8 h
func advance_time(minutes: float) -> void:
	var before := game_minutes
	var total := before + minutes
	game_minutes = fmod(total, 1440.0)
	var mornings := int(floor((total - 480.0) / 1440.0)) - int(floor((before - 480.0) / 1440.0))
	for k in maxi(0, mornings):
		day += 1
		new_day.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()


## Sauvegarde puis quitte (en ligne : laisse le temps à la sauvegarde d'arriver au serveur).
func quit_game() -> void:
	if not Net.is_server:
		save_game()
	if Net.online:
		await get_tree().create_timer(0.5).timeout
		Net.disconnect_from_server()
	get_tree().quit()


# --- Argent et santé -------------------------------------------------------

func fcfa(amount: int) -> String:
	var s := str(absi(amount))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if amount < 0 else "") + s + out + " FCFA"


func add_money(amount: int, reason: String) -> void:
	money += amount
	notify.emit("+%s — %s" % [fcfa(amount), reason])
	Audio.play_sfx("coin", -10.0)


func spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	return true


func fine(amount: int, reason: String) -> void:
	var paid := mini(amount, money)
	money -= paid
	notify.emit("-%s — %s" % [fcfa(paid), reason])


func damage(amount: float, reason: String) -> void:
	health = maxf(health - amount, 0.0)
	notify.emit(reason)


func add_wanted(stars: int, reason: String) -> void:
	var before := wanted
	wanted = clampi(wanted + stars, 0, 5)
	notify.emit(reason)
	if wanted > before:
		Audio.play_sfx("alert")


func lose_star() -> void:
	wanted = maxi(wanted - 1, 0)


func clear_wanted() -> void:
	wanted = 0


## Ligne du relevé de compte (« +5 000 FCFA : dépôt »), datée du jour de jeu
func bank_note(text: String) -> void:
	bank_log.append("Jour %d — %s" % [day, text])
	if bank_log.size() > 30:
		bank_log.pop_front()


func add_item(item: String, count := 1) -> void:
	inventory[item] = int(inventory.get(item, 0)) + count


func inventory_text() -> String:
	if inventory.is_empty():
		return "Ton sac est vide."
	var parts: Array = []
	for k in inventory:
		parts.append("%s x%d" % [k, inventory[k]])
	return ", ".join(parts)


func revive() -> void:
	health = 100.0
	hunger = maxf(hunger, 70.0)
	thirst = maxf(thirst, 70.0)
	energy = maxf(energy, 50.0)
	_is_fainted = false


# --- Contrôles --------------------------------------------------------------

func get_move_input() -> Vector2:
	if typing:
		return Vector2.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > v.length():
		v = touch_move
	return v


func _setup_input() -> void:
	# Touches physiques : fonctionne en QWERTY (WASD) comme en AZERTY (ZQSD).
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("interact", [KEY_E])
	_bind_keys("attack", [KEY_F])
	if not touch_ui:
		# Clic gauche (souris capturée) : coup de poing. Pas sur écran tactile (chaque toucher serait un clic).
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mb)
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("pause", [KEY_ESCAPE, KEY_P])
	_bind_keys("toggle_touch", [KEY_F1])
	_bind_keys("horn", [KEY_H])
	_bind_keys("radio", [KEY_R])
	_bind_keys("steal", [KEY_G])
	_bind_keys("map", [KEY_M, KEY_TAB])
	_bind_keys("chat", [KEY_T])
	_bind_keys("phone", [KEY_C])
	_bind_keys("voice", [KEY_V])
	_bind_keys("voice_group", [KEY_B])
	_bind_keys("camera_view", [KEY_X])
	# Manette
	_bind_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_bind_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_bind_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_bind_button("interact", JOY_BUTTON_Y)
	_bind_button("jump", JOY_BUTTON_A)
	_bind_button("sprint", JOY_BUTTON_B)
	_bind_button("pause", JOY_BUTTON_START)
	_bind_button("horn", JOY_BUTTON_LEFT_SHOULDER)
	_bind_button("radio", JOY_BUTTON_RIGHT_SHOULDER)
	_bind_button("steal", JOY_BUTTON_X)
	_bind_button("map", JOY_BUTTON_BACK)


func _ensure_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)


func _bind_keys(action: String, keys: Array) -> void:
	_ensure_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _bind_axis(action: String, axis: JoyAxis, value: float) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _bind_button(action: String, button: JoyButton) -> void:
	_ensure_action(action)
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


# --- Sauvegarde -------------------------------------------------------------

func save_game() -> void:
	if player_ref != null and is_instance_valid(player_ref):
		player_position = player_ref.get_world_position()
		has_saved_position = true
	var data := {
		"money": money,
		"bank": bank,
		"bank_log": bank_log,
		"jail": jail,
		"employment": employment,
		"lutte": lutte,
		"home": home,
		"garage": garage,
		"day": day,
		"health": health,
		"hunger": hunger,
		"thirst": thirst,
		"energy": energy,
		"minutes": game_minutes,
		"pos": [player_position.x, player_position.y, player_position.z],
		"has_pos": has_saved_position,
		"stats": stats,
		"skills": skills,
		"inventory": inventory,
		"tenue": tenue,
		"garde_robe": garde_robe,
		"faction": faction,
		"vehicles": vehicles,
		"rental": rental,
		"tuto": tuto,
	}
	if Net.is_server:
		return
	if Net.online:
		Net.send_save(data)
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	apply_save(data)


## En ligne : la partie vient du serveur (vide = nouveau joueur).
func start_online(save: Dictionary) -> void:
	_reset_state()
	if not save.is_empty():
		apply_save(save)


func apply_save(data: Dictionary) -> void:
	money = int(data.get("money", START_MONEY))
	bank = int(data.get("bank", 0))
	var bl = data.get("bank_log", [])
	bank_log = bl if bl is Array else []
	jail = clampf(float(data.get("jail", 0.0)), 0.0, 600.0)
	var emp = data.get("employment", {})
	employment = emp if emp is Dictionary else {}
	var hm = data.get("home", {})
	home = hm if hm is Dictionary else {}
	var lt = data.get("lutte", {})
	lutte = lt if lt is Dictionary else {}
	var gg = data.get("garage", {})
	garage = gg if gg is Dictionary else {}
	day = int(data.get("day", 1))
	health = float(data.get("health", 100.0))
	hunger = float(data.get("hunger", 100.0))
	thirst = float(data.get("thirst", 100.0))
	energy = float(data.get("energy", 100.0))
	game_minutes = float(data.get("minutes", 480.0))
	var p = data.get("pos", [])
	if p is Array and p.size() == 3:
		player_position = Vector3(p[0], p[1], p[2])
	has_saved_position = bool(data.get("has_pos", false))
	var inv = data.get("inventory", {})
	if inv is Dictionary:
		inventory = {}
		for k in inv:
			inventory[k] = int(inv[k])
	tenue = str(data.get("tenue", "")).left(64)
	var gr = data.get("garde_robe", {})
	garde_robe = gr if gr is Dictionary else {}
	var vh = data.get("vehicles", [])
	vehicles = vh if vh is Array else []
	var rl = data.get("rental", {})
	rental = rl if rl is Dictionary and rl.has("type") and rl.has("until") else {}
	var fa = data.get("faction", {})
	faction = fa if fa is Dictionary else {}
	# Partie quittée pendant un service : on remet la tenue de ville
	if faction.has("civil"):
		tenue = str(faction["civil"]).left(64)
		faction.erase("civil")
	skills = {}
	var sk = data.get("skills", {})
	if sk is Dictionary:
		for k in SKILLS:
			if sk.has(k):
				skills[k] = clampf(float(sk[k]), 0.0, 100000.0)
	var s = data.get("stats", {})
	if s is Dictionary:
		for k in stats.keys():
			stats[k] = int(s.get(k, 0))
	# Parties d'avant le guide des premiers pas : elles le sautent
	var tt = data.get("tuto", {"done": true})
	tuto = tt if tt is Dictionary else {"done": true}


func new_game() -> void:
	_reset_state()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _reset_state() -> void:
	money = START_MONEY
	bank = 0
	bank_log = []
	jail = 0.0
	employment = {}
	home = {}
	lutte = {}
	garage = {}
	day = 1
	health = 100.0
	hunger = 100.0
	thirst = 100.0
	energy = 100.0
	game_minutes = 480.0
	player_position = Vector3.ZERO
	has_saved_position = false
	stats = {"courses_taxi": 0, "livraisons": 0, "cafes_vendus": 0}
	skills = {}
	inventory = {}
	tenue = ""
	garde_robe = {}
	faction = {}
	tuto = {}
	vehicles = []
	rental = {}
	waypoint = null
	wanted = 0
	rp_job = ""
	_is_fainted = false
