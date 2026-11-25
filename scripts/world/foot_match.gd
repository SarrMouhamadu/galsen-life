extends Node
## Match de mini-foot contre l'ordinateur, 4 contre 4 gardiens compris, sur le terrain du milieu du complexe
## (scripts/world/foot.gd). Comme dans les jeux de football :
## - le porteur garde le ballon dans les pieds (conduite de balle) ; en sprintant il le pousse devant lui ;
## - tir avec barre de puissance et visée (frappe placée enroulée, frappe puissante qui peut passer au-dessus) ;
## - passe dans la course du coéquipier, passe lobée, appel de balle ;
## - feintes et crochets qui effacent le défenseur ; tacles (par derrière : faute et coup franc) ;
## - l'ordinateur joue en équipe : placement selon le ballon, pressing, couverture, appels en profondeur ;
## - gardiens qui se placent, sortent, plongent, captent ou repoussent, puis relancent.
## Le joueur est le n° 10 des jaunes ; ses coéquipiers et adversaires sont des footballeurs en tenue.

const FootBall = preload("res://scripts/world/foot_ball.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")
const PLAYER_MODELS := ["footballeur1", "footballeur2", "footballeur3"]
## Postes (repère de l'équipe : elle attaque vers +x) : [rôle, position, numéro]
const LINEUP := [[["att", Vector2(4, -1), 10], ["gk", Vector2(-17.2, 0), 1], ["def", Vector2(-10, 3), 4], ["mid", Vector2(-3, -4), 8]],
	[["gk", Vector2(-17.2, 0), 1], ["def", Vector2(-10, -3), 5], ["mid", Vector2(-3, 4), 6], ["att", Vector2(4, 1), 9]]]
const HL := FootBall.L / 2.0
const HW := FootBall.W / 2.0
const PICK := 0.75 ## distance de contrôle du ballon
const TACKLE := 1.8

var foot
var ball = FootBall.new()
var men: Array = [] ## {node, team, role, home, speed, player, vel, face, cd, stun, anim, think, receive, skill, skill_dir, knock, hold, dive, dive_side, save, tried}
var carrier := -1 ## index du porteur, -1 : ballon libre
var score := [0, 0]
var time := 0.0
var pause := 0.0
var last_team := -1
var opp_name := ""
var call := false ## le joueur demande le ballon à son coéquipier
var _no_pick := {}
var _restart := {} ## remise en jeu en attente : {team, at}
var _shot_live := false
var _shot_team := -1
var _mesh: MeshInstance3D
var _rng := RandomNumberGenerator.new()
var _note_cd := 0.0
var _player_stun := 0.0


func start(opponent: String) -> void:
	_rng.randomize()
	opp_name = opponent
	score = [0, 0]
	time = foot.MATCH_TIME
	men.clear()
	for team in 2:
		for d in LINEUP[team]:
			var is_player: bool = team == 0 and d[0] == "att"
			var node: Node3D = foot.player
			if not is_player:
				var model: String = "gardien" if d[0] == "gk" else PLAYER_MODELS[_rng.randi() % PLAYER_MODELS.size()]
				node = RealCharacter.create(self, model, 40 + men.size())
				foot._dress(node, foot.KITS[team][1 if d[0] == "gk" else 0], d[2])
			men.append({"node": node, "team": team, "role": d[0], "home": d[1], "number": d[2], "player": is_player,
				"speed": _rng.randf_range(5.3, 6.1) if d[0] != "gk" else 5.5, "vel": Vector2.ZERO, "face": Vector2(_attack(team), 0),
				"cd": 0.0, "stun": 0.0, "anim": 0.0, "think": 0.0, "receive": 0.0, "skill": 0.0, "skill_dir": Vector2.ZERO,
				"knock": 0.0, "hold": 0.0, "dive": 0.0, "dive_side": 0.0, "save": false, "tried": false})
	men.sort_custom(func(a, b): return a["player"] and not b["player"]) # le joueur en premier (index 0)
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = FootBall.R
	sm.height = FootBall.R * 2.0
	_mesh.mesh = sm
	_mesh.material_override = ball_material()
	add_child(_mesh)
	kickoff(0)


func clear() -> void:
	for m in men:
		if not m["player"] and is_instance_valid(m["node"]):
			m["node"].queue_free()
	men.clear()
	if is_instance_valid(_mesh):
		_mesh.queue_free()
	carrier = -1


static var _ball_tex: ImageTexture


