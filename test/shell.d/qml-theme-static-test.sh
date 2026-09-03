#!/bin/bash
# Static check (docs/theming.md): no share/**/*.qml file hardcodes a
# literal #rrggbb(aa) color outside the two files that are allowed to —
# every other QML surface must go through share/qml/KidsTheme.qml (the
# standalone `quickshell -p` files) or qs.Commons' Color/Style singletons
# (share/bar/KidsModule.qml, the one file that runs as a real
# omarchy-shell plugin) instead of a hardcoded hex value, so every surface
# actually follows the active Omarchy theme.
#
# The two allowed exceptions, and why each is real, not an oversight:
#   - share/qml/KidsTheme.qml itself: its own fallback palette IS the
#     literal hex — the thing every other file reads through it.
#   - share/sddm-theme/Main.qml: the SDDM greeter's QML engine is plain
#     QtQuick (metadata.desktop's QtVersion=6, `import QtQuick 2.0` — no
#     Quickshell there at all, confirmed against sddm/sddm upstream by
#     docs/portal.md), so it cannot import share/qml/KidsTheme.qml (which
#     depends on Quickshell.Io.FileView) the way every other file here
#     does. Its colors already come from theme.conf's `config.*`
#     properties (lib/posture.sh's posture_write_portal_conf writes the
#     live ones into theme.conf.user); the literal hex values left in
#     Main.qml are only the `config.x || "#hex"` fallback for a box
#     nothing has provisioned yet, exactly like every other fallback
#     constant in this repo.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

pass() { echo "PASS  $*"; }
fail() {
    echo "FAIL  $*"
    rc=1
}
rc=0

ALLOWED_FILES=(
    "share/qml/KidsTheme.qml"
    "share/sddm-theme/Main.qml"
)

is_allowed() {
    local f="$1" a
    for a in "${ALLOWED_FILES[@]}"; do
        [[ "$f" == "$a" ]] && return 0
    done
    return 1
}

found_any=0
while IFS= read -r -d '' file; do
    rel="${file#"$ROOT"/}"
    is_allowed "$rel" && continue
    found_any=1
    hits="$(grep -noE '#[0-9A-Fa-f]{6,8}' "$file" || true)"
    if [[ -n "$hits" ]]; then
        fail "$rel: literal hex color(s) found (use theme.* / Color.*):"
        while IFS= read -r hit; do fail "    $hit"; done <<<"$hits"
    else
        pass "$rel: no literal hex colors"
    fi
done < <(find "$ROOT/share" -name '*.qml' -print0 | sort -z)

if [[ "$found_any" != 1 ]]; then
    fail "no share/**/*.qml files were found at all — check this test's own find(1) call"
fi

# The two exceptions really do still exist and really do carry hex, so a
# rename or an accidental cleanup of either doesn't silently turn this
# test into "checks nothing".
for f in "${ALLOWED_FILES[@]}"; do
    path="$ROOT/$f"
    if [[ ! -f "$path" ]]; then
        fail "$f: expected exception file is missing"
    elif ! grep -qoE '#[0-9A-Fa-f]{6,8}' "$path"; then
        fail "$f: expected to still contain literal hex (fallback palette) — has it changed?"
    else
        pass "$f: still the expected literal-hex exception"
    fi
done

echo "qml-theme-static-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc

# Quickshell cannot import a sibling directory: no surface may use the directory import.
if grep -rl 'import "../qml"' share >/dev/null 2>&1; then fail "a QML surface still uses import \"../qml\""; else pass "no QML surface imports ../qml"; fi
