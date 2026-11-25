extends Node3D
## Grand marché de Sandaga : tous les étals sont regroupés sur un site rien que pour eux, le grand terrain
## derrière le Marché Sandaga (sol de marché, portique d'entrée, 4 rangées d'étals, deux allées et une allée
## centrale). Les vendeurs n'apparaissent que quand le joueur approche (téléphones).
## [E] près d'un étal : acheter (la nourriture se mange, le reste va dans l'inventaire), ou marchander.
## Gère aussi les petits étals de rue de toute la ville (city.street_stalls : coin ataya, fruits, kiosque) :
## leur vendeur n'apparaît que pour les quelques étals les plus proches du joueur.
## Le joueur peut aussi louer un étal de rue pour la journée et le tenir : les passants s'arrêtent acheter.

const Mk = preload("res://scripts/util/mk.gd")
const RealCharacter = preload("res://scripts/util/real_character.gd")
const Furniture = preload("res://scripts/util/furniture.gd")
const Items = preload("res://scripts/util/items.gd")

const PLACE := "Marché Sandaga"
const SITE_NAME := "Grand marché de Sandaga"
const SITE_W := 46.0 ## largeur du site (le long de la rue)
const SITE_D := 36.0 ## profondeur (vers l'intérieur du pâté de maisons)
## [profondeur, côté des clients : -1 vers la rue, +1 vers le fond]
const ROWS := [[-12.0, -1.0], [-4.0, 1.0], [4.0, -1.0], [12.0, 1.0]]
const COLS := [-16.5, -11.0, -5.5, 5.5, 11.0, 16.5] ## allée centrale entre -3 et 3
const VENDOR_RANGE := 90.0
## type → [nom, couleur de la bâche, articles [nom, prix, satiété (0 = objet gardé)]]
const STALLS := {
	"fruits": ["Fruits et légumes", Color("e63946"), [["Banane", 100, 8], ["Pomme", 150, 8], ["Avocat", 250, 12], ["Citron vert", 50, 2], ["Oignons (1 kg)", 600, 0], ["Patate douce (1 kg)", 500, 0]]],
	"poisson": ["Poissonnerie", Color("3a86ff"), [["Thiof (poisson)", 2500, 0], ["Yaboye (sardinelles)", 500, 0], ["Brochette de poisson", 700, 25]]],
	"pain": ["Pain et beignets", Color("ffb703"), [["Pain tapalapa", 150, 15], ["Croissant", 250, 10], ["Petits pains (6)", 600, 20], ["Beignets", 100, 8], ["Café Touba", 150, 4]]],
	"tissu": ["Tissus wax et bazin", Color("8338ec"), [["Tissu wax (6 yards)", 6000, 0], ["Bazin riche", 12000, 0], ["Foulard", 1500, 0]]],
	"boisson": ["Jus locaux", Color("2a9d8f"), [["Jus de bissap", 200, 6], ["Jus de bouye", 250, 6], ["Jus de gingembre", 200, 6], ["Sachet d'eau", 50, 3]]],
	"artisanat": ["Artisanat", Color("bc6c25"), [["Masque en bois", 5000, 0], ["Panier tressé", 2000, 0], ["Bol en bois sculpté", 1500, 0], ["Pot en laiton", 8000, 0], ["Canari (poterie)", 4000, 0]]],
}
## Étals de rue : type → [nom, articles [nom, prix, satiété (0 : effet du catalogue scripts/util/items.gd)]]
const STREET := {
	"the": ["Coin ataya", [["Ataya (3 verres)", 150, 0], ["Café Touba", 100, 0], ["Sachet d'eau", 50, 0]]],
	"fruits": ["Étal de fruits", [["Mangue", 200, 0], ["Orange", 100, 0], ["Banane", 100, 0], ["Sachet d'arachides", 100, 0]]],
	"recharge": ["Kiosque", [["Bouteille d'eau", 300, 0], ["Biscuits", 150, 0], ["Sachet d'eau", 50, 0]]],
}
const STREET_VENDORS := 4 ## vendeurs de rue affichés en même temps (téléphones)
const STREET_RANGE := 45.0
const KEEP_RENT := 1000 ## location d'un étal de rue pour la journée
const KEEP_RANGE := 5.0 ## au-delà, le joueur a quitté son étal
const WOOD := "res://world/textures/wood.jpg" ## bois (ambientCG Wood051, CC0)
const FABRIC := "res://world/textures/fabric.jpg" ## tissu (ambientCG Fabric086, CC0)
const ORDER := ["fruits", "pain", "tissu", "poisson", "boisson", "fruits", "artisanat", "pain"]
const VENDOR_MODELS := ["femme_robe", "femme_jupe", "femme_maman", "homme_tunique", "homme_age"]
const THANKS := ["« Jërëjëf, ba beneen yoon ! »", "« Waaw, dafa neex ! »", "« Yàlla na la Yàlla barkeel ! » (que Dieu te bénisse)", "« Teranga ! Reviens me voir ! »"]

