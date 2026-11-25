extends Node
## Métiers RP du mode en ligne, joués par les joueurs eux-mêmes :
## - Taximan : conduire un taxi. Les autres joueurs l'appellent, montent, choisissent la destination
##   et paient la course à l'arrivée.
## - Vendeur : tenir un étal au marché. Les passants achètent, les autres joueurs aussi.
## - Factions (factions.gd) : on rejoint au QG, on y prend son service en tenue, avec un véhicule de service.
##   · Police nationale : les joueurs recherchés apparaissent sur le GPS ; on les arrête à pied (prime).
##   · SAMU : les joueurs tombés à terre apparaissent sur le GPS ; on les relève sur place.
##   · Gang de la Médina : livrer des colis louches à travers la ville, recherché par la police en route.
##   Chaque réussite donne de l'expérience : promotion au grade suivant, salaire plus élevé.
## - Mécanicien : en service avec sa camionnette, il répare et fait le plein du véhicule des autres joueurs
##   (action près d'eux) ; le client paie la réparation.
## - Joueur à terre (faim, bagarre) : s'il y a des secouristes en service, il attend le SAMU un moment
##   au lieu de partir tout de suite à l'hôpital.
## Le serveur verse un salaire aux joueurs en service toutes les Net.PAY_EVERY secondes.

const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const Factions = preload("res://scripts/net/factions.gd")
const Outfits = preload("res://scripts/util/outfits.gd")
const Employment = preload("res://scripts/jobs/employment.gd")

const MARKET := "Grand marché de Sandaga" ## (scripts/world/market.gd : site des étals)
const DUTY_RANGE := 14.0
const STALL_RANGE := 30.0
const STALL_LEAVE := 45.0
const ARRIVAL := 45.0
const DOWN_TIME := 75.0 ## secondes à attendre le SAMU avant de partir à l'hôpital
const PARCEL_MIN := 350.0 ## distance des livraisons du gang
const PARCEL_MAX := 1400.0
const PARCEL_ARRIVAL := 22.0
## Ce que vend un joueur vendeur : [nom, prix, satiété (0 = objet gardé dans le sac)]
const SELL_ITEMS := [
	["Mangue", 200, 12], ["Pain tapalapa", 150, 15], ["Fataya", 100, 10], ["Jus de bissap", 200, 6],
	["Café Touba", 150, 4], ["Foulard", 1500, 0], ["Tissu wax (6 yards)", 6000, 0],
]
const REPAIR_PRICE := 2000 ## dépannage par un joueur mécanicien
const NPC_BUYERS := ["Une maman", "Un étudiant", "Un vieux", "Une cliente", "Un touriste", "Un mécanicien"]

var main
var status := ""
var fare := {} ## passager d'un taxi joueur : {driver, pseudo, dest, pos, price}
var patients := {} ## (SAMU en service) id → {who, pos}
var _car = null ## véhicule de service (voiture de police, ambulance)
var _market := ""
var _sales := 0
var _scan_t := 0.0
var _sale_t := 30.0
var _suspect := -1
var _patient := -1
var _down_t := -1.0 ## à terre : secondes restantes avant l'hôpital (-1 = debout)
var _parcel := {} ## (gang) colis en cours : {dest, pos, pay}


func _ready() -> void:
	Net.job_target.connect(_on_job_target)
	Net.arrested.connect(_on_arrested)
	Net.factions.patient.connect(_on_patient)
	Net.factions.healed.connect(_on_healed)
	Net.factions.reward_received.connect(_on_reward)
	Net.city.serviced.connect(_on_serviced)
	Net.city.ticketed.connect(_on_ticketed)


func _on_job_target(text: String, pos: Vector3) -> void:
	GameState.waypoint = pos
	GameState.notify.emit(text + " Sa position est sur ton GPS.")
	Audio.play_sfx("coin", -14.0)


func _on_arrested(cop: String) -> void:
	fare = {}
	if _down_t >= 0.0:
		_end_down()
		GameState.revive()
	if not _parcel.is_empty():
		GameState.notify.emit("La police saisit ton colis...")
		_parcel = {}
	if GameState.rp_job != "":
		_stop(false)
	main.police.arrested_by(cop)


# --- Factions : rejoindre, grade, tenue ----------------------------------------------------

func my_faction() -> String:
	return str(GameState.faction.get("id", ""))


func _xp() -> int:
	return int(GameState.faction.get("xp", 0))


