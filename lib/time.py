#!/usr/bin/env python3
"""lib/time.py — the one place the screen-time engine needs real Python.

bash's `date` can't turn "the clock rolled past midnight but before the
04:00 day boundary" into "yesterday's calendar date" the same way on the
dev machine's BSD date (`date -v-1d`) and the target's GNU date
(`date -d yesterday`) -- and this repo cares about both (AGENTS.md's
bash-3.2 note is the same worry, one layer down). Real calendar
subtraction and weekday math belong here instead, same reasoning as
lib/conf.py's NFKD transliteration.

Usage:
    time.py logical-day "YYYY-MM-DD HH:MM:SS"

Prints two lines: the logical day (SPEC.md Appendix F: the day rolls at
04:00 local, so 03:59 still belongs to the day before) as YYYY-MM-DD,
then "yes" or "no" for whether that logical day is a weekend (R-TIME-2:
Saturday and Sunday, Q22).

Exit 0 on success. Exit 2 with a one-line reason on stderr for a bad
timestamp -- never a Python traceback.
"""
import datetime
import sys

DAY_BOUNDARY_HOUR = 4


def die(msg):
    print(f"time.py: {msg}", file=sys.stderr)
    sys.exit(2)


def cmd_logical_day(argv):
    if len(argv) != 1:
        die("logical-day: needs one \"YYYY-MM-DD HH:MM:SS\" argument")
    try:
        now = datetime.datetime.strptime(argv[0], "%Y-%m-%d %H:%M:%S")
    except ValueError as e:
        die(f"logical-day: bad timestamp '{argv[0]}': {e}")
        return  # unreachable; keeps type-checkers happy
    # Naive on purpose: this system has no notion of timezone anywhere
    # else either (budget/lights-out are plain HH:MM local), so this
    # never converts, only walks the calendar.
    day = now.date()
    if now.hour < DAY_BOUNDARY_HOUR:
        day = day - datetime.timedelta(days=1)
    weekend = "yes" if day.weekday() >= 5 else "no"  # Monday=0 .. Sunday=6
    print(day.isoformat())
    print(weekend)


COMMANDS = {
    "logical-day": cmd_logical_day,
}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        die(f"usage: time.py {{{'|'.join(COMMANDS)}}} ...")
    COMMANDS[argv[0]](argv[1:])


if __name__ == "__main__":
    main(sys.argv[1:])