var city
var player
var hud
var stalls: Array = [] ## {type, pos, front}
var site := Vector3.ZERO ## centre du grand marché (Vector3.ZERO : pas de site)
var site_entrance := Vector3.ZERO ## devant le portique, côté rue
var _discount := 1.0
var _vendor_slots: Array = [] ## [étal (Node3D), modèle, graine, clip]
var _vendors: Array = []
var _view_t := 0.0
var _street_hash := {} ## cellule de 20 m → indices dans city.street_stalls
var _street_vendors := {} ## indice de l'étal → personnage
var _keep := -1 ## étal de rue tenu par le joueur (-1 : aucun)
var _keep_sold := 0
var _keep_earned := 0
var _keep_t := 0.0


func _ready() -> void:
	for i in city.street_stalls.size():
		var sp: Vector3 = city.street_stalls[i]["pos"]
		var hc := Vector2i(floori(sp.x / 20.0), floori(sp.z / 20.0))
		if not _street_hash.has(hc):
			_street_hash[hc] = []
		_street_hash[hc].append(i)
	if not city.places.has(PLACE):
		return
	# Les bâtiments doivent être dans le monde physique pour chercher le terrain libre
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var info: Array = city.place_info[PLACE]
	var curb: Vector3 = city.places[PLACE]
	var n := Vector3(info[3], 0, info[4]).normalized() # de la rue vers l'intérieur du pâté de maisons
	var f := Vector3(-n.z, 0, n.x)
	var c := _find_site(curb, n, f)
	if c == Vector3.INF:
		return
	site = c
	site_entrance = c - n * (SITE_D / 2.0 + 2.0)
	_build_site(c, n)
	var k := 0
	for row in ROWS:
		for x in COLS:
			var type: String = ORDER[k % ORDER.size()]
			var face: Vector3 = n * float(row[1]) # côté des clients
			var pos: Vector3 = c + f * float(x) + n * float(row[0])
			var h := _build_stall(pos, -face, f, type, rng, 0.0)
			if k % 2 == 0:
				_vendor_slots.append([h, VENDOR_MODELS[(k / 2) % VENDOR_MODELS.size()], k + 11, "talk" if k % 4 == 0 else "idle"])
			stalls.append({"type": type, "pos": pos, "front": pos + face * 1.9})
			k += 1
	var crowd: AudioStreamPlayer3D = Audio.make_3d("crowd", -2.0, 55.0)
	add_child(crowd)
	crowd.global_position = c + Vector3(0, 1.5, 0)


## Centre du site : le terrain dégagé (ni bâtiment ni chaussée) le plus proche derrière le marché
func _find_site(curb: Vector3, n: Vector3, f: Vector3) -> Vector3:
	var main = get_parent()
	for d in range(22, 70, 2):
		for shift in [0.0, -6.0, 6.0, -12.0, 12.0]:
			var c: Vector3 = curb + n * float(d) + f * float(shift)
			var ok := true
			for gx in range(-6, 7):
				for gz in range(-4, 5):
					var q: Vector3 = c + f * (gx * SITE_W / 12.0) + n * (gz * SITE_D / 8.0)
					if main.is_inside_building(q) or city.in_roadway(q, 1.0):
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector3(c.x, 0.0, c.z)
	return Vector3.INF


