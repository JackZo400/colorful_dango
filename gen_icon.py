from PIL import Image, ImageDraw, ImageFilter
s = 512; img = Image.new('RGBA', (s, s), (0,0,0,0)); d = ImageDraw.Draw(img)
# 紫色渐变圆
for y in range(s):
    for x in range(s):
        if (x-s/2)**2 + (y-s/2)**2 < (s/2-4)**2:
            img.putpixel((x,y), (int(120+40*x/s), int(80+20*y/s), int(190+40*(x+y)/(2*s)), 255))
# 白色内圆
d.ellipse([s//4, s//4, 3*s//4, 3*s//4], fill=(255,255,255,255))
# 爱心 - 用两个圆 + 三角形
x0,y0=s//2,s//2
d.pieslice([x0-64,y0-90,x0,y0-10], -180, 0, fill=(220,60,120,255))
d.pieslice([x0,y0-90,x0+64,y0-10], -180, 0, fill=(220,60,120,255))
d.polygon([(x0-64,y0-50),(x0+63,y0-50),(x0,y0+40)], fill=(220,60,120,255))
for nm,sz in [('xxxhdpi',512),('xxhdpi',192),('xhdpi',144),('hdpi',96),('mdpi',48)]:
    img.resize((sz,sz), Image.LANCZOS).save(f'android/app/src/main/res/mipmap-{nm}/ic_launcher.png')
print("Done!")
