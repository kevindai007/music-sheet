import Foundation

/// The LiberLive C2's Bluetooth LE protocol, reverse-engineered from the official app (see docs/liberlive-protocol.md).
///
/// Service 0x00FF: A101 notifies guitar events, A103 takes commands and A102 holds the reply.
/// Every message is one frame:
///
///     0      "$"
///     1      "M" app -> guitar, "A" guitar -> app
///     2      total length
///     3      0xC0
///     4..11  random nonce
///     12..15 UInt32 LE timestamp (guitar: ms since power-on)
///     16     CRC-8 (poly 0x31) of bytes 0..15
///     17..   body, byte k XORed with frame[4 + k % 12] and `key[k % 12]`
///     last 2 CRC-16/XMODEM of the scrambled body, little-endian
public enum LiberLive {
    public static let serviceUUID = "00FF"
    public static let notifyUUID = "A101"
    public static let replyUUID = "A102"
    public static let commandUUID = "A103"

    static let key: [UInt8] = [0xB6, 0x1E, 0x2A, 0xB7, 0x69, 0x0D, 0xEA, 0x06, 0x7E, 0x6D, 0xEA, 0xCC]

    public struct Frame: Equatable, Sendable {
        public enum Direction: UInt8, Sendable {
            case toGuitar = 0x4D // "M"
            case fromGuitar = 0x41 // "A"
        }

        public var direction: Direction
        public var nonce: [UInt8]
        public var timestamp: UInt32
        public var body: [UInt8]

        public init(direction: Direction, nonce: [UInt8], timestamp: UInt32, body: [UInt8]) {
            self.direction = direction
            self.nonce = nonce
            self.timestamp = timestamp
            self.body = body
        }

        /// Parses a frame, checking both CRCs. Returns nil for anything else.
        public init?(_ data: Data) {
            let f = [UInt8](data)
            guard f.count >= 19, f[0] == 0x24, Int(f[2]) == f.count, f[3] == 0xC0,
                  let direction = Direction(rawValue: f[1]),
                  LiberLive.crc8(f[0..<16]) == f[16] else { return nil }
            let scrambled = f[17..<(f.count - 2)]
            guard LiberLive.crc16(scrambled) == UInt16(f[f.count - 2]) | UInt16(f[f.count - 1]) << 8 else { return nil }
            self.direction = direction
            nonce = Array(f[4..<12])
            timestamp = f[12..<16].reversed().reduce(0) { $0 << 8 | UInt32($1) }
            body = LiberLive.scramble(Array(scrambled), mask: Array(f[4..<16]))
        }

        public var data: Data {
            precondition(nonce.count == 8 && body.count <= 255 - 19)
            var header: [UInt8] = [0x24, direction.rawValue, UInt8(19 + body.count), 0xC0] + nonce
            header += withUnsafeBytes(of: timestamp.littleEndian, Array.init)
            let scrambled = LiberLive.scramble(body, mask: Array(header[4..<16]))
            let crc = LiberLive.crc16(scrambled)
            return Data(header + [LiberLive.crc8(header)] + scrambled + [UInt8(crc & 0xFF), UInt8(crc >> 8)])
        }

        /// The command or event name, for named messages ("get_vers_all", "noti_chord" …).
        public var name: String? {
            guard let n = body.first.map(Int.init), n > 1, body.count > n else { return nil }
            return String(bytes: body[1...n], encoding: .ascii)
        }

        /// Bytes after the name of a named message.
        public var arguments: ArraySlice<UInt8> {
            guard name != nil, let n = body.first.map(Int.init) else { return [] }
            return body[(n + 1)...]
        }
    }

    /// A chord button pressed on the guitar ("noti_chord").
    public struct ChordPress: Equatable, Sendable {
        public enum Quality: Equatable, Sendable {
            case major, minor, diminished
            case other(UInt8)
        }

        public var root: PitchClass
        public var quality: Quality
        /// Raw event bytes, kept for fields we don't understand yet.
        public var raw: [UInt8]

        public init?(_ frame: Frame) {
            let a = Array(frame.arguments)
            guard frame.direction == .fromGuitar, frame.name == "noti_chord", a.count >= 4, a[1] == 1 else { return nil }
            root = PitchClass(Int(a[0]))
            switch a[3] {
            case 0: quality = .major
            case 1: quality = .minor
            case 3: quality = .diminished
            default: quality = .other(a[3])
            }
            raw = a
        }

        public var chord: Chord {
            switch quality {
            case .major, .other: Chord(root: root)
            case .minor: Chord(root: root, suffix: "m")
            case .diminished: Chord(root: root, suffix: "dim")
            }
        }
    }

    static func scramble(_ body: [UInt8], mask: [UInt8]) -> [UInt8] {
        body.enumerated().map { k, b in b ^ mask[k % 12] ^ key[k % 12] }
    }

    static func crc8(_ bytes: some Sequence<UInt8>) -> UInt8 {
        var c: UInt8 = 0
        for b in bytes {
            c ^= b
            for _ in 0..<8 { c = c & 0x80 != 0 ? (c << 1) ^ 0x31 : c << 1 }
        }
        return c
    }

    static func crc16(_ bytes: some Sequence<UInt8>) -> UInt16 {
        var c: UInt16 = 0
        for b in bytes {
            c ^= UInt16(b) << 8
            for _ in 0..<8 { c = c & 0x8000 != 0 ? (c << 1) ^ 0x1021 : c << 1 }
        }
        return c
    }
}
