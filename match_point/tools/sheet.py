#!/usr/bin/env python3
"""يجمع إطارات اختبار الحركة في لوحة واحدة: sheet.py name cols [crop l,t,r,b]"""
import sys, glob
from PIL import Image
name, cols = sys.argv[1], int(sys.argv[2])
files = sorted(glob.glob(f"/tmp/shots/anim_{name}_*.png"))
ims = [Image.open(f).convert("RGB") for f in files]
if len(sys.argv) > 3:
    l, t, r, b = map(int, sys.argv[3].split(","))
    ims = [im.crop((l, t, r, b)) for im in ims]
w, h = ims[0].size
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (w * cols, h * rows))
for i, im in enumerate(ims):
    sheet.paste(im, ((i % cols) * w, (i // cols) * h))
if sheet.width > 1900:
    sheet = sheet.resize((1900, int(sheet.height * 1900 / sheet.width)))
sheet.save(f"/tmp/shots/sheet_{name}.png")
print(sheet.size, len(ims))
