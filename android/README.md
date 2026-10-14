# HappRouter Android

Bu APK, telefon `HappVPN` Wi-Fi ağına bağlıyken `192.168.1.1` adresindeki Xiaomi Mi Router 4C'ye doğrudan SSH ile bağlanır. Mac'in açık kalması gerekmez. İlk sürüm VPN durumunu, kayıtlı sunucuları, iki HTTPS aboneliğinden sunucu getirmeyi, seçilen sunucuyu test edip router'a kurmayı ve otomatik/elle sunucu seçimini içerir.

## APK oluşturma

Mac'te Android SDK ve mevcut router SSH host kaydı (`~/.happ-router/known_hosts`) gerekir:

```sh
./android/build-apk.sh
```

Çıktı: `dist/HappRouter-Android.apk`. Betik APK'yı yerel ve kalıcı bir imza anahtarıyla imzalar. İmza dosyaları `~/.happ-router/` altında kalır; depoya girmez. Aynı telefondaki güncellemeler için bu imza anahtarını koruyun. Router host anahtarının açık kısmı APK'ya eklenir; telefon farklı bir SSH host kimliğine sessizce bağlanmaz.

## Telefonu eşleştirme

1. APK'yı telefona kurun ve uygulamayı açın. Uygulama telefonda ayrı bir SSH anahtar çifti oluşturur.
2. **Açık anahtarı paylaş** ile yalnızca `ssh-rsa ... happrouter-android` satırını Mac'e aktarın ve `android.pub` adlı metin dosyasına kaydedin.
3. Mac'te bu depodan `./Scripts/pair-android.sh android.pub` komutunu çalıştırın. Betik açık anahtarı router'ın Dropbear yetki dosyasına ekler; özel anahtar telefondan çıkmaz.
4. Telefonu `HappVPN` Wi-Fi ağına bağlayın ve uygulamada **Yenile**'ye basın.

Eşleştirmeden sonra abonelik bağlantılarını girip **Sunucuları getir → Bağlantıyı test et → Test edilen sunucuyu kur** adımlarını kullanın. İkinci alan isteğe bağlıdır. Kurulum seçilen sunucuyu yeniden doğrular; başarısız olursa önceki router yapılandırmasını geri yükler. Abonelik adresleri Android Keystore ile şifrelenerek telefonda saklanır; APK ve router metadata dosyalarına yazılmaz.

Yalnızca Shadowsocks `ss://`, Shadowsocks içeren HTTPS abonelikleri ve Happ'ten alınan Shadowsocks JSON profili desteklenir. Şifreli `happ://crypt5`, VLESS ve Hysteria bu router'daki hafif Shadowsocks istemcisiyle çalışmaz. VPN kesintisinde Wi-Fi üzerinden abonelik indirilemiyorsa mobil veriyle **Sunucuları getir** adımını tamamlayıp kurulumdan önce tekrar `HappVPN` Wi-Fi ağına bağlanın.
