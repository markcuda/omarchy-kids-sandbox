# Theme plumbing: `lib/theme.sh`, `share/qml/KidsTheme.qml`, the portal (issue #48)

Every Kids Mode surface — the parent wizard/panel TUI, the kid-facing Quickshell windows, the
SDDM portal — follows whatever Omarchy theme the parent picked, the same way Omarchy's own
tools and shell do. One bash entry point and one QML entry point, both reading the same kind of
source Omarchy's own code reads, plus one posture writer that gets the portal (which runs before
any session, kid or parent, has ever logged in) the same colors at provision/assert time.

## Ground truth this rests on

Fetched and read directly from `omacom/omarchy` at tag `v4.0.2`, 2026-09 — cited in full in
`lib/theme.sh`'s and `share/qml/KidsTheme.qml`'s own header comments:

- `themes/<name>/` — one directory per theme. What's actually there varies theme to theme; the
  only file every theme in that release ships is `colors.toml` (a theme missing one is
  auto-generated from its `alacritty.toml` at `omarchy theme set` time, `bin/omarchy-theme-
  colors-from-alacritty`). Most themes also carry `backgrounds/`, `icons.theme`, `preview*.png`,
  `unlock.png`; some carry `neovim.lua`, `hyprland.lua`, `vscode.json`, a terminal config. None of
  that other-app-specific config is what Kids Mode reads — only `colors.toml`.
