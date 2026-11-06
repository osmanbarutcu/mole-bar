import Foundation
import IOKit

/// SMC anahtar değerlerini çözer. Yalnızca okuma için gereken türler desteklenir.
enum SMCValue {
    static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(bytes.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        default:
            return nil
        }
    }
}

/// Sıcaklık okumalarını CPU ve GPU için özetler.
struct SensorSummary: Equatable {
    var cpu: Double?
    var gpu: Double?

    /// Makul sıcaklık aralığı. Kapalı sensör 0 veya uç değer döndürür.
    private static let plausible = 10.0...125.0

    /// Apple Silicon: `Tp` (performans çekirdekleri), `Te` (verimlilik çekirdekleri). Intel: `TC`.
    static func isCPUKey(_ key: String) -> Bool {
        key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("TC")
    }

    /// Apple Silicon: `Tg`. Intel: `TG`.
    static func isGPUKey(_ key: String) -> Bool {
        key.hasPrefix("Tg") || key.hasPrefix("TG")
    }

    /// Her grupta en sıcak değer alınır. Ortalama, tek sıcak çekirdeği gizler.
    static func make(_ readings: [String: Double]) -> SensorSummary {
        func hottest(_ match: (String) -> Bool) -> Double? {
            readings.filter { match($0.key) && plausible.contains($0.value) }.values.max()
        }
        return SensorSummary(cpu: hottest(isCPUKey), gpu: hottest(isGPUKey))
    }
}

struct SensorReading: Equatable {
    var summary: SensorSummary
    /// Fan hızları (dev/dk). Fansız Mac'te boştur.
    var fanRPM: [Int]

    var isEmpty: Bool { summary.cpu == nil && summary.gpu == nil && fanRPM.isEmpty }
}

/// AppleSMC kullanıcı istemcisi. Yalnızca okur, hiçbir anahtara yazmaz.
/// Anahtar adları çip nesline göre değişir. Bu yüzden anahtarlar dizinden keşfedilir.
final class SMCReader {
    private struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    /// C yapısıyla aynı yerleşim için 3 bayt dolgu gerekir (toplam 80 bayt).
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attrs: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0, pad3: UInt8 = 0 }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct KeyData {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimit()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let handleEvent: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readIndex: UInt8 = 8
    private static let readKeyInfo: UInt8 = 9

    private var connection: io_connect_t = 0
    private var temperatureKeys: [String]?

    /// Yerleşim 80 bayt değilse çağrılar geçersiz olur. O durumda bağlantı açılmaz.
    init?() {
        guard MemoryLayout<KeyData>.size == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    private static func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func text(_ code: UInt32) -> String {
        withUnsafeBytes(of: code.bigEndian) { String(decoding: $0, as: UTF8.self) }
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var size = MemoryLayout<KeyData>.size
        let status = IOConnectCallStructMethod(connection, Self.handleEvent, &input, size, &output, &size)
        return status == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    func value(_ key: String) -> Double? {
        var request = KeyData()
        request.key = Self.code(key)
        request.data8 = Self.readKeyInfo
        guard let info = call(&request) else { return nil }
        var read = KeyData()
        read.key = request.key
        read.info.dataSize = info.info.dataSize
        read.data8 = Self.readBytes
        guard let output = call(&read) else { return nil }
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.info.dataSize))) }
        return SMCValue.decode(type: Self.text(info.info.dataType), bytes: bytes)
    }

    private func key(at index: UInt32) -> String? {
        var request = KeyData()
        request.data8 = Self.readIndex
        request.data32 = index
        return call(&request).map { Self.text($0.key) }
    }

    /// Sıcaklık anahtarlarını bir kez keşfeder ve saklar.
    private func discoverTemperatureKeys() -> [String] {
        if let temperatureKeys { return temperatureKeys }
        let total = Int(value("#KEY") ?? 0)
        var found: [String] = []
        for index in 0..<min(total, 4000) {
            guard let name = key(at: UInt32(index)) else { continue }
            if SensorSummary.isCPUKey(name) || SensorSummary.isGPUKey(name) { found.append(name) }
        }
        temperatureKeys = found
        return found
    }

    func read() -> SensorReading {
        var readings: [String: Double] = [:]
        for name in discoverTemperatureKeys() {
            if let temperature = value(name) { readings[name] = temperature }
        }
        let fanCount = Int(value("FNum") ?? 0)
        let fans = (0..<min(fanCount, 4)).compactMap { value("F\($0)Ac") }.map { Int($0.rounded()) }
        return SensorReading(summary: SensorSummary.make(readings), fanRPM: fans)
    }
}
