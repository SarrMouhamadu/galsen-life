extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST DE COMPATIBILITÉ MANETTE (CONTROLLER) ---")
	
	# 1. Vérification des actions InputMap pour la manette
	var actions := [
		"move_left", "move_right", "move_forward", "move_back",
		"interact", "jump", "sprint", "attack", "horn", "radio",
		"steal", "map", "phone", "chat", "voice", "camera_view", "pause",
		"ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"
	]
	for act in actions:
		assert(InputMap.has_action(act), "Action manquante dans InputMap : " + act)
		var events: Array = InputMap.action_get_events(act)
		assert(not events.is_empty(), "Aucun événement pour l'action : " + act)
	print("OK: Toutes les 23 actions InputMap sont configurées et actives.")
	
	# 2. Vérification des liaisons spécifiques aux boutons de manette
	var gs = root.get_node("GameState")
	assert(gs != null, "GameState autoload non trouvé")
	
	# Vérifier que l'attaque a bien été liée à la manette (bouton X / carré)
	var attack_events := InputMap.action_get_events("attack")
	var has_joy_attack := false
	for ev in attack_events:
		if ev is InputEventJoypadButton:
			has_joy_attack = true
			break
	assert(has_joy_attack, "attack doit avoir un bouton manette associé")
	print("OK: Bouton d'attaque/combat manette validé.")

	# Vérifier que le smartphone a le D-pad haut
	var phone_events := InputMap.action_get_events("phone")
	var has_joy_phone := false
	for ev in phone_events:
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_DPAD_UP:
			has_joy_phone = true
			break
	assert(has_joy_phone, "phone doit être assigné à JOY_BUTTON_DPAD_UP")
	print("OK: Raccourci manette Smartphone (D-Pad Haut) validé.")

	# Vérifier les actions UI (ui_accept / ui_cancel)
	var accept_events := InputMap.action_get_events("ui_accept")
	var has_joy_accept := false
	for ev in accept_events:
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A:
			has_joy_accept = true
			break
	assert(has_joy_accept, "ui_accept doit avoir JOY_BUTTON_A")

	var cancel_events := InputMap.action_get_events("ui_cancel")
	var has_joy_cancel := false
	for ev in cancel_events:
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_B:
			has_joy_cancel = true
			break
	assert(has_joy_cancel, "ui_cancel doit avoir JOY_BUTTON_B")
	print("OK: Navigation menus manette (A=Valider, B=Annuler) validée.")

	# 3. Test de vibration / retour haptique
	gs.rumble(0.5, 0.5, 0.1)
	print("OK: Appel retour haptique / rumble réussi sans erreur.")

	# 4. Test bascule dynamique Manette <-> Écran Tactile
	gs.gamepad_active = true
	assert(gs.gamepad_active == true, "gamepad_active doit être true")
	
	# Simuler un toucher d'écran pour vérifier la réactivation automatique du tactile
	var touch_ev = InputEventScreenTouch.new()
	touch_ev.pressed = true
	gs._input(touch_ev)
	assert(gs.gamepad_active == false, "Un toucher d'écran doit repasser en mode tactile")
	print("OK: Bascule dynamique Manette <-> Écran Tactile validée.")

	print("TOUS LES TESTS DE COMPATIBILITÉ MANETTE SONT PASSÉS AVEC SUCCÈS !")
	quit(0)
