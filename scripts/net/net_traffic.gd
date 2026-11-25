extends Node3D
## Affiche le trafic partagé envoyé par le serveur (mode en ligne). Les voitures sont des véhicules
## sans physique propre, déplacés en douceur vers la position reçue ; on peut s'y cogner.
## Quand le joueur vole ou hèle une de ces voitures, elle devient un vrai véhicule local (convert).

const Vehicle = preload("res://scripts/vehicles/vehicle.gd")
## Même liste que le serveur (scripts/net/server_traffic.gd) : le type arrive sous forme d'indice
const TYPE_NAMES := ["taxi", "clando", "car_rapide", "police", "coach", "bus", "jakarta", "ndiaga", "grosse_moto"]

var city
var cars := {} ## id → {node, target, yaw}


func _ready() -> void:
	Net.traffic_received.connect(_on_traffic)


func _on_traffic(data: PackedInt32Array) -> void:
	var seen := {}
	for k in range(0, data.size() - 6, 7):
		# 7 entiers par voiture : id, type, x*10, z*10, cap*100, vitesse*10, y*10
		var e := data.slice(k, k + 7)
		var id: int = e[0]
		seen[id] = true
		var target := Vector3(e[2] / 10.0, 0.2 + e[6] / 10.0, e[3] / 10.0)
		var yaw: float = e[4] / 100.0
		if not cars.has(id):
			var v = Vehicle.new()
			v.vehicle_type = TYPE_NAMES[clampi(int(e[1]), 0, TYPE_NAMES.size() - 1)]
			add_child(v)
			v.set_physics_process(false)
			v.collision_layer = 2
			v.collision_mask = 0
			v.ai_city = city
			v.set_meta("net_id", id)
			v.set_meta("net_owner", self)
			v.global_position = target
			v.rotation.y = yaw
			if v.vehicle_type in ["jakarta", "grosse_moto"] and v.get("_rider") != null:
				v._rider.visible = true
			cars[id] = {"node": v, "target": target, "yaw": yaw}
		var c: Dictionary = cars[id]
		c["target"] = target
		c["yaw"] = yaw
		c["node"].speed = e[5] / 10.0
	for id in cars.keys():
		if not seen.has(id):
			cars[id]["node"].queue_free()
			cars.erase(id)


func _process(delta: float) -> void:
	if not Net.online and not cars.is_empty():
		for id in cars:
			cars[id]["node"].queue_free()
		cars.clear()
		return
	var k := 1.0 - exp(-8.0 * delta)
	for id in cars:
		var c: Dictionary = cars[id]
		var v: Node3D = c["node"]
		# Prédiction : entre deux messages, la voiture continue d'avancer à sa vitesse
		var yaw: float = c["yaw"]
		c["target"] = (c["target"] as Vector3) + Vector3(-sin(yaw), 0, -cos(yaw)) * float(v.speed) * delta
		v.global_position = v.global_position.lerp(c["target"], k)
		v.rotation.y = lerp_angle(v.rotation.y, c["yaw"], k)


## La voiture quitte le trafic partagé et devient un véhicule local qui roule tout seul.
func convert(v) -> void:
	if not v.has_meta("net_id"):
		return
	var id: int = v.get_meta("net_id")
	Net.claim_car(id)
	cars.erase(id)
	v.remove_meta("net_id")
	v.remove_meta("net_owner")
	v.set_physics_process(true)
	v.collision_mask = 1 | 2 | 4
	v.ai_city = city
	v.resume_traffic()
