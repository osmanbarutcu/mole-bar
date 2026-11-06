import Foundation

/// Süreç başına ağ hızı. `nettop` ile bir saniyelik fark örneği alır. Kök yetkisi gerekmez.
enum NetPerProcess {
    /// Anahtar süreç kimliği, değer saniyedeki bayt (gelen + giden).
    static func sample() -> [Int32: Double] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-d", "-L", "2", "-s", "1", "-x", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// Çıktıda iki blok vardır. İlki toplam, ikincisi saniyelik farktır. Son blok okunur.
    static func parse(_ output: String) -> [Int32: Double] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard let headerIndex = lines.lastIndex(where: { $0.hasPrefix(",bytes_in") }) else { return [:] }
        var result: [Int32: Double] = [:]
        for line in lines[(headerIndex + 1)...] {
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count >= 3,
                  let dot = fields[0].lastIndex(of: "."),
                  let pid = Int32(fields[0][fields[0].index(after: dot)...]),
                  let inBytes = Double(fields[1]), let outBytes = Double(fields[2]) else { continue }
            result[pid, default: 0] += inBytes + outBytes
        }
        return result
    }
}
