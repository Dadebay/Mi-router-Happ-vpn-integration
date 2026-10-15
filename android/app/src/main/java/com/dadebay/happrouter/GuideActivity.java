package com.dadebay.happrouter;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

public final class GuideActivity extends Activity {
    private static final int BLUE = Color.rgb(34, 103, 234);
    private static final int DARK = Color.rgb(26, 35, 52);
    private static final int MUTED = Color.rgb(102, 115, 137);
    private static final int BG = Color.rgb(245, 247, 251);
    private static final int BORDER = Color.rgb(225, 231, 239);

    private Typeface regular;
    private Typeface semibold;
    private Typeface bold;
    private LinearLayout page;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        regular = getResources().getFont(R.font.gilroy_regular);
        semibold = getResources().getFont(R.font.gilroy_semibold);
        bold = getResources().getFont(R.font.gilroy_bold);
        getWindow().setStatusBarColor(BG);
        getWindow().setNavigationBarColor(BG);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        build();
    }

    private void build() {
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BG);
        page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setPadding(dp(18), dp(22), dp(18), dp(32));
        scroll.addView(page);
        setContentView(scroll);

        Button back = button("←  HappRouter'a dön", false, this::finish);
        page.addView(back);
        TextView title = text("Telefondan kurulum", 28, DARK, bold);
        title.setPadding(0, dp(15), 0, dp(3));
        page.addView(title);
        TextView intro = text("Bilgisayar gerekmez. Bu adımları router'ın yanındaki Android telefonda sırayla yap.",
                14, MUTED, regular);
        intro.setPadding(0, 0, 0, dp(18));
        page.addView(intro);

        step(1, "HappVPN Wi-Fi ağına bağlan",
                "Telefonun Wi-Fi ayarlarından HappVPN ağına gir. Android “İnternet yok” derse “Bağlı kal”ı seç. "
                        + "Uygulama router'a yalnız aynı yerel ağdan erişebilir.");
        step(2, "Router adresini doğrula",
                "HappRouter ana ekranında varsayılan adres 192.168.1.1. Bağlanmıyorsa Wi-Fi ayrıntılarındaki "
                        + "Ağ geçidi / Gateway adresini yazıp “Bağlan”a bas. Farklı router'ın adresi "
                        + "güvenlik kontrolünden geçmez.");
        step(3, "Telefonu bir kez eşleştir",
                "Ana ekrandaki “Telefonu eşleştir” bölümüne router yönetici parolasını gir. Parola uygulamada "
                        + "saklanmaz. Eşleştirme tamamlanınca “Yenile”ye bas.\n\n"
                        + "Parola ile SSH girişi kapalıysa aşağıdan açık anahtarı kopyala. Router'ın yönetim "
                        + "sayfasında System → Administration → SSH-Keys bölümüne yapıştırıp Add key'e bas. "
                        + "Sonra uygulamada “Yenile”ye bas. Yönetici parolan yoksa açık anahtarı router'a "
                        + "zaten erişebilen kişiye gönder; mevcut yetki olmadan eşleştirme yapılamaz.");
        LinearLayout pairingActions = row();
        pairingActions.setPadding(0, 0, 0, dp(14));
        page.addView(pairingActions);
        Button copy = button("Açık anahtarı kopyala", false, this::copyPublicKey);
        pairingActions.addView(copy, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        Button web = button("Router sayfası", false, () -> {
            Intent browser = new Intent(Intent.ACTION_VIEW,
                    Uri.parse("http://" + RouterAddress.get(this)));
            startActivity(browser);
        });
        LinearLayout.LayoutParams webSpace = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        webSpace.leftMargin = dp(8);
        pairingActions.addView(web, webSpace);

        step(4, "VPN aboneliğini ekle",
                "Ana ekranda bir veya iki HTTPS abonelik adresini yapıştır ve “Sunucuları getir”e bas. "
                        + "Tüm Shadowsocks sunucuları tek listede çıkar. happ://crypt5, VLESS ve Hysteria "
                        + "bu router'da çalışmaz; Shadowsocks gerekir. Abonelik adresini kimseyle paylaşma.");
        step(5, "Test et ve kur",
                "“En uygun sunucuyu bul ve test et”e bas. Uygulama router üzerinden gecikmesi düşük çalışan "
                        + "sunucuyu bulur. Aboneliğin bitiş gününü seç ve “Tüm sunucuları kur”a bas. "
                        + "İstersen listeden bir sunucuyu elle seçebilirsin.");
        step(6, "VPN çıkışını kontrol et",
                "“VPN modu”nu açıp “Yenile”ye bas. “VPN açık” ve bir “Çıkış IP” görünüyorsa router "
                        + "VPN üzerinden internete çıkıyor. Otomatik seçim açıkken router çalışan sunucular "
                        + "arasından en düşük gecikmeliyi seçer.");

        LinearLayout problems = card();
        problems.addView(text("Bir adım çalışmazsa", 17, DARK, bold));
        TextView tips = text("• Router bulunamıyor: Wi-Fi ve ağ geçidi adresini kontrol et.\n"
                + "• Host key hatası: Bu IP başka router'a ait. Doğru ağa bağlan.\n"
                + "• Eşleştirme hatası: Parolayı kontrol et veya SSH-Keys yolunu kullan.\n"
                + "• Abonelik inmiyor: Profilleri mobil veriyle getir, testten önce HappVPN Wi-Fi'ye dön.\n"
                + "• VPN testi geçmiyor: Başka Shadowsocks sunucusu dene; mevcut bağlantı korunur.",
                13, MUTED, regular);
        tips.setPadding(0, dp(9), 0, 0);
        tips.setLineSpacing(dp(4), 1f);
        problems.addView(tips);
    }

    private void step(int number, String title, String body) {
        LinearLayout card = card();
        LinearLayout heading = row();
        card.addView(heading);
        TextView badge = text(Integer.toString(number), 13, Color.WHITE, bold);
        badge.setGravity(Gravity.CENTER);
        badge.setBackground(rounded(BLUE, 40, null));
        heading.addView(badge, new LinearLayout.LayoutParams(dp(28), dp(28)));
        TextView name = text(title, 16, DARK, bold);
        LinearLayout.LayoutParams nameSpace = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        nameSpace.leftMargin = dp(10);
        heading.addView(name, nameSpace);
        TextView description = text(body, 13, MUTED, regular);
        description.setPadding(0, dp(10), 0, 0);
        description.setLineSpacing(dp(3), 1f);
        card.addView(description);
    }

    private void copyPublicKey() {
        try {
            String key = new DeviceIdentity(this).publicKey();
            ClipboardManager clipboard = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            clipboard.setPrimaryClip(ClipData.newPlainText("HappRouter açık anahtar", key));
            Toast.makeText(this, "Açık anahtar kopyalandı", Toast.LENGTH_SHORT).show();
        } catch (Exception error) {
            Toast.makeText(this, "Anahtar okunamadı", Toast.LENGTH_LONG).show();
        }
    }

    private LinearLayout card() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(16), dp(16), dp(16), dp(16));
        box.setBackground(rounded(Color.WHITE, 18, BORDER));
        LinearLayout.LayoutParams space = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        space.bottomMargin = dp(12);
        page.addView(box, space);
        return box;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private TextView text(String content, int size, int color, Typeface face) {
        TextView view = new TextView(this);
        view.setText(content);
        view.setTextSize(size);
        view.setTextColor(color);
        view.setTypeface(face);
        return view;
    }

    private Button button(String label, boolean primary, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setTextSize(13);
        button.setTypeface(semibold);
        button.setTextColor(primary ? Color.WHITE : BLUE);
        button.setPadding(dp(10), dp(6), dp(10), dp(6));
        button.setMinHeight(dp(42));
        button.setBackground(rounded(primary ? BLUE : Color.rgb(235, 241, 254), 11, null));
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private GradientDrawable rounded(int fill, int radius, Integer stroke) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(fill);
        drawable.setCornerRadius(dp(radius));
        if (stroke != null) drawable.setStroke(dp(1), stroke);
        return drawable;
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