## Nom de la faction et grade du joueur (« Police nationale — Brigadier »)
func faction_title() -> String:
	var f := my_faction()
	if not Factions.FACTIONS.has(f):
		return ""
	return "%s — %s" % [Factions.FACTIONS[f]["name"], Factions.rank_name(f, _xp())]


## QG de faction tout proche (id de la faction, "" sinon)
func _hq_here(pos: Vector3) -> String:
	for f in Factions.FACTIONS:
		var hq: String = Factions.FACTIONS[f]["hq"]
		if main.city.places.has(hq) and pos.distance_to(main.city.places[hq]) < DUTY_RANGE:
			return f
	return ""


func _join_menu(f: String) -> void:
	var info: Dictionary = Factions.FACTIONS[f]
	main.hud.show_choices("%s — %s" % [info["name"], info["desc"]], [
		["Rejoindre (grade de départ : %s)" % info["ranks"][0], func(): _join(f)],
		["Pas maintenant", func(): pass]], func(): pass)


func _join(f: String) -> void:
	if my_faction() != "":
		GameState.notify.emit("Tu fais déjà partie de : %s. Quitte-la d'abord (menu MÉTIERS)." % Factions.FACTIONS[my_faction()]["name"])
		return
	if f == "police":
		if GameState.inventory.get(Employment.PERMIS_ITEM, 0) <= 0:
			GameState.notify.emit("« Il faut le permis de conduire pour entrer dans la police. » Passe-le à l'auto-école.")
			return
		if GameState.wanted > 0:
			GameState.notify.emit("« Tu es recherché ! » La police ne recrute pas les suspects.")
			return
	GameState.faction = {"id": f, "xp": 0}
	GameState.save_game()
	GameState.notify.emit("Bienvenue : %s ! Tu es %s." % [Factions.FACTIONS[f]["name"], Factions.FACTIONS[f]["ranks"][0]])
	_start_duty(f)


func _leave_faction() -> void:
	var f := my_faction()
	if f == "":
		return
	if GameState.rp_job == f:
		_stop(false)
	GameState.faction = {}
	GameState.save_game()
	GameState.notify.emit("Tu as quitté : %s. Ton grade est perdu." % Factions.FACTIONS[f]["name"])


func _gain_xp(xp: int) -> void:
	var f := my_faction()
	if f == "" or xp <= 0:
		return
	var before := Factions.rank_of(_xp())
	GameState.faction["xp"] = _xp() + xp
	var after := Factions.rank_of(_xp())
	if after > before:
		GameState.notify.emit("PROMOTION ! Tu es maintenant %s (%s). Ton salaire augmente." % [Factions.FACTIONS[f]["ranks"][after], Factions.FACTIONS[f]["name"]])
		Audio.play_sfx("coin", -6.0)
	GameState.save_game()


func _on_reward(xp: int, amount: int, reason: String) -> void:
	if amount > 0:
		GameState.add_money(amount, reason)
	_gain_xp(xp)


## Tenue de service : haut, bas et chapeau de la faction (la coiffure est gardée)
func _wear_uniform(f: String) -> void:
	if not GameState.faction.has("civil"):
		GameState.faction["civil"] = GameState.tenue
	var p := Outfits.parse(GameState.tenue)
	var u: Array = Factions.FACTIONS[f]["uniform"]
	for i in 3:
		p[i] = u[i]
	_set_tenue(Outfits.make(p))


func _take_off_uniform() -> void:
	if GameState.faction.has("civil"):
		var civil := str(GameState.faction["civil"])
		GameState.faction.erase("civil")
		_set_tenue(civil)


func _set_tenue(code: String) -> void:
	GameState.tenue = code
	if main.player.model:
		main.player.model.set_outfit(code)
	GameState.save_game()


# --- Prise et fin de service -------------------------------------------------------------

func _nearest_market(_pos: Vector3) -> String:
	return MARKET if _market_pos() != Vector3.ZERO else ""


func _market_pos() -> Vector3:
	if main.market != null and main.market.site != Vector3.ZERO:
		return main.market.site
	return main.city.places.get("Marché Sandaga", Vector3.ZERO)


