extends Node3D
## Intérieurs visitables : banques, restaurants, boutiques des stations-service, hôpitaux, commissariats,
## supermarchés. Devant la porte : [E] Entrer. Chaque type a une salle meublée (construite à la demande,
## sous la ville) avec un comptoir où l'on agit : compte en banque, repas, achats, soins, amendes.
## Les garages se font en voiture : on s'arrête devant pour repeindre la voiture (et semer la police).

const Mk = preload("res://scripts/util/mk.gd")
const Furniture = preload("res://scripts/util/furniture.gd")

const DOOR_RANGE := 2.6
const GARAGE_RANGE := 7.0
const ROOM := Vector3(14, 4, 12)
const BASE := Vector3(0, -120, 0)
const W_ROOM := 7.0 ## demi-largeur de la salle (ROOM.x / 2)
## Lit (comptoir des logements) quand il n'est pas au fond de la salle
const BED_AT := {"home_loft": Vector3(5.2, 0, 1.0)}
## Loft (world/loft/loft.glb, tools/convert_interior.py) : décalage qui centre son rez-de-chaussée dans la salle
const LOFT_OFFSET := Vector3(-3.04, 0, -1.07)
const TITLES := {"banque": "Banque", "restaurant": "Restaurant", "station": "Boutique de la station",
	"hopital": "Hôpital", "police": "Commissariat", "boutique": "Magasin"}
const FLOORS := {"banque": Color("d8d2c4"), "restaurant": Color("8d6748"), "station": Color("e5e5e5"),
	"hopital": Color("e9f1f2"), "police": Color("b9b3a6"), "boutique": Color("dcdcdc")}
const WALLS := {"banque": Color("f1ede4"), "restaurant": Color("e9c46a"), "station": Color("f8f9fa"),
	"hopital": Color("f4fbfc"), "police": Color("d6dde6"), "boutique": Color("f6f1e7")}
## Plats sénégalais : [nom, prix, satiété]
const DISHES := [["Thiéboudienne", 2500, 60], ["Yassa poulet", 2000, 50], ["Mafé", 2000, 50], ["Thiéré (couscous de mil)", 1500, 40],
	["Dibi (viande grillée)", 1500, 35], ["Sandwich Maïga (pain brochette & spaghetti)", 1000, 35], ["Omelette Maïga complète", 800, 25],
	["Pastels (beignets de poisson)", 500, 12], ["Jus de bissap", 300, 5], ["Café Touba", 150, 3]]
const STATION_ITEMS := [["Bouteille d'eau", 300, 4], ["Sandwich", 1000, 25], ["Café", 300, 3], ["Biscuits", 250, 8], ["Bidon d'huile moteur", 3500, 0], ["Carte de recharge téléphone", 1000, 0]]
const SHOP_ITEMS := [["Sac de riz (5 kg)", 3000, 0], ["Bouteille d'eau", 300, 4], ["Pain", 150, 15], ["Lait caillé", 500, 15], ["Savon", 300, 0], ["Huile (1 L)", 1300, 0], ["Thé vert", 500, 0]]

var main
var inside := ""            ## type de l'intérieur où l'on est ("" = dehors)
var _place := ""            ## nom du lieu visité
var _rooms := {}            ## type → origine de la salle
var _doors: Array = []      ## [nom, type, position de la porte, normale vers le bâtiment]
var _sign: Label3D
var _last_door: Array = [] ## porte par laquelle on est entré (pour ressortir au bon endroit)
## Braquage d'une station ou d'une boutique : le caissier remplit le sac pendant ROB_TIME secondes
## (alarme silencieuse), puis on sort avec le butin et 3 étoiles : les policiers joueurs le voient sur leur GPS
const ROB_TIME := 15.0
const ROB_LOOT := {"station": [15000, 30000], "boutique": [8000, 20000]}
var robbery_status := ""
var _rob_t := -1.0
var _rob_place := ""
var _robbed := {} ## lieu → jour du dernier braquage (un par jour)


func _ready() -> void:
	var city = main.city
	for nm in city.services:
		if not city.places.has(nm):
			continue
		var info: Array = city.place_info[nm]
		var n := Vector3(info[3], 0, info[4])
		_doors.append([nm, city.services[nm], city.places[nm] + n * 1.3, n])


func _process(delta: float) -> void:
	if _rob_t >= 0.0:
		_update_robbery(delta)
	# Ramené dehors sans passer par la porte (arrestation, malaise...) : on quitte l'intérieur
	if inside != "" and main.player.global_position.y > BASE.y + 40.0:
		inside = ""
		main.player.interior_door = Vector3.ZERO
		main.sun.visible = true


## Test : entre dans le premier lieu du type demandé
func enter_first(kind: String) -> void:
	for d in _doors:
		if d[1] == kind:
			_enter(d)
			return


# --- Fournisseur d'actions pour le joueur ----------------------------------------------

