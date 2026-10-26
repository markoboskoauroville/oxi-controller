// Chat.swift — a conversation with Claude for every knob (Marko, 26.10.2026: "if I ask for something that is
// impossible, please tell me it is impossible, or what we would need to change in the app to make it possible ...
// build a chat interface inside this, so there is back and forth communication for a certain prompt or button").
//
// The knob's prompt is the first message. Claude knows exactly what the app can do today (the catalogue below, the
// same roles as the knob's setup) and answers in a fixed shape: possible / partly / impossible, a plain answer, the
// roles to apply when they exist, and what the app would need to make the rest possible. The app applies only roles
// it knows; nothing Claude writes runs by itself. The model is the newest of the family chosen in Settings.
import Foundation

struct ChatTurn: Codable, Equatable, Identifiable {
    var id = UUID()
    var fromMarko: Bool
    var text: String
    var verdict: String? = nil          // possible | partly | buildable | impossible (Claude's turns)
    var turnRole: String? = nil
    var pushRole: String? = nil
    var needs: String? = nil            // what the app would need for the rest
    var applied = false
}

enum Chats {
    static let file = Keys.dataDir.appendingPathComponent("chats.json")
    static func load() -> [Int: [ChatTurn]] {
        guard let d = try? Data(contentsOf: file), let c = try? JSONDecoder().decode([Int: [ChatTurn]].self, from: d) else { return [:] }
        return c
    }
    static func save(_ c: [Int: [ChatTurn]]) {
        try? FileManager.default.createDirectory(at: Keys.dataDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(c).write(to: file)
    }

    /// What the app can do today, for Claude: every role with the sentence the app itself shows for it.
    static func catalogue() -> String {
        let turns = KnobSetup.TurnRole.allCases.map { "  \($0.rawValue): " + turnSentence[$0, default: ""] }.joined(separator: "\n")
        let pushes = KnobSetup.PushRole.allCases.map { "  \($0.rawValue): " + pushSentence[$0, default: ""] }.joined(separator: "\n")
        return "TURN roles (what turning a knob can do):\n\(turns)\nPUSH roles (what pushing a knob can do):\n\(pushes)"
    }
    static let turnSentence: [KnobSetup.TurnRole: String] = [
        .midi: "sends a MIDI control change on a channel into Live (port DJ Mantra Remote); Live's MIDI Map ties it to any one parameter",
        .tracks: "selects the track above or below in the arrangement",
        .scrub: "moves the playhead, a sixteenth note a step",
        .parameter: "chooses which parameter of the selected track's device is automated; with Shift changes its value",
        .hover: "turns the control under the mouse pointer (unreliable, kept for tests)",
        .selected: "changes the parameter last clicked in Live, fine steps (1/508), any device or mixer control",
        .clipPitch: "changes the pitch of the audio clip in Clip View, 5 cents a step",
        .paramStep: "steps to the next or previous parameter of the clicked device",
    ]
    static let pushSentence: [KnobSetup.PushRole: String] = [
        .midi: "sends a MIDI note or CC (off / toggle / momentary)",
        .automationView: "shows or hides automation lanes (A)",
        .automationRecord: "automation arm and record on / off",
        .playStop: "play / stop",
        .pitchZero: "clip pitch back to zero",
        .statusLine: "Live's status line off / on",
    ]

    static let system = """
    You are inside the Mac app "DJ Mantra Ableton Remote for OXI E16". It turns the sixteen knobs of an OXI E16 \
    controller into controls for Ableton Live, through AbletonOSC and a virtual MIDI port. Marko describes in his own \
    words what one knob should do; you decide whether the app can do it today.

    The app can only do what this catalogue lists. Nothing else exists yet:
    {CATALOGUE}

    Answer every message in the JSON shape you are given:
    - verdict "possible" when one TURN role and/or one PUSH role from the catalogue does what he asks; name them \
    exactly as written in the catalogue.
    - verdict "partly" when a role covers part of it; name that role and say in "needs" what is missing.
    - verdict "buildable" when the catalogue cannot do it today but the app can be extended to do it. Say plainly \
    "not yet, but it can be built", and in "needs" name the route and what to add. Most requests are this.
    - verdict "impossible" ONLY when no route below can do it at all (Live exposes nothing for it, or the E16 \
    hardware cannot). Say why. Never use "impossible" for something that only needs new code.
    The routes the app can be extended through (Marko, 26.10.2026: zoom was called impossible and it is not):
      1. A new handler in AbletonOSC calling Live's Python API (Song, Track, Clip, Device, \
    Application.View: zoom_view, scroll_view, focus_view, show_view and more). This is how the app's own roles work.
      2. Mackie Control: Live ships a MackieControl surface script; the app can act as a Mackie Control unit on a \
    virtual port and send its buttons (zoom with the cursor keys, banks, transport, markers, fader and V-pot \
    messages). Uses one of Live's control surface slots.
      3. A Live keyboard shortcut sent to Live's window (as the AUTOMATION VIEW role sends A).
      4. MIDI Map of a CC or note (anything Live shows in blue in MIDI Map mode).
    The E16 hardware: 16 endless knobs with push, one shift key, a 128x64 screen.
    Never claim a role does more than its catalogue line says. Keep "answer" short, plain English, no lists of \
    options he did not ask for. If his message is a question, answer it; verdict then describes the knob as set now.
    The knob's current setup: {CURRENT}
    """

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "verdict": ["type": "string", "enum": ["possible", "partly", "buildable", "impossible"]],
            "answer": ["type": "string"],
            "turn_role": ["anyOf": [["type": "string", "enum": KnobSetup.TurnRole.allCases.map(\.rawValue)], ["type": "null"]]],
            "push_role": ["anyOf": [["type": "string", "enum": KnobSetup.PushRole.allCases.map(\.rawValue)], ["type": "null"]]],
            "needs": ["type": "string"],
        ],
        "required": ["verdict", "answer", "turn_role", "push_role", "needs"],
        "additionalProperties": false,
    ]

    /// One turn of the conversation: the whole history goes, Claude's answer comes back as a ChatTurn.
    static func ask(history: [ChatTurn], current: String, done: @escaping (ChatTurn) -> Void) {
        func fail(_ s: String) { done(ChatTurn(fromMarko: false, text: s)) }
        guard let (key, _) = Keys.current() else { fail("No Anthropic key. Open Settings (⌘,) and choose a key file; the README says how."); return }
        Models.resolve { model, why in
            guard let model else { fail("No model: \(why)."); return }
            let sys = system.replacingOccurrences(of: "{CATALOGUE}", with: catalogue()).replacingOccurrences(of: "{CURRENT}", with: current)
            let messages: [[String: Any]] = history.map { t in
                if t.fromMarko { return ["role": "user", "content": t.text] }
                // Claude's own earlier answers go back as the JSON it wrote, so it stays in the same shape
                let j: [String: Any] = ["verdict": t.verdict ?? "impossible", "answer": t.text, "turn_role": t.turnRole ?? NSNull(),
                                        "push_role": t.pushRole ?? NSNull(), "needs": t.needs ?? ""]
                let s = (try? JSONSerialization.data(withJSONObject: j)).flatMap { String(data: $0, encoding: .utf8) } ?? t.text
                return ["role": "assistant", "content": s]
            }
            let body: [String: Any] = [
                "model": model, "max_tokens": 16000, "system": sys, "messages": messages,
                "output_config": ["format": ["type": "json_schema", "schema": schema]],
            ]
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"; req.timeoutInterval = 300
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: req) { data, resp, err in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                guard code == 200, let json else {
                    let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? err?.localizedDescription ?? "no answer"
                    fail("Claude did not answer (\(code)): \(msg)"); return
                }
                if (json["stop_reason"] as? String) == "refusal" { fail("Claude declined this request."); return }
                let text = ((json["content"] as? [[String: Any]]) ?? []).filter { $0["type"] as? String == "text" }
                    .compactMap { $0["text"] as? String }.joined()
                guard let d = text.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                    fail(text.isEmpty ? "Claude's answer was empty." : text); return
                }
                // only roles the app knows survive (the catalogue is the law, not Claude)
                let turn = (a["turn_role"] as? String).flatMap { KnobSetup.TurnRole(rawValue: $0) }?.rawValue
                let push = (a["push_role"] as? String).flatMap { KnobSetup.PushRole(rawValue: $0) }?.rawValue
                done(ChatTurn(fromMarko: false, text: a["answer"] as? String ?? "", verdict: a["verdict"] as? String,
                              turnRole: turn, pushRole: push, needs: (a["needs"] as? String).flatMap { $0.isEmpty ? nil : $0 }))
            }.resume()
        }
    }
}
