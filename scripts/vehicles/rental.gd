extends Node3D
## Location de véhicules : deux agences (Place de l'Indépendance et Gare de Dakar).
## - On choisit un véhicule et une durée (heures de jeu) ; on paie la location plus une caution.
## - Le véhicule attend devant l'agence, le plein fait. On le rend à n'importe quelle agence (en arrivant
##   au volant, ou à pied s'il est garé tout près) : la caution est rendue, moins l'essence manquante,
##   les dégâts du moteur et le retard (tarif majoré).
## - Plus de LATE_STOLEN heures de retard : l'agence porte plainte pour vol (caution perdue, recherché
##   si on est au volant). Arrêté avec la location : l'agence la récupère et garde la moitié de la caution.
## - Une seule location à la fois ; elle est gardée dans la sauvegarde (GameState.rental).

const Mk = preload("res://scripts/util/mk.gd")
const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
const Employment = preload("res://scripts/jobs/employment.gd")

const AGENCIES := ["Place de l'Indépendance", "Gare de Dakar"]
const RANGE := 4.0
const RETURN_RANGE := 20.0 ## le véhicule doit être garé à moins de 20 m de l'agence
## type → [nom, prix par heure de jeu, caution, permis exigé]
const FLEET := {
	"jakarta": ["Maxi-Scooter T-MAX de Luxe", 1200, 30000, false],
	"grosse_moto": ["Superbike de Luxe V4", 2500, 60000, false],
	"clando": ["Berline VIP de Luxe", 3500, 100000, true],
	"suv": ["SUV de Luxe V8", 4500, 150000, true],
	"van": ["Van VIP Grand Confort", 3000, 120000, true],
}
## heures de jeu (1 h = 1 minute réelle) → remise (les longues locations coûtent moins cher à l'heure)
const DURATIONS := {6: 1.0, 12: 0.85, 48: 0.5}
const COLOR := Color("f8f9fa") ## flotte blanche perle nacrée de prestige
const LATE_RATE := 1.5 ## heure de retard facturée 1,5 fois
const LATE_STOLEN := 24.0
const FUEL_PRICE := 50 ## comme à la pompe (dealership.gd)

var main
var agencies: Array = [] ## [nom, position du comptoir, place de stationnement sur la route]
var car = null ## véhicule loué présent dans la ville
var _check_t := 0.0
var _late_warned := -1


func _ready() -> void:
	var city = main.city
	for place_name in AGENCIES:
		if not city.places.has(place_name):
			continue
		# Le comptoir est au bord de la route la plus proche du lieu (côté lieu), le véhicule garé devant
		var center: Vector3 = city.places[place_name]
		var node: int = city.nearest_node(center, "drive")
		var road: Vector3 = city.node_pos[node] if node >= 0 else center
		var to_place := Vector3(center.x - road.x, 0, center.z - road.z)
		var dir := to_place.normalized() if to_place.length() > 1.0 else Vector3.FORWARD
		var p: Vector3 = city.off_road(road + dir * minf(8.0, maxf(to_place.length(), 6.0)), dir, 1.3)
		p.y = center.y
		agencies.append([place_name, p, road])
		var h := Node3D.new()
		add_child(h)
		h.global_position = Vector3(p.x, 0.16, p.z)
		h.rotation.y = atan2(-dir.x, -dir.z)
		Mk.box(h, Vector3(2.2, 1.0, 0.7), Vector3(0, 0.5, 0.3), Color("1d3557"), true)
		Mk.box(h, Vector3(2.4, 0.06, 0.9), Vector3(0, 1.03, 0.3), Color("f1faee"))
		for sx in [-1, 1]:
			Mk.box(h, Vector3(0.08, 2.4, 0.08), Vector3(sx * 1.1, 1.2, -0.1), Color("adb5bd"))
		Mk.box(h, Vector3(2.6, 0.08, 1.4), Vector3(0, 2.4, 0.1), Color("e63946"))
		Mk.label(h, "LOCATION DE VÉHICULES DE LUXE\nMotos sportives, Berlines VIP & SUV", Vector3(0, 3.0, 0), Mk.SIGN_SIZE - 4, Color("ffd166"))
	if active():
		_spawn(_parking_pos(str(GameState.rental.get("agency", ""))), false)


# --- État ---------------------------------------------------------------------------------

func active() -> bool:
	return not GameState.rental.is_empty()


## Minutes de jeu écoulées depuis le début (un jour commence à 8 h)
static func now() -> float:
	return GameState.day * 1440.0 + fposmod(GameState.game_minutes - 480.0, 1440.0)


## Heures restantes (négatif : en retard)
func hours_left() -> float:
	return (float(GameState.rental.get("until", 0.0)) - now()) / 60.0


func price(type: String, hours: int) -> int:
	return int(snappedf(FLEET[type][1] * hours * DURATIONS[hours], 100.0))


func _agency_pos(place_name: String) -> Vector3:
	for a in agencies:
		if a[0] == place_name:
			return a[1]
	return agencies[0][1] if not agencies.is_empty() else Vector3.ZERO


