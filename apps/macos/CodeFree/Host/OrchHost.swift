import Foundation

/// Shell-owned sidecar lifecycle. Orch never chooses Mac paths.
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
    }

    private var process: Process?
    private var stdoutPipe: Pipe?
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning == true
    }

    /// Launch orchestrator and return endpoint + token. Token is never logged.
    func start(paths: Paths) throws -> LaunchInfo {
        lock.lock()
        defer { lock.unlock() }

        if let existing = process, existing.isRunning {
            // Reattach path: reuse token file + last endpoint if present
            if let info = try? readLaunchInfo(paths: paths, pid: existing.processIdentifier) {
                return info
            }
        }

        try stopLocked()

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
        // New process group so SIGTERM reaches the whole tree (node + children)
        proc.qualityOfService = .userInitiated

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe() // discard stderr to pipe to avoid blocking; logs go to log-dir
        stdoutPipe = pipe

        try proc.run()
        process = proc

        let endpointLine = try readEndpointLine(from: pipe, process: proc)
        let payload = try parseEndpointPayload(endpointLine)

        // Persist for reattach
        try endpointLine.data(using: .utf8)?.write(to: paths.endpointFile, options: .atomic)

        let token = try String(contentsOf: paths.tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HostError.tokenUnreadable
        }
        guard let url = URL(string: payload.endpoint) else {
            throw HostError.badEndpoint(payload.endpoint)
        }

        return LaunchInfo(endpoint: url, token: token, pid: proc.processIdentifier)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        try? stopLocked()
    }

    private func stopLocked() throws {
        guard let proc = process else { return }
        if proc.isRunning {
            // Prefer graceful SIGTERM
            proc.terminate()
            let deadline = Date().addingTimeInterval(3)
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if proc.isRunning {
                proc.interrupt()
            }
        }
        process = nil
        stdoutPipe = nil
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
            // CODE_FREE_ORCH may be a shell command string or absolute path to node script
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
                // Prefer package start via pnpm for workspace deps
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
        // When run from Xcode, SRCROOT is useful if injected; also check common path next to DerivedData is hopeless —
        // rely on CODE_FREE_REPO_ROOT or cwd.
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

    private func readLaunchInfo(paths: Paths, pid: Int32) throws -> LaunchInfo {
        let line = try String(contentsOf: paths.endpointFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = try parseEndpointPayload(line)
        let token = try String(contentsOf: paths.tokenFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: payload.endpoint) else {
            throw HostError.badEndpoint(payload.endpoint)
        }
        return LaunchInfo(endpoint: url, token: token, pid: pid)
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
