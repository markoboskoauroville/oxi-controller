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
    enum TurnRole: String, Codable, CaseIterable { case midi = "MIDI", tracks = "TRACKS", scrub = "SCRUB", parameter = "PARAMETER", hover = "HOVER", selected = "SELECTED", clipPitch = "CLIP PITCH", paramStep = "PARAMETER STEP", zoom = "ZOOM" }
    enum PushRole: String, Codable, CaseIterable { case midi = "MIDI", automationView = "AUTOMATION VIEW", automationRecord = "AUTOMATION RECORD", playStop = "PLAY/STOP", pitchZero = "PITCH TO ZERO", statusLine = "STATUS LINE" }
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
    /// v15: Marko's own note for this knob (the LIST view's text field), saved with the setup
    var note: String = ""
    /// v21 (Marko, 26.10.2026: "an edit button next to the description of the knob and the push ... You fill them in,
    /// but the user can overwrite them"): his own words for what the turn and the push do (after a MIDI Map in Live);
    /// empty = the app's own description
    var turnLabel: String = ""
    var pushLabel: String = ""
    /// v21 (Marko, 26.10.2026: "adjust the color and the intensity of the ring"): 0.1...1, the ring's brightness
    var intensity: Double = 1
    /// v22: the screen's second line under the knob, what the push does (five letters); the first line is name
    var pushName: String = ""

    enum CodingKeys: String, CodingKey { case name, r, g, b, cc, channel, low, high, speed, push, pushKind, pushNumber, pushChannel, turnRole, pushRole, note, turnLabel, pushLabel, intensity, pushName }
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
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        turnLabel = try c.decodeIfPresent(String.self, forKey: .turnLabel) ?? ""
        pushLabel = try c.decodeIfPresent(String.self, forKey: .pushLabel) ?? ""
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
        pushName = try c.decodeIfPresent(String.self, forKey: .pushName) ?? ""
    }

    var colour: Color { Color(red: r, green: g, blue: b) }

    // v21 (Marko, 26.10.2026: "our OXI-E16 needs to always be predictable in its CC numbers and note numbers. The first
    // knob will be CC1, and pressing it sets note 1, and so on until we come to 16. When we go to the next page, we go
    // to 17 and so on ... we have only pages, until we come to the last page"): knob g (0-based over all pages) turns
    // CC n and pushes note n, n = 1...112 on a channel, then the next channel. 112, not 127: CC 120-127 are MIDI's
    // channel mode messages (all notes off, reset ...) and must never come from a knob; CC 0 is bank select. So 7
    // pages a channel, 16 channels, 112 pages, 1,792 knobs.
    static let pagesPerChannel = 7
    static let pageCount = pagesPerChannel * 16
    static func numbers(_ g: Int) -> (channel: Int, number: Int) { (g / 112 + 1, g % 112 + 1) }

    /// Knob g's numbers put back to the rule, whatever a saved setup said.
    mutating func number(_ g: Int) {
        let (ch, n) = KnobSetup.numbers(g)
        cc = n; channel = ch; pushNumber = n; pushChannel = ch; pushKind = .note
        if name.range(of: #"^(K|CC)\d+$"#, options: .regularExpression) != nil { name = "CC\(n)" }   // the old K<n> names
    }

    /// The screen's two lines (v22): the turn's name, and the push's (his own, or a word for what it does).
    var screenLines: (String, String) {
        let push: String
        if !pushName.isEmpty { push = pushName }
        else {
            switch pushRole {
            case .automationView: push = "AUTO"
            case .automationRecord: push = "REC"
            case .playStop: push = "PLAY"
            case .pitchZero: push = "ZERO"
            case .statusLine: push = "LINE"
            case .midi: push = self.push == .off ? "" : "N\(pushNumber)"
            }
        }
        return (name, push)
    }

    static func defaults(_ g: Int) -> KnobSetup {
        let hue = Double(g % 16) / 16
        let c = NSColor(hue: hue, saturation: 0.9, brightness: 1, alpha: 1).usingColorSpace(.sRGB) ?? .white
        var k = KnobSetup(name: "CC\(numbers(g).number)", r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent),
                          cc: 1, channel: 1, pushNumber: 1)
        k.number(g); k.push = .momentary     // momentary: Live's mapped button flips on every press
        return k
    }
}

