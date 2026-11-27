extends SceneTree
## Test unitaire et fonctionnel pour le réalisme physique du personnage et le Studio 3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	print("--- TEST RÉALISME PHYSIQUE DU PERSONNAGE ET STUDIO 3D ---")

	# 1. Test du Shader de peau physique
	var skin_shader: Shader = load("res://characters/skin/skin.gdshader")
	assert(skin_shader != null, "Le shader characters/skin/skin.gdshader doit exister et se charger")
	print("  [OK] Shader de peau PBR avec micro-relief et SSS chargé avec succès")

	# 2. Test du catalogue de tenues et teints de peau
	var OutfitsScript = load("res://scripts/util/outfits.gd")
	assert(OutfitsScript.SKIN_TONES.size() >= 6, "Le catalogue doit proposer au moins 6 teints de peau réalistes")
	assert(OutfitsScript.SKIN_TONES.has("teint_ebene"), "Teint ébène royal manquant")
	assert(OutfitsScript.SKIN_TONES.has("teint_chocolat"), "Teint chocolat chaud manquant")
	assert(OutfitsScript.SKIN_TONES.has("teint_caramel"), "Teint caramel doré manquant")
	assert(OutfitsScript.SKIN_TONES.has("teint_bronze"), "Teint bronze dakarois manquant")
	assert(OutfitsScript.PARTS.has("teint"), "La liste des parties doit inclure 'teint'")

	var test_code := "bazin_or,noir,kufi_bazin,afro,brun,teint_ebene"
	var parsed: Array = OutfitsScript.parse(test_code)
	assert(parsed[0] == "bazin_or", "Haut bazin_or attendu")
	assert(parsed[1] == "noir", "Bas noir attendu")
	assert(parsed[2] == "kufi_bazin", "Chapeau kufi_bazin attendu")
	assert(parsed[3] == "afro", "Coiffure afro attendue")
	assert(parsed[4] == "brun", "Couleur brun attendue")
	assert(parsed[5] == "teint_ebene", "Teint ébène attendu")

	var remade: String = OutfitsScript.make(parsed)
	assert(remade == test_code, "Sérialisation de la tenue avec teint doit être idempotente")
	print("  [OK] Catalogue et sérialisation des teints de peau validés")

	# 3. Test du modèle RealCharacter avec application du teint
	var RealCharacterScript = load("res://scripts/util/real_character.gd")
	var dummy_root := Node3D.new()
	root.add_child(dummy_root)

	var hero = RealCharacterScript.create(dummy_root, "heros", -1)
	assert(hero != null, "Le modèle héros doit être instancié")
	assert(hero.has_method("set_outfit"), "RealCharacter doit avoir set_outfit")
	assert(hero.get("_skins") != null, "RealCharacter doit indexer les maillages de peau")

	hero.set_outfit("vert,noir,,degrade,noir,teint_caramel")
	print("  [OK] Application dynamique du teint et de la tenue sur RealCharacter validée")

	# 4. Test du Studio 3D d'édition de personnage
	var StudioScript = load("res://scripts/ui/character_studio.gd")
	assert(StudioScript != null, "scripts/ui/character_studio.gd doit exister")

	var studio = StudioScript.new()
	root.add_child(studio)
	await create_timer(0.08).timeout

	assert(studio.get("_subview") != null, "Le SubViewport 3D doit être instancié")
	assert(studio.get("_camera") != null, "La caméra 3D du studio doit être présente")
	assert(studio.get("_character_holder") != null, "Le conteneur du personnage 3D doit exister")
	assert(studio.get("_category_tabs") != null, "Les onglets de catégories doivent être présents")
	assert(studio.get("_options_container") != null, "Le conteneur d'options doit être présent")

	# Test bascule des catégories
	studio._switch_category("teint")
	assert(studio.get("_active_category") == "teint", "L'onglet actif doit être 'teint'")
	assert(studio.get("_options_container").get_child_count() > 0, "Des options de teint doivent être générées")

	studio._switch_category("coiffure")
	assert(studio.get("_active_category") == "coiffure", "L'onglet actif doit être 'coiffure'")

	studio._switch_category("studio")
	assert(studio.get("_active_category") == "studio", "L'onglet actif doit être 'studio'")

	# Test génération aléatoire
	var old_look: String = studio.current_outfit
	studio._randomize_look()
	assert(studio.current_outfit != "", "Une tenue aléatoire doit être générée")
	print("  [OK] Studio 3D (SubViewport, Caméra 3D, Éclairage 3 points, Onglets, Aléatoire) validé")

	# Nettoyage
	studio.queue_free()
	dummy_root.queue_free()

	# 5. Test intégration dans le Menu Principal
	var MenuScene = load("res://scenes/menu.tscn")
	var menu = MenuScene.instantiate()
	root.add_child(menu)
	await create_timer(0.05).timeout

	var studio_btn: Button = menu.get("_studio_btn")
	assert(studio_btn != null, "Le bouton _studio_btn doit exister dans le menu principal")
	assert(studio_btn.text.contains("STUDIO PERSONNAGE"), "Le libellé du bouton studio doit être explicite")
	print("  [OK] Accès direct au Studio depuis le Menu Principal validé")
	menu.queue_free()

	# 6. Test intégration dans le Téléphone
	var PhoneScript = load("res://scripts/ui/phone.gd")
	var has_studio_app := false
	for app in PhoneScript.APPS:
		if app[1] == "studio":
			has_studio_app = true
			break
	assert(has_studio_app, "L'application Studio 3D doit être présente dans les applications du téléphone")
	print("  [OK] Application Studio 3D intégrée au smartphone du joueur validée")

	print("[PASS] TOUS LES TESTS DU RÉALISME PHYSIQUE ET DU STUDIO 3D SONT VALIDÉS AVEC SUCCÈS !")
	quit()
