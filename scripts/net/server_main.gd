extends Node
## Scène du serveur dédié (lancé avec `-- --server`) : pas de ville ni de rendu, juste un journal.

var _t := 0.0


func _ready() -> void:
	print("Galsen-Life : serveur prêt. Ctrl+C pour arrêter.")


func _process(delta: float) -> void:
	_t += delta
	if _t >= 60.0:
		_t = 0.0
		var m := int(GameState.game_minutes)
		print("[%02d:%02d à Dakar] %d joueur(s) en ligne" % [m / 60, m % 60, Net._sessions.size()])
