# Mimari ve ilerleme

- **macOS uygulaması:** SwiftUI; router durumunu SSH üzerinden okur. URL Keychain'de saklanır.
- **Controller:** `Scripts/routerctl.py`; VLESS WebSocket/TLS aboneliğini ayrıştırır, Xray yapılandırmasını üretir ve doğrular.
- **Router:** OpenWrt 24.10.5, Xray 25.1.30. `observatory` ve `leastPing` adaylar için hazırlanmıştır. Canlı trafik doğrulama tamamlanana kadar `happ-vpn` Shadowsocks profiline sabittir.
- **Durum:** Xray Metrics için okuma kodu hazırdır; çok sayıda adayın router işlemcisinde oluşturduğu yük nedeniyle izleme şu anda devre dışıdır. Cihazlar DHCP ve Wi-Fi istasyonlarından çıkarılır.
- **Süre dolumu:** `expiry-check.sh` cron ile çalışır; `mode.sh` doğrudan internet moduna geçirir. Uçtan uca geçiş testi bekliyor.
- **Gezinme:** Genel Bakış özet sunar; VPN Ayarları test/sunucu/abonelik işlemlerini, Router trafik ve paylaşım modunu, Cihazlar bağlı istemcileri gösterir.
- **Cihaz kullanımı:** `usage-sample.lua`, Wi-Fi istasyon sayaçlarını dakikada bir biriktirir. Ashgabat gününe göre toplam `/tmp/happvpn` içinde tutulur ve saatte bir kalıcı depoya yazılır. Uygulama ardışık okumaların farkından KB/sn hesaplar.
- **Hafif aday ölçümü:** `probe-nodes.lua`, her 30 dakikada 16 TCP uç noktasını sırayla dener. TCP erişimi VLESS oturumunun çalıştığını göstermez; otomatik trafik geçişini tetiklemez.
- **Güvenlik:** VPN modunda LAN→WAN doğrudan yönlendirme kapalıdır. Özel anahtar ve abonelik dosyaları depoya alınmaz.

## Kalan doğrulama

1. Router işlemci ve bellek sınırına uygun daha küçük aday grubuyla Metrics ölçümünü doğrula.
2. Çalışan adaylara router WAN üzerinden erişilebilirliği test et.
3. Otomatik en düşük gecikme geçişini yalnızca başarılı trafik testi sonrasında etkinleştir.
4. Xray yeniden başlatması için eklenen hazır olma kontrolü ve otomatik geri almayı gerçek abonelik yenilemesinde doğrula.
5. Abonelik süresi dolunca doğrudan internete geçişi ve telefon trafiğini test et.
