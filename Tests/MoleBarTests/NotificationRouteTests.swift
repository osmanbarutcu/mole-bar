import Foundation
import Testing
@testable import MoleBar

struct NotificationRouteTests {
    @Test func cacheAlertOpensCachePage() {
        #expect(NotificationRoute.section(for: "molebar.cache") == .caches)
    }

    @Test func diskAlertOpensDisksPage() {
        #expect(NotificationRoute.section(for: "molebar.disk") == .disks)
    }

    @Test func memoryAlertOpensProcessesPage() {
        #expect(NotificationRoute.section(for: "molebar.memory") == .processes)
    }

    @Test func weeklyScanOpensToolsPage() {
        #expect(NotificationRoute.section(for: "molebar.scan") == .tools)
    }

    @Test func unknownIdentifierHasNoRoute() {
        #expect(NotificationRoute.section(for: "baska.uygulama") == nil)
        #expect(NotificationRoute.section(for: "") == nil)
    }
}
