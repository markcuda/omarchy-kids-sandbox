"""Read portal geometry as data; never load a parent's Lua into a root process."""

import configparser
import hashlib
import json
import math
import os
from pathlib import Path
import pwd
import re
import stat
import subprocess
import sys
try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib


def number(value, fallback, maximum=256):
    if isinstance(value, bool):
        return fallback
    try:
        value = float(value)
    except (TypeError, ValueError):
        return fallback
    return value if math.isfinite(value) and 0 <= value <= maximum else fallback


def read_text(path):
    try:
        with open(os.open(path, os.O_RDONLY | os.O_NONBLOCK), encoding="utf-8") as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
                return ""
            text = source.read(262145)
            return text if len(text) <= 262144 else ""
    except (OSError, UnicodeError):
        return ""


def live_radius(parent, home):
    try:
        owner = pwd.getpwnam(parent)
        if os.geteuid() != 0 or owner.pw_dir != str(home):
            return None
        runtime = f"/run/user/{owner.pw_uid}"
        command = ["/usr/bin/runuser", "-u", parent, "--", "/usr/bin/env", "-i",
                   f"XDG_RUNTIME_DIR={runtime}"]

        def query(arguments, signature=None):
            env = [f"HYPRLAND_INSTANCE_SIGNATURE={signature}"] if signature else []
            output = subprocess.run(command + env + ["/usr/bin/hyprctl"] + arguments,
                                    capture_output=True, text=True, check=True, timeout=2)
            return json.loads(output.stdout)

        instances = query(["instances", "-j"])
        if not isinstance(instances, list) or len(instances) != 1:
            return None
        instance = instances[0]
        pid, signature = instance.get("pid"), instance.get("instance")
        if (type(pid) is not int or pid <= 0 or not isinstance(signature, str)
                or not re.fullmatch(r"[A-Za-z0-9_.-]+", signature)):
            return None
        if (Path(f"/proc/{pid}").stat().st_uid != owner.pw_uid
                or read_text(f"/proc/{pid}/comm").strip() != "Hyprland"):
            return None
        return number(query(["-j", "getoption", "decoration:rounding"], signature).get("int"), None)
    except (KeyError, OSError, ValueError, AttributeError, subprocess.SubprocessError):
        return None


def literal_radius(lua):
    lua = re.sub(r"\[(=*)\[.*?\]\1\]", "", lua, flags=re.S)
    lua = "\n".join(line.split("--", 1)[0] for line in lua.splitlines())
    if re.search(r"\b(function|if|for|while|repeat|dofile|require)\b", lua):
        return None
    assignments = re.findall(r"^\s*rounding\s*=([^\n]*)", lua, re.M)
    if len(assignments) != 1:
        return None
    match = re.fullmatch(r"\s*(\d+(?:\.\d+)?)\s*,?\s*", assignments[0])
    return number(match[1], None) if match else None


def cached_radius(path, identity):
    try:
        info = Path(path).lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            return None
        config = configparser.ConfigParser(interpolation=None)
        config.read_string(read_text(path))
        values = config["General"]
        if values.get("geometryIdentity") != identity:
            return None
        return number(values.get("cornerRadius"), None)
    except (OSError, KeyError, configparser.Error):
        return None


def color_token(value, fallback="foreground"):
    if not isinstance(value, str):
        return fallback
    value = value.strip().lower()
    if value == "text":
        return "foreground"
    if re.fullmatch(r"foreground|background|accent|urgent|transparent|#(?:[0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})", value):
        return value
    return fallback


def geometry(parent, home, cache):
    theme = Path(home) / ".local/state/omarchy/current/theme"
    lua, shell = read_text(theme / "hyprland.lua"), read_text(theme / "shell.toml")
    identity = hashlib.sha256("\0".join((parent, str(home), lua, shell,
                                        read_text(theme.parent / "theme.name"))).encode()).hexdigest()
    radius = live_radius(parent, home)
    if radius is None:
        radius = cached_radius(cache, identity)
    if radius is None:
        radius = literal_radius(lua)
    values = {"geometryIdentity": identity, "cornerRadius": 0 if radius is None else radius}
    controls = {}
    try:
        for section, entries in tomllib.loads(shell).items():
            if section in ("controls", "style") and isinstance(entries, dict):
                controls.update(entries)
    except tomllib.TOMLDecodeError:
        pass
    hover_width = number(controls.get("hover-cursor-border-width"),
                         number(controls.get("normal-border-width"), 1))
    hover_color = color_token(controls.get("hover-cursor-color"))
    for state, width, fill, border in (("normal", 1, 0.04, 0.4),
                                       ("selected", 0, 0.18, 1),
                                       ("focus", hover_width, 0.08, 0.25)):
        if state == "focus":
            fill = number(controls.get("hover-cursor-fill-alpha"), fill, 1)
            border = number(controls.get("hover-cursor-border-alpha"), border, 1)
        values[state + "BorderWidth"] = math.floor(number(controls.get(state + "-border-width"), width) + 0.5)
        values[state + "FillAlpha"] = number(controls.get(state + "-fill-alpha"), fill, 1)
        values[state + "BorderAlpha"] = number(controls.get(state + "-border-alpha"), border, 1)
        values[state + "Color"] = color_token(controls.get(state + "-color"), hover_color if state == "focus" else "foreground")
    return values


if __name__ == "__main__":
    for key, value in geometry(*sys.argv[1:]).items():
        print(f"{key}={value:g}" if isinstance(value, (int, float)) else f"{key}={value}")
