extends CanvasLayer
## Interface : argent, santé, satiété, heure, quartier, objectif, notifications, pause, écran titre.

const TouchControls = preload("res://scripts/ui/touch_controls.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const MapScreen = preload("res://scripts/ui/map_screen.gd")
const Phone = preload("res://scripts/ui/phone.gd")
const EmoteMenu = preload("res://scripts/ui/emote_menu.gd")
const TEX_MIC_ON := preload("res://textures/ui/mic_on.svg")
const TEX_MIC_MUTED := preload("res://textures/ui/mic_muted.svg")

var main
var _money: Label
var _health: ProgressBar
var _hunger: ProgressBar
var _thirst: ProgressBar
var _energy: ProgressBar
var _clock: Label
var _district: Label
var _speed: Label
var _objective: Label
var _police: Label
var _stars: Control
var _minimap
var _prompt_panel: PanelContainer
var _prompt: Label
var _notes: VBoxContainer
var _pause: Control
var _stats: Label
var _intro: Control
var _tut_btn: Button
var _pause_main: Control ## panneau principal de la pause
var _touch_menu: Control ## sous-menu « Commandes tactiles »
var _layout_bar: Control ## barre du mode « Placer les boutons »
var _touch
var _root: Control
var _choices: Control
var _choices_on_cancel: Callable
var map_screen
var _online: Label
var _chat_log: VBoxContainer
var _chat_log_panel: PanelContainer
var _chat_panel: PanelContainer
var _chat_input: LineEdit
var _chat_btn: Button
var _chat_channel := "local"
var _channel_btns := {}
var _services_btn: Button
var _phone_btn: Button
var _mic_btn: Button
var _hud_t := 0.0
var preview_online := false ## test : affiche les boutons du mode en ligne hors connexion
var _radio_btn: Button
var _talk_label: Label
var _voice_dock: HBoxContainer
var _voice_dock_btn: Button
var _radio_dock_btn: Button
var _talk_banner: PanelContainer
var _talk_banner_label: Label
var _mic_down_time := 0.0
var _mic_locked := false
var _radio_down_time := 0.0
var _radio_locked := false
var phone
var emote_menu ## menu GESTES (saluer, danser...)

var _gauges_panel: PanelContainer
var _tr: VBoxContainer
var _top_row: HBoxContainer
var _map_btn: Button
var _pause_btn: Button
var _emote_btn: Button
var _bottom_center: CenterContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	Net.account_deleted.connect(_on_account_deleted)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_root = root

	_touch = TouchControls.new()
	root.add_child(_touch)
	_touch.visible = GameState.touch_ui

	# Haut gauche : argent et jauges
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.45)))
	panel.position = Vector2(16, 16)
	root.add_child(panel)
	_gauges_panel = panel
	var v := VBoxContainer.new()
	panel.add_child(v)
	_money = _label(22, Color("7cfc9a"))
	v.add_child(_money)
	_health = _bar(Color("e63946"))
	v.add_child(_row("Santé", _health))
	_hunger = _bar(Color("f4a261"))
	v.add_child(_row("Satiété", _hunger))
	_thirst = _bar(Color("4cc9f0"))
	v.add_child(_row("Soif", _thirst))
	_energy = _bar(Color("ffd166"))
	v.add_child(_row("Énergie", _energy))
	_stars = Control.new()
	_stars.custom_minimum_size = Vector2(110, 18)
	_stars.draw.connect(_draw_stars)
	v.add_child(_stars)
	_online = _label(13, Color("7cfc9a"))
	_online.visible = Net.online
	v.add_child(_online)

	# Dock vocal dédié (ultra-accessible et très visible pour mobile & PC)
	_voice_dock = HBoxContainer.new()
	_voice_dock.position = Vector2(16, 172)
	_voice_dock.add_theme_constant_override("separation", 8)
	_voice_dock.visible = Net.online or preview_online
	root.add_child(_voice_dock)

	_voice_dock_btn = Button.new()
	_voice_dock_btn.icon = TEX_MIC_MUTED
	_voice_dock_btn.text = " COUPÉ"
	_voice_dock_btn.expand_icon = true
	_voice_dock_btn.add_theme_constant_override("icon_max_width", 26)
	_voice_dock_btn.custom_minimum_size = Vector2(136, 44)
	_voice_dock_btn.add_theme_font_size_override("font_size", 13)
	_voice_dock_btn.focus_mode = Control.FOCUS_NONE
	_style_voice_btn(_voice_dock_btn, false, "local")
	_voice_dock_btn.button_down.connect(_on_mic_press_down)
	_voice_dock_btn.button_up.connect(_on_mic_press_up)
	_voice_dock.add_child(_voice_dock_btn)

	_radio_dock_btn = Button.new()
	_radio_dock_btn.text = "📻 RADIO"
	_radio_dock_btn.custom_minimum_size = Vector2(110, 44)
	_radio_dock_btn.add_theme_font_size_override("font_size", 14)
	_radio_dock_btn.focus_mode = Control.FOCUS_NONE
	_style_voice_btn(_radio_dock_btn, false, "group")
	_radio_dock_btn.button_down.connect(_on_radio_press_down)
	_radio_dock_btn.button_up.connect(_on_radio_press_up)
	_radio_dock_btn.visible = Net.online and Net.social.my_group != ""
	_voice_dock.add_child(_radio_dock_btn)

	# Bannière dynamique au centre de l'écran quand on parle
	_talk_banner = PanelContainer.new()
	_talk_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_talk_banner.offset_left = 220
	_talk_banner.offset_right = -220
	_talk_banner.offset_top = 16
	_talk_banner.offset_bottom = 54
	_talk_banner.visible = false
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.06, 0.35, 0.18, 0.95)
	tsb.border_color = Color("7cfc9a")
	tsb.set_border_width_all(2)
	tsb.set_corner_radius_all(10)
	tsb.content_margin_left = 12
	tsb.content_margin_right = 12
	_talk_banner.add_theme_stylebox_override("panel", tsb)
	_talk_banner_label = _label(14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_talk_banner_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_talk_banner.add_child(_talk_banner_label)
	_talk_banner.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			if main.voice:
				main.voice.stop_talking()
			_mic_locked = false
			_radio_locked = false
	)
	root.add_child(_talk_banner)

	# Haut droite : pause, heure, quartier, vitesse
	var tr := VBoxContainer.new()
	tr.custom_minimum_size = Vector2(150, 0)
	tr.add_theme_constant_override("separation", 3)
	root.add_child(tr)
	tr.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	tr.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tr = tr
	var pause_btn := Button.new()
	pause_btn.text = "  II  "
	pause_btn.custom_minimum_size = Vector2(0, 38)
	pause_btn.add_theme_font_size_override("font_size", 14)
	pause_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.pressed.connect(toggle_pause)
	_pause_btn = pause_btn
	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_END
	top_row.add_theme_constant_override("separation", 5)
	tr.add_child(top_row)
	_top_row = top_row
	var map_btn := Button.new()
	map_btn.text = " CARTE "
	map_btn.custom_minimum_size = Vector2(0, 38)
	map_btn.add_theme_font_size_override("font_size", 14)
	map_btn.focus_mode = Control.FOCUS_NONE
	map_btn.pressed.connect(open_map)
	_map_btn = map_btn
	_chat_btn = Button.new()
	_chat_btn.text = " 💬 CHAT "
	_chat_btn.custom_minimum_size = Vector2(0, 38)
	_chat_btn.add_theme_font_size_override("font_size", 14)
	_chat_btn.focus_mode = Control.FOCUS_NONE
	_chat_btn.pressed.connect(open_chat)
	_chat_btn.visible = true
	top_row.add_child(_chat_btn)
	_services_btn = Button.new()
	_services_btn.text = " MÉTIERS "
	_services_btn.custom_minimum_size = Vector2(0, 38)
	_services_btn.add_theme_font_size_override("font_size", 14)
	_services_btn.focus_mode = Control.FOCUS_NONE
	_services_btn.pressed.connect(func(): main.net_jobs.open_menu())
	_services_btn.visible = Net.online
	top_row.add_child(_services_btn)
	_phone_btn = Button.new()
	_phone_btn.text = " TÉL "
	_phone_btn.custom_minimum_size = Vector2(0, 38)
	_phone_btn.add_theme_font_size_override("font_size", 14)
	_phone_btn.focus_mode = Control.FOCUS_NONE
	_phone_btn.pressed.connect(func(): phone.toggle())
	top_row.add_child(_phone_btn)
	var emote_btn := Button.new()
	emote_btn.text = " GESTES "
	emote_btn.custom_minimum_size = Vector2(0, 38)
	emote_btn.add_theme_font_size_override("font_size", 14)
	emote_btn.focus_mode = Control.FOCUS_NONE
	emote_btn.pressed.connect(func(): emote_menu.toggle())
	top_row.add_child(emote_btn)
	_emote_btn = emote_btn
	# Chat vocal : maintenir pour parler ou appuyer pour basculer (V / B au clavier)
	_mic_btn = Button.new()
	_mic_btn.icon = TEX_MIC_MUTED
	_mic_btn.text = " COUPÉ "
	_mic_btn.expand_icon = true
	_mic_btn.add_theme_constant_override("icon_max_width", 22)
	_mic_btn.custom_minimum_size = Vector2(0, 38)
	_mic_btn.add_theme_font_size_override("font_size", 13)
	_mic_btn.focus_mode = Control.FOCUS_NONE
	_style_voice_btn(_mic_btn, false, "local")
	_mic_btn.button_down.connect(_on_mic_press_down)
	_mic_btn.button_up.connect(_on_mic_press_up)
	_mic_btn.visible = Net.online or preview_online
	top_row.add_child(_mic_btn)
	_radio_btn = Button.new()
	_radio_btn.text = " 📻 RADIO "
	_radio_btn.custom_minimum_size = Vector2(0, 38)
	_radio_btn.add_theme_font_size_override("font_size", 14)
	_radio_btn.focus_mode = Control.FOCUS_NONE
	_style_voice_btn(_radio_btn, false, "group")
	_radio_btn.button_down.connect(_on_radio_press_down)
	_radio_btn.button_up.connect(_on_radio_press_up)
	_radio_btn.visible = (Net.online and Net.social.my_group != "") or preview_online
	top_row.add_child(_radio_btn)
	_talk_label = _label(15, Color("ff595e"), HORIZONTAL_ALIGNMENT_RIGHT)
	_talk_label.visible = false
	tr.add_child(_talk_label)
	top_row.add_child(map_btn)
	top_row.add_child(pause_btn)
	# L'heure sur la ligne des boutons (la colonne de droite reste courte : elle ne cache plus le bouton COUP)
	_clock = _label(20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_clock)
	top_row.move_child(_clock, 0)
	_minimap = Minimap.new()
	_minimap.main = main
	tr.add_child(_minimap)
	_district = _label(14, Color("ffd166"), HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_district)
	_speed = _label(14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	tr.add_child(_speed)

	# Haut centre : objectif
	_objective = _label(16, Color("fff3b0"), HORIZONTAL_ALIGNMENT_CENTER)
	_objective.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_objective.offset_left = 250
	_objective.offset_right = -190
	_objective.offset_top = 62
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_objective)

	_police = _label(16, Color("ff6b6b"), HORIZONTAL_ALIGNMENT_CENTER)
	_police.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_police.offset_left = 250
	_police.offset_right = -190
	_police.offset_top = 110
	_police.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_police)

	# Bas centre : action possible
	var bc := CenterContainer.new()
	bc.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bc.offset_top = -190
	bc.offset_bottom = -130
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bc)
	_bottom_center = bc
	_prompt_panel = PanelContainer.new()
	_prompt_panel.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.65)))
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_prompt_panel.gui_input.connect(func(event: InputEvent):
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			var pl = GameState.player_ref
			if pl and is_instance_valid(pl):
				var sv = pl._nearest_vehicle(1.5)
				if sv:
					pl.enter_vehicle(sv)
				else:
					pl._interact()
	)
	bc.add_child(_prompt_panel)
	_prompt = _label(18, Color.WHITE)
	_prompt_panel.add_child(_prompt)

	# Gauche : notifications
	_notes = VBoxContainer.new()
	_notes.position = Vector2(16, 226)
	_notes.add_theme_constant_override("separation", 6)
	root.add_child(_notes)

	# Discussion et Chat (en ligne & solo)
	_build_chat(root)

	_build_pause(root)
	map_screen = MapScreen.new()
	map_screen.main = main
	root.add_child(map_screen)
	phone = Phone.new()
	phone.main = main
	phone.hud = self
	root.add_child(phone)
	emote_menu = EmoteMenu.new()
	emote_menu.main = main
	root.add_child(emote_menu)
	_build_intro(root)
	GameState.notify.connect(_on_notify)
	get_viewport().size_changed.connect(apply_responsive_layout)
	apply_responsive_layout()


