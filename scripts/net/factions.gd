extends RefCounted
## Factions du mode en ligne : Police nationale, SAMU de Dakar et un gang de quartier.
## - On y entre une fois, au QG (ou depuis le menu MÉTIERS) ; une seule faction à la fois.
## - On prend son service au QG : tenue de la faction, véhicule de service, salaire du serveur.
## - Chaque action réussie (arrestation, joueur relevé, colis livré) donne de l'expérience :
##   l'expérience fait monter en grade, et le grade augmente le salaire.
## L'appartenance est gardée dans la sauvegarde (GameState.faction : {id, xp, civil}).

## id → nom, QG (lieu de la ville), tenue de service [haut, bas, chapeau] (scripts/util/outfits.gd),
## grades, salaire de base (0 = payé à la mission), véhicule de service, description
const FACTIONS := {
	"police": {"name": "Police nationale", "hq": "Commissariat", "uniform": ["bleu_nuit", "bleu_nuit", "casquette_noire"],
		"ranks": ["Agent stagiaire", "Agent", "Brigadier", "Inspecteur", "Commissaire"], "salary": 1500, "vehicle": "police",
		"desc": "Arrêter les joueurs recherchés. Il faut le permis de conduire et ne pas être recherché."},
	"samu": {"name": "SAMU de Dakar", "hq": "Hôpital Principal", "uniform": ["blanc", "blanc", ""],
		"ranks": ["Secouriste", "Ambulancier", "Infirmier", "Médecin", "Médecin-chef"], "salary": 1200, "vehicle": "van",
		"desc": "Relever les joueurs tombés à terre (faim, bagarre) avant qu'on les emmène à l'hôpital."},
	"gang": {"name": "Gang de la Médina", "hq": "Marché Tilène", "uniform": ["noir", "noir", "casquette_rouge"],
		"ranks": ["Petit", "Soldat", "Lieutenant", "Bras droit", "Boss"], "salary": 0, "vehicle": "",
		"desc": "Livrer des colis louches à travers Dakar. Bien payé, mais la police te recherche pendant la livraison."},
}
## Expérience nécessaire pour chaque grade
const RANK_XP := [0, 10, 30, 70, 150]


static func rank_of(xp: int) -> int:
	var r := 0
	for i in RANK_XP.size():
		if xp >= RANK_XP[i]:
			r = i
	return r


static func rank_name(id: String, xp: int) -> String:
	if not FACTIONS.has(id):
		return ""
	return FACTIONS[id]["ranks"][rank_of(xp)]


## Expérience qui manque pour le grade suivant (0 au plus haut grade)
static func xp_to_next(xp: int) -> int:
	var r := rank_of(xp)
	return 0 if r >= RANK_XP.size() - 1 else RANK_XP[r + 1] - xp


## Salaire versé par le serveur à chaque paie : +25 % par grade
static func salary(id: String, xp: int) -> int:
	if not FACTIONS.has(id):
		return 0
	return int(FACTIONS[id]["salary"] * (1.0 + 0.25 * rank_of(xp)))
