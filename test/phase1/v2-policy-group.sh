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
printf '{ "IncognitoModeAvailability": 1, "ForceGoogleSafeSearch": true, "HomepageLocation": "https://kids.example.test/v2-marker" }\n' | sudo tee "$POL" >/dev/null
sudo chown root:omarchy-kids "$POL"; sudo chmod 0640 "$POL"
say "file: $(ls -l "$POL" | awk '{print $1, $3, $4}')"
say "parent (not in group) can read: $(test -r "$POL" && echo YES || echo no)"
say "kid-test can read: $(sudo -u kid-test test -r "$POL" && echo yes || echo NO)"
dump(){ # $1 = user, $2 = data dir
  if [[ $1 == "$USER" ]]; then timeout 90 chromium $CHROME_ARGS --user-data-dir="$2" --dump-dom chrome://policy/ 2>/dev/null
  else sudo -u "$1" bash -c "cd /tmp && timeout 90 chromium $CHROME_ARGS --user-data-dir=$2 --dump-dom chrome://policy/ 2>/dev/null"; fi
}
p=$(dump "$USER" /tmp/v2-parent | grep -oE "v2-marker|IncognitoModeAvailability|ForceGoogleSafeSearch" | sort -u | tr '\n' ' ')
k=$(dump kid-test /tmp/v2-kid | grep -oE "v2-marker|IncognitoModeAvailability|ForceGoogleSafeSearch" | sort -u | tr '\n' ' ')
say "parent sees: [${p}] (expect empty)"
say "kid sees:    [${k}] (expect ForceGoogleSafeSearch IncognitoModeAvailability v2-marker)"
say "parent log:  $(timeout 90 chromium $CHROME_ARGS --user-data-dir=/tmp/v2-parent2 --enable-logging=stderr --dump-dom about:blank 2>&1 >/dev/null | grep -i "v2test" | head -1)"
sudo rm -rf /tmp/v2-parent /tmp/v2-parent2 /tmp/v2-kid
sudo rm -f "$POL"
if [[ -z "$p" && "$k" == *v2-marker* && "$k" == *Incognito* ]]; then say "V2 RESULT: PASS"; else say "V2 RESULT: FAIL"; exit 1; fi
