extends Node3D
## Emploi réaliste : chaque travail a un patron qui recrute.
## - On va voir le patron sur place (ou on le trouve dans l'appli « Liggéey » du téléphone).
## - Conditions d'embauche : expérience, permis de conduire, pas d'ennuis avec la police.
## - Entretien : une question du métier (rendre la monnaie, commission, code de la route...).
## - Contrat : horaires d'ouverture, paie remise par le patron en fin de service, réputation,
##   promotion après de bons services, renvoi si l'on abandonne son poste ou si l'on a affaire à la police.
## Métiers propres à Dakar : taximan au « versement » (on verse sa part au propriétaire du taxi
## et on garde le reste), apprenti de car rapide (crier la destination, encaisser les passagers).
## L'auto-école délivre le permis après un examen du code de la route.

const RealCharacter = preload("res://scripts/util/real_character.gd")
const Mk = preload("res://scripts/util/mk.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")

const TALK_RANGE := 2.6
const VERSEMENT := 5000
const PERMIS_PRICE := 15000
const CAR_RAPIDE_STOPS := ["Gare routière Petersen", "Marché Sandaga", "Marché Tilène", "Grande Mosquée", "Place de l'Indépendance", "Gare de Dakar"]
const PERMIS_ITEM := "Permis de conduire"

## id → patron et contrat
## place, décalage le long du trottoir, modèle, nom, rôle, métier, horaires [[début, fin], ...],
## conditions {experience: services faits ailleurs, permis: true}, question d'entretien [question, bonne réponse, mauvaises...]
const EMPLOYERS := {
	"livreur": {"place": "Chez Adja", "along": 5.0, "model": "femme_maman", "name": "Adja Diallo", "role": "Patronne du restaurant",
		"job": "Livreur de thiéboudienne", "hours": [[11, 15], [18, 23]], "req": {},
		"pay": "1 000 FCFA par livraison + pourboires",
		"q": ["Le client habite loin et le thiéb refroidit. Que fais-tu ?", "Je file vite, prudemment, et je livre chaud", "Je goûte un peu en route", "Je laisse tomber la commande"]},
	"maiga": {"place": "Restaurant Maïga", "along": 4.0, "model": "homme_tunique", "name": "Amadou Maïga", "role": "Gérant du fast-food Maïga",
		"job": "Serveur chez Maïga", "hours": [[6, 24]], "req": {},
		"pay": "600 FCFA par commande servie",
		"q": ["Que mets-tu dans un sandwich Maïga complet ?", "Pain, brochettes de viande, spaghetti et sauce piment", "Du poisson cru", "Juste du pain sec"]},
	"cafe": {"place": "Café Touba", "along": -4.0, "model": "homme_tunique", "name": "Serigne Mbaye", "role": "Propriétaire du stand de café",
		"job": "Vendeur de café Touba", "hours": [[6, 12], [16, 23]], "req": {},
		"pay": "150 FCFA par tasse vendue",
		"q": ["Combien coûte une tasse de café Touba à mon stand ?", "150 FCFA", "1 000 FCFA", "25 FCFA"]},
	"apprenti": {"place": "Gare routière Petersen", "along": 14.0, "model": "homme_afro", "name": "Modou Ndiaye", "role": "Chauffeur de car rapide",
		"job": "Apprenti de car rapide", "hours": [[6, 21]], "req": {},
		"pay": "30 % de la recette des passagers",
		"q": ["Le car est plein et un client veut monter. Que dis-tu ?", "« Toog ! Il y a toujours de la place ! » (assieds-toi)", "« Non, va-t'en ! »", "Je descends lui laisser ma place"]},
	"om": {"place": "Orange Money", "along": 3.0, "model": "femme_ville", "name": "Fatou Sow", "role": "Superviseuse Orange Money",
		"job": "Agent Orange Money", "hours": [[8, 20]], "req": {"experience": 2},
		"pay": "1 % de commission sur chaque opération",
		"q": ["Un client dépose 10 000 FCFA. Quelle est ta commission de 1 % ?", "100 FCFA", "1 000 FCFA", "10 FCFA"]},
	"wave": {"place": "Wave", "along": 3.0, "model": "homme_ville", "name": "Ousmane Ba", "role": "Superviseur Wave",
		"job": "Agent Wave", "hours": [[8, 20]], "req": {"experience": 2},
		"pay": "1 % de commission sur chaque opération",
		"q": ["Quelqu'un t'appelle et demande ton code secret « pour vérifier ». Que fais-tu ?", "Je refuse : c'est une arnaque", "Je le donne, c'est sûrement Wave", "Je donne la moitié du code"]},
	"jadida": {"place": "Jadida", "along": 7.0, "model": "femme_jupe", "name": "Mme Ndiaye", "role": "Gérante du supermarché",
		"job": "Caissier chez Jadida", "hours": [[8, 21]], "req": {"experience": 3},
		"pay": "250 FCFA par client",
		"q": ["Un client paie avec 5 000 FCFA pour 3 250 FCFA d'achats. Combien lui rends-tu ?", "1 750 FCFA", "2 750 FCFA", "1 250 FCFA"]},
	"jumbo": {"place": "Jumbo", "along": -9.0, "model": "homme_age", "name": "Moussa Fall", "role": "Chef du dépôt Jumbo",
		"job": "Livreur Jumbo (camionnette)", "hours": [[7, 18]], "req": {"permis": true, "experience": 3},
		"pay": "1 200 FCFA par boutique + prime de tournée",
		"q": ["Le feu passe à l'orange juste devant toi. Que fais-tu ?", "Je m'arrête si je peux le faire sans danger", "J'accélère pour passer", "Je klaxonne"]},
	"taxi": {"place": "Garage Taxi", "along": 6.0, "model": "homme_ville", "name": "Pape Diop", "role": "Propriétaire de taxis",
		"job": "Taximan au versement", "hours": [], "req": {"permis": true, "experience": 5},
		"pay": "Tu gardes les courses, tu verses 5 000 FCFA par service",
		"q": ["Un client te demande de rouler vite au milieu des piétons. Que fais-tu ?", "Je reste prudent : la sécurité d'abord", "Je fonce, le client est roi", "Je le fais descendre sans le faire payer"]},
}
## Examen du code de la route : [question, bonne réponse, mauvaises...]
const CODE_QUESTIONS := [
	["Que signifie un panneau STOP ?", "Arrêt obligatoire, puis on repart quand c'est libre", "Ralentir seulement", "Interdit de klaxonner"],
	["En ville, la vitesse est limitée à :", "50 km/h", "90 km/h", "Pas de limite"],
	["Un piéton s'engage sur le passage piéton :", "Je m'arrête pour le laisser passer", "Je klaxonne pour qu'il recule", "Je passe avant lui"],
	["Le feu est rouge :", "Je m'arrête et j'attends le vert", "Je passe si personne ne vient", "Je ralentis et je passe"],
	["Au rond-point, qui a la priorité ?", "Les véhicules déjà engagés dans le rond-point", "Celui qui arrive à droite", "Le plus gros véhicule"],
]

