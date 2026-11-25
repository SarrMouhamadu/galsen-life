extends Control
## Mini-carte orientée nord, centrée sur le joueur (fond : carte OpenStreetMap pré-dessinée).

const MAP_SCALE := 0.7 ## pixels par mètre
const PLACE_COLORS := {
	"Hôpital Principal": Color("e63946"),
	"Commissariat": Color("3a86ff"),
	"Café Touba": Color("b5651d"),
	"Chez Adja": Color("f4a261"),
	"Dibiterie": Color("d62828"),
	"Restaurant Maïga": Color("e67e22"),
	"Garage Taxi": Color("ffc300"),
}

var main
var _redraw_t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(140, 140)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	# 20 images/s suffisent pour une mini-carte (économise le processeur des téléphones)
	_redraw_t -= delta
	if _redraw_t <= 0.0:
		_redraw_t = 0.05
		queue_redraw()


func _to_map(w: Vector3, pp: Vector3) -> Vector2:
	return size / 2.0 + Vector2(w.x - pp.x, w.z - pp.z) * MAP_SCALE


func _rect(a: Vector3, b: Vector3, pp: Vector3) -> Rect2:
	var ta := _to_map(a, pp)
	return Rect2(ta, _to_map(b, pp) - ta)


func _draw() -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	var pp: Vector3 = p.get_world_position()
	var center := size / 2.0
	if main.arena and main.arena.contains(pp):
		# À l'arène : plan de l'ovale et de l'aire de combat
		draw_rect(Rect2(Vector2.ZERO, size), Color("cdb68a"))
		var o: Vector3 = main.arena.ORIGIN
		var pts := PackedVector2Array()
		for k in 33:
			var a := k * TAU / 32.0
			pts.append(_to_map(o + Vector3(cos(a) * 70.0, 0, sin(a) * 58.0), pp))
		draw_polyline(pts, Color("00853f"), 6.0)
		draw_circle(_to_map(o, pp), 14.0 * MAP_SCALE, Color("e6cc8f"))
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(6, 6), center + Vector2(-6, 6)]), Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7), false, 3.0)
		return
	if main.foot and main.foot.contains(pp):
		# Au complexe de mini-foot : les trois terrains, le ballon pendant un match
		draw_rect(Rect2(Vector2.ZERO, size), Color("c9b28a"))
		var F = main.foot
		for z in F.PITCHES:
			draw_rect(_rect(F.ORIGIN + Vector3(-F.L / 2.0, 0, z - F.W / 2.0), F.ORIGIN + Vector3(F.L / 2.0, 0, z + F.W / 2.0), pp), Color("2f8f3a"))
		var bw: Vector3 = F.ball_world()
		if bw.is_finite():
			draw_circle(_to_map(bw, pp), 3.0, Color.WHITE)
		draw_colored_polygon(PackedVector2Array([center + Vector2(0, -9), center + Vector2(6, 6), center + Vector2(-6, 6)]), Color("ffd166"))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7), false, 3.0)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("2a6f97"))
	var city = main.city
	var tex: Texture2D = city.minimap_texture
	var res: float = city.map_res
	var origin := Vector2(city.bounds.position.x, city.bounds.position.y)
	# Zone du monde visible → rectangle de la texture, rogné aux bords de la carte
	var half_world := size / 2.0 / MAP_SCALE
	var w0 := Vector2(pp.x, pp.z) - half_world
	var w1 := Vector2(pp.x, pp.z) + half_world
	var c0 := w0.max(origin)
	var c1 := w1.min(origin + city.bounds.size)
	if c1.x > c0.x and c1.y > c0.y:
		var src := Rect2((c0 - origin) / res, (c1 - c0) / res)
		var dst := Rect2((c0 - w0) * MAP_SCALE, (c1 - c0) * MAP_SCALE)
		draw_texture_rect_region(tex, dst, src)
	var view := Rect2(Vector2(-6, -6), size + Vector2(12, 12))
	for place_name in main.city.places:
		var mp := _to_map(main.city.places[place_name], pp)
		if view.has_point(mp):
			draw_circle(mp, 3.5, PLACE_COLORS.get(place_name, Color("ffffff")))

	# Membres de mon groupe (même loin)
	if main.social_ui:
		for gid in main.social_ui.group_pos:
			var gp: Vector2 = _to_map(main.social_ui.group_pos[gid], pp)
			if Rect2(Vector2.ZERO, size).has_point(gp):
				draw_circle(gp, 5.0, Color("06d6a0"))
				draw_arc(gp, 5.0, 0.0, TAU, 12, Color.BLACK, 1.5)
	# Itinéraire GPS
	if main.gps:
		var route: PackedVector3Array = main.gps.route
		for i in range(1, route.size()):
			draw_line(_to_map(route[i - 1], pp), _to_map(route[i], pp), Color("b14cff"), 3.0)
		if GameState.waypoint != null:
			var wp := _to_map(GameState.waypoint, pp).clamp(Vector2(8, 8), size - Vector2(8, 8))
			draw_circle(wp, 6.0, Color("b14cff"))

	# Arrêts de bus
	if main.transit:
		for s in main.transit.stops:
			var sp := _to_map(s["pos"], pp)
			if not view.has_point(sp):
				continue
			var lc := Color("f39200") if s["line"] == "Ligne 1" else Color("2f7fc0")
			draw_rect(Rect2(sp - Vector2(3.5, 3.5), Vector2(7, 7)), lc)
			draw_rect(Rect2(sp - Vector2(3.5, 3.5), Vector2(7, 7)), Color.WHITE, false, 1.0)

	# Feux de circulation
	if main.city and main.city.lights:
		var lights = main.city.lights
		for n in main.city.signal_nodes:
			var npos: Vector3 = main.city.node_pos[n]
			var lp := _to_map(npos, pp)
			if not view.has_point(lp):
				continue
			var st: int = lights.state(n, 0)
			var col: Color = Color("22ff55") if st == 0 else (Color("ffb000") if st == 1 else Color("ff2020"))
			draw_circle(lp, 3.5, col)
			draw_arc(lp, 3.5, 0.0, TAU, 12, Color(0, 0, 0, 0.7), 1.0)

	# Objectif (collé au bord s'il est hors de la carte)
	if main.jobs.has_target:
		var tp := _to_map(main.jobs.target_pos, pp)
		tp = tp.clamp(Vector2(8, 8), size - Vector2(8, 8))
		draw_circle(tp, 7.0, Color("ffd23f"))
		draw_arc(tp, 7.0, 0.0, TAU, 20, Color.BLACK, 1.5)

	# Police : clignote rouge/bleu pendant une poursuite
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	for u in main.police.units:
		if not is_instance_valid(u) or u.driver != null:
			continue
		var up := _to_map(u.global_position, pp)
		if not Rect2(Vector2.ZERO, size).has_point(up):
			continue
		var col: Color = (Color("ff1f3d") if blink else Color("2f6bff")) if u.chasing else Color("1d3557")
		if u.vehicle_type == "army":
			col = Color("9acd32") if blink else Color("4b5320")
		draw_circle(up, 4.5, col)

	# Joueur
	var carrier = p.current_vehicle if p.current_vehicle else p.riding
	var heading: float = carrier.rotation.y if carrier else p.model.rotation.y
	var fwd := Vector2(-sin(heading), -cos(heading))
	var right := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([
		center + fwd * 10.0, center - fwd * 6.0 + right * 7.0,
		center - fwd * 2.0, center - fwd * 6.0 - right * 7.0]), Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7), false, 3.0)
	draw_string(get_theme_default_font(), Vector2(size.x / 2.0 - 5.0, 16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
