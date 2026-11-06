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

    @Test func packageManagerCachesAreListed() {
        for path in ["go/pkg/mod", ".cargo/git", ".nuget/packages", ".composer/cache", ".yarn/berry/cache", ".local/share/pnpm/store"] {
            #expect(DeveloperData.trashable.contains(path), "\(path) listede yok")
        }
    }

    @Test func pathsWithPossiblyIrreplaceableDataAreNotListed() {
        // .m2/repository ve .pub-cache yerel kurulum içerir, yeniden üretilemeyebilir.
        let all = Set(DeveloperData.trashable)
        #expect(!all.contains(".m2/repository"))
        #expect(!all.contains(".pub-cache"))
    }

    @Test func archivesAndBackupsAreDisplayOnly() {
        let relatives = DeveloperData.displayOnly.map(\.relative)
        #expect(relatives.contains("Library/Developer/Xcode/Archives"))
        #expect(relatives.contains("Library/Application Support/MobileSync/Backup"))
        #expect(relatives.contains("Library/Developer/CoreSimulator/Devices"))
    }
}

struct MailDownloadsTests {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Test func openedAttachmentCopiesCanBeTrashed() {
        let copy = home.appendingPathComponent(DeveloperData.mailDownloads).appendingPathComponent("ABC-123")
        #expect(TrashGuard.canTrash(copy))
    }

    @Test func mailStoreStaysProtected() {
        #expect(!TrashGuard.canTrash(home.appendingPathComponent("Library/Mail/V10")))
    }
}
