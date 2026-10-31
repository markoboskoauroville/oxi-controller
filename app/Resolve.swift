// E16 FOR DAVINCI RESOLVE (v27, Marko, 29.10.2026): "the first vertical column will control the first 4 channels solo,
// and the second vertical column ... mute. The next vertical column, number 3, is controlling the first 4 channels
// volume, and the last one is controlling the first 4 channels panning ... if you can read the track names, you can put
// them right there ... Matrix display must be clear: What is solo? What is mute? What is volume? What is panning?"
// and "For any number of channels available in DaVinci Resolve, we can just swap the controls 4 by 4 channels."
//
// Resolve 21.1 takes no Mackie Control (its audio consoles are Blackmagic's own) and its scripting has no track solo,
// mute, fader or pan; measured on his timeline 29.10.2026: SetTrackEnable and SetClipEnabled answer False for audio.
// So, as Marko chose, through the scripting (the DaVinci Resolve Actions router on 127.0.0.1:8940):
//   VOLUME  every clip of the track, AudioVolume in dB (−60 … +12), 0.5 dB a click (0.1 with Shift); push: 0 dB
//   PAN     every clip of the track, AudioPan −100 (L) … +100 (R), 2 a click (0.5 with Shift); push: centre
//   MUTE    the track's clips turned to the bottom (−100 dB), their own volumes kept here and given back on unmute
//   SOLO    the other tracks muted that way while any solo is on
// Knob i: column i % 4 is the function, row i / 4 the track, the page the group of four (page 2 = A5–A8). Turn right
// = on and left = off for SOLO and MUTE; a push toggles. Shift tapped twice: the page turner, as everywhere in the app.
import Foundation

final class ResolveMixer {
    static let shared = ResolveMixer()
    struct Track { var name: String; var vol: Double; var pan: Double; var clips: Int }

    private(set) var count = 0                    // audio tracks on the timeline
    private(set) var tracks: [Int: Track] = [:]   // 1-based
    var muted = Set<Int>(), solo = Set<Int>()
    private var silenced: [Int: [Double]] = [:]   // a track turned down: its clips' own volumes
    private let q = DispatchQueue(label: "e16.resolve")
    static let floor = -100.0

    // MARK: the wire: Python run by the router, its `result` back as JSON