var main
var bosses := {} ## id → {node, pos, label}
var shift := "" ## métier en cours de service ("" = aucun)
var _due := 0 ## paie accumulée pendant le service
var _shift_count := 0 ## unités de travail faites pendant le service
var _taxi = null ## taxi confié par le patron
var _car = null ## car rapide de l'apprenti
var _stop_window := 0.0
var _stop_name := ""
var _cried := false
var _school_pos := Vector3.ZERO


func _ready() -> void:
	var city = main.city
	for id in EMPLOYERS:
		var e: Dictionary = EMPLOYERS[id]
		if not city.places.has(e["place"]):
			continue
		var info: Array = city.place_info[e["place"]]
		var n := Vector3(info[3], 0, info[4])
		var f := Vector3(info[7], 0, info[8]) if info.size() > 8 else Vector3(-n.z, 0, n.x)
		var pos: Vector3 = city.places[e["place"]] + f * float(e["along"]) + n * 1.1
		var holder := Node3D.new()
		add_child(holder)
		holder.global_position = Vector3(pos.x, 0.16, pos.z)
		if main.get("enterprises") != null and main.enterprises.handles(id):
			# Entreprise visitable : le patron reçoit dans son bureau ; ici, l'entrée et son enseigne
			# (pas de texte flottant : le nom de l'entreprise est sur la façade de son bâtiment)
			var sign := Label3D.new()
			sign.visible = false
			holder.add_child(sign)
			var door: Vector3 = main.enterprises.add_entrance(id, holder.global_position, n, f)
			holder.global_position = door
			bosses[id] = {"node": holder, "pos": door, "label": sign, "remote": true}
			continue
		var c = RealCharacter.create(holder, e["model"], hash(id) % 997)
		c.rotation.y = atan2(-n.x, -n.z) + PI
		c.play_clip("talk", 0.0)
		# Pas de nom flottant au-dessus du patron : on le découvre en l'abordant (« Parler à … »)
		var lab := Label3D.new()
		lab.visible = false
		holder.add_child(lab)
		bosses[id] = {"node": holder, "pos": holder.global_position, "label": lab}
	# Auto-école (permis de conduire), à côté de la gare
	if city.places.has("Gare de Dakar"):
		var gi: Array = city.place_info["Gare de Dakar"]
		var gn := Vector3(gi[3], 0, gi[4])
		var gf := Vector3(gi[7], 0, gi[8]) if gi.size() > 8 else Vector3(-gn.z, 0, gn.x)
		_school_pos = city.places["Gare de Dakar"] - gf * 24.0 + gn * 1.1
		var h := Node3D.new()
		add_child(h)
		h.global_position = Vector3(_school_pos.x, 0.16, _school_pos.z)
		var inst = RealCharacter.create(h, "homme_age", 31)
		inst.rotation.y = atan2(-gn.x, -gn.z) + PI
		inst.play_clip("talk", 0.0)
		Mk.box(h, Vector3(1.2, 0.8, 0.08), Vector3(0, 2.9, -0.6), Color("1d3557"))
		Mk.label(h, "AUTO-ÉCOLE", Vector3(0, 2.9, -0.66), 36, Color.WHITE, false).rotation.y = PI
		_school_pos = h.global_position
	_refresh_labels()


