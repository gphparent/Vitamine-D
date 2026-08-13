"""Icône : un soleil héraldique d'or sur champ d'azur semé d'étoiles.

Le motif est celui du blason — « soleil resplendissant », disque cerné de
rayons alternant longs et courts — posé sur le bleu de lapis des enluminures,
parsemé d'étoiles à six branches comme la voûte céleste des manuscrits.

Tout est tracé pixel par pixel : pour chaque point, on demande son rayon et son
angle, puis on regarde s'il tombe dans un rayon du soleil. Cela évite de
remplir des polygones, ce qui serait autrement laborieux sans bibliothèque.
"""
import math
import struct
import zlib

SIZE = 1024
CX = CY = 512.0

AZURE_DEEP = (14, 34, 82)
AZURE_LIGHT = (30, 62, 126)
GOLD = (226, 178, 74)
GOLD_LIGHT = (244, 214, 136)
GOLD_DARK = (135, 96, 30)

DISC_R = 196.0          # rayon du disque
RAY_LONG = 452.0        # pointe des rayons longs
RAY_SHORT = 366.0       # pointe des rayons courts
RAY_COUNT = 16
RAY_HALF_WIDTH = 44.0   # demi-largeur d'un rayon à sa base
OUTLINE = 7.0           # épaisseur du trait de contour

TWO_PI = math.pi * 2
RAY_STEP = TWO_PI / RAY_COUNT

# Étoiles du champ : angle, rayon, taille. Placées à la main pour équilibrer
# la composition — un semis aléatoire produit toujours des paquets.
STARS = [
    (0.20, 610, 26), (0.95, 665, 21), (1.62, 600, 24), (2.35, 672, 20),
    (3.02, 606, 25), (3.78, 668, 21), (4.45, 598, 23), (5.20, 664, 22),
    (0.58, 448, 17), (2.72, 452, 16), (4.86, 446, 17),
]


def mix(a, b, t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def within_sun(r, theta, grow):
    """Le point tombe-t-il dans le soleil, élargi de `grow` pixels ?"""
    if r <= DISC_R + grow:
        return True
    index = round(theta / RAY_STEP)
    tip = RAY_LONG if index % 2 == 0 else RAY_SHORT
    tip += grow
    if r > tip:
        return False
    # Le rayon s'affine linéairement jusqu'à sa pointe.
    span = tip - DISC_R
    taper = 1.0 - (r - DISC_R) / span if span > 0 else 0.0
    half = (RAY_HALF_WIDTH + grow) * max(taper, 0.0)
    delta = abs(theta - index * RAY_STEP)
    if delta > math.pi:
        delta = TWO_PI - delta
    return delta * r <= half


def within_star(x, y, angle, radius, size, grow=0.0):
    sx = CX + math.cos(angle) * radius
    sy = CY + math.sin(angle) * radius
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


def pixel(x, y):
    fx, fy = x + 0.5, y + 0.5
    dx, dy = fx - CX, fy - CY
    r = math.hypot(dx, dy)
    theta = math.atan2(dy, dx) % TWO_PI

    if within_sun(r, theta, 0.0):
        if r <= DISC_R - OUTLINE:
            # Le disque s'éclaircit vers son centre, comme une feuille d'or
            # bombée par le brunissoir.
            return mix(GOLD_LIGHT, GOLD, (r / DISC_R) ** 1.4)
        if r <= DISC_R:
            return GOLD_DARK          # cerne du disque
        return GOLD

    if within_sun(r, theta, OUTLINE):
        return GOLD_DARK              # trait de contour des rayons

    for angle, radius, size in STARS:
        if within_star(fx, fy, angle, radius, size):
            return GOLD
        if within_star(fx, fy, angle, radius, size, OUTLINE * 0.5):
            return GOLD_DARK

    # Champ d'azur, légèrement plus clair au centre pour donner du relief.
    return mix(AZURE_LIGHT, AZURE_DEEP, (r / 720.0) ** 0.8)


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
