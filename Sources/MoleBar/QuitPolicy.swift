import AppKit

/// Çıkış isteğinin sonucu. ⌘Q ve Dock "Çık" uygulamayı kapatmaz, yalnızca menü çubuğuna indirir.
/// Gerçek çıkış iki durumda olur: panelde "Çık" düğmesi ve sistem kapanışı veya oturum kapatma.
final class QuitPolicy {
    enum Decision: Equatable {
        case terminate
        case keepInMenuBar
    }

    static let shared = QuitPolicy()

    /// Dock simgesi yokken uygulama yalnızca menü çubuğunda yaşar.
    static let activationAfterKeepingInMenuBar = NSApplication.ActivationPolicy.accessory
    /// Pencere açılınca Dock simgesi geri gelir.
    static let activationWhenWindowOpens = NSApplication.ActivationPolicy.regular

    private var explicitQuit = false
    private var systemEnding = false

    /// Panelin "Çık" düğmesi çağırır.
    func allowQuit() { explicitQuit = true }

    /// Kapatma, yeniden başlatma veya oturum kapatma başlayınca çağrılır. İptal etmek sistemi bekletirdi.
    func systemIsEnding() { systemEnding = true }

    func decision() -> Decision {
        explicitQuit || systemEnding ? .terminate : .keepInMenuBar
    }
}
