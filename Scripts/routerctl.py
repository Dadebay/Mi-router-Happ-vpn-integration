#!/usr/bin/env python3
"""Local SSH controller for a Xiaomi 4C running OpenWrt and Xray.

Never prints the subscription URL or proxy credentials. All router writes use a
staged file, Xray syntax validation, and a saved last-good configuration.
"""
import argparse
import base64
import json
import os
import re
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home() / '.happ-router'
HOST = '192.168.1.1'
SSH_KEY = HOME / 'router_rsa'
KNOWN_HOSTS = HOME / 'known_hosts'
PROBE_URL = 'https://www.gstatic.com/generate_204'


def setup():
    HOME.mkdir(parents=True, exist_ok=True)
    os.chmod(HOME, 0o700)
    legacy = Path('/private/tmp/ferdinand-router')
    for source, target in ((legacy / 'router_rsa', SSH_KEY), (legacy / 'known_hosts', KNOWN_HOSTS)):
        if not target.exists() and source.exists():
            shutil.copy2(source, target)
            os.chmod(target, 0o600)
    if not SSH_KEY.exists() or not KNOWN_HOSTS.exists():
        raise RuntimeError('Router SSH anahtarı bulunamadı. Kurulum dosyalarını kontrol edin.')


def ssh(command, stdin=None, timeout=60):
    setup()
    args = ['/usr/bin/ssh', '-i', str(SSH_KEY), '-o', 'BatchMode=yes',
            '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=yes',
            '-o', f'UserKnownHostsFile={KNOWN_HOSTS}', f'root@{HOST}', command]
    result = subprocess.run(args, input=stdin, capture_output=True, timeout=timeout)
    if result.returncode:
        message = result.stderr.decode('utf-8', 'replace').strip()
        raise RuntimeError(message or f'Router komutu başarısız ({result.returncode})')
    return result.stdout


def emit(value):
    print(json.dumps(value, ensure_ascii=False, separators=(',', ':')))


