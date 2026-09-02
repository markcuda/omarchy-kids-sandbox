#!/bin/bash
# V2: a Chromium policy file readable only by a group is applied for group members and skipped
# for everyone else. Run on a real Omarchy install with password-free sudo. Creates a test user
# `kid-test` (member of omarchy-kids) and a marker policy; removes the policy file at the end.
set -uo pipefail
POL=/etc/chromium/policies/managed/omarchy-kids-v2test.json
CHROME_ARGS="--headless=new --no-sandbox --disable-gpu --disable-dev-shm-usage"
say(){ printf '%s\n' "$*"; }
say "chromium: $(chromium --version 2>/dev/null)"
sudo groupadd -f omarchy-kids
id kid-test >/dev/null 2>&1 || sudo useradd -m -G omarchy-kids -s /bin/bash kid-test
sudo install -d -m 755 /etc/chromium/policies/managed
printf '{ "IncognitoModeAvailability": 1, "ForceGoogleSafeSearch": true, "URLBlocklist": ["*"], "URLAllowlist": ["chrome://*"] }\n' | sudo tee "$POL" >/dev/null
sudo chown root:omarchy-kids "$POL"; sudo chmod 0640 "$POL"
say "file: $(ls -l "$POL" | awk '{print $1, $3, $4}')"
say "parent (not in group) can read: $(test -r "$POL" && echo YES || echo no)"
say "kid-test can read: $(sudo -u kid-test test -r "$POL" && echo yes || echo NO)"
probe(){ # $1 = user, $2 = data dir. Loads a refused local URL: blocked-by-policy vs plain refusal.
  local cmd="cd /tmp && timeout 90 chromium $CHROME_ARGS --user-data-dir=$2 --enable-logging=stderr --vmodule=config_dir_policy_loader=1 --dump-dom http://127.0.0.1:9/ 2>$2.log"
  if [[ $1 == "$USER" ]]; then bash -c "$cmd"; else sudo -u "$1" bash -c "$cmd"; fi
}
p=$(probe "$USER" /tmp/v2-parent | grep -oE "ERR_BLOCKED_BY_ADMINISTRATOR|ERR_CONNECTION_REFUSED" | sort -u | tr '\n' ' ')
k=$(probe kid-test /tmp/v2-kid | grep -oE "ERR_BLOCKED_BY_ADMINISTRATOR|ERR_CONNECTION_REFUSED" | sort -u | tr '\n' ' ')
say "parent page: [${p}] (expect ERR_CONNECTION_REFUSED: no policy applied)"
say "kid page:    [${k}] (expect ERR_BLOCKED_BY_ADMINISTRATOR: policy applied)"
say "parent log:  $(grep -io "failed to read configuration file[^:]*: [^\n]*" /tmp/v2-parent.log | head -1)"
say "kid log:     $(grep -io "found mandatory policy file[^\n]*v2test[^\n]*\|Failed to read[^\n]*v2test[^\n]*" /tmp/v2-kid.log | head -1)"
sudo rm -f /tmp/v2-parent.log /tmp/v2-kid.log
sudo rm -rf /tmp/v2-parent /tmp/v2-kid
sudo rm -f "$POL"
if [[ "$p" == *CONNECTION_REFUSED* && "$p" != *BLOCKED* && "$k" == *BLOCKED_BY_ADMINISTRATOR* ]]; then say "V2 RESULT: PASS"; else say "V2 RESULT: FAIL"; exit 1; fi
