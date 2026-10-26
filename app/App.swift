// App.swift — DJ MANTRA ABLETON REMOTE for OXI E16 (Marko, 26.10.2026: "can you name this project DJ Mantra Ableton
// Remote for Oxi E16?"). The window: the sixteen knobs as on the device, the chosen knob's setup beside them, and
// CONNECT / GIVE BACK / PRESENT THE OXI / the saved setups along the top. The engine is Engine.swift.
import SwiftUI

let VERSION = 10

@main
struct DJMantraAbletonRemote: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    var body: some Scene {
        WindowGroup("DJ Mantra Ableton Remote for OXI E16 · v\(VERSION)") {
            Main().environmentObject(Delegate.engine)
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    static let engine = Engine()
    func applicationDidFinishLaunching(_ n: Notification) {
        let e = Delegate.engine
        e.connect()
        // tests from the Mac: --profile automation loads the first profile, --help-page N shows that help page
        let a = CommandLine.arguments
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

struct Main: View {
    @EnvironmentObject var e: Engine
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(e.connected ? "GIVE BACK" : "CONNECT") { e.connected ? e.giveBack() : e.connect() }
                Button(e.presenting ? "STOP THE SHOW" : "PRESENT THE OXI") { e.togglePresent() }.disabled(!e.connected)
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
            HStack(alignment: .top, spacing: 14) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<4, id: \.self) { r in
                        GridRow { ForEach(0..<4, id: \.self) { c in KnobCell(i: r * 4 + c) } }
                    }
                }
                .frame(minWidth: 360)
                Editor(i: e.selected).frame(minWidth: 280, maxWidth: 380)
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
            Text("CC\(k.cc)·\(k.push == .off ? "—" : k.push == .toggle ? "TGL" : "MOM")")
                .font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
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
