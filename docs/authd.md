# The parent-password verifier (R-SEC-1, R-SEC-2)

`omarchy-kids-authd` is the one place in Kids Mode that knows how to check the parent's password.
Every screen that asks "is a parent here?" — the exit modal, the ask modal, the lock-screen line,
the portal line, panel confirmations, the bar-widget actions — goes through it instead of
re-implementing password checking itself. I-8: Kids Mode never asks for anything but the parent's
own login password, and never stores it.

## Pieces

- `bin/omarchy-kids-authd` — a root, socket-activated Python daemon. Reads the parent's shadow
  hash fresh on every request (never cached) and answers a one-word yes/no.
- `bin/omarchy-kids-parent-auth` — a small bash client for `pam_exec`. Reads a candidate password
  from stdin, asks the daemon, and turns the answer into an exit code.
- `systemd/omarchy-kids-authd.socket` / `.service` — the socket unit owns
  `/run/omarchy-kids/auth.sock` (mode `0666`, directory `0755`) and starts the daemon on first
  connection.

## Wire protocol

A client connects to the Unix socket, writes exactly one line — the candidate password,
newline-terminated, at most 512 bytes — and reads the reply:

```
client -> "hunter2\n"
server -> "ok\n"    # or "no\n"
server closes the connection
```

Anything that doesn't fit that shape (no newline, over 512 bytes, a client that goes quiet for
more than 5 seconds) gets `no`. The daemon serves one client at a time; there's no reason for it
to do otherwise; and it never writes the candidate anywhere — not to a log, not to disk, not into
an exception message.

## Where the parent's identity and hash come from

- The parent's login name comes from `/etc/omarchy-kids/machine.conf` (a `key=value` file, key
  `parent`), overridable with `--parent NAME` or the `OMARCHY_KIDS_PARENT` environment variable
  (checked in that order: flag, then env, then the config file).
- The hash comes from `/etc/shadow` (path overridable with `--shadow PATH`, which is how the
  tests run without touching the real file), read again on every single request. A locked account
  (a hash starting with `!` or `*`) never matches.
- Comparison is `crypt(3)` via libxcrypt, loaded through `ctypes.CDLL("libcrypt.so.1")` rather
  than Python's `crypt` module, which is gone as of Python 3.13. This also means the daemon
  understands whatever `crypt(3)` on the box understands — yescrypt included — for free. The
  daemon's own result is compared against the stored hash with `hmac.compare_digest`, so a
  mismatch doesn't leak timing information about where the strings diverge.

## Rate limiting

The limiter is in memory, process-wide, and resets on restart:

- 3 wrong answers in a row → refuse (`no`) for 30 seconds, no matter what's sent.
- 10 wrong answers in a row → refuse for 300 seconds.
- A correct answer resets the counter to zero.

While locked out, the daemon does not even look at the candidate — it can't leak a correct
password's worth of timing or oracle behavior during the lockout window, and a truly correct
guess made during a lockout still comes back `no`.

## Threat notes

- **Any local user can talk to the oracle.** The socket is `0666` by design (kid sessions, the
  portal, and the parent's own session all need to reach it, and none of them run as the parent).
  That makes this daemon a password oracle available to anyone on the box, including the kid
  account it exists to keep locked down. The rate limit above is the whole defense against
  brute-forcing it, not a nice-to-have: at worst an attacker gets 3 fast guesses before a 30s
  wait, and 10 before a 5-minute one.
- **The modal is a second line of defense, not the first.** Whatever UI calls into this daemon
  (the exit modal, the portal, etc.) should apply its own pacing/backoff on top of this, per
  I-6 ("honest UI") — don't let a kid brute-force the *daemon's* limit once per boot from every
  surface that calls it.
- **This is not `faillock`.** R-SEC-1 is explicit: the verifier never touches the system's
  faillock state for the parent's login. A string of wrong guesses through Kids Mode cannot lock
  the parent out of their own console login, and console lockouts don't affect this daemon.
- **The daemon fails closed.** No parent configured, no matching shadow entry, an unreadable
  shadow file, a locked/disabled account, libxcrypt missing — every one of those answers `no`
  rather than crashing or falling through to "allowed."

## How PAM uses it

`pam_exec.so` with `expose_authtok` puts the just-typed password on the client's stdin; the
client asks the daemon and turns the reply into an exit code the PAM stack understands:

```
auth [success=1 default=ignore] pam_exec.so quiet expose_authtok /usr/bin/omarchy-kids-parent-auth
```

`success=1` skips the next line (normally a `pam_deny` or similar) when the verifier says yes;
`default=ignore` means every other outcome falls through to whatever comes after, unchanged. This
line is written once and used everywhere R-SEC-2 lists — the exit modal, the ask modal, the
lock-screen line, the portal line, panel confirmations, the bar-widget actions — because
verification always happens in the daemon, never in the caller, whether that caller is running as
root or as the kid.

The client also refuses immediately, without contacting the daemon, if `PAM_TYPE` is set and
isn't `auth` — `pam_exec` invokes the same line for `account`/`session`/`password` stack entries
too, and this isn't valid outside of `auth`.

## Testing

`test/shell.d/authd-test.sh` starts the daemon on a temp socket with a fixed, known sha512-crypt
hash (`$6$saltsalt$...`, for the password `secret123`) and a `--shadow`/`--parent` pointed at
test fixtures — no real `/etc/shadow` or `/etc/omarchy-kids/machine.conf` involved. It needs a
loadable `libcrypt.so.1` to actually run the daemon, which macOS doesn't have; on a host without
it, the test prints `SKIP` and exits 0 rather than failing. Run it directly with:

```
bash test/shell.d/authd-test.sh
```

or as part of the full suite with `test/all`.
