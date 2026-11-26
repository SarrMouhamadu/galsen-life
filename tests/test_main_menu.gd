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

	print("--- TEST MAIN MENU SUCCESS ---")
	quit(0)