## Répartition dynamique et Safe Area (encoche, Dynamic Island, barre d'accueil, bords arrondis)
func apply_responsive_layout() -> void:
	var margins: Dictionary = GameState.get_safe_margins(get_viewport())
	var vp: Vector2 = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	
	# 1. Panneau des jauges (en haut à gauche, respecte l'encoche et les coins arrondis)
	if _gauges_panel and is_instance_valid(_gauges_panel):
		_gauges_panel.position = Vector2(margins.left, margins.top)
	
	# 2. Dock vocal (sous les jauges)
	if _voice_dock and is_instance_valid(_voice_dock):
		var gp_h: float = _gauges_panel.size.y if _gauges_panel and _gauges_panel.size.y > 0 else 156.0
		_voice_dock.position = Vector2(margins.left, margins.top + gp_h + 8.0)
	
	# 3. Notifications (sous le dock vocal)
	if _notes and is_instance_valid(_notes):
		var vd_y: float = _voice_dock.position.y if _voice_dock else (margins.top + 160.0)
		var vd_h: float = (_voice_dock.size.y + 8.0) if (_voice_dock and _voice_dock.visible and _voice_dock.size.y > 0) else 0.0
		_notes.position = Vector2(margins.left, vd_y + vd_h + 4.0)
	
	# 4. Colonne de droite (minimap, boutons du haut, heure, vitesse)
	if _tr and is_instance_valid(_tr):
		_tr.anchor_left = 1.0
		_tr.anchor_right = 1.0
		_tr.anchor_top = 0.0
		_tr.anchor_bottom = 0.0
		_tr.offset_right = -margins.right
		_tr.offset_top = margins.top
	
	# 5. Adaptabilité des boutons du haut selon la largeur de l'écran
	var compact := vp.x < 1180.0 or GameState.touch_ui
	if _map_btn and is_instance_valid(_map_btn):
		_map_btn.text = " 🗺️ " if compact else " CARTE "
	if _pause_btn and is_instance_valid(_pause_btn):
		_pause_btn.text = " ⏸ " if compact else "  II  "
	if _chat_btn and is_instance_valid(_chat_btn):
		_chat_btn.text = " 💬 " if compact else " 💬 CHAT "
	if _services_btn and is_instance_valid(_services_btn):
		_services_btn.text = " 💼 " if compact else " MÉTIERS "
	if _phone_btn and is_instance_valid(_phone_btn):
		_phone_btn.text = " 📱 " if compact else " TÉL "
	if _emote_btn and is_instance_valid(_emote_btn):
		_emote_btn.text = " 🎭 " if compact else " GESTES "
	
	# Sur mobile avec dock vocal, masquer les doublons micro/radio du haut pour libérer 200px
	if GameState.touch_ui:
		if _mic_btn and is_instance_valid(_mic_btn):
			_mic_btn.visible = false
		if _radio_btn and is_instance_valid(_radio_btn):
			_radio_btn.visible = false
	
	# 6. Bannière de parole (centrée sans chevauchement)
	if _talk_banner and is_instance_valid(_talk_banner):
		var gp_w: float = _gauges_panel.size.x if _gauges_panel and _gauges_panel.size.x > 0 else 180.0
		var tr_w: float = _tr.size.x if _tr and _tr.size.x > 0 else 180.0
		_talk_banner.offset_left = margins.left + gp_w + 12.0
		_talk_banner.offset_right = -(margins.right + tr_w + 12.0)
		_talk_banner.offset_top = margins.top
		_talk_banner.offset_bottom = margins.top + 38.0
	
	# 7. Objectif & Police
	if _objective and is_instance_valid(_objective):
		_objective.offset_left = margins.left + 200.0
		_objective.offset_right = -(margins.right + 190.0)
		_objective.offset_top = margins.top + 46.0
	if _police and is_instance_valid(_police):
		_police.offset_left = margins.left + 200.0
		_police.offset_right = -(margins.right + 190.0)
		_police.offset_top = margins.top + 90.0
	
	# 8. Invite d'action (en bas au centre, au-dessus de la barre d'accueil iPhone)
	if _bottom_center and is_instance_valid(_bottom_center):
		var bot_m: float = maxf(130.0, 90.0 + margins.bottom)
		_bottom_center.offset_bottom = -bot_m
		_bottom_center.offset_top = -bot_m - 60.0
	
	# 9. Repositionnement du panneau de chat
	if _chat_panel and _chat_panel.visible:
		_position_chat_panel()


