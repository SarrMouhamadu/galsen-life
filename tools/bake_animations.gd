extends SceneTree
## Outil hors-jeu : adapte les animations en capture de mouvement de la Universal Animation Library
## (Quaternius, CC0) aux personnages MakeHuman du jeu (squelette « game_engine »).
##
##   godot --headless --path . -s res://tools/bake_animations.gd
##
## Pour chaque os, on mesure la rotation de l'animation par rapport à la pose de repos du squelette
## source, on corrige la différence de pose de repos (T-pose / A-pose, orientation, taille), puis on
## l'applique au squelette cible. Résultat : characters/anims/<personnage>.res (AnimationLibrary).

const SRC := "res://characters/anims/source/ual.glb"
const OUT := "res://characters/anims/"
const MODELS := ["heros", "homme_ville", "homme_age", "homme_afro", "homme_tunique",
	"femme_robe", "femme_jupe", "femme_maman", "femme_ville", "soldat", "lutteur1", "lutteur2", "jayden_carter",
	"footballeur1", "footballeur2", "footballeur3", "footballeuse", "gardien"]
## clip source → nom dans le jeu
const CLIPS := {"Idle_Loop": "idle", "Walk_Loop": "walk", "Jog_Fwd_Loop": "jog", "Sprint_Loop": "sprint",
	"Idle_Talking_Loop": "talk", "Sitting_Idle_Loop": "sit", "Dance_Loop": "dance", "Driving_Loop": "drive",
	"Punch_Jab": "punch", "Push_Loop": "push", "Hit_Chest": "hit", "Death01": "fall", "Jump_Start": "jump",
	"Crouch_Idle_Loop": "crouch"}