func get_hint() -> String:
	var p = main.player
	if inside != "":
		if p.riding != null or p.current_vehicle != null or not _rooms.has(inside):
			return "" # (entreprises : enterprises.gd gère ses locaux)
		var o: Vector3 = _rooms[inside]
		if p.global_position.distance_to(o + Vector3(0, 0, ROOM.z / 2.0 - 1.0)) < 2.2:
			return "Sortir"
		if p.global_position.distance_to(o + BED_AT.get(inside, Vector3(0, 0, -ROOM.z / 2.0 + 2.6))) < 2.8:
			return _counter_hint()
		if inside == "home_villa" and p.global_position.distance_to(o + Vector3(ROOM.x / 2.0 - 1.4, 0, -1.5)) < 2.2:
			return "Coffre-fort"
		return ""
	if p.current_vehicle != null:
		var g = _nearest_door(p.current_vehicle.global_position, GARAGE_RANGE, "garage")
		return "Garage : réparer, repeindre" if g != null else ""
	if p.riding != null:
		return ""
	var d = _nearest_door(p.global_position, DOOR_RANGE, "")
	return ("Entrer : " + d[0]) if d != null else ""


func try_interact() -> bool:
	var h := get_hint()
	if h == "":
		return false
	var p = main.player
	if inside != "":
		if h == "Sortir" and main.prison and main.prison.jailed():
			GameState.notify.emit("La porte de la cellule est fermée : encore %d s (caution à l'accueil)." % int(ceil(GameState.jail)))
		elif h == "Sortir":
			_exit()
		elif h == "Coffre-fort":
			main.housing.safe_menu()
		else:
			_counter_menu()
		return true
	if p.current_vehicle != null:
		var v = p.current_vehicle
		var repair := int(ceil(100.0 - v.condition)) * 60
		var covered: bool = main.dealership != null and main.dealership.out_insured(v)
		if covered:
			repair = 0
		var gchoices: Array = [["Repeindre la voiture — 5 000 FCFA", func(): _repaint(v)]]
		if v.condition < 99.0:
			gchoices.push_front(["Réparer le moteur (état %d %%) — %s" % [int(v.condition), "gratuit (assurance)" if covered else GameState.fcfa(repair)], func():
				if GameState.spend(repair):
					v.condition = 100.0
					GameState.notify.emit("Le mécanicien : « Moteur réparé, ça roule comme neuf ! » (%s)" % ("pris en charge par ton assurance" if covered else "-" + GameState.fcfa(repair)))
				else:
					GameState.notify.emit("La réparation coûte %s." % GameState.fcfa(repair))])
		main.hud.show_choices("Garage mécanique", gchoices, func(): pass)
		return true
	var d = _nearest_door(p.global_position, DOOR_RANGE, "")
	_enter(d)
	return true


func _nearest_door(pos: Vector3, rng: float, only: String) -> Variant:
	var best = null
	var bd := rng
	for d in _doors:
		if only != "" and d[1] != only:
			continue
		if only == "" and d[1] == "garage":
			continue
		var dist := Vector2(pos.x - d[2].x, pos.z - d[2].z).length()
		if dist < bd and absf(pos.y - d[2].y) < 3.0:
			bd = dist
			best = d
	return best


# --- Entrer et sortir ----------------------------------------------------------------

## Entrée dans un intérieur qui n'est pas un service (logement)
func enter_custom(place_name: String, kind: String, door: Vector3, n: Vector3) -> void:
	_enter([place_name, kind, door, n])


func _enter(d: Array) -> void:
	var kind: String = d[1]
	_last_door = d
	main.hud.fade_through(func():
		var o := _room(kind)
		inside = kind
		_place = d[0]
		main.player.interior_door = d[2] - d[3] * 2.4
		if _sign != null:
			_sign.text = d[0]
		main.player.global_position = o + Vector3(0, 0.3, ROOM.z / 2.0 - 2.2)
		main.player.velocity = Vector3.ZERO
		main.player.model.rotation.y = 0.0
		main.camera_rig.yaw = 0.0
		main.camera_rig.global_position = main.player.global_position + Vector3(0, 1.6, 0)
		main.sun.visible = false
		GameState.notify.emit("Bienvenue : %s." % d[0]))


func _exit() -> void:
	var d = _last_door if not _last_door.is_empty() else null
	if inside.begins_with("home_") and main.housing:
		main.housing.left_home()
	main.hud.fade_through(func():
		inside = ""
		main.player.interior_door = Vector3.ZERO
		main.sun.visible = true
		if d != null:
			var out: Vector3 = d[2] - d[3] * 2.4
			main.player.global_position = Vector3(out.x, maxf(out.y, 0.3), out.z)
			main.camera_rig.yaw = atan2(d[3].x, d[3].z)
			main.player.model.rotation.y = main.camera_rig.yaw
			main.camera_rig.global_position = main.player.global_position + Vector3(0, 1.6, 0))


## Éclairage intérieur (appelé par main._update_daylight quand on est dedans)
func apply_light(env: Environment) -> void:
	env.ambient_light_energy = 0.75
	env.ambient_light_color = Color("fff1dd")
	env.fog_density = 0.0


# --- Comptoirs ---------------------------------------------------------------------------

func _counter_hint() -> String:
	if inside.begins_with("home_"):
		return "Ton lit : dormir, sauvegarder"
	match inside:
		"banque":
			return "Guichet : compte en banque"
		"restaurant":
			return "Commander un plat"
		"station", "boutique":
			return "Acheter"
		"hopital":
			return "Accueil : se faire soigner"
		"police":
			return "Accueil du commissariat"
	return ""


