extends RefCounted
## Tracé des trottoirs, partagé par le baker (tools/bake_dakar.gd : ce qu'on voit) et le jeu
## (dakar_city.gd : la collision), pour que les deux restent identiques.
##   - coupés seulement aux vrais carrefours de rues carrossables (un sentier ou une allée qui rejoint
##     la rue ne coupe plus le trottoir) ;
##   - jamais sur la chaussée d'une autre rue (bretelles, carrefours en biais) ;
##   - coins des carrefours remplis (plus de sable entre deux trottoirs).

const SIDEWALK_W := 1.8
const STEP := 1.5 ## longueur des morceaux testés contre les autres chaussées
const CELL := 30.0


## nodes : position 2D de chaque nœud. segs : [a, b, largeur, trottoir (bool), carrossable (bool), au sol (bool)].
## Renvoie {"runs": [...], "corners": [...]} :
##   run : {seg, side, a, b (points sur l'axe), d, n, w, ramp_a, ramp_b}  (côté = n * side)
##   corner : {poly (bord intérieur A, coin, bord intérieur B, bord extérieur B, coin extérieur, bord extérieur A),
##             inner (les 3 premiers points : la bordure), dir (sens des dalles)}
static func plan(nodes: PackedVector2Array, segs: Array) -> Dictionary:
	var degree := {}
	var node_w := {}
	var incident := {}
	for i in segs.size():
		var s: Array = segs[i]
		if not s[4]:
			continue
		for nd in [s[0], s[1]]:
			degree[nd] = int(degree.get(nd, 0)) + 1
			node_w[nd] = maxf(float(node_w.get(nd, 0.0)), float(s[2]))
			if not incident.has(nd):
				incident[nd] = []
			incident[nd].append(i)
	# Grille des chaussées carrossables au sol
	var hash := {}
	for i in segs.size():
		var s: Array = segs[i]
		if not s[4] or not s[5]:
			continue
		var pa: Vector2 = nodes[s[0]]
		var pb: Vector2 = nodes[s[1]]
		var r := float(s[2]) / 2.0
		var lo := Vector2(minf(pa.x, pb.x) - r, minf(pa.y, pb.y) - r)
		var hi := Vector2(maxf(pa.x, pb.x) + r, maxf(pa.y, pb.y) + r)
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
				var k := Vector2i(cx, cy)
				if not hash.has(k):
					hash[k] = []
				hash[k].append(i)
	var on_road := func(p: Vector2, own: int) -> bool:
		var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
		for i in hash.get(k, []):
			if i == own:
				continue
			var s: Array = segs[i]
			var q := Geometry2D.get_closest_point_to_segment(p, nodes[s[0]], nodes[s[1]])
			if p.distance_to(q) < float(s[2]) / 2.0 - 0.25:
				return true
		return false
	var runs: Array = []
	var reach := {} ## [seg, bout (0 : a, 1 : b), côté] → le trottoir va jusqu'au carrefour
	for i in segs.size():
		var s: Array = segs[i]
		if not s[3] or not s[5]:
			continue
		var a: Vector2 = nodes[s[0]]
		var b: Vector2 = nodes[s[1]]
		var L := a.distance_to(b)
		if L < 0.05:
			continue
		var d := (b - a) / L
		var n := Vector2(-d.y, d.x)
		var w := float(s[2])
		var da := int(degree.get(s[0], 0))
		var db := int(degree.get(s[1], 0))
		# Cul-de-sac : le trottoir va jusqu'au bout ; rue qui continue : il chevauche un peu le suivant
		var ta: float = (float(node_w[s[0]]) / 2.0 + SIDEWALK_W) if da > 2 else (-0.3 if da == 2 else 0.0)
		var tb: float = (float(node_w[s[1]]) / 2.0 + SIDEWALK_W) if db > 2 else (-0.3 if db == 2 else 0.0)
		if ta + tb >= L - 0.5:
			continue
		var span := L - tb - ta
		var steps := maxi(1, ceili(span / STEP))
		for side in [-1, 1]:
			var run_start := -1.0
			var run_ramp := false
			for k in steps + 1:
				var t0 := ta + span * k / steps
				var keep := false
				if k < steps:
					var tm := ta + span * (k + 0.5) / steps
					var c := a + d * tm
					keep = not on_road.call(c + n * side * (w / 2.0 + 0.3), i) and not on_road.call(c + n * side * (w / 2.0 + SIDEWALK_W - 0.2), i)
				if keep and run_start < 0.0:
					run_start = t0
					run_ramp = k > 0 or da > 2
				elif not keep and run_start >= 0.0:
					var end_ramp := k < steps or db > 2
					runs.append({"seg": i, "side": side, "a": a + d * run_start, "b": a + d * t0, "d": d, "n": n, "w": w,
						"ramp_a": run_ramp, "ramp_b": end_ramp})
					if run_start <= ta + 0.01 and da > 2:
						reach[Vector3i(i, 0, side)] = runs.size() - 1
					if k == steps and db > 2:
						reach[Vector3i(i, 1, side)] = runs.size() - 1
					run_start = -1.0
	# Coins : entre deux rues voisines autour d'un carrefour
	var corners: Array = []
	for nd in incident:
		if int(degree[nd]) < 3:
			continue
		var c0: Vector2 = nodes[nd]
		var arms: Array = []
		for i in incident[nd]:
			var s: Array = segs[i]
			var end := 0 if s[0] == nd else 1
			var other: Vector2 = nodes[s[1 - end]]
			var u := (other - c0).normalized()
			arms.append({"seg": i, "end": end, "u": u, "ang": u.angle(), "w": float(s[2]), "walk": s[3] and s[5]})
		if arms.size() < 2:
			continue
		arms.sort_custom(func(x, y): return x["ang"] < y["ang"])
		var t := float(node_w[nd]) / 2.0 + SIDEWALK_W
		for k in arms.size():
			var A: Dictionary = arms[k]
			var B: Dictionary = arms[(k + 1) % arms.size()]
			var g := fposmod(float(B["ang"]) - float(A["ang"]), TAU)
			if not A["walk"] or not B["walk"] or g < deg_to_rad(55.0) or g > deg_to_rad(195.0):
				continue
			var straight := g > deg_to_rad(165.0) ## côté plat d'un carrefour en T : le trottoir continue tout droit
			var ua: Vector2 = A["u"]
			var ub: Vector2 = B["u"]
			var na := Vector2(-ua.y, ua.x) # côté de A tourné vers B (B est dans le sens trigonométrique)
			var nb := Vector2(ub.y, -ub.x) # côté de B tourné vers A
			# Côté du trottoir dans le repère du tronçon (n = perpendiculaire gauche de a → b)
			var sa_seg: Array = segs[A["seg"]]
			var sb_seg: Array = segs[B["seg"]]
			var side_a := _side_of(nodes, sa_seg, A["end"], na)
			var side_b := _side_of(nodes, sb_seg, B["end"], nb)
			if not reach.has(Vector3i(A["seg"], A["end"], side_a)) or not reach.has(Vector3i(B["seg"], B["end"], side_b)):
				continue
			var wa: float = A["w"] / 2.0
			var wb: float = B["w"] / 2.0
			var a_in := c0 + ua * t + na * wa
			var a_out := c0 + ua * t + na * (wa + SIDEWALK_W)
			var b_in := c0 + ub * t + nb * wb
			var b_out := c0 + ub * t + nb * (wb + SIDEWALK_W)
			var ci = (a_in + b_in) / 2.0
			var co = (a_out + b_out) / 2.0
			if not straight:
				ci = Geometry2D.line_intersects_line(c0 + na * wa, ua, c0 + nb * wb, ub)
				co = Geometry2D.line_intersects_line(c0 + na * (wa + SIDEWALK_W), ua, c0 + nb * (wb + SIDEWALK_W), ub)
				if ci == null or co == null:
					continue
				# Le coin ne dépasse pas le bout des trottoirs
				if (ci - c0).dot(ua) > t + 0.05 or (ci - c0).dot(ub) > t + 0.05:
					continue
			var mid: Vector2 = (ci + co) / 2.0
			if on_road.call(mid, A["seg"]) and on_road.call(mid, B["seg"]):
				continue
			runs[reach[Vector3i(A["seg"], A["end"], side_a)]]["ramp_a" if A["end"] == 0 else "ramp_b"] = false
			runs[reach[Vector3i(B["seg"], B["end"], side_b)]]["ramp_a" if B["end"] == 0 else "ramp_b"] = false
			corners.append({"poly": PackedVector2Array([a_in, ci, b_in, b_out, co, a_out]),
				"inner": PackedVector2Array([a_in, ci, b_in]), "dir": ua if straight else (ua + ub).normalized()})
	return {"runs": runs, "corners": corners}


