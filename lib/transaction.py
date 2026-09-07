#!/usr/bin/python3
"""Validated, durable per-account lifecycle and LUKS ownership records."""

from __future__ import annotations

import json
import os
import re
import stat
import sys
import tempfile
import uuid
from pathlib import Path

SCHEMA = 1
ACCOUNT = re.compile(r"^kid-[a-z0-9]+(?:-[a-z0-9]+)*$")
STATES = ("reserved", "adding", "added", "removing", "removed")
STATE_NEXT = dict(zip(STATES, STATES[1:]))
ACCOUNT_STATES = (
    "planned",
    "creating",
    "created",
    "passworded",
    "fstab",
    "mounted",
    "profile",
    "namespace",
    "accountsservice",
    "face",
    "portal",
    "launcher",
    "session",
    "complete",
    "removing",
    "unmounted",
    "fstab_removed",
    "namespace_removed",
    "accountsservice_removed",
    "face_removed",
    "launcher_removed",
    "session_removed",
    "account_removed",
    "home_moved",
    "cleaned",
)
ACCOUNT_NEXT = dict(zip(ACCOUNT_STATES, ACCOUNT_STATES[1:]))
REQUIRED = {
    "schema",
    "transaction",
    "account",
    "direction",
    "device_uuid",
    "slot",
    "owner",
    "state",
    "password_mode",
    "luks_mode",
    "account_state",
    "destination",
    "display",
    "band",
    "avatar",
}


class Invalid(Exception):
    pass


def valid_uuid(value: object, *, version4: bool = False) -> bool:
    if not isinstance(value, str):
        return False
    try:
        parsed = uuid.UUID(value)
    except (ValueError, AttributeError):
        return False
    return str(parsed) == value and (not version4 or parsed.version == 4)


def validate_data(data: object, account: str) -> dict:
    if not isinstance(data, dict) or set(data) != REQUIRED:
        raise Invalid("record has unknown or missing fields")
    if type(data["schema"]) is not int or data["schema"] != SCHEMA:
        raise Invalid("unsupported transaction schema")
    if data["account"] != account or not ACCOUNT.fullmatch(account):
        raise Invalid("invalid transaction account")
    if data["direction"] not in ("add", "remove"):
        raise Invalid("invalid transaction direction")
    if data["state"] not in STATES or data["account_state"] not in ACCOUNT_STATES:
        raise Invalid("invalid transaction state")
    if data["password_mode"] not in ("set", "none"):
        raise Invalid("invalid password mode")
    if not valid_uuid(data["transaction"], version4=True) or not valid_uuid(data["owner"], version4=True):
        raise Invalid("invalid transaction identity")
    if data["luks_mode"] not in ("owned", "none"):
        raise Invalid("invalid LUKS mode")
    if data["luks_mode"] == "none":
        if data["device_uuid"] is not None or data["slot"] is not None:
            raise Invalid("non-LUKS transaction has LUKS identity")
    else:
        if not valid_uuid(data["device_uuid"]):
            raise Invalid("invalid LUKS device UUID")
        if type(data["slot"]) is not int or not 1 <= data["slot"] <= 31:
            raise Invalid("invalid LUKS slot")
    if not isinstance(data["destination"], str) or "\0" in data["destination"]:
        raise Invalid("invalid home destination")
    if (
        not isinstance(data["display"], str)
        or not 1 <= len(data["display"]) <= 64
        or any(c in data["display"] for c in ("\0", "\n", "\t"))
    ):
        raise Invalid("invalid display name")
    if data["band"] not in ("3-5", "6-8", "9-12", "13+"):
        raise Invalid("invalid band")
    if not isinstance(data["avatar"], str) or not re.fullmatch(r"[a-z0-9-]+", data["avatar"]):
        raise Invalid("invalid avatar")
    return data