## Ballon blanc à 12 pentagones noirs (sommets d'un icosaèdre), texture équirectangulaire de la sphère
static func ball_material() -> StandardMaterial3D:
	if _ball_tex == null:
		var phi := (1.0 + sqrt(5.0)) / 2.0
		var verts: Array = []
		for a in [-1.0, 1.0]:
			for b in [-phi, phi]:
				verts.append(Vector3(0, a, b).normalized())
				verts.append(Vector3(a, b, 0).normalized())
				verts.append(Vector3(b, 0, a).normalized())
		var w := 256
		var h := 128
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		for y in h:
			var lat := PI * (0.5 - (y + 0.5) / h)
			for x in w:
				var lon := TAU * (x + 0.5) / w
				var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
				var c := Color(0.96, 0.96, 0.94)
				for vv in verts:
					var ang := d.angle_to(vv)
					if ang < 0.3:
						c = Color(0.07, 0.07, 0.08)
					elif ang < 0.32:
						c = Color(0.5, 0.5, 0.5)
				img.set_pixel(x, y, c)
		_ball_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _ball_tex
	m.roughness = 0.35
	m.metallic_specular = 0.6
	return m


# --- Repères ----------------------------------------------------------------------------------------

func _attack(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func pos(i: int) -> Vector2:
	var p: Vector3 = men[i]["node"].global_position
	var c: Vector3 = foot._c()
	return Vector2(p.x - c.x, p.z - c.z)


func _set_pos(i: int, v: Vector2) -> void:
	var c: Vector3 = foot._c()
	var n: Node3D = men[i]["node"]
	n.global_position = Vector3(c.x + v.x, c.y + (0.5 if men[i]["player"] else 0.0), c.z + v.y)


func world(v: Vector3) -> Vector3:
	return foot._c() + v


func _home(i: int) -> Vector2:
	var h: Vector2 = men[i]["home"]
	return Vector2(h.x * _attack(men[i]["team"]), h.y * _attack(men[i]["team"]))


func _clamp_pitch(v: Vector2, margin := 0.4) -> Vector2:
	return Vector2(clampf(v.x, -HL + margin, HL - margin), clampf(v.y, -HW + margin, HW - margin))


func owner_team() -> int:
	return men[carrier]["team"] if carrier >= 0 else -1


func player_has_ball() -> bool:
	return carrier == 0


## Le joueur peut frapper : il a le ballon, ou le ballon libre passe à sa portée (reprise de volée)
func player_can_kick() -> bool:
	if carrier == 0:
		return true
	return carrier < 0 and pos(0).distance_to(ball.flat()) < 1.15 and ball.p.y < 1.3 and pause <= 0.0


# --- Déroulement ------------------------------------------------------------------------------------

func update(delta: float) -> void:
	_note_cd -= delta
	for k in _no_pick.keys():
		_no_pick[k] = float(_no_pick[k]) - delta
	_update_player(delta)
	if pause > 0.0:
		pause -= delta
		_hold_positions(delta)
		_update_mesh(delta)
		if pause <= 0.0:
			_resume()
		return
	time -= delta
	_update_ball(delta)
	_update_ais(delta)
	_update_mesh(delta)


func _note(text: String, force := false) -> void:
	if force or _note_cd <= 0.0:
		_note_cd = 1.2
		GameState.notify.emit(text)


func _update_player(delta: float) -> void:
	var m: Dictionary = men[0]
	var v := Vector2(foot.player.velocity.x, foot.player.velocity.z)
	m["vel"] = v
	if v.length() > 0.5:
		m["face"] = v.normalized()
	m["skill"] = float(m["skill"]) - delta
	m["knock"] = float(m["knock"]) - delta
	if m["skill"] > 0.0:
		m["face"] = m["skill_dir"]
	if _player_stun > 0.0:
		_player_stun -= delta
		if _player_stun <= 0.0:
			foot.player.frozen = false


func _update_ball(delta: float) -> void:
	if carrier >= 0:
		var m: Dictionary = men[carrier]
		var me := pos(carrier)
		var face: Vector2 = m["face"]
		var sp: float = m["vel"].length()
		if m["role"] == "gk":
			# Dans les mains du gardien
			ball.p = Vector3(me.x + face.x * 0.35, 1.05, me.y + face.y * 0.35)
			ball.v = Vector3.ZERO
			return
		# Conduite de balle : le ballon reste juste devant le pied
		var ahead := 0.42 + sp * 0.06
		var target := _clamp_pitch(me + face * ahead, FootBall.R + 0.05)
		var cur := ball.flat().lerp(target, 1.0 - exp(-14.0 * delta))
		ball.p = Vector3(cur.x, FootBall.R, cur.y)
		ball.v = Vector3(m["vel"].x, 0.0, m["vel"].y)
		ball.spin = 0.0
		# En sprint, on pousse le ballon devant soi : plus vite, mais l'adversaire peut le chiper
		if sp > 5.6 and m["knock"] <= 0.0:
			m["knock"] = 0.6
			_no_pick[carrier] = 0.2
			carrier = -1
			ball.v = Vector3(face.x, 0.0, face.y) * sp * 1.45
		return
	var ev: String = ball.step(delta)
	match ev:
		"goal+":
			_goal(0)
			return
		"goal-":
			_goal(1)
			return
		"post":
			_note("Poteau !", true)
			Audio.play_sfx("hit", -6.0)
		"out":
			_note("Ballon dehors ! Remise en jeu.", true)
			_set_restart(1 - maxi(last_team, 0), Vector2(clampf(ball.p.x, -HL + 2.0, HL - 2.0), signf(ball.p.z) * (HW - 0.6)))
			return
	if ball.in_goal != 0:
		return
	_try_pickup()


func _try_pickup() -> void:
	var best := -1
	var bd := INF
	var b: Vector2 = ball.flat()
	for i in men.size():
		var m: Dictionary = men[i]
		if m["stun"] > 0.0 or float(_no_pick.get(i, 0.0)) > 0.0 or (i == 0 and _player_stun > 0.0):
			continue
		var gk_area: bool = m["role"] == "gk" and absf(b.x + _attack(m["team"]) * HL) < 6.5 and absf(b.y) < 5.0
		if m["role"] == "gk" and _shot_live and m["team"] != _shot_team and ball.v.length() > 12.0:
			continue # un tir appuyé : c'est l'arrêt (plongeon) qui décide
		var reach: float = PICK + (0.35 if gk_area else 0.0)
		var height: float = 2.3 if gk_area else 0.9
		var d := pos(i).distance_to(b)
		if d < reach and ball.p.y < height and d < bd:
			bd = d
			best = i
	if best < 0:
		return
	var m: Dictionary = men[best]
	var bs := Vector2(ball.v.x, ball.v.z).length()
	if bs > 15.0 and m["role"] != "gk":
		# Frappe trop forte pour être contrôlée : le ballon lui rebondit dessus
		ball.v = Vector3(-ball.v.x * 0.25 + _rng.randf_range(-2, 2), 1.5, -ball.v.z * 0.25 + _rng.randf_range(-2, 2))
		_no_pick[best] = 0.35
		return
	_take(best)


func _take(i: int) -> void:
	var m: Dictionary = men[i]
	if _shot_live and m["team"] != _shot_team and m["role"] == "gk":
		_note("Le gardien capte le ballon !" if m["team"] == 1 else "Ton gardien capte le ballon !")
	elif _shot_live and m["team"] != _shot_team:
		_note("Ballon intercepté.")
	carrier = i
	last_team = m["team"]
	_shot_live = false
	m["receive"] = 0.0
	m["hold"] = 0.0
	ball.spin = 0.0
	ball.v = Vector3.ZERO


## Frappe du ballon par men[i] (tir, passe, dégagement)
func kick(i: int, vel: Vector3, spin := 0.0, is_shot := false) -> void:
	if carrier == i:
		carrier = -1
	if ball.p.y > 0.5 and men[i]["role"] == "gk":
		ball.p.y = 0.6
	ball.v = vel
	ball.spin = spin
	_no_pick[i] = 0.28
	last_team = men[i]["team"]
	_shot_live = is_shot
	_shot_team = men[i]["team"]
	for m in men:
		m["tried"] = false
	_kick_anim(i, clampf(vel.length() / 16.0, 0.9, 1.4))


func _kick_anim(i: int, speed: float) -> void:
	var m: Dictionary = men[i]
	if m["player"]:
		foot._player_anim(speed)
	else:
		m["anim"] = 0.55 / speed
		m["node"].play_clip("kick", 0.05, speed)


func _goal(team: int) -> void:
	score[team] += 1
	Audio.play_sfx("coin", -6.0)
	if team == 0:
		_note("BUUUT ! Ton équipe marque : %d - %d !" % score, true)
	else:
		_note("But de « %s »... %d - %d." % [opp_name, score[0], score[1]], true)
	for m in men:
		if not m["player"]:
			m["anim"] = 3.0
			m["node"].play_clip("dance" if m["team"] == team else "idle", 0.3)
	carrier = -1
	pause = 3.5
	_restart = {"kickoff": 1 - team}


func _set_restart(team: int, at: Vector2) -> void:
	carrier = -1
	ball.reset(at)
	pause = 1.4
	_restart = {"team": team, "at": at}
	# Les adversaires à 3 m
	for i in men.size():
		if men[i]["team"] != team and pos(i).distance_to(at) < 3.0:
			var away := (pos(i) - at).normalized() if pos(i).distance_to(at) > 0.1 else Vector2(-_attack(team), 0)
			_set_pos(i, _clamp_pitch(at + away * 3.2))


## Coup d'envoi : tout le monde à sa place, ballon au centre ; « team » l'engage
func kickoff(team: int) -> void:
	carrier = -1
	ball.reset()
	_shot_live = false
	for i in men.size():
		var h := _home(i)
		var m: Dictionary = men[i]
		var a := _attack(m["team"])
		if m["role"] != "gk":
			h.x = minf(h.x * a, -1.0) * a # chacun dans sa moitié
		if i == 0 and team == 0:
			h = Vector2(-0.4, 0)
		_set_pos(i, h)
		m["vel"] = Vector2.ZERO
		m["face"] = Vector2(a, 0)
		if not m["player"]:
			m["node"].rotation.y = atan2(-a, 0.0)
			m["node"].rotation.z = 0.0
			m["node"].play_clip("idle", 0.2)
	foot.player.velocity = Vector3.ZERO
	foot.player.camera_rig.yaw = -PI / 2.0
	foot.player.model.rotation.y = -PI / 2.0
	pause = 2.5
	_restart = {"team": team, "at": Vector2.ZERO}


func _resume() -> void:
	if _restart.has("kickoff"):
		kickoff(int(_restart["kickoff"]))
		return
	var team: int = int(_restart.get("team", 0))
	var at: Vector2 = _restart.get("at", Vector2.ZERO)
	_restart = {}
	# Le plus proche de l'équipe qui a la remise prend le ballon
	var best := -1
	var bd := INF
	for i in men.size():
		if men[i]["team"] == team and men[i]["role"] != "gk":
			var d := pos(i).distance_to(at)
			if d < bd:
				bd = d
				best = i
	if best >= 0:
		_set_pos(best, _clamp_pitch(at - Vector2(_attack(team) * 0.5, 0)))
		men[best]["face"] = Vector2(_attack(team), 0)
		_take(best)
	if at == Vector2.ZERO:
		_note("Coup d'envoi !")


func _hold_positions(delta: float) -> void:
	for m in men:
		if not m["player"]:
			m["anim"] = float(m["anim"]) - delta
			if m["anim"] <= 0.0:
				m["node"].locomote(0.0)


func _update_mesh(delta: float) -> void:
	if not is_instance_valid(_mesh):
		return
	_mesh.global_position = world(ball.p)
	var hv := Vector2(ball.v.x, ball.v.z)
	if hv.length() > 0.2:
		var axis := Vector3(hv.y, 0, -hv.x).normalized()
		_mesh.rotate(axis, -hv.length() * delta / FootBall.R)


# --- Actions du joueur --------------------------------------------------------------------------------

## Pression sur le tireur : un adversaire tout près gêne la frappe
func _pressure(i: int) -> float:
	var me := pos(i)
	var best := INF
	for j in men.size():
		if men[j]["team"] != men[i]["team"] and men[j]["role"] != "gk":
			best = minf(best, pos(j).distance_to(me))
	return clampf((2.0 - best) / 2.0, 0.0, 1.0)


func player_shoot(power: float, aim: float) -> void:
	if not player_can_kick():
		return
	var err := _pressure(0) * 0.06 + (0.05 if ball.p.y > 0.4 else 0.0)
	var r: Array = FootBall.shot(ball.p, 1.0, aim, power, err, _rng)
	kick(0, r[0], r[1], true)


## Passe : au coéquipier le mieux placé dans la direction donnée (stick ou regard), dans sa course
func player_pass(dir: Vector2, lobbed: bool) -> void:
	if not player_can_kick():
		return
	var from: Vector2 = ball.flat()
	var best := -1
	var bs := -INF
	for j in men.size():
		if j == 0 or men[j]["team"] != 0:
			continue
		var d := pos(j) - from
		if d.length() < 2.0:
			continue
		var align := d.normalized().dot(dir)
		if align < 0.35:
			continue
		var s := align * 3.0 - d.length() / 12.0 - (1.5 if men[j]["role"] == "gk" else 0.0)
		if s > bs:
			bs = s
			best = j
	var to := _clamp_pitch(from + dir * 11.0, 1.0)
	if best >= 0:
		var mv: Vector2 = men[best]["vel"]
		var t := from.distance_to(pos(best)) / (13.0 if not lobbed else 9.0)
		to = _clamp_pitch(pos(best) + mv * t * 1.1 + dir * (1.5 if lobbed else 0.6), 0.8)
		men[best]["receive"] = 2.0
	var v: Vector3 = FootBall.lob(from, to) if lobbed else FootBall.ground_pass(from, to)
	var err := _pressure(0) * 0.05
	v = v.rotated(Vector3.UP, _rng.randfn(0.0, 0.02 + err))
	kick(0, v)


## Feinte / crochet : changement de direction brusque ; les défenseurs proches se font souvent effacer
func player_skill(dir: Vector2) -> bool:
	if carrier != 0:
		return false
	var m: Dictionary = men[0]
	var face: Vector2 = m["face"]
	var nd := dir if dir.length() > 0.3 and dir.normalized().dot(face) < 0.8 else face.rotated((1.0 if _rng.randf() < 0.5 else -1.0) * 1.25)
	m["skill"] = 0.4
	m["skill_dir"] = nd.normalized()
	var beaten := 0
	for j in men.size():
		var o: Dictionary = men[j]
		if o["team"] == 1 and o["role"] != "gk" and pos(j).distance_to(pos(0)) < 2.6 and _rng.randf() < 0.65:
			o["stun"] = 0.8
			beaten += 1
	if beaten > 0:
		_note(["Crochet !", "Quel dribble !", "Il l'a effacé !", "Passement de jambes !"][_rng.randi() % 4], true)
	return true


## Tacle du joueur sur le porteur adverse
func player_tackle() -> void:
	if carrier < 0 or men[carrier]["team"] != 1 or _player_stun > 0.0:
		return
	var o := carrier
	var d := pos(0) - pos(o)
	if d.length() > TACKLE:
		return
	foot._player_anim(1.4)
	var from_behind: bool = d.normalized().dot(men[o]["face"]) < -0.3
	if _rng.randf() < (0.4 if from_behind else 0.62):
		if from_behind and _rng.randf() < 0.45:
			_note("Faute ! Tacle par derrière : coup franc pour « %s »." % opp_name, true)
			_set_restart(1, ball.flat())
			return
		_win_ball(0, o)
		_note("Tacle réussi !")
	else:
		# Raté : on perd l'équilibre un instant
		_player_stun = 0.5
		foot.player.frozen = true


func _win_ball(tackler: int, victim: int) -> void:
	carrier = -1
	var away := (ball.flat() - pos(victim)).normalized() if ball.flat().distance_to(pos(victim)) > 0.05 else Vector2(_attack(men[tackler]["team"]), 0)
	ball.v = Vector3(away.x, 0.0, away.y) * 3.0
	_no_pick[victim] = 0.7
	men[victim]["stun"] = 0.45


## Demander le ballon au coéquipier qui l'a
func player_call() -> void:
	if carrier > 0 and men[carrier]["team"] == 0:
		call = true
		men[carrier]["think"] = 0.0


# --- Intelligence des joueurs ---------------------------------------------------------------------------

func _update_ais(delta: float) -> void:
	var b: Vector2 = ball.flat()
	# Ballon libre : qui y va (le plus rapide de chaque équipe) ; adversaire porteur : qui presse, qui couvre
	var chaser := [-1, -1]
	var ct := [INF, INF]
	var presser := [-1, -1]
	var pd := [INF, INF]
	var cover := [-1, -1]
	var cd2 := [INF, INF]
	for i in men.size():
		var m: Dictionary = men[i]
		if m["role"] == "gk":
			continue
		var t: float = pos(i).distance_to(b) / float(m["speed"]) + (0.0 if m["stun"] <= 0.0 else 1.0)
		if t < ct[m["team"]]:
			ct[m["team"]] = t
			chaser[m["team"]] = i
		if carrier >= 0 and men[carrier]["team"] != m["team"]:
			var d := pos(i).distance_to(pos(carrier))
			if d < pd[m["team"]]:
				cover[m["team"]] = presser[m["team"]]
				cd2[m["team"]] = pd[m["team"]]
				pd[m["team"]] = d
				presser[m["team"]] = i
			elif d < cd2[m["team"]]:
				cd2[m["team"]] = d
				cover[m["team"]] = i
	for i in men.size():
		if i == 0:
			continue
		var m: Dictionary = men[i]
		for k in ["cd", "stun", "anim", "think", "receive", "skill", "knock", "dive"]:
			m[k] = float(m[k]) - delta
		if m["role"] == "gk":
			_goalkeeper(i, delta)
			continue
		var n: Node3D = m["node"]
		if m["stun"] > 0.0:
			m["vel"] = m["vel"].move_toward(Vector2.ZERO, 12.0 * delta)
			_move(i, delta)
			continue
		var team: int = m["team"]
		var target: Vector2
		var spd: float = m["speed"]
		if carrier == i:
			var r: Array = _carry(i)
			target = r[0]
			spd = r[1]
			if carrier != i: # il vient de tirer ou passer
				continue
		elif m["receive"] > 0.0 and carrier < 0:
			target = _intercept(i)
		elif carrier < 0:
			if chaser[team] == i and not (team == 0 and chaser[0] == 0):
				target = _intercept(i)
			else:
				target = _shape(i)
				spd *= 0.75
		elif men[carrier]["team"] == team:
			target = _support(i)
			spd *= 0.85
		else:
			var cp := pos(carrier)
			var own := Vector2(-_attack(team) * HL, 0)
			if presser[team] == i:
				target = cp + (own - cp).normalized() * 0.8
				if pos(i).distance_to(cp) < 1.35 and m["cd"] <= 0.0:
					_ai_tackle(i)
			elif cover[team] == i:
				target = cp + (own - cp).normalized() * 4.5
				spd *= 0.9
			else:
				target = _shape(i)
				spd *= 0.8
		var to := _clamp_pitch(target) - pos(i)
		var want := to.normalized() * minf(spd, to.length() * 3.0) if to.length() > 0.15 else Vector2.ZERO
		m["vel"] = m["vel"].move_toward(want, 16.0 * delta)
		_move(i, delta)
		if carrier != i:
			var tb := b - pos(i)
			# Dès qu'il se déplace, il regarde où il va (sinon il marcherait à reculons) ; arrêté, vers le ballon
			if m["vel"].length() > 0.25:
				m["face"] = m["vel"].normalized()
			elif tb.length() > 0.1:
				m["face"] = tb.normalized()
		elif m["vel"].length() > 0.5:
			m["face"] = m["vel"].normalized() if m["skill"] <= 0.0 else m["skill_dir"]
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-m["face"].x, -m["face"].y), 1.0 - exp(-12.0 * delta))