func _parking_pos(place_name: String) -> Vector3:
	for a in agencies:
		if a[0] == place_name:
			return a[2]
	return agencies[0][2] if not agencies.is_empty() else Vector3.ZERO


func _near_agency(p: Vector3, r: float, parking := false) -> Variant:
	for a in agencies:
		var q: Vector3 = a[2] if parking else a[1]
		if Vector2(p.x - q.x, p.z - q.z).length() < r:
			return a
	return null


func _parked(v) -> bool:
	return _near_agency(v.global_position, RETURN_RANGE, true) != null or _near_agency(v.global_position, RETURN_RANGE) != null


func _car_ok() -> bool:
	return car != null and is_instance_valid(car)


# --- Action du joueur ---------------------------------------------------------------------

func get_hint() -> String:
	var p = main.player
	if p.riding != null or main.interiors.inside != "":
		return ""
	if p.current_vehicle != null:
		if active() and p.current_vehicle == car and _parked(car):
			return "Rendre la location"
		return ""
	if _near_agency(p.global_position, RANGE) != null:
		return "Location de véhicules"
	return ""


func try_interact() -> bool:
	if get_hint() == "":
		return false
	if main.player.current_vehicle != null:
		_give_back()
	else:
		_menu()
	return true


func _menu() -> void:
	var choices: Array = []
	if active():
		var r: Dictionary = GameState.rental
		var left := hours_left()
		var title := "Ta location : %s — %s" % [FLEET[r["type"]][0], ("encore %s" % _hours_text(left)) if left >= 0.0 else ("en retard de %s" % _hours_text(-left))]
		if _car_ok() and _parked(car):
			choices.append(["Rendre le véhicule (caution %s)" % GameState.fcfa(int(r["deposit"])), _give_back])
		elif _car_ok():
			choices.append(["Ramène le véhicule et gare-le devant l'agence pour le rendre", func(): pass])
		else:
			choices.append(["Déclarer le véhicule perdu (caution gardée)", _lost])
		for h in DURATIONS:
			var hours: int = h
			var cost := price(r["type"], hours)
			choices.append(["Prolonger de %d h — %s" % [hours, GameState.fcfa(cost)], func(): _extend(hours)])
		main.hud.show_choices(title, choices, func(): pass)
		return
	for t in FLEET:
		var type: String = t
		var f: Array = FLEET[type]
		choices.append(["%s — %s/h, caution %s%s" % [f[0], GameState.fcfa(f[1]), GameState.fcfa(f[2]), " (permis)" if f[3] else ""], func(): _offer(type)])
	main.hud.show_choices("Location de véhicules — « Bienvenue ! »\nLa caution est rendue au retour, moins l'essence, les dégâts et le retard.", choices, func(): pass)


func _offer(type: String) -> void:
	var f: Array = FLEET[type]
	var choices: Array = []
	for h in DURATIONS:
		var hours: int = h
		var cost := price(type, hours)
		choices.append(["%d h — %s + caution %s" % [hours, GameState.fcfa(cost), GameState.fcfa(f[2])], func(): rent(type, hours)])
	main.hud.show_choices("%s : pour combien de temps ?\n(heures de jeu : 1 h = 1 minute réelle environ)" % f[0], choices, func(): pass)


func rent(type: String, hours: int) -> bool:
	if active():
		GameState.notify.emit("Tu as déjà une location en cours.")
		return false
	var f: Array = FLEET[type]
	if f[3] and GameState.inventory.get(Employment.PERMIS_ITEM, 0) <= 0:
		GameState.notify.emit("« Votre permis, s'il vous plaît. » Il faut le permis de conduire (auto-école) pour louer une voiture.")
		return false
	var total: int = price(type, hours) + int(f[2])
	if not GameState.spend(total):
		GameState.notify.emit("Il te faut %s en liquide (location + caution)." % GameState.fcfa(total))
		return false
	var a = _near_agency(main.player.global_position, RANGE * 4.0)
	var place_name: String = a[0] if a != null else (agencies[0][0] if not agencies.is_empty() else "")
	GameState.rental = {"type": type, "until": now() + hours * 60.0, "deposit": int(f[2]), "rate": int(f[1]),
		"agency": place_name, "fuel": 100.0, "condition": 100.0}
	_late_warned = -1
	_spawn(_parking_pos(place_name), true)
	GameState.save_game()
	Audio.play_sfx("coin", -8.0)
	GameState.notify.emit("Voilà les clés ! %s louée pour %d h. Le plein est fait, elle t'attend devant l'agence." % [f[0], hours])
	return true


func _extend(hours: int) -> void:
	var cost := price(GameState.rental["type"], hours)
	if not GameState.spend(cost):
		GameState.notify.emit("La prolongation coûte %s." % GameState.fcfa(cost))
		return
	GameState.rental["until"] = maxf(float(GameState.rental["until"]), now()) + hours * 60.0
	_late_warned = -1
	GameState.save_game()
	GameState.notify.emit("Location prolongée : encore %s." % _hours_text(hours_left()))


