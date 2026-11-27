extends Node3D
## Logement : louer une chambre ou acheter son chez-soi, de la Médina aux villas du Cap Manuel.
## - Devant la porte, un panneau « À LOUER » / « À VENDRE » : visiter, louer ou acheter.
## - Chez soi (intérieur meublé selon le logement) : dormir (le temps avance, santé, sauvegarde),
##   ranger son argent dans le coffre (villa), et c'est là qu'on se réveille.
## - Loyer payé chaque matin (8 h) ; trois jours d'impayés et le bailleur reprend la chambre.
## - Garage (appartement, villa) : garer sa voiture devant la porte, la ressortir plus tard ;
##   une voiture rangée au garage t'appartient (la conduire n'est plus un vol).
## - Commerces (boutique, tangana, dibiterie, lavage auto) : achetés comme une maison, on y embauche des
##   employés, on commande le stock et on fixe les prix (scripts/world/commerce.gd) ; la recette de chaque
##   journée tombe dans la caisse, à encaisser devant la porte.
## - Revente : 70 % du prix d'achat.
## - En ligne, chaque maison ou commerce à vendre n'a qu'un propriétaire dans tout Dakar
##   (registre du serveur : scripts/net/net_properties.gd) ; son pseudo est écrit sur le panneau.

const Mk = preload("res://scripts/util/mk.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")

const DOOR_RANGE := 2.6
const GARAGE_RANGE := 7.0
const EVICT_DAYS := 3
const RESALE := 0.7
const TILL_DAYS := 7 ## jours de recette que garde un commerce avant qu'on l'encaisse
## id → place de repère, décalage, nom, type d'intérieur (« commerce » : pas d'intérieur), location par jour
## (0 = à vendre), prix, places de garage, recette par jour (commerces), description
const PROPERTIES := {
	"chambre_medina": {"place": "Marché Tilène", "along": -18.0, "name": "Chambre à la Médina", "kind": "chambre",
		"rent": 1000, "price": 0, "garage": 0, "desc": "Une chambre simple dans une maison familiale : natte, matelas, ventilateur."},
	"studio_gueule_tapee": {"place": "Mosquée Seydou Nourou Tall", "along": 16.0, "name": "Studio à Gueule Tapée", "kind": "studio",
		"rent": 0, "price": 250000, "garage": 0, "desc": "Un studio à toi, avec coin cuisine et télévision."},
	"appart_plateau": {"place": "Marché Kermel", "along": -22.0, "name": "Appartement au Plateau", "kind": "appartement",
		"rent": 0, "price": 900000, "garage": 1, "desc": "Appartement moderne au cœur du Plateau, salon, chambre et une place de garage."},
	"loft_plateau": {"place": "Cathédrale", "along": 24.0, "name": "Loft du Plateau", "kind": "loft",
		"rent": 0, "price": 3000000, "garage": 2, "desc": "Loft moderne sur deux niveaux : grand salon en cuir, escalier en colimaçon, bibliothèque, deux places de garage."},
	"villa_cap_manuel": {"place": "Plage de l'Anse Bernard", "along": 30.0, "name": "Villa au Cap Manuel", "kind": "villa",
		"rent": 0, "price": 4500000, "garage": 3, "desc": "Villa de luxe face à la mer : grand salon, piscine, coffre-fort, garage de 3 voitures."},
	"maison_fass": {"place": "Garage mécanique (Fass Delorme)", "along": -18.0, "name": "Maison à Fass", "kind": "appartement",
		"rent": 0, "price": 1200000, "garage": 1, "desc": "Maison de quartier avec cour, salon, chambre et une place pour la voiture."},
	"maison_medina": {"place": "Garage mécanique (Médina)", "along": 20.0, "name": "Maison familiale à la Médina", "kind": "appartement",
		"rent": 0, "price": 1500000, "garage": 2, "desc": "Grande maison familiale de la Médina : salon, chambres et deux places de garage."},
	"tangana_medina": {"place": "Polyclinique de la Médina", "along": -20.0, "name": "Tangana de la Médina", "kind": "commerce",
		"rent": 0, "price": 350000, "garage": 0, "income": 3500, "desc": "Petit tangana du matin : café Touba, pain, omelettes. Rapporte chaque jour."},
	"boutique_sandaga": {"place": "Marché Sandaga", "along": 26.0, "name": "Boutique de tissus à Sandaga", "kind": "commerce",
		"rent": 0, "price": 600000, "garage": 0, "income": 6000, "desc": "Wax, bazin et voiles au cœur de Sandaga. Rapporte chaque jour."},
	"lavage_rebeuss": {"place": "Garage mécanique (Rebeuss)", "along": -16.0, "name": "Lavage auto de Rebeuss", "kind": "commerce",
		"rent": 0, "price": 800000, "garage": 0, "income": 8000, "desc": "Station de lavage avec deux employés. Rapporte chaque jour."},
	"dibiterie_gueule_tapee": {"place": "Garage mécanique (Gueule Tapée)", "along": 18.0, "name": "Dibiterie de Gueule Tapée", "kind": "commerce",
		"rent": 0, "price": 1200000, "garage": 0, "income": 12000, "desc": "Dibiterie réputée du quartier, grillades le soir. Rapporte chaque jour."},
	"resto_maiga": {"place": "Restaurant Maïga", "along": 14.0, "name": "Fast-Food Restaurant Maïga", "kind": "commerce",
		"rent": 0, "price": 850000, "garage": 0, "income": 8500, "desc": "Le célèbre fast-food Maïga : pain brochette, spaghetti, omelettes. Ouvert jour et nuit. Rapporte chaque jour."},
}

