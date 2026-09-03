-- Level 3 Hyprland config (SPEC.md R-DESK-3, Appendix E; I-3, I-5, I-6).
--
-- Root-owned, installed and provisioned the same way as L1.lua (see its
-- header). Appendix E: "Level 3: Omarchy defaults minus: terminal-
-- launching binds under menu=trimmed (kept under full), omarchy-sudo-
-- passwordless, screenshot-to-clipboard of other users' windows (n/a),
-- plus Super+Shift+K." Unlike L1/L2, Level 3 gets the *real* Omarchy
-- desktop -- require("default.hypr.omarchy") pulls in the same
-- bindings, looknfeel, input, envs, and windows a grown-up's session
-- gets (see hypr-omarchy.lua in the reference material this was written
-- against) -- and then this file removes exactly what Appendix E says
-- to remove.
require("default.hypr.omarchy")

-- --- Unbind: terminal-launching binds (menu=trimmed) --------------------
--
-- UNVERIFIED, and the most important gap in this file to close before
-- shipping: default.hypr.bindings.applications -- the module that binds
-- terminal-launching keys (and, per Appendix E, something called
-- "omarchy-sudo-passwordless") -- was not in the reference material
-- used to write this file (only bindings-tiling.lua and
-- bindings-utilities.lua were available, and neither mentions a
-- terminal or sudo at all). hl.unbind here is assumed to take the same
-- key-combo string o.bind's first argument does and remove whatever is
-- bound to it -- bindings-utilities.lua's selection-layer comment
-- describes exactly this operation as risky *only* because it could
-- strip a user's own rebinding of that key from their personal
-- ~/.config/hypr files; L3.lua has no such personal layer (R-DESK-6:
-- the kid's ~/.config/hypr is never read), so unbinding by key here
-- carries none of that risk.
--
-- SUPER + RETURN for the default terminal is assumed from near-universal
-- Hyprland/tiling-WM convention, not confirmed against Omarchy's actual
-- default.hypr.bindings.applications. Confirm the real terminal bind (and
-- whether Omarchy has more than one, e.g. a second terminal or a file
-- manager also gated by menu=trimmed) with `omarchy-menu-keybindings` or
-- `hyprctl binds` on a running Omarchy 4.0.2 box, then fix this list.
hl.unbind("SUPER + RETURN")

-- "omarchy-sudo-passwordless" is deliberately NOT guessed at here. Two
-- reasons: (1) a wrong key-combo guess for hl.unbind risks silently
-- unbinding an unrelated real binding that happens to share that combo,
-- which is worse than doing nothing; (2) reading default.hypr.autostart
-- (this repo's hypr-autostart.lua reference copy) suggests it may not be
-- a keybind at all -- it calls `omarchy-provision-first-run` on every
-- hyprland.start, which sounds like the more likely place passwordless
-- sudo gets granted (a first-run convenience for Omarchy's single-user
-- desktop model), not a key someone presses. If that's right, requiring
-- default.hypr.omarchy above re-runs that provisioning for the kid too,
-- which R-DESK-3/the Appendix G bypass matrix ("Kid runs sudo -> No
-- grant") says must never happen. This needs a real Omarchy box to
-- confirm one way or the other and is called out in the PR/issue rather
-- than silently "fixed" with a guess; see docs/levels.md.

-- --- Add: the exit modal bind (Appendix E) -------------------------------
o.bind("SUPER + SHIFT + K", "Kids Mode: parent", "omarchy-kids-exit")

-- --- Start the session (starts Omarchy's shell, not the L1 launcher) ----
hl.on("hyprland.start", function()
  hl.exec_cmd("omarchy-kids-session-start")
end)

-- --- Band overlay (in practice 13+ has its own look; kept for any kid
-- whose level was manually raised while still in a younger band) -------
local HYPRLAND_DIR = os.getenv("OMARCHY_KIDS_HYPRLAND_DIR") or "/etc/omarchy-kids/hyprland"
local band = os.getenv("OMARCHY_KIDS_BAND")
if band == "3-5" then
  dofile(HYPRLAND_DIR .. "/band-3-5.lua")
elseif band == "6-8" then
  dofile(HYPRLAND_DIR .. "/band-6-8.lua")
end
