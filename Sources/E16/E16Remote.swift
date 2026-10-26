// E16Remote — the OXI E16's Remote Mode over USB MIDI: the Mac takes over the rings and the screen (RESEARCH.md §5).
// Sources: OXI's Remote Mode sheet (docs.google.com/spreadsheets/d/1Yccnrluv10QL_PauMmtCt64EtYjfSeZEXKrlrw8P24w,
// gid 1057524829) and charlesvestal/schwung docs/E16_REMOTE.md (the 8-to-7 packing, the ACK, "send EXIT or it stays
// blank"). SysEx goes to USB1 (CoreMIDI "OXI E16 Port 1"), where the OXI App talks too.
import CoreMIDI
import Foundation

/// One ring: its colour (0-127 per channel) and how much of it is lit (0...1).
struct Ring: Codable, Equatable {
    var r: Int, g: Int, b: Int
    var amount: Double
    var bipolar = false
}

/// A visible configuration of the device: the screen's title, the sixteen knob labels, the sixteen rings.
struct Look: Codable, Equatable {
    var name: String
    var title: String              // 16 characters on the screen
    var labels: [String]           // 16 × 4 characters
    var rings: [Ring]              // 16
}

enum E16Message {
    static let header: [UInt8] = [0xF0, 0x00, 0x21, 0x5B, 0x02, 0x01]

    /// 8-to-7 packing: per group of up to 7 raw bytes, one byte holding their bit 7 (bit k = byte k), then the bytes
    /// with bit 7 cleared (schwung E16_REMOTE.md: FF 00 80 7F 01 FE 55 AA → 25 7F 00 00 7F 01 7E 55 01 2A).
    static func pack(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i = 0
        while i < raw.count {
            let group = raw[i..<min(i + 7, raw.count)]
            var msb: UInt8 = 0
            for (k, b) in group.enumerated() where b & 0x80 != 0 { msb |= 1 << UInt8(k) }
            out.append(msb)
            out.append(contentsOf: group.map { $0 & 0x7F })
            i += 7
        }
        return out
    }

    static func sysex(_ id: [UInt8], _ payload: [UInt8] = []) -> [UInt8] {
        header + id + (payload.isEmpty ? [] : pack(payload)) + [0xF7]
    }

    static let enter = sysex([0x06, 0x55])
    static let exit = sysex([0x06, 0x00])

    static func rings(_ rings: [Ring]) -> [UInt8] {
        var raw: [UInt8] = []
        for (i, r) in rings.prefix(16).enumerated() {
            let amount = Int((max(0, min(1, r.amount)) * 16383).rounded())
            raw += [UInt8(i), c(r.r), c(r.g), c(r.b), UInt8((amount >> 7) & 0x7F), UInt8(amount & 0x7F), r.bipolar ? 1 : 0]
        }
        return sysex([0x06, 0x04], raw)
    }

    /// LABELS: a 16-character title and sixteen 4-character labels, 80 bytes of plain ASCII, space-padded.
    static func labels(title: String, labels: [String]) -> [UInt8] {
        var raw = ascii(title, 16)
        for i in 0..<16 { raw += ascii(i < labels.count ? labels[i] : "", 4) }
        return sysex([0x06, 0x03], raw)
    }

    static func ascii(_ s: String, _ n: Int) -> [UInt8] {
        let bytes = s.uppercased().unicodeScalars.map { $0.isASCII && $0.value >= 32 && $0.value < 127 ? UInt8($0.value) : 0x3F }
        return Array((bytes + Array(repeating: 0x20, count: n)).prefix(n))
    }

    private static func c(_ v: Int) -> UInt8 { UInt8(max(0, min(127, v))) }
}

/// The E16 on CoreMIDI: its USB1 destination for SysEx, and USB1's source to hear the ACK.
final class E16Port {
    private var client = MIDIClientRef()
    private var out = MIDIPortRef()
    private var input = MIDIPortRef()
    private(set) var destination: MIDIEndpointRef = 0
    private let ackLock = NSCondition()
    private var acked = false
    /// Every incoming message from the device (turns, buttons), for whoever listens.
    var onMessage: (([UInt8]) -> Void)?

