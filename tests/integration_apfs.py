#!/usr/bin/env python3
"""Opt-in macOS integration. Creates only its own small temporary APFS image."""
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lazymount_runtime as lm

if sys.platform != 'darwin' or os.environ.get('LAZYMOUNT_TEST_APFS') != '1':
    sys.exit('Opt in on macOS: LAZYMOUNT_TEST_APFS=1 python3 tests/integration_apfs.py')
root = Path(tempfile.mkdtemp(prefix='lazymount-test-')).resolve()
image = root / 'Test.sparsebundle'
point = root / 'volume'; point.mkdir()
print('Disposable test artifacts:', root, flush=True)
subprocess.run([lm.HDIUTIL, 'create', '-size', '128m', '-fs', 'APFS', '-type', 'SPARSEBUNDLE', '-volname', 'LazyMountTest', str(image)], check=True)
manager = lm.APFS(str(image), str(point), state_dir=root/'state')
lock = lm.Lock(manager.lock_file)
try:
    manager.cycle(0)
    assert manager.state == 'Healthy', manager.state
    manager.recover({'ok': False, 'kind': 'io', 'injected': True}, 0)
    assert manager.state == 'Verified', manager.state
    # Execute actual offline verification/repair only on this disposable image.
    current = manager.unmount()
    lm.run([lm.DISKUTIL, 'verifyVolume', current['volume']['DeviceIdentifier']], mutate=True)
    current = manager.identity()
    lm.run([lm.DISKUTIL, 'repairVolume', current['volume']['DeviceIdentifier']], mutate=True)
    current = manager.identity()
    lm.run([lm.DISKUTIL, 'verifyVolume', current['volume']['DeviceIdentifier']], mutate=True)
    lm.run([lm.DISKUTIL, 'mount', '-mountPoint', str(point), current['volume']['DeviceIdentifier']], mutate=True)
    assert manager.probe()['ok']
    print('PASS real APFS lifecycle and offline First Aid on disposable image', flush=True)
finally:
    current = manager.identity()
    if current:
        subprocess.run([lm.HDIUTIL, 'detach', current['container']['ContainerReference']], check=True)
    lock.close()

# Real mounted-but-read-only case; all writes remain inside the disposable image.
lm.run([lm.HDIUTIL, 'attach', '-plist', '-readonly', '-noautofsck', '-mountpoint', str(point), str(image)], mutate=True)
lock = lm.Lock(manager.lock_file)
try:
    assert not manager.probe()['ok']
    manager.cycle(0)
    assert manager.state == 'Verified', manager.state
    print('PASS mounted read-only image automatically recovered and verified', flush=True)
finally:
    current = manager.identity()
    if current:
        lm.run([lm.HDIUTIL, 'detach', current['container']['ContainerReference']], mutate=True)
    lock.close()

# Damage only a copy of our disposable image header, never a user image.
broken = root / 'Broken.sparsebundle'
shutil.copytree(image, broken)
(broken / 'Info.plist').write_bytes(b'invalid test image header')
(broken / 'Info.bckup').write_bytes(b'invalid test image header')
bad = lm.APFS(str(broken), str(point), state_dir=root/'broken-state')
bad.cycle(0)
assert bad.state == 'Degraded'
print('PASS damaged image rejected safely; artifacts retained:', root, flush=True)
