import AppKit
import Darwin

/// Success means a request was accepted, never that the process has exited.
enum ProcessActionError: Error, Equatable {
    case protectedProcess
    case applicationRefused
    case signalFailed(Int32)

    var message: String {
        switch self {
        case .protectedProcess: return "System and SystemPulse processes are protected"
        case .applicationRefused: return "Application refused the quit request"
        case .signalFailed(let code):
            if code == ESRCH { return "Process is no longer running" }
            if code == EPERM { return "Permission denied" }
            return "Signal failed: \(String(cString: strerror(code)))"
        }
    }
}

/// Injectable OS boundary: tests never send real termination signals.
@MainActor
struct ProcessActions {
    var applicationRequest: (pid_t, Bool) -> Bool?
    /// Returns zero on success, otherwise the captured errno (not kill's -1).
    var signalRequest: (pid_t, Int32) -> Int32
    var ownPID: pid_t

    static var live: ProcessActions {
        ProcessActions(
            applicationRequest: { pid, force in
                guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
                return force ? app.forceTerminate() : app.terminate()
            },
            signalRequest: { pid, signal in
                kill(pid, signal) == 0 ? 0 : errno
            }, ownPID: getpid())
    }

    func isProtected(_ pid: pid_t) -> Bool {
        // kill(0) and kill(negative) target process groups, not individual pids.
        pid <= 1 || pid == ownPID
    }

    func request(pid: pid_t, force: Bool) -> Result<Void, ProcessActionError> {
        guard !isProtected(pid) else { return .failure(.protectedProcess) }
        if let accepted = applicationRequest(pid, force) {
            return accepted ? .success(()) : .failure(.applicationRefused)
        }
        let code = signalRequest(pid, force ? SIGKILL : SIGTERM)
        return code == 0 ? .success(()) : .failure(.signalFailed(code))
    }
}
