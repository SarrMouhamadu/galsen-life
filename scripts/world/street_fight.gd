extends Node
## Bagarre de rue : le joueur frappe (touche F, clic gauche, bouton COUP) un passant ou, en ligne, un autre joueur.
## Le passant frappé riposte ou s'enfuit, les témoins crient ; la police s'en mêle (sauf légitime défense).
## Le soir, un fakhman cherche parfois des histoires. KO : on se réveille à l'hôpital (soins payants).
## En ligne, les coups entre joueurs passent par le serveur (scripts/net/net_fight.gd).

const RANGE := 1.7 ## portée d'un coup de poing
const CONE := 0.35 ## devant soi (produit scalaire minimal avec la direction du regard)
const COOLDOWN := 0.42
const WITNESS_RANGE := 14.0
const PROVOKE_EVERY := Vector2(180.0, 360.0) ## secondes entre deux provocations (la nuit ; deux fois moins le jour)
const PROVOKE_LINES := ["Yow ! Lan nga may xool ? (qu'est-ce que tu regardes ?)", "Sa yaay ! Kaay fii ! (viens ici !)",
	"Danga ma xas ? Dinaa la dóor ! (tu me cherches ?)", "Yow, jox ma sa xaalis ! (donne-moi ton argent !)"]

var main
var status := ""
var _cd := 0.0
var _heat := 0.0 ## secondes depuis le dernier coup porté (la police n'est appelée qu'une fois par bagarre)
var _called := false
var _provoke_t := 240.0
var _hurt_note := 0.0
var _ko_by := -1 ## en ligne : joueur qui nous a mis KO


func _ready() -> void:
	for p in main.peds:
		p.fight = self
	if Net.online and Net.fight:
		Net.fight.hit.connect(_on_net_hit)
		Net.fight.fx.connect(func(id, clip): main.remote_players.play_remote(id, clip))
		Net.fight.ko_given.connect(func(victim): GameState.notify.emit("« Daanu na ! » %s est KO." % victim))


func _physics_process(delta: float) -> void:
	_cd -= delta
	_hurt_note -= delta
	_heat += delta
	if _heat > 20.0:
		_called = false
	if Input.is_action_just_pressed("attack") and _can_fight():
		attack()
	_provoke(delta)


func _can_fight() -> bool:
	var p = main.player
	if main.foot and main.foot.in_match():
		return false # au mini-foot, COUP sert à passer le ballon
	return not GameState.typing and not main.hud.choices_open() and p.current_vehicle == null and p.riding == null \
		and not p.frozen and GameState.health > 0.0 and not get_tree().paused


## Coup de poing : alterne les deux mains ; touche ce qui est juste devant
func attack() -> void:
	if _cd > 0.0:
		return
	_cd = COOLDOWN
	var p = main.player
	p.model.play_clip("punch", 0.05, 1.35)
	p.lock_anim(0.45)
	var target = _target()
	if target == null:
		return
	# Le coup part : il porte un instant plus tard (le bras est tendu)
	get_tree().create_timer(0.16).timeout.connect(_land.bind(target))


func _forward() -> Vector3:
	var y: float = main.player.model.rotation.y
	return Vector3(-sin(y), 0, -cos(y))


func _target() -> Variant:
	var p = main.player
	var pp: Vector3 = p.global_position
	var fwd := _forward()
	var best = null
	var bd := RANGE
	for ped in main.peds:
		if not ped.visible or ped.knocked:
			continue
		var d: Vector3 = ped.global_position - pp
		d.y = 0.0
		if d.length() < bd and (d.length() < 0.5 or d.normalized().dot(fwd) > CONE):
			bd = d.length()
			best = ped
	if Net.online and main.remote_players:
		var o = main.remote_players.nearest(pp, RANGE + 0.3)
		if o != null and o["vehicle"] == null:
			var d2: Vector3 = o["pos"] - pp
			d2.y = 0.0
			if d2.length() < bd + 0.3 and (d2.length() < 0.5 or d2.normalized().dot(fwd) > CONE):
				best = {"remote": o["id"], "pseudo": o["pseudo"]}
	return best


