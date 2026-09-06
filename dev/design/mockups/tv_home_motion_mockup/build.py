#!/usr/bin/env python3
"""Inline art/ as data URIs into index.src.html -> index.html (Artifact CSP blocks external hosts)."""
import base64, json, pathlib, sys

HERE = pathlib.Path(__file__).parent
SRC = HERE / "index.src.html"
OUT = HERE / "index.html"

mime = {".jpg": "image/jpeg", ".png": "image/png"}
imgs = {}
for f in sorted((HERE / "art").iterdir()):
    if f.suffix not in mime:
        continue
    imgs[f.stem] = f"data:{mime[f.suffix]};base64," + base64.b64encode(f.read_bytes()).decode()

html = SRC.read_text()
if "__IMG_MAP__" not in html:
    sys.exit("token __IMG_MAP__ missing from source")
OUT.write_text(html.replace("__IMG_MAP__", json.dumps(imgs)))
print(f"{len(imgs)} images -> {OUT} ({OUT.stat().st_size/1_000_000:.2f} MB)")