const LOOPING := ["idle", "walk", "jog", "sprint", "talk", "sit", "dance", "drive", "push", "crouch"]
## Émotes fabriquées à partir de l'attente (la bibliothèque n'a pas ces gestes) : seuls les bras changent
const GESTURES := ["wave", "phone", "clap", "arms_crossed", "dua"]
const FPS := 30.0
## Postures debout : la source garde les genoux fléchis et les fesses en arrière (posture de combat).
## On redresse jambes et bassin vers la position de repos (0 = inchangé, 1 = debout bien droit).
const STRAIGHTEN := {"idle": 0.8, "talk": 0.8}
const LEGS := ["pelvis", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
## Port du haut du corps : la source a le dos voûté, les épaules enroulées vers l'avant et la tête projetée.
## On ramène colonne, nuque et clavicules vers la posture naturelle du squelette cible (dos droit,
## épaules ouvertes), plus fort à l'arrêt qu'en courant (où un buste penché est normal).
const POSTURE := {"idle": 0.8, "talk": 0.75, "walk": 0.6, "jog": 0.35, "sprint": 0.15, "sit": 0.4, "drive": 0.5, "dance": 0.3}
const UPPER := ["spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r"]
## Mains : poings serrés dans la source ; à l'arrêt et en marchant, doigts détendus (légèrement pliés)
## Bras : la source les tient écartés du corps (raides) ; on les rapproche des flancs
const ARMS_IN := {"idle": 0.6, "talk": 0.45, "walk": 0.5, "jog": 0.3, "sit": 0.3}
const RELAX_HANDS := {"idle": 0.6, "talk": 0.5, "walk": 0.55, "sit": 0.5}
## Allures : après l'adaptation, le pied d'appui est posé au sol (la source court « sur coussin d'air », pieds
## 4 à 10 cm au-dessus du sol et talon levé), puis on mesure la vitesse à laquelle il recule sous le corps :
## métadonnée « ground_speed » (m/s), utilisée par le jeu pour caler la cadence sur la vitesse réelle (sans glisser).
## Valeur : part du pied remise à plat pendant l'appui (un sprinteur reste sur l'avant du pied).
const GAITS := {"walk": 0.0, "jog": 0.8, "sprint": 0.45}

## os source → os cible
var MAP := {
	"DEF-hips": "pelvis", "DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02", "DEF-spine.003": "spine_03",
	"DEF-neck": "neck_01", "DEF-head": "head",
}
## Os de la colonne : seul le mouvement est transféré, pas la direction de repos
const SPINE := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"]
## os → os qui donne sa direction (sa « suite »)
var NEXT := {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "head"}


func _init_map() -> void:
	for s in ["L", "R"]:
		var t: String = s.to_lower()
		MAP["DEF-shoulder." + s] = "clavicle_" + t
		MAP["DEF-upper_arm." + s] = "upperarm_" + t
		MAP["DEF-forearm." + s] = "lowerarm_" + t
		MAP["DEF-hand." + s] = "hand_" + t
		MAP["DEF-thigh." + s] = "thigh_" + t
		MAP["DEF-shin." + s] = "calf_" + t
		MAP["DEF-foot." + s] = "foot_" + t
		MAP["DEF-toe." + s] = "ball_" + t
		NEXT["clavicle_" + t] = "upperarm_" + t
		NEXT["upperarm_" + t] = "lowerarm_" + t
		NEXT["lowerarm_" + t] = "hand_" + t
		NEXT["hand_" + t] = "middle_01_" + t
		NEXT["thigh_" + t] = "calf_" + t
		NEXT["calf_" + t] = "foot_" + t
		NEXT["foot_" + t] = "ball_" + t
		for f in [["index", "f_index"], ["middle", "f_middle"], ["ring", "f_ring"], ["pinky", "f_pinky"], ["thumb", "thumb"]]:
			for k in [1, 2, 3]:
				MAP["DEF-%s.0%d.%s" % [f[1], k, s]] = "%s_0%d_%s" % [f[0], k, t]
				if k < 3:
					NEXT["%s_0%d_%s" % [f[0], k, t]] = "%s_0%d_%s" % [f[0], k + 1, t]


func _initialize() -> void:
	_init_map()
	var src_root: Node = (load(SRC) as PackedScene).instantiate()
	var src_skel: Skeleton3D = src_root.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = src_root.find_children("*", "AnimationPlayer", true, false)[0]
	var src_path := String(player.get_node(player.root_node).get_path_to(src_skel))
	print("source : %d os, %d animations, chemin %s" % [src_skel.get_bone_count(), player.get_animation_list().size(), src_path])
	# -- --only=nom (plusieurs fois possible) : ne refaire que ces personnages
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only.append(arg.trim_prefix("--only="))
	for model in MODELS:
		if not only.is_empty() and not model in only:
			continue
		var tgt_root: Node = (load("res://characters/realistic/%s.glb" % model) as PackedScene).instantiate()
		var tgt_skel: Skeleton3D = tgt_root.find_children("*", "Skeleton3D", true, false)[0]
		var tgt_path := String(tgt_root.get_path_to(tgt_skel))
		var lib := AnimationLibrary.new()
		for clip in CLIPS:
			# À l'import, Godot retire le suffixe « _Loop » des animations en boucle
			var src_name: String = clip if player.has_animation(clip) else clip.trim_suffix("_Loop")
			if not player.has_animation(src_name):
				print("  clip absent : ", clip)
				continue
			var cn: String = CLIPS[clip]
			var anim := _retarget(player.get_animation(src_name), src_skel, src_path, tgt_skel, tgt_path, STRAIGHTEN.get(cn, 0.0), POSTURE.get(cn, 0.0), RELAX_HANDS.get(cn, 0.0), ARMS_IN.get(cn, 0.0))
			anim.loop_mode = Animation.LOOP_LINEAR if CLIPS[clip] in LOOPING else Animation.LOOP_NONE
			if GAITS.has(cn):
				_ground_feet(anim, tgt_skel, tgt_path, cn)
			lib.add_animation(CLIPS[clip], anim)
		if lib.has_animation("idle"):
			for g in GESTURES:
				lib.add_animation(g, _gesture(lib.get_animation("idle"), g, tgt_skel, tgt_path))
		var err := ResourceSaver.save(lib, OUT + model + ".res", ResourceSaver.FLAG_COMPRESS)
		print("%s : %d animations (%s)" % [model, lib.get_animation_list().size(), "ok" if err == OK else "ERREUR"])
		tgt_root.free()
	src_root.free()
	quit()


func _bone_dir(skel: Skeleton3D, b: int, next_name: String) -> Vector3:
	var n := skel.find_bone(next_name)
	if n == -1:
		return Vector3.ZERO
	return (skel.get_bone_global_rest(n).origin - skel.get_bone_global_rest(b).origin).normalized()


func _retarget(src: Animation, ss: Skeleton3D, src_path: String, ts: Skeleton3D, tgt_path: String, straighten := 0.0, posture := 0.0, relax := 0.0, arms_in := 0.0) -> Animation:
	var ns := ss.get_bone_count()
	var nt := ts.get_bone_count()
	# Orientation : aligner l'axe gauche-droite des hanches des deux squelettes
	var lr_s := ss.get_bone_global_rest(ss.find_bone("DEF-thigh.L")).origin - ss.get_bone_global_rest(ss.find_bone("DEF-thigh.R")).origin
	var lr_t := ts.get_bone_global_rest(ts.find_bone("thigh_l")).origin - ts.get_bone_global_rest(ts.find_bone("thigh_r")).origin
	var ang := atan2(lr_s.x, lr_s.z) - atan2(lr_t.x, lr_t.z)
	var F := Basis(Vector3.UP, -ang)
	var Fi := F.inverse()
	var lat := lr_t.normalized() ## vers la gauche du personnage cible
	var arm_dir := {} ## os du bras → [direction de repos vers l'avant-bras, côté (+1 gauche, -1 droite)]
	for side in [["l", 1.0], ["r", -1.0]]:
		var ub := ts.find_bone("upperarm_" + side[0])
		var lb := ts.find_bone("lowerarm_" + side[0])
		if ub != -1 and lb != -1:
			arm_dir[ub] = [(ts.get_bone_global_rest(lb).origin - ts.get_bone_global_rest(ub).origin).normalized(), side[1]]
	var hs := ss.get_bone_global_rest(ss.find_bone("DEF-hips")).origin.y
	var ht := ts.get_bone_global_rest(ts.find_bone("pelvis")).origin.y
	var scale := ht / maxf(hs, 0.01)
	# Correspondances et correction de la pose de repos (C : direction source → direction cible)
	var tgt_of := {} ## os cible → os source
	var C := {}
	for sname in MAP:
		var sb := ss.find_bone(sname)
		var tb := ts.find_bone(MAP[sname])
		if sb == -1 or tb == -1:
			continue
		tgt_of[tb] = sb
	var order := _order(ts)
	for tb in order:
		var tname := ts.get_bone_name(tb)
		var c := Basis()
		if tname in SPINE:
			# Colonne : on garde la cambrure naturelle du squelette cible (bassin incliné vers l'arrière
			# chez MakeHuman) et on ne transfère que le mouvement. Copier la direction des os sources
			# faisait basculer tout le buste vers l'avant (poitrine en avant, genoux pliés).
			c = Basis()
		elif tgt_of.has(tb) and NEXT.has(tname):
			var sb: int = tgt_of[tb]
			var snext := ""
			for k in MAP:
				if MAP[k] == NEXT[tname]:
					snext = k
			var ds := F * _bone_dir(ss, sb, snext)
			var dt := _bone_dir(ts, tb, NEXT[tname])
			if ds.length() > 0.5 and dt.length() > 0.5:
				c = Basis(Quaternion(ds, dt))
		elif ts.get_bone_parent(tb) != -1 and C.has(ts.get_bone_parent(tb)):
			c = C[ts.get_bone_parent(tb)]
		C[tb] = c
	# Pistes de l'animation source
	var rot_track := {}
	var pos_hips := src.find_track(NodePath(src_path + ":DEF-hips"), Animation.TYPE_POSITION_3D)
	for b in ns:
		rot_track[b] = src.find_track(NodePath(src_path + ":" + ss.get_bone_name(b)), Animation.TYPE_ROTATION_3D)
	var s_order := _order(ss)
	var s_rest_g := []
	s_rest_g.resize(ns)
	for b in ns:
		s_rest_g[b] = ss.get_bone_global_rest(b).basis.orthonormalized()
	var t_rest_g := []
	t_rest_g.resize(nt)
	for b in nt:
		t_rest_g[b] = ts.get_bone_global_rest(b).basis.orthonormalized()
	var out := Animation.new()
	out.length = src.length
	var tracks := {}
	for tb in tgt_of:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath(tgt_path + ":" + ts.get_bone_name(tb)))
		tracks[tb] = tr
	var pelvis := ts.find_bone("pelvis")
	var ptr := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(ptr, NodePath(tgt_path + ":pelvis"))
	var hips_rest_pos := ss.get_bone_rest(ss.find_bone("DEF-hips")).origin
	var pelvis_rest_pos := ts.get_bone_rest(pelvis).origin
	var steps := maxi(1, int(ceil(src.length * FPS)))
	for k in steps + 1:
		var t := minf(src.length, k / FPS)
		# Pose globale source
		var sg := []
		sg.resize(ns)
		for b in s_order:
			var local := ss.get_bone_rest(b).basis.get_rotation_quaternion()
			if rot_track[b] != -1:
				local = src.rotation_track_interpolate(rot_track[b], t)
			var p := ss.get_bone_parent(b)
			sg[b] = (sg[p] * Basis(local)) if p != -1 else Basis(local)
		# Pose globale cible
		var tg := []
		tg.resize(nt)
		for tb in order:
			var p := ts.get_bone_parent(tb)
			var g: Basis
			if tgt_of.has(tb):
				var sb: int = tgt_of[tb]
				var D: Basis = sg[sb] * (s_rest_g[sb] as Basis).inverse()
				var Dp := F * D * Fi
				# Au repos source (D = I), l'os cible prend la direction de l'os source ; puis le mouvement s'applique.
				g = Dp * (C[tb] as Basis).inverse() * t_rest_g[tb]
			elif p != -1:
				g = tg[p] * (t_rest_g[p] as Basis).inverse() * t_rest_g[tb]
			else:
				g = t_rest_g[tb]
			if arms_in > 0.0 and arm_dir.has(tb):
				# Rapproche le bras du flanc : on réduit seulement l'écart vers l'extérieur
				var dr: Vector3 = arm_dir[tb][0]
				var sd: float = arm_dir[tb][1]
				var dcur: Vector3 = (g * (t_rest_g[tb] as Basis).inverse() * dr).normalized()
				var outward := dcur.dot(lat) * sd
				var dnew := dcur
				if outward > 0.03:
					dnew -= lat * sd * (outward - 0.03) * arms_in
				# Et les bras qui pendent devant le ventre reviennent le long du corps
				var fwd := lat.cross(Vector3.UP)
				var ahead := dnew.dot(fwd)
				if ahead > 0.04:
					dnew -= fwd * (ahead - 0.04) * arms_in
				dnew = dnew.normalized()
				if dnew.dot(dcur) < 0.99999:
					g = Basis(Quaternion(dcur, dnew)) * g
			tg[tb] = g
			if tracks.has(tb):
				var local_b: Basis = ((tg[p] as Basis).inverse() * g) if p != -1 else g
				var q := local_b.get_rotation_quaternion()
				var bn := ts.get_bone_name(tb)
				var fix := 0.0
				if bn in LEGS:
					fix = straighten
				elif bn in UPPER:
					fix = posture
				elif relax > 0.0 and _is_finger(bn):
					fix = relax
				if fix > 0.0:
					q = q.slerp(ts.get_bone_rest(tb).basis.get_rotation_quaternion(), fix)
					# La pose globale suit la correction pour que les os enfants restent cohérents
					var lb := Basis(q)
					tg[tb] = (tg[p] as Basis) * lb if p != -1 else lb
				out.rotation_track_insert_key(tracks[tb], t, q)
		# Petit rebond et balancement du bassin (translation des hanches, mise à l'échelle)
		var delta := Vector3.ZERO
		if pos_hips != -1:
			delta = F * (src.position_track_interpolate(pos_hips, t) - hips_rest_pos) * scale
			delta.x = clampf(delta.x, -0.15, 0.15)
			delta.z = clampf(delta.z, -0.15, 0.15)
			# Jambes redressées : le bassin ne descend plus autant (sinon les pieds passent sous le sol)
			delta *= 1.0 - straighten
		out.position_track_insert_key(ptr, t, pelvis_rest_pos + delta)
	return out


