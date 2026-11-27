extends Control
## Studio de Personnalisation 3D pour chaque Personnage Principal (Galsen Life)
## Chaque protagoniste dakarois possède son propre studio thématique immersif :
## - Studio Urbain Corniche (Modou Fall - Héros)
## - Studio Arène Nationale & Cercle de Sable (Balla Ndiaye - Lutteur Lamb)
## - Studio Stade Abdoulaye Wade (Sadio Diatta - Footballeur Lions)
## - Studio Haute Couture & Bazin Royal (Fatou Kiné Diop - Linguère & Styliste)
## - Studio Patio Médina & Mosquée (El Hadj Ousmane Sy - Doyen)
## - Studio Tactique Forces Armées (Cpt Moussa Traoré - Soldat)
## - Studio Loft Tech Almadies (Ibrahima Cissé - Entrepreneur)
## - Studio Olympique Dakar 2026 (Aïssatou Sow - Lionne)
## - Studio Keur Gui Teranga (Mame Diarra - Matriarche)

const Outfits = preload("res://scripts/util/outfits.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

signal closed(saved: bool)

# Catalogue des Personnages Principaux et de leurs Studios dédiés
const MAIN_CHARACTERS := [
	{
		"id": "heros",
		"name": "Modou Fall",
		"nickname": "Gaïndé du Plateau",
		"title": "Le Héros Dakarois",
		"icon": "🦁",
		"avatar": "heros",
		"district": "Dakar-Plateau",
		"bio": "Jeune débrouillard au grand cœur des ruelles du Plateau. Courageux, vif d'esprit et toujours prêt à aider ses voisins dans les grands défis de Dakar.",
		"quote": "« Dakar ne dort jamais, et la Teranga nous guide ! »",
		"role": "Citoyen & Aventure urbaine",
		"stats": {"Force": 65, "Vitesse": 80, "Endurance": 78, "Charisme": 85, "Style": 82},
		"pose": "idle",
		"default_outfit": ",,,degrade,noir,teint_ebene",
		"studio": {
			"name": "Studio Urbain Corniche & Coucher de Soleil",
			"bg_color": Color("0d1117"),
			"env_color": Color("10141c"),
			"ambient_color": Color("3a404d"),
			"key_color": Color("fff3e0"),
			"key_energy": 1.45,
			"key_rot": Vector3(-25, 40, 0),
			"fill_color": Color("9ec5e8"),
			"fill_energy": 0.55,
			"rim_color": Color("ffd166"),
			"rim_energy": 2.2,
			"pedestal_color": Color("1e232d"),
			"pedestal_accent": Color("ffd166"),
			"pedestal_label": "DAKAR-PLATEAU • CORNICHE EST"
		}
	},
	{
		"id": "lutteur",
		"name": "Balla « Bombardier » Ndiaye",
		"nickname": "Tigre de Pikine",
		"title": "Le Champion des Arènes (Lamb)",
		"icon": "🤼",
		"avatar": "lutteur1",
		"district": "Pikine & Guédiawaye",
		"bio": "Champion incontesté des arènes de lutte sénégalaise avec frappe. Mastodonte respecté de tous, il maîtrise les secrets mystiques des gris-gris et l'art du bakk.",
		"quote": "« Si l'arène tremble, c'est que le Roi entre dans le cercle de sable ! »",
		"role": "Lutteur professionnel & Colosse",
		"stats": {"Force": 98, "Vitesse": 58, "Endurance": 92, "Charisme": 90, "Style": 75},
		"pose": "arms_crossed",
		"default_outfit": ",,,,noir,teint_ebene",
		"studio": {
			"name": "Studio Arène Nationale & Cercle de Sable",
			"bg_color": Color("1a0e05"),
			"env_color": Color("160c04"),
			"ambient_color": Color("4d2e18"),
			"key_color": Color("ffaa5e"),
			"key_energy": 1.7,
			"key_rot": Vector3(-35, 30, 0),
			"fill_color": Color("e76f51"),
			"fill_energy": 0.7,
			"rim_color": Color("ffb703"),
			"rim_energy": 2.8,
			"pedestal_color": Color("5c2c10"),
			"pedestal_accent": Color("ffb703"),
			"pedestal_label": "ARÈNE NATIONALE • CERCLE DES CHAMPIONS"
		}
	},
	{
		"id": "footballeur",
		"name": "Sadio Diatta",
		"nickname": "La Flèche des Lions",
		"title": "L'Étoile des Lions de la Teranga",
		"icon": "⚽",
		"avatar": "footballeur1",
		"district": "Diamniadio / Stade Me Wade",
		"bio": "Attaquant prodige de la sélection nationale du Sénégal. Sa vitesse explosive, ses dribbles déroutants et sa générosité font vibrer tout le peuple sénégalais.",
		"quote": "« Pour le maillot, pour le Sénégal, on donne tout jusqu'à la 90e minute ! »",
		"role": "Footballeur professionnel des Lions",
		"stats": {"Force": 70, "Vitesse": 96, "Endurance": 94, "Charisme": 92, "Style": 86},
		"pose": "dance",
		"default_outfit": "vert,jaune,,court,noir,teint_chocolat",
		"studio": {
			"name": "Studio Stade Abdoulaye Wade (Pelouse des Lions)",
			"bg_color": Color("04150c"),
			"env_color": Color("041a0e"),
			"ambient_color": Color("143d22"),
			"key_color": Color("e8fff0"),
			"key_energy": 1.6,
			"key_rot": Vector3(-30, 50, 0),
			"fill_color": Color("00a86b"),
			"fill_energy": 0.65,
			"rim_color": Color("00ff88"),
			"rim_energy": 2.4,
			"pedestal_color": Color("196f3d"),
			"pedestal_accent": Color("2ecc71"),
			"pedestal_label": "STADE ME ABDOULAYE WADE • 50 000 PLACES"
		}
	},
	{
		"id": "linguere",
		"name": "Fatou Kiné Diop",
		"nickname": "La Reine de la Soie",
		"title": "La Linguère & Styliste de Dakar",
		"icon": "👑",
		"avatar": "femme_robe",
		"district": "Corniche Ouest & Fann Résidence",
		"bio": "Créatrice de mode d'avant-garde et femme d'affaires influente. Elle sublime le Bazin riche et les tissus traditionnels sur les podiums internationaux.",
		"quote": "« L'élégance dakaroise est un art séculaire, une fierté que l'on porte haut. »",
		"role": "Haute Couture & Entrepreneuriat",
		"stats": {"Force": 50, "Vitesse": 72, "Endurance": 76, "Charisme": 97, "Style": 99},
		"pose": "wave",
		"default_outfit": "bazin_or,bazin_or,,tresses,noir,teint_caramel",
		"studio": {
			"name": "Studio Haute Couture & Bazin Royal (Fann)",
			"bg_color": Color("1a0d18"),
			"env_color": Color("150b14"),
			"ambient_color": Color("4a223f"),
			"key_color": Color("fff0f5"),
			"key_energy": 1.5,
			"key_rot": Vector3(-20, 25, 0),
			"fill_color": Color("d4af37"),
			"fill_energy": 0.75,
			"rim_color": Color("ffd700"),
			"rim_energy": 2.5,
			"pedestal_color": Color("3b1834"),
			"pedestal_accent": Color("ffd700"),
			"pedestal_label": "SALON DE HAUTE COUTURE • BAZIN IMPÉRIAL"
		}
	},
	{
		"id": "doyen",
		"name": "El Hadj Ousmane Sy",
		"nickname": "Le Sage du Minaret",
		"title": "Le Doyen de la Médina",
		"icon": "🕌",
		"avatar": "homme_age",
		"district": "Médina / Grande Mosquée",
		"bio": "Notable respecté de la Grande Mosquée de Dakar. Sage écouteur, médiateur des conflits et mémoire vivante des traditions de la presqu'île du Cap-Vert.",
		"quote": "« La patience et la Teranga sont les fondations indestructibles de notre communauté. »",
		"role": "Notable & Guide spirituel",
		"stats": {"Force": 45, "Vitesse": 50, "Endurance": 70, "Charisme": 98, "Style": 90},
		"pose": "dua",
		"default_outfit": "blanc,blanc,kufi_bazin,court,gris,teint_ebene",
		"studio": {
			"name": "Studio Patio Traditionnel de la Médina",
			"bg_color": Color("101614"),
			"env_color": Color("0b120f"),
			"ambient_color": Color("24362d"),
			"key_color": Color("fffae8"),
			"key_energy": 1.4,
			"key_rot": Vector3(-25, 35, 0),
			"fill_color": Color("52b788"),
			"fill_energy": 0.5,
			"rim_color": Color("d8f3dc"),
			"rim_energy": 2.0,
			"pedestal_color": Color("2d4a3e"),
			"pedestal_accent": Color("74c69d"),
			"pedestal_label": "MÉDINA DE DAKAR • PATIO DES SAGES 1914"
		}
	},
	{
		"id": "soldat",
		"name": "Capitaine Moussa Traoré",
		"nickname": "Le Bouclier",
		"title": "Le Protecteur Républicain",
		"icon": "🛡️",
		"avatar": "soldat",
		"district": "Camp Bel-Air / État-Major",
		"bio": "Officier des forces spéciales sénégalaises. Discipliné, courageux et incorruptible, il veille sur la sécurité des institutions et des citoyens de la capitale.",
		"quote": "« On nous tue, on ne nous déshonore pas. Honneur et Patrie ! »",
		"role": "Forces de Défense et Sécurité",
		"stats": {"Force": 88, "Vitesse": 75, "Endurance": 90, "Charisme": 84, "Style": 78},
		"pose": "arms_crossed",
		"default_outfit": ",,,,noir,teint_bronze",
		"studio": {
			"name": "Studio Tactique Défense & Sécurité",
			"bg_color": Color("0a0f14"),
			"env_color": Color("070b0e"),
			"ambient_color": Color("1a2632"),
			"key_color": Color("dcebf7"),
			"key_energy": 1.6,
			"key_rot": Vector3(-30, 45, 0),
			"fill_color": Color("2b4c6f"),
			"fill_energy": 0.6,
			"rim_color": Color("38bdf8"),
			"rim_energy": 2.6,
			"pedestal_color": Color("1e2c3a"),
			"pedestal_accent": Color("38bdf8"),
			"pedestal_label": "FORCES ARMÉES DU SÉNÉGAL • BASE ÉLITE"
		}
	},
	{
		"id": "entrepreneur",
		"name": "Ibrahima Cissé",
		"nickname": "Le Tech-Maker",
		"title": "L'Entrepreneur des Almadies",
		"icon": "💼",
		"avatar": "homme_ville",
		"district": "Les Almadies & Ngor",
		"bio": "Fondateur de startups et créateur d'innovations financières. Dynamique, élégant et connecté aux grandes opportunités économiques de l'Afrique de l'Ouest.",
		"quote": "« Dakar est le hub d'innovation de demain : créativité, ambition et action ! »",
		"role": "Business, Tech & Création",
		"stats": {"Force": 55, "Vitesse": 74, "Endurance": 80, "Charisme": 89, "Style": 94},
		"pose": "talk",
		"default_outfit": "bleu,gris,,degrade,noir,teint_cafe",
		"studio": {
			"name": "Studio Loft Tech & Business (Almadies)",
			"bg_color": Color("0f141c"),
			"env_color": Color("0b0f16"),
			"ambient_color": Color("243042"),
			"key_color": Color("ffffff"),
			"key_energy": 1.45,
			"key_rot": Vector3(-20, 30, 0),
			"fill_color": Color("0ea5e9"),
			"fill_energy": 0.55,
			"rim_color": Color("f59e0b"),
			"rim_energy": 2.2,
			"pedestal_color": Color("1a2230"),
			"pedestal_accent": Color("0ea5e9"),
			"pedestal_label": "ALMADIES BUSINESS LOUNGE • DAKAR TECH"
		}
	},
	{
		"id": "lionne",
		"name": "Aïssatou Sow",
		"nickname": "La Capitaine",
		"title": "La Lionne du Sénégal",
		"icon": "⚡",
		"avatar": "footballeuse",
		"district": "Stade Iba Mar Diop / Médina",
		"bio": "Capitaine emblématique de l'équipe nationale féminine. Modèle d'inspiration pour toute la jeunesse, sa détermination et sa rage de vaincre forcent le respect.",
		"quote": "« Le courage n'a pas de genre, la victoire appartient à ceux qui osent ! »",
		"role": "Athlète olympique & Capitaine",
		"stats": {"Force": 72, "Vitesse": 92, "Endurance": 91, "Charisme": 93, "Style": 88},
		"pose": "dance",
		"default_outfit": "vert,jaune,,tresse_haute,noir,teint_ebene",
		"studio": {
			"name": "Studio Athlète Olympique Dakar 2026",
			"bg_color": Color("081318"),
			"env_color": Color("060f14"),
			"ambient_color": Color("15323d"),
			"key_color": Color("e0f7fa"),
			"key_energy": 1.55,
			"key_rot": Vector3(-25, 45, 0),
			"fill_color": Color("00acc1"),
			"fill_energy": 0.6,
			"rim_color": Color("26c6da"),
			"rim_energy": 2.5,
			"pedestal_color": Color("113540"),
			"pedestal_accent": Color("26c6da"),
			"pedestal_label": "JOJ DAKAR 2026 • COMPLEXE OLYMPIQUE"
		}
	},
	{
		"id": "matriarche",
		"name": "Mame Diarra",
		"nickname": "La Gardienne du Foyer",
		"title": "La Matriarche de la Teranga",
		"icon": "👵🏾",
		"avatar": "femme_maman",
		"district": "Grand Dakar & Colobane",
		"bio": "Mère de famille bienveillante et pilier de la communauté. Sa maison est toujours ouverte, le bol de thiéboudienne toujours prêt pour quiconque passe le seuil.",
		"quote": "« Que chaque visiteur trouve la paix et la bénédiction sous notre toit. »",
		"role": "Piliers de la famille & Teranga",
		"stats": {"Force": 52, "Vitesse": 52, "Endurance": 85, "Charisme": 99, "Style": 91},
		"pose": "wave",
		"default_outfit": ",,,,noir,teint_chocolat",
		"studio": {
			"name": "Studio Grande Maison Familiale (Keur Gui)",
			"bg_color": Color("191410"),
			"env_color": Color("130f0c"),
			"ambient_color": Color("3d2c20"),
			"key_color": Color("ffeedd"),
			"key_energy": 1.45,
			"key_rot": Vector3(-22, 35, 0),
			"fill_color": Color("f97316"),
			"fill_energy": 0.55,
			"rim_color": Color("fde047"),
			"rim_energy": 2.1,
			"pedestal_color": Color("452818"),
			"pedestal_accent": Color("f97316"),
			"pedestal_label": "KEUR GUI • MAISON DE LA TERANGA"
		}
	}
]

const AVATAR_NAMES := {
	"heros": "🦁 Modou Fall — Le Héros Dakarois",
	"lutteur1": "🤼 Balla Ndiaye — Champion de Lamb",
	"footballeur1": "⚽ Sadio Diatta — La Flèche des Lions",
	"femme_robe": "👑 Fatou Kiné Diop — Linguère & Styliste",
	"homme_age": "🕌 El Hadj Ousmane Sy — Doyen de la Médina",
	"soldat": "🛡️ Capitaine Moussa Traoré — Protecteur Républicain",
	"homme_ville": "💼 Ibrahima Cissé — L'Entrepreneur des Almadies",
	"footballeuse": "⚡ Aïssatou Sow — La Lionne du Sénégal",
	"femme_maman": "👵🏾 Mame Diarra — Matriarche de la Teranga",
	"homme_afro": "Jeune Dakarois (Afro & T-shirt)",
	"homme_tunique": "Notable en Tunique Traditionnelle",
	"femme_jupe": "Dakarise Moderne (Jupe élégante)",
	"femme_ville": "Citadine Active (Chemisier & Pantalon)",
	"lutteur2": "Bombardier — Colosse des Arènes",
	"gardien": "Gardien de but des Lions",
	"jayden_carter": "Jayden Carter — Invité VIP International",
}

var current_character_id: String = "heros"
var current_avatar: String = "heros"
var current_outfit: String = ""
var initial_avatar: String = "heros"
var initial_outfit: String = ""
var requested_character_id: String = ""

# Éléments 3D du Studio
var _subview_container: SubViewportContainer
var _subview: SubViewport
var _world: World3D
var _camera: Camera3D
var _env: Environment
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _rim_light: OmniLight3D
var _character_holder: Node3D
var _character_model: Node3D
var _pedestal: MeshInstance3D
var _pedestal_mat: StandardMaterial3D
var _pedestal_ring: MeshInstance3D
var _pedestal_label: Label3D
var _bg_rect: ColorRect

# Contrôle caméra orbitale
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.05
var _cam_dist: float = 2.4
var _cam_target_y: float = 0.95
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

# Interface utilisateur
var _header_title: Label
var _hero_chips_bar: HBoxContainer
var _profile_panel: PanelContainer
var _profile_name: Label
var _profile_title: Label
var _profile_district: Label
var _profile_quote: Label
var _profile_bio: Label
var _profile_role: Label
var _profile_stats_container: VBoxContainer
var _category_tabs: HBoxContainer
var _options_container: VBoxContainer
var _scroll_container: ScrollContainer
var _active_category: String = "avatar"


func _init(initial_char_id: String = "") -> void:
	requested_character_id = initial_char_id


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	focus_mode = Control.FOCUS_ALL

	# Fond studio moderne adaptatif
	_bg_rect = ColorRect.new()
	_bg_rect.anchor_right = 1.0
	_bg_rect.anchor_bottom = 1.0
	_bg_rect.color = Color("0d1117")
	add_child(_bg_rect)

	_setup_3d_studio()
	_setup_ui()

	# Initialiser depuis GameState et Net ou choix demandé
	initial_avatar = Net.avatar if Net.avatar != "" else "heros"
	initial_outfit = GameState.tenue
	current_avatar = initial_avatar
	current_outfit = initial_outfit

	var start_id: String = requested_character_id
	if start_id == "":
		for c in MAIN_CHARACTERS:
			if c["avatar"] == current_avatar or c["id"] == current_avatar:
				start_id = c["id"]
				break
	if start_id == "":
		start_id = "heros"

	select_main_character(start_id, false)
	_switch_category("avatar")


func _setup_3d_studio() -> void:
	_subview_container = SubViewportContainer.new()
	_subview_container.anchor_right = 1.0
	_subview_container.anchor_bottom = 1.0
	_subview_container.stretch = true
	add_child(_subview_container)

	_subview = SubViewport.new()
	_subview.own_world_3d = true
	_subview.transparent_bg = true
	_subview.msaa_3d = Viewport.MSAA_4X
	_subview.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_subview_container.add_child(_subview)

	_world = _subview.world_3d

	# Environnement Studio avec éclairage physique
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("10141c")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("3a404d")
	_env.ambient_light_energy = 0.85
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_enabled = true
	_env.glow_bloom = 0.08

	_camera = Camera3D.new()
	_camera.environment = _env
	_camera.current = true
	_camera.fov = 38.0
	_subview.add_child(_camera)

	# 1. Key Light
	_key_light = DirectionalLight3D.new()
	_key_light.light_color = Color("fff5ea")
	_key_light.light_energy = 1.45
	_key_light.rotation_degrees = Vector3(-25, 40, 0)
	_key_light.shadow_enabled = true
	_subview.add_child(_key_light)

	# 2. Fill Light
	_fill_light = DirectionalLight3D.new()
	_fill_light.light_color = Color("9ec5e8")
	_fill_light.light_energy = 0.55
	_fill_light.rotation_degrees = Vector3(-15, -120, 0)
	_subview.add_child(_fill_light)

	# 3. Rim / Hair Light
	_rim_light = OmniLight3D.new()
	_rim_light.light_color = Color("ffd166")
	_rim_light.light_energy = 2.2
	_rim_light.omni_range = 6.5
	_rim_light.position = Vector3(0, 2.2, -1.8)
	_subview.add_child(_rim_light)

	# Piédestal studio physique 3D
	_pedestal = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.15
	cyl.bottom_radius = 1.25
	cyl.height = 0.06
	_pedestal.mesh = cyl
	_pedestal_mat = StandardMaterial3D.new()
	_pedestal_mat.albedo_color = Color("1e232d")
	_pedestal_mat.roughness = 0.35
	_pedestal_mat.metallic = 0.15
	_pedestal.material_override = _pedestal_mat
	_pedestal.position = Vector3(0, -0.03, 0)
	_subview.add_child(_pedestal)

	# Anneau extérieur lumineux du piédestal
	_pedestal_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.18
	torus.outer_radius = 1.25
	_pedestal_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("ffd166")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("ffd166")
	ring_mat.emission_energy_multiplier = 1.2
	_pedestal_ring.material_override = ring_mat
	_pedestal_ring.position = Vector3(0, 0.005, 0)
	_subview.add_child(_pedestal_ring)

	# Label 3D gravé sur le socle
	_pedestal_label = Label3D.new()
	_pedestal_label.text = "DAKAR-PLATEAU • CORNICHE EST"
	_pedestal_label.font_size = 28
	_pedestal_label.modulate = Color("ffd166")
	_pedestal_label.position = Vector3(0, 0.01, 0.95)
	_pedestal_label.rotation_degrees = Vector3(-90, 0, 0)
	_subview.add_child(_pedestal_label)

	# Nœud hôte du personnage
	_character_holder = Node3D.new()
	_subview.add_child(_character_holder)

	_update_camera_transform()


func _setup_ui() -> void:
	var main_ui := Control.new()
	main_ui.anchor_right = 1.0
	main_ui.anchor_bottom = 1.0
	main_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_ui)

	# En-tête du Studio avec titre thématique et barre de sélection des personnages
	var header := PanelContainer.new()
	header.anchor_right = 1.0
	header.custom_minimum_size = Vector2(0, 94)
	var h_st := StyleBoxFlat.new()
	h_st.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	h_st.border_width_bottom = 2
	h_st.border_color = Color("ffd166")
	h_st.content_margin_left = 16
	h_st.content_margin_right = 16
	h_st.content_margin_top = 8
	h_st.content_margin_bottom = 8
	header.add_theme_stylebox_override("panel", h_st)
	main_ui.add_child(header)

	var h_vbox := VBoxContainer.new()
	h_vbox.add_theme_constant_override("separation", 6)
	header.add_child(h_vbox)

	var top_row := HBoxContainer.new()
	h_vbox.add_child(top_row)

	_header_title = Label.new()
	_header_title.text = "🎨 STUDIO DAKAR — PERSONNAGES PRINCIPAUX"
	_header_title.add_theme_font_size_override("font_size", 16)
	_header_title.add_theme_color_override("font_color", Color("ffd166"))
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_header_title)

	var quick_close := Button.new()
	quick_close.text = "✕ QUITTER"
	quick_close.custom_minimum_size = Vector2(90, 28)
	quick_close.add_theme_font_size_override("font_size", 12)
	quick_close.pressed.connect(_cancel_and_close)
	top_row.add_child(quick_close)

	# Barre de défilement des 9 Personnages Principaux
	var hero_scroll := ScrollContainer.new()
	hero_scroll.custom_minimum_size = Vector2(0, 42)
	hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hero_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h_vbox.add_child(hero_scroll)

	_hero_chips_bar = HBoxContainer.new()
	_hero_chips_bar.add_theme_constant_override("separation", 8)
	hero_scroll.add_child(_hero_chips_bar)

	for ch in MAIN_CHARACTERS:
		var btn := Button.new()
		btn.text = "%s %s" % [ch["icon"], ch["name"]]
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_size_override("font_size", 13)
		var b_st := StyleBoxFlat.new()
		b_st.bg_color = Color(0.12, 0.16, 0.22, 0.9)
		b_st.border_color = Color("384556")
		b_st.set_border_width_all(1)
		b_st.set_corner_radius_all(18)
		b_st.content_margin_left = 12
		b_st.content_margin_right = 12
		btn.add_theme_stylebox_override("normal", b_st)
		btn.pressed.connect(select_main_character.bind(ch["id"], true))
		_hero_chips_bar.add_child(btn)

	# Dossier du personnage sur la gauche (Profile & Stats)
	_setup_profile_panel(main_ui)

	# Panneau latéral droit d'édition détaillée
	var side_panel := PanelContainer.new()
	side_panel.anchor_left = 0.64
	side_panel.anchor_right = 0.985
	side_panel.anchor_top = 0.16
	side_panel.anchor_bottom = 0.96
	var p_st := StyleBoxFlat.new()
	p_st.bg_color = Color(0.08, 0.10, 0.15, 0.94)
	p_st.border_color = Color("2f3846")
	p_st.set_border_width_all(2)
	p_st.set_corner_radius_all(14)
	p_st.content_margin_left = 16
	p_st.content_margin_right = 16
	p_st.content_margin_top = 14
	p_st.content_margin_bottom = 14
	side_panel.add_theme_stylebox_override("panel", p_st)
	main_ui.add_child(side_panel)

	var side_vbox := VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 8)
	side_panel.add_child(side_vbox)

	# Onglets de catégories
	var cat_scroll := ScrollContainer.new()
	cat_scroll.custom_minimum_size = Vector2(0, 44)
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cat_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_vbox.add_child(cat_scroll)

	_category_tabs = HBoxContainer.new()
	_category_tabs.add_theme_constant_override("separation", 6)
	cat_scroll.add_child(_category_tabs)

	var categories := [
		["avatar", "👤 Personnages"],
		["teint", "🏾 Teint"],
		["coiffure", "✂️ Coiffure"],
		["couleur", "🎨 Cheveux"],
		["haut", "👕 Haut"],
		["bas", "👖 Bas"],
		["chapeau", "🧢 Chapeau"],
		["studio", "🎬 Studios & Poses"],
	]
	for cat in categories:
		var btn := Button.new()
		btn.text = cat[1]
		btn.custom_minimum_size = Vector2(90, 36)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_switch_category.bind(cat[0]))
		_category_tabs.add_child(btn)

	# Zone défilante des options sélectionnables
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_vbox.add_child(_scroll_container)

	_options_container = VBoxContainer.new()
	_options_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_container.add_theme_constant_override("separation", 8)
	_scroll_container.add_child(_options_container)

	# Barre d'actions inférieure
	var act_box := HBoxContainer.new()
	act_box.add_theme_constant_override("separation", 8)
	side_vbox.add_child(act_box)

	var rand_btn := Button.new()
	rand_btn.text = "🎲 Aléatoire"
	rand_btn.custom_minimum_size = Vector2(90, 42)
	rand_btn.pressed.connect(_randomize_look)
	act_box.add_child(rand_btn)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 Reset"
	reset_btn.custom_minimum_size = Vector2(75, 42)
	reset_btn.pressed.connect(_reset_look)
	act_box.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "💾 CHOISIR CE PERSONNAGE"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 42)
	var s_st := StyleBoxFlat.new()
	s_st.bg_color = Color("00853f")
	s_st.set_corner_radius_all(8)
	save_btn.add_theme_stylebox_override("normal", s_st)
	save_btn.pressed.connect(_save_and_close)
	act_box.add_child(save_btn)

	# Contrôles de caméra orbitale sur la gauche
	var cam_ctrls := VBoxContainer.new()
	cam_ctrls.anchor_left = 0.02
	cam_ctrls.anchor_top = 0.82
	cam_ctrls.add_theme_constant_override("separation", 4)
	main_ui.add_child(cam_ctrls)

	var zoom_box := HBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 6)
	cam_ctrls.add_child(zoom_box)

	var btn_face := Button.new()
	btn_face.text = "🔍 Visage"
	btn_face.pressed.connect(_set_camera_view.bind(0.85, 1.48))
	zoom_box.add_child(btn_face)

	var btn_bust := Button.new()
	btn_bust.text = "👤 Buste"
	btn_bust.pressed.connect(_set_camera_view.bind(1.45, 1.15))
	zoom_box.add_child(btn_bust)

	var btn_body := Button.new()
	btn_body.text = "🧍 Corps"
	btn_body.pressed.connect(_set_camera_view.bind(2.4, 0.95))
	zoom_box.add_child(btn_body)