func get_hint() -> String:
	var p = main.player
	if p.current_vehicle != null or p.riding != null or _down_t >= 0.0:
		return ""
	var f := _hq_here(p.global_position)
	if f == "":
		return ""
	var name: String = Factions.FACTIONS[f]["name"]
	if GameState.rp_job == f:
		return "%s : colis, fin de service" % name if f == "gang" else "Quitter le service (%s)" % name
	if GameState.rp_job != "":
		return ""
	if my_faction() == f:
		return "Prendre le service (%s)" % name
	return "Rejoindre : %s" % name if my_faction() == "" else ""


func try_interact() -> bool:
	if get_hint() == "":
		return false
	var f := _hq_here(main.player.global_position)
	if GameState.rp_job == f:
		if f == "gang":
			_gang_menu()
		else:
			_stop(true)
	elif my_faction() == f:
		_start_duty(f)
	else:
		_join_menu(f)
	return true


func _start_duty(f: String) -> void:
	if f == "police" and GameState.wanted > 0:
		GameState.notify.emit("« Tu es recherché ! » On ne te confie pas d'uniforme.")
		return
	GameState.rp_job = f
	_suspect = -1
	_patient = -1
	_scan_t = 0.0
	_wear_uniform(f)
	var vtype: String = Factions.FACTIONS[f]["vehicle"]
	if vtype != "" and (_car == null or not is_instance_valid(_car)):
		_car = Vehicle.new()
		_car.vehicle_type = vtype
		main.add_child(_car)
		_car.respawn_in_traffic(main.city, main.player.global_position, 6.0, 40.0)
		_car.ai_enabled = false
		_car.route_active = false
		_car.fuel = 100.0
	var pay := GameState.fcfa(Factions.salary(f, _xp()))
	var every := int(Net.PAY_EVERY / 60.0)
	var rank := Factions.rank_name(f, _xp())
	match f:
		"police":
			GameState.notify.emit("%s en service. Ta voiture de patrouille t'attend devant. Salaire : %s toutes les %d minutes, prime pour chaque arrestation." % [rank, pay, every])
		"samu":
			GameState.notify.emit("%s du SAMU en service. Ton ambulance t'attend devant : les joueurs à terre apparaîtront sur ton GPS. Salaire : %s toutes les %d minutes." % [rank, pay, every])
		"gang":
			GameState.notify.emit("%s du gang. Prends un colis ici (action) et livre-le sans te faire arrêter." % rank)


func _start_mechanic() -> void:
	GameState.rp_job = "mecanicien"
	if _car == null or not is_instance_valid(_car):
		_car = Vehicle.new()
		_car.vehicle_type = "van"
		main.add_child(_car)
		_car.respawn_in_traffic(main.city, main.player.global_position, 6.0, 40.0)
		_car.ai_enabled = false
		_car.route_active = false
		_car.fuel = 100.0
	GameState.notify.emit("Mécanicien en service. Ta camionnette t'attend : les joueurs t'appellent depuis Services, tu répares leur véhicule (action près d'eux, %s payés par le client). Salaire : %s toutes les %d minutes." % [
		GameState.fcfa(REPAIR_PRICE), GameState.fcfa(Net.SALARY["mecanicien"]), int(Net.PAY_EVERY / 60.0)])


## PV reçu d'un policier joueur : l'amende est prise sur l'argent liquide, le reste sur le compte
func _on_ticketed(cop: String, reason: String, amount: int) -> void:
	var cash := mini(amount, GameState.money)
	GameState.money -= cash
	var rest := mini(amount - cash, GameState.bank)
	if rest > 0:
		GameState.bank -= rest
		GameState.bank_note("-%s : PV (%s)" % [GameState.fcfa(rest), reason.to_lower()])
	GameState.notify.emit("PV de l'agent %s : %s. Amende de %s payée." % [cop, reason.to_lower(), GameState.fcfa(cash + rest)])
	Audio.play_sfx("alert")
	GameState.save_game()


## Client : un mécanicien a réparé et fait le plein de mon véhicule
func _on_serviced(mechanic: String, mechanic_id: int) -> void:
	var v = main.player.current_vehicle
	if v == null and main.dealership and main.dealership.out != null and is_instance_valid(main.dealership.out) \
			and main.dealership.out.global_position.distance_to(main.player.global_position) < 15.0:
		v = main.dealership.out
	if v == null:
		GameState.notify.emit("%s voulait réparer ton véhicule, mais tu n'en as pas à côté." % mechanic)
		return
	v.condition = 100.0
	if v.fuel >= 0.0:
		v.fuel = minf(100.0, v.fuel + 40.0)
	if Net.give_money(mechanic_id, REPAIR_PRICE, "Réparation"):
		GameState.notify.emit("%s a réparé ton véhicule et fait le plein (+40 %%). Tu lui paies %s." % [mechanic, GameState.fcfa(REPAIR_PRICE)])
		if main.dealership and main.dealership.out_insured(v):
			GameState.add_money(REPAIR_PRICE, "Ton assurance te rembourse la réparation")
	else:
		GameState.notify.emit("%s a réparé ton véhicule... mais tu n'as pas de quoi le payer !" % mechanic)


