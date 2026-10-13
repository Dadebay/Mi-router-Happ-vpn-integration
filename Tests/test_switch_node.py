import os
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


SOURCE = (Path(__file__).resolve().parents[1] / 'Scripts' / 'switch-node.sh').read_text()


class RouterSwitchTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.base = self.root / 'happvpn'
        (self.base / 'profiles').mkdir(parents=True)
        (self.root / 'bin').mkdir()
        for name, text in {
            'ss-client.json': 'old profile',
            'active-outbound': 'ss-00',
            'selection-mode': 'auto',
            'mode': 'vpn',
            'expires-at': str(int(time.time()) + 3600),
        }.items():
            (self.base / name).write_text(text)
        (self.base / 'profiles' / 'ss-00.json').write_text('old profile')
        (self.base / 'profiles' / 'ss-01.json').write_text('new profile')
        self.make_script(self.base / 'probe-nodes.lua', '#!/bin/sh\nexit 0\n')
        self.make_script(self.root / 'bin' / 'ss-local',
                         '#!/bin/sh\nwhile [ "$1" != "-f" ]; do shift; done\n'
                         'shift\nsleep 60 & echo $! > "$1"\n')
        self.make_script(self.root / 'bin' / 'lua5.3',
                         '#!/bin/sh\ncase "$2" in\n'
                         '  rank) printf "ss-01\\nss-00\\n";;\n'
                         '  check) [ ! -e "' + str(self.root / 'fail-check') + '" ];;\n'
                         'esac\n')
        self.make_script(self.root / 'bin' / 'logger', '#!/bin/sh\nexit 0\n')
        self.make_script(self.root / 'happ-ss', '#!/bin/sh\nexit 0\n')
        source = (SOURCE.replace('BASE=/etc/happvpn', f'BASE={self.base}')
                  .replace('LOCK=/tmp/happvpn-switch.lock', f'LOCK={self.root / "lock"}')
                  .replace('PID=/tmp/happvpn-switch-candidate.pid', f'PID={self.root / "candidate.pid"}')
                  .replace('/tmp/happvpn-switch-candidate.log', str(self.root / 'candidate.log'))
                  .replace('/etc/init.d/happ-ss', str(self.root / 'happ-ss'))
                  .replace('sleep 1', ':'))
        self.make_script(self.root / 'switch-node.sh', source)

    @staticmethod
    def make_script(path, text):
        path.write_text(text)
        path.chmod(0o700)

    def run_switch(self, *args):
        environment = {**os.environ, 'PATH': f'{self.root / "bin"}:{os.environ["PATH"]}'}
        return subprocess.run([str(self.root / 'switch-node.sh'), *args],
                              env=environment, capture_output=True, text=True, timeout=15)

    def test_auto_chooses_lowest_ranked_saved_profile(self):
        result = self.run_switch('auto')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / 'ss-client.json').read_text(), 'new profile')
        self.assertEqual((self.base / 'active-outbound').read_text(), 'ss-01')
        self.assertEqual((self.base / 'selection-mode').read_text(), 'auto')

    def test_manual_choice_pauses_automatic_switching(self):
        result = self.run_switch('manual', 'ss-01')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / 'selection-mode').read_text(), 'manual')
        self.assertEqual(self.run_switch('auto').returncode, 0)
        self.assertEqual((self.base / 'active-outbound').read_text(), 'ss-01')

    def test_failed_exit_check_restores_previous_profile(self):
        (self.root / 'fail-check').touch()
        result = self.run_switch('auto')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.base / 'ss-client.json').read_text(), 'old profile')
        self.assertEqual((self.base / 'active-outbound').read_text(), 'ss-00')


if __name__ == '__main__':
    unittest.main()
