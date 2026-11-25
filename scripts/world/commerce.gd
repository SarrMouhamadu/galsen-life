extends Node3D
## Gestion des commerces achetés (housing.gd : tangana, boutique de Sandaga, lavage auto, dibiterie).
## Un commerce ne tourne qu'avec des employés : on les embauche devant la porte parmi les candidats du jour
## (niveau, salaire demandé, réputation dans le quartier), on les paie chaque matin et on peut les renvoyer.
## Chaque matin (8 h), une journée de travail est comptée :
##   ventes = recette de base × équipe (nombre et niveau) × réputation × prix × stock
##   puis on retire les salaires, la taxe de la ville et ce qu'un employé malhonnête a pris dans la caisse.
## - Stock : en jours de marchandise, commandé au fournisseur (ou par le gérant tout seul, un peu plus cher).
##   Sans stock, presque rien à vendre et la réputation baisse.
## - Prix : bas (moins de marge, la clientèle revient), normal, élevé (plus de marge, la clientèle fuit).
## - Les employés progressent avec le temps (et demandent un meilleur salaire) ; deux jours de salaire
##   impayé et ils démissionnent. Voleur pris deux fois : un voisin donne son nom.
## État par commerce dans GameState.home["biz"][id] (sauvegardé avec le logement).

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")
const Furniture = preload("res://scripts/util/furniture.gd")
const Housing = preload("res://scripts/world/housing.gd")

## id → [métier, nombre de postes]
const ROLES := {
	"tangana_medina": ["Vendeur de café", 2],
	"boutique_sandaga": ["Vendeur de tissus", 3],
	"lavage_rebeuss": ["Laveur", 3],
	"dibiterie_gueule_tapee": ["Grilleur", 4],
	"resto_maiga": ["Cuisinier Maïga", 3],
}
const SALES_MULT := 2.5 ## ventes d'une équipe complète de niveau moyen ≈ 2,4 × la recette de base
const STOCK_COST := 0.6 ## prix d'un jour de stock (× recette de base)
const STOCK_MAX := 7.0
const AUTO_STOCK_EXTRA := 1.1 ## le gérant commande lui-même : 10 % plus cher
const TILL_DAYS := 7
const PRICES := {"bas": [0.85, 3.0, "Prix bas"], "normal": [1.0, 0.0, "Prix normaux"], "eleve": [1.2, -3.0, "Prix élevés"]}
const FIRST := ["Moussa", "Ibrahima", "Cheikh", "Mamadou", "Ousmane", "Abdou", "Pape", "Modou", "Aliou", "Babacar",
	"Fatou", "Awa", "Aminata", "Khady", "Ndèye", "Mariama", "Coumba", "Astou", "Rokhaya", "Sokhna"]
const LAST := ["Diop", "Ndiaye", "Fall", "Sow", "Ba", "Gueye", "Faye", "Sarr", "Mbaye", "Diallo", "Cissé", "Thiam", "Seck", "Ndour", "Kane", "Diouf"]
const VIEW_RANGE := 70.0

var main
var _shown := {} ## id → Node3D (employés et décor visibles devant le commerce)
var _view_t := 0.0


func _ready() -> void:
	GameState.new_day.connect(new_day)
	_migrate()
	if main.housing:
		main.housing._refresh()


# --- État -----------------------------------------------------------------------------

func biz(id: String) -> Dictionary:
	var all: Dictionary = GameState.home.get("biz", {})
	if not all.has(id):
		all[id] = {"staff": [], "stock": 2.0, "price": "normal", "rep": 50.0, "auto": false, "report": {}}
		GameState.home["biz"] = all
	return all[id]


func owned_commerces() -> Array:
	var list: Array = []
	for id in GameState.home.get("owned", []):
		if Housing.PROPERTIES.has(id) and Housing.is_commerce(id):
			list.append(id)
	return list


func income(id: String) -> int:
	return int(Housing.PROPERTIES[id]["income"])