func _counter_menu() -> void:
	var hud = main.hud
	var choices: Array = []
	if inside.begins_with("home_"):
		main.housing.bed_menu()
		return
	match inside:
		"banque":
			for a in [1000, 5000, 20000]:
				var amount: int = a
				choices.append(["Déposer %s" % GameState.fcfa(amount), func(): _deposit(amount)])
			choices.append(["Déposer tout mon argent liquide", func(): _deposit(GameState.money)])
			for a in [1000, 5000, 20000]:
				var amount2: int = a
				choices.append(["Retirer %s" % GameState.fcfa(amount2), func(): _withdraw(amount2)])
			hud.show_choices("%s — sur ton compte : %s" % [_place, GameState.fcfa(GameState.bank)], choices, func(): pass)
		"restaurant":
			for it in DISHES:
				var item: Array = it
				choices.append(["%s — %s" % [item[0], GameState.fcfa(item[1])], func(): _buy(item)])
			if main.cooking and main.cooking.resale_total()[0] > 0:
				var t: Array = main.cooking.resale_total()
				choices.append(["Vendre tes %d plats faits maison — %s" % [t[0], GameState.fcfa(t[1])], main.cooking.sell_dishes])
			hud.show_choices("%s — « Lu ngay lekk ? » (qu'est-ce que tu manges ?)" % _place, choices, func(): pass)
		"station", "boutique":
			var list: Array = STATION_ITEMS if inside == "station" else SHOP_ITEMS
			for it in list:
				var item: Array = it
				choices.append(["%s — %s" % [item[0], GameState.fcfa(item[1])], func(): _buy(item)])
			if _rob_t < 0.0:
				choices.append(["Braquer la caisse (crime : la police sera prévenue)", _confirm_rob])
			hud.show_choices(_place, choices, func(): pass)
		"hopital":
			choices.append(["Consultation et soins complets — %s" % GameState.fcfa(3000), func():
				if GameState.spend(3000):
					GameState.health = 100.0
					GameState.notify.emit("Le docteur te soigne. Tu es en pleine forme !")
				else:
					GameState.notify.emit("Il faut 3 000 FCFA pour la consultation.")])
			choices.append(["Pharmacie : médicaments — %s" % GameState.fcfa(1500), func():
				if GameState.spend(1500):
					GameState.health = minf(100.0, GameState.health + 30.0)
					GameState.notify.emit("Tu prends tes médicaments (+30 santé).")
				else:
					GameState.notify.emit("Pas assez d'argent pour les médicaments.")])
			hud.show_choices(_place, choices, func(): pass)
		"police":
			if main.prison and main.prison.jailed():
				choices.append(["Payer la caution — %s" % GameState.fcfa(main.prison.bail()), main.prison.pay_bail])
				choices.append(["Attendre la fin de la garde à vue", func(): pass])
				hud.show_choices(_place, choices, func(): pass)
				return
			if GameState.wanted > 0:
				var fine := 5000 * GameState.wanted
				choices.append(["Se rendre et payer l'amende — %s" % GameState.fcfa(fine), func():
					if GameState.spend(fine):
						GameState.clear_wanted()
						main.police.reset_all()
						GameState.notify.emit("Tu paies ton amende. L'agent : « Que je ne te revoie plus ! »")
					else:
						GameState.notify.emit("Tu n'as pas de quoi payer l'amende...")])
			if main.dealership:
				for i in main.dealership.impounded():
					var idx: int = i
					choices.append(["Fourrière : récupérer ton véhicule (%s) — %s" % [main.dealership.vehicle_name(GameState.vehicles[idx]).to_lower(), GameState.fcfa(main.dealership.IMPOUND_FEE)], func(): main.dealership.release(idx)])
			choices.append(["Porter plainte", func():
				GameState.notify.emit("L'agent note ta plainte : « On va s'en occuper, inch'Allah. »")])
			hud.show_choices(_place, choices, func(): pass)


