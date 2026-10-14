package com.dadebay.happrouter;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class SecretPrefs {
    private static final String KEY_ALIAS = "HappRouterSubscriptions";
    private final SharedPreferences preferences;

    SecretPrefs(Context context) {
        preferences = context.getSharedPreferences("subscription_secrets", Context.MODE_PRIVATE);
    }

    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        SecretKey existing = (SecretKey) store.getKey(KEY_ALIAS, null);
        if (existing != null) return existing;
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build());
        return generator.generateKey();
    }

    String read(String name) {
        String encoded = preferences.getString(name, null);
        if (encoded == null) return "";
        try {
            byte[] value = Base64.decode(encoded, Base64.NO_WRAP);
            byte[] iv = java.util.Arrays.copyOfRange(value, 0, 12);
            byte[] encrypted = java.util.Arrays.copyOfRange(value, 12, value.length);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, iv));
            return new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
        } catch (Exception ignored) {
            return "";
        }
    }

    void write(String name, String value) throws Exception {
        if (value.isEmpty()) {
            preferences.edit().remove(name).apply();
            return;
        }
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
        byte[] output = new byte[cipher.getIV().length + encrypted.length];
        System.arraycopy(cipher.getIV(), 0, output, 0, cipher.getIV().length);
        System.arraycopy(encrypted, 0, output, cipher.getIV().length, encrypted.length);
        preferences.edit().putString(name, Base64.encodeToString(output, Base64.NO_WRAP)).apply();
    }
}
