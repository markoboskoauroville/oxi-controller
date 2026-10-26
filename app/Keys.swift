// Keys.swift — the Anthropic key, the Mantra way (MANTRA_MANIFEST modules/keyring.md; Marko, 26.10.2026: "please
// check the Mantra Manifest for how we read and parse keys. I would rather you follow that than invent something new").
//
//   §4/§10d  THE PARSER     a key file is a working note: split into blocks on blank lines, the key found by SHAPE
//                           (Anthropic: sk-ant-…), the title by elimination (the block's other words, every key shape
//                           stripped from it); everything else in the file is left alone; duplicates dropped
//   §6b      A FILE PICKER  several files at once; a sentence back ("2 Anthropic keys, 1 with a title; not used by
//                           this app: 3 Gemini"); several keys, one in force by a radio; titles shown, keys never
//   §11      THE ORDER      the environment (ANTHROPIC_API_KEY), a 0600 file in this app's data folder (the keys
//                           picked), `keyring get anthropic`; on this Mac then ~/Downloads/API (the usual fallback)
//   §10d     NO KEY IN A LOG, a key is named by its position: "key 2 of 3"
import AppKit
import Foundation

struct AnthropicKey: Equatable {
    var title: String
    var key: String
    var source: String          // where it came from, for the sentence and the list (never the key)
}

