# Omarchy Kids community scan — what's worth folding in

Source: full read of Omacom Discord #omarchy-kids (9/1/26 8:49 AM creation through 9/3/26
present) plus its "Omarchy-kids Design" thread, via logged-in browser (the southbridge-fur
scraper is dead — see `scraper/VERDICT.md`). 10 of 11 identified community repos were cloned and
read by an independent senior-engineer pass (Codex, read-only, no changes made); one
(`elynch303/ai-dns-parental-control`) 404s — likely announced but never pushed, or private.
Full channel transcript: `channel.md` / `channel.jsonl`. Full repo list with context: `repos.md`.
Per-repo reports: `reports/*.md`.

## The channel in five lines

1. Harris Kenny opened the channel morning of 9/1 recruiting off an X post; has moderated/pinned
   since, repeatedly deferring to DHH as maintainer.
2. DHH personally set the founding architecture at 10:41-10:54 AM day one (kid+adult password
   pair, adult becomes sudo, `omarchy-parent` control binary, DNS allowlist, mascot-led
   onboarding, "build against omarchy/omarchy and omarchy/omarchy-iso") then said "I'll leave you
   all to it" and has not posted since — explicitly not wanting "a panopticon for teenagers."
3. Pete (OMA, verified) is the most active builder, iterating live on a fork of the real omarchy
   repo itself (`peterholko/omarchy`) — this is the closest thing to an official reference
   implementation of DHH's installer-path spec that exists today.
4. Ty (father of 8) is the most prolific *shipper*: `omarchy-clarity` (18 stars, in daily use),
   `omarchy-omaski` (a working game), and collaborating on a mascot prototype.
5. ~40+ other contributors are each independently building narrow slices (DNS filtering,
   phone-approval flows, boot themes, typing games, AI content classification) with essentially
   no cross-coordination — which is the gap this scan is meant to close.

## Repo table