# --- État (sauvegardé dans GameState.employment) -----------------------------------

func state(id: String) -> Dictionary:
	if not GameState.employment.has(id):
		GameState.employment[id] = {"hired": false, "rep": 0, "shifts": 0, "promoted": false, "fired_at": -1}
	return GameState.employment[id]


func is_hired(id: String) -> bool:
	return state(id)["hired"]


func experience() -> int:
	return int(GameState.employment.get("_experience", 0))


func has_permis() -> bool:
	return GameState.inventory.get(PERMIS_ITEM, 0) > 0


func is_open(id: String) -> bool:
	var hours: Array = EMPLOYERS[id]["hours"]
	if hours.is_empty():
		return true
	var h := GameState.game_minutes / 60.0
	for r in hours:
		if h >= float(r[0]) and h < float(r[1]):
			return true
	return false


func hours_text(id: String) -> String:
	var hours: Array = EMPLOYERS[id]["hours"]
	if hours.is_empty():
		return "jour et nuit"
	var parts: Array = []
	for r in hours:
		parts.append("%dh-%dh" % [r[0], r[1]])
	return " et ".join(parts)


## Ce qui manque pour être embauché ("" = rien)
func missing(id: String) -> String:
	var req: Dictionary = EMPLOYERS[id]["req"]
	var st := state(id)
	if int(st["fired_at"]) >= 0 and experience() < int(st["fired_at"]) + 3:
		return "Tu as été renvoyé : reviens après 3 services ailleurs"
	if GameState.wanted > 0:
		return "Pas d'embauche quand la police te recherche"
	if req.get("permis", false) and not has_permis():
		return "Il faut le permis de conduire (auto-école Teranga, près de la gare)"
	var need: int = req.get("experience", 0)
	if experience() < need:
		return "Il faut de l'expérience : %d services faits ailleurs (tu en as %d)" % [need, experience()]
	return ""


func pay_mult(id: String) -> float:
	var st := state(id)
	return (1.25 if st["promoted"] else 1.0) * float(st.get("rate", 1.0))


const CONTRACTS := {"journalier": "Journalier", "cdd": "CDD de 3 mois", "cdi": "CDI"}
## Seuil de réputation qui fait perdre l'emploi, selon la protection du contrat
const FIRE_AT := {"journalier": -2, "cdd": -3, "cdi": -6}


