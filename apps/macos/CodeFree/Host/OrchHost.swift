import Darwin
import Foundation

/// Shell-owned sidecar lifecycle. Orch never chooses Mac paths.
///
/// Hybrid lifecycle: idle quit → SIGTERM; busy quit → leave orch running and reattach
/// on next launch via endpoint file + token (design: wiring § Host contract).
final class OrchHost: @unchecked Sendable {
    struct Paths: Sendable {
        let appSupport: URL
        let dataRoot: URL
        let tokenFile: URL
        let logDir: URL
        let endpointFile: URL

        static func `default`() throws -> Paths {
            let fm = FileManager.default
            guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw HostError.noAppSupport
            }
            let root = base.appendingPathComponent("code-free", isDirectory: true)
            let dataRoot = root.appendingPathComponent("data", isDirectory: true)
            let logDir = root.appendingPathComponent("logs", isDirectory: true)
            try fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)
            try fm.createDirectory(at: logDir, withIntermediateDirectories: true)
            return Paths(
                appSupport: root,
                dataRoot: dataRoot,
                tokenFile: root.appendingPathComponent("token"),
                logDir: logDir,
                endpointFile: root.appendingPathComponent("endpoint.json")
            )
        }
    }

    struct LaunchInfo: Sendable {
        let endpoint: URL
        let token: String
        let pid: Int32
        /// True when this host owns a Process and should SIGTERM it on idle stop.
        let owned: Bool
    }

    private var process: Process?
    private var attachedPid: Int32?
    private var stdoutPipe: Pipe?
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let process, process.isRunning { return true }
        if let pid = attachedPid, Self.isProcessAlive(pid) { return true }
        return false
    }

    /// Launch or reattach to orchestrator. Token is never logged.
    func start(paths: Paths) throws -> LaunchInfo {
        lock.lock()
        defer { lock.unlock() }

        if let existing = process, existing.isRunning {
            if let info = try? readLaunchInfo(paths: paths, pid: existing.processIdentifier, owned: true) {
                return info
            }
        }

        // Hybrid reattach: prior quit left orch running (busy turn).
        if let reattached = try? tryReattach(paths: paths) {
            process = nil
            attachedPid = reattached.pid
            stdoutPipe = nil
            return reattached
        }

        try stopLocked(leaveRunning: false)

        let launch = try resolveOrchLaunch()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launch.executable)
        proc.arguments = launch.arguments + [
            "--data-root", paths.dataRoot.path,
            "--token-file", paths.tokenFile.path,
            "--log-dir", paths.logDir.path,
            "--bind", "127.0.0.1:0",
        ]
        proc.environment = ProcessInfo.processInfo.environment
        proc.qualityOfService = .userInitiated

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe() // discard stderr; logs go to log-dir
        stdoutPipe = pipe

        try proc.run()
        process = proc
        attachedPid = proc.processIdentifier

        let endpointLine = try readEndpointLine(from: pipe, process: proc)
        let payload = try parseEndpointPayload(endpointLine)

        let token = try String(contentsOf: paths.tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HostError.tokenUnreadable
        }
        guard let url = URL(string: payload.endpoint) else {
            throw HostError.badEndpoint(payload.endpoint)
        }

        // Persist endpoint + pid for reattach after busy quit.
        try writeEndpointFile(
            paths: paths,
            endpoint: payload.endpoint,
            tokenFile: paths.tokenFile.path,
            pid: proc.processIdentifier
        )

        return LaunchInfo(
            endpoint: url,
            token: token,
            pid: proc.processIdentifier,
            owned: true
        )
    }

    /// Stop sidecar. When `leaveRunning` is true (active turn), keep the process and endpoint file.
    func stop(leaveRunning: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        try? stopLocked(leaveRunning: leaveRunning)
    }

    private func stopLocked(leaveRunning: Bool) throws {
        if leaveRunning {
            // Detach without SIGTERM so a busy harness keeps running.
            process = nil
            stdoutPipe = nil
            // Keep attachedPid / endpoint.json for reattach.
            return
        }

        if let proc = process, proc.isRunning {
            proc.terminate()
            let deadline = Date().addingTimeInterval(3)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if proc.isRunning {
                proc.interrupt()
            }
        } else if let pid = attachedPid, Self.isProcessAlive(pid) {
            // Reattached external orch — terminate by pid.
            kill(pid, SIGTERM)
            let deadline = Date().addingTimeInterval(3)
            while Self.isProcessAlive(pid) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if Self.isProcessAlive(pid) {
                kill(pid, SIGKILL)
            }
        }

        process = nil
        attachedPid = nil
        stdoutPipe = nil
    }

    // MARK: - Reattach

    /// If endpoint.json points at a live loopback orch, reuse it (do not spawn a second writer).
    private func tryReattach(paths: Paths) throws -> LaunchInfo {
        let info = try readPersistedEndpoint(paths: paths)
        if let pid = info.pid, !Self.isProcessAlive(pid) {
            throw HostError.orchExitedEarly
        }
        guard Self.isEndpointReachable(info.endpoint) else {
            throw HostError.endpointTimeout
        }
        let token = try String(contentsOf: paths.tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HostError.tokenUnreadable
        }
        return LaunchInfo(
            endpoint: info.endpoint,
            token: token,
            pid: info.pid ?? 0,
            owned: false
        )
    }

    private struct PersistedEndpoint {
        let endpoint: URL
        let pid: Int32?
    }

    private func readPersistedEndpoint(paths: Paths) throws -> PersistedEndpoint {
        let line = try String(contentsOf: paths.endpointFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = try parseEndpointPayload(line)
        guard let url = URL(string: payload.endpoint) else {
            throw HostError.badEndpoint(payload.endpoint)
        }
        return PersistedEndpoint(endpoint: url, pid: payload.pid)
    }

    private func writeEndpointFile(
        paths: Paths,
        endpoint: String,
        tokenFile: String,
        pid: Int32
    ) throws {
        let obj: [String: Any] = [
            "endpoint": endpoint,
            "tokenFile": tokenFile,
            "pid": pid,
        ]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        try data.write(to: paths.endpointFile, options: .atomic)
    }

    /// TCP connect probe — cheap liveness before WS hello.
    static func isEndpointReachable(_ url: URL, timeout: TimeInterval = 0.4) -> Bool {
        guard let host = url.host, let port = url.port else { return false }
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        // Non-blocking connect with short poll.
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        guard host.withCString({ inet_pton(AF_INET, $0, &addr.sin_addr) }) == 1 else {
            return false
        }

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if result == 0 { return true }
        if errno != EINPROGRESS { return false }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let ms = Int32(timeout * 1000)
        let pr = poll(&pfd, 1, ms)
        guard pr > 0, (pfd.revents & Int16(POLLOUT)) != 0 else { return false }

        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }

    static func isProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    // MARK: - Resolve binary

    struct OrchLaunch {
        let executable: String
        let arguments: [String]
    }

    /// Resolution order: CODE_FREE_ORCH, built dist cli, pnpm workspace start, PATH code-free-orch.
    static func resolveOrchLaunch() throws -> OrchLaunch {
        let env = ProcessInfo.processInfo.environment

        if let custom = env["CODE_FREE_ORCH"], !custom.isEmpty {
            if custom.contains(" ") {
                return OrchLaunch(executable: "/bin/zsh", arguments: ["-lc", custom])
            }
            return OrchLaunch(executable: custom, arguments: [])
        }

        if let repo = env["CODE_FREE_REPO_ROOT"] ?? discoverRepoRoot() {
            let orchDir = URL(fileURLWithPath: repo)
                .appendingPathComponent("apps/orchestrator")
            let distCli = orchDir.appendingPathComponent("dist/cli.js")
            let srcCli = orchDir.appendingPathComponent("src/cli.ts")
            let node = resolveNode()

            if FileManager.default.fileExists(atPath: distCli.path) {
                return OrchLaunch(
                    executable: node,
                    arguments: [distCli.path]
                )
            }
            if FileManager.default.fileExists(atPath: srcCli.path) {
                if let pnpm = which("pnpm") {
                    return OrchLaunch(
                        executable: pnpm,
                        arguments: [
                            "--dir", orchDir.path,
                            "exec", "node", "--import", "tsx", "src/cli.ts",
                        ]
                    )
                }
                return OrchLaunch(
                    executable: node,
                    arguments: ["--import", "tsx", srcCli.path]
                )
            }
        }

        if let bin = which("code-free-orch") {
            return OrchLaunch(executable: bin, arguments: [])
        }

        throw HostError.orchNotFound
    }

    private func resolveOrchLaunch() throws -> OrchLaunch {
        try Self.resolveOrchLaunch()
    }

    private static func resolveNode() -> String {
        which("node") ?? "/opt/homebrew/bin/node"
    }

    private static func which(_ name: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = [name]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    /// Walk up from executable / cwd looking for pnpm-workspace.yaml.
    private static func discoverRepoRoot() -> String? {
        var candidates: [URL] = []
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        if let env = ProcessInfo.processInfo.environment["PWD"] {
            candidates.append(URL(fileURLWithPath: env))
        }
        for start in candidates {
            var url = start
            for _ in 0..<8 {
                let marker = url.appendingPathComponent("pnpm-workspace.yaml")
                if FileManager.default.fileExists(atPath: marker.path) {
                    return url.path
                }
                let parent = url.deletingLastPathComponent()
                if parent.path == url.path { break }
                url = parent
            }
        }
        return nil
    }

    // MARK: - Endpoint line

    private struct EndpointPayload: Decodable {
        let endpoint: String
        let tokenFile: String?
        let pid: Int32?
    }

    private func readEndpointLine(from pipe: Pipe, process: Process) throws -> String {
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        let deadline = Date().addingTimeInterval(15)

        while Date() < deadline {
            if !process.isRunning && buffer.isEmpty {
                throw HostError.orchExitedEarly
            }
            let chunk = handle.availableData
            if !chunk.isEmpty {
                buffer.append(chunk)
                if let s = String(data: buffer, encoding: .utf8),
                   let line = s.split(separator: "\n", omittingEmptySubsequences: false).first,
                   line.contains("endpoint")
                {
                    return String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        throw HostError.endpointTimeout
    }

    private func parseEndpointPayload(_ line: String) throws -> EndpointPayload {
        guard let data = line.data(using: .utf8) else {
            throw HostError.badEndpoint(line)
        }
        return try JSONDecoder().decode(EndpointPayload.self, from: data)
    }

    private func readLaunchInfo(paths: Paths, pid: Int32, owned: Bool) throws -> LaunchInfo {
        let persisted = try readPersistedEndpoint(paths: paths)
        let token = try String(contentsOf: paths.tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LaunchInfo(endpoint: persisted.endpoint, token: token, pid: pid, owned: owned)
    }
}

enum HostError: Error, LocalizedError {
    case noAppSupport
    case orchNotFound
    case orchExitedEarly
    case endpointTimeout
    case badEndpoint(String)
    case tokenUnreadable

    var errorDescription: String? {
        switch self {
        case .noAppSupport:
            return "Could not resolve Application Support directory"
        case .orchNotFound:
            return "Orchestrator not found. Set CODE_FREE_REPO_ROOT to the repo path, or CODE_FREE_ORCH to the orch command, or install code-free-orch on PATH."
        case .orchExitedEarly:
            return "Orchestrator exited before publishing an endpoint"
        case .endpointTimeout:
            return "Timed out waiting for orchestrator endpoint"
        case .badEndpoint(let s):
            return "Invalid orchestrator endpoint: \(s)"
        case .tokenUnreadable:
            return "Could not read orchestrator token file"
        }
    }
}