func _style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _label(font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = 100.0
	b.show_percentage = false
	b.custom_minimum_size = Vector2(120, 9)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.15)
	bg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("fill", fill)
	b.add_theme_stylebox_override("background", bg)
	return b


func _row(text: String, bar: ProgressBar) -> HBoxContainer:
	var h := HBoxContainer.new()
	var l := _label(12, Color.WHITE)
	l.text = text
	l.custom_minimum_size.x = 52
	h.add_child(l)
	h.add_child(bar)
	return h


func _build_pause(root: Control) -> void:
	_pause = ColorRect.new()
	_pause.color = Color(0, 0, 0, 0.6)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	root.add_child(_pause)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.08, 0.1, 0.95)))
	cc.add_child(panel)
	_pause_main = panel
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(380, 0)
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title := _label(40, Color("fdef42"), HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "PAUSE"
	v.add_child(title)
	_stats = _label(18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_stats)
	v.add_child(_menu_button("Reprendre", toggle_pause))
	v.add_child(_menu_button("Sauvegarder", func():
		GameState.save_game()
		GameState.notify.emit("Partie sauvegardée.")))
	var voice_btn := _menu_button("", func(): pass)
	voice_btn.text = "Chat vocal : activé"
	voice_btn.pressed.connect(func():
		if main.voice:
			main.voice.enabled = not main.voice.enabled
			voice_btn.text = "Chat vocal : %s" % ("activé" if main.voice.enabled else "coupé"))
	v.add_child(voice_btn)
	if GameState.touch_ui:
		v.add_child(_menu_button("Commandes tactiles…", func(): _show_touch_menu(true)))
		_build_touch_menu(cc, root)
	# Visible seulement pendant le guide (mis à jour à l'ouverture de la pause)
	_tut_btn = _menu_button("Arrêter le guide des premiers pas", func():
		main.tutorial.skip()
		_tut_btn.visible = false)
	_tut_btn.visible = false
	v.add_child(_tut_btn)
	var gfx := _menu_button("", func(): pass)
	var order: Array = Graphics.ORDER
	gfx.text = "Graphismes : %s" % Graphics.display_name()
	gfx.pressed.connect(func():
		Graphics.set_profile(order[(order.find(Graphics.profile) + 1) % order.size()])
		gfx.text = "Graphismes : %s" % Graphics.display_name()
		var advised: String = Graphics.device_profile()
		if order.find(Graphics.profile) > order.find(advised):
			GameState.notify.emit("Attention : profil %s trop lourd pour la mémoire de ce téléphone (conseillé : %s). Le jeu risque de se fermer ; il reviendra au profil conseillé s'il plante." % [Graphics.display_name(), Graphics.NAMES[advised]])
		else:
			GameState.notify.emit("Profil graphique %s (passants et circulation : au prochain lancement)." % Graphics.display_name()))
	v.add_child(gfx)
	v.add_child(_menu_button("Nouvelle partie", func():
		GameState.new_game()
		Audio.stop_all()
		get_tree().paused = false
		get_tree().reload_current_scene()))
	if Net.online:
		# Exigence de Google Play : le joueur peut effacer son compte depuis le jeu
		var del := _menu_button("Supprimer mon compte", func():
			show_choices("Supprimer définitivement le compte « %s » ?
Argent, logement et progression en ligne seront effacés." % Net.pseudo, [
				["Oui, supprimer mon compte", func(): Net.delete_account()],
			], func(): pass))
		del.add_theme_color_override("font_color", Color("ff8a80"))
		v.add_child(del)
	v.add_child(_menu_button("Quitter", func():
		GameState.quit_game()))
	var credit := _label(13, Color("aaaaaa"), HORIZONTAL_ALIGNMENT_CENTER)
	credit.text = "Carte : © les contributeurs d'OpenStreetMap"
	v.add_child(credit)