func contract_text(id: String) -> String:
	var st := state(id)
	if not st.has("contract"):
		return ""
	return "%s, salaire %+d %%" % [CONTRACTS[st["contract"]], int(round((float(st.get("rate", 1.0)) - 1.0) * 100.0))]


## Pouvoir de négociation : expérience, permis, réputation et un peu de chance
func _leverage(id: String) -> int:
	var st := state(id)
	return experience() * 4 + (10 if has_permis() else 0) + int(st["rep"]) * 3 + int(st["shifts"]) * 2 + randi_range(0, 30)


## Le métier en cours peut-il être exercé ? (appelé par job_manager et business)
func can_work(id: String) -> bool:
	if not is_hired(id):
		GameState.notify.emit("Il faut d'abord être embauché : va voir %s (%s)." % [EMPLOYERS[id]["name"], EMPLOYERS[id]["role"].to_lower()])
		return false
	if not is_open(id):
		GameState.notify.emit("%s : c'est fermé. Horaires : %s." % [EMPLOYERS[id]["name"], hours_text(id)])
		return false
	return true


func _refresh_labels() -> void:
	for id in bosses:
		var e: Dictionary = EMPLOYERS[id]
		var st := state(id)
		var tag := "EMBAUCHÉ" if st["hired"] else ("RECRUTE" if missing(id) == "" else "RECRUTE (conditions)")
		if st["promoted"]:
			tag = "EMBAUCHÉ — CHEF"
		bosses[id]["label"].text = "%s — %s\n%s : %s" % [e["name"], e["role"], e["job"], tag]


# --- Fournisseur d'actions ----------------------------------------------------------

func _near_boss() -> String:
	var p = main.player
	if p.current_vehicle != null or p.riding != null:
		return ""
	for id in bosses:
		if bosses[id].get("remote", false):
			continue # patron dans son bureau (enterprises.gd)
		if p.global_position.distance_to(bosses[id]["pos"]) < TALK_RANGE:
			return id
	return ""


func get_hint() -> String:
	var p = main.player
	if shift == "taxi" and p.current_vehicle == null and _near_boss() == "taxi":
		return "Rendre le taxi et verser %s" % GameState.fcfa(VERSEMENT)
	var id := _near_boss()
	if id != "":
		return "Parler à %s (%s)" % [EMPLOYERS[id]["name"], EMPLOYERS[id]["role"].to_lower()]
	if _school_pos != Vector3.ZERO and p.current_vehicle == null and p.riding == null and p.global_position.distance_to(_school_pos) < TALK_RANGE:
		return "Auto-école Teranga : passer le permis"
	return ""


func try_interact() -> bool:
	var p = main.player
	var id := _near_boss()
	if id != "":
		_talk(id)
		return true
	if _school_pos != Vector3.ZERO and p.current_vehicle == null and p.riding == null and p.global_position.distance_to(_school_pos) < TALK_RANGE:
		_school()
		return true
	return false


# --- Dialogue avec le patron --------------------------------------------------------

func _talk(id: String) -> void:
	var e: Dictionary = EMPLOYERS[id]
	var st := state(id)
	var hud = main.hud
	var choices: Array = []
	var title := "%s — %s" % [e["name"], e["role"]]
	if not st["hired"]:
		var miss := missing(id)
		title += "\n« Asalaa maalekum ! Tu cherches du travail ? Je cherche un %s. »\nPaie : %s — Horaires : %s" % [e["job"].to_lower(), e["pay"], hours_text(id)]
		if miss == "":
			choices.append(["Oui, je veux travailler (entretien)", func(): _interview(id)])
		else:
			choices.append(["Conditions : " + miss, func(): GameState.notify.emit("%s : « %s. »" % [e["name"], miss])])
	else:
		title += "\nRéputation : %d — Services faits : %d%s" % [st["rep"], st["shifts"], " — Chef (+25 %)" if st["promoted"] else ""]
		if contract_text(id) != "":
			title += "\nContrat : " + contract_text(id)
		if bosses.has(id) and bosses[id].get("remote", false) and int(st["shifts"]) - int(st.get("nego_at", 0)) >= 5:
			choices.append(["Renégocier mon contrat", func(): _negotiate(id, true)])
		if shift == id:
			match id:
				"taxi":
					choices.append(["Rendre le taxi et verser %s" % GameState.fcfa(VERSEMENT), func(): _end_taxi()])
				"apprenti":
					choices.append(["Finir le service", func(): end_shift(id, false)])
				_:
					choices.append(["Finir le service", func(): end_shift(id, false)])
		elif shift == "":
			if id in ["taxi", "apprenti"]:
				choices.append(["Commencer le service", func(): _start_special(id)])
			else:
				choices.append(["Où est mon poste ?", func(): GameState.notify.emit("%s : « Ton poste est juste là. Mets-toi au travail pendant les heures d'ouverture (%s). »" % [e["name"], hours_text(id)])])
		choices.append(["Démissionner", func():
			st["hired"] = false
			if shift == id:
				end_shift(id, true)
			GameState.notify.emit("%s : « Bon... Bonne continuation, inch'Allah. »" % e["name"])
			_refresh_labels()])
	hud.show_choices(title, choices, func(): pass)


