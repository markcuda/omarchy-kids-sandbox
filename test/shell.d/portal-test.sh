#!/bin/bash
# Static checks for the SDDM portal (SPEC.md R-LOGIN-1..5, R-BOOT-3,
# R-SEC-3, I-5, I-7; issue #14): share/sddm-theme/{metadata.desktop,
# theme.conf,Main.qml}, the twelve share/avatars/*.svg, PKGBUILD's
# install of the theme, and lib/posture.sh's/omarchy-kids-assert's
# theme-selection drop-in. Nothing here runs SDDM, Qt, or qmllint --
# there is no SDDM/Qt install on this machine (see the UNTESTED header
# in Main.qml) -- so every check is either a text/grep check, a
# bash -n/python3 xml.etree parse, or exercises lib/posture.sh's shell
# functions directly against a scratch tree (never the real /etc, per
# AGENTS.md rule 8).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
THEME_DIR="$ROOT/share/sddm-theme"
AVATARS_DIR="$ROOT/share/avatars"
PKGBUILD="$ROOT/PKGBUILD"

pass() { echo "PASS  $*"; }
fail() { echo "FAIL  $*"; rc=1; }
rc=0

# --- metadata.desktop -----------------------------------------------------

METADATA="$THEME_DIR/metadata.desktop"
if [[ -f "$METADATA" ]]; then
    pass "share/sddm-theme/metadata.desktop exists"
    if grep -qE '^\[SddmGreeterTheme\]$' "$METADATA"; then
        pass "metadata.desktop has [SddmGreeterTheme]"
    else
        fail "metadata.desktop missing [SddmGreeterTheme]"
    fi
    if grep -qE '^MainScript=Main\.qml$' "$METADATA"; then
        pass "metadata.desktop has MainScript=Main.qml"
    else
        fail "metadata.desktop missing MainScript=Main.qml"
    fi
    for key in Name Type; do
        if grep -qE "^${key}=" "$METADATA"; then
            pass "metadata.desktop has $key="
        else
            fail "metadata.desktop missing $key="
        fi
    done
else
    fail "$METADATA not found"
fi

# --- theme.conf -------------------------------------------------------------

THEME_CONF="$THEME_DIR/theme.conf"
if [[ -f "$THEME_CONF" ]]; then
    pass "share/sddm-theme/theme.conf exists"
    if grep -qE '^\[General\]$' "$THEME_CONF"; then
        pass "theme.conf has [General]"
    else
        fail "theme.conf missing [General]"
    fi
else
    fail "$THEME_CONF not found"
fi

# --- Main.qml ----------------------------------------------------------------

MAIN_QML="$THEME_DIR/Main.qml"
if [[ -f "$MAIN_QML" ]]; then
    pass "share/sddm-theme/Main.qml exists"

    # Braces/parens balance: cheap, no qmllint needed, catches a stray
    # copy/paste error without a real QML engine.
    counts="$(python3 -c "
s = open('$MAIN_QML').read()
print(s.count('{'), s.count('}'), s.count('('), s.count(')'))
")"
    read -r ob cb op cp <<<"$counts"
    if [[ "$ob" == "$cb" && "$op" == "$cp" ]]; then
        pass "Main.qml braces/parens balance ($ob/$cb, $op/$cp)"
    else
        fail "Main.qml braces/parens do not balance ($ob/$cb, $op/$cp)"
    fi

    for needle in "userModel" "sessionModel" "sddm.login" "needsPassword" "sddm.powerOff"; do
        if grep -qF "$needle" "$MAIN_QML"; then
            pass "Main.qml references $needle"
        else
            fail "Main.qml missing a reference to $needle"
        fi
    done

    # Keyboard-complete (I-5, R-LOGIN-4): arrows, Enter, Escape all
    # handled, plus at least one generic Keys.onPressed (the power-off
    # chord).
    for needle in "Keys.onLeftPressed" "Keys.onRightPressed" "Keys.onReturnPressed" "Keys.onEscapePressed" "Keys.onPressed"; do
        if grep -qF "$needle" "$MAIN_QML"; then
            pass "Main.qml handles $needle"
        else
            fail "Main.qml missing $needle"
        fi
    done

    # R-LOGIN-1: parent identified as NOT kid-<slug>, and rendered
    # smaller than a kid tile.
    if grep -qF 'kid-' "$MAIN_QML"; then
        pass "Main.qml keys parent-vs-kid off the 'kid-' prefix"
    else
        fail "Main.qml does not reference the 'kid-' prefix anywhere"
    fi
    if grep -qF 'isParent' "$MAIN_QML"; then
        pass "Main.qml tracks isParent for smaller/last rendering"
    else
        fail "Main.qml has no isParent tracking"
    fi

    # R-LOGIN-3: the session lookup is by file (not a picker UI).
    if grep -qF 'omarchy-kids.desktop' "$MAIN_QML" && grep -qF 'omarchy.desktop' "$MAIN_QML"; then
        pass "Main.qml looks up sessionModel by the pinned .desktop file names"
    else
        fail "Main.qml does not look up both omarchy-kids.desktop and omarchy.desktop"
    fi

    # issue #39: parent detection from portal.json, never solely the
    # "kid-" username prefix; display name and avatar fallbacks.
    for needle in "portal.json" "XMLHttpRequest" "isParentAccount" "portalParent" "portalKids" "avatarSourceFor"; do
        if grep -qF "$needle" "$MAIN_QML"; then
            pass "Main.qml references $needle"
        else
            fail "Main.qml missing a reference to $needle"
        fi
    done
    if grep -qF 'charAt(0).toUpperCase()' "$MAIN_QML"; then
        pass "Main.qml capitalizes the stripped-account-name display fallback"
    else
        fail "Main.qml does not capitalize the stripped-account-name display fallback"
    fi