## Sous-menu de la pause : taille, transparence, caméra, vibrations, place des boutons
func _build_touch_menu(cc: Control, root: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.08, 0.1, 0.95)))
	panel.visible = false
	cc.add_child(panel)
	_touch_menu = panel
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.custom_minimum_size = Vector2(380, 0)
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	var title := _label(32, Color("fdef42"), HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "COMMANDES TACTILES"
	v.add_child(title)
	for spec in [[TouchControls.size_text(), TouchControls.cycle_size], [TouchControls.opacity_text(), TouchControls.cycle_opacity],
			[TouchControls.sens_text(), TouchControls.cycle_sens], [TouchControls.vib_text(), TouchControls.toggle_vibrate]]:
		var tb := _menu_button(spec[0], func(): pass)
		var fn: Callable = spec[1]
		tb.pressed.connect(func():
			tb.text = fn.call()
			_touch.queue_redraw())
		v.add_child(tb)
	v.add_child(_menu_button("Placer les boutons", func(): _layout_mode(true)))
	v.add_child(_menu_button("Retour", func(): _show_touch_menu(false)))

	# Barre du mode placement, en haut de l'écran (la partie reste en pause)
	_layout_bar = PanelContainer.new()
	_layout_bar.add_theme_stylebox_override("panel", _style(Color(0.08, 0.08, 0.1, 0.9)))
	_layout_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_layout_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layout_bar.position.y = 12
	_layout_bar.visible = false
	root.add_child(_layout_bar)
	var lv := VBoxContainer.new()
	_layout_bar.add_child(lv)
	var hint := _label(18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "Fais glisser les boutons et le joystick où tu veux"
	lv.add_child(hint)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	lv.add_child(h)
	var mode := _menu_button("Voir : en voiture", func(): pass)
	mode.pressed.connect(func():
		_touch.in_vehicle = not _touch.in_vehicle
		mode.text = "Voir : à pied" if _touch.in_vehicle else "Voir : en voiture")
	h.add_child(mode)
	h.add_child(_menu_button("Réinitialiser", func():
		TouchControls.reset_layout()
		_touch.queue_redraw()))
	h.add_child(_menu_button("Terminé", func(): _layout_mode(false)))


func _show_touch_menu(on: bool) -> void:
	_pause_main.visible = not on
	_touch_menu.visible = on


func _layout_mode(on: bool) -> void:
	_touch.editing = on
	_touch.in_vehicle = false
	_pause.visible = not on
	_layout_bar.visible = on
	for b in _layout_bar.find_children("*", "Button", true, false):
		if b.text.begins_with("Voir"):
			b.text = "Voir : en voiture"
	_touch.queue_redraw()


## Menu de choix (destination du taxi...) : options = [[texte, Callable], ...]
func show_choices(title_text: String, options: Array, on_cancel: Callable) -> void:
	close_choices()
	_choices_on_cancel = on_cancel
	_choices = ColorRect.new()
	_choices.color = Color(0, 0, 0, 0.55)
	_choices.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_choices)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choices.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.08, 0.11, 0.96)))
	cc.add_child(panel)
	var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
	var margins: Dictionary = GameState.get_safe_margins(get_viewport())
	var max_w: float = clampf(vp.x - margins.left - margins.right - 24.0, 280.0, 520.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(max_w, 0)
	panel.add_child(v)
	var t := _label(22, Color("fdef42"), HORIZONTAL_ALIGNMENT_CENTER)
	t.text = title_text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	var scroll := ScrollContainer.new()
	var visible_items := mini(options.size(), 7)
	var max_h: float = maxf(160.0, vp.y - margins.top - margins.bottom - 170.0)
	scroll.custom_minimum_size = Vector2(max_w - 10.0, minf(visible_items * 52 + 10, max_h))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)
	var btn_box := VBoxContainer.new()
	btn_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_box.add_theme_constant_override("separation", 6)
	scroll.add_child(btn_box)
	var first_btn: Button = null
	for o in options:
		var cb: Callable = o[1]
		var b := _menu_button(o[0], func():
			close_choices()
			cb.call())
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_box.add_child(b)
		if first_btn == null:
			first_btn = b
	var cancel_btn := _menu_button("Annuler / Fermer [B]", func():
		var cb := _choices_on_cancel
		close_choices()
		if cb.is_valid():
			cb.call())
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.add_theme_font_size_override("font_size", 18)
	v.add_child(cancel_btn)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_touch.release_all()
	if first_btn != null:
		first_btn.grab_focus()
	elif cancel_btn != null:
		cancel_btn.grab_focus()


