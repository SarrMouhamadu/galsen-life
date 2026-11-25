extends Node3D
## Les métiers de Galsen-Life : taximan, livreur de thiéboudienne, vendeur de café Touba.
## Gère aussi les lieux où l'on peut agir (dibiterie...) et la balise d'objectif.

const Mk = preload("res://scripts/util/mk.gd")

const CLIENT_LINES := [
	"« Bonjour chauffeur ! %s, s'il te plaît. »",
	"« Asalaa maalekum ! Amène-moi à %s. »",
	"« Dama yàkkamti ! (je suis pressé) Direction %s. »",
	"« %s... ñaata la ? » Le client négocie, vous tombez d'accord.",
]
const CAFE_PRICE := 150
const DIBI_PRICE := 1500
const MAIGA_PRICE := 1000

var city
var player
var employment = null ## emploi : patrons, contrats (employment.gd)
var _taxi_warned = null
var job := ""
var stage := ""
var objective := ""
var target_name := ""
var target_pos := Vector3.ZERO
var has_target := false
var fare := 0
var time_left := 0.0
var _cafe_t := 0.0
var _cafe_sold := 0
var _spots: Array = []
var _beam: Node3D
var _beam_mesh: MeshInstance3D
var _arrow: Node3D


func _ready() -> void:
	_spots = [
		{"id": "cafe", "pos": city.places["Café Touba"], "title": "Café Touba", "sub": "Vendre du café", "color": Color("b5651d")},
		{"id": "resto", "pos": city.places["Chez Adja"], "title": "Chez Adja", "sub": "Livraisons", "color": Color("e76f51")},
		{"id": "dibi", "pos": city.places["Dibiterie"], "title": "Dibiterie", "sub": "Manger", "color": Color("d62828")},
		{"id": "maiga", "pos": city.places.get("Restaurant Maïga", city.places["Dibiterie"]), "title": "Restaurant Maïga", "sub": "Fast-Food / Manger", "color": Color("e67e22")},
	]
	for s in _spots:
		_make_spot_marker(s)
	_beam = Node3D.new()
	add_child(_beam)
	_beam_mesh = Mk.cyl(_beam, 2.2, 2.2, 60.0, Vector3(0, 30, 0), Color(1, 0.82, 0.2, 0.35), false, 16)
	Mk.cyl(_beam, 2.6, 2.6, 0.1, Vector3(0, 0.25, 0), Color(1, 1, 1, 0.6), false, 24)
	_beam.visible = false
	_arrow = Node3D.new()
	add_child(_arrow)
	var cone := Mk.cyl(_arrow, 0.0, 0.3, 0.9, Vector3.ZERO, Color("ffd23f"), false, 8)
	cone.material_override = Mk.mat(Color("ffd23f"), 1.5)
	cone.rotation.x = -PI / 2.0
	_arrow.visible = false


func _make_spot_marker(s: Dictionary) -> void:
	var pos: Vector3 = s["pos"]
	var col: Color = s["color"]
	var ring := Mk.cyl(self, 1.4, 1.4, 0.06, pos + Vector3(0, 0.2, 0), col, false, 24)
	ring.material_override = Mk.mat(Color(col.r, col.g, col.b, 0.8), 1.2, true)
	Mk.label(self, "%s\n%s" % [s["title"], s["sub"]], pos + Vector3(0, 2.6, 0), Mk.SIGN_SIZE, Color.WHITE)


func _process(delta: float) -> void:
	var veh = player.current_vehicle
	var on_taxi: bool = veh != null and veh.vehicle_type == "taxi"
	var my_taxi: bool = on_taxi and (employment == null or employment.taxi_allowed(veh))
	if on_taxi and not my_taxi and job == "" and _taxi_warned != veh:
		_taxi_warned = veh
		GameState.notify.emit("Ce taxi n'est pas le tien. Pour faire taximan, va voir Pape Diop au garage (permis exigé).")
	if my_taxi and job == "":
		job = "taxi"
		stage = "cherche"
		has_target = false
		GameState.notify.emit("Service taxi activé ! Suis la balise jaune pour trouver un client.")
	elif job == "taxi" and not on_taxi:
		cancel()
		GameState.notify.emit("Service taxi en pause. Remonte dans un taxi pour continuer.")
	var pos: Vector3 = player.get_world_position()
	match job:
		"taxi":
			_update_taxi(pos, veh)
		"livraison":
			_update_livraison(delta, pos)
		"cafe":
			_update_cafe(delta, pos)
		"entreprise":
			pass # objectif géré par business.gd
		"etal":
			pass # étal de rue tenu par le joueur : géré par market.gd
		_:
			objective = ""
	_update_markers(pos)