func _move(i: int, delta: float) -> void:
	var m: Dictionary = men[i]
	_set_pos(i, _clamp_pitch(pos(i) + m["vel"] * delta, 0.3))
	if m["anim"] <= 0.0:
		var sp: float = m["vel"].length()
		m["node"].locomote(sp if sp > 0.25 else 0.0)


## Point où aller chercher le ballon (là où il sera quand on l'atteindra)
func _intercept(i: int) -> Vector2:
	var b: Vector2 = ball.flat()
	var bv := Vector2(ball.v.x, ball.v.z)
	var me := pos(i)
	var t := 0.0
	for k in 4:
		t = me.distance_to(b + bv * t * 0.8) / float(men[i]["speed"])
	return _clamp_pitch(b + bv * minf(t, 1.5) * 0.8)


## Placement en bloc : selon le poste, le ballon et l'équipe qui a la possession
func _shape(i: int) -> Vector2:
	var m: Dictionary = men[i]
	var a := _attack(m["team"])
	var h := _home(i)
	var b: Vector2 = ball.flat()
	var poss: bool = carrier >= 0 and men[carrier]["team"] == m["team"]
	var x := h.x + b.x * 0.45 + a * (3.5 if poss else -1.5)
	var z := h.y * 0.8 + b.y * 0.4
	# Défenseur : jamais derrière son but, toujours entre le ballon et son but
	if m["role"] == "def":
		x = clampf(x, -HL + 2.5, HL - 2.5)
		if (x - b.x) * a > -1.0:
			x = b.x - a * 3.0
	return _clamp_pitch(Vector2(x, z), 1.0)


