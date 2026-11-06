import Foundation
import Testing
@testable import MoleBar

private let home = FileManager.default.homeDirectoryForCurrentUser.path

@Suite("TrashGuard.canTrash")
struct TrashGuardTests {
    @Test("ev klasörü ve doğrudan alt öğeleri korunur", arguments: ["", "/Documents", "/Library", "/Desktop"])
    func protectsHomeTopLevel(_ suffix: String) {
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: home + suffix)))
    }

    @Test("ev klasöründe ikinci düzey ve altı açıktır", arguments: ["/Documents/a.txt", "/Library/Caches/foo", "/Downloads/x/y.zip"])
    func allowsHomeDeepPaths(_ suffix: String) {
        #expect(TrashGuard.canTrash(URL(fileURLWithPath: home + suffix)))
    }

    @Test("korumalı ev yolları kapalıdır", arguments: [
        "/Library/Mail/V10/x", "/Library/Messages/chat.db", "/Library/Keychains/login.keychain-db",
        "/Library/Mobile Documents/com~apple~CloudDocs/a", "/Library/Safari/History.db",
        "/Library/Group Containers/group.x/y", "/.ssh/id_ed25519", "/.gnupg/pubring.kbx",
        "/.aws/credentials", "/.kube/config", "/.password-store/a.gpg"
    ])
    func blocksProtectedHomePaths(_ suffix: String) {
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: home + suffix)))
    }

    @Test("medya kütüphaneleri korunur", arguments: [
        "/Pictures/Photos.photoslibrary/x", "/Music/Music.musiclibrary/a", "/Movies/TV.tvlibrary/b"
    ])
    func blocksMediaLibraries(_ suffix: String) {
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: home + suffix)))
    }

    @Test("harici disklerde ikinci düzey açıktır")
    func externalVolumes() {
        #expect(TrashGuard.canTrash(URL(fileURLWithPath: "/Volumes/Disk/a.bin")))
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: "/Volumes/Disk")))
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: "/Volumes")))
    }

    @Test("sistem yolları kapalıdır", arguments: ["/System/Library/x", "/usr/bin/ls", "/Applications/X.app", "/etc/hosts", "/"])
    func blocksSystemPaths(_ path: String) {
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: path)))
    }

    @Test("ana diskin /Volumes bağlantısı korumayı atlatamaz", arguments: [
        "/Library/Mail/x", "/.ssh/id_ed25519", "/Documents"
    ])
    func bootVolumeSymlinkCannotBypass(_ suffix: String) {
        let viaVolumes = "/Volumes/Macintosh HD" + home + suffix
        guard FileManager.default.fileExists(atPath: "/Volumes/Macintosh HD") else { return }
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: viaVolumes)))
    }

    @Test("../ ile kaçış engellenir")
    func dotDotEscape() {
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: home + "/Documents/../Library/Mail/x")))
        #expect(!TrashGuard.canTrash(URL(fileURLWithPath: home + "/Documents/a/../../.ssh/key")))
    }
}
