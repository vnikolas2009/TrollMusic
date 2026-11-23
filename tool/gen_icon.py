"""Генерирует иконку приложения (Android mipmap + iOS AppIcon).

Запуск из корня репозитория: python3 tool/gen_icon.py  (нужен Pillow).
"""
import glob
import math
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def master():
    # фон: диагональный градиент индиго → пурпур → розовый
    c0, c1, c2 = (24, 16, 56), (112, 48, 190), (236, 72, 153)
    bg = Image.new('RGB', (S, S))
    px = bg.load()
    for y in range(S):
        for x in range(S):
            t = (x * 0.35 + y * 0.65) / S
            px[x, y] = lerp(c0, c1, t / 0.6) if t < 0.6 else lerp(c1, c2, (t - 0.6) / 0.4)

    # мягкое свечение за эквалайзером
    glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((190, 250, 834, 800), fill=(255, 255, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    bg = Image.alpha_composite(bg.convert('RGBA'), glow)

    # «эквалайзер» из пяти столбиков, центральный выше всех
    bars = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(bars)
    heights = [250, 430, 600, 400, 300]
    w, gap = 96, 44
    total = len(heights) * w + (len(heights) - 1) * gap
    x = (S - total) // 2
    for h in heights:
        d.rounded_rectangle((x, S // 2 + h // 2 - h, x + w, S // 2 + h // 2),
                            radius=w // 2, fill=(255, 255, 255, 255))
        x += w + gap
    shadow = bars.filter(ImageFilter.GaussianBlur(26))
    shadow = Image.eval(shadow, lambda v: int(v * 0.35))
    out = Image.alpha_composite(bg, Image.merge('RGBA', (
        Image.new('L', (S, S), 0), Image.new('L', (S, S), 0),
        Image.new('L', (S, S), 40), shadow.split()[3])))
    return Image.alpha_composite(out, bars)


def rounded(im, radius_ratio=0.22):
    mask = Image.new('L', im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.size[0] - 1, im.size[1] - 1),
        radius=int(im.size[0] * radius_ratio), fill=255)
    out = im.copy()
    out.putalpha(mask)
    return out


def main():
    img = master()
    for f in glob.glob('android/app/src/main/res/mipmap-*/ic_launcher.png'):
        size = Image.open(f).size[0]
        rounded(img).resize((size, size), Image.LANCZOS).save(f)
    for f in glob.glob('ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png'):
        size = Image.open(f).size[0]
        # iOS не допускает прозрачность: углы скругляет система
        img.convert('RGB').resize((size, size), Image.LANCZOS).save(f)
    img.convert('RGB').resize((512, 512), Image.LANCZOS).save(
        os.path.join('tool', 'icon_preview.png'))


if __name__ == '__main__':
    main()
