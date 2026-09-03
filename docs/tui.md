# The wizard's screen library: `lib/tui.sh` (SPEC.md R-WIZ-9, Appendix A; issue #18)

One renderer over gum, and every screen is data passed to it — a title, an optional Omy line, body
lines, and (for a choice screen) a list of choices with a one-line reason each. No command outside
this file should call `gum` directly; that's what keeps every screen looking the same and lets the
whole wizard be driven from a file instead of a keyboard.

## Pieces

- `lib/tui.sh` — the renderer: `tui_init`, `tui_header`, and one function per screen kind
  (`tui_screen_choose`, `tui_screen_input`, `tui_screen_confirm`, `tui_screen_summary`,
  `tui_progress`). Source it from a command; it is never run on its own.
- `bin/omarchy-kids-tui-demo` — walks three sample screens (Welcome, a choice screen, Done) so a
  human can see the look on a real terminal. Not part of the real wizard, which is later issues;
  this only exercises the renderer.
- `test/shell.d/tui-test.sh` — drives the library and the demo through answers files, with gum
  faked on a stub `PATH` so rendering, Esc, Ctrl+C, and the non-tty failure can all be checked
  without a real terminal.

## Two voices, one header

Spec v1.1: Omy speaks in the first person on Welcome and Done; every other screen is plain. Every
screen still gets the same bordered header — "Kids Mode", the step counter ("step *n* of *N*"),
and the screen's title — but the Omy glyph and voice line above it only render when the screen
asks for them:

```text
tui_header "$title" "$step" "$total" "$show_omy" "$omy_line"
```text

`SHOW_OMY` is `1` on Welcome and Done, `0` everywhere else — pass an empty `OMY_LINE` when it's
`0`, since it's never shown.

## Colors

`tui_init` reads the parent's current Omarchy theme through `omarchy-theme-color` (the same tool
Omarchy's own templates, OSC sequences, and previews resolve colors through) for the accent,
foreground, and muted keys, falling back to upstream's own prompt accent (`#845DF9`, from
`install/provisioning/setup-form.sh`) and 256-color `212` — this repo's `bin/omarchy-kids` stub
already uses the same fallback — when that tool or a theme isn't available yet (a dev machine, or
very early in a fresh install).

## Screen data shapes

Every `tui_screen_*` function takes its list data — choices, body lines, table rows, progress
steps — as the *name* of a bash array the caller already set, not the array itself (`local -n`
namerefs need bash 4.3+, and `test/all` also has to run on the plain macOS bash — 3.2 — that ships
with a contributor's laptop; the library copies the named array with the same indirect-by-name
idiom pre-4.3 bash has always used). Concretely:

| Function | Array element shape |
| --- | --- |
| `tui_screen_choose` | `"value\|label\|reason"` — reason may be empty (`"value\|label\|"`) |
| `tui_screen_confirm` | plain body line strings |
| `tui_screen_summary` | `"label\|value"` |
| `tui_progress` | plain step-label strings |

`|` is the field separator, so it can't appear inside a value, label, or reason.

## The prompt contract

Every prompt (`tui_screen_choose`, `tui_screen_input`, `tui_screen_confirm`) returns one of three
statuses — the installer's own contract, vendored here as knowledge (not code) from
`install/provisioning/setup-form.sh`:

| Exit | Meaning | `$TUI_REPLY` |
| --- | --- | --- |
| `0` | the screen has an answer | the answer |
| `1` | Esc — go back one screen, nothing written | unset/no |
| `130` | Ctrl+C — the human confirmed leaving, nothing written | unset |

A real gum widget already reports Esc as `1` and Ctrl+C as `130` on its own (Ctrl+C arrives as a
raw-mode byte, never a `SIGINT` gum has to catch), so the library only has to read gum's exit
status. Hitting Ctrl+C always shows one more prompt first — "Leave setup? Nothing has been changed
yet." — and only exits `130` if that's confirmed; declining redraws the screen that was
interrupted. A second Ctrl+C right there also means leave, so nobody can get stuck by mashing the
same key.

`tui_screen_confirm` is the odd one out: gum's own confirm widget can't tell Esc from choosing
"No" (both are exit `1`), and for a plain yes/no screen that's the right answer anyway — either way
means don't proceed — so `$TUI_REPLY` is `"no"` and the exit code is `1` for both.

## The answers-file contract

Every prompt has a non-interactive path, for tests and the acceptance harness:

- **A real terminal** (`stdin` is a tty, `OMARCHY_KIDS_TUI_ANSWERS` unset): gum asks, a human
  answers.
- **`OMARCHY_KIDS_TUI_ANSWERS=<file>`**: `tui_init` reads the file into memory once; each prompt
  after that consumes the next line. Two reserved lines stand in for keys a file can't press:
  - `@esc` — same as pressing Esc.
  - `@ctrlc` — same as pressing Ctrl+C. For `tui_screen_choose`/`tui_screen_input` this consumes
    one more line, `yes` or `no`, answering the leave confirmation (`tui_screen_confirm` treats
    `@ctrlc` as leaving directly, matching gum's own behavior above).

  Every screen still renders to stdout in this mode, exactly as an interactive run would — so a
  recorded session reads the same way a human's would, and `bin/omarchy-kids-tui-demo`'s output
  looks identical whether it was you or a file answering.
- **Neither** (`stdin` isn't a tty and `OMARCHY_KIDS_TUI_ANSWERS` isn't set): `tui_init` fails
  closed — returns `2` with a message on stderr — rather than hanging or guessing.

A `tui_screen_choose` answer may be the choice's `value`, its `label`, the exact rendered line
(what an interactive picker returns), or a bare 1-based number — the same number keys the footer
advertises. `tui_screen_input`'s `VALIDATOR` callback (if given) is called as `VALIDATOR "$answer"`;
it should print nothing and return `0` for a valid answer, or print a one-line reason and return
non-zero to have the screen ask again (in file mode, that just consumes the next line).

## Example

```bash
source lib/tui.sh
tui_init || exit $?  # 2 if neither a terminal nor an answers file is available

web_choices=(
  "garden|Only sites you choose|A short list you can grow. Best for younger kids."
  "filtered|Filtered open web|Adult content blocked, safe search on."
)
tui_screen_choose "What can K see on the web?" 7 12 0 "" web_choices "garden"
case $? in
  0)   echo "chose: $TUI_REPLY" ;;
  1)   : ;;  # go back a screen
  130) exit 130 ;;  # left setup; nothing changed
esac
```text

Driving the same screen from a file:

```text
$ printf 'filtered\n' > /tmp/answers
$ OMARCHY_KIDS_TUI_ANSWERS=/tmp/answers bin/omarchy-kids-tui-demo
```text

See `bin/omarchy-kids-tui-demo` for a full three-screen walk (Welcome, a choice screen, Done), and
`test/shell.d/tui-test.sh` for every case above driven through a fake `gum`.