def safe_dir(path: Path, create: bool = False) -> None:
    if create and not path.exists():
        parent = path.parent
        parent_info = parent.lstat()
        if (
            not stat.S_ISDIR(parent_info.st_mode)
            or stat.S_ISLNK(parent_info.st_mode)
            or parent_info.st_uid != os.geteuid()
            or stat.S_IMODE(parent_info.st_mode) & 0o022
        ):
            raise Invalid("transaction parent has unsafe ownership or mode")
        path.mkdir(mode=0o700)
        parent_fd = os.open(parent, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
        try:
            os.fsync(parent_fd)
        finally:
            os.close(parent_fd)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise Invalid("transaction directory is not a directory")
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise Invalid("transaction directory has unsafe ownership or mode")


def record_path(directory: Path, account: str) -> Path:
    if not ACCOUNT.fullmatch(account):
        raise Invalid("invalid account")
    return directory / f"{account}.json"


def load(directory: Path, account: str) -> dict:
    safe_dir(directory)
    path = record_path(directory, account)
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise Invalid("transaction record is not a regular file")
    if info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o600:
        raise Invalid("transaction record has unsafe ownership or mode")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags)
    try:
        opened = os.fstat(fd)
        if (
            opened.st_dev != info.st_dev
            or opened.st_ino != info.st_ino
            or not stat.S_ISREG(opened.st_mode)
            or opened.st_uid != os.geteuid()
            or stat.S_IMODE(opened.st_mode) != 0o600
        ):
            raise Invalid("transaction record changed while opening")
        stream = os.fdopen(fd, "r", encoding="utf-8")
        fd = -1
        with stream:
            data = json.load(stream)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise Invalid("invalid transaction JSON") from exc
    finally:
        if fd >= 0:
            os.close(fd)
    return validate_data(data, account)


def store(directory: Path, account: str, data: dict, *, create: bool = False) -> None:
    safe_dir(directory, create=create)
    validate_data(data, account)
    path = record_path(directory, account)
    fd, temporary = tempfile.mkstemp(prefix=f".{account}.", dir=directory)
    try:
        os.fchmod(fd, 0o600)
        payload = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
        offset = 0
        while offset < len(payload):
            written = os.write(fd, payload[offset:])
            if written <= 0:
                raise OSError("short transaction write")
            offset += written
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(temporary, path)
        directory_fd = os.open(
            directory,
            os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0),
        )
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def create(argv: list[str]) -> None:
    if len(argv) != 9:
        raise Invalid("create needs DIR ACCOUNT DIRECTION DEVICE_UUID SLOT PASSWORD_MODE DISPLAY BAND AVATAR")
    directory, account, direction, device, slot_text, password_mode, display, band, avatar = argv
    directory_path = Path(directory)
    safe_dir(directory_path, create=True)
    if direction != "add" or password_mode not in ("set", "none"):
        raise Invalid("invalid new transaction")
    if device == "-" and slot_text == "-":
        device_uuid = None
        slot = None
        state = "added"
        luks_mode = "none"
    else:
        device_uuid = device
        try:
            slot = int(slot_text)
        except ValueError as exc:
            raise Invalid("invalid slot") from exc
        state = "reserved"
        luks_mode = "owned"
    path = record_path(directory_path, account)
    if path.exists() or path.is_symlink():
        existing = load(directory_path, account)
        expected = {
            "direction": direction,
            "device_uuid": device_uuid,
            "slot": slot,
            "password_mode": password_mode,
            "luks_mode": luks_mode,
            "display": display,
            "band": band,
            "avatar": avatar,
        }
        if any(existing[key] != value for key, value in expected.items()):
            raise Invalid("existing transaction does not match create request")
        return
    data = {
        "schema": SCHEMA,
        "transaction": str(uuid.uuid4()),
        "account": account,
        "direction": direction,
        "device_uuid": device_uuid,
        "slot": slot,
        "owner": str(uuid.uuid4()),
        "state": state,
        "password_mode": password_mode,
        "luks_mode": luks_mode,
        "account_state": "planned",
        "destination": "",
        "display": display,
        "band": band,
        "avatar": avatar,
    }
    store(directory_path, account, data)


def import_token(argv: list[str]) -> None:
    if len(argv) != 5:
        raise Invalid("import-token needs DIR ACCOUNT DISPLAY BAND AVATAR")
    directory, account, display, band, avatar = argv
    try:
        imported = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise Invalid("invalid token JSON") from exc
    expected_keys = {"type", "keyslots", "account", "transaction", "owner", "device_uuid", "slot", "schema"}
    if not isinstance(imported, dict) or set(imported) != expected_keys:
        raise Invalid("token has unknown or missing fields")
    if (
        imported["type"] != "omarchy-kids"
        or type(imported["schema"]) is not int
        or imported["schema"] != SCHEMA
        or type(imported["slot"]) is not int
        or imported["account"] != account
        or imported["keyslots"] != [str(imported["slot"])]
    ):
        raise Invalid("token identity is inconsistent")
    data = {
        "schema": SCHEMA,
        "transaction": imported["transaction"],
        "account": account,
        "direction": "add",
        "device_uuid": imported["device_uuid"],
        "slot": imported["slot"],
        "owner": imported["owner"],
        "state": "added",
        "password_mode": "set",
        "luks_mode": "owned",
        "account_state": "complete",
        "destination": "",
        "display": display,
        "band": band,
        "avatar": avatar,
    }
    path = record_path(Path(directory), account)
    if path.exists() or path.is_symlink():
        raise Invalid("transaction already exists")
    store(Path(directory), account, data, create=True)


