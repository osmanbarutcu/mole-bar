import AppKit
import Foundation
import UserNotifications

struct MoleHealth {
    let score: Int
    let message: String
}

private struct HealthPayload: Decodable {
    let health_score: Int
    let health_score_msg: String
}

/// Kurulu Mole CLI ile köprü. Apple Silicon ve Intel Homebrew yolları denenir.
enum MoleCLI {
    static let candidates = ["/opt/homebrew/bin/mo", "/usr/local/bin/mo"]
    /// Çıktı ayrıştırıcısı bu sürümün gerçek çıktısıyla denendi (Tests/MoleBarTests/Fixtures).
    static let testedVersion = "1.32.0"

    static var path: String { resolvePath(candidates: candidates) ?? candidates[0] }
    static var isInstalled: Bool { resolvePath(candidates: candidates) != nil }

    static func resolvePath(candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// "Mole version 1.32.0" gibi satırdan sürümü alır.
    static func parseVersion(_ output: String) -> String? {
        let range = output.range(of: #"\d+\.\d+\.\d+(?:-[0-9A-Za-z.]*[0-9A-Za-z])?"#, options: .regularExpression)
        return range.map { String(output[$0]) }
    }

    static func isTested(_ version: String?) -> Bool { version == testedVersion }

    /// `mo --version` çalıştırır. 5 saniyede bitmezse süreci sonlandırır.
    static func fetchVersion() async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            guard isInstalled else { return nil }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                if process.isRunning { process.terminate() }
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return parseVersion(String(decoding: data, as: UTF8.self))
        }.value
    }

    /// `mo status -json` çalıştırır. 15 saniyede bitmezse süreci sonlandırır.
    static func fetchHealth() async -> MoleHealth? {
        await Task.detached(priority: .utility) { () -> MoleHealth? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["status", "-json"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            process.environment = environment
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }

            DispatchQueue.global().asyncAfter(deadline: .now() + 15) {
                if process.isRunning { process.terminate() }
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let start = data.firstIndex(of: UInt8(ascii: "{")),
                  let payload = try? JSONDecoder().decode(HealthPayload.self, from: data[start...]) else { return nil }
            return MoleHealth(score: payload.health_score, message: payload.health_score_msg)
        }.value
    }
}

/// Komutu Terminal.app'te açar. Geçici .command dosyası kullanır, Automation izni gerekmez.
/// Yalnızca kod içindeki sabit komutlar geçirilir.
enum TerminalBridge {
    static func run(_ command: String) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("molebar-\(UUID().uuidString).command")
        let script = """
        #!/bin/zsh
        export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
        clear
        \(command)
        rm -f "$0"
        """
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }
}

enum DiskNotifier {
    static func notify(percent: Double) {
        let defaults = UserDefaults.standard
        let parts: [(label: String, key: ReclaimStore.Key)] = [
            ("Önbellek", .cache), ("büyük dosyalar", .large), ("kopyalar", .duplicates)
        ]
        // Değer -1 taranmadı demektir. Taranmamış ve sıfır değerler metne girmez.
        let known = parts.compactMap { part -> String? in
            let bytes = defaults.object(forKey: part.key.rawValue) as? Int ?? -1
            return bytes > 0 ? "\(part.label) \(formatBytes(UInt64(bytes)))" : nil
        }
        let hint = known.isEmpty
            ? "MoleBar panelinden temizlik önizlemesi açabilirsiniz."
            : "Kazanılabilir: " + known.joined(separator: ", ") + "."
        post(
            title: "Disk neredeyse dolu",
            body: String(format: "Ana disk %%%.0f dolu. ", percent) + hint,
            id: "molebar.disk"
        )
    }

    static func post(title: String, body: String, id: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
