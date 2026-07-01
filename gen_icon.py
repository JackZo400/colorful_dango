from PIL import Image, ImageDraw, ImageFilter
import math, os

S = 512
img = Image.new('RGBA', (S, S), (0,0,0,0))
draw = ImageDraw.Draw(img)

# 背景：软渐变圆
for y in range(S):
    for x in range(S):
        dx, dy = x - S/2, y - S/2
        d = math.sqrt(dx*dx + dy*dy)
        if d < S/2 - 8:
            t = d / (S/2)  # 0 at center, 1 at edge
            r = int(139 - 30*t)
            g = int(92 - 20*t)
            b = int(246 - 60*t)
            img.putpixel((x, y), (max(0,r), max(0,g), max(0,b), 255))

# 三个彩色丸子
colors = [
    (255, 100, 180),  # 粉色
    (139, 92, 246),   # 紫色
    (251, 191, 36),   # 金色
]
positions = [(S//2, S//3), (S//3, S*2//3), (S*2//3, S*2//3)]
radii = [60, 55, 55]

for (cx, cy), r, col in zip(positions, radii, colors):
    # 高光
    for y in range(cy-r, cy+r):
        for x in range(cx-r, cx+r):
            if (x-cx)**2 + (y-cy)**2 < r**2:
                dx, dy = x-cx, y-cy
                d = math.sqrt(dx*dx + dy*dy) / r
                # 3D 球体效果：中心亮，边缘暗
                shade = 1.0 - d * 0.3
                # 高光点
                if dy < -r*0.2 and abs(dx) < r*0.3:
                    shade += 0.3
                rv = min(255, int(col[0] * shade))
                gv = min(255, int(col[1] * shade))
                bv = min(255, int(col[2] * shade))
                img.putpixel((x, y), (rv, gv, bv, 255))

# 将左上角白色高光点
for cy, r in [(S//2, 60)]:
    for dy in range(-10, 5):
        for dx in range(-15, 15):
            x, y = S//2 + dx, S//3 + dy
            if 0 <= x < S and 0 <= y < S:
                d2 = dx*dx + (dy+5)*(dy+5)
                if d2 < 80:
                    rv, gv, bv, a = img.getpixel((x, y))
                    img.putpixel((x, y), (min(255, rv+80), min(255, gv+80), min(255, bv+80), a))

base = 'android/app/src/main/res'
for nm, sz in [('xxxhdpi', 96), ('xxhdpi', 72), ('xhdpi', 48), ('hdpi', 36), ('mdpi', 24)]:
    d = f'{base}/mipmap-{nm}'
    os.makedirs(d, exist_ok=True)
    img.resize((sz, sz), Image.LANCZOS).save(f'{d}/ic_launcher.png')

# 也生成 Windows ico
sizes = [(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)]
img.save('windows/runner/resources/app_icon.ico', format='ICO', sizes=sizes)
print("Icons generated!")
