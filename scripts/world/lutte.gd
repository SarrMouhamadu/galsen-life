extends Node3D
## Lutte sénégalaise (solo, et base du mode en ligne) :
## - Écuries de quartier : un chef, des lutteurs, un lieu d'entraînement (plage, terrain) avec leur bannière.
##   Le joueur peut s'y entraîner (sa force monte), rejoindre une écurie et demander un combat à son chef.
## - Journées de lutte : organisées par des promoteurs amateurs à l'Arène de la Médina ou à l'Arène nationale,
##   chaque jour à 17 h. Le promoteur loue le stade, paie un cachet à chaque lutteur et vit de la billetterie.
##   Le joueur peut y combattre (cachet + prime de victoire), regarder, ou organiser lui-même sa journée.
## Le volet à plusieurs (écuries de joueurs, journées entre joueurs) est dans scripts/net/net_lutte.gd.
## Toutes les écuries, promoteurs et lutteurs sont fictifs.

const Mk = preload("res://scripts/util/mk.gd")
const RC = preload("res://scripts/util/real_character.gd")

const HOUR := 17 ## heure des journées de lutte
const ORGANIZE_BEFORE := 15 ## un promoteur ne peut plus monter la journée du jour après 15 h
const TRAIN_COST := 1000
const TRAIN_PER_DAY := 3
const RING_R := 7.0
const NEAR := 220.0 ## distance où l'on assiste à la journée (sinon on n'apprend que les résultats)

## Écuries de Dakar (fictives) : lieu d'entraînement près d'un lieu du jeu, force minimale pour y entrer,
## lutteurs [nom, force, popularité]
const ECURIES := [
	{"id": "ndakaaru", "name": "Écurie Ndakaaru", "place": "Plage de l'Anse Bernard", "chef": "Pa Malick Ndiaye", "color": "e63946", "min": 45,
		"lutteurs": [["Saï Saï Ndiaye", 84, 80], ["Boy Teranga", 71, 62], ["Mbaye Baobab", 60, 41], ["Ndiaga Sable", 47, 22]]},
	{"id": "medina", "name": "Écurie Médina Gaïndé", "place": "Polyclinique de la Médina", "chef": "Doudou Sarr", "color": "f4a261", "min": 30,
		"lutteurs": [["Gaïndé Médina", 79, 74], ["Lamb Tilène", 66, 50], ["Petit Kaddu", 52, 30], ["Ass Malaw", 41, 18]]},
	{"id": "fass", "name": "Écurie Fass Mbollo", "place": "Garage mécanique (Fass Delorme)", "chef": "Ousmane Faye", "color": "2a9d8f", "min": 25,
		"lutteurs": [["Rocher de Fass", 76, 68], ["Mbollo Junior", 63, 44], ["Diop Tonnerre", 55, 33], ["Pape Xaalis", 39, 15]]},
	{"id": "gueule", "name": "Écurie Gueule Tapée", "place": "Garage mécanique (Gueule Tapée)", "chef": "Babacar Diop", "color": "8338ec", "min": 20,
		"lutteurs": [["Taureau du Canal", 73, 61], ["Serigne Fallou Gueye", 58, 37], ["Moussa Rail", 49, 24], ["Boy Canal", 36, 12]]},
	{"id": "rebeuss", "name": "Écurie Rebeuss Ganaw", "place": "Garage mécanique (Rebeuss)", "chef": "Modou Seck", "color": "3a86ff", "min": 15,
		"lutteurs": [["Ganaw Rebeuss", 70, 55], ["Thiaw Lion", 57, 35], ["Aliou Pilon", 45, 20], ["Bébé Dakar", 33, 10]]},
	{"id": "diasse", "name": "Écurie Camp Diassé", "place": "Terrain Camp Abdou Diassé", "chef": "Ibrahima Gaye", "color": "ffbe0b", "min": 0,
		"lutteurs": [["Soldat Diassé", 68, 48], ["Ndoye Caserne", 54, 29], ["Gora Ndar", 43, 17], ["Petit Diassé", 30, 8]]},
]
## Stades de lutte
const VENUES := {
	"medina": {"name": "Arène de la Médina", "rent": 60000, "ticket": 1000},
	"arene": {"name": "Arène nationale", "rent": 180000, "ticket": 2000},
}
## Promoteurs amateurs (fictifs) qui organisent les journées
const PROMOTERS := ["Ndiaga Promotions", "Amicale des amateurs de lutte de la Médina", "Teranga Lutte Prod",
	"Association Mbollo Mi", "Les amis de l'arène de Rebeuss", "Diassé Événements"]
const CHEERS := ["« Yaay boy ! » La foule chante !", "Les tam-tams du sabar résonnent !", "« Bàyyi ko ! » Le public est debout !",
	"Les griots chantent les louanges des lutteurs !", "Les supporters agitent les drapeaux de leur écurie !"]

var main
var status := ""
var spots: Array = [] ## {id, pos, label, ecurie?, venue?}
var _bases := {} ## id d'écurie → {pos, yaw, node, people: [Node3D]}
var _venue_pos := {} ## id d'arène → centre du cercle de lutte
var _venue_door := {} ## id d'arène → direction de l'entrée
var _venue_seat := {} ## id d'arène → rayon du premier gradin
var _rng := RandomNumberGenerator.new()
# Journée en direct
var _live: Dictionary = {} ## journée en cours de déroulement (copie de l'entrée du calendrier)
var _bout := 0
var _phase := ""
var _t := 0.0
var _ring: Node3D
var _fighters: Array = [] ## deux RealCharacter (ou le joueur)
var _crowd: Array = []
var _player_side := -1 ## 0 ou 1 si le joueur lutte dans ce combat
# Mini-jeu de prise (combat du joueur)
var _fight := false
var _hits := 0
var _misses := 0
var _cursor := 0.0
var _cursor_dir := 1.0
var _zone := Vector2(0.4, 0.6)
var _speed := 1.0
var _bar: Control
var _scan_t := 0.0
var auto_press := false ## test : place les prises tout seul


