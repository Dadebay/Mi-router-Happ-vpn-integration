package com.dadebay.happrouter;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URL;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

final class SubscriptionParser {
    interface Fetcher {
        String get(String url) throws Exception;
    }

    private static final int MAX_BYTES = 512 * 1024;
    private static final Set<String> METHODS = new HashSet<>(Arrays.asList(
            "aes-128-gcm", "aes-192-gcm", "aes-256-gcm", "chacha20-ietf-poly1305",
            "xchacha20-ietf-poly1305", "aes-128-cfb", "aes-192-cfb", "aes-256-cfb",
            "aes-128-ctr", "aes-192-ctr", "aes-256-ctr", "chacha20-ietf", "salsa20"));

    static List<VpnProfile> parseInputs(String first, String second, Fetcher fetcher) throws Exception {
        first = first.trim();
        second = second.trim();
        if (first.isEmpty()) throw new IllegalArgumentException("İlk abonelik veya sunucu profili gerekli.");
        if (first.length() > MAX_BYTES || second.length() > MAX_BYTES)
            throw new IllegalArgumentException("Profil çok büyük.");
        if (first.contains("\n") && first.startsWith("https://"))
            throw new IllegalArgumentException("Her aboneliği ayrı alana yapıştırın.");
        if (!second.isEmpty() && (!first.startsWith("https://") || !second.startsWith("https://")))
            throw new IllegalArgumentException("İki abonelik için iki HTTPS adresi girin.");
        if (first.startsWith("happ://") || second.startsWith("happ://"))
            throw new IllegalArgumentException("Şifreli Happ bağlantısı desteklenmiyor; Shadowsocks bağlantısı kullanın.");

        List<RawProfile> raw = new ArrayList<>();
        if (first.startsWith("https://")) {
            parseDownloaded(first, !second.isEmpty(), fetcher, raw);
            if (!second.isEmpty()) parseDownloaded(second, true, fetcher, raw);
        } else {
            if (!second.isEmpty()) throw new IllegalArgumentException("İkinci alan yalnızca HTTPS aboneliği içindir.");
            raw.addAll(parseContent(first));
        }
        if (raw.isEmpty()) throw new IllegalArgumentException("Shadowsocks sunucusu bulunamadı.");
        if (raw.size() > 200) throw new IllegalArgumentException("En fazla 200 sunucu desteklenir.");
        List<VpnProfile> result = new ArrayList<>();
        for (int i = 0; i < raw.size(); i++) {
            RawProfile item = raw.get(i);
            result.add(new VpnProfile(String.format(java.util.Locale.ROOT, "ss-%02d", i),
                    item.name, item.host, item.port, item.method, item.password));
        }
        return result;
    }

    private static void parseDownloaded(String url, boolean showProvider, Fetcher fetcher,
                                        List<RawProfile> result) throws Exception {
        URI parsed;
        try { parsed = URI.create(url); }
        catch (IllegalArgumentException error) { throw new IllegalArgumentException("Abonelik adresi geçersiz."); }
        if (!"https".equals(parsed.getScheme()) || parsed.getHost() == null || parsed.getUserInfo() != null)
            throw new IllegalArgumentException("Abonelik adresi geçersiz.");
        String content = fetcher.get(url);
        if (content.length() > MAX_BYTES) throw new IllegalArgumentException("Abonelik yanıtı çok büyük.");
        List<RawProfile> nodes = parseContent(content);
        if (nodes.isEmpty()) throw new IllegalArgumentException("Abonelikte Shadowsocks sunucusu bulunamadı.");
        for (RawProfile node : nodes) {
            if (showProvider) node.name = cleanName(parsed.getHost() + " · " + node.name);
            result.add(node);
        }
    }

