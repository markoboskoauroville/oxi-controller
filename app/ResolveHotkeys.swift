// v34: E16 FOR DAVINCI RESOLVE AS MIDI TO KEYBOARD (Marko, 31.10.2026: "make this E16 ... basically a MIDI to keyboard
// application, so it triggers all the possible hotkeys. If some hotkeys are not defined, you need to ask me to define them.
// Please read my keyboard shortcuts and work with my own keyboard profile. You need to always read the keyboard to find the
// right key to trigger ... on the matrix display, when the keyboard shortcut is fired, i want to see the name of the action in
// parentheses, but also which keyboard shortcut is being used").
//
// THE PROFILE  ~/Library/Preferences/Blackmagic Design/DaVinci Resolve/keyboard.preset.xml, <PresetListBA>: a Qt data stream
//   (u32 presets, u32 1, QString name, u32 blob length, u32 1, u32 action count; per action QString id, u32 shortcuts, per
//   shortcut u32 keys + u32 codes; Qt code = key | 0x02000000 ⇧ | 0x04000000 ⌘ | 0x08000000 ⌥ | 0x10000000 ⌃). Read again
//   whenever the file changes, so a key Marko remaps in Resolve is the key fired next (tools/resolve_keys.py is the same in
//   Python, for the terminal).
// THE MAP      ~/.config/e16-resolve-map.json: knob (1-16) -> {"press": action, "right": action, "left": action, "label"};
//   written with the first layout (Marko said "yes, please build it" 31.10.2026) when missing. A knob or direction the map
//   leaves out keeps the mixer's behaviour (volume, pan, knob 1's playhead).
// FIRING       the key goes to Resolve's process only (CGEvent.postToPid), never to the app in front. The screen says
//   "(Play/Stop) SPACE"; an action without a key says "(Solo Tracks) NO KEY" and is listed in
//   ~/.config/e16-resolve-missing.json for Marko to define in Resolve (Keyboard Customization).
import AppKit
import Foundation

struct HotkeyBinding: Codable { var press: String?; var right: String?; var left: String?; var label: String? }

final class ResolveHotkeys {
    static let shared = ResolveHotkeys()
    static let presetPath = NSHomeDirectory() + "/Library/Preferences/Blackmagic Design/DaVinci Resolve/keyboard.preset.xml"
    static let mapPath = NSHomeDirectory() + "/.config/e16-resolve-map.json"
    static let missingPath = NSHomeDirectory() + "/.config/e16-resolve-missing.json"

    private(set) var preset = ""
    private(set) var actions: [String: [UInt32]] = [:]     // action id -> first key of each shortcut (Qt code)
    private var stamp: Date?
    private var mapStamp: Date?
    private(set) var map: [Int: HotkeyBinding] = [:]

    /// readable names for the screen
    static let names: [String: String] = [
        "controlPlayToggle": "Play/Stop", "timelineSoloTracks": "Solo Tracks", "timelineMuteTracks": "Mute Tracks",
        "timelineClearRestoreSolo": "Clear Solo", "timelineClearRestoreMutes": "Clear Mutes",
        "fairlightActionsExclusiveSolo": "Exclusive Solo",
    ]
    static func name(_ a: String) -> String {
        if let n = names[a] { return n }
        if a.hasPrefix("editAutoSelectToggleAudio"), let n = Int(a.dropFirst("editAutoSelectToggleAudio".count)) { return "Select A\(n)" }
        return a
    }

    static let firstLayout: [Int: HotkeyBinding] = [
        1: HotkeyBinding(press: "controlPlayToggle", label: "Play/Stop, turn = playhead"),
        2: HotkeyBinding(press: "timelineSoloTracks", label: "Solo the selected tracks"),
        3: HotkeyBinding(press: "timelineMuteTracks", label: "Mute the selected tracks"),
        4: HotkeyBinding(press: "timelineClearRestoreSolo", label: "Clear / restore solo"),
        5: HotkeyBinding(press: "editAutoSelectToggleAudio1", label: "Select audio track 1"),
        6: HotkeyBinding(press: "editAutoSelectToggleAudio2", label: "Select audio track 2"),
        7: HotkeyBinding(press: "editAutoSelectToggleAudio3", label: "Select audio track 3"),
        8: HotkeyBinding(press: "editAutoSelectToggleAudio4", label: "Select audio track 4"),
    ]

