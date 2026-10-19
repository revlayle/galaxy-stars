"""Text art -> C64 binary data. Adapted from Smashy Smashy.

Reads assets/sprites.txt and assets/tiles.txt and writes
  build/sprites.bin    64 bytes per sprite frame, copied to $E800 at startup
  build/chars.bin      8 bytes per char, copied to char FIRST_CHAR onward
  src/gen_assets.p8    name constants for the code

Entries (a ';' starts a comment):
  sprite <name>                          21 rows of 24 hi-res pixels: . 1
  msprite <name>                         21 rows of 12 multicolor pixels: . 1 2 3 (1 = the sprite's own
                                         color, 2 = $D025, 3 = $D026); the code sets the sprite to multicolor
  tile <name> color <0-7> [size <W>x<H>] 16*H rows of 8*W multicolor pixels: . 1 2 3
                                         (W x H tiles of 2x2 chars; stored tile by tile, row by row,
                                         each tile as TL, TR, BL, BR)
  char <name> color <0-7>                8 rows of 8 multicolor pixels: . 1 2 3
  icon <name> color <0-7>                8 rows of 8 hi-res pixels: . 1 (HUD icons)
Multicolor: . = background $D021, 2 = $D022, 3 = $D023, 1 = the cell's own color (color RAM).

Usage: python tools/gfx.py   (run from the project root; build.cmd does this)
Exits with status 1 and "file:line: message" errors if the art is bad. Nothing is written then.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART_FILES = [ROOT / "assets" / "sprites.txt", ROOT / "assets" / "tiles.txt"]
OUT_SPRITES = ROOT / "build" / "sprites.bin"
OUT_CHARS = ROOT / "build" / "chars.bin"
OUT_P8 = ROOT / "src" / "gen_assets.p8"

FIRST_SPRITE_PTR = 160      # $E800 in VIC bank 3: ($E800 - $C000) / 64
MAX_SPRITES = 95            # pointers 160-254
FIRST_CHAR = 64             # chars 0-63 hold the ROM font for the HUD
MAX_CHARS = 256 - FIRST_CHAR

MC_BITS = {".": 0, "2": 1, "3": 2, "1": 3}
SPRITE_MC_BITS = {".": 0, "2": 1, "1": 2, "3": 3}   # 01 = $D025, 10 = sprite color, 11 = $D026
HIRES_BITS = {".": 0, "1": 1}
NAME_RE = r"[a-z][a-z0-9_]*"


class Entry:
    def __init__(self, kind, name, where):
        self.kind = kind
        self.name = name
        self.where = where
        self.color = 0
        self.w = 1          # tiles across (tile entries)
        self.h = 1
        self.rows = []

    def size(self):
        """(pixels per row, rows)"""
        if self.kind == "sprite":
            return 24, 21
        if self.kind == "msprite":
            return 12, 21
        if self.kind == "tile":
            return 8 * self.w, 16 * self.h
        return 8, 8

    def symbols(self):
        return ".1" if self.kind in ("sprite", "icon") else ".123"


def parse_header(words, where, errors):
    """Return an Entry, or None (with an error) if the header is bad."""
    kind = words[0]
    if len(words) < 2 or not re.fullmatch(NAME_RE, words[1]):
        errors.append(f"{where}: expected '{kind} <name>' with a lowercase name (a-z, 0-9, _)")
        return None
    e = Entry(kind, words[1], where)
    rest = words[2:]
    if kind in ("sprite", "msprite"):
        if rest:
            errors.append(f"{where}: expected '{kind} <name>'")
            return None
        return e
    if len(rest) < 2 or rest[0] != "color" or not rest[1].isdigit() or int(rest[1]) > 7:
        errors.append(f"{where}: expected '{kind} <name> color <0-7>' (cells can only use colors 0-7)")
        return None
    e.color = int(rest[1])
    rest = rest[2:]
    if kind == "tile" and rest:
        m = re.fullmatch(r"([1-9])x([1-9])", rest[1]) if len(rest) == 2 and rest[0] == "size" else None
        if not m:
            errors.append(f"{where}: expected 'size <W>x<H>' after the color")
            return None
        e.w, e.h = int(m.group(1)), int(m.group(2))
    elif rest:
        errors.append(f"{where}: unexpected '{' '.join(rest)}'")
        return None
    return e


def parse_file(path, entries, errors):
    rel = path.relative_to(ROOT).as_posix()
    current = None
    swallowing = False      # after a bad header: skip its rows without more errors

    def finish(lineno):
        if current is not None:
            _, nrows = current.size()
            if len(current.rows) != nrows:
                errors.append(f"{current.where}: {current.kind} '{current.name}' has {len(current.rows)} "
                              f"rows, expected {nrows} (ends before line {lineno})")

    lines = path.read_text().splitlines()
    for lineno, raw in enumerate(lines, 1):
        where = f"{rel}:{lineno}"
        line = raw.split(";", 1)[0].strip()
        if not line:
            continue
        words = line.split()
        if words[0] in ("sprite", "msprite", "tile", "char", "icon"):
            finish(lineno)
            current = parse_header(words, where, errors)
            swallowing = current is None
            if current:
                entries.append(current)
        elif len(words) == 1:
            if swallowing:
                continue
            if current is None:
                errors.append(f"{where}: pixel row outside any entry")
                continue
            width, nrows = current.size()
            if len(current.rows) == nrows:
                errors.append(f"{where}: {current.kind} '{current.name}' already has {nrows} rows")
                continue
            if len(line) != width:
                errors.append(f"{where}: row has {len(line)} pixels, expected {width}")
            bad = sorted(set(line) - set(current.symbols()))
            if bad:
                errors.append(f"{where}: symbol(s) {' '.join(bad)} not allowed; use {' '.join(current.symbols())}")
            current.rows.append(line)
        else:
            errors.append(f"{where}: can't read this line: {raw.strip()!r}")
    finish(len(lines) + 1)


def pack_bytes(row, multicolor, bits=MC_BITS):
    """One art row -> bytes, 8 hi-res or 4 multicolor pixels per byte."""
    out = []
    step = 4 if multicolor else 8
    for i in range(0, len(row), step):
        value = 0
        for ch in row[i:i + step]:
            value = (value << 2) | bits[ch] if multicolor else (value << 1) | HIRES_BITS[ch]
        out.append(value)
    return out


def build(entries):
    sprites = bytearray()
    chars = bytearray()
    consts = []
    for e in entries:
        up = e.name.upper()
        if e.kind in ("sprite", "msprite"):
            frame = bytearray(64)
            for y, row in enumerate(e.rows):
                if e.kind == "sprite":
                    frame[y * 3:y * 3 + 3] = bytes(pack_bytes(row, False))
                else:
                    frame[y * 3:y * 3 + 3] = bytes(pack_bytes(row, True, SPRITE_MC_BITS))
            consts.append(f"    const ubyte SPR_{up} = {FIRST_SPRITE_PTR + len(sprites) // 64}")
            sprites += frame
        elif e.kind == "tile":
            first = FIRST_CHAR + len(chars) // 8
            packed = [pack_bytes(r, True) for r in e.rows]     # 2 bytes per tile across
            for ty in range(e.h):
                for tx in range(e.w):
                    for half in range(2):           # top chars, then bottom chars
                        block = packed[ty * 16 + half * 8:ty * 16 + half * 8 + 8]
                        for side in range(2):       # left char, then right char
                            chars += bytes(r[tx * 2 + side] for r in block)
            consts.append(f"    const ubyte TILE_{up}_TL = {first}")
            consts.append(f"    const ubyte TILE_{up}_COLOR = {e.color}")
        else:
            consts.append(f"    const ubyte CHAR_{up} = {FIRST_CHAR + len(chars) // 8}")
            consts.append(f"    const ubyte CHAR_{up}_COLOR = {e.color}")
            chars += bytes(pack_bytes(r, e.kind == "char")[0] for r in e.rows)
    return sprites, chars, consts


def main():
    errors = []
    entries = []
    for path in ART_FILES:
        if not path.exists():
            errors.append(f"{path.relative_to(ROOT).as_posix()}: file not found")
            continue
        parse_file(path, entries, errors)

    seen = {}
    for e in entries:
        key = {"icon": "char", "msprite": "sprite"}.get(e.kind, e.kind)    # same constant prefix
        if (key, e.name) in seen:
            errors.append(f"{e.where}: {e.kind} '{e.name}' already defined at {seen[(key, e.name)]}")
        seen[(key, e.name)] = e.where
    n_sprites = sum(1 for e in entries if e.kind in ("sprite", "msprite"))
    n_chars = sum(4 * e.w * e.h if e.kind == "tile" else 1 for e in entries if e.kind in ("tile", "char", "icon"))
    if n_sprites > MAX_SPRITES:
        errors.append(f"too many sprites: {n_sprites}, max {MAX_SPRITES}")
    if n_chars > MAX_CHARS:
        errors.append(f"too many chars: {n_chars}, max {MAX_CHARS}")

    if errors:
        for msg in errors:
            print(f"gfx.py: error: {msg}", file=sys.stderr)
        return 1

    sprites, chars, consts = build(entries)
    OUT_SPRITES.parent.mkdir(exist_ok=True)
    OUT_SPRITES.write_bytes(sprites)
    OUT_CHARS.write_bytes(chars)
    p8 = [
        "; GENERATED by tools/gfx.py from assets/sprites.txt and assets/tiles.txt. Do not edit.",
        "",
        "assets {",
        f"    const ubyte SPRITE_COUNT = {n_sprites}",
        f"    const ubyte CHAR_COUNT = {n_chars}",
        f"    const ubyte FIRST_CHAR = {FIRST_CHAR}",
        "",
        *consts,
        "}",
        "",
    ]
    text = "\n".join(p8)
    if not OUT_P8.exists() or OUT_P8.read_text() != text:
        OUT_P8.write_text(text)
    print(f"gfx.py: {n_sprites} sprites, {n_chars} chars")
    return 0


if __name__ == "__main__":
    sys.exit(main())
