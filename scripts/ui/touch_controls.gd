extends Control
## Commandes tactiles multi-doigts.
## - À pied : joystick flottant à gauche (zone morte, course quand on pousse à fond), boutons ACTION,
##   SAUT, COURIR (et VOLER près d'une voiture) à droite.
## - En voiture : le joystick ne sert qu'au volant ; pédales GAZ et FREIN (frein puis marche arrière)
##   à droite, KLAXON et ACTION (descendre).
## - Glisser ailleurs sur l'écran tourne la caméra.
## Tout est mis à l'échelle de l'écran ; réglages (taille, transparence, sensibilité de la caméra,
## vibrations, place de chaque bouton) dans le menu pause, enregistrés dans user://controls.cfg.

const CFG := "user://controls.cfg"
const BASE_JOY := 110.0
const DEADZONE := 0.12
const SIZES := {"petite": 0.82, "normale": 1.0, "grande": 1.22}
const SENS := {"lente": 0.6, "normale": 1.0, "rapide": 1.6}
const OPACITY := {"normale": 1.0, "discrète": 0.55, "forte": 1.45}

static var size_pref := "normale"
static var sens_pref := "normale"
static var vibrate := true
static var opacity_pref := "normale"
## Places choisies par le joueur : "foot/interact" → décalage depuis le coin bas-droit, "joy" → repos du
## joystick depuis le coin bas-gauche (en points à l'échelle 1)
static var layout := {}
static var _loaded := false

var in_vehicle := false:
	set(value):
		if value != in_vehicle:
			in_vehicle = value
			release_all()

var can_steal := false:
	set(value):
		if value != can_steal:
			can_steal = value
			queue_redraw()
var veh_label := "MONTER":
	set(value):
		if value != veh_label:
			veh_label = value
			queue_redraw()

## Pendant un match de mini-foot : ACTION → TIR / TACLE, COUP → PASSE / APPEL, SAUT → FEINTE
var foot_mode := false:
	set(value):
		if value != foot_mode:
			foot_mode = value
			queue_redraw()
var foot_labels := {"interact": "TIR", "attack": "PASSE", "jump": "FEINTE"}:
	set(value):
		if value != foot_labels:
			foot_labels = value
			queue_redraw()

var _joy_index := -1
var _joy_center := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _look_index := -1
var _btn_touch := {} ## doigt → bouton (Dictionary)
## Mode « Placer les boutons » (menu pause) : on fait glisser les boutons, aucune action n'est envoyée
var editing := false:
	set(value):
		editing = value
		release_all()
var _grab := {} ## doigt → clé du bouton déplacé ("foot/jump", "joy")
## Boutons : décalage depuis le coin bas-droit (en points à l'échelle 1), rayon
const FOOT := [
	{"action": "interact", "label": "ACTION", "offset": Vector2(-125, -270), "r": 62.0},
	{"action": "jump", "label": "SAUT", "offset": Vector2(-270, -125), "r": 62.0},
	{"action": "steal", "label": "MONTER", "offset": Vector2(-265, -275), "r": 60.0, "cond": "steal"},
	{"action": "sprint", "label": "COURIR", "offset": Vector2(-120, -120), "r": 70.0},
	{"action": "attack", "label": "COUP", "offset": Vector2(-125, -415), "r": 54.0},
]
const CAR := [
	{"action": "gas", "label": "GAZ", "offset": Vector2(-110, -150), "r": 80.0, "pedal": true},
	{"action": "brake", "label": "FREIN", "offset": Vector2(-280, -110), "r": 66.0, "pedal": true},
	{"action": "interact", "label": "ACTION", "offset": Vector2(-265, -265), "r": 52.0},
	{"action": "horn", "label": "KLAXON", "offset": Vector2(-425, -205), "r": 48.0},
	{"action": "camera_view", "label": "VUE", "offset": Vector2(-410, -340), "r": 40.0},
]


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		size_pref = cfg.get_value("touch", "size", size_pref)
		sens_pref = cfg.get_value("touch", "sens", sens_pref)
		vibrate = cfg.get_value("touch", "vibrate", vibrate)
		opacity_pref = cfg.get_value("touch", "opacity", opacity_pref)
		layout = cfg.get_value("touch", "layout", {})
	if not SIZES.has(size_pref):
		size_pref = "normale"
	if not SENS.has(sens_pref):
		sens_pref = "normale"
	if not OPACITY.has(opacity_pref):
		opacity_pref = "normale"


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("touch", "size", size_pref)
	cfg.set_value("touch", "sens", sens_pref)
	cfg.set_value("touch", "vibrate", vibrate)
	cfg.set_value("touch", "opacity", opacity_pref)
	cfg.set_value("touch", "layout", layout)
	cfg.save(CFG)


## Réglages du menu pause : passe à la valeur suivante et renvoie le texte du bouton
static func cycle_size() -> String:
	var keys := SIZES.keys()
	size_pref = keys[(keys.find(size_pref) + 1) % keys.size()]
	save_settings()
	return size_text()