var main
var doors := {} ## id → {pos, n, f, label}
var _next_day_check := 0
var _visit := "" ## logement visité sans être à nous
var _pending_buy := {} ## (en ligne) achat en attente de la réponse du serveur : {id, total}


func _ready() -> void:
	var city = main.city
	for id in PROPERTIES:
		var p: Dictionary = PROPERTIES[id]
		if not city.places.has(p["place"]):
			continue
		var info: Array = city.place_info[p["place"]]
		var n := Vector3(info[3], 0, info[4])
		var f := Vector3(info[7], 0, info[8]) if info.size() > 8 else Vector3(-n.z, 0, n.x)
		var pos: Vector3 = city.places[p["place"]] + f * float(p["along"]) + n * 1.3
		var h := Node3D.new()
		add_child(h)
		h.global_position = Vector3(pos.x, 0.16, pos.z)
		# Porte et panneau
		var door := Mk.box(h, Vector3(1.2, 2.2, 0.1), Vector3(0, 1.1, 0) + n * 0.25, Color("6b4f3a"))
		door.rotation.y = atan2(n.x, n.z)
		var lab := Mk.label(h, "", Vector3(0, 2.7, 0), Mk.SIGN_SIZE, Color("ffd166"))
		doors[id] = {"pos": h.global_position, "n": n, "f": f, "label": lab}
	GameState.new_day.connect(_on_new_day)
	Net.properties.changed.connect(_refresh)
	Net.properties.claim_result.connect(_on_claim)
	ensure_starter_home()
	_refresh()


## Garantit que chaque joueur possède une maison dès le début
func ensure_starter_home() -> void:
	var owned_list: Array = GameState.home.get("owned", [])
	var rented_id: String = GameState.home.get("rented", "")
	if owned_list.is_empty() and rented_id == "":
		owned_list.append("studio_gueule_tapee")
		GameState.home["owned"] = owned_list
		GameState.save_game()


# --- État -----------------------------------------------------------------------------

func owned(id: String) -> bool:
	return id in GameState.home.get("owned", [])


func rented() -> String:
	return GameState.home.get("rented", "")


func has_home(id: String) -> bool:
	return owned(id) or rented() == id


static func is_commerce(id: String) -> bool:
	return PROPERTIES[id]["kind"] == "commerce"


## (en ligne) propriétaire d'une maison ou d'un commerce qui n'est pas à nous ("" = libre)
func other_owner(id: String) -> String:
	if not Net.online or owned(id):
		return ""
	var who: String = Net.properties.owner_of(id)
	return "" if who == Net.pseudo else who


func till(id: String) -> int:
	return int(GameState.home.get("till", {}).get(id, 0))


