package com.dadebay.happrouter;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class RouterMetrics {
    static final class Device {
        String mac;
        String name;
        String ip = "";
        String connection = "Wi-Fi";
        long downloaded;
        long uploaded;
        long downloadToday;
        long uploadToday;
        boolean blocked;
    }

    long wifiRx = -1;
    long wifiTx = -1;
    long wanRx = -1;
    long wanTx = -1;
    long wifiDownloadToday = 0;
    long memoryUsed = -1;
    long memoryTotal = -1;
    long uptimeSeconds = -1;
    int cpuPercent = -1;
    final List<Device> devices = new ArrayList<>();
    final Map<String, Integer> delays = new HashMap<>();
    final Set<String> unavailableNodes = new HashSet<>();

    static String command() {
        return "printf '\\n__NETDEV__\\n'; cat /proc/net/dev; "
                + "printf '\\n__LEASES__\\n'; cat /tmp/dhcp.leases 2>/dev/null; "
                + "printf '\\n__STATIONS__\\n'; iw dev phy0-ap0 station dump 2>/dev/null; "
                + "printf '\\n__NEIGH__\\n'; ip neigh show dev br-lan 2>/dev/null; "
                + "printf '\\n__USAGE__\\n'; cat /tmp/happvpn/usage-today.tsv 2>/dev/null; "
                + "printf '\\n__BLOCKED__\\n'; cat /etc/happvpn/blocked-macs 2>/dev/null; "
                + "printf '\\n__PROBES__\\n'; cat /tmp/happvpn/probe-results.tsv 2>/dev/null; "
                + "printf '\\n__UPTIME__\\n'; cat /proc/uptime; "
                + "printf '\\n__MEMINFO__\\n'; cat /proc/meminfo; "
                + "printf '\\n__CPU1__\\n'; head -n 1 /proc/stat; sleep 1; "
                + "printf '\\n__CPU2__\\n'; head -n 1 /proc/stat";
    }

    static RouterMetrics parse(String raw) {
        RouterMetrics result = new RouterMetrics();
        Map<String, String> sections = new HashMap<>();
        String current = null;
        StringBuilder value = new StringBuilder();
        for (String line : raw.split("\\n")) {
            if (line.matches("__[A-Z0-9]+__")) {
                if (current != null) sections.put(current, value.toString());
                current = line.substring(2, line.length() - 2);
                value.setLength(0);
            } else if (current != null) value.append(line).append('\n');
        }
        if (current != null) sections.put(current, value.toString());

        for (String line : section(sections, "NETDEV").split("\\n")) {
            String[] parts = line.split(":", 2);
            if (parts.length != 2) continue;
            String[] columns = parts[1].trim().split("\\s+");
            if (columns.length < 9) continue;
            if (parts[0].trim().equals("phy0-ap0")) {
                result.wifiRx = number(columns[0]);
                result.wifiTx = number(columns[8]);
            } else if (parts[0].trim().equals("eth0.2")) {
                result.wanRx = number(columns[0]);
                result.wanTx = number(columns[8]);
            }
        }

        Map<String, String[]> leases = new HashMap<>();
        for (String line : section(sections, "LEASES").split("\\n")) {
            String[] columns = line.trim().split("\\s+");
            if (columns.length >= 4) leases.put(columns[1].toLowerCase(Locale.ROOT),
                    new String[] {columns[2], columns[3]});
        }
        String stations = section(sections, "STATIONS");
        for (String chunk : stations.split("(?m)(?=^Station )")) {
            Matcher match = Pattern.compile("^Station ([0-9a-fA-F:]{17})").matcher(chunk);
            if (!match.find()) continue;
            String mac = match.group(1).toLowerCase(Locale.ROOT);
            String details = chunk.substring(match.end());
            Device device = new Device();
            device.mac = mac;
            device.name = mac;
            String[] lease = leases.get(mac);
            if (lease != null) {
                device.ip = lease[0];
                if (!lease[1].equals("*")) device.name = lease[1];
            }
            device.uploaded = extract(details, "rx bytes");
            device.downloaded = extract(details, "tx bytes");
            result.devices.add(device);
        }
        Pattern neighbor = Pattern.compile("(?m)^(\\S+) dev br-lan lladdr ([0-9a-fA-F:]{17})");
        Matcher neighbors = neighbor.matcher(section(sections, "NEIGH"));
        while (neighbors.find()) {
            String mac = neighbors.group(2).toLowerCase(Locale.ROOT);
            boolean present = false;
            for (Device device : result.devices) if (device.mac.equals(mac)) present = true;
            if (present) continue;
            Device device = new Device();
            device.mac = mac;
            device.ip = neighbors.group(1);
            device.connection = "Kablo";
            String[] lease = leases.get(mac);
            device.name = lease != null && !lease[1].equals("*") ? lease[1] : mac;
            result.devices.add(device);
        }
        Set<String> blocked = new HashSet<>();
        for (String line : section(sections, "BLOCKED").split("\\n"))
            if (line.trim().matches("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}"))
                blocked.add(line.trim().toLowerCase(Locale.ROOT));
        for (String line : section(sections, "USAGE").split("\\n")) {
            String[] columns = line.split("\\t");
            if (columns.length != 4 || !columns[0].matches("\\d{4}-\\d{2}-\\d{2}")) continue;
            long upload = number(columns[2]);
            long download = number(columns[3]);
            if (upload < 0 || download < 0) continue;
            result.wifiDownloadToday += download;
            for (Device device : result.devices) if (device.mac.equalsIgnoreCase(columns[1])) {
                device.uploadToday = upload;
                device.downloadToday = download;
            }
        }
        for (Device device : result.devices) device.blocked = blocked.contains(device.mac);
        for (String line : section(sections, "PROBES").split("\\n")) {
            String[] columns = line.split("\\t");
            if (columns.length < 3 || !columns[0].matches("ss-[0-9]{2,3}")) continue;
            if (columns[1].equals("1")) result.delays.put(columns[0], (int) number(columns[2]));
            else result.unavailableNodes.add(columns[0]);
        }

        String uptime = section(sections, "UPTIME").trim().split("\\s+")[0];
        try { result.uptimeSeconds = (long) Double.parseDouble(uptime); }
        catch (NumberFormatException ignored) { }
        long total = extract(section(sections, "MEMINFO"), "MemTotal");
        long available = extract(section(sections, "MEMINFO"), "MemAvailable");
        if (available < 0) {
            available = extract(section(sections, "MEMINFO"), "MemFree")
                    + extract(section(sections, "MEMINFO"), "Buffers")
                    + extract(section(sections, "MEMINFO"), "Cached");
        }
        if (total >= 0 && available >= 0) {
            result.memoryTotal = total * 1024;
            result.memoryUsed = Math.max(0, total - available) * 1024;
        }
        long[] first = cpu(section(sections, "CPU1"));
        long[] second = cpu(section(sections, "CPU2"));
        if (first != null && second != null) {
            long elapsed = second[0] - first[0];
            long idle = second[1] - first[1];
            if (elapsed > 0) result.cpuPercent = (int) Math.max(0,
                    Math.min(100, Math.round(100.0 * (elapsed - idle) / elapsed)));
        }
        return result;
    }

    private static long extract(String text, String label) {
        Matcher match = Pattern.compile("(?m)^\\s*" + Pattern.quote(label) + ":\\s*(\\d+)").matcher(text);
        return match.find() ? number(match.group(1)) : -1;
    }

    private static long[] cpu(String text) {
        String[] values = text.trim().split("\\s+");
        if (values.length < 6 || !values[0].equals("cpu")) return null;
        long total = 0;
        for (int i = 1; i < values.length; i++) total += number(values[i]);
        return new long[] {total, number(values[4]) + number(values[5])};
    }

    private static long number(String value) {
        try { return Long.parseLong(value); }
        catch (NumberFormatException error) { return -1; }
    }

    private static String section(Map<String, String> sections, String name) {
        String value = sections.get(name);
        return value == null ? "" : value;
    }
}
