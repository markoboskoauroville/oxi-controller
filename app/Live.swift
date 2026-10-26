// Live.swift — Ableton Live from the E16 (Marko, 26.10.2026: "The upper-left knob is turning and selecting tracks up or
// down. Pressing on that knob opens the channel automation lane. The second button exchanges the automation parameter,
// and pressing it creates the key frame in the automation line. The third button is scrubbing the timeline. When I
// press it, it's stop/play").
//
// Live's own API answers through AbletonOSC (a Remote Script in the User Library) on UDP; Ableton Live Actions'
// router takes every app's OSC on 127.0.0.1:11002 and passes it on, so this app never fights A1 for Live's one
// answering port (ABLETON_LIVE_ACTIONS README, "The OSC router"). What the API cannot do — show the automation lanes —
// is Live's own key, A (Automation Mode in the Arrangement), sent to Live's process only.
import AppKit
import Foundation

final class Live {
    static let shared = Live()
    private let fd: Int32
    private var router = sockaddr_in()
    /// What Live said last, by address (/live/song/get/current_song_time → [Float] …).
    private(set) var heard: [String: [Any]] = [:]
    private let lock = NSLock()

    private init() {
        fd = socket(AF_INET, SOCK_DGRAM, 0)
        var me = sockaddr_in(); me.sin_family = sa_family_t(AF_INET); me.sin_port = 0; me.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &me) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        router.sin_family = sa_family_t(AF_INET); router.sin_port = in_port_t(11002).bigEndian; router.sin_addr.s_addr = inet_addr("127.0.0.1")
        Thread { self.listen() }.start()
    }

    // MARK: OSC

    private static func pad(_ d: inout Data) { while d.count % 4 != 0 { d.append(0) } }

    static func message(_ address: String, _ args: [Any]) -> Data {
        var d = Data(address.utf8); d.append(0); pad(&d)
        var tags = ","; var body = Data()
        for a in args {
            switch a {
            case let i as Int: tags += "i"; var v = Int32(i).bigEndian; body.append(Data(bytes: &v, count: 4))
            case let f as Double: tags += "f"; var v = Float(f).bitPattern.bigEndian; body.append(Data(bytes: &v, count: 4))
            case let s as String: tags += "s"; body.append(Data(s.utf8)); body.append(0); pad(&body)
            default: break
            }
        }
        d.append(Data(tags.utf8)); d.append(0); pad(&d); d.append(body)
        return d
    }

    func send(_ address: String, _ args: Any...) {
        let d = Live.message(address, args)
        var to = router
        _ = d.withUnsafeBytes { b in withUnsafePointer(to: &to) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, b.baseAddress, d.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
    }

    private func listen() {
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { continue }
            if let (addr, args) = Live.parse(Data(buf[0..<n])) { lock.lock(); heard[addr] = args; lock.unlock() }
        }
    }

    static func parse(_ d: Data) -> (String, [Any])? {
        func str(_ at: inout Int) -> String? {
            guard let end = d[at...].firstIndex(of: 0) else { return nil }
            let s = String(decoding: d[at..<end], as: UTF8.self); at = (end + 4) & ~3; return s
        }
        var at = 0
        guard let addr = str(&at), let tags = str(&at), tags.hasPrefix(",") else { return nil }
        var out: [Any] = []
        for t in tags.dropFirst() {
            switch t {
            case "i": guard at + 4 <= d.count else { break }; out.append(Int(Int32(bigEndian: d[at..<at + 4].withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }))); at += 4
            case "f": guard at + 4 <= d.count else { break }; out.append(Double(Float(bitPattern: UInt32(bigEndian: d[at..<at + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })))); at += 4
            case "s": if let s = str(&at) { out.append(s) }
            case "T": out.append(1)                           // OSC true (Live's is_playing, record_mode …)
            case "F": out.append(0)
            default: break
            }
        }
        return (addr, out)
    }

    /// Ask and wait for the answer (up to [ms]).
    func ask(_ address: String, _ args: Any..., ms: Int = 400) -> [Any]? {
        lock.lock(); heard[address] = nil; lock.unlock()
        let d = Live.message(address, args); var to = router
        _ = d.withUnsafeBytes { b in withUnsafePointer(to: &to) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            sendto(fd, b.baseAddress, d.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } } }
        let until = Date().addingTimeInterval(Double(ms) / 1000)
        while Date() < until {
            lock.lock(); let a = heard[address]; lock.unlock()
            if let a { return a }
            usleep(5000)
        }
        return nil
    }

    // MARK: the profile's actions

    /// The selected track one up or down (the turn's sign), in Live's order of tracks.
    func selectTrack(by step: Int) -> String? {
        guard let n = (ask("/live/song/get/num_tracks")?.last as? Int), n > 0 else { return nil }
        let now = (ask("/live/view/get/selected_track")?.last as? Int) ?? 0
        let next = max(0, min(n - 1, now + (step > 0 ? 1 : -1)))
        send("/live/view/set/selected_track", next)
        let name = ask("/live/track/get/name", next)?.last as? String
        return "\(next + 1) \(name ?? "")"
    }

    // MARK: the parameter of the selected track's device (knob 2)

    private var paramIndex = 0

    /// The selected track, its device (the one selected in Live, else the first) and that device's parameters.
    private func target() -> (track: Int, device: Int, devName: String, params: [String])? {
        guard let t = ask("/live/view/get/selected_track")?.last as? Int else { return nil }
        let sel = ask("/live/view/get/selected_device")
        var d = 0
        if let sel, sel.count >= 2, let st = sel[0] as? Int, st == t, let sd = sel[1] as? Int { d = sd }
        let devs = (ask("/live/track/get/devices/name", t) ?? []).dropFirst().compactMap { $0 as? String }
        guard !devs.isEmpty, d < devs.count else { return nil }
        let params = (ask("/live/device/get/parameters/name", t, d) ?? []).dropFirst(2).compactMap { $0 as? String }
        return (t, d, devs[d], params)
    }

    private func describe(_ t: (track: Int, device: Int, devName: String, params: [String])) -> String {
        let p = min(paramIndex, max(0, t.params.count - 1))
        let value = (ask("/live/device/get/parameter/value_string", t.track, t.device, p)?.last as? String) ?? ""
        return "\(t.devName.uppercased()) · \(t.params.isEmpty ? "—" : t.params[p]) · \(value)"
    }

    func chooseParameter(by step: Int) -> String? {
        guard let t = target(), !t.params.isEmpty else { return "NO DEVICE ON THIS TRACK" }
        paramIndex = max(0, min(t.params.count - 1, paramIndex + (step > 0 ? 1 : -1)))
        return describe(t)
    }

    func changeParameter(by step: Double) -> String? {
        guard let t = target(), !t.params.isEmpty else { return "NO DEVICE ON THIS TRACK" }
        let p = min(paramIndex, t.params.count - 1)
        guard let now = ask("/live/device/get/parameter/value", t.track, t.device, p)?.last as? Double else { return nil }
        let lo = (ask("/live/device/get/parameters/min", t.track, t.device)?.dropFirst(2)[safe: p] as? Double) ?? 0
        let hi = (ask("/live/device/get/parameters/max", t.track, t.device)?.dropFirst(2)[safe: p] as? Double) ?? 1
        let next = max(lo, min(hi, now + (hi - lo) / 127 * step))
        send("/live/device/set/parameter/value", t.track, t.device, p, next)
        usleep(30_000)
        return describe(t)
    }

    private var songTime: Double?
    private var timeAt = Date.distantPast

    /// The playhead moved by [beats] (a turn: a sixteenth per step, faster turns farther).
    func scrub(beats: Double) -> Double? {
        if songTime == nil || Date().timeIntervalSince(timeAt) > 1.5 {
            songTime = ask("/live/song/get/current_song_time")?.last as? Double
        }
        guard let t = songTime else { return nil }
        let next = max(0, t + beats)
        send("/live/song/set/current_song_time", next)
        songTime = next; timeAt = Date()
        return next
    }

    func playStop() -> Bool? {
        let playing = (ask("/live/song/get/is_playing")?.last as? Int) ?? 0
        send(playing == 1 ? "/live/song/stop_playing" : "/live/song/continue_playing")
        return playing != 1
    }

    /// Automation Arm on and the Arrangement's record toggled: turning a knob mapped to a parameter then writes its
    /// key frames into the automation line (what Live's API allows; it cannot drop a breakpoint by itself).
    func automationRecord() -> Bool? {
        send("/live/view/set/automation_arm", 1)                    // AbletonOSC's song handler has no Automation Arm
        let rec = (ask("/live/song/get/record_mode")?.last as? Int) ?? 0
        send("/live/song/set/record_mode", rec == 1 ? 0 : 1)
        if rec != 1, (ask("/live/song/get/is_playing")?.last as? Int) != 1 { send("/live/song/continue_playing") }
        return rec != 1
    }

    // MARK: SELECTED (v7, Marko, 26.10.2026: "I cannot change parameters by selecting them"): the parameter last
    // clicked in Live (song.view.selected_parameter), turned through two commands added to the local AbletonOSC
    // (abletonosc/view.py: /live/view/get/selected_parameter, /live/view/nudge_selected_parameter)

    /// The selected parameter now: its device, name, value as Live writes it, and where the value sits 0…1.
    func readSelected() -> (dev: String, name: String, text: String, frac: Double)? {
        guard let a = ask("/live/view/get/selected_parameter", ms: 300), a.count >= 6,
              let dev = a[0] as? String, let name = a[1] as? String, let text = a[2] as? String,
              let v = a[3] as? Double, let lo = a[4] as? Double, let hi = a[5] as? Double, !name.isEmpty else { return nil }
        return (dev, name, text, hi > lo ? (v - lo) / (hi - lo) : 0)
    }

    /// v11: the next or previous parameter of the device (/live/view/step_parameter); knob 2 then turns that one.
    func stepParameter(by step: Int) -> String {
        guard let a = ask("/live/view/step_parameter", step > 0 ? 1 : -1, ms: 600), a.count >= 3,
              let dev = a[0] as? String, let name = a[1] as? String, let value = a[2] as? String else { return "— Live does not answer" }
        if name.isEmpty { return "CLICK A PARAMETER OF A DEVICE IN LIVE FIRST" }
        let where_ = a.count >= 4 ? " · \(a[3])" : ""
        return "\(dev.uppercased()) · \(name) · \(value)\(where_)"
    }

    func nudgeSelected(by step: Double) -> String {
        guard let a = ask("/live/view/nudge_selected_parameter", step, ms: 600), a.count >= 3,
              let dev = a[0] as? String, let name = a[1] as? String, let value = a[2] as? String else { return "— Live does not answer" }
        if name.isEmpty { return "CLICK A KNOB OR SLIDER IN LIVE FIRST" }
        return "\(dev.uppercased()) · \(name) · \(value)"
    }

    // MARK: CLIP PITCH (v10, Marko, 26.10.2026: "make a special case for pitch sliders"): the clip in Clip View, its
    // Transpose and Detune as cents, through /live/view/get/clip_pitch and /live/view/nudge_clip_pitch (AbletonOSC)

    func clipPitch() -> (clip: String, text: String, cents: Double)? {
        guard let a = ask("/live/view/get/clip_pitch", ms: 300), a.count >= 3, let c = a[0] as? String,
              let t = a[1] as? String, let v = a[2] as? Double else { return nil }
        return (c, t, v)
    }

    func nudgeClipPitch(cents: Double) -> String {
        guard let a = ask("/live/view/nudge_clip_pitch", cents, ms: 600), a.count >= 2, let c = a[0] as? String, let t = a[1] as? String else { return "— Live does not answer" }
        return c.isEmpty ? t : "\(c.uppercased()) · \(t)"
    }

    /// v12: Live's status line (knob 4's and knob 2's place) off or on; nil: toggle. Returns whether it is on.
    func statusLine(_ on: Bool? = nil) -> Bool? {
        let a = on == nil ? ask("/live/view/set/status_line", ms: 500) : ask("/live/view/set/status_line", on! ? 1 : 0, ms: 500)
        return (a?.first as? Int).map { $0 == 1 }
    }

    // MARK: HOVER (Marko, 26.10.2026: "I just simply cover any knob in Ableton, and when I turn the knob in my hardware,
    // it turns that knob. In hovering mode")

    private var dragStart: CGPoint?
    private var dragY: CGFloat = 0
    private var dragEnd: DispatchWorkItem?

    /// The control under the mouse pointer turned: Live's own gesture for every knob, slider and number box is a
    /// vertical drag on it, so a turn becomes a small drag there (a step = [pixels] up or down), posted to Live alone:
    /// the real pointer does not move. Steps close together are one drag; it is let go 250 ms after the last.
    func hover(by step: Double, fine: Bool) -> String? {
        guard let live = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.hasPrefix("com.ableton.live") == true }) else { return "LIVE IS NOT OPEN" }
        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
            return "ALLOW THIS APP: SYSTEM SETTINGS, ACCESSIBILITY"
        }
        let pid = live.processIdentifier
        let at = CGEvent(source: nil)?.location ?? .zero
        func post(_ type: CGEventType, _ p: CGPoint, dy: Int64 = 0) {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
            if dy != 0 { e.setIntegerValueField(.mouseEventDeltaY, value: dy) }
            if fine { e.flags = .maskCommand }                                // ⌘-drag: Live's fine adjustment
            e.postToPid(pid)
        }
        if dragStart == nil { dragStart = at; dragY = 0; post(.leftMouseDown, at) }
        let px = CGFloat(-step * (fine ? 1 : 3))                              // clockwise = up = more
        dragY += px
        post(.leftMouseDragged, CGPoint(x: dragStart!.x, y: dragStart!.y + dragY), dy: Int64(px))
        dragEnd?.cancel()
        let end = DispatchWorkItem { [weak self] in
            guard let self, let s = self.dragStart else { return }
            post(.leftMouseUp, CGPoint(x: s.x, y: s.y + self.dragY)); self.dragStart = nil
        }
        dragEnd = end
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: end)
        return nil
    }

    /// Live's key A, Automation Mode in the Arrangement (the lanes of the selected track shown), posted to Live alone.
    func automationView() -> Bool {
        guard let live = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.hasPrefix("com.ableton.live") == true }) else { return false }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { return false }  // 0 = A
            e.postToPid(live.processIdentifier)
        }
        return true
    }
}

extension Collection {
    subscript(safe i: Index) -> Element? { indices.contains(i) ? self[i] : nil }
}