func _land(target) -> void:
	_heat = 0.0
	Audio.play_sfx("thud", -9.0)
	if target is Dictionary:
		# Autre joueur : le serveur vérifie la distance et lui transmet le coup
		Net.fight.punch(target["remote"])
		if not _called:
			_called = true
			GameState.add_wanted(1, "Tu frappes %s en pleine rue : la police est prévenue !" % target["pseudo"])
		return
	if not is_instance_valid(target) or target.knocked:
		return
	var self_defense: bool = target.started
	var ko: bool = target.take_hit(main.player.global_position, randf_range(20.0, 30.0))
	for ped in main.peds:
		if ped != target and ped.visible and ped.global_position.distance_to(target.global_position) < WITNESS_RANGE and randf() < 0.35:
			ped.witness()
	if self_defense:
		if ko:
			GameState.notify.emit("Le fakhman est à terre. Légitime défense : la police ne te cherche pas.")
		return
	if not _called and (randf() < 0.5 or _cop_near()):
		_called = true
		GameState.add_wanted(1, "Bagarre en pleine rue ! Quelqu'un a appelé la police.")
	if ko:
		if GameState.wanted < 2:
			GameState.add_wanted(1, "Tu as mis un passant KO : la police te recherche !")
		GameState.notify.emit("« Daanu na ! » Le passant est KO.")


func _cop_near() -> bool:
	var pp: Vector3 = main.player.global_position
	for v in get_tree().get_nodes_in_group("vehicles"):
		if v.vehicle_type == "police" and v.global_position.distance_to(pp) < 50.0:
			return true
	return false


## Le joueur reçoit un coup (passant ou autre joueur)
func hit_player(dmg: float, by: String) -> void:
	if GameState.health <= 0.0:
		return
	GameState.health = maxf(GameState.health - dmg, 0.0)
	main.player.model.play_clip("hit", 0.06)
	main.player.lock_anim(0.4)
	Audio.play_sfx("thud", -7.0)
	if _hurt_note <= 0.0:
		_hurt_note = 4.0
		GameState.notify.emit("%s te frappe ! Riposte (F) ou fuis." % by)
	if GameState.health <= 0.0:
		GameState.faint_reason = "ko"
		if _ko_by != -1 and Net.online and Net.fight:
			Net.fight.report_ko(_ko_by)
		_ko_by = -1


func _on_net_hit(attacker: int, who: String, dmg: int) -> void:
	_ko_by = attacker
	hit_player(float(dmg), who)


## Le soir surtout, un fakhman vient chercher des histoires
func _provoke(delta: float) -> void:
	var p = main.player
	if p.current_vehicle != null or p.riding != null or p.interior_door != Vector3.ZERO or p.frozen:
		return
	var h := GameState.game_minutes / 60.0
	var night := h < 5.0 or h > 21.0
	_provoke_t -= delta * (1.0 if night else 0.5)
	if _provoke_t > 0.0:
		return
	_provoke_t = randf_range(PROVOKE_EVERY.x, PROVOKE_EVERY.y)
	for ped in main.peds:
		if not ped.visible or ped.knocked or ped.mood != "":
			continue
		var d: float = ped.global_position.distance_to(p.global_position)
		if d > 6.0 and d < 22.0:
			ped.provoke(PROVOKE_LINES.pick_random())
			GameState.notify.emit("Un fakhman te cherche des histoires ! Défends-toi (F) ou fuis.")
			return


## Test : -- --fight-test (frappe un passant jusqu'au KO, puis reçoit des coups)
func self_test() -> void:
	var p = main.player
	var ped = main.peds[0]
	ped.global_position = p.global_position + _forward() * 1.0
	ped._calm()
	var hits := 0
	while not ped.knocked and hits < 10:
		ped.global_position = p.global_position + _forward() * 1.0
		_cd = 0.0
		attack()
		hits += 1
		await get_tree().create_timer(0.25).timeout
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--shot=") and hits == 2:
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot="))
		await get_tree().create_timer(0.25).timeout
	print("FIGHT passant KO=%s en %d coups, recherché=%d, humeur témoins=%s" % [ped.knocked, hits, GameState.wanted,
		main.peds.slice(1, 8).map(func(x): return x.mood)])
	var other = main.peds[1]
	other.global_position = p.global_position + _forward() * 3.0
	GameState.revive()
	other.provoke("Yow !")
	var hp := GameState.health
	await get_tree().create_timer(6.0).timeout
	print("FIGHT provocation : santé %d -> %d, agresseur humeur=%s" % [int(hp), int(GameState.health), other.mood])
	# On riposte : légitime défense, pas de police en plus
	var stars := GameState.wanted
	var n := 0
	while not other.knocked and n < 10:
		other.global_position = main.player.global_position + _forward() * 1.0
		_cd = 0.0
		attack()
		n += 1
		await get_tree().create_timer(0.5).timeout
	print("FIGHT légitime défense : fakhman KO=%s en %d coups, étoiles %d -> %d" % [other.knocked, n, stars, GameState.wanted])
