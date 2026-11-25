extends Node3D
## Soldat à pied : garde la caserne, ou court après le joueur quand il est très recherché.
## Il ne tire pas : s'il rattrape le joueur à pied, c'est l'arrestation.

const RealCharacter = preload("res://scripts/util/real_character.gd")
const Mk = preload("res://scripts/util/mk.gd")
const RUN_SPEED := 5.6

var city
var player
var chasing := false
var guard_post := Vector3.ZERO
var _model: Node3D
var _bubble: Label3D
var _bubble_t := 0.0
var _route := PackedVector3Array()
var _route_t := 0.0
var _anim_t := 0.0


func setup(p_city, p_player, pos: Vector3, guard := false) -> void:
	city = p_city
	player = p_player
	add_to_group("soldiers")
	_model = RealCharacter.create(self, RealCharacter.SOLDIER)
	_bubble = Mk.label(self, "", Vector3(0, 2.1, 0), Mk.NAME_SIZE, Color("ffd166"))
	_bubble.visible = false
	global_position = pos
	guard_post = pos
	chasing = not guard


func say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = 2.5


## Distance au joueur (à plat)
func player_distance() -> float:
	var pp: Vector3 = player.get_world_position()
	return Vector2(pp.x - global_position.x, pp.z - global_position.z).length()


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	var pp: Vector3 = player.get_world_position()
	var target := guard_post
	if chasing:
		target = pp
		_route_t -= delta
		if player_distance() > 15.0:
			if _route_t <= 0.0 or _route.size() < 2:
				_route = city.route(global_position, pp)
				_route_t = 1.0
			for p in _route:
				if Vector2(p.x - global_position.x, p.z - global_position.z).length() > 3.0:
					target = p
					break
	var to := target - global_position
	to.y = 0.0
	var moving := to.length() > 0.6
	if moving:
		var spd := RUN_SPEED if chasing else 1.4
		global_position += to.normalized() * minf(spd * delta, to.length())
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-10.0 * delta))
		_model.locomote(spd)
	else:
		# Au garde-à-vous, tourné vers le joueur s'il approche
		if not chasing and player_distance() < 15.0:
			var tp := pp - global_position
			_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-tp.x, -tp.z), 1.0 - exp(-5.0 * delta))
		_model.locomote(0.0)