    private func run(_ code: String) -> [String: Any]? {
        let pre = "import json\npm = resolve.GetProjectManager(); pr = pm.GetCurrentProject()\ntl = pr.GetCurrentTimeline() if pr else None\n"
        var req = URLRequest(url: URL(string: "http://127.0.0.1:8940/run")!)
        req.httpMethod = "POST"; req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["who": "e16", "code": pre + code, "timeout": 10])
        var out: [String: Any]?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (j["ok"] as? Bool) == true {
                out = j["result"] as? [String: Any]
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 14)
        return out
    }

    /// Names, volumes and pans of tracks first...first+3 and how many there are. nil: Resolve does not answer.
    func refresh(first: Int) -> Bool {
        q.sync {
            guard let r = run("""
                n = tl.GetTrackCount('audio') if tl else 0
                t = {}
                for i in range(\(first), min(n, \(first + 3)) + 1):
                    it = tl.GetItemListInTrack('audio', i) or []
                    c = it[0] if it else None
                    t[str(i)] = {'name': tl.GetTrackName('audio', i) or ('A%d' % i), 'clips': len(it),
                                 'vol': float(c.GetProperty('AudioVolume') or 0) if c else 0.0,
                                 'pan': float(c.GetProperty('AudioPan') or 0) if c else 0.0}
                result = {'n': n, 't': t}
                """) else { return false }
            count = r["n"] as? Int ?? 0
            for (k, v) in r["t"] as? [String: [String: Any]] ?? [:] {
                guard let i = Int(k) else { continue }
                var vol = v["vol"] as? Double ?? 0
                if let kept = silenced[i]?.first { vol = kept }          // a muted track shows its own level
                tracks[i] = Track(name: v["name"] as? String ?? "A\(i)", vol: vol, pan: v["pan"] as? Double ?? 0, clips: v["clips"] as? Int ?? 0)
            }
            return true
        }
    }

    // MARK: volume and pan, every clip of the track

    /// 29.10.2026 (Marko: "I am turning the knob 3 for the volume of track 1, and nothing is happening"): Audio 1 had no
    /// clips, and volume and pan live on the clips; the screen now says so instead of staying silent.
    private func empty(_ i: Int) -> Bool { (tracks[i]?.clips ?? 0) == 0 }

    func nudge(_ i: Int, volume d: Double) -> String {
        q.sync {
            guard tracks[i] != nil else { return "A\(i): no such track" }
            if empty(i) { return line(i, "NO CLIPS: NOTHING TO TURN") }
            if var kept = silenced[i] {                                    // muted: the level it comes back to
                kept = kept.map { min(12, max(-60, $0 + d)) }; silenced[i] = kept
                tracks[i]?.vol = kept.first ?? 0
            } else if let r = run(setAll(i, "AudioVolume", "min(12.0, max(-60.0, v + \(d)))")), let v = r["v"] as? Double {
                tracks[i]?.vol = v
            }
            return line(i, "VOL " + db(tracks[i]?.vol ?? 0))
        }
    }

    func setVolume(_ i: Int, to v: Double) -> String {
        q.sync {
            if silenced[i] != nil { silenced[i] = silenced[i]!.map { _ in v }; tracks[i]?.vol = v }
            else if let r = run(setAll(i, "AudioVolume", "\(v)")), let nv = r["v"] as? Double { tracks[i]?.vol = nv }
            return line(i, "VOL " + db(tracks[i]?.vol ?? 0))
        }
    }

    func nudge(_ i: Int, pan d: Double) -> String {
        q.sync {
            if empty(i) { return line(i, "NO CLIPS: NOTHING TO PAN") }
            if let r = run(setAll(i, "AudioPan", "min(100.0, max(-100.0, v + \(d)))")), let v = r["v"] as? Double { tracks[i]?.pan = v }
            return line(i, "PAN " + panWord(tracks[i]?.pan ?? 0))
        }
    }

    func setPan(_ i: Int, to v: Double) -> String {
        q.sync {
            if let r = run(setAll(i, "AudioPan", "\(v)")), let nv = r["v"] as? Double { tracks[i]?.pan = nv }
            return line(i, "PAN " + panWord(tracks[i]?.pan ?? 0))
        }
    }

    /// Python that sets prop on every clip of track i to expr (v = the clip's value now) and answers the first.
    private func setAll(_ i: Int, _ prop: String, _ expr: String) -> String {
        """
        first = None
        for c in (tl.GetItemListInTrack('audio', \(i)) or []):
            v = float(c.GetProperty('\(prop)') or 0)
            nv = \(expr)
            c.SetProperty('\(prop)', nv)
            if first is None: first = float(c.GetProperty('\(prop)') or 0)
        result = {'v': first if first is not None else 0.0}
        """
    }

    // MARK: the playhead (v28)

    /// The current timeline's playhead moved by `frames` (negative = back), kept inside the timeline; answers the timecode.
    func movePlayhead(frames: Int) -> String {
        q.sync {
            guard let r = run("""
                fps = float(pr.GetSetting('timelineFrameRate') or 24) if pr else 24.0
                f = int(round(fps))
                def tc2f(tc):
                    h, m, s, fr = [int(x) for x in tc.replace(';', ':').split(':')]
                    return ((h * 60 + m) * 60 + s) * f + fr
                def f2tc(n):
                    return '%02d:%02d:%02d:%02d' % (n // (3600 * f), n // (60 * f) % 60, n // f % 60, n % f)
                cur = tc2f(tl.GetCurrentTimecode())
                new = max(tl.GetStartFrame(), min(tl.GetEndFrame() - 1, cur + (\(frames))))
                tl.SetCurrentTimecode(f2tc(new))
                result = {'tc': tl.GetCurrentTimecode()}
                """), let tc = r["tc"] as? String else { return "PLAYHEAD: RESOLVE DOES NOT ANSWER" }
            return "PLAYHEAD " + tc
        }
    }

    // MARK: mute and solo, by turning tracks down to the floor and back

    func setMute(_ i: Int, _ on: Bool) -> String {
        q.sync { if on { muted.insert(i) } else { muted.remove(i) }; apply() }
        return line(i, muted.contains(i) ? "MUTE ON" : "MUTE OFF")
    }

    func setSolo(_ i: Int, _ on: Bool) -> String {
        q.sync { if on { solo.insert(i) } else { solo.remove(i) }; apply() }
        return line(i, solo.contains(i) ? "SOLO ON" : "SOLO OFF") + (solo.isEmpty ? "" : " · \(solo.count) SOLO")
    }

    /// Every track as mute and solo say: down when muted, or when something else is soloed; back when neither.
    private func apply() {
        for i in 1...max(count, 1) {
            let down = muted.contains(i) || (!solo.isEmpty && !solo.contains(i))
            if down, silenced[i] == nil {
                if let r = run("""
                    vs = []
                    for c in (tl.GetItemListInTrack('audio', \(i)) or []):
                        vs.append(float(c.GetProperty('AudioVolume') or 0)); c.SetProperty('AudioVolume', \(ResolveMixer.floor))
                    result = {'vs': vs}
                    """), let vs = r["vs"] as? [Double] { silenced[i] = vs }
            } else if !down, let vs = silenced[i] {
                let list = vs.map { String($0) }.joined(separator: ",")
                _ = run("""
                    vs = [\(list)]
                    for k, c in enumerate(tl.GetItemListInTrack('audio', \(i)) or []):
                        c.SetProperty('AudioVolume', vs[k] if k < len(vs) else 0.0)
                    result = {'ok': True}
                    """)
                silenced[i] = nil
            }
        }
    }

    // MARK: words for the screen

    func name(_ i: Int) -> String { tracks[i]?.name ?? (i <= count ? "A\(i)" : "") }
    func line(_ i: Int, _ what: String) -> String { "A\(i) \(name(i).uppercased()) · \(what)" }
    func db(_ v: Double) -> String { v <= -59.9 ? "-INF" : String(format: "%+.1f", v) }
    func panWord(_ v: Double) -> String { abs(v) < 0.5 ? "C" : (v < 0 ? "L" : "R") + String(Int(abs(v).rounded())) }
}