func _ready() -> void:
	_rng.randomize()
	_init_state()
	_find_venues()
	for v in VENUES:
		if _venue_pos.has(v):
			var p: Vector3 = _venue_pos[v] + _venue_door.get(v, Vector3(0, 0, 1)) * (RING_R + 15.0 if v == "medina" else RING_R + 9.0)
			spots.append({"id": "bureau", "venue": v, "pos": p, "label": "Bureau des promoteurs — %s" % VENUES[v]["name"]})
	GameState.new_day.connect(_on_new_day)
	_ensure_schedule()
	_place_bases.call_deferred()


## Les lieux d'entraînement ont besoin des collisions de la ville (toits) : posés une fois la physique prête
func _place_bases() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	for e in ECURIES:
		_make_base(e)


# --- État sauvegardé (GameState.lutte) --------------------------------------------------------

func _init_state() -> void:
	var s: Dictionary = GameState.lutte
	if not s.has("force"):
		s["force"] = 20
		s["w"] = 0
		s["l"] = 0
		s["pop"] = 3
		s["ecurie"] = ""
		s["npc"] = {}
		s["journees"] = []
		s["bout"] = {}
		s["train_day"] = 0
		s["train_n"] = 0
	for e in ECURIES:
		for k in e["lutteurs"].size():
			var id := "%s/%d" % [e["id"], k]
			if not s["npc"].has(id):
				var l: Array = e["lutteurs"][k]
				s["npc"][id] = [l[1], l[2], 0, 0] # force, popularité, victoires, défaites


func S() -> Dictionary:
	return GameState.lutte


func ecurie(id: String) -> Dictionary:
	for e in ECURIES:
		if e["id"] == id:
			return e
	return {}


func wrestler_name(id: String) -> String:
	if id == "joueur":
		# Nom de lutteur du joueur (son pseudo en ligne)
		return Net.pseudo if Net.online and Net.pseudo != "" else String(S().get("nom", "Boy Galsen"))
	var parts := id.split("/")
	var e := ecurie(parts[0])
	if e.is_empty():
		return id
	return e["lutteurs"][int(parts[1])][0]


func force_of(id: String) -> float:
	if id == "joueur":
		return float(S()["force"])
	return float(S()["npc"][id][0])


func pop_of(id: String) -> int:
	if id == "joueur":
		return int(S()["pop"])
	return int(S()["npc"][id][1])


## Cachet d'un lutteur selon sa popularité (payé par le promoteur, gagné ou perdu)
static func cachet_for(pop: int) -> int:
	return 5000 + pop * 500


func record(id: String) -> String:
	var a: Array = [S()["w"], S()["l"]] if id == "joueur" else [S()["npc"][id][2], S()["npc"][id][3]]
	return "%d V – %d D" % [a[0], a[1]]


# --- Écuries : lieux d'entraînement ------------------------------------------------------

func _make_base(e: Dictionary) -> void:
	var city = main.city
	if not city.places.has(e["place"]):
		return
	var origin: Vector3 = city.places[e["place"]]
	var p := _find_open(origin)
	var to_street := Vector3(origin.x - p.x, 0, origin.z - p.z)
	var root := Node3D.new()
	root.name = "Ecurie_" + e["id"]
	add_child(root)
	root.global_position = p
	# La bannière (au fond, côté -Z) se lit depuis la rue
	root.rotation.y = atan2(to_street.x, to_street.z) if to_street.length() > 0.5 else 0.0
	var col := Color(e["color"])
	# Aire d'entraînement en sable, sacs de sable et pneus
	Mk.cyl(root, 4.2, 4.2, 0.06, Vector3(0, 0.03, 0), Color("d8c49a"), false, 24)
	for k in 10:
		var a := k * TAU / 10.0
		Mk.box(root, Vector3(0.55, 0.28, 0.35), Vector3(cos(a) * 4.4, 0.14, sin(a) * 4.4), Color("cdb88e"))
	for k in 3:
		Mk.cyl(root, 0.4, 0.4, 0.22, Vector3(-5.6, 0.11 + k * 0.22, -1.5), Color("1b1b1b"), false, 14)
	# Bannière de l'écurie : panneau à leur couleur avec le nom, sur deux poteaux
	Mk.cyl(root, 0.05, 0.05, 3.0, Vector3(-1.6, 1.5, -5.0), Color("6c757d"))
	Mk.cyl(root, 0.05, 0.05, 3.0, Vector3(1.6, 1.5, -5.0), Color("6c757d"))
	Mk.box(root, Vector3(3.4, 0.9, 0.06), Vector3(0, 2.5, -5.0), col)
	var lab := Mk.label(root, e["name"].to_upper(), Vector3(0, 2.5, -4.95), 40, Color.WHITE, false)
	lab.double_sided = false
	lab.outline_size = 8
	lab.width = 330.0
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bases[e["id"]] = {"pos": p, "node": root, "people": []}
	spots.append({"id": "ecurie", "ecurie": e["id"], "pos": p + root.global_transform.basis * Vector3(0, 0, -3.2), "label": "%s — parler à %s" % [e["name"], e["chef"]]})


## Un terrain dégagé d'environ 6 m de rayon près du lieu : ni bâtiment, ni chaussée
func _find_open(origin: Vector3) -> Vector3:
	for r in [12.0, 18.0, 24.0, 31.0, 39.0, 48.0, 60.0]:
		for k in 16:
			var a: float = k * TAU / 16.0 + r * 0.1
			var p := Vector3(origin.x + cos(a) * r, 0.0, origin.z + sin(a) * r)
			var ok := true
			for s in 9:
				var q := p if s == 0 else p + Vector3(cos(s * TAU / 8.0), 0, sin(s * TAU / 8.0)) * 6.0
				if main.is_inside_building(q) or main.city.in_roadway(q, 1.0):
					ok = false
					break
			if ok:
				return p
	return Vector3(origin.x, 0.0, origin.z)


