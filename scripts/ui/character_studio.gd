extends Control
## Studio de Personnalisation 3D du Personnage (Galsen Life)
## Permet d'éditer son avatar en temps réel sous un éclairage studio 3 points :
## - Modèle 3D, Teint de peau sénégalais, Coiffure & Couleur, Haut, Bas, Chapeau
## - Caméra orbitale 360°, zoom visage/buste/corps entier, et prévisualisation des animations

const Outfits = preload("res://scripts/util/outfits.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

signal closed(saved: bool)

var current_avatar: String = "heros"
var current_outfit: String = ""
var initial_avatar: String = "heros"
var initial_outfit: String = ""

# Éléments 3D du Studio
var _subview_container: SubViewportContainer
var _subview: SubViewport
var _world: World3D
var _camera: Camera3D
var _character_holder: Node3D
var _character_model: Node3D
var _pedestal: MeshInstance3D

# Contrôle caméra orbitale
var _cam_yaw: float = 0.0
var _cam_pitch: float = 0.05
var _cam_dist: float = 2.4
var _cam_target_y: float = 0.95
var _is_dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

# Interface utilisateur
var _category_tabs: HBoxContainer
var _options_container: VBoxContainer
var _scroll_container: ScrollContainer
var _active_category: String = "avatar"

const AVATAR_NAMES := {
	"heros": "Héros Dakarois (Polo & Rayures)",
	"homme_ville": "Citadin (Chemise casual)",
	"homme_afro": "Jeune Dakarois (Afro & T-shirt)",
	"homme_tunique": "Élégant (Tunique sénégalaise)",
	"femme_robe": "Sénégalaise (Robe wax traditionnelle)",
	"femme_jupe": "Dakarise (Jupe élégante)",
	"femme_ville": "Citadine (Chemisier & Pantalon)",
	"femme_maman": "Mère de famille (Boubou ample)",
}


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	focus_mode = Control.FOCUS_ALL

	# Fond studio moderne sombre avec halo chaleureux
	var bg := ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color("0d1117")
	add_child(bg)

	_setup_3d_studio()
	_setup_ui()

	# Initialiser depuis GameState et Net
	initial_avatar = Net.avatar if Net.avatar != "" else "heros"
	initial_outfit = GameState.tenue
	current_avatar = initial_avatar
	current_outfit = initial_outfit

	_load_character_preview()
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
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("10141c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("3a404d")
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.08
	_camera = Camera3D.new()
	_camera.environment = env
	_camera.current = true
	_camera.fov = 38.0
	_subview.add_child(_camera)

	# Éclairage 3 points Studio Pro :
	# 1. Key Light (Soleil chaud dakarois)
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color("fff5ea")
	key_light.light_energy = 1.4
	key_light.rotation_degrees = Vector3(-25, 40, 0)
	key_light.shadow_enabled = true
	_subview.add_child(key_light)

	# 2. Fill Light (Débouchage doux ciel bleuté)
	var fill_light := DirectionalLight3D.new()
	fill_light.light_color = Color("9ec5e8")
	fill_light.light_energy = 0.55
	fill_light.rotation_degrees = Vector3(-15, -120, 0)
	_subview.add_child(fill_light)

	# 3. Rim / Hair Light (Lumière de contour dorée)
	var rim_light := OmniLight3D.new()
	rim_light.light_color = Color("ffd166")
	rim_light.light_energy = 2.2
	rim_light.omni_range = 6.0
	rim_light.position = Vector3(0, 2.2, -1.8)
	_subview.add_child(rim_light)

	# Piédestal studio avec disque d'ombre doux
	_pedestal = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.15
	cyl.bottom_radius = 1.25
	cyl.height = 0.06
	_pedestal.mesh = cyl
	var p_mat := StandardMaterial3D.new()
	p_mat.albedo_color = Color("1e232d")
	p_mat.roughness = 0.4
	p_mat.metallic_specular = 0.3
	_pedestal.material_override = p_mat
	_pedestal.position = Vector3(0, -0.03, 0)
	_subview.add_child(_pedestal)

	# Nœud hôte du personnage
	_character_holder = Node3D.new()
	_subview.add_child(_character_holder)

	_update_camera_transform()


func _setup_ui() -> void:
	# Conteneur principal superposé
	var main_ui := Control.new()
	main_ui.anchor_right = 1.0
	main_ui.anchor_bottom = 1.0
	main_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_ui)

	# En-tête du Studio
	var header := PanelContainer.new()
	header.anchor_right = 1.0
	header.custom_minimum_size = Vector2(0, 64)
	var h_st := StyleBoxFlat.new()
	h_st.bg_color = Color(0.06, 0.08, 0.12, 0.88)
	h_st.border_width_bottom = 2
	h_st.border_color = Color("ffd166")
	h_st.content_margin_left = 20
	h_st.content_margin_right = 20
	header.add_theme_stylebox_override("panel", h_st)
	main_ui.add_child(header)

	var h_box := HBoxContainer.new()
	header.add_child(h_box)

	var title_lbl := Label.new()
	title_lbl.text = "🎨 STUDIO DAKAR — PERSONNALISATION PERSONNAGE"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color("ffd166"))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_box.add_child(title_lbl)

	# Panneau latéral droit d'édition
	var side_panel := PanelContainer.new()
	side_panel.anchor_left = 0.62
	side_panel.anchor_right = 0.98
	side_panel.anchor_top = 0.11
	side_panel.anchor_bottom = 0.96
	var p_st := StyleBoxFlat.new()
	p_st.bg_color = Color(0.08, 0.10, 0.15, 0.94)
	p_st.border_color = Color("2f3846")
	p_st.set_border_width_all(2)
	p_st.set_corner_radius_all(14)
	p_st.content_margin_left = 16
	p_st.content_margin_right = 16
	p_st.content_margin_top = 16
	p_st.content_margin_bottom = 16
	side_panel.add_theme_stylebox_override("panel", p_st)
	main_ui.add_child(side_panel)

	var side_vbox := VBoxContainer.new()
	side_vbox.add_theme_constant_override("separation", 10)
	side_panel.add_child(side_vbox)

	# Onglets de catégories (défilant si écran étroit)
	var cat_scroll := ScrollContainer.new()
	cat_scroll.custom_minimum_size = Vector2(0, 46)
	cat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	cat_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_vbox.add_child(cat_scroll)

	_category_tabs = HBoxContainer.new()
	_category_tabs.add_theme_constant_override("separation", 6)
	cat_scroll.add_child(_category_tabs)

	var categories := [
		["avatar", "👤 Modèle"],
		["teint", "🏾 Teint"],
		["coiffure", "✂️ Coiffure"],
		["couleur", "🎨 Cheveux"],
		["haut", "👕 Haut"],
		["bas", "👖 Bas"],
		["chapeau", "🧢 Chapeau"],
		["studio", "🎬 Studio & Poses"],
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
	rand_btn.custom_minimum_size = Vector2(95, 42)
	rand_btn.pressed.connect(_randomize_look)
	act_box.add_child(rand_btn)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 Reset"
	reset_btn.custom_minimum_size = Vector2(75, 42)
	reset_btn.pressed.connect(_reset_look)
	act_box.add_child(reset_btn)

	var save_btn := Button.new()
	save_btn.text = "💾 VALIDER"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 42)
	var s_st := StyleBoxFlat.new()
	s_st.bg_color = Color("00853f")
	s_st.set_corner_radius_all(8)
	save_btn.add_theme_stylebox_override("normal", s_st)
	save_btn.pressed.connect(_save_and_close)
	act_box.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(42, 42)
	close_btn.pressed.connect(_cancel_and_close)
	act_box.add_child(close_btn)

	# Contrôles de rotation et zoom caméra sur la gauche
	var cam_ctrls := VBoxContainer.new()
	cam_ctrls.anchor_left = 0.03
	cam_ctrls.anchor_top = 0.78
	cam_ctrls.add_theme_constant_override("separation", 6)
	main_ui.add_child(cam_ctrls)

	var hint_lbl := Label.new()
	hint_lbl.text = "Glisser : Tourner le personnage\nMolette / Zoom : Vue Visage / Corps"
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", Color("a0aab8"))
	cam_ctrls.add_child(hint_lbl)

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
	btn_body.text = "🧍 Corps Entier"
	btn_body.pressed.connect(_set_camera_view.bind(2.4, 0.95))
	zoom_box.add_child(btn_body)


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
	# Nettoyer les anciennes options
	for ch in _options_container.get_children():
		ch.queue_free()

	# Mettre en surbrillance l'onglet actif
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
	desc.text = "Choisis le modèle de base réaliste de ton citoyen :"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_container.add_child(desc)

	for av_id in Net.AVATARS:
		var btn := Button.new()
		var is_selected: bool = (av_id == current_avatar)
		btn.text = ("✓ " if is_selected else "") + AVATAR_NAMES.get(av_id, av_id)
		btn.custom_minimum_size = Vector2(0, 44)
		if is_selected:
			var sel_st := StyleBoxFlat.new()
			sel_st.bg_color = Color("234236")
			sel_st.border_color = Color("00853f")
			sel_st.set_border_width_all(2)
			sel_st.set_corner_radius_all(8)
			btn.add_theme_stylebox_override("normal", sel_st)
		btn.pressed.connect(func():
			current_avatar = av_id
			_load_character_preview()
			_switch_category("avatar")
		)
		_options_container.add_child(btn)


