#!/bin/bash
# V6 (tmpfs item): which world-writable tmpfs mounts allow exec? A kid with a shell could run a
# downloaded binary from any of them even with a noexec home.
set -uo pipefail
for d in /tmp /dev/shm /run/user/$(id -u) /var/tmp; do
  [[ -d $d ]] || { echo "$d: absent"; continue; }
  opts=$(findmnt -no OPTIONS --target "$d")
  f="$d/.v6-exec-test.$$"; printf '#!/bin/sh\necho ran\n' > "$f" 2>/dev/null && chmod +x "$f" 2>/dev/null
  if [[ -x $f ]] && out=$("$f" 2>/dev/null) && [[ $out == ran ]]; then r="EXEC ALLOWED"; else r="exec blocked"; fi
  rm -f "$f"; echo "$d: $r  [$(findmnt -no FSTYPE --target "$d"), opts: $opts]"
done
