# Omarchy Kids Mode, sandbox path: specification v1

Status: **draft for review**, 2026-09-02. Decisions come from the hub's
[PATH-SANDBOX.md](https://github.com/markcuda/omarchy-kids-mode/blob/main/PATH-SANDBOX.md);
this document turns them into requirements, architecture, and acceptance criteria. Requirement ids
(`R-WEB-3`) are referenced by the issues.

## 1. Scope

**v1 (this spec):** the Kids Mode app on a normal Omarchy 4.0.x install: the parent wizard and
panel, per-kid provisioning, the login portal, the exit modal, the kid desktop at three levels, web
policy, screen time, apps, ask-a-parent, Wi-Fi, recorded data, trust and undo, packaging.

**Phase 2 (not this spec):** the kid onboarding wizard with Omy, earned level progression, Learn
with Omy. v1 leaves a hand-off contract (§6.1) for it.

**Out, deliberately:** installer changes; a parent login of any new kind; cloud or remote anything;
Flatpak; malcontent; timekpr; a machine-wide DNS or browser policy.

## 2. Definitions

- **Parent**: the owner account of the install, in `wheel`. Any adult in the house uses it or its password.
- **Household parent password**: the owner's password. On a Me install it is already root's.
- **Kid profile**: a real Unix account created by the app, member of group `omarchy-kids`, never in `wheel`.
- **Band**: 3-5, 6-8, 9-12, 13+. Picks defaults. Every default is overridable per kid.
- **Level**: 1 (one app, fullscreen), 2 (split), 3 (tiling). Parent-set in v1.
- **Lock**: a root-owned artifact that constrains a kid session. **Fence**: a lock that is a deterrent, not a wall; stated as such in the UI.
- **Path**: this repo is the sandbox path; the installer path is upstream (hub `PATH-INSTALLER.md`).

## 3. Invariants

These hold everywhere and override any feature.

- **I-1 The parent's account is never restricted.** No policy, resolver, firewall, launcher, or hook touches the parent's session, home, browser, or DNS, including while a kid is paused. The only parent-side writes are the ones the parent asks for (hide kids' apps, parents-only fence).
- **I-2 Nothing about a child leaves the machine.** No telemetry, no accounts, no cloud, no network listener.
- **I-3 Every lock is root-owned and lives outside every home.** Nothing in `~` enforces anything.
- **I-4 Every lock is re-asserted after updates** by a pacman hook and verified at every kid login. A missing lock fails closed: the kid session does not start.
- **I-5 Keyboard-complete.** Every screen this repo ships works with no pointer.
- **I-6 Honest UI.** No control is shown that is not enforced. Fences are labeled fences.
- **I-7 Core untouched.** No file owned by the `omarchy` or `omarchy-settings` packages is edited. Extension points only: drop-ins, hooks, session entries, themes, policy folders, own package.

## 4. Requirements

### R-FND Foundation

- R-FND-1 Kids Mode installs as one Arch package on a stock Omarchy 4.0.x Me install and appears as "Kids Mode" in the app drawer.
- R-FND-2 Adding a kid creates a Unix account: `useradd -m`, shell `/bin/bash`, no supplementary groups except `omarchy-kids`; home mounted `nosuid,nodev,noexec` via a bind entry in fstab.
- R-FND-3 The kid account receives the installer path's posture: an explicit sudoers grant that asks for root's password (`Defaults rootpw` scoped to that account), a polkit admin rule naming `unix-user:root` for that account, and `timestamp_timeout=0` so no sudo credential is cached in a kid session.
- R-FND-4 Polkit denies for kid accounts, no prompt: NetworkManager settings modify (unless R-WIFI-2), udisks mount/unlock, systemd manage-units, package management.
- R-FND-5 Text consoles tty2..6 are masked while any kid profile exists; unmasked on remove.
- R-FND-6 Removing a kid removes the account, its LUKS slot, its policy group membership, and moves its home to `~parent/Kids Mode/<name>/` (I-6, R-TRUST-4).

### R-SEC Secrets and disk

- R-SEC-1 One password per kid, set in the wizard, stored in shadow. Minimum length 4 for bands 3-5 and 6-8, 6 for 9-12 and 13+. A profile may be "no password" only in band 3-5.
- R-SEC-2 Each kid's password is added as a LUKS2 key slot on the root device at creation; changed when the password changes; removed with the kid. "No password" profiles get no slot.
- R-SEC-3 The parent password opens any kid's tile at the portal and any kid's lock screen through a PAM `pam_exec` helper that runs with `seteuid`, tries the kid's own password first, and never leaves a cached credential. Root's faillock applies to guesses; the kid's faillock does not block the parent path.
- R-SEC-4 A kid changes their own password from their session with the old one; a parent resets any kid's password from the panel. Both update the LUKS slot.

### R-LOGIN Login portal

- R-LOGIN-1 An SDDM theme shows one tile per kid (avatar from the mascot skin set, name), then a password field; the parent tile last and visually smaller.
- R-LOGIN-2 "No password" profiles log in on Enter.
- R-LOGIN-3 Kid tiles show no session picker; kid accounts are pinned to the `omarchy-kids` session through AccountsService.
- R-LOGIN-4 Full keyboard navigation: arrows between tiles, Enter selects, Esc back.

### R-EXIT Exit modal

- R-EXIT-1 In any kid session, pressing Super three times within 1.5 s opens a root-owned overlay: a password field and two actions, **Pause <name>** ("<possessive> apps stay open. You switch to your desktop.") and **Finish for <name>** ("Closes <possessive> apps. You switch to your desktop.").
- R-EXIT-2 The password is checked against root's through the same helper as R-SEC-3.
- R-EXIT-3 Pause locks the kid session (hyprlock) and switches to the greeter for the parent. Finish terminates the kid's logind session cleanly (apps get SIGTERM, then the session ends) and switches to the greeter.
- R-EXIT-4 A paused kid resumes at their own lock screen with their own password (or the parent's).
- R-EXIT-5 The parent session, when the parent switches away from it, is locked.

### R-DESK Kid desktop

- R-DESK-1 A `omarchy-kids.desktop` Wayland session entry, root-owned, runs `omarchy-kids-session`, which reads the kid's profile and execs Hyprland with `--config /etc/omarchy-kids/hyprland/L<level>.lua` plus the band overlay.
- R-DESK-2 Before starting the compositor the launcher verifies: profile present, policy file readable by this account, sudoers and polkit drop-ins present, home noexec, consoles masked. On any failure it shows a full-screen "Ask a grown-up" screen with the failing check named and exits.
- R-DESK-3 Level 1: every window fullscreen, one at a time; a big-tile launcher listing only allowed apps; `Super+Home` returns to the launcher; no terminal, no file manager. Level 2: 50/50 split, `Super+arrows`, launcher plus the cheat sheet; Level 3: Omarchy tiling with a trimmed root-owned binding set and a kid theme.
- R-DESK-4 The allowlist is what the launcher shows and the bindings reach. Under Level 3 this is a fence (I-6). The "parents only" fence (R-APPS-6) is available in Advanced.
- R-DESK-5 The kid's own `~/.config/hypr` is never read; `--config` wins.

### R-WIZ Wizard and panel

- R-WIZ-1 First run of the app is the wizard; later runs open a home screen listing kids, with a settings gear into the panel.
- R-WIZ-2 The wizard asks up front: Easy or Advanced. Easy: band, then A-or-B chunks (web, time, apps, Wi-Fi, level) preselected from the band table. Advanced: the same cells as a grouped checklist.
- R-WIZ-3 Per kid: name, avatar (pick from the skin set), band, password (or "no password" in 3-5).
- R-WIZ-4 Machine-level setup runs silently on first apply: group, hooks, session entry, SDDM theme, console masking, snapshot (R-TRUST-1).
- R-WIZ-5 A summary in plain words precedes apply. Apply shows progress; app installs continue in the background (R-APPS-3); the safety check is the last screen.
- R-WIZ-6 Add-a-kid runs only R-WIZ-3 and the chunks. Every cell is editable later in the panel.
- R-WIZ-7 The panel per kid shows: time today and this week, top apps, browsing history, open requests, every setting, safety status; and actions: edit, reset password, pause/finish (if live), remove.
- R-WIZ-8 The wizard runs in Omarchy's floating terminal, bash + gum, with the look of the installer: a header where the logo sits (Omy placeholder), one question per screen, step counter, Esc back, Ctrl+C leaves with nothing changed, colors from the parent's current theme. Screens are data; the renderer is a library.

### R-BAND Bands and defaults

| Band | Level | Web | Budget / off at | Starter pack | Wi-Fi | Terminal |
| --- | --- | --- | --- | --- | --- | --- |
| 3-5 | 1 | No browser | 45 min / 19:00 | GCompris, Tux Paint, KTuberling, Blinken | Parent only | No |
| 6-8 | 1 | Walled garden | 60 min / 19:30 | plus SuperTux, SuperTuxKart, KLettres, Kanagram | Parent only | No |
| 9-12 | 2 | Walled garden | 90 min / 20:30 | plus TurboWarp, Luanti, KTouch, Pixelorama, Kiwix | Safe helper | Playground shell |
| 13+ | 3 | Filtered open web | 120 min / 21:30 | plus Sonic Pi, Thonny, KStars | Safe helper | Sandboxed shell |

- R-BAND-1 The table is data (`/usr/share/omarchy-kids/bands.toml`), not code.
- R-BAND-2 Every cell is overridable per kid; the profile stores only overrides.

### R-WEB Web

- R-WEB-1 Chromium remains the browser for everyone. Kids policy lives in `/etc/chromium/policies/managed/omarchy-kids-<band>.json`, mode 0640, owner root, group `omarchy-kids-<band>`; each kid is a member of exactly one band group. The parent is a member of none.
- R-WEB-2 Every kids policy sets: `DnsOverHttpsMode: secure` with a family template (Cloudflare Family by default; CleanBrowsing Family or custom in Advanced), `ForceGoogleSafeSearch`, `ForceYouTubeRestrict: 2`, `IncognitoModeAvailability: 1`, `DeveloperToolsAvailability: 2`, `ExtensionInstallBlocklist: ["*"]`, `BrowserSignin: 0`, `DownloadRestrictions: 1`, `SavingBrowserHistoryDisabled: false`, `AllowDeletingBrowserHistory: false`.
- R-WEB-3 Walled garden adds `URLBlocklist: ["*"]` and a `URLAllowlist` from the band's starter list plus the kid's approved sites. Filtered open web adds neither. No browser hides Chromium from the launcher and sets `URLBlocklist: ["*"]`.
- R-WEB-4 The kid launcher refuses to start Chromium if the kid's policy file is not readable (fail closed).
- R-WEB-5 Web apps installed for a kid use `omarchy-webapp-install` in the kid's account, so they inherit the policy.
- R-WEB-6 Machine DNS is never changed by this package. Advanced may offer machine-wide family DNS as an opt-in belt with the I-1 warning.

### R-TIME Screen time

- R-TIME-1 `omarchy-kids-time` (also reachable as `omarchy-parent-time`) is a root systemd service that accounts active, unlocked logind sessions of kid accounts at 30 s resolution and persists per-day totals under `/var/lib/omarchy-kids/<name>/usage/`.
- R-TIME-2 Budget (minutes/day) and lights-out (HH:MM) per kid; weekend variants optional. Paused or locked time does not count.
- R-TIME-3 Warnings at 10, 5, and 1 minute through the kid session's notification daemon, then a full-screen "time's up" with "Ask for more time".
- R-TIME-4 At budget or lights-out the session is locked, then terminated after a grace of 60 s unless a parent grants more time. "Ask for more time" opens the ask modal (R-ASK-1); a parent password at the keyboard grants a chosen amount; otherwise the request queues.
- R-TIME-5 A local weekly summary per kid in the panel; no email, no cloud.

### R-APPS Apps

- R-APPS-1 Sources: official repos and AUR via `omarchy-pkg-*`. No Flatpak.
- R-APPS-2 Starter packs per band are data (`/usr/share/omarchy-kids/packs/<band>.toml`) with package, launcher name, category, age badge, and any web-app entries.
- R-APPS-3 Confirming the apps screen starts `omarchy-kids-install@<name>.service`, a root oneshot with a journal; the wizard shows progress and never blocks. Failures are listed in the panel with a retry.
- R-APPS-4 Per-kid allowlist: the launcher shows only allowed entries; entries appear as installs land.
- R-APPS-5 "Hide kids' apps from my launcher" writes `Hidden=true` overrides into the parent's own `~/.local/share/applications`, only when the parent enables it.
- R-APPS-6 "Parents only" marks an installed binary `0750 root:omarchy-parents` (a group containing the owner), re-asserted by the pacman hook. Labeled as a fence.
- R-APPS-7 A kids-plugins shelf reads the marketplace catalog filtered to category Kids, verified listings only; installation always goes through R-ASK. No plugin may enforce anything (I-3).

### R-ASK Ask a parent

- R-ASK-1 One modal, "Ask a parent", for more time, an app, a plugin, a site. If a parent types the parent password there, the request is granted on the spot. Otherwise it is appended to `/var/lib/omarchy-kids/queue/` as a root-owned record, and the kid sees "Asked. Your grown-up will see it."
- R-ASK-2 The panel lists open requests per kid with approve/decline on one keystroke. Approve performs the action (install, allowlist, grant minutes).
- R-ASK-3 The queue format is documented so a future home-network approver can read and write it. v1 ships none.

### R-WIFI Wi-Fi

- R-WIFI-1 Per kid: `parent` (default 3-5, 6-8) or `helper` (default 9-12, 13+).
- R-WIFI-2 Under `helper`, `omarchy-kids-wifi` runs a pkexec helper on the host that takes an SSID and password, joins, then sets the connection to ignore DHCP DNS and clear its own DNS. The kid never reaches NetworkManager settings directly.
- R-WIFI-3 Captive portals: on `connectivity: portal` the helper opens the portal URL in a helper window with strict DoH relaxed to automatic for that window's profile, then restores strict on `connectivity: full`. Walled garden still applies except the portal host.
- R-WIFI-4 Under `parent`, the kid-side Wi-Fi panel's join opens the ask modal.

### R-DATA Recorded data and transparency

- R-DATA-1 Recorded, locally: active minutes per day, app launches (name, time), requests and outcomes, browsing history read from the kid's Chromium profile.
- R-DATA-2 Never recorded: keystrokes, screenshots, file contents, message contents.
- R-DATA-3 Each kid session has a "What my grown-ups can see" screen that shows exactly R-DATA-1 for that kid.
- R-DATA-4 History visibility is a per-kid cell; off for a kid means the panel shows none and R-DATA-3 says so.
- R-DATA-5 A `PRIVACY.md` in this repo states all of the above in plain words.

### R-TRUST Trust and undo

- R-TRUST-1 A Snapper snapshot "before Kids Mode" precedes the first apply.
- R-TRUST-2 `omarchy-kids-check` runs at the end of the wizard, from the panel, and at every kid login (R-DESK-2). Each check names what it proves and what it cannot.
- R-TRUST-3 A required firmware-password step: the wizard prints a parent card; the check shows it red until the parent marks it done.
- R-TRUST-4 Remove Kids Mode reverses every lock, removes accounts and slots, keeps every kid's files (R-FND-6), and offers the snapshot.
- R-TRUST-5 A pacman hook (`/etc/pacman.d/hooks/omarchy-kids.hook`) and an Omarchy post-update hook re-run `omarchy-kids-assert`, which restores every lock idempotently.

### R-BUILD Build and packaging

- R-BUILD-1 Bash + gum for the wizard and panel; QML for the exit overlay and the SDDM theme; nothing else.
- R-BUILD-2 One Arch package `omarchy-kids` from this repo's PKGBUILD; AUR when stable.
- R-BUILD-3 Tests: shell tests for every command (bats or Omarchy's `test/shell.d` style); a VM acceptance run on the stock ISO with an unattended `cidata` profile.
- R-BUILD-4 Commands: `omarchy-kids` (app entry), `-provision`, `-session`, `-check`, `-assert`, `-conf`, `-web`, `-time`, `-apps`, `-ask`, `-wifi`, `-remove`. `time`, `dns` (web), `apps` are also installed as `omarchy-parent-<feature>` symlinks unless upstream ships a file of that name.
- R-BUILD-5 Settings use the installer path's key=value format and helpers so pieces can move upstream.

## 5. Architecture

### 5.1 File layout

| Path | Owner | What |
| --- | --- | --- |
| `/usr/bin/omarchy-kids-*` | package | commands (R-BUILD-4) |
| `/usr/share/omarchy-kids/{bands.toml,packs/,hyprland/,tui/,sddm-theme/,policy/}` | package | data: bands, packs, level configs, screens, theme, policy templates |
| `/usr/share/wayland-sessions/omarchy-kids.desktop` | package | the kid session entry |
| `/usr/share/applications/omarchy-kids.desktop` | package | the app in the drawer |
| `/etc/omarchy-kids/kids/<name>.conf` | root, 0644 | per-kid overrides (band, level, web, time, wifi, history, allowlist, avatar) |
| `/etc/omarchy-kids/machine.conf` | root, 0644 | machine-level state: firmware-step done, snapshot id |
| `/etc/chromium/policies/managed/omarchy-kids-<band>.json` | root:omarchy-kids-<band>, 0640 | kids policy (R-WEB-1) |
| `/etc/sudoers.d/omarchy-kids-<name>`, `/etc/polkit-1/rules.d/4x-omarchy-kids*.rules` | root | posture and denies |
| `/etc/pacman.d/hooks/omarchy-kids.hook` | root | re-assert (R-TRUST-5) |
| `/var/lib/omarchy-kids/<name>/{usage/,launches.log}` | root, group kid 0750 | usage state |
| `/var/lib/omarchy-kids/queue/` | root | ask-a-parent records |

Groups: `omarchy-kids` (all kids), `omarchy-kids-<band>` (policy readers), `omarchy-parents` (owner; used by the parents-only fence).

### 5.2 Flows

**First run.** Drawer → floating terminal → Easy/Advanced → band → chunks → name/avatar/password → summary → apply: snapshot, machine setup, provision kid, policy file, LUKS slot, start installs → check → done. Portal shows the new tile at next logout.

**Kid login.** SDDM tile + password → `omarchy-kids-session` → R-DESK-2 checks → Hyprland `--config` → launcher. Time accounting starts on `Active=yes`.

**Pause.** Super×3 → password → Pause → hyprlock in kid session → `SwitchToGreeter` → parent logs in. Parent session locks on its own switch-away (R-EXIT-5). Kid returns via their tile → their existing session's lock screen.

**Finish.** Super×3 → password → Finish → `loginctl terminate-session` after SIGTERM to the session scope → greeter.

**Ask.** Kid action → modal → parent password on the spot, or queue → panel approve → action.

**Update.** `omarchy update` / pacman transaction → hook → `omarchy-kids-assert` → every lock restored; kid login re-checks anyway.

**Remove.** Panel → confirm with parent password → move homes → remove accounts, slots, groups, drop-ins, policy, session pin, theme → unmask consoles → offer snapshot.

### 5.3 Security model

Deterrent for a curious child; the wall is `sudo` plus the firmware password. Kid processes run as their own uid, so the parent's data is kernel-isolated. Known non-walls, stated in the UI: a Level 3 kid with a shell can run installed binaries not fenced by R-APPS-6; a kid who knows a LUKS passphrase and can boot USB (no firmware password) owns the disk; non-browser apps use machine DNS.

## 6. Contracts

### 6.1 Hand-off to Phase 2

The profile file carries `band`, `level`, `avatar`, `name`, `onboarded=false`. Phase 2's kid wizard runs when `onboarded=false` at the start of the kid session and flips it. Level progression in Phase 2 writes `level` through `omarchy-kids-conf` only.

### 6.2 Convergence with the installer path

Feature commands are drop-ins for the upstream `omarchy-parent` dispatcher. Per-kid posture is the upstream `apply --user` step, vendored until upstream ships it. Settings helpers are the upstream `install/helpers/parent.sh` functions, vendored the same way.

## 7. Phase 1 verification (blocking the build order)

| # | Check | Pass |
| --- | --- | --- |
| V1 | Two live Hyprland sessions (parent + paused kid) under SDDM on 4.0.x; switching via `SwitchToGreeter`; both survive `omarchy update` | Both sessions resume; no VT lands on an unlocked session |
| V2 | 0640 root:group policy file | `chrome://policy` empty as parent, full as kid; syslog warning only |
| V3 | Strict DoH behind a captive portal | Portal reachable only via the helper window; strict restored after |
| V4 | LUKS slots | add/change/remove per kid; boot with kid password; 3 kids |
| V5 | PAM helper with `seteuid` | kid password → kid; parent password → same account; wrong → denied; on both lock and SDDM stacks |
| V6 | CORE.md's five: SDDM second user across updates; Limine editor `init=/bin/bash`; tmpfs exec; snapshot rollback from the boot menu; Flatpak override (dropped: no Flatpak) | recorded either way |

## 8. Acceptance for v1 done

1. On a fresh stock Omarchy 4.0.x VM, install the package, run the wizard for two kids (3-5 no-password, 9-12 with password) in under ten minutes without a terminal.
2. Portal shows three tiles; each kid password (or Enter) opens the right desktop at the right level; parent password opens any.
3. Super×3 Pause and Finish both work; the parent's desktop, browser, and DNS are unchanged before, during, and after (I-1 test: `chrome://policy` empty, `resolvectl status` unchanged).
4. Kid browser: walled garden holds; family DoH active; history cannot be cleared.
5. Screen time: budget reached → warnings → lock → ask → parent grants → continues.
6. Ask for an app → queue → approve in panel → installed and visible.
7. `omarchy update` then every check green; delete a lock by hand, kid login refuses to start.
8. Remove Kids Mode → files preserved, portal back to one tile, all checks report "not installed".
9. All of the above with no pointer.

## 9. Decided against, on the record

- Site history hidden from parents (report 07 recommends it for pre-teens): chosen otherwise; per-kid cell.
- Firefox as the kids browser: not needed once the group-readable policy file works.
- Session hook swapping the policy: violates I-1 while paused.
- timekpr-next, malcontent, Flatpak: see hub PATH-SANDBOX.md.
