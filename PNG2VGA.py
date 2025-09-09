# png2vga.py
# Usa Pillow: pip install pillow
# Gera: splash.img (320*200 bytes) e splash.pal (768 bytes RGB palette)
from PIL import Image
import sys

if len(sys.argv) < 2:
    print("Uso: python png2vga.py input.png")
    sys.exit(1)

infile = sys.argv[1]
W, H = 320, 200

img = Image.open(infile).convert("RGB")
img = img.resize((W, H), Image.LANCZOS)

# convert to palette (P) using adaptive palette
p = img.convert("P", palette=Image.ADAPTIVE, colors=256)

# get palette as list of 768 values (R,G,B * 256)
palette = p.getpalette()[:768]  # list length 768

# save palette 3 bytes per entry (0..255)
with open("splash.pal", "wb") as f:
    f.write(bytes(palette))

# save pixel indices (one byte per pixel)
data = p.tobytes()  # already 320*200 bytes
with open("splash.img", "wb") as f:
    f.write(data)

print("Gerado splash.img ({} bytes) e splash.pal ({} bytes)".format(len(data), len(palette)))
print("Agora rode: nasm -f bin stage2.asm -o stage2.bin")
