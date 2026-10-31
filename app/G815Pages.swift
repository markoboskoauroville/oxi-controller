// v38 (Marko, 31.10.2026: "I just don't see in the user interface that it's active. Please show that it's active, and when I
// press the button, it needs to light up in the user interface of the E16 for DaVinci Resolve"): the G815's G1–G5 open
// Resolve's pages (G815 Lights v24+, in the page bar's order). This window shows them: G1 … G5 with the page each one opens,
// read from Resolve's page bar through Accessibility; the page Resolve is on lit (resolve.GetCurrentPage through the
// router, once a second); the key G815 Lights says was pressed (distributed notification community.auroville.g815.gkey)
// flashes white for 0.8 s.
import AppKit
import ApplicationServices
import SwiftUI

final class G815Pages: ObservableObject {
    static let shared = G815Pages()
    @Published var pages: [String] = []
    @Published var current = ""
    @Published var flashKey = 0
    @Published var flashAt = Date.distantPast
    private var timer: Timer?

    init() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("community.auroville.g815.gkey"), object: nil, queue: .main) { [weak self] n in
            guard let self, let k = n.userInfo?["key"] as? Int else { return }
            self.flashKey = k; self.flashAt = Date()
            if let p = n.userInfo?["page"] as? String { self.current = p.lowercased() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async {
            let bar = G815Pages.pageBar()
            var req = URLRequest(url: URL(string: "http://127.0.0.1:8940/run")!)
            req.httpMethod = "POST"; req.timeoutInterval = 2
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["who": "e16", "code": "result = resolve.GetCurrentPage()", "timeout": 2])
            URLSession.shared.dataTask(with: req) { d, _, _ in
                let cur = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["result"] as? String
                DispatchQueue.main.async {
                    if !bar.isEmpty, bar != self.pages { self.pages = bar }
                    if let c = cur, c != self.current { self.current = c }
                }
            }.resume()
        }
    }

    static let names: Set<String> = ["Media", "Photo", "Cut", "Edit", "Fusion", "Color", "Fairlight", "Deliver"]
    private static func attr(_ e: AXUIElement, _ a: String) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil }
    /// Resolve's page bar, left to right (the same reading as G815 Lights)
    static func pageBar() -> [String] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.blackmagic-design.DaVinciResolve").first else { return [] }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var found: [(String, CGFloat)] = []
        func walk(_ e: AXUIElement, _ d: Int) {
            if d > 25 || found.count >= 8 { return }
            if (attr(e, kAXRoleAttribute) as? String) == "AXCheckBox",
               let t = (attr(e, kAXDescriptionAttribute) as? String) ?? (attr(e, kAXTitleAttribute) as? String), names.contains(t) {
                var p = CGPoint.zero; if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
                found.append((t, p.x))
            }
            for c in (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(c, d + 1) }
        }
        if let main = attr(ax, kAXMainWindowAttribute) { walk(main as! AXUIElement, 0) }
        return found.sorted { $0.1 < $1.1 }.map { $0.0 }
    }
}

/// the row in E16 FOR DAVINCI RESOLVE's window: G815  G1 MEDIA  G2 PHOTO  G3 CUT  G4 EDIT  G5 FUSION
struct G815Row: View {
    @ObservedObject var g = G815Pages.shared
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            HStack(spacing: 8) {
                Text("G815").font(.callout.bold()).frame(width: 52, alignment: .leading)
                ForEach(0..<5, id: \.self) { i in
                    let name = i < g.pages.count ? g.pages[i] : "—"
                    let on = name.lowercased() == g.current
                    let flash = g.flashKey == i + 1 && ctx.date.timeIntervalSince(g.flashAt) < 0.8
                    Text("G\(i + 1) \(name.uppercased())").font(.system(.callout, design: .monospaced).bold())
                        .foregroundStyle(flash || on ? .black : .primary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(flash ? Color.white : on ? Color.orange : Color.gray.opacity(0.2)))
                }
                Text(g.pages.count > 5 ? "+\(g.pages.count - 5) more pages: hide some to reach them" : "")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
