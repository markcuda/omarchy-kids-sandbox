-- Band overlay: 3-5 (SPEC.md docs/conf.md band table). Loaded by
-- L1.lua/L2.lua/L3.lua via dofile when OMARCHY_KIDS_BAND=3-5, after the
-- rest of that level's config, so these are the last word. Kept simple
-- on purpose: bigger cursor, bigger gaps, and bigger UI scale for a
-- pre-reader with less fine motor control than an older band.
--
-- Cursor size: hl.env, following the same XCURSOR_SIZE/HYPRCURSOR_SIZE
-- pattern default.hypr.envs uses (default there is "24").
hl.env("XCURSOR_SIZE", "48")
hl.env("HYPRCURSOR_SIZE", "48")

-- General gaps: looser than either level's default, for bigger visual
-- targets between tiles/windows.
hl.config({
  general = { gaps_in = 16, gaps_out = 32 },
})

-- Font/UI scale for GTK and Qt apps (the launcher itself is Qt/QML).
-- UNVERIFIED: not every app in this band's pack respects these (SDL
-- games like SuperTux/SuperTuxKart generally don't), so this is a
-- best-effort "where applicable" scale, not a guarantee every app in
-- share/packs/3-5.toml actually looks bigger.
hl.env("GDK_SCALE", "1.5")
hl.env("QT_SCALE_FACTOR", "1.5")