## Logement principal (où l'on se réveille) : le plus beau que l'on possède, sinon la location
func main_home() -> String:
	var best := ""
	var best_price := -1
	for id in GameState.home.get("owned", []):
		if PROPERTIES.has(id) and not is_commerce(id) and int(PROPERTIES[id]["price"]) > best_price:
			best = id
			best_price = PROPERTIES[id]["price"]
	if best == "" and rented() != "":
		best = rented()
	return best


func home_position() -> Variant:
	var id := main_home()
	if id == "" or not doors.has(id):
		return null
	return doors[id]["pos"] - doors[id]["n"] * 2.2 + Vector3(0, 0.3, 0)


func _refresh() -> void:
	for id in doors:
		var p: Dictionary = PROPERTIES[id]
		var lab: Label3D = doors[id]["label"]
		var other := other_owner(id)
		if has_home(id) and is_commerce(id):
			lab.text = "%s\nTON COMMERCE — recette %s" % [p["name"], GameState.fcfa(till(id))]
			lab.modulate = Color("7cfc9a")
		elif has_home(id):
			lab.text = "%s\nCHEZ TOI" % p["name"]
			lab.modulate = Color("7cfc9a")
		elif other != "":
			lab.text = "%s\nPROPRIÉTÉ DE %s" % [p["name"], other.to_upper()]
			lab.modulate = Color("c9c9c9")
		elif is_commerce(id):
			lab.text = "%s\nÀ VENDRE — %s (%d employés, jusqu'à %s / jour)" % [p["name"], GameState.fcfa(p["price"]), int(main.commerce.slots(id)) if main.commerce else 2, GameState.fcfa(int(p["income"]) * 2)]
			lab.modulate = Color("ffd166")
		elif int(p["rent"]) > 0:
			lab.text = "%s\nÀ LOUER — %s / jour" % [p["name"], GameState.fcfa(p["rent"])]
			lab.modulate = Color("ffd166")
		else:
			lab.text = "%s\nÀ VENDRE — %s" % [p["name"], GameState.fcfa(p["price"])]
			lab.modulate = Color("ffd166")


# --- Actions devant la porte -------------------------------------------------------------

func _door_near(pos: Vector3, rng: float) -> String:
	for id in doors:
		if Vector2(pos.x - doors[id]["pos"].x, pos.z - doors[id]["pos"].z).length() < rng:
			return id
	return ""


func get_hint() -> String:
	var p = main.player
	if main.interiors.inside != "":
		return ""
	if p.current_vehicle != null:
		var gid := _door_near(p.current_vehicle.global_position, GARAGE_RANGE)
		if gid != "" and owned(gid) and int(PROPERTIES[gid]["garage"]) > 0:
			return "Garer la voiture dans mon garage"
		return ""
	if p.riding != null:
		return ""
	var id := _door_near(p.global_position, DOOR_RANGE)
	if id == "":
		return ""
	if has_home(id):
		return ("Ton commerce : " if is_commerce(id) else "Rentrer chez toi : ") + PROPERTIES[id]["name"]
	if other_owner(id) != "":
		return "%s (propriété de %s)" % [PROPERTIES[id]["name"], other_owner(id)]
	if is_commerce(id):
		return "Commerce à vendre : " + PROPERTIES[id]["name"]
	return ("Louer / visiter : " if int(PROPERTIES[id]["rent"]) > 0 else "Visiter / acheter : ") + PROPERTIES[id]["name"]


func try_interact() -> bool:
	var h := get_hint()
	if h == "":
		return false
	var p = main.player
	if p.current_vehicle != null:
		_park(_door_near(p.current_vehicle.global_position, GARAGE_RANGE), p.current_vehicle)
		return true
	var id := _door_near(p.global_position, DOOR_RANGE)
	if has_home(id) and is_commerce(id):
		_commerce_menu(id)
	elif has_home(id):
		_home_menu(id)
	elif other_owner(id) != "":
		GameState.notify.emit("Cette propriété appartient à %s. Elle n'est pas à vendre." % other_owner(id))
	else:
		_offer(id)
	return true