static func cycle_sens() -> String:
	var keys := SENS.keys()
	sens_pref = keys[(keys.find(sens_pref) + 1) % keys.size()]
	save_settings()
	return sens_text()


static func cycle_opacity() -> String:
	var keys := OPACITY.keys()
	opacity_pref = keys[(keys.find(opacity_pref) + 1) % keys.size()]
	save_settings()
	return opacity_text()


static func reset_layout() -> void:
	layout = {}
	save_settings()


static func toggle_vibrate() -> String:
	vibrate = not vibrate
	save_settings()
	return vib_text()


static func size_text() -> String:
	return "Boutons tactiles : %s" % size_pref


static func sens_text() -> String:
	return "Caméra (glisser) : %s" % sens_pref


static func opacity_text() -> String:
	return "Transparence : %s" % opacity_pref


static func vib_text() -> String:
	return "Vibrations : %s" % ("oui" if vibrate else "non")


func _ready() -> void:
	load_settings()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Échelle : taille de l'écran (référence 1280 × 720) × préférence du joueur
## BASE_SCALE : les boutons ronds et le joystick étaient trop gros sur téléphone (réduits d'un quart)
const BASE_SCALE := 0.75


func _scale() -> float:
	return clampf(minf(size.x / 1280.0, size.y / 720.0), 0.75, 1.8) * float(SIZES[size_pref]) * BASE_SCALE


func _buttons() -> Array:
	return CAR if in_vehicle else FOOT


func _key(b: Dictionary) -> String:
	return ("car/" if in_vehicle else "foot/") + String(b["action"])


## Centre d'un bouton à l'écran (place choisie par le joueur, sinon place d'origine), toujours dans l'écran
func _center(b: Dictionary, s: float) -> Vector2:
	var off: Vector2 = layout.get(_key(b), b["offset"])
	var r: float = b["r"] * s
	var c := size + off * s
	return Vector2(clampf(c.x, r, size.x - r), clampf(c.y, r, size.y - r))


## Repos du joystick
func _joy_home(s: float) -> Vector2:
	var off: Vector2 = layout.get("joy", Vector2(185.0, -175.0))
	var jr := BASE_JOY * s
	return Vector2(clampf(off.x * s, jr, size.x - jr), clampf(size.y + off.y * s, jr, size.y - jr))


## Le doigt qui se pose ici prend le joystick : bas de l'écran du côté du joystick (à droite s'il y a
## été déplacé), ou tout près de sa place
func _in_joy_zone(p: Vector2) -> bool:
	var s := _scale()
	var home := _joy_home(s)
	if p.distance_to(home) < BASE_JOY * s * 1.6:
		return true
	if p.y < size.y * 0.3:
		return false
	return p.x < size.x * 0.42 if home.x < size.x * 0.5 else p.x > size.x * 0.58


func release_all() -> void:
	for idx in _btn_touch:
		var b: Dictionary = _btn_touch[idx]
		if not b.get("pedal", false):
			Input.action_release(b["action"])
	_btn_touch.clear()
	_grab.clear()
	_joy_index = -1
	_look_index = -1
	_joy_vec = Vector2.ZERO
	GameState.touch_move = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if editing:
		_edit_input(event)
		return
	if event is InputEventScreenTouch:
		if GameState.gamepad_active:
			GameState.gamepad_active = false
		var le = make_input_local(event)
		var p: Vector2 = le.position
		var idx: int = le.index
		if le.pressed:
			var b = _button_at(p)
			if b != null:
				_btn_touch[idx] = b
				if not b.get("pedal", false):
					Input.action_press(b["action"])
				if vibrate:
					Input.vibrate_handheld(18)
			elif _joy_index == -1 and _in_joy_zone(p):
				_joy_index = idx
				_joy_center = p
				_joy_vec = Vector2.ZERO
			elif _look_index == -1:
				_look_index = idx
		else:
			if _btn_touch.has(idx):
				var rb: Dictionary = _btn_touch[idx]
				if not rb.get("pedal", false):
					Input.action_release(rb["action"])
				_btn_touch.erase(idx)
			if idx == _joy_index:
				_joy_index = -1
				_joy_vec = Vector2.ZERO
			if idx == _look_index:
				_look_index = -1
		_update_move()
		queue_redraw()
	elif event is InputEventScreenDrag:
		var le = make_input_local(event)
		if le.index == _joy_index:
			var v: Vector2 = ((le.position - _joy_center) / (BASE_JOY * _scale())).limit_length(1.0)
			# Zone morte : un petit effleurement ne fait pas bouger
			_joy_vec = Vector2.ZERO if v.length() < DEADZONE else v.normalized() * inverse_lerp(DEADZONE, 1.0, v.length())
			_update_move()
			queue_redraw()
		elif le.index == _look_index:
			GameState.touch_look += le.relative * float(SENS[sens_pref])


