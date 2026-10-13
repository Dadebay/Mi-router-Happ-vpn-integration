# HappRouter

Xiaomi Mi Router 4C üzerindeki OpenWrt/Shadowsocks VPN için macOS kontrol paneli.

## Durum

- VPN durumu ve router üzerinden gerçek çıkış IP testi
- Wi-Fi veri sayaçları ve bağlı cihazlar
- Sunucu adları ve varsa TCP gecikme ölçümleri
- Happ uygulamasından kopyalanan sunucu JSON'unu, `ss://` bağlantısını veya Shadowsocks içeren HTTPS aboneliğini kontrol etme ve router'a kurma
- Abonelik bitiş tarihi ve süre dolunca doğrudan internete geçiş görevi
- Genel Bakış, VPN Ayarları, Router ve Cihazlar için ayrı gezinme sayfaları
- Router sayfasından VPN/doğrudan internet modu arasında elle geçiş
- Router sayfasında mevcut OpenWrt/Shadowsocks kurulumunun yardımcı dosyalarını ve zamanlayıcılarını tek düğmeyle yükleme; VPN sayfasında test hatası ve servis günlüklerini görüntüleme

**Kurulum düğmesinin kapsamı:** Mac ile LAN üzerinden erişilen, SSH anahtarı tanıtılmış Xiaomi 4C üzerinde mevcut OpenWrt/Shadowsocks temelini denetler; yardımcı betikleri, servis dosyasını ve cron görevlerini yeniden yükler. İlk firmware kurulumu, SSH anahtarı tanıtma ve Shadowsocks paketlerinin yüklenmesi bu düğmenin kapsamı dışındadır. Eksik ön koşullar uygulamada açık hata olarak gösterilir. Kurulum sırasında mevcut sunucu profili ve internet modu korunur.
- Cihazlar sayfasında bağlı Wi-Fi cihazlarının bugünkü toplam indirmesi, cihaz başına indirme hızı ve internet engeli
- Kaydedilen Sistem / Açık / Koyu görünüm seçimi ve mavi ana renk

**13 Ekim 2026 çalışan router sürümü:** Happ uygulamasından alınan Shadowsocks sunucu profili, Xiaomi Mi Router 4C üzerinde `ss-local` ve `ss-redir` ile çalışıyor. Router yeniden başlatıldıktan sonra servis otomatik açıldı. Android telefon `HappVPN` Wi-Fi ağına bağlandığında çıkış IP'si `78.232.59.122` olarak ve YouTube erişimiyle doğrulandı. DNS istekleri VPN içinden iletiliyor. `Scripts/happ-ss.init`, `Scripts/happ-ss.nft` ve `Scripts/mode.sh` bu çalışan yönlendirme düzeninin kaynak dosyalarıdır.

Sunucu parolası yalnızca router'daki `/etc/happvpn/ss-client.json` dosyasında tutulur; bu depoda bulunmaz. Güvenlik duvarındaki `6c:1f:f7:17:eb:39` MAC adresi kurulum sırasında Mac'in kablolu bağlantısını doğrudan internette tutmak için ayrılmıştır. Başka kurulumda bu adres uyarlanmalıdır. VPN yönlendiricisi durursa Wi-Fi istemcileri doğrudan WAN'a çıkamaz. Abonelik bitişini denetleyen mevcut görev, süre dolduğunda doğrudan moda geçer.

macOS uygulamasında yeni profil önce router üzerinde ayrı bir dinleyicide gerçek VPN çıkış IP'siyle test edilir. Başarılı olursa çalışan servis yeni profile geçirilir ve yeniden test edilir. İkinci test başarısızsa önceki profil geri yüklenir. Çalışan sürümün Git etiketi `working-router-vpn-2026-10-13`.

Shadowsocks sunucuları için hafif TCP erişim testi 30 dakikada bir çalışır. Bu ölçüm VPN kimlik doğrulamasını veya gerçek çıkış hızını kanıtlamaz. Otomatik sunucu seçimi henüz etkin değil. `n/a`, TCP bağlantısının kurulamadığını veya ölçümün bulunmadığını gösterir. Ülke bayrakları sağlayıcının etiketidir, fiziksel konum kanıtı değildir.

## Kullanım

Uygulama router'a `192.168.1.1` adresinden SSH ile bağlanır. Yerel SSH anahtarını `~/.happ-router` altında kullanır. Mac'in Wi-Fi ayarlarını değiştirmez. Router'daki VPN ve süre dolumu görevi Mac kapalıyken çalışır.

Happ macOS uygulamasında çalışan Shadowsocks sunucusunu seçip **Copy Server JSON** komutunu kullan. HappRouter'da **Panodan al**, **Profili kontrol et** ve **Sunucuyu değiştir** düğmelerine bas. HTTPS aboneliğinde birden fazla desteklenen Shadowsocks sunucusu varsa kurulacak sunucuyu listeden seç. Şifreli `happ://crypt5` bağlantıları doğrudan çözülemez; Happ içinden sunucu JSON'u alınmalıdır. Yalnızca VLESS profilleri içeren abonelikler bu router üzerinde desteklenmez.

## Geliştirme

```sh
swift build -c release
python3 -m py_compile Scripts/routerctl.py
./Scripts/build-app.sh
```

Uygulamayı paketlerken `Scripts/routerctl.py` ve `Scripts/RouterScripts` kaynaklarını ekleyin. `Scripts/build-app.sh` bunu yapar. Gilroy fontlarını kullanıcıya ait yerel font klasöründen paketleyin; lisanslı font dosyaları depoda bulunmaz.

Girilen profil uygulamada Keychain'de, aktif sunucu parolası router'da yalnızca root erişimli dosyada saklanır. VPN kimlik bilgileri ve özel SSH anahtarı bu depoya eklenmez. Veri sayaçları aylık fatura miktarı değildir; router yeniden başladığında sıfırlanır.

## Sınırlar

Router 64 MB RAM ve tek çekirdekli. Xray/VLESS yolu bu cihazda açılışta takıldığı için çalışan bağlantıda Shadowsocks-libev kullanılır. `ss-local`, `ss-redir` ve DNS relay servisi açılışta procd tarafından başlatılır. Süre dolumu sonrası doğrudan internet geçişi kuruldu, ancak uçtan uca test edilmedi.

Elle doğrudan internet ve VPN moduna geçiş router'da doğrulandı; geçişten sonra VPN çıkış IP'si tekrar başarıyla ölçüldü. Telefonla doğrudan mod trafik testi ayrıca yapılmalıdır.

Wi-Fi cihaz sayaçları router’da dakikada bir toplanır. Anlık indirme hızı uygulama açıkken ardışık 10 saniyelik okumaların farkından hesaplanır. Günlük toplam Ashgabat gününe göredir; router sayaç dosyasını saatte bir kalıcı depoya yazar. Elektrik kesintisinde en fazla yaklaşık bir saatlik toplam kaybolabilir. Kablolu cihaz başına sayaç henüz yoktur. Wi-Fi cihazının yerel ağ trafiği de kablosuz sayaçlara dahil olabilir.

Cihaz engeli MAC adresine göre VPN ve doğrudan internet trafiğini durdurur; router yönetim erişimi açık kalır. Engelli cihaz Wi-Fi ağına bağlı görünmeye devam edebilir. Çevrimdışı olsa bile Cihazlar sayfasından engeli kaldırılabilir. Telefonun özel/rastgele MAC adresi değişirse yeni adrese ayrıca engel koymak gerekir.