extension Engine {
    /// The track a knob of this page drives (1-based), and what it does: 0 SOLO, 1 MUTE, 2 VOLUME, 3 PAN.
    func resolveTrack(_ i: Int) -> Int { page * 4 + i / 4 + 1 }
    func resolveFunction(_ i: Int) -> Int { i % 4 }

    func resolveTurn(_ i: Int, by step: Double) {
        let t = resolveTrack(i), m = ResolveMixer.shared
        guard t <= max(m.count, 1) else { showLive("A\(t): THE TIMELINE HAS \(m.count) AUDIO TRACKS"); return }
        lastTouched = i
        let fine = shift
        // v28 (Marko, 31.10.2026: "When I turn it left or right, it makes solo on the first column ... Pressing needs to
        // send notes and turning needs to send CC, so they cannot do the same function at the same time ... Encoder number
        // 1, turning it up or down, is going to scroll through the timeline"): a TURN (CC) never switches SOLO or MUTE;
        // that is the PRESS (note) only. Knob 1 turned moves the playhead: 12 frames (half a second) a click, 1 with Shift.
        if i == 0 { scrollTimeline(by: Int(step) * (fine ? 1 : 12)); return }
        let f = resolveFunction(i)
        if f <= 1 { showLive("A\(t): TURN DOES NOTHING HERE, PRESS = \(f == 0 ? "SOLO" : "MUTE")"); return }
        DispatchQueue.global().async {
            let said = f == 2 ? m.nudge(t, volume: step * (fine ? 0.1 : 0.5)) : m.nudge(t, pan: step * (fine ? 0.5 : 2))
            DispatchQueue.main.async { self.ringsDue = true; self.showLive(said) }
        }
    }

