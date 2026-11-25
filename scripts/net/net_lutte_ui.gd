extends Node
## Lutte en ligne, côté joueur : organiser une journée entre joueurs, appel au cercle,
## résultats, cercle de sable posé au stade pendant une journée de joueurs (voir net_lutte.gd).

const Mk = preload("res://scripts/util/mk.gd")

var main
var _rings := {} ## jid → cercle de sable


func _ready() -> void:
	var L = Net.lutte
	L.journees_changed.connect(_refresh_rings)
	L.journee_called.connect(_on_called)
	L.journee_bout.connect(_on_bout)
	L.journee_ended.connect(_on_end)
	L.ecurie_list_received.connect(_on_list)


## Bureau des promoteurs : choisir le cachet puis le nombre de lutteurs, déposer la caution
func organize(venue: String, pos: Vector3) -> void:
	var L = Net.lutte
	var opts: Array = []
	for c in L.CACHETS:
		var cachet: int = c
		opts.append(["Cachet de %s par lutteur" % GameState.fcfa(cachet), _choose_size.bind(venue, pos, cachet)])
	main.hud.show_choices("Journée entre joueurs — chaque lutteur touche le cachet, le vainqueur une prime de 50 %.\nTu déposes la caution ; le serveur te rend le reste et la billetterie à la fin.", opts, func(): pass)


func _choose_size(venue: String, pos: Vector3, cachet: int) -> void:
	var L = Net.lutte
	var opts: Array = []
	for s in L.SIZES:
		var size: int = s
		opts.append(["%d lutteurs (%d combats) — caution %s" % [size, size / 2, GameState.fcfa(L.escrow_for(cachet, size))], func():
			if L.announce(venue, pos, cachet, size):
				GameState.notify.emit("Journée annoncée à tous les joueurs ! Lance-la depuis le téléphone (Lutte) quand les lutteurs sont là.")
			else:
				GameState.notify.emit("Il te faut %s de caution." % GameState.fcfa(L.escrow_for(cachet, size)))])
	main.hud.show_choices("Combien de lutteurs ?", opts, func(): pass)


func _on_called(_jid: int, pos: Vector3, side: int) -> void:
	var p = main.player
	p.leave_any_vehicle()
	p.global_position = pos + Vector3(-0.7 if side == 0 else 0.7, 0.5, 0)
	p.model.rotation.y = -PI / 2.0 if side == 0 else PI / 2.0
	GameState.notify.emit("On t'appelle au cercle ! Bàkk, puis le combat commence.")
	p.model.play_clip("dance", 0.2)


func _on_bout(jid: int, winner: String, loser: String, forfeit: bool) -> void:
	var j: Dictionary = Net.lutte.journees.get(jid, {})
	var who: String = j.get("promoter", "?")
	GameState.notify.emit("Journée de %s : %s bat %s%s" % [who, winner, loser, " par forfait" if forfeit else " !"])


func _on_end(jid: int, text: String) -> void:
	GameState.notify.emit(text)
	if _rings.has(jid):
		_rings[jid].queue_free()
		_rings.erase(jid)


func _on_list(list: Array) -> void:
	var L = Net.lutte
	var opts: Array = []
	for e in list:
		var ename: String = e[0]
		var txt := "%s — chef %s, %d membre(s), %d V – %d D" % [ename, e[1], e[2], e[3], e[4]]
		if L.my_ecurie == "":
			opts.append(["Rejoindre : " + txt, func(): L.rpc_ecurie_join.rpc_id(1, ename)])
		else:
			opts.append([txt, func(): pass])
	if opts.is_empty():
		opts.append(["Aucune écurie de joueurs pour l'instant : fonde la première !", func(): pass])
	main.hud.show_choices("Écuries de joueurs", opts, func(): pass)


## Cercle de sable au stade pendant une journée de joueurs lancée près de soi
func _refresh_rings() -> void:
	var pp: Vector3 = main.player.get_world_position()
	for jid in Net.lutte.journees:
		var j: Dictionary = Net.lutte.journees[jid]
		if j["state"] == "running" and not _rings.has(jid) and pp.distance_to(j["pos"]) < 400.0:
			var r := Node3D.new()
			main.add_child(r)
			r.global_position = j["pos"]
			Mk.cyl(r, 6.0, 6.0, 0.08, Vector3(0, 0.04, 0), Color("dcc79c"), false, 32)
			for k in 24:
				var a := k * TAU / 24.0
				var sack := Mk.box(r, Vector3(0.7, 0.3, 0.4), Vector3(cos(a) * 6.2, 0.15, sin(a) * 6.2), Color("efe6d0"))
				sack.rotation.y = -a
			_rings[jid] = r