else
    fail "$MAIN_QML not found"
fi

# --- avatars: twelve SVGs, each parses as XML -------------------------------

EXPECTED_AVATARS=(fox owl panda frog whale cat bear bee koala otter penguin tiger)
if [[ -d "$AVATARS_DIR" ]]; then
    pass "share/avatars/ exists"
    missing=()
    for a in "${EXPECTED_AVATARS[@]}"; do
        [[ -f "$AVATARS_DIR/$a.svg" ]] || missing+=("$a.svg")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        pass "all twelve avatar SVGs are present"
    else
        fail "missing avatar SVGs: ${missing[*]}"
    fi

    bad=()
    for a in "${EXPECTED_AVATARS[@]}"; do
        f="$AVATARS_DIR/$a.svg"
        [[ -f "$f" ]] || continue
        if ! python3 -c "import xml.etree.ElementTree as ET; ET.parse('$f')" >/dev/null 2>&1; then
            bad+=("$a.svg")
        fi
    done
    if [[ ${#bad[@]} -eq 0 ]]; then
        pass "every avatar SVG parses as well-formed XML"
    else
        fail "avatar SVGs that failed to parse: ${bad[*]}"
    fi

    if [[ -f "$AVATARS_DIR/LICENSE" ]] && grep -qi "CC0" "$AVATARS_DIR/LICENSE"; then
        pass "share/avatars/LICENSE declares CC0"
    else
        fail "share/avatars/LICENSE missing or does not mention CC0"
    fi
else
    fail "$AVATARS_DIR not found"
fi

# --- PKGBUILD installs the theme --------------------------------------------

if [[ -f "$PKGBUILD" ]]; then
    if bash -n "$PKGBUILD"; then
        pass "bash -n PKGBUILD"
    else
        fail "bash -n PKGBUILD"
    fi
    pkg_body="$(sed -n '/^package()/,/^}/p' "$PKGBUILD")"
    if grep -qE 'share/sddm-theme/\.' <<<"$pkg_body" && grep -qF '/usr/share/sddm/themes/omarchy-kids' <<<"$pkg_body"; then
        pass "package() installs share/sddm-theme/ to /usr/share/sddm/themes/omarchy-kids/"
    else
        fail "package() does not install share/sddm-theme/ to /usr/share/sddm/themes/omarchy-kids/"
    fi

    # issue #39: qt6-svg so the avatar SVGs actually rasterize.
    depends_line="$(grep -E '^depends=' "$PKGBUILD")"
    if grep -qF 'qt6-svg' <<<"$depends_line"; then
        pass "PKGBUILD depends= includes qt6-svg"
    else
        fail "PKGBUILD depends= is missing qt6-svg"
    fi
else
    fail "$PKGBUILD not found"
fi

# --- lib/posture.sh: the theme drop-in writer, exercised directly ----------
# (never the real /etc/sddm.conf.d -- AGENTS.md rule 8).

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# shellcheck source=lib/conf.sh
source "$ROOT/lib/conf.sh"
# shellcheck source=lib/posture.sh
source "$ROOT/lib/posture.sh"

OMARCHY_KIDS_ROOT="$TMP/root"
export OMARCHY_KIDS_ROOT
posture_write_sddm_theme_dropin
DROPIN="$OMARCHY_KIDS_ROOT/etc/sddm.conf.d/zz-omarchy-kids-theme.conf"
if [[ -f "$DROPIN" ]] && grep -qE '^\[Theme\]$' "$DROPIN" && grep -qE '^Current=omarchy-kids$' "$DROPIN"; then
    pass "posture_write_sddm_theme_dropin writes [Theme] Current=omarchy-kids"
else
    fail "posture_write_sddm_theme_dropin did not write the expected drop-in"
fi
posture_remove_sddm_theme_dropin
if [[ ! -e "$DROPIN" ]]; then
    pass "posture_remove_sddm_theme_dropin removes the drop-in"
else
    fail "posture_remove_sddm_theme_dropin left the drop-in in place"
fi
unset OMARCHY_KIDS_ROOT

# --- lib/posture.sh: the sddm.service XHR drop-in writer (issue #39) ------

OMARCHY_KIDS_ROOT="$TMP/root2"
export OMARCHY_KIDS_ROOT
posture_write_sddm_xhr_dropin
XHR_DROPIN="$OMARCHY_KIDS_ROOT/etc/systemd/system/sddm.service.d/omarchy-kids-portal-xhr.conf"
if [[ -f "$XHR_DROPIN" ]] && grep -qE '^\[Service\]$' "$XHR_DROPIN" && grep -qxF 'Environment=QML_XHR_ALLOW_FILE_READ=1' "$XHR_DROPIN"; then
    pass "posture_write_sddm_xhr_dropin writes the QML_XHR_ALLOW_FILE_READ drop-in"
else
    fail "posture_write_sddm_xhr_dropin did not write the expected drop-in"
fi
posture_remove_sddm_xhr_dropin
if [[ ! -e "$XHR_DROPIN" ]]; then
    pass "posture_remove_sddm_xhr_dropin removes the drop-in"
else
    fail "posture_remove_sddm_xhr_dropin left the drop-in in place"
fi
unset OMARCHY_KIDS_ROOT

# --- lib/posture.sh: portal.json (issue #39) -------------------------------

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP portal.json checks: jq not found"
elif ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP portal.json checks: python3 not found"
else
    PORTAL_JSON="$TMP/portal.json"
    posture_write_portal_json "$PORTAL_JSON" mark \
        "$(printf 'kid-ada\tAda Lovelace\tfox')" \
        "$(printf 'kid-cy\tCy\towl')"
    if [[ -f "$PORTAL_JSON" ]]; then
        pass "posture_write_portal_json writes the file"
        check() { # got want label
            if [[ "$1" == "$2" ]]; then pass "$3"; else fail "$3 (want '$2', got '$1')"; fi
        }
        check "$(jq -e -r '.' "$PORTAL_JSON" >/dev/null 2>&1 && echo valid || echo invalid)" "valid" \
            "portal.json is valid JSON"
        check "$(jq -r '.parent' "$PORTAL_JSON")" "mark" "portal.json: parent"
        check "$(jq -r '.kids["kid-ada"].name' "$PORTAL_JSON")" "Ada Lovelace" "portal.json: kids[kid-ada].name"
        check "$(jq -r '.kids["kid-ada"].avatar' "$PORTAL_JSON")" "fox" "portal.json: kids[kid-ada].avatar"
        check "$(jq -r '.kids["kid-cy"].name' "$PORTAL_JSON")" "Cy" "portal.json: kids[kid-cy].name"
        check "$(jq -r '.kids | length' "$PORTAL_JSON")" "2" "portal.json: exactly two kids"
        mode="$(stat -f '%Lp' "$PORTAL_JSON" 2>/dev/null || stat -c '%a' "$PORTAL_JSON" 2>/dev/null)"
        check "$mode" "644" "portal.json: mode 0644"
        # idempotence: a second write with the same content is a no-op
        mtime1="$(stat -f '%m' "$PORTAL_JSON" 2>/dev/null || stat -c '%Y' "$PORTAL_JSON" 2>/dev/null)"
        sleep 1
        posture_write_portal_json "$PORTAL_JSON" mark \
            "$(printf 'kid-ada\tAda Lovelace\tfox')" \
            "$(printf 'kid-cy\tCy\towl')"
        mtime2="$(stat -f '%m' "$PORTAL_JSON" 2>/dev/null || stat -c '%Y' "$PORTAL_JSON" 2>/dev/null)"
        check "$mtime2" "$mtime1" "posture_write_portal_json is idempotent (no rewrite on unchanged content)"
    else
        fail "posture_write_portal_json did not write $PORTAL_JSON"
    fi
fi

echo "portal-test RESULT: $([[ $rc == 0 ]] && echo PASS || echo FAIL)"
exit $rc
