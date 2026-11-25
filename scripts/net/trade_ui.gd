extends Node
## Fenêtre d'échange entre joueurs (mode en ligne) : à gauche ton offre (argent liquide, objets du sac,
## véhicules), à droite celle de l'autre joueur, en direct ; « Valider » des deux côtés pour conclure.
## La logique et les vérifications sont dans scripts/net/net_trade.gd.

const MONEY_STEPS := [-5000, -1000, 1000, 5000]

var main
var _layer: CanvasLayer
var _win: Control
var _mine: VBoxContainer
var _theirs: VBoxContainer
var _status: Label
var _lock_btn: Button
var _title: Label


func _ready() -> void:
	var t = Net.trade
	t.main = main
	t.invited.connect(_on_invited)
	t.opened.connect(_on_opened)
	t.their_offer_changed.connect(func(_o): _refresh())
	t.mine_changed.connect(_refresh)
	t.locks_changed.connect(func(_m, _t): _refresh())
	t.closed.connect(_on_closed)
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)


func is_open() -> bool:
	return _win != null and is_instance_valid(_win)


func _on_invited(tid: int, from: String) -> void:
	main.hud.show_choices("%s te propose un échange" % from, [
		["Accepter et ouvrir l'échange", func(): Net.trade.accept(tid)],
	], func(): Net.trade.decline(tid))


func _on_closed(message: String) -> void:
	if is_open():
		_win.queue_free()
	_win = null
	main.hud.close_choices()
	GameState.notify.emit(message)


func _on_opened(_tid: int, other: String) -> void:
	main.hud.close_choices()
	if is_open():
		_win.queue_free()
	_win = ColorRect.new()
	_win.color = Color(0, 0, 0, 0.45)
	_win.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_win)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.add_child(cc)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.96)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	_title = _label(20, Color("fdef42"))
	_title.text = "Échange avec %s" % other
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	v.add_child(cols)
	_mine = _column(cols, "Ton offre")
	_theirs = _column(cols, "Offre de %s" % other)
	_status = _label(14, Color("caffbf"))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	_lock_btn = _button("VALIDER", func(): Net.trade.lock())
	_lock_btn.custom_minimum_size = Vector2(180, 44)
	row.add_child(_lock_btn)
	var cancel := _button("Annuler", func(): Net.trade.cancel())
	cancel.custom_minimum_size = Vector2(140, 44)
	row.add_child(cancel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.hud._touch.release_all()
	_refresh()


func _column(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	parent.add_child(box)
	var t := _label(16, Color.WHITE)
	t.text = title
	box.add_child(t)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(380, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 4)
	sc.add_child(inner)
	return inner


func _refresh() -> void:
	if not is_open():
		return
	var t = Net.trade
	for c in _mine.get_children():
		c.queue_free()
	for c in _theirs.get_children():
		c.queue_free()
	# Ton offre : argent, objets du sac, véhicules
	var money_row := HBoxContainer.new()
	var ml := _label(15, Color("7cfc9a"))
	ml.text = "Argent : %s" % GameState.fcfa(int(t.my_offer["money"]))
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money_row.add_child(ml)
	for st in MONEY_STEPS:
		var step: int = st
		var b := _button(("%+d" % (step / 1000)) + "k", func(): t.set_money(int(t.my_offer["money"]) + step))
		b.custom_minimum_size = Vector2(46, 34)
		money_row.add_child(b)
	_mine.add_child(money_row)
	var items: Array = GameState.inventory.keys()
	items.sort()
	if items.is_empty():
		_mine.add_child(_note("Ton sac est vide."))
	for it in items:
		var item: String = it
		var r := HBoxContainer.new()
		var l := _label(14, Color.WHITE)
		l.text = "%s  %d / %d" % [item, int(t.my_offer["items"].get(item, 0)), int(GameState.inventory[item])]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		r.add_child(l)
		for d in [-1, 1]:
			var delta: int = d
			var b := _button("−" if delta < 0 else "+", func(): t.add_item(item, delta))
			b.custom_minimum_size = Vector2(40, 32)
			r.add_child(b)
		_mine.add_child(r)
	for i in GameState.vehicles.size():
		var idx: int = i
		var veh: Dictionary = GameState.vehicles[idx]
		var chosen: bool = idx in t.my_offer["vehicles"]
		var ok: bool = t.vehicle_tradable(idx, main)
		var name: String = main.dealership.vehicle_name(veh)
		var b := _button(("✓ " if chosen else "") + "Véhicule : %s %s" % [name, str(veh.get("color", "")).to_lower()] + ("" if ok else " (indisponible)"), func(): t.toggle_vehicle(idx))
		b.disabled = not ok and not chosen
		b.custom_minimum_size = Vector2(0, 34)
		_mine.add_child(b)
	var H = main.housing
	for pid in GameState.home.get("owned", []):
		var prop: String = pid
		if H == null or not H.PROPERTIES.has(prop) or int(H.PROPERTIES[prop]["price"]) <= 0:
			continue
		var chosen: bool = prop in t.my_offer["properties"]
		var why: String = H.trade_block(prop)
		var pb := _button(("✓ " if chosen else "") + H.PROPERTIES[prop]["name"] + ("" if why == "" else " (%s)" % why), func(): t.toggle_property(prop))
		pb.disabled = why != "" and not chosen
		pb.custom_minimum_size = Vector2(0, 34)
		_mine.add_child(pb)
	# Offre de l'autre
	var o: Dictionary = t.their_offer
	var lines: Array = []
	if int(o.get("money", 0)) > 0:
		lines.append("Argent : %s" % GameState.fcfa(int(o["money"])))
	var oi = o.get("items", {})
	if oi is Dictionary:
		for item in oi:
			lines.append("%d × %s" % [int(oi[item]), item])
	var ov = o.get("vehicles", [])
	if ov is Array:
		for veh in ov:
			if veh is Dictionary:
				lines.append("Véhicule : %s %s (essence %d %%)" % [main.dealership.vehicle_name(veh), str(veh.get("color", "")).to_lower(), int(veh.get("fuel", 100))])
	var op = o.get("properties", [])
	if op is Array and H != null:
		for p in op:
			if p is Dictionary and H.PROPERTIES.has(str(p.get("id", ""))):
				var info: Dictionary = H.PROPERTIES[str(p["id"])]
				var bz = p.get("biz", {})
				var staff = bz.get("staff", []) if bz is Dictionary else []
				var extra: String = " — %d employé(s)" % staff.size() if H.is_commerce(str(p["id"])) and staff is Array else ""
				lines.append("%s (prix en agence %s)%s" % [info["name"], GameState.fcfa(int(info["price"])), extra])
	if lines.is_empty():
		_theirs.add_child(_note("Rien pour l'instant."))
	for line in lines:
		var l := _label(15, Color("ffd166"))
		l.text = line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_theirs.add_child(l)
	var me := "Tu as validé" if t.my_lock else "Tu n'as pas validé"
	var them := "%s a validé" % t.other_name if t.their_lock else "%s n'a pas validé" % t.other_name
	_status.text = "%s — %s. Toute modification annule les validations." % [me, them]
	_lock_btn.disabled = t.my_lock
	_lock_btn.text = "VALIDÉ ✓" if t.my_lock else "VALIDER"


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _note(text: String) -> Label:
	var l := _label(14, Color(1, 1, 1, 0.6))
	l.text = text
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b
