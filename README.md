# HappRouter

Xiaomi Mi Router 4C üzerindeki OpenWrt ve Xray için macOS kontrol paneli.

## Durum

- VPN durumu ve router üzerinden gerçek çıkış IP testi
- Wi-Fi/VPN veri sayaçları ve bağlı cihazlar
- Abonelikten gelen sunucu adları, ülke etiketleri ve varsa gecikme ölçümleri
- Yeni HTTPS abonelik URL'sini kontrol etme ve router'a kurma
- Abonelik bitiş tarihi ve süre dolunca doğrudan internete geçiş görevi
- Genel Bakış, VPN Ayarları, Router ve Cihazlar için ayrı gezinme sayfaları
- Router sayfasından VPN/doğrudan internet modu arasında elle geçiş
- Cihazlar sayfasında Wi-Fi cihazı başına indirme hızı ve bugün indirilen veri

VLESS WebSocket/TLS adayları için hafif TCP erişim testi 30 dakikada bir çalışır. Bu ölçüm VPN kimlik doğrulamasını veya gerçek çıkış hızını kanıtlamaz. Otomatik sunucu seçimi üzerinde çalışılıyor. Şu anda kullanıcı trafiği çalışan Happ Shadowsocks profiline sabitlenmiştir; adaylar canlı trafiği değiştirmez. `n/a`, TCP bağlantısının kurulamadığını veya ölçümün bulunmadığını gösterir. Ülke bayrakları sağlayıcının etiketidir, fiziksel konum kanıtı değildir.

## Kullanım

Uygulama router'a `192.168.1.1` adresinden SSH ile bağlanır. Yerel SSH anahtarını `~/.happ-router` altında kullanır. Mac'in Wi-Fi ayarlarını değiştirmez. Router'daki VPN ve süre dolumu görevi Mac kapalıyken çalışır.

Yeni abonelik için önce **Profilleri kontrol et**, ardından **Router'a kur** düğmelerini kullan. Kurulum önce Xray JSON'unu doğrular ve mevcut yapılandırmayı yedekler. Router yeniden başlatması 10 dakikayı aşabilir. Kurulum, VPN çıkışını doğrulayamazsa önceki yapılandırmaya döner ve router doğrudan internet modunda kalır. Sunucular arasında otomatik geçiş henüz tamamlanmadı.

## Geliştirme

```sh
swift build -c release
python3 -m py_compile Scripts/routerctl.py
./Scripts/build-app.sh
```

Xray 25.1.30 için yerel macOS doğrulama ikilisi `Tools/xray-validator` konumuna ayrı sağlanmalıdır; ikili depoya eklenmez. Uygulamayı paketlerken `Scripts/routerctl.py` dosyasını kaynaklara ekleyin. Gilroy fontlarını kullanıcıya ait yerel font klasöründen paketleyin; lisanslı font dosyaları depoda bulunmaz.

Abonelik URL'si uygulamada Keychain'de, router'da root erişimli dosyada saklanır. VPN kimlik bilgileri ve özel SSH anahtarı bu depoya eklenmez. Veri sayaçları aylık fatura miktarı değildir; router veya Xray yeniden başladığında sıfırlanır.

## Sınırlar

Router 64 MB RAM ve tek çekirdekli. İlk router ölçüm ve otomatik geçiş denemesi, sağlayıcı bağlantıları router WAN'ından zaman aşımına uğradığı için canlı trafiğe alınmadı. Süre dolumu sonrası doğrudan internet geçişi kuruldu, ancak uçtan uca test edilmedi.

Elle doğrudan internet ve VPN moduna geçiş router'da doğrulandı; geçişten sonra VPN çıkış IP'si tekrar başarıyla ölçüldü. Telefonla doğrudan mod trafik testi ayrıca yapılmalıdır.

Wi-Fi cihaz sayaçları router’da dakikada bir toplanır. Anlık indirme hızı uygulama açıkken ardışık 10 saniyelik okumaların farkından hesaplanır. Günlük toplam Ashgabat gününe göredir; router sayaç dosyasını saatte bir kalıcı depoya yazar. Elektrik kesintisinde en fazla yaklaşık bir saatlik toplam kaybolabilir. Kablolu cihaz başına sayaç henüz yoktur. Wi-Fi cihazının yerel ağ trafiği de kablosuz sayaçlara dahil olabilir.
