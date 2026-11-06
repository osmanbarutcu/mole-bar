import Foundation
import Testing
@testable import MoleBar

struct OrphanScannerTests {
    @Test func readsBundleIDFromPlainName() {
        #expect(OrphanScanner.bundleID(fromName: "com.example.Tool") == "com.example.Tool")
    }

    @Test func stripsSavedStateSuffix() {
        #expect(OrphanScanner.bundleID(fromName: "com.example.Tool.savedState") == "com.example.Tool")
    }

    @Test func rejectsNamesThatAreNotBundleIDs() {
        #expect(OrphanScanner.bundleID(fromName: "Google") == nil)
        #expect(OrphanScanner.bundleID(fromName: "example.com") == nil)
        #expect(OrphanScanner.bundleID(fromName: ".DS_Store") == nil)
        #expect(OrphanScanner.bundleID(fromName: "com.example.My Tool") == nil)
    }

    @Test func rejectsAppleAndOwnIDs() {
        #expect(OrphanScanner.bundleID(fromName: "com.apple.Safari") == nil)
        #expect(OrphanScanner.bundleID(fromName: "local.molebar") == nil)
    }

    @Test func installedAppOwnsItsHelpersAndParents() {
        let installed: Set<String> = ["com.example.tool"]
        #expect(OrphanScanner.isOwned("com.example.tool", by: installed))
        #expect(OrphanScanner.isOwned("com.example.tool.helper", by: installed))
        #expect(OrphanScanner.isOwned("com.example.TOOL", by: installed))
        #expect(!OrphanScanner.isOwned("com.example.other", by: installed))
        #expect(!OrphanScanner.isOwned("com.example.toolbox", by: installed))
    }

    @Test func orphanIDsSkipInstalledApps() {
        let names = ["com.example.tool", "com.gone.app", "com.gone.app.savedState", "Plain Folder"]
        let result = OrphanScanner.orphanIDs(names: names, installed: ["com.example.tool"])
        #expect(result == ["com.gone.app", "com.gone.app"])
    }

    @Test func sameVendorAsInstalledAppIsHidden() {
        // Güncelleyiciler ve yardımcılar /Applications dışında durur. Aynı üreticide kurulu uygulama varsa gizlenir.
        let installed: Set<String> = ["com.microsoft.Word"]
        #expect(OrphanScanner.orphanIDs(names: ["com.microsoft.autoupdate2"], installed: installed).isEmpty)
        #expect(OrphanScanner.orphanIDs(names: ["com.other.autoupdate2"], installed: installed) == ["com.other.autoupdate2"])
    }

    @Test func vendorIsTheFirstTwoComponents() {
        #expect(OrphanScanner.vendor(of: "com.microsoft.Word.helper") == "com.microsoft")
    }
}
