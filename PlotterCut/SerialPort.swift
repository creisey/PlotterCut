import Foundation
import Darwin

enum FlowControl: String, CaseIterable, Identifiable, Codable {
    case none = "Keine", xonxoff = "XON/XOFF", rtscts = "RTS/CTS"
    var id: String { rawValue }
}

enum SerialError: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let m): return m }
    }
}

enum SerialPort {
    static func list() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return items.filter { $0.hasPrefix("cu.") && !$0.contains("Bluetooth") }
            .sorted().map { "/dev/" + $0 }
    }

    nonisolated static func send(_ data: Data, to path: String, baud: Int, flow: FlowControl, dropLines: Bool) throws {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw SerialError.failed("Port öffnen fehlgeschlagen: \(String(cString: strerror(errno)))") }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, 0) // wieder blockierend

        var t = termios()
        guard tcgetattr(fd, &t) == 0 else { throw SerialError.failed("Port-Einstellungen nicht lesbar") }
        cfmakeraw(&t)
        cfsetspeed(&t, speed_t(baud))
        t.c_cflag |= tcflag_t(CS8 | CLOCAL | CREAD)
        t.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CCTS_OFLOW | CRTS_IFLOW | HUPCL)
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        if dropLines { t.c_cflag |= tcflag_t(HUPCL) } // DTR/RTS beim Schliessen abschalten
        switch flow {
        case .xonxoff: t.c_iflag |= tcflag_t(IXON | IXOFF)
        case .rtscts:  t.c_cflag |= tcflag_t(CCTS_OFLOW | CRTS_IFLOW)
        case .none:    break
        }
        guard tcsetattr(fd, TCSANOW, &t) == 0 else { throw SerialError.failed("Port-Einstellungen nicht setzbar") }
        tcflush(fd, TCIOFLUSH)

        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off < raw.count {
                let n = write(fd, base + off, min(256, raw.count - off))
                if n < 0 {
                    if errno == EINTR || errno == EAGAIN { usleep(1000); continue }
                    throw SerialError.failed("Senden fehlgeschlagen: \(String(cString: strerror(errno)))")
                }
                off += n
            }
        }
        tcdrain(fd)
    }
}
