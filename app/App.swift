// App.swift — DJ MANTRA ABLETON REMOTE for OXI E16 (Marko, 26.10.2026: "can you name this project DJ Mantra Ableton
// Remote for Oxi E16?"). The window: the sixteen knobs as on the device, the chosen knob's setup beside them, and
// CONNECT / GIVE BACK / PRESENT THE OXI / the saved setups along the top. The engine is Engine.swift.
import SwiftUI

let VERSION = 19

@main
struct DJMantraAbletonRemote: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup("DJ Mantra Ableton Remote for OXI E16 · v\(VERSION)") {
            Main().environmentObject(Delegate.engine)
                .frame(minWidth: 900, minHeight: 620)
        }
        // v18 (Marko, 26.10.2026: "I also need settings ... a file picker for the Anthropic key, and a way to choose the model")
        Settings { SettingsView() }
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    static let engine = Engine()
    func applicationDidFinishLaunching(_ n: Notification) {
        let e = Delegate.engine
        let args = CommandLine.arguments
        // --import FILE...: the same parser as Settings' file picker; --ask: a chat test, no window, the E16 left alone
        if let m = args.firstIndex(of: "--import") {
            print(Keys.importFiles(args[(m + 1)...].prefix { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) })); fflush(stdout)
            if !args.contains("--ask") { exit(0) }
        }
        if args.contains("--ask") { NSApp.setActivationPolicy(.prohibited); NSApp.windows.forEach { $0.orderOut(nil) } } else { e.connect() }
        // tests from the Mac: --profile automation loads the first profile, --help-page N shows that help page
        let a = CommandLine.arguments
        // a test from the Terminal, through the real chat code: --ask 3 "make this knob play and stop" [--family haiku]
        if let f = a.firstIndex(of: "--family"), f + 1 < a.count { Models.family = a[f + 1] }
        if let q = a.firstIndex(of: "--ask"), q + 2 < a.count, let n = Int(a[q + 1]) {
            let i = n - 1; let before = e.chats[i]?.count ?? 0; let t0 = Date()
            e.send(a[q + 2], knob: i)
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { t in
                guard e.asking == nil, (e.chats[i]?.count ?? 0) >= before + 2, let r = e.chats[i]?.last else { return }
                t.invalidate()
                print("[\(Models.resolved ?? Models.family)] \(String(format: "%.1f", Date().timeIntervalSince(t0))) s · \(r.verdict ?? "-") · turn \(r.turnRole ?? "-") · push \(r.pushRole ?? "-")\n  \(r.text)\n  needs: \(r.needs ?? "-")")
                fflush(stdout); exit(0)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if a.contains("--profile"), a.contains("automation") { e.liveAutomationProfile() }
            if let i = a.firstIndex(of: "--help-page"), i + 1 < a.count, let n = Int(a[i + 1]) { e.helpPage = n - 2; e.helpTurn(1) }
        }
    }
    // the E16 back to its scene when the app goes (otherwise it stays blank)
    func applicationWillTerminate(_ n: Notification) { Delegate.engine.giveBack() }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

private let orange = Color(red: 1, green: 0.58, blue: 0)
private let noteBlue = Color(red: 0.36, green: 0.72, blue: 1)