func _interview(id: String) -> void:
	var e: Dictionary = EMPLOYERS[id]
	var q: Array = e["q"]
	var answers: Array = q.slice(1)
	var good: String = q[1]
	answers.shuffle()
	var choices: Array = []
	for a in answers:
		var ans: String = a
		choices.append([ans, func():
			if ans == good and bosses.has(id) and bosses[id].get("remote", false):
				_negotiate(id)
				return
			if ans == good:
				state(id)["hired"] = true
				state(id)["rep"] = 1
				GameState.notify.emit("%s : « Dafa baax ! Tu es embauché comme %s. Horaires : %s. »" % [e["name"], e["job"].to_lower(), hours_text(id)])
				Audio.play_sfx("coin", -8.0)
			else:
				GameState.notify.emit("%s : « Hmm... ce n'est pas la bonne réponse. Reviens quand tu seras prêt. »" % e["name"])
			_refresh_labels()])
	main.hud.show_choices("Entretien avec %s\n« %s »" % [e["name"], q[0]], choices, func(): pass)


# --- Services : début, paie, fin --------------------------------------------------------

## Démarre un service (kiosque, caisse, stand...). Retourne false si impossible.
func begin(id: String) -> bool:
	if shift != "" and shift != id:
		GameState.notify.emit("Tu es déjà en service ailleurs.")
		return false
	if not can_work(id):
		return false
	shift = id
	_due = 0
	_shift_count = 0
	return true


## Une unité de travail faite (client servi, livraison, tasse...) : la paie s'accumule chez le patron.
func earn(id: String, amount: int, label: String, quiet := false) -> void:
	if shift != id:
		return
	var pay := int(round(amount * pay_mult(id) / 25.0)) * 25
	_due += pay
	_shift_count += 1
	if not quiet:
		GameState.notify.emit("%s (+%s à toucher en fin de service)" % [label, GameState.fcfa(pay)])


## Fin de service : le patron paie (moitié seulement si abandon de poste) et note le travail.
func end_shift(id: String, abandoned: bool) -> void:
	if shift != id:
		return
	shift = ""
	var e: Dictionary = EMPLOYERS[id]
	var st := state(id)
	var pay := _due if not abandoned else _due / 2
	if pay > 0:
		GameState.add_money(pay, "Paie de %s (%s)" % [e["name"], e["job"].to_lower()])
	if abandoned:
		_rep(id, -2, "%s : « Tu as abandonné ton poste ! Que ça ne se reproduise pas. »" % e["name"])
	elif _shift_count >= 3:
		st["shifts"] += 1
		GameState.employment["_experience"] = experience() + 1
		_rep(id, 1, "%s : « Jërëjëf, bon travail aujourd'hui ! » (%d services)" % [e["name"], st["shifts"]])
		if not st["promoted"] and st["shifts"] >= 5 and st["rep"] >= 5:
			st["promoted"] = true
			GameState.notify.emit("PROMOTION ! %s te nomme chef : +25 %% de paie." % e["name"])
	else:
		GameState.notify.emit("%s : « Service bien court aujourd'hui... »" % e["name"])
	_due = 0
	_shift_count = 0
	_refresh_labels()


