extends Node
## Garde à vue : un joueur arrêté (par la police du jeu ou par un joueur policier) passe un moment en cellule
## au Commissariat, en plus de l'amende. La sortie est fermée tant que la peine n'est pas finie ;
## on peut payer une caution à l'accueil pour sortir plus tôt. La peine restante est sauvegardée
## (quitter le jeu ne la fait pas disparaître).

const PER_STAR := 40.0 ## secondes de cellule par étoile
const MAX_TIME := 200.0
const BAIL_PER_10S := 1500 ## caution : par tranche de 10 secondes restantes
const PLACE := "Commissariat"

var main
var status := ""
var _resume := false
var _wait := 0.0 ## entrée en cellule en cours (fondu au noir)


func _ready() -> void:
	# Partie quittée pendant une peine : on reprend en cellule
	_resume = GameState.jail > 0.0


func jailed() -> bool:
	return GameState.jail > 0.0


## Mise en cellule pour `stars` étoiles
func lock_up(stars: int) -> void:
	GameState.jail = minf(MAX_TIME, PER_STAR * maxi(stars, 1))
	_enter_cell()
	GameState.notify.emit("Garde à vue : %d secondes en cellule. Caution possible à l'accueil." % int(GameState.jail))


func _enter_cell() -> void:
	var city = main.city
	if not city.places.has(PLACE):
		GameState.jail = 0.0
		return
	var info: Array = city.place_info[PLACE]
	_wait = 2.0
	main.interiors.enter_custom("Cellule — Commissariat", "police", city.places[PLACE], Vector3(info[3], 0, info[4]))


func bail() -> int:
	return int(ceil(GameState.jail / 10.0)) * BAIL_PER_10S


func pay_bail() -> void:
	var cost := bail()
	if not GameState.spend(cost):
		GameState.notify.emit("La caution est de %s : tu n'as pas assez." % GameState.fcfa(cost))
		return
	GameState.jail = 0.0
	status = ""
	GameState.notify.emit("Caution payée (%s). « Tu es libre, la porte est ouverte. »" % GameState.fcfa(cost))


func _process(delta: float) -> void:
	if _resume and main.interiors != null:
		_resume = false
		_enter_cell()
		GameState.notify.emit("Ta garde à vue n'est pas finie : encore %d secondes." % int(GameState.jail))
	if GameState.jail <= 0.0:
		return
	# Sorti de la cellule par un autre moyen (téléportation) : on y retourne
	_wait -= delta
	if main.interiors.inside == "" and _wait <= 0.0:
		_enter_cell()
	GameState.jail = maxf(0.0, GameState.jail - delta)
	status = "EN CELLULE — encore %d s (caution : %s à l'accueil)" % [int(ceil(GameState.jail)), GameState.fcfa(bail())]
	if GameState.jail <= 0.0:
		status = ""
		GameState.notify.emit("Ta garde à vue est finie. Tu peux sortir : « Que je ne te revoie plus ! »")
		GameState.save_game()
