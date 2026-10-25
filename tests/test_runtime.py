import errno
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lazymount_runtime as lm


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.manager = lm.APFS('/tmp/test.sparsebundle', '/Volumes/Test', state_dir=Path(self.temp.name))
        self.manager.uuid = 'UUID'
        self.identity = {'volume': {'DeviceIdentifier': 'disk99s1', 'MountPoint': '/Volumes/Test', 'VolumeUUID': 'UUID'},
                         'container': {'ContainerReference': 'disk99', 'Volumes': []},
                         'image': {'system-entities': [{'dev-entry': '/dev/disk98'}]}}

    def tearDown(self):
        self.temp.cleanup()

    def test_modern_backend_selected_without_legacy_fallback(self):
        with patch.object(lm, 'modern_images_available', return_value=True), patch.object(lm, 'run', side_effect=lm.Failure('attach failed')) as command:
            with self.assertRaises(lm.Failure):
                self.manager.attach()
            command.assert_called_once()
            self.assertEqual(command.call_args.args[0][:3], [lm.DISKUTIL, 'image', 'attach'])
            self.assertNotIn('--mountOptions', command.call_args.args[0])
            self.assertIn('--mountPoint', command.call_args.args[0])

    def test_legacy_backend_for_older_macos_only(self):
        with patch.object(lm, 'modern_images_available', return_value=False), patch.object(lm, 'run') as command:
            self.manager.attach()
            self.assertEqual(command.call_args.args[0][:2], [lm.HDIUTIL, 'attach'])
            self.assertIn('-noautofsck', command.call_args.args[0])
            self.assertNotIn('-owners', command.call_args.args[0])

    def test_modern_offline_attach_never_mounts(self):
        with patch.object(lm, 'modern_images_available', return_value=True), patch.object(lm, 'run') as command:
            lm.attach_image(self.manager.image)
            self.assertIn('--noMount', command.call_args.args[0])
            self.assertNotIn('--mountPoint', command.call_args.args[0])

    def test_offline_mount_default_volume_needs_no_root_mkdir(self):
        self.manager.approved = 'UUID'
        self.identity['volume']['VolumeName'] = 'Test'
        with patch.object(self.manager, 'unmount', return_value=self.identity), patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'probe', return_value={'ok': True}), patch.object(lm, 'run') as command, patch.object(Path, 'mkdir') as mkdir:
            self.manager.offline_repair()
            mount_commands = [c.args[0] for c in command.call_args_list if 'mount' in c.args[0]]
            self.assertEqual(mount_commands, [[lm.DISKUTIL, 'mount', 'disk99s1']])
            self.assertFalse(any(c.args and c.args[0] == '/Volumes/Test' for c in mkdir.call_args_list))
            self.assertEqual(self.manager.state, 'Verified')

    def test_mounted_but_unwritable_enters_recovery(self):
        with patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'probe', return_value={'ok': False, 'kind': 'io'}), patch.object(self.manager, 'recover') as recovery:
            self.manager.cycle()
            recovery.assert_called_once()

    def test_permission_sync_capacity_timeout_never_repair(self):
        for kind in ('permission', 'sync', 'capacity', 'timeout', 'cleanup'):
            with patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'probe', return_value={'ok': False, 'kind': kind}), patch.object(self.manager, 'recover') as recovery:
                self.manager.cycle()
                recovery.assert_not_called()

    def test_corrupt_attach_fails_closed(self):
        with patch.object(self.manager, 'identity', return_value=None), patch('os.path.exists', return_value=True), patch('os.path.ismount', return_value=False), patch.object(self.manager, 'attach', side_effect=lm.Failure('corrupt image')):
            self.manager.cycle()
            self.assertEqual(self.manager.state, 'Degraded')

    def test_device_renumbering_uses_uuid_and_physical_store(self):
        for n in (5, 27):
            image = {'image-path': '/tmp/test.sparsebundle', 'owner-uid': os.getuid(), 'system-entities': [{'dev-entry': f'/dev/disk{n}s2'}]}
            container = {'ContainerReference': f'disk{n+1}', 'PhysicalStores': [{'DeviceIdentifier': f'disk{n}s2'}], 'Volumes': [{'DeviceIdentifier': f'disk{n+1}s1', 'APFSVolumeUUID': 'UUID'}]}
            info = {'DeviceIdentifier': f'disk{n+1}s1', 'VolumeUUID': 'UUID', 'FilesystemType': 'apfs', 'MountPoint': '/Volumes/Test'}
            with patch.object(lm, 'plist', side_effect=[{'images': [image]}, {'Containers': [container]}, info]):
                self.assertEqual(self.manager.identity()['volume']['DeviceIdentifier'], f'disk{n+1}s1')

    def test_wrong_image_store_rejected(self):
        with patch.object(lm, 'plist', side_effect=[{'images': [{'image-path': '/tmp/test.sparsebundle', 'owner-uid': os.getuid(), 'system-entities': []}]}, {'Containers': [{'PhysicalStores': [{'DeviceIdentifier': 'disk123'}]}]}]):
            with self.assertRaises(lm.Failure):
                self.manager.identity()

    def test_repair_failure_never_mounts_or_verifies_success(self):
        self.manager.approved = 'UUID'
        calls = []
        def command(args, **kwargs):
            calls.append(args)
            if 'verifyVolume' in args or 'repairVolume' in args:
                raise lm.Failure('corruption or repair failure')
            return b''
        with patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'unmount', return_value=self.identity), patch.object(self.manager, 'attach'), patch.object(self.manager, 'probe', return_value={'ok': False, 'kind': 'io'}), patch.object(lm, 'plist', return_value={'WholeDisk': True, 'DeviceIdentifier': 'disk98'}), patch.object(lm, 'run', side_effect=command):
            self.manager.cycle(0)
        self.assertTrue(any('repairVolume' in c for c in calls))
        self.assertFalse(any('mount' in c for c in calls))
        self.assertEqual(self.manager.state, 'Degraded')

    def test_unapproved_never_repairs(self):
        with patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'unmount', return_value=self.identity), patch.object(self.manager, 'attach'), patch.object(self.manager, 'probe', return_value={'ok': False, 'kind': 'io'}), patch.object(lm, 'plist', return_value={'WholeDisk': True, 'DeviceIdentifier': 'disk98'}), patch.object(lm, 'run') as command:
            self.manager.cycle(0)
            self.assertFalse(any('repairVolume' in c.args[0] for c in command.call_args_list))

    def test_busy_volume_never_unmounts(self):
        identity = {'container': {'Volumes': [{'MountPoint': '/Volumes/Test'}]}}
        result = subprocess.CompletedProcess([], 0, b'open file', b'')
        with patch.object(self.manager, 'identity', return_value=identity), patch.object(lm.subprocess, 'run', return_value=result), patch.object(lm, 'run') as command:
            with self.assertRaises(lm.Failure):
                self.manager.unmount()
            command.assert_not_called()

    def test_approved_corrupt_filesystem_offline_path(self):
        self.manager.approved = 'UUID'
        self.identity['volume'].pop('MountPoint')
        with patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'offline_repair') as repair:
            self.manager.cycle(0)
            repair.assert_called_once()

    def test_unmounted_without_backup_is_not_repaired(self):
        self.identity['volume'].pop('MountPoint')
        with patch.object(self.manager, 'identity', return_value=self.identity), patch.object(self.manager, 'offline_repair') as repair:
            self.manager.cycle(0)
            repair.assert_not_called()
            self.assertEqual(self.manager.state, 'Degraded')

    def test_duplicate_lock(self):
        path = Path(self.temp.name) / 'lock'
        lock = lm.Lock(path)
        try:
            with self.assertRaises(lm.Failure):
                lm.Lock(path)
        finally:
            lock.close()
        lm.Lock(path).close()

    def test_probe_readback_and_cleanup(self):
        out = lm.run([sys.executable, str(lm.ROOT / 'lazymount_runtime.py'), 'probe', self.temp.name])
        self.assertTrue(json.loads(out)['ok'])
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])

    def test_timeout_is_real(self):
        with self.assertRaises(lm.Failure):
            lm.run([sys.executable, '-c', 'import time; time.sleep(10)'], timeout=.05)

    def test_cooldown_persisted(self):
        self.manager.last_recovery = 12345
        self.manager.status('Degraded', 'test')
        loaded = lm.APFS('/tmp/test.sparsebundle', '/Volumes/Test', state_dir=Path(self.temp.name))
        self.assertEqual(loaded.last_recovery, 12345)
        self.assertEqual(loaded.uuid, 'UUID')


if __name__ == '__main__':
    unittest.main()