## Mobilier des logements : lit au fond, puis selon le standing
func _furnish_home(root: Node3D, kind: String, bz: float) -> void:
	var big := kind in ["home_appartement", "home_villa"]
	var bw := 2.0 if big else 1.4
	var W := ROOM.x / 2.0
	# Lit : cadre en bois, matelas, drap, oreillers ; tables de chevet et cadre au-dessus
	Mk.box(root, Vector3(bw + 0.1, 0.3, 2.15), Vector3(0, 0.15, bz + 0.3), Color("5b4636"), true)
	Mk.box(root, Vector3(bw + 0.1, 1.0, 0.08), Vector3(0, 0.5, bz - 0.78), Color("4a3728"))
	Mk.box(root, Vector3(bw - 0.1, 0.22, 2.0), Vector3(0, 0.41, bz + 0.3), Color("f1f1f1"))
	Mk.box(root, Vector3(bw - 0.06, 0.06, 1.3), Vector3(0, 0.54, bz + 0.68), [Color("e76f51"), Color("2a9d8f"), Color("264653"), Color("e9c46a")][kind.length() % 4])
	for px in ([-0.45, 0.45] if big else [0.0]):
		Mk.box(root, Vector3(0.6 if big else 0.55, 0.13, 0.36), Vector3(px, 0.6, bz - 0.45), Color("ffffff"))
	for sx in ([-1.0, 1.0] if big else [1.0]):
		Furniture.place(root, "ClassicNightstand_01", Vector3(sx * (bw / 2.0 + 0.45), 0, bz - 0.55))
	Furniture.picture(root, Vector3(0, 1.85, -ROOM.z / 2.0 + 0.11), 0.0, 0.8)
	Furniture.place(root, "ceiling_fan", Vector3(0, ROOM.y, 0.5), 0.0, false)
	match kind:
		"home_chambre":
			# Natte au sol, vieux poste de télévision, chaises en plastique, ventilateur sur pied, seau
			Mk.box(root, Vector3(2.2, 0.03, 1.6), Vector3(-3.5, 0.02, 1.0), Color("d4a373"))
			for k in 6:
				Mk.box(root, Vector3(2.2, 0.035, 0.08), Vector3(-3.5, 0.025, 0.4 + k * 0.24), Color("bc6c25"))
			Furniture.place(root, "ClassicNightstand_01", Vector3(-W + 0.45, 0, -1.2), PI / 2.0)
			Furniture.place(root, "Television_01", Vector3(-W + 0.45, 0.7, -1.2), PI / 2.0, false)
			Furniture.place(root, "plastic_monobloc_chair_01", Vector3(-3.6, 0, -1.4), -PI / 2.0)
			Furniture.place(root, "plastic_monobloc_chair_01", Vector3(-2.4, 0, 2.8), PI * 0.8)
			Mk.cyl(root, 0.04, 0.04, 1.3, Vector3(3.0, 0.65, -2.0), Color("dddddd"), false, 6)
			Mk.cyl(root, 0.35, 0.35, 0.12, Vector3(3.0, 1.35, -2.0), Color("9ec1cf"), false, 12).rotation.x = PI / 2.0
			Mk.cyl(root, 0.2, 0.16, 0.35, Vector3(4.5, 0.18, 2.5), Color("2a9d8f"), false, 10)
			Furniture.place(root, "drawer_cabinet", Vector3(W - 0.35, 0, 1.0), -PI / 2.0)
			# Coin repas : petite table ronde et chaises, théière sur le réchaud (ataya)
			Furniture.place(root, "round_wooden_table_01", Vector3(3.0, 0, 2.2), 0.0, true, 0.6)
			Furniture.place(root, "plastic_monobloc_chair_01", Vector3(3.0, 0, 3.1), PI)
			Furniture.place(root, "plastic_monobloc_chair_01", Vector3(2.1, 0, 2.2), PI / 2.0)
			Mk.cyl(root, 0.12, 0.14, 0.12, Vector3(-3.0, 0.06, 1.0), Color("495057"), false, 10)
			Mk.cyl(root, 0.06, 0.08, 0.12, Vector3(-3.0, 0.18, 1.0), Color("adb5bd"), false, 10)
			Furniture.picture(root, Vector3(-W + 0.11, 1.9, 2.5), PI / 2.0, 0.7)
		"home_studio", "home_appartement", "home_villa":
			# Salon : meuble télé avec écran plat contre le mur, canapé face à la télé, table basse sur un tapis
			var tv_w := 1.2 if kind == "home_studio" else (1.6 if kind == "home_appartement" else 2.0)
			Furniture.place(root, "CoffeeTable_01", Vector3(-W + 0.6, 0, 0), PI / 2.0)
			Furniture.flat_tv(root, Vector3(-W + 0.55, 0.6, 0), PI / 2.0, tv_w)
			Furniture.place(root, "sofa_02" if kind == "home_villa" else "Sofa_01", Vector3(-2.4, 0, 0), -PI / 2.0)
			Mk.box(root, Vector3(3.0, 0.02, 3.4), Vector3(-4.2, 0.01, 0), Color("9d0208") if big else Color("457b9d"))
			Furniture.place(root, "CoffeeTable_01", Vector3(-4.0, 0, 0), PI / 2.0, true, 0.75)
			if big:
				Furniture.place(root, "ArmChair_01", Vector3(-4.0, 0, 2.3), PI)
				Furniture.place(root, "ArmChair_01", Vector3(-4.0, 0, -2.3), 0.0)
			Furniture.place(root, "drawer_cabinet", Vector3(-4.6, 0, -ROOM.z / 2.0 + 0.35))
			# Cuisine : réfrigérateur, plan de travail, cuisinière
			Mk.box(root, Vector3(0.75, 1.8, 0.7), Vector3(W - 0.5, 0.9, 4.6), Color("f8f9fa"), true)
			Mk.box(root, Vector3(0.04, 0.5, 0.02), Vector3(W - 0.88, 1.2, 4.35), Color("adb5bd"))
			Mk.box(root, Vector3(0.65, 0.9, 1.8), Vector3(W - 0.45, 0.45, 2.9), Color("e9ecef"), true)
			Mk.box(root, Vector3(0.7, 0.04, 1.85), Vector3(W - 0.45, 0.92, 2.9), Color("6c757d"))
			Furniture.place(root, "electric_stove", Vector3(W - 0.4, 0, 1.55), -PI / 2.0)
			if big:
				# Salle à manger : table en bois et quatre chaises
				Furniture.place(root, "painted_wooden_table", Vector3(3.0, 0, 1.4))
				for c in [[-0.5, 0.75, PI], [0.5, 0.75, PI], [-0.5, -0.75, 0.0], [0.5, -0.75, 0.0]]:
					Furniture.place(root, "dining_chair_02", Vector3(3.0 + c[0], 0, 1.4 + c[1]), c[2])
				for pz in [-4.6, 4.6]:
					Mk.cyl(root, 0.25, 0.2, 0.5, Vector3(-W + 0.6, 0.25, pz), Color("a0522d"), false, 10)
					Mk.sphere(root, 0.55, Vector3(-W + 0.6, 1.0, pz), Color("2d6a4f"))
			else:
				Furniture.place(root, "round_wooden_table_01", Vector3(3.2, 0, 1.4), 0.0, true, 0.6)
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(3.2, 0, 2.3), PI)
	if kind == "home_villa":
		# Bassin du patio et coffre-fort
		Mk.box(root, Vector3(4.0, 0.12, 3.0), Vector3(3.5, 0.06, -2.4), Color("e9ecef"), true)
		Mk.box(root, Vector3(3.4, 0.05, 2.4), Vector3(3.5, 0.14, -2.4), Color(0.15, 0.55, 0.85, 0.9))
		Mk.box(root, Vector3(0.7, 0.9, 0.6), Vector3(W - 0.5, 0.45, -1.5), Color("495057"), true)
		Mk.cyl(root, 0.1, 0.1, 0.05, Vector3(W - 0.85, 0.55, -1.5), Color("d4af37"), false, 12).rotation.z = PI / 2.0
		Mk.label(root, "COFFRE-FORT", Vector3(W - 0.9, 1.2, -1.5), 22, Color("d4af37"))


