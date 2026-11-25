extends SceneTree
## Outil : mesure la vitesse « naturelle » des allures (pied d'appui qui recule) pour caler la cadence en jeu.
##   godot --headless --path . -s res://tools/measure_gait.gd -- heros walk walk_formal jog sprint

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var model: String = args[0] if args.size() > 0 else "heros"
	var clips: Array = args.slice(1) if args.size() > 1 else ["walk", "walk_formal", "jog", "sprint"]
	var root: Node = (load("res://characters/realistic/%s.glb" % model) as PackedScene).instantiate()
	get_root().add_child(root)
	var skel: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ap := AnimationPlayer.new()
	root.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", load("res://characters/anims/%s.res" % model))
	var fl := skel.find_bone("foot_l")
	var pel := skel.find_bone("pelvis")
	for clip in clips:
		ap.play(clip)
		var anim := ap.get_animation(clip)
		var L := anim.length
		var n := 60
		var zs: Array = []
		for k in n:
			ap.seek(L * k / n, true)
			var f := skel.get_bone_global_pose(fl).origin - skel.get_bone_global_pose(pel).origin
			zs.append(f.z)
		# Phase d'appui : le pied recule ; vitesse = pente moyenne quand il recule
		var back := 0.0
		var t_back := 0.0
		for k in n:
			var dz: float = zs[(k + 1) % n] - zs[k]
			if dz < 0.0:
				back += -dz
				t_back += L / n
		print("GAIT %s %s : durée %.2f s, amplitude %.2f m, vitesse d'appui %.2f m/s" % [model, clip, L, zs.max() - zs.min(), back / maxf(t_back, 0.001)])
	quit()
