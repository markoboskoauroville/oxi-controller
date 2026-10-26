// Engine.swift — DJ MANTRA ABLETON REMOTE: the E16's brain (Marko, 26.10.2026: "make a setup for each of its knobs:
// what push does, etc. ... All of these need to be in our app").
//
// The E16 is held in Remote Mode: it sends every turn (CC 1-16 on channel 1, relative: 1…8 clockwise, 127…120
// counter-clockwise, faster turns larger) and every push (note 0-15, Shift note 16), and draws only what the Mac
// tells it. Here each knob has a setup — its name, its colour, what a turn sends (CC, channel, range, speed), what a
// push does (toggle or momentary, a note or a CC) — the value is kept, the ring and the screen are drawn from it, and
// the result goes to Ableton Live (or anything) through this app's own virtual MIDI port "DJ Mantra Remote".
import CoreMIDI
import Foundation
import SwiftUI

struct KnobSetup: Codable, Equatable {
    enum Push: String, Codable, CaseIterable { case off = "OFF", toggle = "TOGGLE", momentary = "MOMENTARY" }
    enum Kind: String, Codable, CaseIterable { case note = "NOTE", cc = "CC" }
    var name: String
    var r: Double, g: Double, b: Double         // 0...1
    var cc: Int                                 // what a turn sends
    var channel: Int                            // 1-16
    var low: Int = 0, high: Int = 127
    var speed: Double = 1                       // a step of the knob × speed
    var push: Push = .toggle
    var pushKind: Kind = .note
    var pushNumber: Int
    var pushChannel: Int = 1

    var colour: Color { Color(red: r, green: g, blue: b) }

    static func defaults(_ i: Int) -> KnobSetup {
        let hue = Double(i) / 16
        let c = NSColor(hue: hue, saturation: 0.9, brightness: 1, alpha: 1).usingColorSpace(.sRGB) ?? .white
        return KnobSetup(name: "K\(i + 1)", r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent),
                         cc: 20 + i, channel: 1, pushNumber: 36 + i)
    }
}

struct Setup: Codable { var name: String; var knobs: [KnobSetup] }

final class Engine: ObservableObject {
    @Published var knobs: [KnobSetup] = (0..<16).map(KnobSetup.defaults)
    @Published var values: [Double] = Array(repeating: 0, count: 16)
    @Published var pushed: [Bool] = Array(repeating: false, count: 16)
    @Published var selected = 0
    @Published var setupName = "MY SETUP"
    @Published var status = "Not connected"
    @Published var connected = false
    @Published var presenting = false
    @Published var lastTouched: Int? = nil
    @Published var shift = false

    private var e16: E16Port?
    private var client = MIDIClientRef()
    private var source = MIDIEndpointRef()
    private var ringsDue = false
    private var presentStop = false

    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DJ Mantra Ableton Remote/setups", isDirectory: true)