func _rep(id: String, delta: int, text: String) -> void:
	var st := state(id)
	st["rep"] = int(st["rep"]) + delta
	GameState.notify.emit(text)
	if st["rep"] <= int(FIRE_AT.get(st.get("contract", "cdd"), -3)):
		st["hired"] = false
		st["rep"] = 0
		st["fired_at"] = experience()
		GameState.notify.emit("%s : « Tu es renvoyé ! » Tu as perdu ton travail." % EMPLOYERS[id]["name"])
	_refresh_labels()


# --- Taximan au versement ------------------------------------------------------------

func _start_special(id: String) -> void:
	if not can_work(id):
		return
	if id == "taxi":
		if GameState.money < VERSEMENT:
			GameState.notify.emit("Pape Diop : « Il faut pouvoir payer le versement de %s à la fin. »" % GameState.fcfa(VERSEMENT))
			return
		shift = "taxi"
		_due = 0
		_shift_count = 0
		_taxi = Vehicle.new()
		_taxi.vehicle_type = "taxi"
		main.add_child(_taxi)
		_taxi.respawn_in_traffic(main.city, main.player.global_position, 6.0, 30.0)
		_taxi.ai_enabled = false
		_taxi.route_active = false
		_taxi.set_meta("taxi_patron", true)
		_taxi.speed = 0.0
		_taxi.velocity = Vector3.ZERO
		GameState.waypoint = _taxi.global_position
		GameState.notify.emit("Pape Diop : « Voici les clés de mon taxi. Les courses sont pour toi, tu me verses %s ce soir. »" % GameState.fcfa(VERSEMENT))
	elif id == "apprenti":
		_start_apprenti()


## Le taxi du patron peut-il servir aux courses ? (job_manager)
func taxi_allowed(veh) -> bool:
	return shift == "taxi" and veh != null and veh.has_meta("taxi_patron")


func count_taxi_fare() -> void:
	if shift == "taxi":
		_shift_count += 1


func _end_taxi() -> void:
	var e: Dictionary = EMPLOYERS["taxi"]
	if GameState.spend(VERSEMENT):
		GameState.notify.emit("Tu verses %s à Pape Diop." % GameState.fcfa(VERSEMENT))
		end_shift("taxi", false)
	else:
		GameState.notify.emit("Tu n'as pas de quoi payer le versement...")
		end_shift("taxi", true)
		_rep("taxi", -1, "%s : « Et mon versement ?! »" % e["name"])
	if _taxi != null and is_instance_valid(_taxi) and main.player.current_vehicle != _taxi:
		_taxi.queue_free()
	_taxi = null


# --- Apprenti de car rapide --------------------------------------------------------

func _start_apprenti() -> void:
	var city = main.city
	var names: Array = []
	for n in CAR_RAPIDE_STOPS:
		if city.places.has(n):
			names.append(n)
	var pts := PackedVector3Array()
	var stop_idx := {}
	for k in names.size():
		var seg: PackedVector3Array = city.route(city.places[names[k]], city.places[names[(k + 1) % names.size()]], true)
		if seg.size() < 2:
			continue
		if pts.is_empty():
			pts.append_array(seg)
		else:
			pts.append_array(seg.slice(1))
		stop_idx[pts.size() - 1] = names[(k + 1) % names.size()]
	if pts.size() < 4:
		GameState.notify.emit("Le car rapide est en panne aujourd'hui.")
		return
	shift = "apprenti"
	_due = 0
	_shift_count = 0
	_car = Vehicle.new()
	_car.vehicle_type = "car_rapide"
	main.add_child(_car)
	_car.ai_city = city
	_car.line_name = "Car rapide de Modou"
	_car.global_position = pts[0] + Vector3(0, 0.3, 0)
	var dir := pts[1] - pts[0]
	_car.rotation.y = atan2(-dir.x, -dir.z)
	_car.follow_route(pts, true, stop_idx)
	_car.route_i = 1
	_car.reached_stop.connect(_on_car_stop)
	main.player.ride(_car)
	GameState.notify.emit("Modou : « Monte derrière ! À chaque arrêt, crie la destination pour attirer les clients ! »")


func apprenti_riding() -> bool:
	return shift == "apprenti" and _car != null and main.player.riding == _car


