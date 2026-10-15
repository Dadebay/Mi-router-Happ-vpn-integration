package com.dadebay.happrouter;

import android.app.Activity;
import android.content.Context;
import android.content.res.Configuration;

import java.util.Locale;

final class AppLanguage {
    private static final String DEFAULT_LANGUAGE = "tk";

    static String current(Context context) {
        String value = context.getSharedPreferences("app_settings", Context.MODE_PRIVATE)
                .getString("language", DEFAULT_LANGUAGE);
        return supported(value) ? value : DEFAULT_LANGUAGE;
    }

    static void select(Context context, String language) {
        if (!supported(language)) throw new IllegalArgumentException("Unsupported language");
        context.getSharedPreferences("app_settings", Context.MODE_PRIVATE)
                .edit().putString("language", language).apply();
    }

    static Context wrap(Context context) {
        Configuration configuration = new Configuration(context.getResources().getConfiguration());
        configuration.setLocale(Locale.forLanguageTag(current(context)));
        return context.createConfigurationContext(configuration);
    }

    private static boolean supported(String language) {
        return "tk".equals(language) || "ru".equals(language) || "en".equals(language);
    }

    static abstract class Screen extends Activity {
        @Override protected void attachBaseContext(Context base) {
            super.attachBaseContext(AppLanguage.wrap(base));
        }
    }
}
