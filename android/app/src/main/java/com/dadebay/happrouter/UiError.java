package com.dadebay.happrouter;

import android.content.Context;

final class UiError {
    private UiError() { }

    static String message(Context context, Exception error) {
        String detail = error.getMessage();
        if (detail == null || detail.isEmpty()) return context.getString(R.string.generic_error);
        int resource = switch (detail) {
            case "İlk abonelik veya sunucu profili gerekli." -> R.string.parser_first_required;
            case "Profil çok büyük." -> R.string.parser_profile_large;
            case "Her aboneliği ayrı alana yapıştırın." -> R.string.parser_separate_fields;
            case "İki abonelik için iki HTTPS adresi girin." -> R.string.parser_two_https;
            case "Şifreli Happ bağlantısı desteklenmiyor; Shadowsocks bağlantısı kullanın." -> R.string.parser_happ_unsupported;
            case "İkinci alan yalnızca HTTPS aboneliği içindir." -> R.string.parser_second_https;
            case "Shadowsocks sunucusu bulunamadı." -> R.string.parser_no_ss;
            case "En fazla 200 sunucu desteklenir." -> R.string.parser_max_servers;
            case "Abonelik adresi geçersiz." -> R.string.parser_url_invalid;
            case "Abonelik yanıtı çok büyük." -> R.string.parser_response_large;
            case "Abonelikte Shadowsocks sunucusu bulunamadı." -> R.string.parser_no_ss_in_sub;
            case "Abonelik HTTPS olmalı." -> R.string.parser_https_only;
            case "Abonelik yanıt vermedi." -> R.string.parser_no_response;
            case "Abonelik okunamadı. Telefonun internetini kontrol edin." -> R.string.parser_read_failed;
            case "Sunucu JSON biçimi geçersiz." -> R.string.parser_json_invalid;
            case "Shadowsocks bağlantısı geçersiz." -> R.string.parser_ss_invalid;
            case "Eklentili Shadowsocks sunucusu desteklenmiyor." -> R.string.parser_ss_plugin;
            case "Shadowsocks kimliği geçersiz." -> R.string.parser_ss_credentials;
            case "Shadowsocks adresi geçersiz." -> R.string.parser_ss_address;
            case "Sunucu adresi veya portu geçersiz." -> R.string.parser_server_port;
            case "Şifreleme yöntemi desteklenmiyor." -> R.string.parser_cipher;
            case "Sunucu parolası geçersiz." -> R.string.parser_password;
            default -> 0;
        };
        return resource == 0 ? detail : context.getString(resource);
    }
}
