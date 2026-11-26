extends Control
## Menu de départ : jouer en solo, ou se connecter au serveur en ligne.
## Réglages retenus (adresse, pseudo, mot de passe, personnage) dans user://net_settings.cfg.

const SETTINGS := "user://net_settings.cfg"
const MAIN := "res://scenes/main.tscn"
const AVATAR_NAMES := {
	"heros": "Le héros (polo)", "homme_ville": "Homme en tenue de ville", "homme_afro": "Jeune homme à l'afro",
	"homme_tunique": "Homme en tunique", "femme_robe": "Femme en sari", "femme_jupe": "Jeune femme en jupe",
	"femme_ville": "Jeune femme en jean", "femme_maman": "Femme en robe bleue",
}
## Arguments de test qui démarrent directement la partie solo
const DIRECT_ARGS := ["--screenshot=", "--test-taxi", "--portrait", "--showcase", "--map", "--arena", "--at=", "--look=", "--overhead=", "--phone=", "--emote=", "--fps-test", "--perf-probe", "--pos=", "--inside-test", "--audit", "--office=", "--touch-test", "--drive-test", "--lutte-test", "--fight-test", "--crowd-test", "--lutte-live", "--lutte-base=", "--latlon=", "--enter=", "--talk=", "--home=", "--dealer-test", "--city-test", "--fish-test", "--rob-test", "--impound-test", "--cook-test", "--rooms-shot", "--feet-test", "--ped-motion", "--traffic-motion", "--rooms-walk", "--rental-test", "--biz-test", "--market-scan", "--market-test", "--goods-shots", "--hud-shot", "--trade-net", "--trade-shot", "--foot-test", "--foot-net", "--foot", "--foot-night", "--tuto-test", "--touch-layout"]

var _host: LineEdit
var _channel: OptionButton
var _pseudo: LineEdit
var _password: LineEdit
var _avatar: OptionButton
var _friend_code: LineEdit
var _create: CheckBox
var _status: Label
var _connect_btn: Button
var _offline_btn: Button
var _offline_fallback_btn: Button
var _scroll: ScrollContainer
var _margin: MarginContainer
var _content_vbox: VBoxContainer


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
	_build()
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
	var margins: Dictionary = GameState.get_safe_margins(get_viewport())
	var target_w := clampf(vp_size.x - margins.left - margins.right - 20.0, 280.0, 480.0)
	if _content_vbox and absf(_content_vbox.custom_minimum_size.x - target_w) > 1.0:
		_content_vbox.custom_minimum_size.x = target_w
	
	if _margin:
		_margin.add_theme_constant_override("margin_left", int(margins.left))
		_margin.add_theme_constant_override("margin_right", int(margins.right))
		_margin.add_theme_constant_override("margin_top", int(margins.top))
		_margin.add_theme_constant_override("margin_bottom", int(maxf(margins.bottom, 24.0)))

	# Élévation réactive de l'interface quand le clavier virtuel apparaît sur smartphone (iOS / Android)
	var kb_h := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	var target_bottom: float = -float(kb_h) if kb_h > 0 else 0.0
	if absf(_scroll.offset_bottom - target_bottom) > 1.0:
		_scroll.offset_bottom = lerpf(_scroll.offset_bottom, target_bottom, 0.45)


