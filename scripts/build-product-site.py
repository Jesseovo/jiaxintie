"""Build the static product site from versioned source and verified release files."""
import argparse
import hashlib
import html
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "website"
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--release-dir", type=Path, default=ROOT / "build-tools/release-v1.0/assets")
parser.add_argument("--public-url", default="https://jesseovo.github.io/jiaxintie")
args = parser.parse_args()
args.public_url = args.public_url.rstrip("/")
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)


def inline(value):
    tokens = re.split(r"(`[^`]+`|\[[^\]]+\]\([^)]+\)|\*\*[^*]+\*\*|https://[^\s<>]+)", value)
    rendered = []
    for token in tokens:
        if token.startswith("`") and token.endswith("`"):
            rendered.append("<code>" + html.escape(token[1:-1]) + "</code>")
        elif token.startswith("**") and token.endswith("**"):
            rendered.append("<strong>" + html.escape(token[2:-2]) + "</strong>")
        elif re.fullmatch(r"\[[^\]]+\]\([^)]+\)", token):
            label, url = re.fullmatch(r"\[([^\]]+)\]\(([^)]+)\)", token).groups()
            url = {"usage.zh-CN.md": "guide.html", "../VALIDATION.md": "https://github.com/Jesseovo/jiaxintie/blob/main/VALIDATION.md", "../CHANGELOG.md": "https://github.com/Jesseovo/jiaxintie/blob/main/CHANGELOG.md", "development.md": "https://github.com/Jesseovo/jiaxintie/blob/main/docs/development.md"}.get(url, url)
            rendered.append(f'<a href="{html.escape(url, quote=True)}">{html.escape(label)}</a>')
        elif token.startswith("https://"):
            rendered.append(f'<a href="{html.escape(token, quote=True)}">{html.escape(token)}</a>')
        else:
            rendered.append(html.escape(token))
    return "".join(rendered)


def render_markdown(text):
    ids = {"安装与启动": "install", "快捷键": "shortcuts", "截图与标注": "capture", "桌面贴图": "pin", "保存与缓存": "storage", "已知范围": "limits"}
    lines = text.splitlines()
    pieces, toc = [], []
    current_section = False
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.startswith("# "):
            i += 1
            continue
        if line.startswith("## "):
            if current_section:
                pieces.append("</section>")
            title = line[3:]
            identifier = ids.get(title, "section-" + str(len(toc) + 1))
            toc.append((identifier, title))
            pieces.append(f'<section id="{identifier}"><h2>{inline(title)}</h2>')
            current_section = True
            i += 1
        elif line.startswith("### "):
            pieces.append("<h3>" + inline(line[4:]) + "</h3>")
            i += 1
        elif line.startswith("```"):
            block = []
            i += 1
            while i < len(lines) and not lines[i].startswith("```"):
                block.append(lines[i]); i += 1
            pieces.append("<pre><code>" + html.escape("\n".join(block)) + "</code></pre>")
            i += 1
        elif line.startswith("|"):
            table = []
            while i < len(lines) and lines[i].startswith("|"):
                table.append([cell.strip() for cell in lines[i].strip("|").split("|")]); i += 1
            rows = ["<tr>" + "".join("<th>" + inline(cell) + "</th>" for cell in table[0]) + "</tr>"]
            for row in table[2:]:
                rows.append("<tr>" + "".join("<td>" + inline(cell) + "</td>" for cell in row) + "</tr>")
            pieces.append('<div class="table-scroll"><table>' + "".join(rows) + "</table></div>")
        elif line.startswith("- ") or re.match(r"^\d+\. ", line):
            ordered = not line.startswith("- ")
            pattern = r"^\d+\. " if ordered else r"^- "
            items = []
            while i < len(lines) and re.match(pattern, lines[i]):
                items.append("<li>" + inline(re.sub(pattern, "", lines[i])) + "</li>"); i += 1
            tag = "ol" if ordered else "ul"
            pieces.append(f"<{tag}>" + "".join(items) + f"</{tag}>")
        else:
            paragraph = [line]
            i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r"^(#|```|\||- |\d+\. )", lines[i]):
                paragraph.append(lines[i]); i += 1
            pieces.append("<p>" + inline(" ".join(paragraph)) + "</p>")
    if current_section:
        pieces.append("</section>")
    return "\n".join(pieces), toc


