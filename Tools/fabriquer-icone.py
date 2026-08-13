"""Icône : un écu tranché, soleil d'or et lune d'argent.

L'application fait deux choses sans rapport l'une avec l'autre — la vitamine D,
qui demande un Soleil haut, et le calage de l'horloge interne, qui demande la
lumière rasante du matin et la pénombre du soir. L'icône le dit d'un coup d'œil
en partageant le champ par une diagonale : au-dessus le Soleil resplendissant,
au-dessous la lune en croissant sur un ciel étoilé.

Le partage en diagonale porte un nom en héraldique — l'écu est dit *tranché* —
et c'est exactement le procédé employé pour figurer deux qualités d'une même
chose. Le trait d'or qui sépare les deux champs est la *trangle* de la partition.

Tout est tracé pixel par pixel, avec quatre échantillons par point pour adoucir
les bords : sans bibliothèque de dessin, remplir des polygones serait autrement
laborieux, et demander à chaque point son rayon et son angle suffit.
"""
import math
import struct
import zlib

SIZE = 1024
SAMPLES = 2                     # 2×2 échantillons par pixel

# Champs. Le jour et la nuit sont deux valeurs du même bleu : c'est une seule
# composition partagée, non deux images accolées.
AZURE_DAY = (46, 92, 168)
AZURE_DAY_DEEP = (26, 60, 124)
AZURE_NIGHT = (12, 24, 60)
AZURE_NIGHT_DEEP = (6, 12, 34)

GOLD = (226, 178, 74)
GOLD_LIGHT = (244, 214, 136)
GOLD_DARK = (135, 96, 30)

SILVER = (216, 222, 238)
SILVER_LIGHT = (241, 244, 252)
SILVER_DARK = (128, 138, 166)

# --- Partition -------------------------------------------------------------
# La diagonale va du coin bas-gauche au coin haut-droit : fx + fy = SIZE.
# Au-dessus (somme plus petite) le jour, au-dessous la nuit.
BAND_HALF = 9.0                 # demi-épaisseur du trait d'or

# --- Soleil ----------------------------------------------------------------
SUN_CX = SUN_CY = 356.0
SUN_DISC_R = 132.0
SUN_RAY_LONG = 300.0
SUN_RAY_SHORT = 246.0
SUN_RAY_COUNT = 16
SUN_RAY_HALF_WIDTH = 30.0

# --- Lune ------------------------------------------------------------------
# Un croissant est un disque moins un autre disque, décalé. Le décalage décide
# de l'épaisseur ; l'angle décide de l'orientation du croissant.
MOON_CX = MOON_CY = 668.0
MOON_R = 176.0
MOON_BITE_R = 158.0
MOON_BITE_ANGLE = math.radians(-38.0)
MOON_BITE_OFFSET = 118.0

OUTLINE = 6.0
TWO_PI = math.pi * 2
SUN_RAY_STEP = TWO_PI / SUN_RAY_COUNT

# Étoiles du champ de nuit : angle et rayon autour du centre de la lune, puis
# taille. Placées à la main — un semis aléatoire produit toujours des paquets.
STARS = [
    (2.55, 300, 21), (3.05, 226, 15), (3.45, 300, 18),
    (1.95, 268, 16), (1.35, 316, 14), (4.05, 268, 15),
    (2.80, 372, 13), (3.90, 352, 12),
]