func close_choices() -> void:
	if _choices != null and is_instance_valid(_choices):
		_choices.queue_free()
	_choices = null
	_choices_on_cancel = Callable()


func choices_open() -> bool:
	return _choices != null and is_instance_valid(_choices)


func _menu_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b


func _build_intro(root: Control) -> void:
	_intro = ColorRect.new()
	_intro.color = Color(0.03, 0.03, 0.05, 0.82)
	_intro.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_intro)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro.add_child(cc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	cc.add_child(v)
	var title := _label(84, Color("fdef42"), HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "GALSEN-LIFE"
	v.add_child(title)
	var sub := _label(28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	sub.text = "Dalal ak jàmm ci Dakar ! (Bienvenue à Dakar)"
	v.add_child(sub)
	var help := _label(19, Color("dddddd"), HORIZONTAL_ALIGNMENT_CENTER)
	if GameState.touch_ui:
		help.text = "Joystick à gauche pour bouger • glisse à droite pour regarder\nACTION : monter (passager ou conducteur), parler, travailler • VOLER • SAUT / FREIN • KLAXON"
	else:
		help.text = "ZQSD / WASD ou flèches : bouger • Souris : caméra (clic pour la capturer)\nE : action (monter, attendre le bus, acheter, travailler, parler) • G : voler • M : carte et GPS • Espace : saut / frein • Maj : courir • H : klaxon • R : radio • Échap : pause"
	v.add_child(help)
	var jobs := _label(19, Color("a8dadc"), HORIZONTAL_ALIGNMENT_CENTER)
	jobs.text = "Gagne ta vie : monte dans un taxi jaune et noir, livre le thiéb de Chez Adja,\nvends du café Touba au marché Sandaga... et n'oublie pas de manger un dibi !\nAttention : voler une voiture ou renverser un passant, et la police te tombe dessus."
	v.add_child(jobs)
	var go := _label(24, Color("7cfc9a"), HORIZONTAL_ALIGNMENT_CENTER)
	go.text = "Touche l'écran ou appuie sur une touche pour commencer"
	v.add_child(go)
	var credit := _label(14, Color("bbbbbb"), HORIZONTAL_ALIGNMENT_CENTER)
	credit.text = "Carte de Dakar : © les contributeurs d'OpenStreetMap (ODbL)"
	v.add_child(credit)


func _hide_intro() -> void:
	var tw := create_tween()
	tw.tween_property(_intro, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _intro.visible = false)


func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	return false


func _input(event: InputEvent) -> void:
	if phone.visible and GameState.typing:
		# On écrit dans le téléphone : seule Échap compte (les lettres vont dans le champ)
		if _is_escape(event):
			phone._unfocus()
			get_viewport().set_input_as_handled()
		return
	if _chat_panel and _chat_panel.visible:
		if _is_escape(event):
			close_chat()
			get_viewport().set_input_as_handled()
		elif event is InputEventScreenTouch and event.pressed:
			var cr := _chat_panel.get_global_rect()
			if not cr.has_point(event.position):
				close_chat()
				get_viewport().set_input_as_handled()
		return
	if _intro.visible and _intro.modulate.a >= 1.0:
		if _is_press(event):
			_hide_intro()
			get_viewport().set_input_as_handled()
		return
	if choices_open() and event.is_action_pressed("ui_cancel"):
		var cb := _choices_on_cancel
		close_choices()
		if cb.is_valid():
			cb.call()
		get_viewport().set_input_as_handled()
		return
	if map_screen.visible:
		if event.is_action_pressed("pause") or event.is_action_pressed("map") or event.is_action_pressed("ui_cancel"):
			map_screen.close()
			get_viewport().set_input_as_handled()
		return
	if phone.visible and (event.is_action_pressed("pause") or event.is_action_pressed("phone") or event.is_action_pressed("ui_cancel")):
		phone.close()
		get_viewport().set_input_as_handled()
		return
	if _chat_panel != null and _chat_panel.visible and event.is_action_pressed("ui_cancel"):
		close_chat()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("phone") and not get_tree().paused and not choices_open():
		phone.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("chat") and not get_tree().paused:
		open_chat()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not get_tree().paused:
		open_map()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_touch"):
		GameState.touch_ui = not GameState.touch_ui
		_touch.visible = GameState.touch_ui
		_touch.release_all()


# --- Système de Discussion et Chat (Mobile & Desktop) ---------------------

func _is_escape(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE


func release_touch() -> void:
	_touch.release_all()


func _build_chat(p_root: Control) -> void:
	# 1. Fenêtre d'affichage des messages reçus avec fond sombre semi-transparent
	_chat_log_panel = PanelContainer.new()
	_chat_log_panel.position = Vector2(16, 320)
	var log_sb := StyleBoxFlat.new()
	log_sb.bg_color = Color(0.04, 0.07, 0.11, 0.75)
	log_sb.set_corner_radius_all(8)
	log_sb.content_margin_left = 12
	log_sb.content_margin_top = 8
	log_sb.content_margin_right = 12
	log_sb.content_margin_bottom = 8
	_chat_log_panel.add_theme_stylebox_override("panel", log_sb)
	_chat_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_log_panel.visible = false
	p_root.add_child(_chat_log_panel)

	_chat_log = VBoxContainer.new()
	_chat_log.add_theme_constant_override("separation", 4)
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_log_panel.add_child(_chat_log)

	# 2. Panneau de saisie et de discussion complet
	_chat_panel = PanelContainer.new()
	_chat_panel.position = Vector2(16, 520)
	_chat_panel.custom_minimum_size = Vector2(540, 130)
	var chat_sb := StyleBoxFlat.new()
	chat_sb.bg_color = Color(0.06, 0.1, 0.15, 0.96)
	chat_sb.border_color = Color("00a896")
	chat_sb.border_width_left = 2
	chat_sb.border_width_top = 2
	chat_sb.border_width_right = 2
	chat_sb.border_width_bottom = 2
	chat_sb.set_corner_radius_all(12)
	chat_sb.content_margin_left = 12
	chat_sb.content_margin_top = 10
	chat_sb.content_margin_right = 12
	chat_sb.content_margin_bottom = 10
	_chat_panel.add_theme_stylebox_override("panel", chat_sb)
	_chat_panel.visible = false
	p_root.add_child(_chat_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_chat_panel.add_child(vb)

	# Ligne 1 : Choix du canal + Bouton Fermer
	var chan_row := HBoxContainer.new()
	chan_row.add_theme_constant_override("separation", 6)
	vb.add_child(chan_row)

	var chan_lbl := Label.new()
	chan_lbl.text = "💬 Canal :"
	chan_lbl.add_theme_font_size_override("font_size", 12)
	chan_lbl.add_theme_color_override("font_color", Color("ffd166"))
	chan_row.add_child(chan_lbl)

	var channels := [
		["local", "📍 Proche"],
		["all", "🌍 Dakar (Tous)"],
		["group", "👥 Groupe"],
		["faction", "📻 Radio"]
	]
	for c in channels:
		var cid: String = c[0]
		var clbl: String = c[1]
		var btn := Button.new()
		btn.text = clbl
		btn.add_theme_font_size_override("font_size", 11)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func(): _select_channel(cid))
		chan_row.add_child(btn)
		_channel_btns[cid] = btn

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chan_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close_chat)
	chan_row.add_child(close_btn)

	# Ligne 2 : Phrases rapides en un clic (Mobile Friendly)
	var quick_scroll := ScrollContainer.new()
	quick_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	quick_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quick_scroll.custom_minimum_size = Vector2(0, 30)
	vb.add_child(quick_scroll)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 6)
	quick_scroll.add_child(quick_row)

	var phrases := [
		"👋 Salamalekum !",
		"🚕 Taxi disponible ?",
		"⚽ Match au Stade !",
		"🤼 Qui pour la lutte ?",
		"🚗 Monte avec moi !",
		"📍 On va où ?",
		"💰 Merci beaucoup !"
	]
	for phrase in phrases:
		var p_text: String = phrase
		var p_btn := Button.new()
		p_btn.text = p_text
		p_btn.add_theme_font_size_override("font_size", 11)
		p_btn.focus_mode = Control.FOCUS_NONE
		p_btn.pressed.connect(func():
			if _chat_input:
				_chat_input.text = p_text
				_send_current_chat()
		)
		quick_row.add_child(p_btn)

	# Ligne 3 : Ligne de saisie + Bouton Envoyer tactile
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	vb.add_child(input_row)

	_chat_input = LineEdit.new()
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.custom_minimum_size = Vector2(300, 42)
	_chat_input.max_length = 160
	_chat_input.text_submitted.connect(func(_t): _send_current_chat())
	input_row.add_child(_chat_input)

	var send_btn := Button.new()
	send_btn.text = " 🚀 Envoyer "
	send_btn.custom_minimum_size = Vector2(96, 42)
	send_btn.add_theme_font_size_override("font_size", 13)
	var send_sb := StyleBoxFlat.new()
	send_sb.bg_color = Color("00853f")
	send_sb.set_corner_radius_all(6)
	send_btn.add_theme_stylebox_override("normal", send_sb)
	send_btn.focus_mode = Control.FOCUS_NONE
	send_btn.pressed.connect(_send_current_chat)
	input_row.add_child(send_btn)

	_select_channel("local")
	Net.chat_received.connect(_on_chat)


func _select_channel(cid: String) -> void:
	_chat_channel = cid
	for k in _channel_btns:
		var b: Button = _channel_btns[k]
		if k == cid:
			b.modulate = Color("00a896")
		else:
			b.modulate = Color(0.7, 0.75, 0.8)
	if _chat_input:
		match cid:
			"local":
				_chat_input.placeholder_text = "Message aux joueurs proches (bulle 3D)..."
			"all":
				_chat_input.placeholder_text = "Message public à tout Dakar (/t)..."
			"group":
				_chat_input.placeholder_text = "Message à ton groupe Mbokk (/g)..."
			"faction":
				_chat_input.placeholder_text = "Message à la radio de ta faction (/f)..."


func open_chat() -> void:
	if _chat_panel == null:
		return
	_chat_panel.visible = true
	_position_chat_panel()
	_chat_input.grab_focus()
	GameState.typing = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_touch.release_all()


func open_chat_direct(who: String) -> void:
	open_chat()
	_select_channel("local")
	_chat_input.text = "@" + who + " "
	_chat_input.caret_column = _chat_input.text.length()


func close_chat() -> void:
	if _chat_panel:
		_chat_panel.visible = false
	if _chat_input:
		_chat_input.release_focus()
	GameState.typing = false


func _send_current_chat() -> void:
	if _chat_input == null:
		return
	var text := _chat_input.text.strip_edges()
	if text == "":
		return
	if _chat_channel == "all" and not text.begins_with("/t ") and not text.begins_with("/a "):
		text = "/t " + text
	elif _chat_channel == "group" and not text.begins_with("/g "):
		text = "/g " + text
	elif _chat_channel == "faction" and not text.begins_with("/f "):
		text = "/f " + text
	Net.send_chat(text)
	Audio.play_sfx("coin", -18.0)
	_chat_input.text = ""
	close_chat()


func _position_chat_panel() -> void:
	if _chat_panel == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var margins: Dictionary = GameState.get_safe_margins(get_viewport())
	var kb_h := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	var bot_m: float = float(kb_h) + 12.0 if kb_h > 0 else maxf(60.0, margins.bottom + 12.0)
	_chat_panel.custom_minimum_size.x = clampf(vp.x - margins.left - margins.right, 280.0, 540.0)
	_chat_panel.position = Vector2(margins.left, vp.y - bot_m - _chat_panel.size.y)


func _on_chat(from: String, text: String) -> void:
	if _chat_log_panel:
		_chat_log_panel.visible = true
	var color := Color.WHITE
	if from.begins_with("[Proche]"):
		color = Color("ffd166")
	elif from.begins_with("[Tous]") or from.begins_with("[Dakar]"):
		color = Color("06d6a0")
	elif from.begins_with("[Radio"):
		color = Color("f77f00")
	elif from.begins_with("[") and not from.begins_with("[Serveur"):
		color = Color("e0aaff")
	elif "Serveur" in from:
		color = Color("caffbf")

	var l := _label(13, color)
	l.text = "%s : %s" % [from, text]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 480
	_chat_log.add_child(l)
	while _chat_log.get_child_count() > 7:
		var old := _chat_log.get_child(0)
		_chat_log.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(25.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func():
		if _chat_log and _chat_log.get_child_count() == 0 and _chat_log_panel:
			_chat_log_panel.visible = false
	)


## Fondu au noir, action (téléportation...), retour à l'image.
func fade_through(cb: Callable) -> void:
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tw := black.create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.6)
	tw.tween_callback(cb)
	tw.tween_interval(0.4)
	tw.tween_property(black, "color:a", 0.0, 0.8)
	tw.tween_callback(black.queue_free)


func open_map() -> void:
	if get_tree().paused or choices_open():
		return
	_touch.release_all()
	map_screen.open()


func _on_mic_press_down() -> void:
	_mic_down_time = Time.get_ticks_msec() / 1000.0
	if not _mic_locked:
		if main.voice:
			main.voice.start_talking("local")


func _on_mic_press_up() -> void:
	var duration: float = (Time.get_ticks_msec() / 1000.0) - _mic_down_time
	if duration < 0.35:
		_mic_locked = not _mic_locked
		if _mic_locked:
			if main.voice and main.voice.talking == "":
				main.voice.start_talking("local")
				GameState.notify.emit("🎙️ Micro activé (en direct). Réappuie pour couper.")
		else:
			if main.voice:
				main.voice.stop_talking()
				GameState.notify.emit("🎙️❌ Micro coupé.")
	else:
		_mic_locked = false
		if main.voice:
			main.voice.stop_talking()


func _on_radio_press_down() -> void:
	_radio_down_time = Time.get_ticks_msec() / 1000.0
	if not _radio_locked:
		if main.voice:
			main.voice.start_talking("group")


func _on_radio_press_up() -> void:
	var duration: float = (Time.get_ticks_msec() / 1000.0) - _radio_down_time
	if duration < 0.35:
		_radio_locked = not _radio_locked
		if _radio_locked:
			if main.voice and main.voice.talking == "":
				main.voice.start_talking("group")
				GameState.notify.emit("📻 Radio de groupe activée. Réappuie pour couper.")
		else:
			if main.voice:
				main.voice.stop_talking()
				GameState.notify.emit("📻 Radio coupée.")
	else:
		_radio_locked = false
		if main.voice:
			main.voice.stop_talking()


func _style_voice_btn(btn: Button, active: bool, channel: String) -> void:
	var base_col: Color
	var border_col: Color
	if channel == "group":
		base_col = Color(0.60, 0.28, 0.05, 0.95) if active else Color(0.18, 0.14, 0.10, 0.88)
		border_col = Color("ffd166") if active else Color("f4a261")
	else:
		base_col = Color(0.08, 0.42, 0.22, 0.95) if active else Color(0.18, 0.10, 0.12, 0.88)
		border_col = Color("7cfc9a") if active else Color("e63946")

	var sb := StyleBoxFlat.new()
	sb.bg_color = base_col
	sb.border_color = border_col
	sb.set_border_width_all(3 if active else 2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_color_override("font_color", Color.WHITE if active else Color("ffccd5"))


func toggle_pause() -> void:
	if _touch.editing: # Retour pendant le placement des boutons : on revient au sous-menu
		_layout_mode(false)
		return
	if _touch_menu != null:
		_show_touch_menu(false)
	var paused := not get_tree().paused
	get_tree().paused = paused
	_pause.visible = paused
	_touch.release_all()
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_stats.text = "Courses de taxi : %d\nLivraisons : %d\nCafés vendus : %d\n\nSac : %s" % [
			GameState.stats["courses_taxi"], GameState.stats["livraisons"], GameState.stats["cafes_vendus"], GameState.inventory_text()]
		_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tut_btn.visible = main != null and main.tutorial != null and main.tutorial.active()
		var vp := get_viewport().get_visible_rect().size if get_viewport() else Vector2(1280, 720)
		var margins: Dictionary = GameState.get_safe_margins(get_viewport())
		if _pause_main:
			var scroll: ScrollContainer = _pause_main.get_child(0) if _pause_main.get_child_count() > 0 and _pause_main.get_child(0) is ScrollContainer else null
			if scroll:
				scroll.custom_minimum_size.y = minf(540.0, maxf(220.0, vp.y - margins.top - margins.bottom - 48.0))
		if _touch_menu:
			var scroll: ScrollContainer = _touch_menu.get_child(0) if _touch_menu.get_child_count() > 0 and _touch_menu.get_child(0) is ScrollContainer else null
			if scroll:
				scroll.custom_minimum_size.y = minf(540.0, maxf(220.0, vp.y - margins.top - margins.bottom - 48.0))


## Étoiles de recherche, dessinées (la police par défaut n'a pas le glyphe ★).
func _draw_stars() -> void:
	var blink: bool = GameState.wanted > 0 and main != null and main.police.status != "" and int(Time.get_ticks_msec() / 300) % 2 == 0
	for k in 5:
		var center := Vector2(9.0 + k * 21.0, 9.0)
		var pts := PackedVector2Array()
		for q in 10:
			var ang := -PI / 2.0 + q * PI / 5.0
			var rad := 8.0 if q % 2 == 0 else 3.4
			pts.append(center + Vector2(cos(ang), sin(ang)) * rad)
		var col := Color(1, 1, 1, 0.18)
		if k < GameState.wanted:
			col = Color("ffffff") if blink else Color("ffd23f")
		_stars.draw_colored_polygon(pts, col)


func _on_notify(text: String) -> void:
	var l := _label(14, Color.WHITE)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 340
	_notes.add_child(l)
	if _notes.get_child_count() > 5:
		_notes.get_child(0).queue_free()
	var tw := l.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _process(delta: float) -> void:
	if _chat_panel and _chat_panel.visible:
		_position_chat_panel()
	if main == null or main.player == null:
		return
	# Textes de l'interface : 10 mises à jour par seconde suffisent (moins de calcul sur téléphone)
	_hud_t -= delta
	if _hud_t > 0.0:
		return
	_hud_t = 0.1
	_money.text = GameState.fcfa(GameState.money)
	_health.value = GameState.health
	_hunger.value = GameState.hunger
	_thirst.value = GameState.thirst
	_energy.value = GameState.energy
	var m := int(GameState.game_minutes)
	_clock.text = "%02d:%02d" % [m / 60, m % 60]
	var p = main.player
	var pos: Vector3 = p.get_world_position()
	if main.foot and main.foot.contains(pos):
		_district.text = "Complexe de mini-foot"
	else:
		_district.text = "Pikine — Arène nationale" if main.arena and main.arena.contains(pos) else main.city.district_at(pos)
	if main.interiors and main.interiors.inside != "":
		var ins: String = main.interiors.inside
		if ins.begins_with("ent_") and main.enterprises:
			_district.text = main.enterprises.ENTERPRISES[ins.trim_prefix("ent_")]["title"]
		else:
			_district.text = main.interiors.TITLES.get(ins, "Chez toi")
	elif main.weather and main.weather.state != "clair":
		_district.text += " · " + main.weather.label()
	var veh = p.current_vehicle
	_speed.visible = veh != null
	var on: bool = Net.online or preview_online
	_online.visible = true
	_chat_btn.visible = true
	_mic_btn.visible = on
	_radio_btn.visible = (Net.online and Net.social.my_group != "") or preview_online
	var talking: String = main.voice.talking if main.voice else ""
	var is_talking: bool = talking != ""
	if not is_talking:
		_mic_locked = false
		_radio_locked = false

	if _voice_dock:
		_voice_dock.visible = on
		_radio_dock_btn.visible = (Net.online and Net.social.my_group != "") or preview_online

		if talking == "local":
			_voice_dock_btn.icon = TEX_MIC_ON
			_voice_dock_btn.text = " EN DIRECT"
			_mic_btn.icon = TEX_MIC_ON
			_mic_btn.text = " EN DIRECT "
			_style_voice_btn(_voice_dock_btn, true, "local")
			_style_voice_btn(_mic_btn, true, "local")
		else:
			_voice_dock_btn.icon = TEX_MIC_MUTED
			_voice_dock_btn.text = " COUPÉ"
			_mic_btn.icon = TEX_MIC_MUTED
			_mic_btn.text = " COUPÉ "
			_style_voice_btn(_voice_dock_btn, false, "local")
			_style_voice_btn(_mic_btn, false, "local")

		if talking == "group":
			_radio_dock_btn.text = "📻 ● RADIO"
			_radio_btn.text = " 📻 ● RADIO "
			_style_voice_btn(_radio_dock_btn, true, "group")
			_style_voice_btn(_radio_btn, true, "group")
		else:
			_radio_dock_btn.text = "📻 RADIO"
			_radio_btn.text = " 📻 RADIO "
			_style_voice_btn(_radio_dock_btn, false, "group")
			_style_voice_btn(_radio_btn, false, "group")

	if _talk_banner:
		_talk_banner.visible = is_talking
		if is_talking:
			var pulse: float = 0.82 + 0.18 * sin(Time.get_ticks_msec() * 0.008)
			_talk_banner.modulate = Color(1.0, 1.0, 1.0, pulse)
			if talking == "local":
				_talk_banner_label.text = "🎙️ ● MICRO EN DIRECT (Proximité 35m) — Tu parles aux joueurs autour • Touche pour couper"
			else:
				_talk_banner_label.text = "📻 ● RADIO DE GROUPE EN DIRECT — Tous tes membres t'entendent • Touche pour couper"

	_talk_label.visible = false
	var n: int = phone.unread_total()
	_phone_btn.text = " TÉL (%d) " % n if n > 0 else " TÉL "
	_services_btn.visible = on and main.net_jobs != null
	if Net.online:
		_online.text = "En ligne : %d joueur(s) — %s" % [Net.players_online(), Net.pseudo]
	else:
		_online.text = "Mode Hors-ligne (Solo) — %s" % (Net.pseudo if Net.pseudo != "" else "Dakar")
	if veh:
		_speed.text = "%s — %d km/h" % [veh.display_name, int(absf(veh.speed) * 3.6)]
		if veh.fuel >= 0.0:
			_speed.text += " — essence %d %%" % int(veh.fuel)
		if veh.condition < 100.0:
			_speed.text += " — moteur %d %%" % int(veh.condition)
	var trip: String = main.transit.status if main.transit else ""
	var arena_txt: String = main.arena.status if main.arena else ""
	if main.lutte and main.lutte.status != "":
		arena_txt = main.lutte.status
	if main.foot and main.foot.status != "":
		arena_txt = main.foot.status
	var rp_txt: String = main.net_jobs.status if main.net_jobs else ""
	if main.employment and main.employment.status() != "":
		rp_txt = main.employment.status()
	if main.social_ui and main.social_ui.status != "":
		rp_txt = main.social_ui.status
	if main.interiors and main.interiors.robbery_status != "":
		rp_txt = main.interiors.robbery_status
	if main.fishing and main.fishing.status != "":
		rp_txt = main.fishing.status
	if main.prison and main.prison.status != "":
		rp_txt = main.prison.status
	if trip == "" and arena_txt == "" and rp_txt != "":
		trip = rp_txt
	var mission_txt: String = main.missions.objective if (main != null and main.get("missions") != null) else ""
	_objective.text = trip if trip != "" else (arena_txt if arena_txt != "" else (mission_txt if mission_txt != "" else main.jobs.objective))
	if _objective.text == "" and main.tutorial:
		_objective.text = main.tutorial.objective
	_police.text = main.police.status
	_stars.queue_redraw()
	var hint: String = p.get_interaction_hint()
	_prompt_panel.visible = hint != "" and not get_tree().paused and not _intro.visible
	var in_foot: bool = main.foot != null and main.foot.in_match()
	var nv = p._nearest_vehicle()
	if in_foot:
		_prompt.text = hint
	elif GameState.gamepad_active:
		if nv != null:
			_prompt.text = "🎮 [Y/△] " + hint + "   [X/□] Voler"
		else:
			_prompt.text = "🎮 [Y/△] " + hint
	elif nv != null:
		var prefix: String = "Touche ici ou bouton [%s] : " % ("MOTO" if nv.vehicle_type in ["jakarta", "grosse_moto"] else "AUTO") if GameState.touch_ui else "[E] ou [G] "
		_prompt.text = prefix + hint
	else:
		_prompt.text = ("ACTION : " if GameState.touch_ui else "[E] ") + hint
	if not _touch.editing: # en mode placement, le joueur choisit lui-même À PIED / EN VOITURE
		_touch.in_vehicle = veh != null
	_touch.foot_mode = main.foot != null and main.foot.in_match()
	if veh == null and p.riding == null and (nv != null or "[G] voler" in hint or "voler" in hint.to_lower() or "monter" in hint.to_lower()):
		_touch.can_steal = true
		if nv != null:
			if nv.vehicle_type in ["jakarta", "grosse_moto"]:
				_touch.veh_label = "MOTO"
			else:
				_touch.veh_label = "AUTO"
		else:
			_touch.veh_label = "MONTER"
	else:
		_touch.can_steal = false


## Compte effacé par le serveur : retour au menu principal
func _on_account_deleted() -> void:
	get_tree().paused = false
	Audio.stop_all()
	Net.disconnect_from_server()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