func _on_car_stop(stop_name: String) -> void:
	_stop_name = stop_name
	_stop_window = 5.0
	_cried = false
	GameState.notify.emit("Arrêt %s — appuie sur l'action pour crier la destination !" % stop_name)


## Action de l'apprenti (touche d'action pendant le trajet)
func apprenti_action() -> void:
	if _stop_window > 0.0 and not _cried:
		_cried = true
		var next: String = CAR_RAPIDE_STOPS[(CAR_RAPIDE_STOPS.find(_stop_name) + 1) % CAR_RAPIDE_STOPS.size()]
		var riders := randi_range(3, 8)
		var cash := riders * 150
		GameState.notify.emit("« %s ! %s ! Dem, dem ! » — %d passagers montent (%s encaissés)" % [next.to_upper(), next, riders, GameState.fcfa(cash)])
		earn("apprenti", int(cash * 0.3), "Ta part : 30 % de la recette")
		Audio.play_sfx("coin", -12.0)
		return
	# Hors arrêt : descendre et finir le service
	main.player.end_ride()
	end_shift("apprenti", _shift_count < 1)
	if _car != null and is_instance_valid(_car):
		_car.queue_free()
	_car = null


func _process(delta: float) -> void:
	if _stop_window > 0.0:
		_stop_window -= delta
		if _stop_window <= 0.0 and not _cried and shift == "apprenti":
			GameState.notify.emit("Tu n'as rien crié : le car repart presque vide...")
			earn("apprenti", 75, "Un seul passager")
	if shift != "":
		var e: Dictionary = EMPLOYERS[shift]
		# Arrestation ou police à tes trousses : le patron l'apprend
		if GameState.wanted >= 2:
			var id := shift
			end_shift(id, true)
			_rep(id, -1, "%s : « La police te cherche ? Pas dans mon entreprise ! »" % e["name"])
		elif not is_open(shift) and not shift in ["taxi", "apprenti"]:
			end_shift(shift, false)
			GameState.notify.emit("%s ferme. Fin du service." % e["name"])


func status() -> String:
	if shift == "":
		return ""
	var e: Dictionary = EMPLOYERS[shift]
	match shift:
		"apprenti":
			if _stop_window > 0.0 and not _cried:
				return "APPRENTI — Arrêt %s : crie la destination ! (%d s)" % [_stop_name, ceili(_stop_window)]
			return "APPRENTI — Car rapide de Modou — part : %s (action hors arrêt : descendre)" % GameState.fcfa(_due)
		"taxi":
			return ""
	return ""


# --- Auto-école -----------------------------------------------------------------

func _school() -> void:
	if has_permis():
		GameState.notify.emit("M. Sarr : « Tu as déjà ton permis. Roule prudemment ! »")
		return
	main.hud.show_choices("Auto-école Teranga — M. Sarr\n« L'examen du code coûte %s. Il faut 3 bonnes réponses sur 3. »" % GameState.fcfa(PERMIS_PRICE),
		[["Passer l'examen (%s)" % GameState.fcfa(PERMIS_PRICE), func():
			if not GameState.spend(PERMIS_PRICE):
				GameState.notify.emit("Il te faut %s pour l'examen." % GameState.fcfa(PERMIS_PRICE))
				return
			var qs: Array = CODE_QUESTIONS.duplicate()
			qs.shuffle()
			_exam(qs.slice(0, 3), 0)]], func(): pass)


func _exam(qs: Array, score: int) -> void:
	if qs.is_empty():
		if score >= 3:
			GameState.add_item(PERMIS_ITEM)
			GameState.notify.emit("Félicitations ! Tu as ton PERMIS DE CONDUIRE. Les patrons de taxi et de Jumbo peuvent t'embaucher.")
			Audio.play_sfx("coin", -6.0)
		else:
			GameState.notify.emit("Échec à l'examen (%d/3). Révise ton code et reviens !" % score)
		_refresh_labels()
		return
	var q: Array = qs[0]
	var answers: Array = q.slice(1)
	answers.shuffle()
	var choices: Array = []
	for a in answers:
		var ans: String = a
		choices.append([ans, func(): _exam(qs.slice(1), score + (1 if ans == q[1] else 0))])
	main.hud.show_choices("Code de la route — question %d/3\n%s" % [4 - qs.size(), q[0]], choices, func(): pass)


