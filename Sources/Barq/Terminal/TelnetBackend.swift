import Foundation
import Network

/// Telnet backend over TCP with minimal option negotiation (refuses every
/// option except SGA, strips IAC sequences from the data stream).
final class TelnetBackend: StreamBackend {
    var onData: ((ArraySlice<UInt8>) -> Void)?
    var onClosed: ((String?) -> Void)?

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "io.barq.telnet", qos: .userInteractive)

    // Telnet protocol bytes
    private static let IAC: UInt8 = 255
    private static let DONT: UInt8 = 254
    private static let DO: UInt8 = 253
    private static let WONT: UInt8 = 252
    private static let WILL: UInt8 = 251
    private static let SB: UInt8 = 250
    private static let SE: UInt8 = 240
    private static let OPT_SGA: UInt8 = 3
    private static let OPT_ECHO: UInt8 = 1

    private enum ParseState {
        case data, iac, negotiate(UInt8), subnegotiation, subnegotiationIAC
    }
    private var state: ParseState = .data

    init(host: String, port: Int) {
        self.host = host
        self.port = UInt16(clamping: port)
    }

    func open() throws {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 23,
            using: .tcp
        )
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.onClosed?("Telnet connection failed: \(error.localizedDescription)")
            case .cancelled:
                self?.onClosed?(nil)
            default:
                break
            }
        }
        receiveLoop(connection)
        connection.start(queue: queue)
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let payload = self.parseTelnet([UInt8](data))
                if !payload.isEmpty {
                    self.onData?(payload[...])
                }
            }
            if isComplete {
                self.onClosed?("Connection closed by remote host")
                return
            }
            if error == nil {
                self.receiveLoop(connection)
            }
        }
    }

    /// Handle IAC negotiation; return plain data bytes.
    /// Internal (not private) so the protocol state machine is unit-testable.
    func parseTelnet(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var responses: [UInt8] = []

        for byte in bytes {
            switch state {
            case .data:
                if byte == Self.IAC { state = .iac } else { out.append(byte) }
            case .iac:
                switch byte {
                case Self.IAC:
                    out.append(byte) // escaped 0xFF
                    state = .data
                case Self.DO, Self.DONT, Self.WILL, Self.WONT:
                    state = .negotiate(byte)
                case Self.SB:
                    state = .subnegotiation
                default:
                    state = .data
                }
            case .negotiate(let verb):
                switch verb {
                case Self.DO:
                    // Accept SGA, refuse everything else.
                    responses += [Self.IAC, byte == Self.OPT_SGA ? Self.WILL : Self.WONT, byte]
                case Self.WILL:
                    responses += [Self.IAC, (byte == Self.OPT_SGA || byte == Self.OPT_ECHO) ? Self.DO : Self.DONT, byte]
                default:
                    break // DONT/WONT need no reply
                }
                state = .data
            case .subnegotiation:
                if byte == Self.IAC { state = .subnegotiationIAC }
            case .subnegotiationIAC:
                state = byte == Self.SE ? .data : .subnegotiation
            }
        }

        if !responses.isEmpty {
            lastNegotiationResponse = responses
            connection?.send(content: Data(responses), completion: .contentProcessed { _ in })
        }
        return out
    }

    /// Last IAC negotiation reply produced — captured for unit tests.
    private(set) var lastNegotiationResponse: [UInt8] = []

    func write(_ data: Data) {
        // Escape 0xFF bytes per telnet spec.
        var escaped = Data()
        for byte in data {
            escaped.append(byte)
            if byte == Self.IAC { escaped.append(Self.IAC) }
        }
        connection?.send(content: escaped, completion: .contentProcessed { _ in })
    }

    func close() {
        connection?.cancel()
        connection = nil
    }
}
