"""Remplace les étiquettes des produits des rayons (photos de marques étrangères) par des produits
sénégalais inventés : riz, mil, huile d'arachide, ataya, café Touba, bissap, savon, javel...

    python tools/senegal_labels.py <rects_epicerie.json> <rects_menage.json>

Les cadres viennent de tools/shop_uv_rects.py : chaque étiquette est dessinée exactement à la place
de l'ancienne, donc elle retombe sur le bon paquet en 3D ; le reste de l'image est recouvert de petits
paquets. Aucune vraie marque. Les images d'origine sont réécrites : relancer tools/extract_shop.py avant.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SHOP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "world", "shop")
FONT = "C:/Windows/Fonts/arialbd.ttf"
GREEN, YELLOW, RED = (0, 133, 63), (253, 239, 66), (227, 27, 35)

## image → (fichier, produits [nom, sous-titre, couleur du paquet, couleur du texte])
PRODUCTS = {
	"мармелад": ("gondole_epicerie_мармелад.jpg", [
		["Arachides grillées", "Kaolack", (196, 120, 48), (255, 255, 255)],
		["Bonbons Bissap", "goût hibiscus", (150, 20, 60), (255, 230, 240)],
		["Biscuits Baobab", "au pain de singe", (235, 205, 140), (90, 50, 20)],
		["Noix de cajou", "Casamance", (120, 70, 30), (255, 240, 200)],
		["Thiakry", "dessert de mil", (250, 245, 230), (40, 90, 60)],
		["Chips de manioc", "croustillantes", (240, 190, 40), (120, 30, 20)],
		["Dattes", "Tabaski", (90, 40, 20), (250, 210, 120)],
		["Caramels Teranga", "au lait", (210, 150, 60), (60, 30, 10)],
		["Bouye en poudre", "jus de baobab", (230, 220, 200), (150, 40, 40)],
	]),
	"рамены": ("gondole_epicerie_рамены.jpg", [
		["Riz brisé parfumé", "5 kg", (245, 245, 235), (0, 110, 60)],
		["Thiéré", "couscous de mil", (220, 180, 110), (90, 40, 10)],
		["Arraw", "granulés de mil", (200, 160, 90), (255, 255, 255)],
		["Fonio", "Sénégal oriental", (240, 225, 170), (120, 60, 20)],
		["Thé vert Ataya", "gunpowder", (20, 110, 70), (253, 239, 66)],
		["Café Touba", "au djar", (70, 35, 20), (250, 220, 150)],
		["Lait en poudre", "Ndiambour", (40, 90, 170), (255, 255, 255)],
		["Sucre en morceaux", "1 kg", (250, 250, 250), (200, 30, 40)],
		["Bouillon Yassa", "cubes", (230, 60, 30), (255, 230, 80)],
		["Bissap séché", "fleurs d'hibiscus", (120, 10, 40), (255, 255, 255)],
		["Niébé", "haricots", (235, 215, 180), (120, 60, 30)],
		["Huile d'arachide", "1 L", (240, 200, 40), (130, 50, 10)],
		["Pâte d'arachide", "pour le mafé", (150, 80, 30), (255, 230, 170)],
		["Tamarin", "dakhar en pulpe", (110, 60, 30), (255, 220, 140)],
		["Ditakh", "fruit frais", (40, 120, 50), (255, 255, 255)],
		["Sel iodé", "Lac Rose", (250, 210, 220), (180, 30, 90)],
	]),
	"суши": ("gondole_epicerie_суши.jpg", [
		["Thiof", "poisson frais", (220, 235, 240), (20, 70, 120)],
		["Yaboye", "sardinelles", (210, 230, 240), (20, 60, 110)],
		["Dibi d'agneau", "à griller", (180, 60, 40), (255, 240, 220)],
		["Fataya", "à la viande", (230, 180, 110), (120, 40, 10)],
		["Pastels", "au thon", (240, 200, 120), (130, 50, 20)],
		["Accara", "beignets de niébé", (220, 160, 70), (90, 30, 10)],
		["Crevettes", "de Joal", (250, 200, 190), (160, 40, 40)],
		["Poulet yassa", "plat préparé", (250, 230, 150), (120, 70, 0)],
	]),
	"трава": ("gondole_epicerie_трава.jpg", [
		["Menthe fraîche", "pour l'ataya", (210, 240, 210), (20, 100, 40)],
		["Gombo", "frais", (200, 235, 190), (30, 100, 30)],
		["Feuilles d'oseille", "bissap vert", (190, 230, 180), (20, 90, 30)],
		["Feuilles de manioc", "soupou kandia", (180, 225, 170), (20, 80, 30)],
	]),
	"бытовое": ("gondole_menage_бытовое.jpg", [
		["Savon de karité", "Kédougou", (245, 235, 210), (120, 70, 20)],
		["Eau de javel", "Ndox Set", (230, 240, 255), (20, 70, 160)],
		["Lessive Sabu", "poudre 1 kg", (40, 120, 200), (255, 255, 255)],
		["Liquide vaisselle", "citron vert", (120, 200, 60), (255, 255, 255)],
		["Insecticide", "anti-moustiques", (230, 120, 20), (255, 255, 255)],
		["Thiouraye", "encens", (110, 30, 90), (250, 220, 120)],
		["Beurre de karité", "pur", (250, 240, 200), (140, 90, 20)],
		["Gel douche", "bissap", (180, 20, 70), (255, 255, 255)],
		["Désodorisant", "parfum ylang", (240, 180, 220), (120, 20, 80)],
		["Savon noir", "traditionnel", (60, 50, 40), (240, 220, 160)],
	]),
	"быт2": ("gondole_menage_быт2.jpg", [
		["Nettoyant sol", "parfum menthe", (60, 170, 160), (255, 255, 255)],
		["Javel parfumée", "lavande", (150, 120, 210), (255, 255, 255)],
		["Savon liquide", "karité", (250, 230, 180), (120, 70, 20)],
		["Détachant", "boubous blancs", (230, 245, 255), (30, 80, 160)],
		["Lessive liquide", "Teranga", (30, 100, 190), (253, 239, 66)],
		["Anti-cafards", "spray", (200, 40, 30), (255, 255, 255)],
		["Éponges", "lot de 3", (250, 210, 40), (20, 110, 60)],
		["Shampoing", "aloe vera", (90, 180, 90), (255, 255, 255)],
	]),
}


def darker(c, k):
	return tuple(max(0, v - k) for v in c)


def fit_font(draw, lines, w, h):
	size = max(6, int(h))
	while size > 5:
		font = ImageFont.truetype(FONT, size)
		boxes = [draw.textbbox((0, 0), l, font=font) for l in lines]
		tw = max(b[2] - b[0] for b in boxes)
		th = sum(b[3] - b[1] for b in boxes) + (len(lines) - 1) * size * 0.15
		if tw <= w and th <= h:
			return font
		size -= 1
	return ImageFont.truetype(FONT, 5)


def wrap(name):
	words = name.split(" ")
	if len(words) == 1:
		return [name]
	best = None
	for k in range(1, len(words)):
		pair = [" ".join(words[:k]), " ".join(words[k:])]
		if best is None or max(len(x) for x in pair) < max(len(x) for x in best):
			best = pair
	return best


def label(img, box, prod):
	name, sub, bg, fg = prod
	d = ImageDraw.Draw(img)
	x0, y0, x1, y1 = box
	w, h = x1 - x0, y1 - y0
	d.rectangle(box, fill=bg)
	# Bande aux couleurs du drapeau en bas, liseré autour
	band = max(2, h // 9)
	for k, c in enumerate([GREEN, YELLOW, RED]):
		d.rectangle([x0 + k * w / 3.0, y1 - band, x0 + (k + 1) * w / 3.0, y1], fill=c)
	d.rectangle(box, outline=darker(bg, 60), width=max(1, w // 40))
	# Pastille ronde (le « logo » du produit) avec une étoile verte
	r = min(w, h) * 0.15
	cx, cy = x0 + w * 0.5, y0 + h * 0.08 + r
	d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fg, outline=darker(fg, 40))
	d.ellipse([cx - r * 0.35, cy - r * 0.35, cx + r * 0.35, cy + r * 0.35], fill=GREEN)
	# Nom en gros, sous-titre en petit
	top = cy + r + h * 0.04
	area_h = (y1 - band) - top - h * 0.03
	lines = wrap(name) if len(name) > 9 and w < h * 1.6 else [name]
	font = fit_font(d, lines, w * 0.9, area_h * 0.62)
	y = top
	for l in lines:
		b = d.textbbox((0, 0), l, font=font)
		d.text((x0 + (w - (b[2] - b[0])) / 2 - b[0], y - b[1]), l, font=font, fill=fg)
		y += (b[3] - b[1]) + font.size * 0.15
	sf = fit_font(d, [sub], w * 0.9, max(5.0, area_h * 0.2))
	b = d.textbbox((0, 0), sub, font=sf)
	if y + (b[3] - b[1]) < y1 - band:
		d.text((x0 + (w - (b[2] - b[0])) / 2 - b[0], y + font.size * 0.1 - b[1]), sub, font=sf, fill=darker(fg, 20))


def main():
	rects = {}
	for p in sys.argv[1:]:
		rects.update(json.load(open(p, encoding="utf-8")))
	for key, (fname, prods) in PRODUCTS.items():
		path = os.path.join(SHOP, fname)
		img = Image.open(path).convert("RGB")
		W, H = img.size
		# Fond : toute l'image recouverte de petits paquets (aucune photo d'origine ne reste,
		# même sur les faces trop petites pour une étiquette lisible)
		cw, ch = 48, 64
		for gy in range(0, H, ch):
			for gx in range(0, W, cw):
				label(img, [gx, gy, min(W, gx + cw) - 1, min(H, gy + ch) - 1], prods[(gx // cw + gy // ch * 3) % len(prods)])
		boxes = []
		for u0, v0, u1, v1 in rects.get(key, []):
			# UV : v vers le haut ; image : y vers le bas
			b = [int(max(0, u0) * W), int((1 - min(1, v1)) * H), int(min(1, u1) * W), int((1 - max(0, v0)) * H)]
			if b[2] - b[0] >= 14 and b[3] - b[1] >= 14:
				boxes.append(b)
		boxes.sort(key=lambda b: -(b[2] - b[0]) * (b[3] - b[1]))
		for k, b in enumerate(boxes):
			label(img, b, prods[k % len(prods)])
		img.save(path, quality=90)
		print("ETIQUETTES", fname, len(boxes))


main()