## Côté (-1 ou 1) du tronçon qui regarde dans la direction `towards` depuis son bout `end`
static func _side_of(nodes: PackedVector2Array, s: Array, end: int, towards: Vector2) -> int:
	var d: Vector2 = (nodes[s[1]] - nodes[s[0]]).normalized()
	var n := Vector2(-d.y, d.x)
	return 1 if n.dot(towards) > 0.0 else -1


## Enregistré par le baker (world/dakar/sidewalks.res) : le jeu n'a pas à refaire le calcul au lancement
static func save(pl: Dictionary, path: String) -> void:
	var runs := PackedFloat32Array()
	for r in pl["runs"]:
		runs.append_array([r["a"].x, r["a"].y, r["b"].x, r["b"].y, r["d"].x, r["d"].y, r["n"].x, r["n"].y, r["w"], r["side"]])
	var corners := PackedFloat32Array()
	for c in pl["corners"]:
		for p in c["poly"]:
			corners.append_array([p.x, p.y])
	var res := Resource.new()
	res.set_meta("runs", runs)
	res.set_meta("corners", corners)
	ResourceSaver.save(res, path, ResourceSaver.FLAG_COMPRESS)


static func load_saved(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {}
	var res: Resource = load(path)
	var runs: Array = []
	var f: PackedFloat32Array = res.get_meta("runs")
	for i in range(0, f.size(), 10):
		runs.append({"a": Vector2(f[i], f[i + 1]), "b": Vector2(f[i + 2], f[i + 3]), "d": Vector2(f[i + 4], f[i + 5]),
			"n": Vector2(f[i + 6], f[i + 7]), "w": f[i + 8], "side": int(f[i + 9])})
	var corners: Array = []
	var g: PackedFloat32Array = res.get_meta("corners")
	for i in range(0, g.size(), 12):
		var poly := PackedVector2Array()
		for k in 6:
			poly.append(Vector2(g[i + k * 2], g[i + k * 2 + 1]))
		corners.append({"poly": poly})
	return {"runs": runs, "corners": corners}
