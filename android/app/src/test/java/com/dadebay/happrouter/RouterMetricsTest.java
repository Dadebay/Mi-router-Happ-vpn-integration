package com.dadebay.happrouter;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public class RouterMetricsTest {
    @Test public void parsesRouterAndDeviceReadings() {
        String sample = """
                __NETDEV__
                phy0-ap0: 120000 0 0 0 0 0 0 0 3400000 0 0 0 0 0 0 0
                eth0.2: 9000000 0 0 0 0 0 0 0 300000 0 0 0 0 0 0 0
                __LEASES__
                123 aa:bb:cc:dd:ee:ff 192.168.1.20 Galaxy-A34 *
                __STATIONS__
                Station aa:bb:cc:dd:ee:ff (on phy0-ap0)
                    rx bytes: 12345
                    tx bytes: 67890
                __NEIGH__
                __USAGE__
                2026-10-15\taa:bb:cc:dd:ee:ff\t1000\t2000
                __BLOCKED__
                aa:bb:cc:dd:ee:ff
                __PROBES__
                ss-00\t1\t109\t123456
                ss-01\t0\t0\t123456
                __UPTIME__
                7200.12 123.45
                __MEMINFO__
                MemTotal: 56000 kB
                MemAvailable: 14000 kB
                __CPU1__
                cpu  100 0 100 800 0 0 0 0 0 0
                __CPU2__
                cpu  120 0 120 860 0 0 0 0 0 0
                """;
        RouterMetrics result = RouterMetrics.parse(sample);
        assertEquals(3_400_000, result.wifiTx);
        assertEquals(9_000_000, result.wanRx);
        assertEquals(2_000, result.wifiDownloadToday);
        assertEquals(56_000L * 1024, result.memoryTotal);
        assertEquals(42_000L * 1024, result.memoryUsed);
        assertEquals(7200, result.uptimeSeconds);
        assertEquals(40, result.cpuPercent);
        assertEquals(1, result.devices.size());
        RouterMetrics.Device phone = result.devices.get(0);
        assertEquals("Galaxy-A34", phone.name);
        assertEquals("192.168.1.20", phone.ip);
        assertEquals(67_890, phone.downloaded);
        assertEquals(12_345, phone.uploaded);
        assertEquals(2_000, phone.downloadToday);
        assertTrue(phone.blocked);
        assertEquals(Integer.valueOf(109), result.delays.get("ss-00"));
        assertTrue(result.unavailableNodes.contains("ss-01"));
    }

    @Test public void routerAddressStaysOnPrivateLan() {
        assertTrue(RouterAddress.valid("192.168.1.1"));
        assertTrue(RouterAddress.valid("192.168.28.1"));
        assertTrue(RouterAddress.valid("10.0.0.1"));
        assertFalse(RouterAddress.valid("8.8.8.8"));
        assertFalse(RouterAddress.valid("192.168.1.999"));
    }
}
