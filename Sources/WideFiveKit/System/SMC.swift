import Foundation
import IOKit

/// Minimal AppleSMC reader for CPU temperature and fan RPM. Works on Intel Macs (incl. 2020 13" MBP);
/// on Apple Silicon most keys differ and readings may return nil.
public final class SMC {
    public static let shared = SMC()

    private struct KeyDataVers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
    private typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                 UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    private struct KeyData {
        var key: UInt32 = 0
        var vers = KeyDataVers()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private var conn: io_connect_t = 0
    private var available = false
    private var keyInfoCache: [UInt32: KeyInfo] = [:]

    private init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        available = IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess
        IOObjectRelease(service)
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outSize = MemoryLayout<KeyData>.stride
        let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
        return r == kIOReturnSuccess && output.result == 0 ? output : nil
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard available else { return nil }
        let k = Self.fourCC(key)
        var info = keyInfoCache[k]
        if info == nil {
            var input = KeyData()
            input.key = k
            input.data8 = 9 // kSMCGetKeyInfo
            guard let out = call(&input) else { return nil }
            info = out.keyInfo
            keyInfoCache[k] = info
        }
        guard let info, info.dataSize > 0 else { return nil }
        var input = KeyData()
        input.key = k
        input.keyInfo.dataSize = info.dataSize
        input.data8 = 5 // kSMCReadKey
        guard var out = call(&input) else { return nil }
        let bytes = withUnsafeBytes(of: &out.bytes) { Array($0.prefix(Int(info.dataSize))) }
        let t = info.dataType
        let type = String(bytes: [UInt8(t >> 24 & 0xFF), UInt8(t >> 16 & 0xFF), UInt8(t >> 8 & 0xFF), UInt8(t & 0xFF)], encoding: .ascii) ?? ""
        return (type, bytes)
    }

    private func number(_ key: String) -> Double? {
        guard let (type, b) = read(key), !b.isEmpty else { return nil }
        switch type {
        case "sp78" where b.count >= 2: return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256
        case "fpe2" where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
        case "flt " where b.count >= 4:
            return Double(Float(bitPattern: UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24))
        case "ui8 ": return Double(b[0])
        case "ui16" where b.count >= 2: return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        default: return nil
        }
    }

    public var cpuTemperature: Double? {
        for k in ["TC0P", "TC0D", "TC0E", "TC0F", "TCXC", "Tp09", "Tp01", "Tp05"] {
            if let v = number(k), v > 5, v < 130 { return v }
        }
        return nil
    }

    public var fanRPM: Double? {
        if let v = number("F0Ac"), v >= 0 { return v }
        return nil
    }
}
