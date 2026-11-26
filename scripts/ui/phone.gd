extends Control
## Téléphone du joueur (touche C ou bouton TÉL) : Messages, Wave, Orange Money, GPS, Services,
## Joueurs et Carte. En ligne : SMS et virements entre joueurs. En solo : les contacts de la famille.

const W := 290.0
const H := 440.0
const BG := Color("101318")
## Contacts du jeu : réponses automatiques
const NPC := {
	"Maman": ["Doom, rentre avant la nuit !", "Tu as mangé ? Il reste du thiéb à la maison.", "Yàlla na la Yàlla barkeel.", "Appelle ton père, il te cherche."],
	"Tonton Ablaye": ["Neveu ! Passe au garage demain.", "Les clandos ne paient plus comme avant...", "Waaw, waaw. On se voit à l'arène !"],
	"Fatou (cousine)": ["Mdr t'es où ?", "On va à la plage ce week-end ?", "Ramène-moi du bissap stp"],
}
const APPS := [
	["Messages", "messages", Color("2a9d8f")],
	["Wave", "wave", Color("1dc8ff")],
	["Banque (compte, virements)", "bank", Color("1d3557")],
	["Orange Money", "om", Color("ff7900")],
	["GPS", "gps", Color("8338ec")],
	["Musique & Radio", "music", Color("e63946")],
	["Services", "services", Color("e63946")],
	["Joueurs", "players", Color("3a86ff")],
	["Code Ami (jouer à deux)", "friend_code", Color("7209b7")],
	["Carte", "map", Color("6a994e")],
	["Liggéey (emplois)", "jobs", Color("bc6c25")],
	["Keur (maisons, commerces)", "homes", Color("6a994e")],
	["Mbokk (groupe)", "group", Color("06d6a0")],
	["Défis (courses)", "races", Color("e76f51")],
	["Lutte (écuries)", "lutte", Color("d62828")],
	["Sapé (vêtements)", "sape", Color("9b5de5")],
	["Sac (objets)", "bag", Color("e9c46a")],
	["Profil (compétences)", "profile", Color("ef476f")],
	["Oto (mes véhicules)", "cars", Color("457b9d")],
	["Biznis (mes commerces)", "biz", Color("2d6a4f")],
	["Bonus (vidéo)", "bonus", Color("f9c74f")],
]
const Outfits = preload("res://scripts/util/outfits.gd")
const Items = preload("res://scripts/util/items.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")
const PRESETS := [500, 1000, 2000, 5000, 10000]
const FEE := 0.01 ## frais des virements (1 %)

var main
var hud
var convs := {} ## contact → [[moi ?, texte], ...]
var unread := {} ## contact → nombre de messages non lus
var history: Array = [] ## opérations Wave / Orange Money
var _app := "home"
var _contact := ""
var _wallet := ""
var _recipient := ""
var _title: Label
var _clock: Label
var _content: VBoxContainer
var _scroll: ScrollContainer
var _entry: LineEdit
## Défilement au doigt : la liste suit le doigt même s'il part d'un bouton, et un bouton
## ne s'active pas si le doigt a glissé (pas d'achat par erreur en faisant défiler)
var _touch_y0 := 0.0
var _tracking := false
var _dragged := false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vp := get_viewport_rect().size if get_viewport() else Vector2(1280, 720)
	var margins: Dictionary = GameState.get_safe_margins(get_viewport())
	var cur_w: float = minf(W, vp.x - margins.left - margins.right - 24.0)
	var cur_h: float = minf(H, vp.y - margins.top - margins.bottom - 24.0)
	custom_minimum_size = Vector2(cur_w, cur_h)
	# En bas à droite, respecte l'encoche et la barre d'accueil
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	var r_off: float = margins.right + 16.0
	var b_off: float = margins.bottom + 16.0
	offset_left = -cur_w - r_off
	offset_right = -r_off
	offset_top = -cur_h - b_off
	offset_bottom = -b_off
	var frame := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.set_corner_radius_all(22)
	sb.set_border_width_all(4)
	sb.border_color = Color("2b2d33")
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	frame.add_theme_stylebox_override("panel", sb)
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	frame.add_child(v)
	# Barre d'état
	var bar := HBoxContainer.new()
	v.add_child(bar)
	var op := _label("Orange SN  4G", 11, Color("bbbbbb"))
	op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(op)
	_clock = _label("08:00", 11, Color("bbbbbb"))
	bar.add_child(_clock)
	_title = _label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_title.clip_text = true
	v.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 5)
	_content.mouse_filter = Control.MOUSE_FILTER_STOP # le défilement au doigt est géré par _input
	_scroll.add_child(_content)
	# Boutons du bas
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 5)
	v.add_child(nav)
	for b in [["Retour", _back], ["Accueil", func(): _show("home")], ["Fermer", close]]:
		var btn := _button(b[0], b[1], Color("2b2d33"))
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(btn)
	for c in NPC:
		convs[c] = []
	Net.sms_received.connect(_on_sms)
	Net.money_received.connect(_on_money)
	Ads.changed.connect(_on_ads_changed)


func _on_ads_changed() -> void:
	if visible and _app == "bonus":
		_show("bonus")


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch and event.pressed and GameState.typing:
		var r := get_global_rect()
		if not r.has_point(event.position):
			_unfocus()
	var to_local := _scroll.get_global_transform_with_canvas().affine_inverse()
	if event is InputEventScreenTouch:
		if event.pressed:
			_tracking = Rect2(Vector2.ZERO, _scroll.size).has_point(to_local * event.position)
			_touch_y0 = event.position.y
			_dragged = false
		else:
			_tracking = false # _dragged reste vrai jusqu'au prochain appui : le bouton lâché l'ignore
	elif event is InputEventScreenDrag and _tracking:
		if not _dragged and absf(event.position.y - _touch_y0) > 12.0:
			_dragged = true
		if _dragged:
			_scroll.scroll_vertical -= int(to_local.basis_xform(event.relative).y)
			get_viewport().set_input_as_handled() # la caméra ne tourne pas en même temps


func _process(_delta: float) -> void:
	if visible:
		var m := int(GameState.game_minutes)
		_clock.text = "%02d:%02d" % [m / 60, m % 60]
		var vp := get_viewport_rect().size if get_viewport() else Vector2(1280, 720)
		var margins: Dictionary = GameState.get_safe_margins(get_viewport())
		var cur_w: float = minf(W, vp.x - margins.left - margins.right - 24.0)
		var cur_h: float = minf(H, vp.y - margins.top - margins.bottom - 24.0)
		var r_off: float = margins.right + 16.0
		var b_off: float = maxf(margins.bottom + 8.0, 16.0)
		offset_right = -r_off
		offset_left = -cur_w - r_off
		var kb_h := DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
		if kb_h > 0 and GameState.typing:
			var target_b := -float(kb_h) - 10.0
			offset_bottom = lerpf(offset_bottom, target_b, 0.4)
			offset_top = offset_bottom - cur_h
		else:
			offset_bottom = lerpf(offset_bottom, -b_off, 0.4)
			offset_top = offset_bottom - cur_h


# --- Ouverture ---------------------------------------------------------------------------

func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.release_touch()
	_show("home")


func close() -> void:
	_unfocus()
	visible = false


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func unread_total() -> int:
	var n := 0
	for c in unread:
		n += unread[c]
	return n


func _back() -> void:
	match _app:
		"chat":
			_show("messages")
		"send":
			_show(_wallet)
		"report_player":
			_show("players")
		"delete_account":
			_show("profile")
		"home":
			close()
		_:
			_show("home")


