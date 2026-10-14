package com.dadebay.happrouter;

import android.content.Context;
import android.util.Base64;

import com.jcraft.jsch.JSch;
import com.jcraft.jsch.KeyPair;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

final class DeviceIdentity {
    private final File privateFile;
    private final File publicFile;

    DeviceIdentity(Context context) {
        privateFile = new File(context.getFilesDir(), "router_identity");
        publicFile = new File(context.getFilesDir(), "router_identity.pub");
    }

    synchronized void ensure() throws Exception {
        if (privateFile.exists() && publicFile.exists()) return;
        if (privateFile.exists() || publicFile.exists())
            throw new IllegalStateException("Telefon anahtarı eksik. Uygulama verisini temizleyip yeniden eşleştirin.");
        KeyPair pair = KeyPair.genKeyPair(new JSch(), KeyPair.RSA, 3072);
        File temporary = new File(privateFile.getParentFile(), "router_identity.tmp");
        try {
            try (FileOutputStream output = new FileOutputStream(temporary)) {
                pair.writePrivateKey(output);
            }
            if (!temporary.renameTo(privateFile)) throw new Exception("Telefon anahtarı kaydedilemedi.");
            String publicKey = "ssh-rsa " + Base64.encodeToString(pair.getPublicKeyBlob(), Base64.NO_WRAP)
                    + " happrouter-android\n";
            Files.write(publicFile.toPath(), publicKey.getBytes(StandardCharsets.US_ASCII));
        } finally {
            pair.dispose();
            temporary.delete();
        }
    }

    byte[] privateKey() throws Exception {
        ensure();
        return Files.readAllBytes(privateFile.toPath());
    }

    String publicKey() throws Exception {
        ensure();
        return new String(Files.readAllBytes(publicFile.toPath()), StandardCharsets.US_ASCII).trim();
    }
}
