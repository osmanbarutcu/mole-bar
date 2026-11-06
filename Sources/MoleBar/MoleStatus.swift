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

/// Kurulu Mole CLI ile köprü. Yol Homebrew varsayılanıdır.
enum MoleCLI {
    static let path = "/opt/homebrew/bin/mo"
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: path) }

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
        post(
            title: "Disk neredeyse dolu",
            body: String(format: "Ana disk %%%.0f dolu. MoleBar panelinden temizlik önizlemesi açabilirsiniz.", percent),
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
