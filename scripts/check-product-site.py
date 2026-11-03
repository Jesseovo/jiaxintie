"""Check generated product pages, internal anchors, static assets and download hashes."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import argparse
import hashlib

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
root = parser.parse_args().directory.resolve()


class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids = set()
        self.refs = []
        self.headings = 0
        self.feed(text)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                raise RuntimeError("Duplicate id: " + attrs["id"])
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.headings += 1
        for key in ["href", "src"]:
            if key in attrs:
                self.refs.append(attrs[key])


pages = {file: Page(file.read_text()) for file in root.glob("*.html")}
assert {p.name for p in pages} == {"index.html", "about.html", "guide.html"}
for path, page in pages.items():
    assert page.headings == 1, path
    for reference in page.refs:
        parts = urlsplit(reference)
        if parts.scheme or parts.netloc:
            continue
        target = (path.parent / unquote(parts.path)).resolve() if parts.path else path
        if target.is_dir():
            target /= "index.html"
        assert target.is_relative_to(root), reference
        assert target.is_file(), (path, reference)
        if parts.fragment and target.suffix == ".html":
            assert parts.fragment in pages[target].ids, (path, reference)
for line in (root / "downloads/SHA256SUMS.txt").read_text().splitlines():
    digest, filename = line.split("  ", 1)
    file = root / "downloads" / filename
    assert hashlib.sha256(file.read_bytes()).hexdigest() == digest, filename
print("PASS: three pages, internal links/anchors, static files and both release checksums")
