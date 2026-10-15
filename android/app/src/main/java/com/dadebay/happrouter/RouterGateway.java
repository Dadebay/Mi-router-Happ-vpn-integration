package com.dadebay.happrouter;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

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
        boolean vpnRunning;
        RouterMetrics metrics;
        final List<SavedNode> nodes = new ArrayList<>();
    }

    static final class Candidate {
        final VpnProfile profile;
        final String exitIp;
        Candidate(VpnProfile profile, String exitIp) {
            this.profile = profile;
            this.exitIp = exitIp;
        }
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
            value.metrics = RouterMetrics.parse(ssh.exec(RouterMetrics.command(), 40));
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
                String tag = node.optString("tag");
                value.nodes.add(new SavedNode(tag, node.optString("name"),
                        value.metrics.delays.get(tag),
                        value.metrics.unavailableNodes.contains(tag) ? false
                                : value.metrics.delays.containsKey(tag) ? true : null));
            }
            value.vpnRunning = "ready".equals(ssh.exec("if netstat -lnt | grep -q ':1080 ' "
                    + "&& netstat -lnt | grep -q ':12345 '; then echo ready; else echo starting; fi", 15));
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
                throw new Exception(context.getString(R.string.server_no_internet), error);
            } finally {
                try { ssh.exec("if [ -s /tmp/happ-mobile-probe.pid ]; then "
                        + "kill $(cat /tmp/happ-mobile-probe.pid) 2>/dev/null || true; fi; "
                        + "rm -f /tmp/happ-mobile-probe.json /tmp/happ-mobile-probe.pid "
                        + "/tmp/happ-mobile-probe.log", 15); }
                catch (Exception ignored) { }
            }
        }
    }

    Candidate bestCandidate(List<VpnProfile> profiles) throws Exception {
        if (profiles.isEmpty()) throw new IllegalArgumentException(context.getString(R.string.servers_empty));
        List<VpnProfile> ranked = new ArrayList<>();
        if (profiles.size() == 1) ranked.add(profiles.get(0));
        else {
            StringBuilder input = new StringBuilder();
            Map<String, VpnProfile> byTag = new HashMap<>();
            for (VpnProfile profile : profiles) {
                input.append(profile.tag).append('\t').append(profile.server).append('\t')
                        .append(profile.port).append('\n');
                byTag.put(profile.tag, profile);
            }
            Map<VpnProfile, Integer> delays = new HashMap<>();
            try (RouterSsh ssh = new RouterSsh(context, identity)) {
                ssh.write("/tmp/happ-mobile-probes.tsv", bytes(input.toString()));
                ssh.write("/tmp/happ-mobile-probes.lua", readAsset("probe-nodes.lua"));
                try {
                    String result = ssh.exec("lua5.3 /tmp/happ-mobile-probes.lua "
                            + "/tmp/happ-mobile-probes.tsv /tmp/happ-mobile-probes.results "
                            + "&& cat /tmp/happ-mobile-probes.results",
                            Math.max(30, Math.min(450, profiles.size() * 3 + 10)));
                    for (String line : result.split("\\n")) {
                        String[] parts = line.split("\\t");
                        if (parts.length < 3 || !"1".equals(parts[1])) continue;
                        VpnProfile profile = byTag.get(parts[0]);
                        if (profile == null) continue;
                        try { delays.put(profile, Integer.parseInt(parts[2])); }
                        catch (NumberFormatException ignored) { }
                    }
                } finally {
                    try { ssh.exec("rm -f /tmp/happ-mobile-probes.tsv "
                            + "/tmp/happ-mobile-probes.lua /tmp/happ-mobile-probes.results "
                            + "/tmp/happ-mobile-probes.results.tmp", 10); }
                    catch (Exception ignored) { }
                }
            }
            ranked.addAll(delays.keySet());
            ranked.sort(Comparator.comparingInt(delays::get));
        }
        if (ranked.isEmpty()) throw new Exception(context.getString(R.string.servers_unreachable));
        for (VpnProfile profile : ranked) {
            try { return new Candidate(profile, testCandidate(profile)); }
            catch (Exception ignored) { /* Try the next reachable server. */ }
        }
        throw new Exception(context.getString(R.string.vpn_exit_unverified));
    }

    String install(List<VpnProfile> profiles, String selectedTag, long expiry) throws Exception {
        if (profiles.isEmpty() || profiles.size() > 200 || !selectedTag.matches("ss-[0-9]{2,3}"))
            throw new IllegalArgumentException(context.getString(R.string.selection_invalid));
        if (expiry <= System.currentTimeMillis() / 1000)
            throw new IllegalArgumentException(context.getString(R.string.expiry_future));
        boolean found = false;
        for (VpnProfile node : profiles) if (node.tag.equals(selectedTag)) found = true;
        if (!found) throw new IllegalArgumentException(context.getString(R.string.selected_missing));
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
                throw new Exception(context.getString(R.string.install_unverified), error);
            } finally {
                try { ssh.exec("rm -f /tmp/happ-mobile-apply.sh", 15); }
                catch (Exception ignored) { }
            }
        }
    }

    void select(String tag) throws Exception {
        if (!tag.matches("ss-[0-9]{2,3}")) throw new IllegalArgumentException(context.getString(R.string.selection_invalid));
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.exec("/etc/happvpn/switch-node.sh manual " + tag, 180);
        }
    }

    void automatic() throws Exception {
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.exec("/etc/happvpn/switch-node.sh enable-auto", 180);
        }
    }

    void setMode(String mode) throws Exception {
        if (!mode.equals("vpn") && !mode.equals("direct"))
            throw new IllegalArgumentException(context.getString(R.string.mode_invalid));
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            if (mode.equals("vpn")) {
                long expiry = Long.parseLong(ssh.exec("cat /etc/happvpn/expires-at", 15));
                if (expiry <= System.currentTimeMillis() / 1000)
                    throw new Exception(context.getString(R.string.subscription_expired));
                ssh.exec("/etc/happvpn/node-helper.lua check 1080", 30);
            }
            ssh.exec("/etc/happvpn/mode.sh " + mode, 45);
        }
    }

    void setDeviceBlocked(String mac, boolean blocked) throws Exception {
        if (mac == null || !mac.matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}"))
            throw new IllegalArgumentException(context.getString(R.string.mac_invalid));
        try (RouterSsh ssh = new RouterSsh(context, identity)) {
            ssh.write("/tmp/happ-mobile-block.sh", readAsset("mobile-block.sh"));
            try {
                ssh.exec("chmod 700 /tmp/happ-mobile-block.sh && /tmp/happ-mobile-block.sh "
                        + mac.toLowerCase(java.util.Locale.ROOT) + " "
                        + (blocked ? "block" : "unblock"), 60);
            } finally {
                try { ssh.exec("rm -f /tmp/happ-mobile-block.sh", 10); }
                catch (Exception ignored) { }
            }
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
