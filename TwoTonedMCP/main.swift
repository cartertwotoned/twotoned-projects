// twotoned-mcp — the Claude Code connection for TwoToned Projects.
//
// Claude Code starts this small program (an MCP server over stdio) in the folder
// a session is working in. It answers the MCP handshake itself and forwards tool
// requests, together with that folder, to the running TwoToned Projects app over a
// private local socket. The app does all the work and only exposes the project
// whose linked folder contains the session's folder.

import Foundation
import Darwin

let serverName = "twotoned-projects"
let serverVersion = "0.5.1"
let appBundleID = "com.twotonedstudios.projects"

let socketPath = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/TwoToned Projects/mcp.sock").path

let workingDirectory = FileManager.default.currentDirectoryPath

let instructions = """
This folder may be tracked in TwoToned Projects, the user's project manager app. Its tools let you read \
and update the project's lists (tasks, bugs, ideas and any custom lists) while you work.

- When starting work, call get_project to see the project and its Up Next list. The first item in Up Next \
is the user's current task.
- When you finish something that's tracked, mark it done with complete_item.
- When you find a bug or a follow-up you aren't fixing right now, add it with add_item rather than only \
mentioning it in chat.
- Only reorder, rename, delete, or restructure lists when the user asks or it's clearly part of the task.
- You can only see the project linked to this session's folder. If no project is linked, the tools say so; \
tell the user they can link the folder in TwoToned Projects › Project settings › Folders.
"""

// MARK: - stdout

func send(_ object: [String: Any]) {
    guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

func respond(id: Any, result: [String: Any]) {
    send(["jsonrpc": "2.0", "id": id, "result": result])
}

func respond(id: Any, errorCode: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id, "error": ["code": errorCode, "message": message]])
}

// MARK: - Connection to the app

final class AppConnection {
    private var fd: Int32 = -1

    func connect() -> Bool {
        if fd >= 0 { return true }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = Array(socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(s); return false }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            path.withUnsafeBytes { dest.copyMemory(from: $0) }
        }
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { close(s); return false }
        var noSigPipe: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        fd = s
        return true
    }

    func reset() {
        if fd >= 0 { close(fd) }
        fd = -1
    }

    /// Sends one request line and reads one response line.
    func request(_ object: [String: Any]) -> [String: Any]? {
        guard connect(), var data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        data.append(0x0A)
        let written = data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        guard written else { reset(); return nil }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { reset(); return nil }
            response.append(contentsOf: buffer[0..<n])
            if response.last == 0x0A { break }
        }
        return try? JSONSerialization.jsonObject(with: response) as? [String: Any]
    }
}

let connection = AppConnection()

/// Makes sure the app is running, starting it in the background if needed.
@MainActor func ensureAppRunning() -> Bool {
    if connection.connect() { return true }

    // This helper lives at TwoToned Projects.app/Contents/MacOS/twotoned-mcp — open that exact app.
    let executable = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).resolvingSymlinksInPath()
    let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = appURL.pathExtension == "app" ? ["-g", "-j", appURL.path] : ["-g", "-j", "-b", appBundleID]
    try? open.run()
    open.waitUntilExit()

    for _ in 0..<60 {
        usleep(250_000)
        if connection.connect() { return true }
    }
    return false
}

/// Forwards a tools/* request to the app, retrying once if the app restarted.
@MainActor func forward(_ message: [String: Any]) -> [String: Any]? {
    let envelope: [String: Any] = ["cwd": workingDirectory, "message": message]
    for _ in 0..<2 {
        guard ensureAppRunning() else { return nil }
        if let reply = connection.request(envelope) { return reply }
        connection.reset()
    }
    return nil
}

// MARK: - Main loop (newline-delimited JSON-RPC on stdin/stdout)

signal(SIGPIPE, SIG_IGN)

while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty,
          let data = line.data(using: .utf8),
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = message["method"] as? String
    else { continue }

    let id = message["id"]

    switch method {
    case "initialize":
        guard let id else { continue }
        let params = message["params"] as? [String: Any]
        respond(id: id, result: [
            "protocolVersion": params?["protocolVersion"] as? String ?? "2025-06-18",
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": serverName, "title": "TwoToned Projects", "version": serverVersion],
            "instructions": instructions,
        ])

    case "ping":
        if let id { respond(id: id, result: [:]) }

    case "tools/list", "tools/call":
        guard let id else { continue }
        if let reply = forward(message) {
            if let result = reply["result"] as? [String: Any] {
                respond(id: id, result: result)
            } else {
                let error = reply["error"] as? [String: Any]
                respond(id: id, errorCode: error?["code"] as? Int ?? -32603,
                        message: error?["message"] as? String ?? "TwoToned Projects returned an unexpected reply.")
            }
        } else {
            respond(id: id, errorCode: -32603,
                    message: "TwoToned Projects isn't running and couldn't be started. Ask the user to open it.")
        }

    default:
        // Notifications (no id) need no reply; unknown requests get "method not found".
        if let id { respond(id: id, errorCode: -32601, message: "Method not found: \(method)") }
    }
}
