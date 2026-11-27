extends Control
## Carte complète de Dakar (touche M ou bouton CARTE) : zoom, déplacement, lieux, arrêts de bus,
## entreprises. Un clic (ou un appui) pose le point GPS ; un second clic dessus l'efface.

const LABELLED := ["Place de l'Indépendance", "Monument de la Renaissance Africaine", "Marché Sandaga", "Grande Mosquée", "Hôpital Principal", "Gare de Dakar",
	"Marché Kermel", "Marché Tilène", "Gare routière Petersen", "Cathédrale", "Assemblée nationale",
	"Porte du Millénaire", "Phare des Mamelles", "Commissariat", "Caserne", "Plage de l'Anse Bernard", "Stade Iba Mar Diop",
	"Église Saint-Laurent", "Orange Money", "Wave", "Jumbo", "Jadida", "Chez Adja", "Café Touba", "Dibiterie", "Restaurant Maïga", "Garage Taxi"]

var main
var zoom := 1.0
var center := Vector2.ZERO ## point du monde (x, z) au centre de l'écran
var _bar: HBoxContainer
var _dragging := false
var _drag_moved := 0.0
var _press_pos := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var bar := HBoxContainer.new()
	_bar = bar
	bar.position = Vector2(16, 16)
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	for spec in [["Fermer", func(): close()], ["+", func(): _zoom_by(1.4)], ["−", func(): _zoom_by(1.0 / 1.4)],
			["Effacer le GPS", func(): main.gps.clear()], ["Ma position", func(): _center_on_player()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(70, 52)
		b.add_theme_font_size_override("font_size", 20)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(spec[1])
		bar.add_child(b)


func open() -> void:
	visible = true
	var margins: Dictionary = GameState.get_safe_margins(get_viewport())
	if _bar:
		_bar.position = Vector2(margins.left, margins.top)
	_center_on_player()
	var city = main.city
	zoom = minf(size.x / city.bounds.size.x, size.y / city.bounds.size.y) * 2.2
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


func _center_on_player() -> void:
	var pp: Vector3 = main.player.get_world_position()
	center = Vector2(pp.x, pp.z)
	queue_redraw()


func _zoom_by(f: float) -> void:
	zoom = clampf(zoom * f, 0.1, 8.0)
	queue_redraw()


func _to_screen(w: Vector2) -> Vector2:
	return size / 2.0 + (w - center) * zoom


func _to_world(s: Vector2) -> Vector2:
	return center + (s - size / 2.0) / zoom


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_by(1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_by(1.0 / 1.2)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
				_press_pos = event.position
			else:
				_dragging = false
				if _drag_moved < 8.0:
					_tap(event.position)
	elif event is InputEventMouseMotion and _dragging:
		center -= event.relative / zoom
		_drag_moved += event.relative.length()
		queue_redraw()
	elif event is InputEventMagnifyGesture:
		_zoom_by(event.factor)


func _tap(pos: Vector2) -> void:
	var w := _to_world(pos)
	var gps = main.gps
	if GameState.waypoint != null:
		var wp: Vector3 = GameState.waypoint
		if _to_screen(Vector2(wp.x, wp.z)).distance_to(pos) < 18.0:
			gps.clear()
			queue_redraw()
			return
	# Accroche au lieu le plus proche si on clique dessus
	var target := Vector3(w.x, 0, w.y)
	var label := ""
	for place_name in main.city.places:
		var p: Vector3 = main.city.places[place_name]
		if _to_screen(Vector2(p.x, p.z)).distance_to(pos) < 14.0:
			target = p
			label = place_name
			break
	gps.set_waypoint(target, label)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("map") or event.is_action_pressed("pause")):
		close()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if main == null:
		return
	var city = main.city
	draw_rect(Rect2(Vector2.ZERO, size), Color("2a6f97"))
	var tex: Texture2D = city.minimap_texture
	var origin := Vector2(city.bounds.position.x, city.bounds.position.y)
	draw_texture_rect(tex, Rect2(_to_screen(origin), city.bounds.size * zoom), false)
	var font := get_theme_default_font()
	# Itinéraire GPS
	var route: PackedVector3Array = main.gps.route
	for i in range(1, route.size()):
		draw_line(_to_screen(Vector2(route[i - 1].x, route[i - 1].z)), _to_screen(Vector2(route[i].x, route[i].z)), Color("b14cff"), 4.0)
	# Arrêts de bus
	for s in main.transit.stops:
		var sp := _to_screen(Vector2(s["pos"].x, s["pos"].z))
		draw_rect(Rect2(sp - Vector2(5, 5), Vector2(10, 10)), Color("f39200") if s["line"] == "Ligne 1" else Color("2f7fc0"))
	# Feux de circulation
	if city.lights:
		for n in city.signal_nodes:
			var npos: Vector3 = city.node_pos[n]
			var sp := _to_screen(Vector2(npos.x, npos.z))
			if sp.x < -20 or sp.y < -20 or sp.x > size.x + 20 or sp.y > size.y + 20:
				continue
			var st: int = city.lights.state(n, 0)
			var col: Color = Color("22ff55") if st == 0 else (Color("ffb000") if st == 1 else Color("ff2020"))
			draw_circle(sp, 4.0, col)
			draw_arc(sp, 4.0, 0.0, TAU, 12, Color(0, 0, 0, 0.8), 1.0)
	# Lieux
	for place_name in city.places:
		var p: Vector3 = city.places[place_name]
		var sp := _to_screen(Vector2(p.x, p.z))
		if sp.x < -50 or sp.y < -50 or sp.x > size.x + 50 or sp.y > size.y + 50:
			continue
		var col := Color("ffd166")
		if place_name.begins_with("Orange Money"):
			col = Color("ff7900")
		elif place_name.begins_with("Wave"):
			col = Color("1dc3f3")
		draw_circle(sp, 6.0, col)
		draw_arc(sp, 6.0, 0.0, TAU, 16, Color.BLACK, 1.5)
		if place_name in LABELLED or zoom > 1.2:
			draw_string(font, sp + Vector2(9, 5), place_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	# Point GPS
	if GameState.waypoint != null:
		var wp: Vector3 = GameState.waypoint
		var ws := _to_screen(Vector2(wp.x, wp.z))
		draw_circle(ws, 10.0, Color("b14cff"))
		draw_arc(ws, 10.0, 0.0, TAU, 20, Color.WHITE, 2.0)
	# Joueur
	var pp: Vector3 = main.player.get_world_position()
	var ps := _to_screen(Vector2(pp.x, pp.z))
	draw_circle(ps, 9.0, Color.WHITE)
	draw_circle(ps, 6.0, Color("e63946"))
	draw_string(font, Vector2(16, size.y - 20), "Clique pour poser le GPS • molette ou +/− pour zoomer • glisse pour déplacer • M pour fermer • Carte © OpenStreetMap",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