struct Main: View {
    @EnvironmentObject var e: Engine
    @State private var view = UserDefaults.standard.string(forKey: "view") ?? "knobs"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(e.connected ? "GIVE BACK" : "CONNECT") { e.connected ? e.giveBack() : e.connect() }
                Button(e.presenting ? "STOP THE SHOW" : "PRESENT THE OXI") { e.togglePresent() }.disabled(!e.connected)
                Button(e.statusLineOn ? "LIVE STATUS LINE: ON" : "LIVE STATUS LINE: OFF") { e.toggleStatusLine() }
                Spacer()
                TextField("setup", text: $e.setupName).frame(maxWidth: 180)
                Button("SAVE") { e.save() }
                Menu("RECALL") {
                    Button("AUTOMATION (the first profile)") { e.liveAutomationProfile() }
                    Divider()
                    ForEach(e.saved(), id: \.self) { n in Button(n) { e.recall(n) } }
                }.frame(maxWidth: 110)
            }
            Text(e.status).font(.system(.callout, design: .monospaced))
                .foregroundStyle(e.connected ? .green : .secondary).fixedSize(horizontal: false, vertical: true)
            // v15 (Marko, 26.10.2026: "Please make two views: same as an icon view, what is now, or list view")
            Picker("", selection: $view) { Text("KNOBS").tag("knobs"); Text("LIST").tag("list") }
                .pickerStyle(.segmented).frame(maxWidth: 220)
                .onChange(of: view) { _, v in UserDefaults.standard.set(v, forKey: "view") }
            HStack(alignment: .top, spacing: 14) {
                if view == "list" {
                    ScrollView { VStack(spacing: 6) { ForEach(0..<16, id: \.self) { i in KnobRow(i: i) } } }
                        .frame(minWidth: 460)
                } else {
                    Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(0..<4, id: \.self) { r in
                            GridRow { ForEach(0..<4, id: \.self) { c in KnobCell(i: r * 4 + c) } }
                        }
                    }
                    .frame(minWidth: 460)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $e.side) { Text("SETUP").tag("setup"); Text("CHAT").tag("chat") }
                        .pickerStyle(.segmented)
                    if e.side == "chat" { ChatView(i: e.selected) } else { Editor(i: e.selected) }
                }
                .frame(minWidth: 300, maxWidth: 400)
            }
            Text("Ableton Live: Settings → Link, Tempo & MIDI → MIDI Ports → Input \"DJ Mantra Remote\": Track and Remote on; then MIDI Map (⌘M) a control and turn the knob. Shift on the E16 shows the values on its screen and turns the knobs finer. Knob 16 is HELP: turning it reads a page for every knob on the E16\'s screen, pushing it leaves.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }
}

struct KnobCell: View {
    @EnvironmentObject var e: Engine
    let i: Int
    @State private var dragLast: [Int: Double] = [:]
    var body: some View {
        let k = e.knobs[i]
        let span = Double(max(1, k.high - k.low))
        let amount = (e.values[i] - Double(k.low)) / span
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.gray.opacity(0.25), lineWidth: 6)
                Circle().trim(from: 0, to: amount).stroke(k.colour.opacity(k.push == .off || e.pushed[i] ? 1 : 0.45),
                                                          style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(Int(e.values[i].rounded()))").font(.system(.body, design: .monospaced).bold())
            }
            .frame(width: 58, height: 58)
            Text(k.name).font(.system(.callout, design: .monospaced).bold()).lineLimit(1)
            // what it does, in full (Marko: "I want to see what the knobs do right on this screen")
            Text(e.turnText(i)).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            // the push in orange (Marko, 26.10.2026: "color code the push part. Put it in orange"); his note in blue
            Text(e.pushText(i)).font(.caption).foregroundStyle(orange).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !k.note.isEmpty { Text("“" + k.note + "”").font(.caption).italic().foregroundStyle(noteBlue).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).stroke(e.selected == i ? orange : Color.gray.opacity(0.3), lineWidth: e.selected == i ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { e.selected = i }
        // the mouse wheel on a knob turns it, as on the device; v4 (Marko, 26.10.2026: "two-way communication ... I can
        // also turn the knobs in this app"): so does a drag up or down; either way the E16's ring follows
        .onScrollWheel { dy in e.turn(i, by: dy) }
        .gesture(DragGesture(minimumDistance: 2).onChanged { g in
            let step = -(g.translation.height - dragLast[i, default: 0]) / 3
            if abs(step) >= 1 { e.turn(i, by: step.rounded()); dragLast[i] = g.translation.height }
        }.onEnded { _ in dragLast[i] = 0 })
    }
}

/// v15: a row of the LIST view: the knob's ring and name, Marko's own note, what it does.
struct KnobRow: View {
    @EnvironmentObject var e: Engine
    let i: Int
    var body: some View {
        let k = e.knobs[i]
        let span = Double(max(1, k.high - k.low))
        // v17 (Marko, 26.10.2026: "First is the function ... and then there is a knob, and then there is a note")
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(e.turnText(i)).font(.callout).fixedSize(horizontal: false, vertical: true)
                Text(e.pushText(i)).font(.callout).foregroundStyle(orange).fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle().stroke(Color.gray.opacity(0.25), lineWidth: 4)
                Circle().trim(from: 0, to: (e.values[i] - Double(k.low)) / span).stroke(k.colour, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(i + 1)").font(.system(.caption, design: .monospaced).bold())
            }
            .frame(width: 34, height: 34)
            Text(k.name).font(.system(.body, design: .monospaced).bold()).frame(width: 52, alignment: .leading)
            // v18 (Marko, 26.10.2026: "Where my notes are now, show the prompt instead"): what the knob should do, in his
            // words; Return sends it to Claude, whose answer opens in the CHAT beside the knobs
            TextField("prompt: what should this knob do?", text: Binding(get: { e.knobs[i].note }, set: { e.knobs[i].note = $0; e.save() }), axis: .vertical)
                .textFieldStyle(.roundedBorder).foregroundStyle(noteBlue).frame(minWidth: 160, maxWidth: 240)
                .onSubmit { e.selected = i; e.side = "chat"; e.send(e.knobs[i].note, knob: i) }
            Spacer(minLength: 0)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8).stroke(e.selected == i ? orange : Color.gray.opacity(0.3), lineWidth: e.selected == i ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { e.selected = i }
        .onScrollWheel { dy in e.turn(i, by: dy) }
    }
}

