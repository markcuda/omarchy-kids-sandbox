#!/bin/bash
# R-BAR-3: strict request counting fails closed on queue I/O and never emits
# a partial count that could become a false parent badge.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$ROOT" <<'PY'
import builtins
import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile

root = sys.argv[1]
spec = importlib.util.spec_from_file_location("ask", os.path.join(root, "lib", "ask.py"))
ask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ask)

def record(path, stamp):
    with open(path, "w", encoding="utf-8") as stream:
        json.dump({"kid": "kid-ada", "kind": "time", "what": "10",
                   "minutes": 10, "asked_at": stamp, "state": "open"}, stream)

with tempfile.TemporaryDirectory() as directory:
    first = os.path.join(directory, "1000000000-first.json")
    second = os.path.join(directory, "1000000001-second.json")
    record(first, 1000000000)
    record(second, 1000000001)

    original_open = builtins.open
    def deny_second(path, *args, **kwargs):
        if os.fspath(path) == second:
            raise PermissionError("fixture denied")
        return original_open(path, *args, **kwargs)

    stdout = io.StringIO()
    try:
        builtins.open = deny_second
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            ask.cmd_list_open_strict([directory])
    except SystemExit as exc:
        assert exc.code == 2, exc.code
    else:
        raise AssertionError("second unreadable record did not fail")
    finally:
        builtins.open = original_open
    assert stdout.getvalue() == "", repr(stdout.getvalue())

    class PartialScan:
        def __enter__(self):
            return self
        def __exit__(self, *args):
            return False
        def close(self):
            return None
        def __iter__(self):
            yield type("Entry", (), {"path": first, "name": os.path.basename(first), "is_file": lambda self: True})()
            raise FileNotFoundError("fixture disappeared")

    original_scandir = ask.os.scandir
    stdout = io.StringIO()
    try:
        ask.os.scandir = lambda path: PartialScan()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            ask.cmd_list_open_strict([directory])
    except SystemExit as exc:
        assert exc.code == 2, exc.code
    else:
        raise AssertionError("post-open queue disappearance did not fail")
    finally:
        ask.os.scandir = original_scandir
    assert stdout.getvalue() == "", repr(stdout.getvalue())

    original_scandir = ask.os.scandir
    def deny_scan(path):
        raise PermissionError("fixture denied scan")
    stdout = io.StringIO()
    try:
        ask.os.scandir = deny_scan
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(io.StringIO()):
            ask.cmd_list_open_strict([directory])
    except SystemExit as exc:
        assert exc.code == 2, exc.code
    else:
        raise AssertionError("unreadable queue did not fail")
    finally:
        ask.os.scandir = original_scandir
    assert stdout.getvalue() == "", repr(stdout.getvalue())

print("request-count-strict-test: PASS")
PY
