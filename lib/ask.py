#!/usr/bin/env python3
"""lib/ask.py -- the one place omarchy-kids-ask needs JSON (SPEC.md
R-ASK-1..3, Appendix D).

Reads and writes one queue record per request:

    { "kid": account, "kind": "time|app|plugin|site", "what": string,
      "minutes": int?, "asked_at": ts, "state": "open|approved|declined",
      "decided_at": ts?, "by": "keyboard|panel|widget" }

"Approvers append, never rewrite history" (Appendix D) is read here as:
a record's state moves from "open" to "approved"/"declined" exactly
once. `decide` refuses (exit 3) if the record is already decided --
nothing here ever flips a decision back, and nothing here ever edits
`kid`/`kind`/`what`/`minutes`/`asked_at` after they're first written.

Usage:
    ask.py write DIR --kid K --kind KIND --what WHAT [--minutes N]
                      --state open|approved [--by keyboard|panel|widget]
    ask.py decide PATH --state approved|declined --by panel|keyboard|widget
    ask.py show PATH [--field FIELD]
    ask.py list-open DIR [--kid KID]

Exit 0 on success. Exit 2 for a bad argument or unreadable file, exit 3
for "already decided" (decide only) -- never a Python traceback.
"""
import glob
import json
import os
import sys
import time

KINDS = ("time", "app", "plugin", "site")
STATES = ("open", "approved", "declined")
BY = ("keyboard", "panel", "widget")


def die(msg, code=2):
    print(f"ask.py: {msg}", file=sys.stderr)
    sys.exit(code)


def load_record(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        die(f"no such record: {path}")
    except (OSError, json.JSONDecodeError) as e:
        die(f"could not read {path}: {e}")


def write_atomic(path, record):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, mode=0o755, exist_ok=True)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(record, f, sort_keys=True)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def parse_kv_args(argv, flags):
    """Pulls --flag value pairs out of argv (any order); returns (dict,
    leftover positional args). `flags` is the set of recognized --names
    (without the leading --)."""
    out = {}
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--"):
            name = a[2:]
            if name not in flags:
                die(f"unknown option --{name}")
            if i + 1 >= len(argv):
                die(f"--{name} needs a value")
            out[name] = argv[i + 1]
            i += 2
        else:
            rest.append(a)
            i += 1
    return out, rest


def cmd_write(argv):
    opts, rest = parse_kv_args(
        argv, {"kid", "kind", "what", "minutes", "state", "by"}
    )
    if len(rest) != 1:
        die("write: needs DIR")
    directory = rest[0]

    kid = opts.get("kid") or die("write: --kid is required")
    kind = opts.get("kind") or die("write: --kind is required")
    what = opts.get("what")
    if what is None:
        die("write: --what is required")
    state = opts.get("state", "open")

    if kind not in KINDS:
        die(f"write: unknown kind '{kind}' (must be one of {', '.join(KINDS)})")
    if state not in STATES:
        die(f"write: unknown state '{state}' (must be one of {', '.join(STATES)})")

    now = int(time.time())
    record = {
        "kid": kid,
        "kind": kind,
        "what": what,
        "asked_at": now,
        "state": state,
    }
    if "minutes" in opts:
        try:
            record["minutes"] = int(opts["minutes"])
        except ValueError:
            die("write: --minutes must be an integer")

    if state != "open":
        by = opts.get("by")
        if by not in BY:
            die(f"write: --state {state} needs --by (one of {', '.join(BY)})")
        record["decided_at"] = now
        record["by"] = by

    os.makedirs(directory, mode=0o755, exist_ok=True)
    # <unix-ts>-<account>-<kind>.json (Appendix D); a counter suffix
    # keeps two requests in the same second from colliding.
    base = f"{now}-{kid}-{kind}"
    path = os.path.join(directory, f"{base}.json")
    n = 1
    while os.path.exists(path):
        n += 1
        path = os.path.join(directory, f"{base}-{n}.json")
    write_atomic(path, record)
    print(os.path.basename(path))


def cmd_decide(argv):
    opts, rest = parse_kv_args(argv, {"state", "by"})
    if len(rest) != 1:
        die("decide: needs PATH")
    path = rest[0]
    state = opts.get("state")
    by = opts.get("by")
    if state not in ("approved", "declined"):
        die("decide: --state must be 'approved' or 'declined'")
    if by not in BY:
        die(f"decide: --by must be one of {', '.join(BY)}")

    record = load_record(path)
    if record.get("state") != "open":
        die(f"already decided ({record.get('state')}) -- {path}", code=3)

    record["state"] = state
    record["decided_at"] = int(time.time())
    record["by"] = by
    write_atomic(path, record)


def cmd_show(argv):
    opts, rest = parse_kv_args(argv, {"field"})
    if len(rest) != 1:
        die("show: needs PATH")
    record = load_record(rest[0])
    field = opts.get("field")
    if field is None:
        json.dump(record, sys.stdout, sort_keys=True)
        print()
        return
    value = record.get(field, "")
    print("" if value is None else value)


def cmd_list_open(argv):
    opts, rest = parse_kv_args(argv, {"kid"})
    if len(rest) != 1:
        die("list-open: needs DIR")
    directory = rest[0]
    want_kid = opts.get("kid")

    rows = []
    for path in sorted(glob.glob(os.path.join(directory, "*.json"))):
        try:
            with open(path, "r", encoding="utf-8") as f:
                record = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue  # a malformed record is skipped, not a crash
        if record.get("state") != "open":
            continue
        if want_kid and record.get("kid") != want_kid:
            continue
        record_id = os.path.basename(path)[: -len(".json")]
        rows.append(
            (
                record_id,
                record.get("kid", ""),
                record.get("kind", ""),
                record.get("what", ""),
                record.get("minutes", ""),
                record.get("asked_at", ""),
            )
        )
    for row in rows:
        print("\t".join(str(v) for v in row))


COMMANDS = {
    "write": cmd_write,
    "decide": cmd_decide,
    "show": cmd_show,
    "list-open": cmd_list_open,
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        die(f"usage: ask.py {{{'|'.join(COMMANDS)}}} ...")
    COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    main(sys.argv[1:])
