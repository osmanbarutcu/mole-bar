# MoleBar

MoleBar, macOS menü çubuğunda CPU, bellek ve disk kullanımını gösterir. [Mole](https://github.com/tw93/mole) ile temizlik ve bakım önizlemesi sunar.

MoleBar, Mole'un resmi uygulaması değildir. Kişisel kullanım için yazıldı. Mole GPL-3.0 lisanslıdır.

## Gereksinimler

- macOS 15 veya üstü. Liquid Glass görünümü macOS 26 ve üstünde çalışır. Eski sürümde yedek materyal kullanılır.
- Swift 6 araçları (Command Line Tools yeterlidir, Xcode gerekmez).
- Mole: `brew install mole`. Mole yoksa sağlık skoru, temizlik ve bakım önizlemesi çalışmaz.

## Kurulum

1. Depoyu açın: `cd mole`
2. Kurun: `./install.sh`

Betik uygulamayı derler, `/Applications/MoleBar.app` altına kopyalar ve açar. Yalnızca derlemek için `./make-app.sh` çalıştırın.

## Kullanım

- Menü çubuğundaki metne tıklayın. Panel açılır: Genel, Diskler, Süreçler, Araçlar.
- `⌥⌘M` paneli açar.
- Uygulamayı çift tıklayın. Ana pencere açılır: Genel, Diskler, Analiz, Büyük dosyalar, Yinelenenler, Önbellek, Uygulamalar, Süreçler, Araçlar, Ayarlar.
- Ayarlar'da menü çubuğu görünümü (metin veya ikon), disk uyarı eşiği, girişte başlatma ve haftalık tarama bulunur.

## Güvenlik

- Temizlik önizlemesi (`mo clean --dry-run`) hiçbir şey silmez.
- Gerçek temizlik yalnızca onaydan sonra çalışır. Yalnızca kullanıcı seviyesi dosyaları siler. Geri alınamaz.
- Disk analizi salt okunurdur. Çöp ikonu öğeyi Çöp Kutusu'na taşır. Ev klasörünün doğrudan alt öğeleri korunur.
- Yinelenenler sayfası ev klasöründe (gizli klasörler ve ~/Library hariç) aynı içerikli dosyaları SHA-256 ile bulur. Taşıma Çöp Kutusu'nadır. Her gruptaki son kopya taşınamaz.
- Diskler sayfasındaki "Kazanılabilir alan" kartı, son taramaların sonucunu gösterir. Kategoriler çakışabilir, toplam yoktur.
- Önbellek sayfası; uygulama önbelleklerini, günlükleri ve geliştirici önbelleklerini listeler. Seçilenler Çöp Kutusu'na taşınır. "Çöp Kutusu'nu boşalt" kalıcıdır ve ayrı onay ister.
- Yinelenenler sayfasında "Gizli klasörleri ve Library'yi de tara" anahtarı vardır. Varsayılan kapalıdır.
- Genel sayfasında pil, ısı durumu ve açık kalma süresi görünür. Mac 30 günden uzun açıksa uyarı çıkar.
- Süreçler sayfası CPU, Bellek ve Ağ sıralaması sunar.
- Önbellek sayfası OrbStack/Docker, Mail ve Spotlight dizini boyutunu yalnızca gösterir. MoleBar bunları silmez. Boyut hesabı sert bağlantıları bir kez sayar.
- Araçlar sayfası hedefi eksik giriş öğelerini listeler. Silmez.
- Ayarlar sayfasında tema, son işlemler ve son hatalar bulunur. Ana pencerede ⌘1–⌘0 sayfa değiştirir.
- Uygulamalar sayfası, uygulamayı ve `~/Library` artıklarını Çöp Kutusu'na taşır. Çalışan uygulama engellenir. Kalıcı silme yoktur.
- Süreç sonlandırma `SIGTERM` gönderir. Sistem süreçleri korunur.
- Gerçek `mo optimize` Terminal'de çalışır, çünkü yönetici izni ister.
- Korunan yollar `mo clean --whitelist` ile Terminal'de yönetilir. Uygulama bu dosyayı yazmaz. Dosya varsa Mole'un varsayılan korumalarını değiştirir.

## Bilinen sınırlar

- Uygulama yerel Apple Development sertifikasıyla imzalanır. Sertifika yoksa ad-hoc imza kullanılır. Başka bir Mac'e kopyalarsanız Gatekeeper uyarı verebilir.
- ⌥⌘M kısayolu sistemin iç sınıf adlarına dayanır. macOS güncellemesinde bozulabilir.
- Disk analizi ve Büyük dosyalar sayfası, bazı klasörler için Tam Disk Erişimi ister. Erişilemeyen öğe sayısı ekranda görünür. İzin yoksa sonuçlar eksik kalır. Örnek: 426 bin dosya görüldü, izinli betik 626 bin dosya gördü.
- `mo purge` Mole'da hata verebilir (`discovered[@]: unbound variable`). Doğrulanmadı.
- Gerçek `mo clean` çıktı biçimi doğrulanmadı. Boşalan alan diskten ölçülür.

## Geliştirme

- Simgeyi yeniden üretin: `swift scripts/make-icon.swift /tmp/AppIcon.iconset`, ardından `iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns`.
- Karar günlüğü ve ilerleme: `memory-bank/`.
- Testleri çalıştırın: `swift test`. Testler Swift Testing kullanır (`Tests/MoleBarTests`). XCTest gerekmez.
- Kaynak dosya değişince ilk `swift test` çalıştırması `TestingMacros` eklenti hatası verebilir. Komutu bir kez daha çalıştırın.
- Panel görünümünü pencerede görmek için: `MOLEBAR_PANEL_PREVIEW=1 /Applications/MoleBar.app/Contents/MacOS/MoleBar`.
- Ekran görüntüleri: `scripts/ui-shots.sh [klasör] [system|light|dark]`. Terminal için Erişilebilirlik izni gerekir.