func _commerce_menu(id: String) -> void:
	if main.commerce:
		main.commerce.menu(id)
		return
	var p: Dictionary = PROPERTIES[id]
	var choices: Array = []
	if till(id) > 0:
		choices.append(["Encaisser la recette (%s)" % GameState.fcfa(till(id)), func(): _collect(id)])
	choices.append(["Revendre (%s)" % GameState.fcfa(_resale(id)), func(): _confirm_sell(id)])
	main.hud.show_choices("%s — rapporte %s chaque matin (jusqu'à %d jours de recette en caisse)" % [p["name"], GameState.fcfa(p["income"]), TILL_DAYS], choices, func(): pass)


func _collect(id: String) -> void:
	var amount := till(id)
	var t: Dictionary = GameState.home.get("till", {})
	t.erase(id)
	GameState.home["till"] = t
	GameState.add_money(amount, "Recette : %s" % PROPERTIES[id]["name"])
	_refresh()
	GameState.save_game()


func _resale(id: String) -> int:
	return int(snappedf(int(PROPERTIES[id]["price"]) * RESALE, 1000.0))


func _confirm_sell(id: String) -> void:
	main.hud.show_choices("Revendre %s pour %s ?" % [PROPERTIES[id]["name"], GameState.fcfa(_resale(id))], [
		["Oui, revendre", func(): _sell(id)], ["Non", func(): pass]], func(): pass)


func _sell(id: String) -> void:
	if not GameState.garage.get(id, []).is_empty():
		GameState.notify.emit("Sors d'abord tes voitures du garage.")
		return
	if till(id) > 0:
		_collect(id)
	var list: Array = GameState.home.get("owned", [])
	list.erase(id)
	GameState.home["owned"] = list
	GameState.garage.erase(id)
	if main.commerce and is_commerce(id):
		main.commerce.sold(id)
	Net.properties.release(id)
	GameState.add_money(_resale(id), "Vente : %s" % PROPERTIES[id]["name"])
	_refresh()
	GameState.save_game()


## --- Échange entre joueurs (scripts/net/net_trade.gd) : la maison ou le commerce change de main ---
## Raison pour laquelle on ne peut pas céder ce bien ("" : possible)
func trade_block(id: String) -> String:
	if not has_home(id) or not PROPERTIES.has(id) or int(PROPERTIES[id]["price"]) <= 0:
		return "pas à toi"
	if not GameState.garage.get(id, []).is_empty():
		return "voitures au garage"
	return ""


## Céder un bien : la recette en caisse est encaissée, les employés et le stock partent avec le commerce
func give_away(id: String) -> Dictionary:
	if till(id) > 0:
		_collect(id)
	var list: Array = GameState.home.get("owned", [])
	list.erase(id)
	GameState.home["owned"] = list
	GameState.garage.erase(id)
	var b := {}
	if is_commerce(id) and GameState.home.get("biz", {}).has(id):
		b = GameState.home["biz"][id].duplicate(true)
	if main.commerce and is_commerce(id):
		main.commerce.sold(id)
	_refresh()
	return b


## Recevoir un bien (ou le récupérer si l'échange échoue)
func take(id: String, b: Dictionary) -> void:
	if not PROPERTIES.has(id) or has_home(id):
		return
	var list: Array = GameState.home.get("owned", [])
	list.append(id)
	GameState.home["owned"] = list
	if is_commerce(id):
		if not b.is_empty():
			var all: Dictionary = GameState.home.get("biz", {})
			all[id] = b
			GameState.home["biz"] = all
		elif main.commerce:
			main.commerce.biz(id)
	_refresh()


func _home_menu(id: String) -> void:
	var choices: Array = [["Entrer", func(): enter(id)]]
	var cars: Array = GameState.garage.get(id, [])
	if int(PROPERTIES[id]["garage"]) > 0:
		for k in cars.size():
			var idx: int = k
			var car: Dictionary = cars[k]
			choices.append(["Sortir du garage : %s" % Vehicle.TYPES.get(car["type"], {"name": car["type"]})["name"], func(): _unpark(id, idx)])
	if rented() == id:
		choices.append(["Rendre la chambre", func():
			GameState.home["rented"] = ""
			GameState.notify.emit("Tu rends les clés de la chambre.")
			_refresh()])
	elif owned(id):
		choices.append(["Revendre (%s)" % GameState.fcfa(_resale(id)), func(): _confirm_sell(id)])
	main.hud.show_choices(PROPERTIES[id]["name"], choices, func(): pass)


