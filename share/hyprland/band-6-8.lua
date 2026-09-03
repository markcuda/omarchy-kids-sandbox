-- Band overlay: 6-8 (SPEC.md docs/conf.md band table). See band-3-5.lua
-- for the loading mechanism and the caveats on scale envs. Smaller bump
-- than 3-5's, since a 6-8 kid needs less accommodation.
hl.env("XCURSOR_SIZE", "32")
hl.env("HYPRCURSOR_SIZE", "32")

hl.config({
  general = { gaps_in = 10, gaps_out = 20 },
})

hl.env("GDK_SCALE", "1.25")
hl.env("QT_SCALE_FACTOR", "1.25")
