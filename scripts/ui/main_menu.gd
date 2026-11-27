extends Control
## Menu de départ : jouer en solo, ou se connecter au serveur en ligne.
## Réglages retenus (adresse, pseudo, mot de passe, personnage, thème) dans user://net_settings.cfg.

const SETTINGS := "user://net_settings.cfg"
const MAIN := "res://scenes/main.tscn"
const AVATAR_NAMES := {
	"heros": "🦁 Modou Fall — Le Héros Dakarois",
	"lutteur1": "🤼 Balla Ndiaye — Champion des Arènes (Lamb)",
	"footballeur1": "⚽ Sadio Diatta — La Flèche des Lions",
	"femme_robe": "👑 Fatou Kiné Diop — Linguère & Styliste",
	"homme_age": "🕌 El Hadj Ousmane Sy — Doyen de la Médina",
	"soldat": "🛡️ Capitaine Moussa Traoré — Protecteur Républicain",
	"homme_ville": "💼 Ibrahima Cissé — L'Entrepreneur des Almadies",
	"footballeuse": "⚡ Aïssatou Sow — La Lionne du Sénégal",
	"femme_maman": "👵🏾 Mame Diarra — La Matriarche de la Teranga",
	"homme_afro": "Jeune Dakarois (Afro & T-shirt)",
	"homme_tunique": "Notable en Tunique Traditionnelle",
	"femme_jupe": "Dakarise Moderne (Jupe élégante)",
	"femme_ville": "Citadine Active (Chemisier & Pantalon)",
	"lutteur2": "Bombardier — Colosse des Arènes",
	"gardien": "Gardien de but des Lions",
	"jayden_carter": "Jayden Carter — Invité VIP International",
}
## Arguments de test qui démarrent directement la partie solo
const DIRECT_ARGS := ["--screenshot=", "--test-taxi", "--portrait", "--showcase", "--map", "--arena", "--at=", "--look=", "--overhead=", "--phone=", "--emote=", "--fps-test", "--perf-probe", "--pos=", "--inside-test", "--audit", "--office=", "--touch-test", "--drive-test", "--lutte-test", "--fight-test", "--crowd-test", "--lutte-live", "--lutte-base=", "--latlon=", "--enter=", "--talk=", "--home=", "--dealer-test", "--city-test", "--fish-test", "--rob-test", "--impound-test", "--cook-test", "--rooms-shot", "--feet-test", "--ped-motion", "--traffic-motion", "--rooms-walk", "--rental-test", "--biz-test", "--market-scan", "--market-test", "--goods-shots", "--hud-shot", "--trade-net", "--trade-shot", "--foot-test", "--foot-net", "--foot", "--foot-night", "--tuto-test", "--touch-layout"]

var is_light_mode := false

var _bg: ColorRect
var _bg_texture: TextureRect
var _bg_overlay: ColorRect
var _scroll: ScrollContainer
var _margin: MarginContainer
var _center_box: CenterContainer
var _master_container: BoxContainer
var _hero_box: VBoxContainer
var _card_panel: PanelContainer
var _content_vbox: VBoxContainer
var _compact_header: VBoxContainer