## Sans le ballon, son équipe attaque : appels en profondeur, se démarquer
func _support(i: int) -> Vector2:
	var m: Dictionary = men[i]
	var a := _attack(m["team"])
	var cp := pos(carrier)
	var t := _shape(i)
	if m["role"] != "def":
		# Appel : devant le porteur, dans l'espace, du côté opposé
		var side := -signf(cp.y) if absf(cp.y) > 1.0 else (1.0 if i % 2 == 0 else -1.0)
		t = Vector2(cp.x + a * (6.0 if m["role"] == "att" else 3.0), side * (4.0 if m["role"] == "att" else 6.0))
		if absf(t.x) > HL - 4.0:
			t.x = a * (HL - 4.0)
	# Se décaler de l'adversaire le plus proche
	var o := _nearest_opp(i, t)
	if o >= 0 and pos(o).distance_to(t) < 2.0:
		t += (t - pos(o)).normalized() * 1.5
	if t.distance_to(cp) < 3.5:
		t = cp + (t - cp).normalized() * 3.5
	return _clamp_pitch(t, 1.0)


func _nearest_opp(i: int, at: Vector2) -> int:
	var best := -1
	var bd := INF
	for j in men.size():
		if men[j]["team"] != men[i]["team"] and men[j]["role"] != "gk":
			var d := pos(j).distance_to(at)
			if d < bd:
				bd = d
				best = j
	return best


