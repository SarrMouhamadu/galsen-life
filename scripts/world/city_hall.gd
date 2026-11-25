extends Node3D
## Mairie de Dakar (guichet près de l'Assemblée nationale) et banque en ligne côté joueur.
## - Carte d'identité : délivrée au guichet (exigée pour voter et se présenter).
## - En ligne (scripts/net/net_city.gd) : élection du maire, vote (une voix par compte), candidature payante ;
##   le maire fixe la taxe sur la recette des commerces et touche un salaire pris dans la caisse de la ville.
## - Virements bancaires reçus (même pendant l'absence) et réponses du serveur aux virements envoyés.

const Mk = preload("res://scripts/util/mk.gd")

const PLACE := "Assemblée nationale"
const RANGE := 4.0
const ID_ITEM := "Carte d'identité"
const ID_PRICE := 2000
const CANDIDACY := 25000

var main
var pos := Vector3.ZERO


func _ready() -> void:
	Net.city.bank_received.connect(_on_bank_received)
	Net.city.bank_answer.connect(_on_bank_answer)
	var city = main.city
	if not city.places.has(PLACE):
		return
	var info: Array = city.place_info[PLACE]
	var n := Vector3(info[3], 0, info[4])
	var f := Vector3(info[7], 0, info[8]) if info.size() > 8 else Vector3(-n.z, 0, n.x)
	pos = city.places[PLACE] + f * 14.0 + n * 1.0
	var h := Node3D.new()
	add_child(h)
	h.global_position = Vector3(pos.x, 0.16, pos.z)
	var desk := Mk.box(h, Vector3(1.8, 1.1, 0.6), Vector3(0, 0.55, 0) + n * 0.4, Color("f1faee"))
	desk.rotation.y = atan2(n.x, n.z)
	Mk.box(h, Vector3(0.06, 2.6, 0.06), Vector3(0.9, 1.3, 0) + n * 0.4, Color("c9ccd1"))
	var flag := Mk.box(h, Vector3(0.9, 0.6, 0.03), Vector3(1.38, 2.3, 0) + n * 0.4, Color("00853f"))
	flag.rotation.y = atan2(n.x, n.z)
	Mk.label(h, "MAIRIE DE DAKAR\nÉtat civil — Élections", Vector3(0, 2.4, 0), Mk.SIGN_SIZE, Color("f1faee"))


static func has_id() -> bool:
	return int(GameState.inventory.get(ID_ITEM, 0)) > 0


func mayor() -> String:
	return str(Net.city.state.get("mayor", "")) if Net.online else ""


## Taxe (%) sur la recette des commerces (0 hors ligne)
func tax_rate() -> int:
	return int(Net.city.state.get("tax", 0)) if Net.online else 0


func get_hint() -> String:
	var p = main.player
	if p.current_vehicle != null or p.riding != null or pos == Vector3.ZERO or main.interiors.inside != "":
		return ""
	if Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < RANGE:
		return "Mairie de Dakar : état civil, élections"
	return ""


func try_interact() -> bool:
	if get_hint() == "":
		return false
	_menu()
	return true


func _menu() -> void:
	var choices: Array = []
	if not has_id():
		choices.append(["Faire sa carte d'identité (%s)" % GameState.fcfa(ID_PRICE), _make_id])
	var title := "Mairie de Dakar"
	if not Net.online:
		title += "\nLes élections du maire ont lieu en ligne."
		if choices.is_empty():
			choices.append(["« Tes papiers sont en règle. »", func(): pass])
		main.hud.show_choices(title, choices, func(): pass)
		return
	var st: Dictionary = Net.city.state
	var hours := maxi(0, int((float(st.get("end", 0.0)) - Time.get_unix_time_from_system()) / 3600.0))
	title += "\nMaire : %s — taxe des commerces : %d %% — caisse : %s\nFin du scrutin dans %d h" % [
		mayor() if mayor() != "" else "personne", tax_rate(), GameState.fcfa(int(st.get("treasury", 0))), hours]
	var cands: Dictionary = st.get("candidates", {})
	for c in cands:
		var who: String = c
		choices.append(["Voter pour %s (%d voix)" % [who, int(cands[who])], func(): _vote(who)])
	if not cands.has(Net.pseudo):
		choices.append(["Se présenter à l'élection (%s)" % GameState.fcfa(CANDIDACY), _run])
	if mayor() == Net.pseudo:
		for r in [0, 5, 10, 15, 20]:
			var rate: int = r
			choices.append(["Maire : fixer la taxe à %d %%" % rate, func(): Net.city.set_tax(rate)])
	main.hud.show_choices(title, choices, func(): pass)


func _make_id() -> void:
	if not GameState.spend(ID_PRICE):
		GameState.notify.emit("La carte coûte %s." % GameState.fcfa(ID_PRICE))
		return
	GameState.add_item(ID_ITEM)
	GameState.save_game()
	GameState.notify.emit("Photo, empreintes, signature : voici ta carte d'identité sénégalaise !")


func _vote(who: String) -> void:
	if not has_id():
		GameState.notify.emit("« Ta carte d'identité, s'il te plaît. » Fais-la d'abord au guichet.")
		return
	Net.city.vote(who)


func _run() -> void:
	if not has_id():
		GameState.notify.emit("Il faut une carte d'identité pour se présenter.")
		return
	if not GameState.spend(CANDIDACY):
		GameState.notify.emit("La caution de candidature est de %s." % GameState.fcfa(CANDIDACY))
		return
	Net.city.run_for_mayor()
	GameState.notify.emit("Candidature déposée ! Fais campagne : les joueurs votent à la mairie.")


# --- Banque en ligne ----------------------------------------------------------------------

## Virement de son compte en banque vers celui d'un joueur (même absent)
func bank_transfer(to: String, amount: int) -> void:
	to = to.strip_edges()
	if not Net.online:
		GameState.notify.emit("Les virements entre joueurs se font en ligne.")
	elif amount <= 0 or to == "":
		GameState.notify.emit("Entre le pseudo du joueur et un montant.")
	elif to == Net.pseudo:
		GameState.notify.emit("Tu ne peux pas te virer de l'argent à toi-même.")
	elif GameState.bank < amount:
		GameState.notify.emit("Solde du compte insuffisant (%s)." % GameState.fcfa(GameState.bank))
	else:
		GameState.bank -= amount
		GameState.bank_note("-%s : virement à %s" % [GameState.fcfa(amount), to])
		Net.city.bank_transfer(to, amount, "")


func _on_bank_answer(ok: bool, to: String, amount: int, message: String) -> void:
	if ok:
		GameState.notify.emit("Virement de %s envoyé à %s." % [GameState.fcfa(amount), to])
		Audio.play_sfx("coin", -10.0)
	else:
		GameState.bank += amount
		GameState.bank_note("+%s : virement à %s annulé" % [GameState.fcfa(amount), to])
		GameState.notify.emit("Virement refusé : %s Ton argent est revenu sur ton compte." % message)
	GameState.save_game()


func _on_bank_received(from: String, amount: int, note: String) -> void:
	GameState.bank += amount
	GameState.bank_note("+%s : virement de %s%s" % [GameState.fcfa(amount), from, (" (%s)" % note) if note != "" else ""])
	GameState.notify.emit("Banque : %s t'a viré %s sur ton compte." % [from, GameState.fcfa(amount)])
	Audio.play_sfx("coin", -10.0)
	GameState.save_game()