| Repo | Author (channel) | What it is | Licence | Verdict |
|---|---|---|---|---|
| jfuerwentsches/omarchy-kids | Nesh (posted) | Single-child-tier config layer: Quickshell launcher, Rust usage-tracking agent, C++/Qt6 remote parent Control Center, cross-machine pairing | MIT | Different shape (remote multi-computer mgmt), not a security boundary — child owns its own enforcement daemon. Adopt the launcher UX and remote-pairing crypto pattern, skip the trust model. |
| peterholko/omarchy (fork, `build/kids-all`) | Pete | The installer-path spec (DHH's design) actually implemented against the real omarchy tree: profile selection at install, `omarchy-parent` binary, root-owned screen-time, DNS/Chromium policy, LUKS slots, pacman-hook-safe app restriction | MIT | **Most important read.** Closest thing to canonical. One-account model (kid+adult share a Unix account) — architecturally different from our per-kid-account design, but the privileged-helper patterns are directly reusable. |
| TyRichards/omarchy-clarity | Ty | Password-gated `/etc/hosts` distraction/adult-site blocker, scrypt-protected, weekly-refreshed blocklist, systemd reconciliation | MIT | Single-user focus tool, not Kids Mode — but the root-helper pattern (`lib/clarity-root`) and its isolated Python test harness are worth stealing wholesale for our own root-owned ledger helper. |
| TyRichards/omarchy-omaski | Ty | PICO-8-style SkiFree game as an Omarchy Quickshell bar plugin, with a built-in sprite editor | MIT | Not Kids-Mode-relevant itself, but the plugin-surface pattern (manifest + bar widget + IPC + physical-pixel-safe QML canvas) is a clean template for our app-pack games. |
| aphexddb/omarchy-pisafe | Bart S. (posted) | Go DNS daemon: profiles, stale-cache fallback, resolver failover, Tailscale/Docker-aware filtering, deliberately stays out of `/usr/share/omarchy/` to avoid fighting `omarchy-dns` | MIT | Best-of-breed DNS layer among everything found. World-writable control socket and a too-broad sudoers rule to avoid, but the systemd hardening and atomic gravity-swap are worth adopting directly. |
| aphexddb/omarchy-parentapproval | (referenced day 2) | Go daemon + PWA: cryptographically signed, single-use, TTL'd approval requests from a parent's phone, sealed against the relay, PAM/polkit/sudo integrated, Quickshell layer-shell overlay | MIT | **Highest-value single find.** Directly comparable to (and materially more secure than) a naive ask-a-parent queue. Protocol/signing code is portable; several real auth bugs to fix before reuse (unbound socket ops, unauthenticated push registration). |
| Deoxizn/omarchy-kids-edition-plymouth | Deoxizn/Tomis (posted) | Plymouth (boot splash) theme pack for a "kids edition," password-entry animation | **None** — no LICENSE file | Cosmetic only, small scope, 3x duplicated 235-line scripts. Treat as unlicensed until author clarifies; don't copy code/art without permission. |
| elynch303/ai-dns-parental-control | Erogn (posted) | Announced as AdGuard-over-Pi-hole DNS blocking with AI transcription analysis of YouTube content ("not finished yet") | Unknown | **404 — not publicly readable.** Could not verify claims; revisit later if it's pushed. |
| HxHippy/omarchy-kids-setup | HxHippy (posted) | Bash onboarding wizard skeleton (age band, preset, budget, bedtime, PIN), dry-run by default, Phase-1 host-fact verifier, physical-laptop test runbook | MIT | Explicitly a skeleton, and has real bugs (new account gets no password so can't log in; PIN interpolated into `bash -c` — command-injection risk). Adopt the dry-run/`--apply` pattern and Phase-1 fact-collector idea; do not adopt the apply code as-is. |
| tsouth89/typearchy | Pete (posted) | Local-first typing-practice game/app pack with deterministic content generation, optional cloud score-sharing (Cloudflare Workers + D1) | MIT | No enforcement value, but strong app-pack template: manifest/bar-widget registration, keyboard-exclusive Quickshell overlay, atomic local-state writes with corruption quarantine, parity-tested content generator. |
| OldJobobo/omascot | Ty (posted) | Prototype animated desktop-companion mascot ("Omy"): 932-PNG sprite library, app-context-aware reactions, per-monitor Wayland overlay, live-reloaded config | MIT (code); art provenance unverified | Presentation-only, explicitly a prototype, no tests. Directly reusable as our mascot/companion layer — animation pipeline, context-reaction mapping, and overlay placement logic are all solid — but treat as a UI skin, not a security surface, and confirm art rights before shipping any of the actual sprite assets. |

Not sent to Codex (official/upstream, not third-party): `omarchy/omarchy` PR #9750 (sudo
parent-vs-kid password, against the real DHH-owned repo — worth tracking as the signal for
where upstream lands) and `omacom/aether` (the canonical theming tool, referenced constantly as
the on-ramp for anyone building a Kids theme).

## Worth folding in (ordered)

1. **Adopt the ask-a-parent protocol design from `aphexddb/omarchy-parentapproval`.**
   Signed, single-use, TTL'd requests (`internal/protocol/protocol.go`), with command details
   sealed from the relay (`internal/protocol/box.go`), are a materially stronger design than a
   plain request-queue file. Where it lands: our ask-a-parent request queue component. Fix the
   two real bugs before reuse — unbound-by-peer-UID socket operations
   (`internal/daemon/daemon.go:233-240`) and unauthenticated push registration
   (`internal/relay/relay.go:836-868`). Effort: medium (borrow the protocol/crypto layer, skip
   the phone-relay infrastructure unless we want cross-device approval too).

2. **Adopt the root-helper + isolated-test pattern from `TyRichards/omarchy-clarity`
   (`lib/clarity-root`) and `aphexddb/omarchy-pisafe` (`internal/hostdns`, `packaging/pisafe.service`).**
   Both show a privileged helper that writes managed, marked, atomically-swapped policy files
   with narrow systemd hardening (`CAP_NET_BIND_SERVICE`, restricted write paths). Where it
   lands: our root-owned screen-time ledger and DNS/Chromium policy writers. Effort: small — this
   is mostly "copy the shape," not the code.

3. **Study `peterholko/omarchy`'s installer-path implementation before our next architecture
   review.** It's the most literal implementation of DHH's own founding spec that exists, and it
   diverges from our design on one Unix account (kid+adult share it) vs. our per-kid-account +
   per-kid-LUKS-slot model. We should either explicitly document why we diverge (multi-kid
   support, cleaner LUKS story) or reconsider adopting the one-account-per-machine simplicity for
   the sandbox's parent-setup-first flow. Effort: a design discussion, not code.

4. **Borrow the DNS daemon shape from `aphexddb/omarchy-pisafe`** — profiles, stale-cache
   fallback so a bad network day doesn't unblock everything, resolver failover, and explicit
   avoidance of the official `omarchy-dns` command surface. Where it lands: walled-garden DNS
   layer. Avoid its world-writable control socket and overly broad sudoers rule. Effort: medium.

5. **Adopt the mascot/companion architecture from `OldJobobo/omascot`** for our SDDM face-tile
   portal and parent wizard's "Omy" character — the app-context reaction mapping
   (`Overlay.qml:436-485`), non-covering window placement, and PNG-sprite animation pipeline
   (`AnimationCatalog.js` + `scripts/generate-companion-animations.py`) are all more developed
   than anything we've built. Confirm art-asset provenance/licence with the author before
   shipping the actual sprites; the code pattern is MIT and clean to reuse regardless.
   Effort: medium.

6. **Use the app-pack plugin template from `TyRichards/omarchy-omaski` and `tsouth89/typearchy`**
   for our own packs: manifest.json + BarWidget.qml + IPC target, physical-pixel-safe QML canvas
   scaling, atomic local-state writes with a corruption-quarantine fallback. Effort: small,
   reusable as boilerplate for every future pack.

7. **Adopt the dry-run-by-default + Phase-1 fact-collector pattern from
   `HxHippy/omarchy-kids-setup`** for our own onboarding wizard and VM test harness — good UX
   idea, badly executed here (do not copy the apply code: it creates a passwordless account and
   has a command-injection path via an unsanitized PIN in a root `bash -c`). Effort: small idea,
   skip the implementation.

## Already ours or better

- Our per-kid Unix account + per-kid LUKS slot model is more thorough than every community repo
  found — most (jfuerwentsches, HxHippy, peterholko's installer path) run one shared account or a
  single child tier.
- Our SDDM face-tile portal has no community equivalent; every repo either uses the stock SDDM
  screen or has no login surface at all.
- Our live QEMU VM test harness is more complete than anything found except peterholko's fork,
  which depends on an external `omarchy-iso-test` harness rather than shipping its own.
- Our walled-garden Chromium policy is comparable in ambition to peterholko's `omarchy-parent-dns`
  + Chromium/Firefox policy work, but nothing else in the community set attempts browser-level
  policy at all — most stop at DNS.

## Avoid

- Do not copy `HxHippy/omarchy-kids-setup`'s apply path verbatim — passwordless account creation
  and PIN command-injection are real, exploitable bugs, not style nits.
- Do not treat DNS-only blocking (`omarchy-pisafe`, `omarchy-clarity`'s `/etc/hosts` approach) as
  sufficient on its own — both repos' own docs admit VPNs/proxies/direct-IP bypass it; it's a
  layer, not the whole fence.
- Do not adopt `jfuerwentsches/omarchy-kids`' trust model where the enforcement daemon runs
  inside the child's own account — a child process can alter its own budgets and unlock list.
- Do not ship `Deoxizn/omarchy-kids-edition-plymouth`'s code or art without a licence — the repo
  has none, only a README claim of being "based on" Omarchy's theme.
- Do not build browsing-history collection into our design by default the way peterholko's
  `omarchy-parent-browsing` does, if "nothing about a child leaves the machine" remains our
  privacy stance.

## Three recommended tickets

1. **Ask-a-parent: adopt signed/TTL'd request protocol** — port the request-signing and sealing
   design from `aphexddb/omarchy-parentapproval`'s `internal/protocol/` into our ask-a-parent
   queue, fixing its peer-UID-binding and push-auth gaps along the way; skip the phone-relay
   infra for v1, keep the design open to add it later.
2. **Root-ledger helper: adopt the marked-atomic-write + systemd-hardening pattern** from
   `omarchy-clarity`'s `lib/clarity-root` and `omarchy-pisafe`'s `packaging/pisafe.service` for
   our screen-time ledger and DNS/Chromium policy writers, with an isolated filesystem test suite
   modeled on `tests/test_clarity_root.py`.
3. **Architecture note: document our divergence from the installer-path one-account model** —
   write a short ADR comparing our per-kid-account + per-kid-LUKS design against
   `peterholko/omarchy`'s one-shared-account installer path (DHH's own spec), so the tradeoff is
   deliberate and defensible rather than implicit.
