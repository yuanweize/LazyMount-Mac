#!/usr/bin/env python3
"""Per-user installation and migration; private config is never overwritten."""
import datetime
import os
from pathlib import Path
import plistlib
import pwd
import shutil
import subprocess
import sys
import tempfile
import time

SOURCE = Path(__file__).resolve().parent
HOME = Path(pwd.getpwuid(os.getuid()).pw_dir)
DEST = HOME / 'Scripts'
AGENTS = HOME / 'Library/LaunchAgents'
PLIST = AGENTS / 'com.lazymount.plist'
DOMAIN = 'gui/' + str(os.getuid())
LABELS = {'com.lazymount', 'com.example.mountmanager'}
FILES = ('mount_manager.sh', 'lazymount_runtime.py')


def call(args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)


def stop():
    for label in LABELS:
        if call(['launchctl', 'print', DOMAIN + '/' + label], False).returncode == 0:
            call(['launchctl', 'bootout', DOMAIN + '/' + label])
    # Old v2 shells can leave orphan monitors. Match only our installed script,
    # then terminate descendants normally; never kill disk image/repair processes.
    rows = call(['ps', '-axo', 'pid=,ppid=,command=']).stdout.splitlines()
    processes = {}
    for row in rows:
        fields = row.strip().split(None, 2)
        if len(fields) == 3:
            processes[int(fields[0])] = (int(fields[1]), fields[2])
    old = {pid for pid, (_, command) in processes.items()
           if command in ('/bin/bash ' + str(DEST / 'mount_manager.sh'),
                          '/bin/bash ' + str(DEST / 'mount_manager.sh') + ' ')}
    descendants = set(old)
    while True:
        added = {pid for pid, (parent, _) in processes.items() if parent in descendants}
        if added.issubset(descendants):
            break
        descendants.update(added)
    for pid in descendants:
        cmd = processes[pid][1]
        if any(word in cmd for word in ('fsck', 'hdiutil', 'diskutil')):
            raise RuntimeError('An old disk operation is still running; wait before upgrading')
    for pid in descendants:
        try:
            os.kill(pid, 15)
        except ProcessLookupError:
            pass
    # A live v3 kernel lock prevents replacement during an in-flight recovery.
    from lazymount_runtime import Lock, STATE
    for _ in range(30):
        try:
            lock = Lock(STATE / 'service.lock')
            lock.close()
            return
        except Exception:
            time.sleep(1)
    raise RuntimeError('Service is still stopping; installation aborted safely')


def main(action):
    os.umask(0o077)
    if sys.platform != 'darwin' or os.getuid() == 0:
        raise RuntimeError('Run as the macOS login user, without sudo')
    if action == 'status':
        result = call(['launchctl', 'print', DOMAIN + '/com.lazymount'], False)
        print(result.stdout or result.stderr)
        return result.returncode
    if action not in ('install', 'update', 'restart', 'uninstall'):
        raise RuntimeError('Usage: ./install.sh install|update|restart|status|uninstall')
    if action == 'restart':
        for path in AGENTS.glob('*.plist'):
            try:
                data = plistlib.loads(path.read_bytes())
                if data.get('ProgramArguments') == ['/bin/bash', str(DEST / 'mount_manager.sh')]:
                    LABELS.add(data['Label'])
            except Exception:
                continue
        stop()
        call(['launchctl', 'bootstrap', DOMAIN, str(PLIST)])
        return 0
    AGENTS.mkdir(parents=True, exist_ok=True)
    backup = HOME / 'Library/Application Support/LazyMount/backups' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    backup.mkdir(parents=True, mode=0o700)
    old_plists = []
    for path in AGENTS.glob('*.plist'):
        try:
            data = plistlib.loads(path.read_bytes())
        except Exception:
            continue
        if data.get('Label') in LABELS or data.get('ProgramArguments') == ['/bin/bash', str(DEST / 'mount_manager.sh')]:
            LABELS.add(data['Label'])
            shutil.copy2(path, backup / path.name)
            old_plists.append(path)
    for name in (*FILES, 'mount_manager.local.sh'):
        if (DEST / name).exists():
            shutil.copy2(DEST / name, backup / name)
    if action != 'uninstall':
        call(['/bin/bash', '-n', str(SOURCE / 'mount_manager.sh')])
        compile((SOURCE / 'lazymount_runtime.py').read_text(), 'lazymount_runtime.py', 'exec')
    previously_loaded = {label for label in LABELS
                         if call(['launchctl', 'print', DOMAIN + '/' + label], False).returncode == 0}
    stop()
    try:
        for path in old_plists:
            path.unlink()
        if action == 'uninstall':
            print('Service removed. Installed files, local settings, mounts and Keychain retained.')
            return 0
        DEST.mkdir(parents=True, exist_ok=True)
        for name in FILES:
            fd, tmp = tempfile.mkstemp(dir=DEST)
            with os.fdopen(fd, 'wb') as stream:
                stream.write((SOURCE / name).read_bytes())
            os.chmod(tmp, 0o700)
            os.replace(tmp, DEST / name)
        config = DEST / 'mount_manager.local.sh'
        if not config.exists():
            candidate = SOURCE / 'mount_manager.local.sh'
            if candidate.exists():
                shutil.copy2(candidate, config)
            else:
                config.write_text('# Local configuration; enable only the services you use.\nSMB_ENABLED="false"\nRCLONE_ENABLED="false"\n')
            os.chmod(config, 0o600)
        data = plistlib.loads((SOURCE / 'com.lazymount.plist').read_bytes())
        data['ProgramArguments'] = ['/bin/bash', str(DEST / 'mount_manager.sh')]
        data['EnvironmentVariables'] = {'HOME': str(HOME), 'LAZYMOUNT_PYTHON': sys.executable,
                                        'PATH': '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'}
        data['WorkingDirectory'] = str(DEST)
        PLIST.write_bytes(plistlib.dumps(data))
        PLIST.chmod(0o600)
        call(['/usr/bin/plutil', '-lint', str(PLIST)])
        call(['launchctl', 'enable', DOMAIN + '/com.lazymount'])
        call(['launchctl', 'bootstrap', DOMAIN, str(PLIST)])
        print('Installed LazyMount 3.0.2; Label=com.lazymount; backup=' + str(backup))
        return 0
    except Exception:
        # Restore the complete prior installation after a failed deployment.
        call(['launchctl', 'bootout', DOMAIN + '/com.lazymount'], False)
        if PLIST.exists():
            PLIST.unlink()
        for name in FILES:
            if (backup / name).exists():
                shutil.copy2(backup / name, DEST / name)
        for path in old_plists:
            shutil.copy2(backup / path.name, path)
            path.chmod(0o600)
            label = plistlib.loads(path.read_bytes()).get('Label')
            if label in previously_loaded:
                call(['launchctl', 'bootstrap', DOMAIN, str(path)], False)
        raise



if __name__ == '__main__':
    os.umask(0o077)
    try:
        from lazymount_runtime import Lock, STATE
        installation_lock = Lock(STATE / 'install.lock')
        sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else 'install'))
    except Exception as exc:
        sys.exit(str(exc))