## Loft du Plateau : vrai modèle 3D (« free Loft 17 », dasy444, CC BY), fermé par des murs sombres,
## porte de sortie à l'avant et grand lit sur la droite du salon.
func _build_loft(root: Node3D) -> void:
	var inst: Node3D = load("res://world/loft/loft.glb").instantiate()
	inst.position = LOFT_OFFSET
	root.add_child(inst)
	# Collisions : chaque meuble, l'escalier et la mezzanine
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		mi.create_trimesh_collision()
	# Enveloppe : sol, plafond et murs (le modèle d'origine est ouvert sur deux côtés)
	var wall := Color("2b2b2d")
	Mk.box(root, Vector3(14.2, 0.2, 14.2), Vector3(0, -0.12, -1.9), Color("8a8a88"), true)
	Mk.box(root, Vector3(14.2, 0.2, 14.2), Vector3(0, 7.5, -1.9), wall, true)
	Mk.box(root, Vector3(14.2, 7.5, 0.2), Vector3(0, 3.75, 5.06), wall, true)
	Mk.box(root, Vector3(14.2, 7.5, 0.2), Vector3(0, 3.75, -9.0), wall, true)
	Mk.box(root, Vector3(0.2, 7.5, 14.2), Vector3(7.06, 3.75, -1.9), wall, true)
	Mk.box(root, Vector3(0.2, 7.5, 14.2), Vector3(-7.1, 3.75, -1.9), wall, true)
	Mk.box(root, Vector3(1.6, 2.4, 0.08), Vector3(0, 1.2, 4.92), Color("5b4636"))
	Mk.label(root, "SORTIE", Vector3(0, 2.7, 4.86), 40, Color("2dc653"))
	# Grand lit contre le mur de droite (tête vers +X), tables de chevet
	var bed := Node3D.new()
	bed.position = BED_AT["home_loft"]
	bed.rotation.y = -PI / 2.0
	root.add_child(bed)
	Mk.box(bed, Vector3(2.1, 0.3, 2.15), Vector3(0, 0.15, 0.3), Color("1f1f1f"), true)
	Mk.box(bed, Vector3(2.1, 1.1, 0.1), Vector3(0, 0.55, -0.78), Color("3a3a3c"))
	Mk.box(bed, Vector3(1.9, 0.22, 2.0), Vector3(0, 0.41, 0.3), Color("f1f1f1"))
	Mk.box(bed, Vector3(1.94, 0.06, 1.3), Vector3(0, 0.54, 0.68), Color("6c757d"))
	for px in [-0.45, 0.45]:
		Mk.box(bed, Vector3(0.6, 0.13, 0.36), Vector3(px, 0.6, -0.45), Color("ffffff"))
	for sx in [-1.0, 1.0]:
		Furniture.place(bed, "ClassicNightstand_01", Vector3(sx * 1.5, 0, -0.55))
	# Lumière chaude du salon et de la mezzanine
	for lp in [Vector3(-3.5, 3.2, 0.5), Vector3(3.0, 3.2, 0.5), Vector3(0.0, 3.2, 3.5), Vector3(-2.0, 6.5, -5.5)]:
		var l := OmniLight3D.new()
		l.position = lp
		l.omni_range = 9.0
		l.light_energy = 1.3
		l.light_color = Color("ffe8cc")
		root.add_child(l)


func _deposit(amount: int) -> void:
	amount = mini(amount, GameState.money)
	if amount <= 0:
		GameState.notify.emit("Tu n'as pas d'argent liquide à déposer.")
		return
	GameState.money -= amount
	GameState.bank += amount
	GameState.bank_note("+%s : dépôt au guichet" % GameState.fcfa(amount))
	GameState.notify.emit("Dépôt de %s. Compte : %s (à l'abri des amendes et des vols)." % [GameState.fcfa(amount), GameState.fcfa(GameState.bank)])
	Audio.play_sfx("coin", -10.0)


