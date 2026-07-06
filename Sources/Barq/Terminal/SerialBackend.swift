import Foundation
import Darwin

enum SerialError: LocalizedError {
    case cannotOpen(String)
    var errorDescription: String? {
        switch self {
        case .cannotOpen(let path): return "Cannot open serial device \(path)"
        }
    }
}

/// Raw serial port backend using POSIX termios.
final class SerialBackend: StreamBackend {
    var onData: ((ArraySlice<UInt8>) -> Void)?
    var onClosed: ((String?) -> Void)?

    private let path: String
    private let baudRate: Int
    private let dataBits: Int
    private let stopBits: Int
    private let parity: String

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "io.barq.serial", qos: .userInteractive)

    init(path: String, baudRate: Int, dataBits: Int = 8, stopBits: Int = 1, parity: String = "none") {
        self.path = path
        self.baudRate = baudRate
        self.dataBits = dataBits
        self.stopBits = stopBits
        self.parity = parity
    }

    func open() throws {
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.cannotOpen(path) }

        var tty = termios()
        tcgetattr(fd, &tty)
        cfmakeraw(&tty)
        cfsetspeed(&tty, speed_t(baudRate))

        // Data bits
        tty.c_cflag &= ~tcflag_t(CSIZE)
        switch dataBits {
        case 5: tty.c_cflag |= tcflag_t(CS5)
        case 6: tty.c_cflag |= tcflag_t(CS6)
        case 7: tty.c_cflag |= tcflag_t(CS7)
        default: tty.c_cflag |= tcflag_t(CS8)
        }
        // Stop bits
        if stopBits == 2 { tty.c_cflag |= tcflag_t(CSTOPB) } else { tty.c_cflag &= ~tcflag_t(CSTOPB) }
        // Parity
        switch parity {
        case "even":
            tty.c_cflag |= tcflag_t(PARENB)
            tty.c_cflag &= ~tcflag_t(PARODD)
        case "odd":
            tty.c_cflag |= tcflag_t(PARENB) | tcflag_t(PARODD)
        default:
            tty.c_cflag &= ~tcflag_t(PARENB)
        }
        tty.c_cflag |= tcflag_t(CLOCAL) | tcflag_t(CREAD)
        tcsetattr(fd, TCSANOW, &tty)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, self.fd >= 0 else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(self.fd, &buf, buf.count)
            if n > 0 {
                self.onData?(buf[0..<n])
            } else if n == 0 {
                self.teardown(message: "Serial device disconnected")
            }
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { Darwin.close(fd) }
            self?.fd = -1
        }
        readSource = source
        source.resume()
    }

    func write(_ data: Data) {
        guard fd >= 0 else { return }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { break }
                offset += n
            }
        }
    }

    func close() {
        teardown(message: nil)
    }

    private func teardown(message: String?) {
        readSource?.cancel()
        readSource = nil
        if let message { onClosed?(message) }
    }

    /// Enumerate serial devices, mirroring `/dev/{tty,cu}.*`.
    static func availablePorts() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else { return [] }
        return entries
            .filter { $0.hasPrefix("cu.") || $0.hasPrefix("tty.") }
            .map { "/dev/\($0)" }
            .sorted()
    }
}
