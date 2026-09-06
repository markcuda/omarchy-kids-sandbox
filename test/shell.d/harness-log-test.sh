#!/bin/bash
# Execute the actual harness functions using only owned files and commands.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$DIR" <<'PY'
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])

def function(path, name):
    match = re.search(r'^' + name + r'\(\) \{\n.*?^\}', path.read_text(), re.M | re.S)
    assert match, name
    return match.group()

def executable(path, body):
    path.write_text('#!/bin/bash\nset -euo pipefail\n' + body + '\n')
    path.chmod(0o700)

with tempfile.TemporaryDirectory(prefix='kids-harness-log-') as directory:
    root = Path(directory)
    commands = root / 'bin'
    commands.mkdir()
    runtime = root / 'owner runtime'
    runtime.mkdir(mode=0o700)
    marker = root / 'ran'
    executable(commands / 'runuser', '''
[[ "$1" == -u && "$2" == kid-test && "$3" == -- ]]
shift 3
exec env OWNER_CONTEXT=yes "$@"
''')
    executable(commands / 'mktemp', '''
[[ ${OWNER_CONTEXT:-} == yes ]] || exit 71
[[ ${FAIL_ALLOCATE:-0} != 1 ]] || exit 72
exec /usr/bin/mktemp "$@"
''')
    executable(commands / 'setsid', 'exec "$@"')
    launch = function(repo / 'scripts/media-driver.sh', 'run_gui_command')
    launch = launch.replace(' runuser ', ' ' + str(commands / 'runuser') + ' ')
    payload = 'printf session-output; printf ran > ' + shlex.quote(str(marker))
    # This command boundary refuses unrecognized shell shapes before execution.
    # Tests never run arbitrary remote redirections, even against mutated source.
    guard = root / 'remote-command.py'
    guard.write_text(r"""import os, re, shlex, subprocess, sys
mode, command = sys.argv[1:3]
if mode == 'launch':
    argv = shlex.split(command)
    expected = ['env', '-i', 'PATH=/usr/bin:/bin', sys.argv[3], '-u', 'kid-test', '--', 'env',
                'XDG_RUNTIME_DIR=' + sys.argv[4], 'PATH=' + sys.argv[5] + ':/usr/bin:/bin',
                'FAIL_ALLOCATE=' + os.environ.get('FAIL_ALLOCATE', '0'), '/bin/bash', '-c']
    if argv[:-1] != expected:
        raise SystemExit(90)
    match = re.fullmatch(r'log=\$\(mktemp "\$XDG_RUNTIME_DIR/omarchy-kids-media[.]XXXXXX"\) \|\| exit 1; setsid /bin/bash -c (.+) >"\$log" 2>&1 </dev/null &', argv[-1])
    if not match or shlex.split(match[1]) != [sys.argv[6]]:
        raise SystemExit(91)
    raise SystemExit(subprocess.run(argv).returncode)
if mode == 'install':
    allowed = ['pacman -U --noconfirm /tmp/omarchy-kids-*.pkg.tar.zst && sync',
               'pacman -Qkk omarchy-kids']
    if command not in allowed:
        raise SystemExit(92)
    raise SystemExit(subprocess.run(['/bin/bash', '-c', command]).returncode)
raise SystemExit(93)
""")
    launch_guard = ' '.join(shlex.quote(str(value)) for value in
                           [sys.executable, guard, 'launch'])
    guard_args = ' '.join(shlex.quote(str(value)) for value in
                         [commands / 'runuser', runtime, commands, payload])
    for mode in ['launch', 'install']:
        result = subprocess.run([sys.executable, str(guard), mode, 'printf refused',
                                 str(commands / 'runuser'), str(runtime), str(commands), payload],
                                capture_output=True, timeout=10)
        assert result.returncode in (90, 92) and result.stdout == b''
    script = root / 'launch.sh'
    script.write_text('''#!/bin/bash
set -uo pipefail
shell_quote() { printf '%q' "$1"; }
vmroot() { ''' + launch_guard + ' "$1" ' + guard_args + '''; }
gui_session_env() {
  printf '%s\\n' ''' + ' '.join(shlex.quote(value) for value in [
        'XDG_RUNTIME_DIR=' + str(runtime),
        'PATH=' + str(commands) + ':/usr/bin:/bin',
    ]) + ''' "FAIL_ALLOCATE=${FAIL_ALLOCATE:-0}"
}
''' + launch + '\nrun_gui_command kid-test ' + shlex.quote(payload) + ' async\n')
    result = subprocess.run(['/bin/bash', str(script)], capture_output=True, timeout=10)
    assert result.returncode == 0, result.stderr
    for _ in range(100):
        if marker.exists():
            break
        import time
        time.sleep(0.01)
    assert marker.read_text() == 'ran'
    logs = list(runtime.glob('omarchy-kids-media.*'))
    assert len(logs) == 1, logs
    assert logs[0].stat().st_mode & 0o777 == 0o600
    assert logs[0].read_text() == 'session-output'
    marker.unlink()
    result = subprocess.run(['/bin/bash', str(script)], env=dict(os.environ, FAIL_ALLOCATE='1'),
                            capture_output=True, timeout=10)
    assert result.returncode != 0, 'failed allocation was accepted'
    assert not marker.exists(), 'command ran after allocation failed'

    # Build/install uses local logs; remote command failure must survive sync.
    out = root / 'out'
    out.mkdir()
    (out / 'omarchy-kids-fixture.pkg.tar.zst').write_text('fixture')
    install = function(repo / 'test/live/lib.sh', 'build_install')
    executable(commands / 'pacman', '''
printf '%s\\n' "$1" >> "$CALLS"
printf 'package output\\n'
if [[ "$1" == -U ]]; then exit "${INSTALL_STATUS:-0}"; fi
exit "${VERIFY_STATUS:-0}"
''')
    executable(commands / 'sync', 'printf sync >> "$CALLS"')
    install_script = root / 'install.sh'
    install_script.write_text('''#!/bin/bash
set -uo pipefail
vm_ready() { return 0; }
air() { return 0; }
scp() { return 0; }
vmroot() { ''' + shlex.quote(sys.executable) + ' ' + shlex.quote(str(guard)) + ''' install "$1"; }
LIVE_REMOTE_REPO=fixture
LIVE_SSH_CFG=fixture
LIVE_OUT_DIR=''' + shlex.quote(str(out)) + '\n' + install + '\nbuild_install\n')
    for label, install_status, verify_status in [('success', 0, 0), ('install-fails', 7, 0), ('verify-fails', 0, 8)]:
        for log in out.glob('live-pacman-*.log'):
            log.unlink()
        calls = root / (label + '.calls')
        env = dict(os.environ, PATH=str(commands) + ':/usr/bin:/bin', CALLS=str(calls),
                   INSTALL_STATUS=str(install_status), VERIFY_STATUS=str(verify_status))
        result = subprocess.run(['/bin/bash', str(install_script)], env=env, capture_output=True, timeout=10)
        assert (result.returncode == 0) == (label == 'success'), (label, result.stderr)
        assert (out / 'live-pacman-U.log').read_text() == 'package output\n'
        if install_status:
            assert calls.read_text() == '-U\n', 'failed install continued to sync/verification'
            assert not (out / 'live-pacman-Qkk.log').exists()
        else:
            assert (out / 'live-pacman-Qkk.log').read_text() == 'package output\n'
            assert calls.read_text() == '-U\nsync-Qkk\n'
print('harness-log-test: PASS')
PY
