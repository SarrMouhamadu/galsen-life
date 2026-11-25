extends RefCounted
## Ballon de mini-foot : physique commune au match contre l'ordinateur (scripts/world/foot_match.gd) et au
## serveur des matchs entre joueurs (scripts/net/net_foot.gd), et calcul des frappes (tirs, passes, lobs).
## Repère du terrain : centre au sol, x dans la longueur (buts en x = ±L/2), z dans la largeur.
## Pas de référence aux autoloads : le serveur précharge ce script depuis Net.

const R := 0.11 ## rayon (ballon taille 5)
const G := 9.81
const L := 36.0
const W := 20.0
const GOAL_W := 3.0
const GOAL_H := 2.0
const GOAL_DEPTH := 1.1
const FENCE_H := 4.5 ## bandes + grillage ; au-dessus, le ballon sort

var p := Vector3(0, R, 0)
var v := Vector3.ZERO
var spin := 0.0 ## effet : accélération latérale (m/s²), positive vers la gauche de la trajectoire
var in_goal := 0 ## 1 : dans le but de droite (+x), -1 : de gauche, 0 : en jeu


func reset(at := Vector2.ZERO) -> void:
	p = Vector3(at.x, R, at.y)
	v = Vector3.ZERO
	spin = 0.0
	in_goal = 0


func on_ground() -> bool:
	return p.y < R + 0.03


func flat() -> Vector2:
	return Vector2(p.x, p.z)


## Avance d'un pas. Renvoie un évènement : "goal+" / "goal-" (le ballon a entièrement franchi la ligne
## de but de droite / de gauche), "post" (poteau ou barre), "board" (bande), "out" (par-dessus le grillage), ""
func step(dt: float) -> String:
	var ev := ""
	var hv := Vector2(v.x, v.z)
	var hs := hv.length()
	# Effet (Magnus) : la trajectoire s'incurve, de moins en moins
	if absf(spin) > 0.05 and hs > 3.0 and not on_ground():
		var perp := Vector2(-hv.y, hv.x) / hs
		v.x += perp.x * spin * dt
		v.z += perp.y * spin * dt
	spin *= exp(-0.9 * dt)
	# Air
	v -= v * minf(1.0, 0.012 * v.length() * dt)
	v.y -= G * dt
	p += v * dt
	if p.y < R:
		p.y = R
		if v.y < -1.0:
			v.y = -v.y * 0.5 # rebond sur le gazon synthétique
			v.x *= 0.88
			v.z *= 0.88
			spin *= 0.5
		else:
			v.y = 0.0
	if on_ground() and absf(v.y) < 0.5:
		# Roulement : freinage du gazon (≈ 1 m/s² + un peu selon la vitesse)
		hv = Vector2(v.x, v.z)
		hs = hv.length()
		if hs > 0.0:
			var ns := maxf(0.0, hs - (0.9 + 0.12 * hs) * dt)
			v.x *= ns / hs
			v.z *= ns / hs
	var hl := L / 2.0
	var hw := W / 2.0
	if in_goal != 0:
		# Dans les filets : le ballon reste dans la cage et s'y arrête
		var back := hl + GOAL_DEPTH - R
		if absf(p.x) > back:
			p.x = signf(p.x) * back
			v.x *= -0.1
			v.z *= 0.4
		if absf(p.z) > GOAL_W / 2.0 - R:
			p.z = signf(p.z) * (GOAL_W / 2.0 - R)
			v.z *= -0.2
		if p.y > GOAL_H - R:
			p.y = GOAL_H - R
			v.y = -absf(v.y) * 0.2
		return ""
	# Lignes de but
	if absf(p.x) > hl - R:
		var mouth := absf(p.z) < GOAL_W / 2.0 - R * 0.5 and p.y < GOAL_H - R * 0.5
		var frame := absf(p.z) < GOAL_W / 2.0 + R and p.y < GOAL_H + R
		if mouth:
			if absf(p.x) > hl + R:
				in_goal = 1 if p.x > 0.0 else -1
				return "goal+" if p.x > 0.0 else "goal-"
		elif frame and absf(p.x) < hl + R:
			# Poteau ou barre : ça sonne !
			p.x = signf(p.x) * (hl - R)
			v.x = -v.x * 0.7
			if absf(absf(p.z) - GOAL_W / 2.0) < R * 2.0:
				v.z += signf(p.z) * absf(v.x) * 0.3
			else:
				v.y = -absf(v.y) * 0.5 - 1.0
			ev = "post"
		elif p.y > FENCE_H:
			return "out"
		elif absf(p.z) >= GOAL_W / 2.0 or p.y >= GOAL_H:
			p.x = signf(p.x) * (hl - R)
			v.x = -v.x * 0.55
			ev = "board"
	# Bandes et grillage des côtés
	if absf(p.z) > hw - R:
		if p.y > FENCE_H:
			return "out"
		p.z = signf(p.z) * (hw - R)
		v.z = -v.z * 0.55
		spin = 0.0
		ev = "board"
	return ev