struct Editor: View {
    @EnvironmentObject var e: Engine
    let i: Int
    var body: some View {
        let b = Binding(get: { e.knobs[i] }, set: { e.knobs[i] = $0; e.edited() })
        Form {
            Section("KNOB \(i + 1)") {
                TextField("Name (4 on the screen)", text: Binding(get: { b.wrappedValue.name }, set: { b.wrappedValue.name = String($0.prefix(4)).uppercased() }))
                ColorPicker("Colour", selection: Binding(get: { b.wrappedValue.colour }, set: { c in
                    let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
                    b.wrappedValue.r = Double(n.redComponent); b.wrappedValue.g = Double(n.greenComponent); b.wrappedValue.b = Double(n.blueComponent)
                }), supportsOpacity: false)
            }
            Section("TURN") {
                Picker("In Live", selection: b.turnRole) { ForEach(KnobSetup.TurnRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Stepper("CC \(b.wrappedValue.cc)", value: b.cc, in: 0...127)
                Stepper("Channel \(b.wrappedValue.channel)", value: b.channel, in: 1...16)
                Stepper("From \(b.wrappedValue.low)", value: b.low, in: 0...126)
                Stepper("To \(b.wrappedValue.high)", value: b.high, in: 1...127)
                Picker("Speed", selection: b.speed) { Text("½").tag(0.5); Text("1").tag(1.0); Text("2").tag(2.0); Text("4").tag(4.0) }
            }
            Section("PUSH") {
                Picker("In Live", selection: b.pushRole) { ForEach(KnobSetup.PushRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Does", selection: b.push) { ForEach(KnobSetup.Push.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Sends", selection: b.pushKind) { ForEach(KnobSetup.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Stepper("\(b.wrappedValue.pushKind.rawValue) \(b.wrappedValue.pushNumber)", value: b.pushNumber, in: 0...127)
                Stepper("Channel \(b.wrappedValue.pushChannel)", value: b.pushChannel, in: 1...16)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - the mouse wheel on a view (SwiftUI has none on macOS 14)

private struct ScrollCatcher: NSViewRepresentable {
    let onScroll: (Double) -> Void
    func makeNSView(context: Context) -> NSView { let v = WheelView(); v.onScroll = onScroll; return v }
    func updateNSView(_ v: NSView, context: Context) { (v as? WheelView)?.onScroll = onScroll }
    final class WheelView: NSView {
        var onScroll: ((Double) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let d = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.25 : 1)
            if d != 0 { onScroll?(Double(d)) }
        }
    }
}

extension View {
    func onScrollWheel(_ f: @escaping (Double) -> Void) -> some View { overlay(ScrollCatcher(onScroll: f)) }
}

// MARK: - v18: the chat with Claude for the chosen knob (Chat.swift)

private let readme = URL(string: "https://github.com/markoboskoauroville/oxi-controller#the-anthropic-key-and-the-chat")!

struct ChatView: View {
    @EnvironmentObject var e: Engine
    let i: Int
    @State private var draft = ""
    var body: some View {
        let turns = e.chats[i] ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("KNOB \(i + 1) · \(e.knobs[i].name)").font(.system(.callout, design: .monospaced).bold())
                Spacer()
                Button("SEND PROMPT") { e.send(e.knobs[i].note, knob: i) }.disabled(e.knobs[i].note.isEmpty || e.asking != nil)
                Button("CLEAR") { e.clearChat(i) }.disabled(turns.isEmpty)
            }
            ScrollViewReader { sv in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if turns.isEmpty {
                            Text("Write what this knob should do in its prompt (LIST view) and press Return, or write here. Claude says whether the app can do it, applies nothing by itself, and says what the app would need when it cannot.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(turns) { t in Bubble(t: t, i: i).id(t.id) }
                        if e.asking == i { Text("Claude is thinking…").font(.caption).foregroundStyle(.secondary).id("wait") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: turns.count) { _, _ in if let l = turns.last { sv.scrollTo(l.id, anchor: .bottom) } }
            }
            HStack {
                TextField("answer Claude…", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder)
                    .onSubmit { e.send(draft, knob: i); draft = "" }
                Button("SEND") { e.send(draft, knob: i); draft = "" }.disabled(draft.isEmpty || e.asking != nil)
            }
        }
    }
}

private struct Bubble: View {
    @EnvironmentObject var e: Engine
    let t: ChatTurn
    let i: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if t.fromMarko {
                Text(t.text).foregroundStyle(noteBlue)
            } else {
                if let v = t.verdict {
                    // v19 (Marko, 26.10.2026: zoom was called impossible "but it is possible"): NOT YET is not IMPOSSIBLE
                    Text(v == "buildable" ? "NOT YET · CAN BE BUILT" : v.uppercased()).font(.caption.bold())
                        .foregroundStyle(v == "possible" ? .green : v == "partly" ? .yellow : v == "buildable" ? orange : .red)
                }
                Text(t.text)
                if let n = t.needs { Text("To make it possible: " + n).font(.caption).foregroundStyle(.secondary) }
                if t.turnRole != nil || t.pushRole != nil {
                    HStack {
                        Text([t.turnRole.map { "TURN: " + $0 }, t.pushRole.map { "PUSH: " + $0 }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption.monospaced()).foregroundStyle(orange)
                        Button(t.applied ? "APPLIED" : "APPLY") { e.apply(t, knob: i) }.disabled(t.applied)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(t.fromMarko ? Color.blue.opacity(0.08) : Color.gray.opacity(0.10)))
    }
}

// MARK: - v18: Settings (⌘,): the Anthropic key by file picker, the model (MANTRA_MANIFEST keyring.md §6b, model-names.md)

struct SettingsView: View {
    @State private var keys = Keys.saved()
    @State private var active = Keys.activeIndex
    @State private var said = ""
    @State private var inForce = Keys.current()?.from ?? "none"
    @State private var family = Models.family
    @State private var model = ""
    var body: some View {
        Form {
            Section("ANTHROPIC KEY") {
                HStack {
                    Button("Choose key files…") { pick() }
                    Link("How the key is found (README)", destination: readme)
                }
                if !said.isEmpty { Text(said).font(.caption).fixedSize(horizontal: false, vertical: true) }
                if keys.isEmpty {
                    Text("No key picked. The app then looks, in order, at ANTHROPIC_API_KEY, `keyring get anthropic` and the notes in ~/Downloads/API.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("In force", selection: $active) {
                        ForEach(keys.indices, id: \.self) { n in
                            Text("Anthropic · key \(n + 1) of \(keys.count)" + (keys[n].title.isEmpty ? "" : " · \(keys[n].title)") + " · \(keys[n].source)").tag(n)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .onChange(of: active) { _, v in Keys.activeIndex = v; Models.resolved = nil; refresh() }
                    Button("Remove the key in force") {
                        var k = keys; k.remove(at: min(active, k.count - 1)); Keys.save(k); Keys.activeIndex = 0; refresh()
                    }
                }
                Text("In use now: \(inForce)").font(.caption)
            }
            Section("MODEL") {
                Picker("Family", selection: $family) {
                    Text("Opus (the most careful)").tag("opus"); Text("Sonnet").tag("sonnet"); Text("Haiku (the fastest, cheapest)").tag("haiku")
                }
                .onChange(of: family) { _, v in Models.family = v; resolve() }
                Text(model.isEmpty ? "asking the API…" : "Works with \(model)").font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .onAppear { resolve() }
    }
    private func refresh() { keys = Keys.saved(); active = min(Keys.activeIndex, max(0, keys.count - 1)); inForce = Keys.current()?.from ?? "none" }
    private func resolve() { model = ""; Models.resolve { m, why in DispatchQueue.main.async { model = m == nil ? why : why } } }
    private func pick() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.canChooseDirectories = false
        p.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/API")
        p.message = "Choose the notes that hold your Anthropic keys (other text in them is fine)"
        if p.runModal() == .OK { said = Keys.importFiles(p.urls); Models.resolved = nil; refresh(); resolve() }
    }
}