## Les lutteurs et le chef n'apparaissent que quand le joueur est près (téléphones)
func _update_bases() -> void:
	var pp: Vector3 = main.player.global_position
	for id in _bases:
		var b: Dictionary = _bases[id]
		var near: bool = pp.distance_to(b["pos"]) < 90.0
		if near and b["people"].is_empty():
			var e := ecurie(id)
			var root: Node3D = b["node"]
			var chef := RC.create(root, "homme_tunique", 3)
			chef.position = Vector3(0, 0, -3.2)
			chef.play_clip("talk", 0.0)
			b["people"].append(chef)
			for k in 2:
				var w := RC.create(root, "lutteur1" if k == 0 else "lutteur2", -1)
				w.position = Vector3(-0.45 if k == 0 else 0.45, 0, 0.6)
				w.rotation.y = PI / 2.0 if k == 0 else -PI / 2.0
				w.play_clip("push", 0.0)
				_tint_pagne(w, Color(e["color"]))
				b["people"].append(w)
		elif not near and not b["people"].is_empty():
			for n in b["people"]:
				n.queue_free()
			b["people"] = []


func _tint_pagne(w: Node3D, col: Color) -> void:
	for mi in w.find_children("*", "MeshInstance3D", true, false):
		if "short" in String(mi.name).to_lower():
			var m := StandardMaterial3D.new()
			m.albedo_color = col
			m.roughness = 0.85
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, m)


func _ecurie_menu(eid: String) -> void:
	var e := ecurie(eid)
	var s := S()
	var opts: Array = []
	var member: bool = s["ecurie"] == eid
	if member:
		opts.append(["S'entraîner avec l'écurie (1 h, gratuit)", _train.bind(eid, 0)])
		if s["bout"].is_empty():
			opts.append(["Demander un combat à %s" % e["chef"], _ask_bout.bind(eid)])
		else:
			opts.append(["Mon prochain combat", _show_my_bout])
		opts.append(["Voir les lutteurs de l'écurie", _show_roster.bind(eid)])
		opts.append(["Quitter l'écurie", _leave.bind(eid)])
	else:
		opts.append(["S'entraîner ici (1 h, %s)" % GameState.fcfa(TRAIN_COST), _train.bind(eid, TRAIN_COST)])
		opts.append(["Rejoindre l'écurie (force demandée : %d)" % e["min"], _join.bind(eid)])
		opts.append(["Voir les lutteurs de l'écurie", _show_roster.bind(eid)])
	opts.append(["Calendrier des journées de lutte", _show_calendar])
	var head := "%s — chef : %s\nTa force : %d   Popularité : %d   Bilan : %s" % [e["name"], e["chef"], s["force"], s["pop"], record("joueur")]
	main.hud.show_choices(head, opts, func(): pass)


func _train(eid: String, cost: int) -> void:
	var s := S()
	if int(s["train_day"]) != GameState.day:
		s["train_day"] = GameState.day
		s["train_n"] = 0
	if int(s["train_n"]) >= TRAIN_PER_DAY:
		GameState.notify.emit("Tes muscles sont à bout : reviens demain pour t'entraîner.")
		return
	if cost > 0 and not GameState.spend(cost):
		GameState.notify.emit("Il te faut %s pour t'entraîner ici." % GameState.fcfa(cost))
		return
	s["train_n"] = int(s["train_n"]) + 1
	# Les progrès ralentissent avec le niveau
	var gain := maxi(1, int(round(4.0 - float(s["force"]) / 30.0)) + _rng.randi_range(0, 1))
	s["force"] = mini(int(s["force"]) + gain, 99)
	main.player.model.play_clip("push", 0.2)
	main.hud.fade_through(func():
		GameState.advance_time(60.0)
		GameState.hunger = maxf(GameState.hunger - 8.0, 0.0)
		main.player.model.play_clip("idle", 0.3)
		GameState.notify.emit("Séance de lutte sur le sable : force +%d (%d)." % [gain, s["force"]]))


func _join(eid: String) -> void:
	var e := ecurie(eid)
	var s := S()
	if s["ecurie"] == eid:
		return
	if int(s["force"]) < int(e["min"]):
		GameState.notify.emit("%s : « Reviens quand tu auras %d de force. Entraîne-toi ! »" % [e["chef"], e["min"]])
		return
	if s["ecurie"] != "":
		GameState.notify.emit("Quitte d'abord %s." % ecurie(s["ecurie"])["name"])
		return
	s["ecurie"] = eid
	GameState.notify.emit("Bienvenue à %s ! %s te trouvera des combats dans les journées de lutte." % [e["name"], e["chef"]])


func _leave(eid: String) -> void:
	var s := S()
	if not s["bout"].is_empty():
		GameState.notify.emit("Tu as un combat prévu : honore-le avant de quitter l'écurie.")
		return
	s["ecurie"] = ""
	GameState.notify.emit("Tu as quitté %s." % ecurie(eid)["name"])


func _show_roster(eid: String) -> void:
	var e := ecurie(eid)
	var lines: Array = []
	for k in e["lutteurs"].size():
		var id := "%s/%d" % [eid, k]
		lines.append("%s — force %d, popularité %d, %s" % [wrestler_name(id), int(force_of(id)), pop_of(id), record(id)])
	if S()["ecurie"] == eid:
		lines.append("%s — force %d, popularité %d, %s" % [wrestler_name("joueur"), S()["force"], S()["pop"], record("joueur")])
	main.hud.show_choices("%s\n%s" % [e["name"], "\n".join(lines)], [["OK", func(): pass]], func(): pass)