    static String fetchHttps(String address) throws Exception {
        URL url = new URL(address);
        if (!"https".equalsIgnoreCase(url.getProtocol()))
            throw new IllegalArgumentException("Abonelik HTTPS olmalı.");
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(20000);
        connection.setRequestProperty("User-Agent", "HappRouter/1.0");
        try {
            if (connection.getResponseCode() != 200) throw new Exception("Abonelik yanıt vermedi.");
            if (!"https".equalsIgnoreCase(connection.getURL().getProtocol()))
                throw new IllegalArgumentException("Abonelik HTTPS olmalı.");
            try (InputStream input = connection.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[4096];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    output.write(buffer, 0, count);
                    if (output.size() > MAX_BYTES) throw new IllegalArgumentException("Abonelik yanıtı çok büyük.");
                }
                return output.toString(StandardCharsets.UTF_8.name()).trim();
            }
        } catch (IllegalArgumentException error) {
            throw error;
        } catch (Exception error) {
            throw new Exception("Abonelik okunamadı. Telefonun internetini kontrol edin.", error);
        } finally {
            connection.disconnect();
        }
    }

    private static List<RawProfile> parseContent(String content) throws Exception {
        content = content.trim();
        if (!content.startsWith("{") && !content.contains("ss://")) {
            try {
                String decoded = decodeBase64(content.replaceAll("\\s+", ""));
                if (decoded.contains("://") || decoded.startsWith("{")) content = decoded.trim();
            } catch (IllegalArgumentException ignored) { /* Original text may be a plain profile. */ }
        }
        List<RawProfile> nodes = new ArrayList<>();
        if (content.startsWith("{")) {
            JSONObject document;
            try { document = new JSONObject(content); }
            catch (JSONException error) { throw new IllegalArgumentException("Sunucu JSON biçimi geçersiz."); }
            String remarks = document.optString("remarks", "Happ sunucusu");
            JSONArray outbounds = document.optJSONArray("outbounds");
            if (outbounds != null) for (int i = 0; i < outbounds.length(); i++) {
                JSONObject outbound = outbounds.optJSONObject(i);
                if (outbound == null || !"shadowsocks".equals(outbound.optString("protocol"))) continue;
                JSONObject settings = outbound.optJSONObject("settings");
                JSONArray servers = settings == null ? null : settings.optJSONArray("servers");
                if (servers == null) continue;
                for (int j = 0; j < servers.length(); j++) {
                    JSONObject server = servers.optJSONObject(j);
                    if (server != null) nodes.add(validated(remarks, server.optString("address"),
                            server.optInt("port", -1), server.optString("method"), server.optString("password")));
                }
            }
        } else {
            for (String line : content.split("\\R")) {
                line = line.trim();
                if (line.startsWith("ss://")) nodes.add(parseSs(line));
            }
        }
        return nodes;
    }

    private static RawProfile parseSs(String value) throws Exception {
        String body = value.substring(5);
        int hash = body.indexOf('#');
        String name = hash >= 0 ? urlDecode(body.substring(hash + 1)) : "";
        if (hash >= 0) body = body.substring(0, hash);
        int query = body.indexOf('?');
        if (query >= 0) {
            if (body.substring(query + 1).contains("plugin="))
                throw new IllegalArgumentException("Eklentili Shadowsocks sunucusu desteklenmiyor.");
            body = body.substring(0, query);
        }
        if (!body.contains("@")) body = decodeBase64(body);
        int at = body.lastIndexOf('@');
        if (at < 1) throw new IllegalArgumentException("Shadowsocks bağlantısı geçersiz.");
        String credentials = body.substring(0, at);
        if (!credentials.contains(":")) credentials = decodeBase64(credentials);
        else credentials = urlDecode(credentials);
        int colon = credentials.indexOf(':');
        if (colon < 1) throw new IllegalArgumentException("Shadowsocks kimliği geçersiz.");
        URI endpoint;
        try { endpoint = URI.create("http://" + body.substring(at + 1)); }
        catch (IllegalArgumentException error) { throw new IllegalArgumentException("Shadowsocks adresi geçersiz."); }
        return validated(name.isEmpty() ? endpoint.getHost() : name, endpoint.getHost(),
                endpoint.getPort(), credentials.substring(0, colon), credentials.substring(colon + 1));
    }

    private static RawProfile validated(String name, String host, int port, String method, String password) {
        if (host == null || !host.matches("[A-Za-z0-9.:-]{1,253}") || host.equals("127.0.0.1")
                || host.equals("0.0.0.0") || port < 1 || port > 65535)
            throw new IllegalArgumentException("Sunucu adresi veya portu geçersiz.");
        if (!METHODS.contains(method)) throw new IllegalArgumentException("Şifreleme yöntemi desteklenmiyor.");
        if (password == null || password.isEmpty() || password.length() > 512)
            throw new IllegalArgumentException("Sunucu parolası geçersiz.");
        return new RawProfile(cleanName(name), host, port, method, password);
    }

    private static String cleanName(String value) {
        String name = (value == null ? "" : value).replaceAll("[\\x00-\\x1f\\x7f]+", " ").trim();
        return name.isEmpty() ? "Happ sunucusu" : name.substring(0, Math.min(name.length(), 80));
    }

    private static String decodeBase64(String value) {
        String padded = value + "====".substring(0, (4 - value.length() % 4) % 4);
        try { return new String(Base64.getDecoder().decode(padded), StandardCharsets.UTF_8); }
        catch (IllegalArgumentException error) {
            return new String(Base64.getUrlDecoder().decode(padded), StandardCharsets.UTF_8);
        }
    }

    private static String urlDecode(String value) throws Exception {
        return URLDecoder.decode(value.replace("+", "%2B"), StandardCharsets.UTF_8.name());
    }

    private static final class RawProfile {
        String name;
        final String host;
        final int port;
        final String method;
        final String password;

        RawProfile(String name, String host, int port, String method, String password) {
            this.name = name;
            this.host = host;
            this.port = port;
            this.method = method;
            this.password = password;
        }
    }
}
