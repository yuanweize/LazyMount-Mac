import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import install


class InstallTests(unittest.TestCase):
    def test_legacy_label_migration_and_config_preservation(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            dest = home / 'Scripts'; dest.mkdir()
            agents = home / 'Library/LaunchAgents'; agents.mkdir(parents=True)
            private = b'SMB_USER="separate_network_account"\nRCLONE_ENABLED="false"\n'
            (dest / 'mount_manager.local.sh').write_bytes(private)
            old = agents / 'arbitrary-filename.plist'
            old.write_bytes(plistlib.dumps({'Label': 'com.legacy.mountservice', 'ProgramArguments': ['/bin/bash', str(dest / 'mount_manager.sh')]}))
            calls = []
            def fake(args, check=True):
                calls.append(args)
                return subprocess.CompletedProcess(args, 0, '', '')
            with patch.multiple(install, HOME=home, DEST=dest, AGENTS=agents, PLIST=agents/'com.lazymount.plist', LABELS={'com.lazymount', 'com.example.mountmanager'}), patch.object(install.sys, 'platform', 'darwin'), patch.object(install.os, 'getuid', return_value=501), patch.object(install, 'stop'), patch.object(install, 'call', side_effect=fake):
                install.main('install')
                self.assertFalse(old.exists())
                self.assertIn('com.legacy.mountservice', install.LABELS)
                self.assertEqual((dest/'mount_manager.local.sh').read_bytes(), private)
                generated = plistlib.loads((agents/'com.lazymount.plist').read_bytes())
                self.assertEqual(generated['Label'], 'com.lazymount')
                self.assertEqual((agents/'com.lazymount.plist').stat().st_mode & 0o777, 0o600)
                self.assertEqual(generated['EnvironmentVariables']['HOME'], str(home))
                install.main('update')
                self.assertEqual((dest/'mount_manager.local.sh').read_bytes(), private)
                install.main('uninstall')
                self.assertFalse((agents/'com.lazymount.plist').exists())
                self.assertEqual((dest/'mount_manager.local.sh').read_bytes(), private)

    def test_failed_bootstrap_restores_old_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory); dest = home/'Scripts'; dest.mkdir()
            agents = home/'Library/LaunchAgents'; agents.mkdir(parents=True)
            old_script = b'old release'
            (dest/'mount_manager.sh').write_bytes(old_script)
            (dest/'mount_manager.local.sh').write_text('SMB_ENABLED="false"')
            old = agents/'legacy.plist'
            old.write_bytes(plistlib.dumps({'Label': 'com.example.mountmanager'}))
            def fake(args, check=True):
                if 'bootstrap' in args and args[-1].endswith('com.lazymount.plist'):
                    raise subprocess.CalledProcessError(5, args)
                return subprocess.CompletedProcess(args, 0, '', '')
            with patch.multiple(install, HOME=home, DEST=dest, AGENTS=agents, PLIST=agents/'com.lazymount.plist', LABELS={'com.lazymount', 'com.example.mountmanager'}), patch.object(install.sys, 'platform', 'darwin'), patch.object(install.os, 'getuid', return_value=501), patch.object(install, 'stop'), patch.object(install, 'call', side_effect=fake):
                with self.assertRaises(subprocess.CalledProcessError):
                    install.main('update')
            self.assertTrue(old.exists())
            self.assertEqual((dest/'mount_manager.sh').read_bytes(), old_script)
            self.assertEqual((dest/'mount_manager.local.sh').read_text(), 'SMB_ENABLED="false"')


if __name__ == '__main__':
    unittest.main()