## Geste des bras posé sur l'animation d'attente (le reste du corps respire normalement).
## Pour chaque bras on donne la direction voulue du bras et de l'avant-bras dans le repère du personnage
## (av = devant, h = haut, ext = vers l'extérieur de ce côté) ; p = phase 0..1 dans la boucle.
func _gesture(idle: Animation, g: String, ts: Skeleton3D, tgt_path: String) -> Animation:
	var out: Animation = idle.duplicate(true)
	var L := (ts.get_bone_global_rest(ts.find_bone("thigh_l")).origin - ts.get_bone_global_rest(ts.find_bone("thigh_r")).origin).normalized()
	var U := Vector3.UP
	var F := L.cross(U) ## devant le personnage
	var order := _order(ts)
	var nt := ts.get_bone_count()
	var rest_g := []
	rest_g.resize(nt)
	for b in nt:
		rest_g[b] = ts.get_bone_global_rest(b).basis.orthonormalized()
	var track := {}
	for b in nt:
		track[b] = out.find_track(NodePath(tgt_path + ":" + ts.get_bone_name(b)), Animation.TYPE_ROTATION_3D)
	var arms := []
	for side in [["l", 1.0], ["r", -1.0]]:
		var ub := ts.find_bone("upperarm_" + side[0])
		var lb := ts.find_bone("lowerarm_" + side[0])
		var hb := ts.find_bone("hand_" + side[0])
		if ub == -1 or lb == -1 or hb == -1 or track[ub] == -1 or track[lb] == -1:
			continue
		# Direction de chaque os dans son propre repère (vers l'os suivant)
		var du: Vector3 = (rest_g[ub] as Basis).inverse() * (ts.get_bone_global_rest(lb).origin - ts.get_bone_global_rest(ub).origin).normalized()
		var dl: Vector3 = (rest_g[lb] as Basis).inverse() * (ts.get_bone_global_rest(hb).origin - ts.get_bone_global_rest(lb).origin).normalized()
		arms.append([ub, lb, side[1], du, dl])
	# Nombre entier d'oscillations dans la boucle (pas de saut au raccord)
	var cyc := func(per_s: float) -> float: return maxf(1.0, round(idle.length * per_s))
	for k in out.track_get_key_count(track[arms[0][0]]):
		var t := out.track_get_key_time(track[arms[0][0]], k)
		var p := t / maxf(idle.length, 0.001)
		# Pose globale d'attente à cet instant
		var gl := []
		gl.resize(nt)
		for b in order:
			var par := ts.get_bone_parent(b)
			var lq: Quaternion = ts.get_bone_rest(b).basis.get_rotation_quaternion()
			if track[b] != -1:
				lq = out.rotation_track_interpolate(track[b], t)
			gl[b] = (gl[par] * Basis(lq)) if par != -1 else Basis(lq)
		for arm in arms:
			var sd: float = arm[2]
			var ext := L * sd
			var want = _gesture_dirs(g, sd, p, cyc, F, U, ext)
			if want == null:
				continue
			var ub: int = arm[0]
			var lb: int = arm[1]
			var par_u := ts.get_bone_parent(ub)
			var gu: Basis = gl[ub]
			var cur_u: Vector3 = (gu * (arm[3] as Vector3)).normalized()
			var gu2 := Basis(Quaternion(cur_u, (want[0] as Vector3).normalized())) * gu
			var gl_low: Basis = gu2 * ((gu.inverse() * (gl[lb] as Basis)))
			var cur_l: Vector3 = (gl_low * (arm[4] as Vector3)).normalized()
			var gl2 := Basis(Quaternion(cur_l, (want[1] as Vector3).normalized())) * gl_low
			var lu: Basis = ((gl[par_u] as Basis).inverse() * gu2) if par_u != -1 else gu2
			out.track_set_key_value(track[ub], k, lu.get_rotation_quaternion())
			out.track_set_key_value(track[lb], k, (gu2.inverse() * gl2).get_rotation_quaternion())
	out.loop_mode = Animation.LOOP_LINEAR
	return out


