extends RefCounted
## Tenues du joueur (appli « Sapé » du téléphone) : couleur du haut, couleur du bas, chapeau,
## coiffure et couleur des cheveux (coiffeur).
## Une tenue tient dans un petit texte « haut,bas,chapeau,coiffure,couleur » (ex. « vert,noir,,afro,brun ») :
## c'est lui qui est sauvegardé et transmis aux autres joueurs en ligne. Une partie vide garde
## le vêtement d'origine du personnage.

## id → [nom, couleur, prix]
const COLORS := {
	"blanc": ["Blanc", Color("f4f1ea"), 2000],
	"noir": ["Noir", Color("1c1c1e"), 2000],
	"kaki": ["Kaki", Color("8a7f55"), 2500],
	"ciel": ["Bleu ciel", Color("8ec5ea"), 2500],
	"bleu_nuit": ["Bleu nuit", Color("1d2b53"), 3000],
	"bordeaux": ["Bordeaux", Color("6d1a2b"), 3000],
	"vert": ["Vert Lions", Color("00853f"), 3500],
	"jaune": ["Jaune Lions", Color("fdef42"), 3500],
	"rouge": ["Rouge Lions", Color("e31b23"), 3500],
	"bazin_or": ["Bazin doré", Color("c9a227"), 8000],
}
## id → [nom, forme, couleur, prix]
const HATS := {
	"casquette_noire": ["Casquette noire", "casquette", Color("1c1c1e"), 1500],
	"casquette_verte": ["Casquette verte", "casquette", Color("00853f"), 1500],
	"casquette_rouge": ["Casquette rouge", "casquette", Color("e31b23"), 1500],
	"kufi_blanc": ["Kufi blanc", "kufi", Color("f4f1ea"), 1000],
	"kufi_bazin": ["Kufi bazin", "kufi", Color("c9a227"), 3000],
	"chapeau_paille": ["Chapeau de paille", "paille", Color("d9b46a"), 2500],
}
## Coiffeur : id → [nom, coiffure MakeHuman (characters/hair/<homme|femme>_<fichier>.glb, "" = rasé), prix]
const HAIRS := {
	"rase": ["Crâne rasé", "", 1000],
	"brosse": ["Coupe brosse", "short01", 1500],
	"court": ["Coupe courte", "short02", 1500],
	"degrade": ["Dégradé", "short04", 1500],
	"afro": ["Afro", "afro01", 2500],
	"chignon": ["Chignon", "rehmanpolanski_hair_bun_brown", 2500],
	"queue": ["Queue de cheval", "ponytail01", 2500],
	"carre": ["Carré", "bob02", 3000],
	"meches": ["Mèches", "elvs_double_mh_braid", 3000],
	"tresses": ["Tresses", "braid01", 4000],
}
## Couleur des cheveux : id → [nom, teinte (multiplie la texture, au-delà de 1 pour éclaircir), prix]
const HAIR_COLORS := {
	"noir": ["Noir", Color(0.16, 0.14, 0.13), 1000],
	"brun": ["Brun", Color(0.62, 0.45, 0.34), 1000],
	"henne": ["Henné", Color(1.5, 0.62, 0.4), 2000],
	"blond": ["Blond décoloré", Color(2.4, 1.95, 1.2), 2500],
}
const PARTS := ["haut", "bas", "chapeau", "coiffure", "couleur"]
const CATALOGS := [COLORS, COLORS, HATS, HAIRS, HAIR_COLORS]
const PART_NAMES := ["Haut", "Bas", "Chapeau", "Coiffure", "Couleur des cheveux"]
const MAX_LEN := 96


## [haut, bas, chapeau, coiffure, couleur] : les valeurs inconnues (ancienne version, tricherie) sont ignorées
static func parse(code: String) -> Array:
	var p := code.left(MAX_LEN).split(",")
	var out := ["", "", "", "", ""]
	for i in mini(p.size(), PARTS.size()):
		var v := p[i].strip_edges()
		if CATALOGS[i].has(v):
			out[i] = v
	return out


## Texte d'une tenue (vide si tout est d'origine) ; les parties vides de la fin sont retirées
static func make(parts: Array) -> String:
	var p := parse(",".join(PackedStringArray(parts)))
	while not p.is_empty() and p[-1] == "":
		p.pop_back()
	return ",".join(PackedStringArray(p))


## Objet du catalogue : « haut:vert », « bas:noir », « chapeau:kufi_blanc », « coiffure:afro », « couleur:brun »
static func item_price(item: String) -> int:
	var kv := item.split(":")
	var i := PARTS.find(kv[0])
	if kv.size() != 2 or i == -1 or not CATALOGS[i].has(kv[1]):
		return 0
	var e: Array = CATALOGS[i][kv[1]]
	return e[-1]


static func item_name(item: String) -> String:
	var kv := item.split(":")
	var i := PARTS.find(kv[0])
	if kv.size() != 2 or i == -1 or not CATALOGS[i].has(kv[1]):
		return "?"
	var name: String = CATALOGS[i][kv[1]][0]
	match kv[0]:
		"haut", "bas":
			return "%s %s" % [PART_NAMES[i], name.to_lower()]
		"couleur":
			return "Cheveux " + name.to_lower()
	return name
