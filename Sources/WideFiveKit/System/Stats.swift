import Foundation
import IOKit.ps
import Darwin

/// Samples CPU, memory, battery, network, disk. Call `sample()` ~1/sec.
public final class Stats {
    public static let shared = Stats()

    public private(set) var cpu: Double = 0          // 0…1
    public private(set) var cpuHistory: [Double] = []
    public private(set) var memUsed: Double = 0      // bytes
    public private(set) var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory)
    public private(set) var battery: Double?         // 0…1
    public private(set) var charging = false
    public private(set) var netUp: Double = 0        // bytes/sec
    public private(set) var netDown: Double = 0
    public private(set) var netHistory: [Double] = []
    public private(set) var diskFree: Double = 0
    public private(set) var diskTotal: Double = 0
    public private(set) var temperature: Double?
    public private(set) var fan: Double?
    public var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private var prevTicks: (used: UInt64, total: UInt64)?
    private var prevNet: (inB: UInt64, outB: UInt64, t: Double)?
    private var lastSample: Double = 0
    private var tick = 0

    public func sampleIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastSample >= 0.95 { sample(); lastSample = now }
    }

    public func sample() {
        sampleCPU(); sampleMemory(); sampleNet()
        if tick % 5 == 0 { sampleBattery(); sampleDisk() }
        if tick % 2 == 0 { temperature = SMC.shared.cpuTemperature; fan = SMC.shared.fanRPM }
        tick += 1
    }

    private func sampleCPU() {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        var ncpu: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &ncpu, &info, &count) == KERN_SUCCESS, let info else { return }
        var used: UInt64 = 0, total: UInt64 = 0
        for i in 0..<Int(ncpu) {
            let base = Int(CPU_STATE_MAX) * i
            let user = UInt64(info[base + Int(CPU_STATE_USER)]), sys = UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt64(info[base + Int(CPU_STATE_NICE)]), idle = UInt64(info[base + Int(CPU_STATE_IDLE)])
            used += user + sys + nice
            total += user + sys + nice + idle
        }
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        if let p = prevTicks, total > p.total {
            cpu = Double(used - p.used) / Double(total - p.total)
            cpuHistory.append(cpu)
            if cpuHistory.count > 60 { cpuHistory.removeFirst() }
        }
        prevTicks = (used, total)
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        memUsed = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private func sampleBattery() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { battery = nil; return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            battery = Double(cur) / Double(max)
            charging = (d[kIOPSIsChargingKey] as? Bool) ?? false || (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return
        }
        battery = nil
    }

    private func sampleNet() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var inB: UInt64 = 0, outB: UInt64 = 0
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let name = String(cString: cur.pointee.ifa_name)
            if let addr = cur.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), !name.hasPrefix("lo"),
               let data = cur.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                inB += UInt64(data.pointee.ifi_ibytes)
                outB += UInt64(data.pointee.ifi_obytes)
            }
            p = cur.pointee.ifa_next
        }
        let t = ProcessInfo.processInfo.systemUptime
        if let prev = prevNet, t > prev.t, inB >= prev.inB, outB >= prev.outB {
            netDown = Double(inB - prev.inB) / (t - prev.t)
            netUp = Double(outB - prev.outB) / (t - prev.t)
            netHistory.append(netDown)
            if netHistory.count > 60 { netHistory.removeFirst() }
        }
        prevNet = (inB, outB, t)
    }

    private func sampleDisk() {
        if let a = try? FileManager.default.attributesOfFileSystem(forPath: "/") {
            diskFree = (a[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
            diskTotal = (a[.systemSize] as? NSNumber)?.doubleValue ?? 0
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let cap = v.volumeAvailableCapacityForImportantUsage { diskFree = Double(cap) }
    }

    public static func bytes(_ b: Double, perSec: Bool = false) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var v = b, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1024; i += 1 }
        let s = v >= 100 || i == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return s + units[i] + (perSec ? "/s" : "")
    }
}