struct Setup: Codable { var name: String; var knobs: [KnobSetup]; var pages: [[KnobSetup]]? = nil }

final class Engine: ObservableObject {
    // v21: pages, each sixteen knobs; knobs, values and pushed are the page in front
    @Published var pages: [[KnobSetup]] = [(0..<16).map(KnobSetup.defaults)]
    @Published var page = 0
    @Published var pageValues: [[Double]] = [Array(repeating: 0, count: 16)]
    @Published var pagePushed: [[Bool]] = [Array(repeating: false, count: 16)]
    var knobs: [KnobSetup] { get { pages[page] } set { pages[page] = newValue } }
    var values: [Double] { get { pageValues[page] } set { pageValues[page] = newValue } }
    var pushed: [Bool] { get { pagePushed[page] } set { pagePushed[page] = newValue } }
    /// Knob i of this page over all pages (the chat's key, the CC and note numbers).
    func global(_ i: Int) -> Int { page * 16 + i }

    /// v21: the next or another page; a page never seen is made with its numbers.
    func goTo(page p: Int) {
        let p = max(0, min(KnobSetup.pageCount - 1, p))
        while pages.count <= p {
            let n = pages.count
            pages.append((0..<16).map { KnobSetup.defaults(n * 16 + $0) })
        }
        while pageValues.count < pages.count { pageValues.append(Array(repeating: 0, count: 16)) }
        while pagePushed.count < pages.count { pagePushed.append(Array(repeating: false, count: 16)) }
        page = p; lastTouched = nil; liveSays = ""
        status = navMode ? "PAGE \(p + 1) of \(KnobSetup.pageCount)" : pageLine()
        drawAll()
    }

