package com.dadebay.happrouter;

import android.app.Activity;
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
        TextView subtitle = text("Mi Router 4C · VPN yönetimi", 14, MUTED, Typeface.NORMAL);
        subtitle.setPadding(0, dp(3), 0, dp(20));
        page.addView(subtitle);

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
        savedNodes = vertical();
        savedNodes.setPadding(0, dp(10), 0, 0);
        status.addView(savedNodes);

        pairingCard = card(page);
        pairingCard.addView(text("Telefonu eşleştir", 17, DARK, Typeface.BOLD));
        TextView pairingInfo = text("Telefon kendi SSH anahtarını oluşturdu. Açık anahtarı Mac'e aktar ve "
                + "Scripts/pair-android.sh ile router'a ekle. Özel anahtar yalnızca bu telefonda kalır.",
                13, MUTED, Typeface.NORMAL);
        pairingInfo.setPadding(0, dp(8), 0, dp(10));
        pairingCard.addView(pairingInfo);
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
            startActivity(Intent.createChooser(share, "Açık anahtarı Mac'e gönder"));
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
        testedText = text("Önce bir sunucuyu test et. Test mevcut bağlantıyı değiştirmez.",
                13, MUTED, Typeface.NORMAL);
        testedText.setPadding(0, dp(10), 0, dp(10));
        previewSection.addView(testedText);
        testButton = button("Bağlantıyı test et", false, this::testSelected);
        previewSection.addView(testButton);
        TextView expiryLabel = text("Abonelik bitiş günü", 12, MUTED, Typeface.BOLD);
        expiryLabel.setPadding(0, dp(18), 0, dp(4));
        previewSection.addView(expiryLabel);
        expiryInput = input("Bitiş günü");
        expiryInput.setFocusable(false);
        expiryInput.setOnClickListener(view -> chooseDate());
        previewSection.addView(expiryInput);
        installButton = button("Test edilen sunucuyu kur", true, this::installSelected);
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
            renderSavedNodes();
            if (expiryInput.getText().length() == 0 && status.expiry > 0)
                expiryInput.setText(Instant.ofEpochSecond(status.expiry)
                        .atZone(ZoneId.systemDefault()).toLocalDate().toString());
        }, error -> {
            connectionText.setText("Router'a bağlanılamadı · HappVPN Wi-Fi bağlantısını kontrol et.");
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
            String name = node.name + (active ? " · Aktif" : "");
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

    private void fetchProfiles() {
        String first = firstInput.getText().toString();
        String second = secondInput.getText().toString();
        background(() -> SubscriptionParser.parseInputs(first, second, SubscriptionParser::fetchHttps), nodes -> {
            previewNodes = nodes;
            selectedTag = nodes.get(0).tag;
            testedTag = "";
            testedIp = "";
            try {
                secrets.write("first", first.trim());
                secrets.write("second", second.trim());
            } catch (Exception error) {
                showMessage("Abonelik adresleri güvenli depoya kaydedilemedi.", ERROR);
            }
            renderPreview();
            showMessage(nodes.size() + " sunucu getirildi. Şimdi bağlantıyı test et.", BLUE);
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
            radio.setPadding(dp(4), dp(7), 0, dp(7));
            radio.setButtonTintList(android.content.res.ColorStateList.valueOf(BLUE));
            radio.setOnClickListener(view -> {
                selectedTag = node.tag;
                testedTag = "";
                testedIp = "";
                testedText.setText("Önce bu sunucuyu test et. Test mevcut bağlantıyı değiştirmez.");
                updateActions();
            });
            previewChoices.addView(radio);
            if (node.tag.equals(selectedTag)) previewChoices.check(radio.getId());
        }
        testedText.setText(testedTag.isEmpty()
                ? "Önce bir sunucuyu test et. Test mevcut bağlantıyı değiştirmez."
                : "Bağlantı başarılı · Çıkış IP: " + testedIp);
        testedText.setTextColor(testedTag.isEmpty() ? MUTED : SUCCESS);
        updateActions();
    }

    private void testSelected() {
        VpnProfile node = selectedProfile();
        if (node == null) return;
        background(() -> gateway.testCandidate(node), ip -> {
            testedTag = node.tag;
            testedIp = ip;
            testedText.setText("Bağlantı başarılı · Çıkış IP: " + ip);
            testedText.setTextColor(SUCCESS);
            updateActions();
            showMessage("Sunucu çalışıyor. Kuruluma hazır.", SUCCESS);
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
        view.setTypeface(Typeface.DEFAULT, weight);
        return view;
    }

    private EditText input(String hint) {
        EditText view = new EditText(this);
        view.setSingleLine(true);
        view.setTextSize(14);
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
        button.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
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
