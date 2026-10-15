# HappRouter Android

Android uygulaması, Xiaomi Mi Router 4C üzerindeki mevcut HappRouter kurulumunu yerel Wi-Fi üzerinden yönetir. Mac'in açık kalması gerekmez. Router modu ve VPN çıkış IP'si, CPU/RAM, Wi-Fi ve WAN trafiği, günlük cihaz kullanımı, bağlı cihazların IP adresleri, engelleme kuralları ve kayıtlı Shadowsocks sunucuları uygulamada görünür. Sunucu ve internet modu değiştirilebilir.

Kullanıcı için kısa telefon kılavuzu: [ANDROID-KULLANIM.md](../Docs/ANDROID-KULLANIM.md).
Uygulamanın üstündeki **Adım adım rehberi aç** düğmesi aynı kurulum yolunu, ilk eşleştirme seçeneklerini ve hata çözümlerini çevrimdışı gösterir.
Ana ekrandaki **TM / RU / EN** seçimi uygulamayı ve rehberi Türkmence, Rusça veya İngilizce gösterir. Seçilen dil cihazda saklanır. İlk açılış dili Türkmencedir.
Bağlantı, abonelik ve beklenmeyen uygulama hataları telefonda son 30 gün ve en fazla 100 olayla sınırlı tutulur. Router bağlantı kartındaki hata raporu düğmesi TXT dosyasını Gmail taslağına ekler; kullanıcı gönderimi Gmail üzerinden tamamlar. Abonelik bağlantıları ve anahtarlar rapordan çıkarılır.

## APK oluşturma

Android SDK ve router'ın önceden doğrulanmış SSH host anahtarı (`~/.happ-router/known_hosts`) gerekir:

```sh
./android/build-apk.sh
```

Çıktı `dist/HappRouter-Android.apk` dosyasıdır. Sürüm imzası `~/.happ-router/` altında kalır. Aynı telefona güncelleme kurabilmek için imza dosyasını koruyun. APK yalnız router'ın sabitlenmiş açık SSH host anahtarına bağlanır; router LAN IP adresi uygulamadan değiştirilebilir, host kimliği değiştirilemez.

## İlk eşleştirme

1. Telefonu HappVPN Wi-Fi ağına bağlayın, uygulamayı açın, router'ın LAN IP adresini girin.
2. Router'da SSH parola girişi açıksa **Telefonu eşleştir** alanına yönetici parolasını yazın. Uygulama kendi açık SSH anahtarını router'a ekler; parola saklanmaz.
3. SSH parola girişi kapalıysa uygulamadaki açık anahtarı kopyalayıp telefonun tarayıcısında OpenWrt LuCI **System → Administration → SSH-Keys** bölümüne ekleyin. Bu işlem router'ın yönetici parolasını gerektirir. LuCI yoksa anahtarı mevcut SSH yöneticisine iletin; Mac'te `./Scripts/pair-android.sh android.pub` kullanılabilir.
4. **Yenile** ile router durumunu açın.

## Sunucu ekleme

En fazla iki HTTPS aboneliği veya bir `ss://` bağlantısı girin. **Sunucuları getir** tüm Shadowsocks profillerini tek listede gösterir. **En uygun sunucuyu bul ve test et** router üzerinden TCP gecikmesine göre sıralar, ardından gerçek VPN çıkışını doğrular. İsteyen kullanıcı tek sunucuyu elle seçip test edebilir. Bitiş tarihini seçip **Tüm sunucuları kur** ile profil listesini router'a yükleyin. Kurulum seçilen sunucuyu tekrar doğrular; başarısızlıkta önceki yapılandırmayı geri yükler. Daha sonra otomatik seçim en hızlı çalışan sunucuyu kullanır.

Abonelik adresleri Android Keystore ile şifrelenerek yalnız telefonda saklanır. APK'ya veya router'ın metadata dosyalarına yazılmaz. `happ://crypt5`, VLESS ve Hysteria bu router'ın Shadowsocks istemcisiyle çalışmaz. Wi-Fi üzerinden abonelik indirilemiyorsa geçici olarak mobil veriyle profilleri getirip kurulumdan önce tekrar HappVPN Wi-Fi'ye bağlanın.

Uygulama yalnız yerel router ağından çalışır; internet üzerinden uzaktan yönetim açmaz.