func _offer(id: String) -> void:
	var p: Dictionary = PROPERTIES[id]
	var choices: Array = []
	if not is_commerce(id):
		choices.append(["Visiter", func():
			_visit = id
			enter(id)])
	if int(p["rent"]) > 0:
		var deposit: int = int(p["rent"]) * 3
		choices.append(["Louer : caution %s puis %s par jour" % [GameState.fcfa(deposit), GameState.fcfa(p["rent"])], func():
			if rented() != "":
				GameState.notify.emit("Tu loues déjà un logement. Rends-le d'abord.")
			elif GameState.spend(deposit):
				GameState.home["rented"] = id
				GameState.home["unpaid"] = 0
				GameState.notify.emit("Le bailleur te donne les clés. Loyer : %s chaque matin." % GameState.fcfa(p["rent"]))
				_refresh()
			else:
				GameState.notify.emit("Il te faut %s pour la caution." % GameState.fcfa(deposit))])
	else:
		var fees := int(round(int(p["price"]) * 0.05 / 1000.0)) * 1000
		var total: int = int(p["price"]) + fees
		choices.append(["Acheter : %s + frais de notaire %s" % [GameState.fcfa(p["price"]), GameState.fcfa(fees)], func(): _buy(id, total)])
	main.hud.show_choices("%s\n%s" % [p["name"], p["desc"]], choices, func(): pass)


## Achat : on paie avec l'argent liquide, complété par le compte en banque.
## En ligne, le serveur réserve d'abord la propriété (un seul propriétaire dans Dakar).
func _buy(id: String, total: int) -> void:
	if GameState.money + GameState.bank < total:
		GameState.notify.emit("Il te faut %s (liquide + banque). Travaille encore un peu !" % GameState.fcfa(total))
		return
	if Net.online:
		_pending_buy = {"id": id, "total": total}
		Net.properties.claim(id)
		return
	_complete_buy(id, total)


func _on_claim(pid: String, ok: bool, who: String) -> void:
	if _pending_buy.get("id", "") != pid:
		_refresh()
		return
	var total: int = _pending_buy["total"]
	_pending_buy = {}
	if not ok:
		GameState.notify.emit("Trop tard : %s vient d'acheter %s." % [who, PROPERTIES[pid]["name"]])
		_refresh()
		return
	if GameState.money + GameState.bank < total:
		Net.properties.release(pid)
		return
	_complete_buy(pid, total)


func _complete_buy(id: String, total: int) -> void:
	var from_bank: int = maxi(0, total - GameState.money)
	GameState.money -= total - from_bank
	GameState.bank -= from_bank
	var list: Array = GameState.home.get("owned", [])
	list.append(id)
	GameState.home["owned"] = list
	if is_commerce(id):
		GameState.notify.emit("Félicitations ! %s est à toi. Devant la porte : embauche ton équipe (2 jours de stock offerts). La recette tombe chaque matin." % PROPERTIES[id]["name"])
		if main.commerce:
			main.commerce.biz(id)
	else:
		GameState.notify.emit("Félicitations ! Tu es propriétaire : %s. Tu te réveilleras ici." % PROPERTIES[id]["name"])
	Audio.play_sfx("coin", -4.0)
	_refresh()
	GameState.save_game()


func enter(id: String) -> void:
	var d: Dictionary = doors[id]
	main.interiors.enter_custom(PROPERTIES[id]["name"], "home_" + PROPERTIES[id]["kind"], d["pos"] + d["n"] * 0.5, d["n"])


# --- Chez soi : le lit et le coffre ---------------------------------------------------------

func bed_menu() -> void:
	var choices: Array = []
	var visiting := _visit != "" and not has_home(_visit)
	if visiting:
		main.hud.show_choices("Visite", [["« C'est joli ! » (achète ou loue pour pouvoir dormir ici)", func(): pass]], func(): pass)
		return
	if not Net.online:
		choices.append(["Dormir jusqu'au matin (7 h)", func(): _sleep(-1.0)])
		choices.append(["Faire une sieste (2 heures)", func(): _sleep(120.0)])
	else:
		choices.append(["Se reposer (en ligne, l'heure de la ville ne change pas)", func(): _sleep(0.0)])
	choices.append(["Cuisiner (Coin cuisine & garde-manger)", kitchen_menu])
	choices.append(["Changer d'habits (Dressing & Studio 3D)", wardrobe_menu])
	choices.append(["Sauvegarder la partie", func():
		GameState.save_game()
		GameState.notify.emit("Partie sauvegardée.")])
	main.hud.show_choices("Ton lit", choices, func(): pass)


