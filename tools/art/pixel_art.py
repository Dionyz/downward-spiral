"""Original pixel art drawn in code for Downward Spiral, where the DCSS CC0 set has nothing that
fits: white UI glyphs, the smaller status icons, the melee slash / heal / level-up effects, the UI
9-patch skin and the title logo. Everything here is released under CC0 1.0 like the rest of the
placeholders. Imported by import_placeholders.py; each function returns a PIL RGBA image.

Drawn with hard pixels only: no anti-aliasing, so the game can scale it by whole multiples."""
import math
from PIL import Image, ImageDraw, ImageFont

OUTLINE = (11, 10, 14, 255)
WHITE = (255, 255, 255, 255)
SHADE = (196, 196, 204, 255)      # bottom-right edge of a white glyph (still tints cleanly)


def _canvas(n=32):
    return Image.new("RGBA", (n, n), (0, 0, 0, 0))


def outline(img, col=OUTLINE):
    """1 px dark outline around every opaque pixel (4-neighbour)."""
    w, h = img.size
    src = img.load()
    out = img.copy()
    dst = out.load()
    for y in range(h):
        for x in range(w):
            if src[x, y][3] > 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and src[nx, ny][3] > 0:
                    dst[x, y] = col
                    break
    return out


def _shade_white(img):
    """Grey the white pixels that have no white pixel below-right: a 1 px pixel-art bevel."""
    w, h = img.size
    px = img.load()
    snap = img.copy().load()
    for y in range(h):
        for x in range(w):
            if snap[x, y] == WHITE:
                below = snap[x, y + 1] if y + 1 < h else (0, 0, 0, 0)
                right = snap[x + 1, y] if x + 1 < w else (0, 0, 0, 0)
                if below != WHITE or right != WHITE:
                    px[x, y] = SHADE
    return img


def _glyph(draw_fn):
    img = _canvas()
    d = ImageDraw.Draw(img)
    draw_fn(d)
    return outline(_shade_white(img))


# --- white tintable UI glyphs (32 x 32) ----------------------------------------------

def glyph_up():
    return _glyph(lambda d: (d.polygon([(16, 4), (28, 17), (21, 17), (21, 28), (11, 28), (11, 17), (4, 17)], fill=WHITE)))


def glyph_down():
    return glyph_up().transpose(Image.FLIP_TOP_BOTTOM)


def glyph_check():
    return _glyph(lambda d: d.polygon([(3, 16), (8, 11), (13, 16), (24, 5), (29, 10), (13, 26)], fill=WHITE))


def glyph_grip():
    def f(d):
        for cx in (10, 18):
            for cy in (6, 14, 22):
                d.rectangle([cx, cy, cx + 4, cy + 4], fill=WHITE)
    return _glyph(f)


def glyph_upgrade():
    # Double chevron pointing up: reads as "better" even at 16 px.
    def f(d):
        for top in (3, 14):
            d.polygon([(16, top), (29, top + 13), (23, top + 13), (16, top + 6), (9, top + 13), (3, top + 13)], fill=WHITE)
    return _glyph(f)


def glyph_star():
    pts = []
    for i in range(10):
        r = 14 if i % 2 == 0 else 6
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((16 + r * math.cos(a), 17 + r * math.sin(a)))
    return _glyph(lambda d: d.polygon(pts, fill=WHITE))


def glyph_boon():
    # Four-pointed sparkle with a small gem in the middle.
    def f(d):
        d.polygon([(16, 2), (19, 13), (30, 16), (19, 19), (16, 30), (13, 19), (2, 16), (13, 13)], fill=WHITE)
        d.polygon([(25, 4), (26, 7), (29, 8), (26, 9), (25, 12), (24, 9), (21, 8), (24, 7)], fill=WHITE)
    return _glyph(f)


def glyph_family():
    # A heater shield: the generic boon-family badge.
    def f(d):
        d.polygon([(5, 4), (27, 4), (27, 16), (24, 23), (16, 29), (8, 23), (5, 16)], fill=WHITE)
    img = _glyph(f)
    d = ImageDraw.Draw(img)
    d.line([(16, 8), (16, 23)], fill=OUTLINE)
    d.line([(9, 13), (23, 13)], fill=OUTLINE)
    return img


