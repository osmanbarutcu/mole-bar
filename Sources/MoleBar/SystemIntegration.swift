import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Genel kısayol ⌥⌘M. Carbon `RegisterEventHotKey` kullanır, erişilebilirlik izni gerektirmez.
enum GlobalHotKey {
    private static var hotKeyRef: EventHotKeyRef?
    private static var handlerRef: EventHandlerRef?

    static func register() {
        guard hotKeyRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { PanelToggle.toggle() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        let identifier = EventHotKeyID(signature: OSType(0x4D4F4C45), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), UInt32(optionKey | cmdKey), identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    static func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

/// MenuBarExtra paneli için açma API'si yoktur. Durum çubuğu düğmesine tıklama gönderilir.
/// Bu yöntem sistemin iç sınıf adlarına dayanır; macOS güncellemesinde bozulabilir.
enum PanelToggle {
    @MainActor
    static func toggle() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = firstButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func firstButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for child in view.subviews {
            if let found = firstButton(in: child) { return found }
        }
        return nil
    }
}

/// Girişte başlatma. macOS Giriş Öğeleri listesine kaydeder; kullanıcı onayı gerekebilir.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var errorText: String?

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