func kitchen_menu() -> void:
	if main.cooking:
		main.cooking.menu()
	else:
		GameState.notify.emit("La cuisine est prête.")


func wardrobe_menu() -> void:
	var choices: Array = []
	choices.append(["🎨 Ouvrir le Studio 3D complet (Look, coiffure, teint, habits)", _open_studio_in_house])
	choices.append(["👑 Grand Boubou Bazin Royal (Fête & Vendredi)", func():
		_apply_quick_outfit("bazin_or,bazin_or,kufi_bazin,court,noir,teint_ebene", "Grand Boubou en Bazin Royal enfilé !")
	])
	choices.append(["🦁 Tenue des Lions de la Teranga (Vert & Jaune)", func():
		_apply_quick_outfit("vert,jaune,,court,noir,teint_ebene", "Maillot officiel des Lions de la Teranga enfilé !")
	])
	choices.append(["👕 Tenue Décontractée Dakar (T-shirt & Jean)", func():
		_apply_quick_outfit("blanc,bleu,,degrade,noir,teint_caramel", "Tenue décontractée enfilée !")
	])
	choices.append(["🕌 Tunique Traditionnelle Blanche", func():
		_apply_quick_outfit("blanc,blanc,kufi_blanc,court,gris,teint_ebene", "Tunique blanche traditionnelle enfilée !")
	])
	choices.append(["🎲 Tenue surprise stylée", _random_quick_outfit])
	main.hud.show_choices("Dressing & Garde-robe de la maison", choices, func(): pass)


func _open_studio_in_house() -> void:
	var CharacterStudioScript = load("res://scripts/ui/character_studio.gd")
	if not CharacterStudioScript:
		return
	var studio = CharacterStudioScript.new(Net.avatar, false)
	main.add_child(studio)
	studio.closed.connect(func(saved: bool):
		if saved:
			if main.player and main.player.has_method("update_avatar"):
				main.player.update_avatar(Net.avatar, GameState.tenue)
			elif main.player and main.player.get("model") and main.player.model.has_method("set_outfit"):
				main.player.model.set_outfit(GameState.tenue)
			GameState.notify.emit("Tu as enfilé ta nouvelle tenue devant le miroir !")
	)


func _apply_quick_outfit(code: String, msg: String) -> void:
	GameState.tenue = code
	if main.player and main.player.has_method("update_avatar"):
		main.player.update_avatar(Net.avatar, GameState.tenue)
	elif main.player and main.player.get("model") and main.player.model.has_method("set_outfit"):
		main.player.model.set_outfit(GameState.tenue)
	GameState.save_game()
	GameState.notify.emit(msg)


func _random_quick_outfit() -> void:
	var OutfitsScript = load("res://scripts/util/outfits.gd")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var color_keys: Array = OutfitsScript.COLORS.keys()
	var rand_top: String = str(color_keys[rng.randi() % color_keys.size()])
	var rand_bot: String = str(color_keys[rng.randi() % color_keys.size()])
	var hat_keys: Array = [""] + OutfitsScript.HATS.keys()
	var rand_hat: String = str(hat_keys[rng.randi() % hat_keys.size()])
	var code := "%s,%s,%s,court,noir,teint_ebene" % [rand_top, rand_bot, rand_hat]
	_apply_quick_outfit(code, "Nouvelle tenue stylée enfilée !")


