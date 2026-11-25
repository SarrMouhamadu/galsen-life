extends SceneTree
## Outil : planche de la course vue de côté (8 instants d'une boucle) pour juger la foulée et la pose des pieds.
##   godot --path . -s res://tools/gait_shot.gd -- --model=footballeur1 --clip=jog --out=C:/chemin/planche.png

var _f := 0
var _c
var _cam: Camera3D
var _imgs: Array = []
var _clip := "jog"
var _out := "user://gait.png"
var _model := "footballeur1"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			_model = a.substr(8)
		elif a.begins_with("--clip="):
			_clip = a.substr(7)
		elif a.begins_with("--out="):
			_out = a.substr(6)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.8, 0.85)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.6
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.25, 0.55, 0.25)
	ground.material_override = gm
	root.add_child(ground)
	# Repère tous les 10 cm au sol
	for k in 30:
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.01, 0.002, 1.0)
		m.mesh = bm
		m.position = Vector3(0, 0.001, -1.5 + k * 0.1)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(0.9, 0.9, 0.9) if k % 5 == 0 else Color(0.4, 0.7, 0.4)
		m.material_override = mm
		root.add_child(m)
	var h := Node3D.new()
	root.add_child(h)
	_c = load("res://scripts/util/real_character.gd").create(h, _model, -1)
	_cam = Camera3D.new()
	_cam.position = Vector3(3.2, 0.9, 0)
	_cam.fov = 38
	root.add_child(_cam)
	_cam.rotation.y = PI / 2.0
	_cam.current = true


func _process(_d: float) -> bool:
	_f += 1
	var ap: AnimationPlayer = _c._anim
	if _f == 2:
		ap.play(_clip, 0.0)
		ap.speed_scale = 0.0
	if _f < 30:
		return false
	var k := (_f - 30) / 6
	var phase := (_f - 30) % 6
	if k >= 8:
		var w := 360 * 8
		var sheet := Image.create(w, 520, false, Image.FORMAT_RGBA8)
		for i in _imgs.size():
			var im: Image = _imgs[i]
			im.resize(360, 520)
			sheet.blit_rect(im, Rect2i(0, 0, 360, 520), Vector2i(i * 360, 0))
		sheet.save_png(_out)
		print("planche : ", _out)
		return true
	if phase == 0:
		ap.seek(ap.get_animation(_clip).length * k / 8.0, true)
	elif phase == 5:
		var img: Image = root.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		_imgs.append(img)
	return false
