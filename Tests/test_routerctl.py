import io
import json
import sys
import tarfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'Scripts'))
import routerctl  # noqa: E402


SAMPLE = ('ss://aes-128-gcm:pass123@example.com:443#France\n'
          'ss://aes-128-gcm:pass456@example.net:443#Finland')


class ProfileMigrationTests(unittest.TestCase):
    def setUp(self):
        self.calls = []

    def fake_ssh(self, command, stdin=None, timeout=60):
        self.calls.append((command, stdin))
        if command.startswith('cat /etc/happvpn/selection-mode'):
            return b'auto'
        if command.startswith('cat /etc/happvpn/mode'):
            return b'vpn'
        return b''

    def test_stages_every_profile_before_switching(self):
        with patch.object(routerctl, 'ssh', side_effect=self.fake_ssh), \
             patch.object(routerctl, 'active_test', return_value='203.0.113.1') as test_exit, \
             patch.object(routerctl, '_cleanup_candidate'), \
             patch.object(routerctl, 'emit') as emit:
            routerctl.install_profile(SAMPLE, int(time.time()) + 3600, 'ss-00')

        archive = next(data for command, data in self.calls if 'tar -xf -' in command)
        with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
            self.assertEqual(bundle.getnames(), ['ss-00.json', 'ss-01.json'])
            self.assertEqual([member.mode for member in bundle.getmembers()], [0o600, 0o600])
            self.assertEqual(json.load(bundle.extractfile('ss-01.json'))['server'], 'example.net')
        commands = '\n'.join(command for command, _ in self.calls)
        self.assertNotIn('pass123', commands)
        self.assertNotIn('pass456', commands)
        self.assertIn('printf auto > /etc/happvpn/selection-mode', commands)
        self.assertEqual(test_exit.call_count, 2)
        self.assertTrue(emit.call_args.args[0]['ok'])

    def test_restart_failure_restores_the_previous_profile(self):
        failed = False

        def fail_first_restart(command, stdin=None, timeout=60):
            nonlocal failed
            result = self.fake_ssh(command, stdin, timeout)
            if command == '/etc/init.d/happ-ss restart' and not failed:
                failed = True
                raise RuntimeError('restart failed')
            return result

        with patch.object(routerctl, 'ssh', side_effect=fail_first_restart), \
             patch.object(routerctl, 'active_test', return_value='203.0.113.1'), \
             patch.object(routerctl, '_cleanup_candidate'):
            with self.assertRaisesRegex(RuntimeError, 'restart failed'):
                routerctl.install_profile(SAMPLE, int(time.time()) + 3600, 'ss-00')

        commands = '\n'.join(command for command, _ in self.calls)
        self.assertIn('cp /etc/happvpn/ss-client.json.last-good /etc/happvpn/ss-client.json', commands)
        self.assertIn('printf auto > /etc/happvpn/selection-mode', commands)


class ServerSelectionTests(unittest.TestCase):
    def test_rejects_invalid_tag_before_ssh(self):
        with patch.object(routerctl, 'ssh') as ssh:
            with self.assertRaises(ValueError):
                routerctl.select_node('ss-00;reboot')
        ssh.assert_not_called()


if __name__ == '__main__':
    unittest.main()
