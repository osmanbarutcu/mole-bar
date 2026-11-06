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

struct SnapshotAgeTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func minutesHoursAndDays() {
        #expect(LocalSnapshots.ageText(of: now.addingTimeInterval(-5 * 60), now: now) == "5 dk önce")
        #expect(LocalSnapshots.ageText(of: now.addingTimeInterval(-3 * 3_600), now: now) == "3 saat önce")
        #expect(LocalSnapshots.ageText(of: now.addingTimeInterval(-4 * 86_400), now: now) == "4 gün önce")
    }

    @Test func justNowForUnderOneMinute() {
        #expect(LocalSnapshots.ageText(of: now.addingTimeInterval(-20), now: now) == "az önce")
    }

    @Test func futureDatesAreTreatedAsJustNow() {
        #expect(LocalSnapshots.ageText(of: now.addingTimeInterval(500), now: now) == "az önce")
    }

    @Test func snapshotsOlderThanThreeDaysAreUnusual() {
        #expect(LocalSnapshots.isUnusuallyOld(now.addingTimeInterval(-4 * 86_400), now: now))
        #expect(!LocalSnapshots.isUnusuallyOld(now.addingTimeInterval(-2 * 86_400), now: now))
    }
}