func _start_vendor(market: String) -> void:
	GameState.rp_job = "vendeur"
	_market = market
	_sales = 0
	_sale_t = randf_range(15.0, 25.0)
	GameState.notify.emit("Tu tiens un étal au %s. Les passants et les autres joueurs peuvent t'acheter. Salaire : %s toutes les %d minutes." % [market, GameState.fcfa(Net.SALARY["vendeur"]), int(Net.PAY_EVERY / 60.0)])


func _stop(tell: bool) -> void:
	var job := GameState.rp_job
	GameState.rp_job = ""
	status = ""
	if Factions.FACTIONS.has(job):
		_take_off_uniform()
		patients.clear()
		if not _parcel.is_empty():
			_parcel = {}
			GameState.waypoint = null
		if _car != null and is_instance_valid(_car) and _car.driver == null:
			_car.queue_free()
			_car = null
		if tell:
			GameState.notify.emit("Fin de ton service : %s." % Factions.FACTIONS[job]["name"])
	elif tell and Net.JOBS.has(job):
		GameState.notify.emit("Fin de ton service de %s." % Net.JOBS[job].to_lower())
	if job == "mecanicien" and _car != null and is_instance_valid(_car) and _car.driver == null:
		_car.queue_free()
		_car = null


# --- Menu MÉTIERS ------------------------------------------------------------------------

func open_menu() -> void:
	var counts := {"taxi": 0, "police": 0, "vendeur": 0, "samu": 0, "gang": 0, "mecanicien": 0}
	for id in Net.roster:
		var j: String = Net.roster[id]["job"]
		if counts.has(j):
			counts[j] += 1
	var choices: Array = []
	var job := GameState.rp_job
	var mine := my_faction()
	if job != "":
		choices.append(["Quitter le service (%s)" % Net.JOBS[job], func():
			if GameState.rp_job == "taxi" and main.player.current_vehicle:
				GameState.notify.emit("Descends du taxi pour arrêter le service.")
			else:
				_stop(true)])
	else:
		for fid in Factions.FACTIONS:
			var f: String = fid
			var info: Dictionary = Factions.FACTIONS[f]
			if mine == f:
				choices.append(["Prendre le service : %s (%s)" % [info["name"], Factions.rank_name(f, _xp())], func(): _menu_hq(f)])
			elif mine == "":
				choices.append(["Rejoindre : %s (au %s)" % [info["name"], info["hq"]], func(): _menu_hq(f)])
		choices.append(["Tenir un étal au marché", _menu_vendor])
		choices.append(["Devenir mécanicien (dépannage des joueurs)", _start_mechanic])
		choices.append(["Devenir taximan (conduire un taxi)", func():
			GameState.notify.emit("Monte au volant d'un taxi : tu es aussitôt en service et les joueurs peuvent t'appeler.")])
	choices.append(["Appeler un taxi (%d en service)" % counts["taxi"], func(): Net.call_service("taxi")])
	choices.append(["Appeler la police (%d en service)" % counts["police"], func(): Net.call_service("police")])
	choices.append(["Appeler le SAMU (%d en service)" % counts["samu"], func(): Net.call_service("samu")])
	choices.append(["Appeler un mécanicien (%d en service)" % counts["mecanicien"], func(): Net.call_service("mecanicien")])
	if mine != "" and job == "":
		choices.append(["Quitter la faction : %s (grade perdu)" % Factions.FACTIONS[mine]["name"], _confirm_leave])
	var title := "Métiers en ligne — %d taximan(s), %d policier(s), %d au SAMU, %d vendeur(s)" % [counts["taxi"], counts["police"], counts["samu"], counts["vendeur"]]
	if mine != "":
		var left := Factions.xp_to_next(_xp())
		title += "\nTa faction : %s (%d XP%s)" % [faction_title(), _xp(), (", encore %d pour la promotion" % left) if left > 0 else ""]
	main.hud.show_choices(title, choices, func(): pass)