func _show(app: String) -> void:
	_unfocus()
	_app = app
	for ch in _content.get_children():
		ch.queue_free()
	_entry = null
	match app:
		"home":
			_home()
		"messages":
			_messages()
		"chat":
			_chat()
		"wave", "om":
			_wallet_app(app)
		"send":
			_send_screen()
		"gps":
			_gps()
		"services":
			_services()
		"players":
			_players()
		"friend_code":
			_friend_code_app()
		"jobs":
			_jobs_app()
		"homes":
			_homes_app()
		"group":
			_group_app()
		"races":
			_races_app()
		"lutte":
			_lutte_app()
		"music":
			_music_app()
		"bonus":
			_bonus_app()
		"sape":
			_sape_app()
		"bag":
			_bag_app()
		"cars":
			_cars_app()
		"biz":
			_biz_app()
		"bank":
			_bank_app()
		"profile":
			_profile_app()
		"map":
			close()
			hud.open_map()
	_scroll.scroll_vertical = 0


# --- Écrans ------------------------------------------------------------------------------

func _home() -> void:
	_title.text = "Galsen Phone"
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	var first_btn: Button = null
	for a in APPS:
		var id: String = a[1]
		var text: String = a[0]
		if id == "messages" and unread_total() > 0:
			text += " (%d)" % unread_total()
		var b := _button(text, func(): _show(id), a[2])
		b.custom_minimum_size = Vector2(120, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		if first_btn == null:
			first_btn = b
	if first_btn != null and GameState.gamepad_active:
		first_btn.grab_focus()
	_content.add_child(_label("Solde : %s" % GameState.fcfa(GameState.money), 14, Color("7cfc9a"), HORIZONTAL_ALIGNMENT_CENTER))
	if not Net.online:
		_content.add_child(_note("Mode solo : SMS et virements entre joueurs disponibles en ligne."))


func _contacts() -> Array:
	# Conversations d'abord, puis les joueurs proches, puis les autres (40 contacts au plus)
	var list: Array = []
	for c in convs:
		if NPC.has(c) or not convs[c].is_empty():
			list.append(c)
	if Net.online:
		for id in _players_sorted():
			var who: String = Net.roster[id]["pseudo"]
			if not who in list:
				list.append(who)
	return list.slice(0, 40)


## Joueurs proches d'abord, puis les autres
func _players_sorted() -> Array:
	var ids: Array = []
	for id in Net.remote:
		if Net.roster.has(id):
			ids.append(id)
	for id in Net.roster:
		if not id in ids:
			ids.append(id)
	return ids


func _messages() -> void:
	_title.text = "Messages"
	for c in _contacts():
		var who: String = c
		var last: String = ""
		if convs.has(who) and not convs[who].is_empty():
			last = " — " + str(convs[who][-1][1]).left(22)
		var n: int = unread.get(who, 0)
		var tag := " (%d)" % n if n > 0 else ""
		var b := _button(who + tag + last, func(): _open_chat(who), Color("1e2a30"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_content.add_child(b)


func _open_chat(who: String) -> void:
	_contact = who
	unread.erase(who)
	_show("chat")


func _chat() -> void:
	_title.text = _contact
	if not convs.has(_contact):
		convs[_contact] = []
	for m in convs[_contact]:
		var mine: bool = m[0]
		var l := _label(m[1], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Color("caffbf") if mine else Color.WHITE)
		_content.add_child(l)
	if convs[_contact].is_empty():
		_content.add_child(_note("Aucun message. Écris le premier !"))
	_entry = _line("Ton message...")
	_entry.max_length = 200
	_entry.text_submitted.connect(func(_t): _send_sms())
	_content.add_child(_entry)
	_content.add_child(_button("Envoyer", _send_sms, Color("2a9d8f")))
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func _send_sms() -> void:
	if _entry == null:
		return
	var text := _entry.text.strip_edges()
	if text == "":
		return
	var who := _contact
	if NPC.has(who):
		convs[who].append([true, text])
		_reply_later(who)
	elif Net.online:
		Net.send_sms(who, text)
		convs[who].append([true, text])
	else:
		GameState.notify.emit("Pas de réseau pour joindre %s (mode solo)." % who)
		return
	_show("chat")


func _reply_later(who: String) -> void:
	await get_tree().create_timer(randf_range(2.0, 5.0)).timeout
	_on_sms(who, NPC[who].pick_random())


func _on_sms(from: String, text: String) -> void:
	if not convs.has(from):
		convs[from] = []
	convs[from].append([false, text])
	if visible and _app == "chat" and _contact == from:
		_show("chat")
	else:
		unread[from] = unread.get(from, 0) + 1
		GameState.notify.emit("SMS de %s : %s" % [from, text.left(60)])
		if visible and _app in ["home", "messages"]:
			_show(_app)
	Audio.play_sfx("coin", -18.0)


# --- Wave et Orange Money ----------------------------------------------------------------

func _wallet_name(app: String) -> String:
	return "Wave" if app == "wave" else "Orange Money"


func _wallet_app(app: String) -> void:
	_wallet = app
	_title.text = _wallet_name(app)
	_content.add_child(_label("Solde : %s" % GameState.fcfa(GameState.money), 20, Color("7cfc9a"), HORIZONTAL_ALIGNMENT_CENTER))
	if Net.online:
		_content.add_child(_note("Envoyer de l'argent à un joueur (frais %d %%) :" % int(FEE * 100)))
		var any := false
		for id in _players_sorted().slice(0, 30):
			var who: String = Net.roster[id]["pseudo"]
			any = true
			_content.add_child(_button("Envoyer à %s" % who, func():
				_recipient = who
				_show("send"), APPS[1][2] if app == "wave" else APPS[2][2]))
		if not any:
			_content.add_child(_note("Aucun autre joueur connecté."))
	else:
		_content.add_child(_note("Les virements entre joueurs fonctionnent en ligne."))
	_content.add_child(_label("Dernières opérations", 14, Color.WHITE))
	if history.is_empty():
		_content.add_child(_note("Aucune opération."))
	for h in history.slice(maxi(0, history.size() - 10)):
		_content.add_child(_note(h))


func _send_screen() -> void:
	_title.text = "%s → %s" % [_wallet_name(_wallet), _recipient]
	_entry = _line("Montant en FCFA")
	_entry.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_content.add_child(_entry)
	var row := GridContainer.new()
	row.columns = 3
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	for a in PRESETS:
		var amount: int = a
		var b := _button(GameState.fcfa(amount), func(): _entry.text = str(amount), Color("2b2d33"))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	_content.add_child(_button("Envoyer", _transfer, APPS[1][2] if _wallet == "wave" else APPS[2][2]))


func _transfer() -> void:
	var amount := _entry.text.strip_edges().to_int() if _entry else 0
	var fee := maxi(0, ceili(amount * FEE))
	var id := Net.peer_of(_recipient)
	if amount <= 0:
		GameState.notify.emit("Entre un montant.")
	elif id < 0:
		GameState.notify.emit("%s n'est plus connecté." % _recipient)
	elif GameState.money < amount + fee:
		GameState.notify.emit("Solde insuffisant : il faut %s (frais compris)." % GameState.fcfa(amount + fee))
	elif Net.give_money(id, amount, "Virement %s" % _wallet_name(_wallet)):
		GameState.spend(fee)
		history.append("-%s → %s (%s, frais %s)" % [GameState.fcfa(amount), _recipient, _wallet_name(_wallet), GameState.fcfa(fee)])
		GameState.notify.emit("%s : %s envoyés à %s." % [_wallet_name(_wallet), GameState.fcfa(amount), _recipient])
		Audio.play_sfx("coin", -10.0)
		_show(_wallet)


func _on_money(from: String, amount: int, reason: String) -> void:
	history.append("+%s de %s%s" % [GameState.fcfa(amount), from, (" (%s)" % reason) if reason != "" else ""])
	if history.size() > 40:
		history.pop_front()
	if visible and _app in ["wave", "om", "home"]:
		_show(_app)


# --- GPS, services, joueurs --------------------------------------------------------------

func _gps() -> void:
	_title.text = "GPS"
	if GameState.waypoint != null:
		_content.add_child(_button("Effacer l'itinéraire", func():
			main.gps.clear()
			_show("gps"), Color("6c757d")))
	var pp: Vector3 = main.player.get_world_position()
	var list: Array = []
	for n in main.city.places:
		list.append([pp.distance_to(main.city.places[n]), n])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for e in list.slice(0, 30):
		var place_name: String = e[1]
		var d: float = e[0]
		var txt := "%s — %s" % [place_name, ("%d m" % int(d)) if d < 1000.0 else ("%.1f km" % (d / 1000.0))]
		var b := _button(txt, func():
			main.gps.set_waypoint(main.city.places[place_name], place_name)
			close(), Color("2d1f45"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_content.add_child(b)


func _services() -> void:
	_title.text = "Services"
	if Net.online:
		_content.add_child(_button("Appeler un taxi", func():
			Net.call_service("taxi")
			close(), Color("f4a261")))
		_content.add_child(_button("Appeler la police (17)", func():
			Net.call_service("police")
			close(), Color("3a86ff")))
		_content.add_child(_button("Appeler le SAMU (15)", func():
			Net.call_service("samu")
			close(), Color("e63946")))
		_content.add_child(_button("Appeler un mécanicien (dépannage)", func():
			Net.call_service("mecanicien")
			close(), Color("6c757d")))
		if main.net_jobs:
			if main.net_jobs.faction_title() != "":
				_content.add_child(_note("Ta faction : " + main.net_jobs.faction_title()))
			_content.add_child(_button("Métiers et factions (police, SAMU, gang)", func():
				close()
				main.net_jobs.open_menu(), Color("2a9d8f")))
	else:
		_content.add_child(_note("Taxi : fais signe à un taxi au bord de la route (action près de lui)."))
		_content.add_child(_note("Bus et cars rapides : attends à un arrêt de bus."))
	_content.add_child(_note("Hôpital Principal : en cas de malaise, on t'y emmène."))


func _players() -> void:
	_title.text = "Joueurs en ligne"
	if not Net.online:
		_content.add_child(_note("Joue en ligne pour voir les autres joueurs."))
		return
	if Net.roster.is_empty():
		_content.add_child(_note("Tu es seul en ville pour le moment."))
	var pp: Vector3 = main.player.get_world_position()
	# Les joueurs proches d'abord (position connue), puis les autres ; 50 au plus
	var ids: Array = Net.remote.keys()
	for id in Net.roster:
		if not id in ids:
			ids.append(id)
	_content.add_child(_note("%d joueur(s) en ligne" % Net.players_online()))
	var share_f_btn := _button("🤝 Partager / Entrer un Code Ami", func(): _show("friend_code"), Color("7209b7"))
	_content.add_child(share_f_btn)
	for id in ids.slice(0, 50):
		var info: Dictionary = Net.roster.get(id, {})
		if info.is_empty():
			continue
		var who: String = info["pseudo"]
		var job: String = info["job"]
		var near: bool = Net.remote.has(id)
		var st: Dictionary = Net.remote[id]["state"] if near else {}
		var where := "loin"
		if near:
			where = "%d m" % int(Vector2(pp.x - float(st["x"]), pp.z - float(st["z"])).length())
		var txt := "%s — %s — %s" % [who, Net.JOBS.get(job, "sans métier"), where]
		if int(info["wl"]) > 0:
			txt += " — RECHERCHÉ"
		var pl := _label(txt, 13, Color.WHITE)
		pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(pl)
		var row := HBoxContainer.new()
		_content.add_child(row)
		var sms := _button("SMS", func(): _open_chat(who), Color("2a9d8f"))
		var pay := _button("Wave", func():
			_wallet = "wave"
			_recipient = who
			_show("send"), Color("1dc8ff"))
		var add_f := _button("+ Ami", func():
			Net.save_friend(who, Net.generate_friend_code(who))
			GameState.notify.emit("%s ajouté à tes amis enregistrés !" % who)
			Audio.play_sfx("coin", -6.0)
		, Color("5a189a"))
		var btns: Array = [sms, pay, add_f]
		if near:
			var gp := Vector3(float(st["x"]), 0.2, float(st["z"]))
			btns.append(_button("GPS", func():
				main.gps.set_waypoint(gp, who)
				close(), Color("8338ec")))
		for b in btns:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
		if who.to_lower() != Net.pseudo.to_lower():
			var mod_row := HBoxContainer.new()
			_content.add_child(mod_row)
			var is_blk := Net.is_blocked(who)
			var blk_btn := _button("Débloquer" if is_blk else "Bloquer", func():
				if Net.is_blocked(who):
					Net.unblock_player(who)
					GameState.notify.emit("%s débloqué." % who)
				else:
					Net.block_player(who)
					GameState.notify.emit("%s bloqué (messages et voix masqués)." % who)
				_show("players"), Color("457b9d") if is_blk else Color("d90429"))
			var rep_btn := _button("Signaler", func():
				_report_player_prompt(who), Color("e76f51"))
			blk_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rep_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mod_row.add_child(blk_btn)
			mod_row.add_child(rep_btn)


func _report_player_prompt(who: String) -> void:
	_unfocus()
	_app = "report_player"
	for ch in _content.get_children():
		ch.queue_free()
	_entry = null
	_title.text = "Signaler : %s" % who
	_content.add_child(_label("Modération & Sécurité", 14, Color("e9ecef")))
	_content.add_child(_note("Sélectionne le motif du signalement pour l'équipe de modération :"))
	var reasons = [
		"Comportement toxique ou insultes",
		"Triche, piratage ou exploit de bug",
		"Spam, arnaque ou publicité",
		"Harcèlement ou menaces",
		"Contenu ou pseudo inapproprié"
	]
	for r in reasons:
		var r_str: String = r
		_content.add_child(_button(r_str, func():
			Net.report_player(who, r_str)
			GameState.notify.emit("Joueur %s signalé. Merci de veiller à la sécurité du jeu !" % who)
			_show("players"), Color("e63946")))
	_content.add_child(_button("Annuler", func(): _show("players"), Color("6c757d")))


# --- Code Ami : jouer ensemble en ligne ----------------------------------------------

func _friend_code_app() -> void:
	_title.text = "Code Ami — Jouer ensemble"

	var my_code := Net.get_my_friend_code()
	_content.add_child(_label("TON CODE AMI UNIQUE", 13, Color("90e0ef"), HORIZONTAL_ALIGNMENT_CENTER))

	var code_card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.12, 0.16, 0.24, 0.95)
	csb.border_color = Color("7cfc9a")
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(12)
	csb.content_margin_top = 10
	csb.content_margin_bottom = 10
	code_card.add_theme_stylebox_override("panel", csb)
	_content.add_child(code_card)

	var card_v := VBoxContainer.new()
	card_v.add_theme_constant_override("separation", 6)
	code_card.add_child(card_v)

	var code_display := Label.new()
	code_display.text = my_code
	code_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_display.add_theme_font_size_override("font_size", 28)
	code_display.add_theme_color_override("font_color", Color("fdef42"))
	card_v.add_child(code_display)

	var card_sub := Label.new()
	card_sub.text = "Partage ce code à un ami pour vous retrouver à Dakar !"
	card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_sub.add_theme_font_size_override("font_size", 11)
	card_sub.add_theme_color_override("font_color", Color("ced4da"))
	card_v.add_child(card_sub)

	var copy_row := HBoxContainer.new()
	copy_row.add_theme_constant_override("separation", 6)
	_content.add_child(copy_row)

	var copy_code_btn := _button("📋 Copier le code", func():
		DisplayServer.clipboard_set(my_code)
		GameState.notify.emit("Code %s copié dans le presse-papier !" % my_code)
		Audio.play_sfx("coin", -8.0)
	, Color("2a9d8f"))
	copy_code_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_row.add_child(copy_code_btn)

	var share_text_btn := _button("💬 Invitation", func():
		var share_msg := "Rejoins-moi sur Galsen-Life ! Mon code ami est : %s. Entre ce code dans ton jeu pour me retrouver en direct à Dakar !" % my_code
		DisplayServer.clipboard_set(share_msg)
		GameState.notify.emit("Message d'invitation copié ! Envoie-le sur WhatsApp ou SMS.")
		Audio.play_sfx("coin", -8.0)
	, Color("7209b7"))
	share_text_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_row.add_child(share_text_btn)

	_content.add_child(HSeparator.new())

	_content.add_child(_label("REJOINDRE UN AMI AVEC SON CODE", 13, Color("fdef42")))
	_content.add_child(_note("Entre le code de ton ami pour te téléporter à ses côtés :"))

	_entry = _line("Code de ton ami (ex: GAL-12345)")
	_content.add_child(_entry)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	_content.add_child(join_row)

	var paste_entry_btn := _button("Coller", func():
		var cb := DisplayServer.clipboard_get().strip_edges()
		if cb != "" and _entry != null:
			_entry.text = cb
	, Color("495057"))
	paste_entry_btn.custom_minimum_size = Vector2(70, 38)
	join_row.add_child(paste_entry_btn)

	var join_btn := _button("🚀 Rejoindre !", func():
		if _entry == null:
			return
		var cd := _entry.text.strip_edges()
		if cd == "":
			GameState.notify.emit("Entre un code ami.")
			return
		Net.join_by_friend_code(cd)
	, Color("e63946"))
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(join_btn)

	_content.add_child(HSeparator.new())

	_content.add_child(_label("MES AMIS ENREGISTRÉS", 13, Color.WHITE))
	if Net.saved_friends.is_empty():
		_content.add_child(_note("Aucun ami enregistré. Rejoins un ami avec son code pour l'ajouter automatiquement."))
	else:
		for f in Net.saved_friends:
			if not f is Dictionary:
				continue
			var fn: String = f.get("pseudo", "")
			var fc: String = f.get("code", "")
			if fn == "":
				continue

			var is_online := false
			for sid in Net.roster:
				if Net.roster[sid].get("pseudo", "").to_lower() == fn.to_lower():
					is_online = true
					break

			var friend_box := PanelContainer.new()
			var fsb := StyleBoxFlat.new()
			fsb.bg_color = Color(0.10, 0.13, 0.18, 0.9)
			fsb.set_corner_radius_all(8)
			fsb.content_margin_left = 6
			fsb.content_margin_right = 6
			fsb.content_margin_top = 4
			fsb.content_margin_bottom = 4
			friend_box.add_theme_stylebox_override("panel", fsb)
			_content.add_child(friend_box)

			var fv := VBoxContainer.new()
			fv.add_theme_constant_override("separation", 3)
			friend_box.add_child(fv)

			var status_dot := "🟢 En ligne à Dakar" if is_online else "⚪ Hors ligne"
			var fn_lbl := _label("%s (%s) — %s" % [fn, fc, status_dot], 12, Color("7cfc9a") if is_online else Color("adb5bd"))
			fv.add_child(fn_lbl)

			var f_actions := HBoxContainer.new()
			f_actions.add_theme_constant_override("separation", 4)
			fv.add_child(f_actions)

			if is_online:
				var rej_b := _button("Rejoindre", func():
					Net.join_by_friend_code(fc)
				, Color("2a9d8f"))
				rej_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				f_actions.add_child(rej_b)

			var sms_b := _button("SMS", func():
				_open_chat(fn)
			, Color("1dc8ff"))
			sms_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			f_actions.add_child(sms_b)

			var del_b := _button("Retirer", func():
				Net.remove_saved_friend(fc)
				_show("friend_code")
			, Color("6c757d"))
			del_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			f_actions.add_child(del_b)


# --- Mbokk : groupe ------------------------------------------------------------------

func _group_app() -> void:
	_title.text = "Mbokk — Mon groupe"
	if not Net.online:
		_content.add_child(_note("Les groupes fonctionnent en ligne."))
		return
	var s = Net.social
	_content.add_child(_button("🤝 Partager mon Code Ami à un ami", func(): _show("friend_code"), Color("7209b7")))
	if s.my_group == "":
		_content.add_child(_note("Crée ton groupe (ta « famille ») : son nom s'affiche sous ton pseudo, tu as un chat de groupe (/g dans le chat) et tu vois tes membres sur la mini-carte."))
		_entry = _line("Nom du groupe")
		_entry.max_length = 20
		_content.add_child(_entry)
		_content.add_child(_button("Créer le groupe", func():
			if _entry and _entry.text.strip_edges().length() >= 3:
				s.rpc_group_create.rpc_id(1, _entry.text.strip_edges())
				close(), Color("06d6a0")))
		return
	_content.add_child(_label("« %s »" % s.my_group, 16, Color("06d6a0")))
	for m in s.my_members:
		var on: bool = int(m[1]) > 0
		_content.add_child(_note("%s%s — %s" % [m[0], " (chef)" if m[2] else "", "en ligne" if on else "hors ligne"]))
		var mid: int = m[1]
		if on and main.social_ui and main.social_ui.group_pos.has(mid):
			var gp: Vector3 = main.social_ui.group_pos[mid]
			var nm: String = m[0]
			_content.add_child(_button("GPS vers %s" % nm, func():
				main.gps.set_waypoint(gp, nm)
				close(), Color("6a4c93")))
	_content.add_child(_label("Inviter un joueur proche", 14, Color.WHITE))
	var any := false
	for id in Net.remote:
		if Net.social.tags.has(id):
			continue
		any = true
		var pid: int = id
		_content.add_child(_button("Inviter %s" % Net.remote[id]["pseudo"], func(): s.rpc_group_invite.rpc_id(1, pid), Color("2a9d8f")))
	if not any:
		_content.add_child(_note("Aucun joueur sans groupe autour de toi."))
	_content.add_child(_button("Quitter le groupe", func():
		s.rpc_group_leave.rpc_id(1)
		close(), Color("6c757d")))


# --- Défis : courses de voitures et lutte ---------------------------------------------

func _races_app() -> void:
	_title.text = "Défis — Courses et lutte"
	if not Net.online or main.social_ui == null:
		_content.add_child(_note("Les défis entre joueurs fonctionnent en ligne."))
		return
	var ui = main.social_ui
	_content.add_child(_note("LUTTE : approche-toi d'un joueur et appuie sur l'action → « Défier à la lutte »."))
	if ui.race_id >= 0 and ui.race_host == multiplayer.get_unique_id() and not ui._race_running:
		var rid: int = ui.race_id
		_content.add_child(_note("Ta course : %s" % ", ".join(ui.race_names)))
		_content.add_child(_button("Lancer la course !", func():
			Net.social.rpc_race_start.rpc_id(1, rid)
			close(), Color("e63946")))
	_content.add_child(_label("Courses ouvertes près de toi", 14, Color.WHITE))
	var pp: Vector3 = main.player.get_world_position()
	if ui.open_races.is_empty():
		_content.add_child(_note("Aucune pour le moment."))
	for rid in ui.open_races:
		var r: Dictionary = ui.open_races[rid]
		var d := int(Vector2(pp.x - r["pos"].x, pp.z - r["pos"].z).length())
		var id2: int = rid
		_content.add_child(_note("%s → %s — mise %s — départ à %d m" % [r["host"], r["dest"], GameState.fcfa(r["fee"]), d]))
		var start_pos: Vector3 = r["pos"]
		var row := HBoxContainer.new()
		_content.add_child(row)
		var join := _button("S'inscrire", func():
			ui.join_race(id2)
			close(), Color("e76f51"))
		var go := _button("GPS départ", func():
			main.gps.set_waypoint(start_pos, "Départ de la course")
			close(), Color("6a4c93"))
		for b in [join, go]:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)
	_content.add_child(_label("Ouvrir une course (au volant)", 14, Color.WHITE))
	for fee in [0, 1000, 5000]:
		var f: int = fee
		_content.add_child(_note("Mise : %s" % ("aucune" if f == 0 else GameState.fcfa(f))))
		var row2 := HBoxContainer.new()
		_content.add_child(row2)
		for dest in ["Place de l'Indépendance", "Grande Mosquée", "Porte du Millénaire", "Gare routière Petersen"]:
			var dn: String = dest
			var b2 := _button(dn.replace("Place de l'", "").replace("Gare routière ", "").left(10), func():
				ui.create_race(dn, f)
				close(), Color("9d0208"))
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(b2)


# --- Lutte : carrière, écuries, journées ----------------------------------------------

func _lutte_app() -> void:
	_title.text = "Lutte — Làmb"
	var lt = main.lutte
	if lt == null:
		return
	var s: Dictionary = GameState.lutte
	var ec: String = lt.ecurie(s["ecurie"]).get("name", "sans écurie") if s["ecurie"] != "" else "sans écurie"
	_content.add_child(_label("Force %d — popularité %d" % [s["force"], s["pop"]], 15, Color("ffd166")))
	_content.add_child(_note("Bilan : %s — %s — cachet actuel : %s" % [lt.record("joueur"), ec, GameState.fcfa(lt.cachet_for(int(s["pop"])))]))
	if not s["bout"].is_empty():
		var b: Dictionary = s["bout"]
		_content.add_child(_note("Prochain combat : contre %s, %s à 17 h au %s." % [lt.wrestler_name(b["opp"]),
			"aujourd'hui" if int(b["day"]) == GameState.day else "demain", lt.VENUES[b["venue"]]["name"]]))
		var vp: Vector3 = lt._venue_pos.get(b["venue"], Vector3.ZERO)
		_content.add_child(_button("GPS vers le stade", func():
			main.gps.set_waypoint(vp, "Combat de lutte")
			close(), Color("6a4c93")))
	_content.add_child(_label("Journées de lutte", 14, Color.WHITE))
	for line in lt.calendar_lines():
		_content.add_child(_note(line))
	_content.add_child(_label("Écuries de Dakar (entraînement, combats)", 14, Color.WHITE))
	for e in lt.ECURIES:
		var eid: String = e["id"]
		if not lt._bases.has(eid):
			continue
		var bp: Vector3 = lt._bases[eid]["pos"]
		var en: String = e["name"]
		_content.add_child(_button("%s (force %d+)" % [en, e["min"]], func():
			main.gps.set_waypoint(bp, en)
			close(), Color(e["color"]).darkened(0.35)))
	for v in lt.VENUES:
		if lt._venue_pos.has(v):
			var vpos: Vector3 = lt._venue_pos[v]
			var vn: String = lt.VENUES[v]["name"]
			_content.add_child(_button("GPS : %s (organiser une journée)" % vn, func():
				main.gps.set_waypoint(vpos, vn)
				close(), Color("495057")))
	if not Net.online:
		_content.add_child(_note("En ligne : écuries de joueurs et journées de lutte entre joueurs."))
		return
	var L = Net.lutte
	_content.add_child(_label("Écurie de joueurs (en ligne)", 14, Color("06d6a0")))
	if L.my_ecurie != "":
		_content.add_child(_note("« %s » — %d V – %d D" % [L.my_ecurie, L.my_record.x, L.my_record.y]))
		for m in L.my_members:
			_content.add_child(_note("%s%s — %s" % [m[0], " (chef)" if m[2] else "", "en ligne" if m[1] else "hors ligne"]))
		_content.add_child(_button("Quitter l'écurie", func():
			L.rpc_ecurie_leave.rpc_id(1)
			close(), Color("6c757d")))
	else:
		_content.add_child(_note("Fonde ton écurie (%s) : son chef touche 10 %% des cachets de ses lutteurs." % GameState.fcfa(L.CREATE_FEE)))
		_entry = _line("Nom de l'écurie")
		_entry.max_length = 24
		_content.add_child(_entry)
		_content.add_child(_button("Fonder l'écurie", func():
			if _entry and _entry.text.strip_edges().length() >= 3:
				if GameState.spend(L.CREATE_FEE):
					L.rpc_ecurie_create.rpc_id(1, _entry.text.strip_edges())
				else:
					GameState.notify.emit("Il te faut %s pour fonder une écurie." % GameState.fcfa(L.CREATE_FEE))
				close(), Color("06d6a0")))
	_content.add_child(_button("Voir les écuries de joueurs", func():
		L.rpc_ecurie_list_req.rpc_id(1)
		close(), Color("2a9d8f")))
	_content.add_child(_label("Journées entre joueurs", 14, Color("06d6a0")))
	if L.journees.is_empty():
		_content.add_child(_note("Aucune. Organise la tienne au bureau des promoteurs d'un stade."))
	for jid in L.journees:
		var j: Dictionary = L.journees[jid]
		var id2: int = jid
		var mine: bool = j["promoter"] == Net.pseudo
		var registered: bool = Net.pseudo in j["names"]
		_content.add_child(_note("%s — %s, cachet %s, %d/%d lutteurs%s : %s" % [j["promoter"], lt.VENUES[j["venue"]]["name"],
			GameState.fcfa(j["cachet"]), j["names"].size(), j["max"], " (en cours)" if j["state"] == "running" else "", ", ".join(j["names"])]))
		var row := HBoxContainer.new()
		_content.add_child(row)
		var btns: Array = []
		if j["state"] == "open":
			if mine:
				btns.append(_button("Lancer", func():
					L.rpc_journee_start.rpc_id(1, id2)
					close(), Color("e63946")))
				btns.append(_button("Annuler", func():
					L.rpc_journee_cancel.rpc_id(1, id2)
					close(), Color("6c757d")))
			else:
				btns.append(_button("Se désinscrire" if registered else "S'inscrire", func():
					L.rpc_journee_register.rpc_id(1, id2, not registered)
					close(), Color("d62828")))
		var jp: Vector3 = j["pos"]
		btns.append(_button("GPS", func():
			main.gps.set_waypoint(jp, "Journée de lutte")
			close(), Color("6a4c93")))
		for b2 in btns:
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b2)


# --- Keur : logement ----------------------------------------------------------------

## Musique & Radio : Sabar & Tama, JOJ Dakar 2026, Mbalax FM
func _music_app() -> void:
	_title.text = "Musique & Radio"
	var playing: bool = Audio.is_radio_playing()
	var cur_idx: int = Audio.current_track_idx

	var status_text: String
	var status_col: Color
	if playing:
		status_text = "🔊 En écoute : %s" % Audio.TRACK_NAMES[cur_idx]
		status_col = Color("7cfc9a")
	else:
		status_text = "🔇 Radio éteinte"
		status_col = Color("aaaaaa")

	var sl := _label(status_text, 13, status_col)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(sl)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	_content.add_child(controls)

	var btn_stop := _button("⏹️ Éteindre" if playing else "▶ Écouter", func():
		Audio.set_radio(not playing)
		_show("music"), Color("e63946") if playing else Color("2a9d8f"))
	btn_stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(btn_stop)

	var btn_next := _button("⏭️ Suivant", func():
		Audio.next_radio_track()
		_show("music"), Color("457b9d"))
	btn_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(btn_next)

	var btn_rand := _button("🔀 Aléatoire", func():
		Audio.play_random_track(true)
		_show("music"), Color("e76f51"))
	btn_rand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(btn_rand)

	var track_descs := [
		"Nobel — Chef-d'œuvre acoustique et poétique de Souleymane Faye & Xalam. Un monument de la musique sénégalaise.",
		"Fatou Yo — Le tube planétaire de Touré Kunda. Rythmes mandingues et percussions casamançaises légendaires.",
		"Fondinke — Grand classique de Touré Kunda célébrant la jeunesse et l'énergie africaine.",
		"Em'ma — Succès mondial intemporel de Touré Kunda aux grooves chaleureux et cuivres éclatants.",
		"Is Do Si — Morceau culte du groupe Xalam fusionnant jazz, afrobeat et polyrythmies sénégalaises.",
		"Ninki Nanka — Hymne mythique de Xalam inspiré de la légende du dragon Ninki Nanka.",
		"Natalia — Balade afro-mandingue envoûtante et mélodique de Touré Kunda.",
		"Duunya — Réflexion poétique et philosophique de Touré Kunda sur la vie et le destin.",
		"Miniyamba — Le grand hymne traditionnel mandingue revisité avec la voix puissante de Coumba Gawlo.",
		"Reference — Hip-hop mbalax sénégalais de Books feat. Jas, production signée Ama Diop.",
		"Massa Thiono — Morceau acoustique profond de Diogal Sakho (Archive INA). Guitare folk et chant wolof.",
		"Weet — La voix poétique et engagée d'El Hadji Ndiaye. Guitare acoustique et émotion pure.",
		"Sogni — Le duo légendaire Pape & Cheikh aux accents folk acoustiques de Dakar.",
		"Wolof Song — Polyphonies vocales traditionnelles du Sénégal et chœurs sacrés.",
		"Hymne officiel des JOJ Dakar 2026 interprété par Baaba Maal.",
		"Chant patriotique et traditionnel légendaire interprété par Kiné Lam lors de la cérémonie des JOJ Dakar 2026.",
		"Générique officiel JOJ Dakar 2026 composé par Iss 814 Beats. Rythme électro-mbalax énergique et moderne.",
		"Enregistrement live authentique de la cérémonie JOJ Dakar 2026 : percussions Sabar, Tama, chants des lutteurs et ambiance d'arène.",
		"Thème musical officiel de la Cérémonie d'Ouverture des Jeux Olympiques de la Jeunesse Dakar 2026.",
		"Rythme Sabar & Tama (Bakk Sénégal) : Synthèse polyrythmique des arènes avec Thiol, Mbëng-mbëng et kora.",
		"Galsen Mbalax FM : Groove urbain dakarois non-stop avec balafon et guitare."
	]

	_content.add_child(_note("🎲 Playlist aléatoire active : à chaque entrée dans le jeu, une musique est tirée au sort (avec priorité à Touré Kunda, Xalam et Souleymane Faye)."))

	for i in Audio.TRACK_NAMES.size():
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		_content.add_child(box)

		var is_cur: bool = (i == cur_idx)
		var t_title := _label(Audio.TRACK_NAMES[i], 14, Color("ffd166") if is_cur else Color("ffffff"))
		t_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(t_title)

		var desc: String = track_descs[i] if i < track_descs.size() else ""
		var d_lbl := _label(desc, 11, Color("b0b8c4"))
		d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(d_lbl)

		var btn_label := "▶ Écouter ce rythme" if not (is_cur and playing) else "🔊 Morceau actif"
		var btn_col := Color("2a9d8f") if (is_cur and playing) else Color("3a86ff")
		var play_btn := _button(btn_label, func():
			Audio.set_radio_track(i)
			Audio.set_radio(true)
			_show("music"), btn_col)
		play_btn.custom_minimum_size = Vector2(0, 34)
		box.add_child(play_btn)

	_content.add_child(_note("💡 Dans n'importe quel véhicule (voiture, clando, moto, scooter), appuyez sur [R] ou sur le bouton Radio de l'écran pour changer de musique en roulant !"))


## Vidéo avec récompense (scripts/autoload/ads.gd) : le joueur choisit de la regarder
func _bonus_app() -> void:
	Ads.start()
	_title.text = "Bonus"
	_content.add_child(_note("Regarde une courte vidéo publicitaire jusqu'au bout et reçois %s sur ton compte. %d vidéo(s) restante(s) aujourd'hui." % [
		GameState.fcfa(Ads.REWARD), Ads.left_today()]))
	if Ads.can_show():
		_content.add_child(_button("Regarder une vidéo (+%s)" % GameState.fcfa(Ads.REWARD), func():
			Ads.show_rewarded(func(): GameState.add_money(Ads.REWARD, "Bonus vidéo")), Color("f9c74f")))
	else:
		_content.add_child(_note(Ads.why_not()))
	if Ads.privacy_options_required():
		_content.add_child(_button("Choix de confidentialité (pubs)", Ads.show_privacy_options, Color("6c757d")))


## Boutique de vêtements et coiffeur : on achète une couleur, un chapeau ou une coupe une fois,
## puis on le porte quand on veut. En ligne, les autres joueurs voient la tenue.
func _sape_app() -> void:
	_title.text = "Sapé — Vêtements"
	var cur := Outfits.parse(GameState.tenue)
	_content.add_child(_note("Argent : %s. Achète une fois, porte-le quand tu veux. En ligne, tout le monde voit ta tenue." % GameState.fcfa(GameState.money)))
	# Personnages d'une seule pièce : tenue et cheveux d'origine, seuls les chapeaux s'ajoutent
	var single: bool = Net.online and Net.avatar in RealCharacter.AI_MODELS
	if single:
		_content.add_child(_note("Ton personnage garde sa tenue et sa coiffure d'origine : seuls les chapeaux lui vont."))
	for i in Outfits.PARTS.size():
		if single and i != 2:
			continue
		if i == 3:
			_content.add_child(_label("Coiffeur", 18, Color("fdef42")))
		var part: String = Outfits.PARTS[i]
		_content.add_child(_label(Outfits.PART_NAMES[i], 15, Color.WHITE))
		var none_text: String = ["Vêtement d'origine", "Vêtement d'origine", "Sans chapeau", "Coiffure d'origine", "Couleur d'origine"][i]
		_content.add_child(_button(("✓ " if cur[i] == "" else "") + none_text, _wear.bind(i, ""), Color("495057")))
		var catalog: Dictionary = Outfits.CATALOGS[i]
		for id in catalog:
			var item := "%s:%s" % [part, id]
			var e: Array = catalog[id]
			var color: Color
			match i:
				2:
					color = e[2]
				3:
					color = Color("7f5539")
				4:
					color = (e[1] as Color).clamp() if id != "noir" else Color("2b2522")
				_:
					color = e[1]
			var text: String = e[0]
			if cur[i] == id:
				text = "✓ " + text + " (porté)"
			elif GameState.garde_robe.has(item):
				text = "Porter : " + text
			else:
				text = "%s — %s" % [text, GameState.fcfa(Outfits.item_price(item))]
			var b := _button(text, _buy_or_wear.bind(i, id), color.darkened(0.25) if color.get_luminance() > 0.2 else Color("5a5a62"))
			if color.get_luminance() > 0.6:
				b.add_theme_color_override("font_color", Color.BLACK)
			_content.add_child(b)


func _buy_or_wear(i: int, id: String) -> void:
	var item := "%s:%s" % [Outfits.PARTS[i], id]
	if not GameState.garde_robe.has(item):
		var price := Outfits.item_price(item)
		if not GameState.spend(price):
			GameState.notify.emit("Pas assez d'argent liquide (%s)" % GameState.fcfa(price))
			return
		GameState.garde_robe[item] = true
		GameState.notify.emit("-%s — %s" % [GameState.fcfa(price), Outfits.item_name(item)])
		Audio.play_sfx("coin", -10.0)
	_wear(i, id)


func _wear(i: int, id: String) -> void:
	var p := Outfits.parse(GameState.tenue)
	p[i] = id
	GameState.tenue = Outfits.make(p)
	var pl = main.player
	if pl and pl.model and pl.model.has_method("set_outfit"):
		pl.model.set_outfit(GameState.tenue)
	GameState.save_game()
	var keep := _scroll.scroll_vertical # on reste au même endroit de la liste
	_show("sape")
	_scroll.set_deferred("scroll_vertical", keep)


func _homes_app() -> void:
	_title.text = "Keur — Maisons et commerces"
	var hs = main.housing
	if hs == null:
		return
	var home_pos = hs.home_position()
	if home_pos != null:
		var hp: Vector3 = home_pos
		_content.add_child(_button("Rentrer chez moi (GPS)", func():
			main.gps.set_waypoint(hp, "Chez moi")
			close(), Color("2d6a4f")))
	_content.add_child(_note("Argent : %s liquide + %s en banque" % [GameState.fcfa(GameState.money), GameState.fcfa(GameState.bank)]))
	for id in hs.PROPERTIES:
		var pr: Dictionary = hs.PROPERTIES[id]
		var status := ""
		if hs.owned(id) and hs.is_commerce(id):
			status = "Ton commerce : %s par jour, %s en caisse" % [GameState.fcfa(pr["income"]), GameState.fcfa(hs.till(id))]
		elif hs.owned(id):
			status = "Tu es propriétaire"
		elif hs.other_owner(id) != "":
			status = "Propriété de %s" % hs.other_owner(id)
		elif hs.is_commerce(id):
			status = "Commerce à vendre : %s, rapporte %s par jour" % [GameState.fcfa(pr["price"]), GameState.fcfa(pr["income"])]
		elif hs.rented() == id:
			status = "Tu loues (impayés : %d jour(s))" % int(GameState.home.get("unpaid", 0))
		elif int(pr["rent"]) > 0:
			status = "À louer : %s par jour (caution 3 jours)" % GameState.fcfa(pr["rent"])
		else:
			status = "À vendre : %s (+5 %% de frais de notaire)" % GameState.fcfa(pr["price"])
		var cars: Array = GameState.garage.get(id, [])
		var t := _label(pr["name"], 15, Color("ffd166"))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(t)
		var garage_txt := ("\nGarage : %d/%d voiture(s)" % [cars.size(), pr["garage"]]) if int(pr["garage"]) > 0 else ""
		_content.add_child(_note("%s\n%s%s" % [pr["desc"], status, garage_txt]))
		if hs.doors.has(id):
			var dp: Vector3 = hs.doors[id]["pos"]
			var nm: String = pr["name"]
			_content.add_child(_button("GPS vers l'adresse", func():
				main.gps.set_waypoint(dp, nm)
				close(), Color("6a4c93")))


# --- Sac : objets achetés, à manger et à boire ----------------------------------------

func _bag_app() -> void:
	_title.text = "Sac — %d / %d objet(s)" % [GameState.bag_count(), Items.BAG_MAX]
	_content.add_child(_note("Satiété %d — Soif %d — Énergie %d\nAcheté sans faim ni soif, un produit est rangé ici : utilise-le quand tu veux." % [
		int(GameState.hunger), int(GameState.thirst), int(GameState.energy)]))
	if GameState.inventory.is_empty():
		_content.add_child(_note("Ton sac est vide."))
		return
	var names: Array = GameState.inventory.keys()
	names.sort()
	for n in names:
		var item: String = n
		var count: int = GameState.inventory[item]
		if Items.is_consumable(item):
			_content.add_child(_button("%s x%d — consommer (%s)" % [item, count, Items.describe(item)], func():
				if GameState.use_item(item):
					GameState.notify.emit("Tu prends : %s. Dafa neex !" % item)
				_show("bag"), Color("2a9d8f")))
		else:
			_content.add_child(_note("%s x%d" % [item, count]))


# --- Profil : compétences et parcours -------------------------------------------------------

func _profile_app() -> void:
	_title.text = "Profil — %s" % (Net.pseudo if Net.pseudo != "" else "Mon personnage")
	_content.add_child(_label("Compétences", 14, Color("e9ecef")))
	var hints := {"conduite": "monte en roulant ; les accidents abîment moins le moteur",
		"endurance": "monte en courant ; courir fatigue moins",
		"peche": "monte en pêchant ; plus de temps pour ferrer, plus de beaux poissons",
		"cuisine": "monte en cuisinant chez toi ; plus de portions par recette"}
	for k in GameState.SKILLS:
		var lv := GameState.skill_level(k)
		_content.add_child(_label("%s — niveau %d/10  %s" % [GameState.SKILLS[k], lv, "★".repeat(lv)], 13, Color("ffd166")))
		_content.add_child(_note(hints[k]))
	_content.add_child(_label("Parcours", 14, Color("e9ecef")))
	var lines: Array = ["Jour %d à Dakar" % GameState.day,
		"Argent : %s — compte : %s" % [GameState.fcfa(GameState.money), GameState.fcfa(GameState.bank)],
		"Courses de taxi : %d — livraisons : %d — cafés vendus : %d" % [GameState.stats["courses_taxi"], GameState.stats["livraisons"], GameState.stats["cafes_vendus"]],
		"Véhicules : %d — logements : %d" % [GameState.vehicles.size(), GameState.home.get("owned", []).size()]]
	if GameState.lutte.has("force"):
		lines.append("Lutte : force %d" % int(GameState.lutte["force"]))
	if main.net_jobs and main.net_jobs.faction_title() != "":
		lines.append("Faction : " + main.net_jobs.faction_title())
	if main.city_hall and main.city_hall.has_id():
		lines.append("Carte d'identité : oui")
	for l in lines:
		_content.add_child(_note(l))
	if Net.online:
		_content.add_child(_label("Gestion du compte", 14, Color("e9ecef")))
		_content.add_child(_note("Conformément aux directives de confidentialité Apple, vous pouvez supprimer votre compte à tout moment."))
		_content.add_child(_button("Supprimer définitivement mon compte", func():
			_confirm_delete_account(), Color("d90429")))


func _confirm_delete_account() -> void:
	_unfocus()
	_app = "delete_account"
	for ch in _content.get_children():
		ch.queue_free()
	_entry = null
	_title.text = "Supprimer mon compte"
	_content.add_child(_label("ATTENTION : ACTION IRRÉVERSIBLE", 15, Color("e63946"), HORIZONTAL_ALIGNMENT_CENTER))
	_content.add_child(_note("La suppression de votre compte effacera définitivement :\n• Votre personnage et progression\n• Vos véhicules, propriétés et objets\n• Vos soldes bancaires et liquidités\n\nCette action est immédiate et irréversible."))
	_content.add_child(_button("Confirmer la suppression définitive", func():
		Net.delete_account()
		GameState.notify.emit("Demande de suppression envoyée au serveur...")
		close(), Color("d90429")))
	_content.add_child(_button("Annuler et revenir", func():
		_show("profile"), Color("6c757d")))


# --- Banque : solde, relevé, virement à un joueur (même absent) -------------------------------

func _bank_app() -> void:
	_title.text = "Banque — Mon compte"
	_content.add_child(_label("Solde du compte : %s" % GameState.fcfa(GameState.bank), 16, Color("7cfc9a"), HORIZONTAL_ALIGNMENT_CENTER))
	_content.add_child(_note("Liquide sur toi : %s. Dépôts et retraits au guichet d'une banque." % GameState.fcfa(GameState.money)))
	if Net.online and main.city_hall:
		_content.add_child(_label("Virement (gratuit, même si le joueur est absent)", 13, Color("e9ecef")))
		var to := _line("Pseudo du joueur")
		_content.add_child(to)
		_entry = _line("Montant en FCFA")
		_entry.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		_content.add_child(_entry)
		var amount_entry := _entry
		_content.add_child(_button("Envoyer le virement", func():
			_unfocus()
			main.city_hall.bank_transfer(to.text, amount_entry.text.strip_edges().to_int())
			_show("bank"), APPS[2][2]))
	else:
		_content.add_child(_note("Virements entre joueurs : en ligne."))
	_content.add_child(_label("Relevé de compte", 13, Color("e9ecef")))
	if GameState.bank_log.is_empty():
		_content.add_child(_note("Aucune opération."))
	for i in range(GameState.bank_log.size() - 1, -1, -1):
		_content.add_child(_note(str(GameState.bank_log[i])))


# --- Biznis : commerces à soi --------------------------------------------------------

func _biz_app() -> void:
	_title.text = "Biznis — Mes commerces"
	var cm = main.commerce
	if cm == null:
		return
	var list: Array = cm.owned_commerces()
	if list.is_empty():
		_content.add_child(_note("Tu n'as pas encore de commerce. Tangana, boutique, lavage, dibiterie : cherche les panneaux « À VENDRE » en ville (carte). Embauche une équipe, commande le stock, encaisse la recette."))
		return
	for i in list:
		var id: String = i
		var b: Dictionary = cm.biz(id)
		var d: Dictionary = main.housing.doors.get(id, {})
		var pname: String = cm.Housing.PROPERTIES[id]["name"]
		_content.add_child(_label(pname, 15, Color("ffd166")))
		_content.add_child(_note("Réputation %d/100 — équipe %d/%d — stock %d j — caisse %s
%s" % [int(b["rep"]), b["staff"].size(), cm.slots(id),
			int(floor(float(b["stock"]))), GameState.fcfa(main.housing.till(id)), cm.report_text(id)]))
		for e in b["staff"]:
			_content.add_child(_note("   %s %s — %s / jour" % [e["name"], cm.stars(int(e["skill"])), GameState.fcfa(e["wage"])]))
		if not d.is_empty():
			var dp: Vector3 = d["pos"]
			_content.add_child(_button("GPS vers " + pname, func():
				main.gps.set_waypoint(dp, pname)
				close(), Color("2d6a4f")))


# --- Oto : véhicules à soi ----------------------------------------------------------

func _cars_app() -> void:
	_title.text = "Oto — Mes véhicules"
	var dl = main.dealership
	if dl == null:
		return
	if dl.pos != Vector3.ZERO:
		var dp: Vector3 = dl.pos
		_content.add_child(_button("GPS vers la concession auto", func():
			main.gps.set_waypoint(dp, "Concession auto")
			close(), Color("6a4c93")))
	var rt = main.rental
	if rt != null and rt.active():
		var r: Dictionary = GameState.rental
		var left: float = rt.hours_left()
		_content.add_child(_note("Location : %s — %s, rends-la à une agence (Place de l'Indépendance, Gare de Dakar)." % [rt.FLEET[r["type"]][0],
			("encore " + rt._hours_text(left)) if left >= 0.0 else ("EN RETARD de " + rt._hours_text(-left))]))
		if rt._car_ok():
			var cp: Vector3 = rt.car.global_position
			_content.add_child(_button("GPS vers le véhicule loué", func():
				main.gps.set_waypoint(cp, "Véhicule loué")
				close(), Color("e63946")))
		var ap: Vector3 = rt._agency_pos(str(r.get("agency", "")))
		_content.add_child(_button("GPS vers l'agence de location", func():
			main.gps.set_waypoint(ap, "Agence de location")
			close(), Color("1d3557")))
	elif rt != null and not rt.agencies.is_empty():
		var ap0: Vector3 = rt.agencies[0][1]
		_content.add_child(_button("GPS vers la location de véhicules", func():
			main.gps.set_waypoint(ap0, "Location de véhicules")
			close(), Color("1d3557")))
	if dl.owned().is_empty():
		_content.add_child(_note("Tu n'as pas encore de véhicule. Achète une moto sportive ou une voiture de luxe à la concession de prestige (Plateau)."))
		return
	_content.add_child(_note("La dépanneuse t'amène ton véhicule pour %s. Un seul véhicule dehors à la fois. Fais le plein dans les stations-service." % GameState.fcfa(dl.DELIVERY)))
	for i in dl.owned().size():
		var idx: int = i
		var data: Dictionary = dl.owned()[i]
		var is_out: bool = idx == dl._out_idx and dl.out != null
		_content.add_child(_note("%s — essence %d %%%s" % [dl.vehicle_name(data), int(data.get("fuel", 100.0)), " (dehors)" if is_out else (" (à la fourrière)" if data.get("impound", false) else "")]))
		if is_out:
			_content.add_child(_button("Ranger ce véhicule", func():
				dl.store()
				_show("cars"), Color("bc6c25")))
		else:
			_content.add_child(_button("Faire venir (%s)" % GameState.fcfa(dl.DELIVERY), func():
				dl.bring(idx)
				close(), Color("2a9d8f")))


# --- Liggéey : offres d'emploi ------------------------------------------------------

func _jobs_app() -> void:
	_title.text = "Liggéey — Offres d'emploi"
	var emp = main.employment
	if emp == null:
		return
	_content.add_child(_note("Expérience : %d service(s)%s" % [emp.experience(), " — Permis de conduire ✔" if emp.has_permis() else " — Pas de permis"]))
	for id in emp.EMPLOYERS:
		var e: Dictionary = emp.EMPLOYERS[id]
		var st: Dictionary = emp.state(id)
		var status := ""
		if st["hired"]:
			status = "Embauché%s, réputation %d" % [" (chef)" if st["promoted"] else "", st["rep"]]
		else:
			var miss: String = emp.missing(id)
			status = "Recrute" if miss == "" else miss
		var jl := _label(e["job"], 15, Color("ffd166"))
		jl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(jl)
		_content.add_child(_note("%s (%s) — %s
Paie : %s — Horaires : %s
%s" % [e["name"], e["role"], e["place"], e["pay"], emp.hours_text(id), status]))
		if emp.bosses.has(id):
			var bp: Vector3 = emp.bosses[id]["pos"]
			var who: String = e["name"]
			_content.add_child(_button("GPS vers %s" % who, func():
				main.gps.set_waypoint(bp, who)
				close(), Color("6a4c93")))
	if emp._school_pos != Vector3.ZERO:
		var sp: Vector3 = emp._school_pos
		var sl := _label("Auto-école Teranga — permis de conduire", 15, Color("9bf6ff"))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(sl)
		_content.add_child(_button("GPS vers l'auto-école", func():
			main.gps.set_waypoint(sp, "Auto-école Teranga")
			close(), Color("1d3557")))


# --- Utilitaires -------------------------------------------------------------------------

func _unfocus() -> void:
	if _entry != null and is_instance_valid(_entry) and _entry.has_focus():
		_entry.release_focus()
	GameState.typing = false


func _label(text: String, size_px: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


func _note(text: String) -> Label:
	var l := _label(text, 12, Color("aaaaaa"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, color: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 14)
	b.clip_text = true
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = color.lightened(0.15) if state == "hover" else (color.darkened(0.2) if state == "pressed" else color)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func():
		if not _dragged:
			cb.call())
	return b


func _line(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 36)
	e.add_theme_font_size_override("font_size", 14)
	e.focus_entered.connect(func():
		GameState.typing = true
		call_deferred("_scroll_to_entry", e)
	)
	e.focus_exited.connect(func():
		GameState.typing = false
	)
	return e


func _scroll_to_entry(e: Control) -> void:
	if not e or not is_instance_valid(e) or not _scroll or not is_instance_valid(_scroll):
		return
	await get_tree().create_timer(0.06).timeout
	if not is_instance_valid(e) or not is_instance_valid(_scroll):
		return
	var rel_y := e.global_position.y - _scroll.global_position.y
	_scroll.scroll_vertical = clampi(int(_scroll.scroll_vertical + rel_y - 40), 0, 3000)
