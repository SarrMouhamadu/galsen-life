extends Node3D
## Entreprises où travailler :
## - kiosques Orange Money et Wave : agent (dépôts et retraits), 1 % de commission par client servi ;
## - supermarché Jadida : caissier, 250 FCFA par client ;
## - dépôt Jumbo : tournée de livraison de cartons dans 3 boutiques, avec prime.
## Les noms sont écrits sur les enseignes ; aucun logo n'est reproduit.

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

const KIOSKS := [["Orange Money", "om"], ["Orange Money (Petersen)", "om"], ["Wave", "wave"], ["Wave (Kermel)", "wave"]]
const AMOUNTS := [2000, 5000, 10000, 15000, 25000, 50000]
const SERVE_TIME := 9.0
const JUMBO_STOPS := 3
const JUMBO_PAY := 1200
const JUMBO_BONUS := 1500
const CASHIER_PAY := 250

var city
var player
var jobs
var employment = null
var spots: Array = [] ## {kind, name, pos, n}
var _active = null
var _customer: Node3D
var _request := 0
var _request_txt := ""
var _wait := 0.0
var _next := 0.0
var _served := 0
var _earned := 0
var _stops_left := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for k in KIOSKS:
		_add_spot(k[0], k[1])
	_add_spot("Jadida", "jadida")
	_add_spot("Jumbo", "jumbo")


func _add_spot(place: String, kind: String) -> void:
	if not city.places.has(place):
		return
	var info: Array = city.place_info[place]
	var curb: Vector3 = city.places[place]
	var n := Vector3(info[3], 0, info[4])
	spots.append({"kind": kind, "name": place, "pos": curb, "n": n})
	var h := Node3D.new()
	add_child(h)
	# Les kiosques sont sur le trottoir ; les grandes enseignes un peu en retrait
	var hp: Vector3 = Vector3(curb.x, 0.0, curb.z) + n * (0.4 if kind in ["om", "wave"] else 2.2)
	h.position = city.off_road(hp, n, 0.8 if kind in ["om", "wave"] else 1.6) + Vector3(0, 0.16, 0)
	h.rotation.y = atan2(-n.x, -n.z) + PI
	match kind:
		"om":
			_kiosk(h, Color("ff7900"), Color("111111"), "Orange Money", Color("ff7900"))
		"wave":
			_kiosk(h, Color("1dc3f3"), Color("ffffff"), "Wave", Color("1b75bb"))
		"jadida", "jumbo":
			pass # siège visitable avec le nom en façade (scripts/world/enterprises.gd)


func _kiosk(h: Node3D, body: Color, accent: Color, brand: String, text_col: Color) -> void:
	Mk.box(h, Vector3(2.4, 2.4, 1.6), Vector3(0, 1.2, 0.4), body, true)
	Mk.box(h, Vector3(2.0, 1.0, 0.05), Vector3(0, 1.5, -0.41), Color(0.15, 0.15, 0.18)) # guichet
	Mk.box(h, Vector3(2.6, 0.12, 0.5), Vector3(0, 1.0, -0.6), accent) # comptoir
	Mk.box(h, Vector3(2.8, 0.15, 2.0), Vector3(0, 2.5, 0.3), accent) # toit
	var plate := Mk.box(h, Vector3(2.4, 0.5, 0.06), Vector3(0, 2.85, -0.42), accent)
	var t := Mk.label(h, brand, Vector3(0, 2.85, -0.47), 48, text_col, false)
	t.rotation.y = PI
	t.outline_size = 0


func _spot_near(pp: Vector3) -> Variant:
	for s in spots:
		if Vector2(pp.x - s["pos"].x, pp.z - s["pos"].z).length() < 3.2:
			return s
	return null


func _title(kind: String) -> String:
	match kind:
		"om":
			return "Agent Orange Money"
		"wave":
			return "Agent Wave"
		"jadida":
			return "Caissier chez Jadida"
	return "Livreur Jumbo"


func get_hint() -> String:
	if player.riding != null:
		return ""
	if _active != null and _customer != null and player.current_vehicle == null:
		return "Servir le client"
	var s = _spot_near(player.get_world_position())
	if s == null:
		return ""
	if employment != null and not employment.is_hired(s["kind"]):
		return ""
	if s["kind"] == "jumbo":
		return "Prendre une tournée Jumbo (%d boutiques)" % JUMBO_STOPS if jobs.job == "" else ""
	if player.current_vehicle != null:
		return ""
	if _active == s:
		return "Fermer le service"
	return "Travailler : %s" % _title(s["kind"]) if jobs.job == "" else ""


func try_interact() -> bool:
	if player.riding != null:
		return false
	if _active != null and _customer != null and player.current_vehicle == null and _active["kind"] != "jumbo":
		_serve()
		return true
	var s = _spot_near(player.get_world_position())
	if s == null:
		return false
	if employment != null and not employment.is_hired(s["kind"]):
		return false
	if s["kind"] == "jumbo":
		if jobs.job != "":
			return false
		if employment != null and not employment.begin("jumbo"):
			return true
		_start_jumbo(s)
		return true
	if player.current_vehicle != null:
		return false
	if _active == s:
		_end_shift()
		return true
	if jobs.job != "":
		GameState.notify.emit("Termine d'abord ton travail en cours.")
		return true
	if employment != null and not employment.begin(s["kind"]):
		return true
	_active = s
	jobs.job = "entreprise"
	_served = 0
	_earned = 0
	_next = 2.0
	GameState.notify.emit("Tu commences ton service : %s. Sers les clients avec [E]." % _title(s["kind"]))
	return true


