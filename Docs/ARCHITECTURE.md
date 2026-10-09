# Mimari ve ilerleme

- **macOS uygulaması:** SwiftUI; router durumunu SSH üzerinden okur. URL Keychain'de saklanır.
- **Controller:** `Scripts/routerctl.py`; VLESS WebSocket/TLS aboneliğini ayrıştırır, Xray yapılandırmasını üretir ve doğrular.
- **Router:** OpenWrt 24.10.5, Xray 25.1.30. Aynı anda yalnızca bir VLESS profili ve eski Shadowsocks yedeği yüklenir. Xray'in çok sayıda profili eşzamanlı izlemesi 64 MB cihazı aşırı yüklediğinden etkin değildir.
- **Durum:** Cihazlar DHCP ve Wi-Fi istasyonlarından çıkarılır. Xray Metrics şu an etkin değildir; arayüzdeki sunucu gecikmeleri ayrı bir TCP probundan gelir.
- **Süre dolumu:** `expiry-check.sh` cron ile çalışır; `mode.sh` doğrudan internet moduna geçirir. Uçtan uca geçiş testi bekliyor.
- **Gezinme:** Genel Bakış özet sunar; VPN Ayarları test/sunucu/abonelik işlemlerini, Router trafik ve paylaşım modunu, Cihazlar bağlı istemcileri gösterir.
- **Cihaz kullanımı:** `usage-sample.lua`, Wi-Fi istasyon sayaçlarını dakikada bir biriktirir. Ashgabat gününe göre toplam `/tmp/happvpn` içinde tutulur ve saatte bir kalıcı depoya yazılır. Uygulama ardışık okumaların farkından KB/sn hesaplar.
- **Hafif aday ölçümü:** `probe-nodes.lua`, her 30 dakikada 16 TCP uç noktasını sırayla dener. TCP erişimi VLESS oturumunun çalıştığını göstermez; otomatik trafik geçişini tetiklemez.
- **Güvenlik:** VPN modunda LAN→WAN doğrudan yönlendirme kapalıdır. Özel anahtar ve abonelik dosyaları depoya alınmaz.

## Kalan doğrulama

1. Router'da seçili VLESS profiliyle gerçek çıkış IP'sini doğrula. Mac üzerinde aynı profil ve router WAN yolu başarıyla test edildi; router Xray el sıkışması ayrıca sınanıyor.
2. Otomatik en düşük gecikme geçişini yalnızca başarılı VPN trafik testi sonrasında etkinleştir.
3. Xray yeniden başlatması için eklenen hazır olma kontrolü ve otomatik geri almayı gerçek abonelik yenilemesinde doğrula.
4. Abonelik süresi dolunca doğrudan internete geçişi ve telefon trafiğini test et.
