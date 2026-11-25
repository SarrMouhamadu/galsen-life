"""Logo du jeu (icon.png, 512 x 512) : un baobab en silhouette devant un grand soleil couchant, rayons de
lumière, nom du jeu en très gros et pastille verte « LIFE », bande aux couleurs du Sénégal.
Peu d'éléments et des couleurs vives : il reste lisible en petit (écran d'accueil, fiche du Play Store).
Dessiné en 2048 px puis réduit (bords lisses).

Ancien logo (l'icône du jeu vient maintenant de tools/make_icon_urbain.py).

    python tools/make_icon.py   -> export/icon_512.png
                                   et export/icon_1024.png
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FONT = "C:/Windows/Fonts/seguibl.ttf"  # Segoe UI Black
GREEN, YELLOW, RED = (0, 133, 63), (253, 239, 66), (227, 27, 35)
INK = (28, 12, 30)  # silhouettes et contours : brun-violet très sombre (plus chaud que le noir)


def lerp(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background(img):
    """Ciel de coucher de soleil, du jaune doré au centre au rouge profond sur les bords"""
    cx, cy = 1024, 1080
    inner, mid, outer = (255, 214, 90), (255, 122, 28), (176, 22, 58)
    px = img.load()
    for y in range(0, S, 2):
        for x in range(0, S, 2):
            d = math.hypot(x - cx, (y - cy) * 1.1) / 1500.0
            c = lerp(inner, mid, d / 0.45) if d < 0.45 else lerp(mid, outer, (d - 0.45) / 0.55)
            for dx in (0, 1):
                for dy in (0, 1):
                    px[x + dx, y + dy] = c + (255,)


def rays(img):
    """Rayons de lumière autour du soleil"""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = 1024, 1080
    n = 18
    for k in range(n):
        a0 = k * 2 * math.pi / n
        a1 = a0 + math.pi / n * 0.55
        d.polygon([(cx, cy), (cx + math.cos(a0) * 2400, cy + math.sin(a0) * 2400),
                   (cx + math.cos(a1) * 2400, cy + math.sin(a1) * 2400)], fill=(255, 240, 200, 46))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(6)))


def sun(img):
    cx, cy, r = 1024, 1080, 470
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - r - 140, cy - r - 140, cx + r + 140, cy + r + 140], fill=(255, 236, 150, 150))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(80)))
    disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disc)
    for k in range(r, 0, -3):
        dd.ellipse([cx - k, cy - k, cx + k, cy + k], fill=lerp((255, 250, 205), (255, 170, 40), k / r) + (255,))
    img.alpha_composite(disc)


def _limb(d, x0, y0, ang, ln, w0, w1, depth, seed):
    """Branche effilée (trapèze) ; se divise en deux plus petites"""
    a = math.radians(ang)
    x1, y1 = x0 + math.cos(a) * ln, y0 + math.sin(a) * ln
    nx, ny = -math.sin(a), math.cos(a)
    d.polygon([(x0 + nx * w0, y0 + ny * w0), (x1 + nx * w1, y1 + ny * w1),
               (x1 - nx * w1, y1 - ny * w1), (x0 - nx * w0, y0 - ny * w0)], fill=INK)
    d.ellipse([x1 - w1, y1 - w1, x1 + w1, y1 + w1], fill=INK)
    if depth > 0:
        for i, da in enumerate((-30, 26)):
            jitter = ((seed * 7 + i * 13) % 11) - 5
            _limb(d, x1, y1, ang + da + jitter, ln * 0.62, w1, max(4, w1 * 0.5), depth - 1, seed + i + 1)


def baobab(img):
    """Baobab à droite du soleil (le tireur est à gauche) : tronc énorme et renflé, couronne de branches courtes"""
    d = ImageDraw.Draw(img)
    bx, base = 1360, 1720
    top = 1120
    d.polygon([(bx - 250, base + 40), (bx - 225, base - 220), (bx - 160, top + 60), (bx - 120, top),
               (bx + 120, top), (bx + 165, top + 60), (bx + 230, base - 220), (bx + 260, base + 40)], fill=INK)
    for i, (ang, ln, w) in enumerate([(-172, 300, 50), (-145, 280, 54), (-118, 230, 52), (-90, 210, 50),
                                      (-62, 230, 52), (-35, 280, 54), (-8, 300, 50)]):
        _limb(d, bx + math.cos(math.radians(ang)) * 80, top + 24, ang, ln * 0.78, w * 0.9, w * 0.5, 2, i)


def ground(img):
    """Colline au pied du baobab"""
    d = ImageDraw.Draw(img)
    d.ellipse([-500, 1650, S + 500, 2900], fill=INK)


def title(img):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    dl, ds = ImageDraw.Draw(layer), ImageDraw.Draw(shadow)
    f = ImageFont.truetype(FONT, 455)
    txt = "GALSEN"
    w = dl.textlength(txt, font=f)
    x, y = (S - w) / 2, 150
    ds.text((x + 16, y + 30), txt, font=f, fill=(60, 0, 20, 160), stroke_width=40, stroke_fill=(60, 0, 20, 160))
    dl.text((x, y), txt, font=f, fill=(255, 255, 255), stroke_width=30, stroke_fill=INK)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))
    img.alpha_composite(layer)


def gunman(img):
    """Personnage du jeu, pistolet tendu, debout sur la colline à gauche du baobab : l'arme se découpe sur le soleil.
    Silhouette rendue par tools/pose_shot.gd (tools/silhouette_arme.png)."""
    sil = Image.open(os.path.join(ROOT, "tools", "silhouette_arme.png")).convert("RGBA")
    sil = sil.crop(sil.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox())
    h = 1000
    sil = sil.resize((round(sil.width * h / sil.height), h), Image.LANCZOS)
    a = sil.getchannel("A")
    flat = Image.new("RGBA", sil.size, INK + (255,))
    flat.putalpha(a)
    img.alpha_composite(flat, (200, 1740 - h))


def life_badge(img):
    """Pastille verte « LIFE » posée sur la colline"""
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, 300)
    txt = "LIFE"
    w = d.textlength(txt, font=f)
    bw, bh = w + 220, 330
    x0, y0 = (S - bw) / 2, 1560
    d.rounded_rectangle([x0 - 16, y0 - 16, x0 + bw + 16, y0 + bh + 16], radius=bh / 2 + 16, fill=YELLOW)
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=bh / 2, fill=GREEN)
    d.text(((S - w) / 2, y0 - 22), txt, font=f, fill=YELLOW)


def flag(img):
    d = ImageDraw.Draw(img)
    top = 1950
    w = S / 3
    for i, c in enumerate([GREEN, YELLOW, RED]):
        d.rectangle([i * w, top, (i + 1) * w, S], fill=c)


def main():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    background(img)
    rays(img)
    sun(img)
    baobab(img)
    ground(img)
    gunman(img)
    life_badge(img)
    flag(img)
    title(img)
    rgb = img.convert("RGB")
    os.makedirs(os.path.join(ROOT, "export"), exist_ok=True)
    rgb.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "export", "icon_512.png"))
    rgb.resize((1024, 1024), Image.LANCZOS).save(os.path.join(ROOT, "export", "icon_1024.png"))
    # Aperçu en petit (taille d'une icône sur l'écran d'accueil), pour juger la lisibilité
    rgb.resize((96, 96), Image.LANCZOS).save(os.path.join(ROOT, "export", "icon_96.png"))
    print("export/icon_512.png, export/icon_1024.png, export/icon_96.png")


if __name__ == "__main__":
    main()
