#!/usr/bin/env python3
"""LazyMount 3: bounded probes, plist identity, conservative APFS recovery."""
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import signal
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent
STATE = Path.home() / 'Library/Application Support/LazyMount'
DISKUTIL = '/usr/sbin/diskutil'
HDIUTIL = '/usr/bin/hdiutil'


def log(message):
    print(time.strftime('%Y-%m-%d %H:%M:%S'), message, flush=True)


class Failure(Exception):
    pass


class Lock:
    """Kernel lock; no stale PID deletion race. Retained for entire lifecycle."""
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        os.fchmod(fd, 0o600)
        self.file = os.fdopen(fd, 'a+')
        try:
            fcntl.flock(self.file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self.file.close()
            raise Failure('another instance holds ' + path.name)

    def close(self):
        self.file.close()


def run(args, timeout=30, mutate=False):
    # Never kill a filesystem repair halfway through. Its image lock stays held.
    # Read-only operations/probes have actual deadlines; failure is not health.
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = proc.communicate(timeout=None if mutate else timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        try:
            proc.communicate(timeout=2)
        except subprocess.TimeoutExpired:
            # Do not return and allow another recovery while an I/O worker lives.
            log('Degraded: operation stuck in kernel; waiting, recovery blocked')
            proc.communicate()
        raise Failure('timeout: ' + args[0])
    if proc.returncode:
        raise Failure(f'{Path(args[0]).name} exit={proc.returncode}: ' + err.decode(errors='replace')[-1000:] + out.decode(errors='replace')[-1000:])
    return out


def plist(args):
    try:
        return plistlib.loads(run(args))
    except (ValueError, plistlib.InvalidFileException) as exc:
        raise Failure('invalid plist response') from exc


def probe_worker(directory):
    """Only touch our exclusive random file, never games or existing filenames."""
    name = None
    stage = 'create'
    result = {'ok': False}
    try:
        fd, name = tempfile.mkstemp(prefix='.lazymount-probe-', dir=directory)
        payload = os.urandom(4096)
        with os.fdopen(fd, 'wb') as stream:
            stage = 'write'
            stream.write(payload)
            stream.flush()
            stage = 'sync'
            os.fsync(stream.fileno())
        stage = 'readback'
        with open(name, 'rb') as stream:
            if stream.read() != payload:
                raise OSError(errno.EIO, 'readback mismatch')
        result = {'ok': True}
    except OSError as exc:
        kind = ('permission' if exc.errno in (errno.EACCES, errno.EPERM) else
                'readonly' if exc.errno == errno.EROFS else
                'capacity' if exc.errno in (errno.ENOSPC, errno.EDQUOT) else
                'sync' if stage == 'sync' else 'io')
        result = {'ok': False, 'kind': kind, 'stage': stage, 'errno': exc.errno}
    finally:
        if name:
            try:
                os.unlink(name)
            except OSError as exc:
                result = {'ok': False, 'kind': 'cleanup', 'errno': exc.errno}
    print(json.dumps(result), flush=True)


class APFS:
    def __init__(self, image, mountpoint, uuid='', approved='', state_dir=STATE):
        self.image = os.path.realpath(image)
        self.mountpoint = os.path.realpath(mountpoint)
        self.uuid = uuid.upper()
        self.approved = approved.upper()
        digest = hashlib.sha256(self.image.encode()).hexdigest()
        self.state_file = state_dir / (digest + '.json')
        self.lock_file = state_dir / (digest + '.lock')
        self.last_recovery = 0
        if self.state_file.exists():
            saved = json.loads(self.state_file.read_text())
            if self.uuid and saved.get('uuid') != self.uuid:
                raise Failure('configured UUID differs from pinned image identity')
            self.uuid = saved.get('uuid', self.uuid)
            self.last_recovery = saved.get('last_recovery', 0)
        self.state = 'Unknown'

    def status(self, state, reason):
        self.state = state
        log(f'APFS {state}: {reason}')
        self.state_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        data = {'uuid': self.uuid, 'state': state, 'reason': reason,
                'last_recovery': self.last_recovery, 'updated': time.time()}
        fd, tmp = tempfile.mkstemp(dir=self.state_file.parent)
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream)
        os.replace(tmp, self.state_file)

    def identity(self):
        images = plist([HDIUTIL, 'info', '-plist']).get('images', [])
        matches = [i for i in images if os.path.realpath(i.get('image-path', '')) == self.image]
        if not matches:
            return None
        if len(matches) != 1:
            raise Failure('ambiguous image attachments')
        image = matches[0]
        if image.get('owner-uid') != os.getuid():
            raise Failure('image belongs to another user')
        entities = {e['dev-entry'].removeprefix('/dev/') for e in image.get('system-entities', []) if e.get('dev-entry')}
        containers = plist([DISKUTIL, 'apfs', 'list', '-plist']).get('Containers', [])
        candidates = []
        for container in containers:
            stores = {s['DeviceIdentifier'] for s in container.get('PhysicalStores', [])}
            if not stores or not stores.issubset(entities):
                continue
            # Do not repair an image sharing a container with another backing store.
            for volume in container.get('Volumes', []):
                info = plist([DISKUTIL, 'info', '-plist', volume['DeviceIdentifier']])
                volume['MountPoint'] = info.get('MountPoint', '')
                if self.uuid:
                    selected = volume.get('APFSVolumeUUID', '').upper() == self.uuid
                else:
                    selected = volume.get('MountPoint') == self.mountpoint or volume.get('Name') == Path(self.mountpoint).name
                if selected:
                    if info.get('FilesystemType') != 'apfs':
                        raise Failure('not an APFS volume')
                    candidates.append((container, info, image))
        if len(candidates) != 1:
            raise Failure('expected APFS UUID not uniquely present in the configured image')
        container, info, image = candidates[0]
        current_uuid = info.get('VolumeUUID', '').upper()
        if not current_uuid or (self.uuid and current_uuid != self.uuid):
            raise Failure('volume UUID mismatch')
        if info.get('MountPoint') and info['MountPoint'] != self.mountpoint:
            raise Failure('volume mounted at an unexpected path')
        self.uuid = current_uuid
        return {'container': container, 'volume': info, 'image': image}

    def probe(self):
        try:
            return json.loads(run([sys.executable, str(ROOT / 'lazymount_runtime.py'), 'probe', self.mountpoint], timeout=10))
        except Failure as exc:
            return {'ok': False, 'kind': 'timeout', 'detail': str(exc)}

    def attach(self):
        # No unconditional fsck on boot. Read-only attach flags/owners-off overrides
        # cannot silently undermine the recovery contract.
        run([HDIUTIL, 'attach', '-plist', '-noautofsck', '-owners', 'on',
             '-mountpoint', self.mountpoint, self.image], mutate=True)

    def idle(self, identity):
        for volume in identity['container'].get('Volumes', []):
            point = volume.get('MountPoint')
            if not point:
                continue
            proc = subprocess.run(['/usr/sbin/lsof', '-nP', '+f', '--', point],
                                  capture_output=True, timeout=10)
            # lsof's 1 + empty output means no open files. Errors fail closed.
            if proc.returncode != 1 or proc.stdout.strip() or proc.stderr.strip():
                raise Failure('open handles or incomplete lsof inspection; close applications first')

    def unmount(self):
        current = self.identity()
        if not current:
            raise Failure('image detached during recovery')
        self.idle(current)
        run([DISKUTIL, 'unmountDisk', current['container']['ContainerReference']], mutate=True)
        current = self.identity()
        if not current or any(v.get('MountPoint') for v in current['container'].get('Volumes', [])):
            raise Failure('container is not fully unmounted')
        return current

    def recover(self, initial, cooldown):
        if time.time() - self.last_recovery < cooldown:
            self.status('Degraded', 'recovery cooldown; ' + json.dumps(initial))
            return
        self.last_recovery = time.time()
        self.status('Recovering', 'normal unmount/remount; no forced eject')
        current = self.unmount()
        # Reattach the exact image with owners enabled, avoiding stale attach state.
        whole = []
        for entity in current['image'].get('system-entities', []):
            device = entity.get('dev-entry')
            if device:
                info = plist([DISKUTIL, 'info', '-plist', device])
                if info.get('WholeDisk') and info.get('DeviceIdentifier') != current['container']['ContainerReference']:
                    whole.append(device)
        if len(whole) != 1:
            raise Failure('image whole disk is ambiguous')
        run([HDIUTIL, 'detach', whole[0]], mutate=True)
        self.attach()
        current = self.identity()
        if not current or current['volume'].get('MountPoint') != self.mountpoint:
            raise Failure('reattach did not mount the pinned UUID')
        checked = self.probe()
        if checked['ok']:
            self.status('Verified', 'write/fsync/readback passed after normal reattach')
            return
        # Permissions, capacity and unsupported sync are not proof of corruption.
        if checked.get('kind') in ('permission', 'capacity', 'sync', 'timeout', 'cleanup'):
            self.status('Degraded', json.dumps(checked))
            return
        if self.approved != self.uuid:
            self.status('Degraded', 'write still fails; backup confirmation/UUID repair approval required: ' + json.dumps(checked))
            return
        self.offline_repair()

    def offline_repair(self):
        if not self.uuid or self.approved != self.uuid:
            raise Failure('backup/UUID approval required for offline repair')
        current = self.unmount()
        target = current['volume']['DeviceIdentifier']
        try:
            run([DISKUTIL, 'verifyVolume', target], mutate=True)
        except Failure as exc:
            log('APFS verification failed: ' + str(exc))
            current = self.identity()
            if not current or any(v.get('MountPoint') for v in current['container'].get('Volumes', [])):
                raise Failure('repair preconditions changed')
            run([DISKUTIL, 'repairVolume', current['volume']['DeviceIdentifier']], mutate=True)
            current = self.identity()
            if not current:
                raise Failure('identity lost after repair')
            run([DISKUTIL, 'verifyVolume', current['volume']['DeviceIdentifier']], mutate=True)
        current = self.identity()
        if not current:
            raise Failure('identity lost before mount')
        run([DISKUTIL, 'mount', '-mountPoint', self.mountpoint, current['volume']['DeviceIdentifier']], mutate=True)
        current = self.identity()
        if not current or current['volume'].get('MountPoint') != self.mountpoint:
            raise Failure('mount verification failed')
        checked = self.probe()
        self.status('Verified' if checked['ok'] else 'Degraded', json.dumps(checked))

    def recover_unmounted(self, cooldown):
        if not self.uuid or self.approved != self.uuid:
            raise Failure('unmounted image requires backup/UUID approval and diagnosis')
        if time.time() - self.last_recovery < cooldown:
            raise Failure('unmounted image recovery cooldown')
        self.last_recovery = time.time()
        self.status('Recovering', 'approved offline verification/repair')
        self.offline_repair()

    def cycle(self, cooldown=3600):
        try:
            current = self.identity()
            if not current:
                if not os.path.exists(self.image):
                    raise Failure('image unavailable; other mount services remain running')
                if os.path.ismount(self.mountpoint):
                    raise Failure('mountpoint occupied by a different filesystem')
                try:
                    self.attach()
                except Failure:
                    if not self.uuid or self.approved != self.uuid:
                        raise
                    if time.time() - self.last_recovery < cooldown:
                        raise Failure('attachment recovery cooldown')
                    # A damaged filesystem may be attachable without mounting.
                    # Never guess identity when its APFS metadata is unreadable.
                    if not self.identity():
                        run([HDIUTIL, 'attach', '-plist', '-nomount', '-noautofsck', self.image], mutate=True)
                current = self.identity()
            if not current:
                raise Failure('attach did not produce the expected APFS volume')
            if not current['volume'].get('MountPoint'):
                self.recover_unmounted(cooldown)
                return
            checked = self.probe()
            if checked['ok']:
                self.status('Healthy', 'write/fsync/readback passed')
                return
            self.status('Degraded', json.dumps(checked))
            if checked.get('kind') in ('permission', 'capacity', 'sync', 'timeout', 'cleanup'):
                return
            self.recover(checked, cooldown)
        except (Failure, OSError, ValueError, subprocess.TimeoutExpired) as exc:
            self.status('Degraded', str(exc))


def service():
    os.umask(0o077)
    try:
        lock = Lock(STATE / 'service.lock')
    except Failure as exc:
        log(str(exc))
        return 0
    stopping = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopping.set())
    signal.signal(signal.SIGINT, lambda *_: stopping.set())
    children = {}
    threads = []

    def worker(mode):
        while not stopping.is_set():
            child = subprocess.Popen(['/bin/bash', str(ROOT / 'mount_manager.sh'), mode], start_new_session=True)
            children[mode] = child
            if stopping.is_set():
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            child.wait()
            children.pop(mode, None)
            stopping.wait(60)

    def apfs_worker():
        image = os.environ.get('BUNDLE_PATH', '')
        name = os.environ.get('BUNDLE_VOLUME_NAME', '')
        if not image or not name:
            return
        try:
            manager = APFS(image, '/Volumes/' + name, os.environ.get('BUNDLE_VOLUME_UUID', ''),
                           os.environ.get('BUNDLE_REPAIR_APPROVED_UUID', ''))
            image_lock = Lock(manager.lock_file)
            try:
                while not stopping.is_set():
                    manager.cycle(max(60, int(os.environ.get('BUNDLE_RECOVERY_COOLDOWN', '3600'))))
                    stopping.wait(max(30, int(os.environ.get('BUNDLE_CHECK_INTERVAL', '300'))))
            finally:
                image_lock.close()
        except (Failure, ValueError) as exc:
            log('APFS disabled: ' + str(exc))

    log('LazyMount ' + os.environ.get('SCRIPT_VERSION', '?') + ' service started')
    for action in [lambda: worker('--smb'), lambda: worker('--rclone'), apfs_worker]:
        thread = threading.Thread(target=action)
        thread.start()
        threads.append(thread)
    stopping.wait()
    # Normal termination only. APFS mutation finishes before releasing its lock.
    for child in list(children.values()):
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for thread in threads:
        thread.join()
    lock.close()
    return 0


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'probe':
        probe_worker(sys.argv[2])
    elif sys.argv[1:] == ['service']:
        sys.exit(service())
    else:
        sys.exit('Usage: lazymount_runtime.py service | probe DIRECTORY')
