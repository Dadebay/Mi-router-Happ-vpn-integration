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
- Router sayfasında mevcut OpenWrt/Xray kurulumunun yardımcı dosyalarını ve zamanlayıcılarını tek düğmeyle yükleme; VPN sayfasında test hatası ve Xray günlüklerini görüntüleme

**Kurulum düğmesinin kapsamı:** Mac ile LAN üzerinden erişilen, SSH anahtarı tanıtılmış Xiaomi 4C üzerinde mevcut OpenWrt/Xray temelini denetler; yardımcı betikleri ve cron görevlerini yeniden yükler. İlk firmware kurulumu, SSH anahtarı tanıtma ve Xray çekirdeğini flash belleğe yerleştirme bu düğmenin kapsamı dışındadır. Eksik ön koşullar uygulamada açık hata olarak gösterilir. Kurulum sırasında mevcut abonelik, Xray yapılandırması ve internet modu korunur.
- Cihazlar sayfasında Wi-Fi cihazı başına indirme hızı ve bugün indirilen veri

**13 Ekim 2026 çalışan router sürümü:** Happ uygulamasından alınan Shadowsocks sunucu profili, Xiaomi Mi Router 4C üzerinde `ss-local` ve `ss-redir` ile çalışıyor. Router yeniden başlatıldıktan sonra servis otomatik açıldı. Android telefon `HappVPN` Wi-Fi ağına bağlandığında çıkış IP'si `78.232.59.122` olarak ve YouTube erişimiyle doğrulandı. DNS istekleri VPN içinden iletiliyor. `Scripts/happ-ss.init`, `Scripts/happ-ss.nft` ve `Scripts/mode.sh` bu çalışan yönlendirme düzeninin kaynak dosyalarıdır.

Sunucu parolası yalnızca router'daki `/etc/happvpn/ss-client.json` dosyasında tutulur; bu depoda bulunmaz. Güvenlik duvarındaki `6c:1f:f7:17:eb:39` MAC adresi kurulum sırasında Mac'in kablolu bağlantısını doğrudan internette tutmak için ayrılmıştır. Başka kurulumda bu adres uyarlanmalıdır. VPN yönlendiricisi durursa Wi-Fi istemcileri doğrudan WAN'a çıkamaz. Abonelik bitişini denetleyen mevcut görev, süre dolduğunda doğrudan moda geçer.

macOS uygulamasının abonelik kurma ekranı hâlâ Xray/VLESS yolunu kullanıyor; çalışan Shadowsocks sunucusunu değiştirme işlevi için uyarlanması gerekiyor.

VLESS WebSocket/TLS adayları için hafif TCP erişim testi 30 dakikada bir çalışır. Bu ölçüm VPN kimlik doğrulamasını veya gerçek çıkış hızını kanıtlamaz. Otomatik sunucu seçimi üzerinde çalışılıyor. Router'ın 64 MB belleğine sığması için aynı anda yalnızca bir VLESS sunucusu Xray'e yüklenir; listedeki diğer sunucuların TCP gecikmesi görünür, fakat trafik onlara otomatik geçmez. `n/a`, TCP bağlantısının kurulamadığını veya ölçümün bulunmadığını gösterir. Ülke bayrakları sağlayıcının etiketidir, fiziksel konum kanıtı değildir.

## Kullanım

Uygulama router'a `192.168.1.1` adresinden SSH ile bağlanır. Yerel SSH anahtarını `~/.happ-router` altında kullanır. Mac'in Wi-Fi ayarlarını değiştirmez. Router'daki VPN ve süre dolumu görevi Mac kapalıyken çalışır.

Yeni abonelik için önce **Profilleri kontrol et**, ardından **Router'a kur** düğmelerini kullan. Kurulum listedeki ilk VLESS sunucusunu seçer, Xray JSON'unu doğrular ve mevcut yapılandırmayı yedekler. Bu router'da Xray açılışı yaklaşık 20 dakika sürebilir. Kurulum, VPN çıkışını doğrulayamazsa önceki yapılandırmaya döner ve router doğrudan internet modunda kalır. Sunucular arasında otomatik geçiş henüz tamamlanmadı.

## Geliştirme

```sh
swift build -c release
python3 -m py_compile Scripts/routerctl.py
./Scripts/build-app.sh
```

Xray 25.1.30 için yerel macOS doğrulama ikilisi `Tools/xray-validator` konumuna ayrı sağlanmalıdır; ikili depoya eklenmez. Uygulamayı paketlerken `Scripts/routerctl.py` dosyasını kaynaklara ekleyin. Gilroy fontlarını kullanıcıya ait yerel font klasöründen paketleyin; lisanslı font dosyaları depoda bulunmaz.

Abonelik URL'si uygulamada Keychain'de, router'da root erişimli dosyada saklanır. VPN kimlik bilgileri ve özel SSH anahtarı bu depoya eklenmez. Veri sayaçları aylık fatura miktarı değildir; router veya Xray yeniden başladığında sıfırlanır.

## Sınırlar

Router 64 MB RAM ve tek çekirdekli. Xray/VLESS yolu bu cihazda açılışta takıldığı için çalışan bağlantıda Shadowsocks-libev kullanılır. `ss-local`, `ss-redir` ve DNS relay servisi açılışta procd tarafından başlatılır. Süre dolumu sonrası doğrudan internet geçişi kuruldu, ancak uçtan uca test edilmedi.

Elle doğrudan internet ve VPN moduna geçiş router'da doğrulandı; geçişten sonra VPN çıkış IP'si tekrar başarıyla ölçüldü. Telefonla doğrudan mod trafik testi ayrıca yapılmalıdır.

Wi-Fi cihaz sayaçları router’da dakikada bir toplanır. Anlık indirme hızı uygulama açıkken ardışık 10 saniyelik okumaların farkından hesaplanır. Günlük toplam Ashgabat gününe göredir; router sayaç dosyasını saatte bir kalıcı depoya yazar. Elektrik kesintisinde en fazla yaklaşık bir saatlik toplam kaybolabilir. Kablolu cihaz başına sayaç henüz yoktur. Wi-Fi cihazının yerel ağ trafiği de kablosuz sayaçlara dahil olabilir.