    init() {
        try? FileManager.default.createDirectory(at: Engine.dir, withIntermediateDirectories: true)
        MIDIClientCreateWithBlock("DJ Mantra Ableton Remote" as CFString, &client, nil)
        // the port Ableton sees: Preferences → Link/Tempo/MIDI → Input "DJ Mantra Remote" (Track and Remote on)
        MIDISourceCreate(client, "DJ Mantra Remote" as CFString, &source)
        if let last = UserDefaults.standard.string(forKey: "lastSetup"), let s = load(last) { apply(s) }
        // the rings at most 30 times a second, whatever the knobs do
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.flushRings() }
    }

    // MARK: the device

    func connect() {
        guard !connected else { return }
        guard let port = E16Port() else { status = "The OXI E16 is not on USB (CoreMIDI: no \"OXI E16 Port 1\")"; return }
        e16 = port
        port.onMessage = { [weak self] bytes in DispatchQueue.main.async { self?.heard(bytes) } }
        status = "Connecting…"
        DispatchQueue.global().async {
            let acked = port.enterSigned()                          // the signature on the screen first
            DispatchQueue.main.async {
                self.connected = true
                self.status = acked ? "E16 held (Remote Mode)" : "E16 held (Remote Mode; no ACK heard, but it answers)"
                self.drawAll()
            }
        }
    }

    /// The E16 back to its own scene: without EXIT it stays blank (schwung, RESEARCH.md §5).
    func giveBack() {
        presentStop = true
        e16?.exitRemote()
        e16 = nil
        connected = false
        status = "Given back to its scene"
    }

    private func heard(_ b: [UInt8]) {
        guard b.count >= 3, !presenting else { return }
        let kind = b[0] & 0xF0
        if kind == 0xB0, (1...16).contains(Int(b[1])) {                   // a turn
            let i = Int(b[1]) - 1
            let raw = Int(b[2])
            let step = raw < 64 ? raw : raw - 128
            turn(i, by: Double(step))
        } else if kind == 0x90 || kind == 0x80 {                          // a push or a release
            let note = Int(b[1]); let down = kind == 0x90 && b[2] > 0
            if note == 16 { shift = down; drawLabels(); return }
            if (0..<16).contains(note) { press(note, down: down) }
        }
    }

    func turn(_ i: Int, by step: Double) {
        let k = knobs[i]
        let v = max(Double(k.low), min(Double(k.high), values[i] + step * k.speed * (shift ? 0.25 : 1)))
        guard v != values[i] else { return }
        values[i] = v; lastTouched = i; selected = i
        send([0xB0 | UInt8(max(0, min(15, k.channel - 1))), UInt8(max(0, min(127, k.cc))), UInt8(v.rounded())])
        ringsDue = true; drawLabels()
    }

    func press(_ i: Int, down: Bool) {
        let k = knobs[i]
        switch k.push {
        case .off: return
        case .toggle: if down { pushed[i].toggle(); out(k, pushed[i]) } else { return }
        case .momentary: pushed[i] = down; out(k, down)
        }
        lastTouched = i; selected = i; ringsDue = true; drawLabels()
    }

    private func out(_ k: KnobSetup, _ on: Bool) {
        let ch = UInt8(max(0, min(15, k.pushChannel - 1))), n = UInt8(max(0, min(127, k.pushNumber)))
        switch k.pushKind {
        case .note: send([(on ? 0x90 : 0x80) | ch, n, on ? 127 : 0])
        case .cc: send([0xB0 | ch, n, on ? 127 : 0])
        }
    }

    private func send(_ bytes: [UInt8]) {
        var buf = [UInt8](repeating: 0, count: 256)
        buf.withUnsafeMutableBytes { raw in
            let list = raw.baseAddress!.assumingMemoryBound(to: MIDIPacketList.self)
            let p = MIDIPacketListInit(list)
            _ = bytes.withUnsafeBufferPointer { MIDIPacketListAdd(list, raw.count, p, 0, bytes.count, $0.baseAddress!) }
            MIDIReceived(source, list)
        }
    }

    // MARK: drawing on the device

    func drawAll() { ringsDue = true; flushRings(); drawLabels() }

    private func flushRings() {
        guard ringsDue, connected, !presenting, let e16 else { return }
        ringsDue = false
        let rings = (0..<16).map { i -> Ring in
            let k = knobs[i]
            let lit = k.push == .off || pushed[i] ? 1.0 : 0.35                // a toggled-off knob glows dimmer
            let span = Double(max(1, k.high - k.low))
            return Ring(r: Int(k.r * 127 * lit), g: Int(k.g * 127 * lit), b: Int(k.b * 127 * lit),
                        amount: (values[i] - Double(k.low)) / span)
        }
        e16.send(E16Message.rings(rings))
    }

    /// The screen: the title tells the last knob touched and its value (or the setup's name), the sixteen labels
    /// their names; with Shift held, their values.
    func drawLabels() {
        guard connected, !presenting, let e16 else { return }
        let title: String
        if let i = lastTouched { title = "\(knobs[i].name) \(Int(values[i].rounded()))" + (knobs[i].push != .off && pushed[i] ? " ON" : "") }
        else { title = setupName }
        let labels = (0..<16).map { shift ? String(Int(values[$0].rounded())) : knobs[$0].name }
        e16.send(E16Message.labels(title: title, labels: labels))
    }

    // MARK: PRESENT THE OXI

    func togglePresent() {
        if presenting { presentStop = true; return }
        guard connected, let e16 else { status = "Connect the E16 first"; return }
        presenting = true; presentStop = false; status = "PRESENT THE OXI"
        DispatchQueue.global().async {
            e16.present(seconds: 0, stop: { self.presentStop })
            DispatchQueue.main.async {
                self.presenting = false
                self.status = self.connected ? "E16 held (Remote Mode)" : self.status
                self.drawAll()
            }
        }
    }

    // MARK: setups

    func file(_ name: String) -> URL { Engine.dir.appendingPathComponent(name.uppercased().replacingOccurrences(of: "/", with: "-") + ".json") }

    func saved() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: Engine.dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(Setup(name: setupName, knobs: knobs)).write(to: file(setupName))
        UserDefaults.standard.set(setupName.uppercased(), forKey: "lastSetup")
        status = "Saved \(setupName.uppercased())"
        objectWillChange.send()
    }

    func load(_ name: String) -> Setup? {
        guard let d = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(Setup.self, from: d)
    }

    func recall(_ name: String) {
        guard let s = load(name) else { return }
        apply(s); UserDefaults.standard.set(name, forKey: "lastSetup")
        status = "Recalled \(name)"; lastTouched = nil; drawAll()
    }

    private func apply(_ s: Setup) {
        setupName = s.name
        knobs = s.knobs.count == 16 ? s.knobs : (0..<16).map { $0 < s.knobs.count ? s.knobs[$0] : KnobSetup.defaults($0) }
    }

    func edited() { ringsDue = true; drawLabels() }
}