func _setup_profile_panel(parent: Control) -> void:
	_profile_panel = PanelContainer.new()
	_profile_panel.anchor_left = 0.02
	_profile_panel.anchor_right = 0.30
	_profile_panel.anchor_top = 0.16
	_profile_panel.anchor_bottom = 0.80
	var p_st := StyleBoxFlat.new()
	p_st.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	p_st.border_color = Color("ffd166")
	p_st.set_border_width_all(1)
	p_st.set_corner_radius_all(12)
	p_st.content_margin_left = 14
	p_st.content_margin_right = 14
	p_st.content_margin_top = 12
	p_st.content_margin_bottom = 12
	_profile_panel.add_theme_stylebox_override("panel", p_st)
	parent.add_child(_profile_panel)

	var p_scroll := ScrollContainer.new()
	p_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_profile_panel.add_child(p_scroll)

	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", 6)
	p_scroll.add_child(pv)

	_profile_name = Label.new()
	_profile_name.text = "Modou Fall"
	_profile_name.add_theme_font_size_override("font_size", 18)
	_profile_name.add_theme_color_override("font_color", Color("ffd166"))
	pv.add_child(_profile_name)

	_profile_title = Label.new()
	_profile_title.text = "Le Héros Dakarois"
	_profile_title.add_theme_font_size_override("font_size", 13)
	_profile_title.add_theme_color_override("font_color", Color("7cfc9a"))
	pv.add_child(_profile_title)

	_profile_district = Label.new()
	_profile_district.text = "📍 Dakar-Plateau"
	_profile_district.add_theme_font_size_override("font_size", 12)
	_profile_district.add_theme_color_override("font_color", Color("a0aab8"))
	pv.add_child(_profile_district)

	_profile_quote = Label.new()
	_profile_quote.text = "« Dakar ne dort jamais ! »"
	_profile_quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_quote.add_theme_font_size_override("font_size", 12)
	_profile_quote.add_theme_color_override("font_color", Color("ffdd80"))
	pv.add_child(_profile_quote)

	var sep1 := HSeparator.new()
	pv.add_child(sep1)

	_profile_bio = Label.new()
	_profile_bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_bio.add_theme_font_size_override("font_size", 12)
	_profile_bio.add_theme_color_override("font_color", Color("cbd5e1"))
	pv.add_child(_profile_bio)

	var sep2 := HSeparator.new()
	pv.add_child(sep2)

	var stats_title := Label.new()
	stats_title.text = "ATTRIBUTS DU CITOYEN"
	stats_title.add_theme_font_size_override("font_size", 12)
	stats_title.add_theme_color_override("font_color", Color("ffd166"))
	pv.add_child(stats_title)

	_profile_stats_container = VBoxContainer.new()
	_profile_stats_container.add_theme_constant_override("separation", 4)
	pv.add_child(_profile_stats_container)


