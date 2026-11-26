extends Node
## Gestionnaire des Missions et Quêtes urbaines de Dakar.
## Propose des missions scénarisées immersives (JOJ 2026, Lamb, Maïga, Jumbo, Urgence hôpital, Wave/OM...)
## avec suivi GPS, balises lumineuses, chronomètres, étapes narratives et récompenses généreuses.

const Mk = preload("res://scripts/util/mk.gd")

const MISSIONS := {
	"joj_convoy": {
		"id": "joj_convoy",
		"title": "Convoi Officiel JOJ Dakar 2026",
		"icon": "🏅",
		"giver": "Mamy Mbaye & Le Comité JOJ",
		"desc": "Dakar prépare les Jeux Olympiques de la Jeunesse 2026 ! Achemine le matériel sportif et déploie les drapeaux officiels aux points névralgiques de la capitale.",
		"reward": 20000,
		"steps": [
			{
				"text": "Rejoins la Gare de Dakar pour réceptionner le chargement officiel",
				"place": "Gare de Dakar",
				"radius": 12.0,
				"action_hint": "Prendre en charge le matériel JOJ"
			},
			{
				"text": "Achemine le matériel sportif au Stade Iba Mar Diop",
				"place": "Stade Iba Mar Diop",
				"radius": 15.0,
				"action_hint": "Décharger les équipements d'athlétisme"
			},
			{
				"text": "Hisse les bannières JOJ 2026 sur la Place de l'Indépendance",
				"place": "Place de l'Indépendance",
				"radius": 14.0,
				"action_hint": "Déployer les bannières officielles"
			},
			{
				"text": "Rejoins la Porte du Millénaire pour valider la tournée olympique",
				"place": "Porte du Millénaire",
				"radius": 14.0,
				"action_hint": "Valider le convoi auprès du commissaire JOJ"
			}
		]
	},
	"maiga_rush": {
		"id": "maiga_rush",
		"title": "Tournée Express Fast-Food Maïga",
		"icon": "🥪",
		"giver": "Amadou Maïga (Gérant Fast-Food)",
		"desc": "C'est l'heure de pointe du soir ! Les commandes de sandwichs brochettes, dibi et frites chaudes affluent. Livre les clients avant que ça ne refroidisse !",
		"reward": 12500,
		"steps": [
			{
				"text": "Passe au Restaurant Maïga récupérer les commandes chaudes",
				"place": "Restaurant Maïga",
				"radius": 10.0,
				"action_hint": "Récupérer les sacs de sandwichs"
			},
			{
				"text": "Livre la 1ère commande au Marché Sandaga (chrono express)",
				"place": "Marché Sandaga",
				"radius": 12.0,
				"time_limit": 110.0,
				"action_hint": "Donner le sandwich au commerçant"
			},
			{
				"text": "Livre la 2ème commande aux chauffeurs de la Gare routière Petersen",
				"place": "Gare routière Petersen",
				"radius": 14.0,
				"time_limit": 100.0,
				"action_hint": "Donner les sandwichs aux chauffeurs"
			},
			{
				"text": "Dernière livraison aux supporters du Stade Iba Mar Diop",
				"place": "Stade Iba Mar Diop",
				"radius": 14.0,
				"time_limit": 110.0,
				"action_hint": "Livrer le méga-pack Maïga"
			}
		]
	},
	"lamb_champion": {
		"id": "lamb_champion",
		"title": "Le Sacre du Champion de Lamb",
		"icon": "🤼",
		"giver": "Mbaye Guèye (Ancien Champion de Lutte)",
		"desc": "Un combat décisif se prépare dans l'arène. Remplis les rituels traditionnels de préparation physique et mystique pour triompher dans l'arène de lutte !",
		"reward": 25000,
		"steps": [
			{
				"text": "Cours jusqu'à la Plage de l'Anse Bernard pour l'échauffement cardio",
				"place": "Plage de l'Anse Bernard",
				"radius": 14.0,
				"action_hint": "Faire les séries de pompes sur le sable"
			},
			{
				"text": "Achète ton Nguimb béni et tes gris-gris au Marché Tilène",
				"place": "Marché Tilène",
				"radius": 14.0,
				"action_hint": "Récupérer le Nguimb traditionnel"
			},
			{
				"text": "Reçois les prières des anciens près de la Grande Mosquée",
				"place": "Grande Mosquée",
				"radius": 15.0,
				"action_hint": "Recevoir les bénédictions"
			},
			{
				"text": "Pénètre dans l'Arène de lutte de Fass et triomphe du rival",
				"place": "Caserne",
				"radius": 16.0,
				"action_hint": "Entrer dans l'arène sous le Sabar"
			}
		]
	},
	"hopital_urgence": {
		"id": "hopital_urgence",
		"title": "Urgence Médicale Dakar-Secours",
		"icon": "🚑",
		"giver": "Dr Awa Fall (Médecin urgentiste)",
		"desc": "Une urgence absolue s'est déclarée à la Médina. Achemine les poches de sang et le matériel de réanimation sans encombre jusqu'à l'Hôpital Principal !",
		"reward": 15000,
		"steps": [
			{
				"text": "Récupère la mallette médicale à la Polyclinique de la Médina",
				"place": "Polyclinique de la Médina",
				"radius": 10.0,
				"action_hint": "Charger la glacière médicale"
			},
			{
				"text": "Fends la circulation jusqu'à l'Hôpital Aristide Le Dantec",
				"place": "Hôpital Aristide Le Dantec",
				"radius": 12.0,
				"time_limit": 120.0,
				"action_hint": "Déposer les premiers soins"
			},
			{
				"text": "Livre le matériel critique d'urgence à l'Hôpital Principal",
				"place": "Hôpital Principal",
				"radius": 14.0,
				"time_limit": 110.0,
				"action_hint": "Transmettre l'équipement au chirurgien"
			}
		]
	},
	"jumbo_supply": {
		"id": "jumbo_supply",
		"title": "Grand Ravitaillement Boutiques Jumbo",
		"icon": "📦",
		"giver": "Moussa Fall (Chef du Dépôt Jumbo)",
		"desc": "Les dépôts Jumbo doivent réapprovisionner les épiceries de quartier avant le week-end. Prends le volant et assure la livraison des cartons !",
		"reward": 16000,
		"steps": [
			{
				"text": "Passe au Dépôt Jumbo charger la camionnette de livraison",
				"place": "Jumbo",
				"radius": 12.0,
				"action_hint": "Charger les cartons de bouillon Jumbo"
			},
			{
				"text": "Ravitailler le grossiste du Marché Kermel",
				"place": "Marché Kermel",
				"radius": 12.0,
				"action_hint": "Déposer 10 cartons à Kermel"
			},
			{
				"text": "Livrer le supermarché Jadida",
				"place": "Jadida",
				"radius": 12.0,
				"action_hint": "Déposer 15 cartons chez Jadida"
			},
			{
				"text": "Approvisionner l'épicerie du Marché Sandaga",
				"place": "Marché Sandaga",
				"radius": 14.0,
				"action_hint": "Déposer les cartons à Sandaga"
			},
			{
				"text": "Retourne signer la feuille de tournée au Dépôt Jumbo",
				"place": "Jumbo",
				"radius": 12.0,
				"action_hint": "Valider la feuille de tournée"
			}
		]
	},
	"wave_cash": {
		"id": "wave_cash",
		"title": "Transfert de Fonds Wave & Orange Money",
		"icon": "📲",
		"giver": "Fatou Sow (Superviseuse Mobile Money)",
		"desc": "Les retraits d'argent explosent à Dakar ! Les kiosques centraux sont à court de liquidités. Transporte les fonds bancaires sous haute sécurité.",
		"reward": 14000,
		"steps": [
			{
				"text": "Retire la mallette de billets sécurisée à la Banque SGBS",
				"place": "Banque SGBS",
				"radius": 12.0,
				"action_hint": "Récupérer la valise de fonds sécurisée"
			},
			{
				"text": "Ravitailler le Kiosque Wave de la Place de l'Indépendance",
				"place": "Wave",
				"radius": 12.0,
				"action_hint": "Recharger le coffre du kiosque Wave"
			},
			{
				"text": "Approvisionner le Kiosque Orange Money de Petersen",
				"place": "Orange Money (Petersen)",
				"radius": 14.0,
				"action_hint": "Remettre le cash au gérant Orange Money"
			}
		]
	},
	"port_rescue": {
		"id": "port_rescue",
		"title": "Le Colis Égaré du Port de Dakar",
		"icon": "🕵️",
		"giver": "Modou Kane (Transitaire du Port)",
		"desc": "Un colis confidentiel de haute valeur est tombé d'un conteneur entre le Port et la Gare. Retrouve-le et sécurise-le au poste de police !",
		"reward": 13000,
		"steps": [
			{
				"text": "Inspecte les voies ferroviaires près de la Gare de Dakar",
				"place": "Gare de Dakar",
				"radius": 14.0,
				"action_hint": "Chercher la caisse scellée"
			},
			{
				"text": "Récupère le colis sécurisé près des entrepôts du port",
				"place": "Restaurant Cercle de la Rade",
				"radius": 14.0,
				"action_hint": "Récupérer la marchandise perdue"
			},
			{
				"text": "Dépose le colis sous scellé au Commissariat (Dakar-Plateau)",
				"place": "Commissariat (Dakar-Plateau)",
				"radius": 14.0,
				"action_hint": "Consigner le colis à la police"
			}
		]
	},
	"taxi_rally": {
		"id": "taxi_rally",
		"title": "La Traversée Nocturne des Taxis",
		"icon": "🚕",
		"giver": "Pape Diop (Doyen des Taximen)",
		"desc": "Le grand rallye citadin des taximen dakarois est lancé ! Traverse la ville à travers les points emblématiques sans accident.",
		"reward": 18000,
		"steps": [
			{
				"text": "Rejoins le point de départ au Garage Taxi",
				"place": "Garage Taxi",
				"radius": 12.0,
				"action_hint": "Pointer au départ du rallye"
			},
			{
				"text": "Franchis le point de passage de la Cathédrale de Dakar",
				"place": "Cathédrale",
				"radius": 15.0,
				"action_hint": "Pointer à la Cathédrale"
			},
			{
				"text": "Passe le contrôle devant l'Assemblée nationale",
				"place": "Assemblée nationale",
				"radius": 15.0,
				"action_hint": "Valider le passage à l'Assemblée"
			},
			{
				"text": "Ligne d'arrivée victorieuse sur la Place de l'Indépendance !",
				"place": "Place de l'Indépendance",
				"radius": 16.0,
				"action_hint": "Franchir la ligne d'arrivée"
			}
		]
	}
}

