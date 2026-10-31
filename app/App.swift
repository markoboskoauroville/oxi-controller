// App.swift — DJ MANTRA ABLETON REMOTE for OXI E16 (Marko, 26.10.2026: "can you name this project DJ Mantra Ableton
// Remote for Oxi E16?"). The window: the sixteen knobs as on the device, the chosen knob's setup beside them, and
// CONNECT / GIVE BACK / PRESENT THE OXI / the saved setups along the top. The engine is Engine.swift.
import SwiftUI
import ApplicationServices

let VERSION = 38

@main
struct DJMantraAbletonRemote: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        // v28: the Resolve copy says so in its title (Marko: "I don't know where I can control this ... for DaVinci Resolve")
        WindowGroup((Bundle.main.bundleIdentifier ?? "").lowercased().contains("resolve")
                    ? "E16 for DaVinci Resolve · v\(VERSION) · LEDs brightness at the top"
                    : "E16 Ableton Remote · v\(VERSION)") {
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
        // v27: E16 FOR DAVINCI RESOLVE: the same app as its own bundle (or --resolve): the Resolve mixer, page 1 = A1–A4
        if args.contains("--resolve") || (Bundle.main.bundleIdentifier ?? "").lowercased().contains("resolve") {
            e.resolveMode = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { e.resolveRefresh() }
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in if e.resolveMode, !e.navMode { e.resolveRefresh() } }
        }
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
    // v31: the ✕ closes the window only, the app stays ON (OFF quits); the Dock or the star opens the window again
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { false }
}

private let orange = Color(red: 1, green: 0.58, blue: 0)
private let noteBlue = Color(red: 0.36, green: 0.72, blue: 1)
private let amber = Color(red: 0xE8/255, green: 0xA3/255, blue: 0x3D/255)

// v29: the permissions the Ableton remote uses: Accessibility (the knob under the mouse posts drags and Live's key A to
// Live, Live.swift). The Resolve copy uses none, so its window shows no word. Never asked at --login.
enum Permissions {
    static let needed = ["Accessibility"]
    static func allowed(_ p: String) -> Bool {
        switch p {
        case "Accessibility": return AXIsProcessTrusted()
        default: return true
        }
    }
    static var missing: [String] { needed.filter { !allowed($0) } }
    // the system's own request once (it puts the app in the list), then the page of the first one missing
    static func openMissing() {
        guard let p = missing.first else { return }
        if p == "Accessibility" { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + p)!)
    }
}

