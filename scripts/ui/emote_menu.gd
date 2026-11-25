extends PanelContainer
## Menu des gestes (bouton GESTES du HUD ou touche G) : saluer, téléphoner, applaudir, danser...
## Le geste dure jusqu'à ce que le joueur bouge ; en ligne, les joueurs proches le voient.

const NetEmotes = preload("res://scripts/net/net_emotes.gd")

var main


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -24.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.92)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for e in NetEmotes.LIST:
		grid.add_child(_button(e[0], _pick.bind(e[1])))
	grid.add_child(_button("Arrêter", _pick.bind(""), Color("6c757d")))
	grid.add_child(_button("Fermer", close, Color("2b2d33")))


func _button(text: String, cb: Callable, color := Color("3a86ff")) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 50)
	b.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = color.lightened(0.15) if state == "hover" else (color.darkened(0.2) if state == "pressed" else color)
		s.set_corner_radius_all(10)
		b.add_theme_stylebox_override(state, s)
	b.pressed.connect(cb)
	return b


func _pick(clip: String) -> void:
	var p = main.player
	if p:
		if clip == "":
			p.stop_emote()
		else:
			p.start_emote(clip)
	close()


func toggle() -> void:
	visible = not visible


func close() -> void:
	visible = false


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G and not GameState.typing:
		toggle()
