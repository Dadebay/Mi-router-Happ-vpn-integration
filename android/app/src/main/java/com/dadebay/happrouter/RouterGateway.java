package com.dadebay.happrouter;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

final class RouterGateway {
    static final class SavedNode {
        final String tag;
        final String name;
        final Integer delay;
        final Boolean alive;

        SavedNode(String tag, String name, Integer delay, Boolean alive) {
            this.tag = tag;
            this.name = name;
            this.delay = delay;
            this.alive = alive;
        }
    }

    static final class Status {
        String mode;
        String active;
        String selection;
        long expiry;
        String exitIp;
        final List<SavedNode> nodes = new ArrayList<>();
    }

    private final Context context;
    private final DeviceIdentity identity;

    RouterGateway(Context context, DeviceIdentity identity) {
        this.context = context;
        this.identity = identity;
    }

    Status status() throws Exception {
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            Status value = new Status();
            value.mode = ssh.exec("cat /etc/happvpn/mode 2>/dev/null || echo vpn", 15);
            value.active = ssh.exec("cat /etc/happvpn/active-outbound 2>/dev/null || true", 15);
            value.selection = ssh.exec("cat /etc/happvpn/selection-mode 2>/dev/null || echo auto", 15);
            String expiry = ssh.exec("cat /etc/happvpn/expires-at 2>/dev/null || echo 0", 15);
            try { value.expiry = Long.parseLong(expiry); } catch (NumberFormatException ignored) { value.expiry = 0; }
            String nodes = ssh.exec("cat /etc/happvpn/nodes.json 2>/dev/null || echo '[]'", 15);
            JSONArray array = new JSONArray(nodes);
            for (int i = 0; i < array.length(); i++) {
                JSONObject node = array.optJSONObject(i);
                if (node == null) continue;
                value.nodes.add(new SavedNode(node.optString("tag"), node.optString("name"), null, null));
            }
            if ("vpn".equals(value.mode)) {
                try { value.exitIp = ssh.exec("/etc/happvpn/node-helper.lua check 1080", 25); }
                catch (Exception ignored) { value.exitIp = null; }
            }
            return value;
        }
    }

    String testCandidate(VpnProfile node) throws Exception {
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.write("/tmp/happ-mobile-probe.json", bytes(node.configJson().toString()));
            try {
                ssh.exec("ss-local -c /tmp/happ-mobile-probe.json -b 127.0.0.1 -l 11084 "
                        + "-f /tmp/happ-mobile-probe.pid >/tmp/happ-mobile-probe.log 2>&1", 20);
                ssh.exec("sleep 1", 5);
                return ssh.exec("/etc/happvpn/node-helper.lua check 11084", 35);
            } catch (Exception error) {
                throw new Exception("Sunucu router üzerinden internete çıkamadı. Mevcut bağlantı değiştirilmedi.", error);
            } finally {
                try { ssh.exec("if [ -s /tmp/happ-mobile-probe.pid ]; then "
                        + "kill $(cat /tmp/happ-mobile-probe.pid) 2>/dev/null || true; fi; "
                        + "rm -f /tmp/happ-mobile-probe.json /tmp/happ-mobile-probe.pid "
                        + "/tmp/happ-mobile-probe.log", 15); }
                catch (Exception ignored) { }
            }
        }
    }

    String install(List<VpnProfile> profiles, String selectedTag, long expiry) throws Exception {
        if (profiles.isEmpty() || profiles.size() > 200 || !selectedTag.matches("ss-[0-9]{2,3}"))
            throw new IllegalArgumentException("Sunucu seçimi geçersiz.");
        if (expiry <= System.currentTimeMillis() / 1000)
            throw new IllegalArgumentException("Gelecekteki abonelik bitiş tarihini seçin.");
        boolean found = false;
        for (VpnProfile node : profiles) if (node.tag.equals(selectedTag)) found = true;
        if (!found) throw new IllegalArgumentException("Seçilen sunucu bulunamadı.");
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.exec("set -e; test -x /etc/happvpn/node-helper.lua; "
                    + "test -x /etc/happvpn/mode.sh; command -v ss-local >/dev/null; "
                    + "rm -rf /etc/happvpn/profiles.mobile-stage; "
                    + "mkdir -p /etc/happvpn/profiles.mobile-stage", 20);
            JSONArray preview = new JSONArray();
            StringBuilder probes = new StringBuilder();
            for (VpnProfile node : profiles) {
                ssh.write("/etc/happvpn/profiles.mobile-stage/" + node.tag + ".json",
                        bytes(node.configJson().toString()));
                preview.put(node.previewJson());
                probes.append(node.tag).append('\t').append(node.server).append('\t')
                        .append(node.port).append('\n');
            }
            ssh.write("/etc/happvpn/nodes.mobile-stage", bytes(preview.toString()));
            ssh.write("/etc/happvpn/probes.mobile-stage", bytes(probes.toString()));
            ssh.write("/etc/happvpn/selected.mobile-stage", bytes(selectedTag));
            ssh.write("/etc/happvpn/expires.mobile-stage", bytes(Long.toString(expiry)));
            ssh.write("/tmp/happ-mobile-apply.sh", readAsset("mobile-apply.sh"));
            ssh.exec("chmod 700 /tmp/happ-mobile-apply.sh", 15);
            try {
                return ssh.exec("/tmp/happ-mobile-apply.sh", 120);
            } catch (Exception error) {
                throw new Exception("Kurulum doğrulanamadı. Router durumunu yenileyip aktif sunucuyu kontrol edin.", error);
            } finally {
                try { ssh.exec("rm -f /tmp/happ-mobile-apply.sh", 15); }
                catch (Exception ignored) { }
            }
        }
    }

    void select(String tag) throws Exception {
        if (!tag.matches("ss-[0-9]{2,3}")) throw new IllegalArgumentException("Sunucu seçimi geçersiz.");
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.exec("/etc/happvpn/switch-node.sh manual " + tag, 180);
        }
    }

    void automatic() throws Exception {
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.exec("/etc/happvpn/switch-node.sh enable-auto", 180);
        }
    }

    private byte[] readAsset(String name) throws Exception {
        try (InputStream input = context.getAssets().open(name);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            return output.toByteArray();
        }
    }

    private static byte[] bytes(String value) {
        return value.getBytes(StandardCharsets.UTF_8);
    }
}