# --- Négociation du contrat (au bureau du patron, assis face à lui) --------------------

## Étape 1 : le type de contrat. Étape 2 : le salaire. Le patron accepte, fait une contre-offre ou refuse.
func _negotiate(id: String, renew := false) -> void:
	var e: Dictionary = EMPLOYERS[id]
	var choices: Array = []
	var cdi_ok := experience() >= 5 or int(state(id)["shifts"]) >= 5
	choices.append(["Journalier : libre, paie de base, peu protégé", func(): _nego_salary(id, "journalier", 0.0, renew)])
	choices.append(["CDD de 3 mois : +5 % de paie", func(): _nego_salary(id, "cdd", 0.05, renew)])
	choices.append(["CDI : +10 % de paie, bien protégé" + ("" if cdi_ok else " (il faut 5 services d'expérience)"), func():
		if cdi_ok:
			_nego_salary(id, "cdi", 0.10, renew)
		else:
			GameState.notify.emit("%s : « Un CDI ? Montre-moi d'abord ce que tu sais faire. Je te propose un CDD. »" % e["name"])
			_nego_salary(id, "cdd", 0.05, renew)])
	var intro := "« Bon, parlons de ton contrat. »" if renew else "« Dafa baax, tu as bien répondu ! Parlons de ton contrat. »"
	main.hud.show_choices("%s — %s\n%s\nPoste : %s — Paie de base : %s" % [e["name"], e["role"], intro, e["job"], e["pay"]], choices, func():
		GameState.notify.emit("%s : « Réfléchis et reviens me voir. »" % e["name"]))


func _nego_salary(id: String, contract: String, bonus: float, renew: bool) -> void:
	var e: Dictionary = EMPLOYERS[id]
	var choices: Array = []
	for ask in [0.0, 0.10, 0.25]:
		var a: float = ask
		var txt := "J'accepte votre offre" if a == 0.0 else "Je demande %d %% de plus" % int(a * 100.0)
		choices.append([txt, func(): _nego_answer(id, contract, bonus, a, renew)])
	main.hud.show_choices("%s : « %s. Et pour le salaire ? »" % [e["name"], CONTRACTS[contract]], choices, func():
		GameState.notify.emit("%s : « Comme tu veux. La porte reste ouverte. »" % e["name"]))


func _nego_answer(id: String, contract: String, bonus: float, ask: float, renew: bool) -> void:
	var e: Dictionary = EMPLOYERS[id]
	var lev := _leverage(id)
	var got := 0.0
	var line := ""
	if ask == 0.0:
		line = "« Marché conclu ! »"
	elif ask <= 0.10:
		if lev >= 25:
			got = ask
			line = "« D'accord, tu le mérites. »"
		else:
			got = 0.05
			line = "« 10 %, c'est trop. Je te donne 5 %, c'est mon dernier mot. »"
	else:
		if lev >= 45:
			got = ask
			line = "« Tu sais négocier, toi ! Va pour 25 %. »"
		elif lev >= 25:
			got = 0.10
			line = "« 25 % ?! Non. Je peux aller jusqu'à 10 %. »"
		else:
			# Refus : on peut accepter la paie de base ou partir
			main.hud.show_choices("%s : « Tu demandes beaucoup pour un débutant. C'est la paie de base, à prendre ou à laisser. »" % e["name"], [
				["J'accepte la paie de base", func(): _sign(id, contract, bonus, renew, "« Bienvenue dans l'équipe. »")],
				["Je refuse et je pars", func(): GameState.notify.emit("%s : « Dommage. Bonne continuation. »" % e["name"])],
			], func(): pass)
			return
	_sign(id, contract, bonus + got, renew, line)


func _sign(id: String, contract: String, raise: float, renew: bool, line: String) -> void:
	var e: Dictionary = EMPLOYERS[id]
	var st := state(id)
	st["hired"] = true
	if not renew:
		st["rep"] = 1
	st["contract"] = contract
	st["rate"] = snappedf(1.0 + raise, 0.01)
	st["nego_at"] = int(st["shifts"])
	Audio.play_sfx("coin", -8.0)
	GameState.notify.emit("%s : %s Contrat signé : %s. Horaires : %s." % [e["name"], line, contract_text(id), hours_text(id)])
	_refresh_labels()