func _withdraw(amount: int) -> void:
	amount = mini(amount, GameState.bank)
	if amount <= 0:
		GameState.notify.emit("Ton compte est vide.")
		return
	GameState.bank -= amount
	GameState.money += amount
	GameState.bank_note("-%s : retrait au guichet" % GameState.fcfa(amount))
	GameState.notify.emit("Retrait de %s. Compte : %s." % [GameState.fcfa(amount), GameState.fcfa(GameState.bank)])
	Audio.play_sfx("coin", -10.0)


# --- Braquage -----------------------------------------------------------------------------

func _confirm_rob() -> void:
	main.hud.show_choices("Braquer %s ? Tu seras recherché par la police." % _place, [
		["Oui : « La caisse, vite ! »", _start_robbery], ["Non, je rigolais", func(): pass]], func(): pass)


func _start_robbery() -> void:
	if not ROB_LOOT.has(inside):
		return
	if GameState.rp_job == "police":
		GameState.notify.emit("Un policier en service ne braque pas les boutiques !")
		return
	if int(_robbed.get(_place, -1)) == GameState.day:
		GameState.notify.emit("Le caissier : « On a déjà été braqués aujourd'hui, la caisse est vide ! »")
		return
	_robbed[_place] = GameState.day
	_rob_place = _place
	_rob_t = ROB_TIME
	GameState.notify.emit("« La caisse, vite ! » Le caissier remplit le sac en tremblant... Reste au comptoir %d secondes." % int(ROB_TIME))


func _update_robbery(delta: float) -> void:
	var o: Vector3 = _rooms.get(inside, Vector3.ZERO)
	var at_counter: bool = inside != "" and _place == _rob_place 			and main.player.global_position.distance_to(o + Vector3(0, 0, -ROOM.z / 2.0 + 2.6)) < 4.5
	if not at_counter:
		_rob_t = -1.0
		robbery_status = ""
		GameState.notify.emit("Tu as quitté le comptoir : braquage raté, pas de butin.")
		return
	_rob_t -= delta
	robbery_status = "BRAQUAGE — le caissier remplit le sac : %d s" % int(ceil(_rob_t))
	if _rob_t <= 0.0:
		_rob_t = -1.0
		robbery_status = ""
		var r: Array = ROB_LOOT.get(inside, [8000, 20000])
		var loot := randi_range(int(r[0]), int(r[1]))
		GameState.add_money(loot, "Butin du braquage")
		GameState.add_wanted(3, "Le caissier a déclenché l'alarme : la police arrive ! Fuis avec ton butin (%s)." % GameState.fcfa(loot))


func _buy(item: Array) -> void:
	if not GameState.spend(item[1]):
		GameState.notify.emit("Il te faut %s." % GameState.fcfa(item[1]))
		return
	var food: int = item[2]
	if food > 0 and GameState.take_food(item[0], food):
		GameState.notify.emit("%s (-%s). Dafa neex !" % [item[0], GameState.fcfa(item[1])])
	elif food > 0:
		GameState.notify.emit("Tu n'en as pas besoin maintenant : %s rangé dans ton sac (-%s)." % [item[0], GameState.fcfa(item[1])])
	else:
		GameState.add_item(item[0])
		GameState.notify.emit("Acheté : %s (-%s), rangé dans ton sac." % [item[0], GameState.fcfa(item[1])])
	Audio.play_sfx("coin", -12.0)


## Garage : nouvelle couleur, et la police perd ta trace (une étoile en moins)
func _repaint(v) -> void:
	if not GameState.spend(5000):
		GameState.notify.emit("Le mécanicien : « C'est 5 000 FCFA, grand ! »")
		return
	main.hud.fade_through(func():
		var palette := [Color("1d3557"), Color("e63946"), Color("f1faee"), Color("2a9d8f"), Color("6d6875"), Color("ffb703"), Color("264653")]
		v.repaint(palette[randi() % palette.size()])
		if GameState.wanted > 0:
			GameState.lose_star()
		GameState.notify.emit("Voiture repeinte ! Les policiers ne la reconnaissent plus."))


# --- Salles -------------------------------------------------------------------------

