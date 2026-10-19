import Foundation

struct TmuxSessionInfo: Equatable {
    let id: String
    let name: String
    let title: String
    let directory: String
    let attachedClients: Int
    let createdAt: Int64
}

protocol SessionBackend {
    func list() throws -> [TmuxSessionInfo]
    func create() throws -> TmuxSessionInfo
    func end(id: String) throws
    func rename(id: String, name: String) throws
    func attachmentCommand(id: String) -> String
}

/// Stateless commands to tmux’s default server. Call on a background queue.
final class TmuxBackend: SessionBackend {
    let executable: URL
    let socketName: String?
    let configuration: URL?
    private let environment: [String: String]
    // Use a literal ASCII control-character range. POSIX's [[:cntrl:]]
    // contains colons that tmux interprets as format-modifier delimiters.
    private static let controlCharacters = "[\u{0001}-\u{001F}\u{007F}]"
    private let format = ["#{session_id}", "#{s/\(controlCharacters)/ /:session_name}",
                          "#{s/\(controlCharacters)/ /:pane_title}", "#{s/\(controlCharacters)/ /:pane_current_path}",
                          "#{session_attached}", "#{session_created}"].joined(separator: "\t")

    init(executable: URL? = nil, socketName: String? = nil, configuration: URL? = nil) throws {
        let candidates = [ProcessInfo.processInfo.environment["AGENT_MANAGER_TMUX"],
                          "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let path = executable?.path ?? candidates.compactMap({ $0 }).first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }), FileManager.default.isExecutableFile(atPath: path) else {
            throw BackendError("tmux was not found. Install it with ‘brew install tmux’, then reopen the app. You can also set AGENT_MANAGER_TMUX to its absolute path in the Xcode scheme.")
        }
        self.executable = URL(fileURLWithPath: path)
        self.socketName = socketName
        self.configuration = configuration
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "TMUX")
        environment.removeValue(forKey: "TMUX_PANE")
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        self.environment = environment
    }

    func list() throws -> [TmuxSessionInfo] {
        let result = try run(["list-sessions", "-F", format])
        if result.status != 0 {
            // tmux has no server until the first session is created. Never hide
            // permission, version, or protocol errors behind an empty list.
            if result.output.contains("No such file or directory") ||
                result.output.hasPrefix("no server running on ") ||
                result.output.contains("Connection refused") { return [] }
            throw BackendError(result.output)
        }
        return try Self.parse(result.output)
    }

    func create() throws -> TmuxSessionInfo {
        let name = "session-" + UUID().uuidString.lowercased().prefix(8)
        let result = try run(["new-session", "-d", "-P", "-F", format, "-s", String(name), "-c", NSHomeDirectory()])
        guard result.status == 0 else { throw BackendError(result.output) }
        guard let info = try Self.parse(result.output).first else {
            throw BackendError(result.output.isEmpty ? "tmux did not create a session." : result.output)
        }
        return info
    }

    func end(id: String) throws {
        let result = try run(["kill-session", "-t", id])
        guard result.status == 0 else { throw BackendError(result.output) }
    }

    static func validatedName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw BackendError("Enter a session name.") }
        guard name.rangeOfCharacter(from: .controlCharacters) == nil,
              !name.contains(":"), !name.contains(".") else {
            throw BackendError("Use a name without periods, colons, or control characters.")
        }
        return name
    }

    func rename(id: String, name: String) throws {
        let name = try Self.validatedName(name)
        let result = try run(["rename-session", "-t", id, name])
        guard result.status == 0 else { throw BackendError(result.output) }
    }

    func reloadPersonalConfiguration() throws {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        let candidates = [home.appendingPathComponent(".tmux.conf"), xdg.appendingPathComponent("tmux/tmux.conf")]
        guard let config = configuration ?? candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw BackendError("No personal tmux configuration was found.")
        }
        let result = try run(["source-file", config.path])
        guard result.status == 0 else { throw BackendError(result.output) }
    }

    func attachmentCommand(id: String) -> String {

        // Ghostty's command is a shell command. Quote every argument, including
        // executable paths and tmux IDs ($0, $1, …). No shell in management calls.
        let arguments = ["/usr/bin/env", "-u", "TMUX", "-u", "TMUX_PANE",
                         executable.path] + serverArguments + ["attach-session", "-t", id]
        // On macOS Ghostty wraps this in `bash -c "exec -l <command>"`.
        // Supplying our own exec would make bash try to execute a file named exec.
        return arguments.map(Self.shellQuote).joined(separator: " ")
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func parse(_ output: String) throws -> [TmuxSessionInfo] {
        try output.split(separator: "\n").map { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, fields[0].range(of: #"^\$[0-9]+$"#, options: .regularExpression) != nil,
                  let clients = Int(fields[4]), let createdAt = Int64(fields[5]) else { throw BackendError("Unexpected tmux session response.") }
            return TmuxSessionInfo(id: fields[0], name: fields[1], title: fields[2], directory: fields[3], attachedClients: clients, createdAt: createdAt)
        }
    }

    // Omitting -f lets tmux load the user’s normal configuration on server startup.
    // Explicit configurations are only needed by isolated tests.
    private var serverArguments: [String] {
        (socketName.map { ["-L", $0] } ?? []) + (configuration.map { ["-f", $0.path] } ?? [])
    }

    struct CommandResult { let status: Int32; let output: String }
    func run(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = serverArguments + arguments
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Drain before waiting: avoids deadlock if tmux returns lots of sessions.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    struct BackendError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message.trimmingCharacters(in: .whitespacesAndNewlines) }
        var errorDescription: String? { message }
    }
}