def glyph_trophy():
    def f(d):
        d.rectangle([9, 4, 23, 6], fill=WHITE)
        d.polygon([(9, 6), (23, 6), (22, 13), (19, 17), (13, 17), (10, 13)], fill=WHITE)
        d.rectangle([14, 17, 18, 22], fill=WHITE)
        d.rectangle([10, 23, 22, 27], fill=WHITE)
        for x0 in (4, 24):
            d.rectangle([x0, 6, x0 + 3, 8], fill=WHITE)
            d.rectangle([x0 if x0 == 4 else x0 + 2, 6, (x0 + 1) if x0 == 4 else x0 + 3, 12], fill=WHITE)
        d.line([(6, 12), (9, 13)], fill=WHITE, width=2)
        d.line([(23, 13), (26, 12)], fill=WHITE, width=2)
    return _glyph(f)


GLYPHS = {"ui_up": glyph_up, "ui_down": glyph_down, "ui_check": glyph_check, "ui_grip": glyph_grip,
          "ui_upgrade": glyph_upgrade, "ui_star": glyph_star, "ui_family": glyph_family, "boon": glyph_boon,
          "town_trophy": glyph_trophy}


# --- status icons (16 x 16, full colour) ---------------------------------------------------

Y, Y2 = (255, 224, 74, 255), (255, 250, 200, 255)
O = (255, 140, 40, 255)
R, R2, R3 = (208, 40, 40, 255), (255, 120, 110, 255), (120, 16, 24, 255)
C, C2 = (120, 210, 255, 255), (230, 250, 255, 255)
B, B2 = (60, 110, 220, 255), (150, 190, 255, 255)
G, G2 = (110, 200, 70, 255), (40, 110, 40, 255)
P, P2 = (170, 90, 230, 255), (240, 160, 255, 255)
S, S2, S3 = (150, 150, 160, 255), (210, 210, 220, 255), (90, 90, 100, 255)
N = (130, 90, 50, 255)
GOLD, GOLD2 = (214, 166, 79, 255), (255, 220, 130, 255)


def _status(draw_fn):
    img = _canvas(16)
    draw_fn(ImageDraw.Draw(img), img)
    return outline(img)


def _plus_star(d, x, y, col=Y, core=Y2):
    d.point([(x, y - 1), (x - 1, y), (x + 1, y), (x, y + 1)], fill=col)
    d.point((x, y), fill=core)


def st_stunned():
    def f(d, img):
        d.ellipse([1, 5, 14, 12], outline=O)
        for x, y in ((3, 7), (12, 7), (8, 11), (8, 4)):
            _plus_star(d, x, y)
    return _status(f)


def st_knocked_down():
    def f(d, img):
        d.rectangle([1, 12, 14, 13], fill=N)
        d.polygon([(4, 2), (11, 2), (11, 5), (14, 5), (7.5, 10), (1, 5), (4, 5)], fill=O)
    return _status(f)


def st_bleeding():
    def f(d, img):
        d.polygon([(7, 1), (8, 1), (12, 8), (3, 8)], fill=R)
        d.ellipse([3, 5, 12, 14], fill=R)
        d.point([(5, 9), (5, 10), (6, 8)], fill=R2)
        d.point([(10, 12), (9, 13)], fill=R3)
    return _status(f)


def st_slowed():
    def f(d, img):
        d.rectangle([2, 1, 13, 2], fill=N)
        d.rectangle([2, 13, 13, 14], fill=N)
        d.polygon([(3, 3), (12, 3), (8, 8), (7, 8)], fill=B2)
        d.polygon([(7, 8), (8, 8), (12, 12), (3, 12)], fill=B2)
        d.polygon([(5, 4), (10, 4), (8, 7), (7, 7)], fill=Y)
        d.polygon([(7, 10), (8, 10), (11, 12), (4, 12)], fill=Y)
    return _status(f)