## [direction du bras, direction de l'avant-bras] voulues, ou null pour laisser ce bras au repos
func _gesture_dirs(g: String, sd: float, p: float, cyc: Callable, F: Vector3, U: Vector3, ext: Vector3):
	var right := sd < 0.0
	match g:
		"wave": # salut de la main droite, avant-bras qui se balance
			if not right:
				return null
			var sw := sin(p * TAU * cyc.call(1.6)) * 0.45
			return [ext * 0.75 + U * 0.55 + F * 0.15, U + ext * sw + F * 0.1]
		"phone": # main droite à l'oreille
			if not right:
				return null
			return [-U * 0.3 + F * 0.3 + ext * 0.75, U * 1.0 - ext * 0.42 + F * 0.05]
		"clap": # applaudit devant la poitrine
			var o := 0.5 + 0.5 * sin(p * TAU * cyc.call(2.4))
			return [-U * 0.8 + F * 0.45 + ext * 0.2, F * 0.45 + U * 0.5 - ext * (0.45 + 0.4 * o)]
		"arms_crossed": # bras croisés sur la poitrine
			var h := 0.08 if right else 0.0
			return [-U * 0.9 + F * 0.3 + ext * 0.12, -ext * 1.0 + F * 0.3 + U * (0.12 + h)]
		"dua": # mains levées devant soi, paumes vers le ciel (prière)
			return [-U * 0.9 + F * 0.3 + ext * 0.2, U * 0.6 + F * 0.75 + ext * 0.05]
	return null


