import Foundation
import Testing
@testable import MoleBar

struct LocalSnapshotsTests {
    @Test func parsesSnapshotLinesAndIgnoresHeader() {
        let output = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-04-091500.local
        com.apple.TimeMachine.2026-11-05-123456.local
        """
        let snapshots = LocalSnapshots.parse(output)
        #expect(snapshots.map(\.stamp) == ["2026-11-04-091500", "2026-11-05-123456"])
    }

    @Test func emptyOutputGivesNoSnapshots() {
        #expect(LocalSnapshots.parse("Snapshots for disk /:\n").isEmpty)
        #expect(LocalSnapshots.parse("").isEmpty)
    }

    @Test func ignoresUnrelatedAndMalformedLines() {
        let output = "com.apple.os.update-ABC123\ncom.apple.TimeMachine.bozuk.local\ncom.apple.TimeMachine.2026-11-05-123456.local"
        #expect(LocalSnapshots.parse(output).map(\.stamp) == ["2026-11-05-123456"])
    }

    @Test func dateIsReadFromStamp() throws {
        let snapshot = try #require(LocalSnapshots.parse("com.apple.TimeMachine.2026-11-05-123456.local").first)
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: snapshot.date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 5)
        #expect(parts.hour == 12 && parts.minute == 34 && parts.second == 56)
    }

    @Test func deleteCommandNamesStampWithoutRunning() {
        let snapshot = LocalSnapshots.parse("com.apple.TimeMachine.2026-11-05-123456.local")[0]
        #expect(LocalSnapshots.deleteCommand(for: snapshot) == "sudo tmutil deletelocalsnapshots 2026-11-05-123456")
    }
}
