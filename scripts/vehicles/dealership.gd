extends Node3D
## Concession auto, véhicules à soi et essence.
## - Concession (près du Garage CFAO, Plateau) : acheter une moto Jakarta, une berline, un taxi ou une
##   camionnette, au choix de la couleur. Le permis de conduire est exigé pour les voitures.
##   Revente à 60 % du prix.
## - Mes véhicules (appli « Oto » du téléphone) : faire venir un de ses véhicules près de soi (un seul
##   dehors à la fois), puis le ranger. L'essence restante est gardée dans la sauvegarde.
## - Assurance : souscrite à la concession pour INSURANCE_DAYS jours de jeu (un pourcentage du prix) ;
##   la réparation du moteur au garage est alors gratuite, et le mécanicien en ligne aussi.
## - Fourrière : arrêté pendant qu'un de ses véhicules est dehors, il part à la fourrière ; on le récupère
##   à l'accueil du commissariat (IMPOUND_FEE), sinon impossible de le faire venir.
## - Essence : chaque véhicule conduit par le joueur a un réservoir (vehicle.gd : fuel). À sec, il ne
##   roule plus. On fait le plein dans les stations-service (Total, Shell, Oilibya...).

const Mk = preload("res://scripts/util/mk.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const Employment = preload("res://scripts/jobs/employment.gd")

const PLACE := "Garage CFAO Express Service"
const RANGE := 4.0
const STATION_RANGE := 16.0
const MAX_OWNED := 4
const RESALE := 0.6
const DELIVERY := 500 ## dépanneuse qui amène le véhicule
const IMPOUND_FEE := 10000 ## sortie de fourrière
const INSURANCE_RATE := 0.03 ## prix de l'assurance : 3 % du prix du véhicule
const INSURANCE_DAYS := 7
const FUEL_PRICE := 50 ## FCFA par pour cent de réservoir (le plein complet : 5 000 FCFA)
## type → [nom, prix, permis exigé, description]
const CATALOG := {
	"jakarta": ["Maxi-Scooter T-MAX de Luxe", 2200000, false, "Le deux-roues de prestige de Dakar : finitions or et noir carbone, double optique LED, accélération vive et grand standing."],
	"grosse_moto": ["Superbike de Luxe (1000cc V4)", 4500000, false, "Hyper-sportive de prestige : châssis carbone, jantes forgées, étriers Brembo et accélération foudroyante."],
	"clando": ["Berline VIP de Luxe (BMW / Mercedes)", 5500000, true, "Grande berline de prestige : confort présidentiel, V8 bi-turbo, vitres teintées et sellerie cuir pleine fleur."],
	"suv": ["SUV de Luxe (Range Rover / V8)", 7500000, true, "Le 4x4 de prestige ultime : imposant, suspension pneumatique, toit panoramique et puissance V8."],
	"taxi": ["Taxi VIP Dakar", 2500000, true, "Taxi moderne grand confort : idéal pour transporter les clients VIP de Dakar."],
	"van": ["Van VIP Grand Standing", 3200000, true, "Grand van tout confort pour les cortèges et les personnalités."],
}
const COLORS := {
	"Noir Onyx Métallisé": Color("0a0a0c"),
	"Blanc Perle Nacré": Color("f8f9fa"),
	"Gris Nardo Satin": Color("1c1d21"),
	"Bleu Nuit Impérial": Color("0b2545"),
	"Rouge Rubis Candy": Color("8b0000"),
	"Or Champagne Royal": Color("c5a059"),
	"Vert Émeraude Métallique": Color("133c2e"),
	"Argent Diamant": Color("5c677d"),
}

var main
var pos := Vector3.ZERO
var stations: Array = [] ## positions des stations-service
var out = null ## véhicule à soi sorti en ville
var _out_idx := -1
var _sync_t := 0.0


func _ready() -> void:
	var city = main.city
	for place_name in city.places:
		if str(place_name).begins_with("Station "):
			stations.append(city.places[place_name])
	if not city.places.has(PLACE):
		return
	var info: Array = city.place_info[PLACE]
	var n := Vector3(info[3], 0, info[4])
	var f := Vector3(info[7], 0, info[8]) if info.size() > 8 else Vector3(-n.z, 0, n.x)
	pos = city.places[PLACE] + f * 10.0 + n * 1.0
	var h := Node3D.new()
	add_child(h)
	h.global_position = Vector3(pos.x, 0.16, pos.z)
	var desk := Mk.box(h, Vector3(1.8, 1.0, 0.6), Vector3(0, 0.5, 0) + n * 0.4, Color("2b2d42"))
	desk.rotation.y = atan2(n.x, n.z)
	Mk.label(h, "CONCESSION AUTO DE LUXE\nMotos sportives, Berlines VIP & SUV", Vector3(0, 2.4, 0), Mk.SIGN_SIZE, Color("ffd166"))


# --- Véhicules à soi -----------------------------------------------------------------------

func owned() -> Array:
	return GameState.vehicles


func vehicle_name(v: Dictionary) -> String:
	var t: String = v.get("type", "")
	return CATALOG[t][0] if CATALOG.has(t) else Vehicle.TYPES.get(t, {"name": t})["name"]


## Faire venir un de ses véhicules près de soi
func bring(idx: int) -> void:
	if idx < 0 or idx >= owned().size():
		return
	if owned()[idx].get("impound", false):
		GameState.notify.emit("Ton véhicule (%s) est à la fourrière : récupère-le à l'accueil du commissariat (%s)." % [vehicle_name(owned()[idx]).to_lower(), GameState.fcfa(IMPOUND_FEE)])
		return
	if main.player.current_vehicle != null or main.interiors.inside != "":
		GameState.notify.emit("Sors d'abord (dehors, à pied) pour faire venir ton véhicule.")
		return
	if out != null and is_instance_valid(out):
		store()
	if not GameState.spend(DELIVERY):
		GameState.notify.emit("La dépanneuse coûte %s." % GameState.fcfa(DELIVERY))
		return
	var data: Dictionary = owned()[idx]
	var v = Vehicle.new()
	v.vehicle_type = data["type"]
	main.add_child(v)
	v.respawn_in_traffic(main.city, main.player.global_position, 8.0, 40.0)
	v.ai_enabled = false
	v.route_active = false
	v.speed = 0.0
	v.fuel = float(data.get("fuel", 100.0))
	v.condition = float(data.get("condition", 100.0))
	v.set_meta("owned", true)
	if str(data.get("color", "")) != "":
		v.repaint(Color(data["color"]))
	out = v
	_out_idx = idx
	GameState.waypoint = v.global_position
	GameState.notify.emit("Ton véhicule t'attend tout près (GPS) : %s, essence %d %%." % [vehicle_name(data).to_lower(), int(v.fuel)])


## Arrestation : le véhicule sorti part à la fourrière
func impound() -> void:
	if out == null or not is_instance_valid(out) or _out_idx < 0:
		return
	var idx := _out_idx
	store()
	owned()[idx]["impound"] = true
	GameState.notify.emit("Ton véhicule (%s) part à la fourrière (récupération au commissariat : %s)." % [vehicle_name(owned()[idx]).to_lower(), GameState.fcfa(IMPOUND_FEE)])
	GameState.save_game()


func impounded() -> Array:
	var list: Array = []
	for i in owned().size():
		if owned()[i].get("impound", false):
			list.append(i)
	return list


func release(idx: int) -> void:
	if not GameState.spend(IMPOUND_FEE):
		GameState.notify.emit("La sortie de fourrière coûte %s." % GameState.fcfa(IMPOUND_FEE))
		return
	owned()[idx].erase("impound")
	GameState.save_game()
	GameState.notify.emit("« Signe ici. » Ton véhicule (%s) est sorti de la fourrière : fais-le venir avec l'appli Oto." % vehicle_name(owned()[idx]).to_lower())


## Ranger le véhicule sorti (il retourne au parking, l'essence est gardée)
func store() -> void:
	if out == null or not is_instance_valid(out):
		out = null
		return
	if main.player.current_vehicle == out:
		main.player.exit_vehicle()
	_sync_fuel()
	out.queue_free()
	out = null
	_out_idx = -1
	GameState.save_game()


func _sync_fuel() -> void:
	if out != null and is_instance_valid(out) and _out_idx >= 0 and _out_idx < owned().size():
		owned()[_out_idx]["fuel"] = snappedf(out.fuel, 0.1)
		owned()[_out_idx]["condition"] = snappedf(out.condition, 0.1)


func _process(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 2.0
		if out != null and not is_instance_valid(out):
			out = null
			_out_idx = -1
		_sync_fuel()


# --- Concession et stations : action du joueur -------------------------------------------

func _station_near(p: Vector3) -> bool:
	for s in stations:
		if Vector2(p.x - s.x, p.z - s.z).length() < STATION_RANGE:
			return true
	return false


func _refuel_cost(v) -> int:
	return int(ceil(100.0 - v.fuel)) * FUEL_PRICE


func get_hint() -> String:
	var p = main.player
	var v = p.current_vehicle
	if v != null:
		if v.fuel >= 0.0 and v.fuel < 99.0 and _station_near(v.global_position):
			return "Faire le plein (%s)" % GameState.fcfa(_refuel_cost(v))
		return ""
	if p.riding != null or pos == Vector3.ZERO or main.interiors.inside != "":
		return ""
	if Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < RANGE:
		return "Concession auto : acheter, revendre"
	return ""


func try_interact() -> bool:
	var h := get_hint()
	if h == "":
		return false
	if main.player.current_vehicle != null:
		_refuel(main.player.current_vehicle)
	else:
		_menu()
	return true


func _refuel(v) -> void:
	var need := int(ceil(100.0 - v.fuel))
	var cost := need * FUEL_PRICE
	if not GameState.spend(cost):
		# Pas assez pour le plein : on met ce qu'on peut payer
		need = GameState.money / FUEL_PRICE
		cost = need * FUEL_PRICE
		if need <= 0:
			GameState.notify.emit("Le pompiste : « Pas d'argent, pas d'essence, grand ! »")
			return
		GameState.money -= cost
	v.fuel = minf(100.0, v.fuel + need)
	_sync_fuel()
	GameState.notify.emit("Le pompiste te sert : réservoir à %d %% (-%s)." % [int(v.fuel), GameState.fcfa(cost)])
	Audio.play_sfx("coin", -12.0)


func _menu() -> void:
	var choices: Array = []
	for t in CATALOG:
		var type: String = t
		var c: Array = CATALOG[type]
		choices.append(["%s — %s%s" % [c[0], GameState.fcfa(c[1]), " (permis)" if c[2] else ""], func(): _offer(type)])
	for i in owned().size():
		var idx: int = i
		var data: Dictionary = owned()[i]
		if insured(data):
			choices.append(["Assuré : %s (jusqu'au jour %d)" % [vehicle_name(data), int(data["insured_until"])], func(): pass])
		else:
			choices.append(["Assurer : %s — %s pour %d jours" % [vehicle_name(data), GameState.fcfa(insurance_price(data)), INSURANCE_DAYS], func(): _insure(idx)])
		choices.append(["Revendre : %s (%s)" % [vehicle_name(data), GameState.fcfa(_resale(data))], func(): _confirm_sell(idx)])
	main.hud.show_choices("Concession auto — « Dalal ak jàmm ! » (%d/%d véhicules à toi)" % [owned().size(), MAX_OWNED], choices, func(): pass)


func insured(data: Dictionary) -> bool:
	return int(data.get("insured_until", -1)) >= GameState.day


func insurance_price(data: Dictionary) -> int:
	var c: Array = CATALOG.get(data.get("type", ""), ["", 500000])
	return int(c[1] * INSURANCE_RATE)


## Le véhicule sorti (celui que conduit le joueur) est-il assuré ?
func out_insured(v) -> bool:
	return v != null and v == out and _out_idx >= 0 and _out_idx < owned().size() and insured(owned()[_out_idx])


func _insure(idx: int) -> void:
	var data: Dictionary = owned()[idx]
	var price := insurance_price(data)
	if not GameState.spend(price):
		GameState.notify.emit("L'assurance coûte %s." % GameState.fcfa(price))
		return
	data["insured_until"] = GameState.day + INSURANCE_DAYS
	GameState.save_game()
	GameState.notify.emit("Ton véhicule (%s) est assuré jusqu'au jour %d : réparations gratuites au garage." % [vehicle_name(data).to_lower(), int(data["insured_until"])])


func _offer(type: String) -> void:
	var c: Array = CATALOG[type]
	var choices: Array = []
	for cn in COLORS:
		var col_name: String = cn
		choices.append(["%s — %s" % [col_name, GameState.fcfa(c[1])], func(): _buy(type, col_name)])
	main.hud.show_choices("%s : %s\nChoisis la couleur." % [c[0], c[3]], choices, func(): pass)


func _buy(type: String, col_name: String) -> void:
	var c: Array = CATALOG[type]
	if owned().size() >= MAX_OWNED:
		GameState.notify.emit("Tu as déjà %d véhicules : revends-en un d'abord." % MAX_OWNED)
		return
	if c[2] and GameState.inventory.get(Employment.PERMIS_ITEM, 0) <= 0:
		GameState.notify.emit("« Montre-moi ton permis ! » Il faut le permis de conduire (auto-école) pour acheter une voiture.")
		return
	var price: int = c[1]
	if GameState.money + GameState.bank < price:
		GameState.notify.emit("Il te faut %s (liquide + banque)." % GameState.fcfa(price))
		return
	var from_bank: int = maxi(0, price - GameState.money)
	GameState.money -= price - from_bank
	GameState.bank -= from_bank
	owned().append({"type": type, "color": COLORS[col_name].to_html(false), "fuel": 100.0})
	GameState.save_game()
	Audio.play_sfx("coin", -4.0)
	GameState.notify.emit("Félicitations ! %s %s est à toi, le plein est fait. Fais-le venir quand tu veux (téléphone → Oto)." % [c[0], col_name.to_lower()])
	bring(owned().size() - 1)


func _resale(data: Dictionary) -> int:
	var c: Array = CATALOG.get(data.get("type", ""), ["", 0])
	return int(snappedf(c[1] * RESALE, 1000.0))


func _confirm_sell(idx: int) -> void:
	var data: Dictionary = owned()[idx]
	main.hud.show_choices("Revendre %s pour %s ?" % [vehicle_name(data), GameState.fcfa(_resale(data))], [
		["Oui, revendre", func(): _sell(idx)], ["Non", func(): pass]], func(): pass)


func _sell(idx: int) -> void:
	if idx >= owned().size():
		return
	if idx == _out_idx:
		store()
	var data: Dictionary = owned()[idx]
	owned().remove_at(idx)
	if _out_idx > idx:
		_out_idx -= 1
	GameState.add_money(_resale(data), "Vente : %s" % vehicle_name(data))
	GameState.save_game()