func _confirm_leave() -> void:
	main.hud.show_choices("Quitter : %s ? Ton grade (%s) sera perdu." % [Factions.FACTIONS[my_faction()]["name"], Factions.rank_name(my_faction(), _xp())], [
		["Oui, quitter la faction", _leave_faction], ["Non", func(): pass]], func(): pass)


## Aller au QG d'une faction (ou y agir si on y est déjà)
func _menu_hq(f: String) -> void:
	var hq: String = Factions.FACTIONS[f]["hq"]
	if _hq_here(main.player.global_position) == f and main.player.current_vehicle == null:
		if my_faction() == f:
			_start_duty(f)
		else:
			_join_menu(f)
	else:
		GameState.waypoint = main.city.places[hq]
		GameState.notify.emit("Va au %s (GPS activé), puis appuie sur l'action." % hq)


func _menu_vendor() -> void:
	var pos: Vector3 = main.player.global_position
	var m := _nearest_market(pos)
	if m == "":
		return
	if pos.distance_to(_market_pos()) < STALL_RANGE and main.player.current_vehicle == null:
		_start_vendor(m)
	else:
		GameState.waypoint = _market_pos()
		GameState.notify.emit("Va au %s pour tenir un étal (GPS activé)." % m)


# --- Chaque image ------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not Net.online:
		return
	var p = main.player
	var veh = p.current_vehicle
	var in_taxi: bool = veh != null and veh.vehicle_type == "taxi"
	if in_taxi and GameState.rp_job == "":
		GameState.rp_job = "taxi"
		GameState.notify.emit("Taximan en service : les joueurs peuvent t'appeler depuis MÉTIERS. Salaire : %s toutes les %d minutes." % [GameState.fcfa(Net.SALARY["taxi"]), int(Net.PAY_EVERY / 60.0)])
	elif GameState.rp_job == "taxi" and not in_taxi:
		_stop(true)
	match GameState.rp_job:
		"police":
			_update_police(delta)
		"samu":
			_update_samu()
		"gang":
			_update_gang()
		"vendeur":
			_update_vendor(delta)
		"taxi":
			status = "Taximan en service — en attente d'un appel"
		"mecanicien":
			status = "Mécanicien en service — va voir les joueurs qui t'appellent"
		_:
			status = ""
	_update_down(delta)
	_update_fare()


func _update_police(delta: float) -> void:
	if GameState.wanted > 0:
		_stop(false)
		GameState.notify.emit("Un policier recherché ? Tu es suspendu de tes fonctions !")
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 2.0
	var rank := Factions.rank_name("police", _xp())
	var pos: Vector3 = main.player.get_world_position()
	var s = main.remote_players.nearest_wanted(pos)
	if s == null:
		_suspect = -1
		status = "%s en service — patrouille" % rank
		return
	var d := int(pos.distance_to(s["pos"]))
	status = "[%s] Suspect : %s %s — %d m (approche-toi à pied pour l'arrêter)" % [rank, s["pseudo"], "*".repeat(s["wl"]), d]
	GameState.waypoint = s["pos"]
	if s["id"] != _suspect:
		_suspect = s["id"]
		GameState.notify.emit("Avis de recherche : %s (%s). Sa position est sur ton GPS." % [s["pseudo"], "*".repeat(s["wl"])])


func _update_vendor(delta: float) -> void:
	var p = main.player
	if p.current_vehicle != null or p.global_position.distance_to(_market_pos()) > STALL_LEAVE:
		_stop(false)
		GameState.notify.emit("Tu as laissé ton étal : fin du service de vendeur.")
		return
	status = "Vendeur au %s — %d vente(s)" % [_market, _sales]
	_sale_t -= delta
	if _sale_t <= 0.0:
		_sale_t = randf_range(25.0, 45.0)
		var item: Array = SELL_ITEMS.pick_random()
		_sales += 1
		GameState.add_money(item[1], "%s t'achète : %s" % [NPC_BUYERS.pick_random(), item[0]])
		Audio.play_sfx("coin", -12.0)


# --- SAMU ----------------------------------------------------------------------------------

func _on_patient(id: int, who: String, pos: Vector3, down: bool) -> void:
	if not down:
		patients.erase(id)
		return
	patients[id] = {"who": who, "pos": pos}
	if GameState.rp_job == "samu":
		GameState.waypoint = pos
		GameState.notify.emit("URGENCE : %s est à terre ! Sa position est sur ton GPS." % who)
		Audio.play_sfx("coin", -10.0)