func select_main_character(char_id: String, apply_default_outfit := false) -> void:
	var char_data: Dictionary = {}
	for c in MAIN_CHARACTERS:
		if c["id"] == char_id or c["avatar"] == char_id:
			char_data = c
			break
	if char_data.is_empty():
		char_data = MAIN_CHARACTERS[0]

	current_character_id = char_data["id"]
	current_avatar = char_data["avatar"]
	if apply_default_outfit or current_outfit == "":
		current_outfit = char_data.get("default_outfit", ",,,degrade,noir,teint_ebene")

	# Mise à jour du studio 3D
	apply_studio_theme(char_data["studio"])
	_load_character_preview()

	# Jouer l'animation signature
	var pose: String = char_data.get("pose", "idle")
	if _character_model and _character_model.has_method("play_clip"):
		_character_model.play_clip(pose, 0.3)

	# Mise à jour de l'interface
	if _header_title:
		_header_title.text = "🎨 %s — %s (%s)" % [
			char_data["studio"]["name"].to_upper(),
			char_data["name"],
			char_data["title"]
		]

	_update_profile_card(char_data)
	_update_hero_chips()
	if _active_category == "avatar":
		_build_avatar_options()


func apply_studio_theme(theme: Dictionary) -> void:
	if _bg_rect:
		_bg_rect.color = theme.get("bg_color", Color("0d1117"))
	if _env:
		_env.background_color = theme.get("env_color", Color("10141c"))
		_env.ambient_light_color = theme.get("ambient_color", Color("3a404d"))
	if _key_light:
		_key_light.light_color = theme.get("key_color", Color("fff3e0"))
		_key_light.light_energy = theme.get("key_energy", 1.4)
		_key_light.rotation_degrees = theme.get("key_rot", Vector3(-25, 40, 0))
	if _fill_light:
		_fill_light.light_color = theme.get("fill_color", Color("9ec5e8"))
		_fill_light.light_energy = theme.get("fill_energy", 0.55)
	if _rim_light:
		_rim_light.light_color = theme.get("rim_color", Color("ffd166"))
		_rim_light.light_energy = theme.get("rim_energy", 2.2)
	if _pedestal_mat:
		_pedestal_mat.albedo_color = theme.get("pedestal_color", Color("1e232d"))
	if _pedestal_ring and _pedestal_ring.material_override:
		_pedestal_ring.material_override.albedo_color = theme.get("pedestal_accent", Color("ffd166"))
		_pedestal_ring.material_override.emission = theme.get("pedestal_accent", Color("ffd166"))
	if _pedestal_label:
		_pedestal_label.text = theme.get("pedestal_label", "DAKAR-PLATEAU")
		_pedestal_label.modulate = theme.get("pedestal_accent", Color("ffd166"))