    init?(port: Int = 1) {
        MIDIClientCreateWithBlock("Oxi Controller" as CFString, &client, nil)
        MIDIOutputPortCreate(client, "out" as CFString, &out)
        guard let d = E16Port.endpoint(destinations: true, port: port) else { return nil }
        destination = d
        MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &input) { [weak self] list, _ in
            self?.receive(list)
        }
        if let s = E16Port.endpoint(destinations: false, port: port) { MIDIPortConnectSource(input, s, nil) }
    }

    static func name(_ e: MIDIEndpointRef) -> String {
        var s: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s)
        return (s?.takeRetainedValue() as String?) ?? ""
    }

    static func endpoint(destinations: Bool, port: Int) -> MIDIEndpointRef? {
        let n = destinations ? MIDIGetNumberOfDestinations() : MIDIGetNumberOfSources()
        for i in 0..<n {
            let e = destinations ? MIDIGetDestination(i) : MIDIGetSource(i)
            let nm = name(e)
            if nm.contains("OXI E16") && nm.contains("Port \(port)") { return e }
        }
        return nil
    }

    func send(_ bytes: [UInt8]) {
        // SysEx through MIDISendSysex would be asynchronous; a packet list of up to 64 KB is plenty here
        var buffer = [UInt8](repeating: 0, count: bytes.count + 1024)
        buffer.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let p = MIDIPacketListInit(list)
            _ = bytes.withUnsafeBufferPointer { MIDIPacketListAdd(list, raw.count, p, 0, bytes.count, $0.baseAddress!) }
            MIDISend(out, destination, list)
        }
    }

    /// ENTER until the device says 06 53 (schwung: "send ENTER repeatedly until the ACK arrives").
    func enterRemote(timeout: TimeInterval = 3) -> Bool {
        ackLock.lock(); acked = false; ackLock.unlock()
        let until = Date().addingTimeInterval(timeout)
        while Date() < until {
            send(E16Message.enter)
            ackLock.lock()
            if !acked { ackLock.wait(until: Date().addingTimeInterval(0.25)) }
            let ok = acked
            ackLock.unlock()
            if ok { return true }
        }
        return false
    }

    func exitRemote() { send(E16Message.exit) }

    func show(_ look: Look) {
        send(E16Message.labels(title: look.title, labels: look.labels))
        send(E16Message.rings(look.rings))
    }

    private var sysex: [UInt8] = []

    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        // MIDI 1.0 words: 0x2 = channel voice (3 bytes), 0x3 = SysEx 7 in 6-byte packets
        for packet in list.unsafeSequence() {
            let words = Array(UnsafeBufferPointer(start: withUnsafePointer(to: packet.pointee.words) { UnsafeRawPointer($0).assumingMemoryBound(to: UInt32.self) }, count: Int(packet.pointee.wordCount)))
            var i = 0
            while i < words.count {
                let w = words[i]
                switch w >> 28 {
                case 0x2:
                    onMessage?([UInt8((w >> 16) & 0xFF), UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF)])
                    i += 1
                case 0x3:
                    let status = (w >> 20) & 0xF, n = Int((w >> 16) & 0xF)
                    let w2 = i + 1 < words.count ? words[i + 1] : 0
                    let bytes = [UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF), UInt8((w2 >> 24) & 0xFF), UInt8((w2 >> 16) & 0xFF), UInt8((w2 >> 8) & 0xFF), UInt8(w2 & 0xFF)]
                    if status == 0 || status == 1 { sysex = [] }
                    sysex += bytes.prefix(n)
                    if status == 0 || status == 3 { gotSysex(sysex) }
                    i += 2
                default: i += 1
                }
            }
        }
    }

    private func gotSysex(_ body: [UInt8]) {
        // the ACK: header without F0 (CoreMIDI's UMP SysEx carries no F0/F7), then 06 53
        let h = Array(E16Message.header.dropFirst())
        if body.count >= h.count + 2, Array(body.prefix(h.count)) == h, body[h.count] == 0x06, body[h.count + 1] == 0x53 {
            ackLock.lock(); acked = true; ackLock.signal(); ackLock.unlock()
        }
        onMessage?([0xF0] + body + [0xF7])
    }
}
