# Wi-Fi: `omarchy-kids-wifi`, `omarchy-kids-wifid`, and the picker (SPEC.md R-WIFI-1..4; issue #26)

Kids can join new Wi-Fi (the school's network, a café) without ever touching NetworkManager
directly, and without the network they join being able to weaken the DoH filtering already forced
into their Chromium policy (R-WEB-6/I-1).

## Why a daemon at all

Kid accounts are polkit-denied, no prompt, from `org.freedesktop.NetworkManager.settings.modify`
(`lib/posture.sh`'s `41-omarchy-kids-deny.rules`, R-FND-4) — the action every plain `nmcli
device wifi connect` needs to save a connection profile. `bin/omarchy-kids-wifid` is the one
root, socket-activated process that may call `nmcli` on a kid's behalf, the same shape as
`bin/omarchy-kids-authd` (docs/authd.md): one request per connection, stdlib-only Python,
socket-activated via `systemd/omarchy-kids-wifid.{socket,service}`.

Unlike authd, this daemon isn't a password oracle — it identifies its caller by the kernel's own
idea of who is on the other end of the socket (`SO_PEERCRED`, never anything the client claims),
maps that uid to an account, and refuses outright unless that account's `wifi` profile key
(`bin/omarchy-kids-conf`, Appendix B) resolves to `helper`. `parent`-mode kids get nothing from
this daemon at all — R-WIFI-1's other value.

## Pieces

- `bin/omarchy-kids-wifid` — the root daemon. Reads the caller's uid via `SO_PEERCRED`, shells out
  to `omarchy-kids-conf get <account> wifi` to resolve the profile, and only then runs `nmcli` —
  always with a fixed, hardcoded argument list (`subprocess.run([...])`, never `shell=True`, never
  string interpolation into a command line), so nothing a client sends over the socket can smuggle
  in an extra flag.
- `bin/omarchy-kids-wifi` — the kid-side (and, for `portal`, band-side) command: `list`, `join`,
  `status`, `forget`, `portal`, `picker`. Talks to the daemon over the socket; never calls `nmcli`
  itself.
- `share/wifi/shell.qml` — the kid-facing Quickshell picker (`omarchy-kids-wifi picker`).
- `share/hyprland/L1.lua` / `L2.lua` / `L3.lua` — bind `Super+Shift+W` to `omarchy-kids-wifi
  picker` at every level (Appendix E). The bind itself is unconditional (these files are static
  and provisioned once, R-DESK-1); `picker` is what actually refuses for a `parent`-mode kid.
- `systemd/omarchy-kids-wifid.socket` / `.service` — same shape as `omarchy-kids-authd`'s units.

## Wire protocol

A client connects to `/run/omarchy-kids/wifi.sock`, writes its request, shuts down its write side
(or just closes), and reads the reply:

```
LIST\n                          -> "OK\n" + nmcli's own terse output, or "REFUSED ...\n"/"ERROR ...\n"
STATUS\n                        -> "OK\n" + nmcli's own terse output
JOIN <ssid>\n<password>\n       -> "OK\njoined kids-<ssid>\n", or an ERROR line
FORGET <ssid>\n                 -> "OK\nforgot kids-<ssid>\n", or an ERROR line
```

`<password>` may be empty (an open network); the header line is required, the password line is
not. The daemon serves one request per connection — same reasoning as authd: there's no need for
more, and it keeps every request's authorization decision (the `SO_PEERCRED` check) tied 1:1 to
one accepted connection.

Every reply starts with one of three words:

- `OK` — the payload (if any) follows on subsequent lines.
- `REFUSED <reason>` — the peer's account isn't `wifi=helper` (or has no resolvable profile at
  all). `bin/omarchy-kids-wifi` turns this into exit code 3.
- `ERROR <reason>` — the request was allowed, but `nmcli` (or the request itself) failed — a bad
  SSID, a wrong password, a network that's out of range by the time `join` runs, etc. Exit code 1.

## What `join` actually does

1. `nmcli device wifi connect <ssid> [password <password>] name kids-<ssid>` — always targets
   (creates, if needed) a connection named `kids-<ssid>`, **never** a bare-named `<ssid>`
   connection, even if one already exists for that network. That existing connection wasn't
   created by this daemon, so it's never touched (R-WIFI-2's "never touch connections it did not
   create") — the cost is that a network can end up with two connection profiles (the parent's own
   bare-named one, and the kid's `kids-`-prefixed one), which is the trade-off, not a bug.
2. `nmcli connection modify kids-<ssid> ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
   ipv4.dns "" ipv6.dns "" connection.zone kids` — forces the network's own DNS to be ignored and
   clears any DNS servers already recorded on the connection (R-WIFI-2). This is the whole point:
   without it, a captive network or a school's resolver could quietly hand out its own DNS and
   short-circuit the DoH filtering forced into the kid's Chromium policy (R-WEB-2, R-WEB-6).
   `connection.zone kids` additionally tags the connection so a future pass can recognize every
   connection this daemon owns without relying on the name prefix alone.
3. `nmcli connection up kids-<ssid>` — reactivates so the DNS change takes on a connection that
   `device wifi connect` may have already brought up with the network's own DNS still attached.

`forget <ssid>` only ever runs `nmcli connection delete kids-<ssid>` — by construction, it can
never reach a connection this daemon didn't create.

## The per-kid `wifi` key (Appendix B)

| Value | Meaning |
| --- | --- |
| `parent` | Default for 3-5, 6-8. The kid cannot use `omarchy-kids-wifi` at all; every subcommand (and the picker) refuses. R-WIFI-4 says the kid-side join should instead open the ask modal — **not built here**, see "Known gap" below. |
| `helper` | Default for 9-12, 13+. `omarchy-kids-wifid` will act on this account's requests. |

Read/write it the normal way: `omarchy-kids-conf get <kid> wifi` / `omarchy-kids-conf set <kid>
wifi helper`.

## The picker (`omarchy-kids-wifi picker`, `share/wifi/shell.qml`)

Bound to `Super+Shift+W` at every level. `picker` checks the profile itself before ever launching
Quickshell: a `parent`-mode (or profile-less) kid gets a small toast (`share/time/toast.qml`,
reused from the screen-time warnings) saying Wi-Fi needs a grown-up, and the command exits without
opening anything (I-6: the bind existing is not the same claim as the bind doing anything). A
`helper`-mode kid gets the real picker: arrow keys through nearby networks (from `omarchy-kids-wifi
list`), Enter to join (a password field appears first if the network needs one), Esc to back out
of the password field or close the picker entirely.

Every action the picker takes still goes through `omarchy-kids-wifi` → `omarchy-kids-wifid`, which
re-checks `SO_PEERCRED` on every single connection — the picker's own check is a UX nicety, not the
real gate.

## The captive-portal window (`omarchy-kids-wifi portal`)

Some networks (a school's guest Wi-Fi, most cafés) intercept all traffic until you complete a
captive-portal page, which usually needs to load over plain `http://`, not `https://`. R-WIFI-3
asks for a helper window that opens one to a known page and briefly relaxes just enough filtering
to let it load.

`omarchy-kids-wifi portal [--apply]` opens `http://neverssl.com` (a site built exactly for this —
deliberately plain HTTP, so a captive portal's intercept actually fires) and, only for a `garden`
(walled-garden) band, temporarily adds `neverssl.com` to that band's Chromium
`URLAllowlist` (R-WEB-3) for ten minutes:

```
omarchy-kids-web install <band> --allow <tmp-file-with-just-neverssl.com> --apply
systemd-run --unit omarchy-kids-wifi-portal-restore-<band> --on-active=10min \
  --description "..." -- omarchy-kids-web install <band> --apply
```

The second command (no `--allow`) re-renders the band's normal policy ten minutes later,
restoring the strict allowlist. Like every other command that writes under `/etc`, this is
`DRY_RUN=1` by default (AGENTS.md rule 8) — pass `--apply` (or `DRY_RUN=0`) to actually write.

For a `filtered` band (13+), nothing is blocked by host in the first place (R-WEB-3: "filtered
open web adds neither" allowlist nor blocklist), so `portal` skips the allow/restore dance
entirely and just opens the browser. For a `none` band (3-5), there is no browser in the launcher
at all (R-WEB-3's "No browser" mode), so `portal` refuses outright — there is nothing to open
(I-6).

### Risk, read before wiring this into anything automatic

- **This widens the walled garden band-wide, not kid-wide or connection-wide.** Any kid on that
  same `garden` band can reach `neverssl.com` for the whole ten-minute window, not just the one
  who hit the captive portal.
- **The restore is scheduled, not confirmed.** `systemd-run --on-active=10min` fires ten minutes
  later regardless of whether anything is watching; if the machine suspends, powers off, or
  `systemd-run`/the system manager is unavailable before it fires, the temporary allow silently
  outlives its window until the next unrelated `omarchy-kids-web install` for that band (e.g. a
  parent changing any other web setting). Nothing here re-checks that the restore job actually
  ran.
- **The exposure is bounded to one fixed, non-secret hostname.** `neverssl.com` is hardcoded, never
  taken from anything the kid or the network supplies, so this cannot be used to smuggle an
  arbitrary host onto the allowlist.
- **No unprivileged path yet.** `omarchy-kids-web install --apply` writes root-owned files under
  `/etc/chromium/policies/managed/` and the restore's `systemd-run` job needs to talk to the
  system manager as root; `portal` has no polkit/pkexec wiring of its own to let an unprivileged
  kid session actually run either half for real (`omarchy-kids-wifid`, the one root path this
  issue adds, only ever runs `nmcli`, never `omarchy-kids-web`). Until a follow-up issue adds that
  path, `--apply` here is meant for a root context — the panel, or a future dedicated helper — not
  a kid's own session calling it directly. Treated the same way `omarchy-kids-exit --pause`
  documents its own not-yet-built mechanism, rather than quietly pretending it works.

## Known gap: R-WIFI-4 (`parent` mode → ask modal)

R-WIFI-4 says a `parent`-mode kid's join attempt should open the ask modal
(`bin/omarchy-kids-ask`, docs/ask.md). That modal's queue record (Appendix D) has a fixed `kind`
enum — `time | app | plugin | site` — that does not include `wifi`; adding a fifth kind (and
deciding what "approve" even means for a Wi-Fi request — join it *for* the kid? just flip their
`wifi` key to `helper`?) is a real design decision, not a plumbing one, and is out of scope for
this issue. Every `omarchy-kids-wifi` subcommand instead refuses a `parent`-mode kid honestly, with
a one-line reason (the picker: a toast; everything else: stderr and exit 3) — no control here
claims to open anything it doesn't (I-6).

## Testing

`test/shell.d/wifi-test.sh` covers, all offline and without a real NetworkManager or root:

- `bin/omarchy-kids-wifid`'s request parsing and `nmcli` argument-vector construction, tested by
  importing the file as a Python module (`importlib`) and calling its functions directly — the
  same reasoning `test/shell.d/authd-test.sh` gives for driving `omarchy-kids-authd` as a real
  process instead doesn't carry over cleanly here, since faking `SO_PEERCRED` across a real Unix
  socket from a test harness is far more machinery than importing the module and calling
  `cmd_join`/`cmd_forget`/`parse_request` with a fake `nmcli` stub on `$PATH`.
- `bin/omarchy-kids-wifi`'s `require_helper` refusal for `wifi=parent` (and for no profile at
  all), against a scratch `OMARCHY_KIDS_ETC`/`OMARCHY_KIDS_SHARE` tree, the same convention
  `test/shell.d/conf-test.sh` and `test/shell.d/web-test.sh` use.
- `omarchy-kids-wifi forget` only ever building a `kids-<ssid>` argument, never a bare SSID.
- `omarchy-kids-wifi portal`'s temporary-allow-file and `systemd-run` restore command, in
  `DRY_RUN=1` (the default) — printed, never executed, per AGENTS.md rule 8.

```
bash test/shell.d/wifi-test.sh
```

## What needs the VM (never run here — AGENTS.md rule 8)

- `bin/omarchy-kids-wifid` actually accepting a connection from a real kid uid and reading its
  `SO_PEERCRED` — this only runs on Linux at all (guarded in `main()`), and this repo was written
  without a Linux box with NetworkManager, systemd socket activation, or a kid account to test
  against.
- Every `share/wifi/shell.qml` claim: this has never run against a real Quickshell (see its own
  UNTESTED header) — `Process.stdout`/`SplitParser` reading a command's output back into QML is
  new to this repo (share/launcher/shell.qml and share/exit-modal/shell.qml only ever *start* a
  process or write to one's stdin).
- The `Super+Shift+W` bind actually reaching Hyprland and `omarchy-kids-wifi picker` actually
  showing/hiding the right thing.
- The whole `portal` flow end to end: a real captive portal intercepting `http://neverssl.com`,
  the temporary allow actually letting Chromium load it, and the `systemd-run` restore firing on
  schedule.
- `nmcli device wifi connect ... name kids-<ssid>` actually creating a *new* connection (not
  silently reusing/renaming an existing bare-named one) on a real NetworkManager, and
  `ipv4.ignore-auto-dns`/`ipv6.ignore-auto-dns` actually taking effect after `connection up`.