## Le porteur décide : tir, passe, feinte ou conduite. Renvoie [cible, vitesse]
func _carry(i: int) -> Array:
	var m: Dictionary = men[i]
	var a := _attack(m["team"])
	var me := pos(i)
	var goal := Vector2(a * HL, 0)
	var to_goal := goal - me
	var dist := to_goal.length()
	var o := _nearest_opp(i, me)
	var od: float = pos(o).distance_to(me) if o >= 0 else INF
	if m["think"] <= 0.0 or (call and m["team"] == 0):
		m["think"] = _rng.randf_range(0.3, 0.6)
		# Ton coéquipier te donne le ballon quand tu le demandes
		if call and m["team"] == 0:
			call = false
			_ai_pass(i, 0)
			return [me, 0.0]
		var lane := _lane_clear(me, goal, m["team"])
		if dist < 13.5 and absf(me.y) < 7.5 and (lane or dist < 7.0) and _rng.randf() < 0.7:
			var power := clampf(dist / 16.0 + _rng.randf_range(-0.12, 0.12), 0.3, 0.88)
			var r: Array = FootBall.shot(ball.p, a, _rng.randf_range(-0.95, 0.95), power, 0.04 + _pressure(i) * 0.06, _rng)
			kick(i, r[0], r[1], true)
			if m["team"] == 1:
				_note("Frappe de « %s » !" % opp_name)
			return [me, 0.0]
		var mate := _best_mate(i)
		if mate >= 0 and ((od < 2.3 and _rng.randf() < 0.75) or (float(mate_score) > 3.0 and _rng.randf() < 0.5) or (mate == 0 and _rng.randf() < 0.45)):
			_ai_pass(i, mate)
			return [me, 0.0]
		if od < 1.7 and _rng.randf() < 0.4:
			m["skill"] = 0.45
			m["skill_dir"] = to_goal.normalized().rotated((1.0 if _rng.randf() < 0.5 else -1.0) * 1.1)
			if o > 0 and _rng.randf() < 0.5:
				men[o]["stun"] = 0.6
	var dir := to_goal.normalized()
	if m["skill"] > 0.0:
		return [me + m["skill_dir"] * 3.0, float(m["speed"]) * 1.1]
	if o >= 0 and od < 3.0:
		dir = (dir + (me - pos(o)).normalized() * 0.9).normalized()
	if absf(me.y) > HW - 1.6:
		dir.y -= signf(me.y) * 0.7
	return [me + dir.normalized() * 3.0, float(m["speed"]) * 0.82]