var _host: LineEdit
var _channel: OptionButton
var _pseudo: LineEdit
var _password: LineEdit
var _avatar: OptionButton
var _customize_avatar_btn: Button
var _friend_code: LineEdit
var _create: CheckBox
var _customize_on_start: CheckBox
var _status: Label
var _connect_btn: Button
var _offline_btn: Button
var _studio_btn: Button
var _offline_fallback_btn: Button
var _theme_btn: Button
var _compact_theme_btn: Button
var _credits_btn: Button
var _friend_toggle_btn: Button
var _paste_btn: Button
var _copy_my_code_btn: Button
var _my_code_label: Label
var _fields_list: Array[LineEdit] = []
var _labels_list: Array[Label] = []
var _feature_pills: Array[PanelContainer] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var wants_online := false
	for a in args:
		if a.begins_with("--online=") or a == "--server":
			wants_online = true
	for a in args:
		if wants_online:
			break
		for d in DIRECT_ARGS:
			if a.begins_with(d):
				# Lancements de test : sauvegarde séparée, la partie du joueur n'est jamais touchée
				GameState.save_path = "user://test_save.json"
				get_tree().call_deferred("change_scene_to_file", MAIN)
				return
	
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	is_light_mode = bool(cfg.get_value("ui", "light_mode", false))
	if has_node("/root/GameState"):
		get_node("/root/GameState").light_mode = is_light_mode

	_build()
	apply_theme()
	CrashReport.step("menu")
	Net.login_result.connect(_on_login)
	Net.connection_changed.connect(func(s): _status.text = s)

	# Connexion automatique (tests) : -- --online=hôte --pseudo=... --password=... [--create] [--avatar=...]
	var auto := {}
	for a in args:
		if a.begins_with("--") and "=" in a:
			auto[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	if auto.has("online"):
		_host.text = auto["online"]
		_pseudo.text = auto.get("pseudo", _pseudo.text)
		_password.text = auto.get("password", _password.text)
		_create.button_pressed = "--create" in args
		var idx := Net.AVATARS.find(auto.get("avatar", "heros"))
		_avatar.select(maxi(0, idx))
		_on_connect()


func _process(_delta: float) -> void:
	if not _scroll:
		return
	var vp_size := get_viewport_rect().size
	var margins: Dictionary = {"left": 16.0, "top": 12.0, "right": 16.0, "bottom": 16.0}
	if has_node("/root/GameState"):
		margins = get_node("/root/GameState").get_safe_margins(get_viewport())
	
	if _margin:
		_margin.add_theme_constant_override("margin_left", int(maxf(margins.left, 16.0)))
		_margin.add_theme_constant_override("margin_right", int(maxf(margins.right, 16.0)))
		_margin.add_theme_constant_override("margin_top", int(maxf(margins.top, 12.0)))
		_margin.add_theme_constant_override("margin_bottom", int(maxf(margins.bottom, 20.0)))

	# Élévation réactive de l'interface quand le clavier virtuel apparaît sur smartphone (iOS / Android)
	var kb_h := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	var target_bottom: float = -float(kb_h) if kb_h > 0 else 0.0
	if absf(_scroll.offset_bottom - target_bottom) > 1.0:
		_scroll.offset_bottom = lerpf(_scroll.offset_bottom, target_bottom, 0.45)

	# Agencement adaptatif sans vide : 2 colonnes en paysage / large, 1 colonne fluide en portrait / étroit
	var avail_w: float = vp_size.x - float(margins.left) - float(margins.right) - 32.0
	var is_wide: bool = vp_size.x >= 700.0 and (vp_size.x / maxf(vp_size.y, 1.0)) >= 1.22
	_update_responsive_layout(is_wide, avail_w, vp_size)


func _update_responsive_layout(is_wide: bool, avail_w: float, vp_size: Vector2) -> void:
	if not _master_container or not _card_panel or not _content_vbox:
		return
	
	if is_wide:
		# Mode Paysage : 2 colonnes équilibrées pour remplir l'écran sans vide
		_master_container.vertical = false
		_master_container.add_theme_constant_override("separation", 28)
		if _hero_box:
			_hero_box.visible = true
			var hero_w := clampf(avail_w * 0.45, 300.0, 520.0)
			_hero_box.custom_minimum_size.x = hero_w
		if _compact_header:
			_compact_header.visible = false
		
		var card_w := clampf(avail_w * 0.50, 340.0, 520.0)
		_card_panel.custom_minimum_size.x = card_w
		_content_vbox.custom_minimum_size.x = card_w - 36.0
	else:
		# Mode Portrait ou Écran compact : 1 colonne fluide et centrée
		_master_container.vertical = true
		_master_container.add_theme_constant_override("separation", 12)
		if _hero_box:
			_hero_box.visible = false
		if _compact_header:
			_compact_header.visible = true
		
		var card_w := clampf(avail_w, 280.0, 520.0)
		_card_panel.custom_minimum_size.x = card_w
		_content_vbox.custom_minimum_size.x = card_w - 28.0


func _input(event: InputEvent) -> void:
	# Ferme le clavier virtuel si l'utilisateur touche l'arrière-plan en dehors des champs
	if event is InputEventScreenTouch and event.pressed:
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit:
			var r := fo.get_global_rect()
			if not r.has_point(event.position):
				fo.release_focus()


func _build() -> void:
	# 1. Fond d'écran photographique de Dakar avec superposition réactive
	_bg = ColorRect.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_bg_texture = TextureRect.new()
	_bg_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists("res://textures/ui/dakar_corniche.jpg"):
		_bg_texture.texture = load("res://textures/ui/dakar_corniche.jpg")
	elif ResourceLoader.exists("res://textures/ui/dakar_bg.jpg"):
		_bg_texture.texture = load("res://textures/ui/dakar_bg.jpg")
	add_child(_bg_texture)

	_bg_overlay = ColorRect.new()
	_bg_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg_overlay)

	# 2. Scroll container plein écran
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	# 3. Marges safe-area
	_margin = MarginContainer.new()
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_margin)

	# 4. Centrage vertical sur les écrans hauts pour ne jamais laisser de vide
	_center_box = CenterContainer.new()
	_center_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_child(_center_box)

	# 5. Master container (devient horizontal en paysage, vertical en portrait)
	_master_container = BoxContainer.new()
	_master_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_box.add_child(_master_container)

	# =========================================================================
	# COLONNE DE GAUCHE : Vitrine Dakar & Présentation (affichée en mode large)
	# =========================================================================
	_hero_box = VBoxContainer.new()
	_hero_box.add_theme_constant_override("separation", 14)
	_hero_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_master_container.add_child(_hero_box)

	# Carte photographique du Monument de la Renaissance
	if ResourceLoader.exists("res://textures/world/renaissance_monument.jpg"):
		var preview_panel := PanelContainer.new()
		var preview_st := StyleBoxFlat.new()
		preview_st.set_corner_radius_all(12)
		preview_st.bg_color = Color(0, 0, 0, 0.4)
		preview_st.border_width_left = 1
		preview_st.border_width_top = 1
		preview_st.border_width_right = 1
		preview_st.border_width_bottom = 1
		preview_st.border_color = Color(1, 1, 1, 0.25)
		preview_panel.clip_contents = true
		preview_panel.add_theme_stylebox_override("panel", preview_st)

		var preview_img := TextureRect.new()
		preview_img.texture = load("res://textures/world/renaissance_monument.jpg")
		preview_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		preview_img.custom_minimum_size = Vector2(320, 150)
		preview_panel.add_child(preview_img)

		var caption_box := PanelContainer.new()
		caption_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		var cap_st := StyleBoxFlat.new()
		cap_st.bg_color = Color(0, 0, 0, 0.65)
		cap_st.content_margin_top = 4.0
		cap_st.content_margin_bottom = 4.0
		caption_box.add_theme_stylebox_override("panel", cap_st)

		var caption := Label.new()
		caption.text = "📍 Monument de la Renaissance Africaine • Dakar"
		caption.add_theme_font_size_override("font_size", 11)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption_box.add_child(caption)
		preview_panel.add_child(caption_box)

		_hero_box.add_child(preview_panel)

	var hero_badge := Label.new()
	hero_badge.text = "🇸🇳 SÉNÉGAL • DAKAR 3D"
	hero_badge.add_theme_font_size_override("font_size", 13)
	_labels_list.append(hero_badge)
	_hero_box.add_child(hero_badge)

	var hero_title := Label.new()
	hero_title.text = "GALSEN-LIFE"
	hero_title.add_theme_font_size_override("font_size", 42)
	hero_title.name = "HeroTitle"
	_labels_list.append(hero_title)
	_hero_box.add_child(hero_title)

	var hero_desc := Label.new()
	hero_desc.text = "Plonge dans l'ambiance authentique de Dakar : sillonne la ville en taxi ou car rapide, affronte les champions dans les arènes de lutte, commande chez Maïga et vis ta vie de citoyen sénégalais !"
	hero_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hero_desc.add_theme_font_size_override("font_size", 14)
	_labels_list.append(hero_desc)
	_hero_box.add_child(hero_desc)

	# Pilules de fonctionnalités
	var pills_box := VBoxContainer.new()
	pills_box.add_theme_constant_override("separation", 6)
	_hero_box.add_child(pills_box)

	var features := [
		"🚕 Taxis, Ndiaga Ndiaye & Concession auto",
		"🤼 Lamb traditionnel, Arènes & Métiers urbains",
		"🥪 11 Restaurants Maïga & Vendeurs ambulants",
		"🏅 Célébration JOJ Dakar 2026 & Mbalax non-stop"
	]
	for feat in features:
		var pill := PanelContainer.new()
		var p_lbl := Label.new()
		p_lbl.text = feat
		p_lbl.add_theme_font_size_override("font_size", 12)
		_labels_list.append(p_lbl)
		pill.add_child(p_lbl)
		_feature_pills.append(pill)
		pills_box.add_child(pill)

	# Ligne statut serveur et bouton de thème large
	var hero_bottom_row := HBoxContainer.new()
	hero_bottom_row.add_theme_constant_override("separation", 10)
	_hero_box.add_child(hero_bottom_row)

	var live_indicator := Label.new()
	live_indicator.text = "🟢 Serveur officiel Dakar opérationnel"
	live_indicator.add_theme_font_size_override("font_size", 12)
	live_indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_labels_list.append(live_indicator)
	hero_bottom_row.add_child(live_indicator)

	_theme_btn = Button.new()
	_theme_btn.text = "☀️ Mode Clair" if not is_light_mode else "🌙 Mode Sombre"
	_theme_btn.custom_minimum_size = Vector2(140, 36)
	_theme_btn.add_theme_font_size_override("font_size", 13)
	_theme_btn.pressed.connect(toggle_theme)
	hero_bottom_row.add_child(_theme_btn)

	# =========================================================================
	# COLONNE DE DROITE : Carte du Formulaire d'Inscription / Connexion
	# =========================================================================
	_card_panel = PanelContainer.new()
	_card_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_master_container.add_child(_card_panel)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 18)
	card_margin.add_theme_constant_override("margin_right", 18)
	card_margin.add_theme_constant_override("margin_top", 18)
	card_margin.add_theme_constant_override("margin_bottom", 18)
	_card_panel.add_child(card_margin)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 10)
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_margin.add_child(_content_vbox)

	# En-tête compact (pour smartphones en mode portrait)
	_compact_header = VBoxContainer.new()
	_compact_header.add_theme_constant_override("separation", 4)
	_content_vbox.add_child(_compact_header)

	var compact_top_row := HBoxContainer.new()
	_compact_header.add_child(compact_top_row)

	var compact_title := Label.new()
	compact_title.text = "GALSEN-LIFE"
	compact_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	compact_title.add_theme_font_size_override("font_size", 28)
	compact_title.name = "CompactTitle"
	_labels_list.append(compact_title)
	compact_top_row.add_child(compact_title)

	_compact_theme_btn = Button.new()
	_compact_theme_btn.text = "☀️ Clair" if not is_light_mode else "🌙 Sombre"
	_compact_theme_btn.custom_minimum_size = Vector2(85, 32)
	_compact_theme_btn.add_theme_font_size_override("font_size", 12)
	_compact_theme_btn.pressed.connect(toggle_theme)
	compact_top_row.add_child(_compact_theme_btn)

	var compact_sub := Label.new()
	compact_sub.text = "🇸🇳 Dakar Open-World • Connexion & Inscription"
	compact_sub.add_theme_font_size_override("font_size", 13)
	_labels_list.append(compact_sub)
	_compact_header.add_child(compact_sub)

	# Configuration réseau et profil
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)

	_host = LineEdit.new()
	_host.text = str(cfg.get_value("net", "host", Net.DEFAULT_HOST))
	_host.visible = false
	_content_vbox.add_child(_host)

	_channel = OptionButton.new()
	for ch in Net.CHANNELS:
		_channel.add_item(ch["name"])
	var saved_chan: int = int(cfg.get_value("net", "channel_idx", 0))
	_channel.select(clampi(saved_chan, 0, Net.CHANNELS.size() - 1))
	_channel.visible = false
	_content_vbox.add_child(_channel)

	# Champs de saisie
	var saved_p: String = str(cfg.get_value("net", "pseudo", ""))
	var saved_pw: String = str(cfg.get_value("net", "password", ""))

	_pseudo = _field(_content_vbox, "Pseudo (ex: Moussa, Awa, Modou)", saved_p)

	_avatar = OptionButton.new()
	_avatar.custom_minimum_size = Vector2(0, 46)
	_avatar.add_theme_font_size_override("font_size", 15)
	for a in Net.AVATARS:
		_avatar.add_item(AVATAR_NAMES.get(a, a))
	_avatar.select(maxi(0, Net.AVATARS.find(cfg.get_value("net", "avatar", "heros"))))
	_content_vbox.add_child(_avatar)

	_customize_avatar_btn = Button.new()
	_customize_avatar_btn.text = "🎨 Personnaliser ce personnage avant de jouer"
	_customize_avatar_btn.custom_minimum_size = Vector2(0, 38)
	_customize_avatar_btn.add_theme_font_size_override("font_size", 13)
	_customize_avatar_btn.pressed.connect(func(): _open_studio(false))
	_content_vbox.add_child(_customize_avatar_btn)

	_password = _field(_content_vbox, "Mot de passe", saved_pw)
	_password.secret = true

	# Enchaînement naturel au clavier virtuel
	_pseudo.text_submitted.connect(func(_t): _password.grab_focus())
	_password.text_submitted.connect(func(_t): _on_connect())

	# Option créer un compte
	_create = CheckBox.new()
	_create.text = " Créer un compte"
	_create.custom_minimum_size = Vector2(0, 36)
	_create.add_theme_font_size_override("font_size", 15)
	_content_vbox.add_child(_create)

	# Actions principales
	var actions_box := VBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 8)
	_content_vbox.add_child(actions_box)

	_customize_on_start = CheckBox.new()
	_customize_on_start.text = " 🎨 Ouvrir le Studio 3D avant de lancer la partie"
	_customize_on_start.custom_minimum_size = Vector2(0, 34)
	_customize_on_start.add_theme_font_size_override("font_size", 14)
	_customize_on_start.button_pressed = bool(cfg.get_value("ui", "customize_on_start", false))
	_customize_on_start.toggled.connect(func(pressed: bool):
		var c := ConfigFile.new()
		c.load(SETTINGS)
		c.set_value("ui", "customize_on_start", pressed)
		c.save(SETTINGS)
	)
	actions_box.add_child(_customize_on_start)

	_connect_btn = Button.new()
	_connect_btn.text = "🌐 SE CONNECTER"
	_connect_btn.custom_minimum_size = Vector2(0, 48)
	_connect_btn.add_theme_font_size_override("font_size", 16)
	_connect_btn.pressed.connect(_on_connect)
	actions_box.add_child(_connect_btn)

	_offline_btn = Button.new()
	_offline_btn.text = "🎮 JOUER EN SOLO"
	_offline_btn.custom_minimum_size = Vector2(0, 48)
	_offline_btn.add_theme_font_size_override("font_size", 16)
	_offline_btn.pressed.connect(_start_offline)
	actions_box.add_child(_offline_btn)

	_studio_btn = Button.new()
	_studio_btn.text = "🎨 STUDIO PERSONNAGE (Personnaliser)"
	_studio_btn.custom_minimum_size = Vector2(0, 46)
	_studio_btn.add_theme_font_size_override("font_size", 15)
	_studio_btn.pressed.connect(_open_studio)
	actions_box.add_child(_studio_btn)

	_create.toggled.connect(func(pressed: bool):
		if pressed:
			_connect_btn.text = "🌐 CRÉER MON COMPTE"
		else:
			_connect_btn.text = "🌐 SE CONNECTER"
	)

	# Code ami repliable
	_friend_toggle_btn = Button.new()
	_friend_toggle_btn.text = "🤝 Code ami (optionnel)"
	_friend_toggle_btn.flat = true
	_friend_toggle_btn.custom_minimum_size = Vector2(0, 32)
	_friend_toggle_btn.add_theme_font_size_override("font_size", 13)
	_content_vbox.add_child(_friend_toggle_btn)

	var f_box := VBoxContainer.new()
	f_box.add_theme_constant_override("separation", 6)
	f_box.visible = false
	_content_vbox.add_child(f_box)

	_friend_toggle_btn.pressed.connect(func():
		f_box.visible = !f_box.visible
		if f_box.visible:
			_friend_toggle_btn.text = "🤝 Masquer code ami"
			call_deferred("_scroll_to_control", f_box)
		else:
			_friend_toggle_btn.text = "🤝 Code ami (optionnel)"
	)

	var f_row := HBoxContainer.new()
	f_row.add_theme_constant_override("separation", 6)
	f_box.add_child(f_row)

	_friend_code = _field(f_row, "Code d'un ami (ex: GAL-12345)", "")
	_friend_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_code.text_submitted.connect(func(_t): _on_connect())

	_paste_btn = Button.new()
	_paste_btn.text = "Coller"
	_paste_btn.custom_minimum_size = Vector2(70, 44)
	_paste_btn.add_theme_font_size_override("font_size", 13)
	_paste_btn.pressed.connect(func():
		var clip := DisplayServer.clipboard_get().strip_edges()
		if clip != "":
			_friend_code.text = clip
	)
	f_row.add_child(_paste_btn)

	var my_code_row := HBoxContainer.new()
	my_code_row.add_theme_constant_override("separation", 6)
	f_box.add_child(my_code_row)

	var init_p: String = cfg.get_value("net", "pseudo", "")
	var my_c_val := Net.generate_friend_code(init_p if init_p != "" else "Joueur")
	_my_code_label = Label.new()
	_my_code_label.text = "Mon code : %s" % my_c_val
	_my_code_label.add_theme_font_size_override("font_size", 12)
	_my_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_labels_list.append(_my_code_label)
	my_code_row.add_child(_my_code_label)

	_copy_my_code_btn = Button.new()
	_copy_my_code_btn.text = "Copier mon code"
	_copy_my_code_btn.custom_minimum_size = Vector2(130, 32)
	_copy_my_code_btn.add_theme_font_size_override("font_size", 12)
	_copy_my_code_btn.pressed.connect(func():
		var cur_p := _pseudo.text.strip_edges()
		var c := Net.generate_friend_code(cur_p if cur_p != "" else "Joueur")
		DisplayServer.clipboard_set(c)
		_status.text = "Code ami %s copié !" % c
	)
	my_code_row.add_child(_copy_my_code_btn)

	_pseudo.text_changed.connect(func(new_p: String):
		var c := Net.generate_friend_code(new_p.strip_edges() if new_p.strip_edges() != "" else "Joueur")
		_my_code_label.text = "Mon code : %s" % c
	)

	# Statut
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_labels_list.append(_status)
	_content_vbox.add_child(_status)

	if saved_p == "":
		_create.button_pressed = true
		_connect_btn.text = "🌐 CRÉER MON COMPTE"
	else:
		_create.button_pressed = false

	# Bouton de secours solo
	_offline_fallback_btn = Button.new()
	_offline_fallback_btn.text = "🎮 Continuer en Solo"
	_offline_fallback_btn.custom_minimum_size = Vector2(0, 44)
	_offline_fallback_btn.add_theme_font_size_override("font_size", 15)
	_offline_fallback_btn.pressed.connect(_start_offline)
	_offline_fallback_btn.visible = false
	_content_vbox.add_child(_offline_fallback_btn)

	# Crédits
	_credits_btn = Button.new()
	_credits_btn.text = "Crédits & Mentions"
	_credits_btn.flat = true
	_credits_btn.custom_minimum_size = Vector2(0, 30)
	_credits_btn.add_theme_font_size_override("font_size", 12)
	_credits_btn.pressed.connect(_show_credits)
	_content_vbox.add_child(_credits_btn)