## Le chef cherche un adversaire d'une autre écurie, de force proche, pour la prochaine journée
func _ask_bout(eid: String) -> void:
	var e := ecurie(eid)
	var s := S()
	var j := _next_journee(true)
	if j.is_empty():
		GameState.notify.emit("%s : « Pas de journée de lutte prévue pour l'instant, repasse demain. »" % e["chef"])
		return
	var best := ""
	var best_d := INF
	for id in s["npc"]:
		if String(id).begins_with(eid + "/") or _on_card(j, id):
			continue
		var d := absf(force_of(id) - float(s["force"])) + _rng.randf() * 6.0
		if d < best_d:
			best_d = d
			best = id
	if best == "":
		return
	var cachet := cachet_for(int(s["pop"]))
	var when := "aujourd'hui" if int(j["day"]) == GameState.day else "demain"
	main.hud.show_choices("%s : « %s organise une journée %s à 17 h au %s.\nJe te mets contre %s (%s, force %d, %s).\nCachet : %s, plus la moitié en prime si tu gagnes. »" % [
		e["chef"], j["promoter"], when, VENUES[j["venue"]]["name"], wrestler_name(best), ecurie(best.split("/")[0])["name"],
		int(force_of(best)), record(best), GameState.fcfa(cachet)], [
		["J'accepte le combat", func():
			s["bout"] = {"day": j["day"], "venue": j["venue"], "opp": best, "cachet": cachet}
			# Le combat du joueur ouvre la journée (les grandes affiches passent en dernier)
			j["bouts"].insert(0, ["joueur", best])
			GameState.notify.emit("Combat signé contre %s, %s à 17 h au %s. Ne sois pas en retard !" % [wrestler_name(best), when, VENUES[j["venue"]]["name"]])],
		["Pas maintenant", func(): pass]], func(): pass)


func _show_my_bout() -> void:
	var b: Dictionary = S()["bout"]
	if b.is_empty():
		return
	var when := "aujourd'hui" if int(b["day"]) == GameState.day else "demain"
	main.hud.show_choices("Ton prochain combat : contre %s, %s à 17 h au %s.\nCachet : %s (+ moitié si tu gagnes)." % [
		wrestler_name(b["opp"]), when, VENUES[b["venue"]]["name"], GameState.fcfa(int(b["cachet"]))], [
		["GPS vers le stade", func(): main.gps.set_waypoint(_venue_pos[b["venue"]], VENUES[b["venue"]]["name"])],
		["OK", func(): pass]], func(): pass)


# --- Calendrier des journées -------------------------------------------------------------

func _on_new_day() -> void:
	var s := S()
	# On garde les journées d'aujourd'hui et à venir
	var keep: Array = []
	for j in s["journees"]:
		if int(j["day"]) >= GameState.day:
			keep.append(j)
	s["journees"] = keep
	if not s["bout"].is_empty() and int(s["bout"]["day"]) < GameState.day:
		s["bout"] = {}
	_ensure_schedule()


func _ensure_schedule() -> void:
	var s := S()
	for d in [GameState.day, GameState.day + 1]:
		var found := false
		for j in s["journees"]:
			if int(j["day"]) == d:
				found = true
		if not found and not (d == GameState.day and GameState.game_minutes > HOUR * 60.0 + 90.0):
			s["journees"].append(_npc_journee(d))


## Journée montée par un promoteur amateur : 3 ou 4 combats entre lutteurs d'écuries différentes, de force proche
func _npc_journee(d: int) -> Dictionary:
	var ids: Array = S()["npc"].keys()
	ids.shuffle()
	var bouts: Array = []
	var used := {}
	var n := _rng.randi_range(3, 4)
	for a in ids:
		if bouts.size() >= n:
			break
		if used.has(a):
			continue
		var best := ""
		var best_d := INF
		for b in ids:
			if used.has(b) or b == a or String(b).split("/")[0] == String(a).split("/")[0]:
				continue
			var dd := absf(force_of(a) - force_of(b))
			if dd < best_d:
				best_d = dd
				best = b
		if best != "" and best_d < 18.0:
			used[a] = true
			used[best] = true
			bouts.append([a, best])
	# Les combats les plus attendus en dernier (choc de clôture)
	bouts.sort_custom(func(x, y): return pop_of(x[0]) + pop_of(x[1]) < pop_of(y[0]) + pop_of(y[1]))
	return {"day": d, "venue": "medina" if _rng.randf() < 0.65 else "arene", "promoter": PROMOTERS.pick_random(),
		"bouts": bouts, "player": false, "cost": 0, "done": false}


func _next_journee(for_signing := false) -> Dictionary:
	var best := {}
	for j in S()["journees"]:
		if j["done"]:
			continue
		var d: int = j["day"]
		if d == GameState.day and GameState.game_minutes > (HOUR - 1) * 60.0 and for_signing:
			continue # trop tard pour signer aujourd'hui
		if best.is_empty() or d < int(best["day"]):
			best = j
	return best


func _on_card(j: Dictionary, id: String) -> bool:
	for b in j["bouts"]:
		if id in b:
			return true
	return false


func _show_calendar() -> void:
	var lines: Array = []
	for j in S()["journees"]:
		if j["done"]:
			continue
		var when := "Aujourd'hui" if int(j["day"]) == GameState.day else "Demain"
		lines.append("%s 17 h — %s, par %s :" % [when, VENUES[j["venue"]]["name"], "toi" if j["player"] else j["promoter"]])
		for b in j["bouts"]:
			lines.append("    %s contre %s" % [wrestler_name(b[0]), wrestler_name(b[1])])
	if lines.is_empty():
		lines.append("Aucune journée prévue.")
	main.hud.show_choices("Journées de lutte\n" + "\n".join(lines), [["OK", func(): pass]], func(): pass)


