#!/usr/bin/env python3
"""lib/conf.py — the one place omarchy-kids-conf needs Python.

Reads share/bands/bands.toml and share/packs/<band>.toml with the
stdlib's tomllib (3.11+) and prints plain text a bash caller can consume
directly with $(...). Also does the Appendix B.1 slug rule, since NFKD
transliteration is painful in bash. No writing: bands.toml and the pack
files are read-only data (Appendix C); only a kid's own .conf is ever
written, and that's lib/conf.sh's job.

Usage:
    conf.py slug NAME
    conf.py band-list BANDS_TOML
    conf.py band-dump BANDS_TOML BAND
    conf.py band-get BANDS_TOML BAND KEY
    conf.py pack-ids PACK_TOML
    conf.py pack-sites PACK_TOML
    conf.py pack-app PACK_TOML ID

Exit 0 on success. Exit 2 with a one-line reason on stderr for a bad
band, key, or missing file — never a Python traceback.
"""
import sys
import unicodedata

if sys.version_info >= (3, 11):
    import tomllib
else:  # pragma: no cover - Arch ships 3.11+; this is a courtesy for dev boxes
    try:
        import tomli as tomllib
    except ImportError:
        print(
            "conf.py: needs Python 3.11+ (tomllib) or the 'tomli' package",
            file=sys.stderr,
        )
        sys.exit(2)

BANDS_ORDER = ("3-5", "6-8", "9-12", "13+")


def die(msg):
    print(f"conf.py: {msg}", file=sys.stderr)
    sys.exit(2)


def load_toml(path):
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except FileNotFoundError:
        die(f"no such file: {path}")
    except tomllib.TOMLDecodeError as e:
        die(f"bad TOML in {path}: {e}")


def toml_scalar(value):
    """Render a TOML scalar the way bash key=value files expect it."""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def cmd_slug(argv):
    if not argv:
        die("slug: needs a display name")
    name = " ".join(argv)
    # NFKD splits an accented letter into base + combining mark(s); we
    # then drop every combining mark and any remaining non-ASCII, so
    # e.g. "Zoë" -> "Zoe" (Appendix B.1: transliterate common accents).
    decomposed = unicodedata.normalize("NFKD", name)
    ascii_only = decomposed.encode("ascii", "ignore").decode("ascii")
    slug = "".join(ch for ch in ascii_only.lower() if ch.isalnum())
    slug = slug[:24]
    if not slug:
        die(f"slug: '{name}' has no alphanumeric characters to slug")
    print(f"kid-{slug}")


def cmd_band_list(argv):
    if len(argv) != 1:
        die("band-list: needs BANDS_TOML")
    data = load_toml(argv[0])
    bands = data.get("band", {})
    for band in BANDS_ORDER:
        if band not in bands:
            continue
        b = bands[band]
        print(f"{band}\t{b.get('label', '')}\t{b.get('blurb', '')}")


def _band_table(data, band):
    bands = data.get("band", {})
    if band not in bands:
        die(f"unknown band: {band}")
    return bands[band]


def cmd_band_dump(argv):
    if len(argv) != 2:
        die("band-dump: needs BANDS_TOML BAND")
    data = load_toml(argv[0])
    table = _band_table(data, argv[1])
    for key, value in table.items():
        print(f"{key}={toml_scalar(value)}")


def cmd_band_get(argv):
    if len(argv) != 3:
        die("band-get: needs BANDS_TOML BAND KEY")
    data = load_toml(argv[0])
    table = _band_table(data, argv[1])
    key = argv[2]
    if key not in table:
        die(f"band '{argv[1]}' has no '{key}'")
    print(toml_scalar(table[key]))


def cmd_pack_ids(argv):
    if len(argv) != 1:
        die("pack-ids: needs PACK_TOML")
    data = load_toml(argv[0])
    ids = [app["id"] for app in data.get("app", []) if "id" in app]
    print(",".join(ids))


def cmd_pack_sites(argv):
    if len(argv) != 1:
        die("pack-sites: needs PACK_TOML")
    data = load_toml(argv[0])
    sites = data.get("garden", {}).get("sites", [])
    print(",".join(sites))


def cmd_pack_app(argv):
    # Used by bin/omarchy-kids-session-start to resolve one allowlisted
    # launcher id to its pack metadata (label, pkg, and the optional
    # `web` URL for a web app -- see AGENTS.md's packs/<band>.toml row)
    # without hand-parsing TOML in bash. Tab-separated so a bash caller
    # can `IFS=$'\t' read -r label pkg web`.
    if len(argv) != 2:
        die("pack-app: needs PACK_TOML ID")
    data = load_toml(argv[0])
    want = argv[1]
    for app in data.get("app", []):
        if app.get("id") == want:
            label = app.get("label", "")
            pkg = app.get("pkg", "")
            web = app.get("web", "")
            print(f"{label}\t{pkg}\t{web}")
            return
    die(f"no such app id in pack: {want}")


COMMANDS = {
    "slug": cmd_slug,
    "band-list": cmd_band_list,
    "band-dump": cmd_band_dump,
    "band-get": cmd_band_get,
    "pack-ids": cmd_pack_ids,
    "pack-sites": cmd_pack_sites,
    "pack-app": cmd_pack_app,
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        die(f"usage: conf.py {{{'|'.join(COMMANDS)}}} ...")
    COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    main(sys.argv[1:])
