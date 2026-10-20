"""Build-time font subsetting: keep only the characters the game can show.

    python tools/subset_fonts.py subset    # back up game/assets/fonts/*.ttf, write subsets in their place
    python tools/subset_fonts.py restore   # put the full fonts back

The character set is every character in the game's text files (scenes, scripts, data) plus printable ASCII and
common CJK punctuation, so text built at run time from those pieces (names, numbers, notices) is covered.
Called by tools/build.sh and tools/export_web.sh around the export; the repo always keeps the full fonts.
"""
import pathlib
import shutil
import sys

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
FONTS = GAME / "assets" / "fonts"
BACKUP = ROOT / "tools" / "dl" / "fonts_full"
SCAN = ["scenes", "src", "data", "assets"]
EXT = {".tscn", ".tres", ".gd", ".json", ".cfg", ".txt", ".godot"}
EXTRA = "".join(chr(c) for c in range(0x20, 0x7F)) + "，。、；：？！“”‘’（）《》【】—…·～％＋－×÷０１２３４５６７８９"


def charset() -> str:
    chars = set(EXTRA)
    files = [GAME / "project.godot"]
    for d in SCAN:
        files += [p for p in (GAME / d).rglob("*") if p.suffix in EXT and p.is_file()]
    for p in files:
        try:
            chars.update(p.read_text(encoding="utf-8"))
        except UnicodeDecodeError:
            pass
    return "".join(sorted(c for c in chars if c.isprintable()))


def do_subset() -> None:
    if BACKUP.exists() and any(BACKUP.iterdir()):
        sys.exit("tools/dl/fonts_full is not empty: run `restore` first")
    BACKUP.mkdir(parents=True, exist_ok=True)
    text = charset()
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    for f in sorted(FONTS.glob("*.ttf")):
        shutil.copy2(f, BACKUP / f.name)
        font = subset.load_font(str(f), opts)
        s = subset.Subsetter(opts)
        s.populate(text=text)
        s.subset(font)
        subset.save_font(font, str(f), opts)
        print(f"{f.name}: {(BACKUP / f.name).stat().st_size / 1e6:.1f} MB -> {f.stat().st_size / 1e6:.2f} MB")
    print(f"{len(text)} characters")


def do_restore() -> None:
    if not BACKUP.exists():
        return
    for f in BACKUP.glob("*.ttf"):
        shutil.move(str(f), FONTS / f.name)
    BACKUP.rmdir()


if __name__ == "__main__":
    {"subset": do_subset, "restore": do_restore}[sys.argv[1]]()