enum Keys {
    static let anthropic = try! NSRegularExpression(pattern: #"sk-ant-[A-Za-z0-9_\-]{20,}"#)
    /// The other providers' shapes, only to count what the app has no use for (keyring.md §4).
    static let others: [(String, NSRegularExpression)] = [
        ("Gemini", try! NSRegularExpression(pattern: #"AQ\.[A-Za-z0-9_\-.]{20,}"#)),
        ("Google", try! NSRegularExpression(pattern: #"AIza[A-Za-z0-9_\-]{30,}"#)),
        ("Groq", try! NSRegularExpression(pattern: #"gsk_[A-Za-z0-9]{20,}"#)),
        ("Speechify", try! NSRegularExpression(pattern: #"\bsk_[A-Za-z0-9]{30,}"#)),
        ("GitHub", try! NSRegularExpression(pattern: #"(ghp_|github_pat_)[A-Za-z0-9_]{20,}"#)),
    ]

    static let dataDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DJ Mantra Ableton Remote", isDirectory: true)
    static let store = dataDir.appendingPathComponent("keys.txt")          // keyring v1, 0600

    private static func matches(_ re: NSRegularExpression, _ s: String) -> [String] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    /// Every Anthropic key in a note, with its title; and how many keys of other providers it held.
    static func parse(_ text: String, source: String) -> (keys: [AnthropicKey], others: [String: Int]) {
        var found: [AnthropicKey] = []
        var counts: [String: Int] = [:]
        // the keyring v1 format first (provider: / label: / key:), then any note, block by block
        let blocks = text.components(separatedBy: CharacterSet.newlines).split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        for block in blocks {
            let lines = block.map { $0.trimmingCharacters(in: .whitespaces) }
            let joined = lines.joined(separator: "\n")
            for (name, re) in others { let n = matches(re, joined).count; if n > 0 { counts[name, default: 0] += n } }
            let keys = matches(anthropic, joined)
            guard !keys.isEmpty else { continue }
            var title = lines.first(where: { $0.lowercased().hasPrefix("label:") }).map { String($0.dropFirst(6)) } ?? ""
            if title.isEmpty {
                // by elimination: the first line that is not only a key, with every key shape taken out of it
                title = lines.lazy.map { line -> String in
                    var t = line
                    for k in matches(anthropic, t) { t = t.replacingOccurrences(of: k, with: "") }
                    for (_, re) in others { for k in matches(re, t) { t = t.replacingOccurrences(of: k, with: "") } }
                    for p in ["provider:", "key:", "api key", "API key"] { t = t.replacingOccurrences(of: p, with: "") }
                    return t.trimmingCharacters(in: CharacterSet(charactersIn: " :=-\t\"'"))
                }.first(where: { !$0.isEmpty && $0.lowercased() != "anthropic" }) ?? ""
            }
            for k in keys { found.append(AnthropicKey(title: title.trimmingCharacters(in: .whitespaces), key: k, source: source)) }
        }
        return (found, counts)
    }

    // MARK: the store (keys picked in Settings), keyring v1, 0600

    static func saved() -> [AnthropicKey] {
        guard let t = try? String(contentsOf: store, encoding: .utf8) else { return [] }
        return parse(t, source: "picked").keys
    }

    static func save(_ keys: [AnthropicKey]) {
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        var out = "# keyring v1\n# DJ Mantra Ableton Remote, \(keys.count) entries\n"
        for k in keys { out += "\nprovider: anthropic\nlabel: \(k.title)\nkey: \(k.key)\n" }
        FileManager.default.createFile(atPath: store.path, contents: Data(out.utf8), attributes: [.posixPermissions: 0o600])
    }

    /// Files picked: parsed, merged (duplicates dropped), stored; the sentence back.
    static func importFiles(_ urls: [URL]) -> String {
        var all = saved()
        var sentences: [String] = []
        for u in urls {
            guard let data = try? Data(contentsOf: u), let text = String(data: data, encoding: .utf8) else {
                sentences.append("\(u.lastPathComponent): not a text file"); continue
            }
            let (keys, others) = parse(text, source: u.lastPathComponent)
            let fresh = keys.filter { k in !all.contains(where: { $0.key == k.key }) }
            all += fresh
            var s = "\(u.lastPathComponent): "
            s += keys.isEmpty ? "no Anthropic key found in it" : "\(fresh.count) Anthropic key\(fresh.count == 1 ? "" : "s") added (\(keys.filter { !$0.title.isEmpty }.count) with a title)"
            if keys.count > fresh.count { s += ", \(keys.count - fresh.count) already known" }
            if !others.isEmpty { s += "; not used by this app: " + others.map { "\($0.value) \($0.key)" }.joined(separator: ", ") }
            sentences.append(s)
        }
        save(all)
        return sentences.joined(separator: ". ")
    }

    // MARK: the key in force, in the manifest's order

    static var activeIndex: Int {
        get { UserDefaults.standard.integer(forKey: "activeKey") }
        set { UserDefaults.standard.set(newValue, forKey: "activeKey") }
    }

    /// The key to use now and a sentence saying where it came from (never the key).
    static func current() -> (key: String, from: String)? {
        if let k = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !k.isEmpty { return (k, "the environment (ANTHROPIC_API_KEY)") }
        let picked = saved()
        if !picked.isEmpty {
            let i = min(max(0, activeIndex), picked.count - 1)
            let k = picked[i]
            return (k.key, "key \(i + 1) of \(picked.count)" + (k.title.isEmpty ? "" : ", \(k.title)") + " (picked)")
        }
        for path in ["/opt/homebrew/bin/keyring", "/usr/local/bin/keyring", NSHomeDirectory() + "/.local/bin/keyring"] where FileManager.default.isExecutableFile(atPath: path) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = ["get", "anthropic"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            if (try? p.run()) != nil { p.waitUntilExit()
                let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if let k = matches(anthropic, s).first { return (k, "keyring get anthropic") }
            }
        }
        // the usual fallback on this Mac: the API folder's notes, by shape
        let api = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/API")
        let files = ((try? FileManager.default.contentsOfDirectory(at: api, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["txt", "md", ""].contains($0.pathExtension.lowercased()) }
            .sorted { a, b in   // the files named for Claude first
                let ka = a.lastPathComponent.lowercased().contains("claude") || a.lastPathComponent.lowercased().contains("anthropic")
                let kb = b.lastPathComponent.lowercased().contains("claude") || b.lastPathComponent.lowercased().contains("anthropic")
                return ka && !kb
            }
        for f in files {
            guard let t = try? String(contentsOf: f, encoding: .utf8), let k = parse(t, source: f.lastPathComponent).keys.first else { continue }
            return (k.key, "\(f.lastPathComponent) in ~/Downloads/API")
        }
        return nil
    }
}

/// The model by family, never a fixed version (MANTRA_MANIFEST modules/model-names.md): the newest model of the
/// family chosen in Settings, asked of the API once a session (GET /v1/models).
enum Models {
    static let families = ["opus", "sonnet", "haiku"]
    static var family: String {
        get { UserDefaults.standard.string(forKey: "modelFamily") ?? "opus" }
        set { UserDefaults.standard.set(newValue, forKey: "modelFamily"); resolved = nil }
    }
    static var resolved: String?

    /// The newest model id of the family, from the API's own list; nil (with the reason) when it cannot be asked.
    static func resolve(completion: @escaping (String?, String) -> Void) {
        if let r = resolved { completion(r, "\(r) (newest \(family))"); return }
        guard let (key, _) = Keys.current() else { completion(nil, "no Anthropic key: pick a key file in Settings"); return }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                completion(nil, err.map { "the API did not answer: \($0.localizedDescription)" } ?? "the API answered \(code)"); return
            }
            // newest first: the list comes newest first; take the first id that names the family
            let fam = family
            if let id = list.compactMap({ $0["id"] as? String }).first(where: { $0.contains(fam) }) {
                resolved = id; completion(id, "\(id) (newest \(fam))")
            } else { completion(nil, "no \(fam) model in the API's list") }
        }.resume()
    }
}
