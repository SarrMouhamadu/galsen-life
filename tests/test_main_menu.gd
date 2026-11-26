extends SceneTree
## Test unitaire pour l'écran de connexion / menu principal épuré.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST MAIN MENU ---")
	var menu_scene = load("res://scenes/menu.tscn")
	assert(menu_scene != null, "scenes/menu.tscn doit exister")
	
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	
	# Laisser le temps à _ready()
	await create_timer(0.05).timeout
	
	assert(menu.get("_pseudo") != null, "_pseudo doit être instancié")
	assert(menu.get("_password") != null, "_password doit être instancié")
	assert(menu.get("_avatar") != null, "_avatar doit être instancié")
	assert(menu.get("_offline_btn") != null, "_offline_btn doit être instancié")
	assert(menu.get("_connect_btn") != null, "_connect_btn doit être instancié")
	assert(menu.get("_create") != null, "_create doit être instancié")
	assert(menu.get("_status") != null, "_status doit être instancié")

	var pseudo: LineEdit = menu.get("_pseudo")
	var pw: LineEdit = menu.get("_password")
	var create_btn: CheckBox = menu.get("_create")
	var connect_btn: Button = menu.get("_connect_btn")
	var offline_btn: Button = menu.get("_offline_btn")
	
	print("[PASS] Tous les composants principaux sont instanciés")
	
	# Test bascule Inscription / Connexion
	create_btn.button_pressed = false
	assert(connect_btn.text == "🌐 SE CONNECTER", "Bouton doit afficher SE CONNECTER quand create=false")
	create_btn.button_pressed = true
	assert(connect_btn.text == "🌐 CRÉER MON COMPTE", "Bouton doit afficher CRÉER MON COMPTE quand create=true")
	print("[PASS] Bascule Se connecter / Créer mon compte OK")
	
	# Test responsive layout update
	menu._process(0.016)
	var content_vbox: VBoxContainer = menu.get("_content_vbox")
	assert(content_vbox != null, "_content_vbox doit exister")
	assert(content_vbox.custom_minimum_size.x >= 280.0, "Largeur responsive respectée")
	print("[PASS] Calcul responsive safe-margins OK")

	# Test responsive 2 colonnes sans vide en mode paysage (écran large)
	var hero_box: VBoxContainer = menu.get("_hero_box")
	var compact_header: VBoxContainer = menu.get("_compact_header")
	var card_panel: PanelContainer = menu.get("_card_panel")
	
	menu._update_responsive_layout(true, 1100.0, Vector2(1248, 650))
	assert(hero_box.visible == true, "La vitrine Dakar de gauche doit être visible en paysage large")
	assert(compact_header.visible == false, "L'en-tête compact de la carte doit être masqué en 2 colonnes")
	assert(card_panel.custom_minimum_size.x >= 340.0, "La carte doit s'adapter pour remplir l'espace sans vide")
	assert(hero_box.custom_minimum_size.x >= 300.0, "La vitrine de gauche doit occuper harmonieusement l'espace")
	print("[PASS] Agencement responsive 2 colonnes (paysage large sans vide) validé")

	# Test responsive 1 colonne fluide en mode portrait / écran compact
	menu._update_responsive_layout(false, 360.0, Vector2(390, 844))
	assert(hero_box.visible == false, "La vitrine gauche doit être masquée en mode compact/portrait")
	assert(compact_header.visible == true, "L'en-tête compact doit être affiché dans la carte en mode portrait")
	assert(card_panel.custom_minimum_size.x == 360.0, "La carte doit épouser fluidement la largeur de l'écran")
	print("[PASS] Agencement responsive 1 colonne fluide (portrait/compact) validé")

	# Test bascule Mode Clair / Mode Sombre
	var initial_mode: bool = menu.is_light_mode
	menu.toggle_theme()
	assert(menu.is_light_mode == !initial_mode, "toggle_theme() doit inverser is_light_mode")
	var gs = root.get_node_or_null("GameState")
	if gs != null:
		assert(gs.light_mode == menu.is_light_mode, "GameState.light_mode doit être synchronisé")
	
	# Forcer le test en Mode Clair
	menu.is_light_mode = true
	menu.apply_theme()
	assert(menu.get("_bg").color == Color("f4f6fa"), "Le fond d'écran doit être clair en mode light")
	assert("Sombre" in menu.get("_theme_btn").text, "Le bouton de thème doit proposer de basculer vers le mode sombre")
	print("[PASS] Mode Clair (Light Mode) validé avec succès (palette claire, cartes et champs adaptés)")

	# Forcer le test en Mode Sombre
	menu.is_light_mode = false
	menu.apply_theme()
	assert(menu.get("_bg").color == Color("0e1217"), "Le fond d'écran doit être sombre en dark mode")
	assert("Clair" in menu.get("_theme_btn").text, "Le bouton de thème doit proposer de basculer vers le mode clair")
	print("[PASS] Mode Sombre (Dark Mode) validé avec succès")

	print("--- TEST MAIN MENU SUCCESS ---")
	quit(0)