- `$HOME/.local/state/omarchy/current/theme/` — the **current** theme: a real directory (not a
  symlink), rebuilt whole by `bin/omarchy-theme-set` on every `omarchy theme set` (copy the theme,
  overlay the user's own copy if any, generate the dynamic app configs, `mv` into place). **Not**
  `$HOME/.config/omarchy/current/theme` — that path doesn't exist on this stack. The theme's own
  display name lives beside it, in `.../current/theme.name` (`bin/omarchy-theme-current`).
- `bin/omarchy-theme-color` — "Resolve semantic colors from an Omarchy theme colors.toml", the
  same tool Omarchy's own templates, OSC sequences, and previews resolve colors through
  (`docs/tui.md` already cited this before this file existed). Defaults to reading
  `$HOME/.local/state/omarchy/current/theme/colors.toml`, or `--file <path>`. Resolves a semantic
  key (`background`, `foreground`, `accent`, `muted`, `red`, `orange`, …) through a legacy
  `color0..15`/short-name alias cascade and derived shades, so a theme only defining part of the
  palette still resolves every key. **Omarchy's own palette has no `error`/`warning` key** — this
  repo maps those to `red` and `orange` (itself falling back to `yellow`), the colors Omarchy's
  own generated app configs already use for error/warning states.
- `shell/Commons/Color.qml` / `Style.qml` / `qmldir` — the real Quickshell shell's own theme
  singletons (`module qs.Commons`, `singleton Color 1.0`, `singleton Style 1.0`). `Color` reads
  `colors.toml` (foreground/background/accent/urgent/muted) with a FileView at startup and is
  pushed live updates over shell IPC on every theme change; `Style.fontFamily` is always the
  fontconfig alias `"monospace"`, resolved to a concrete family with `fc-match -f '%{family[0]}'
  monospace` (`Style.qml`'s `fcMatchProc`) — never read from `colors.toml` at all.
- There is **no system-wide (root-level) current theme** anywhere in this release — every path
  above is `$HOME`-relative, because Omarchy is a single-user desktop. That's why the portal
  section below has to resolve the *parent's* `$HOME` explicitly.

## `lib/theme.sh`: the bash entry point

```sh
theme_dir                 # the directory whose colors.toml the functions below read
theme_color NAME           # background | foreground | accent | muted | error | warning
                            # (plus three portal-only extras: surface | surface_muted | highlight)
theme_font                 # the resolved font family, same as Style.qml's fcMatchProc
```

`theme_color` shells out to `omarchy-theme-color --file "$(theme_dir)/colors.toml" <key>` (mapping
`error`→`red`, `warning`→`orange`) and falls back to this repo's own dark palette — the exact
values `share/sddm-theme/theme.conf` and every `share/**/*.qml` file already hardcoded before this
file existed — whenever that tool isn't on `PATH`, the theme has no `colors.toml` yet, or a key
comes back empty. `theme_font` runs the identical `fc-match` command `Style.qml` does, falling back
to `"JetBrainsMono Nerd Font"` (`theme.conf`'s own original default).

`THEME_KIDS_HOME` overrides `$HOME` for a caller resolving *another* account's theme — the portal
writer below is the one caller that needs it, since it runs as root but has to read the parent's
theme, not root's.

**Issue #48 live finding**: running a Kids Mode command outside a full Omarchy session (no
Hyprland login — SSH, `unshare`, CI) can leave `$OMARCHY_PATH` unset, and Omarchy's own tools
depend on it to find their own installed files. Sourcing `lib/theme.sh` now, unconditionally and
before any Omarchy tool runs:

- defaults `OMARCHY_PATH` to `/usr/share/omarchy` (where the package installs itself) if unset;
- upgrades `LANG` to `C.UTF-8` if it's unset or the plain `"C"` locale (gum's own box-drawing
  needs a UTF-8 locale, not just to look right — the bordered header in `lib/tui.sh`).

Beyond that, a theme tool that's missing or broken for any other reason never aborts a Kids Mode
command — `theme_color`/`theme_font` fall back to the palette above, with exactly **one** warning
line per process (`_theme_kids_tool_ready`'s own cache — never once per color resolved), not a
crash and not silence. `test/shell.d/theme-test.sh` proves this under `set -euo pipefail`, the mode
every `bin/omarchy-kids-*` command runs in.

`lib/tui.sh` sources `lib/theme.sh` and uses `theme_color` for every `gum style` flag it emits
(`TUI_C_ACCENT`/`TUI_C_FG`/`TUI_C_MUTED`/`TUI_C_ERROR` — the bordered header, the Omy voice line,
footers, and a failed validator's error line), so the wizard and panel look like `omarchy-menu`
under whatever theme the parent is running (`docs/tui.md`'s own "Colors" section).

## `share/qml/KidsTheme.qml`: the QML entry point

Every Quickshell surface in this repo except `share/bar/KidsModule.qml` runs as its own standalone
`quickshell -p <file>` process (`share/launcher/shell.qml`'s own header explains why), not inside
Omarchy's long-running `omarchy-shell`. That rules out `import qs.Commons` for those files — that
module namespace only exists inside the shell process itself, and nothing here sets
`QML2_IMPORT_PATH` to extend it to a bare `quickshell -p` invocation. So `share/qml/KidsTheme.qml`
does for those files exactly what `shell/Commons/Color.qml` does for the real shell: read
`$HOME/.local/state/omarchy/current/theme/colors.toml` straight off disk with a `FileView`, using
the same key/fallback chases (`background`→`color0`, `accent`→`color4`, `foreground`→`color7`,
`muted`→`color8`, plus this repo's own `error`→`red`→`color1` and `warning`→`orange`→`yellow`→
`color3`), and resolve the font with the identical `fc-match` command via a
`Process`/`StdioCollector`/`onStreamFinished` — the one `Quickshell.Io.Process` shape already
confirmed live in this repo (`share/bar/KidsModule.qml`'s own `askProcess`).

It's a plain `QtObject`, not a `pragma Singleton`: every file that wants it just instantiates its
own copy —

```qml
import "../qml"
// ...
KidsTheme { id: theme }
// ...
color: theme.background
```

— because each `shell.qml` here is already its own separate process; there's no cross-file
singleton worth sharing within one QML engine the way the real shell needs one. Every color a
file needs beyond the six names (a "raised tile" look, a highlighted state) is derived from those
six with `Qt.lighter()`/`Qt.darker()` rather than adding more names to the shared contract — see
any of `share/launcher/shell.qml`, `share/exit-modal/shell.qml`, etc. for the pattern.

**`share/bar/KidsModule.qml` is the one exception**: it really does run inside `omarchy-shell`, as
a first-party-style plugin (its own header cites `manual/32-shell-plugins.md` and the real
`shell/Ui/Panel.qml`-based examples this file's structure mirrors), so it imports `qs.Commons`
directly — `Color.background`/`Color.accent`/`Color.muted`/`Color.urgent`/`Color.foreground` and
`Style.font.family`/`Style.selectedFillFor(...)` — instead of `KidsTheme.qml`. That's the "prefer
importing Omarchy's own shell theme singleton" path the module system actually allows here.

## The portal: `theme.conf` / `theme.conf.user`

`share/sddm-theme/Main.qml` runs under SDDM's own greeter engine — plain `QtQuick` (`metadata.
desktop`'s `QtVersion=6`, `import QtQuick 2.0`, confirmed against `omacom/omarchy`'s and `sddm/
sddm`'s own upstream source, `docs/portal.md`). **There is no Quickshell there at all**, so
`Main.qml` cannot import `share/qml/KidsTheme.qml` (which needs `Quickshell.Io.FileView`) — this is
the one QML file in this repo that keeps its own hardcoded `config.x || "#hex"` fallbacks, same as
before this issue, for exactly that reason (and the one exemption in the static check below).

`Main.qml` already reads every color as `config.<key>` — SDDM's own `ThemeConfig::setTo()`
(`sddm/sddm`'s `src/common/ThemeConfig.cpp`) loads `theme.conf`'s `[General]` keys into that
`config` property, then loads a *second* file, `theme.conf.user`, right beside it, and layers any
key it sets non-empty over the first (`docs/portal.md`'s own citation for `parent=`/`kids=`). This
issue adds nine more keys to that same `theme.conf.user`, alongside `parent=`/`kids=`, so SDDM
picks all of it up in the one pass it already makes:

| `theme.conf.user` key | `lib/theme.sh` source |
| --- | --- |
| `backgroundColor` | `theme_color background` |
| `tileColor` | `theme_color surface` (→ `lighter_background`) |
| `tileHighlightColor` | `theme_color highlight` (→ `selection`) |
| `parentTileColor` | `theme_color surface_muted` (→ `dark_background`) |
| `accentColor` | `theme_color accent` |
| `textColor` | `theme_color foreground` |
| `mutedTextColor` | `theme_color muted` |
| `errorColor` | `theme_color error` |
| `fontFamily` | `theme_font` |

`lib/posture.sh`'s `posture_theme_conf_lines PARENT` resolves all nine, with `THEME_KIDS_HOME` set
to the *parent's* `$HOME` (`posture_parent_home`, a real `getent passwd` lookup — the account
already exists by the time posture writes anything) — not root's, since posture code runs as root
and there is no root-level theme to read (see "Ground truth" above). `posture_portal_conf_text`
appends those nine lines to the existing `parent=`/`kids=` `[General]` block, so
`posture_write_portal_conf` writes (and `omarchy-kids-assert`'s `portal-conf` lock re-asserts) the
whole eleven-key file in one write, same as before this issue.

This runs at **provision and assert time**, not at kid-login time: whatever theme the parent was
running the moment `omarchy-kids-provision add`/`omarchy-kids-assert` last ran is what the portal
shows, until the next provision/assert. `omarchy-kids-assert` runs on every pacman transaction
(the `omarchy-kids.hook`) and at boot, so a parent who changes their Omarchy theme picks it up on
the portal after the next of those — not instantly, the same way `theme.conf.user`'s `parent=`/
`kids=` data already only refreshes on assert, not live.

## How a theme author gets Kids Mode for free

Nothing. A theme that already works with Omarchy — a `colors.toml` with the usual
`background`/`foreground`/`accent`/`color0..15` keys — already themes every Kids Mode surface
through this plumbing, with zero Kids Mode-specific work: `theme_color`/`KidsTheme.qml` read the
exact same file Omarchy's own tools do, with the exact same alias/fallback rules. A theme that
also defines the *semantic* names — `red`, `orange` (or `yellow`), `lighter_background`,
`dark_background`, `selection` — gets more accurate `error`/`warning`/tile-surface colors than one
that only ships the plain ANSI `colorN` set; both work.

## Tests

- `test/shell.d/theme-test.sh` — `theme_dir`/`theme_color`/`theme_font` against a fixture
  `colors.toml` and the fallback path (real-shaped fake `omarchy-theme-color`/`fc-match` on a
  stub `PATH`, `THEME_KIDS_HOME` pointed at a scratch home); the issue #48 `OMARCHY_PATH`/`LANG`
  defaults; a broken theme tool never aborting a caller running under `set -euo pipefail`, logging
  exactly one line.
- `test/shell.d/qml-theme-static-test.sh` — no `share/**/*.qml` file hardcodes a literal
  `#rrggbb`/`#rrggbbaa` color outside `share/qml/KidsTheme.qml` (its own fallback palette) and
  `share/sddm-theme/Main.qml` (the SDDM-engine exemption above) — and that those two files still
  actually carry hex, so the exemption list can't silently start checking nothing.
- `test/shell.d/portal-test.sh` — `posture_theme_conf_lines`/`posture_portal_conf_text` emit all
  nine keys, falling back correctly with no parent theme on disk, and — with a fixture `colors.
  toml` under a scratch parent `$HOME` plus a stub `omarchy-theme-color` — that the real values
  actually flow through `posture_write_portal_conf` end to end.

## What still needs the VM

Nothing here can be visually confirmed without a real Quickshell/Hyprland session and a real SDDM
greeter (`share/launcher/shell.qml`'s own UNTESTED banner, `docs/portal.md`'s own "Ground truth"
section — neither has changed). Once in the VM: set at least two different Omarchy themes (a dark
one and `white`, say) and screenshot every surface under each — the launcher, the exit modal, ask,
the time toast and time's-up overlay, the plugins shelf, the Wi-Fi picker, the parent's bar widget,
and the SDDM portal after a provision/assert — to confirm colors actually follow the theme instead
of just compiling. Also confirm `share/bar/KidsModule.qml`'s `import qs.Commons` actually resolves
inside a real `omarchy-shell` plugin load (its own header's still-unconfirmed item), and that
`Style.selectedFillFor`'s three-argument call really matches what a live `Style.qml` expects.
