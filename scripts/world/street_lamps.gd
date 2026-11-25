extends Node3D
## Lampadaires le long des rues (un tous les ~28 m sur les trottoirs), dessinés en MultiMesh (très peu coûteux).
## La nuit : têtes lumineuses et flaques de lumière orangée (sodium) sur le sol et les murs, calculées par les
## shaders de la ville (world/shaders/city_lamps.gdshaderinc) pour les lampadaires les plus proches de la caméra
## (6 / 10 / 16 / 24 selon le profil), plus loin un simple halo au sol. Quelques vraies lumières (0 / 4 / 8)
## éclairent en plus les personnages et les voitures, mais pas la ville (déjà éclairée par ses shaders).

const SPACING := 28.0
const MIN_ROAD := 5.0
const HEIGHT := 7.0
const LAMP_COLOR := Color("ffb86b")

var main
var city
var lamps: Array = [] ## [position du pied, direction du bras]
var _hash := {} ## cellule de 40 m → indices
var _head_mat: StandardMaterial3D
var _glow_mat: ShaderMaterial
var _lights: Array[OmniLight3D] = []
var _night := 0.0
var _scan_t := 0.0
var _img: Image ## un texel RGBA32F par lampadaire proche (position de la tête, intensité)
var _tex: ImageTexture
const POOL_MAX := 32
const CITY_LAYER := 2 ## couche visuelle des maillages de la ville : les vraies lumières l'ignorent


func _ready() -> void:
	_place_lamps()
	_build_meshes()
	_img = Image.create_empty(POOL_MAX, 1, false, Image.FORMAT_RGBAF)
	_tex = ImageTexture.create_from_image(_img)
	RenderingServer.global_shader_parameter_set("city_lamps", _tex)
	RenderingServer.global_shader_parameter_set("city_lamp_night", 0.0)
	_city_layer(city)
	_ensure_lights()
	Graphics.changed.connect(_ensure_lights)


func _place_lamps() -> void:
	var taken := {}
	var done := {}
	for key in city._edge:
		var a: int = key.x
		var b: int = key.y
		if a > b or done.has(key):
			continue
		done[key] = true
		var info: Array = city._edge[key]
		if (int(info[1]) & city.DRIVE) == 0 or float(info[0]) < MIN_ROAD:
			continue
		var L: float = city.segment_length(a, b)
		var t := 5.0
		var side := 1 if (a + b) % 2 == 0 else -1
		while t < L - 2.0:
			# Au bord du trottoir, côté chaussée
			var p: Vector3 = city.sidewalk_point(a, b, t, side)
			var dd: Vector3 = (city.node_pos[b] - city.node_pos[a]).normalized()
			p -= Vector3(-dd.z, 0, dd.x) * side * 0.55
			var cell := Vector2i(floori(p.x / SPACING), floori(p.z / SPACING))
			# Pas de lampadaire sur une chaussée (carrefour, rue qui croise)
			var free: bool = not city.in_roadway(p, 0.2)
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for q in taken.get(cell + Vector2i(dx, dz), []):
						if Vector2(q.x - p.x, q.z - p.z).length() < SPACING:
							free = false
			if free:
				if not taken.has(cell):
					taken[cell] = []
				taken[cell].append(p)
				var road: Vector3 = (city.node_pos[a] + city.node_pos[b]) * 0.5
				var arm := Vector3(road.x - p.x, 0, road.z - p.z)
				# Le bras pointe vers la chaussée (perpendiculaire à la rue)
				var d: Vector3 = (city.node_pos[b] - city.node_pos[a]).normalized()
				var perp := Vector3(-d.z, 0, d.x)
				arm = perp if perp.dot(arm) > 0.0 else -perp
				lamps.append([p, arm])
				var hc := Vector2i(floori(p.x / 40.0), floori(p.z / 40.0))
				if not _hash.has(hc):
					_hash[hc] = PackedInt32Array()
				_hash[hc].append(lamps.size() - 1)
			t += 10.0


