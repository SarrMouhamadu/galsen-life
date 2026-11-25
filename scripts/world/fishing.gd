extends Node3D
## Pêche à la Plage de l'Anse Bernard : on achète une canne chez la mareyeuse, on lance sa ligne
## sur la plage, on ferre quand ça mord (action au bon moment), puis on revend sa pêche à la mareyeuse.
## Le poisson est rangé dans le sac (limite du sac) ; chaque lancer fatigue un peu.

const Mk = preload("res://scripts/util/mk.gd")
const Items = preload("res://scripts/util/items.gd")

const PLACE := "Plage de l'Anse Bernard"
const ROD := "Canne à pêche"
const ROD_PRICE := 3500
const STALL_RANGE := 3.5
const SHORE_RANGE := 30.0 ## zone de pêche autour du bord de l'eau
const BITE_WINDOW := 2.2 ## secondes pour ferrer
const ENERGY_PER_CAST := 3.0
## [nom, prix de revente, chances]
const FISH := [
	["Yaboy (sardinelle)", 300, 40], ["Dorade", 800, 25], ["Capitaine", 1500, 14],
	["Poulpe", 1200, 9], ["Thiof", 2500, 10], ["Vieille sandale", 0, 2],
]

var main
var status := ""
var stall := Vector3.ZERO
var shore := Vector3.ZERO
var _state := "" ## "" | "attente" | "touche"
var _t := 0.0
var _rod: Node3D = null


func _ready() -> void:
	var city = main.city
	if not city.places.has(PLACE):
		return
	var info: Array = city.place_info[PLACE]
	var n := Vector3(info[3], 0, info[4])
	stall = city.places[PLACE] + n * 6.0
	# Le centre de la plage (vers la mer) ; à défaut, plus loin dans l'axe de la plage
	shore = Vector3(info[9], 0.3, info[10]) if info.size() > 10 else city.places[PLACE] + n * 50.0
	var h := Node3D.new()
	add_child(h)
	h.global_position = Vector3(stall.x, 0.07, stall.z)
	h.rotation.y = atan2(n.x, n.z)
	Mk.box(h, Vector3(2.6, 0.85, 1.2), Vector3(0, 0.43, 0), Color("8d6748"), true)
	Mk.box(h, Vector3(2.2, 0.12, 0.9), Vector3(0, 0.92, 0), Color("bfd7ea"))
	for sx in [-1, 1]:
		Mk.cyl(h, 0.05, 0.05, 2.3, Vector3(sx * 1.3, 1.15, 0), Color("444444"), false, 4)
	Mk.box(h, Vector3(3.0, 0.06, 1.8), Vector3(0, 2.3, 0), Color("2a9d8f"))
	Mk.label(h, "MAREYEUSE — Poisson frais\nCannes à pêche", Vector3(0, 2.9, 0), Mk.SIGN_SIZE - 4, Color("f1faee"))


func has_rod() -> bool:
	return int(GameState.inventory.get(ROD, 0)) > 0


func _on_foot() -> bool:
	var p = main.player
	return p.current_vehicle == null and p.riding == null and main.interiors.inside == ""


func _near(pos: Vector3, r: float) -> bool:
	var p: Vector3 = main.player.global_position
	return pos != Vector3.ZERO and Vector2(p.x - pos.x, p.z - pos.z).length() < r


func get_hint() -> String:
	if not _on_foot():
		return ""
	if _near(stall, STALL_RANGE):
		return "Mareyeuse : canne à pêche, vendre ta pêche"
	if _state == "touche":
		return "Ça mord ! Ferre !"
	if _state == "attente":
		return "Remonter la ligne"
	if has_rod() and _near(shore, SHORE_RANGE):
		return "Pêcher"
	return ""


func try_interact() -> bool:
	if get_hint() == "":
		return false
	if _near(stall, STALL_RANGE):
		_stall_menu()
	elif _state == "touche":
		_catch()
	elif _state == "attente":
		_stop("Tu remontes ta ligne.")
	else:
		_cast()
	return true