func _update_profile_card(char_data: Dictionary) -> void:
	if not _profile_name:
		return
	_profile_name.text = "%s %s" % [char_data["icon"], char_data["name"]]
	_profile_title.text = "%s (%s)" % [char_data["title"], char_data.get("nickname", "")]
	_profile_district.text = "📍 %s" % char_data.get("district", "Dakar")
	_profile_quote.text = char_data.get("quote", "")
	_profile_bio.text = char_data.get("bio", "")

	for ch in _profile_stats_container.get_children():
		ch.queue_free()

	var stats: Dictionary = char_data.get("stats", {})
	for stat_name in stats:
		var val: int = stats[stat_name]
		var s_row := HBoxContainer.new()
		var s_lbl := Label.new()
		s_lbl.text = "%s :" % stat_name
		s_lbl.custom_minimum_size = Vector2(80, 0)
		s_lbl.add_theme_font_size_override("font_size", 11)
		s_lbl.add_theme_color_override("font_color", Color("cbd5e1"))
		s_row.add_child(s_lbl)

		var bar := ProgressBar.new()
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.custom_minimum_size = Vector2(0, 14)
		bar.max_value = 100
		bar.value = val
		bar.show_percentage = false
		var sb_fill := StyleBoxFlat.new()
		sb_fill.bg_color = char_data["studio"].get("pedestal_accent", Color("ffd166"))
		sb_fill.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("fill", sb_fill)
		s_row.add_child(bar)

		var v_lbl := Label.new()
		v_lbl.text = " %d%%" % val
		v_lbl.custom_minimum_size = Vector2(38, 0)
		v_lbl.add_theme_font_size_override("font_size", 11)
		v_lbl.add_theme_color_override("font_color", Color("ffd166"))
		s_row.add_child(v_lbl)
		_profile_stats_container.add_child(s_row)


