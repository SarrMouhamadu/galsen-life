extends Node3D
## GPS : point posé sur la carte, itinéraire par les rues (affiché sur la mini-carte) et balise violette.

const Mk = preload("res://scripts/util/mk.gd")

var city
var player
var route := PackedVector3Array()
var label := ""
var _beam: Node3D
var _t := 0.0


func _ready() -> void:
	_beam = Node3D.new()
	add_child(_beam)
	var m := Mk.cyl(_beam, 1.6, 1.6, 80.0, Vector3(0, 40, 0), Color(0.7, 0.3, 1.0, 0.3), false, 16)
	m.material_override = Mk.mat(Color(0.7, 0.3, 1.0, 0.3), 0.0, true)
	_beam.visible = false


func set_waypoint(pos: Vector3, place_label := "") -> void:
	GameState.waypoint = pos
	label = place_label
	_t = 0.0
	_recompute()
	GameState.notify.emit("GPS : %s (%d m)" % [label if label != "" else "point sur la carte", int(_dist())])


func clear() -> void:
	GameState.waypoint = null
	route = PackedVector3Array()
	label = ""
	_beam.visible = false


func _dist() -> float:
	if GameState.waypoint == null:
		return 0.0
	var wp: Vector3 = GameState.waypoint
	var pp: Vector3 = player.get_world_position()
	return Vector2(wp.x - pp.x, wp.z - pp.z).length()


func _recompute() -> void:
	if GameState.waypoint == null:
		return
	route = city.route(player.get_world_position(), GameState.waypoint, player.current_vehicle != null)
	if route.size() > 0:
		route.insert(0, player.get_world_position())
		route.append(GameState.waypoint)


func _process(delta: float) -> void:
	if GameState.waypoint == null:
		_beam.visible = false
		return
	_beam.visible = true
	_beam.global_position = GameState.waypoint
	_t -= delta
	if _t <= 0.0:
		_t = 1.5
		_recompute()
	if _dist() < 15.0:
		GameState.notify.emit("Tu es arrivé : %s." % (label if label != "" else "destination"))
		clear()
