"""Variante « RP urbain » du logo : Dakar la nuit, le personnage du jeu en gros plan, pistolet tendu, détouré
par un contre-jour rouge-orangé, nom du jeu penché en bas. Personnage rendu par
tools/pose_shot.gd --couleur (tools/perso_arme.png). Dessiné en 2048 px puis réduit.

Logo actuel du jeu.

    python tools/make_icon_urbain.py   -> icon.png (icône du jeu), export/icon_urbain_512.png (fiche du Play Store),
                                          export/icon_urbain_1024.png, export/icon_urbain_96.png (aperçu en petit)
"""
import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

S = 2048
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONT = "C:/Windows/Fonts/seguibl.ttf"  # Segoe UI Black
GREEN, YELLOW, RED = (0, 133, 63), (253, 239, 66), (227, 27, 35)
INK = (10, 6, 14)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def sky(img):
    """Ciel de nuit : bleu nuit en haut, lueur de la ville rouge-orangé à l'horizon"""
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / S
        c = lerp((12, 14, 40), (70, 20, 60), t / 0.6) if t < 0.6 else lerp((70, 20, 60), (200, 60, 30), (t - 0.6) / 0.4)
        d.line([(0, y), (S, y)], fill=c + (255,))


def city(img):
    """Silhouette d'immeubles et d'un minaret, fenêtres allumées"""
    rnd = random.Random(7)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    base = 1640
    x = -20
    while x < S:
        w = rnd.randint(110, 230)
        h = rnd.randint(260, 640)
        d.rectangle([x, base - h, x + w, S], fill=(30, 12, 34, 255))
        for wy in range(base - h + 30, base - 20, 46):
            for wx in range(x + 18, x + w - 24, 38):
                if rnd.random() < 0.32:
                    d.rectangle([wx, wy, wx + 16, wy + 22], fill=(255, 200, 90, 220))
        x += w + rnd.randint(0, 30)
    # Minaret (côté droit, derrière le titre)
    mx = 1700
    d.rectangle([mx - 40, base - 980, mx + 40, S], fill=(30, 12, 34, 255))
    d.rectangle([mx - 62, base - 760, mx + 62, base - 720], fill=(30, 12, 34, 255))
    d.polygon([(mx - 40, base - 980), (mx, base - 1110), (mx + 40, base - 980)], fill=(30, 12, 34, 255))
    d.ellipse([mx - 12, base - 1150, mx + 12, base - 1126], fill=(255, 200, 90, 255))
    img.alpha_composite(layer)


def moon(img):
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([1300, 140, 1700, 540], fill=(255, 230, 190, 120))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(70)))
    ImageDraw.Draw(img).ellipse([1400, 240, 1600, 440], fill=(255, 244, 220, 255))


def hero(img):
    """Personnage en buste, en couleur (rendu par tools/pose_shot.gd --couleur), halo rouge-orangé derrière"""
    sil = Image.open(os.path.join(ROOT, "tools", "perso_arme.png")).convert("RGBA")
    sil = sil.crop(sil.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox())
    sil = sil.crop((0, 0, sil.width, int(sil.height * 0.6)))  # de la tête aux hanches
    h = 1500
    sil = sil.resize((round(sil.width * h / sil.height), h), Image.LANCZOS)
    a = sil.getchannel("A")
    pos = (150, 1880 - h)
    # Halo : alpha élargi puis flouté, sous la silhouette
    big = Image.new("L", (S, S), 0)
    big.paste(a, pos)
    rim = big.filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(28))
    glow = Image.new("RGBA", (S, S), (255, 90, 30, 255))
    glow.putalpha(rim)
    img.alpha_composite(glow)
    halo = big.filter(ImageFilter.GaussianBlur(140))
    wide = Image.new("RGBA", (S, S), (255, 60, 40, 255))
    wide.putalpha(halo.point(lambda v: min(255, int(v * 0.9))))
    img.alpha_composite(wide)
    img.alpha_composite(sil, pos)


def _slanted_text(txt, size, fill, stroke, stroke_fill, slant=0.22):
    f = ImageFont.truetype(FONT, size)
    tmp = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    l, t, r, b = tmp.textbbox((0, 0), txt, font=f, stroke_width=stroke)
    w, h = r - l, b - t
    pad = int(h * slant) + 20
    layer = Image.new("RGBA", (w + pad + 20, h + 40), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((pad - l, 20 - t), txt, font=f, fill=fill, stroke_width=stroke, stroke_fill=stroke_fill)
    # Penché vers la droite (cisaillement horizontal)
    return layer.transform(layer.size, Image.AFFINE, (1, slant, -slant * layer.height, 0, 1, 0), Image.BICUBIC)


def title(img):
    # Bandeau sombre en bas pour que le titre ressorte
    band = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bd = ImageDraw.Draw(band)
    for y in range(1250, S):
        bd.line([(0, y), (S, y)], fill=(5, 2, 8, int(min(1.0, (y - 1250) / 350) * 235)))
    img.alpha_composite(band)
    g = _slanted_text("GALSEN", 430, (255, 255, 255), 26, INK)
    sh = Image.new("RGBA", g.size, (0, 0, 0, 0))
    sh.putalpha(g.getchannel("A").point(lambda v: v * 0.7))
    x = (S - g.width) // 2
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18)), (x + 14, 1300 + 24))
    img.alpha_composite(g, (x, 1300))
    # « LIFE » en blanc sur une bande rouge penchée
    life = _slanted_text("LIFE", 230, YELLOW, 0, None)
    bw, bh = life.width + 120, 250
    y0 = 1730
    x0 = (S - bw) // 2
    d = ImageDraw.Draw(img)
    k = 0.22 * bh
    d.polygon([(x0 + k, y0), (x0 + bw + k, y0), (x0 + bw, y0 + bh), (x0, y0 + bh)], fill=RED)
    d.polygon([(x0 + k - 30, y0), (x0 + k - 6, y0), (x0 - 6, y0 + bh), (x0 - 30, y0 + bh)], fill=GREEN)
    d.polygon([(x0 + bw + k + 6, y0), (x0 + bw + k + 30, y0), (x0 + bw + 30, y0 + bh), (x0 + bw + 6, y0 + bh)], fill=GREEN)
    img.alpha_composite(life, ((S - life.width) // 2, y0 + (bh - life.height) // 2 + 6))


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    sky(img)
    moon(img)
    city(img)
    hero(img)
    title(img)
    rgb = img.convert("RGB")
    rgb.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "icon.png"))  # icône du jeu
    os.makedirs(os.path.join(ROOT, "export"), exist_ok=True)
    for n in (512, 1024, 96):
        rgb.resize((n, n), Image.LANCZOS).save(os.path.join(ROOT, "export", "icon_urbain_%d.png" % n))
    print("icon.png, export/icon_urbain_512.png, export/icon_urbain_1024.png, export/icon_urbain_96.png")


if __name__ == "__main__":
    main()
