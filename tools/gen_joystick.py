"""Draws the touch joystick (modules/game_joystick) at 2x, in the style of
the touch UI's icon set (ot-client#28): a dark see-through disc with a light
ring, white arrows. Same names and proportions as the old art, so the
module's layout is unchanged.

    python3 tools/gen_joystick.py
"""
import math
from PIL import Image, ImageDraw

OUT = 'data/images/game/mobile/'
SS = 4  # drawn this much bigger, then scaled down (smooth edges)
RING = (220, 220, 220, 150)
DISC = (0, 0, 0, 90)
ARROW = (235, 235, 235, 235)


def canvas(size):
    return Image.new('RGBA', (size * SS, size * SS), (0, 0, 0, 0))


def save(image, size, name):
    image.resize((size, size), Image.LANCZOS).save(OUT + name + '.png')


def pad(size, arrows):
    """The base: disc, outer ring, inner ring; arrows on the stick's pad"""
    im = canvas(size)
    d = ImageDraw.Draw(im)
    s = size * SS
    w = 3 * SS
    d.ellipse((w, w, s - w, s - w), fill=DISC, outline=RING, width=w)
    inner = s * 0.27
    d.ellipse((s / 2 - inner, s / 2 - inner, s / 2 + inner, s / 2 + inner), outline=(220, 220, 220, 70), width=2 * SS)
    if arrows:
        for angle in (0, 90, 180, 270):
            triangle(d, s / 2, s / 2, s * 0.39, s * 0.075, angle, (220, 220, 220, 190))
    return im


def triangle(d, cx, cy, distance, half, angle, colour):
    """A triangle pointing outwards at `angle` (0 = up), `distance` from the
    centre"""
    a = math.radians(angle)
    ux, uy = math.sin(a), -math.cos(a)
    px, py = -uy, ux
    tip = (cx + ux * (distance + half), cy + uy * (distance + half))
    left = (cx + ux * (distance - half) + px * half * 1.2, cy + uy * (distance - half) + py * half * 1.2)
    right = (cx + ux * (distance - half) - px * half * 1.2, cy + uy * (distance - half) - py * half * 1.2)
    d.polygon([tip, left, right], fill=colour)


def arrow(size, angle):
    """One D-pad arrow: a white triangle filling its square, pointing at
    `angle`"""
    im = canvas(size)
    d = ImageDraw.Draw(im)
    s = size * SS
    triangle(d, s / 2, s / 2, 0, s * 0.3, angle, ARROW)
    return im


# stick: pad with arrows, and the knob
save(pad(300, True), 300, 'keypad')
knob = canvas(98)
d = ImageDraw.Draw(knob)
s = 98 * SS
d.ellipse((2 * SS, 2 * SS, s - 2 * SS, s - 2 * SS), fill=(200, 200, 200, 170), outline=(255, 255, 255, 200), width=3 * SS)
save(knob, 98, 'keypad_pointer')

# D-pad: the pad without arrows (they are separate widgets that light up)
dpad = pad(300, False)
d = ImageDraw.Draw(dpad)
s = 300 * SS
d.ellipse((s / 2 - 10 * SS, s / 2 - 10 * SS, s / 2 + 10 * SS, s / 2 + 10 * SS), outline=RING, width=2 * SS)
save(dpad, 300, 'dpad')
for name, angle in (('n', 0), ('ne', 45), ('e', 90), ('se', 135), ('s', 180), ('sw', 225), ('w', 270), ('nw', 315)):
    save(arrow(80, angle), 80, 'dpad_' + name)
