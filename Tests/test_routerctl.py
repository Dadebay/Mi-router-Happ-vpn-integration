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


class MultipleSubscriptionTests(unittest.TestCase):
    def test_two_https_subscriptions_form_one_server_list(self):
        first = 'https://first.example/sub/private-token'
        second = 'https://second.example/sub/another-token'
        with patch.object(routerctl, 'fetch_subscription', side_effect=[
            'ss://aes-128-gcm:pass123@example.com:443#France',
            'ss://aes-128-gcm:pass456@example.net:443#Finland',
        ]) as fetch:
            profiles = routerctl.parse_profiles(first + '\n' + second)

        self.assertEqual([node['tag'] for node, _ in profiles], ['ss-00', 'ss-01'])
        self.assertEqual([node['name'] for node, _ in profiles],
                         ['first.example · France', 'second.example · Finland'])
        self.assertEqual([config['server'] for _, config in profiles],
                         ['example.com', 'example.net'])
        self.assertNotIn('private-token', json.dumps([node for node, _ in profiles]))
        self.assertNotIn('another-token', json.dumps([node for node, _ in profiles]))
        self.assertEqual(fetch.call_count, 2)

    def test_rejects_more_than_two_or_mixed_https_sources(self):
        with patch.object(routerctl, 'fetch_subscription') as fetch:
            with self.assertRaisesRegex(ValueError, 'En fazla iki HTTPS'):
                routerctl.parse_profiles('https://a.example/sub\nhttps://b.example/sub\nhttps://c.example/sub')
            with self.assertRaisesRegex(ValueError, 'En fazla iki HTTPS'):
                routerctl.parse_profiles('https://a.example/sub\nss://aes-128-gcm:pass@example.com:443')
        fetch.assert_not_called()


class ServerSelectionTests(unittest.TestCase):
    def test_rejects_invalid_tag_before_ssh(self):
        with patch.object(routerctl, 'ssh') as ssh:
            with self.assertRaises(ValueError):
                routerctl.select_node('ss-00;reboot')
        ssh.assert_not_called()


class CandidateProbeTests(unittest.TestCase):
    def test_exit_probe_connects_to_ipv4_destination(self):
        answer = [(routerctl.socket.AF_INET, routerctl.socket.SOCK_STREAM, 6,
                   '', ('34.160.111.145', 443))]
        with patch.object(routerctl.socket, 'getaddrinfo', return_value=answer) as lookup:
            request = routerctl.socks_ipv4_request('ifconfig.me', 443)
        lookup.assert_called_once_with('ifconfig.me', 443, routerctl.socket.AF_INET,
                                       routerctl.socket.SOCK_STREAM)
        self.assertEqual(request, b'\x05\x01\x00\x01\x22\xa0\x6f\x91\x01\xbb')

    def test_exit_ip_accepts_ipv4_and_ipv6_but_rejects_non_ip_response(self):
        self.assertEqual(routerctl.validated_exit_ip('65.109.188.233'), '65.109.188.233')
        self.assertEqual(routerctl.validated_exit_ip('2a01:4f9:c010:2f23::1'),
                         '2a01:4f9:c010:2f23::1')
        with self.assertRaisesRegex(RuntimeError, 'IP yanıtı geçersiz'):
            routerctl.validated_exit_ip('2a01:4f9:c010:2f23::1', version=4)
        with self.assertRaisesRegex(RuntimeError, 'IP yanıtı geçersiz'):
            routerctl.validated_exit_ip('<html>error</html>')

    def test_probe_checks_selected_server_without_changing_live_profile(self):
        with patch.object(routerctl, 'ssh', return_value=b'') as ssh, \
             patch.object(routerctl, 'active_test', return_value='203.0.113.1') as test_exit, \
             patch.object(routerctl, 'emit') as emit:
            routerctl.probe_profile(SAMPLE, 'ss-01')
        config = json.loads(ssh.call_args_list[0].kwargs['stdin'])
        self.assertEqual(config['server'], 'example.net')
        commands = '\n'.join(call.args[0] for call in ssh.call_args_list)
        self.assertNotIn('/etc/happvpn/', commands)
        self.assertNotIn('pass456', commands)
        self.assertIn('rm -f /tmp/happ-ss-probe.pid', commands)
        test_exit.assert_called_once_with(emit_result=False, remote_port=11083)
        self.assertEqual(emit.call_args.args[0]['exitIP'], '203.0.113.1')

    def test_probe_failure_cleans_temporary_profile(self):
        with patch.object(routerctl, 'ssh', return_value=b'') as ssh, \
             patch.object(routerctl, 'active_test', side_effect=RuntimeError('TLS closed')):
            with self.assertRaisesRegex(RuntimeError, 'TLS closed'):
                routerctl.probe_profile(SAMPLE, 'ss-00')
        self.assertIn('rm -f /tmp/happ-ss-probe.pid', ssh.call_args_list[-1].args[0])


class DiagnosticBackupTests(unittest.TestCase):
    def test_archive_date_is_validated_before_ssh(self):
        with patch.object(routerctl, 'ssh') as ssh:
            with self.assertRaises(ValueError):
                routerctl.backup_read('2026-10-13;reboot')
        ssh.assert_not_called()

    def test_archive_listing_keeps_only_dated_files(self):
        listing = b'2026-10-13 2048\ninvalid 100\n2026-10-12 1024\n'
        with patch.object(routerctl, 'ssh', return_value=listing):
            self.assertEqual(routerctl.list_backups(), [
                {'date': '2026-10-13', 'size': 2048},
                {'date': '2026-10-12', 'size': 1024},
            ])


if __name__ == '__main__':
    unittest.main()
