import Foundation
import Darwin

public struct UsageClient: Sendable {
    public init() {}
    public func fetch(_ service: UsageService, executable: String = "") async throws -> ServiceUsage {
        // Pipes are handled on a worker thread, never the main actor or widget process.
        try await Task.detached(priority: .utility) {
            let path = try Self.resolve(service, override: executable)
            let arguments: [String]
            switch service {
            case .codex: arguments = ["app-server"]
            case .claude: arguments = ["-p", "/usage", "--output-format", "json", "--no-session-persistence"]
            case .antigravity: arguments = ["quota", "--json"]
            }
            let session = try CommandSession(path: path, arguments: arguments)
            defer { session.close() }
            if service == .codex {
                try session.send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "ai_usage", "version": "1.0.0"]]])
                _ = try session.response(id: 1)
                try session.send(["method": "initialized"])
                try session.send(["id": 2, "method": "account/rateLimits/read"])
                return try UsageParsers.codex(session.response(id: 2))
            } else {
                let hint = service == .claude ? "claude -p /usage" : "/Applications/agy-usage/agy-usage quota --json"
                let output = try session.allOutput(failureMessage: "\(service.name) CLI 執行失敗。請在終端機執行 \(hint) 檢查登入狀態。")
                return try service == .claude ? UsageParsers.claude(output) : UsageParsers.antigravity(output)
            }
        }.value
    }

    static func resolve(_ service: UsageService, override: String) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let name = service == .antigravity ? "agy-usage" : service.rawValue
        let defaults = (service == .antigravity ? ["/Applications/agy-usage/agy-usage"] : []) +
            ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "\(home)/.local/bin/\(name)", "\(home)/.cargo/bin/\(name)"]
        let candidates = override.isEmpty ? defaults : [override]
        guard let path = candidates.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageError.message("找不到 \(service.name) CLI。請在設定填入可執行檔的絕對路徑。")
        }
        return path
    }
}

// One owner, on a dedicated worker. poll bounds both read latency and process lifetime.
final class CommandSession {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private let deadline: ContinuousClock.Instant
    private var ended = false
    private var received = 0

    init(path: String, arguments: [String], timeout: Duration = .seconds(30)) throws {
        deadline = .now + timeout
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        // Do not persist stderr: CLIs may print account or configuration details.
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        environment["NO_COLOR"] = "1"
        process.environment = environment
        try process.run()
        try output.fileHandleForWriting.close()
        try input.fileHandleForReading.close()
    }

    func close() {
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
        if process.isRunning {
            process.terminate()
            // A stalled server must not leak a background process.
            let until = ContinuousClock.now + .milliseconds(200)
            while process.isRunning && ContinuousClock.now < until { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
    }

    func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func response(id: Int) throws -> Data {
        while true {
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == id else { continue }
                if object["error"] != nil {
                    throw UsageError.message("Codex app-server 拒絕用量請求。請確認 codex login 狀態。")
                }
                guard let result = object["result"] else { throw UsageError.message("Codex RPC 回應缺少 result。") }
                return try JSONSerialization.data(withJSONObject: result)
            }
            guard !ended else { throw UsageError.message("Codex app-server 在回應前結束。") }
            try readChunk()
        }
    }

    func allOutput(failureMessage: String = "CLI 執行失敗，請在終端機確認登入狀態。") throws -> Data {
        try input.fileHandleForWriting.close()
        while !ended { try readChunk() }
        while process.isRunning { try checkDeadline(); usleep(10_000) }
        guard process.terminationStatus == 0 else { throw UsageError.message(failureMessage) }
        return buffer
    }

    private func checkDeadline() throws {
        guard ContinuousClock.now < deadline else { throw UsageError.message("讀取用量逾時（30 秒），請稍後再試。") }
    }
    private func readChunk() throws {
        try checkDeadline()
        var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
        let status = poll(&descriptor, 1, 100)
        if status < 0 {
            if errno == EINTR { return }
            throw UsageError.message("無法讀取 CLI 輸出。")
        }
        guard status > 0 else { return }
        var bytes = [UInt8](repeating: 0, count: 8192)
        let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
        if count == 0 { ended = true; return }
        guard count > 0 else { throw UsageError.message("CLI 連線中斷。") }
        received += count
        guard received <= 2_000_000 else { throw UsageError.message("CLI 輸出超過大小上限。") }
        buffer.append(contentsOf: bytes.prefix(count))
    }
}