## Pose globale (repère du squelette) de chaque os à la clé k : rotations des pistes, position du bassin
func _fk(anim: Animation, ts: Skeleton3D, order: Array, tr: Dictionary, ptr: int, pelvis: int, k: int) -> Array:
	var g := []
	g.resize(ts.get_bone_count())
	for b in order:
		var rest := ts.get_bone_rest(b)
		var local := Transform3D(rest.basis.orthonormalized(), rest.origin)
		if tr.has(b):
			local.basis = Basis(anim.track_get_key_value(tr[b], k) as Quaternion)
		if b == pelvis:
			local.origin = anim.track_get_key_value(ptr, k)
		var p := ts.get_bone_parent(b)
		g[b] = (g[p] as Transform3D) * local if p != -1 else local
	return g


## Hauteur de la semelle (0 : posée au sol) : la plus basse de l'avant du pied et du talon,
## comparées à leur hauteur debout au repos
func _sole(g: Array, foot: int, ball: int, rest_foot: float, rest_ball: float) -> float:
	return minf((g[ball] as Transform3D).origin.y - rest_ball, (g[foot] as Transform3D).origin.y - rest_foot)


## Pose le pied d'appui au sol : bassin abaissé (constant sur la boucle), puis jambe pliée par IK à deux os
## pour que chaque pied d'appui touche le sol sans s'enfoncer, et pied remis en partie à plat.
func _ground_feet(anim: Animation, ts: Skeleton3D, tgt_path: String, clip: String) -> void:
	var order := _order(ts)
	var tr := {}
	for b in ts.get_bone_count():
		var t := anim.find_track(NodePath(tgt_path + ":" + ts.get_bone_name(b)), Animation.TYPE_ROTATION_3D)
		if t != -1:
			tr[b] = t
	var ptr := anim.find_track(NodePath(tgt_path + ":pelvis"), Animation.TYPE_POSITION_3D)
	var pelvis := ts.find_bone("pelvis")
	if ptr == -1 or pelvis == -1:
		return
	var keys := anim.track_get_key_count(ptr)
	var legs := []
	for side in ["l", "r"]:
		var leg := [ts.find_bone("thigh_" + side), ts.find_bone("calf_" + side), ts.find_bone("foot_" + side), ts.find_bone("ball_" + side)]
		if -1 in leg:
			return
		for b in leg.slice(0, 3):
			if not tr.has(b):
				return
		legs.append(leg)
	var rest_foot: float = ts.get_bone_global_rest(legs[0][2]).origin.y
	var rest_ball: float = ts.get_bone_global_rest(legs[0][3]).origin.y
	var flatten: float = GAITS[clip]
	# 1. Bassin : le pied d'appui moyen descend jusqu'au sol
	var lows := []
	for k in keys:
		var g := _fk(anim, ts, order, tr, ptr, pelvis, k)
		lows.append(minf(_sole(g, legs[0][2], legs[0][3], rest_foot, rest_ball), _sole(g, legs[1][2], legs[1][3], rest_foot, rest_ball)))
	var sorted := lows.duplicate()
	sorted.sort()
	var drop: float = maxf(0.0, sorted[int(sorted.size() * 0.2)])
	for k in keys:
		anim.track_set_key_value(ptr, k, (anim.track_get_key_value(ptr, k) as Vector3) - Vector3(0, drop, 0))
	# 2. Chaque jambe : pied d'appui posé, jamais sous le sol
	for k in keys:
		var g := _fk(anim, ts, order, tr, ptr, pelvis, k)
		for leg in legs:
			var th: int = leg[0]
			var ca: int = leg[1]
			var fo: int = leg[2]
			var ba: int = leg[3]
			var sole := _sole(g, fo, ba, rest_foot, rest_ball)
			var w := 1.0 - smoothstep(0.08, 0.16, sole) # 1 : en appui, 0 : en l'air
			if w <= 0.0 and sole >= 0.0:
				continue
			var fg: Transform3D = g[fo]
			# Pied remis à plat autour de la cheville (le talon redescend), selon la part voulue
			var toe: Vector3 = (g[ba] as Transform3D).origin - fg.origin
			var rest_toe := ts.get_bone_global_rest(ba).origin - ts.get_bone_global_rest(fo).origin
			var foot_basis := fg.basis
			if flatten > 0.0 and w > 0.0 and toe.length() > 0.01:
				var flat_toe := Vector3(toe.x, 0, toe.z).normalized() * Vector3(rest_toe.x, 0, rest_toe.z).length() + Vector3(0, rest_toe.y, 0)
				var q := Quaternion(toe.normalized(), flat_toe.normalized())
				foot_basis = Basis(Quaternion.IDENTITY.slerp(q, flatten * w)) * fg.basis
			var new_toe := foot_basis * (fg.basis.inverse() * toe)
			# Semelle après remise à plat, puis cheville déplacée pour la poser au sol
			var s2 := minf(fg.origin.y + new_toe.y - rest_ball, fg.origin.y - rest_foot)
			var dy := -s2 * w if s2 > 0.0 else -s2
			var H: Vector3 = (g[th] as Transform3D).origin
			var K: Vector3 = (g[ca] as Transform3D).origin
			var A: Vector3 = fg.origin
			var At := A + Vector3(0, dy, 0)
			var a := K.distance_to(H)
			var b := A.distance_to(K)
			var d := clampf(At.distance_to(H), absf(a - b) + 0.001, a + b - 0.001)
			var n := (K - H).cross(A - H)
			if n.length() < 0.00001:
				continue
			n = n.normalized()
			var ang := acos(clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0))
			var dir := (At - H).normalized()
			var K2 := H + dir.rotated(n, ang) * a
			var K3 := H + dir.rotated(n, -ang) * a
			var Kn := K2 if K2.distance_to(K) < K3.distance_to(K) else K3
			var R1 := Basis(Quaternion((K - H).normalized(), (Kn - H).normalized()))
			var thigh_g: Basis = R1 * (g[th] as Transform3D).basis
			var calf_dir := (R1 * (A - K)).normalized()
			var R2 := Basis(Quaternion(calf_dir, (At - Kn).normalized()))
			var calf_g: Basis = R2 * R1 * (g[ca] as Transform3D).basis
			var parent_g: Basis = (g[ts.get_bone_parent(th)] as Transform3D).basis
			anim.track_set_key_value(tr[th], k, (parent_g.inverse() * thigh_g).orthonormalized().get_rotation_quaternion())
			anim.track_set_key_value(tr[ca], k, (thigh_g.inverse() * calf_g).orthonormalized().get_rotation_quaternion())
			anim.track_set_key_value(tr[fo], k, (calf_g.inverse() * foot_basis).orthonormalized().get_rotation_quaternion())
	# 3. Vitesse du pied d'appui : celle du corps
	var dt := anim.length / maxf(1.0, keys - 1.0)
	var dist := 0.0
	var time := 0.0
	var prev := _fk(anim, ts, order, tr, ptr, pelvis, 0)
	for k in range(1, keys):
		var g := _fk(anim, ts, order, tr, ptr, pelvis, k)
		for leg in legs:
			if _sole(g, leg[2], leg[3], rest_foot, rest_ball) < 0.02 and _sole(prev, leg[2], leg[3], rest_foot, rest_ball) < 0.02:
				var v: Vector3 = (g[leg[3]] as Transform3D).origin - (prev[leg[3]] as Transform3D).origin
				dist += Vector2(v.x, v.z).length()
				time += dt
		prev = g
	var gs := dist / time if time > 0.0 else 0.0
	anim.set_meta("ground_speed", gs)
	print("  %s : bassin abaissé de %.1f cm, vitesse au sol %.2f m/s (%.2f s d'appui)" % [clip, drop * 100.0, gs, time])


func _is_finger(bn: String) -> bool:
	for f in ["index_", "middle_", "ring_", "pinky_", "thumb_"]:
		if bn.begins_with(f):
			return true
	return false


## Ordre parent → enfant
func _order(skel: Skeleton3D) -> Array:
	var n := skel.get_bone_count()
	var done := {}
	var order: Array = []
	while order.size() < n:
		for i in n:
			if done.has(i):
				continue
			var p := skel.get_bone_parent(i)
			if p == -1 or done.has(p):
				done[i] = true
				order.append(i)
	return order
