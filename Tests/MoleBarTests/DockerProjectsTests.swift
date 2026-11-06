import Foundation
import Testing
@testable import MoleBar

struct DockerProjectsTests {
    private let mb: UInt64 = 1_000_000

    @Test func sizeParsingUsesDecimalUnitsAndFirstToken() {
        #expect(DockerSize.parse("774B") == 774)
        #expect(DockerSize.parse("0B") == 0)
        #expect(DockerSize.parse("217kB") == 217_000)
        #expect(DockerSize.parse("599.2MB") == 599_200_000)
        #expect(DockerSize.parse("1.801GB") == 1_801_000_000)
        #expect(DockerSize.parse("217kB (virtual 297MB)") == 217_000)
    }

    @Test func unreadableSizeIsNil() {
        #expect(DockerSize.parse("N/A") == nil)
        #expect(DockerSize.parse("") == nil)
    }

    @Test func longestBoundedCandidateWins() {
        let candidates = ["mia", "mia-erp", "fintec"]
        #expect(DockerProjects.attribute("ddev-mia-erp-snapshots", candidates: candidates) == "mia-erp")
        #expect(DockerProjects.attribute("ddev-mia-snapshots", candidates: candidates) == "mia")
        #expect(DockerProjects.attribute("postgres:16-mia-erp-built", candidates: candidates) == "mia-erp")
        #expect(DockerProjects.attribute("random-volume", candidates: candidates) == nil)
    }

    @Test func shortNamesAndPartialWordsDoNotMatch() {
        #expect(DockerProjects.attribute("ddev/ddev-webserver:v1", candidates: ["web"]) == nil)
        #expect(DockerProjects.attribute("web_data", candidates: ["web"]) == "web")
        #expect(DockerProjects.attribute("a-b", candidates: ["a"]) == nil)
    }

    @Test func shortGenericCandidateDoesNotStealVolumesOfLongerProject() {
        // Gerçek veri: mia-web-wp projesinin hacimleri "web" klasörüne gitmemeli.
        #expect(DockerProjects.attribute("mia-web-wp_project_mutagen", candidates: ["web"]) == nil)
        #expect(DockerProjects.attribute("ddev-mia-web-wp-snapshots", candidates: ["web"]) == nil)
        #expect(DockerProjects.attribute("mia-web-wp-mariadb", candidates: ["web", "mia-web-wp"]) == "mia-web-wp")
    }

    @Test func prefixMatchBeatsInnerMatch() {
        #expect(DockerProjects.attribute("fintec-cache", candidates: ["fintec", "cache-long-name"]) == "fintec")
        #expect(DockerProjects.attribute("ddev-fintec-snapshots", candidates: ["fintec"]) == "fintec")
    }

    @Test func parsesImagesContainersAndVolumes() throws {
        let json = """
        {
          "Images": [{"Repository": "postgres", "Tag": "16-mia-erp-built", "UniqueSize": "599.2MB", "Size": "708MB"}],
          "Containers": [{"Names": "ddev-mia-erp-web", "Size": "18.1MB (virtual 1.4GB)",
                          "Labels": "a=b,com.docker.compose.project=ddev-mia-erp,com.docker.compose.service=web"}],
          "Volumes": [{"Name": "mia-erp-mariadb", "Size": "1.5GB", "Labels": ""}],
          "BuildCache": []
        }
        """
        let entries = DockerProjects.parse(Data(json.utf8))
        #expect(entries.count == 3)
        let image = try #require(entries.first { $0.kind == .image })
        #expect(image.name == "postgres:16-mia-erp-built")
        #expect(image.bytes == 599_200_000)
        let container = try #require(entries.first { $0.kind == .container })
        #expect(container.name == "ddev-mia-erp-web")
        #expect(container.bytes == 18_100_000)
        #expect(container.project == "mia-erp")
        let volume = try #require(entries.first { $0.kind == .volume })
        #expect(volume.bytes == 1_500_000_000)
        #expect(volume.project == nil)
    }

    @Test func invalidJsonGivesNoEntries() {
        #expect(DockerProjects.parse(Data("bozuk".utf8)).isEmpty)
        #expect(DockerProjects.parse(Data()).isEmpty)
    }

    @Test func groupsSumByKindAndPutUnattributedLast() {
        let entries = [
            DockerEntry(kind: .container, name: "ddev-mia-erp-web", bytes: 20 * mb, project: "mia-erp"),
            DockerEntry(kind: .volume, name: "mia-erp-mariadb", bytes: 1_500 * mb, project: nil),
            DockerEntry(kind: .image, name: "postgres:16-mia-erp-built", bytes: 600 * mb, project: nil),
            DockerEntry(kind: .volume, name: "fintec_data", bytes: 300 * mb, project: nil),
            DockerEntry(kind: .volume, name: "bilinmeyen", bytes: 9_000 * mb, project: nil)
        ]
        let groups = DockerProjects.group(entries, candidates: ["mia-erp", "fintec"])
        #expect(groups.map(\.name) == ["mia-erp", "fintec", DockerProjects.otherName])
        let mia = groups[0]
        #expect(mia.total == 2_120 * mb)
        #expect(mia.bytes(.volume) == 1_500 * mb)
        #expect(mia.bytes(.container) == 20 * mb)
        #expect(mia.bytes(.image) == 600 * mb)
    }

    @Test func labelProjectNeedsNoCandidate() {
        let entries = [DockerEntry(kind: .container, name: "x-1", bytes: 5 * mb, project: "fintec")]
        #expect(DockerProjects.group(entries, candidates: []).map(\.name) == ["fintec"])
    }

    @Test func filterKeepsGroupsWhoseNameOrEntriesMatch() {
        let entries = [
            DockerEntry(kind: .volume, name: "mia-erp-mariadb", bytes: 1, project: nil),
            DockerEntry(kind: .volume, name: "fintec_data", bytes: 1, project: nil)
        ]
        let groups = DockerProjects.group(entries, candidates: ["mia-erp", "fintec"])
        #expect(DockerProjects.filter(groups, query: "mia-erp").map(\.name) == ["mia-erp"])
        #expect(DockerProjects.filter(groups, query: "").count == 2)
        #expect(DockerProjects.filter(groups, query: "yok").isEmpty)
    }
}
