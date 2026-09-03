
## Source header (moved from `bin/omarchy-kids-launcher-ctl`, issue #49)

Kept for reference; the file itself now carries a 3-line pointer instead.

```text
omarchy-kids-launcher-ctl: the one place the Level 1/2 Hyprland binds
(share/hyprland/L1.lua, L2.lua) go to reach the big-tile launcher
(share/launcher/shell.qml), so the Lua files don't have to guess
Quickshell's IPC details themselves (SPEC.md R-DESK-3, R-DESK-5,
Appendix E).

UNVERIFIED, and the main thing to confirm in the VM before this ships:

  `show` focuses the launcher window by its Qt/QML `title` ("Omarchy
  Kids Launcher") using plain `hyprctl dispatch focuswindow`, a stable
  core Hyprland dispatcher unrelated to Quickshell. This assumes the
  launcher is a normal top-level window (so it takes the same
  fullscreen windowrule as every other Level 1/2 app) rather than a
  wlr-layer-shell overlay; see shell.qml's header for why.

  `activate` writes "activate" into a control file that shell.qml
  polls (see its header) instead of calling into Quickshell's IPC
  system directly -- deliberately, since this repo has no confirmed
  reference for Quickshell's IPC CLI syntax. If a real `quickshell ...
  ipc call ...` turns out to work, this is the one file to change.

  `log` is unrelated to the launcher window itself: it's the
  kid-writable half of R-DATA-1's "app launches" (issue #27). The
  root-owned launches.log a parent's panel and a kid's own "what my
  grown-ups can see" screen read lives under /var/lib/omarchy-kids/,
  which a kid can never write to directly (I-3) -- so shell.qml calls
  this instead, once per tile launch (see its own header), to append
  one line to a file *this* account can write: its own
  $XDG_RUNTIME_DIR. bin/omarchy-kids-time-ledger's tick folds new
  lines from there into the root-owned log once a minute
  (lib/data.sh's data_fold_launches -- see that file's header for the
  trust boundary this mirrors from screen time). A kid could edit or
  delete their own runtime copy before the next fold; that's the same
  "deterrent, not a wall" honesty this file's own header already
  states for the rest of this package (SPEC.md 5.3) -- nothing about
  `log` enforces anything, it only records.
```