def st_frozen():
    def f(d, img):
        d.line([(7, 1), (7, 14)], fill=C)
        d.line([(1, 7), (14, 7)], fill=C)
        d.line([(3, 3), (12, 12)], fill=C)
        d.line([(3, 12), (12, 3)], fill=C)
        d.point([(6, 2), (8, 2), (6, 13), (8, 13), (2, 6), (2, 8), (13, 6), (13, 8)], fill=C2)
        d.rectangle([6, 6, 8, 8], fill=C2)
    return _status(f)


def st_transfixed():
    def f(d, img):
        d.ellipse([1, 1, 14, 14], outline=P)
        d.ellipse([4, 4, 11, 11], outline=P2)
        d.rectangle([7, 7, 8, 8], fill=P)
    return _status(f)


def st_dazed():
    def f(d, img):
        for y in (3, 7, 11):
            d.line([(2, y + 1), (4, y), (6, y + 1), (8, y), (10, y + 1), (12, y)], fill=Y)
        d.point((13, y), fill=Y2)
    return _status(f)


def st_armor():
    def f(d, img):
        d.polygon([(2, 2), (5, 2), (7, 4), (8, 4), (10, 2), (13, 2), (13, 7), (12, 13), (3, 13), (2, 7)], fill=S)
        d.line([(4, 4), (4, 11)], fill=S2)
        d.line([(7, 6), (7, 12)], fill=S3)
        d.line([(3, 9), (12, 9)], fill=S3)
    return _status(f)


def st_shield():
    def f(d, img):
        d.polygon([(2, 1), (13, 1), (13, 8), (8, 14), (7, 14), (2, 8)], fill=GOLD)
        d.polygon([(4, 3), (11, 3), (11, 8), (8, 12), (7, 12), (4, 8)], fill=B)
        d.line([(5, 4), (5, 8)], fill=B2)
    return _status(f)


def st_sanctuary():
    def f(d, img):
        d.ellipse([1, 1, 14, 14], outline=GOLD2)
        d.ellipse([2, 2, 13, 13], outline=GOLD)
        d.line([(7, 4), (7, 11)], fill=WHITE)
        d.line([(8, 4), (8, 11)], fill=WHITE)
        d.line([(5, 6), (10, 6)], fill=WHITE)
    return _status(f)


def st_warcry():
    def f(d, img):
        d.rectangle([6, 2, 9, 9], fill=R)
        d.rectangle([6, 11, 9, 13], fill=R)
        d.line([(6, 2), (6, 8)], fill=R2)
        for a, b in (((1, 3), (3, 5)), ((14, 3), (12, 5)), ((1, 11), (3, 10)), ((14, 11), (12, 10))):
            d.line([a, b], fill=O)
    return _status(f)


def st_envenomed():
    def f(d, img):
        d.line([(3, 12), (12, 3)], fill=S2, width=2)
        d.line([(12, 3), (13, 2)], fill=WHITE)
        d.rectangle([2, 11, 4, 13], fill=N)
        d.line([(1, 10), (5, 14)], fill=GOLD)
        d.point([(9, 7), (10, 8), (10, 9), (6, 10)], fill=G)
        d.point([(10, 10)], fill=G2)
    return _status(f)


# Drawn here only where DCSS has no status overlay (see import_placeholders.py STATUS).
STATUS_DRAWN = {"stunned": st_stunned, "knocked_down": st_knocked_down, "bleeding": st_bleeding,
                "slowed": st_slowed, "frozen": st_frozen, "transfixed": st_transfixed, "dazed": st_dazed,
                "armor": st_armor, "shield": st_shield, "sanctuary": st_sanctuary, "warcry": st_warcry,
                "envenomed": st_envenomed}


