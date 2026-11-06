# Elle doğrulama listesi

Bu adımlar otomatik test ile doğrulanamaz. Her adımı sürüm öncesi kendiniz çalıştırın.
Sonucu "Geçti" veya "Kaldı" olarak not edin.

## 1. Kısayol ⌥⌘M

1. Ayarlar'da "Kısayol ⌥⌘M ile ana pencereyi aç veya kapat" anahtarını açın.
2. Başka bir uygulamaya geçin. ⌥⌘M tuşlarına basın.
3. Beklenen: MoleBar ana penceresi açılır.
4. ⌥⌘M tuşlarına yeniden basın.
5. Beklenen: Pencere öndeyse kapanır.
6. Hata varsa Ayarlar'da turuncu metin görünür. Günlük: `/usr/bin/log show --predicate 'subsystem == "local.molebar"' --last 5m`

Deneysel seçenek:

1. Ayarlar > Menü çubuğu > "Özel menü çubuğu öğesi (deneysel)" anahtarını açın. MoleBar'ı yeniden başlatın.
2. Menü çubuğunda tek MoleBar öğesi olmalıdır. İkinci öğe görünüyorsa Kaldı yazın.
3. ⌥⌘M tuşuna basın. Beklenen: Menü çubuğu paneli açılır. Yeniden basınca kapanır.
4. Panelin dışına tıklayın. Beklenen: Panel kapanır.
5. Öğeye fareyle tıklayın. Beklenen: Panel açılır ve kapanır.

## 2. Bildirime tıklama

1. Ayarlar'da Önbellek uyarısını 1 GB yapın.
2. Haftalık taramayı elle başlatın veya eşik aşılmasını bekleyin.
3. Gelen bildirime tıklayın.
4. Beklenen: Ana pencere açılır ve ilgili sayfa görünür. Önbellek bildirimi Önbellek sayfasını açar.

## 3. CSV dışa aktarma

1. Büyük dosyalar sayfasında Tara'ya basın. Tarama bitince CSV düğmesine basın.
2. Kaydetme penceresinde bir klasör seçin ve kaydedin.
3. Dosyayı elektronik tabloda açın.
4. Beklenen: Sütunlar Ad, Klasör, Tür, Boyut (bayt). Dosya adı `=` ile başlıyorsa hücre `'=` ile başlar.
5. Analiz sayfasında aynı denemeyi tekrarlayın.

## 4. Mail ek kopyaları

1. Mail'de bir ek açın. Ek `Mail Downloads` klasörüne kopyalanır.
2. Önbellek sayfasını yenileyin.
3. Beklenen: `Mail Downloads` altındaki kopya listede görünür.
4. Seçip Çöp Kutusu'na taşıyın. Finder'dan geri alınabildiğini doğrulayın.
5. Beklenen: `~/Library/Mail` içindeki hiçbir öğe listede yoktur.

## 5. Yetim artıklar

1. Uygulamalar sayfasında "Yetim artıklar" sekmesini açın.
2. Beklenen: Sekme kendi taranır. Kurulu uygulamaların kalıntıları listede yoktur.
3. Bir öğeyi seçin. Çöp Kutusu'na taşıyın. Geri alın.
4. Bilinen yanlış pozitif riski: Uygulama harici diskteyse kalıntısı yetim görünür.

## 6. Güncelleme denetimi

1. Ayarlar > Güncellemeler anahtarını açın. Varsayılan kapalıdır.
2. Beklenen: Yeni sürüm yoksa hiçbir bildirim gelmez.
3. Test için `defaults delete local.molebar lastUpdateCheck` komutunu çalıştırıp uygulamayı yeniden başlatın.
4. Gerçek GitHub sürümü kurulu sürümden yeniyse bildirim gelir ve Ayarlar'da düğme görünür.
5. Düğme yalnızca `https://github.com/...` adresini açar.

## 7. Menü çubuğu grafiği

1. Ayarlar > Menü çubuğu > Grafik'i seçin.
2. CPU, RAM ve Ağ ölçümlerini sırayla seçin.
3. Beklenen: Grafik ve yanındaki metin seçilen ölçümü gösterir. Ağ metni `/s` ile biter.
4. Açık ve koyu menü çubuğunda okunur olduğunu doğrulayın.

## 8. VoiceOver

1. ⌘F5 ile VoiceOver'ı açın.
2. Genel sayfasında halka göstergelerine gidin.
3. Beklenen: "CPU, yüzde 28" gibi okunur.
4. Analiz haritasında bir karoya gidin. Beklenen: "Library, klasör, 84 GB" gibi okunur.
5. İkon düğmelerine gidin. Beklenen: "Yeniden tara" gibi bir ad okunur.

## 9. Koyu ve açık tema

1. Ayarlar'da görünümü sırayla Açık ve Koyu yapın.
2. Harita, Yetim artıklar, Homebrew ve Dış bağlantılar kartlarına bakın.
3. Beklenen: Metin okunur. Karolar zemin ile ayırt edilir.