func cancel() -> void:
	job = ""
	stage = ""
	has_target = false
	objective = ""


func _set_target(p_name: String, pos: Vector3, color: Color) -> void:
	target_name = p_name
	target_pos = pos
	has_target = true
	_beam_mesh.material_override = Mk.mat(color, 0.0, true)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Taxi --------------------------------------------------------------------

func _update_taxi(pos: Vector3, veh) -> void:
	if not has_target:
		var a: Dictionary = city.random_address(pos, 50.0, 200.0)
		_set_target(a["name"], a["pos"], Color(1, 0.82, 0.2, 0.35))
	var d := _flat_dist(pos, target_pos)
	var slow: bool = absf(veh.speed) < 4.0
	if stage == "cherche":
		objective = "TAXI — Un client t'attend : %s (%d m)" % [target_name, int(d)]
		if d < 6.0 and slow:
			var dest: Dictionary = city.random_address(target_pos, 90.0, 260.0)
			var dist := _flat_dist(target_pos, dest["pos"])
			fare = int(round((500.0 + dist * 12.0) / 50.0)) * 50
			stage = "course"
			_set_target(dest["name"], dest["pos"], Color(0.3, 1, 0.4, 0.35))
			GameState.notify.emit(CLIENT_LINES.pick_random() % dest["name"])
	else:
		objective = "TAXI — Dépose le client : %s (%d m) — %s" % [target_name, int(d), GameState.fcfa(fare)]
		if d < 6.0 and slow:
			GameState.add_money(fare, "Course de taxi")
			GameState.stats["courses_taxi"] += 1
			if employment:
				employment.count_taxi_fare()
			GameState.notify.emit("« Jërëjëf, ba beneen yoon ! »")
			stage = "cherche"
			has_target = false


# --- Livraison de thiéboudienne ---------------------------------------------

func _start_livraison(pos: Vector3) -> void:
	var a: Dictionary = city.random_address(pos, 100.0, 260.0)
	var dist := _flat_dist(pos, a["pos"])
	time_left = dist / 6.5 + 25.0
	job = "livraison"
	_set_target(a["name"], a["pos"], Color(0.3, 0.8, 1.0, 0.35))
	GameState.notify.emit("Adja te confie un bol de thiéboudienne bien chaud. Prends la Jakarta, vite !")


func _update_livraison(delta: float, pos: Vector3) -> void:
	time_left -= delta
	var d := _flat_dist(pos, target_pos)
	objective = "LIVRAISON — %s (%d m) — %d s" % [target_name, int(d), maxi(0, int(time_left))]
	if d < 5.0:
		var pay := 1000
		if time_left > 0.0:
			pay += int(time_left) * 25
			GameState.notify.emit("« Neex na ! » Le client te laisse un pourboire.")
		else:
			pay = 500
			GameState.notify.emit("« Dafa sedd ! » (c'est froid !) Paiement réduit.")
		if employment:
			employment.earn("livreur", pay, "Livraison faite")
		else:
			GameState.add_money(pay, "Livraison de thiéb")
		GameState.stats["livraisons"] += 1
		cancel()
		GameState.notify.emit("Retourne chez Adja pour une autre livraison (ou parle-lui pour finir le service et toucher ta paie).")


# --- Café Touba --------------------------------------------------------------

