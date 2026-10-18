import AppKit
import Darwin

/// Reads the process table straight from the kernel (no `ps`), plus per-process argv, cwd and CPU time via libproc.
public struct ProcessInfoRecord: Equatable {
    public var pid: pid_t
    public var ppid: pid_t
    public var comm: String
    /// "ttys003" or nil for a process without a controlling terminal.
    public var tty: String?
    /// Seconds since 1970.
    public var startTime: Double
}

public enum ProcessScanner {
    static let machToSeconds: Double = {
        var tb = mach_timebase_info()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom) / 1e9
    }()

    /// Every process owned by the current user.
    public static func list() -> [ProcessInfoRecord] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(getuid())]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        size += size / 4 // processes may appear between the two calls
        let count = size / MemoryLayout<kinfo_proc>.stride + 1
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        var bytes = count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &procs, &bytes, nil, 0) == 0 else { return [] }
        let n = bytes / MemoryLayout<kinfo_proc>.stride
        var out: [ProcessInfoRecord] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var kp = procs[i]
            let pid = kp.kp_proc.p_pid
            guard pid > 0 else { continue }
            let comm = withUnsafePointer(to: &kp.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
            let tdev = kp.kp_eproc.e_tdev
            var tty: String?
            if tdev != -1, tdev != 0, let name = devname(tdev, mode_t(S_IFCHR)) {
                tty = String(cString: name)
            }
            let st = kp.kp_proc.p_starttime
            out.append(ProcessInfoRecord(pid: pid, ppid: kp.kp_eproc.e_ppid, comm: comm, tty: tty,
                                         startTime: Double(st.tv_sec) + Double(st.tv_usec) / 1e6))
        }
        return out
    }

    /// argv of a process we own (empty when the kernel refuses).
    public static func arguments(_ pid: pid_t) -> [String] {
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return [] }
        var buf = [UInt8](repeating: 0, count: Int(argmax))
        var size = Int(argmax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = Int(buf.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < size, buf[i] != 0 { i += 1 }      // exec path
        while i < size, buf[i] == 0 { i += 1 }      // padding
        var args: [String] = []
        var start = i
        while i < size, args.count < argc {
            if buf[i] == 0 {
                args.append(String(decoding: buf[start..<i], as: UTF8.self))
                i += 1
                start = i
            } else {
                i += 1
            }
        }
        return args
    }

    public static func path(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        return String(cString: buf)
    }

    /// Current working directory of a process we own.
    public static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// User + system CPU time consumed so far, in seconds.
    public static func cpuTime(_ pid: pid_t) -> Double? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return Double(info.pti_total_user &+ info.pti_total_system) * machToSeconds
    }

    public static func isAlive(_ pid: pid_t) -> Bool {
        pid > 0 && (kill(pid, 0) == 0 || errno == EPERM)
    }

    /// Walks up the parent chain to the first regular (Dock-visible) app, e.g. a `claude` process → `zsh` → `login` → Terminal.
    public static func hostApp(of pid: pid_t, in table: [pid_t: ProcessInfoRecord]) -> NSRunningApplication? {
        var p = pid
        for _ in 0..<12 {
            guard p > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular { return app }
            guard let rec = table[p] else { return nil }
            p = rec.ppid
        }
        return nil
    }
}