## Placer les boutons : un doigt attrape le bouton (ou le joystick) sous lui et le fait glisser
func _edit_input(event: InputEvent) -> void:
	var s := _scale()
	if event is InputEventScreenTouch:
		if GameState.gamepad_active:
			GameState.gamepad_active = false
		var le = make_input_local(event)
		if le.pressed:
			var b = _button_at(le.position, true)
			if b != null:
				_grab[le.index] = _key(b)
			elif le.position.distance_to(_joy_home(s)) < BASE_JOY * s:
				_grab[le.index] = "joy"
		elif _grab.has(le.index):
			_grab.erase(le.index)
			save_settings()
		queue_redraw()
	elif event is InputEventScreenDrag:
		var le = make_input_local(event)
		if not _grab.has(le.index):
			return
		var k: String = _grab[le.index]
		if k == "joy":
			layout["joy"] = Vector2(le.position.x, le.position.y - size.y) / s
		else:
			layout[k] = (le.position - size) / s
		queue_redraw()


## Direction envoyée au jeu : joystick à pied ; en voiture, volant au joystick et pédales
func _update_move() -> void:
	if not in_vehicle:
		GameState.touch_move = _joy_vec
		return
	var pedal := 0.0
	for b in _btn_touch.values():
		if b["action"] == "gas":
			pedal -= 1.0
		elif b["action"] == "brake":
			pedal += 1.0
	GameState.touch_move = Vector2(_joy_vec.x, clampf(pedal, -1.0, 1.0))


func is_pressed(action: String) -> bool:
	for b in _btn_touch.values():
		if b["action"] == action:
			return true
	return false


func _visible_button(b: Dictionary) -> bool:
	return editing or b.get("cond", "") != "steal" or can_steal


func _button_at(p: Vector2, all := false) -> Variant:
	var s := _scale()
	for b in _buttons():
		if not all and not _visible_button(b):
			continue
		if p.distance_to(_center(b, s)) < b["r"] * s * 1.12: # zone un peu plus large que le dessin
			return b
	return null


## Couleur avec la transparence choisie par le joueur (plus visible en mode placement)
func _a(c: Color) -> Color:
	var k: float = 1.25 if editing else float(OPACITY[opacity_pref])
	return Color(c.r, c.g, c.b, clampf(c.a * k, 0.0, 0.95))


func _process(_delta: float) -> void:
	if not editing:
		var want_visible: bool = GameState.touch_ui and not GameState.gamepad_active
		if visible != want_visible:
			visible = want_visible


func _draw() -> void:
	if GameState.gamepad_active and not editing:
		return
	var s := _scale()
	var font := get_theme_default_font()
	var jr := BASE_JOY * s
	var base := _joy_center if _joy_index != -1 else _joy_home(s)
	draw_circle(base, jr, _a(Color(1, 1, 1, 0.12)))
	draw_arc(base, jr, 0.0, TAU, 48, _a(Color(1, 1, 1, 0.35)), 3.0)
	if not in_vehicle:
		draw_arc(base, jr * 0.92, 0.0, TAU, 48, _a(Color(1, 0.82, 0.25, 0.25)), 2.0) # au bord : on court
	else:
		draw_line(base - Vector2(jr, 0), base + Vector2(jr, 0), _a(Color(1, 1, 1, 0.25)), 2.0) # volant : gauche / droite
	draw_circle(base + _joy_vec * jr, 46.0 * s, _a(Color(1, 1, 1, 0.42)))
	if editing and _grab.values().has("joy"):
		draw_arc(base, jr + 6.0, 0.0, TAU, 48, Color(1, 0.82, 0.25, 0.9), 4.0)
	for b in _buttons():
		if not _visible_button(b):
			continue
		var c: Vector2 = _center(b, s)
		var r: float = b["r"] * s
		var on := is_pressed(b["action"]) or (editing and _grab.values().has(_key(b)))
		var fill := Color(0, 0, 0, 0.35)
		if b["action"] == "gas":
			fill = Color(0.1, 0.55, 0.25, 0.75 if on else 0.45)
		elif b["action"] == "brake":
			fill = Color(0.75, 0.15, 0.15, 0.75 if on else 0.45)
		elif b["action"] == "steal":
			fill = Color(0.95, 0.55, 0.1, 0.85 if on else 0.55)
		elif on:
			fill = Color(1, 0.82, 0.25, 0.55)
		draw_circle(c, r, _a(fill))
		var ring_col := Color(1.0, 0.85, 0.25, 0.95) if b["action"] == "steal" else Color(1, 1, 1, 0.65)
		draw_arc(c, r, 0.0, TAU, 40, _a(ring_col), 3.5 if b["action"] == "steal" else 3.0)
		var fs := int(20 * s)
		var text: String = b["label"]
		if foot_mode and not in_vehicle:
			text = foot_labels.get(b["action"], b["label"])
		elif b["action"] == "steal":
			text = veh_label
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-ts.x / 2.0, fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _a(Color(1, 1, 1, 0.95)))