func _update_cafe(delta: float, pos: Vector3) -> void:
	var spot: Vector3 = city.places["Café Touba"]
	objective = "CAFÉ TOUBA — Reste au stand pour vendre (%d tasses vendues)" % _cafe_sold
	if _flat_dist(pos, spot) > 6.0 or player.current_vehicle != null:
		cancel()
		GameState.notify.emit("Tu as quitté ton stand de café.")
		if employment:
			employment.end_shift("cafe", true)
		return
	_cafe_t += delta
	if _cafe_t >= 4.0:
		_cafe_t = 0.0
		_cafe_sold += 1
		if employment:
			employment.earn("cafe", CAFE_PRICE, "Tasse vendue", true)
		else:
			GameState.add_money(CAFE_PRICE, "Tasse de café Touba")
		GameState.stats["cafes_vendus"] += 1


# --- Interactions sur place --------------------------------------------------

func _spot_near() -> Variant:
	var pos: Vector3 = player.get_world_position()
	for s in _spots:
		if _flat_dist(pos, s["pos"]) < 3.2:
			return s
	return null


func try_interact() -> bool:
	var s = _spot_near()
	if s == null:
		return false
	var on_foot: bool = player.current_vehicle == null
	match s["id"]:
		"cafe":
			if not on_foot:
				return false
			if job == "cafe":
				cancel()
				GameState.notify.emit("Tu fermes ton stand. Jërëjëf !")
				if employment:
					employment.end_shift("cafe", false)
			elif job == "" and employment != null and not employment.begin("cafe"):
				pass
			elif job == "":
				job = "cafe"
				_cafe_t = 0.0
				_cafe_sold = 0
				GameState.notify.emit("Tu vends du café Touba : %s la tasse." % GameState.fcfa(CAFE_PRICE))
			else:
				GameState.notify.emit("Termine d'abord ton travail en cours.")
		"resto":
			if job == "" and employment != null and not employment.begin("livreur"):
				pass
			elif job == "":
				_start_livraison(player.get_world_position())
			elif job == "livraison":
				GameState.notify.emit("Tu as déjà une livraison en cours !")
			else:
				return false
		"dibi":
			if not on_foot:
				return false
			if GameState.spend(DIBI_PRICE):
				GameState.hunger = 100.0
				GameState.health = minf(100.0, GameState.health + 25.0)
				GameState.stats["dibis"] = GameState.stats.get("dibis", 0) + 1
				GameState.notify.emit("Dibi bu neex ! Tu as bien mangé (-%s)." % GameState.fcfa(DIBI_PRICE))
			else:
				GameState.notify.emit("Il te faut %s pour manger." % GameState.fcfa(DIBI_PRICE))
		"maiga":
			if not on_foot:
				return false
			if GameState.spend(MAIGA_PRICE):
				GameState.hunger = 100.0
				GameState.health = minf(100.0, GameState.health + 30.0)
				GameState.stats["maiga"] = GameState.stats.get("maiga", 0) + 1
				GameState.notify.emit("Sandwich Maïga bu neex ! Pain brochette, spaghetti chaud & piment doux (-%s)." % GameState.fcfa(MAIGA_PRICE))
			else:
				GameState.notify.emit("Il te faut %s pour manger chez Maïga." % GameState.fcfa(MAIGA_PRICE))
	return true


func get_hint() -> String:
	var s = _spot_near()
	if s == null:
		return ""
	var on_foot: bool = player.current_vehicle == null
	match s["id"]:
		"cafe":
			if on_foot:
				return "Fermer le stand" if job == "cafe" else "Vendre du café Touba"
		"resto":
			if job == "":
				return "Prendre une livraison"
		"dibi":
			if on_foot:
				return "Manger un dibi (%s)" % GameState.fcfa(DIBI_PRICE)
		"maiga":
			if on_foot:
				return "Manger chez Maïga (%s)" % GameState.fcfa(MAIGA_PRICE)
	return ""


# --- Balise et flèche --------------------------------------------------------

func _update_markers(pos: Vector3) -> void:
	_beam.visible = has_target
	_arrow.visible = has_target
	if not has_target:
		return
	_beam.global_position = target_pos
	var h := 3.0
	var veh = player.current_vehicle
	if veh:
		h = veh.size.y + 1.8
	_arrow.global_position = pos + Vector3(0, h, 0)
	var look := Vector3(target_pos.x, _arrow.global_position.y, target_pos.z)
	if _arrow.global_position.distance_to(look) > 0.5:
		_arrow.look_at(look, Vector3.UP)
