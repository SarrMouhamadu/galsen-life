extends Node
## Cuisine à la maison : avec les produits du sac (poisson pêché, riz et huile de la boutique), on prépare
## des plats sénégalais chez soi. Les plats vont dans le sac : on les mange ou on les revend au restaurant.
## Plus la compétence Cuisine monte, plus une recette donne de portions.

const Items = preload("res://scripts/util/items.gd")

## nom → [ingrédients {produit: quantité}, plat, portions]
const RECIPES := {
	"Thiéboudienne": [{"Sac de riz (5 kg)": 1, "@poisson": 1}, "Thiéboudienne", 3],
	"Pastels": [{"Yaboy (sardinelle)": 2, "Huile (1 L)": 1}, "Pastels (beignets de poisson)", 4],
	"Brochettes de poisson": [{"@gros_poisson": 1}, "Brochette de poisson", 2],
	"Poulpe grillé": [{"Poulpe": 1, "Huile (1 L)": 1}, "Poulpe grillé", 2],
}
## « @poisson » : n'importe quel poisson ; « @gros_poisson » : capitaine, thiof ou dorade
const FISH := ["Yaboy (sardinelle)", "Dorade", "Capitaine", "Thiof"]
const BIG_FISH := ["Capitaine", "Thiof", "Dorade"]
## Prix de rachat des plats faits maison par les restaurants
const RESALE := {"Thiéboudienne": 1500, "Pastels (beignets de poisson)": 300, "Brochette de poisson": 800, "Poulpe grillé": 1000}

var main


func _pick(slot: String) -> String:
	var list: Array = FISH if slot == "@poisson" else BIG_FISH
	for f in list:
		if int(GameState.inventory.get(f, 0)) > 0:
			return f
	return ""


## Ingrédients réels d'une recette ({} s'il en manque)
func _ingredients(recipe: String) -> Dictionary:
	var need: Dictionary = RECIPES[recipe][0]
	var real := {}
	for k in need:
		var item: String = k
		if item.begins_with("@"):
			item = _pick(k)
			if item == "":
				return {}
		if int(GameState.inventory.get(item, 0)) < int(need[k]):
			return {}
		real[item] = int(need[k])
	return real


func portions(recipe: String) -> int:
	var lv := GameState.skill_level("cuisine")
	return int(RECIPES[recipe][2]) + (1 if lv >= 4 else 0) + (1 if lv >= 8 else 0)


func _describe(recipe: String) -> String:
	var parts: Array = []
	var need: Dictionary = RECIPES[recipe][0]
	for k in need:
		var item: String = {"@poisson": "poisson", "@gros_poisson": "capitaine, thiof ou dorade"}.get(k, k)
		parts.append("%d %s" % [need[k], item.to_lower()])
	return ", ".join(parts)


func menu() -> void:
	var choices: Array = []
	for r in RECIPES:
		var recipe: String = r
		var ok := not _ingredients(recipe).is_empty()
		choices.append(["%s%s x%d — %s" % ["" if ok else "(il manque) ", recipe, portions(recipe), _describe(recipe)], func(): cook(recipe)])
	main.hud.show_choices("Cuisine — niveau %d\nPoisson : pêche à l'Anse Bernard. Riz et huile : boutiques." % GameState.skill_level("cuisine"), choices, func(): pass)


func cook(recipe: String) -> bool:
	var ing := _ingredients(recipe)
	if ing.is_empty():
		GameState.notify.emit("Il te manque des ingrédients : %s." % _describe(recipe))
		return false
	var n := portions(recipe)
	var used := 0
	for k in ing:
		used += int(ing[k])
	if GameState.bag_count() - used + n > Items.BAG_MAX:
		GameState.notify.emit("Ton sac est trop plein pour ranger ces plats.")
		return false
	for k in ing:
		GameState.inventory[k] = int(GameState.inventory[k]) - int(ing[k])
		if GameState.inventory[k] <= 0:
			GameState.inventory.erase(k)
	var dish: String = RECIPES[recipe][1]
	GameState.add_item(dish, n)
	GameState.add_skill("cuisine", 6.0)
	if not Net.online:
		GameState.advance_time(45.0)
	GameState.save_game()
	GameState.notify.emit("Ça sent bon ! %s x%d préparé, rangé dans ton sac." % [dish, n])
	return true


## Restaurant : rachat des plats faits maison
func resale_total() -> Array:
	var total := 0
	var count := 0
	for d in RESALE:
		var c := int(GameState.inventory.get(d, 0))
		total += c * int(RESALE[d])
		count += c
	return [count, total]


func sell_dishes() -> void:
	var t := resale_total()
	if t[0] == 0:
		return
	for d in RESALE:
		GameState.inventory.erase(d)
	GameState.add_money(t[1], "Le restaurant rachète tes %d plats" % t[0])
	GameState.save_game()
