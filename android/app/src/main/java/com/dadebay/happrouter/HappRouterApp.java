package com.dadebay.happrouter;

import android.app.Application;

public final class HappRouterApp extends Application {
    @Override public void onCreate() {
        super.onCreate();
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler((thread, error) -> {
            ErrorReport.record(this, error);
            if (previous != null) previous.uncaughtException(thread, error);
        });
    }
}
