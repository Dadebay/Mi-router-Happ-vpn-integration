package com.dadebay.happrouter;

import org.json.JSONException;
import org.json.JSONObject;

final class VpnProfile {
    final String tag;
    final String name;
    final String server;
    final int port;
    final String method;
    final String password;

    VpnProfile(String tag, String name, String server, int port, String method, String password) {
        this.tag = tag;
        this.name = name;
        this.server = server;
        this.port = port;
        this.method = method;
        this.password = password;
    }

    JSONObject configJson() throws JSONException {
        JSONObject value = new JSONObject();
        value.put("server", server);
        value.put("server_port", port);
        value.put("method", method);
        value.put("password", password);
        value.put("local_address", "127.0.0.1");
        value.put("local_port", 1080);
        value.put("timeout", 30);
        return value;
    }

    JSONObject previewJson() throws JSONException {
        JSONObject value = new JSONObject();
        value.put("tag", tag);
        value.put("name", name);
        value.put("address", server);
        value.put("port", port);
        value.put("country", "");
        return value;
    }
}
