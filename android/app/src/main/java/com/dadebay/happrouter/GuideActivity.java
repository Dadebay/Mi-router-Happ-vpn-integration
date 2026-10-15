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

public final class GuideActivity extends AppLanguage.Screen {
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

        Button back = button(getString(R.string.guide_back), false, this::finish);
        page.addView(back);
        TextView title = text(getString(R.string.guide_title), 28, DARK, bold);
        title.setPadding(0, dp(15), 0, dp(3));
        page.addView(title);
        TextView intro = text(getString(R.string.guide_intro),
                14, MUTED, regular);
        intro.setPadding(0, 0, 0, dp(18));
        page.addView(intro);

        step(1, getString(R.string.guide_step1_title), getString(R.string.guide_step1_body));
        step(2, getString(R.string.guide_step2_title), getString(R.string.guide_step2_body));
        step(3, getString(R.string.guide_step3_title), getString(R.string.guide_step3_body));
        LinearLayout pairingActions = row();
        pairingActions.setPadding(0, 0, 0, dp(14));
        page.addView(pairingActions);
        Button copy = button(getString(R.string.guide_copy_key), false, this::copyPublicKey);
        pairingActions.addView(copy, new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        Button web = button(getString(R.string.guide_router_page), false, () -> {
            Intent browser = new Intent(Intent.ACTION_VIEW,
                    Uri.parse("http://" + RouterAddress.get(this)));
            startActivity(browser);
        });
        LinearLayout.LayoutParams webSpace = new LinearLayout.LayoutParams(0,
                ViewGroup.LayoutParams.WRAP_CONTENT, 1);
        webSpace.leftMargin = dp(8);
        pairingActions.addView(web, webSpace);

        step(4, getString(R.string.guide_step4_title), getString(R.string.guide_step4_body));
        step(5, getString(R.string.guide_step5_title), getString(R.string.guide_step5_body));
        step(6, getString(R.string.guide_step6_title), getString(R.string.guide_step6_body));

        LinearLayout problems = card();
        problems.addView(text(getString(R.string.guide_troubleshoot_title), 17, DARK, bold));
        TextView tips = text(getString(R.string.guide_troubleshoot_body),
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
            clipboard.setPrimaryClip(ClipData.newPlainText(getString(R.string.key_clip_label), key));
            Toast.makeText(this, R.string.guide_key_copied, Toast.LENGTH_SHORT).show();
        } catch (Exception error) {
            ErrorReport.record(this, error);
            Toast.makeText(this, R.string.guide_key_failed, Toast.LENGTH_LONG).show();
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