func _update_hero_chips() -> void:
	if not _hero_chips_bar:
		return
	var idx := 0
	for ch in MAIN_CHARACTERS:
		if idx < _hero_chips_bar.get_child_count():
			var btn = _hero_chips_bar.get_child(idx)
			if btn is Button:
				var is_sel: bool = (ch["id"] == current_character_id)
				var b_st := StyleBoxFlat.new()
				b_st.bg_color = Color("234236") if is_sel else Color(0.12, 0.16, 0.22, 0.9)
				b_st.border_color = Color("ffd166") if is_sel else Color("384556")
				b_st.set_border_width_all(2 if is_sel else 1)
				b_st.set_corner_radius_all(18)
				b_st.content_margin_left = 12
				b_st.content_margin_right = 12
				btn.add_theme_stylebox_override("normal", b_st)
				btn.add_theme_color_override("font_color", Color("ffd166") if is_sel else Color("cbd5e1"))
		idx += 1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
			_drag_start = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = clampf(_cam_dist - 0.15, 0.65, 3.2)
			_update_camera_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = clampf(_cam_dist + 0.15, 0.65, 3.2)
			_update_camera_transform()
	elif event is InputEventMouseMotion and _is_dragging:
		var delta: Vector2 = event.position - _drag_start
		_drag_start = event.position
		_cam_yaw -= delta.x * 0.008
		_cam_pitch = clampf(_cam_pitch + delta.y * 0.005, -0.25, 0.55)
		_update_camera_transform()


