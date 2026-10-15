package com.dadebay.happrouter;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

public final class ErrorReportTest {
    @Test public void removesSubscriptionLinksAndCredentials() {
        String result = ErrorReport.sanitize("Failed https://example.com/sub/private-token "
                + "ss://cipher:password@example.com:8388 password=hunter2 "
                + "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB");
        assertFalse(result.contains("private-token"));
        assertFalse(result.contains("cipher:password"));
        assertFalse(result.contains("hunter2"));
        assertFalse(result.contains("AAAAB3"));
        assertTrue(result.contains("[redacted-link]"));
    }
}
