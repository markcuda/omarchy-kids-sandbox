# Web policy: `omarchy-kids-web` and `share/policy/` (R-WEB-1..4)

Chromium stays the browser for everyone; a kid's copy is locked by a managed policy file only
their account's group can read. `share/policy/` is the data (SPEC.md §5.1's `policy/` directory);
`bin/omarchy-kids-web` is the one thing that turns that data into the file Chromium actually
reads.

## Files

| Path | What |
| --- | --- |
| `share/policy/<band>.json` | The band's fixed policy keys (R-WEB-2), plus `URLBlocklist`/an empty `URLAllowlist` placeholder for the two walled-garden bands. One file per band: `3-5.json`, `6-8.json`, `9-12.json`, `13+.json`. |
| `share/policy/README.md` | Every key above, its type, and where it was verified (no comments in JSON, so the citations live here). |
| `share/policy/lists/<band>.txt` | The band's starter list: one host per line, `#` starts a comment (full-line or trailing). `omarchy-kids-web render` merges this into the final `URLAllowlist` for a garden band. |
| `share/policy/chromium-flags.conf` | Omarchy's own Chromium launch flags (`omacom/omarchy` `config/chromium-flags.conf`, tag `v4.0.2`), minus every `--load-extension` entry. One flag per line, same format as Omarchy's file. Read by `omarchy-kids-web launch` and copied into a kid's own `~/.config/chromium-flags.conf` by `omarchy-kids-provision` -- see "Why not just `chromium`" below. |
| `bin/omarchy-kids-web` | `render`/`install`/`launch` — see below. |
| `/etc/chromium/policies/managed/omarchy-kids-<band>.json` | The installed result: root:`omarchy-kids-<band>`, mode `0640` (R-WEB-1). |

## Precedence

For a **walled-garden** band (6-8, 9-12 — `web=garden` in `share/bands/bands.toml`), the final
`URLAllowlist` is the union of:

1. `share/policy/lists/<band>.txt` — the band's starter list, and
2. an optional `--allow FILE` passed to `render`/`install` (same one-host-per-line format) — for
   example a kid's own approved sites.

Both are deduplicated and sorted; there is no priority between them, since both are simply
allowed. For **no browser** (3-5, `web=none`) and **filtered open web** (13+, `web=filtered`),
there is no `URLAllowlist` at all — see "Why 13+ has no list" below — and `--allow` is refused
outright rather than silently accepted and ignored (I-6: don't ship a control that isn't
enforced).

`omarchy-kids-web` reads a band's `web` mode from `share/bands/bands.toml` via
`omarchy-kids-conf band <band>`, not a second hardcoded copy of that table.

### Relationship to `share/packs/<band>.toml`'s `[garden]` table

`share/packs/<band>.toml` already carries a `[garden].sites` list (Appendix C) that
`omarchy-kids-conf get <kid> sites` falls back to for Appendix B's `sites` key — a *kid's own*
approved-sites override, resolved per kid, not rendered into a Chromium policy directly. The two
lists cover different jobs and are edited separately:

- `share/policy/lists/<band>.txt` — what this issue's tool renders into the live policy's
  `URLAllowlist` for every kid in that band. **This is the file a parent edits to grow the
  band's walled garden** (see below).
- `share/packs/<band>.toml`'s `[garden].sites` — a new kid's starting point for their own `sites`
  override, a separate mechanism (not wired to `omarchy-kids-web` by this issue).

They're kept in rough sync by hand for the well-known sites both lists already agree on
(PBS Kids, National Geographic Kids, Scratch, ...); nothing enforces that they stay identical, and
they don't need to be — a kid's own `sites` override can diverge from the band's shared starter
list.

### Why 13+ has no list

SPEC.md R-WEB-3 is explicit: "Filtered open web adds neither" `URLBlocklist` nor `URLAllowlist`.
That band's filtering is R-WEB-2's baseline (SafeSearch, YouTube Restricted Mode, and the family
DNS-over-HTTPS resolver) plus whatever the resolver's own categories cover — not a Chromium-side
site list. `share/policy/lists/13+.txt` still exists, but only as parked reference data for a
future Advanced option that isn't built yet; it is never read by `render` or `install` today.

