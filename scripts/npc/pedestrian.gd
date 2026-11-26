extends Node3D
## Piéton : fait le tour de son pâté de maisons et parle wolof quand on l'aborde.
## Bagarre de rue (scripts/world/street_fight.gd) : frappé, il riposte ou s'enfuit ; KO, il se relève plus tard.

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")

const PHRASES := [
	"Nanga def ?",
	"Maa ngi fi rekk !",
	"Asalaa maalekum !",
	"Jërëjëf !",
	"Na nga fanaane ?",
	"Ana sa waa kër ?",
	"Ba beneen yoon !",
	"Dama xiif... (j'ai faim)",
	"Ñaata la ? (c'est combien ?)",
	"Teranga, waaw !",
	"Dama yàkkamti ! (je suis pressé)",
]
const CLOTHES := [
	Color("1d4ed8"), Color("f59e0b"), Color("10b981"), Color("e11d48"), Color("7c3aed"),
	Color("f8fafc"), Color("0ea5e9"), Color("84cc16"), Color("d946ef"), Color("b45309"),
]
const SKINS := [Color("4a2c1d"), Color("5c3a24"), Color("6b4430"), Color("3d2416")]
const HURT := ["Aïe !", "Wouy !", "Yow, bàyyi ma !", "Lan la ?!", "Dangay def lan ?!"]
const ANGRY := ["Ñëwal fii ! (viens ici !)", "Dinaa la dóor ! (je vais te frapper !)", "Yaa ngi may xas ?!", "Kaay ! Kaay ! (viens !)"]
const SCARED := ["Wallaay ! Ndimbal ! (au secours !)", "Police ! Police !", "Dama ragal ! (j'ai peur !)"]

const VENDOR_ITEMS := {
	"arachides": {"name": "Arachides chaudes", "price": 100, "satiety": 15, "shouts": ["« Gerte thiaf ! Arachides chaudes ! »", "« Arachides bien grillées ! 100 F ! »"]},
	"cafe": {"name": "Café Touba", "price": 100, "satiety": 12, "shouts": ["« Café Touba chaud ! Café Touba ! »", "« Café Touba bu tàkk ! 100 FCFA ! »"]},
	"eau": {"name": "Sachet d'eau fraîche", "price": 50, "satiety": 8, "shouts": ["« Ndox mu sedd ! Sachet d'eau 50 francs ! »", "« De l'eau fraîche ! Ndox ! »"]},
	"fruits": {"name": "Mangues & Bananes", "price": 150, "satiety": 20, "shouts": ["« Mangues fraîches, bananes douces ! »", "« Fruits du marché ! »"]},
	"mouchoirs": {"name": "Mouchoirs & Lunettes", "price": 200, "satiety": 5, "shouts": ["« Mouchoirs, lunettes, chargeurs ! »", "« Yow grand, amna lunettes ! »"]},
}

var is_vendor := false
var vendor_type := ""
var vendor_item := ""
var vendor_price := 100
var vendor_satiety := 15
var _vendor_shout_t := 0.0

var is_crossing := false
var _cross_phase := 0.0
var _cross_cd := 0.0
var _cross_start_pos := Vector3.ZERO
var _cross_end_pos := Vector3.ZERO

var knocked := false
var health := 100.0
var mood := "" ## "" (promenade), "fight" (se bat contre le joueur), "flee" (s'enfuit)
var started := false ## c'est lui qui a cherché la bagarre (légitime défense pour le joueur)
var brave := 0.5 ## probabilité de riposter quand on le frappe
var fight = null ## scripts/world/street_fight.gd (posé par ce module)
var _mood_t := 0.0
# Trottoir : chacun sa file, on s'écarte devant un autre passant, le joueur ou un obstacle (étal, mur)
const LANE_MAX := 0.55
const BODY_LAYER := 16 ## couche des corps des passants (le joueur s'y cogne, les voitures non)
var _lane := 0.0
var _dodge := 0.0
var _dodge_target := 0.0
var _slow := 1.0
var _slow_target := 1.0 ## ralentir et repartir en douceur (pas d'à-coups de vitesse)
var _vel := 0.0 ## vitesse réelle (m/s) : l'animation de marche suit le déplacement, sans patiner
var _look_t := 0.0
var _body: StaticBody3D
var _act_t := 0.0 ## animation de coup en cours : la marche ne l'écrase pas
var _cd := 0.0
var city = null
var _from := 0
var _to := 0
var _t := 0.0
var _side := 1
var _speed := 1.3
var _cross_wait := 0.0 ## temps passé à attendre au bord du trottoir
var _cross_block := false
var _last_target := Vector3.ZERO
var _walk_t := 0.0
var _model: Node3D
var _bubble: Label3D
var _bubble_t := 0.0