func _sleep(minutes: float) -> void:
	main.hud.fade_through(func():
		var before := GameState.game_minutes
		if minutes < 0.0:
			var target := 7.0 * 60.0
			minutes = fmod(target - before + 1440.0, 1440.0)
			if minutes < 30.0:
				minutes += 1440.0
		if minutes > 0.0:
			GameState.advance_time(minutes)
		GameState.health = 100.0
		GameState.energy = 100.0
		GameState.hunger = maxf(10.0, GameState.hunger - minutes / 30.0)
		GameState.thirst = maxf(10.0, GameState.thirst - minutes / 25.0)
		GameState.save_game()
		GameState.notify.emit("Tu te réveilles reposé. Il est %02d h %02d." % [int(GameState.game_minutes) / 60, int(GameState.game_minutes) % 60]))


func safe_menu() -> void:
	var choices: Array = []
	var safe: int = GameState.home.get("safe", 0)
	choices.append(["Ranger tout mon argent liquide", func():
		GameState.home["safe"] = safe + GameState.money
		GameState.money = 0
		GameState.notify.emit("Coffre-fort : %s à l'abri." % GameState.fcfa(GameState.home["safe"]))])
	choices.append(["Prendre l'argent du coffre (%s)" % GameState.fcfa(safe), func():
		GameState.money += int(GameState.home.get("safe", 0))
		GameState.home["safe"] = 0
		GameState.notify.emit("Tu prends l'argent du coffre.")])
	main.hud.show_choices("Coffre-fort — %s" % GameState.fcfa(safe), choices, func(): pass)


func left_home() -> void:
	_visit = ""


# --- Loyer -----------------------------------------------------------------------------

func _on_new_day() -> void:
	# (La journée des commerces, recette et taxe, est comptée par commerce.gd)
	_refresh()
	var id := rented()
	if id == "":
		return
	var rent: int = PROPERTIES[id]["rent"]
	if GameState.spend(rent):
		GameState.home["unpaid"] = 0
		GameState.notify.emit("Loyer payé au bailleur : %s." % GameState.fcfa(rent))
	elif GameState.bank >= rent:
		GameState.bank -= rent
		GameState.home["unpaid"] = 0
		GameState.notify.emit("Loyer payé depuis ton compte en banque : %s." % GameState.fcfa(rent))
	else:
		GameState.home["unpaid"] = int(GameState.home.get("unpaid", 0)) + 1
		var u: int = GameState.home["unpaid"]
		if u >= EVICT_DAYS:
			GameState.home["rented"] = ""
			GameState.notify.emit("Le bailleur a repris la chambre : %d jours de loyer impayés !" % u)
			_refresh()
		else:
			GameState.notify.emit("Le bailleur : « Et mon loyer ? » (%d jour(s) d'impayé)" % u)


# --- Garage ----------------------------------------------------------------------------

func _park(id: String, v) -> void:
	var cars: Array = GameState.garage.get(id, [])
	if cars.size() >= int(PROPERTIES[id]["garage"]):
		GameState.notify.emit("Ton garage est plein (%d place(s))." % PROPERTIES[id]["garage"])
		return
	if v.vehicle_type in ["bus", "coach", "police", "army"]:
		GameState.notify.emit("Ce véhicule ne rentre pas dans ton garage (et il se remarque trop...).")
		return
	cars.append({"type": v.vehicle_type, "color": v.get_meta("paint").to_html() if v.has_meta("paint") and v.get_meta("paint") is Color else ""})
	GameState.garage[id] = cars
	main.player.exit_vehicle()
	v.queue_free()
	if GameState.wanted > 0:
		GameState.lose_star()
	GameState.notify.emit("Voiture rangée au garage. Elle est à toi maintenant.")
	GameState.save_game()


func _unpark(id: String, idx: int) -> void:
	var cars: Array = GameState.garage.get(id, [])
	if idx >= cars.size():
		return
	var car: Dictionary = cars[idx]
	cars.remove_at(idx)
	GameState.garage[id] = cars
	var v = Vehicle.new()
	v.vehicle_type = car["type"]
	main.add_child(v)
	v.respawn_in_traffic(main.city, doors[id]["pos"], 3.0, 25.0)
	v.ai_enabled = false
	v.route_active = false
	v.speed = 0.0
	v.set_meta("owned", true)
	if car.get("color", "") != "":
		v.repaint(Color(car["color"]))
	main.player.global_position = v.global_position + Vector3(0, 0.5, 0)
	main.player.enter_vehicle(v)
	GameState.notify.emit("Tu sors ta voiture du garage.")