## Bascule interactive entre le Mode Clair et le Mode Sombre
func toggle_theme() -> void:
	is_light_mode = !is_light_mode
	if has_node("/root/GameState"):
		get_node("/root/GameState").light_mode = is_light_mode
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value("ui", "light_mode", is_light_mode)
	cfg.save(SETTINGS)
	apply_theme()


## Applique les styles clairs ou sombres à tous les éléments de l'interface
func apply_theme() -> void:
	# 1. Palette de couleurs
	var col_bg := Color("f4f6fa") if is_light_mode else Color("0e1217")
	var col_card_bg := Color("ffffff") if is_light_mode else Color(0.11, 0.14, 0.19, 0.96)
	var col_card_border := Color("cbd5e1") if is_light_mode else Color(0.25, 0.33, 0.44, 0.7)
	var col_field_bg := Color("f8fafc") if is_light_mode else Color(0.12, 0.16, 0.22, 0.95)
	var col_field_border := Color("cbd5e1") if is_light_mode else Color(0.28, 0.36, 0.48, 0.8)
	var col_field_focus := Color("059669") if is_light_mode else Color("7cfc9a")
	var col_text := Color("0f172a") if is_light_mode else Color.WHITE
	var col_sub := Color("475569") if is_light_mode else Color(0.65, 0.75, 0.85)
	var col_gold := Color("b45309") if is_light_mode else Color("fdef42")
	var col_status := Color("b45309") if is_light_mode else Color("ffd166")
	var col_pill_bg := Color(0.92, 0.95, 0.98, 0.9) if is_light_mode else Color(0.14, 0.18, 0.24, 0.8)
	var col_pill_border := Color("cbd5e1") if is_light_mode else Color(0.25, 0.32, 0.42, 0.6)

	if _bg:
		_bg.color = col_bg
	if _bg_overlay:
		_bg_overlay.color = Color(0.96, 0.97, 0.99, 0.82) if is_light_mode else Color(0.06, 0.08, 0.12, 0.84)

	# 2. Carte formulaire
	if _card_panel:
		var card_st := StyleBoxFlat.new()
		card_st.bg_color = col_card_bg
		card_st.border_color = col_card_border
		card_st.border_width_left = 1
		card_st.border_width_top = 1
		card_st.border_width_right = 1
		card_st.border_width_bottom = 1
		card_st.corner_radius_top_left = 14
		card_st.corner_radius_top_right = 14
		card_st.corner_radius_bottom_right = 14
		card_st.corner_radius_bottom_left = 14
		card_st.shadow_color = Color(0.1, 0.15, 0.25, 0.08) if is_light_mode else Color(0, 0, 0, 0.4)
		card_st.shadow_size = 8
		_card_panel.add_theme_stylebox_override("panel", card_st)

	# 3. Champs de saisie
	var field_st := StyleBoxFlat.new()
	field_st.bg_color = col_field_bg
	field_st.border_color = col_field_border
	field_st.border_width_left = 1
	field_st.border_width_top = 1
	field_st.border_width_right = 1
	field_st.border_width_bottom = 1
	field_st.corner_radius_top_left = 8
	field_st.corner_radius_top_right = 8
	field_st.corner_radius_bottom_right = 8
	field_st.corner_radius_bottom_left = 8
	field_st.content_margin_left = 12.0
	field_st.content_margin_right = 12.0

	var field_focus_st := field_st.duplicate() as StyleBoxFlat
	field_focus_st.border_color = col_field_focus
	field_focus_st.border_width_left = 2
	field_focus_st.border_width_top = 2
	field_focus_st.border_width_right = 2
	field_focus_st.border_width_bottom = 2

	for f in _fields_list:
		if is_instance_valid(f):
			f.add_theme_stylebox_override("normal", field_st)
			f.add_theme_stylebox_override("focus", field_focus_st)
			f.add_theme_color_override("font_color", col_text)
			f.add_theme_color_override("font_placeholder_color", Color("94a3b8") if is_light_mode else Color(0.55, 0.65, 0.75))

	if _avatar and is_instance_valid(_avatar):
		_avatar.add_theme_stylebox_override("normal", field_st)
		_avatar.add_theme_color_override("font_color", col_text)

	# 4. Boutons d'action
	var solo_st := StyleBoxFlat.new()
	solo_st.bg_color = Color("15803d") if is_light_mode else Color(0.10, 0.32, 0.22, 0.95)
	solo_st.border_color = Color("166534") if is_light_mode else Color("7cfc9a")
	solo_st.border_width_left = 2
	solo_st.border_width_top = 2
	solo_st.border_width_right = 2
	solo_st.border_width_bottom = 2
	solo_st.corner_radius_top_left = 8
	solo_st.corner_radius_top_right = 8
	solo_st.corner_radius_bottom_right = 8
	solo_st.corner_radius_bottom_left = 8

	if _offline_btn and is_instance_valid(_offline_btn):
		_offline_btn.add_theme_stylebox_override("normal", solo_st)
		_offline_btn.add_theme_stylebox_override("hover", solo_st)
		_offline_btn.add_theme_color_override("font_color", Color.WHITE)

	if _offline_fallback_btn and is_instance_valid(_offline_fallback_btn):
		_offline_fallback_btn.add_theme_stylebox_override("normal", solo_st)
		_offline_fallback_btn.add_theme_stylebox_override("hover", solo_st)
		_offline_fallback_btn.add_theme_color_override("font_color", Color.WHITE)

	var connect_st := StyleBoxFlat.new()
	connect_st.bg_color = Color("2563eb") if is_light_mode else Color(0.18, 0.24, 0.35, 0.95)
	connect_st.border_color = Color("1d4ed8") if is_light_mode else Color("90e0ef")
	connect_st.border_width_left = 2
	connect_st.border_width_top = 2
	connect_st.border_width_right = 2
	connect_st.border_width_bottom = 2
	connect_st.corner_radius_top_left = 8
	connect_st.corner_radius_top_right = 8
	connect_st.corner_radius_bottom_right = 8
	connect_st.corner_radius_bottom_left = 8

	if _connect_btn and is_instance_valid(_connect_btn):
		_connect_btn.add_theme_stylebox_override("normal", connect_st)
		_connect_btn.add_theme_stylebox_override("hover", connect_st)
		_connect_btn.add_theme_color_override("font_color", Color.WHITE)

	var studio_st := StyleBoxFlat.new()
	studio_st.bg_color = Color("c9a227").darkened(0.2) if is_light_mode else Color(0.28, 0.22, 0.08, 0.95)
	studio_st.border_color = Color("ffd166")
	studio_st.set_border_width_all(2)
	studio_st.set_corner_radius_all(8)
	if _studio_btn and is_instance_valid(_studio_btn):
		_studio_btn.add_theme_stylebox_override("normal", studio_st)
		_studio_btn.add_theme_stylebox_override("hover", studio_st)
		_studio_btn.add_theme_color_override("font_color", Color.WHITE)

	if _customize_avatar_btn and is_instance_valid(_customize_avatar_btn):
		_customize_avatar_btn.add_theme_stylebox_override("normal", studio_st)
		_customize_avatar_btn.add_theme_stylebox_override("hover", studio_st)
		_customize_avatar_btn.add_theme_color_override("font_color", Color.WHITE)

	if _customize_on_start and is_instance_valid(_customize_on_start):
		_customize_on_start.add_theme_color_override("font_color", col_text)
		_customize_on_start.add_theme_color_override("font_pressed_color", col_field_focus)

	# 5. Boutons de bascule de thème
	var theme_st := StyleBoxFlat.new()
	theme_st.bg_color = Color("e2e8f0") if is_light_mode else Color(0.18, 0.22, 0.29, 0.9)
	theme_st.border_color = Color("cbd5e1") if is_light_mode else Color(0.35, 0.42, 0.52, 0.8)
	theme_st.border_width_left = 1
	theme_st.border_width_top = 1
	theme_st.border_width_right = 1
	theme_st.border_width_bottom = 1
	theme_st.corner_radius_top_left = 6
	theme_st.corner_radius_top_right = 6
	theme_st.corner_radius_bottom_right = 6
	theme_st.corner_radius_bottom_left = 6

	if _theme_btn and is_instance_valid(_theme_btn):
		_theme_btn.text = "🌙 Mode Sombre" if is_light_mode else "☀️ Mode Clair"
		_theme_btn.add_theme_stylebox_override("normal", theme_st)
		_theme_btn.add_theme_stylebox_override("hover", theme_st)
		_theme_btn.add_theme_color_override("font_color", col_text)

	if _compact_theme_btn and is_instance_valid(_compact_theme_btn):
		_compact_theme_btn.text = "🌙 Sombre" if is_light_mode else "☀️ Clair"
		_compact_theme_btn.add_theme_stylebox_override("normal", theme_st)
		_compact_theme_btn.add_theme_stylebox_override("hover", theme_st)
		_compact_theme_btn.add_theme_color_override("font_color", col_text)

	# 6. Checkbox & Status
	if _create and is_instance_valid(_create):
		_create.add_theme_color_override("font_color", col_text)
		_create.add_theme_color_override("font_pressed_color", col_field_focus)

	if _status and is_instance_valid(_status):
		_status.add_theme_color_override("font_color", col_status)

	if _credits_btn and is_instance_valid(_credits_btn):
		_credits_btn.add_theme_color_override("font_color", col_sub)

	if _friend_toggle_btn and is_instance_valid(_friend_toggle_btn):
		_friend_toggle_btn.add_theme_color_override("font_color", col_sub)

	if _my_code_label and is_instance_valid(_my_code_label):
		_my_code_label.add_theme_color_override("font_color", col_gold)

	# 7. Pilules de fonctionnalités
	var pill_st := StyleBoxFlat.new()
	pill_st.bg_color = col_pill_bg
	pill_st.border_color = col_pill_border
	pill_st.border_width_left = 1
	pill_st.border_width_top = 1
	pill_st.border_width_right = 1
	pill_st.border_width_bottom = 1
	pill_st.corner_radius_top_left = 6
	pill_st.corner_radius_top_right = 6
	pill_st.corner_radius_bottom_right = 6
	pill_st.corner_radius_bottom_left = 6
	pill_st.content_margin_left = 8.0
	pill_st.content_margin_right = 8.0
	pill_st.content_margin_top = 4.0
	pill_st.content_margin_bottom = 4.0

	for p in _feature_pills:
		if is_instance_valid(p):
			p.add_theme_stylebox_override("panel", pill_st)

	# 8. Titres & Textes
	for l in _labels_list:
		if is_instance_valid(l):
			if l.name == "HeroTitle" or l.name == "CompactTitle":
				l.add_theme_color_override("font_color", col_gold)
			elif l == _status:
				l.add_theme_color_override("font_color", col_status)
			elif l == _my_code_label:
				l.add_theme_color_override("font_color", col_gold)
			else:
				l.add_theme_color_override("font_color", col_sub)