func setup(p_city, rng: RandomNumberGenerator, near: Vector3) -> void:
	add_to_group("pedestrians")
	city = p_city
	_speed = rng.randf_range(1.0, 1.7)
	brave = rng.randf_range(0.15, 0.8)
	_lane = rng.randf_range(-0.4, 0.4)
	_look_t = rng.randf() * 0.25
	# Corps : le joueur ne passe plus à travers les passants
	_body = StaticBody3D.new()
	_body.collision_layer = BODY_LAYER
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	_body.add_child(cs)
	add_child(_body)

	# Vendeurs ambulants : environ 25% des piétons vendent des articles dans les rues
	is_vendor = rng.randf() < 0.25
	if is_vendor:
		var v_keys: Array = VENDOR_ITEMS.keys()
		vendor_type = v_keys[rng.randi() % v_keys.size()]
		var v_data: Dictionary = VENDOR_ITEMS[vendor_type]
		vendor_item = v_data["name"]
		vendor_price = v_data["price"]
		vendor_satiety = v_data["satiety"]
		_vendor_shout_t = rng.randf_range(4.0, 15.0)
	else:
		vendor_type = ""
		vendor_item = ""

	_cross_cd = rng.randf_range(6.0, 22.0)

	_model = RealCharacter.create(self, RealCharacter.random_ped_name(rng), rng.randi())
	_bubble = Mk.label(self, "", Vector3(0, 2.1, 0), Mk.NAME_SIZE, Color.WHITE)
	_bubble.visible = false
	respawn(near, 10.0, 110.0)


## Replace le piéton sur un trottoir entre min_d et max_d mètres de `near`.
func respawn(near: Vector3, min_d: float, max_d: float) -> void:
	_from = city.random_node_around(near, min_d, max_d, "walk")
	var nb: PackedInt32Array = city.walk_neighbors(_from)
	_to = nb[city.rng.randi() % nb.size()] if not nb.is_empty() else _from
	_t = city.rng.randf() * city.segment_length(_from, _to)
	_side = 1 if city.rng.randf() < 0.5 else -1
	position = city.sidewalk_point(_from, _to, _t, _side)
	_last_target = position
	_vel = _speed
	knocked = false
	is_crossing = false
	_cross_phase = 0.0
	_set_solid(true)
	_dodge = 0.0
	_dodge_target = 0.0
	health = 100.0
	mood = ""
	started = false
	_model.rotation.x = 0.0


