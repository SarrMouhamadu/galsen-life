extends Node3D
## Sons spatialisés de la ville : vagues à la plage, foule (celle du grand marché : market.gd), moteurs des voitures proches.
## Ils s'entendent de plus en plus fort en s'approchant et viennent de la bonne direction.

const SOURCES := [
	["Plage de l'Anse Bernard", "waves", 2.0, 90.0],
	["Gare routière Petersen", "crowd", -4.0, 40.0],
	["Place de l'Indépendance", "crowd", -10.0, 35.0],
]
const ENGINE_RANGE := 35.0
const ENGINES := 4

var main
var _engines: Array[AudioStreamPlayer3D] = []
var _scan_t := 0.0


func _ready() -> void:
	for s in SOURCES:
		if not main.city.places.has(s[0]):
			continue
		var p: AudioStreamPlayer3D = Audio.make_3d(s[1], s[2], s[3])
		add_child(p)
		p.global_position = main.city.places[s[0]] + Vector3(0, 1.5, 0)
	# Quelques moteurs suivent les voitures les plus proches (nombre limité pour les téléphones)
	for i in ENGINES:
		var e: AudioStreamPlayer3D = Audio.make_3d("engine", -14.0, ENGINE_RANGE)
		e.autoplay = false
		add_child(e)
		_engines.append(e)


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	var near: Array = []
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v == main.player.current_vehicle or not v.visible:
			continue
		var d: float = v.global_position.distance_to(c)
		if d < ENGINE_RANGE and absf(v.speed) > 0.5:
			near.append([d, v])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for i in _engines.size():
		var e := _engines[i]
		if i < near.size():
			var v = near[i][1]
			e.global_position = v.global_position
			e.pitch_scale = clampf(0.7 + absf(v.speed) / 14.0, 0.7, 1.8) * (0.8 if v.vehicle_type in ["bus", "coach"] else 1.0)
			if not e.playing and e.stream != null:
				e.play()
		elif e.playing:
			e.stop()
