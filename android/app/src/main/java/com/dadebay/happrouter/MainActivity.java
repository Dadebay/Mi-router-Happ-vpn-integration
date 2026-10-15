package com.dadebay.happrouter;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.DatePickerDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.text.InputType;
import android.text.method.PasswordTransformationMethod;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.TextView;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Callable;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

public final class MainActivity extends Activity {
    private static final int BLUE = Color.rgb(34, 103, 234);
    private static final int DARK = Color.rgb(26, 35, 52);
    private static final int MUTED = Color.rgb(102, 115, 137);
    private static final int BG = Color.rgb(245, 247, 251);
    private static final int BORDER = Color.rgb(225, 231, 239);
    private static final int SUCCESS = Color.rgb(23, 145, 90);
    private static final int ERROR = Color.rgb(205, 56, 70);

    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private Typeface regularFont;
    private Typeface semiboldFont;
    private Typeface boldFont;
    private DeviceIdentity identity;
    private SecretPrefs secrets;
    private RouterGateway gateway;
    private RouterGateway.Status routerStatus;
    private List<VpnProfile> previewNodes = new ArrayList<>();
    private String selectedTag = "";
    private String testedTag = "";
    private String testedIp = "";
    private boolean busy;

    private TextView connectionText;
    private TextView messageText;
    private TextView pairingKey;
    private TextView previewSummary;
    private TextView testedText;
    private LinearLayout pairingCard;
    private LinearLayout metricsCard;
    private LinearLayout devicesCard;
    private LinearLayout metricsContent;
    private LinearLayout devicesContent;
    private LinearLayout modeRow;
    private EditText routerIpInput;
    private EditText pairingPassword;
    private Button revealKeyButton;
    private LinearLayout savedNodes;
    private LinearLayout previewSection;
    private RadioGroup previewChoices;
    private EditText firstInput;
    private EditText secondInput;
    private EditText expiryInput;
    private Button refreshButton;
    private Button fetchButton;
    private Button testButton;
    private Button installButton;
    private Button automaticButton;
    private ProgressBar progress;

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        regularFont = getResources().getFont(R.font.gilroy_regular);
        semiboldFont = getResources().getFont(R.font.gilroy_semibold);
        boldFont = getResources().getFont(R.font.gilroy_bold);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        identity = new DeviceIdentity(this);
        secrets = new SecretPrefs(this);
        gateway = new RouterGateway(this, identity);
        buildScreen();
        firstInput.setText(secrets.read("first"));
        secondInput.setText(secrets.read("second"));
        background(() -> identity.publicKey(), key -> {
            pairingKey.setText(key);
            refreshStatus();
        });
    }

    private void buildScreen() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);
        LinearLayout page = vertical();
        page.setPadding(dp(18), dp(28), dp(18), dp(34));
        scroll.addView(page);
        setContentView(scroll);

        page.addView(text("HappRouter", 29, DARK, Typeface.BOLD));
        TextView subtitle = text("Mi Router 4C · Telefon kontrol paneli", 14, MUTED, Typeface.NORMAL);
        subtitle.setPadding(0, dp(3), 0, dp(20));
        page.addView(subtitle);

        LinearLayout guide = card(page);
        guide.addView(text("İlk kurulum", 17, DARK, Typeface.BOLD));
        TextView guideHint = text("Router'ın yanındaki kişi tüm adımları telefondan tamamlayabilir.",
                13, MUTED, Typeface.NORMAL);
        guideHint.setPadding(0, dp(5), 0, dp(9));
        guide.addView(guideHint);
        guide.addView(button("Adım adım rehberi aç", false,
                () -> startActivity(new Intent(this, GuideActivity.class))));

        LinearLayout addressCard = card(page);
        addressCard.addView(text("Router adresi", 17, DARK, Typeface.BOLD));
        LinearLayout addressRow = row();
        addressRow.setPadding(0, dp(9), 0, 0);
        addressCard.addView(addressRow);
        routerIpInput = input("192.168.1.1");
        routerIpInput.setTransformationMethod(null);
        routerIpInput.setInputType(InputType.TYPE_CLASS_PHONE);
        routerIpInput.setText(RouterAddress.get(this));
        LinearLayout.LayoutParams addressSpace = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        addressSpace.rightMargin = dp(8);
        addressRow.addView(routerIpInput, addressSpace);
        addressRow.addView(button("Bağlan", false, () -> {
            try {
                RouterAddress.save(this, routerIpInput.getText().toString().trim());
                routerStatus = null;
                refreshStatus();
            } catch (Exception error) { showMessage(error.getMessage(), ERROR); }
        }));

        LinearLayout status = card(page);
        LinearLayout statusHeader = row();
        status.addView(statusHeader);
        TextView statusTitle = text("Router bağlantısı", 17, DARK, Typeface.BOLD);
        statusHeader.addView(statusTitle, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        refreshButton = button("Yenile", false, this::refreshStatus);
        statusHeader.addView(refreshButton);
        connectionText = text("Kontrol ediliyor…", 14, MUTED, Typeface.NORMAL);
        connectionText.setPadding(0, dp(12), 0, 0);
        status.addView(connectionText);
        modeRow = row();
        modeRow.setPadding(0, dp(12), 0, 0);
        status.addView(modeRow);
        modeRow.addView(button("VPN modu", false, () -> changeMode("vpn")));
        modeRow.addView(button("Normal internet", false, () -> changeMode("direct")));
        modeRow.setVisibility(View.GONE);
        savedNodes = vertical();
        savedNodes.setPadding(0, dp(10), 0, 0);
        status.addView(savedNodes);

        metricsCard = card(page);
        metricsCard.addView(text("Router verileri", 17, DARK, Typeface.BOLD));
        metricsContent = vertical();
        metricsContent.setPadding(0, dp(8), 0, 0);
        metricsCard.addView(metricsContent);
        metricsCard.setVisibility(View.GONE);

        devicesCard = card(page);
        devicesCard.addView(text("Bağlı cihazlar", 17, DARK, Typeface.BOLD));
        devicesContent = vertical();
        devicesContent.setPadding(0, dp(8), 0, 0);
        devicesCard.addView(devicesContent);
        devicesCard.setVisibility(View.GONE);

        pairingCard = card(page);
        pairingCard.addView(text("Telefonu eşleştir", 17, DARK, Typeface.BOLD));
        TextView pairingInfo = text("HappVPN Wi-Fi ağına bağlan. Router yönetici parolan varsa "
                + "buradan eşleştir. Parola telefonda saklanmaz. Parolayla SSH kapalıysa "
                + "açık anahtarı router'ın yönetim sayfasındaki SSH anahtarlarına ekle.",
                13, MUTED, Typeface.NORMAL);
        pairingInfo.setPadding(0, dp(8), 0, dp(10));
        pairingCard.addView(pairingInfo);
        pairingPassword = input("Router yönetici parolası");
        pairingPassword.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        pairingCard.addView(pairingPassword);
        Button pairButton = button("Telefonu eşleştir", true, this::pairPhone);
        LinearLayout.LayoutParams pairSpace = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        pairSpace.topMargin = dp(9);
        pairingCard.addView(pairButton, pairSpace);
        pairingKey = text("Anahtar hazırlanıyor…", 11, DARK, Typeface.NORMAL);
        pairingKey.setTextIsSelectable(true);
        pairingKey.setPadding(dp(10), dp(10), dp(10), dp(10));
        pairingKey.setBackground(rounded(BG, 10, BORDER));
        pairingKey.setVisibility(View.GONE);
        revealKeyButton = button("Açık anahtarı göster", false, () -> {
            boolean show = pairingKey.getVisibility() != View.VISIBLE;
            pairingKey.setVisibility(show ? View.VISIBLE : View.GONE);
            revealKeyButton.setText(show ? "Açık anahtarı gizle" : "Açık anahtarı göster");
        });
        pairingCard.addView(revealKeyButton);
        pairingCard.addView(pairingKey);
        LinearLayout pairingActions = row();
        pairingActions.setPadding(0, dp(10), 0, 0);
        pairingCard.addView(pairingActions);
        pairingActions.addView(button("Kopyala", false, () -> {
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            clipboard.setPrimaryClip(ClipData.newPlainText("HappRouter public key", pairingKey.getText()));
            showMessage("Açık anahtar kopyalandı.", SUCCESS);
        }));
        pairingActions.addView(button("Paylaş", false, () -> {
            Intent share = new Intent(Intent.ACTION_SEND);
            share.setType("text/plain");
            share.putExtra(Intent.EXTRA_TEXT, pairingKey.getText().toString());
            startActivity(Intent.createChooser(share, "Açık anahtarı paylaş"));
        }));

        LinearLayout profile = card(page);
        profile.addView(text("Abonelikleri değiştir", 17, DARK, Typeface.BOLD));
        TextView help = text("En fazla iki HTTPS bağlantısı ekle. Shadowsocks sunucuları tek listede görünür.",
                13, MUTED, Typeface.NORMAL);
        help.setPadding(0, dp(6), 0, dp(14));
        profile.addView(help);
        profile.addView(text("1. abonelik veya ss://", 12, MUTED, Typeface.BOLD));
        firstInput = input("HTTPS abonelik veya Shadowsocks bağlantısı");
        profile.addView(firstInput);
        TextView secondLabel = text("2. abonelik · isteğe bağlı", 12, MUTED, Typeface.BOLD);
        secondLabel.setPadding(0, dp(10), 0, 0);
        profile.addView(secondLabel);
        secondInput = input("İkinci HTTPS abonelik adresi");
        profile.addView(secondInput);
        Button visibility = button("Adresleri göster / gizle", false, () -> {
            boolean show = firstInput.getTransformationMethod() != null;
            firstInput.setTransformationMethod(show ? null : PasswordTransformationMethod.getInstance());
            secondInput.setTransformationMethod(show ? null : PasswordTransformationMethod.getInstance());
            firstInput.setSelection(firstInput.length());
            secondInput.setSelection(secondInput.length());
        });
        LinearLayout.LayoutParams visibilitySpace = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        visibilitySpace.topMargin = dp(8);
        profile.addView(visibility, visibilitySpace);
        fetchButton = button("Sunucuları getir", true, this::fetchProfiles);
        LinearLayout.LayoutParams fetchSpace = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        fetchSpace.topMargin = dp(14);
        profile.addView(fetchButton, fetchSpace);

        previewSection = card(page);
        previewSection.addView(text("Yeni sunucular", 17, DARK, Typeface.BOLD));
        previewSummary = text("", 13, MUTED, Typeface.NORMAL);
        previewSummary.setPadding(0, dp(6), 0, dp(10));
        previewSection.addView(previewSummary);
        previewChoices = new RadioGroup(this);
        previewSection.addView(previewChoices);
        testedText = text("Uygulama en uygun sunucuyu bulur. İstersen listeden elle seçebilirsin.",
                13, MUTED, Typeface.NORMAL);
        testedText.setPadding(0, dp(10), 0, dp(10));
        previewSection.addView(testedText);
        testButton = button("En uygun sunucuyu bul ve test et", false, this::testSelected);
        previewSection.addView(testButton);
        TextView expiryLabel = text("Abonelik bitiş günü", 12, MUTED, Typeface.BOLD);
        expiryLabel.setPadding(0, dp(18), 0, dp(4));
        previewSection.addView(expiryLabel);
        expiryInput = input("Bitiş günü");
        expiryInput.setFocusable(false);
        expiryInput.setOnClickListener(view -> chooseDate());
        previewSection.addView(expiryInput);
        installButton = button("Tüm sunucuları kur", true, this::installSelected);
        LinearLayout.LayoutParams installSpace = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        installSpace.topMargin = dp(12);
        previewSection.addView(installButton, installSpace);
        previewSection.setVisibility(View.GONE);

        progress = new ProgressBar(this);
        progress.setVisibility(View.GONE);
        LinearLayout.LayoutParams progressSpace = new LinearLayout.LayoutParams(dp(32), dp(32));
        progressSpace.gravity = Gravity.CENTER_HORIZONTAL;
        progressSpace.topMargin = dp(16);
        page.addView(progress, progressSpace);
        messageText = text("", 13, MUTED, Typeface.NORMAL);
        messageText.setPadding(dp(4), dp(18), dp(4), 0);
        page.addView(messageText);
        renderPreview();
    }

    private void refreshStatus() {
        background(() -> gateway.status(), status -> {
            routerStatus = status;
            pairingCard.setVisibility(View.GONE);
            String mode = "vpn".equals(status.mode) ? "VPN açık" : "Normal internet";
            String ip = status.exitIp == null ? "Çıkış IP doğrulanamadı" : "Çıkış IP: " + status.exitIp;
            connectionText.setText(mode + " · " + ip);
            modeRow.setVisibility(View.VISIBLE);
            renderMetrics();
            renderDevices();
            renderSavedNodes();
            if (expiryInput.getText().length() == 0 && status.expiry > 0)
                expiryInput.setText(Instant.ofEpochSecond(status.expiry)
                        .atZone(ZoneId.systemDefault()).toLocalDate().toString());
        }, error -> {
            String reason = error.getMessage();
            connectionText.setText(reason == null || reason.isEmpty()
                    ? "Bağlanılamadı · HappVPN Wi-Fi ve router adresini kontrol et." : reason);
            modeRow.setVisibility(View.GONE);
            metricsCard.setVisibility(View.GONE);
            devicesCard.setVisibility(View.GONE);
            pairingCard.setVisibility(View.VISIBLE);
        });
    }

    private void renderSavedNodes() {
        savedNodes.removeAllViews();
        if (routerStatus == null || routerStatus.nodes.isEmpty()) return;
        TextView label = text("Kayıtlı sunucular", 13, MUTED, Typeface.BOLD);
        label.setPadding(0, dp(8), 0, dp(5));
        savedNodes.addView(label);
        for (RouterGateway.SavedNode node : routerStatus.nodes) {
            LinearLayout line = row();
            line.setPadding(0, dp(7), 0, dp(7));
            boolean active = node.tag.equals(routerStatus.active);
            String delay = node.delay != null ? " · " + node.delay + " ms"
                    : Boolean.FALSE.equals(node.alive) ? " · Ulaşılamıyor" : "";
            String name = node.name + delay + (active ? " · Aktif" : "");
            line.addView(text(name, 13, active ? BLUE : DARK, active ? Typeface.BOLD : Typeface.NORMAL),
                    new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            if (!active) line.addView(button("Seç", false, () -> changeNode(node.tag)));
            savedNodes.addView(line);
        }
        automaticButton = button("Otomatik seçim: "
                + ("auto".equals(routerStatus.selection) ? "Açık" : "Kapalı"),
                false, this::enableAutomatic);
        automaticButton.setEnabled(!"auto".equals(routerStatus.selection) && !busy);
        savedNodes.addView(automaticButton);
    }

    private void renderMetrics() {
        metricsContent.removeAllViews();
        RouterMetrics m = routerStatus.metrics;
        addMetric("VPN servisi", routerStatus.vpnRunning ? "Çalışıyor" : "Başlıyor / kapalı");
        addMetric("CPU", m.cpuPercent < 0 ? "—" : m.cpuPercent + "%");
        addMetric("RAM", m.memoryTotal < 0 ? "—" : formatBytes(m.memoryUsed)
                + " / " + formatBytes(m.memoryTotal));
        addMetric("Çalışma süresi", m.uptimeSeconds < 0 ? "—"
                : m.uptimeSeconds / 3600 + " saat");
        addMetric("Wi-Fi trafiği", formatBytes(m.wifiTx));
        addMetric("WAN trafiği", formatBytes(m.wanRx));
        addMetric("Bugün indirilen", formatBytes(m.wifiDownloadToday));
        if (routerStatus.expiry > 0) addMetric("Abonelik bitişi",
                Instant.ofEpochSecond(routerStatus.expiry)
                        .atZone(ZoneId.systemDefault()).toLocalDate().toString());
        metricsCard.setVisibility(View.VISIBLE);
    }

    private void addMetric(String label, String value) {
        LinearLayout line = row();
        line.setPadding(0, dp(7), 0, dp(7));
        line.addView(text(label, 13, MUTED, Typeface.NORMAL),
                new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        line.addView(text(value, 13, DARK, Typeface.BOLD));
        metricsContent.addView(line);
    }

    private void renderDevices() {
        devicesContent.removeAllViews();
        List<RouterMetrics.Device> devices = routerStatus.metrics.devices;
        if (devices.isEmpty()) devicesContent.addView(text("Bağlı cihaz bulunmadı.", 13, MUTED,
                Typeface.NORMAL));
        for (RouterMetrics.Device device : devices) {
            LinearLayout item = vertical();
            item.setPadding(0, dp(11), 0, dp(11));
            LinearLayout heading = row();
            item.addView(heading);
            heading.addView(text(device.name, 14, DARK, Typeface.BOLD),
                    new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
            heading.addView(button(device.blocked ? "Engeli kaldır" : "Engelle", false,
                    () -> confirmDeviceBlock(device)));
            String details = device.connection + " · " + (device.ip.isEmpty() ? "IP bilinmiyor" : device.ip)
                    + "\nBugün ↓ " + formatBytes(device.downloadToday)
                    + "  ↑ " + formatBytes(device.uploadToday)
                    + "\nToplam ↓ " + formatBytes(device.downloaded)
                    + "  ↑ " + formatBytes(device.uploaded);
            item.addView(text(details, 12, MUTED, Typeface.NORMAL));
            devicesContent.addView(item);
        }
        devicesCard.setVisibility(View.VISIBLE);
    }

    private void confirmDeviceBlock(RouterMetrics.Device device) {
        String verb = device.blocked ? "engeli kaldırılsın mı?" : "internet erişimi engellensin mi?";
        new AlertDialog.Builder(this).setTitle(device.name)
                .setMessage(device.ip + " adresli cihazın " + verb)
                .setNegativeButton("Vazgeç", null)
                .setPositiveButton(device.blocked ? "Engeli kaldır" : "Engelle", (dialog, which) ->
                        background(() -> { gateway.setDeviceBlocked(device.mac, !device.blocked); return true; },
                                result -> {
                                    showMessage("Cihaz kuralı güncellendi.", SUCCESS);
                                    refreshStatus();
                                }))
                .show();
    }

    private void pairPhone() {
        char[] password = pairingPassword.getText().toString().toCharArray();
        pairingPassword.setText("");
        background(() -> { RouterSsh.pairWithPassword(this, identity, password); return true; },
                result -> {
                    showMessage("Telefon eşleştirildi.", SUCCESS);
                    refreshStatus();
                }, error -> connectionText.setText("Eşleştirme başarısız. Router parolasını ve Wi-Fi'yi kontrol et."));
    }

    private void changeMode(String mode) {
        if (routerStatus == null || mode.equals(routerStatus.mode)) return;
        background(() -> { gateway.setMode(mode); return true; }, result -> {
            showMessage(mode.equals("vpn") ? "VPN modu açıldı." : "Normal internet açıldı.", SUCCESS);
            refreshStatus();
        });
    }

    private static String formatBytes(long bytes) {
        if (bytes < 0) return "—";
        if (bytes >= 1_000_000_000) return String.format(java.util.Locale.US, "%.2f GB", bytes / 1e9);
        if (bytes >= 1_000_000) return String.format(java.util.Locale.US, "%.1f MB", bytes / 1e6);
        if (bytes >= 1_000) return String.format(java.util.Locale.US, "%.0f KB", bytes / 1e3);
        return bytes + " B";
    }

    private void fetchProfiles() {
        String first = firstInput.getText().toString();
        String second = secondInput.getText().toString();
        background(() -> SubscriptionParser.parseInputs(first, second, SubscriptionParser::fetchHttps), nodes -> {
            previewNodes = nodes;
            selectedTag = "";
            testedTag = "";
            testedIp = "";
            try {
                secrets.write("first", first.trim());
                secrets.write("second", second.trim());
            } catch (Exception error) {
                showMessage("Abonelik adresleri güvenli depoya kaydedilemedi.", ERROR);
            }
            renderPreview();
            showMessage(nodes.size() + " sunucu getirildi. En uygunu test edebilirsin.", BLUE);
        });
    }

    private void renderPreview() {
        previewSection.setVisibility(previewNodes.isEmpty() ? View.GONE : View.VISIBLE);
        previewChoices.removeAllViews();
        previewSummary.setText(previewNodes.size() + " Shadowsocks sunucusu");
        for (VpnProfile node : previewNodes) {
            RadioButton radio = new RadioButton(this);
            radio.setId(View.generateViewId());
            radio.setText(node.name);
            radio.setTextSize(14);
            radio.setTextColor(DARK);
            radio.setTypeface(regularFont);
            radio.setPadding(dp(4), dp(7), 0, dp(7));
            radio.setButtonTintList(android.content.res.ColorStateList.valueOf(BLUE));
            radio.setOnClickListener(view -> {
                selectedTag = node.tag;
                testedTag = "";
                testedIp = "";
                testedText.setText("Elle seçilen sunucuyu test et. Mevcut bağlantı değişmez.");
                testButton.setText("Seçilen sunucuyu test et");
                updateActions();
            });
            previewChoices.addView(radio);
            if (node.tag.equals(selectedTag)) previewChoices.check(radio.getId());
        }
        testedText.setText(testedTag.isEmpty()
                ? "Uygulama en uygun sunucuyu bulur. İstersen listeden elle seçebilirsin."
                : "Bağlantı başarılı · Çıkış IP: " + testedIp);
        testButton.setText(selectedTag.isEmpty() ? "En uygun sunucuyu bul ve test et"
                : "Seçilen sunucuyu test et");
        testedText.setTextColor(testedTag.isEmpty() ? MUTED : SUCCESS);
        updateActions();
    }

    private void testSelected() {
        VpnProfile node = selectedProfile();
        List<VpnProfile> snapshot = new ArrayList<>(previewNodes);
        background(() -> node == null ? gateway.bestCandidate(snapshot)
                : new RouterGateway.Candidate(node, gateway.testCandidate(node)), candidate -> {
            selectedTag = candidate.profile.tag;
            testedTag = candidate.profile.tag;
            testedIp = candidate.exitIp;
            renderPreview();
            showMessage("Çalışan sunucu bulundu: " + candidate.profile.name, SUCCESS);
        });
    }

    private void installSelected() {
        if (!selectedTag.equals(testedTag)) return;
        long expiry;
        try {
            LocalDate day = LocalDate.parse(expiryInput.getText().toString(), DateTimeFormatter.ISO_LOCAL_DATE);
            expiry = day.atTime(23, 59, 59).atZone(ZoneId.systemDefault()).toEpochSecond();
        } catch (Exception error) {
            showMessage("Geçerli bir bitiş günü seç.", ERROR);
            return;
        }
        List<VpnProfile> snapshot = new ArrayList<>(previewNodes);
        String tag = selectedTag;
        background(() -> gateway.install(snapshot, tag, expiry), ip -> {
            showMessage("Kurulum tamamlandı. VPN çıkış IP: " + ip, SUCCESS);
            previewNodes.clear();
            selectedTag = "";
            testedTag = "";
            renderPreview();
            refreshStatus();
        });
    }

    private VpnProfile selectedProfile() {
        for (VpnProfile node : previewNodes) if (node.tag.equals(selectedTag)) return node;
        return null;
    }

    private void changeNode(String tag) {
        background(() -> { gateway.select(tag); return "Sunucu değiştirildi."; }, result -> {
            showMessage(result, SUCCESS);
            refreshStatus();
        });
    }

    private void enableAutomatic() {
        background(() -> { gateway.automatic(); return "Otomatik seçim açıldı."; }, result -> {
            showMessage(result, SUCCESS);
            refreshStatus();
        });
    }

    private void chooseDate() {
        LocalDate current;
        try { current = LocalDate.parse(expiryInput.getText().toString()); }
        catch (Exception ignored) { current = LocalDate.now().plusMonths(1); }
        new DatePickerDialog(this, (picker, year, month, day) -> expiryInput.setText(
                LocalDate.of(year, month + 1, day).toString()),
                current.getYear(), current.getMonthValue() - 1, current.getDayOfMonth()).show();
    }

    private <T> void background(Callable<T> task, Consumer<T> success) {
        background(task, success, null);
    }

    private <T> void background(Callable<T> task, Consumer<T> success, Consumer<Exception> failure) {
        if (busy) return;
        setBusy(true);
        worker.execute(() -> {
            try {
                T value = task.call();
                runOnUiThread(() -> {
                    setBusy(false);
                    success.accept(value);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    setBusy(false);
                    String message = error.getMessage();
                    showMessage(message == null ? "İşlem tamamlanamadı." : message, ERROR);
                    if (failure != null) failure.accept(error);
                    if (routerStatus == null) pairingCard.setVisibility(View.VISIBLE);
                });
            }
        });
    }

    private void setBusy(boolean value) {
        busy = value;
        progress.setVisibility(value ? View.VISIBLE : View.GONE);
        refreshButton.setEnabled(!value);
        fetchButton.setEnabled(!value);
        firstInput.setEnabled(!value);
        secondInput.setEnabled(!value);
        updateActions();
    }

    private void updateActions() {
        testButton.setEnabled(!busy && !previewNodes.isEmpty());
        installButton.setEnabled(!busy && !testedTag.isEmpty() && testedTag.equals(selectedTag));
        if (automaticButton != null && routerStatus != null)
            automaticButton.setEnabled(!busy && !"auto".equals(routerStatus.selection));
    }

    private void showMessage(String value, int color) {
        messageText.setText(value);
        messageText.setTextColor(color);
    }

    private LinearLayout card(LinearLayout parent) {
        LinearLayout card = vertical();
        card.setPadding(dp(16), dp(16), dp(16), dp(16));
        card.setBackground(rounded(Color.WHITE, 18, BORDER));
        LinearLayout.LayoutParams space = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        space.bottomMargin = dp(14);
        parent.addView(card, space);
        return card;
    }

    private LinearLayout vertical() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private TextView text(String value, int size, int color, int weight) {
        TextView view = new TextView(this);
        view.setText(value);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(weight == Typeface.BOLD ? boldFont : regularFont);
        return view;
    }

    private EditText input(String hint) {
        EditText view = new EditText(this);
        view.setSingleLine(true);
        view.setTextSize(14);
        view.setTypeface(regularFont);
        view.setHint(hint);
        view.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        view.setTransformationMethod(PasswordTransformationMethod.getInstance());
        view.setPadding(dp(12), dp(11), dp(12), dp(11));
        view.setBackground(rounded(BG, 11, BORDER));
        return view;
    }

    private Button button(String label, boolean prominent, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setTextSize(13);
        button.setTypeface(semiboldFont);
        button.setTextColor(prominent ? Color.WHITE : BLUE);
        button.setPadding(dp(13), dp(7), dp(13), dp(7));
        button.setMinHeight(dp(42));
        button.setBackground(rounded(prominent ? BLUE : Color.rgb(235, 241, 254), 11, null));
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private GradientDrawable rounded(int fill, int radius, Integer border) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setCornerRadius(dp(radius));
        if (border != null) drawable.setStroke(dp(1), border);
        return drawable;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override protected void onDestroy() {
        worker.shutdownNow();
        super.onDestroy();
    }
}
