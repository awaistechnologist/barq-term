import Foundation
import Darwin

/// Local IPC endpoint for barq-mcp (and any future CLI): a Unix domain socket
/// speaking newline-delimited JSON `{id, method, params}` → `{id, result|error}`.
/// Only processes owned by the same user may connect.
final class BridgeServer {
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "io.barq.bridge", qos: .userInitiated)
    private let handler: BridgeHandler
    private let socketPath: String

    init(handler: BridgeHandler, socketPath: String = AppPaths.bridgeSocket.path) {
        self.handler = handler
        self.socketPath = socketPath
    }

    func start() {
        unlink(socketPath)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let ok = withUnsafeMutablePointer(to: &addr.sun_path) { tuplePtr -> Bool in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                socketPath.withCString { src in
                    guard strlen(src) < capacity else { return false }
                    strcpy(dest, src)
                    return true
                }
            }
        }
        guard ok else { close(listenFD); listenFD = -1; return }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard bound == 0, listen(listenFD, 8) == 0 else {
            close(listenFD)
            listenFD = -1
            return
        }
        chmod(socketPath, 0o600)

        let source = DispatchSource.makeReadSource(fileDescriptor: listenFD, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        acceptSource = source
        source.resume()
        NSLog("Barq bridge listening at \(socketPath)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(socketPath)
    }

    private func acceptConnection() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }

        // Same-user check.
        var uid = uid_t()
        var gid = gid_t()
        if getpeereid(fd, &uid, &gid) != 0 || uid != getuid() {
            close(fd)
            return
        }
        _ = BridgeConnection(fd: fd, queue: queue, handler: handler)
    }
}

/// One client connection; kept alive by its dispatch source reference.
private final class BridgeConnection {
    private let fd: Int32
    private let source: DispatchSourceRead
    private var inbox = Data()
    private let handler: BridgeHandler
    private let writeLock = NSLock()
    private var selfRef: BridgeConnection?

    init(fd: Int32, queue: DispatchQueue, handler: BridgeHandler) {
        self.fd = fd
        self.handler = handler
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        selfRef = self
        source.setEventHandler { [weak self] in self?.readAvailable() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            close(self.fd)
            self.selfRef = nil
        }
        source.resume()
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &buf, buf.count)
        if n <= 0 {
            source.cancel()
            return
        }
        inbox.append(contentsOf: buf[0..<n])
        while let newline = inbox.firstIndex(of: 0x0A) {
            let line = inbox.prefix(upTo: newline)
            inbox.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            process(line: Data(line))
        }
    }

    private func process(line: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let id = object["id"]
        else { return }
        let method = object["method"] as? String ?? ""
        let params = object["params"] as? [String: Any] ?? [:]

        Task {
            var response: [String: Any] = ["id": id]
            do {
                response["result"] = try await handler.handle(method: method, params: params)
            } catch {
                response["error"] = error.localizedDescription
            }
            self.write(response)
        }
    }

    private func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        writeLock.lock()
        defer { writeLock.unlock() }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { break }
                offset += n
            }
        }
    }
}