func _end_shift(abandoned := false) -> void:
	if _active == null:
		return
	GameState.notify.emit("Fin du service : %d clients servis." % _served)
	if employment:
		employment.end_shift(_active["kind"], abandoned)
	_clear_customer()
	_active = null
	if jobs.job == "entreprise":
		jobs.cancel()


func _clear_customer() -> void:
	if _customer != null and is_instance_valid(_customer):
		_customer.queue_free()
	_customer = null


func _spawn_customer() -> void:
	var s: Dictionary = _active
	_customer = RealCharacter.create(self, RealCharacter.random_ped_name(_rng), _rng.randi())
	var n: Vector3 = s["n"]
	_customer.global_position = s["pos"] + n * 0.6 + Vector3(0, 0.16, 0)
	_customer.rotation.y = atan2(-n.x, -n.z)
	_customer.play_clip("talk", 0.0)
	_wait = SERVE_TIME
	if s["kind"] == "jadida":
		var items := _rng.randi_range(2, 9)
		_request = items * _rng.randi_range(300, 900)
		_request = int(round(_request / 25.0)) * 25
		_request_txt = "%d articles — %s" % [items, GameState.fcfa(_request)]
	else:
		_request = AMOUNTS[_rng.randi() % AMOUNTS.size()]
		_request_txt = "%s de %s" % ["Dépôt" if _rng.randf() < 0.5 else "Retrait", GameState.fcfa(_request)]


func _serve() -> void:
	var pay := CASHIER_PAY if _active["kind"] == "jadida" else maxi(100, int(round(_request * 0.01 / 25.0)) * 25)
	_served += 1
	_earned += pay
	if employment:
		employment.earn(_active["kind"], pay, "Client servi : %s" % _request_txt)
	else:
		GameState.add_money(pay, "%s : %s" % [_title(_active["kind"]), _request_txt])
	_clear_customer()
	_next = _rng.randf_range(3.0, 6.0)


# --- Tournée Jumbo ---------------------------------------------------------------------

func _start_jumbo(s: Dictionary) -> void:
	_active = s
	jobs.job = "entreprise"
	_stops_left = JUMBO_STOPS
	_earned = 0
	GameState.notify.emit("Tournée Jumbo : livre les cartons dans %d boutiques. Prends la camionnette Jumbo !" % JUMBO_STOPS)
	_next_stop()


func _next_stop() -> void:
	var a: Dictionary = city.random_address(player.get_world_position(), 150.0, 500.0)
	jobs._set_target("Boutique — " + a["name"], a["pos"], Color(0.95, 0.2, 0.2, 0.35))


func _process(delta: float) -> void:
	if _active == null:
		return
	if jobs.job != "entreprise":
		# Le travail a été interrompu (arrestation, évanouissement...)
		_clear_customer()
		_active = null
		return
	var pp: Vector3 = player.get_world_position()
	if _active["kind"] == "jumbo":
		var d := Vector2(pp.x - jobs.target_pos.x, pp.z - jobs.target_pos.z).length()
		jobs.objective = "JUMBO — Livre les cartons : %s (%d m) — %d/%d" % [jobs.target_name, int(d), JUMBO_STOPS - _stops_left + 1, JUMBO_STOPS]
		if d < 7.0:
			_stops_left -= 1
			_earned += JUMBO_PAY
			if employment:
				employment.earn("jumbo", JUMBO_PAY, "Cartons livrés")
			else:
				GameState.add_money(JUMBO_PAY, "Cartons Jumbo livrés")
			if _stops_left <= 0:
				if employment:
					employment.earn("jumbo", JUMBO_BONUS, "Prime de tournée", true)
					GameState.notify.emit("Tournée terminée ! Moussa Fall te paie au dépôt.")
					employment.end_shift("jumbo", false)
				else:
					GameState.add_money(JUMBO_BONUS, "Prime de tournée Jumbo")
				_active = null
				jobs.cancel()
			else:
				_next_stop()
		return
	# Kiosque ou caisse : le joueur doit rester à son poste
	var spot_pos: Vector3 = _active["pos"]
	if Vector2(pp.x - spot_pos.x, pp.z - spot_pos.z).length() > 6.0 or player.current_vehicle != null:
		GameState.notify.emit("Tu as quitté ton poste !")
		_end_shift(true)
		return
	if _customer == null:
		_next -= delta
		jobs.objective = "%s — en attente de clients (%d servis, %s)" % [_title(_active["kind"]).to_upper(), _served, GameState.fcfa(_earned)]
		if _next <= 0.0:
			_spawn_customer()
		return
	_wait -= delta
	jobs.objective = "%s — Client : %s — [E] servir (%d s)" % [_title(_active["kind"]).to_upper(), _request_txt, ceili(_wait)]
	if _wait <= 0.0:
		GameState.notify.emit("Le client s'en va : « Dafa yàgg ! » (c'est trop long)")
		_clear_customer()
		_next = _rng.randf_range(3.0, 6.0)