## Vitesse au départ d'une passe à ras de terre pour arriver en `to` avec environ `arrive` m/s
static func ground_pass(from: Vector2, to: Vector2, arrive := 4.5) -> Vector3:
	var d := to - from
	var dist := d.length()
	# Freinage moyen du gazon ≈ 0,9 + 0,12 v : on vise large
	var v0 := clampf(sqrt(arrive * arrive + 2.0 * (1.1 + 0.12 * arrive * 1.5) * dist) + dist * 0.06, 5.0, 19.0)
	var dir := d.normalized() if dist > 0.01 else Vector2(1, 0)
	return Vector3(dir.x * v0, 0.0, dir.y * v0)


## Passe lobée (ou dégagement) qui retombe en `to`
static func lob(from: Vector2, to: Vector2) -> Vector3:
	var d := to - from
	var dist := maxf(d.length(), 2.0)
	var t := 0.75 + dist * 0.045 ## temps de vol
	var dir := d.normalized() if d.length() > 0.01 else Vector2(1, 0)
	var hs := dist / t * 1.04
	return Vector3(dir.x * hs, G * t / 2.0, dir.y * hs)


## Tir vers le but adverse (attack = +1 : but de droite, -1 : de gauche).
## aim : visée dans la largeur du but, de -1 (poteau gauche vu du tireur) à 1 ; power : 0..1 (barre de
## puissance) ; skill_err : imprécision (pression d'un défenseur, mauvais angle, ballon en l'air...).
## Renvoie [vitesse (Vector3), effet]. Une frappe trop puissante peut passer au-dessus.
static func shot(from: Vector3, attack: float, aim: float, power: float, skill_err: float, rng: RandomNumberGenerator) -> Array:
	var gx := attack * L / 2.0
	# Droite du tireur qui regarde le but de droite (+x) : +z ; celui de gauche : -z
	var tz := clampf(aim * attack, -1.0, 1.0) * (GOAL_W / 2.0 - 0.3)
	var target := Vector2(gx + attack * 0.4, tz)
	var from2 := Vector2(from.x, from.z)
	var dist := (target - from2).length()
	var speed := lerpf(11.0, 27.0, power)
	var t := dist / speed
	# Frappe placée : enroulée, elle part vers l'extérieur et revient dans le cadre
	var curl := 0.0
	if power < 0.6:
		curl = -clampf(tz / (GOAL_W / 2.0), -1.0, 1.0) * attack * 2.5 * (0.6 - power) / 0.6
		var d0 := (target - from2).normalized()
		target -= Vector2(-d0.y, d0.x) * 0.5 * curl * t * t
	# Hauteur visée : à ras de terre en frappe placée, de plus en plus haut avec la puissance
	var ty := lerpf(0.25, 1.5, power * power) + rng.randf_range(-0.2, 0.25) + maxf(0.0, power - 0.85) * 4.0
	var err := 0.015 + 0.06 * power * power + skill_err + dist / 260.0
	var dir := (target - from2).normalized().rotated(rng.randfn(0.0, err))
	var vy := (ty - from.y + 0.5 * G * t * t) / maxf(t, 0.05)
	return [Vector3(dir.x * speed, clampf(vy, -2.0, 9.0), dir.y * speed), curl]
