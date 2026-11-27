extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST SYSTÈME DE MISSIONS ET QUÊTES DE DAKAR ---")

	var game_state = root.get_node_or_null("GameState")
	assert(game_state != null, "L'autoload GameState doit être disponible")

	# 1. Vérification du script MissionManager
	var MissionManagerScript = load("res://scripts/jobs/mission_manager.gd")
	assert(MissionManagerScript != null, "MissionManager script doit charger sans erreur")

	var mgr = MissionManagerScript.new()
	root.add_child(mgr)

	# 2. Vérification des 16 missions de Dakar (Solo Teranga et Multijoueur en ligne)
	assert(mgr.MISSIONS.size() >= 16, "Il doit y avoir au moins 16 missions scénarisées (actuel: %d)" % mgr.MISSIONS.size())
	
	var expected_missions := [
		"joj_convoy", "maiga_rush", "lamb_champion", "hopital_urgence",
		"jumbo_supply", "wave_cash", "port_rescue", "taxi_rally",
		"renaissance_odyssey", "mamelles_night_watch", "soumbedioune_taleb", "couture_bazin_royal",
		"online_teranga_rally", "online_police_patrol", "online_car_rapide_tour", "online_bank_heist_defense"
	]
	var solo_count := 0
	var online_count := 0
	for m_id in expected_missions:
		assert(mgr.MISSIONS.has(m_id), "Mission manquante : %s" % m_id)
		var m: Dictionary = mgr.MISSIONS[m_id]
		assert(m.title != "", "Titre requis pour %s" % m_id)
		assert(m.giver != "", "Donneur d'ordre requis pour %s" % m_id)
		assert(m.reward >= 10000, "Récompense doit être généreuse (>= 10000 FCFA) pour %s" % m_id)
		assert(m.steps.size() >= 3, "Chaque mission doit avoir au moins 3 étapes pour %s" % m_id)
		if m.get("mode", "all") == "online":
			online_count += 1
		else:
			solo_count += 1
		print("  [OK] Mission validée : %s %s [%s] (%s, %d étapes)" % [m["icon"], m["title"], m.get("mode", "all"), game_state.fcfa(m["reward"]), m["steps"].size()])

	assert(online_count >= 4, "Au moins 4 contrats multijoueur en ligne doivent être présents")
	assert(solo_count >= 8, "Au moins 8 missions solo & teranga doivent être présentes")
	print("[PASS] Toutes les 16 missions scénarisées (Solo & Multijoueur) sont parfaitement configurées !")

	# 3. Test du déroulement d'une mission en mode hors ligne (joj_convoy)
	var initial_money: int = game_state.money
	var initial_done: int = game_state.stats.get("missions_done", 0)

	var ok = mgr.start_mission("joj_convoy")
	assert(ok, "start_mission doit retourner true")
	assert(mgr.has_active_mission(), "has_active_mission doit être true")
	assert(mgr.active_id == "joj_convoy", "active_id doit être joj_convoy")
	assert(mgr.step_idx == 0, "Doit débuter à l'étape 0")
	assert(game_state.waypoint != null, "Le waypoint GPS doit être actif")

	# Simulation _process
	mgr._process(0.1)
	assert(mgr.objective != "", "L'objectif doit être affiché")
	assert("Convoi Officiel JOJ Dakar 2026" in mgr.objective, "L'objectif doit mentionner le titre de la mission")

	# Progression des étapes
	mgr.advance_step()
	assert(mgr.step_idx == 1, "Doit passer à l'étape 1")
	mgr.advance_step()
	assert(mgr.step_idx == 2, "Doit passer à l'étape 2")
	mgr.advance_step()
	assert(mgr.step_idx == 3, "Doit passer à l'étape 3")

	# Dernière étape -> Récompense et complétion
	mgr.advance_step()
	assert(not mgr.has_active_mission(), "La mission doit être terminée")
	assert(game_state.money == initial_money + 20000, "Le joueur doit avoir touché les 20 000 FCFA de prime")
	assert(game_state.stats.get("missions_done", 0) == initial_done + 1, "missions_done doit s'incrémenter")
	assert("joj_convoy" in game_state.missions.get("completed", []), "joj_convoy doit figurer dans les missions complétées")
	print("[PASS] Déroulement, progression d'étapes et récompense hors ligne validés avec succès !")

	# 4. Test des missions multijoueur en ligne et événements réseau
	var NetScript = load("res://scripts/net/net.gd")
	var net_node = root.get_node_or_null("Net")
	if net_node == null:
		net_node = NetScript.new()
		root.add_child(net_node)
	assert(net_node.has_method("send_mission_event"), "Net doit avoir send_mission_event")
	assert(net_node.has_method("rpc_mission_event"), "Net doit avoir rpc_mission_event")
	var ok_online = mgr.start_mission("online_teranga_rally")
	assert(ok_online, "start_mission online_teranga_rally doit réussir")
	assert(mgr.active_id == "online_teranga_rally", "Mission active en ligne")
	mgr.cancel_mission()
	assert(not mgr.has_active_mission(), "Mission annulée")
	print("[PASS] Événements et contrats multijoueur en ligne validés !")

	# 5. Test des points d'amorçage dans le monde ouvert (WORLD_MISSION_HUBS)
	assert(mgr.WORLD_MISSION_HUBS.size() >= 10, "Au moins 10 points de contact de missions dans Dakar")
	assert(mgr.WORLD_MISSION_HUBS.has("Place de l'Indépendance"), "Hub Place de l'Indépendance requis")
	assert(mgr.WORLD_MISSION_HUBS.has("Porte du Millénaire"), "Hub Porte du Millénaire requis")
	assert(mgr.WORLD_MISSION_HUBS.has("Marché Tilène"), "Hub Marché Tilène requis")
	print("[PASS] Points de contact et amorçage dans le monde ouvert de Dakar validés !")

	# 6. Test de l'application Missions dans le Téléphone
	var PhoneScript = load("res://scripts/ui/phone.gd")
	var phone = PhoneScript.new()
	root.add_child(phone)
	var has_mission_app := false
	for app in phone.APPS:
		if app[1] == "missions":
			has_mission_app = true
			break
	assert(has_mission_app, "L'application 'missions' doit figurer dans APPS du téléphone")
	assert(phone.get("_mission_filter") != null, "Filtre de missions présent dans phone")
	print("[PASS] Application 'Missions & Quêtes' avec filtres Solo/En Ligne intégrée au smartphone !")

	phone.queue_free()
	mgr.queue_free()

	print("--- TOUS LES TESTS DE MISSIONS SONT PASSÉS AVEC SUCCÈS ! ---")
	quit(0)
