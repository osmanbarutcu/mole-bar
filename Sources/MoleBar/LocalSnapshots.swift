import Foundation

struct LocalSnapshot: Identifiable {
    let stamp: String
    let date: Date
    var id: String { stamp }
}

/// Yerel Time Machine anlık görüntüleri. Yalnızca listeler. MoleBar silmez, silme komutunu kullanıcıya verir.
enum LocalSnapshots {
    private static let prefix = "com.apple.TimeMachine."

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter
    }()

    /// `tmutil listlocalsnapshots /` çıktısını ayrıştırır. Başlık ve tanımsız satırlar atlanır.
    static func parse(_ output: String) -> [LocalSnapshot] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix(prefix) else { return nil }
            var stamp = String(text.dropFirst(prefix.count))
            if stamp.hasSuffix(".local") { stamp.removeLast(".local".count) }
            guard let date = formatter.date(from: stamp) else { return nil }
            return LocalSnapshot(stamp: stamp, date: date)
        }
    }

    /// Time Machine yerel görüntüleri normalde en çok bir gün tutulur. 3 günden eskisi olağandışıdır.
    static let unusualAge: TimeInterval = 3 * 86_400

    static func isUnusuallyOld(_ date: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(date) > unusualAge
    }

    /// "5 dk önce", "3 saat önce", "4 gün önce". Gelecek tarih ve bir dakikadan yeni kayıt "az önce" olur.
    static func ageText(of date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "az önce" }
        if seconds < 3_600 { return "\(seconds / 60) dk önce" }
        if seconds < 86_400 { return "\(seconds / 3_600) saat önce" }
        return "\(seconds / 86_400) gün önce"
    }

    static func deleteCommand(for snapshot: LocalSnapshot) -> String {
        "sudo tmutil deletelocalsnapshots \(snapshot.stamp)"
    }

    /// `tmutil` çalışmazsa veya 8 saniyede bitmezse boş döner.
    static func list() -> [LocalSnapshot] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return parse(String(decoding: data, as: UTF8.self))
    }
}