func _input(event: InputEvent) -> void:
	# Ferme le clavier virtuel si l'utilisateur touche l'arrière-plan en dehors des champs
	if event is InputEventScreenTouch and event.pressed:
		var fo := get_viewport().gui_get_focus_owner()
		if fo is LineEdit:
			var r := fo.get_global_rect()
			if not r.has_point(event.position):
				fo.release_focus()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("101418")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_scroll)

	_margin = MarginContainer.new()
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_theme_constant_override("margin_left", 16)
	_margin.add_theme_constant_override("margin_right", 16)
	_margin.add_theme_constant_override("margin_top", 16)
	_margin.add_theme_constant_override("margin_bottom", 24)
	_scroll.add_child(_margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var vp_size := get_viewport_rect().size
	v.custom_minimum_size = Vector2(clampf(vp_size.x - 32.0, 280.0, 440.0), 0)
	_content_vbox = v
	_margin.add_child(v)

	# Titre épuré
	var title := Label.new()
	title.text = "GALSEN-LIFE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("fdef42"))
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Dakar"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	v.add_child(sub)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)

	# Hôte réseau invisible (toujours le serveur officiel)
	_host = LineEdit.new()
	_host.text = str(cfg.get_value("net", "host", Net.DEFAULT_HOST))
	_host.visible = false
	v.add_child(_host)

	# Canal de connexion invisible (géré automatiquement en arrière-plan)
	_channel = OptionButton.new()
	for ch in Net.CHANNELS:
		_channel.add_item(ch["name"])
	var saved_chan: int = int(cfg.get_value("net", "channel_idx", 0))
	_channel.select(clampi(saved_chan, 0, Net.CHANNELS.size() - 1))
	_channel.visible = false
	v.add_child(_channel)

	# --- Profil du Joueur ---
	var saved_p: String = str(cfg.get_value("net", "pseudo", ""))
	var saved_pw: String = str(cfg.get_value("net", "password", ""))

	_pseudo = _field(v, "Pseudo", saved_p)

	_avatar = OptionButton.new()
	_avatar.custom_minimum_size = Vector2(0, 46)
	_avatar.add_theme_font_size_override("font_size", 15)
	for a in Net.AVATARS:
		_avatar.add_item(AVATAR_NAMES.get(a, a))
	_avatar.select(maxi(0, Net.AVATARS.find(cfg.get_value("net", "avatar", "heros"))))
	var av_sb := StyleBoxFlat.new()
	av_sb.bg_color = Color(0.11, 0.14, 0.19, 0.95)
	av_sb.border_color = Color(0.25, 0.33, 0.44, 0.8)
	av_sb.border_width_left = 1
	av_sb.border_width_top = 1
	av_sb.border_width_right = 1
	av_sb.border_width_bottom = 1
	av_sb.corner_radius_top_left = 8
	av_sb.corner_radius_top_right = 8
	av_sb.corner_radius_bottom_right = 8
	av_sb.corner_radius_bottom_left = 8
	av_sb.content_margin_left = 12.0
	av_sb.content_margin_right = 12.0
	_avatar.add_theme_stylebox_override("normal", av_sb)
	v.add_child(_avatar)

	_password = _field(v, "Mot de passe", saved_pw)
	_password.secret = true

	# Enchaînement naturel au clavier virtuel
	_pseudo.text_submitted.connect(func(_t): _password.grab_focus())
	_password.text_submitted.connect(func(_t): _on_connect())

	# Option créer un compte
	_create = CheckBox.new()
	_create.text = " Créer un compte"
	_create.custom_minimum_size = Vector2(0, 36)
	_create.add_theme_font_size_override("font_size", 15)
	_create.add_theme_color_override("font_color", Color(0.80, 0.85, 0.90))
	_create.add_theme_color_override("font_pressed_color", Color("7cfc9a"))
	v.add_child(_create)

	# --- Boutons d'action principaux ---
	var actions_box := VBoxContainer.new()
	actions_box.add_theme_constant_override("separation", 8)
	v.add_child(actions_box)

	# 1. Mode Solo
	_offline_btn = Button.new()
	_offline_btn.text = "🎮 JOUER EN SOLO"
	_offline_btn.custom_minimum_size = Vector2(0, 48)
	_offline_btn.add_theme_font_size_override("font_size", 16)
	var solo_st := StyleBoxFlat.new()
	solo_st.bg_color = Color(0.10, 0.32, 0.22, 0.95)
	solo_st.border_color = Color("7cfc9a")
	solo_st.border_width_left = 2
	solo_st.border_width_top = 2
	solo_st.border_width_right = 2
	solo_st.border_width_bottom = 2
	solo_st.corner_radius_top_left = 8
	solo_st.corner_radius_top_right = 8
	solo_st.corner_radius_bottom_right = 8
	solo_st.corner_radius_bottom_left = 8
	_offline_btn.add_theme_stylebox_override("normal", solo_st)
	_offline_btn.add_theme_stylebox_override("hover", solo_st)
	_offline_btn.pressed.connect(_start_offline)
	actions_box.add_child(_offline_btn)

	# 2. Mode En Ligne
	_connect_btn = Button.new()
	_connect_btn.text = "🌐 SE CONNECTER"
	_connect_btn.custom_minimum_size = Vector2(0, 48)
	_connect_btn.add_theme_font_size_override("font_size", 16)
	var net_st := StyleBoxFlat.new()
	net_st.bg_color = Color(0.18, 0.24, 0.35, 0.95)
	net_st.border_color = Color("90e0ef")
	net_st.border_width_left = 2
	net_st.border_width_top = 2
	net_st.border_width_right = 2
	net_st.border_width_bottom = 2
	net_st.corner_radius_top_left = 8
	net_st.corner_radius_top_right = 8
	net_st.corner_radius_bottom_right = 8
	net_st.corner_radius_bottom_left = 8
	_connect_btn.add_theme_stylebox_override("normal", net_st)
	_connect_btn.add_theme_stylebox_override("hover", net_st)
	_connect_btn.pressed.connect(_on_connect)
	actions_box.add_child(_connect_btn)

	_create.toggled.connect(func(pressed: bool):
		if pressed:
			_connect_btn.text = "🌐 CRÉER MON COMPTE"
		else:
			_connect_btn.text = "🌐 SE CONNECTER"
	)

	# --- Code ami (replié par défaut) ---
	var friend_toggle_btn := Button.new()
	friend_toggle_btn.text = "🤝 Code ami (optionnel)"
	friend_toggle_btn.flat = true
	friend_toggle_btn.custom_minimum_size = Vector2(0, 32)
	friend_toggle_btn.add_theme_font_size_override("font_size", 13)
	friend_toggle_btn.add_theme_color_override("font_color", Color(0.60, 0.75, 0.85))
	v.add_child(friend_toggle_btn)

	var f_box := VBoxContainer.new()
	f_box.add_theme_constant_override("separation", 6)
	f_box.visible = false
	v.add_child(f_box)

	friend_toggle_btn.pressed.connect(func():
		f_box.visible = !f_box.visible
		if f_box.visible:
			friend_toggle_btn.text = "🤝 Masquer code ami"
			call_deferred("_scroll_to_control", f_box)
		else:
			friend_toggle_btn.text = "🤝 Code ami (optionnel)"
	)

	var f_row := HBoxContainer.new()
	f_row.add_theme_constant_override("separation", 6)
	f_box.add_child(f_row)

	_friend_code = _field(f_row, "Code d'un ami (ex: GAL-12345)", "")
	_friend_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_code.text_submitted.connect(func(_t): _on_connect())

	var paste_btn := Button.new()
	paste_btn.text = "Coller"
	paste_btn.custom_minimum_size = Vector2(70, 44)
	paste_btn.add_theme_font_size_override("font_size", 13)
	paste_btn.pressed.connect(func():
		var clip := DisplayServer.clipboard_get().strip_edges()
		if clip != "":
			_friend_code.text = clip
	)
	f_row.add_child(paste_btn)

	var my_code_row := HBoxContainer.new()
	my_code_row.add_theme_constant_override("separation", 6)
	f_box.add_child(my_code_row)

	var init_p: String = cfg.get_value("net", "pseudo", "")
	var my_c_val := Net.generate_friend_code(init_p if init_p != "" else "Joueur")
	var my_code_label := Label.new()
	my_code_label.text = "Mon code : %s" % my_c_val
	my_code_label.add_theme_font_size_override("font_size", 12)
	my_code_label.add_theme_color_override("font_color", Color("fdef42"))
	my_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_code_row.add_child(my_code_label)

	var copy_my_code_btn := Button.new()
	copy_my_code_btn.text = "Copier mon code"
	copy_my_code_btn.custom_minimum_size = Vector2(130, 32)
	copy_my_code_btn.add_theme_font_size_override("font_size", 12)
	copy_my_code_btn.pressed.connect(func():
		var cur_p := _pseudo.text.strip_edges()
		var c := Net.generate_friend_code(cur_p if cur_p != "" else "Joueur")
		DisplayServer.clipboard_set(c)
		_status.text = "Code ami %s copié !" % c
	)
	my_code_row.add_child(copy_my_code_btn)

	_pseudo.text_changed.connect(func(new_p: String):
		var c := Net.generate_friend_code(new_p.strip_edges() if new_p.strip_edges() != "" else "Joueur")
		my_code_label.text = "Mon code : %s" % c
	)

	# --- Statut (concis, seulement sur action) ---
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("ffd166"))
	_status.add_theme_font_size_override("font_size", 13)
	v.add_child(_status)

	if saved_p == "":
		_create.button_pressed = true
		_connect_btn.text = "🌐 CRÉER MON COMPTE"
	else:
		_create.button_pressed = false

	# Bouton de secours hors-ligne en cas d'échec serveur
	_offline_fallback_btn = Button.new()
	_offline_fallback_btn.text = "🎮 Continuer en Solo"
	_offline_fallback_btn.custom_minimum_size = Vector2(0, 44)
	_offline_fallback_btn.add_theme_font_size_override("font_size", 15)
	_offline_fallback_btn.add_theme_stylebox_override("normal", solo_st)
	_offline_fallback_btn.add_theme_stylebox_override("hover", solo_st)
	_offline_fallback_btn.pressed.connect(_start_offline)
	_offline_fallback_btn.visible = false
	v.add_child(_offline_fallback_btn)

	# Crédits
	var credits := _button("Crédits", _show_credits)
	credits.flat = true
	credits.custom_minimum_size = Vector2(0, 30)
	credits.add_theme_font_size_override("font_size", 13)
	credits.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	v.add_child(credits)


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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.14, 0.19, 0.95)
	sb.border_color = Color(0.25, 0.33, 0.44, 0.8)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_bottom_left = 8
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	e.add_theme_stylebox_override("normal", sb)
	var sb_focus := sb.duplicate() as StyleBoxFlat
	sb_focus.border_color = Color("7cfc9a")
	sb_focus.border_width_left = 2
	sb_focus.border_width_top = 2
	sb_focus.border_width_right = 2
	sb_focus.border_width_bottom = 2
	e.add_theme_stylebox_override("focus", sb_focus)
	e.focus_entered.connect(func():
		call_deferred("_scroll_to_control", e)
	)
	parent.add_child(e)
	return e


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(cb)
	return b


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
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("net", "pseudo", _pseudo.text.strip_edges())
		cfg.set_value("net", "password", _password.text.strip_edges())
		cfg.save(SETTINGS)
		get_tree().change_scene_to_file(MAIN)


func _start_offline() -> void:
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
	cfg.save(SETTINGS)

	Net.start_offline(chosen_p, chosen_av)
	get_tree().change_scene_to_file(MAIN)