def fetch_subscription(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname:
        raise ValueError('Abonelik adresi https:// ile başlamalı.')
    request = urllib.request.Request(url, headers={'User-Agent': 'HappRouter/1.0'})
    with urllib.request.urlopen(request, timeout=20) as response:
        raw = response.read(512 * 1024 + 1)
    if len(raw) > 512 * 1024:
        raise ValueError('Abonelik yanıtı çok büyük.')
    text = raw.decode('utf-8', 'replace').strip()
    if not text.startswith('vless://'):
        try:
            text = base64.b64decode(text + '=' * (-len(text) % 4), validate=True).decode('utf-8')
        except (ValueError, UnicodeError) as exc:
            raise ValueError('Abonelik VLESS bağlantı listesi içermiyor.') from exc
    return text


def parse_subscription(text):
    nodes = []
    outbounds = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith('vless://'):
            continue
        uri = urllib.parse.urlsplit(line)
        q = urllib.parse.parse_qs(uri.query, keep_blank_values=True)
        first = lambda key, default='': q.get(key, [default])[0]
        if first('type') != 'ws' or first('security') != 'tls':
            continue
        if not uri.hostname or not uri.port or not uri.username:
            continue
        tag = f'node-{len(nodes):02d}'
        name = urllib.parse.unquote(uri.fragment) or tag
        tls = {'serverName': first('sni', uri.hostname), 'allowInsecure': False}
        if first('alpn'):
            tls['alpn'] = first('alpn').split(',')
        if first('fp'):
            tls['fingerprint'] = first('fp')
        ws = {'path': first('path', '/')}
        if first('host'):
            ws['headers'] = {'Host': first('host')}
        outbounds.append({
            'tag': tag, 'protocol': 'vless',
            'settings': {'vnext': [{'address': uri.hostname, 'port': uri.port,
                                    'users': [{'id': urllib.parse.unquote(uri.username), 'encryption': 'none'}]}]},
            'streamSettings': {'network': 'ws', 'security': 'tls',
                               'tlsSettings': tls, 'wsSettings': ws},
        })
        nodes.append({'tag': tag, 'name': name, 'address': uri.hostname,
                      'country': name[:2] if name[:1] in ('🇹', '🇪', '🇵', '🇫', '🇷') else ''})
    if not nodes:
        raise ValueError('Desteklenen VLESS WebSocket/TLS profili bulunamadı.')
    return nodes, outbounds


def build_config(base, outbounds):
    fallback = next((item for item in base.get('outbounds', []) if item.get('tag') == 'happ-vpn'), None)
    if not fallback:
        raise ValueError('Çalışan Happ VPN yedek profili bulunamadı; mevcut bağlantı korunuyor.')
    config = dict(base)
    config['inbounds'] = list(base.get('inbounds', [])) + [
        {'tag': 'metrics-in', 'listen': '127.0.0.1', 'port': 11111,
         'protocol': 'dokodemo-door',
         'settings': {'address': '127.0.0.1', 'port': 11111, 'network': 'tcp'}}]
    config['outbounds'] = [fallback] + outbounds
    config['observatory'] = {'subjectSelector': ['node-'], 'probeUrl': PROBE_URL,
                             'probeInterval': '2m', 'enableConcurrency': False}
    config['routing'] = {
        'domainStrategy': 'AsIs',
        'balancers': [{'tag': 'best', 'selector': ['node-'],
                       'fallbackTag': 'happ-vpn', 'strategy': {'type': 'leastPing'}}],
        'rules': [
            {'type': 'field', 'inboundTag': ['metrics-in'], 'outboundTag': 'Metrics'},
            {'type': 'field', 'inboundTag': ['socks', 'tproxy', 'dns-in'],
             'outboundTag': 'happ-vpn'}],
    }
    config['metrics'] = {'tag': 'Metrics'}
    config['stats'] = {}
    config['policy'] = {'system': {'statsInboundUplink': True, 'statsInboundDownlink': True,
                                   'statsOutboundUplink': True, 'statsOutboundDownlink': True}}
    config['log'] = {'loglevel': 'warning'}
    return config


def node_preview(url):
    nodes, outbounds = parse_subscription(fetch_subscription(url))
    emit({'ok': True, 'count': len(nodes), 'nodes': nodes,
          'note': 'Bağlantı adresleri okundu. Gerçek ms testi router tarafından yapılır.'})
    return nodes, outbounds


def install_subscription(url, expires_at):
    if not isinstance(expires_at, int) or expires_at < int(time.time()):
        raise ValueError('Gelecekteki abonelik bitiş tarihini seçin.')
    nodes, outbounds = parse_subscription(fetch_subscription(url))
    base = json.loads(ssh('cat /etc/xray/config.json').decode('utf-8'))
    candidate = build_config(base, outbounds)
    validator = Path(__file__).parent / 'xray-validator'
    if not validator.exists():
        validator = Path(__file__).parent.parent / 'Tools' / 'xray-validator'
    if not validator.exists():
        raise RuntimeError('Xray doğrulama aracı bulunamadı; çalışan yapılandırma korunuyor.')
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', prefix='happvpn-', delete=True) as file:
        os.chmod(file.name, 0o600)
        json.dump(candidate, file, ensure_ascii=False)
        file.flush()
        validation = subprocess.run([str(validator), 'run', '-test', '-config', file.name,
                                     '-format', 'json'], capture_output=True, timeout=30)
        if validation.returncode:
            raise RuntimeError('Xray yapılandırması geçersiz; çalışan bağlantı korunuyor.')
    ssh('umask 077; cat > /tmp/happvpn-candidate.json',
        stdin=json.dumps(candidate, ensure_ascii=False).encode('utf-8'))
    ssh('umask 077; cat > /tmp/happvpn-nodes.json',
        stdin=json.dumps(nodes, ensure_ascii=False).encode('utf-8'))
    ssh('umask 077; cat > /tmp/happvpn-subscription-url', stdin=url.encode('utf-8'))
    ssh('umask 077; cat > /tmp/happvpn-expires-at', stdin=str(expires_at).encode('ascii'))
    # The matching macOS Xray build validates without consuming the router's RAM.
    ssh('cp /etc/xray/config.json /etc/xray/config.json.last-good && '
        'cp /tmp/happvpn-candidate.json /etc/xray/config.json && chmod 600 /etc/xray/config.json && '
        'cp /tmp/happvpn-nodes.json /etc/happvpn/nodes.json && chmod 600 /etc/happvpn/nodes.json && '
        'cp /tmp/happvpn-subscription-url /etc/happvpn/subscription-url && chmod 600 /etc/happvpn/subscription-url && '
        'cp /tmp/happvpn-expires-at /etc/happvpn/expires-at && chmod 600 /etc/happvpn/expires-at && '
        '([ ! -x /etc/happvpn/mode.sh ] || /etc/happvpn/mode.sh vpn) && '
        '/etc/init.d/xray restart', timeout=45)
    emit({'ok': True, 'count': len(nodes), 'note': 'Abonelik kuruldu; Xray yeniden başlıyor.'})


def status():
    command = '''printf '__NETDEV__\\n'; cat /proc/net/dev; printf '\\n__LEASES__\\n'; cat /tmp/dhcp.leases 2>/dev/null; printf '\\n__STATIONS__\\n'; iw dev phy0-ap0 station dump 2>/dev/null; printf '\\n__NEIGH__\\n'; ip neigh show dev br-lan; printf '\\n__METRICS__\\n'; timeout 3 wget -qO- http://127.0.0.1:11111/debug/vars 2>/dev/null; printf '\\n__NODES__\\n'; cat /etc/happvpn/nodes.json 2>/dev/null; printf '\\n__SYSTEM__\\n'; cat /proc/uptime; netstat -lnt | grep -q ':1080 ' && echo ready || echo starting; cat /etc/happvpn/expires-at 2>/dev/null || echo 0; cat /etc/happvpn/mode 2>/dev/null || echo vpn'''
    raw = ssh(command, timeout=35).decode('utf-8', 'replace')
    sections = {}
    for part in re.split(r'__(NETDEV|LEASES|STATIONS|NEIGH|METRICS|NODES|SYSTEM)__\n', raw)[1:]:
        pass
    pieces = re.split(r'__(NETDEV|LEASES|STATIONS|NEIGH|METRICS|NODES|SYSTEM)__\n', raw)
    for index in range(1, len(pieces) - 1, 2):
        sections[pieces[index]] = pieces[index + 1].strip()
    netdev = {}
    for line in sections.get('NETDEV', '').splitlines():
        if ':' not in line:
            continue
        name, numbers = line.split(':', 1)
        columns = numbers.split()
        if len(columns) >= 9:
            netdev[name.strip()] = {'rx': int(columns[0]), 'tx': int(columns[8])}
    lease_by_mac = {}
    for line in sections.get('LEASES', '').splitlines():
        columns = line.split()
        if len(columns) >= 4:
            lease_by_mac[columns[1].lower()] = {'ip': columns[2], 'name': columns[3]}
    devices = []
    for station in re.split(r'(?=^Station )', sections.get('STATIONS', ''), flags=re.M):
        match = re.search(r'^Station ([0-9a-f:]+)', station, re.M)
        if not match:
            continue
        mac = match.group(1).lower()
        item = {'mac': mac, 'type': 'Wi-Fi', **lease_by_mac.get(mac, {})}
        for field, label in (('rx bytes', 'uploaded'), ('tx bytes', 'downloaded')):
            number = re.search(rf'^\s*{re.escape(field)}:\s*(\d+)', station, re.M)
            item[label] = int(number.group(1)) if number else 0
        devices.append(item)
    for line in sections.get('NEIGH', '').splitlines():
        match = re.search(r'^(\S+) dev br-lan lladdr ([0-9a-f:]+)', line)
        if match and not any(item.get('ip') == match.group(1) for item in devices):
            mac = match.group(2).lower()
            devices.append({'mac': mac, 'ip': match.group(1), 'type': 'Kablo',
                            'name': lease_by_mac.get(mac, {}).get('name', '')})
    try:
        metrics = json.loads(sections.get('METRICS') or '{}')
    except json.JSONDecodeError:
        metrics = {}
    try:
        nodes = json.loads(sections.get('NODES') or '[]')
    except json.JSONDecodeError:
        nodes = []
    observations = metrics.get('observatory', {})
    for node in nodes:
        observation = observations.get(node['tag'], {})
        node['alive'] = observation.get('alive')
        node['delay'] = observation.get('delay') if observation.get('alive') else None
        node['lastTry'] = observation.get('last_try_time')
    healthy = [node for node in nodes if node.get('alive') and isinstance(node.get('delay'), (int, float))]
    best = min(healthy, key=lambda node: node['delay']) if healthy else None
    stats = metrics.get('stats', {}).get('inbound', {}).get('tproxy', {})
    vpn_bytes = ({'rx': stats.get('downlink', 0), 'tx': stats.get('uplink', 0)}
                 if metrics else None)
    system = sections.get('SYSTEM', '').splitlines()
    emit({'ok': True, 'vpnRunning': len(system) >= 2 and system[1].strip() == 'ready',
          'uptimeSeconds': float(system[0].split()[0]) if system else 0,
          'wifi': netdev.get('phy0-ap0', {}), 'wan': netdev.get('eth0.2', {}),
          'vpnBytes': vpn_bytes, 'devices': devices, 'nodes': nodes,
          'best': best['tag'] if best else 'happ-vpn',
          'fallback': best is None, 'metricsAvailable': bool(metrics),
          'expiresAt': int(system[2]) if len(system) >= 3 and system[2].isdigit() else 0,
          'mode': system[3] if len(system) >= 4 else 'vpn',
          'updatedAt': int(time.time())})


def set_expiry(expires_at):
    if not isinstance(expires_at, int) or expires_at < int(time.time()):
        raise ValueError('Gelecekteki abonelik bitiş tarihini seçin.')
    ssh('umask 077; cat > /etc/happvpn/expires-at', stdin=str(expires_at).encode('ascii'))
    emit({'ok': True, 'note': 'Abonelik bitiş tarihi kaydedildi.'})


def active_test():
    # A tunnel through the router's SOCKS listener verifies the real VPN exit.
    setup()
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        local_port = reservation.getsockname()[1]
    ssh_args = ['/usr/bin/ssh', '-i', str(SSH_KEY), '-o', 'BatchMode=yes',
                '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=yes',
                '-o', f'UserKnownHostsFile={KNOWN_HOSTS}', '-N',
                '-L', f'{local_port}:127.0.0.1:1080', f'root@{HOST}']
    proc = subprocess.Popen(ssh_args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        deadline = time.monotonic() + 30
        while True:
            if proc.poll() is not None:
                raise RuntimeError('SSH tüneli açılamadı.')
            try:
                s = socket.create_connection(('127.0.0.1', local_port), timeout=2)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise RuntimeError('SSH tüneli zaman aşımına uğradı.')
                time.sleep(0.5)
        s.settimeout(12)
        s.sendall(b'\x05\x01\x00')
        if s.recv(2) != b'\x05\x00':
            raise RuntimeError('Router SOCKS bağlantısı kurulamadı.')
        host = b'ifconfig.me'
        s.sendall(b'\x05\x01\x00\x03' + bytes([len(host)]) + host + b'\x01\xbb')
        answer = s.recv(10)
        if len(answer) < 2 or answer[1] != 0:
            raise RuntimeError('VPN sunucusuna bağlanılamadı.')
        secure = ssl.create_default_context().wrap_socket(s, server_hostname='ifconfig.me')
        secure.sendall(b'GET /ip HTTP/1.0\r\nHost: ifconfig.me\r\nConnection: close\r\n\r\n')
        data = bytearray()
        while len(data) < 32768:
            chunk = secure.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
        secure.close()
        body = bytes(data).split(b'\r\n\r\n', 1)[-1].decode('utf-8', 'replace').strip()
        if not re.fullmatch(r'\d{1,3}(?:\.\d{1,3}){3}', body):
            raise RuntimeError('VPN çıkış IP yanıtı geçersiz.')
        emit({'ok': True, 'exitIP': body})
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['status', 'preview', 'test', 'apply', 'expiry'])
    parser.add_argument('--url')
    parser.add_argument('--expires', type=int)
    args = parser.parse_args()
    try:
        if args.command == 'status':
            status()
        elif args.command in ('preview', 'apply'):
            url = sys.stdin.read().strip() if args.url == '-' else args.url
            if not url:
                raise ValueError('Abonelik adresini girin.')
            if args.command == 'preview':
                node_preview(url)
            else:
                install_subscription(url, args.expires)
        elif args.command == 'test':
            active_test()
        elif args.command == 'expiry':
            set_expiry(args.expires)
    except Exception as exc:
        emit({'ok': False, 'error': str(exc)})
        sys.exit(1)


if __name__ == '__main__':
    main()