func calendar_lines() -> Array:
	var lines: Array = []
	for j in S()["journees"]:
		if j["done"]:
			continue
		var when := "Aujourd'hui" if int(j["day"]) == GameState.day else "Demain"
		var card: Array = []
		for b in j["bouts"]:
			card.append("%s – %s" % [wrestler_name(b[0]), wrestler_name(b[1])])
		lines.append("%s 17 h, %s (%s) : %s" % [when, VENUES[j["venue"]]["name"], "ta journée" if j["player"] else j["promoter"], " ; ".join(card)])
	return lines


# --- Le joueur promoteur ---------------------------------------------------------------------

func _bureau_menu(venue: String) -> void:
	var v: Dictionary = VENUES[venue]
	var d := GameState.day if GameState.game_minutes < ORGANIZE_BEFORE * 60.0 else GameState.day + 1
	for j in S()["journees"]:
		if int(j["day"]) == d and j["player"]:
			GameState.notify.emit("Tu organises déjà la journée de %s." % ("ce soir" if d == GameState.day else "demain"))
			return
	var opts: Array = []
	for n in [3, 5]:
		var card := _build_card(n)
		var cost := _card_cost(card, venue)
		opts.append(["%s journée : %d combats — coût %s" % ["Petite" if n == 3 else "Grande", card.size(), GameState.fcfa(cost)], _confirm_organize.bind(venue, d, card)])
	opts.append(["Calendrier des journées", _show_calendar])
	main.hud.show_choices("%s — organiser une journée de lutte (%s à 17 h)\nLocation du stade : %s. Tu paies d'avance la location et les cachets ;\nla billetterie (%s la place) te revient, selon la popularité de ton affiche." % [
		v["name"], "aujourd'hui" if d == GameState.day else "demain", GameState.fcfa(v["rent"]), GameState.fcfa(v["ticket"])], opts, func(): pass)


## Affiche : les meilleurs combats disponibles (lutteurs de force proche, écuries différentes)
func _build_card(n: int) -> Array:
	var ids: Array = S()["npc"].keys()
	ids.sort_custom(func(a, b): return pop_of(a) > pop_of(b))
	var used := {}
	var card: Array = []
	for a in ids:
		if card.size() >= n:
			break
		if used.has(a):
			continue
		for b in ids:
			if used.has(b) or b == a or String(b).split("/")[0] == String(a).split("/")[0]:
				continue
			if absf(force_of(a) - force_of(b)) < 15.0:
				used[a] = true
				used[b] = true
				card.append([a, b])
				break
	card.reverse() # choc de clôture en dernier
	return card


func _card_cost(card: Array, venue: String) -> int:
	var cost: int = VENUES[venue]["rent"]
	for b in card:
		cost += cachet_for(pop_of(b[0])) + cachet_for(pop_of(b[1]))
	return cost


func _confirm_organize(venue: String, d: int, card: Array) -> void:
	var cost := _card_cost(card, venue)
	var lines: Array = []
	for b in card:
		lines.append("%s contre %s" % [wrestler_name(b[0]), wrestler_name(b[1])])
	main.hud.show_choices("Ton affiche au %s :\n%s\nCoût total : %s" % [VENUES[venue]["name"], "\n".join(lines), GameState.fcfa(cost)], [
		["Signer les contrats et louer le stade", func():
			if not GameState.spend(cost):
				GameState.notify.emit("Il te faut %s pour monter cette journée." % GameState.fcfa(cost))
				return
			var s := S()
			# Le stade est à toi ce jour-là : la journée du promoteur amateur est annulée (sauf si ton combat y est)
			var keep: Array = []
			for j in s["journees"]:
				if int(j["day"]) == d and not j["player"]:
					for b in j["bouts"]:
						if "joueur" in b:
							card.insert(0, b)
							s["bout"]["venue"] = venue
					continue
				keep.append(j)
			keep.append({"day": d, "venue": venue, "promoter": "toi", "bouts": card, "player": true, "cost": cost, "done": false})
			s["journees"] = keep
			GameState.notify.emit("Journée signée ! Rendez-vous %s à 17 h au %s. Les affiches sont collées dans tout Dakar." % [
				"ce soir" if d == GameState.day else "demain", VENUES[venue]["name"]])],
		["Annuler", func(): pass]], func(): pass)


## Billetterie d'une journée organisée par le joueur : dépend de la popularité de l'affiche (risque de perte)
func _gate(j: Dictionary) -> int:
	var pop := 0.0
	for b in j["bouts"]:
		pop += pop_of(b[0]) + pop_of(b[1])
	pop /= maxf(1.0, j["bouts"].size() * 2.0)
	var factor := 0.55 + pop / 100.0 * 1.0 + _rng.randf_range(-0.2, 0.25)
	return int(int(j["cost"]) * factor)


# --- Stades : centre du cercle de lutte ----------------------------------------------------

func _find_venues() -> void:
	# Arène de la Médina : construite dans la carte (tools/bake_dakar.gd), distincte du stade de football
	var m = main.city.find_child("CentreArene", true, false)
	if m != null:
		_venue_pos["medina"] = m.global_position
		var door: Vector2 = m.get_meta("door", Vector2.RIGHT)
		_venue_door["medina"] = Vector3(door.x, 0, door.y)
		_venue_seat["medina"] = float(m.get_meta("seat_r", 11.4))
	if main.arena:
		_venue_pos["arene"] = main.arena.ORIGIN
		_venue_door["arene"] = Vector3(0, 0, 1)


# --- Chaque image ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_update_bases()
		_check_schedule()
	if _fight:
		_update_fight(delta)
		return
	if _live.is_empty():
		status = ""
		return
	_run_live(delta)


func _check_schedule() -> void:
	if not _live.is_empty():
		return
	for j in S()["journees"]:
		if j["done"] or int(j["day"]) != GameState.day or GameState.game_minutes < HOUR * 60.0:
			continue
		var centre: Vector3 = _venue_pos.get(j["venue"], Vector3.ZERO)
		var pp: Vector3 = main.player.get_world_position()
		if GameState.game_minutes < HOUR * 60.0 + 120.0 and pp.distance_to(centre) < NEAR:
			_start_live(j)
		elif GameState.game_minutes >= HOUR * 60.0 + 20.0:
			_simulate(j) # loin du stade : on apprend seulement les résultats
		return


