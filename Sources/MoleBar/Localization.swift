import Foundation

/// Arayüz metnini çevirir. Anahtar Türkçe metindir. Çeviri yoksa anahtar aynen döner.
/// Çeviriler `Resources/<dil>.lproj/Localizable.strings` dosyasındadır. `make-app.sh` bunları pakete kopyalar.
/// Değişkenli metinde anahtar biçim belirteci taşır: `L("%d satır kaydedildi.", count)`.
/// Değişken yoksa `String(format:)` çalışmaz, böylece metindeki `%` işareti bozulmaz.
/// SwiftUI `Text("sabit")` metinleri bu işlevi kullanmaz, aynı tablodan kendiliğinden çevrilir.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
}