func _update_samu() -> void:
	var pos: Vector3 = main.player.get_world_position()
	var best := -1
	var bd := INF
	for id in patients:
		var d: float = pos.distance_to(patients[id]["pos"])
		if d < bd:
			bd = d
			best = id
	var rank := Factions.rank_name("samu", _xp())
	if best == -1:
		_patient = -1
		status = "%s du SAMU en service — aucune urgence" % rank
		return
	status = "[%s] Urgence : %s — %d m (approche-toi à pied pour le soigner)" % [rank, patients[best]["who"], int(bd)]
	if best != _patient:
		_patient = best
		GameState.waypoint = patients[best]["pos"]


## Ce joueur attend-il les soins du secouriste que je suis ?
func can_heal(id: int) -> bool:
	return GameState.rp_job == "samu" and patients.has(id)


## (joueur) tombé à terre : s'il y a des secouristes en service, on les attend. Renvoie false sinon.
func go_down() -> bool:
	if not Net.online:
		return false
	var medics := 0
	for id in Net.roster:
		if Net.roster[id]["job"] == "samu":
			medics += 1
	if medics == 0:
		return false
	if GameState.rp_job != "":
		_stop(false)
	_down_t = DOWN_TIME
	main.player.frozen = true
	main.player.start_emote("crouch")
	Net.factions.set_down(true)
	GameState.notify.emit("Tu es à terre ! %d secouriste(s) du SAMU prévenu(s). Tiens bon, sinon direction l'hôpital." % medics)
	return true


func _update_down(delta: float) -> void:
	if _down_t < 0.0:
		return
	_down_t -= delta
	status = "À TERRE — le SAMU arrive (%d s avant l'hôpital)" % int(ceil(_down_t))
	if _down_t <= 0.0:
		_end_down()
		main.go_to_hospital()


func _end_down() -> void:
	_down_t = -1.0
	status = ""
	main.player.frozen = false
	main.player.stop_emote()
	Net.factions.set_down(false)


func _on_healed(medic: String) -> void:
	if _down_t < 0.0:
		return
	_end_down()
	GameState.revive()
	GameState.health = 70.0
	GameState.notify.emit("%s du SAMU t'a relevé sur place ! Pas besoin d'aller à l'hôpital." % medic)
	Audio.play_sfx("coin", -10.0)


# --- Gang : colis à livrer ----------------------------------------------------------------

func _gang_menu() -> void:
	var choices: Array = []
	if _parcel.is_empty():
		choices.append(["Prendre un colis à livrer (la police sera prévenue)", _take_parcel])
	choices.append(["Quitter le service", func(): _stop(true)])
	main.hud.show_choices("Gang de la Médina — %s" % Factions.rank_name("gang", _xp()), choices, func(): pass)


func _take_parcel() -> void:
	var from: Vector3 = main.player.global_position
	var options: Array = []
	for place_name in main.city.places:
		var d: float = from.distance_to(main.city.places[place_name])
		if d > PARCEL_MIN and d < PARCEL_MAX:
			options.append(place_name)
	if options.is_empty():
		GameState.notify.emit("Pas de livraison pour le moment.")
		return
	var dest: String = options.pick_random()
	var pos: Vector3 = main.city.places[dest]
	var pay := (2500.0 + from.distance_to(pos) * 3.0) * (1.0 + 0.25 * Factions.rank_of(_xp()))
	_parcel = {"dest": dest, "pos": pos, "pay": int(snappedf(pay, 100.0))}
	GameState.waypoint = pos
	GameState.add_wanted(2, "Un colis louche... quelqu'un a prévenu la police !")
	GameState.notify.emit("Livre le colis à %s (GPS) : %s à la clé. Ne te fais pas arrêter !" % [dest, GameState.fcfa(_parcel["pay"])])


func _update_gang() -> void:
	var rank := Factions.rank_name("gang", _xp())
	if _parcel.is_empty():
		status = "%s du gang — prends un colis au Marché Tilène" % rank
		return
	var d: float = main.player.get_world_position().distance_to(_parcel["pos"])
	status = "[%s] Colis pour %s — %d m" % [rank, _parcel["dest"], int(d)]
	if d < PARCEL_ARRIVAL:
		GameState.add_money(_parcel["pay"], "Colis livré à %s" % _parcel["dest"])
		_parcel = {}
		GameState.waypoint = null
		_gain_xp(3)
		GameState.notify.emit("Livraison faite. Retourne au Marché Tilène pour un autre colis.")


