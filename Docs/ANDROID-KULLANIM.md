# HappRouter'ı Android telefondan kullanma

Bu kılavuzu router'ın yanındaki kişiye gönderin. Bilgisayar gerekmez; telefonun **HappVPN Wi-Fi ağına** bağlı olması gerekir. Uygulama VPN'i telefonda çalıştırmaz, Mi Router 4C üzerindeki mevcut VPN'i yönetir.

## 1. Uygulamayı kur

[HappRouter Android APK dosyasını indir](https://github.com/Dadebay/Mi-router-Happ-vpn-integration/raw/refs/heads/main/releases/HappRouter-Android-v0.3.1.apk). Telefonda dosyayı açın. Android isterse dosyayı açtığınız uygulamaya **Bilinmeyen uygulamaları yükleme** izni verin. Uygulama adı **HappRouter**. Ana ekranın üstündeki **TM / RU / EN** düğmeleriyle Türkmence, Rusça veya İngilizce seçebilirsiniz; seçim telefonda saklanır. Üstteki **Adım adım rehberi aç** düğmesi bu anlatımı seçilen dilde uygulamanın içinde gösterir.

## 2. Router'a bağlan

Telefonu **HappVPN** Wi-Fi ağına bağlayın. Android “Bu ağda internet yok” derse **Bağlı kal** seçin. Uygulamadaki router adresi başlangıçta `192.168.1.1`. Router'ın adresi farklıysa Wi-Fi bağlantı ayrıntılarındaki **Ağ geçidi / Gateway** değerini yazıp **Bağlan**'a basın. Başka bir router'ın Wi-Fi ağı üzerinden bu cihaza bağlanamazsınız.

## 3. Telefonu bir kez eşleştir

Router'ın yönetici parolası biliniyorsa uygulamada **Telefonu eşleştir** alanına yazın. Parola kaydedilmez. Eşleştirme başarılı olduğunda **Yenile**'ye basın.

Parola ile SSH girişi kapalıysa uygulamadaki **Açık anahtarı göster → Kopyala** adımlarını kullanın. Aynı telefonda `http://192.168.1.1` (veya router'ın gerçek adresi) açıp OpenWrt yönetim sayfasına giriş yapın. **System → Administration → SSH-Keys** bölümünde açık anahtarın tamamını yapıştırıp **Add key**'e basın; ardından uygulamada **Yenile**'ye basın. Bu sayfa bulunmuyorsa açık anahtarı router'a daha önce erişimi olan yöneticiye gönderin. Yönetici parolası ya da mevcut yetkili erişim olmadan yeni bir telefonu güvenli biçimde eşleştirmek mümkün değildir.

## 4. Router durumunu kontrol et

Üstte **VPN açık** ve **Çıkış IP** görünmeli. Aşağıda aktif sunucu, gecikmeler, CPU, RAM, trafik ve bağlı cihazların IP/kullanım bilgileri var. Cihazın internetini kesmek için kendi satırındaki **Engelle**'ye basın; tekrar açmak için **Engeli kaldır**'a basın. Kendi telefonunuzu yanlışlıkla engellemeyin.

## 5. VPN aboneliği ekle veya değiştir

**Abonelikleri değiştir** bölümüne bir veya iki HTTPS abonelik adresi yapıştırın. Adresler gizlenir ve yalnız telefonda şifreli saklanır. **Sunucuları getir**'e basın; bütün desteklenen Shadowsocks sunucuları tek listede görünür. **En uygun sunucuyu bul ve test et** en düşük gecikmeli çalışan sunucuyu router üzerinden dener. İsterseniz listeden bir sunucuyu elle seçip test edebilirsiniz. Aboneliğin **bitiş gününü** seçip **Tüm sunucuları kur**'a basın. Sonra **VPN modu** ve **Yenile** ile çıkış IP'sini kontrol edin. **Otomatik seçim** açıkken router erişilebilir en düşük gecikmeli sunucuya geçer.

## Bağlanmazsa

- Telefonda HappVPN Wi-Fi ve router adresini kontrol edin. Telefon başka Wi-Fi'deyse uygulama router'a erişemez.
- “Host key” hatası çıkarsa belirtilen IP'deki cihaz farklı bir router'dır. Doğru Wi-Fi ve IP'yi bulun; güvenlik denetimini kapatmayın.
- Eşleştirme başarısızsa yönetici parolasını ve router'da parola ile SSH girişinin açık olup olmadığını kontrol edin. Gerekirse 3. adımdaki OpenWrt yolunu kullanın.
- Profil gelmiyorsa HTTPS adresini ve internet bağlantısını kontrol edin. Gerekirse profilleri mobil veriden indirin, test ve kurulumdan önce HappVPN Wi-Fi'ye dönün.
- `happ://crypt5`, VLESS ve Hysteria profilleri bu kurulumda çalışmaz; Shadowsocks (`ss://`) gerekir.
- VPN test geçmezse uygulama mevcut çalışan router ayarını değiştirmez. Başka abonelik/sunucu deneyin.

**Güvenlik:** Abonelik adreslerini, router parolasını veya özel SSH anahtarını kimseye göndermeyin. Açık SSH anahtarı `ssh-rsa` ile başlar ve eşleştirme için paylaşılabilir.

OpenWrt'nin [SSH anahtarı ekleme yönergesi](https://openwrt.org/docs/guide-user/security/dropbear.public-key.auth) LuCI adımlarını gösterir.

## Hata raporunu gönder

Uygulamada router bağlantı kartındaki **Gmail arkaly hata hasabatyny iber / Отправить отчёт через Gmail / Send error report via Gmail** düğmesine basın. Gmail, alıcısı `dadebaygurbanow333@gmail.com` olan yeni bir ileti açar ve son 30 günün en fazla 100 hata kaydını TXT dosyası olarak ekler. Göndermeden önce dosyayı kontrol edip Gmail’de **Gönder** düğmesine basın. Gmail yüklü değilse başka bir e-posta uygulaması seçilebilir. Abonelik bağlantıları ve anahtarlar hata kaydında gizlenir.