def mix(a, b, t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def within_sun(x, y, grow):
    """Le point tombe-t-il dans le soleil, élargi de `grow` pixels ?"""
    dx, dy = x - SUN_CX, y - SUN_CY
    r = math.hypot(dx, dy)
    if r <= SUN_DISC_R + grow:
        return True
    if r > SUN_RAY_LONG + grow:
        return False
    theta = math.atan2(dy, dx) % TWO_PI
    index = round(theta / SUN_RAY_STEP)
    tip = (SUN_RAY_LONG if index % 2 == 0 else SUN_RAY_SHORT) + grow
    if r > tip:
        return False
    # Le rayon s'affine linéairement jusqu'à sa pointe.
    span = tip - SUN_DISC_R
    taper = 1.0 - (r - SUN_DISC_R) / span if span > 0 else 0.0
    half = (SUN_RAY_HALF_WIDTH + grow) * max(taper, 0.0)
    delta = abs(theta - index * SUN_RAY_STEP)
    if delta > math.pi:
        delta = TWO_PI - delta
    return delta * r <= half


def within_moon(x, y, grow):
    dx, dy = x - MOON_CX, y - MOON_CY
    if math.hypot(dx, dy) > MOON_R + grow:
        return False
    bx = MOON_CX + math.cos(MOON_BITE_ANGLE) * MOON_BITE_OFFSET
    by = MOON_CY + math.sin(MOON_BITE_ANGLE) * MOON_BITE_OFFSET
    return math.hypot(x - bx, y - by) > MOON_BITE_R - grow


def within_star(x, y, angle, radius, size, grow=0.0):
    sx = MOON_CX + math.cos(angle) * radius
    sy = MOON_CY + math.sin(angle) * radius
    dx, dy = x - sx, y - sy
    r = math.hypot(dx, dy)
    if r > size + grow:
        return False
    if r <= size * 0.22 + grow:
        return True
    step = TWO_PI / 6
    theta = math.atan2(dy, dx) % TWO_PI
    index = round(theta / step)
    taper = 1.0 - r / (size + grow)
    delta = abs(theta - index * step)
    if delta > math.pi:
        delta = TWO_PI - delta
    return delta * r <= (size * 0.30 + grow) * max(taper, 0.0)


def sample(fx, fy):
    """Couleur d'un point, en flottants."""
    # Distance signée à la diagonale, positive du côté de la nuit.
    side = (fx + fy - SIZE) / math.sqrt(2.0)

    # Le trait d'or de la partition passe avant tout le reste.
    if abs(side) <= BAND_HALF:
        return GOLD if abs(side) <= BAND_HALF - 2.5 else GOLD_DARK

    if side < 0:
        # --- Champ de jour ---
        if within_sun(fx, fy, 0.0):
            r = math.hypot(fx - SUN_CX, fy - SUN_CY)
            if r <= SUN_DISC_R - OUTLINE:
                # Le disque s'éclaircit vers son centre, comme une feuille d'or
                # bombée par le brunissoir.
                return mix(GOLD_LIGHT, GOLD, (r / SUN_DISC_R) ** 1.4)
            if r <= SUN_DISC_R:
                return GOLD_DARK
            return GOLD
        if within_sun(fx, fy, OUTLINE):
            return GOLD_DARK
        depth = math.hypot(fx - SUN_CX, fy - SUN_CY) / 620.0
        return mix(AZURE_DAY, AZURE_DAY_DEEP, depth ** 0.9)

    # --- Champ de nuit ---
    if within_moon(fx, fy, 0.0):
        r = math.hypot(fx - MOON_CX, fy - MOON_CY)
        if within_moon(fx, fy, -OUTLINE):
            return mix(SILVER_LIGHT, SILVER, (r / MOON_R) ** 1.2)
        return SILVER_DARK
    if within_moon(fx, fy, OUTLINE):
        return SILVER_DARK

    for angle, radius, size in STARS:
        if within_star(fx, fy, angle, radius, size):
            return SILVER
        if within_star(fx, fy, angle, radius, size, OUTLINE * 0.5):
            return SILVER_DARK

    depth = math.hypot(fx - MOON_CX, fy - MOON_CY) / 620.0
    return mix(AZURE_NIGHT, AZURE_NIGHT_DEEP, depth ** 0.9)


def pixel(x, y):
    """Moyenne de SAMPLES × SAMPLES échantillons, pour adoucir les bords."""
    total = [0.0, 0.0, 0.0]
    offset = 1.0 / (SAMPLES * 2)
    for i in range(SAMPLES):
        for j in range(SAMPLES):
            colour = sample(x + offset + i / SAMPLES, y + offset + j / SAMPLES)
            for k in range(3):
                total[k] += colour[k]
    count = SAMPLES * SAMPLES
    return bytes(max(0, min(255, round(c / count))) for c in total)


def write(path):
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            rows.extend(pixel(x, y))

    def chunk(tag, payload):
        body = tag + payload
        return (struct.pack(">I", len(payload)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)
    return len(png)


if __name__ == "__main__":
    import sys
    print(f"écrit : {sys.argv[1]}  ({write(sys.argv[1]) / 1024:.0f} Ko)")
