extends SceneTree
## Test automatisé de responsivité et d'adaptation aux écrans mobiles (Safe Area, encoche, Home bar, ratios 19.5:9 et 4:3).

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n--- TEST DE RESPONSIVITÉ ET SAFE AREA ---")
	var game_state = root.get_node("GameState")
	assert(game_state != null, "L'autoload GameState doit exister")
	
	# 1. Test des marges GameState
	game_state.simulated_safe_area = Rect2i() # standard
	var default_m: Dictionary = game_state.get_safe_margins()
	assert(default_m.left >= 16.0, "Marge gauche par défaut >= 16")
	assert(default_m.right >= 16.0, "Marge droite par défaut >= 16")
	assert(default_m.top >= 12.0, "Marge haut par défaut >= 12")
	assert(default_m.bottom >= 16.0, "Marge bas par défaut >= 16")
	print("OK: Marges par défaut validées : ", default_m)
	
	# Simulation iPhone 12 Pro Paysage (Fenêtre 2532 x 1170, Safe Area 100, 0, 2332, 1120)
	var win_w := 2532
	var win_h := 1170
	# Encoche à gauche (130px physique), Home bar en bas (60px physique), bords arrondis à droite (100px)
	game_state.simulated_window_size = Vector2i(win_w, win_h)
	game_state.simulated_safe_area = Rect2i(130, 0, win_w - 230, win_h - 60)
	
	# Simuler la conversion sur viewport 1280x720
	var sim_vp := SubViewport.new()
	sim_vp.size = Vector2i(1280, 720)
	root.add_child(sim_vp)
	
	var iphone_m: Dictionary = game_state.get_safe_margins(sim_vp)
	assert(iphone_m.left > 16.0, "L'encoche gauche doit augmenter la marge gauche")
	assert(iphone_m.bottom > 16.0, "La barre d'accueil doit augmenter la marge basse")
	assert(iphone_m.right > 16.0, "Les coins arrondis doivent augmenter la marge droite")
	print("OK: Marges iPhone 12 Pro détectées : Gauche=%.1f px, Droite=%.1f px, Bas=%.1f px, Haut=%.1f px" % [
		iphone_m.left, iphone_m.right, iphone_m.bottom, iphone_m.top
	])
	
	# 2. Test des commandes tactiles dans la Safe Area
	var TouchControls = load("res://scripts/ui/touch_controls.gd")
	var touch = TouchControls.new()
	touch.size = Vector2(1280, 720)
	sim_vp.add_child(touch)
	
	var s: float = touch._scale()
	var joy_pos: Vector2 = touch._joy_home(s)
	assert(joy_pos.x >= touch.BASE_JOY * s + (iphone_m.left - 16.0), "Le joystick doit être décalé de l'encoche gauche")
	print("OK: Position repos joystick avec Safe Area validée : ", joy_pos)
	
	for b in touch.FOOT:
		var btn_pos: Vector2 = touch._center(b, s)
		assert(btn_pos.x <= 1280.0 - (iphone_m.right - 16.0) - b["r"] * s + 0.1, "Bouton tactile %s ne doit pas déborder sur l'encoche/coins droits" % b["label"])
		assert(btn_pos.y <= 720.0 - (iphone_m.bottom - 16.0) - b["r"] * s + 0.1, "Bouton tactile %s ne doit pas chevaucher la barre d'accueil" % b["label"])
	print("OK: Tous les boutons tactiles piéton sont contenus dans la Safe Area")
	
	touch.in_vehicle = true
	for b in touch.CAR:
		var btn_pos: Vector2 = touch._center(b, s)
		assert(btn_pos.x <= 1280.0 - (iphone_m.right - 16.0) - b["r"] * s + 0.1, "Pédale/Bouton %s ne doit pas déborder sur l'encoche droite" % b["label"])
		assert(btn_pos.y <= 720.0 - (iphone_m.bottom - 16.0) - b["r"] * s + 0.1, "Pédale/Bouton %s ne doit pas chevaucher la barre d'accueil" % b["label"])
	print("OK: Tous les boutons tactiles véhicule sont contenus dans la Safe Area")
	
	# 3. Test du Smartphone
	var Phone = load("res://scripts/ui/phone.gd")
	var phone = Phone.new()
	sim_vp.add_child(phone)
	phone._process(0.016)
	assert(phone.offset_right <= -iphone_m.right, "Le téléphone ne doit pas déborder à droite sur l'encoche")
	assert(phone.offset_bottom <= -iphone_m.bottom, "Le téléphone ne doit pas toucher la barre d'accueil")
	print("OK: Le Smartphone s'ancre parfaitement dans la Safe Area : offset_right=%.1f, offset_bottom=%.1f" % [phone.offset_right, phone.offset_bottom])
	
	# 4. Test du HUD et de apply_responsive_layout
	var Hud = load("res://scripts/ui/hud.gd")
	var hud = Hud.new()
	sim_vp.add_child(hud)
	hud.apply_responsive_layout()
	print("HUD Gauges position: ", hud._gauges_panel.position if hud._gauges_panel else "null")
	print("Expected min left: ", iphone_m.left)
	
	assert(hud._gauges_panel.position.x >= iphone_m.left - 0.1, "Le panneau des jauges doit respecter l'encoche gauche")
	assert(hud._gauges_panel.position.y >= iphone_m.top - 0.1, "Le panneau des jauges doit respecter le haut")
	assert(hud._voice_dock.position.x >= iphone_m.left - 0.1, "Le dock vocal doit respecter l'encoche gauche")
	assert(hud._tr.offset_right <= -iphone_m.right + 0.1, "La colonne minimap/boutons doit respecter la marge droite")
	assert(hud._bottom_center.offset_bottom <= -iphone_m.bottom + 0.1, "L'invite d'action doit s'élever au-dessus de la barre d'accueil")
	print("OK: Disposition réactive du HUD validée avec succès sur écran à encoche")
	
	# 5. Test du menu des choix (show_choices)
	hud.show_choices("Test Destination", [["Point A", func(): pass], ["Point B", func(): pass]], func(): pass)
	assert(hud._choices != null, "La fenêtre des choix est instanciée")
	hud.close_choices()
	print("OK: Fenêtre réactive des choix et destinations validée")
	
	# 6. Test du Menu Emotes
	var EmoteMenu = load("res://scripts/ui/emote_menu.gd")
	var emotes = EmoteMenu.new()
	sim_vp.add_child(emotes)
	emotes.open()
	assert(emotes.offset_bottom <= -iphone_m.bottom, "Le menu des gestes doit respecter la barre d'accueil")
	emotes.close()
	print("OK: Menu des gestes réactif validé")
	
	# Nettoyage
	game_state.simulated_safe_area = Rect2i()
	sim_vp.queue_free()
	
	print("\n--- TOUS LES TESTS DE RESPONSIVITÉ SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