struct Main: View {
    @EnvironmentObject var e: Engine
    @State private var view = UserDefaults.standard.string(forKey: "view") ?? "knobs"
    @State private var showProfiles = false
    @State private var permOK = Permissions.missing.isEmpty   // v29: read every 2 s, set only when it changed
    /// v28 (Marko, 29.10.2026: "You open E16 for DaVinci Resolve, and inside are the settings from Ableton Live"):
    /// the Resolve copy shows only the Resolve mixer.
    var body: some View {
        // v31: the first row of every app, ON OFF … name … TOP PERMISSIONS ✕ (Marko, 31.10.2026)
        VStack(spacing: 0) {
            TopRow(name: e.resolveMode ? "E16 for DaVinci Resolve" : "E16 Ableton Remote",
                   permissions: !e.resolveMode && !permOK)
            if e.resolveMode { ResolveWindow() } else { ableton }
        }
    }
    var ableton: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(e.connected ? "GIVE BACK" : "CONNECT") { e.connected ? e.giveBack() : e.connect() }
                Button(e.presenting ? "STOP THE SHOW" : "PRESENT THE OXI") { e.togglePresent() }.disabled(!e.connected)
                Button(e.statusLineOn ? "LIVE STATUS LINE: ON" : "LIVE STATUS LINE: OFF") { e.toggleStatusLine() }
                // v28: the brightness of every LED ring on the E16
                Text("LEDs").font(.caption.bold())
                Slider(value: $e.ledBrightness, in: 0.05...1).frame(width: 140)
                Text("\(Int((e.ledBrightness * 100).rounded())) %").font(.caption.monospaced()).frame(width: 40)
                Spacer()
                // v24: a profile is saved from the page(s) it sits on, and placed on pages in PROFILES
                TextField("profile", text: $e.setupName).frame(maxWidth: 180)
                Button("SAVE PROFILE") { e.save() }
                Button("PROFILES…") { showProfiles = true }
                // v29's PERMISSIONS moved in v31 to the first row (TopRow), beside TOP and ✕
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                let p = Permissions.missing.isEmpty; if p != permOK { permOK = p }
            }
            Text(e.status).font(.system(.callout, design: .monospaced))
                .foregroundStyle(e.connected ? .green : .secondary).fixedSize(horizontal: false, vertical: true)
            // v21 (Marko, 26.10.2026: "make this application on macOS have next page, next page, next page, until we
            // come to the end of all the knobs"); on the E16: Shift + knob 16
            HStack(spacing: 8) {
                Button("◀ PAGE") { e.goTo(page: e.page - 1) }.disabled(e.page == 0)
                Text(e.pageLine()).font(.system(.callout, design: .monospaced).bold()).foregroundStyle(orange)
                Button("PAGE ▶") { e.goTo(page: e.page + 1) }.disabled(e.page == KnobSetup.pageCount - 1)
                Button("FIRST") { e.goTo(page: 0) }.disabled(e.page == 0)
                // v24: the page's own name (shown on the E16 when you choose pages)
                TextField("page name", text: Binding(get: { e.pageName(e.page) }, set: { e.setPageName($0) })).frame(maxWidth: 160)
            }
            // v15 (Marko, 26.10.2026: "Please make two views: same as an icon view, what is now, or list view")
            Picker("", selection: $view) { Text("KNOBS").tag("knobs"); Text("LIST").tag("list") }
                .pickerStyle(.segmented).frame(maxWidth: 220)
                .onChange(of: view) { _, v in UserDefaults.standard.set(v, forKey: "view") }
            HStack(alignment: .top, spacing: 14) {
                if view == "list" {
                    ScrollView { VStack(spacing: 6) {
                        HStack {
                            Text("TURN").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                            Text("PUSH").foregroundStyle(orange).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                            Text("KNOB").frame(width: 96, alignment: .leading)
                            Text("PROMPT").foregroundStyle(noteBlue).frame(minWidth: 160, maxWidth: 240, alignment: .leading)
                        }
                        .font(.caption.bold()).padding(.horizontal, 6)
                        ForEach(0..<16, id: \.self) { i in KnobRow(i: i) }
                    } }
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
            Text("Ableton Live: Settings → Link, Tempo & MIDI → MIDI Ports → Input \"DJ Mantra Remote\": Track and Remote on; then MIDI Map (⌘M) a control and turn or push the knob, and write what it does with ✎. Every knob has its own numbers: knob 1 is CC 1 and note 1, knob 16 is CC 16 and note 16, the next page goes on from 17, channel 1 up to 112, then channel 2. Shift on the E16 shows the values and turns the knobs finer; Tap Shift twice to choose a page: knobs 1–15 jump to their page, knob 16 turns one page on or back; tap Shift twice again to play.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .sheet(isPresented: $showProfiles) { ProfilesView().environmentObject(e) }
    }
}

// ---------------------------------------------------------------- the first row (v31)
// Marko, 31.10.2026: "Each needs to have the same user interface elements. On, off and top. Please build it in every
// application." MANTRA_MANIFEST swift-apps.md, "The first row of every app": ON (green) OFF (grey: quits; the E16 goes
// back to its scene in applicationWillTerminate), the app's name centred, TOP (green: the window floats above every
// other window; UserDefaults "onTop", applied at launch), PERMISSIONS only while one is missing, ✕ closes the window.
private let rowGreen = Color(red: 0x33/255, green: 0xD1/255, blue: 0x7A/255)
private let rowGrey = Color(red: 0x7A/255, green: 0x80/255, blue: 0x87/255)

struct TopRow: View {
    let name: String
    let permissions: Bool
    @AppStorage("onTop") private var onTop = false
    var body: some View {
        ZStack {
            Text(name).font(.system(size: 13, weight: .bold)).lineLimit(1)
            HStack(spacing: 10) {
                Text("ON").foregroundStyle(rowGreen)
                Text("OFF").foregroundStyle(rowGrey)
                    .contentShape(Rectangle()).onTapGesture { NSApp.terminate(nil) }
                    .axButton("Off", id: "off") { DispatchQueue.main.async { NSApp.terminate(nil) } }
                    .help("Switch the app off: the E16 goes back to its own scene, then the app quits")
                Spacer()
                Text("TOP").foregroundStyle(onTop ? rowGreen : rowGrey)
                    .contentShape(Rectangle()).onTapGesture { onTop.toggle(); TopRow.float(onTop) }
                    .axButton("Top", id: "top", value: onTop ? "on" : "off") { onTop.toggle(); TopRow.float(onTop) }
                    .help("Always on top: green, the window stays above every other window")
                if permissions {
                    Text("PERMISSIONS").foregroundStyle(amber)
                        .contentShape(Rectangle()).onTapGesture { Permissions.openMissing() }
                        .axButton("Permissions", id: "permissions") { Permissions.openMissing() }
                        .help("Accessibility is off: the knob under the mouse cannot turn Live's controls. This opens its page in System Settings")
                }
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(rowGrey)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
                    .onTapGesture { NSApp.keyWindow?.performClose(nil) }
                    .axButton("Close window", id: "close") { (NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible && TopRow.ours($0) })?.performClose(nil) }
                    .help("Close the window (the app stays on)")
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 14).frame(height: 32)
        .onAppear { DispatchQueue.main.async { TopRow.float(onTop) } }
    }
    static func ours(_ w: NSWindow) -> Bool { w.title.hasPrefix("E16 Ableton Remote") || w.title.hasPrefix("DJ Mantra Ableton Remote") || w.title.hasPrefix("E16 for DaVinci Resolve") }
    static func float(_ on: Bool) { for w in NSApp.windows where ours(w) { w.level = on ? .floating : .normal } }
}

extension View {
    // every control an Accessibility button (MANTRA_MANIFEST swift-apps.md, "Accessibility built in", 31.10.2026)
    func axButton(_ label: String, id: String, value: String? = nil, _ action: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .accessibilityValue(value ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}

/// v24 (Marko, 26.10.2026: "Each profile can be assigned to the range of pages ... in the setting of each profile, so
/// that I can assign it the fixed page inside the device"): every saved profile, where it sits, and PLACE.
struct ProfilesView: View {
    @EnvironmentObject var e: Engine
    @Environment(\.dismiss) private var dismiss
    @State private var at: [String: Int] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROFILES ON THE E16").font(.headline)
            Text("A profile is a saved set of knobs, one page or several. PLACE puts it on the E16 from the page you choose; those pages carry its name, and the E16 keeps them: tap Shift twice, push the page's knob, and play. Everything placed is kept by the app and comes back at its next start.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(e.saved(), id: \.self) { n in
                let count = e.profilePages(n).count
                HStack(spacing: 10) {
                    Text(n).font(.system(.body, design: .monospaced).bold()).frame(minWidth: 140, alignment: .leading)
                    Text(count == 1 ? "1 page" : "\(count) pages").font(.caption).frame(width: 60, alignment: .leading)
                    Text(e.placedAt(n).map { "now on page " + $0 } ?? "not on the E16").font(.caption)
                        .foregroundStyle(e.placedAt(n) == nil ? .secondary : .primary).frame(width: 130, alignment: .leading)
                    Stepper("page \(at[n, default: e.page] + 1)" + (count > 1 ? "–\(at[n, default: e.page] + count)" : ""),
                            value: Binding(get: { at[n, default: e.page] }, set: { at[n] = $0 }), in: 0...(KnobSetup.pageCount - count))
                        .frame(width: 150)
                    Button("PLACE") { e.place(n, at: at[n, default: e.page]) }
                }
            }
            Divider()
            HStack {
                Button("AUTOMATION as it came (on page 1)") { e.liveAutomationProfile() }
                Spacer()
                Button("DONE") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16).frame(minWidth: 620)
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
            // v21 (Marko, 26.10.2026: "an edit button next to the description of the knob and the push ... a turn
            // column and a push column. You fill them in, but the user can overwrite them")
            OwnWords(i: i, push: false).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            OwnWords(i: i, push: true).frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle().stroke(Color.gray.opacity(0.25), lineWidth: 4)
                Circle().trim(from: 0, to: (e.values[i] - Double(k.low)) / span).stroke(k.colour, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                Text("\(e.knobs[i].cc)").font(.system(.caption, design: .monospaced).bold())
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
            Section("KNOB \(i + 1) · PAGE \(e.page + 1) · CC and note \(b.wrappedValue.cc), channel \(b.wrappedValue.channel)") {
                // v22: the E16's screen shows two lines under each knob, five letters each
                TextField("Screen, turn line (5)", text: Binding(get: { b.wrappedValue.name }, set: { b.wrappedValue.name = String($0.prefix(5)).uppercased() }))
                TextField("Screen, push line (5)", text: Binding(get: { b.wrappedValue.pushName }, set: { b.wrappedValue.pushName = String($0.prefix(5)).uppercased() }), prompt: Text(b.wrappedValue.screenLines.1))
            }
            // v21 (Marko, 26.10.2026: "a color picker with all the available colors, so the user can adjust the color and
            // the intensity of the ring"): the palette, any colour beside it, and the ring's brightness
            Section("RING") {
                RingPalette(knob: b)
                ColorPicker("Any colour", selection: Binding(get: { b.wrappedValue.colour }, set: { c in
                    let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
                    b.wrappedValue.r = Double(n.redComponent); b.wrappedValue.g = Double(n.greenComponent); b.wrappedValue.b = Double(n.blueComponent)
                }), supportsOpacity: false)
                HStack {
                    Text("Intensity")
                    Slider(value: Binding(get: { b.wrappedValue.intensity }, set: { b.wrappedValue.intensity = $0 }), in: 0.1...1)
                    Text("\(Int((b.wrappedValue.intensity * 100).rounded())) %").font(.caption.monospaced()).frame(width: 44)
                }
                Circle().fill(b.wrappedValue.colour.opacity(0.25 + 0.75 * b.wrappedValue.intensity)).frame(width: 28, height: 28)
            }
            Section("TURN") {
                Picker("In Live", selection: b.turnRole) { ForEach(KnobSetup.TurnRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Text("Sends CC \(b.wrappedValue.cc) on channel \(b.wrappedValue.channel)").font(.caption)
                Stepper("From \(b.wrappedValue.low)", value: b.low, in: 0...126)
                Stepper("To \(b.wrappedValue.high)", value: b.high, in: 1...127)
                Picker("Speed", selection: b.speed) { Text("½").tag(0.5); Text("1").tag(1.0); Text("2").tag(2.0); Text("4").tag(4.0) }
            }
            Section("PUSH") {
                Picker("In Live", selection: b.pushRole) { ForEach(KnobSetup.PushRole.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Does", selection: b.push) { ForEach(KnobSetup.Push.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Text("Sends note \(b.wrappedValue.pushNumber) on channel \(b.wrappedValue.pushChannel)").font(.caption)
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
        let turns = e.chats[e.global(i)] ?? []
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
                        if e.asking == e.global(i) { Text("Claude is thinking…").font(.caption).foregroundStyle(.secondary).id("wait") }
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

// MARK: - v21: his own words for a turn or a push, and the ring's palette

/// The app's description of a turn or a push, with ✎: his own words replace it (an empty field gives it back).
struct OwnWords: View {
    @EnvironmentObject var e: Engine
    let i: Int
    let push: Bool
    @State private var editing = false
    @State private var draft = ""
    var body: some View {
        let own = push ? e.knobs[i].pushLabel : e.knobs[i].turnLabel
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if editing {
                TextField(push ? "what the push does" : "what the turn does", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).onSubmit(done)
                Button("OK", action: done)
            } else {
                Text(push ? e.pushText(i) : e.turnText(i)).font(.callout).italic(!own.isEmpty)
                    .foregroundStyle(push ? orange : Color.primary).fixedSize(horizontal: false, vertical: true)
                Button { draft = own; editing = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help(push ? "Write what this push does" : "Write what this turn does")
            }
        }
    }
    private func done() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if push { e.knobs[i].pushLabel = t } else { e.knobs[i].turnLabel = t }
        editing = false; e.edited(); e.save()
    }
}

/// The ring's colours: twelve hues around the wheel, then white, in full; the intensity slider dims them.
struct RingPalette: View {
    @Binding var knob: KnobSetup
    static let colours: [(Double, Double, Double)] = (0..<12).map { h -> (Double, Double, Double) in
        let c = NSColor(hue: Double(h) / 12, saturation: 1, brightness: 1, alpha: 1).usingColorSpace(.sRGB) ?? .white
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    } + [(1, 1, 1)]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(RingPalette.colours.indices, id: \.self) { n in
                let (r, g, b) = RingPalette.colours[n]
                let on = abs(knob.r - r) + abs(knob.g - g) + abs(knob.b - b) < 0.05
                Circle().fill(Color(red: r, green: g, blue: b)).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(on ? Color.primary : .clear, lineWidth: 2))
                    .onTapGesture { knob.r = r; knob.g = g; knob.b = b }
            }
        }
    }
}


/// v28: E16 FOR DAVINCI RESOLVE's own window: the E16 as it is laid out, four rows = the page's four audio tracks,
/// four columns = SOLO, MUTE, VOLUME, PAN; every cell works with the mouse as the knob does; the LEDs' brightness.
struct ResolveWindow: View {
    @EnvironmentObject var e: Engine
    private let names = ["SOLO", "MUTE", "VOLUME", "PAN"]
    private let tint: [Color] = [.yellow, .red, .green, Color(red: 0.3, green: 0.55, blue: 1)]
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let m = ResolveMixer.shared
            let pages = max(1, (m.count + 3) / 4)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("E16 FOR DAVINCI RESOLVE").font(.title2.bold())
                    Spacer()
                    Button(e.connected ? "GIVE BACK THE E16" : "CONNECT THE E16") { e.connected ? e.giveBack() : e.connect() }
                    Text("LEDs").font(.callout.bold())
                    Slider(value: $e.ledBrightness, in: 0.05...1).frame(width: 160)
                    Text("\(Int((e.ledBrightness * 100).rounded())) %").font(.callout.monospaced()).frame(width: 44)
                }
                HStack(spacing: 10) {
                    Button("◀ PAGE") { e.goTo(page: e.page - 1) }.disabled(e.page == 0)
                    Text("Page \(e.page + 1) of \(pages) · tracks A\(e.page * 4 + 1)–A\(e.page * 4 + 4) · \(m.count) audio tracks on the timeline")
                        .font(.system(.callout, design: .monospaced).bold()).foregroundStyle(orange)
                    Button("PAGE ▶") { e.goTo(page: e.page + 1) }.disabled(e.page >= pages - 1)
                    Button("READ RESOLVE AGAIN") { e.resolveRefresh() }
                    Spacer()
                }
                Text(e.status).font(.system(.callout, design: .monospaced)).foregroundStyle(e.connected ? .green : .secondary)
                G815Row()                                   // v38: the G815's G1–G5 = Resolve's pages, the current one lit
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Text("TRACK").font(.caption.bold()).frame(width: 190, alignment: .leading)
                        ForEach(0..<4, id: \.self) { c in
                            Text("\(c + 1) · \(names[c])").font(.caption.bold()).foregroundStyle(tint[c]).frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<4, id: \.self) { r in
                        let t = e.page * 4 + r + 1
                        let tr = m.tracks[t]
                        GridRow {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("A\(t)  \(t <= m.count ? m.name(t) : "—")").font(.headline)
                                Text(t > m.count ? "no track" : (tr?.clips ?? 0) == 0 ? "no clips: nothing to turn" : "\(tr!.clips) clips")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 190, alignment: .leading)
                            ForEach(0..<4, id: \.self) { c in cell(r * 4 + c, t: t, c: c, m: m) }
                        }
                    }
                }
                Text("On the E16: column 1 SOLO, 2 MUTE, 3 VOLUME, 4 PAN; each row one track. SOLO and MUTE: turn right on, left off, push toggles. VOLUME: 0.5 dB a click (0.1 with Shift), push = 0 dB. PAN: push = centre. Tap Shift twice to turn the pages (A5–A8 and on). Volume and pan act on every clip of the track; Resolve's scripting cannot reach its Fairlight faders.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(16)
        }
    }

    @ViewBuilder func cell(_ i: Int, t: Int, c: Int, m: ResolveMixer) -> some View {
        let live = t <= m.count
        let tr = m.tracks[t]
        VStack(spacing: 6) {
            switch c {
            case 0, 1:
                let on = c == 0 ? m.solo.contains(t) : m.muted.contains(t)
                Button(on ? (c == 0 ? "SOLO ON" : "MUTED") : (c == 0 ? "solo" : "mute")) { e.resolvePress(i) }
                    .buttonStyle(.borderedProminent).tint(on ? tint[c] : .gray.opacity(0.4))
            case 2:
                Text((tr?.clips ?? 0) == 0 ? "—" : m.db(tr!.vol) + " dB").font(.title3.monospaced().bold())
                HStack { Button("−") { e.resolveTurn(i, by: -1) }; Button("0 dB") { e.resolvePress(i) }; Button("+") { e.resolveTurn(i, by: 1) } }
            default:
                Text((tr?.clips ?? 0) == 0 ? "—" : m.panWord(tr!.pan)).font(.title3.monospaced().bold())
                HStack { Button("◀") { e.resolveTurn(i, by: -1) }; Button("C") { e.resolvePress(i) }; Button("▶") { e.resolveTurn(i, by: 1) } }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint[c].opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint[c].opacity(0.5)))
        .disabled(!live)
        .opacity(live ? 1 : 0.35)
    }
}