func _room(kind: String) -> Vector3:
	if _rooms.has(kind):
		return _rooms[kind]
	var o := BASE + Vector3(_rooms.size() * 40.0, 0, 0)
	_rooms[kind] = o
	var root := Node3D.new()
	root.position = o
	add_child(root)
	if kind == "home_loft":
		_build_loft(root)
		return o
	var fl: Color = FLOORS.get(kind, {"home_chambre": Color("b08968"), "home_studio": Color("d4c5a9"), "home_appartement": Color("c9b79c"), "home_villa": Color("ece6da")}.get(kind, Color("cccccc")))
	var wl: Color = WALLS.get(kind, {"home_chambre": Color("e9d8a6"), "home_studio": Color("a8dadc"), "home_appartement": Color("f1faee"), "home_villa": Color("fdfcf8")}.get(kind, Color("eeeeee")))
	Mk.box(root, Vector3(ROOM.x, 0.2, ROOM.z), Vector3(0, -0.1, 0), fl, true)
	Mk.box(root, Vector3(ROOM.x, 0.2, ROOM.z), Vector3(0, ROOM.y + 0.1, 0), Color("f7f7f2"), true)
	Mk.box(root, Vector3(ROOM.x, ROOM.y, 0.2), Vector3(0, ROOM.y / 2.0, -ROOM.z / 2.0), wl, true)
	Mk.box(root, Vector3(ROOM.x, ROOM.y, 0.2), Vector3(0, ROOM.y / 2.0, ROOM.z / 2.0), wl, true)
	Mk.box(root, Vector3(0.2, ROOM.y, ROOM.z), Vector3(-ROOM.x / 2.0, ROOM.y / 2.0, 0), wl.darkened(0.05), true)
	Mk.box(root, Vector3(0.2, ROOM.y, ROOM.z), Vector3(ROOM.x / 2.0, ROOM.y / 2.0, 0), wl.darkened(0.05), true)
	# Plinthe, porte de sortie et néons au plafond
	Mk.box(root, Vector3(ROOM.x - 0.4, 0.15, 0.05), Vector3(0, 0.08, -ROOM.z / 2.0 + 0.12), wl.darkened(0.3))
	Mk.box(root, Vector3(1.6, 2.4, 0.08), Vector3(0, 1.2, ROOM.z / 2.0 - 0.12), Color("5b4636"))
	Mk.label(root, "SORTIE", Vector3(0, 2.7, ROOM.z / 2.0 - 0.2), 40, Color("2dc653"))
	for x in [-3.5, 3.5]:
		for z in [-2.5, 2.5]:
			Mk.box(root, Vector3(1.6, 0.05, 0.3), Vector3(x, ROOM.y - 0.03, z), Color("ffffff"), false, Mk.mat(Color("fffbea"), 2.0))
	for x in [-3.5, 3.5]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, ROOM.y - 0.6, 0)
		l.omni_range = 11.0
		l.light_energy = 1.4
		l.light_color = Color("fff3e0")
		root.add_child(l)
	var counter_z := -ROOM.z / 2.0 + 1.6
	if kind.begins_with("home_"):
		_furnish_home(root, kind, counter_z)
	match kind:
		"banque":
			Mk.box(root, Vector3(9, 1.1, 0.8), Vector3(0, 0.55, counter_z), Color("5c4033"), true)
			Mk.box(root, Vector3(9.1, 0.05, 0.9), Vector3(0, 1.12, counter_z), Color("d6ccc2"))
			for x in [-3.0, 0.0, 3.0]:
				Mk.box(root, Vector3(2.4, 1.0, 0.04), Vector3(x, 1.65, counter_z), Color(0.7, 0.85, 0.95, 0.35))
				Mk.label(root, "GUICHET", Vector3(x, 2.4, counter_z), 28, Color("1d3557"), false)
				Furniture.place(root, "metal_office_desk", Vector3(x, 0, counter_z - 1.0), 0.0, false, 0.6)
			# Attente : canapés face aux guichets ; bureau du conseiller avec deux chaises
			Furniture.place(root, "Sofa_01", Vector3(-4.2, 0, 3.4), PI)
			Furniture.place(root, "Sofa_01", Vector3(-4.2, 0, 1.4), PI)
			Furniture.place(root, "metal_office_desk", Vector3(4.6, 0, 1.6), -PI / 2.0)
			Furniture.place(root, "dining_chair_02", Vector3(5.6, 0, 1.6), -PI / 2.0)
			Furniture.place(root, "dining_chair_02", Vector3(3.3, 0, 1.2), PI / 2.0)
			Furniture.place(root, "dining_chair_02", Vector3(3.3, 0, 2.0), PI / 2.0)
			Mk.box(root, Vector3(0.8, 1.8, 0.6), Vector3(6.3, 0.9, 4.6), Color("2b2d42"), true)
			Mk.label(root, "DAB", Vector3(6.3, 2.0, 4.25), 22, Color("ffffff"), false)
			for x in [-5.5, 5.5]:
				Furniture.picture(root, Vector3(x, 1.9, -ROOM.z / 2.0 + 0.11), 0.0)
		"restaurant":
			Mk.box(root, Vector3(5, 1.1, 0.8), Vector3(0, 0.55, counter_z), Color("6b4f3a"), true)
			Mk.box(root, Vector3(5.1, 0.05, 0.9), Vector3(0, 1.12, counter_z), Color("c9ada7"))
			Furniture.place(root, "CashRegister_01", Vector3(1.6, 1.14, counter_z), 0.0, false, 0.7)
			Furniture.place(root, "electric_stove", Vector3(-1.5, 0, -ROOM.z / 2.0 + 0.4))
			Furniture.place(root, "electric_stove", Vector3(-0.9, 0, -ROOM.z / 2.0 + 0.4))
			Furniture.place(root, "steel_frame_shelves_01", Vector3(2.2, 0, -ROOM.z / 2.0 + 0.35))
			Mk.label(root, "MENU\nThiéboudienne 2500\nYassa 2000 - Mafé 2000\nThiéré 1500 - Bissap 300", Vector3(-4.5, 2.4, -ROOM.z / 2.0 + 0.15), 26, Color("ffffff"), false)
			# Tables rondes en bois et chaises monobloc, comme dans les gargotes de Dakar
			for x in [-4.4, 4.4]:
				for z in [-1.8, 0.8, 3.4]:
					Furniture.place(root, "round_wooden_table_01", Vector3(x, 0, z), 0.0, true, 0.65)
					Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x - 0.85, 0, z), PI / 2.0)
					Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x + 0.85, 0, z), -PI / 2.0)
			for z in [-1.5, 2.5]:
				Furniture.place(root, "ceiling_fan", Vector3(0, ROOM.y, z), 0.0, false)
			Furniture.picture(root, Vector3(4.5, 1.9, -ROOM.z / 2.0 + 0.11), 0.0)
		"station", "boutique":
			Mk.box(root, Vector3(3, 1.0, 0.8), Vector3(-3, 0.5, counter_z), Color("e63946"), true)
			Furniture.place(root, "CashRegister_01", Vector3(-3.4, 1.0, counter_z), 0.0, false, 0.7)
			Furniture.place(root, "steel_frame_shelves_01", Vector3(-3.0, 0, -ROOM.z / 2.0 + 0.35))
			# Rayons d'un vrai supermarché : gondoles garnies (épicerie, ménage), congélateur, chariots
			Furniture.place(root, "shop/gondole_epicerie", Vector3(1.4, 0, 0.6), PI / 2.0)
			Furniture.place(root, "shop/gondole_menage", Vector3(4.0, 0, 0.6), PI / 2.0)
			Furniture.place(root, "shop/congelateur", Vector3(W_ROOM - 0.6, 0, 0.6), PI / 2.0)
			for k in 2:
				Furniture.place(root, "shop/chariot", Vector3(-5.8 + k * 0.45, 0, 4.4), 0.25, false)
		"hopital":
			Mk.box(root, Vector3(5, 1.1, 0.8), Vector3(0, 0.55, counter_z), Color("f8f9fa"), true)
			Furniture.place(root, "metal_office_desk", Vector3(0, 0, counter_z - 1.0), 0.0, false, 0.6)
			Mk.label(root, "+ ACCUEIL - URGENCES", Vector3(-4.0, 2.6, -ROOM.z / 2.0 + 0.15), 32, Color("d62828"), false)
			for x in [-5.6, 5.6]:
				# Lit d'hôpital : sommier métallique, matelas, oreiller ; table de chevet
				Mk.box(root, Vector3(1.0, 0.55, 2.1), Vector3(x, 0.28, 0.6), Color("adb5bd"), true)
				Mk.box(root, Vector3(0.95, 0.15, 2.0), Vector3(x, 0.63, 0.6), Color("e9f5f9"))
				Mk.box(root, Vector3(0.8, 0.12, 0.45), Vector3(x, 0.76, -0.2), Color("ffffff"))
				Furniture.place(root, "ClassicNightstand_01", Vector3(x - signf(x) * 0.95, 0, -0.2), -signf(x) * PI / 2.0)
				# Pied à perfusion
				var px: float = x - signf(x) * 0.75
				Mk.cyl(root, 0.015, 0.015, 1.9, Vector3(px, 0.95, 1.4), Color("ced4da"), false, 6)
				Mk.cyl(root, 0.22, 0.22, 0.03, Vector3(px, 0.02, 1.4), Color("6c757d"), false, 8)
				Mk.box(root, Vector3(0.14, 0.22, 0.05), Vector3(px, 1.75, 1.4), Color(0.85, 0.95, 1.0, 0.7))
			for x in [-2.6, -2.0, -1.4, 1.4, 2.0, 2.6]:
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x, 0, 3.6), PI)
		"police":
			Mk.box(root, Vector3(5, 1.2, 0.8), Vector3(0, 0.6, counter_z), Color("1e3a8a"), true)
			Mk.label(root, "POLICE NATIONALE", Vector3(-4.0, 2.6, -ROOM.z / 2.0 + 0.15), 34, Color("1e3a8a"), false)
			# Bureaux des agents, archives, banc des prévenus
			for x in [-4.4, 4.4]:
				Furniture.place(root, "metal_office_desk", Vector3(x, 0, -1.0))
				Furniture.place(root, "dining_chair_02", Vector3(x, 0, -1.9))
				Furniture.place(root, "plastic_monobloc_chair_01", Vector3(x, 0, -0.1), PI)
			Furniture.place(root, "steel_frame_shelves_01", Vector3(-W_ROOM + 0.35, 0, 2.0), PI / 2.0)
			Furniture.place(root, "steel_frame_shelves_01", Vector3(-W_ROOM + 0.35, 0, 3.2), PI / 2.0)
			Furniture.place(root, "painted_wooden_table", Vector3(4.4, 0, 3.6), 0.0, true, 0.6)
			Mk.box(root, Vector3(1.2, 0.9, 0.02), Vector3(5, 1.9, -ROOM.z / 2.0 + 0.12), Color("f1e3c8"))
			Mk.label(root, "AVIS DE\nRECHERCHE", Vector3(5, 2.2, -ROOM.z / 2.0 + 0.15), 20, Color("8b0000"), false)
	_sign = Mk.label(root, "", Vector3(0, 3.5, -ROOM.z / 2.0 + 0.15), 44, Color("fdef42"), false) if _sign == null else _sign
	if _sign.get_parent() != root:
		_sign.reparent(root)
		_sign.position = Vector3(0, 3.5, -ROOM.z / 2.0 + 0.15)
	return o
