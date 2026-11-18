import Foundation

/// Registers (or removes) the bundled helper as a user-level MCP server in Claude Code.
///
/// Prefers Claude Code's own `claude mcp add/remove` command, which is the supported
/// way to change its config. Falls back to editing `~/.claude.json` directly (just
/// the one `mcpServers` entry) only if the `claude` command can't be found.
@MainActor
@Observable
final class ClaudeConnection {
    static let shared = ClaudeConnection()
    nonisolated static let serverName = "twotoned-projects"

    enum Status: Equatable {
        case notConnected
        case connected
        /// Registered, but pointing at a different copy of the app (e.g. it was moved).
        case outdated(String)
    }

    private(set) var status: Status = .notConnected
    private(set) var busy = false
    private(set) var message: String?

    nonisolated static var helperPath: String {
        Bundle.main.bundleURL.appending(path: "Contents/MacOS/twotoned-mcp").path
    }

    nonisolated static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude.json")
    }

    func refresh() {
        guard let command = Self.registeredCommand() else { status = .notConnected; return }
        status = command == Self.helperPath ? .connected : .outdated(command)
    }

    /// Called at launch: if the app moved since connecting, point Claude Code at this copy.
    func repairIfNeeded() {
        refresh()
        if case .outdated = status { Task { await connect(quietly: true) } }
    }

    func connect(quietly: Bool = false) async {
        busy = true
        let result = await Task.detached(priority: .userInitiated) { Self.register() }.value
        busy = false
        refresh()
        if !quietly || status != .connected { message = result }
    }

    func disconnect() async {
        busy = true
        let result = await Task.detached(priority: .userInitiated) { Self.unregister() }.value
        busy = false
        refresh()
        message = result
    }

    // MARK: Work (off the main thread)

    nonisolated static func registeredCommand() -> String? {
        guard let data = try? Data(contentsOf: configURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let entry = servers[serverName] as? [String: Any]
        else { return nil }
        return entry["command"] as? String
    }

    nonisolated private static func register() -> String {
        if let cli = findCLI() {
            _ = run(cli, ["mcp", "remove", "--scope", "user", serverName])
            let (status, output) = run(cli, ["mcp", "add", "--scope", "user", serverName, "--", helperPath])
            if status == 0 { return "Connected. Start or reopen a Claude Code session to use it." }
            return "Claude Code couldn't add the connection: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        do {
            try editConfig { servers in
                servers[serverName] = ["type": "stdio", "command": helperPath, "args": [String](), "env": [String: String]()]
            }
            return "Connected. Start or reopen a Claude Code session to use it."
        } catch {
            return "Couldn't update Claude Code's settings: \(error.localizedDescription)"
        }
    }

    nonisolated private static func unregister() -> String {
        if let cli = findCLI() {
            let (status, output) = run(cli, ["mcp", "remove", "--scope", "user", serverName])
            if status == 0 || registeredCommand() == nil { return "Disconnected. Running sessions keep it until they restart." }
            return "Claude Code couldn't remove the connection: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        do {
            try editConfig { servers in servers[serverName] = nil }
            return "Disconnected. Running sessions keep it until they restart."
        } catch {
            return "Couldn't update Claude Code's settings: \(error.localizedDescription)"
        }
    }

    /// Changes only the `mcpServers` entry, keeping everything else in the file as is.
    nonisolated private static func editConfig(_ change: (inout [String: Any]) -> Void) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: configURL) {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = parsed
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        change(&servers)
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: configURL, options: .atomic)
    }

    /// Finds the `claude` command: common install locations, then the login shell's PATH.
    nonisolated static func findCLI() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
            "\(home)/.local/bin/claude", "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude",
        ]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        let (status, output) = run("/bin/zsh", ["-lc", "command -v claude"])
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return status == 0 && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