## Résultats sans y assister
func _simulate(j: Dictionary) -> void:
	j["done"] = true
	var lines: Array = []
	for b in j["bouts"]:
		if "joueur" in b:
			_forfeit()
			lines.append("%s gagne par forfait (tu n'es pas venu)" % wrestler_name(b[1] if b[0] == "joueur" else b[0]))
			continue
		var w := _decide(b[0], b[1])
		_apply_result(b, w)
		lines.append("%s bat %s" % [wrestler_name(b[w]), wrestler_name(b[1 - w])])
	if j["player"]:
		var gate := _gate(j)
		GameState.add_money(gate, "Billetterie de ta journée de lutte")
		lines.append("Bilan : %s" % _bilan(j, gate))
	if j["player"] or S()["ecurie"] != "":
		GameState.notify.emit("Résultats de la journée au %s : %s" % [VENUES[j["venue"]]["name"], " ; ".join(lines)])


func _bilan(j: Dictionary, gate: int) -> String:
	var profit: int = gate - int(j["cost"])
	return "%s de recette pour %s de dépenses (%s%s)" % [GameState.fcfa(gate), GameState.fcfa(int(j["cost"])), "+" if profit >= 0 else "", GameState.fcfa(profit)]


func _forfeit() -> void:
	var s := S()
	s["bout"] = {}
	s["pop"] = maxi(0, int(s["pop"]) - 5)
	s["l"] = int(s["l"]) + 1


## 0 ou 1 : le vainqueur, selon les forces (le plus fort gagne plus souvent, pas toujours)
func _decide(a: String, b: String) -> int:
	var p := 1.0 / (1.0 + exp(-(force_of(a) - force_of(b)) / 10.0))
	return 0 if _rng.randf() < p else 1


func _apply_result(b: Array, w: int) -> void:
	var s := S()
	for k in 2:
		var id: String = b[k]
		var won := k == w
		if id == "joueur":
			s["w" if won else "l"] = int(s["w" if won else "l"]) + 1
			s["pop"] = clampi(int(s["pop"]) + (6 if won else -2), 0, 100)
			s["force"] = mini(int(s["force"]) + (1 if won else 0), 99)
		else:
			var st: Array = s["npc"][id]
			st[2 if won else 3] = int(st[2 if won else 3]) + 1
			st[1] = clampi(int(st[1]) + (3 if won else -2), 0, 100)
			st[0] = clampi(int(st[0]) + (1 if won and _rng.randf() < 0.4 else 0), 0, 99)


# --- Journée en direct au stade ------------------------------------------------------------

func _start_live(j: Dictionary) -> void:
	_live = j
	_bout = -1
	var centre: Vector3 = _venue_pos[j["venue"]]
	if j["venue"] == "arene" and main.arena:
		main.arena.lutte_busy = true
		for w in main.arena._w:
			w.visible = false
	else:
		_build_ring(centre, j["venue"])
	GameState.notify.emit("La journée de lutte commence au %s ! Organisée par %s." % [VENUES[j["venue"]]["name"], "toi" if j["player"] else j["promoter"]])
	Audio.set_radio_track(Audio.find_track("Sabar, Tama & Mbeur"))
	Audio.set_radio(true)
	_next_bout()


## Cercle de sable posé sur la pelouse, sacs de sable tout autour, spectateurs debout
func _build_ring(centre: Vector3, venue := "") -> void:
	_ring = Node3D.new()
	add_child(_ring)
	_ring.global_position = centre
	var arena := _venue_seat.has(venue)
	if not arena:
		Mk.cyl(_ring, RING_R, RING_R, 0.08, Vector3(0, 0.04, 0), Color("dcc79c"), false, 32)
	for k in 28:
		var a := k * TAU / 28.0
		var sack := Mk.box(_ring, Vector3(0.7, 0.3, 0.4), Vector3(cos(a) * (RING_R + 0.2), 0.15, sin(a) * (RING_R + 0.2)), Color("efe6d0"))
		sack.rotation.y = -a
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var n := 18 if Graphics.get_value("char_range") > 80.0 else 10
	var door: Vector3 = _venue_door.get(venue, Vector3(0, 0, 1))
	for k in n:
		var a := k * TAU / n + rng.randf_range(-0.1, 0.1)
		var r := RING_R + 2.5 + rng.randf() * 3.0
		var h := 0.0
		if arena:
			# Spectateurs debout dans les gradins (pas dans l'allée de l'entrée)
			if absf(angle_difference(a, atan2(door.z, door.x))) < 0.45:
				a += 0.9
			var tier := rng.randi_range(0, 6)
			r = float(_venue_seat[venue]) + tier * 0.85 + 0.2
			h = 0.45 * (tier + 1)
		var c := RC.create(_ring, RC.random_ped_name(rng), k)
		c.position = Vector3(cos(a) * r, h, sin(a) * r)
		c.rotation.y = atan2(cos(a), sin(a))
		c.play_clip("dance" if k % 3 == 0 else "idle", 0.0)
		_crowd.append(c)