    func pageLine() -> String {
        let (ch, a) = KnobSetup.numbers(page * 16), b = a + 15
        return "PAGE \(page + 1) of \(KnobSetup.pageCount) · CC and notes \(a)–\(b) · channel \(ch)"
    }
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
        // v13 (Marko, 26.10.2026: "the device itself is on the camera, so you can use the camera to test"): a test door
        // on 127.0.0.1:11010 (UDP): "turn N STEP", "push N", "release N", "shift 0|1" act as the E16's own messages
        Thread { [weak self] in self?.testDoor() }.start()
        // v8 (Marko, 26.10.2026: "our device is reading selected parameters ... it shows the value with an LED ... If I
        // click on other parameters, the value is read from that parameter"): a SELECTED knob's ring follows Live
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.followSelected() }
    }

    private func testDoor() {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_port = in_port_t(11010).bigEndian; a.sin_addr.s_addr = inet_addr("127.0.0.1")
        guard withUnsafePointer(to: &a, { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }) == 0 else { return }
        var buf = [UInt8](repeating: 0, count: 256)
        while true {
            let n = recv(fd, &buf, buf.count, 0); guard n > 0 else { continue }
            let w = String(decoding: buf[0..<n], as: UTF8.self).split(separator: " ").map(String.init)
            guard let cmd = w.first else { continue }
            let knob = w.count > 1 ? (Int(w[1]) ?? 1) - 1 : 0
            DispatchQueue.main.async {
                switch cmd {
                case "turn": let st = w.count > 2 ? (Int(w[2]) ?? 1) : 1
                    self.heard([0xB0, UInt8(knob + 1), UInt8(st < 0 ? 128 + st : st)])
                case "push": self.heard([0x90, UInt8(knob), 127])
                case "release": self.heard([0x80, UInt8(knob), 0])
                case "shift": self.heard([w.count > 1 && w[1] == "1" ? 0x90 : 0x80, 16, w.count > 1 && w[1] == "1" ? 127 : 0])
                case "present": self.togglePresent()
                case "nav": self.setNav(!self.navMode)
                case "role":   // role 15 ZOOM: a knob's turn role, as APPLY sets it (v20, for tests from the Mac)
                    if let r = KnobSetup.TurnRole(rawValue: w.dropFirst(2).joined(separator: " ")) { self.knobs[knob].turnRole = r; self.edited(); self.save() }
                default: break
                }
            }
        }
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
        // knobs still as they came (named K<n>, plain MIDI) share one page instead of three each (64 pages, seen
        // through the camera 26.10.2026)
        let plain = (0..<15).filter { i in let k = knobs[i]; return k.name == "K\(i + 1)" && k.turnRole == .midi && k.pushRole == .midi }
        if !plain.isEmpty {
            let list = plain.map { "\($0 + 1)" }.joined(separator: ", ")
            pages.append(("KNOBS \(list)", "These knobs are not set up yet. Each one sends its own control change into Live through the port DJ Mantra Remote, control change twenty for knob one and one more for every knob after it, and its push switches a note on and off. Map them in Live with MIDI Map, or give them a job in the app."))
        }
        for i in 0..<15 where !plain.contains(i) {
            let k = knobs[i]
            let kind = k.pushKind == .note ? "note" : "control change"
            let turn: String
            switch k.turnRole {
            case .tracks: turn = "Turning selects the track above or below in Live's arrangement."
            case .scrub: turn = "Turning moves the playhead along the timeline, a sixteenth note for every step. Hold Shift for finer steps."
            case .paramStep: turn = "Turning jumps to the next or the previous parameter of the device whose parameter you clicked in Live. The screen names it, its value and its place among the device's parameters. The SELECTED knob then turns this parameter. Clicking another parameter in Live starts again from there."
            case .zoom: turn = "Turning zooms the timeline of Live's arrangement in (to the right) or out (to the left), as the + and - keys do."
            case .clipPitch: turn = "Turning changes the pitch of the audio clip shown in Clip View, five cents a step, Transpose and Detune together. Hold Shift for single cents. The screen shows the semitones and cents."
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
            case .statusLine: push = "Pushing closes the line at the bottom of Live's window that tells which parameter this knob is on, and the next push opens it again."
            case .pitchZero: push = "Pushing sets the clip's pitch back to zero semitones and zero cents."
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

    /// v15 (Marko, 26.10.2026: "write under each of the nodes in the application: what is it doing?"): what a knob's
    /// turn and push do, in a few words, for the window.
    func turnText(_ i: Int) -> String {
        let k = knobs[i]
        if !k.turnLabel.isEmpty { return "Turn: " + k.turnLabel }
        switch k.turnRole {
        case .tracks: return "Turn: track up / down (↑ ↓)"
        case .scrub: return "Turn: playhead, a 16th per step (← → by the grid)"
        case .selected: return "Turn: the parameter clicked or stepped to (click it, then ↑ ↓)"
        case .paramStep: return "Turn: next / previous parameter"
        case .clipPitch: return "Turn: clip pitch, 5 cents a step"
        case .zoom: return "Turn: arrangement zoom in / out (+ −)"
        case .hover: return "Turn: the control under the mouse"
        case .parameter: return "Turn: the device's parameters"
        case .midi: return "Turn: CC \(k.cc), channel \(k.channel) (map it: ⌘M)"
        }
    }

    func pushText(_ i: Int) -> String {
        let k = knobs[i]
        if !k.pushLabel.isEmpty { return "Push: " + k.pushLabel }
        switch k.pushRole {
        case .automationView: return "Push: automation view (A)"
        case .automationRecord: return "Push: automation record on / off (F9)"
        case .playStop: return "Push: play / stop (Space)"
        case .pitchZero: return "Push: pitch back to zero (click Transpose, then Delete)"
        case .statusLine: return "Push: Live's status line off"
        case .midi:
            let what = "\(k.pushKind == .note ? "note" : "CC") \(k.pushNumber)"
            switch k.push {
            case .off: return "Push: nothing"
            case .toggle: return "Push: \(what) on / off"
            case .momentary: return "Push: \(what) while held"
            }
        }
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
        // v21 (Marko, 26.10.2026: "I don't need help anymore, because help is already written in this application"):
        // knob sixteen is a knob like the others; with Shift held it turns the pages
        if kind == 0xB0, b[1] == 16, shift { let raw = Int(b[2]); goTo(page: page + (raw < 64 ? 1 : -1)); return }
        if helpPage != nil, kind == 0xB0 || (kind == 0x90 && b[2] > 0) { helpPage = nil }
        if navMode {
            if kind == 0xB0, Engine.navMiddle.contains(Int(b[1]) - 1) { let raw = Int(b[2]); goTo(page: page + (raw < 64 ? 1 : -1)); return }
            if kind == 0x90, b[2] > 0, b[1] < 16 { navPress(Int(b[1])); return }
            if !(b[1] == 16 && (kind == 0x90 || kind == 0x80)) { return }
        }
        if kind == 0xB0, (1...16).contains(Int(b[1])) {                   // a turn
            let i = Int(b[1]) - 1
            let raw = Int(b[2])
            let step = raw < 64 ? raw : raw - 128
            turn(i, by: Double(step))
        } else if kind == 0x90 || kind == 0x80 {                          // a push or a release
            let note = Int(b[1]); let down = kind == 0x90 && b[2] > 0
            if note == 16 {
                shift = down
                if down {   // Shift tapped twice within half a second: the page cross on or off
                    if Date().timeIntervalSince(lastShiftTap) < 0.5 { lastShiftTap = .distantPast; setNav(!navMode); return }
                    lastShiftTap = Date()
                }
                drawLabels(); return
            }
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
        case .paramStep:
            // v11 (Marko, 26.10.2026: "I select one parameter, and then with this one, I'm jumping to other parameters")
            lastTouched = i; selected = i
            DispatchQueue.global().async { let said = Live.shared.stepParameter(by: Int(step)); DispatchQueue.main.async { self.showLive(said) } }
            return
        case .zoom:
            // v20 (Marko, 26.10.2026: "Turning the knob should change the zoom level on the Ableton arrangement view
            // timeline"): Live's own zoom_view through AbletonOSC (Live.zoomArrangement), one zoom click per step
            lastTouched = i; selected = i
            let n = Int(step.rounded()); guard n != 0 else { return }
            DispatchQueue.global().async { let said = Live.shared.zoomArrangement(n); DispatchQueue.main.async { self.showLive(said) } }
            return
        case .clipPitch:
            lastTouched = i; selected = i
            let cents = step * k.speed * (shift ? 1 : 5)
            DispatchQueue.global().async { let said = Live.shared.nudgeClipPitch(cents: cents); DispatchQueue.main.async { self.showLive(said) } }
            return
        case .selected:
            // v7: the parameter last clicked in Live (Live.nudgeSelected); Shift = fine
            lastTouched = i; selected = i
            // v9 (Marko, 26.10.2026: "Maybe 127 steps is not fine enough ... More high resolution and more
            // precision"): Live takes the value as a float over OSC, so the step is ours: a click 1/508 of the range
            // (Live's nudge counts 1/127 per unit), with Shift 1/2540; a fast spin still covers the range, as the E16
            // sends larger steps when turned fast
            let st = step * k.speed * (shift ? 0.05 : 0.25)
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
        guard connected, !presenting, !navMode, let e16 else { return }
        helpPage = nil
        // v22: Live's answer big for two seconds, then the labels again
        e16.send(E16Message.framebuffer(Screen.message(said)))
        messageUntil = Date().addingTimeInterval(2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.05) { [weak self] in self?.drawLabels() }
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
                case .statusLine: said = Live.shared.statusLine().map { $0 ? "LIVE STATUS LINE ON" : "LIVE STATUS LINE OFF" } ?? "— Live does not answer"
                case .pitchZero: said = Live.shared.clipPitch().map { Live.shared.nudgeClipPitch(cents: -$0.cents) } ?? "— Live does not answer"
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
        if navMode {   // the cross: arms orange, full; the middle white; the corners dark
            let arms = Engine.navLeft.union(Engine.navRight).union(Engine.navUp).union(Engine.navDown)
            e16.send(E16Message.rings((0..<16).map { i in
                arms.contains(i) ? Ring(r: 127, g: 60, b: 0, amount: 1) : Engine.navMiddle.contains(i) ? Ring(r: 110, g: 110, b: 110, amount: 1) : Ring(r: 0, g: 0, b: 0, amount: 0)
            }))
            return
        }
        let rings = (0..<16).map { i -> Ring in
            let k = knobs[i]
            let lit = (k.push == .off || pushed[i] ? 1.0 : 0.35) * k.intensity  // a toggled-off knob glows dimmer
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
        if navMode { e16.send(E16Message.framebuffer(Screen.nav(page: page, of: KnobSetup.pageCount, last: lastPage))); return }
        guard Date() >= messageUntil else { return }
        // v22 (Marko, 26.10.2026: "removing the title ... all the space for my custom labels"): two lines a knob; with
        // Shift held the first line is the knob's value
        let cells = (0..<16).map { i -> (String, String) in
            let (t, p) = knobs[i].screenLines
            return (shift ? String(Int(values[i].rounded())) : t, knobs[i].push != .off && pushed[i] && knobs[i].pushRole == .midi ? "ON" : p)
        }
        e16.send(E16Message.framebuffer(Screen.grid(cells, touched: lastTouched)))
    }

    // MARK: v22, the page cross (Marko, 26.10.2026: "I tap the Shift key 2 times, and I enter a special mode to navigate
    // the pages ... paint a cross with the light ... All buttons on the left side are the left arrow, all buttons on the
    // right side are the right arrow, all buttons above the middle are the up arrow, and all buttons below the middle
    // are the down arrow. The 4 in the middle are for turning")

    @Published var navMode = false
    private var lastShiftTap = Date.distantPast
    private var messageUntil = Date.distantPast
    static let navLeft: Set<Int> = [4, 8], navRight: Set<Int> = [7, 11], navUp: Set<Int> = [1, 2], navDown: Set<Int> = [13, 14]
    static let navMiddle: Set<Int> = [5, 6, 9, 10]
    /// The last page in use: the highest page opened or set up (up arrow).
    var lastPage: Int { pages.count - 1 }

    func setNav(_ on: Bool) {
        navMode = on; lastTouched = nil
        status = on ? "PAGES: ◀ ▶ one page, ▲ the last page in use, ▼ page 1, turn the middle to flip, push the middle or tap Shift twice to leave" : pageLine()
        drawAll()
    }

    /// A push while the cross is lit.
    private func navPress(_ i: Int) {
        if Engine.navLeft.contains(i) { goTo(page: page - 1) }
        else if Engine.navRight.contains(i) { goTo(page: page + 1) }
        else if Engine.navUp.contains(i) { goTo(page: lastPage) }
        else if Engine.navDown.contains(i) { goTo(page: 0) }
        else if Engine.navMiddle.contains(i) { setNav(false) }
    }

    // MARK: PRESENT THE OXI

    @Published var statusLineOn = true

    func toggleStatusLine() {
        let want = !statusLineOn
        DispatchQueue.global().async { let r = Live.shared.statusLine(want); DispatchQueue.main.async { if let r { self.statusLineOn = r; self.status = r ? "Live's status line on" : "Live's status line off" } else { self.status = "Live does not answer" } } }
    }

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
        try? enc.encode(Setup(name: setupName, knobs: pages[0], pages: pages)).write(to: file(setupName))
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
        var ps = s.pages ?? [s.knobs]
        for p in ps.indices { ps[p] = (0..<16).map { var k = $0 < ps[p].count ? ps[p][$0] : KnobSetup.defaults(p * 16 + $0); k.number(p * 16 + $0); return k } }
        if ps.isEmpty { ps = [(0..<16).map(KnobSetup.defaults)] }
        page = 0; pages = ps
        pageValues = ps.map { _ in Array(repeating: 0, count: 16) }; pagePushed = ps.map { _ in Array(repeating: false, count: 16) }
    }

    func edited() { ringsDue = true; drawLabels() }

    // MARK: v18, the chat with Claude for every knob (Chat.swift)

    @Published var chats: [Int: [ChatTurn]] = Chats.load()
    @Published var asking: Int? = nil
    @Published var side = "setup"           // the panel beside the knobs: SETUP or CHAT

    /// The knob's setup in words, for Claude.
    func currentSetup(_ i: Int) -> String {
        "knob \(i + 1) of page \(page + 1) (CC and note \(knobs[i].cc), channel \(knobs[i].channel)), named \(knobs[i].name); turn role \(knobs[i].turnRole.rawValue) (\(turnText(i))); push role \(knobs[i].pushRole.rawValue) (\(pushText(i)))"
    }

    /// Marko's message (the prompt, or a reply in the chat) goes to Claude with the whole conversation of that knob.
    func send(_ text: String, knob i: Int) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, asking == nil else { return }
        let g = global(i)
        chats[g, default: []].append(ChatTurn(fromMarko: true, text: t)); Chats.save(chats)
        asking = g
        Chats.ask(history: chats[g] ?? [], current: currentSetup(i)) { [weak self] answer in
            DispatchQueue.main.async {
                guard let self else { return }
                self.chats[g, default: []].append(answer); Chats.save(self.chats); self.asking = nil
            }
        }
    }

    /// APPLY on Claude's answer: only roles the app knows (Chats.ask already dropped any other).
    func apply(_ turn: ChatTurn, knob i: Int) {
        if let r = turn.turnRole.flatMap(KnobSetup.TurnRole.init(rawValue:)) { knobs[i].turnRole = r }
        if let r = turn.pushRole.flatMap(KnobSetup.PushRole.init(rawValue:)) { knobs[i].pushRole = r }
        let g = global(i)
        if let n = chats[g]?.firstIndex(where: { $0.id == turn.id }) { chats[g]?[n].applied = true; Chats.save(chats) }
        edited(); save()
    }

    func clearChat(_ i: Int) { chats[global(i)] = []; Chats.save(chats) }


    /// The first profile, AUTOMATION (Marko, 26.10.2026): knob 1 tracks / automation view, knob 2 a parameter's CC
    /// / automation record, knob 3 scrub / play-stop; the others plain MIDI.
    private var following = false
    private var lastSelectedName = ""

    private func followSelected() {
        // v10: the CLIP PITCH knob's ring follows the clip's pitch (−48…+48 semitones across the ring)
        if connected, !presenting, let j = knobs.firstIndex(where: { $0.turnRole == .clipPitch }) {
            DispatchQueue.global().async {
                guard let p = Live.shared.clipPitch() else { return }
                DispatchQueue.main.async {
                    let k = self.knobs[j]
                    let v = Double(k.low) + (p.cents + 4800) / 9600 * Double(k.high - k.low)
                    if abs(v - self.values[j]) > 0.1 { self.values[j] = v; self.ringsDue = true }
                }
            }
        }
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
        k[3].name = "PARM"; k[3].turnRole = .paramStep; k[3].pushRole = .statusLine; (k[3].r, k[3].g, k[3].b) = (1, 0.85, 0.2)
        k[4].name = "PTCH"; k[4].turnRole = .clipPitch; k[4].pushRole = .pitchZero; (k[4].r, k[4].g, k[4].b) = (0.9, 0.3, 0.9)
        k[2].name = "TIME"; k[2].turnRole = .scrub; k[2].pushRole = .playStop; (k[2].r, k[2].g, k[2].b) = (0.24, 0.6, 1)
        page = 0
        knobs = k; values[1] = 64; setupName = "AUTOMATION"; lastTouched = nil   // its name (Marko, 26.10.2026)
        save(); drawAll()
    }
}
