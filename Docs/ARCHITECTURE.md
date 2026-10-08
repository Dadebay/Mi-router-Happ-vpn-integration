# Mimari ve ilerleme

- **macOS uygulaması:** SwiftUI; router durumunu SSH üzerinden okur. URL Keychain'de saklanır.
- **Controller:** `Scripts/routerctl.py`; VLESS WebSocket/TLS aboneliğini ayrıştırır, Xray yapılandırmasını üretir ve doğrular.
- **Router:** OpenWrt 24.10.5, Xray 25.1.30. `observatory` ve `leastPing` adaylar için hazırlanmıştır. Canlı trafik doğrulama tamamlanana kadar `happ-vpn` Shadowsocks profiline sabittir.
- **Durum:** Xray Metrics router localhost adresinden SSH ile okunur. Cihazlar DHCP ve Wi-Fi istasyonlarından çıkarılır.
- **Süre dolumu:** `expiry-check.sh` cron ile çalışır; `mode.sh` doğrudan internet moduna geçirir. Uçtan uca geçiş testi bekliyor.
- **Gezinme:** Genel Bakış özet sunar; VPN Ayarları test/sunucu/abonelik işlemlerini, Router trafik ve paylaşım modunu, Cihazlar bağlı istemcileri gösterir.
- **Güvenlik:** VPN modunda LAN→WAN doğrudan yönlendirme kapalıdır. Özel anahtar ve abonelik dosyaları depoya alınmaz.

## Kalan doğrulama

1. Router'da Metrics ve aday ölçümlerini doğrula.
2. Çalışan adaylara router WAN üzerinden erişilebilirliği test et.
3. Otomatik en düşük gecikme geçişini yalnızca başarılı trafik testi sonrasında etkinleştir.
4. Xray yeniden başlatması için hazır olma kontrolü ve otomatik geri alma ekle.
5. Abonelik süresi dolunca doğrudan internete geçişi ve telefon trafiğini test et.