func _next_bout() -> void:
	for f in _fighters:
		if is_instance_valid(f) and f != main.player.model:
			f.queue_free()
	_fighters = []
	_player_side = -1
	_bout += 1
	if _bout >= _live["bouts"].size():
		_end_live()
		return
	var b: Array = _live["bouts"][_bout]
	var centre: Vector3 = _venue_pos[_live["venue"]]
	for k in 2:
		var id: String = b[k]
		if id == "joueur":
			if main.player.get_world_position().distance_to(centre) > 60.0 or main.player.current_vehicle != null:
				# Pas au bord du cercle à l'appel de ton nom : forfait
				_forfeit()
				GameState.notify.emit("On appelle ton nom au %s... tu n'es pas là : défaite par forfait !" % VENUES[_live["venue"]]["name"])
				var other: String = b[1 - k]
				var st: Array = S()["npc"][other]
				st[2] = int(st[2]) + 1
				_bout_pause()
				return
			_player_side = k
			main.player.global_position = centre + Vector3(-4.0 if k == 0 else 4.0, 0.3, 0)
			main.player.model.rotation.y = -PI / 2.0 if k == 0 else PI / 2.0
			_fighters.append(main.player.model)
			main.player.frozen = true
			main.player.model.play_clip("dance", 0.3)
		else:
			var w := RC.create(self, "lutteur1" if (hash(id) % 2 == 0) else "lutteur2", -1)
			w.global_position = centre + Vector3(-4.0 if k == 0 else 4.0, 0.0 if _live["venue"] == "medina" else 0.3, 0)
			w.rotation.y = -PI / 2.0 if k == 0 else PI / 2.0
			w.play_clip("dance", 0.0)
			_tint_pagne(w, Color(ecurie(id.split("/")[0])["color"]))
			_fighters.append(w)
	_phase = "bakk"
	_t = 0.0
	var title := "choc de clôture" if _bout == _live["bouts"].size() - 1 and _bout > 0 else "combat %d" % (_bout + 1)
	GameState.notify.emit("%s : %s (%s) contre %s (%s). Bàkk au son du sabar !" % [title.capitalize(), wrestler_name(b[0]), _ecurie_short(b[0]), wrestler_name(b[1]), _ecurie_short(b[1])])


func _ecurie_short(id: String) -> String:
	if id == "joueur":
		return ecurie(S()["ecurie"])["name"] if S()["ecurie"] != "" else "sans écurie"
	return ecurie(id.split("/")[0])["name"]


func _bout_pause() -> void:
	_phase = "pause"
	_t = 0.0


func _run_live(delta: float) -> void:
	_t += delta
	if _bout < 0 or _bout >= _live["bouts"].size():
		return
	var b: Array = _live["bouts"][_bout]
	var centre: Vector3 = _venue_pos[_live["venue"]]
	var y := 0.3 if _live["venue"] == "arene" else 0.0
	match _phase:
		"bakk":
			status = "BÀKK — %s et %s dansent et défient l'adversaire" % [wrestler_name(b[0]), wrestler_name(b[1])]
			if _t > 6.0:
				_phase = "approche"
				_t = 0.0
				for f in _fighters:
					f.play_clip("walk", 0.3, 0.8)
		"approche":
			status = "Les lutteurs s'avancent au centre du cercle..."
			for k in _fighters.size():
				var f: Node3D = _fighters[k]
				var target := centre + Vector3(-0.55 if k == 0 else 0.55, y if f != main.player.model else 0.3, 0)
				var node: Node3D = main.player if f == main.player.model else f
				node.global_position = node.global_position.move_toward(target, delta * 1.3)
			if _t > 3.5:
				_phase = "corps"
				_t = 0.0
				for f in _fighters:
					f.play_clip("push", 0.3)
				if _player_side != -1:
					_start_player_fight(b[1 - _player_side])
				else:
					GameState.notify.emit("Empoignade ! " + CHEERS.pick_random())
		"corps":
			if _player_side != -1:
				return # le mini-jeu du joueur décide
			status = "CORPS À CORPS — %s contre %s" % [wrestler_name(b[0]), wrestler_name(b[1])]
			var sway := sin(_t * 1.7) * 0.3
			for k in _fighters.size():
				_fighters[k].global_position = centre + Vector3((-0.55 if k == 0 else 0.55) + sway, y, 0)
			if _t > 7.0:
				var w := _decide(b[0], b[1])
				_finish_bout(w)
		"fin":
			status = "« Daanu na ! » Le vainqueur danse devant son public"
			if _t > 5.0:
				_bout_pause()
		"pause":
			status = "Pause : les griots chantent, les supporters dansent..."
			if _t > 3.0:
				if _player_side != -1:
					main.player.frozen = false
					# Sortie par l'allée de l'entrée (les gradins entourent le cercle)
					main.player.global_position = centre + _venue_door.get(_live["venue"], Vector3(0, 0, 1)) * (RING_R + 3.0) + Vector3(0, 0.5, 0)
				_next_bout()


func _finish_bout(w: int) -> void:
	var b: Array = _live["bouts"][_bout]
	_apply_result(b, w)
	_fighters[1 - w].play_clip("fall", 0.15)
	_fighters[w].play_clip("dance", 0.3)
	GameState.notify.emit("« Daanu na ! » %s est à terre : victoire de %s !" % [wrestler_name(b[1 - w]), wrestler_name(b[w])])
	if _player_side != -1:
		var s := S()
		var cachet := int(s["bout"].get("cachet", cachet_for(int(s["pop"]))))
		var won := w == _player_side
		var pay := cachet + (cachet / 2 if won else 0)
		GameState.add_money(pay, "Cachet de lutte%s" % (" + prime de victoire" if won else ""))
		if auto_press:
			print("LUTTE combat du joueur : %s, payé %d, bilan %s, popularité %d" % ["gagné" if won else "perdu", pay, record("joueur"), s["pop"]])
		s["bout"] = {}
	_phase = "fin"
	_t = 0.0


func _end_live() -> void:
	var j := _live
	j["done"] = true
	var msg := "Fin de la journée de lutte au %s." % VENUES[j["venue"]]["name"]
	if j["player"]:
		var gate := _gate(j)
		GameState.add_money(gate, "Billetterie de ta journée de lutte")
		msg += " " + _bilan(j, gate)
	GameState.notify.emit(msg)
	Audio.set_radio(false)
	for f in _fighters:
		if is_instance_valid(f) and f != main.player.model:
			f.queue_free()
	_fighters = []
	for c in _crowd:
		if is_instance_valid(c):
			c.queue_free()
	_crowd = []
	if _ring:
		_ring.queue_free()
		_ring = null
	if j["venue"] == "arene" and main.arena:
		main.arena.lutte_busy = false
		for w in main.arena._w:
			w.visible = true
	_live = {}
	status = ""


