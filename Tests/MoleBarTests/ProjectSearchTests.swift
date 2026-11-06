import Foundation
import Testing
@testable import MoleBar

struct ProjectSearchTests {
    private func artifact(_ path: String, kind: String, project: String, bytes: UInt64 = 1) -> ProjectArtifact {
        ProjectArtifact(url: URL(fileURLWithPath: path), kind: kind, project: project, lastActive: nil, disk: "brtc-disk", bytes: bytes, sized: true)
    }

    private var sample: [ProjectArtifact] {
        [
            artifact("/Volumes/brtc-disk/Proje/mia-erp/vendor", kind: "vendor", project: "mia-erp"),
            artifact("/Volumes/brtc-disk/Proje/mia-erp/node_modules", kind: "node_modules", project: "mia-erp"),
            artifact("/Volumes/brtc-disk/Proje/mia-bt-destek/vendor", kind: "vendor", project: "mia-bt-destek"),
            artifact("/Volumes/brtc-disk/Proje/fintec/web/node_modules", kind: "node_modules", project: "web")
        ]
    }

    @Test func emptyOrBlankQueryReturnsEverything() {
        #expect(ProjectFilter.search(sample, query: "").count == 4)
        #expect(ProjectFilter.search(sample, query: "   ").count == 4)
    }

    @Test func projectNameMatchIsCaseInsensitive() {
        #expect(ProjectFilter.search(sample, query: "MIA-ERP").map(\.project) == ["mia-erp", "mia-erp"])
    }

    @Test func similarNamesDoNotMatchLongerQuery() {
        #expect(ProjectFilter.search(sample, query: "mia-erp").allSatisfy { $0.project == "mia-erp" })
    }

    @Test func pathSegmentMatchesWhenProjectNameDiffers() {
        let hits = ProjectFilter.search(sample, query: "fintec")
        #expect(hits.count == 1)
        #expect(hits[0].project == "web")
    }

    @Test func allTokensMustMatchIncludingKind() {
        let hits = ProjectFilter.search(sample, query: "erp vendor")
        #expect(hits.count == 1)
        #expect(hits[0].kind == "vendor")
    }

    @Test func diacriticsAreIgnored() {
        let items = [artifact("/Volumes/x/Proje/Çalışma/vendor", kind: "vendor", project: "Çalışma")]
        #expect(ProjectFilter.search(items, query: "calisma").count == 1)
    }

    @Test func matchesHelperWorksOnPlainText() {
        #expect(ProjectFilter.matches("ddev-mia-erp-snapshots", query: "mia-erp"))
        #expect(!ProjectFilter.matches("ddev-mia-erp-snapshots", query: "fintec"))
        #expect(ProjectFilter.matches("anything", query: ""))
    }
}
