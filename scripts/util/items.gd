extends RefCounted
## Ce qui se mange et se boit : effet sur la faim (satiété), la soif et l'énergie.
## Les boutiques gardent leur prix et leur valeur de satiété ; ce catalogue ajoute la soif et l'énergie.
## Acheté sans faim ni soif, un produit va dans le sac ; on l'utilise ensuite depuis l'appli « Sac ».

## nom → [satiété, soif, énergie] (la satiété de la boutique prime si elle est donnée)
const CONSUMABLES := {
	"Thiéboudienne": [60, 5, 5], "Yassa poulet": [50, 5, 5], "Mafé": [50, 0, 5], "Thiéré (couscous de mil)": [40, 0, 5],
	"Dibi (viande grillée)": [35, 0, 5], "Pastels (beignets de poisson)": [12, 0, 0], "Brochette de poisson": [25, 0, 0], "Poulpe grillé": [30, 0, 5],
	"Mangue": [12, 8, 0], "Banane": [8, 2, 3], "Orange": [8, 10, 0], "Sachet d'arachides": [10, 0, 2],
	"Pomme": [8, 6, 0], "Avocat": [12, 2, 0], "Citron vert": [2, 6, 0], "Croissant": [10, 0, 2], "Petits pains (6)": [20, 0, 0],
	"Pain tapalapa": [15, 0, 0], "Pain": [15, 0, 0], "Fataya": [10, 0, 0], "Beignets": [8, 0, 0], "Sandwich": [25, 0, 0],
	"Biscuits": [8, 0, 2], "Lait caillé": [15, 15, 0],
	"Café Touba": [4, 10, 25], "Café": [3, 10, 20], "Thé vert": [0, 15, 15], "Ataya (3 verres)": [0, 20, 20],
	"Jus de bissap": [6, 35, 0], "Jus de bouye": [6, 35, 3], "Jus de gingembre": [6, 30, 5],
	"Sachet d'eau": [3, 30, 0], "Bouteille d'eau": [4, 50, 0],
}
const BAG_MAX := 30 ## objets dans le sac


static func is_consumable(name: String) -> bool:
	return CONSUMABLES.has(name)


## Effets : [satiété, soif, énergie]
static func effects(name: String, food := -1) -> Array:
	var e: Array = CONSUMABLES.get(name, [maxi(food, 0), 0, 0])
	return [food if food > 0 else e[0], e[1], e[2]]


## Le joueur a-t-il besoin de ce produit maintenant ? (sinon il va dans le sac)
static func needed(name: String, food := -1) -> bool:
	var e := effects(name, food)
	return (e[0] > 0 and GameState.hunger < 90.0) or (e[1] > 0 and GameState.thirst < 90.0) or (e[2] > 0 and GameState.energy < 90.0)


## Texte court des effets (« +35 soif, +25 énergie »)
static func describe(name: String) -> String:
	var e := effects(name)
	var parts: Array = []
	if e[0] > 0:
		parts.append("+%d satiété" % e[0])
	if e[1] > 0:
		parts.append("+%d soif" % e[1])
	if e[2] > 0:
		parts.append("+%d énergie" % e[2])
	return ", ".join(parts)
