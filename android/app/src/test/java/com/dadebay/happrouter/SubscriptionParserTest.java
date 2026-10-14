package com.dadebay.happrouter;

import org.junit.Test;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;

import static org.junit.Assert.*;

public class SubscriptionParserTest {
    @Test public void combinesTwoSubscriptionsWithoutExposingTheirTokens() throws Exception {
        String first = "https://first.example/sub/private-token";
        String second = "https://second.example/sub/other-token";
        List<VpnProfile> nodes = SubscriptionParser.parseInputs(first, second, url -> {
            if (url.equals(first)) return "ss://aes-128-gcm:pass1@first-node.example:443#France";
            if (url.equals(second)) return "ss://aes-128-gcm:pass2@second-node.example:443#Finland";
            throw new AssertionError("Unexpected URL");
        });
        assertEquals(2, nodes.size());
        assertEquals("ss-00", nodes.get(0).tag);
        assertEquals("ss-01", nodes.get(1).tag);
        assertEquals("first.example · France", nodes.get(0).name);
        assertEquals("second.example · Finland", nodes.get(1).name);
        assertEquals("pass2", nodes.get(1).configJson().getString("password"));
        assertFalse(nodes.get(0).previewJson().toString().contains("private-token"));
    }

    @Test public void decodesBase64Subscription() throws Exception {
        String encoded = Base64.getEncoder().encodeToString(
                "ss://aes-256-gcm:pass@node.example:443#Working".getBytes(StandardCharsets.UTF_8));
        List<VpnProfile> nodes = SubscriptionParser.parseInputs("https://example.org/sub", "", url -> encoded);
        assertEquals(1, nodes.size());
        assertEquals("node.example", nodes.get(0).server);
    }

    @Test public void rejectsMixedProfilesBeforeFetch() {
        try {
            SubscriptionParser.parseInputs("ss://aes-128-gcm:pass@node.example:443",
                    "https://example.org/sub", url -> { throw new AssertionError("Fetched"); });
            fail("Expected validation error");
        } catch (IllegalArgumentException expected) {
            assertTrue(expected.getMessage().contains("HTTPS"));
        } catch (Exception unexpected) {
            fail(unexpected.toString());
        }
    }
}