var main
var city
var player

var active_id := ""
var step_idx := 0
var time_left := 0.0
var objective := ""
var target_pos := Vector3.ZERO
var target_name := ""

var _beam: Node3D
var _beam_mesh: MeshInstance3D
var _arrow: Node3D


func _ready() -> void:
	_beam = Node3D.new()
	add_child(_beam)
	_beam_mesh = Mk.cyl(_beam, 2.2, 2.2, 65.0, Vector3(0, 32.5, 0), Color(0.96, 0.65, 0.1, 0.45), false, 16)
	Mk.cyl(_beam, 2.8, 2.8, 0.15, Vector3(0, 0.25, 0), Color(1, 1, 1, 0.7), false, 24)
	_beam.visible = false

	_arrow = Node3D.new()
	add_child(_arrow)
	var cone := Mk.cyl(_arrow, 0.0, 0.35, 1.0, Vector3.ZERO, Color("f59e0b"), false, 8)
	cone.material_override = Mk.mat(Color("f59e0b"), 1.8)
	cone.rotation.x = -PI / 2.0
	_arrow.visible = false


func has_active_mission() -> bool:
	return active_id != "" and MISSIONS.has(active_id)


func get_active_mission() -> Dictionary:
	if has_active_mission():
		return MISSIONS[active_id]
	return {}


