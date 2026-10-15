package com.dadebay.happrouter;

import android.content.Context;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.Session;
import com.jcraft.jsch.UIKeyboardInteractive;
import com.jcraft.jsch.UserInfo;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

final class RouterSsh implements AutoCloseable {
    private final Session session;

    RouterSsh(Context context, DeviceIdentity identity) throws Exception {
        this(context, identity, null);
    }

    private RouterSsh(Context context, DeviceIdentity identity, char[] password) throws Exception {
        JSch jsch = new JSch();
        try (InputStream knownHosts = context.getAssets().open("router_known_hosts")) {
            String pinned = new String(knownHosts.readAllBytes(), StandardCharsets.US_ASCII);
            String address = RouterAddress.get(context);
            // Reuse the pinned Xiaomi host key when its LAN address changes.
            jsch.setKnownHosts(new ByteArrayInputStream(
                    pinned.replace("192.168.1.1 ", address + " ")
                            .getBytes(StandardCharsets.US_ASCII)));
        }
        if (password == null) jsch.addIdentity("HappRouter Android", identity.privateKey(), null, null);
        session = jsch.getSession("root", RouterAddress.get(context), 22);
        session.setConfig("StrictHostKeyChecking", "yes");
        session.setConfig("PreferredAuthentications", password == null
                ? "publickey" : "keyboard-interactive,password");
        if (password != null) {
            session.setPassword(new String(password));
            session.setUserInfo(new PasswordInfo(password));
        }
        session.setTimeout(15000);
        try {
            session.connect(15000);
        } catch (Exception error) {
            throw new Exception("Router bağlantısı kurulamadı. Wi-Fi, router IP'si, yönetici parolası veya eşleştirmeyi kontrol edin. "
                    + error.getMessage(), error);
        }
    }

    static void pairWithPassword(Context context, DeviceIdentity identity, char[] password) throws Exception {
        if (password.length == 0) throw new IllegalArgumentException("Router yönetici parolasını girin.");
        try (RouterSsh ssh = new RouterSsh(context, identity, password)) {
            String command = "umask 077; mkdir -p /etc/dropbear; "
                    + "touch /etc/dropbear/authorized_keys; chmod 600 /etc/dropbear/authorized_keys; "
                    + "read -r key; grep -Fqx \"$key\" /etc/dropbear/authorized_keys "
                    + "|| printf '%s\\n' \"$key\" >> /etc/dropbear/authorized_keys";
            ssh.exec(command, (identity.publicKey() + "\n").getBytes(StandardCharsets.US_ASCII), 20);
        } finally {
            Arrays.fill(password, '\0');
        }
    }

    private static final class PasswordInfo implements UserInfo, UIKeyboardInteractive {
        private final char[] password;
        PasswordInfo(char[] password) { this.password = password; }
        @Override public String getPassphrase() { return null; }
        @Override public String getPassword() { return new String(password); }
        @Override public boolean promptPassword(String message) { return true; }
        @Override public boolean promptPassphrase(String message) { return false; }
        @Override public boolean promptYesNo(String message) { return false; }
        @Override public void showMessage(String message) { }
        @Override public String[] promptKeyboardInteractive(String destination, String name,
                String instruction, String[] prompts, boolean[] echo) {
            String[] answers = new String[prompts.length];
            Arrays.fill(answers, new String(password));
            return answers;
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