func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	if knocked or city == null:
		return
	_act_t -= delta
	if mood != "":
		_brawl(delta)
		return

	# Comportement de vendeur ambulant : crie ses produits
	if is_vendor:
		_vendor_shout_t -= delta
		if _vendor_shout_t <= 0.0:
			_vendor_shout_t = randf_range(12.0, 25.0)
			if VENDOR_ITEMS.has(vendor_type):
				var shouts: Array = VENDOR_ITEMS[vendor_type]["shouts"]
				say(shouts.pick_random())

	# Comportement de traversant : marche à travers la rue
	if is_crossing:
		var cross_vec := _cross_end_pos - _cross_start_pos
		var cross_len := cross_vec.length()
		if cross_len > 0.1:
			var car_close := _check_incoming_car()
			if car_close and _cross_phase < 0.25:
				_cross_wait += delta
				if _cross_wait < 2.5:
					_model.locomote(0.0)
					return
			_cross_phase += (_speed * 1.35 / cross_len) * delta
			var cur_p := _cross_start_pos.lerp(_cross_end_pos, clampf(_cross_phase, 0.0, 1.0))
			position = cur_p
			var f_dir := Vector2(cross_vec.x, cross_vec.z)
			if f_dir.length() > 0.01:
				_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-f_dir.x, -f_dir.y), 1.0 - exp(-10.0 * delta))
			_model.locomote(_speed * 1.35)
			if _cross_phase >= 1.0:
				is_crossing = false
				_side = -_side
				_cross_cd = randf_range(15.0, 35.0)
				_last_target = position
		return

	var L: float = city.segment_length(_from, _to)

	# Déclenchement de la traversée de rue (traversants)
	_cross_cd -= delta
	if _cross_cd <= 0.0 and L > 8.0:
		var near_zebra: bool = city.zebras.has(Vector2i(_from, _to)) or city.zebras.has(Vector2i(_to, _from))
		var want_cross := false
		if near_zebra:
			want_cross = randf() < 0.65
		elif _t > 4.0 and _t < L - 4.0:
			want_cross = randf() < 0.35
		if want_cross:
			start_crossing()
			return

	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = 0.25
		_look_ahead()
	_dodge = move_toward(_dodge, _dodge_target, delta * 1.2)
	_slow = move_toward(_slow, _slow_target, delta * (4.0 if _slow_target < _slow else 1.5))
	# Le point suivi n'avance que si le corps suit (au coin d'une rue, le trottoir suivant est décalé :
	# on y marche au lieu d'y glisser)
	var lag := Vector2(position.x - _last_target.x, position.z - _last_target.z).length()
	# Au bord du trottoir avant un carrefour : on attend le feu ou que les voitures soient passées
	var waiting := _t > L - 1.0 and _cross_block
	if waiting:
		_cross_wait += delta
	else:
		_cross_wait = 0.0
	if lag < 0.8 and not waiting:
		_t += _speed * _slow * delta
	if _t >= L:
		_t -= L
		var nxt: int = city.next_node(_from, _to, "walk")
		_from = _to
		_to = nxt
	var target: Vector3 = city.sidewalk_point(_from, _to, _t, _side) + _across() * (_lane + _dodge)
	_last_target = target
	var to := target - position
	to.y = 0.0
	# Pas plus vite qu'une marche un peu pressée
	var step := minf(to.length(), maxf(_speed * _slow * 1.35, 0.4) * delta)
	var before := position
	if to.length() > 0.001:
		position += to.normalized() * step
	position.y = lerpf(position.y, target.y, 1.0 - exp(-8.0 * delta))
	_vel = lerpf(_vel, Vector2(position.x - before.x, position.z - before.z).length() / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	# Regarde dans le sens du déplacement réel (le point suivi est atteint à chaque image : l'écart
	# restant est presque nul et ne donne pas la direction). À l'arrêt, vers la suite du trottoir.
	var moved := Vector2(position.x - before.x, position.z - before.z)
	var head := Vector2(to.x, to.z) if moved.length() < 0.002 else moved
	if moved.length() < 0.002 and head.length() < 0.05:
		var seg: Vector3 = city.node_pos[_to] - city.node_pos[_from]
		head = Vector2(seg.x, seg.z)
	if head.length() > 0.0005:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-head.x, -head.y), 1.0 - exp(-8.0 * delta))
	if _act_t <= 0.0:
		_model.locomote(_vel)


## Démarre une traversée de la rue vers le trottoir opposé
func start_crossing() -> void:
	if is_crossing or knocked or city == null:
		return
	var cur_side_pt: Vector3 = city.sidewalk_point(_from, _to, _t, _side)
	var opp_t: float = clampf(_t + randf_range(2.0, 5.0), 0.0, city.segment_length(_from, _to))
	var opp_side_pt: Vector3 = city.sidewalk_point(_from, _to, opp_t, -_side)
	_cross_start_pos = cur_side_pt
	_cross_end_pos = opp_side_pt
	_t = opp_t
	is_crossing = true
	_cross_phase = 0.0
	_cross_wait = 0.0


## Vérifie si une voiture approche rapidement de la trajectoire du piéton
func _check_incoming_car() -> bool:
	var me: Vector3 = global_position
	for v in get_tree().get_nodes_in_group("vehicles"):
		if absf(v.speed) < 2.0:
			continue
		var to_v: Vector3 = v.global_position - me
		to_v.y = 0.0
		if to_v.length() < 14.0:
			var fwd: Vector3 = -v.global_transform.basis.z * signf(v.speed)
			if fwd.dot(-to_v.normalized()) > 0.45:
				return true
	return false