func start_mission(id: String) -> bool:
	if not MISSIONS.has(id):
		return false
	var m: Dictionary = MISSIONS[id]
	active_id = id
	step_idx = 0
	_setup_step()
	GameState.notify.emit("🎯 MISSION ACCEPTÉE : %s !\n%s" % [m["title"], m["desc"]])
	Audio.play_sfx("coin", -6.0)
	return true


func cancel_mission() -> void:
	if not has_active_mission():
		return
	var m: Dictionary = MISSIONS[active_id]
	GameState.notify.emit("Mission abandonnée : %s." % m["title"])
	active_id = ""
	step_idx = 0
	objective = ""
	target_pos = Vector3.ZERO
	_beam.visible = false
	_arrow.visible = false
	if GameState.waypoint != null:
		GameState.waypoint = null


func _setup_step() -> void:
	if not has_active_mission():
		return
	var m: Dictionary = MISSIONS[active_id]
	var steps: Array = m["steps"]
	if step_idx >= steps.size():
		_complete_mission()
		return
	var st: Dictionary = steps[step_idx]
	target_name = st["place"]
	time_left = float(st.get("time_limit", 0.0))

	# Résolution de la position cible
	if city and city.places.has(target_name):
		target_pos = city.places[target_name]
	elif city and city.places.has("Place de l'Indépendance"):
		target_pos = city.places["Place de l'Indépendance"]
	else:
		target_pos = Vector3.ZERO

	GameState.waypoint = target_pos
	_beam.visible = true
	_beam.global_position = target_pos
	_arrow.visible = true