func _scroll_to_control(c: Control) -> void:
	if not c or not is_instance_valid(c) or not _scroll or not is_instance_valid(_scroll):
		return
	await get_tree().create_timer(0.06).timeout
	if not is_instance_valid(c) or not is_instance_valid(_scroll):
		return
	var c_y := c.global_position.y
	var s_y := _scroll.global_position.y
	var s_h := _scroll.size.y
	var rel_y := c_y - s_y
	if rel_y < 20.0 or rel_y > s_h - c.size.y - 20.0:
		var target := _scroll.scroll_vertical + int(rel_y - (s_h * 0.35))
		_scroll.scroll_vertical = clampi(target, 0, 3000)


## Crédits des modèles sous licence CC BY (obligatoires) — détail dans vehicles/CREDITS.md
func _show_credits() -> void:
	var d := AcceptDialog.new()
	d.title = "Crédits"
	d.dialog_text = """Carte : © les contributeurs OpenStreetMap (ODbL).
Animations et premiers véhicules : Quaternius (CC0).
Mobilier : Poly Haven (CC0). Textures : ambientCG (CC0).

Véhicules (Sketchfab, CC BY 4.0 sauf mention) :
• Car Rapide – Iconic Senegal Public Transport : KidBi-Gaming
• Ndiaga Niaye low poly, Bus Tata : gamehubgamehubsenegal
• 1968 BMW 2002 : tonielpro520
• PS1 Police Car - Chevrolet Caprice 1978 : zufari4
• yamaha dt 125 repainted : EmanuelRestrepoVelez
• 2013 Chevrolet Caprice Highway Patrol : ActsOfDoge (licence standard)
Intérieurs (Sketchfab) : free Loft 17 (CC BY 4.0) et Super market for free (licence standard) : dasy444
Personnages (Sketchfab) : Black girl avatar (CC BY 4.0) : norrellewalker ; Low Poly Girl (CC BY 4.0) : manoeldarochadeoliveira ;
Indian Woman in Saree (licence standard) : Pixel_Monster ;
Rigged Female Character in Blue Ruffle Dress (CC BY 4.0) : florah
Port : texture des conteneurs tirée de « Road » (Sketchfab, CC BY 4.0) : aesre938
Modèles adaptés pour le jeu. creativecommons.org/licenses/by/4.0"""
	add_child(d)
	d.popup_centered()