## Sol en terre battue, allées en ciment, bordures basses, portique d'entrée côté rue, parasols
func _build_site(c: Vector3, n: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = c
	root.rotation.y = atan2(n.x, n.z) # +Z local vers l'intérieur du pâté de maisons
	var ground := Mk.box(root, Vector3(SITE_W, 0.04, SITE_D), Vector3(0, 0.02, 0), Color.WHITE)
	ground.material_override = Mk.textured(FABRIC, Color("b59a72"), 6.0, 1.0)
	for z in [-8.0, 8.0]:
		Mk.box(root, Vector3(SITE_W - 2.0, 0.05, 3.2), Vector3(0, 0.03, z), Color("c9bfae"))
	Mk.box(root, Vector3(4.6, 0.05, SITE_D - 2.0), Vector3(0, 0.03, 0), Color("c9bfae"))
	# Bordures basses, ouvertes au milieu de chaque côté
	var curb_col := Color("8d8478")
	var hw := SITE_W / 2.0
	var hd := SITE_D / 2.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Mk.box(root, Vector3(hw - 3.0, 0.35, 0.3), Vector3(sx * (hw / 2.0 + 1.5), 0.17, sz * hd), curb_col, true)
			Mk.box(root, Vector3(0.3, 0.35, hd - 3.0), Vector3(sx * hw, 0.17, sz * (hd / 2.0 + 1.5)), curb_col, true)
	# Portique d'entrée, côté rue
	for sx in [-1.0, 1.0]:
		Mk.box(root, Vector3(0.6, 5.0, 0.6), Vector3(sx * 3.2, 2.5, -hd), Color("e9c46a"), true)
	Mk.box(root, Vector3(7.6, 1.2, 0.5), Vector3(0, 5.4, -hd), Color("2a9d8f"))
	var outside := Mk.label(root, SITE_NAME.to_upper(), Vector3(0, 5.4, -hd - 0.27), 46, Color("fdef42"), false)
	outside.rotation.y = PI
	Mk.label(root, SITE_NAME.to_upper(), Vector3(0, 5.4, -hd + 0.27), 46, Color("fdef42"), false)
	# Parasols au bout des allées
	var cols := [Color("e63946"), Color("ffb703"), Color("2a9d8f"), Color("8338ec")]
	var i := 0
	for z in [-8.0, 8.0]:
		for sx in [-1.0, 1.0]:
			var px: float = sx * (hw - 2.4)
			Mk.cyl(root, 0.04, 0.04, 2.4, Vector3(px, 1.2, z), Color("555555"), false, 6)
			Mk.cyl(root, 1.4, 0.05, 0.5, Vector3(px, 2.5, z), cols[i % cols.size()], false, 10)
			i += 1


func _process(delta: float) -> void:
	if _keep >= 0:
		_update_keeping(delta)
	_view_t -= delta
	if _view_t > 0.0:
		return
	_view_t = 1.0
	_update_street_vendors()
	if site == Vector3.ZERO:
		return
	var pp: Vector3 = player.global_position
	var near := Vector2(pp.x - site.x, pp.z - site.z).length() < VENDOR_RANGE
	if near and _vendors.is_empty():
		for v in _vendor_slots:
			var vendor = RealCharacter.create(v[0], v[1], v[2])
			vendor.position = Vector3(0, 0, 1.2) # derrière l'étal
			vendor.play_clip(v[3], 0.0)
			_vendors.append(vendor)
	elif not near and not _vendors.is_empty():
		for v in _vendors:
			if is_instance_valid(v):
				v.queue_free()
		_vendors.clear()


func _build_stall(pos: Vector3, n: Vector3, f: Vector3, type: String, rng: RandomNumberGenerator, base_y := 0.16) -> Node3D:
	var h := Node3D.new()
	add_child(h)
	h.position = Vector3(pos.x, base_y, pos.z)
	h.rotation.y = atan2(-n.x, -n.z) + PI # face à la rue
	var def: Array = STALLS[type]
	# Table en planches (bois brut), pieds en tubes de fer, bâche en tissu
	var wood := Mk.textured(WOOD, Color("e8d6bd"), 1.2)
	var table := Mk.box(h, Vector3(3.2, 0.08, 1.3), Vector3(0, 0.82, 0), Color.WHITE, true)
	table.material_override = wood
	var front_panel := Mk.box(h, Vector3(3.2, 0.7, 0.04), Vector3(0, 0.43, -0.63), Color.WHITE)
	front_panel.material_override = Mk.textured(WOOD, Color("c4a688"), 1.2)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			Mk.cyl(h, 0.035, 0.035, 0.8, Vector3(sx * 1.5, 0.4, sz * 0.55), Color("4a4a48"), false, 6)
			Mk.cyl(h, 0.03, 0.03, 2.5, Vector3(sx * 1.6, 1.25, sz * 0.75), Color("5a5a58"), false, 6)
	var cloth := Mk.textured(FABRIC, def[1], 0.8, 0.95)
	var canvas := Mk.box(h, Vector3(3.6, 0.03, 2.2), Vector3(0, 2.5, 0.1), Color.WHITE)
	canvas.rotation.x = -0.12
	canvas.material_override = cloth
	# Lambrequin qui pend à l'avant de la bâche
	var valance := Mk.box(h, Vector3(3.6, 0.28, 0.02), Vector3(0, 2.25, -1.0), Color.WHITE)
	valance.material_override = cloth
	# Sol : vieille bâche, caisses, sacs et bassines
	var mat := Mk.box(h, Vector3(4.2, 0.01, 3.2), Vector3(0, 0.005, 0.3), Color.WHITE)
	mat.material_override = Mk.textured(FABRIC, Color("8a7f6a"), 1.5, 1.0)
	# Caisses en bois (vrais modèles), parfois une deuxième empilée et une caisse en plastique à côté
	var stack := rng.randi_range(1, 3)
	Furniture.place(h, "goods/wooden_crate_01", Vector3(-1.95, 0.0, 0.65), PI / 2.0 + rng.randf_range(-0.15, 0.15), false)
	if stack >= 2:
		Furniture.place(h, "goods/wooden_crate_01", Vector3(-1.95, 0.35, 0.65), PI / 2.0 + rng.randf_range(-0.2, 0.2), false)
	if stack >= 3:
		Furniture.place(h, "goods/plastic_crate_01", Vector3(-1.9, 0.0, 1.3), rng.randf_range(-0.3, 0.3), false)
	var burlap := Mk.textured(FABRIC, Color("c2a878"), 0.5, 1.0)
	for k in rng.randi_range(1, 3):
		var sack := Mk.sphere(h, 0.28, Vector3(1.85, 0.3, 0.3 + k * 0.45), Color.WHITE, Vector3(1.0, 1.25, 0.9))
		sack.material_override = burlap
	var basin_cols := [Color("e63946"), Color("3a86ff"), Color("06d6a0"), Color("ffb703")]
	if rng.randf() < 0.7:
		Mk.cyl(h, 0.36, 0.26, 0.2, Vector3(rng.randf_range(0.8, 1.3) * (1.0 if rng.randf() < 0.5 else -1.0), 0.1, 1.15), basin_cols[rng.randi() % basin_cols.size()], false, 16)
	_goods(h, type, rng)
	Mk.label(h, def[0], Vector3(0, 2.75, 0), Mk.SIGN_SIZE - 4, Color("fff3b0"))
	return h


## Marchandises posées sur l'étal : vrais modèles (Poly Haven CC0, world/goods/) ; les tas de fruits et
## de légumes sont des MultiMesh (Furniture.pile). Le dessus de la table est à y ≈ 0.86, clients côté -z.
func _goods(h: Node3D, type: String, rng: RandomNumberGenerator) -> void:
	var top := 0.865
	var sd := rng.randi()
	match type:
		"fruits":
			# Devant : bols et paniers garnis ; derrière : régimes de bananes et un tas de pommes sur la table
			var piles := [["food_lime_01", 20, 3, 1.0, false], ["food_avocado_01", 10, 2, 1.0, false], ["lemon", 14, 2, 1.0, false], ["sweet_potato", 14, 2, 1.1, true], ["yellow_onion", 16, 3, 1.0, false]]
			for k in piles.size():
				var x := -1.2 + k * 0.6
				var bowl := "goods/wooden_bowl_01" if k % 2 == 0 else "goods/wicker_basket_01"
				Furniture.place(h, bowl, Vector3(x, top, -0.34), rng.randf_range(-0.3, 0.3), false)
				var p: Array = piles[k]
				Furniture.pile(h, "goods/" + p[0], Vector3(x, top + 0.02, -0.34), Vector2(0.26, 0.22), p[1], p[2], p[3], sd + k, p[4])
			# Au milieu, de grands tas à même la table
			var big := [["yellow_onion", 40], ["sweet_potato", 30], ["food_lime_01", 55]]
			for k in big.size():
				Furniture.pile(h, "goods/" + big[k][0], Vector3(-0.95 + k * 0.95, top, 0.04), Vector2(0.75, 0.32), big[k][1], 3, 1.0, sd + 20 + k, big[k][0] == "sweet_potato")
			for k in 3:
				Furniture.place(h, "goods/bananas", Vector3(-1.15 + k * 0.55, top + 0.04, 0.42), rng.randf_range(-0.3, 0.3), false)
			Furniture.pile(h, "goods/food_apple_01", Vector3(1.0, top, 0.42), Vector2(0.8, 0.22), 30, 3, 1.0, sd + 9)
		"poisson":
			# Bac de glace et poissons sur la table, caisse en plastique et seau au sol
			Mk.box(h, Vector3(3.0, 0.05, 1.1), Vector3(0, 0.88, 0), Color("dfe7ec"))
			var fish_cols := [Color("9aa7b2"), Color("b8c2c9"), Color("c47a6a")]
			for row in 3:
				for k in 8:
					var big_fish := row == 1
					var r := 0.07 if big_fish else 0.05
					var c: Color = fish_cols[2] if big_fish and k % 3 == 0 else fish_cols[(k + row) % 2]
					var f := Node3D.new()
					h.add_child(f)
					f.position = Vector3(-1.25 + k * 0.36 + rng.randf_range(-0.04, 0.04), 0.92, -0.35 + row * 0.35)
					f.rotation.y = rng.randf_range(-0.25, 0.25)
					Mk.sphere(f, r, Vector3.ZERO, c, Vector3(2.6, 0.75, 1.0))
					var tail := Mk.box(f, Vector3(0.06, 0.012, r * 1.6), Vector3(-r * 2.7, 0, 0), c.darkened(0.15))
					tail.rotation.y = PI / 4.0
					Mk.sphere(f, r * 0.18, Vector3(r * 2.0, r * 0.25, r * 0.55), Color("15171a"))
			Furniture.place(h, "goods/plastic_crate_03", Vector3(-0.9, 0.0, -0.95), rng.randf_range(-0.2, 0.2), false)
			Furniture.place(h, "goods/wooden_bucket_01", Vector3(0.9, 0.0, -0.95), 0.0, false)
		"pain":
			# Pains tapalapa à l'arrière, croissants et beignets en paniers, petits pains, cafetière de café Touba
			for g in 2:
				for k in 5:
					var bread := Mk.cyl(h, 0.045, 0.04, 0.62, Vector3(-0.75 + g * 1.2 + rng.randf_range(-0.03, 0.03), 0.91 + (k / 3) * 0.08, 0.2 + (k % 3) * 0.1), Color("d4a373"), false, 8)
					bread.rotation = Vector3(0.0, rng.randf_range(-0.08, 0.08), PI / 2.0)
			Furniture.place(h, "goods/wicker_basket_01", Vector3(-1.1, top, -0.3), 0.1, false)
			Furniture.pile(h, "goods/croissant", Vector3(-1.1, top + 0.02, -0.3), Vector2(0.24, 0.18), 8, 2, 1.0, sd)
			Furniture.place(h, "goods/wooden_bowl_01", Vector3(-0.45, top, -0.3), 0.0, false)
			for k in 8:
				Mk.sphere(h, 0.04, Vector3(-0.45 + rng.randf_range(-0.08, 0.08), top + 0.05 + (k / 5) * 0.05, -0.3 + rng.randf_range(-0.08, 0.08)), Color("b5763a")) # beignets
			for k in 2:
				Furniture.place(h, "goods/hamburger_buns", Vector3(0.25, top, -0.4 + k * 0.17), rng.randf_range(-0.1, 0.1), false)
			Furniture.place(h, "goods/carved_wooden_plate", Vector3(0.85, top, -0.3), 0.0, false)
			Furniture.pile(h, "goods/croissant", Vector3(0.85, top + 0.02, -0.3), Vector2(0.2, 0.2), 4, 1, 1.0, sd + 1)
			Furniture.place(h, "goods/brass_pot_01", Vector3(1.3, top, 0.05), 0.0, false)
		"tissu":
			var wax := [Color("e85d04"), Color("2a9d8f"), Color("d00000"), Color("ffb703"), Color("7b2cbf"), Color("1d4ed8"), Color("06d6a0")]
			for k in 7:
				var roll := Mk.cyl(h, 0.13, 0.13, 1.0, Vector3(-1.2 + k * 0.4, 0.98, 0), wax[k % wax.size()], false, 10)
				roll.rotation.x = PI / 2.0
			Furniture.place(h, "goods/wicker_basket_02", Vector3(0.0, 0.0, -0.95), 0.0, false)
		"boisson":
			# Bouteilles de jus dans des caisses en plastique, seau de glace au sol
			var juice := [Color("8b0000"), Color("f1eee5"), Color("e9c46a")]
			for c in 3:
				var cx := -1.0 + c * 1.0
				Furniture.place(h, "goods/plastic_crate_03", Vector3(cx, top, 0.0), 0.0, false)
				for k in 8:
					Mk.cyl(h, 0.04, 0.04, 0.3, Vector3(cx - 0.17 + (k % 4) * 0.113, top + 0.17, -0.06 + int(k / 4) * 0.12), juice[(k + c) % 3], false, 8)
			# Devant : sachets d'eau et de bissap en tas
			for k in 14:
				var bag := Mk.sphere(h, 0.05, Vector3(-1.2 + (k % 7) * 0.4 + rng.randf_range(-0.05, 0.05), top + 0.03, -0.38 + int(k / 7) * 0.12), Color(0.9, 0.95, 1.0) if k % 2 == 0 else Color("8b0000"), Vector3(1.6, 0.5, 1.0))
				bag.rotation.y = rng.randf_range(-0.6, 0.6)
			Furniture.place(h, "goods/wooden_bucket_01", Vector3(1.0, 0.0, -0.95), 0.0, false)
		"artisanat":
			# Masques à l'arrière ; devant : vanneries, bols et plat sculptés, pot en laiton ; canari au sol
			for k in 4:
				var mask := Mk.box(h, Vector3(0.26, 0.45, 0.05), Vector3(-1.1 + k * 0.7, 1.09, 0.38), Color("5a3612")) # masques
				mask.rotation.x = -0.15
				for e in [-0.06, 0.06]:
					Mk.box(mask, Vector3(0.05, 0.025, 0.02), Vector3(e, 0.08, -0.03), Color("e9c46a"))
				Mk.box(mask, Vector3(0.03, 0.1, 0.03), Vector3(0, -0.01, -0.035), Color("3d2410"))
			var front := ["wicker_basket_02", "wooden_bowl_01", "carved_wooden_plate", "brass_pot_01", "wooden_bowl_02", "wicker_basket_01"]
			for k in front.size():
				Furniture.place(h, "goods/" + front[k], Vector3(-1.25 + k * 0.5, top, -0.32), rng.randf_range(-0.3, 0.3), false)
			# Deuxième rang : bols empilés, plats sculptés et paniers
			for k in 3:
				var x := -0.95 + k * 0.95
				Furniture.place(h, "goods/wooden_bowl_01", Vector3(x - 0.2, top, 0.05), 0.0, false)
				Furniture.place(h, "goods/wooden_bowl_01", Vector3(x - 0.2, top + 0.06, 0.05), 0.5, false)
				Furniture.place(h, "goods/carved_wooden_plate", Vector3(x + 0.18, top, 0.05), rng.randf(), false)
				Furniture.place(h, "goods/carved_wooden_plate", Vector3(x + 0.18, top + 0.035, 0.05), rng.randf(), false)
			Furniture.place(h, "goods/ceramic_pot", Vector3(0.6, 0.0, -1.05), 0.0, false)


func _stall_near(pp: Vector3) -> Variant:
	for s in stalls:
		if Vector2(pp.x - s["front"].x, pp.z - s["front"].z).length() < 2.6:
			return s
	var hc := Vector2i(floori(pp.x / 20.0), floori(pp.z / 20.0))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for i in _street_hash.get(hc + Vector2i(dx, dz), []):
				var st: Dictionary = city.street_stalls[i]
				var front: Vector3 = st["pos"] + st["face"] * 1.0
				if Vector2(pp.x - front.x, pp.z - front.z).length() < 1.8:
					return {"type": st["type"], "street": true, "index": i}
	return null


## Vendeurs des étals de rue : seulement pour les étals les plus proches du joueur
func _update_street_vendors() -> void:
	if player == null:
		return
	var pp: Vector3 = player.get_world_position()
	var near: Array = [] ## [distance, indice]
	var hc := Vector2i(floori(pp.x / 20.0), floori(pp.z / 20.0))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for i in _street_hash.get(hc + Vector2i(dx, dz), []):
				var sp: Vector3 = city.street_stalls[i]["pos"]
				var d: float = Vector2(pp.x - sp.x, pp.z - sp.z).length()
				if d < STREET_RANGE:
					near.append([d, i])
	near.sort()
	var keep := {}
	for k in mini(near.size(), STREET_VENDORS):
		if near[k][1] != _keep: # l'étal que tient le joueur n'a pas d'autre vendeur
			keep[near[k][1]] = true
	for i in _street_vendors.keys():
		if not keep.has(i):
			if is_instance_valid(_street_vendors[i]):
				_street_vendors[i].queue_free()
			_street_vendors.erase(i)
	for i in keep:
		if not _street_vendors.has(i):
			_street_vendors[i] = _make_street_vendor(i)


func _make_street_vendor(i: int) -> Node3D:
	var st: Dictionary = city.street_stalls[i]
	var face: Vector3 = st["face"]
	var along := Vector3(-face.z, 0, face.x)
	var h := Node3D.new()
	add_child(h)
	var clip := "idle"
	match st["type"]:
		"the":
			# Assis sur un tabouret à côté du réchaud, il sert le thé
			h.position = st["pos"] + along * 0.75 - face * 0.12 + Vector3(0, -0.12, 0)
			clip = "sit"
		"fruits":
			h.position = st["pos"] - face * 0.55
		_:
			h.position = st["pos"] + along * 0.95
	h.rotation.y = atan2(-face.x, -face.z) # regarde vers la rue (le modèle regarde vers -Z)
	var c = RealCharacter.create(h, VENDOR_MODELS[i % VENDOR_MODELS.size()], 500 + i)
	c.play_clip(clip, 0.0)
	return h


func get_hint() -> String:
	if player.current_vehicle != null or player.riding != null:
		return ""
	if _keep >= 0 and _near_kept():
		return "Fermer l'étal"
	var s = _stall_near(player.global_position)
	if s == null:
		return ""
	return "Acheter : %s" % (STREET[s["type"]][0] if s.has("street") else STALLS[s["type"]][0])


func try_interact() -> bool:
	if player.current_vehicle != null or player.riding != null:
		return false
	if _keep >= 0 and _near_kept():
		_stop_keeping("Tu fermes ton étal.")
		return true
	var s = _stall_near(player.global_position)
	if s == null:
		return false
	_open_shop(s)
	return true


func _open_shop(s: Dictionary) -> void:
	var def: Array = STALLS[s["type"]] if not s.has("street") else [STREET[s["type"]][0], null, STREET[s["type"]][1]]
	var choices: Array = []
	for item in def[2]:
		var price := int(round(float(item[1]) * _discount / 25.0)) * 25
		choices.append(["%s — %s" % [item[0], GameState.fcfa(price)], _buy.bind(item, price)])
	if _discount >= 1.0:
		choices.append(["Marchander (« Wàññil ma ! »)", _haggle.bind(s)])
	if s.has("street") and _keep < 0:
		choices.append(["Tenir cet étal aujourd'hui (location %s)" % GameState.fcfa(KEEP_RENT), _start_keeping.bind(int(s["index"]))])
	hud.show_choices("%s — « Lu nga bëgg ? » (qu'est-ce que tu veux ?)" % def[0], choices, func(): _discount = 1.0)


func _buy(item: Array, price: int) -> void:
	_discount = 1.0
	if not GameState.spend(price):
		GameState.notify.emit("« Amul xaalis ? » (pas d'argent ?) Il te faut %s." % GameState.fcfa(price))
		return
	var food: int = item[2]
	var eat: bool = food > 0 or Items.is_consumable(item[0])
	if eat and GameState.take_food(item[0], food if food > 0 else -1):
		GameState.health = minf(100.0, GameState.health + Items.effects(item[0], food if food > 0 else -1)[0] * 0.2)
		GameState.notify.emit("Tu prends : %s (-%s). %s" % [item[0], GameState.fcfa(price), THANKS.pick_random()])
	elif eat:
		GameState.notify.emit("%s rangé dans ton sac pour plus tard (-%s). %s" % [item[0], GameState.fcfa(price), THANKS.pick_random()])
	else:
		GameState.add_item(item[0])
		GameState.notify.emit("Acheté : %s (-%s), rangé dans ton sac. %s" % [item[0], GameState.fcfa(price), THANKS.pick_random()])
	Audio.play_sfx("coin", -12.0)


func _haggle(s: Dictionary) -> void:
	if randf() < 0.55:
		_discount = 0.8
		GameState.notify.emit("« Bon, pour toi, -20 %. Waaw ! »")
	else:
		_discount = 1.0
		GameState.notify.emit("« Dedet ! C'est déjà le prix, grand ! » (non)")
	_open_shop(s)


# --- Étal de rue tenu par le joueur ------------------------------------------------

func _start_keeping(i: int) -> void:
	var jm = player.job_manager
	if jm != null and jm.job != "":
		GameState.notify.emit("Termine d'abord ton travail en cours.")
		return
	if not GameState.spend(KEEP_RENT):
		GameState.notify.emit("Le vendeur : « La place, c'est %s pour la journée, grand. »" % GameState.fcfa(KEEP_RENT))
		return
	_keep = i
	_keep_sold = 0
	_keep_earned = 0
	_keep_t = 0.0
	if jm != null:
		jm.job = "etal"
	# Le vendeur te laisse sa place
	if _street_vendors.has(i):
		if is_instance_valid(_street_vendors[i]):
			_street_vendors[i].queue_free()
		_street_vendors.erase(i)
	GameState.notify.emit("Tu loues l'étal (-%s). « Bon courage, les clients arrivent ! » Reste à côté pour vendre." % GameState.fcfa(KEEP_RENT))


func _near_kept() -> bool:
	var st: Dictionary = city.street_stalls[_keep]
	var front: Vector3 = st["pos"] + st["face"] * 1.0
	var pp: Vector3 = player.get_world_position()
	return Vector2(pp.x - front.x, pp.z - front.z).length() < KEEP_RANGE


func _update_keeping(delta: float) -> void:
	var jm = player.job_manager
	if jm != null and jm.job != "etal":
		_keep = -1 # travail annulé ailleurs (arrestation, évanouissement…)
		return
	if player.current_vehicle != null or not _near_kept():
		_stop_keeping("Tu as quitté ton étal.")
		return
	var st: Dictionary = city.street_stalls[_keep]
	_keep_t += delta
	# Plus il y a de passants autour, plus les clients s'arrêtent souvent
	var wait := 6.0
	if _keep_t >= 1.0:
		var crowd := 0
		for p in get_tree().get_nodes_in_group("pedestrians"):
			if p is Node3D and (p as Node3D).global_position.distance_to(st["pos"]) < 15.0:
				crowd += 1
		wait = clampf(6.0 - crowd * 0.8, 2.5, 6.0)
		if randf() < 1.0 / wait:
			var items: Array = STREET[st["type"]][1]
			var item: Array = items[randi() % items.size()]
			var qty := 1 + randi() % 2 # « Mets-m'en deux ! »
			var price: int = int(item[1]) * qty
			_keep_sold += qty
			_keep_earned += price
			GameState.add_money(price, "Étal : %s%s" % [item[0], " ×2" if qty > 1 else ""])
			GameState.stats["ventes_etal"] = int(GameState.stats.get("ventes_etal", 0)) + qty
		_keep_t = 0.0
	if jm != null:
		jm.objective = "%s — %d vente%s, %s gagnés   •   [E] fermer l'étal" % [STREET[st["type"]][0].to_upper(), _keep_sold, "s" if _keep_sold > 1 else "", GameState.fcfa(_keep_earned)]


func _stop_keeping(why: String) -> void:
	var jm = player.job_manager
	if jm != null and jm.job == "etal":
		jm.cancel()
	_keep = -1
	var net := _keep_earned - KEEP_RENT
	GameState.notify.emit("%s %d vente%s, %s encaissés (%s après la location)." % [why, _keep_sold, "s" if _keep_sold > 1 else "", GameState.fcfa(_keep_earned), ("+" if net >= 0 else "-") + GameState.fcfa(net)])