def crop_status(src_img):
    """A DCSS corner status icon (a few pixels in a 32 x 32 tile) centered on a 16 x 16 canvas."""
    box = src_img.getbbox()
    part = src_img.crop(box)
    out = _canvas(16)
    out.alpha_composite(part, ((16 - part.width) // 2, (16 - part.height) // 2))
    return out


# --- effect frames (32 x 32) ------------------------------------------------------------

def fx_slash(frame):
    """Melee slash: a white arc sweeping top-right to bottom-left over 3 frames."""
    img = _canvas()
    d = ImageDraw.Draw(img)
    spans = [(-80, -20), (-80, 70), (10, 80)]
    widths = [3, 4, 2]
    a0, a1 = spans[frame]
    box = [2, 2, 29, 29]
    d.arc(box, a0, a1, fill=(200, 210, 230, 255), width=widths[frame] + 1)
    d.arc([box[0] + 1, box[1] + 1, box[2] - 1, box[3] - 1], a0, a1, fill=WHITE, width=max(1, widths[frame] - 1))
    if frame == 1:
        d.arc([5, 5, 26, 26], -60, 50, fill=(255, 120, 110, 255), width=1)
    return img


def fx_heal(frame):
    """Green crosses rising and fading: 3 frames."""
    img = _canvas()
    d = ImageDraw.Draw(img)
    spots = [(8, 22), (20, 18), (14, 26), (24, 25), (11, 14)]
    col = [(140, 255, 140, 255), (95, 211, 95, 255), (60, 150, 60, 200)][frame]
    for i, (x, y) in enumerate(spots):
        y -= frame * 5 + (i % 2) * 2
        s = 2 if (i + frame) % 2 == 0 else 1
        if y < 2:
            continue
        d.line([(x - s, y), (x + s, y)], fill=col)
        d.line([(x, y - s), (x, y + s)], fill=col)
        if s == 2:
            d.point((x, y), fill=WHITE)
    return img


def fx_levelup(frame):
    """Golden ring expanding with sparkles: 4 frames."""
    img = _canvas()
    d = ImageDraw.Draw(img)
    r = [5, 9, 12, 14][frame]
    col = [GOLD2, GOLD2, GOLD, (214, 166, 79, 150)][frame]
    d.ellipse([16 - r, 16 - r, 15 + r, 15 + r], outline=col, width=2 if frame < 2 else 1)
    for i in range(8):
        a = i * math.pi / 4 + frame * 0.3
        rr = r + 2 + frame
        x, y = int(16 + rr * math.cos(a)), int(16 + rr * math.sin(a))
        if 1 <= x <= 30 and 1 <= y <= 30:
            _plus_star(d, x, y, GOLD2, WHITE)
    if frame == 0:
        d.rectangle([14, 14, 17, 17], fill=WHITE)
    return img


FX_DRAWN = {"slash": (fx_slash, 3), "heal": (fx_heal, 3), "levelup": (fx_levelup, 4)}


# --- UI skin: 9-patch textures (documented margins in ART_SPEC.md) ------------------------

def _hex(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def nine_box(size, fill, light, dark, edge, notch=True):
    """A bevelled box: dark outer edge, light top-left inner line, dark bottom-right inner line,
    flat fill. Corners are notched (one transparent pixel) for a pixel-art look."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    n = size - 1
    d.rectangle([0, 0, n, n], fill=edge)
    d.rectangle([1, 1, n - 1, n - 1], fill=fill)
    d.line([(1, 1), (n - 1, 1)], fill=light)
    d.line([(1, 1), (1, n - 1)], fill=light)
    d.line([(1, n - 1), (n - 1, n - 1)], fill=dark)
    d.line([(n - 1, 1), (n - 1, n - 1)], fill=dark)
    if notch:
        for p in ((0, 0), (n, 0), (0, n), (n, n)):
            img.putpixel(p, (0, 0, 0, 0))
    return img


def ui_panel():
    img = nine_box(16, _hex("1a1822"), _hex("2e2a3a"), _hex("121016"), _hex("0b0a0e"))
    # Small gold rivets in the corners.
    for p in ((2, 2), (13, 2), (2, 13), (13, 13)):
        img.putpixel(p, _hex("6b5530"))
    return img


def ui_popup():
    """Tips and tutorial cards: the panel with a gold edge."""
    img = nine_box(16, _hex("221f2b"), _hex("3a3446"), _hex("15131a"), _hex("d6a64f"))
    for p in ((1, 1), (14, 1), (1, 14), (14, 14)):
        img.putpixel(p, _hex("ffe08a"))
    return img


def ui_button(state):
    spec = {
        "normal": ("231f2d", "3d374b", "141219", "0b0a0e"),
        "hover": ("2d2839", "4e4660", "191620", "8a6a32"),
        "pressed": ("16141c", "0f0e13", "3a3446", "d6a64f"),
        "disabled": ("15131a", "1d1a24", "101014", "0b0a0e"),
    }[state]
    return nine_box(16, *(_hex(c) for c in spec))


def ui_chip():
    return nine_box(12, _hex("16141c"), _hex("26222f"), _hex("0f0e13"), _hex("0b0a0e"))


def ui_bar_bg():
    return nine_box(8, _hex("2b2733"), _hex("1b1820"), _hex("3a3446"), _hex("0b0a0e"), notch=False)


def ui_bar_fill(col_hex):
    base = _hex(col_hex)
    hi = tuple(min(255, int(c * 1.35 + 20)) for c in base[:3]) + (255,)
    lo = tuple(int(c * 0.65) for c in base[:3]) + (255,)
    img = Image.new("RGBA", (8, 8), base)
    d = ImageDraw.Draw(img)
    d.line([(0, 1), (7, 1)], fill=hi)
    d.line([(0, 6), (7, 6)], fill=lo)
    d.line([(0, 7), (7, 7)], fill=lo)
    d.line([(0, 0), (7, 0)], fill=hi)
    return img


# (file name, builder, 9-patch margin in source pixels)
UI_SKIN = [
    ("panel", ui_panel, 4), ("chip", ui_chip, 3), ("popup", ui_popup, 4),
    ("button", lambda: ui_button("normal"), 4), ("button_hover", lambda: ui_button("hover"), 4),
    ("button_pressed", lambda: ui_button("pressed"), 4), ("button_disabled", lambda: ui_button("disabled"), 4),
    ("bar_bg", ui_bar_bg, 2), ("bar_hp", lambda: ui_bar_fill("c0392b"), 2),
    ("bar_mana", lambda: ui_bar_fill("2e6fd1"), 2), ("bar_xp", lambda: ui_bar_fill("d6a64f"), 2),
    ("bar_enemy", lambda: ui_bar_fill("8e3b2f"), 2), ("bar_shield", lambda: ui_bar_fill("9fd8ff"), 2),
]


# --- title logo -----------------------------------------------------------------------------

def title_logo(font_path):
    """'DOWNWARD SPIRAL' in a pixel font, gold with a dark outline and drop shadow. 192 x 56."""
    W, H = 192, 56
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    font = ImageFont.truetype(font_path, 40)
    lines = ["DOWNWARD", "SPIRAL"]
    text = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(text)
    y = 2
    boxes = []
    for ln in lines:
        bb = d.textbbox((0, 0), ln, font=font)
        w = bb[2] - bb[0]
        x = (W - w) // 2 - bb[0]
        d.text((x, y - bb[1]), ln, font=font, fill=WHITE)
        boxes.append((y, bb[3] - bb[1]))
        y += bb[3] - bb[1] + 6
    # Hard-threshold the glyphs (no anti-aliasing), then colour by row: a 3-step gold ramp.
    px = text.load()
    ramp = [_hex("ffe08a"), _hex("f0c060"), _hex("d6a64f"), _hex("a87a32")]
    for yy in range(H):
        for xx in range(W):
            if px[xx, yy][3] >= 128:
                row_y, row_h = next(((by, bh) for by, bh in boxes if by <= yy < by + bh + 6), boxes[-1])
                t = (yy - row_y) / max(1, row_h)
                px[xx, yy] = ramp[min(3, max(0, int(t * 4)))]
            else:
                px[xx, yy] = (0, 0, 0, 0)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sp = shadow.load()
    for yy in range(H):
        for xx in range(W):
            if px[xx, yy][3] and xx + 2 < W and yy + 2 < H:
                sp[xx + 2, yy + 2] = _hex("3a1d10")
    img.alpha_composite(shadow)
    img.alpha_composite(outline(text))
    return img