func _field(parent: Control, placeholder: String, value: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.custom_minimum_size = Vector2(0, 46)
	e.add_theme_font_size_override("font_size", 15)
	_fields_list.append(e)
	e.focus_entered.connect(func():
		call_deferred("_scroll_to_control", e)
	)
	parent.add_child(e)
	return e


func _on_connect() -> void:
	_pseudo.text = _pseudo.text.strip_edges()
	_password.text = _password.text.strip_edges()
	if _pseudo.text.length() < 3 or _password.text.length() < 4:
		_status.text = "Pseudo (min 3 car.) et mot de passe (min 4 car.) requis."
		return

	# Connexion automatique des tests (--online=...) : on ne touche pas aux réglages du joueur
	var from_test := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--online="):
			from_test = true

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var ch_idx: int = _channel.selected if _channel else 0
	var ch: Dictionary = Net.CHANNELS[clampi(ch_idx, 0, Net.CHANNELS.size() - 1)]
	var target_port: int = int(ch.get("port", Net.PORT))
	var target_host: String = _host.text.strip_edges()
	if target_host == "" or target_host == Net.DEFAULT_HOST:
		target_host = str(ch.get("host", Net.DEFAULT_HOST))

	if not from_test:
		cfg.set_value("net", "host", target_host)
		cfg.set_value("net", "pseudo", _pseudo.text)
		cfg.set_value("net", "password", _password.text)
		cfg.set_value("net", "avatar", Net.AVATARS[_avatar.selected])
		cfg.set_value("net", "channel_idx", ch_idx)
		cfg.set_value("ui", "light_mode", is_light_mode)
		cfg.save(SETTINGS)

	if _friend_code and _friend_code.text.strip_edges() != "":
		Net.pending_friend_join_code = _friend_code.text.strip_edges().to_upper()

	_connect_btn.disabled = true
	_status.text = "Connexion..."
	if _offline_fallback_btn:
		_offline_fallback_btn.visible = false

	# Sécurité timeout connexion (7s) : réactive le bouton si le serveur met du temps à répondre
	var conn_timer := get_tree().create_timer(7.0)
	conn_timer.timeout.connect(func():
		if not Net.online and _connect_btn and is_instance_valid(_connect_btn) and _connect_btn.disabled:
			_connect_btn.disabled = false
			_status.text = "Serveur injoignable pour l'instant. Joue en solo !"
			if _offline_fallback_btn and is_instance_valid(_offline_fallback_btn):
				_offline_fallback_btn.visible = true
	)

	Net.connect_and_login(target_host, _pseudo.text, _password.text, Net.AVATARS[_avatar.selected], _create.button_pressed, target_port)


func _on_login(ok: bool, message: String) -> void:
	_status.text = message
	_connect_btn.disabled = false
	if not ok:
		if _offline_fallback_btn and is_instance_valid(_offline_fallback_btn):
			_offline_fallback_btn.visible = true
		if "Compte inconnu" in message or "inconnu" in message:
			_create.button_pressed = true
			_status.text = "Compte introuvable. Touche « Créer mon compte »."
		elif "déjà pris" in message and _create.button_pressed:
			_create.button_pressed = false
			_status.text = "Ce compte existe déjà. Touche « Se connecter »."
		elif "déjà connecté" in message:
			_status.text = "Session en cours de déconnexion. Réessaie."
		elif "Mot de passe incorrect" in message:
			_status.text = "Mot de passe incorrect."
	if ok:
		Audio.stop_music()
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("net", "pseudo", _pseudo.text.strip_edges())
		cfg.set_value("net", "password", _password.text.strip_edges())
		cfg.set_value("ui", "light_mode", is_light_mode)
		cfg.save(SETTINGS)
		get_tree().change_scene_to_file(MAIN)


func _start_offline() -> void:
	if _customize_on_start and _customize_on_start.button_pressed:
		_open_studio(true)
		return

	Audio.stop_music()
	var chosen_p: String = _pseudo.text.strip_edges() if _pseudo else ""
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	if chosen_p == "":
		chosen_p = str(cfg.get_value("net", "pseudo", "Galsenois"))
	if chosen_p == "":
		chosen_p = "Galsenois"
	var chosen_av: String = Net.AVATARS[_avatar.selected] if _avatar else str(cfg.get_value("net", "avatar", "heros"))

	cfg.set_value("net", "pseudo", chosen_p)
	cfg.set_value("net", "avatar", chosen_av)
	cfg.set_value("ui", "light_mode", is_light_mode)
	cfg.save(SETTINGS)

	Net.start_offline(chosen_p, chosen_av)
	get_tree().change_scene_to_file(MAIN)


func _open_studio(auto_launch: bool = false) -> void:
	var CharacterStudioScript = load("res://scripts/ui/character_studio.gd")
	var chosen_av: String = Net.AVATARS[_avatar.selected] if _avatar else ""
	var studio = CharacterStudioScript.new(chosen_av, auto_launch)
	add_child(studio)
	studio.closed.connect(func(saved: bool):
		if saved:
			var idx := Net.AVATARS.find(Net.avatar)
			if idx != -1 and _avatar:
				_avatar.select(idx)
	)
