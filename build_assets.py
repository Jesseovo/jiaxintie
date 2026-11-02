"""Remove only edge-connected near-white background, then create cropped icons."""
from collections import deque
from pathlib import Path
import sys
from PIL import Image, ImageFilter

source = Path(sys.argv[1])
target = Path(__file__).resolve().parent / "assets"
image = Image.open(source).convert("RGBA")
w, h = image.size
pixels = image.load()
visited = bytearray(w * h)
queue = deque()

def visit(x, y):
    index = y * w + x
    if not visited[index] and (pixels[x, y][3] == 0 or min(pixels[x, y][:3]) >= 247):
        visited[index] = 1
        queue.append((x, y))

for x in range(w):
    visit(x, 0)
    visit(x, h - 1)
for y in range(h):
    visit(0, y)
    visit(w - 1, y)
while queue:
    x, y = queue.popleft()
    pixels[x, y] = (255, 255, 255, 0)
    if x:
        visit(x - 1, y)
    if x + 1 < w:
        visit(x + 1, y)
    if y:
        visit(x, y - 1)
    if y + 1 < h:
        visit(x, y + 1)

# Clear the last pale fringe without touching enclosed white face details.
alpha = image.getchannel("A").filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.4))
image.putalpha(alpha)
bounds = alpha.getbbox()
image = image.crop(bounds)
image.thumbnail((488, 488), Image.Resampling.LANCZOS)
logo = Image.new("RGBA", (512, 512))
logo.alpha_composite(image, ((512 - image.width) // 2, (512 - image.height) // 2))
target.mkdir(exist_ok=True)
logo.save(target / "logo.png")
logo.save(target / "app.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print(f"Removed background; source bounds={bounds}; output=512x512 RGBA; transparent corners.")
