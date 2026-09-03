# Settings: profiles, bands, and `omarchy-kids-conf` (R-BAND-1, R-BAND-2, R-BUILD-5)

One way to read and write every kid setting: band defaults live as data in `bands.toml`, a kid's
own choices live as overrides in their profile file, and `omarchy-kids-conf` is the only thing that
knows how to combine the two. No other command should read or write a kid's `.conf` file directly.

## Pieces

- `share/bands/bands.toml` — the R-BAND table as data (Appendix C): one `[band."<band>"]` table
  per band, with every value in it treated as a default.
- `share/packs/<band>.toml` — each band's starter apps (`[[app]]`) and, for a walled-garden band,
  its starter site list (`[garden]`).
- `/etc/omarchy-kids/kids/<account>.conf` — one kid's overrides, `key=value`, only the keys that
  differ from the band ever appear here (R-BAND-2).
- `bin/omarchy-kids-conf` — the CLI below.
- `lib/conf.sh` — the `key=value` file helpers (`conf_get`/`conf_set`/`conf_del`) other commands
  can also source.
- `lib/conf.py` — the one place this uses Python: reading TOML (stdlib `tomllib`) and the
  Appendix B.1 slug rule (NFKD transliteration). Never runs on its own; `omarchy-kids-conf` shells
  out to it.

## Precedence

For every key in the table below, `omarchy-kids-conf get <kid> <key>` resolves in this order and
stops at the first hit:

1. **override** — the key is set in the kid's `.conf` file.
2. **band** — the kid's band supplies it, from `bands.toml` (most keys) or from
   `share/packs/<band>.toml` (`allowlist`, `sites`).
3. **default** — a global default that isn't band-specific (`dns`, `history_visible`, `password`,
   `onboarded`).

`name`, `avatar`, and `band` have no default at all: they must already be an override, or `get`
(and anything that resolves through them) exits 2.

"Reset to band defaults" (`omarchy-kids-conf reset <kid>`) deletes every override except
`band`, `name`, `avatar`, `password`, and `onboarded` — a kid's identity and password survive a
reset; everything else falls back to their band.

## Appendix B keys

| Key | Values | Default source | Default |
| --- | --- | --- | --- |
| `name` | text | none — required | — |
| `avatar` | id from `share/avatars/` | none — required | — |
| `band` | `3-5` `6-8` `9-12` `13+` | none — required | — |
| `level` | `1` `2` `3` | band | per band |
| `web` | `garden` `filtered` `none` | band | per band |
| `dns` | `cloudflare-family` `cleanbrowsing-family` `custom:<url>` | global | `cloudflare-family` |
| `budget_min`, `budget_min_weekend` | integer minutes | band | per band |
| `lights_out`, `lights_out_weekend` | `HH:MM` | band | per band |
| `wifi` | `parent` `helper` | band | per band |
| `history_visible` | `yes` `no` | global | `yes` |
| `menu` | `trimmed` `full` | band | per band (trimmed for Levels 1-2, full for Level 3) |
| `allowlist` | comma-separated launcher ids | band's pack | the full starter pack |
| `sites` | comma-separated hosts | band's pack | the band's `[garden]` list |
| `password` | `set` `none` | global | `set` |
| `onboarded` | `yes` `no` | global | `no` |

