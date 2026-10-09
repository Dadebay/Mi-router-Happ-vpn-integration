# Mimari ve ilerleme

- **macOS uygulaması:** SwiftUI; router durumunu SSH üzerinden okur. URL Keychain'de saklanır.
- **Controller:** `Scripts/routerctl.py`; VLESS WebSocket/TLS aboneliğini ayrıştırır, Xray yapılandırmasını üretir ve doğrular.
- **Router:** OpenWrt 24.10.5, Xray 25.1.30. Aynı anda yalnızca bir VLESS profili ve eski Shadowsocks yedeği yüklenir. Xray'in çok sayıda profili eşzamanlı izlemesi 64 MB cihazı aşırı yüklediğinden etkin değildir.
- **Durum:** Cihazlar DHCP ve Wi-Fi istasyonlarından çıkarılır. Xray Metrics şu an etkin değildir; arayüzdeki sunucu gecikmeleri ayrı bir TCP probundan gelir.
- **Süre dolumu:** `expiry-check.sh` cron ile çalışır; `mode.sh` doğrudan internet moduna geçirir. Uçtan uca geçiş testi bekliyor.
- **Gezinme:** Genel Bakış özet sunar; VPN Ayarları test/sunucu/abonelik işlemlerini, Router trafik ve paylaşım modunu, Cihazlar bağlı istemcileri gösterir.
- **Cihaz kullanımı:** `usage-sample.lua`, Wi-Fi istasyon sayaçlarını dakikada bir biriktirir. Ashgabat gününe göre toplam `/tmp/happvpn` içinde tutulur ve saatte bir kalıcı depoya yazılır. Uygulama ardışık okumaların farkından KB/sn hesaplar.
- **Hafif aday ölçümü:** `probe-nodes.lua`, her 30 dakikada 16 TCP uç noktasını sırayla dener. TCP erişimi VLESS oturumunun çalıştığını göstermez; otomatik trafik geçişini tetiklemez.
- **Kurulum ve hata ayıklama:** macOS uygulamasındaki kurulum düğmesi mevcut OpenWrt/Xray temelini kontrol edip yardımcı betikleri ve cron görevlerini idempotent biçimde yükler. Günlük ekranı son Xray olaylarını gösterir; canlı test gerçek VPN çıkış IP'sini doğrular. Eksik firmware/Xray çekirdeği kurulum düğmesi tarafından yüklenmez.
- **Güvenlik:** VPN modunda LAN→WAN doğrudan yönlendirme kapalıdır. Özel anahtar ve abonelik dosyaları depoya alınmaz.

## Kalan doğrulama

9 Ekim 2026 canlı tanı: Router WAN üzerinden VLESS sunucusuna TCP, TLS 1.2 ve WebSocket 101 el sıkışmaları başarılı. Aynı abonelik profili Mac Xray ile doğrudan gerçek çıkış IP'si veriyor. Router üzerindeki 25.1.30 MIPSLE Xray çekirdeği geçici yalnızca SOCKS + freedom yapılandırmasında bile dört dakika içinde dinleme portu açamadı; `top` ölçümünde %97 sistem CPU kullanımı ve yaklaşık 6 yük ortalaması görüldü. Takılan Xray işlemi durdurulduktan sonra CPU %100 boşta kaldı. Router `direct` modda normal WAN paylaşımına devam ediyor. Bu nedenle mevcut Xray ile VPN modu ve otomatik sunucu geçişi etkinleştirilmemelidir. Çalışan ve ölçülmüş daha hafif bir router istemcisi veya farklı donanım gerekir.

8 Ekim akşamı telefonda doğrulanan `78.232.43.x` VPN çıkışı VLESS değil, eski Shadowsocks `happ-vpn` profilindendi. Eski profil `/etc/xray/config.json.last-good` ve `config.json.ss-lastgood` dosyalarında korunuyor. Sonraki VLESS denemesi etkin yapılandırmayı `node-00` profiline, paylaşımı `direct` moda çevirdi. 9 Ekim'deki yeni kontrolde eski Shadowsocks sunucusu router WAN'ından TCP `connection refused` döndürdü; Mac'in ayrı internet yolundan erişilebildi. Yeni aboneliğin 16 VLESS sunucusunun tümü Mac üzerinde router WAN tüneli kullanılarak gerçek çıkış testiyle denendi ve başarısız oldu; TCP erişim değerleri çalışmayı kanıtlamıyor. Eski profili VPN modunda etkinleştirmek şu anda istemci internetini keseceğinden yapılmadı.

1. Router'da seçili VLESS profiliyle gerçek çıkış IP'sini doğrula. Mac üzerinde aynı profil ve router WAN yolu başarıyla test edildi; router Xray, varsayılan TLS ve TLS 1.2 ile 60 saniyelik HTTPS ve 120 saniyelik HTTP denemelerinde zaman aşımına uğradı.
2. Otomatik en düşük gecikme geçişini yalnızca başarılı VPN trafik testi sonrasında etkinleştir.
3. Xray yeniden başlatması için eklenen hazır olma kontrolü ve otomatik geri almayı gerçek abonelik yenilemesinde doğrula.
4. Abonelik süresi dolunca doğrudan internete geçişi ve telefon trafiğini test et.
