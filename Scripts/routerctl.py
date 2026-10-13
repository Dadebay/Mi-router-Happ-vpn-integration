#!/usr/bin/env python3
"""Local SSH controller for the Xiaomi 4C Shadowsocks VPN gateway.

Never prints subscription URLs or proxy credentials. A new server is tested on
a separate listener before it replaces the saved working configuration.
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
import time
import urllib.parse
import urllib.request
from pathlib import Path

HOME = Path.home() / '.happ-router'
HOST = '192.168.1.1'
SSH_KEY = HOME / 'router_rsa'
KNOWN_HOSTS = HOME / 'known_hosts'
ROUTER_SCRIPTS = ('mode.sh', 'expiry-check.sh', 'probe-nodes.lua', 'usage-sample.lua',
                  'dns-relay.lua')
SUPPORTED_CIPHERS = frozenset({
    'aes-128-gcm', 'aes-192-gcm', 'aes-256-gcm', 'chacha20-ietf-poly1305',
    'xchacha20-ietf-poly1305', 'aes-128-cfb', 'aes-192-cfb', 'aes-256-cfb',
    'aes-128-ctr', 'aes-192-ctr', 'aes-256-ctr', 'chacha20-ietf', 'salsa20',
})
CRON_ENTRIES = (
    '*/5 * * * * /etc/happvpn/expiry-check.sh',
    '* * * * * /etc/happvpn/usage-sample.lua',
    '*/30 * * * * /etc/happvpn/probe-nodes.lua',
)


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


def script_directory():
    bundled = Path(__file__).parent / 'RouterScripts'
    return bundled if bundled.is_dir() else Path(__file__).parent


def install_helpers():
    board = json.loads(ssh('ubus call system board').decode('utf-8'))
    if board.get('board_name') != 'xiaomi,mi-router-4c':
        raise RuntimeError('Bu kurulum yalnızca Xiaomi Mi Router 4C için hazırlanmıştır.')
    requirements = ssh("for cmd in ss-local ss-redir lua5.3 nft iw uci; do command -v \"$cmd\" >/dev/null || echo \"$cmd\"; done; "
                       "lua5.3 -e 'require(\"socket\")' >/dev/null 2>&1 || echo lua-socket; "
                       "test -s /etc/happvpn/ss-client.json || echo ss-client-config; "
                       "test -s /etc/nftables.d/happvpn.nft || echo vpn-firewall",
                       timeout=20).decode('utf-8').splitlines()
    if requirements:
        raise RuntimeError('Router hazırlığı eksik: ' + ', '.join(requirements) +
                           '. OpenWrt/Shadowsocks temel kurulumu gerekli; çalışan ağ ayarları değiştirilmedi.')
    source = script_directory()
    missing = [name for name in (*ROUTER_SCRIPTS, 'happ-ss.init', 'happ-ss.nft')
               if not (source / name).is_file()]
    if missing:
        raise RuntimeError('Uygulama kurulum dosyaları eksik: ' + ', '.join(missing))
    ssh('umask 077; mkdir -p /etc/happvpn; test -d /etc/happvpn', timeout=20)
    for name in ROUTER_SCRIPTS:
        content = (source / name).read_bytes()
        ssh(f'umask 077; cat > /etc/happvpn/.{name}.new && '
            f'chmod 755 /etc/happvpn/.{name}.new && '
            f'mv /etc/happvpn/.{name}.new /etc/happvpn/{name}',
            stdin=content, timeout=20)
    ssh('umask 077; cat > /etc/happvpn/happvpn.nft.vpn.ss && '
        'chmod 600 /etc/happvpn/happvpn.nft.vpn.ss',
        stdin=(source / 'happ-ss.nft').read_bytes(), timeout=20)
    ssh('umask 077; cat > /etc/init.d/happ-ss && chmod 755 /etc/init.d/happ-ss && '
        '/etc/init.d/happ-ss enable',
        stdin=(source / 'happ-ss.init').read_bytes(), timeout=20)
    # Keep user-defined cron jobs and replace only the entries owned by HappRouter.
    existing = ssh('crontab -l 2>/dev/null || true', timeout=20).decode('utf-8').splitlines()
    retained = [line for line in existing if not any('/etc/happvpn/' + name in line
                for name in ROUTER_SCRIPTS)]
    cron = '\n'.join(retained + list(CRON_ENTRIES)) + '\n'
    ssh('umask 077; cat > /tmp/happvpn-cron.new && '
        'crontab /tmp/happvpn-cron.new && rm /tmp/happvpn-cron.new && '
        '/etc/init.d/cron enable && /etc/init.d/cron restart',
        stdin=cron.encode('utf-8'), timeout=30)
    # Direct mode stays active until a real VPN exit test succeeds.
    emit({'ok': True, 'note': 'Router yardımcıları ve ölçüm görevleri kuruldu. '
          'Yeni sunucuyu eklemeden önce profili kontrol edin.'})


def diagnostics():
    command = ("printf '== Sistem ==\\n'; ubus call system board | grep -E 'model|version' | head -n 3; "
               "printf '\\n== Mod / Shadowsocks ==\\n'; cat /etc/happvpn/mode 2>/dev/null || true; "
               "printf '\\n'; netstat -lnt 2>/dev/null | grep -E ':1080 |:12345 ' || true; "
               "printf '\\n== Son VPN olayları ==\\n'; "
               "logread 2>/dev/null | grep -E 'ss-local|ss-redir|happ-ss|happvpn:' | tail -n 35")
    output = ssh(command, timeout=25).decode('utf-8', 'replace')[-12000:]
    output = re.sub(r'https?://[^\s]+', '[adres gizlendi]', output)
    output = re.sub(r'\b[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}\b', '[kimlik gizlendi]', output)
    emit({'ok': True, 'logs': output})


def fetch_subscription(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname:
        raise ValueError('Abonelik adresi https:// ile başlamalı.')
    request = urllib.request.Request(url, headers={'User-Agent': 'HappRouter/1.0'})
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read(512 * 1024 + 1)
    except Exception as exc:
        raise RuntimeError('Abonelik adresi okunamadı. İnternet bağlantısını kontrol edin.') from exc
    if len(raw) > 512 * 1024:
        raise ValueError('Abonelik yanıtı çok büyük.')
    text = raw.decode('utf-8', 'replace').strip()
    if not any(line.strip().startswith(('ss://', 'vless://')) for line in text.splitlines()):
        try:
            compact = ''.join(text.split())
            decoded = base64.b64decode(compact + '=' * (-len(compact) % 4),
                                       altchars=b'-_', validate=True).decode('utf-8')
            if '://' in decoded:
                text = decoded
        except (ValueError, UnicodeError):
            pass
    return text


def _base64_text(value):
    try:
        return base64.b64decode(value + '=' * (-len(value) % 4),
                                altchars=b'-_', validate=True).decode('utf-8')
    except (ValueError, UnicodeError) as exc:
        raise ValueError('Shadowsocks bağlantı biçimi geçersiz.') from exc


def _validated_server(address, port, method, password):
    if not isinstance(address, str) or not re.fullmatch(r'[A-Za-z0-9.:-]{1,253}', address):
        raise ValueError('Sunucu adresi geçersiz.')
    if address in ('0.0.0.0', '127.0.0.1', '::1'):
        raise ValueError('Yerel adres VPN sunucusu olamaz.')
    if type(port) is not int or not 1 <= port <= 65535:
        raise ValueError('Sunucu portu geçersiz.')
    if method not in SUPPORTED_CIPHERS:
        raise ValueError('Bu Shadowsocks şifreleme yöntemi router tarafından desteklenmiyor.')
    if not isinstance(password, str) or not 1 <= len(password) <= 512:
        raise ValueError('Sunucu parolası geçersiz.')
    return {'server': address, 'server_port': port, 'password': password,
            'method': method, 'local_address': '127.0.0.1', 'local_port': 1080,
            'timeout': 30}


def _parse_ss_uri(value):
    if not value.startswith('ss://'):
        raise ValueError('Shadowsocks bağlantısı ss:// ile başlamalı.')
    body, _, fragment = value[5:].partition('#')
    authority, _, query = body.partition('?')
    if urllib.parse.parse_qs(query).get('plugin'):
        raise ValueError('Eklenti kullanan Shadowsocks sunucusu desteklenmiyor.')
    if '@' not in authority:
        authority = _base64_text(authority)
    if '@' not in authority:
        raise ValueError('Shadowsocks bağlantı biçimi geçersiz.')
    credentials, host_port = authority.rsplit('@', 1)
    credentials = urllib.parse.unquote(credentials)
    if ':' not in credentials:
        credentials = _base64_text(credentials)
    if ':' not in credentials:
        raise ValueError('Shadowsocks kimlik bilgileri geçersiz.')
    method, password = credentials.split(':', 1)
    host = urllib.parse.urlsplit('ss://' + host_port)
    try:
        port = host.port
    except ValueError as exc:
        raise ValueError('Shadowsocks portu geçersiz.') from exc
    config = _validated_server(host.hostname, port, method, password)
    name = urllib.parse.unquote(fragment) or host.hostname
    return name, config


def parse_profiles(source):
    source = source.strip()
    if len(source) > 512 * 1024:
        raise ValueError('Profil çok büyük.')
    if source.startswith('happ://'):
        raise ValueError('Şifreli Happ bağlantısını router açamıyor. Happ içinden "Copy Server JSON" ile sunucuyu kopyalayın.')
    if source.startswith('https://'):
        source = fetch_subscription(source)
    entries = []
    if source.startswith('{'):
        try:
            document = json.loads(source)
        except json.JSONDecodeError as exc:
            raise ValueError('Sunucu JSON biçimi geçersiz.') from exc
        if not isinstance(document, dict):
            raise ValueError('Sunucu JSON biçimi geçersiz.')
        remarks = document.get('remarks')
        for outbound in document.get('outbounds', []):
            if not isinstance(outbound, dict) or outbound.get('protocol') != 'shadowsocks':
                continue
            for server in outbound.get('settings', {}).get('servers', []):
                if not isinstance(server, dict):
                    continue
                config = _validated_server(server.get('address'), server.get('port'),
                                           server.get('method'), server.get('password'))
                entries.append((remarks if isinstance(remarks, str) else 'Happ sunucusu', config))
    else:
        for line in source.splitlines():
            line = line.strip()
            if line.startswith('ss://'):
                entries.append(_parse_ss_uri(line))
    if not entries:
        raise ValueError('Desteklenen Shadowsocks sunucusu bulunamadı. Happ içinden "Copy Server JSON" kullanın.')
    if len(entries) > 200:
        raise ValueError('Profil listesi çok büyük.')
    profiles = []
    for index, (name, config) in enumerate(entries):
        clean_name = re.sub(r'[\x00-\x1f\x7f]+', ' ', name).strip()[:80] or 'Happ sunucusu'
        node = {'tag': f'ss-{index:02d}', 'name': clean_name,
                'address': config['server'], 'port': config['server_port'], 'country': ''}
        profiles.append((node, config))
    return profiles


def node_preview(source):
    profiles = parse_profiles(source)
    emit({'ok': True, 'count': len(profiles), 'nodes': [node for node, _ in profiles],
          'note': 'Sunucu profilleri okundu. Gerçek VPN testi kurulumdan önce yapılır.'})


def _cleanup_candidate():
    try:
        ssh('rm -f /tmp/happ-ss-candidate.json /tmp/happ-ss-candidate.log', timeout=15)
    except Exception:
        pass


def install_profile(source, expires_at, selected_tag=None):
    if not isinstance(expires_at, int) or expires_at < int(time.time()):
        raise ValueError('Gelecekteki abonelik bitiş tarihini seçin.')
    profiles = parse_profiles(source)
    if len(profiles) > 1 and not selected_tag:
        raise ValueError('Kurulacak sunucuyu listeden seçin.')
    chosen = next(((node, config) for node, config in profiles
                   if node['tag'] == (selected_tag or 'ss-00')), None)
    if not chosen:
        raise ValueError('Seçilen sunucu bu profilde bulunamadı.')
    node, config = chosen
    ssh('umask 077; cat > /tmp/happ-ss-candidate.json',
        stdin=json.dumps(config, ensure_ascii=False).encode('utf-8'))
    # Probe the new server without interrupting the working listener or clients.
    try:
        ssh('ss-local -c /tmp/happ-ss-candidate.json -b 127.0.0.1 -l 11082 '
            '-f /tmp/happ-ss-candidate.pid >/tmp/happ-ss-candidate.log 2>&1', timeout=15)
        active_test(emit_result=False, remote_port=11082)
    except Exception as exc:
        _cleanup_candidate()
        raise RuntimeError('Yeni sunucunun VPN çıkışı doğrulanamadı; çalışan profil korundu.') from exc
    finally:
        ssh('if [ -s /tmp/happ-ss-candidate.pid ]; then '
            'kill $(cat /tmp/happ-ss-candidate.pid) 2>/dev/null || true; '
            'rm -f /tmp/happ-ss-candidate.pid; fi', timeout=15)
    ssh('cp /etc/happvpn/ss-client.json /etc/happvpn/ss-client.json.last-good')
    try:
        ssh('cp /tmp/happ-ss-candidate.json /etc/happvpn/ss-client.json && '
            'chmod 600 /etc/happvpn/ss-client.json && '
            '/etc/init.d/happ-ss restart', timeout=30)
        exit_ip = active_test(emit_result=False)
    except Exception as exc:
        ssh('cp /etc/happvpn/ss-client.json.last-good /etc/happvpn/ss-client.json && '
            '/etc/init.d/happ-ss restart', timeout=30)
        _cleanup_candidate()
        raise RuntimeError('Yeni profil açılamadı; önceki çalışan profil geri yüklendi.') from exc
    nodes = [item for item, _ in profiles]
    probes = ''.join(f"{item['tag']}\t{item['address']}\t{item['port']}\n"
                     for item in nodes)
    ssh('umask 077; cat > /etc/happvpn/nodes.json',
        stdin=json.dumps(nodes, ensure_ascii=False).encode('utf-8'))
    ssh('umask 077; cat > /etc/happvpn/probes.tsv', stdin=probes.encode('utf-8'))
    ssh('umask 077; cat > /etc/happvpn/active-outbound', stdin=node['tag'].encode('ascii'))
    ssh('umask 077; cat > /etc/happvpn/expires-at', stdin=str(expires_at).encode('ascii'))
    ssh('/etc/happvpn/mode.sh vpn', timeout=45)
    _cleanup_candidate()
    emit({'ok': True, 'count': len(profiles), 'exitIP': exit_ip,
          'note': 'Yeni sunucu router üzerinde doğrulandı ve kullanıma alındı.'})


def status():
    command = '''printf '__NETDEV__\\n'; cat /proc/net/dev; printf '\\n__LEASES__\\n'; cat /tmp/dhcp.leases 2>/dev/null; printf '\\n__STATIONS__\\n'; iw dev phy0-ap0 station dump 2>/dev/null; printf '\\n__NEIGH__\\n'; ip neigh show dev br-lan; printf '\\n__USAGE__\\n'; cat /tmp/happvpn/usage-today.tsv 2>/dev/null; printf '\\n__PROBES__\\n'; cat /tmp/happvpn/probe-results.tsv 2>/dev/null; printf '\\n__METRICS__\\n'; printf '\\n__NODES__\\n'; cat /etc/happvpn/nodes.json 2>/dev/null; printf '\\n__ACTIVE__\\n'; cat /etc/happvpn/active-outbound 2>/dev/null || echo happ-vpn; printf '\\n__SYSTEM__\\n'; cat /proc/uptime; if netstat -lnt | grep -q ':1080 ' && netstat -lnt | grep -q ':12345 '; then echo ready; else echo starting; fi; cat /etc/happvpn/expires-at 2>/dev/null || echo 0; cat /etc/happvpn/mode 2>/dev/null || echo vpn'''
    raw = ssh(command, timeout=35).decode('utf-8', 'replace')
    sections = {}
    pieces = re.split(r'__(NETDEV|LEASES|STATIONS|NEIGH|USAGE|PROBES|METRICS|NODES|ACTIVE|SYSTEM)__\n', raw)
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
    usage = {}
    for line in sections.get('USAGE', '').splitlines():
        columns = line.split('\t')
        if len(columns) == 4 and re.fullmatch(r'\d{4}-\d{2}-\d{2}', columns[0]):
            try:
                usage[columns[1].lower()] = {'uploadToday': int(columns[2]),
                                             'downloadToday': int(columns[3])}
            except ValueError:
                continue
    for device in devices:
        device.update(usage.get(device['mac'], {}))
    try:
        metrics = json.loads(sections.get('METRICS') or '{}')
    except json.JSONDecodeError:
        metrics = {}
    try:
        nodes = json.loads(sections.get('NODES') or '[]')
    except json.JSONDecodeError:
        nodes = []
    observations = metrics.get('observatory', {})
    tcp_probes = {}
    for line in sections.get('PROBES', '').splitlines():
        columns = line.split('\t')
        if len(columns) == 4 and columns[1] in ('0', '1'):
            try:
                tcp_probes[columns[0]] = {'alive': columns[1] == '1',
                                           'delay': int(columns[2]),
                                           'last_try_time': int(columns[3])}
            except ValueError:
                continue
    for node in nodes:
        observation = observations.get(node['tag'], tcp_probes.get(node['tag'], {}))
        node['alive'] = observation.get('alive')
        node['delay'] = observation.get('delay') if observation.get('alive') else None
        node['lastTry'] = observation.get('last_try_time')
    healthy = [node for node in nodes if node.get('alive') and isinstance(node.get('delay'), (int, float))]
    best = min(healthy, key=lambda node: node['delay']) if healthy else None
    stats = metrics.get('stats', {}).get('inbound', {}).get('tproxy', {})
    vpn_bytes = ({'rx': stats.get('downlink', 0), 'tx': stats.get('uplink', 0)}
                 if metrics else None)
    system = sections.get('SYSTEM', '').splitlines()
    # Router marker files may have no trailing newline; parse fields separately.
    tail = sections.get('SYSTEM', '')
    expiry_match = re.search(r'(?m)^([0-9]{10})(vpn|direct)?$', tail)
    expires_at = int(expiry_match.group(1)) if expiry_match else 0
    mode_match = re.search(r'(vpn|direct)\s*$', tail)
    mode = mode_match.group(1) if mode_match else 'vpn'
    active_outbound = sections.get('ACTIVE', '').strip() or 'happ-vpn'
    emit({'ok': True, 'vpnRunning': len(system) >= 2 and system[1].strip() == 'ready',
          'uptimeSeconds': float(system[0].split()[0]) if system else 0,
          'wifi': netdev.get('phy0-ap0', {}), 'wan': netdev.get('eth0.2', {}),
          'vpnBytes': vpn_bytes, 'devices': devices, 'nodes': nodes,
          'wifiDownloadToday': sum(item['downloadToday'] for item in usage.values()),
          'best': best['tag'] if best else 'happ-vpn',
          'fallback': active_outbound == 'happ-vpn',
          'activeOutbound': active_outbound, 'metricsAvailable': bool(metrics),
          'expiresAt': expires_at,
          'mode': mode,
          'updatedAt': int(time.time())})


def set_expiry(expires_at):
    if not isinstance(expires_at, int) or expires_at < int(time.time()):
        raise ValueError('Gelecekteki abonelik bitiş tarihini seçin.')
    ssh('umask 077; cat > /etc/happvpn/expires-at', stdin=str(expires_at).encode('ascii'))
    emit({'ok': True, 'note': 'Abonelik bitiş tarihi kaydedildi.'})


def set_mode(mode):
    if mode not in ('vpn', 'direct'):
        raise ValueError('Geçersiz internet modu.')
    if mode == 'vpn':
        expires_at = int(ssh('cat /etc/happvpn/expires-at').decode('ascii').strip())
        if int(time.time()) >= expires_at:
            raise ValueError('Abonelik süresi dolmuş. Yeni bitiş tarihini kaydedin.')
        active_test(emit_result=False)
    ssh(f'/etc/happvpn/mode.sh {mode}', timeout=45)
    emit({'ok': True, 'note': 'Router internet modu değiştirildi.', 'mode': mode})


def active_test(emit_result=True, remote_port=1080):
    # A tunnel through the router's SOCKS listener verifies the real VPN exit.
    setup()
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        local_port = reservation.getsockname()[1]
    ssh_args = ['/usr/bin/ssh', '-i', str(SSH_KEY), '-o', 'BatchMode=yes',
                '-o', 'ConnectTimeout=8', '-o', 'StrictHostKeyChecking=yes',
                '-o', f'UserKnownHostsFile={KNOWN_HOSTS}', '-N',
                '-L', f'{local_port}:127.0.0.1:{remote_port}', f'root@{HOST}']
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
        # Keep a bounded timeout for a new endpoint's TLS response.
        s.settimeout(60)
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
        if emit_result:
            emit({'ok': True, 'exitIP': body})
        return body
    except TimeoutError as exc:
        raise RuntimeError('Router üzerindeki VPN 60 saniyede yanıt vermedi.') from exc
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['status', 'preview', 'test', 'apply', 'expiry',
                                            'mode-vpn', 'mode-direct', 'install', 'logs'])
    parser.add_argument('--url')
    parser.add_argument('--expires', type=int)
    parser.add_argument('--tag')
    args = parser.parse_args()
    try:
        if args.command == 'status':
            status()
        elif args.command == 'install':
            install_helpers()
        elif args.command == 'logs':
            diagnostics()
        elif args.command in ('preview', 'apply'):
            url = sys.stdin.read().strip() if args.url == '-' else args.url
            if not url:
                raise ValueError('Abonelik adresini girin.')
            if args.command == 'preview':
                node_preview(url)
            else:
                install_profile(url, args.expires, args.tag)
        elif args.command == 'test':
            active_test()
        elif args.command == 'expiry':
            set_expiry(args.expires)
        elif args.command in ('mode-vpn', 'mode-direct'):
            set_mode(args.command.removeprefix('mode-'))
    except Exception as exc:
        emit({'ok': False, 'error': str(exc)})
        sys.exit(1)


if __name__ == '__main__':
    main()