func _build_skin_tone_options() -> void:
	var p := Outfits.parse(current_outfit)
	var cur_tone: String = p[5] if p.size() > 5 else ""

	var desc := Label.new()
	desc.text = "Carnation et teint épidermique du personnage :"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_container.add_child(desc)

	# Option teint d'origine du modèle
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


func _build_outfit_part_options(part_idx: int, title: String) -> void:
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
	desc.text = "Anime ton personnage dans le studio pour valider le rendu physique de ses mouvements :"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_container.add_child(desc)

	var poses := [
		["idle", "🧘 Pose d'attente (Respiration naturelle)"],
		["wave", "👋 Saluer"],
		["arms_crossed", "💪 Bras croisés"],
		["dance", "💃 Danse festive"],
		["dua", "🤲 Prière (Dua)"],
		["talk", "🗣️ Discussion animée"],
		["sit", "🪑 S'asseoir"],
	]
	for p in poses:
		var btn := Button.new()
		btn.text = p[1]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.pressed.connect(func():
			if _character_model and _character_model.has_method("play_clip"):
				_character_model.play_clip(p[0], 0.2)
		)
		_options_container.add_child(btn)


func _randomize_look() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	current_avatar = Net.AVATARS[rng.randi() % Net.AVATARS.size()]
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

	# Mettre à jour le fichier de configuration local
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("net", "avatar", current_avatar)
	cfg.save("user://settings.cfg")
	GameState.save_game()

	# Mettre à jour le joueur réel dans le monde s'il existe
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
