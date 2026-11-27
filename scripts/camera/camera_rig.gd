extends Node3D
## Caméra à la 3e personne : souris (PC), glisser du doigt (mobile), suit le joueur ou le véhicule.

var target: Node3D
var yaw := 0.0
var pitch := -0.3
var distance := 5.0
var spring: SpringArm3D
var camera: Camera3D
var _look_cooldown := 0.0
var hood_view := false ## vue capot en voiture (touche X, bouton VUE)
var _walk_bob_t := 0.0
var _cam_roll := 0.0


func _ready() -> void:
	spring = SpringArm3D.new()
	spring.spring_length = distance
	spring.margin = 0.3
	var shape := SphereShape3D.new()
	shape.radius = 0.25
	spring.shape = shape
	add_child(spring)
	camera = Camera3D.new()
	camera.far = 700.0
	camera.fov = 70.0
	spring.add_child(camera)
	camera.current = true


func set_target(t: Node3D) -> void:
	target = t
	if spring:
		spring.clear_excluded_objects()
		if t is CollisionObject3D:
			spring.add_excluded_object(t.get_rid())
	var d = t.get("camera_distance")
	distance = d if d != null else 5.0
	var in_car: bool = t.get("max_speed") != null and t.get("size") != null
	if in_car:
		# Repositionnement immédiat et alignement dans le sens de marche du véhicule
		global_position = t.global_position + Vector3(0, 1.6, 0)
		yaw = t.rotation.y
		pitch = -0.22
		_look_cooldown = 0.0
	elif global_position == Vector3.ZERO:
		global_position = t.global_position + Vector3(0, 1.6, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate(event.relative * 0.0035)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not OS.has_feature("mobile") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _rotate(rel: Vector2) -> void:
	yaw -= rel.x
	pitch = clampf(pitch - rel.y, -1.25, 0.35)
	_look_cooldown = 2.0


func _process(delta: float) -> void:
	if GameState.touch_look != Vector2.ZERO:
		_rotate(GameState.touch_look * 0.006)
		GameState.touch_look = Vector2.ZERO
	# Rotation de la caméra au stick droit de la manette (Right Stick)
	var joy_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var joy_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var joy_look := Vector2(joy_x, joy_y)
	if joy_look.length() > 0.15:
		GameState.gamepad_active = true
		var sens: float = 2.8 * delta
		_rotate(Vector2(joy_x * sens, joy_y * sens))
	if target == null or not is_instance_valid(target):
		return
	var vsize = target.get("size")
	var in_car: bool = vsize != null and target.get("max_speed") != null
	if in_car and Input.is_action_just_pressed("camera_view") and not GameState.typing:
		hood_view = not hood_view
	if in_car and hood_view:
		# Vue capot : juste au-dessus du pare-brise, dans l'axe de la voiture
		var hood: Vector3 = target.global_transform * Vector3(0, vsize.y + 0.3, -vsize.z * 0.12)
		global_position = hood
		_look_cooldown -= delta
		if _look_cooldown <= 0.0:
			yaw = lerp_angle(yaw, target.rotation.y, 1.0 - exp(-8.0 * delta))
			pitch = lerpf(pitch, -0.06, 1.0 - exp(-4.0 * delta))
		spring.spring_length = 0.0
		camera.fov = lerpf(camera.fov, 72.0 + 10.0 * clampf(absf(target.speed) / target.max_speed, 0.0, 1.0), 1.0 - exp(-3.0 * delta))
		rotation = Vector3(pitch, yaw, 0.0)
		return
	var dest := target.global_position + Vector3(0, 1.6, 0)
	global_position = global_position.lerp(dest, 1.0 - exp(-14.0 * delta))
	# Champ de vision : s'élargit avec la vitesse (sensation de vitesse en voiture)
	var fov_target := 70.0
	if in_car:
		fov_target += 10.0 * clampf(absf(target.speed) / target.max_speed, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-3.0 * delta))
	# En voiture, la caméra se replace doucement derrière le véhicule.
	_look_cooldown -= delta
	var spd = target.get("speed")
	if spd != null and _look_cooldown <= 0.0 and absf(spd) > 2.0:
		yaw = lerp_angle(yaw, target.rotation.y, 1.0 - exp(-2.5 * delta))
	spring.spring_length = lerpf(spring.spring_length, distance, 1.0 - exp(-4.0 * delta))
	
	# Réalisme de mouvement : balancement naturel de la tête (head-bobbing) à pied
	if not in_car and target.is_on_floor():
		var vel: Vector3 = target.velocity if target.get("velocity") != null else Vector3.ZERO
		var ground_spd := Vector2(vel.x, vel.z).length()
		if ground_spd > 0.4:
			_walk_bob_t += delta * ground_spd * 1.8
			var bob_y := sin(_walk_bob_t * 2.0) * 0.032 * clampf(ground_spd / 4.5, 0.0, 1.0)
			var bob_x := cos(_walk_bob_t) * 0.022 * clampf(ground_spd / 4.5, 0.0, 1.0)
			camera.position = camera.position.lerp(Vector3(bob_x, bob_y, 0.0), 1.0 - exp(-12.0 * delta))
		else:
			camera.position = camera.position.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))

	# Inclinaison dynamique de la caméra (banking roll) en virage
	var roll_target := 0.0
	if in_car:
		var slip_val = target.get("slip")
		if slip_val != null:
			roll_target = clampf(float(slip_val) * 0.12, -0.06, 0.06)
	_cam_roll = lerpf(_cam_roll, roll_target, 1.0 - exp(-6.0 * delta))
	rotation = Vector3(pitch, yaw, _cam_roll)