func _update_camera_transform() -> void:
	if not _camera:
		return
	var target := Vector3(0, _cam_target_y, 0)
	var x: float = sin(_cam_yaw) * cos(_cam_pitch) * _cam_dist
	var y: float = sin(_cam_pitch) * _cam_dist + _cam_target_y
	var z: float = cos(_cam_yaw) * cos(_cam_pitch) * _cam_dist
	_camera.position = Vector3(x, y, z)
	_camera.look_at(target, Vector3.UP)


func _set_camera_view(dist: float, target_y: float) -> void:
	_cam_dist = dist
	_cam_target_y = target_y
	_update_camera_transform()


func _load_character_preview() -> void:
	if _character_model and is_instance_valid(_character_model):
		_character_model.queue_free()
		_character_model = null

	_character_model = RealCharacter.create(_character_holder, current_avatar, -1)
	if _character_model and _character_model.has_method("set_outfit"):
		_character_model.set_outfit(current_outfit)
	if _character_model and _character_model.has_method("play_clip"):
		_character_model.play_clip("idle", 0.3)


func _switch_category(cat_id: String) -> void:
	_active_category = cat_id
	for ch in _options_container.get_children():
		ch.queue_free()

	for btn in _category_tabs.get_children():
		if btn is Button:
			btn.flat = not (btn.text.to_lower().contains(cat_id))

	match cat_id:
		"avatar":
			_build_avatar_options()
		"teint":
			_build_skin_tone_options()
		"coiffure":
			_build_hair_style_options()
		"couleur":
			_build_hair_color_options()
		"haut":
			_build_outfit_part_options(0, "Haut (Chemise / Polo / Tunique)")
		"bas":
			_build_outfit_part_options(1, "Bas (Pantalon / Jupe)")
		"chapeau":
			_build_hat_options()
		"studio":
			_build_studio_pose_options()