# --- Passager d'un taxi joueur -----------------------------------------------------------

## Le joueur monte dans le taxi d'un autre joueur et choisit sa destination.
func take_taxi(driver: int, who: String, v) -> void:
	var pp: Vector3 = main.player.global_position
	var options: Array = []
	for place_name in main.transit.TAXI_PLACES:
		if not main.city.places.has(place_name):
			continue
		var pos: Vector3 = main.city.places[place_name]
		if pos.distance_to(pp) < 80.0:
			continue
		options.append([main.transit.taxi_price(pp, pos), place_name])
	options.sort_custom(func(a, b): return a[0] < b[0])
	var choices: Array = []
	for o in options.slice(0, 8):
		var price: int = o[0]
		var dest: String = o[1]
		choices.append(["%s — %s" % [dest, GameState.fcfa(price)], func(): _start_fare(driver, who, v, dest, price)])
	main.hud.show_choices("Taxi de %s — « Fan nga dem ? » (où vas-tu ?)" % who, choices, func(): pass)


func _start_fare(driver: int, who: String, v, dest: String, price: int) -> void:
	if not is_instance_valid(v) or v.global_position.distance_to(main.player.global_position) > 9.0:
		GameState.notify.emit("Le taxi de %s est parti." % who)
		return
	if GameState.money < price:
		GameState.notify.emit("Il te faut %s pour cette course." % GameState.fcfa(price))
		return
	var pos: Vector3 = main.city.places[dest]
	main.player.ride(v)
	Net.send_fare(driver, dest, price, pos)
	fare = {"driver": driver, "pseudo": who, "dest": dest, "pos": pos, "price": price}
	GameState.waypoint = pos
	GameState.notify.emit("Course vers %s avec %s : %s à payer à l'arrivée." % [dest, who, GameState.fcfa(price)])


func _update_fare() -> void:
	if fare.is_empty():
		return
	var p = main.player
	if p.riding == null or not is_instance_valid(p.riding):
		GameState.notify.emit("Tu es descendu avant d'arriver : la course n'est pas payée.")
		fare = {}
		return
	var d: float = p.get_world_position().distance_to(fare["pos"])
	status = "Taxi de %s → %s (%s) — %d m" % [fare["pseudo"], fare["dest"], GameState.fcfa(fare["price"]), int(d)]
	if d < ARRIVAL:
		if Net.give_money(fare["driver"], fare["price"], "Course de taxi"):
			GameState.notify.emit("Arrivé à %s ! Tu paies %s à %s. Appuie sur l'action pour descendre." % [fare["dest"], GameState.fcfa(fare["price"]), fare["pseudo"]])
		else:
			GameState.notify.emit("Tu n'as pas de quoi payer la course... %s n'est pas content !" % fare["pseudo"])
		GameState.waypoint = null
		fare = {}
		status = ""


# --- Acheter à un joueur vendeur ---------------------------------------------------------

func buy_from(vendor: int, who: String) -> void:
	var choices: Array = []
	for it in SELL_ITEMS:
		var item: Array = it
		choices.append(["%s — %s" % [item[0], GameState.fcfa(item[1])], func(): _buy(vendor, who, item)])
	main.hud.show_choices("Étal de %s — « Lu nga bëgg ? »" % who, choices, func(): pass)


func _buy(vendor: int, who: String, item: Array) -> void:
	if not Net.roster.has(vendor):
		GameState.notify.emit("%s a fermé son étal." % who)
		return
	if not Net.give_money(vendor, item[1], "Vente : %s" % item[0]):
		GameState.notify.emit("Il te faut %s." % GameState.fcfa(item[1]))
		return
	var food: int = item[2]
	if food > 0 and GameState.take_food(item[0], food):
		GameState.notify.emit("Tu achètes à %s : %s (-%s). Dafa neex !" % [who, item[0], GameState.fcfa(item[1])])
	elif food > 0:
		GameState.notify.emit("Acheté à %s : %s (-%s), rangé dans ton sac pour plus tard." % [who, item[0], GameState.fcfa(item[1])])
	else:
		GameState.add_item(item[0])
		GameState.notify.emit("Acheté à %s : %s (-%s), rangé dans ton sac." % [who, item[0], GameState.fcfa(item[1])])
	Audio.play_sfx("coin", -12.0)
