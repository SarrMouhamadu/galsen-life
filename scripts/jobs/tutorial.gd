extends Node
## Premiers pas à Dakar : petite mission guidée pour les nouveaux joueurs (quelques minutes).
## Se faire embaucher au Café Touba, vendre trois tasses, toucher sa paie, manger un dibi, ouvrir le téléphone.
## Chaque étape pose le GPS et s'affiche en objectif ; prime à la fin. Progression dans GameState.tuto
## (sauvegardée) ; les parties qui existaient avant ce guide le sautent. On peut l'arrêter depuis la pause.

const REWARD := 2000
const CUPS := 3

var main
var objective := "" ## texte affiché en haut de l'écran (quand aucun travail n'en affiche)
var _step := -1
var _cups0 := 0
var _wait := 0.0


func _ready() -> void:
	# Laisse l'écran d'accueil se fermer avant le premier message
	_wait = 3.0


func active() -> bool:
	return not GameState.tuto.get("done", false)


func skip() -> void:
	GameState.tuto = {"done": true}
	objective = ""
	if main.gps.label in ["Café Touba", "Dibiterie"]:
		main.gps.clear()
	GameState.notify.emit("Guide des premiers pas arrêté. Bonne route à Dakar !")


func _process(delta: float) -> void:
	if not active():
		objective = ""
		return
	if _wait > 0.0:
		_wait -= delta
		return
	var step: int = GameState.tuto.get("step", 0)
	if step != _step:
		_enter(step)
	match step:
		0:
			objective = "PREMIERS PAS — Va voir Serigne Mbaye au Café Touba (suis le GPS) et fais-toi embaucher" + _far()
			if main.employment.is_hired("cafe"):
				_next()
		1:
			var sold: int = GameState.stats.get("cafes_vendus", 0) - _cups0
			objective = "PREMIERS PAS — Au stand, ouvre la vente de café Touba : %d / %d tasses vendues" % [mini(sold, CUPS), CUPS]
			if sold >= CUPS:
				_next()
		2:
			objective = "PREMIERS PAS — Ferme ton stand (ou parle à Serigne Mbaye) pour toucher ta paie"
			if main.employment.shift != "cafe":
				_next()
		3:
			objective = "PREMIERS PAS — Tu as faim ? Mange un dibi à la Dibiterie (suis le GPS)" + _far()
			if GameState.stats.get("dibis", 0) > GameState.tuto.get("dibis0", 0):
				_next()
		4:
			objective = "PREMIERS PAS — Ouvre ton téléphone (%s) : banque, GPS, messages, bonus…" % \
				("bouton téléphone" if GameState.touch_ui else "touche C ou bouton téléphone")
			if main.hud.phone.visible:
				_next()
		_:
			_finish()


## Loin à pied : on rappelle qu'on peut arrêter un taxi (passager) ou prendre le bus
func _far() -> String:
	if GameState.waypoint == null or main.player.current_vehicle != null:
		return ""
	var d: float = main.gps._dist()
	return "
%d m : c'est loin à pied, arrête un taxi ou prends le bus" % int(d) if d > 400.0 else ""


func _enter(step: int) -> void:
	_step = step
	match step:
		0:
			GameState.notify.emit("Nouveau à Dakar ? Suis le guide des premiers pas pour gagner tes premiers FCFA (tu peux l'arrêter dans le menu Pause).")
			main.gps.set_waypoint(main.city.places["Café Touba"], "Café Touba")
		1:
			_cups0 = GameState.stats.get("cafes_vendus", 0)
			if GameState.waypoint == null:
				main.gps.set_waypoint(main.city.places["Café Touba"], "Café Touba")
		3:
			GameState.tuto["dibis0"] = GameState.stats.get("dibis", 0)
			main.gps.set_waypoint(main.city.places["Dibiterie"], "Dibiterie")


func _next() -> void:
	GameState.tuto["step"] = GameState.tuto.get("step", 0) + 1
	if GameState.tuto["step"] == 1 and main.gps.label == "Café Touba":
		pass # le stand est au même endroit : le GPS reste
	elif main.gps.label in ["Café Touba", "Dibiterie"]:
		main.gps.clear()
	Audio.play_sfx("coin", -14.0)
	GameState.save_game()


func _finish() -> void:
	GameState.tuto = {"done": true}
	objective = ""
	GameState.add_money(REWARD, "Prime des premiers pas")
	GameState.notify.emit("Bravo, tu connais les bases ! Taxi, livraisons, lutte, foot, Orange Money… Dakar est à toi.")
	GameState.save_game()
