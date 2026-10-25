"""Generates the 32x32 icons for the action bar's targeting and general
special actions (data/images/game/actionbar/actions/*.png) from images the
client already ships: a target symbol (monster, players, skull, party), the
sword, hand or eye from the mobile action buttons, and a small badge.

    python3 tools/gen_action_icons.py
"""
import os

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), "..", "data", "images", "game")
OUT = os.path.join(ROOT, "actionbar", "actions")
SIZE = 32


def load(path):
    return Image.open(os.path.join(ROOT, path)).convert("RGBA")


def crop_symbol(path, box):
    """The picture part of a mobile button image (without its text label)."""
    return load(path).crop(box)


def fit(image, size):
    image = image.copy()
    scale = size / max(image.size)
    return image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))),
                        Image.NEAREST if scale >= 1 else Image.LANCZOS)


SWORD = crop_symbol("mobile/attack.png", (2, 0, 46, 34))
FOLLOW = crop_symbol("mobile/follow.png", (10, 0, 38, 34))
HAND = crop_symbol("mobile/use.png", (6, 0, 42, 36))
EYE = crop_symbol("mobile/look.png", (0, 6, 48, 30))
TARGETS = {
    "monster": load("battle/icon-battlelist-monster.png"),
    "players": load("battle/icon-battlelist-players.png"),
    "skull": load("battle/icon-battlelist-skull.png"),
    "party": load("battle/icon-battlelist-party.png"),
}

# 5x7 pixel glyphs for the badges
GLYPHS = {
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "F": ["11111", "10000", "11110", "10000", "10000", "10000", "10000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
}


def badge(canvas, text, color):
    """A small rounded label in the bottom-left corner."""
    width = len(text) * 6 + 3
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((0, SIZE - 11, width, SIZE - 1), radius=2, fill=(0, 0, 0, 220), outline=color)
    for i, char in enumerate(text):
        for y, row in enumerate(GLYPHS[char]):
            for x, bit in enumerate(row):
                if bit == "1":
                    canvas.putpixel((2 + i * 6 + x, SIZE - 9 + y), color)


def paste(canvas, image, size, position):
    image = fit(image, size)
    canvas.alpha_composite(image, position)


def target_icon(target, letter, color):
    canvas = Image.new("RGBA", (SIZE, SIZE))
    paste(canvas, TARGETS[target], 20, (1, 0))
    paste(canvas, SWORD, 18, (14, 12))
    badge(canvas, letter, color)
    return canvas


def crosshair(canvas):
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((17, 1, 31, 15), outline=(255, 80, 80, 255), width=2)
    draw.line((24, 0, 24, 16), fill=(255, 80, 80, 255))
    draw.line((16, 8, 32, 8), fill=(255, 80, 80, 255))


def main():
    os.makedirs(OUT, exist_ok=True)
    gold = (240, 200, 80, 255)
    green = (110, 220, 110, 255)
    red = (240, 90, 90, 255)
    blue = (120, 170, 255, 255)
    icons = {
        "attackNearestMonster": target_icon("monster", "N", gold),
        "attackFurthestMonster": target_icon("monster", "F", gold),
        "attackHighestHpMonster": target_icon("monster", "+", green),
        "attackLowestHpMonster": target_icon("monster", "-", red),
        "cycleMonster": target_icon("monster", "C", blue),
        "attackNearestPlayer": target_icon("players", "N", gold),
        "attackFurthestPlayer": target_icon("players", "F", gold),
        "attackHighestHpPlayer": target_icon("players", "+", green),
        "attackLowestHpPlayer": target_icon("players", "-", red),
        "cyclePlayer": target_icon("players", "C", blue),
        "attackSkulled": target_icon("skull", "C", blue),
        "attackYellowSkull": target_icon("skull", "Y", gold),
        "attackNonParty": target_icon("party", "!", red),
    }

    follow = Image.new("RGBA", (SIZE, SIZE))
    paste(follow, TARGETS["players"], 16, (0, 0))
    paste(follow, FOLLOW, 26, (10, 2))
    badge(follow, "N", gold)
    icons["followNearestPlayer"] = follow

    stop = Image.new("RGBA", (SIZE, SIZE))
    paste(stop, SWORD, 28, (2, 2))
    draw = ImageDraw.Draw(stop)
    draw.line((4, 4, 28, 28), fill=red, width=4)
    draw.line((28, 4, 4, 28), fill=red, width=4)
    icons["stopAttack"] = stop

    coins = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(coins)
    for i, (x, y) in enumerate([(4, 14), (12, 10), (8, 4)]):
        draw.ellipse((x, y, x + 16, y + 12), fill=(214, 168, 40, 255), outline=(120, 80, 10, 255))
        draw.ellipse((x + 4, y + 3, x + 12, y + 9), outline=(255, 230, 120, 255))
    draw.polygon([(24, 22), (31, 26), (24, 30)], fill=(255, 255, 255, 255))
    icons["convertCurrency"] = coins

    for name, symbol in (("useAtCrosshair", HAND), ("lookAtCrosshair", EYE)):
        canvas = Image.new("RGBA", (SIZE, SIZE))
        paste(canvas, symbol, 26, (0, 5))
        crosshair(canvas)
        icons[name] = canvas

    menu = Image.new("RGBA", (SIZE, SIZE))
    draw = ImageDraw.Draw(menu)
    draw.rounded_rectangle((2, 8, 24, 30), radius=3, fill=(40, 40, 40, 255), outline=(200, 200, 200, 255))
    for y in (13, 18, 23):
        draw.line((6, y, 20, y), fill=(220, 220, 220, 255), width=2)
    crosshair(menu)
    icons["contextMenuAtCrosshair"] = menu

    for name, image in icons.items():
        image.save(os.path.join(OUT, name + ".png"))
    print(f"{len(icons)} icons in {OUT}")


if __name__ == "__main__":
    main()
