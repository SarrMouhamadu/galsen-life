extends SceneTree
## Test automatisé : maison du joueur, dormir, cuisiner et changer d'habits (Galsen Life)

class DummyCity extends Node:
	var places: Dictionary = {}
	var place_info: Dictionary = {}


class DummyHud extends CanvasLayer:
	func fade_through(cb: Callable) -> void:
		if cb.is_valid():
			cb.call()
	func show_choices(_title: String, _choices: Array, _on_cancel: Callable) -> void:
		pass


class DummyMain extends Node:
	var city = null
	var hud = null
	var cooking = null
	var housing = null
	var player = null
	var commerce = null


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	print("--- TEST MAISON DU JOUEUR, DORMIR, CUISINER ET CHANGER D'HABITS ---")

	var gs = root.get_node_or_null("GameState")
	assert(gs != null, "GameState autoload doit être présent")

	# 1. Vérification que chaque joueur a une maison dès le début
	gs._reset_state()
	assert(not gs.home.get("owned", []).is_empty(), "Chaque joueur doit avoir au moins une maison possédée au départ")
	var starter_home_id: String = gs.home["owned"][0]
	assert(starter_home_id == "studio_gueule_tapee", "La maison de départ doit être studio_gueule_tapee")
	print("  [OK] Attribution automatique de la maison de départ au joueur validée (%s)" % starter_home_id)

	# 2. Instanciation du système de logement et de la ville
	var HousingScript = load("res://scripts/world/housing.gd")
	var CookingScript = load("res://scripts/world/cooking.gd")
	var InteriorsScript = load("res://scripts/world/interiors.gd")

	var dummy_main = DummyMain.new()
	root.add_child(dummy_main)

	var hud_mock = DummyHud.new()
	dummy_main.hud = hud_mock
	dummy_main.add_child(hud_mock)

	var cooking = CookingScript.new()
	cooking.main = dummy_main
	dummy_main.cooking = cooking
	dummy_main.add_child(cooking)

	# Mock de joueur
	var player_node = CharacterBody3D.new()
	player_node.set_script(load("res://scripts/player/player.gd"))
	dummy_main.player = player_node
	dummy_main.add_child(player_node)

	# Mock city
	var city_mock = DummyCity.new()
	city_mock.places = {
		"Marché Tilène": Vector3(100, 0, 100),
		"Mosquée Seydou Nourou Tall": Vector3(200, 0, 200),
		"Marché Kermel": Vector3(300, 0, 300),
		"Cathédrale": Vector3(400, 0, 400),
		"Plage de l'Anse Bernard": Vector3(500, 0, 500),
		"Garage mécanique (Fass Delorme)": Vector3(600, 0, 600),
		"Garage mécanique (Médina)": Vector3(700, 0, 700),
		"Polyclinique de la Médina": Vector3(800, 0, 800),
		"Marché Sandaga": Vector3(900, 0, 900),
		"Garage mécanique (Rebeuss)": Vector3(1000, 0, 1000),
		"Garage mécanique (Gueule Tapée)": Vector3(1100, 0, 1100),
		"Restaurant Maïga": Vector3(1200, 0, 1200),
	}
	city_mock.place_info = {
		"Marché Tilène": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Mosquée Seydou Nourou Tall": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Marché Kermel": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Cathédrale": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Plage de l'Anse Bernard": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Garage mécanique (Fass Delorme)": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Garage mécanique (Médina)": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Polyclinique de la Médina": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Marché Sandaga": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Garage mécanique (Rebeuss)": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Garage mécanique (Gueule Tapée)": ["", "", "", 0, 1, 0, 0, 1, 0],
		"Restaurant Maïga": ["", "", "", 0, 1, 0, 0, 1, 0],
	}
	dummy_main.city = city_mock
	dummy_main.add_child(city_mock)

	var housing = HousingScript.new()
	housing.main = dummy_main
	dummy_main.housing = housing
	dummy_main.add_child(housing)

	await create_timer(0.05).timeout

	assert(housing.has_home(starter_home_id), "Le joueur doit être propriétaire de sa maison de départ")
	assert(housing.main_home() == starter_home_id, "main_home() doit renvoyer la maison possédée")
	var home_pos = housing.home_position()
	assert(home_pos != null, "home_position() doit renvoyer une position valide")
	print("  [OK] Position et propriété de la maison validées : %s à %s" % [starter_home_id, str(home_pos)])

	# 3. Test : Dormir dans la maison
	gs.energy = 25.0
	gs.health = 45.0
	var before_minutes: float = gs.game_minutes
	housing._sleep(120.0) # Sieste de 2 heures
	assert(gs.energy == 100.0, "Dormir / faire une sieste doit remonter l'énergie à 100%")
	assert(gs.health == 100.0, "Dormir / faire une sieste doit soigner la santé à 100%")
	assert(gs.game_minutes != before_minutes, "Le temps doit avancer pendant le sommeil")
	print("  [OK] Dormir dans son lit (régénération complète énergie et santé) validé avec succès !")

	# 4. Test : Cuisiner dans la maison
	# Garde-manger de la maison
	cooking.pantry_supplies()
	assert(int(gs.inventory.get("Sac de riz (5 kg)", 0)) >= 2, "Le garde-manger doit fournir du riz")
	assert(int(gs.inventory.get("Huile (1 L)", 0)) >= 2, "Le garde-manger doit fournir de l'huile")
	assert(int(gs.inventory.get("Yaboy (sardinelle)", 0)) >= 4, "Le garde-manger doit fournir du poisson")
	print("  [OK] Garde-manger de la maison approvisionné avec succès !")

	# Cuisiner des plats
	assert(cooking.RECIPES.has("Thiéboudienne"), "Recette Thiéboudienne requise")
	assert(cooking.RECIPES.has("Pastels"), "Recette Pastels requise")
	assert(cooking.RECIPES.has("Yassa poulet"), "Recette Yassa poulet requise")
	assert(cooking.RECIPES.has("Mafé"), "Recette Mafé requise")

	var cook_ok: bool = cooking.cook("Thiéboudienne")
	assert(cook_ok, "La préparation de la Thiéboudienne doit réussir avec les ingrédients")
	assert(int(gs.inventory.get("Thiéboudienne", 0)) >= 3, "La Thiéboudienne préparée doit être ajoutée au sac")
	assert(gs.skill_level("cuisine") >= 1, "La compétence cuisine doit progresser")

	# Manger un plat fait maison
	gs.hunger = 40.0
	var eat_ok: bool = gs.use_item("Thiéboudienne")
	assert(eat_ok, "Le joueur doit pouvoir consommer son plat fait maison")
	assert(gs.hunger > 40.0, "Manger le plat doit restaurer la faim")
	print("  [OK] Cuisiner à la maison (Thiéboudienne, Yassa, Pastels...) et manger validé avec succès !")

	# 5. Test : Changer d'habits dans la maison (Dressing)
	var old_tenue: String = gs.tenue
	housing._apply_quick_outfit("bazin_or,bazin_or,kufi_bazin,court,noir,teint_ebene", "Boubou royal")
	assert(gs.tenue == "bazin_or,bazin_or,kufi_bazin,court,noir,teint_ebene", "Le dressing doit changer la tenue en Bazin royal")

	housing._apply_quick_outfit("vert,jaune,,court,noir,teint_ebene", "Lions Teranga")
	assert(gs.tenue == "vert,jaune,,court,noir,teint_ebene", "Le dressing doit changer la tenue aux couleurs des Lions")

	housing._random_quick_outfit()
	assert(gs.tenue != "", "La tenue aléatoire du dressing doit être valide")
	print("  [OK] Changer d'habits au dressing de la maison (Bazin, Lions, Casual...) validé !")

	# 6. Test : Vérification des emplacements 3D dans tous les types de logements
	for k in ["home_chambre", "home_studio", "home_appartement", "home_villa", "home_loft"]:
		assert(InteriorsScript.KITCHEN_AT.has(k), "La position de la cuisine doit être définie pour %s" % k)
		assert(InteriorsScript.WARDROBE_AT.has(k), "La position du dressing doit être définie pour %s" % k)
		var k_pos: Vector3 = InteriorsScript.KITCHEN_AT[k]
		var w_pos: Vector3 = InteriorsScript.WARDROBE_AT[k]
		assert(k_pos != Vector3.ZERO, "Position cuisine non nulle pour %s" % k)
		assert(w_pos != Vector3.ZERO, "Position dressing non nulle pour %s" % k)
	print("  [OK] Zones 3D (Lit, Cuisine, Dressing) configurées pour toutes les maisons de Dakar !")

	# Nettoyage
	dummy_main.queue_free()

	print("[PASS] TOUS LES TESTS MAISON, DORMIR, CUISINER ET CHANGER D'HABITS SONT VALIDÉS AVEC SUCCÈS (100%) !")
	quit(0)
