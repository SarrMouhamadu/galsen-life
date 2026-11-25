extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST MODE HORS-LIGNE ---")
	var net = root.get_node_or_null("Net")
	assert(net != null, "Autoload Net non trouvé")
	net.start_offline("Moussa", "homme_afro")
	assert(net.online == false, "Net.online doit être false")
	assert(net.pseudo == "Moussa", "Net.pseudo doit être Moussa")
	assert(net.avatar == "homme_afro", "Net.avatar doit être homme_afro")
	print("OK: Net.start_offline validé (online=", net.online, ", pseudo=", net.pseudo, ", avatar=", net.avatar, ")")

	# Test instantiation of main scene in offline mode
	var gs = root.get_node("GameState")
	gs.save_path = "user://test_offline_save.json"
	gs.new_game()
	
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout

	assert(main.player != null, "Player doit être instancié")
	assert(main.city != null, "City doit être instanciée")
	print("OK: Scène Main instanciée avec succès en mode Hors-Ligne!")
	print("TOUS LES TESTS DU MODE HORS-LIGNE SONT PASSÉS AVEC SUCCÈS.")
	quit()
