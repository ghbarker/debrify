# TV Home motion concepts — volume II

Five new Android TV Home concepts, each organised around **one verb of motion**
rather than one arrangement of parts. Volume I (`tv_home_layouts_mockup/`) moved
the furniture; these change how the screen *behaves*.

Open **`index.html`**, click a screen, and drive it with the arrow keys. Atlas
also answers <kbd>Enter</kbd> (dive) and <kbd>Backspace</kbd> (pull up).
Auto-demo runs until you press a key.

| # | Concept | Verb | Shape |
|---|---------|------|-------|
| VI | Mural | pan | Backdrops hung edge to edge; the rail walks a camera along the wall — no cross-dissolve anywhere |
| VII | Bloom | grow | The stage grows out of the focused card and collapses back into it |
| VIII | Reel | glide | One title per screen; ↑↓ next title, ←→ change lane |
| IX | Diorama | parallax | Three planes at three speeds, cards yaw toward the viewer, slow specular sweep |
| X | Atlas | zoom | Two altitudes — a map of every row, and a dive into one; the camera is the navigation |

## Files

- `index.html` — the built page (artwork inlined as data URIs). Open this.
- `index.src.html` — source, with an `__IMG_MAP__` token where the artwork goes.
- `art/` — downscaled metahub stills, posters and logo art (~1 MB), copied from volume I.
- `build.py` — base64s `art/` into the token and writes `index.html`.

```
python3 build.py
```

## Notes

- Every concept is judged against the measured Mi Box baseline (50 ms median per
  frame, 88 % missed vsync) and the fact that the cost is **per keypress**, not
  per second. The three cheapest here — Bloom, Mural, Reel — add no new per-press
  work; Diorama and Atlas do, and say so.
- Severance is excluded from the sample set: its metahub logo is a black
  wordmark, invisible on an ink ground. Same note as volume I.
- All five are additive — a new value in `tv_home_style`, a new branch in the
  board build. Canvas stays the default.