    /// v28: the playhead moved by frames; turns that come while Resolve is still moving are added up, never queued one by one
    func scrollTimeline(by frames: Int) {
        pendingScroll += frames
        guard !scrolling else { return }
        scrolling = true
        DispatchQueue.global().async {
            while true {
                let n: Int = DispatchQueue.main.sync { let x = self.pendingScroll; self.pendingScroll = 0; return x }
                if n == 0 { break }
                let said = ResolveMixer.shared.movePlayhead(frames: n)
                DispatchQueue.main.async { self.showLive(said) }
            }
            DispatchQueue.main.async { self.scrolling = false }
        }
    }

    func resolvePress(_ i: Int) {
        let t = resolveTrack(i), m = ResolveMixer.shared
        guard t <= max(m.count, 1) else { return }
        lastTouched = i
        DispatchQueue.global().async {
            let said: String
            switch self.resolveFunction(i) {
            case 0: said = m.setSolo(t, !m.solo.contains(t))
            case 1: said = m.setMute(t, !m.muted.contains(t))
            case 2: said = m.setVolume(t, to: 0)
            default: said = m.setPan(t, to: 0)
            }
            DispatchQueue.main.async { self.ringsDue = true; self.showLive(said) }
        }
    }

    /// Names and levels for this page's four tracks, from Resolve (off the main thread), then the screen and rings.
    func resolveRefresh() {
        let first = page * 4 + 1
        DispatchQueue.global().async {
            let ok = ResolveMixer.shared.refresh(first: first)
            DispatchQueue.main.async {
                if !ok { self.status = "Resolve does not answer (is DaVinci Resolve Actions' router running?)" }
                else { self.status = "DAVINCI RESOLVE · A\(first)–A\(first + 3) of \(ResolveMixer.shared.count) audio tracks · Shift twice: pages" }
                self.ringsDue = true; self.drawLabels()
            }
        }
    }

    /// The screen: per knob what it is and its state, and under it the track's name; columns SOLO, MUTE, VOL, PAN.
    func resolveCells() -> [(String, String)] {
        let m = ResolveMixer.shared
        return (0..<16).map { i in
            let t = resolveTrack(i)
            guard t <= m.count else { return ("", "") }
            let name = String(m.name(t).uppercased().prefix(5))
            let tr = m.tracks[t]
            switch resolveFunction(i) {
            case 0: return (m.solo.contains(t) ? "SOLO*" : "solo", name)
            case 1: return (m.muted.contains(t) ? "MUTE*" : "mute", name)
            case 2: return ((tr?.clips ?? 0) == 0 ? "V --" : "V" + (tr.map { m.db($0.vol) } ?? "?"), name)
            default: return ((tr?.clips ?? 0) == 0 ? "P --" : "P " + (tr.map { m.panWord($0.pan) } ?? "?"), name)
            }
        }
    }

    /// The rings: SOLO yellow, MUTE red (bright when on), VOLUME green and PAN blue as far round as they are.
    func resolveRings() -> [Ring] {
        let m = ResolveMixer.shared
        return (0..<16).map { i in
            let t = resolveTrack(i)
            guard t <= m.count else { return Ring(r: 0, g: 0, b: 0, amount: 0) }
            let tr = m.tracks[t]
            switch resolveFunction(i) {
            case 0: let on = m.solo.contains(t); return Ring(r: on ? 127 : 30, g: on ? 110 : 26, b: 0, amount: on ? 1 : 0.15)
            case 1: let on = m.muted.contains(t); return Ring(r: on ? 127 : 30, g: 0, b: 0, amount: on ? 1 : 0.15)
            case 2: return Ring(r: 0, g: 110, b: 20, amount: max(0, min(1, ((tr?.vol ?? 0) + 60) / 72)))
            default: return Ring(r: 0, g: 40, b: 127, amount: max(0, min(1, ((tr?.pan ?? 0) + 100) / 200)))
            }
        }
    }
}