## Achète un article auprès d'un vendeur ambulant
func buy(buyer) -> void:
	if not is_vendor:
		talk()
		return
	if not GameState.spend(vendor_price):
		say("« Amul xaalis ? » (pas d'argent ?) Il te faut %s." % GameState.fcfa(vendor_price))
		return
	GameState.hunger = minf(100.0, GameState.hunger + vendor_satiety)
	GameState.health = minf(100.0, GameState.health + 10.0)
	Audio.play_sfx("coin", -10.0)
	say("« Jërëjëf grand ! Yàlla na la barkeel ! »")
	GameState.notify.emit("Tu as acheté : %s (-%s)." % [vendor_item, GameState.fcfa(vendor_price)])

## Direction perpendiculaire au trottoir (vers l'extérieur de la rue)
func _across() -> Vector3:
	var d: Vector3 = city.node_pos[_to] - city.node_pos[_from]
	d.y = 0.0
	if d.length() < 0.01:
		return Vector3.ZERO
	d = d.normalized()
	return Vector3(-d.z, 0, d.x) * _side


## Regarde devant soi : passant, joueur ou obstacle à moins de 1,6 m dans sa file → on se décale ou on ralentit
func _look_ahead() -> void:
	var fwd := Vector3(-sin(_model.rotation.y), 0, -cos(_model.rotation.y))
	var across := _across()
	var me := position
	var blocked := false
	var others: Array = get_tree().get_nodes_in_group("pedestrians")
	if GameState.player_ref:
		others.append(GameState.player_ref)
	for o in others:
		if o == self or not o.visible:
			continue
		var d: Vector3 = o.global_position - me
		d.y = 0.0
		var ahead := d.dot(fwd)
		var side := d.dot(across)
		if ahead > -0.2 and ahead < 1.6 and absf(side) < 0.55:
			blocked = true
			# On passe du côté où il y a le plus de place sur le trottoir
			var want := _lane + _dodge + (-0.7 if side > 0.0 else 0.7)
			_dodge_target = clampf(want, -LANE_MAX, LANE_MAX) - _lane
			_slow_target = 0.35 if ahead < 0.7 else 0.7
			break
	if not blocked:
		# Obstacle fixe (étal, poteau, mur) à hauteur de table et de poitrine
		var space := get_world_3d().direct_space_state
		for h in [0.84, 1.3]:
			var q := PhysicsRayQueryParameters3D.create(me + Vector3(0, h, 0), me + Vector3(0, h, 0) + fwd * 1.4, 1 | 2)
			if not space.intersect_ray(q).is_empty():
				blocked = true
				_dodge_target = (-LANE_MAX if _lane + _dodge > 0.0 else LANE_MAX) - _lane
				_slow_target = 0.5
				break
	if not blocked:
		_slow_target = 1.0
		_dodge_target = move_toward(_dodge_target, 0.0, 0.15)
	_cross_block = _crossing_blocked()


## Faut-il attendre avant de traverser au carrefour devant ? Aux feux : tant que les voitures de la rue à
## traverser ont le vert. Ailleurs : tant qu'une voiture arrive vite tout près. Jamais plus de 20 s.
func _crossing_blocked() -> bool:
	if _cross_wait > 20.0:
		return false
	var L: float = city.segment_length(_from, _to)
	if _t < L - 2.5 or city.drive_neighbors(_to).size() + city.drive_incoming(_to).size() < 4:
		return false
	var np: Vector3 = city.node_pos[_to]
	var dw: Vector3 = np - city.node_pos[_from]
	dw.y = 0.0
	dw = dw.normalized()
	if city.lights != null and city.lights.has_lights(_to):
		return not city.lights.walk_green(_to, Vector3(-dw.z, 0, dw.x))
	var r: float = city.junction_radius(_to) + 10.0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if absf(v.speed) < 2.0:
			continue
		var rel: Vector3 = v.global_position - np
		rel.y = 0.0
		if rel.length() > r:
			continue
		var fwd: Vector3 = -v.global_transform.basis.z * signf(v.speed)
		if fwd.dot(-rel) > 0.0:
			return true
	return false


func talk() -> void:
	say(PHRASES.pick_random())


