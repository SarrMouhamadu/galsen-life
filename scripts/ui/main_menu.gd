extends Control
## Menu de départ : jouer en solo, ou se connecter au serveur en ligne.
## Réglages retenus (adresse, pseudo, personnage) dans user://net_settings.cfg — jamais le mot de passe.

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
		_pseudo.text = auto.get("pseudo", "")
		_password.text = auto.get("password", "")
		_create.button_pressed = "--create" in args
		var idx := Net.AVATARS.find(auto.get("avatar", "heros"))
		_avatar.select(maxi(0, idx))
		_on_connect()


func _process(_delta: float) -> void:
	if not _scroll:
		return
	var vp_size := get_viewport_rect().size
	var target_w := clampf(vp_size.x - 32.0, 280.0, 480.0)
	if _content_vbox and absf(_content_vbox.custom_minimum_size.x - target_w) > 1.0:
		_content_vbox.custom_minimum_size.x = target_w

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

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var vp_size := get_viewport_rect().size
	v.custom_minimum_size = Vector2(clampf(vp_size.x - 32.0, 280.0, 480.0), 0)
	_content_vbox = v
	center.add_child(v)

	var title := Label.new()
	title.text = "GALSEN-LIFE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("fdef42"))
	v.add_child(title)

	var sub := Label.new()
	sub.text = "Dalal ak jàmm ci Dakar !"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	v.add_child(sub)

	var solo := _button("Jouer en solo", func(): get_tree().change_scene_to_file(MAIN))
	solo.custom_minimum_size = Vector2(0, 48)
	solo.add_theme_font_size_override("font_size", 20)
	v.add_child(solo)

	var sep := HSeparator.new()
	v.add_child(sep)

	var online_title := Label.new()
	online_title.text = "Jouer en ligne"
	online_title.add_theme_font_size_override("font_size", 22)
	online_title.add_theme_color_override("font_color", Color("7cfc9a"))
	v.add_child(online_title)

	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	_host = _field(v, "Adresse du serveur", cfg.get_value("net", "host", Net.DEFAULT_HOST))
	# Version des joueurs : toujours le serveur officiel
	if not OS.is_debug_build():
		_host.text = Net.DEFAULT_HOST
		_host.visible = false

	# Canal de connexion : sélection automatique transparente sans encombrer l'écran
	_channel = OptionButton.new()
	for ch in Net.CHANNELS:
		_channel.add_item(ch["name"])
	var saved_chan: int = int(cfg.get_value("net", "channel_idx", 0))
	_channel.select(clampi(saved_chan, 0, Net.CHANNELS.size() - 1))
	_channel.visible = false
	v.add_child(_channel)

	_pseudo = _field(v, "Pseudo (3 à 16 caractères)", cfg.get_value("net", "pseudo", ""))
	_password = _field(v, "Mot de passe", "")
	_password.secret = true

	# Enchaînement rapide et naturel au clavier virtuel
	_pseudo.text_submitted.connect(func(_t): _password.grab_focus())
	_password.text_submitted.connect(func(_t): _on_connect())

	_avatar = OptionButton.new()
	_avatar.custom_minimum_size = Vector2(0, 44)
	_avatar.add_theme_font_size_override("font_size", 18)
	for a in Net.AVATARS:
		_avatar.add_item(AVATAR_NAMES.get(a, a))
	_avatar.select(maxi(0, Net.AVATARS.find(cfg.get_value("net", "avatar", "heros"))))
	v.add_child(_avatar)

	# Code ami optionnel pour rejoindre directement un ami à Dakar
	var f_box := VBoxContainer.new()
	f_box.add_theme_constant_override("separation", 6)
	v.add_child(f_box)

	var f_header := HBoxContainer.new()
	f_header.add_theme_constant_override("separation", 8)
	f_box.add_child(f_header)

	var f_label := Label.new()
	f_label.text = "🤝 Rejoindre un ami (optionnel) :"
	f_label.add_theme_font_size_override("font_size", 15)
	f_label.add_theme_color_override("font_color", Color("90e0ef"))
	f_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	f_header.add_child(f_label)

	var f_row := HBoxContainer.new()
	f_row.add_theme_constant_override("separation", 6)
	f_box.add_child(f_row)

	_friend_code = _field(f_row, "Code ami (ex: GAL-12345)", "")
	_friend_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_friend_code.text_submitted.connect(func(_t): _on_connect())

	var paste_btn := Button.new()
	paste_btn.text = "Coller"
	paste_btn.custom_minimum_size = Vector2(75, 46)
	paste_btn.add_theme_font_size_override("font_size", 15)
	paste_btn.pressed.connect(func():
		var clip := DisplayServer.clipboard_get().strip_edges()
		if clip != "":
			_friend_code.text = clip
	)
	f_row.add_child(paste_btn)

	var my_code_row := HBoxContainer.new()
	my_code_row.add_theme_constant_override("separation", 8)
	f_box.add_child(my_code_row)

	var init_p: String = cfg.get_value("net", "pseudo", "")
	var my_c_val := Net.generate_friend_code(init_p if init_p != "" else "Joueur")
	var my_code_label := Label.new()
	my_code_label.text = "Ton code ami : %s" % my_c_val
	my_code_label.add_theme_font_size_override("font_size", 14)
	my_code_label.add_theme_color_override("font_color", Color("fdef42"))
	my_code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_code_row.add_child(my_code_label)

	var copy_my_code_btn := Button.new()
	copy_my_code_btn.text = "📋 Partager mon code"
	copy_my_code_btn.custom_minimum_size = Vector2(160, 36)
	copy_my_code_btn.add_theme_font_size_override("font_size", 13)
	copy_my_code_btn.pressed.connect(func():
		var cur_p := _pseudo.text.strip_edges()
		var c := Net.generate_friend_code(cur_p if cur_p != "" else "Joueur")
		DisplayServer.clipboard_set(c)
		_status.text = "Code ami %s copié ! Partage-le à ton ami pour jouer ensemble." % c
	)
	my_code_row.add_child(copy_my_code_btn)

	_pseudo.text_changed.connect(func(new_p: String):
		var c := Net.generate_friend_code(new_p.strip_edges() if new_p.strip_edges() != "" else "Joueur")
		my_code_label.text = "Ton code ami : %s" % c
	)

	# Case à cocher "Créer un compte"
	_create = CheckBox.new()
	_create.text = " Nouveau joueur ? Créer un compte"
	_create.custom_minimum_size = Vector2(0, 46)
	_create.add_theme_font_size_override("font_size", 18)
	_create.add_theme_color_override("font_color", Color("e2e8f0"))
	_create.add_theme_color_override("font_pressed_color", Color("7cfc9a"))
	_create.add_theme_color_override("font_hover_color", Color.WHITE)
	_create.add_theme_color_override("font_hover_pressed_color", Color("7cfc9a"))
	
	var create_box := StyleBoxFlat.new()
	create_box.bg_color = Color(0.12, 0.16, 0.22, 0.9)
	create_box.border_color = Color(0.30, 0.40, 0.52, 0.8)
	create_box.border_width_left = 2
	create_box.border_width_top = 2
	create_box.border_width_right = 2
	create_box.border_width_bottom = 2
	create_box.corner_radius_top_left = 8
	create_box.corner_radius_top_right = 8
	create_box.corner_radius_bottom_right = 8
	create_box.corner_radius_bottom_left = 8
	create_box.content_margin_left = 14.0
	create_box.content_margin_right = 14.0
	create_box.content_margin_top = 8.0
	create_box.content_margin_bottom = 8.0
	_create.add_theme_stylebox_override("normal", create_box)
	_create.add_theme_stylebox_override("hover", create_box)
	
	var create_box_pressed := create_box.duplicate() as StyleBoxFlat
	create_box_pressed.bg_color = Color(0.08, 0.24, 0.16, 0.95)
	create_box_pressed.border_color = Color("7cfc9a")
	_create.add_theme_stylebox_override("pressed", create_box_pressed)
	_create.add_theme_stylebox_override("hover_pressed", create_box_pressed)
	v.add_child(_create)

	_connect_btn = _button("Se connecter", _on_connect)
	_connect_btn.custom_minimum_size = Vector2(0, 50)
	_connect_btn.add_theme_font_size_override("font_size", 20)
	v.add_child(_connect_btn)

	_create.toggled.connect(func(pressed: bool):
		if pressed:
			_create.text = " ✓ Créer un nouveau compte"
			_connect_btn.text = "Créer mon compte et jouer"
		else:
			_create.text = " Nouveau joueur ? Créer un compte"
			_connect_btn.text = "Se connecter"
	)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("ffd166"))
	_status.add_theme_font_size_override("font_size", 14)
	v.add_child(_status)

	var note := Label.new()
	note.text = "Ne réutilise pas un mot de passe important. Carte : © OpenStreetMap."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("999999"))
	v.add_child(note)

	var credits := _button("Crédits", _show_credits)
	credits.flat = true
	credits.custom_minimum_size = Vector2(0, 36)
	credits.add_theme_font_size_override("font_size", 16)
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
	e.add_theme_font_size_override("font_size", 17)
	e.focus_entered.connect(func():
		call_deferred("_scroll_to_control", e)
	)
	parent.add_child(e)
	return e


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b


func _on_connect() -> void:
	if _pseudo.text.strip_edges().length() < 3 or _password.text.length() < 4:
		_status.text = "Pseudo d'au moins 3 caractères et mot de passe d'au moins 4 caractères."
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
		cfg.set_value("net", "host", _host.text.strip_edges())
		cfg.set_value("net", "pseudo", _pseudo.text.strip_edges())
		cfg.set_value("net", "avatar", Net.AVATARS[_avatar.selected])
		cfg.set_value("net", "channel_idx", ch_idx)
		cfg.save(SETTINGS)
	if _friend_code and _friend_code.text.strip_edges() != "":
		Net.pending_friend_join_code = _friend_code.text.strip_edges().to_upper()
	_connect_btn.disabled = true
	Net.connect_and_login(target_host, _pseudo.text, _password.text, Net.AVATARS[_avatar.selected], _create.button_pressed, target_port)


func _on_login(ok: bool, message: String) -> void:
	_status.text = message
	_connect_btn.disabled = false
	if ok:
		get_tree().change_scene_to_file(MAIN)
