package com.dadebay.happrouter;

import android.content.Context;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

final class RouterSsh implements AutoCloseable {
    private final Session session;

    RouterSsh(Context context, DeviceIdentity identity) throws Exception {
        JSch jsch = new JSch();
        try (InputStream knownHosts = context.getAssets().open("router_known_hosts")) {
            jsch.setKnownHosts(knownHosts);
        }
        jsch.addIdentity("HappRouter Android", identity.privateKey(), null, null);
        session = jsch.getSession("root", "192.168.1.1", 22);
        session.setConfig("StrictHostKeyChecking", "yes");
        session.setConfig("PreferredAuthentications", "publickey");
        session.setTimeout(15000);
        try {
            session.connect(15000);
        } catch (Exception error) {
            throw new Exception("Router bağlantısı kurulamadı. HappVPN Wi-Fi bağlantısını ve telefon eşleştirmesini kontrol edin.", error);
        }
    }

    String exec(String command, byte[] input, int timeoutSeconds) throws Exception {
        ChannelExec channel = (ChannelExec) session.openChannel("exec");
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        ByteArrayOutputStream error = new ByteArrayOutputStream();
        channel.setCommand(command);
        channel.setOutputStream(output);
        channel.setErrStream(error);
        if (input != null) channel.setInputStream(new ByteArrayInputStream(input));
        try {
            channel.connect(15000);
            long deadline = System.currentTimeMillis() + timeoutSeconds * 1000L;
            while (!channel.isClosed()) {
                if (System.currentTimeMillis() > deadline) throw new Exception("Router işlemi zaman aşımına uğradı.");
                Thread.sleep(50);
            }
            if (channel.getExitStatus() != 0)
                throw new Exception("Router komutu başarısız oldu (" + channel.getExitStatus() + ").");
            return output.toString(StandardCharsets.UTF_8.name()).trim();
        } finally {
            channel.disconnect();
        }
    }

    String exec(String command, int timeoutSeconds) throws Exception {
        return exec(command, null, timeoutSeconds);
    }

    void write(String path, byte[] content) throws Exception {
        if (!path.matches("[/A-Za-z0-9._-]+")) throw new IllegalArgumentException("Dosya yolu geçersiz.");
        exec("umask 077; cat > " + path + " && chmod 600 " + path, content, 25);
    }

    @Override public void close() {
        session.disconnect();
    }
}