index = (SOURCE / "index.html").read_text()
index = index.replace('content="assets/share-cover.png"', f'content="{args.public_url}/assets/share-cover.png"')
index = index.replace("</head>", f'<link rel="canonical" href="{args.public_url}/"><meta property="og:url" content="{args.public_url}/"></head>')
(output / "index.html").write_text(index)
for filename in ["styles.css", "app.js"]:
    shutil.copy2(SOURCE / filename, output / filename)
shutil.copytree(SOURCE / "assets", output / "assets", dirs_exist_ok=True)

header = re.search(r"<header\b.*?</header>", index, re.S).group()
footer = re.search(r"<footer\b.*?</footer>", index, re.S).group()
icons = re.search(r'<svg class="icon-defs".*?</svg>', index, re.S).group()
for fragment in ["#how", "#features", "#download"]:
    header = header.replace('href="' + fragment + '"', 'href="./' + fragment + '"')
    footer = footer.replace('href="' + fragment + '"', 'href="./' + fragment + '"')

for filename, path, title, subtitle, kicker in [
    ("guide.html", ROOT / "docs/usage.zh-CN.md", "顺手使用夹心贴。", "安装、快捷键、保存位置和权限，放在这里慢慢看。", "THE LITTLE HANDBOOK"),
    ("about.html", ROOT / "docs/ABOUT.md", "小工具，也可以认真做。", "关于夹心贴想解决的问题，以及它已经做到和还没做到的事。", "ABOUT JIAXINTIE"),
]:
    text = path.read_text()
    text = text.replace("下载地址：https://github.com/Jesseovo/jiaxintie/releases/tag/v1.0", "下载地址：[官网双平台下载](./#download)")
    body, toc = render_markdown(text)
    nav = "".join(f'<a href="#{identifier}">{html.escape(label)}</a>' for identifier, label in toc)
    page = f'''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#faf7f2"><title>{title} — 夹心贴</title><meta name="description" content="{subtitle}"><link rel="canonical" href="{args.public_url}/{filename}"><link rel="icon" href="assets/logo.png"><link rel="stylesheet" href="styles.css"><script src="app.js" defer></script></head><body><a class="skip-link" href="#main">跳到正文</a>{header}<main id="main" class="wrap"><div class="document-hero"><span class="eyebrow">{kicker}</span><h1>{title}</h1><p>{subtitle}</p></div><div class="document-layout"><nav class="document-toc" aria-label="本页目录">{nav}</nav><article class="document-body">{body}</article></div></main>{footer}{icons}</body></html>'''
    (output / filename).write_text(page)

release_dir = args.release_dir.resolve()
checksum_file = release_dir / "SHA256SUMS.txt"
expected = {"JiaXinTie-Windows-x64-v1.0.zip", "JiaXinTie-macOS-universal-v1.0.zip"}
checked = set()
for line in checksum_file.read_text().splitlines():
    digest, filename = line.split("  ", 1)
    if filename not in expected:
        raise RuntimeError("Unexpected release file: " + filename)
    actual = hashlib.sha256((release_dir / filename).read_bytes()).hexdigest()
    if actual != digest:
        raise RuntimeError("Release checksum mismatch: " + filename)
    checked.add(filename)
if checked != expected:
    raise RuntimeError("Both desktop release files are required")
(output / "downloads").mkdir(exist_ok=True)
for filename in sorted(expected | {"SHA256SUMS.txt"}):
    shutil.copy2(release_dir / filename, output / "downloads" / filename)

(output / "robots.txt").write_text(f"User-agent: *\nAllow: /\nSitemap: {args.public_url}/sitemap.xml\n")
(output / ".nojekyll").touch()
urls = ["", "about.html", "guide.html"]
(output / "sitemap.xml").write_text('<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + "".join(f"<url><loc>{args.public_url}/{path}</loc></url>" for path in urls) + "</urlset>")
print("Static product site built:", output)
print("Pages: index.html, about.html, guide.html; verified v1.0 download files included.")
