import Foundation
import Testing
@testable import MoleBar

@Suite("DiskExplainer")
struct DiskExplainerTests {
    private let gb: UInt64 = 1 << 30
    private let boot = "Macintosh HD"

    @Test("boyuta göre büyükten küçüğe sıralanır")
    func sorted() {
        let entries = DiskExplainer.entries(
            containers: [("OrbStack", 48 * gb), ("Mail", 5 * gb), ("Spotlight dizini", 8 * gb)],
            cacheBytes: Int(3 * gb), trashBytes: 0, projectsByDisk: [boot: 6 * gb], bootDisk: boot)
        #expect(entries.map(\.name) == ["OrbStack", "Spotlight dizini", "Proje çıktıları", "Mail", "Uygulama önbelleği"])
    }

    @Test("100 MB altı ve okunamayan öğeler listelenmez")
    func filtersSmallAndUnknown() {
        let entries = DiskExplainer.entries(
            containers: [("Mail", 50 << 20), ("OrbStack", nil), ("Spotlight dizini", 2 * gb)],
            cacheBytes: 0, trashBytes: 10, projectsByDisk: [:], bootDisk: boot)
        #expect(entries.map(\.name) == ["Spotlight dizini"])
    }

    @Test("her disk için ayrı proje girdisi oluşur ve diske bağlanır")
    func projectsPerDisk() {
        let entries = DiskExplainer.entries(
            containers: [], cacheBytes: 0, trashBytes: 0,
            projectsByDisk: [boot: 2 * gb, "brtc-disk": 5 * gb, "Küçük": 1 << 20], bootDisk: boot)
        #expect(entries.map(\.disk) == ["brtc-disk", boot])
        #expect(entries.allSatisfy { $0.name == "Proje çıktıları" })
    }

    @Test("gruplar: ana disk önce, diğerleri toplamına göre")
    func grouping() {
        let entries = DiskExplainer.entries(
            containers: [("OrbStack", 1 * gb)], cacheBytes: 0, trashBytes: 0,
            projectsByDisk: ["Z-disk": 3 * gb, "A-disk": 9 * gb], bootDisk: boot)
        let groups = DiskExplainer.grouped(entries, bootDisk: boot)
        #expect(groups.map(\.disk) == [boot, "A-disk", "Z-disk"])
        #expect(groups[0].entries.map(\.name) == ["OrbStack"])
    }

    @Test("ana diskte girdi yoksa bile ana disk grubu görünür")
    func bootAlwaysShown() {
        let entries = DiskExplainer.entries(
            containers: [], cacheBytes: 0, trashBytes: 0, projectsByDisk: ["brtc-disk": 2 * gb], bootDisk: boot)
        #expect(DiskExplainer.grouped(entries, bootDisk: boot).map(\.disk) == [boot, "brtc-disk"])
    }

    @Test("taranmamış kategoriler ayrı bildirilir")
    func unscanned() {
        #expect(DiskExplainer.unscanned(cacheBytes: -1, projectsScanned: false) == ["Önbellek", "Proje çıktıları"])
        #expect(DiskExplainer.unscanned(cacheBytes: 0, projectsScanned: true).isEmpty)
    }

    @Test("MoleBar'ın temizleyebildiği öğe sayfa önerir, diğerleri önermez")
    func sectionsOnlyForOwnActions() {
        let entries = DiskExplainer.entries(
            containers: [("OrbStack", 2 * gb)], cacheBytes: Int(2 * gb), trashBytes: 0, projectsByDisk: [boot: 2 * gb], bootDisk: boot)
        func section(_ name: String) -> MainSection? { entries.first { $0.name == name }?.section }
        #expect(section("OrbStack") == nil)
        #expect(section("Uygulama önbelleği") == .caches)
        #expect(section("Proje çıktıları") == .projects)
    }

    @Test("her satırın bir eylemi var")
    func everyRowHasAnAction() {
        let entries = DiskExplainer.entries(
            containers: [("OrbStack", 2 * gb), ("Docker Desktop", 2 * gb), ("Spotlight dizini", 2 * gb), ("Mail", 2 * gb)],
            cacheBytes: Int(2 * gb), trashBytes: Int(2 * gb), projectsByDisk: [boot: 2 * gb], bootDisk: boot)
        #expect(entries.count == 7)
        for entry in entries { #expect(entry.action != nil, "\(entry.name) eylemsiz") }
    }

    @Test("konteyner eylemleri uygulamayı açar veya komutu kopyalar")
    func outsideActions() {
        let entries = DiskExplainer.entries(
            containers: [("OrbStack", 2 * gb), ("Docker Desktop", 2 * gb), ("Spotlight dizini", 2 * gb), ("Mail", 2 * gb)],
            cacheBytes: -1, trashBytes: -1, projectsByDisk: [:], bootDisk: boot)
        func action(_ name: String) -> DiskExplainer.Action? { entries.first { $0.name == name }?.action }
        #expect(action("Mail") == .openApp(bundleID: "com.apple.mail", name: "Mail", label: "Mail'i aç"))
        #expect(action("OrbStack") == .openApp(bundleID: "dev.kdrag0n.MacVirt", name: "OrbStack", label: "OrbStack'i aç"))
        #expect(action("Docker Desktop") == .openApp(bundleID: "com.docker.docker", name: "Docker Desktop", label: "Docker'ı aç"))
        #expect(action("Spotlight dizini") == .copyCommand("sudo mdutil -E /"))
    }

    @Test("kendi öğeleri sayfa açar")
    func ownRowsOpenPages() {
        let entries = DiskExplainer.entries(
            containers: [], cacheBytes: Int(2 * gb), trashBytes: Int(2 * gb), projectsByDisk: [boot: 2 * gb], bootDisk: boot)
        func action(_ name: String) -> DiskExplainer.Action? { entries.first { $0.name == name }?.action }
        #expect(action("Uygulama önbelleği") == .openPage(.caches))
        #expect(action("Çöp Kutusu") == .openPage(.caches))
        #expect(action("Proje çıktıları") == .openPage(.projects))
    }

    @Test("Mail önerisi doğrulanmış menü adını kullanır")
    func mailAdviceUsesVerifiedMenuName() {
        let entries = DiskExplainer.entries(
            containers: [("Mail", 2 * gb)], cacheBytes: -1, trashBytes: -1, projectsByDisk: [:], bootDisk: boot)
        let advice = entries.first { $0.name == "Mail" }?.advice ?? ""
        #expect(advice.contains("İlişikleri Sil"))
        #expect(!advice.contains("Ek Dosyaları Kaldır"))
    }
}

@Suite("ProjectDiskTotals")
struct ProjectDiskTotalsTests {
    @Test("kayıt JSON olarak gidip gelir")
    func roundTrip() {
        let totals: [String: UInt64] = ["Macintosh HD": 5, "brtc-disk": 9]
        #expect(ProjectDiskTotals.decode(ProjectDiskTotals.encode(totals)) == totals)
    }

    @Test("bozuk ya da boş kayıt boş sözlük döner")
    func badInput() {
        #expect(ProjectDiskTotals.decode("").isEmpty)
        #expect(ProjectDiskTotals.decode("{bozuk").isEmpty)
    }
}