func _complete_mission() -> void:
	var m: Dictionary = MISSIONS[active_id]
	var reward: int = int(m["reward"])
	GameState.add_money(reward, "Mission accomplie : " + m["title"])
	GameState.stats["missions_done"] = GameState.stats.get("missions_done", 0) + 1
	var completed: Array = GameState.missions.get("completed", [])
	if not active_id in completed:
		completed.append(active_id)
	GameState.missions["completed"] = completed

	GameState.notify.emit("🏆 MISSION ACCOMPLIE : %s !\nTu reçois %s ! Félicitations !" % [m["title"], GameState.fcfa(reward)])
	Audio.play_sfx("coin", 0.0)

	active_id = ""
	step_idx = 0
	objective = ""
	target_pos = Vector3.ZERO
	_beam.visible = false
	_arrow.visible = false
	GameState.waypoint = null


func _fail_mission(reason: String) -> void:
	GameState.notify.emit("❌ MISSION ÉCHOUÉE : %s" % reason)
	cancel_mission()


func advance_step() -> void:
	if not has_active_mission():
		return
	var m: Dictionary = MISSIONS[active_id]
	var steps: Array = m["steps"]
	step_idx += 1
	if step_idx < steps.size():
		GameState.notify.emit("✔ Étape validée (%d/%d) ! Prochaine destination : %s." % [step_idx, steps.size(), steps[step_idx]["place"]])
		Audio.play_sfx("coin", -8.0)
		_setup_step()
	else:
		_complete_mission()


func _process(delta: float) -> void:
	if not has_active_mission():
		_beam.visible = false
		_arrow.visible = false
		return

	var m: Dictionary = MISSIONS[active_id]
	var steps: Array = m["steps"]
	if step_idx >= steps.size():
		return

	var st: Dictionary = steps[step_idx]
	var p_pos: Vector3 = player.get_world_position() if player else Vector3.ZERO
	var d := Vector2(p_pos.x - target_pos.x, p_pos.z - target_pos.z).length()

	# Gestion du chronomètre si l'étape en comporte un
	if time_left > 0.0:
		time_left -= delta
		if time_left <= 0.0:
			_fail_mission("Le temps limite est écoulé !")
			return
		objective = "🎯 %s (%d/%d) — %s (%d m) — ⏱ %d s" % [
			m["title"],
			step_idx + 1,
			steps.size(),
			st["text"],
			int(d),
			maxi(0, int(time_left))
		]
	else:
		objective = "🎯 %s (%d/%d) — %s (%d m)" % [
			m["title"],
			step_idx + 1,
			steps.size(),
			st["text"],
			int(d)
		]

	# Balise et flèche de guidage
	_beam.global_position = target_pos
	var h := 3.0
	if player and player.current_vehicle:
		h = player.current_vehicle.size.y + 1.8
	_arrow.global_position = p_pos + Vector3(0, h, 0)
	var look := Vector3(target_pos.x, _arrow.global_position.y, target_pos.z)
	if _arrow.global_position.distance_to(look) > 0.5:
		_arrow.look_at(look, Vector3.UP)

	# Validation automatique si aucun bouton d'action n'est requis
	var rad: float = float(st.get("radius", 12.0))
	if d <= rad and st.get("action_hint", "") == "":
		advance_step()


## Fournisseur d'interactions pour player.providers
func get_hint() -> String:
	if not has_active_mission():
		return ""
	var m: Dictionary = MISSIONS[active_id]
	var steps: Array = m["steps"]
	if step_idx >= steps.size():
		return ""
	var st: Dictionary = steps[step_idx]
	var action_hint: String = st.get("action_hint", "")
	if action_hint == "":
		return ""
	var p_pos: Vector3 = player.get_world_position() if player else Vector3.ZERO
	var d := Vector2(p_pos.x - target_pos.x, p_pos.z - target_pos.z).length()
	var rad: float = float(st.get("radius", 12.0))
	if d <= rad:
		return "Action : %s" % action_hint
	return ""


func try_interact() -> bool:
	if not has_active_mission():
		return false
	var m: Dictionary = MISSIONS[active_id]
	var steps: Array = m["steps"]
	if step_idx >= steps.size():
		return false
	var st: Dictionary = steps[step_idx]
	var action_hint: String = st.get("action_hint", "")
	if action_hint == "":
		return false
	var p_pos: Vector3 = player.get_world_position() if player else Vector3.ZERO
	var d := Vector2(p_pos.x - target_pos.x, p_pos.z - target_pos.z).length()
	var rad: float = float(st.get("radius", 12.0))
	if d <= rad:
		advance_step()
		return true
	return false