var mate_score := 0.0


## Coéquipier le mieux placé pour une passe (plus avancé, démarqué, ligne de passe libre)
func _best_mate(i: int) -> int:
	var a := _attack(men[i]["team"])
	var me := pos(i)
	var best := -1
	mate_score = -INF
	for j in men.size():
		if j == i or men[j]["team"] != men[i]["team"] or men[j]["role"] == "gk":
			continue
		var p := pos(j)
		var o := _nearest_opp(j, p)
		var free: float = clampf(pos(o).distance_to(p), 0.0, 6.0) if o >= 0 else 6.0
		var s := (p.x - me.x) * a * 0.35 + free * 0.7 - me.distance_to(p) * 0.12 + (1.0 if men[j]["player"] else 0.0)
		if not _lane_clear(me, p, men[i]["team"]):
			s -= 4.0
		if s > mate_score:
			mate_score = s
			best = j
	return best


func _ai_pass(i: int, j: int) -> void:
	var from: Vector2 = ball.flat()
	var mv: Vector2 = men[j]["vel"]
	var t := from.distance_to(pos(j)) / 12.0
	var to := _clamp_pitch(pos(j) + mv * t, 0.8)
	var lobbed := not _lane_clear(from, to, men[i]["team"]) and from.distance_to(to) > 8.0
	var v: Vector3 = FootBall.lob(from, to) if lobbed else FootBall.ground_pass(from, to)
	v = v.rotated(Vector3.UP, _rng.randfn(0.0, 0.03 + _pressure(i) * 0.05))
	men[j]["receive"] = 2.0
	kick(i, v)