func _spawn(at: Vector3, gps: bool) -> void:
	if at == Vector3.ZERO:
		return
	var r: Dictionary = GameState.rental
	var v = Vehicle.new()
	v.vehicle_type = r["type"]
	main.add_child(v)
	# Garé sur la route la plus proche de l'agence
	var city = main.city
	var a: int = city.nearest_node(at, "drive")
	var nb: PackedInt32Array = city.drive_neighbors(a) if a >= 0 else PackedInt32Array()
	if nb.is_empty():
		v.respawn_in_traffic(city, at, 4.0, 30.0)
	else:
		v.start_traffic(city, a, nb[0])
	v.ai_enabled = false
	v.route_active = false
	v.speed = 0.0
	v.fuel = float(r.get("fuel", 100.0))
	v.condition = float(r.get("condition", 100.0))
	v.set_meta("owned", true)
	v.set_meta("rental", true)
	v.repaint(COLOR)
	car = v
	if gps:
		GameState.waypoint = v.global_position


## Rendre le véhicule : la caution revient, moins les frais
func _give_back() -> void:
	if not active() or not _car_ok():
		return
	var r: Dictionary = GameState.rental
	var fees := {}
	var fuel_missing := int(ceil(100.0 - clampf(car.fuel, 0.0, 100.0)))
	if fuel_missing > 2:
		fees["essence"] = fuel_missing * FUEL_PRICE
	var damage: float = 100.0 - car.condition
	if damage > 5.0:
		fees["dégâts"] = int(snappedf(int(r["deposit"]) * damage / 100.0, 100.0))
	var late := -hours_left()
	if late > 0.25:
		fees["retard"] = int(ceil(late)) * int(int(r["rate"]) * LATE_RATE)
	var total := 0
	for k in fees:
		total += int(fees[k])
	var deposit: int = r["deposit"]
	if main.player.current_vehicle == car:
		main.player.exit_vehicle()
	car.queue_free()
	car = null
	GameState.rental = {}
	if total <= deposit:
		GameState.add_money(deposit - total, "Caution rendue" + _fees_text(fees))
	else:
		GameState.fine(total - deposit, "Frais de location au-delà de la caution" + _fees_text(fees))
	GameState.save_game()


func _fees_text(fees: Dictionary) -> String:
	if fees.is_empty():
		return " (véhicule rendu en parfait état, merci !)"
	var parts: Array = []
	for k in fees:
		parts.append("%s %s" % [k, GameState.fcfa(fees[k])])
	return " — retenues : " + ", ".join(parts)


func _lost() -> void:
	if _car_ok():
		car.queue_free()
	car = null
	GameState.rental = {}
	GameState.save_game()
	GameState.notify.emit("L'agence garde ta caution pour le véhicule perdu.")


## Arrêté par la police : l'agence récupère sa location et garde la moitié de la caution
func on_arrest() -> void:
	if not active():
		return
	var back: int = int(GameState.rental["deposit"]) / 2
	if _car_ok():
		if main.player.current_vehicle == car:
			main.player.exit_vehicle()
		car.queue_free()
	car = null
	GameState.rental = {}
	GameState.add_money(back, "L'agence a récupéré ta location à la fourrière : moitié de la caution rendue")
	GameState.save_game()


static func _hours_text(h: float) -> String:
	if h < 1.0:
		return "%d min" % maxi(1, int(h * 60.0))
	return "%d h %02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


# --- Suivi : essence gardée, rappels de retard, plainte pour vol -------------------------------

func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t > 0.0 or not active():
		return
	_check_t = 2.0
	if _car_ok():
		GameState.rental["fuel"] = snappedf(car.fuel, 0.1)
		GameState.rental["condition"] = snappedf(car.condition, 0.1)
	else:
		car = null
	var left := hours_left()
	if left < 0.5 and left >= 0.0 and _late_warned == -1:
		_late_warned = -2
		GameState.notify.emit("Location : il reste moins de 30 min. Rends le véhicule à une agence ou prolonge.")
	elif left < 0.0:
		var late_h := int(-left) / 3 * 3
		if late_h > _late_warned:
			_late_warned = late_h
			GameState.notify.emit("Location en retard de %s : chaque heure est facturée %s." % [_hours_text(-left), GameState.fcfa(int(int(GameState.rental["rate"]) * LATE_RATE))])
		if -left >= LATE_STOLEN:
			_stolen()


func _stolen() -> void:
	var driving: bool = _car_ok() and main.player.current_vehicle == car
	if _car_ok():
		car.remove_meta("rental")
		car.remove_meta("owned")
	car = null
	GameState.rental = {}
	GameState.save_game()
	if driving:
		GameState.add_wanted(2, "L'agence de location a porté plainte : le véhicule est déclaré volé !")
	else:
		GameState.notify.emit("L'agence de location a porté plainte pour vol : ta caution est perdue.")