## `omarchy-kids-web render <band> [--allow FILE] [--out FILE]`

Prints the final managed-policy JSON to stdout (or `--out FILE`). Pure — never touches
`/etc`. Used by `install` internally, and useful on its own to preview what a band's policy would
look like, or to check a kid's own approved-sites file before installing it.

```console
$ omarchy-kids-web render 6-8
{
  "DnsOverHttpsMode": "secure",
  ...
  "URLAllowlist": ["highlightskids.org", "kids.nationalgeographic.com", "pbskids.org", ...]
}
```text

## `omarchy-kids-web install <band> [--allow FILE] [--apply]`

Renders, then writes `/etc/chromium/policies/managed/omarchy-kids-<band>.json` at `0640
root:omarchy-kids-<band>` (R-WEB-1), through a same-directory temp file and rename so a browser
reading the managed-policy directory never sees a half-written file. `DRY_RUN=1` is the default
(AGENTS.md rule 8); pass `--apply`, or set `DRY_RUN=0`, to write for real. `OMARCHY_KIDS_ROOT`
prefixes the system path, the same convention `bin/omarchy-kids-session` and `lib/posture.sh`
already use, for pointing a test run at a scratch tree instead of the real `/etc`.

Ownership (`chown root:omarchy-kids-<band>`) is attempted best-effort and never fails the call:
a real run is always root (the pacman hook, the boot unit, or a parent's polkit-elevated action),
at which point it always succeeds; a non-root dev or test run cannot chown to `root:<group>`, and
`bin/omarchy-kids-assert`'s own `chromium-policy:<band>` lock already fixes the mode (and
attempts ownership again) on the real target — same reasoning `docs/assert.md` gives for that
lock, which this issue's writer fills in (that doc's own note: "a separate issue's deliverable").

## `omarchy-kids-web launch [URL]` — why not just `chromium` (issue #44)

The Web tile's exec used to be the bare command `chromium`. Live on the test laptop, that ran
Arch's `/usr/bin/chromium` wrapper script, which reads `~/.config/chromium-flags.conf` and
appends whatever it finds to the real binary's argv. Omarchy's own copy of that file
(`omacom/omarchy` `config/chromium-flags.conf`, tag `v4.0.2` — landed in a fresh kid's home by
`omarchy-provision-user`, the per-user setup `omarchy-kids-provision add` runs, R-FND-2) is:

```console
--ozone-platform=wayland
--ozone-platform-hint=wayland
--password-store=basic
--enable-features=TouchpadOverscrollHistoryNavigation
--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url,/usr/share/omarchy/default/chromium/extensions/yt-dlp,/usr/share/omarchy/default/chromium/extensions/whatsapp-slim
```

That last flag tries to load Omarchy's three bundled extensions unpacked. The kids policy always
sets `ExtensionInstallBlocklist: ["*"]` and `DeveloperToolsAvailability: 2` (R-WEB-2), so Chromium
refused every one of them and showed "Failed to load extension … Loading of unpacked extensions
is disabled by the administrator" on every single launch — a modal that also stole keyboard focus
(I-5). The policy was working exactly as intended; the flag it was refusing should never have
been offered to begin with.