func say(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = 3.0


func hit_by_vehicle() -> void:
	if knocked:
		return
	knocked = true
	_set_solid(false)
	say("Wouy ! Ndeysaan !")
	var tw := create_tween()
	if _model.has_animations():
		_model.play_clip("fall", 0.1)
		tw.tween_interval(5.0)
	else:
		tw.tween_property(_model, "rotation:x", -PI / 2.0, 0.25)
		tw.tween_interval(5.0)
		tw.tween_property(_model, "rotation:x", 0.0, 0.5)
	tw.tween_callback(_get_up)


# --- Bagarre de rue -----------------------------------------------------------------------

## Reçoit un coup venant de `from`. Renvoie vrai s'il tombe KO.
func take_hit(from: Vector3, dmg: float) -> bool:
	if knocked:
		return false
	health -= dmg
	_face(from)
	if health <= 0.0:
		_ko()
		return true
	_model.play_clip("hit", 0.06)
	_act_t = 0.55
	if mood == "":
		mood = "fight" if randf() < brave else "flee"
		say(ANGRY.pick_random() if mood == "fight" else SCARED.pick_random())
	else:
		say(HURT.pick_random())
	_mood_t = 25.0
	return false


## Cherche la bagarre au joueur (provocation d'un fakhman)
func provoke(text: String) -> void:
	mood = "fight"
	started = true
	_mood_t = 40.0
	say(text)


## Témoin d'une bagarre : certains s'éloignent en criant
func witness() -> void:
	if mood == "" and not knocked:
		mood = "flee"
		_mood_t = 8.0
		say(SCARED.pick_random())


func _ko() -> void:
	knocked = true
	_set_solid(false)
	health = 0.0
	mood = ""
	say("Aaah...")
	_model.play_clip("fall", 0.1)
	var tw := create_tween()
	tw.tween_interval(10.0)
	tw.tween_callback(func():
		knocked = false
		_set_solid(true)
		health = 60.0
		started = false
		mood = "flee"
		_mood_t = 10.0
		_model.play_clip("idle", 0.3)
		say("Dinaa la wax police ! (je vais le dire à la police !)"))


func _set_solid(on: bool) -> void:
	if _body:
		_body.collision_layer = BODY_LAYER if on else 0


func _face(target: Vector3) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		_model.rotation.y = atan2(-d.x, -d.z)


func _brawl(delta: float) -> void:
	_mood_t -= delta
	_cd -= delta
	var pl = GameState.player_ref
	if pl == null or not is_instance_valid(pl):
		_calm()
		return
	var pp: Vector3 = pl.global_position
	var to := Vector3(pp.x - position.x, 0, pp.z - position.z)
	var dist := to.length()
	var busy: bool = pl.current_vehicle != null or pl.frozen or GameState.health <= 0.0
	if _mood_t <= 0.0 or dist > 30.0 or (mood == "fight" and busy):
		_calm()
		return
	if mood == "flee":
		var away := -to.normalized() if dist > 0.01 else Vector3.FORWARD
		position += away * 4.6 * delta
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-away.x, -away.z), 1.0 - exp(-10.0 * delta))
		if _act_t <= 0.0:
			_model.locomote(4.6)
		return
	# Riposte : il s'approche et frappe
	if dist > 1.05:
		position += to.normalized() * 3.4 * delta
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-10.0 * delta))
		if _act_t <= 0.0:
			_model.locomote(3.4)
	else:
		_face(pp)
		if _act_t <= 0.0:
			_model.play_clip("idle", 0.2)
		if _cd <= 0.0:
			_cd = randf_range(1.0, 1.7)
			_act_t = 0.6
			_model.play_clip("punch", 0.05, 1.2)
			get_tree().create_timer(0.25).timeout.connect(func():
				if not knocked and mood == "fight" and is_instance_valid(pl) and position.distance_to(pl.global_position) < 1.7 and fight:
					fight.hit_player(randf_range(5.0, 9.0), "Un passant"))


## Fin de la bagarre : il reprend sa promenade depuis le trottoir le plus proche
func _calm() -> void:
	mood = ""
	started = false
	_from = city.nearest_node(position, "walk")
	var nb: PackedInt32Array = city.walk_neighbors(_from)
	_to = nb[city.rng.randi() % nb.size()] if not nb.is_empty() else _from
	_t = 0.0


func _get_up() -> void:
	knocked = false
	_set_solid(true)
	say("Dangay daw lool ! (tu roules trop vite !)")
