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
    /// v2: what a turn and a push do in Live besides plain MIDI (Live.swift)
    enum TurnRole: String, Codable, CaseIterable { case midi = "MIDI", tracks = "TRACKS", scrub = "SCRUB", parameter = "PARAMETER", hover = "HOVER", selected = "SELECTED" }
    enum PushRole: String, Codable, CaseIterable { case midi = "MIDI", automationView = "AUTOMATION VIEW", automationRecord = "AUTOMATION RECORD", playStop = "PLAY/STOP" }
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
    var turnRole: TurnRole = .midi
    var pushRole: PushRole = .midi

    enum CodingKeys: String, CodingKey { case name, r, g, b, cc, channel, low, high, speed, push, pushKind, pushNumber, pushChannel, turnRole, pushRole }
    init(name: String, r: Double, g: Double, b: Double, cc: Int, channel: Int, pushNumber: Int) {
        self.name = name; self.r = r; self.g = g; self.b = b; self.cc = cc; self.channel = channel; self.pushNumber = pushNumber
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name); r = try c.decode(Double.self, forKey: .r); g = try c.decode(Double.self, forKey: .g); b = try c.decode(Double.self, forKey: .b)
        cc = try c.decode(Int.self, forKey: .cc); channel = try c.decode(Int.self, forKey: .channel)
        low = try c.decodeIfPresent(Int.self, forKey: .low) ?? 0; high = try c.decodeIfPresent(Int.self, forKey: .high) ?? 127
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        push = try c.decodeIfPresent(Push.self, forKey: .push) ?? .toggle; pushKind = try c.decodeIfPresent(Kind.self, forKey: .pushKind) ?? .note
        pushNumber = try c.decode(Int.self, forKey: .pushNumber); pushChannel = try c.decodeIfPresent(Int.self, forKey: .pushChannel) ?? 1
        turnRole = try c.decodeIfPresent(TurnRole.self, forKey: .turnRole) ?? .midi; pushRole = try c.decodeIfPresent(PushRole.self, forKey: .pushRole) ?? .midi
    }

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
        // v8 (Marko, 26.10.2026: "our device is reading selected parameters ... it shows the value with an LED ... If I
        // click on other parameters, the value is read from that parameter"): a SELECTED knob's ring follows Live
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.followSelected() }
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

    // MARK: HELP on the E16's screen (Marko, 26.10.2026: "describe what parameters are doing, what knobs are doing, and
    // to scroll between pages ... If there is not enough text, you need to actually write big text. No shortcuts ...
    // I'm scrolling with the 16 encoder"): knob 16 turns the pages, its push leaves; any other knob leaves too.

    @Published var helpPage: Int? = nil

    func helpPages() -> [(String, String)] {
        var pages: [(String, String)] = [("HELP", "Turn knob sixteen to read the pages, one page for every knob. Push knob sixteen to leave the help. Touching any other knob also leaves it. This setup is called \(setupName).")]
        for i in 0..<15 {
            let k = knobs[i]
            let kind = k.pushKind == .note ? "note" : "control change"
            let turn: String
            switch k.turnRole {
            case .tracks: turn = "Turning selects the track above or below in Live's arrangement."
            case .scrub: turn = "Turning moves the playhead along the timeline, a sixteenth note for every step. Hold Shift for finer steps."
            case .selected: turn = "Turning changes the parameter you last clicked in Live, any knob, slider or button of any device or of the mixer. The screen names the device, the parameter and its value. Hold Shift for fine steps. With automation recording on, the turns are written as key frames."
            case .hover: turn = "Hover mode: rest the mouse pointer on any knob, slider or number in Live, and turning this knob turns that control, as dragging it with the mouse would. Hold Shift for fine steps. Do not rest the pointer on a clip: the same drag would move it."
            case .parameter: turn = "Turning chooses which parameter of the selected track's device is automated; the screen names the device, the parameter and its value. Turning with Shift held changes that value in Live."
            case .midi: turn = "Turning sends control change \(k.cc) on MIDI channel \(k.channel), from \(k.low) to \(k.high), into Live through the port DJ Mantra Remote. Map it to a parameter with MIDI Map."
            }
            let push: String
            switch k.pushRole {
            case .automationView: push = "Pushing shows or hides the automation lanes of the tracks in Live's arrangement."
            case .automationRecord: push = "Pushing switches automation recording on or off. While it is on, turning a mapped knob writes key frames into the automation line."
            case .playStop: push = "Pushing starts Live playing, or stops it."
            case .midi:
                switch k.push {
                case .off: push = "Pushing does nothing."
                case .toggle: push = "Pushing switches \(kind) \(k.pushNumber) on MIDI channel \(k.pushChannel) on, and the next push off again."
                case .momentary: push = "Pushing sends \(kind) \(k.pushNumber) on MIDI channel \(k.pushChannel) while the knob is held down."
                }
            }
            pages.append(("KNOB \(i + 1): \(k.name)", turn + " " + push))
        }
        return pages
    }

    /// The help as the screen shows it: every knob's text cut into pages that fit in readable letters.
    func screenPages() -> [String] {
        helpPages().flatMap { (title, text) in Signature.pages(for: title + ". " + text) }
    }

    func helpTurn(_ step: Int) {
        let pages = screenPages()
        helpPage = max(0, min(pages.count - 1, (helpPage ?? -1) + (step > 0 ? 1 : -1)))
        drawHelp()
    }

    func leaveHelp() { guard helpPage != nil else { return }; helpPage = nil; drawLabels() }

    private func drawHelp() {
        guard connected, let e16, let p = helpPage else { return }
        let pages = screenPages()
        // the preset's name on top, the knob and its explanation under it (Marko, 26.10.2026)
        e16.send(E16Message.framebuffer(Signature.page(title: setupName.uppercased(), body: pages[min(p, pages.count - 1)], number: "\(p + 1)/\(pages.count)")))
    }

    private func heard(_ b: [UInt8]) {
        guard b.count >= 3, !presenting else { return }
        let kind = b[0] & 0xF0
        // knob sixteen is the help's page knob
        if kind == 0xB0, b[1] == 16 { let raw = Int(b[2]); helpTurn(raw < 64 ? raw : raw - 128); return }
        if (kind == 0x90 || kind == 0x80), b[1] == 15 { if kind == 0x90 && b[2] > 0 { leaveHelp() }; return }
        if helpPage != nil, kind == 0xB0 || (kind == 0x90 && b[2] > 0) { helpPage = nil }
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

    @Published var liveSays = ""

    func turn(_ i: Int, by step: Double) {
        let k = knobs[i]
        switch k.turnRole {
        case .tracks:
            lastTouched = i; selected = i
            DispatchQueue.global().async { let r = Live.shared.selectTrack(by: Int(step)); DispatchQueue.main.async { self.showLive(r.map { "TRACK " + $0 } ?? "— Live does not answer") } }
            return
        case .scrub:
            lastTouched = i; selected = i
            let beats = step * 0.25 * k.speed * (shift ? 0.25 : 1)
            DispatchQueue.global().async { let t = Live.shared.scrub(beats: beats); DispatchQueue.main.async { self.live(t.map { String(format: "BEAT %.2f", $0 + 1) } ?? "— Live does not answer") } }
            return
        case .parameter:
            // v4 (Marko, 26.10.2026: "The second button exchanges the automation parameter ... If I'm changing the
            // parameter of utility, it tells me utility is changing what"): a turn chooses the parameter of the
            // selected track's device; with Shift it changes that parameter's value in Live
            lastTouched = i; selected = i
            let sh = shift
            DispatchQueue.global().async {
                let said = sh ? Live.shared.changeParameter(by: step * k.speed) : Live.shared.chooseParameter(by: Int(step))
                DispatchQueue.main.async { self.showLive(said ?? "— Live does not answer") }
            }
            return
        case .selected:
            // v7: the parameter last clicked in Live (Live.nudgeSelected); Shift = fine
            lastTouched = i; selected = i
            let st = step * k.speed * (shift ? 0.25 : 1)
            DispatchQueue.global().async { let said = Live.shared.nudgeSelected(by: st); DispatchQueue.main.async { self.showLive(said) } }
            return
        case .hover:
            // v5: the control under the mouse pointer in Live turns with this knob (Live.hover); Shift = fine (⌘-drag)
            lastTouched = i; selected = i
            if let said = Live.shared.hover(by: step * k.speed, fine: shift) { showLive(said) }
            else if liveSays != "HOVER" { liveSays = "HOVER"; status = "Live: HOVER — the knob under the mouse pointer turns" }
            return
        case .midi: break
        }
        let v = max(Double(k.low), min(Double(k.high), values[i] + step * k.speed * (shift ? 0.25 : 1)))
        guard v != values[i] else { return }
        values[i] = v; lastTouched = i; selected = i
        send([0xB0 | UInt8(max(0, min(15, k.channel - 1))), UInt8(max(0, min(127, k.cc))), UInt8(v.rounded())])
        ringsDue = true; drawLabels()
    }

    private func live(_ said: String) { showLive(said) }

    /// What Live says, big on the screen under the preset's name (and in the app's status line).
    func showLive(_ said: String) {
        liveSays = said; status = "Live: " + said
        guard connected, !presenting, let e16 else { return }
        helpPage = nil
        e16.send(E16Message.framebuffer(Signature.page(title: setupName.uppercased(), body: said, number: "LIVE")))
    }

    func press(_ i: Int, down: Bool) {
        let k = knobs[i]
        if k.pushRole != .midi {
            guard down else { return }
            lastTouched = i; selected = i
            DispatchQueue.global().async {
                let said: String
                switch k.pushRole {
                case .automationView: said = Live.shared.automationView() ? "AUTOMATION VIEW (A)" : "— Live is not open"
                case .automationRecord: said = Live.shared.automationRecord().map { $0 ? "AUTOMATION RECORD ON" : "RECORD OFF" } ?? "— Live does not answer"
                case .playStop: said = Live.shared.playStop().map { $0 ? "PLAY" : "STOP" } ?? "— Live does not answer"
                case .midi: said = ""
                }
                DispatchQueue.main.async { self.live(said) }
            }
            return
        }
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
        if let i = lastTouched, knobs[i].turnRole != .midi || knobs[i].pushRole != .midi, !liveSays.isEmpty { title = liveSays }
        else if let i = lastTouched { title = "\(knobs[i].name) \(Int(values[i].rounded()))" + (knobs[i].push != .off && pushed[i] ? " ON" : "") }
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

    /// The first profile, AUTOMATION (Marko, 26.10.2026): knob 1 tracks / automation view, knob 2 a parameter's CC
    /// / automation record, knob 3 scrub / play-stop; the others plain MIDI.
    private var following = false
    private var lastSelectedName = ""

    private func followSelected() {
        guard connected, !presenting, !following, let i = knobs.firstIndex(where: { $0.turnRole == .selected }) else { return }
        following = true
        DispatchQueue.global().async {
            let r = Live.shared.readSelected()
            DispatchQueue.main.async {
                self.following = false
                guard let r else { return }
                let k = self.knobs[i]
                let v = Double(k.low) + r.frac * Double(k.high - k.low)
                if abs(v - self.values[i]) > 0.2 { self.values[i] = v; self.ringsDue = true }
                // another parameter clicked in Live: the screen names it
                let id = r.dev + "|" + r.name
                if id != self.lastSelectedName {
                    if !self.lastSelectedName.isEmpty { self.showLive("\(r.dev.uppercased()) · \(r.name) · \(r.text)") }
                    self.lastSelectedName = id
                }
            }
        }
    }

    func liveAutomationProfile() {
        var k = (0..<16).map(KnobSetup.defaults)
        k[0].name = "TRK"; k[0].turnRole = .tracks; k[0].pushRole = .automationView; (k[0].r, k[0].g, k[0].b) = (1, 0.58, 0)
        k[1].name = "AUTO"; k[1].turnRole = .selected; k[1].pushRole = .automationRecord; (k[1].r, k[1].g, k[1].b) = (0.2, 0.82, 0.48)
        k[2].name = "TIME"; k[2].turnRole = .scrub; k[2].pushRole = .playStop; (k[2].r, k[2].g, k[2].b) = (0.24, 0.6, 1)
        knobs = k; values[1] = 64; setupName = "AUTOMATION"; lastTouched = nil   // its name (Marko, 26.10.2026)
        save(); drawAll()
    }
}