# --- Combat du joueur : mini-jeu de timing (comme à l'arène) --------------------------------

func _start_player_fight(opp: String) -> void:
	_fight = true
	_hits = 0
	_misses = 0
	_cursor = 0.0
	# Plus l'adversaire est fort par rapport à toi, plus le curseur va vite et la zone est étroite
	var gap := clampf((force_of(opp) - float(S()["force"])) / 40.0, -0.5, 1.0)
	_speed = 0.9 + gap * 0.5
	_new_zone(gap)
	_bar = Control.new()
	_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar.custom_minimum_size = Vector2(520, 60)
	_bar.position = Vector2(-260, -260)
	_bar.draw.connect(_draw_bar)
	main.hud._root.add_child(_bar)
	GameState.notify.emit("Combat contre %s (force %d, toi %d) ! ACTION quand le curseur est dans la zone verte. 3 prises pour gagner." % [
		wrestler_name(opp), int(force_of(opp)), S()["force"]])


func _new_zone(gap := 0.0) -> void:
	var w := clampf(_rng.randf_range(0.14, 0.2) - gap * 0.06 - _hits * 0.02, 0.06, 0.3)
	var c := _rng.randf_range(0.2, 0.8)
	_zone = Vector2(c - w / 2.0, c + w / 2.0)


func _draw_bar() -> void:
	var w := 520.0
	_bar.draw_rect(Rect2(0, 0, w, 40), Color(0, 0, 0, 0.6))
	_bar.draw_rect(Rect2(_zone.x * w, 0, (_zone.y - _zone.x) * w, 40), Color("2dc653"))
	_bar.draw_rect(Rect2(_cursor * w - 3, -6, 6, 52), Color.WHITE)
	_bar.draw_string(_bar.get_theme_default_font(), Vector2(0, 62), "Prises : %d / 3      Ratés : %d / 3" % [_hits, _misses], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


func _update_fight(delta: float) -> void:
	_cursor += _cursor_dir * delta * (_speed + _hits * 0.25)
	if _cursor > 1.0:
		_cursor = 1.0
		_cursor_dir = -1.0
	elif _cursor < 0.0:
		_cursor = 0.0
		_cursor_dir = 1.0
	status = "COMBAT — place ta prise au bon moment !"
	if auto_press and _cursor >= _zone.x + 0.01 and _cursor <= _zone.y - 0.01:
		_press()
		return
	if _bar:
		_bar.queue_redraw()


func _press() -> void:
	var opp: Node3D = _fighters[1 - _player_side]
	if _cursor >= _zone.x and _cursor <= _zone.y:
		_hits += 1
		opp.play_clip("hit", 0.1)
		GameState.notify.emit("Belle prise ! " + CHEERS.pick_random())
		if _hits >= 3:
			_end_player_fight(true)
			return
		_new_zone()
		opp.play_clip("push", 0.4)
	else:
		_misses += 1
		main.player.model.play_clip("hit", 0.1)
		GameState.notify.emit("Raté ! Ton adversaire te bouscule.")
		if _misses >= 3:
			_end_player_fight(false)
			return
		main.player.model.play_clip("push", 0.4)


func _end_player_fight(won: bool) -> void:
	_fight = false
	if _bar:
		_bar.queue_free()
		_bar = null
	if not won:
		GameState.damage(10.0, "« Dama daanu... » Tu es tombé.")
	_finish_bout(_player_side if won else 1 - _player_side)


# --- Interactions -----------------------------------------------------------------------------

func _spot_near(pp: Vector3) -> Variant:
	for s in spots:
		if Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length() < 2.6:
			return s
	return null


func get_hint() -> String:
	if _fight:
		return "Placer ta prise !"
	if main.player.current_vehicle != null or main.player.riding != null:
		return ""
	var s = _spot_near(main.player.global_position)
	return "" if s == null else s["label"]


func try_interact() -> bool:
	if _fight:
		_press()
		return true
	if main.player.current_vehicle != null or main.player.riding != null:
		return false
	var s = _spot_near(main.player.global_position)
	if s == null:
		return false
	if s["id"] == "ecurie":
		_ecurie_menu(s["ecurie"])
	elif s["id"] == "bureau":
		if Net.online and main.net_lutte_ui:
			main.hud.show_choices(VENUES[s["venue"]]["name"] + " — bureau des promoteurs", [
				["Organiser une journée (lutteurs de Dakar)", _bureau_menu.bind(s["venue"])],
				["Organiser une journée entre joueurs (en ligne)", main.net_lutte_ui.organize.bind(s["venue"], _venue_pos[s["venue"]] + (Vector3(0, 0, -18.0) if s["venue"] == "arene" else Vector3.ZERO))],
				["Calendrier des journées", _show_calendar]], func(): pass)
		else:
			_bureau_menu(s["venue"])
	return true


# --- Tests -------------------------------------------------------------------------------------

## Test : -- --lutte-test : écurie, entraînement, combat signé, journée simulée et journée organisée
func self_test() -> void:
	var s := S()
	s["force"] = 50
	_join("diasse")
	_ask_bout("diasse")
	print("LUTTE écurie=%s force=%d bases=%d stades=%s" % [s["ecurie"], s["force"], _bases.size(), _venue_pos.keys()])
	print("LUTTE calendrier : ", calendar_lines())
	var card := _build_card(3)
	print("LUTTE affiche promoteur : %s coût=%d" % [card.map(func(b): return "%s-%s" % [wrestler_name(b[0]), wrestler_name(b[1])]), _card_cost(card, "medina")])