func _build_avatar_options() -> void:
	var desc := Label.new()
	desc.text = "Choisis un Personnage Principal pour entrer dans son Studio thématique :"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_container.add_child(desc)

	for ch in MAIN_CHARACTERS:
		var card := PanelContainer.new()
		var is_selected: bool = (ch["id"] == current_character_id)
		var c_st := StyleBoxFlat.new()
		c_st.bg_color = Color("234236") if is_selected else Color(0.11, 0.14, 0.20, 0.9)
		c_st.border_color = Color("ffd166") if is_selected else Color("334155")
		c_st.set_border_width_all(2 if is_selected else 1)
		c_st.set_corner_radius_all(10)
		c_st.content_margin_left = 12
		c_st.content_margin_right = 12
		c_st.content_margin_top = 10
		c_st.content_margin_bottom = 10
		card.add_theme_stylebox_override("panel", c_st)
		_options_container.add_child(card)

		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 4)
		card.add_child(cv)

		var r1 := HBoxContainer.new()
		cv.add_child(r1)

		var name_lbl := Label.new()
		name_lbl.text = "%s %s" % [ch["icon"], ch["name"]]
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color("ffd166"))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r1.add_child(name_lbl)

		if is_selected:
			var act_tag := Label.new()
			act_tag.text = "ACTIF"
			act_tag.add_theme_font_size_override("font_size", 11)
			act_tag.add_theme_color_override("font_color", Color("7cfc9a"))
			r1.add_child(act_tag)

		var title_lbl := Label.new()
		title_lbl.text = "%s • %s" % [ch["title"], ch["district"]]
		title_lbl.add_theme_font_size_override("font_size", 12)
		title_lbl.add_theme_color_override("font_color", Color("cbd5e1"))
		cv.add_child(title_lbl)

		var studio_lbl := Label.new()
		studio_lbl.text = "🎬 %s" % ch["studio"]["name"]
		studio_lbl.add_theme_font_size_override("font_size", 11)
		studio_lbl.add_theme_color_override("font_color", Color("94a3b8"))
		cv.add_child(studio_lbl)

		var sel_btn := Button.new()
		sel_btn.text = "Entrer dans ce Studio" if not is_selected else "✓ Studio Actuel"
		sel_btn.custom_minimum_size = Vector2(0, 34)
		sel_btn.pressed.connect(select_main_character.bind(ch["id"], true))
		cv.add_child(sel_btn)


func _build_skin_tone_options() -> void:
	var p := Outfits.parse(current_outfit)
	var cur_tone: String = p[5] if p.size() > 5 else ""

	var desc := Label.new()
	desc.text = "Carnation et teint épidermique du personnage :"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_container.add_child(desc)

	var def_btn := Button.new()
	def_btn.text = ("✓ " if cur_tone == "" else "") + "Teint naturel d'origine"
	def_btn.custom_minimum_size = Vector2(0, 42)
	def_btn.pressed.connect(_set_skin_tone.bind(""))
	_options_container.add_child(def_btn)

	for tone_id in Outfits.SKIN_TONES:
		var data: Array = Outfits.SKIN_TONES[tone_id]
		var btn := Button.new()
		var is_sel: bool = (cur_tone == tone_id)
		btn.text = ("✓ " if is_sel else "") + data[0]
		btn.custom_minimum_size = Vector2(0, 44)
		var col: Color = data[1]
		var b_st := StyleBoxFlat.new()
		b_st.bg_color = col.darkened(0.15)
		b_st.border_color = Color("ffd166") if is_sel else col.lightened(0.2)
		b_st.set_border_width_all(3 if is_sel else 1)
		b_st.set_corner_radius_all(8)
		b_st.content_margin_left = 14
		btn.add_theme_stylebox_override("normal", b_st)
		btn.pressed.connect(_set_skin_tone.bind(tone_id))
		_options_container.add_child(btn)


func _set_skin_tone(tone_id: String) -> void:
	var p := Outfits.parse(current_outfit)
	while p.size() < 6:
		p.append("")
	p[5] = tone_id
	current_outfit = Outfits.make(p)
	if _character_model and _character_model.has_method("set_outfit"):
		_character_model.set_outfit(current_outfit)
	_switch_category("teint")


func _build_hair_style_options() -> void:
	var p := Outfits.parse(current_outfit)
	var cur_hair: String = p[3]

	var def_btn := Button.new()
	def_btn.text = ("✓ " if cur_hair == "" else "") + "Coiffure d'origine"
	def_btn.custom_minimum_size = Vector2(0, 42)
	def_btn.pressed.connect(_set_hair_style.bind(""))
	_options_container.add_child(def_btn)

	for h_id in Outfits.HAIRS:
		var data: Array = Outfits.HAIRS[h_id]
		var btn := Button.new()
		var is_sel: bool = (cur_hair == h_id)
		btn.text = ("✓ " if is_sel else "") + data[0]
		btn.custom_minimum_size = Vector2(0, 42)
		btn.pressed.connect(_set_hair_style.bind(h_id))
		_options_container.add_child(btn)


func _set_hair_style(h_id: String) -> void:
	var p := Outfits.parse(current_outfit)
	p[3] = h_id
	current_outfit = Outfits.make(p)
	if _character_model and _character_model.has_method("set_outfit"):
		_character_model.set_outfit(current_outfit)
	_switch_category("coiffure")


func _build_hair_color_options() -> void:
	var p := Outfits.parse(current_outfit)
	var cur_col: String = p[4]

	for c_id in Outfits.HAIR_COLORS:
		var data: Array = Outfits.HAIR_COLORS[c_id]
		var btn := Button.new()
		var is_sel: bool = (cur_col == c_id)
		btn.text = ("✓ " if is_sel else "") + data[0]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(_set_hair_color.bind(c_id))
		_options_container.add_child(btn)


func _set_hair_color(c_id: String) -> void:
	var p := Outfits.parse(current_outfit)
	p[4] = c_id
	current_outfit = Outfits.make(p)
	if _character_model and _character_model.has_method("set_outfit"):
		_character_model.set_outfit(current_outfit)
	_switch_category("couleur")