## Aucun adversaire près de la ligne entre a et b
func _lane_clear(a: Vector2, b: Vector2, team: int) -> bool:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.01:
		return true
	for j in men.size():
		if men[j]["team"] == team:
			continue
		var p := pos(j)
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		if t > 0.05 and t < 0.95 and (a + ab * t).distance_to(p) < 1.1:
			return false
	return true


func _ai_tackle(i: int) -> void:
	var m: Dictionary = men[i]
	m["cd"] = _rng.randf_range(0.8, 1.5)
	if _rng.randf() > 0.6:
		return
	var o := carrier
	var victim_is_player: bool = men[o]["player"]
	m["anim"] = 0.4
	m["node"].play_clip("kick", 0.05, 1.5)
	var chance := 0.42
	if victim_is_player and men[0]["skill"] > 0.0:
		chance = 0.12 # en pleine feinte
	elif men[o]["vel"].length() < 1.5:
		chance = 0.3 # ballon protégé
	var behind: bool = (pos(i) - pos(o)).normalized().dot(men[o]["face"]) < -0.3
	if _rng.randf() < chance:
		if behind and _rng.randf() < 0.3:
			_note("Faute ! Coup franc pour %s." % ("ton équipe" if men[o]["team"] == 0 else "« %s »" % opp_name), true)
			_set_restart(men[o]["team"], ball.flat())
			return
		_win_ball(i, o)
		if victim_is_player:
			_note("Tu perds le ballon !")
	elif victim_is_player:
		pass


# --- Gardiens ------------------------------------------------------------------------------------------