`omarchy-kids-web launch` fixes this by never going through the wrapper at all: it execs
`/usr/lib/chromium/chromium` — the real binary Arch's `/usr/bin/chromium` wrapper itself execs
after reading that flags file — directly. Its argv is Omarchy's four Wayland/password-
store/feature flags from `share/policy/chromium-flags.conf` (the same four lines above, minus the
`--load-extension` line — this repo's own copy of that file), then `--no-first-run
--no-default-browser-check --hide-crash-restore-bubble --disable-session-crashed-bubble`, then
`URL` if one was given on the command line, else the band's rendered policy's
`RestoreOnStartupURLs[0]` if it ever defines one (none of today's four band templates do — see
`share/policy/README.md`). The last two flags exist because Finish (`bin/omarchy-kids-exit`,
R-EXIT-1) ends the Hyprland compositor while Chromium is still running mid-session, so without
them the *next* launch shows Chromium's own "Restore pages? Chromium didn't shut down correctly"
crash bubble instead of a clean start.

Before exec'ing anything, `launch` re-checks that this band's managed-policy file is actually
readable (R-WEB-4) — the same fail-closed rule the tile-omission logic below already gives the
Web tile itself, repeated here as defense in depth for whatever else might call `launch` directly.
The band comes from `$OMARCHY_KIDS_BAND` (set by the tile's own exec line, `OMARCHY_KIDS_BAND=<band>
omarchy-kids-web launch`, the same convention `bin/omarchy-kids-session-start`'s "more-apps" tile
already uses) or, if unset, `omarchy-kids-conf get $OMARCHY_KIDS_ACCOUNT band`.

**A kid running `chromium` directly from a terminal** (bands 9-12/13+ have one, R-BAND's table)
still goes through Arch's wrapper and still reads `~/.config/chromium-flags.conf` — a path
`omarchy-kids-web launch` never touches. So `omarchy-kids-provision add` overwrites that file with
`share/policy/chromium-flags.conf` too, at `root:root 0644`: readable (Chromium's wrapper still
picks it up) but not writable, so a kid can't quietly restore the `--load-extension` flag by
editing it. It isn't undeletable — the kid still owns `~/.config` itself, and deleting the file
just leaves Chromium with no user flags file at all, never Omarchy's extension-loading one back.

## How a parent edits the walled garden

Open `share/policy/lists/<band>.txt` (installed at
`/usr/share/omarchy-kids/policy/lists/<band>.txt`) in a text editor, add a line — plain hostname,
optionally followed by `# a reason` — and re-run `omarchy-kids-web install <band> --apply` (as
root) to push the change live. Chromium's managed-policy directory is watched for changes, so a
kid's already-open browser picks it up without a restart (confirmed in `docs/phase1/V2.md`'s
notes on the same directory). There is no wizard screen for this yet (Phase 2 / a future R-WIZ
issue); editing the file directly is the only way in v1.

## Fail-closed: the launcher's web tile

`bin/omarchy-kids-session`'s own R-DESK-2 `check_policy` already refuses the **entire** kid
session if the band's policy file is missing or unreadable, for any band whose `web` isn't `none`
(see `docs/session.md`). `bin/omarchy-kids-session-start` — which builds the Level 1/2 launcher's
tile list — carries the same check as defense in depth: it only adds the `chromium` tile when
`/etc/chromium/policies/managed/omarchy-kids-<band>.json` exists and is readable by the kid's own
account, and logs a line naming why the tile was left out otherwise
(`$XDG_RUNTIME_DIR/omarchy-kids/session-<uid>.log`, the same file `omarchy-kids-session` itself
writes to). A kid never sees a Web tile that would silently fail to open (I-6). `omarchy-kids-web
launch` itself repeats this same check (see above) before it ever execs Chromium, so the rule
holds even if something other than this tile ever calls `launch` directly.

## Verifying policy keys

Every key in `share/policy/<band>.json` was checked against Chromium's own generated policy
list, not written from memory — see `share/policy/README.md` for the exact source and the
per-key citations.

## Verified live (2026-09-03, QEMU test VM)

As a 6-8 kid, the Web tile started Chromium (the launch was logged) and `https://example.com`
rendered Chromium's own "This page is blocked. Your organization doesn't allow you to view this
site", so the managed policy at `/etc/chromium/policies/managed/omarchy-kids-6-8.json` (0640
root:omarchy-kids-6-8) is loaded and the walled garden holds. Two warts found and tracked in
#44: Omarchy's wrapper adds `--load-extension` for its bundled extensions, which the policy
rightly refuses with a modal error every launch, and a "Chromium didn't shut down correctly"
bubble appears after a Finish. DoH and the 9-12/13+ filtered mode are not yet checked live.