func _build_outfit_part_options(part_idx: int, _title: String) -> void:
	var p := Outfits.parse(current_outfit)
	var cur_val: String = p[part_idx]

	var def_btn := Button.new()
	def_btn.text = ("✓ " if cur_val == "" else "") + "Couleur d'origine"
	def_btn.custom_minimum_size = Vector2(0, 42)
	def_btn.pressed.connect(_set_outfit_part.bind(part_idx, ""))
	_options_container.add_child(def_btn)

	for col_id in Outfits.COLORS:
		var data: Array = Outfits.COLORS[col_id]
		var btn := Button.new()
		var is_sel: bool = (cur_val == col_id)
		btn.text = ("✓ " if is_sel else "") + data[0]
		btn.custom_minimum_size = Vector2(0, 42)
		var col: Color = data[1]
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.darkened(0.25)
		sb.border_color = Color("ffd166") if is_sel else col
		sb.set_border_width_all(3 if is_sel else 1)
		sb.set_corner_radius_all(8)
		sb.content_margin_left = 12
		btn.add_theme_stylebox_override("normal", sb)
		if col.get_luminance() > 0.65:
			btn.add_theme_color_override("font_color", Color.BLACK)
		btn.pressed.connect(_set_outfit_part.bind(part_idx, col_id))
		_options_container.add_child(btn)


func _set_outfit_part(part_idx: int, val: String) -> void:
	var p := Outfits.parse(current_outfit)
	p[part_idx] = val
	current_outfit = Outfits.make(p)
	if _character_model and _character_model.has_method("set_outfit"):
		_character_model.set_outfit(current_outfit)
	_switch_category("haut" if part_idx == 0 else "bas")


func _build_hat_options() -> void:
	var p := Outfits.parse(current_outfit)
	var cur_hat: String = p[2]

	var none_btn := Button.new()
	none_btn.text = ("✓ " if cur_hat == "" else "") + "Sans couvre-chef"
	none_btn.custom_minimum_size = Vector2(0, 42)
	none_btn.pressed.connect(_set_hat.bind(""))
	_options_container.add_child(none_btn)

	for hat_id in Outfits.HATS:
		var data: Array = Outfits.HATS[hat_id]
		var btn := Button.new()
		var is_sel: bool = (cur_hat == hat_id)
		btn.text = ("✓ " if is_sel else "") + data[0]
		btn.custom_minimum_size = Vector2(0, 42)
		btn.pressed.connect(_set_hat.bind(hat_id))
		_options_container.add_child(btn)


func _set_hat(hat_id: String) -> void:
	var p := Outfits.parse(current_outfit)
	p[2] = hat_id
	current_outfit = Outfits.make(p)
	if _character_model and _character_model.has_method("set_outfit"):
		_character_model.set_outfit(current_outfit)
	_switch_category("chapeau")


func _build_studio_pose_options() -> void:
	var desc := Label.new()
	desc.text = "Studios thématiques et animations des personnages :"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_container.add_child(desc)

	var s_title := Label.new()
	s_title.text = "AMBIANCE STUDIO 3D :"
	s_title.add_theme_font_size_override("font_size", 12)
	s_title.add_theme_color_override("font_color", Color("ffd166"))
	_options_container.add_child(s_title)

	for ch in MAIN_CHARACTERS:
		var s_btn := Button.new()
		var s_name: String = ch["studio"]["name"]
		s_btn.text = "%s %s" % [ch["icon"], s_name]
		s_btn.custom_minimum_size = Vector2(0, 38)
		s_btn.pressed.connect(apply_studio_theme.bind(ch["studio"]))
		_options_container.add_child(s_btn)

	var p_title := Label.new()
	p_title.text = "POSES & ANIMATIONS 3D :"
	p_title.add_theme_font_size_override("font_size", 12)
	p_title.add_theme_color_override("font_color", Color("ffd166"))
	_options_container.add_child(p_title)

	var poses := [
		["idle", "🧘 Pose d'attente (Respiration naturelle)"],
		["arms_crossed", "💪 Bras croisés (Colosse / Détermination)"],
		["wave", "👋 Saluer la Teranga"],
		["dance", "💃 Danse festive / Célébration"],
		["dua", "🤲 Prière traditionnelle (Dua)"],
		["talk", "🗣️ Discussion animée"],
		["sit", "🪑 S'asseoir"],
	]
	for p in poses:
		var btn := Button.new()
		btn.text = p[1]
		btn.custom_minimum_size = Vector2(0, 42)
		btn.pressed.connect(func():
			if _character_model and _character_model.has_method("play_clip"):
				_character_model.play_clip(p[0], 0.2)
		)
		_options_container.add_child(btn)


func _randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var rand_ch = MAIN_CHARACTERS[rng.randi() % MAIN_CHARACTERS.size()]
	select_main_character(rand_ch["id"], false)

	var tone_keys := Outfits.SKIN_TONES.keys()
	var hair_keys := Outfits.HAIRS.keys()
	var color_keys := Outfits.COLORS.keys()
	var hat_keys := [""] + Outfits.HATS.keys()

	var rand_top: String = str(color_keys[rng.randi() % color_keys.size()])
	var rand_bot: String = str(color_keys[rng.randi() % color_keys.size()])
	var rand_hat: String = str(hat_keys[rng.randi() % hat_keys.size()])
	var rand_hair: String = str(hair_keys[rng.randi() % hair_keys.size()])
	var rand_tone: String = str(tone_keys[rng.randi() % tone_keys.size()])

	current_outfit = "%s,%s,%s,%s,noir,%s" % [rand_top, rand_bot, rand_hat, rand_hair, rand_tone]
	_load_character_preview()
	_switch_category(_active_category)


func _reset_look() -> void:
	current_avatar = initial_avatar
	current_outfit = initial_outfit
	_load_character_preview()
	_switch_category(_active_category)


func _save_and_close() -> void:
	GameState.tenue = current_outfit
	Net.avatar = current_avatar

	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("net", "avatar", current_avatar)
	cfg.set_value("net", "character_id", current_character_id)
	cfg.save("user://settings.cfg")
	GameState.save_game()

	var tree = get_tree()
	if tree:
		var players = tree.get_nodes_in_group("player")
		for p in players:
			if p.get("model") and p.model.has_method("set_outfit"):
				p.model.set_outfit(current_outfit)

	closed.emit(true)
	queue_free()


func _cancel_and_close() -> void:
	closed.emit(false)
	queue_free()