func slots(id: String) -> int:
	return int(ROLES.get(id, ["Employé", 2])[1])


func role(id: String) -> String:
	return ROLES.get(id, ["Employé", 2])[0]


func wages(id: String) -> int:
	var w := 0
	for e in biz(id)["staff"]:
		w += int(e["wage"])
	return w


## Les commerces achetés avant les employés gardent leur recette : un premier employé et du stock offerts
func _migrate() -> void:
	var news: Array = []
	for id in owned_commerces():
		if not GameState.home.get("biz", {}).has(id):
			var b := biz(id)
			var e := _candidate(id, 0, 1)
			e["skill"] = 2
			e["honesty"] = 0.95
			e["wage"] = _wage(id, 2)
			b["staff"].append(e)
			b["stock"] = 3.0
			news.append(Housing.PROPERTIES[id]["name"])
	if not news.is_empty():
		GameState.notify.emit("Nouveau : tes commerces se gèrent ! %s embauche des employés et commande du stock devant la porte." % ", ".join(news))


# --- Candidats et employés ----------------------------------------------------------------

func _wage(id: String, skill: int) -> int:
	return int(snappedf(income(id) * 0.12 * (0.7 + 0.15 * skill), 50.0))


## Candidat n° k du jour pour ce commerce (le même toute la journée)
func _candidate(id: String, day: int, k: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s/%d/%d" % [id, day, k])
	var woman := rng.randf() < 0.5
	var first: String = FIRST[(10 if woman else 0) + rng.randi() % 10]
	var skill := 1 + int(floor(pow(rng.randf(), 1.4) * 5.0))
	var honesty := rng.randf_range(0.35, 1.0)
	var wage := int(snappedf(_wage(id, skill) * rng.randf_range(0.9, 1.15), 50.0))
	var seen := honesty + rng.randf_range(-0.18, 0.18)
	var hint := "Recommandé par l'imam du quartier" if seen > 0.85 else ("Sérieux, d'après son ancien patron" if seen > 0.65 else "Personne ne le connaît vraiment")
	return {"name": "%s %s" % [first, LAST[rng.randi() % LAST.size()]], "woman": woman, "skill": skill, "honesty": snappedf(honesty, 0.01),
		"wage": wage, "days": 0, "unpaid": 0, "thefts": 0, "hint": hint, "model": rng.randi() % 4}


func candidates(id: String) -> Array:
	var list: Array = []
	var names: Array = []
	for e in biz(id)["staff"]:
		names.append(e["name"])
	for k in 3:
		var c := _candidate(id, GameState.day, k + 2)
		if not c["name"] in names:
			list.append(c)
	return list


static func stars(n: int) -> String:
	return "★".repeat(n) + "☆".repeat(5 - n)


func hire(id: String, c: Dictionary) -> bool:
	var b := biz(id)
	if b["staff"].size() >= slots(id):
		GameState.notify.emit("L'équipe est complète (%d postes). Renvoie quelqu'un d'abord." % slots(id))
		return false
	for e in b["staff"]:
		if e["name"] == c["name"]:
			return false
	b["staff"].append(c.duplicate())
	_refresh_view(id)
	GameState.save_game()
	GameState.notify.emit("%s commence demain matin comme %s (%s / jour)." % [c["name"], role(id).to_lower(), GameState.fcfa(c["wage"])])
	return true


func fire(id: String, idx: int) -> void:
	var b := biz(id)
	if idx < 0 or idx >= b["staff"].size():
		return
	var e: Dictionary = b["staff"][idx]
	b["staff"].remove_at(idx)
	_refresh_view(id)
	GameState.save_game()
	GameState.notify.emit("%s rend son tablier : « %s »" % [e["name"], "Que Dieu te garde, patron." if int(e["thefts"]) == 0 else "C'est pas moi, je te jure !"])


func order_stock(id: String, days: int) -> bool:
	var b := biz(id)
	days = mini(days, int(STOCK_MAX - float(b["stock"])))
	if days <= 0:
		GameState.notify.emit("La réserve est pleine (%d jours de stock)." % int(STOCK_MAX))
		return false
	var cost := int(income(id) * STOCK_COST) * days
	if GameState.money + GameState.bank < cost:
		GameState.notify.emit("Le fournisseur veut %s (liquide + banque)." % GameState.fcfa(cost))
		return false
	var from_bank: int = maxi(0, cost - GameState.money)
	GameState.money -= cost - from_bank
	GameState.bank -= from_bank
	b["stock"] = float(b["stock"]) + days
	GameState.save_game()
	GameState.notify.emit("Le fournisseur livre %d jours de marchandise (-%s)." % [days, GameState.fcfa(cost)])
	return true


# --- La journée de travail (chaque matin) -------------------------------------------------

func new_day() -> void:
	_migrate()
	var rate: int = main.city_hall.tax_rate() if main.city_hall else 0
	var taxes := 0
	var lines: Array = []
	for id in owned_commerces():
		var r := simulate(id, rate, randi())
		taxes += int(r["tax"])
		lines.append("%s : %s%s" % [Housing.PROPERTIES[id]["name"], ("+" if int(r["net"]) >= 0 else ""), GameState.fcfa(r["net"])])
		for ev in r["events"]:
			GameState.notify.emit(ev)
	if taxes > 0:
		Net.city.pay_tax(taxes)
	if not lines.is_empty():
		GameState.notify.emit("Bilan d'hier — " + ", ".join(lines) + (" (taxe de la ville : %s, %d %%)" % [GameState.fcfa(taxes), rate] if taxes > 0 else ""))
	if main.housing:
		main.housing._refresh()


## Une journée pour un commerce : met à jour la caisse, le stock, la réputation et l'équipe
func simulate(id: String, tax_rate: int, rseed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rseed
	var b := biz(id)
	var inc := income(id)
	var staff: Array = b["staff"]
	var events: Array = []
	var pname: String = Housing.PROPERTIES[id]["name"]
	var t: Dictionary = GameState.home.get("till", {})
	# Le gérant commande tout seul s'il manque du stock
	if b["auto"] and float(b["stock"]) < 2.0 and not staff.is_empty():
		var cost := int(inc * STOCK_COST * AUTO_STOCK_EXTRA) * 2
		if int(t.get(id, 0)) >= cost:
			t[id] = int(t.get(id, 0)) - cost
			b["stock"] = float(b["stock"]) + 2.0
			events.append("%s : le gérant a commandé 2 jours de stock (%s pris dans la caisse)." % [pname, GameState.fcfa(cost)])
	var power := 0.0
	var skill_sum := 0
	for e in staff:
		power += 0.5 + 0.15 * int(e["skill"])
		skill_sum += int(e["skill"])
	var stock := float(b["stock"])
	var stock_frac := clampf(stock, 0.0, 1.0)
	var price: Array = PRICES.get(b["price"], PRICES["normal"])
	var rep := float(b["rep"])
	var sales := 0
	if not staff.is_empty():
		var used := minf(1.0, stock)
		b["stock"] = stock - used
		sales = int(inc * SALES_MULT * minf(1.0, power / slots(id)) * (0.6 + 0.8 * rep / 100.0) * float(price[0]) * (0.15 + 0.85 * stock_frac))
	# Réputation : la qualité de l'équipe la tire vers le haut, les ruptures de stock et les prix élevés vers le bas
	if staff.is_empty():
		rep -= 5.0
		events.append("%s est resté fermé hier : personne pour tenir le commerce. Embauche quelqu'un !" % pname)
	else:
		var target := 30.0 + 12.0 * float(skill_sum) / staff.size()
		rep += (target - rep) * 0.2 + float(price[1])
		if stock_frac < 1.0:
			rep -= 8.0
			events.append("%s : rupture de stock ! Les clients repartent les mains vides. Commande au fournisseur." % pname)
		elif float(b["stock"]) < 1.0:
			events.append("%s : plus de stock pour aujourd'hui, pense à commander." % pname)
	b["rep"] = clampf(rep, 0.0, 100.0)
	# Vols dans la caisse
	var theft := 0
	for e in staff:
		if sales > 0 and rng.randf() < (1.0 - float(e["honesty"])) * 0.35:
			var took := int(sales * rng.randf_range(0.05, 0.15))
			theft += took
			e["thefts"] = int(e["thefts"]) + 1
			if int(e["thefts"]) >= 2:
				events.append("%s : il manque %s dans la caisse. Un voisin a vu %s se servir..." % [pname, GameState.fcfa(took), e["name"]])
			else:
				events.append("%s : il manque %s dans la caisse. Qui a fait ça ?" % [pname, GameState.fcfa(took)])
	var tax := sales * tax_rate / 100
	var pay := wages(id)
	var net := sales - theft - tax - pay
	var till := int(t.get(id, 0)) + net
	# Salaires : la caisse, puis la banque ; sinon les employés ne sont pas payés
	if till < 0:
		var missing := -till
		till = 0
		if GameState.bank >= missing:
			GameState.bank -= missing
			events.append("%s : la caisse ne suffisait pas, %s de salaires payés depuis ta banque." % [pname, GameState.fcfa(missing)])
		else:
			GameState.bank = 0
			for e in staff:
				e["unpaid"] = int(e["unpaid"]) + 1
			events.append("%s : tes employés n'ont pas été payés !" % pname)
	else:
		for e in staff:
			e["unpaid"] = 0
	t[id] = mini(till, inc * 3 * TILL_DAYS)
	GameState.home["till"] = t
	# Départs, progression
	for i in range(staff.size() - 1, -1, -1):
		var e: Dictionary = staff[i]
		if int(e["unpaid"]) >= 2:
			staff.remove_at(i)
			events.append("%s démissionne : « Deux jours sans salaire, patron, je ne peux pas. »" % e["name"])
			continue
		e["days"] = int(e["days"]) + 1
		if int(e["days"]) % 8 == 0 and int(e["skill"]) < 5:
			e["skill"] = int(e["skill"]) + 1
			e["wage"] = int(snappedf(int(e["wage"]) * 1.12, 50.0))
			events.append("%s progresse (%s) et passe à %s / jour." % [e["name"], stars(int(e["skill"])), GameState.fcfa(e["wage"])])
	b["report"] = {"day": GameState.day - 1, "sales": sales, "wages": pay, "tax": tax, "theft": theft, "net": net}
	_refresh_view(id)
	return {"net": net, "tax": tax, "sales": sales, "events": events}


# --- Menus -------------------------------------------------------------------------------

func menu(id: String) -> void:
	_migrate()
	var b := biz(id)
	var p: Dictionary = Housing.PROPERTIES[id]
	var choices: Array = []
	var till: int = main.housing.till(id)
	if till > 0:
		choices.append(["Encaisser la recette (%s)" % GameState.fcfa(till), func(): main.housing._collect(id)])
	choices.append(["Équipe : %d/%d %s(s) — salaires %s / jour" % [b["staff"].size(), slots(id), role(id).to_lower(), GameState.fcfa(wages(id))], func(): staff_menu(id)])
	var day_cost := int(income(id) * STOCK_COST)
	choices.append(["Stock : %.0f jour(s) — commander (%s le jour)" % [floor(float(b["stock"])), GameState.fcfa(day_cost)], func(): stock_menu(id)])
	choices.append(["%s — changer" % PRICES[b["price"]][2], func(): price_menu(id)])
	choices.append(["Revendre (%s)" % GameState.fcfa(main.housing._resale(id)), func(): main.housing._confirm_sell(id)])
	main.hud.show_choices("%s\nRéputation %d/100 — %s" % [p["name"], int(b["rep"]), report_text(id)], choices, func(): pass)


func report_text(id: String) -> String:
	var r: Dictionary = biz(id)["report"]
	if r.is_empty():
		return "premier bilan demain matin"
	var s := "hier : ventes %s, salaires %s" % [GameState.fcfa(r["sales"]), GameState.fcfa(r["wages"])]
	if int(r["tax"]) > 0:
		s += ", taxe %s" % GameState.fcfa(r["tax"])
	if int(r["theft"]) > 0:
		s += ", volé %s" % GameState.fcfa(r["theft"])
	return s + " → %s" % GameState.fcfa(r["net"])


func staff_menu(id: String) -> void:
	var b := biz(id)
	var choices: Array = []
	for i in b["staff"].size():
		var idx: int = i
		var e: Dictionary = b["staff"][i]
		choices.append(["Renvoyer %s %s — %s / jour, %d jour(s) ici" % [e["name"], stars(int(e["skill"])), GameState.fcfa(e["wage"]), int(e["days"])], func(): _confirm_fire(id, idx)])
	if b["staff"].size() < slots(id):
		for c in candidates(id):
			var cand: Dictionary = c
			choices.append(["Embaucher %s %s — %s / jour (%s)" % [cand["name"], stars(int(cand["skill"])), GameState.fcfa(cand["wage"]), cand["hint"]], func(): hire(id, cand)])
	main.hud.show_choices("Équipe — %s\nNiveau ★ : plus de ventes et une meilleure réputation. Nouveaux candidats chaque matin." % Housing.PROPERTIES[id]["name"], choices, func(): pass)


func _confirm_fire(id: String, idx: int) -> void:
	var e: Dictionary = biz(id)["staff"][idx]
	main.hud.show_choices("Renvoyer %s ?" % e["name"], [["Oui, renvoyer", func(): fire(id, idx)], ["Non", func(): pass]], func(): pass)


func stock_menu(id: String) -> void:
	var b := biz(id)
	var day_cost := int(income(id) * STOCK_COST)
	var choices: Array = []
	for d in [1, 3, 7]:
		var days: int = d
		choices.append(["Commander %d jour(s) — %s" % [days, GameState.fcfa(day_cost * days)], func(): order_stock(id, days)])
	choices.append(["%s : le gérant commande tout seul (+10 %%, pris dans la caisse)" % ("Activé" if b["auto"] else "Désactivé"), func():
		b["auto"] = not b["auto"]
		GameState.save_game()
		GameState.notify.emit("Commande automatique du stock : %s." % ("activée" if b["auto"] else "désactivée"))])
	main.hud.show_choices("Stock — %.1f jour(s) en réserve (max %d)" % [float(b["stock"]), int(STOCK_MAX)], choices, func(): pass)


func price_menu(id: String) -> void:
	var b := biz(id)
	var choices: Array = []
	for k in PRICES:
		var key: String = k
		var pr: Array = PRICES[key]
		var desc: String = {"bas": "les clients reviennent, la réputation monte", "normal": "équilibré", "eleve": "+20 % de marge, la réputation baisse"}[key]
		choices.append(["%s%s — %s" % ["✔ " if b["price"] == key else "", pr[2], desc], func():
			b["price"] = key
			GameState.save_game()])
	main.hud.show_choices("Prix pratiqués", choices, func(): pass)


func sold(id: String) -> void:
	var all: Dictionary = GameState.home.get("biz", {})
	all.erase(id)
	_hide(id)


# --- Employés visibles devant le commerce ------------------------------------------------------

func _process(delta: float) -> void:
	_view_t -= delta
	if _view_t > 0.0 or main.housing == null:
		return
	_view_t = 1.5
	var pp: Vector3 = main.player.global_position
	var open := GameState.game_minutes >= 7.0 * 60.0 and GameState.game_minutes < 23.0 * 60.0
	for id in main.housing.doors:
		if not Housing.is_commerce(id):
			continue
		var d: Dictionary = main.housing.doors[id]
		var near: bool = Vector2(pp.x - d["pos"].x, pp.z - d["pos"].z).length() < VIEW_RANGE and main.interiors.inside == ""
		var want: bool = near and open and main.housing.owned(id)
		if want and not _shown.has(id):
			_show(id)
		elif not want and _shown.has(id):
			_hide(id)


func _refresh_view(id: String) -> void:
	if _shown.has(id):
		_hide(id)


func _hide(id: String) -> void:
	if _shown.has(id):
		if is_instance_valid(_shown[id]):
			_shown[id].queue_free()
		_shown.erase(id)


func _show(id: String) -> void:
	var d: Dictionary = main.housing.doors[id]
	var n: Vector3 = d["n"]
	var root := Node3D.new()
	add_child(root)
	root.global_position = d["pos"]
	root.rotation.y = atan2(-n.x, -n.z) # +Z du repère vers la rue
	_shown[id] = root
	# Décor devant la porte (le côté +Z regarde la rue)
	match id:
		"tangana_medina":
			Furniture.place(root, "painted_wooden_table", Vector3(1.8, 0, 1.2), 0.0, true, 0.6)
			for x in [0.9, 2.7]:
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x, 0, 2.2), PI)
		"resto_maiga":
			Furniture.place(root, "painted_wooden_table", Vector3(1.8, 0, 1.2), 0.0, true, 0.6)
			for x in [0.9, 2.7]:
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x, 0, 2.2), PI)
			Mk.box(root, Vector3(1.3, 0.85, 0.6), Vector3(-1.6, 0.42, 1.0), Color("2b2b2b"), true)
			Mk.box(root, Vector3(0.45, 0.12, 0.3), Vector3(-1.4, 0.91, 1.0), Color("e9c46a"))
			Mk.box(root, Vector3(0.4, 0.12, 0.25), Vector3(-1.85, 0.91, 1.0), Color("8b0000"))
		"dibiterie_gueule_tapee":
			for x in [-2.6, 2.6]:
				Furniture.place(root, "round_wooden_table_01", Vector3(x, 0, 2.0))
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x - 0.7, 0, 2.0), PI / 2.0)
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x + 0.7, 0, 2.0), -PI / 2.0)
			Mk.box(root, Vector3(1.2, 0.8, 0.5), Vector3(1.2, 0.4, 0.8), Color("2b2b2b"), true) # grill
			Mk.box(root, Vector3(1.1, 0.05, 0.4), Vector3(1.2, 0.83, 0.8), Color("b5651d"))
		"boutique_sandaga":
			Furniture.place(root, "steel_frame_shelves_01", Vector3(-1.8, 0, 0.6))
			for k in 6:
				Mk.box(root, Vector3(0.5, 0.12, 0.35), Vector3(-2.1 + (k % 3) * 0.32, 0.65 + (k / 3) * 0.5, 0.6), Color.from_hsv(float(k) / 6.0, 0.7, 0.85))
		"lavage_rebeuss":
			Mk.box(root, Vector3(0.5, 0.6, 0.5), Vector3(2.0, 0.3, 1.2), Color("1d3557")) # bidons et seau
			Mk.cyl(root, 0.18, 0.15, 0.35, Vector3(2.7, 0.18, 1.3), Color("e63946"), false, 8)
	# Les employés à leur poste
	var staff: Array = biz(id)["staff"]
	for i in mini(staff.size(), 3):
		var e: Dictionary = staff[i]
		var models: Array = RealCharacter.WOMEN if e["woman"] else RealCharacter.MEN
		var h := Node3D.new()
		root.add_child(h)
		h.position = Vector3(-0.8 + i * 1.3, 0, 1.0 + (i % 2) * 0.5)
		var c = RealCharacter.create(h, models[int(e["model"]) % models.size()], hash(e["name"]) % 997)
		c.play_clip("talk" if i % 2 == 0 else "idle", 0.0)
		Mk.label(h, "%s\n%s" % [e["name"], role(id)], Vector3(0, 2.15, 0), 18, Color("f1faee"))