`dns` and `history_visible` are also carried in `bands.toml` for every band (so a parent or a
future screen can see them alongside the rest of that band's defaults); the global default above
is what a key falls back to if the band table ever didn't carry it.

### Band-only fields (not profile keys)

`bands.toml` additionally carries `label`, `blurb`, `terminal` (`none` `playground` `sandboxed`),
`password_min`, and `password_optional` for each band. These describe the band itself — shown in
the wizard, used by the desktop session — and are never read through `get`/`set`/`show`, never
written to a kid's `.conf` file, and aren't part of Appendix B.

### Machine-level keys (`machine.conf`, not profile keys)

`/etc/omarchy-kids/machine.conf` (SPEC.md §5.1) holds settings with no kid to scope them to —
`parent` (docs/provision.md) and the key below — as plain `key=value` lines, read and written
directly with `lib/conf.sh`'s `conf_get`/`conf_set`, not through `omarchy-kids-conf`: there is no
kid argument for a machine-wide setting to hang off of.

| Key | Values | Default | What it does |
| --- | --- | --- | --- |
| `boot.snapshot_entries` | `hide` `show` | `hide` | `omarchy-kids-assert`'s `limine-snapshots` lock (docs/assert.md, issue #38): while `hide` and any kid exists, `/etc/default/limine`'s `MAX_SNAPSHOT_ENTRIES=0` hides Snapper's boot-menu entries, so a kid with a disk password can't pick a pre-Kids-Mode snapshot from Limine's menu and land on the parent's desktop. `show` restores the value `MAX_SNAPSHOT_ENTRIES` held before we touched it. The parent's own rollback path stays `snapper rollback` from the running system. |

## Band defaults

| Band | Level | Web | Budget / lights-out | Weekend lights-out | Wi-Fi | Terminal | Password |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 3-5 | 1 | none | 45 min / 19:00 | 19:30 | parent | none | min 4, optional |
| 6-8 | 1 | garden | 60 min / 19:30 | 20:00 | parent | none | min 4 |
| 9-12 | 2 | garden | 90 min / 20:30 | 21:00 | helper | playground | min 6 |
| 13+ | 3 | filtered | 120 min / 21:30 | 22:00 | helper | sandboxed | min 6 |

`omarchy-kids-conf bands` prints each band's `label` and `blurb`; `omarchy-kids-conf band <band>`
prints its full default table, including the band-only fields above.

## File locations (overridable for tests)

| What | Default path | Env override |
| --- | --- | --- |
| Kid overrides directory | `/etc/omarchy-kids/kids/` | `OMARCHY_KIDS_ETC` (the `/etc/omarchy-kids` root) |
| `bands.toml` and `packs/` | `/usr/share/omarchy-kids/` | `OMARCHY_KIDS_SHARE` |

Every path a real run touches is built from these two roots, so
`OMARCHY_KIDS_ETC=$scratch/etc OMARCHY_KIDS_SHARE=$scratch/share omarchy-kids-conf ...` runs
entirely against a throwaway tree — see `test/shell.d/conf-test.sh`.

## Commands

```
omarchy-kids-conf get <kid> <key>          effective value: override, else band, else default
omarchy-kids-conf set <kid> <key> <value>  write an override (validated against the table above)
omarchy-kids-conf show <kid>                every key, its value, and where it came from
omarchy-kids-conf reset <kid>                clear overrides except band/name/avatar/password/onboarded
omarchy-kids-conf bands                      list bands with their label and blurb
omarchy-kids-conf band <band>                print one band's defaults
omarchy-kids-conf slug <display name>        the kid- account-name slug for a display name (Appendix B.1)
```

`set` refuses a key that isn't in Appendix B, and a value that doesn't match the key's format, with
exit 2 and a one-line reason on stderr. `get` on an unknown key also exits 2. `get` on `name`,
`avatar`, or `band` with no override set exits 2, naming the missing key.

## Examples

```
$ omarchy-kids-conf set kid-ada name Ada
kid-ada: name=Ada
$ omarchy-kids-conf set kid-ada avatar fox
kid-ada: avatar=fox
$ omarchy-kids-conf set kid-ada band 6-8
kid-ada: band=6-8

$ omarchy-kids-conf get kid-ada level        # no override -> band 6-8's default
1
$ omarchy-kids-conf set kid-ada level 2      # override wins from here on
kid-ada: level=2
$ omarchy-kids-conf get kid-ada level
2

$ omarchy-kids-conf show kid-ada
KEY                  VALUE                          SOURCE
name                 Ada                            override
avatar               fox                            override
band                 6-8                            override
level                2                              override
web                  garden                         band
...
onboarded            no                             default

$ omarchy-kids-conf reset kid-ada            # level's override is gone; identity stays
kid-ada: reset to band defaults
$ omarchy-kids-conf get kid-ada level
1

$ omarchy-kids-conf slug "Zoë  O'Brien"
kid-zoeobrien
```

## Appendix B.1: the account-name slug

`kid-` plus a slug of the display name: lowercase ASCII, common accents transliterated (NFKD
decomposition, then combining marks and anything non-ASCII dropped), non-alphanumeric characters
dropped, the result truncated to 24 characters. Collisions (`kid-ada` already taken) are the
caller's job — `omarchy-kids-conf slug` always returns the same answer for the same name and never
appends a `-2` itself.