    // MARK: the profile

    func reloadIfChanged() {
        let m = (try? FileManager.default.attributesOfItem(atPath: ResolveHotkeys.presetPath))?[.modificationDate] as? Date
        if m != stamp, let x = try? String(contentsOfFile: ResolveHotkeys.presetPath, encoding: .utf8) { stamp = m; parse(x) }
        let mm = (try? FileManager.default.attributesOfItem(atPath: ResolveHotkeys.mapPath))?[.modificationDate] as? Date
        if mm == nil { writeFirstLayout() }
        else if mm != mapStamp, let d = FileManager.default.contents(atPath: ResolveHotkeys.mapPath),
                let j = try? JSONDecoder().decode([String: HotkeyBinding].self, from: d) {
            mapStamp = mm; map = Dictionary(uniqueKeysWithValues: j.compactMap { k, v in Int(k).map { ($0, v) } })
        }
    }

    private func writeFirstLayout() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let j = Dictionary(uniqueKeysWithValues: ResolveHotkeys.firstLayout.map { ("\($0.key)", $0.value) })
        if let d = try? enc.encode(j) { try? d.write(to: URL(fileURLWithPath: ResolveHotkeys.mapPath)) }
        map = ResolveHotkeys.firstLayout
        mapStamp = (try? FileManager.default.attributesOfItem(atPath: ResolveHotkeys.mapPath))?[.modificationDate] as? Date
    }

    private func parse(_ xml: String) {
        guard let r = xml.range(of: "<PresetListBA>"), let e = xml.range(of: "</PresetListBA>") else { return }
        let hex = Array(xml[r.upperBound..<e.lowerBound].utf8)
        var b = [UInt8](); b.reserveCapacity(hex.count / 2)
        func nib(_ c: UInt8) -> UInt8 { c <= 57 ? c - 48 : (c | 32) - 87 }
        var i = 0; while i + 1 < hex.count { b.append(nib(hex[i]) << 4 | nib(hex[i + 1])); i += 2 }
        var p = 0
        func u32() -> UInt32 {
            guard p + 4 <= b.count else { p = b.count; return 0 }
            let v = UInt32(b[p]) << 24 | UInt32(b[p + 1]) << 16 | UInt32(b[p + 2]) << 8 | UInt32(b[p + 3]); p += 4; return v
        }
        func qstr() -> String {
            let n = Int(u32()); guard n != 0xFFFFFFFF, n > 0, p + n <= b.count else { return "" }
            var units = [UInt16](); var k = p
            while k + 1 < p + n { units.append(UInt16(b[k]) << 8 | UInt16(b[k + 1])); k += 2 }
            p += n; return String(decoding: units, as: UTF16.self)
        }
        _ = u32(); _ = u32(); preset = qstr(); _ = u32(); _ = u32()
        let count = Int(u32())
        var out: [String: [UInt32]] = [:]
        for _ in 0..<count {
            guard p < b.count else { break }
            let id = qstr()
            var codes: [UInt32] = []
            for _ in 0..<Int(u32()) {
                let n = Int(u32())
                for k in 0..<n { let c = u32(); if k == 0 { codes.append(c) } }
            }
            out[id] = codes
        }
        actions = out
    }

    // MARK: Qt code -> a Mac key press

    static let letters: [Character: CGKeyCode] = [
        "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7, "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14,
        "R": 15, "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
        "8": 28, "0": 29, "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37, "J": 38, "'": 39, "K": 40, ";": 41,
        "\\": 42, ",": 43, "/": 44, "N": 45, "M": 46, ".": 47, "`": 50]
    static let special: [UInt32: CGKeyCode] = [
        0x20: 49, 0x01000000: 53, 0x01000001: 48, 0x01000003: 51, 0x01000004: 36, 0x01000005: 76, 0x01000007: 117,
        0x01000010: 115, 0x01000011: 119, 0x01000012: 123, 0x01000013: 126, 0x01000014: 124, 0x01000015: 125,
        0x01000016: 116, 0x01000017: 121]
    static let fkeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    static func keyText(_ code: UInt32) -> String {
        var s = ""
        if code & 0x10000000 != 0 { s += "CTRL " }; if code & 0x08000000 != 0 { s += "OPT " }
        if code & 0x02000000 != 0 { s += "SHIFT " }; if code & 0x04000000 != 0 { s += "CMD " }
        let k = code & 0x01FFFFFF
        let named: [UInt32: String] = [0x20: "SPACE", 0x01000000: "ESC", 0x01000001: "TAB", 0x01000003: "BKSP", 0x01000004: "RETURN",
                                       0x01000005: "ENTER", 0x01000007: "DEL", 0x01000010: "HOME", 0x01000011: "END",
                                       0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
                                       0x01000016: "PGUP", 0x01000017: "PGDN"]
        if let n = named[k] { s += n } else if (0x01000030...0x01000043).contains(k) { s += "F\(k - 0x01000030 + 1)" }
        else if let u = UnicodeScalar(k) { s += String(Character(u)).uppercased() }
        return s
    }

    static func cg(_ code: UInt32) -> (CGKeyCode, CGEventFlags)? {
        var f = CGEventFlags()
        if code & 0x02000000 != 0 { f.insert(.maskShift) }; if code & 0x04000000 != 0 { f.insert(.maskCommand) }
        if code & 0x08000000 != 0 { f.insert(.maskAlternate) }; if code & 0x10000000 != 0 { f.insert(.maskControl) }
        let k = code & 0x01FFFFFF
        if let s = special[k] { return (s, f) }
        if (0x01000030...0x01000043).contains(k) { return (fkeys[Int(k - 0x01000030)], f) }
        if let u = UnicodeScalar(k), let c = letters[Character(String(Character(u)).uppercased())] { return (c, f) }
        return nil
    }

    // MARK: firing

    /// the binding of knob (1-based) for press / right / left, nil when the map leaves it to the mixer
    func action(knob: Int, _ how: String) -> String? {
        reloadIfChanged()
        guard let b = map[knob] else { return nil }
        return how == "press" ? b.press : how == "right" ? b.right : b.left
    }

    /// fires the action's key into Resolve; the screen text: "(Play/Stop) SPACE" or "(Solo Tracks) NO KEY"
    func fire(_ action: String) -> String {
        let said = fireKey(action)
        // v35: every fire on one line in ~/Library/Logs/e16-resolve.log, with the Accessibility state (a key posted to another
        // app without it is dropped by macOS without a word)
        let line = "\(Date()) \(action) -> \(said) · accessibility \(AXIsProcessTrusted() ? "on" : "OFF")\n"
        let log = NSHomeDirectory() + "/Library/Logs/e16-resolve.log"
        if !FileManager.default.fileExists(atPath: log) { FileManager.default.createFile(atPath: log, contents: nil) }
        if let h = FileHandle(forWritingAtPath: log) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
        return AXIsProcessTrusted() ? said : said + " · PERMISSIONS"
    }

    private func fireKey(_ action: String) -> String {
        reloadIfChanged()
        let label = "(" + ResolveHotkeys.name(action) + ")"
        guard let code = actions[action]?.first else { noteMissing(action); return label + " NO KEY" }
        guard let (kc, flags) = ResolveHotkeys.cg(code) else { return label + " " + ResolveHotkeys.keyText(code) + " ?" }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.blackmagic-design.DaVinciResolve").first else {
            return label + " RESOLVE IS NOT RUNNING"
        }
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            if let e = CGEvent(keyboardEventSource: src, virtualKey: kc, keyDown: down) { e.flags = flags; e.postToPid(app.processIdentifier) }
        }
        return label + " " + ResolveHotkeys.keyText(code)
    }

    private func noteMissing(_ action: String) {
        var j = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: ResolveHotkeys.missingPath)))) as? [String: String] ?? [:]
        j[action] = ResolveHotkeys.name(action)
        if let d = try? JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: URL(fileURLWithPath: ResolveHotkeys.missingPath))
        }
    }
}
