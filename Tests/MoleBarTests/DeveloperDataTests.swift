import Foundation
import Testing
@testable import MoleBar

struct DeveloperDataTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test func trashablePathsPassTrashGuard() {
        for path in DeveloperData.trashable {
            #expect(TrashGuard.canTrash(home.appendingPathComponent(path)), "\(path) korumalı yolda")
        }
    }

    @Test func displayOnlyPathsAreNeverTrashable() {
        let trashable = Set(DeveloperData.trashable)
        for item in DeveloperData.displayOnly {
            #expect(!trashable.contains(item.relative), "\(item.relative) hem listeli hem silinebilir")
        }
    }

    @Test func archivesAndBackupsAreDisplayOnly() {
        let relatives = DeveloperData.displayOnly.map(\.relative)
        #expect(relatives.contains("Library/Developer/Xcode/Archives"))
        #expect(relatives.contains("Library/Application Support/MobileSync/Backup"))
        #expect(relatives.contains("Library/Developer/CoreSimulator/Devices"))
    }
}
