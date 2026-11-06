import AppKit
import Foundation
import Testing
@testable import MoleBar

struct SystemIntegrationTests {
    @Test func statusItemWindowMatchesByClassName() {
        #expect(PanelToggle.isStatusItemWindow(className: "NSStatusBarWindow", level: 0))
    }

    @Test func statusItemWindowMatchesByLevelWhenClassNameChanges() {
        // macOS sürümü iç sınıf adını değiştirirse düzey (status bar) yine eşleşir.
        #expect(PanelToggle.isStatusItemWindow(className: "YeniSistemPenceresi", level: NSWindow.Level.statusBar.rawValue))
    }

    @Test func ordinaryWindowsDoNotMatch() {
        #expect(!PanelToggle.isStatusItemWindow(className: "NSWindow", level: NSWindow.Level.normal.rawValue))
        #expect(!PanelToggle.isStatusItemWindow(className: "SwiftUI.AppKitWindow", level: NSWindow.Level.normal.rawValue))
    }

    @Test @MainActor func appStaysInMenuBarAfterLastWindowCloses() {
        let delegate = AppDelegate()
        let terminates = delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        #expect(!terminates)
    }

    @Test func hotKeyClosesMainWindowOnlyWhenVisibleAndActive() {
        #expect(PanelToggle.shouldCloseMain(isVisible: true, isActive: true))
        #expect(!PanelToggle.shouldCloseMain(isVisible: true, isActive: false))
        #expect(!PanelToggle.shouldCloseMain(isVisible: false, isActive: true))
    }

    @Test func successGivesNoFailureText() {
        #expect(GlobalHotKey.failureText(0) == nil)
    }

    @Test func existingHotKeyErrorExplainsConflict() throws {
        let text = try #require(GlobalHotKey.failureText(-9878))
        #expect(text.contains("başka bir uygulama"))
    }

    @Test func otherErrorsShowTheCode() throws {
        let text = try #require(GlobalHotKey.failureText(-50))
        #expect(text.contains("-50"))
    }
}
