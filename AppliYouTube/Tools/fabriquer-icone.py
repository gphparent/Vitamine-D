"""Icône : un bouton de lecture derrière un sceau d'approbation.

L'appli ne montre que ce qu'un juge a approuvé. L'icône dit la même chose : la
lecture, oui, mais marquée d'un sceau.

Chaque pixel demande son appartenance à chaque forme (rectangle arrondi,
triangle, disque, coche) et les couleurs se superposent dans l'ordre. Quatre
échantillons par pixel suffisent à adoucir les bords.

    python Tools/fabriquer-icone.py
"""
import math
import struct
import zlib

SIZE = 1024
SAMPLES = 2                     # 2×2 échantillons par pixel
SORTIE = "AppliYouTube/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

FOND_HAUT = (24, 26, 38)
FOND_BAS = (40, 30, 44)
ECRAN = (196, 52, 48)
ECRAN_OMBRE = (150, 36, 38)
BLANC = (250, 248, 244)
SCEAU = (64, 150, 96)
SCEAU_BORD = (236, 244, 238)

# Écran : rectangle arrondi centré un peu au-dessus du milieu.
EX0, EY0, EX1, EY1, ER = 172.0, 262.0, 852.0, 742.0, 120.0
# Triangle de lecture.
TRI = [(430.0, 382.0), (430.0, 622.0), (630.0, 502.0)]
# Sceau : disque en bas à droite, avec sa coche.
SX, SY, SR, SBORD = 764.0, 762.0, 150.0, 22.0
COCHE = [(690.0, 766.0), (744.0, 820.0), (842.0, 712.0)]
COCHE_EP = 30.0


def dans_rect_arrondi(x, y):
    cx = min(max(x, EX0 + ER), EX1 - ER)
    cy = min(max(y, EY0 + ER), EY1 - ER)
    return (x - cx) ** 2 + (y - cy) ** 2 <= ER ** 2 and EX0 <= x <= EX1 and EY0 <= y <= EY1


def dans_triangle(x, y):
    (ax, ay), (bx, by), (cx, cy) = TRI
    d1 = (x - bx) * (ay - by) - (ax - bx) * (y - by)
    d2 = (x - cx) * (by - cy) - (bx - cx) * (y - cy)
    d3 = (x - ax) * (cy - ay) - (cx - ax) * (y - ay)
    neg = d1 < 0 or d2 < 0 or d3 < 0
    pos = d1 > 0 or d2 > 0 or d3 > 0
    return not (neg and pos)


def distance_segment(x, y, a, b):
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (ax + t * dx), y - (ay + t * dy))


def couleur(x, y):
    t = y / SIZE
    c = tuple(FOND_HAUT[i] + (FOND_BAS[i] - FOND_HAUT[i]) * t for i in range(3))
    if dans_rect_arrondi(x, y):
        # Léger dégradé vers le bas de l'écran.
        u = (y - EY0) / (EY1 - EY0)
        c = tuple(ECRAN[i] + (ECRAN_OMBRE[i] - ECRAN[i]) * u for i in range(3))
        if dans_triangle(x, y):
            c = BLANC
    d = math.hypot(x - SX, y - SY)
    if d <= SR + SBORD:
        c = SCEAU_BORD
    if d <= SR:
        c = SCEAU
        if min(distance_segment(x, y, COCHE[0], COCHE[1]),
               distance_segment(x, y, COCHE[1], COCHE[2])) <= COCHE_EP / 2:
            c = BLANC
    return c


def pixel(px, py):
    total = [0.0, 0.0, 0.0]
    for sx in range(SAMPLES):
        for sy in range(SAMPLES):
            c = couleur(px + (sx + 0.5) / SAMPLES, py + (sy + 0.5) / SAMPLES)
            for i in range(3):
                total[i] += c[i]
    n = SAMPLES * SAMPLES
    return bytes(int(round(v / n)) for v in total)


def png(largeur, hauteur, lignes):
    def bloc(type_, donnees):
        return (struct.pack(">I", len(donnees)) + type_ + donnees
                + struct.pack(">I", zlib.crc32(type_ + donnees) & 0xFFFFFFFF))
    brut = b"".join(b"\x00" + ligne for ligne in lignes)
    return (b"\x89PNG\r\n\x1a\n"
            + bloc(b"IHDR", struct.pack(">IIBBBBB", largeur, hauteur, 8, 2, 0, 0, 0))
            + bloc(b"IDAT", zlib.compress(brut, 9))
            + bloc(b"IEND", b""))


if __name__ == "__main__":
    lignes = [b"".join(pixel(x, y) for x in range(SIZE)) for y in range(SIZE)]
    with open(SORTIE, "wb") as f:
        f.write(png(SIZE, SIZE, lignes))
    print("Icône écrite :", SORTIE)
