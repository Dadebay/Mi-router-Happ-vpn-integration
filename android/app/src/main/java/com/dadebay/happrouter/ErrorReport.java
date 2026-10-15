package com.dadebay.happrouter;

import android.content.Context;
import android.os.Build;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

final class ErrorReport {
    private static final int MAX_EVENTS = 100;
    private static final long RETENTION_SECONDS = 30L * 24 * 60 * 60;
    private static final DateTimeFormatter FILENAME_DATE =
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss-SSS").withZone(ZoneOffset.UTC);

    private ErrorReport() { }

    static synchronized void record(Context context, Throwable error) {
        try {
            File log = new File(context.getFilesDir(), "errors.log");
            long now = Instant.now().getEpochSecond();
            List<String> entries = recentEntries(log, now);
            StringBuilder event = new StringBuilder();
            event.append(now).append(" | ").append(Instant.ofEpochSecond(now));
            Throwable cause = error;
            for (int depth = 0; cause != null && depth < 3; depth++, cause = cause.getCause()) {
                event.append(depth == 0 ? " | " : " | caused by ")
                        .append(cause.getClass().getName()).append(": ")
                        .append(sanitize(cause.getMessage()));
                StackTraceElement[] trace = cause.getStackTrace();
                for (int i = 0; i < Math.min(6, trace.length); i++) {
                    StackTraceElement frame = trace[i];
                    event.append(" | at ").append(frame.getClassName()).append('.')
                            .append(frame.getMethodName()).append(':').append(frame.getLineNumber());
                }
            }
            entries.add(event.toString());
            if (entries.size() > MAX_EVENTS)
                entries = new ArrayList<>(entries.subList(entries.size() - MAX_EVENTS, entries.size()));
            write(log, String.join("\n", entries) + "\n");
        } catch (Exception ignored) {
            // Diagnostic storage must never interrupt the app or its crash handler.
        }
    }

    static synchronized File export(Context context) throws Exception {
        Instant instant = Instant.now();
        long now = instant.getEpochSecond();
        File directory = new File(context.getCacheDir(), "reports");
        if (!directory.exists() && !directory.mkdirs()) throw new Exception("Cannot create report directory");
        File[] oldReports = directory.listFiles();
        if (oldReports != null) for (File old : oldReports) {
            if (old.isFile() && old.lastModified() < System.currentTimeMillis() - 7L * 24 * 60 * 60 * 1000)
                old.delete();
        }
        File report = new File(directory,
                "HappRouter-errors-" + FILENAME_DATE.format(instant) + ".txt");
        List<String> entries = recentEntries(new File(context.getFilesDir(), "errors.log"), now);
        String version = context.getPackageManager().getPackageInfo(context.getPackageName(), 0).versionName;
        String header = "HappRouter error report\n"
                + "Generated (UTC): " + Instant.ofEpochSecond(now) + "\n"
                + "App version: " + version + "\n"
                + "Android: " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")\n"
                + "Device: " + sanitize(Build.MANUFACTURER + " " + Build.MODEL) + "\n"
                + "Language: " + AppLanguage.current(context) + "\n"
                + "Events (last 30 days, up to 100): " + entries.size() + "\n\n";
        write(report, header + (entries.isEmpty() ? "No errors recorded.\n"
                : String.join("\n", entries) + "\n"));
        return report;
    }

    private static List<String> recentEntries(File file, long now) throws Exception {
        List<String> entries = new ArrayList<>();
        if (!file.exists()) return entries;
        for (String line : Files.readAllLines(file.toPath(), StandardCharsets.UTF_8)) {
            int separator = line.indexOf(" | ");
            if (separator < 1) continue;
            try {
                long time = Long.parseLong(line.substring(0, separator));
                if (time >= now - RETENTION_SECONDS && time <= now + 60) entries.add(line);
            } catch (NumberFormatException ignored) { }
        }
        if (entries.size() > MAX_EVENTS)
            return new ArrayList<>(entries.subList(entries.size() - MAX_EVENTS, entries.size()));
        return entries;
    }

    static String sanitize(String value) {
        if (value == null) return "";
        String safe = value.replaceAll("(?i)(?:https?|ss|happ)://[^\\s\\\"']+", "[redacted-link]")
                .replaceAll("(?i)(password|passwd|token|secret|private[_-]?key)\\s*[:=]\\s*[^\\s,;]+",
                        "$1=[redacted]")
                .replaceAll("(?i)ssh-rsa\\s+[A-Za-z0-9+/=]+", "[redacted-key]")
                .replace('\n', ' ').replace('\r', ' ');
        return safe.length() > 400 ? safe.substring(0, 400) + "…" : safe;
    }

    private static void write(File file, String text) throws Exception {
        try (FileOutputStream output = new FileOutputStream(file)) {
            output.write(text.getBytes(StandardCharsets.UTF_8));
        }
    }
}