func _mm(mesh: Mesh, transforms: Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	return mi


func _build_meshes() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.1
	pole.height = HEIGHT
	pole.radial_segments = 6
	pole.rings = 1
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color("5b6168")
	pole_mat.roughness = 0.5
	pole_mat.metallic = 0.6
	pole.material = pole_mat
	var arm := BoxMesh.new()
	arm.size = Vector3(0.08, 0.08, 1.6)
	arm.material = pole_mat
	var head := BoxMesh.new()
	head.size = Vector3(0.32, 0.12, 0.7)
	_head_mat = StandardMaterial3D.new()
	_head_mat.albedo_color = Color("d8d8d0")
	_head_mat.emission_enabled = true
	_head_mat.emission = LAMP_COLOR
	_head_mat.emission_energy_multiplier = 0.0
	head.material = _head_mat
	var glow := PlaneMesh.new()
	glow.size = Vector2(13, 13)
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = _glow_shader()
	glow.material = _glow_mat
	var tp: Array = []
	var ta: Array = []
	var th: Array = []
	var tg: Array = []
	for l in lamps:
		var p: Vector3 = l[0]
		var d: Vector3 = l[1]
		var yaw := atan2(d.x, d.z)
		var basis := Basis(Vector3.UP, yaw)
		tp.append(Transform3D(Basis(), p + Vector3(0, HEIGHT * 0.5, 0)))
		ta.append(Transform3D(basis, p + Vector3(0, HEIGHT - 0.1, 0) + d * 0.75))
		th.append(Transform3D(basis, p + Vector3(0, HEIGHT - 0.2, 0) + d * 1.5))
		tg.append(Transform3D(Basis(), Vector3(p.x, 0.0, p.z) + d * 1.8 + Vector3(0, 0.1, 0)))
	_mm(pole, tp)
	_mm(arm, ta).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm(head, th).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mm(glow, tg).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Les maillages dessinés par city_ground / city_facade passent sur leur propre couche visuelle
func _city_layer(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.mesh and c.mesh.get_surface_count() > 0:
			var m = c.mesh.surface_get_material(0)
			if m is ShaderMaterial and m.shader and m.shader.resource_path.begins_with("res://world/shaders/city_"):
				c.layers = CITY_LAYER
		_city_layer(c)


static func _glow_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 color : source_color = vec3(1.0, 0.72, 0.42);
uniform float night = 0.0;
varying float cam_d;
void vertex() {
	cam_d = distance((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz, CAMERA_POSITION_WORLD);
}
void fragment() {
	// De près, les shaders de la ville dessinent déjà la flaque de lumière : le halo n'apparaît qu'au loin
	float d = length(UV * 2.0 - 1.0);
	ALBEDO = color * pow(max(0.0, 1.0 - d), 2.2) * night * 0.7 * smoothstep(40.0, 70.0, cam_d);
}
"""
	return s


func _ensure_lights() -> void:
	var n: int = Graphics.get_value("lamp_lights")
	while _lights.size() > n:
		_lights.pop_back().queue_free()
	while _lights.size() < n:
		var l := OmniLight3D.new()
		l.light_color = LAMP_COLOR
		l.omni_range = 16.0
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.light_cull_mask = 0xFFFFF & ~CITY_LAYER
		l.visible = false
		add_child(l)
		_lights.append(l)


## night : 0 le jour, 1 en pleine nuit (calculé par main)
func set_night(night: float) -> void:
	_night = night
	_head_mat.emission_energy_multiplier = night * 4.0
	_glow_mat.set_shader_parameter("night", night)
	RenderingServer.global_shader_parameter_set("city_lamp_night", night)


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.25
	var on := _night > 0.05
	var cam := get_viewport().get_camera_3d()
	if not on or cam == null:
		for l in _lights:
			l.visible = false
		return
	# Lampadaires les plus proches de la caméra
	var c := cam.global_position
	var hc := Vector2i(floori(c.x / 40.0), floori(c.z / 40.0))
	var near: Array = []
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for i in _hash.get(hc + Vector2i(dx, dz), PackedInt32Array()):
				var p: Vector3 = lamps[i][0]
				near.append([Vector2(p.x - c.x, p.z - c.z).length(), i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	_update_pools(near)
	for k in _lights.size():
		var l := _lights[k]
		if k < near.size():
			var lamp: Array = lamps[near[k][1]]
			l.global_position = (lamp[0] as Vector3) + Vector3(0, HEIGHT - 0.6, 0) + (lamp[1] as Vector3) * 1.5
			l.light_energy = 1.6 * _night
			l.visible = true
		else:
			l.visible = false


## Écrit les lampadaires les plus proches pour les shaders de la ville. Le plus éloigné de la liste s'éteint
## en douceur (pas de flaque qui apparaît d'un coup quand on avance).
func _update_pools(near: Array) -> void:
	var n := mini(mini(int(Graphics.get_value("lamp_pools")), POOL_MAX), near.size())
	var far: float = near[n - 1][0] if n > 0 else 0.0
	for k in POOL_MAX:
		if k < n:
			var lamp: Array = lamps[near[k][1]]
			var p: Vector3 = (lamp[0] as Vector3) + Vector3(0, HEIGHT - 0.3, 0) + (lamp[1] as Vector3) * 1.5
			var w := clampf((far - float(near[k][0])) / 12.0 + 0.15, 0.0, 1.0)
			_img.set_pixel(k, 0, Color(p.x, p.y, p.z, w))
		else:
			_img.set_pixel(k, 0, Color(0, 0, 0, 0))
	_tex.update(_img)
	if "--lamp-debug" in OS.get_cmdline_user_args():
		print("lampes proches : %d, la plus proche à %.1f m, nuit %.2f" % [n, near[0][0] if n > 0 else -1.0, _night])
	RenderingServer.global_shader_parameter_set("city_lamp_count", float(n))