func _goalkeeper(i: int, delta: float) -> void:
	var m: Dictionary = men[i]
	var n: Node3D = m["node"]
	var team: int = m["team"]
	var a := _attack(team)
	var own := Vector2(-a * HL, 0)
	var b: Vector2 = ball.flat()
	var me := pos(i)
	# Plongeon en cours
	if m["dive"] > 0.0:
		var k: float = clampf(1.0 - m["dive"] / 0.9, 0.0, 1.0)
		var side: float = m["dive_side"]
		if k < 0.45:
			_set_pos(i, _clamp_pitch(Vector2(me.x, clampf(me.y + side * 4.5 * delta, -FootBall.GOAL_W / 2.0 - 0.6, FootBall.GOAL_W / 2.0 + 0.6))))
		n.rotation.z = side * a * minf(1.0, k * 2.5) * 1.25
		if m["save"] and _shot_live and me.distance_to(b) < 1.7 and ball.p.y < 2.4:
			_save(i)
		if m["dive"] <= 0.05:
			n.rotation.z = 0.0
		return
	n.rotation.z = 0.0
	if carrier == i:
		# Le ballon dans les mains : il relance vers un coéquipier démarqué
		m["hold"] = float(m["hold"]) + delta
		m["face"] = Vector2(a, 0)
		n.rotation.y = atan2(-a, 0.0)
		if m["anim"] <= 0.0:
			n.locomote(0.0)
		if m["hold"] > 1.4:
			var j := _best_mate(i)
			if j >= 0:
				var to: Vector2 = pos(j) + men[j]["vel"] * 0.8
				var v: Vector3 = FootBall.ground_pass(b, to) if b.distance_to(to) < 15.0 else FootBall.lob(b, to)
				men[j]["receive"] = 2.0
				kick(i, v)
			else:
				kick(i, FootBall.lob(b, Vector2(0, _rng.randf_range(-5, 5))))
		return
	# Placement sur la ligne ballon - centre du but, plus avancé quand le ballon est loin
	var dv := b - own
	var out := clampf(0.6 + dv.length() * 0.05, 0.6, 2.4)
	var target := own + dv.normalized() * out
	target.y = clampf(target.y, -FootBall.GOAL_W / 2.0 - 0.2, FootBall.GOAL_W / 2.0 + 0.2)
	# Sortie sur un ballon libre dans sa surface
	if carrier < 0 and absf(b.x - own.x) < 6.0 and absf(b.y) < 4.5 and not _shot_live:
		target = b
	if _shot_live and _shot_team != team and not m["tried"]:
		_try_dive(i)
	var to := target - me
	var want := to.normalized() * minf(5.5, to.length() * 4.0) if to.length() > 0.1 else Vector2.ZERO
	m["vel"] = m["vel"].move_toward(want, 18.0 * delta)
	_set_pos(i, pos(i) + m["vel"] * delta)
	var tb := b - pos(i)
	if tb.length() > 0.1:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-tb.x, -tb.y), 1.0 - exp(-10.0 * delta))
	if m["anim"] <= 0.0:
		n.locomote(m["vel"].length())
	if m["save"] and _shot_live and pos(i).distance_to(b) < 1.1 and ball.p.y < 2.3:
		_save(i)


## Tir cadré qui arrive : le gardien décide une fois s'il l'arrête, et plonge si besoin
func _try_dive(i: int) -> void:
	var m: Dictionary = men[i]
	var a := _attack(m["team"])
	var own_x := -a * HL
	if ball.v.x * a >= -1.0:
		return # le ballon ne va pas vers son but
	var t: float = (own_x - ball.p.x) / ball.v.x
	if t < 0.0 or t > 1.4:
		return
	m["tried"] = true
	var z: float = ball.p.z + ball.v.z * t
	var y: float = maxf(FootBall.R, ball.p.y + ball.v.y * t - 0.5 * FootBall.G * t * t)
	if absf(z) > FootBall.GOAL_W / 2.0 + 0.25 or y > FootBall.GOAL_H + 0.3:
		m["save"] = false
		return # non cadré : il laisse passer
	var dz := z - pos(i).y
	var speed: float = ball.v.length()
	var chance := clampf(1.02 - speed * 0.021 - maxf(0.0, absf(dz) - 0.5) * 0.28 - (0.12 if y > 1.4 else 0.0) - (0.1 if t < 0.35 else 0.0), 0.08, 0.88)
	m["save"] = _rng.randf() < chance
	if absf(dz) > 0.55:
		m["dive"] = 0.9
		m["dive_side"] = signf(dz)
		m["anim"] = 0.9
		m["node"].play_clip("jump", 0.05, 1.3)


func _save(i: int) -> void:
	var m: Dictionary = men[i]
	var a := _attack(m["team"])
	m["save"] = false
	_shot_live = false
	var speed: float = ball.v.length()
	if speed < 17.0 and ball.p.y < 1.7 and m["dive"] <= 0.0:
		_take(i)
		_note("Arrêt du gardien !" if m["team"] == 1 else "Ton gardien capte le ballon !", true)
	else:
		# Parade : le ballon est repoussé sur le côté
		ball.v = Vector3(a * _rng.randf_range(3.0, 6.0), _rng.randf_range(2.0, 4.5), signf(ball.p.z + 0.01) * _rng.randf_range(4.0, 8.0))
		ball.spin = 0.0
		_no_pick[i] = 0.5
		last_team = m["team"]
		_note("Parade du gardien !" if m["team"] == 1 else "Superbe parade de ton gardien !", true)