func _stall_menu() -> void:
	var choices: Array = []
	if not has_rod():
		choices.append(["Acheter une canne à pêche (%s)" % GameState.fcfa(ROD_PRICE), _buy_rod])
	var total := 0
	var count := 0
	for f in FISH:
		var c := int(GameState.inventory.get(f[0], 0))
		total += c * int(f[1])
		count += c
	if count > 0:
		choices.append(["Vendre ta pêche : %d prise(s) pour %s" % [count, GameState.fcfa(total)], _sell])
	var prices: Array = []
	for f in FISH:
		if f[1] > 0:
			prices.append("%s %s" % [f[0], GameState.fcfa(f[1])])
	choices.append(["« Reviens avec du thiof, je te le paie bien ! »", func(): pass])
	main.hud.show_choices("Mareyeuse de l'Anse Bernard\n" + ", ".join(prices), choices, func(): pass)


func _buy_rod() -> void:
	if not GameState.spend(ROD_PRICE):
		GameState.notify.emit("La canne coûte %s." % GameState.fcfa(ROD_PRICE))
		return
	GameState.add_item(ROD)
	GameState.save_game()
	GameState.notify.emit("Canne à pêche achetée ! Va au bord de l'eau, lance ta ligne et ferre quand ça mord.")


func _sell() -> void:
	var total := 0
	for f in FISH:
		var c := int(GameState.inventory.get(f[0], 0))
		if c > 0:
			total += c * int(f[1])
			GameState.inventory.erase(f[0])
	if total > 0:
		GameState.add_money(total, "Vente de ta pêche")
	else:
		GameState.notify.emit("La mareyeuse rit : « Garde tes sandales, je ne les achète pas ! »")
	GameState.save_game()


func _cast() -> void:
	if GameState.bag_count() >= Items.BAG_MAX:
		GameState.notify.emit("Ton sac est plein : vends ta pêche à la mareyeuse.")
		return
	if GameState.energy < ENERGY_PER_CAST:
		GameState.notify.emit("Tu es trop fatigué pour pêcher. Repose-toi.")
		return
	GameState.energy -= ENERGY_PER_CAST
	_state = "attente"
	_t = randf_range(5.0, 11.0)
	_show_rod(true)
	GameState.notify.emit("Tu lances ta ligne... Attends que ça morde.")


## Chances d'une prise : les beaux poissons (≥ 1 200 FCFA) deviennent plus fréquents avec le niveau
func _weight(f: Array) -> int:
	return int(f[2]) * (1 + GameState.skill_level("peche") / 3) if int(f[1]) >= 1200 else int(f[2])


func _catch() -> void:
	var total := 0
	for f in FISH:
		total += _weight(f)
	var r := randi() % total
	var fish: Array = FISH[0]
	for f in FISH:
		r -= _weight(f)
		if r < 0:
			fish = f
			break
	GameState.add_item(fish[0])
	GameState.add_skill("peche", 4.0)
	Audio.play_sfx("coin", -14.0)
	var extra := " Belle prise, ça vaut %s !" % GameState.fcfa(fish[1]) if fish[1] >= 1500 else ""
	_stop("Tu as pêché : %s.%s" % [fish[0], extra])


func _stop(text: String) -> void:
	_state = ""
	status = ""
	_show_rod(false)
	GameState.notify.emit(text)


func _show_rod(on: bool) -> void:
	if not on:
		if _rod != null and is_instance_valid(_rod):
			_rod.queue_free()
		_rod = null
		return
	if _rod != null and is_instance_valid(_rod):
		return
	_rod = Node3D.new()
	main.player.add_child(_rod)
	_rod.position = Vector3(0.3, 1.1, 0.2)
	_rod.rotation.x = deg_to_rad(55)
	Mk.cyl(_rod, 0.012, 0.025, 2.4, Vector3(0, 1.2, 0), Color("5c4033"), false, 5)


func _process(delta: float) -> void:
	if _state == "":
		return
	if not _on_foot() or not _near(shore, SHORE_RANGE + 5.0):
		_stop("Tu as rangé ta canne.")
		return
	_t -= delta
	if _state == "attente":
		status = "Ligne à l'eau... patience"
		if _t <= 0.0:
			_state = "touche"
			_t = BITE_WINDOW + 0.15 * GameState.skill_level("peche")
			Audio.play_sfx("coin", -20.0)
			GameState.notify.emit("Ça mord ! Ferre vite (action) !")
	elif _state == "touche":
		status = "ÇA MORD ! Appuie sur l'action !"
		if _t <= 0.0:
			_state = "attente"
			_t = randf_range(5.0, 11.0)
			GameState.notify.emit("Trop tard, le poisson s'est échappé avec l'appât. Ta ligne est toujours à l'eau.")
