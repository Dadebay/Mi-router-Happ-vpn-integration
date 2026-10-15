package com.dadebay.happrouter;

import android.content.Context;
import android.content.SharedPreferences;

final class RouterAddress {
    private static final String DEFAULT = "192.168.1.1";

    static String get(Context context) {
        return context.getSharedPreferences("router", Context.MODE_PRIVATE)
                .getString("address", DEFAULT);
    }

    static void save(Context context, String address) {
        if (!valid(address)) throw new IllegalArgumentException(context.getString(R.string.invalid_router_ip));
        context.getSharedPreferences("router", Context.MODE_PRIVATE).edit()
                .putString("address", address).apply();
    }

    static boolean valid(String address) {
        if (address == null || !address.matches("[0-9.]{7,15}")) return false;
        String[] parts = address.split("\\.", -1);
        if (parts.length != 4) return false;
        int[] bytes = new int[4];
        for (int i = 0; i < 4; i++) {
            if (parts[i].isEmpty() || parts[i].length() > 3) return false;
            bytes[i] = Integer.parseInt(parts[i]);
            if (bytes[i] > 255 || !Integer.toString(bytes[i]).equals(parts[i])) return false;
        }
        return bytes[0] == 10 || (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31)
                || (bytes[0] == 192 && bytes[1] == 168);
    }
}
