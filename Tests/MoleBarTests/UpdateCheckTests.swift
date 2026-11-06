import Foundation
import Testing
@testable import MoleBar

struct UpdateCheckTests {
    @Test func parsesTagFromReleaseJSON() {
        let data = Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/osmanbarutcu/mole-bar/releases/tag/v0.2.0","draft":false,"prerelease":false}"#.utf8)
        let release = UpdateCheck.parse(data)
        #expect(release?.version == "0.2.0")
        #expect(release?.url.absoluteString == "https://github.com/osmanbarutcu/mole-bar/releases/tag/v0.2.0")
    }

    @Test func ignoresDraftsAndPrereleases() {
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"v9.0.0","html_url":"https://github.com/o/r/releases/tag/v9.0.0","draft":true}"#.utf8)) == nil)
        #expect(UpdateCheck.parse(Data(#"{"tag_name":"v9.0.0","html_url":"https://github.com/o/r/releases/tag/v9.0.0","prerelease":true}"#.utf8)) == nil)
    }

    @Test func rejectsBadInput() {
        #expect(UpdateCheck.parse(Data("bozuk".utf8)) == nil)
        #expect(UpdateCheck.parse(Data("{}".utf8)) == nil)
    }

    @Test func refusesLinksOutsideGitHub() {
        // Yanıt değiştirilse bile kullanıcı başka siteye yönlendirilmez.
        let data = Data(#"{"tag_name":"v0.2.0","html_url":"https://kotu.example/indir"}"#.utf8)
        #expect(UpdateCheck.parse(data) == nil)
    }

    @Test func comparesVersionsNumerically() {
        #expect(UpdateCheck.isNewer("0.2.0", than: "0.1.0"))
        #expect(UpdateCheck.isNewer("0.10.0", than: "0.9.0"))
        #expect(UpdateCheck.isNewer("1.0.0", than: "0.9.9"))
        #expect(!UpdateCheck.isNewer("0.1.0", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("0.1.0", than: "0.2.0"))
    }

    @Test func badVersionStringsAreNeverNewer() {
        #expect(!UpdateCheck.isNewer("abc", than: "0.1.0"))
        #expect(!UpdateCheck.isNewer("0.2.0", than: "abc"))
    }

    @Test func tagWithoutVPrefixWorks() {
        let data = Data(#"{"tag_name":"0.3.1","html_url":"https://github.com/o/r/releases/tag/0.3.1"}"#.utf8)
        #expect(UpdateCheck.parse(data)?.version == "0.3.1")
    }
}
