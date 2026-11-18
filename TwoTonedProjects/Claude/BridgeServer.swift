import Foundation
import Darwin

/// Local socket the bundled `twotoned-mcp` helper talks to.
///
/// It lives in the app's own data folder, is readable only by you (0600), and
/// costs nothing while idle: each connection is a thread blocked in `read`.
nonisolated final class BridgeServer: @unchecked Sendable {
    static var socketPath: String { DataStore.dataDirectory.appending(path: "mcp.sock").path }

    private let handler: @Sendable (Data) -> Data
    private var listenFD: Int32 = -1

    init(handler: @escaping @Sendable (Data) -> Data) {
        self.handler = handler
    }

    func start() {
        let path = Self.socketPath
        try? FileManager.default.createDirectory(at: DataStore.dataDirectory, withIntermediateDirectories: true)
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return }
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in bytes.withUnsafeBytes { dest.copyMemory(from: $0) } }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }
        chmod(path, 0o600)
        listenFD = fd

        let thread = Thread { [self] in acceptLoop() }
        thread.name = "TwoToned Claude bridge"
        thread.qualityOfService = .utility
        thread.start()
    }

    func stop() {
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(Self.socketPath)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { [self] in serve(client) }
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { return }
            pending.append(contentsOf: buffer[0..<n])
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending.subdata(in: pending.startIndex..<newline)
                pending.removeSubrange(pending.startIndex...newline)
                var reply = handler(line)
                reply.append(0x0A)
                let ok = reply.withUnsafeBytes { raw -> Bool in
                    var offset = 0
                    while offset < raw.count {
                        let w = write(fd, raw.baseAddress! + offset, raw.count - offset)
                        if w <= 0 { return false }
                        offset += w
                    }
                    return true
                }
                if !ok { return }
            }
        }
    }
}