def import_profile(argv: list[str]) -> None:
    if len(argv) != 6:
        raise Invalid("import-profile needs DIR ACCOUNT PASSWORD_MODE DISPLAY BAND AVATAR")
    directory, account, password_mode, display, band, avatar = argv
    create([directory, account, "add", "-", "-", password_mode, display, band, avatar])
    data = load(Path(directory), account)
    data["account_state"] = "complete"
    store(Path(directory), account, data)


def transition(argv: list[str]) -> None:
    if len(argv) != 4:
        raise Invalid("transition needs DIR ACCOUNT FROM TO")
    directory, account, old, new = argv
    data = load(Path(directory), account)
    if data["state"] != old or STATE_NEXT.get(old) != new:
        raise Invalid("invalid transaction transition")
    data["state"] = new
    if new == "removing":
        data["direction"] = "remove"
    store(Path(directory), account, data)


def lifecycle(argv: list[str]) -> None:
    if len(argv) != 4:
        raise Invalid("lifecycle needs DIR ACCOUNT FROM TO")
    directory, account, old, new = argv
    data = load(Path(directory), account)
    if data["account_state"] != old or ACCOUNT_NEXT.get(old) != new:
        raise Invalid("invalid account transition")
    data["account_state"] = new
    store(Path(directory), account, data)


def destination(argv: list[str]) -> None:
    if len(argv) != 3:
        raise Invalid("destination needs DIR ACCOUNT PATH")
    directory, account, value = argv
    data = load(Path(directory), account)
    if data["destination"] and data["destination"] != value:
        raise Invalid("home destination is already fixed")
    data["destination"] = value
    store(Path(directory), account, data)


def token(data: dict) -> dict:
    if data["luks_mode"] != "owned":
        raise Invalid("transaction has no LUKS token")
    return {
        "type": "omarchy-kids",
        "keyslots": [str(data["slot"])],
        "account": data["account"],
        "transaction": data["transaction"],
        "owner": data["owner"],
        "device_uuid": data["device_uuid"],
        "slot": data["slot"],
        "schema": SCHEMA,
    }


def main() -> int:
    if len(sys.argv) < 2:
        raise Invalid("missing command")
    command, args = sys.argv[1], sys.argv[2:]
    if command == "ensure-dir" and len(args) == 1:
        safe_dir(Path(args[0]), create=True)
    elif command == "create":
        create(args)
    elif command == "import-token":
        import_token(args)
    elif command == "import-profile":
        import_profile(args)
    elif command == "validate" and len(args) == 2:
        load(Path(args[0]), args[1])
    elif command == "field" and len(args) == 3:
        if args[2] not in REQUIRED:
            raise Invalid("unknown transaction field")
        value = load(Path(args[0]), args[1]).get(args[2])
        if value is None:
            return 0
        print(value)
    elif command == "transition":
        transition(args)
    elif command == "lifecycle":
        lifecycle(args)
    elif command == "destination":
        destination(args)
    elif command == "token" and len(args) == 2:
        print(json.dumps(token(load(Path(args[0]), args[1])), separators=(",", ":")))
    elif command == "list" and len(args) == 1:
        directory = Path(args[0])
        safe_dir(directory)
        identities: set[str] = set()
        active_slots: set[tuple[str, int]] = set()
        for path in sorted(directory.glob("kid-*.json")):
            account = path.name.removesuffix(".json")
            data = load(directory, account)
            for identity in (data["transaction"], data["owner"]):
                if identity in identities:
                    raise Invalid("duplicate transaction identity")
                identities.add(identity)
            if data["luks_mode"] == "owned" and data["state"] != "removed":
                device_slot = (data["device_uuid"], data["slot"])
                if device_slot in active_slots:
                    raise Invalid("duplicate active LUKS reservation")
                active_slots.add(device_slot)
            print(account)
    else:
        raise Invalid("invalid command or arguments")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (Invalid, OSError) as exc:
        print(f"transaction: {exc}", file=sys.stderr)
        raise SystemExit(1)
