// e16looks — store and recall visible configurations of the OXI E16 (Marko, 26.10.2026: "first test with this app is:
// can you store different configurations and recall different configurations? You find your own configurances. It
// will be good if they can be actually visual, maybe changing the colors of rings or text display on the screen").
//
//   e16looks seed            write the four looks of my own (SUNRISE, OCEAN, FOREST, LIVE MIX)
//   e16looks list            the stored looks
//   e16looks show NAME       recall one onto the device (Remote Mode)
//   e16looks cycle [s=4]     recall each in turn, s seconds apiece, then give the device back
//   e16looks present [s]     PRESENT THE OXI: the light show, s seconds (0: until Ctrl-C), then the device back
//   e16looks exit            give the device back (EXIT REMOTE MODE; otherwise it stays blank)
//
// Looks live in ~/Library/Application Support/Oxi Controller/looks/<NAME>.json, one Look each (E16Remote.swift).
import Foundation

let dir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Oxi Controller/looks", isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

func file(_ name: String) -> URL { dir.appendingPathComponent(name.uppercased().replacingOccurrences(of: "/", with: "-") + ".json") }

func store(_ look: Look) {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? enc.encode(look).write(to: file(look.name))
}

func load(_ name: String) -> Look? {
    guard let d = try? Data(contentsOf: file(name)) else { return nil }
    return try? JSONDecoder().decode(Look.self, from: d)
}

func all() -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
}

/// A colour from hue (0...1) at full saturation, 0-127 per channel.
func hue(_ h: Double, _ v: Double = 1) -> (Int, Int, Int) {
    let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
    let q = 1 - f, t = f
    let (r, g, b): (Double, Double, Double) = [(1, t, 0), (q, 1, 0), (0, 1, t), (0, q, 1), (t, 0, 1), (1, 0, q)][i]
    return (Int(r * v * 127), Int(g * v * 127), Int(b * v * 127))
}

func seed() {
    // SUNRISE: red at knob 1 to yellow at 16, the rings rising like a sun
    store(Look(name: "SUNRISE", title: "SUNRISE", labels: (1...16).map { "S\($0)" },
               rings: (0..<16).map { i in let c = hue(Double(i) / 16 * 0.16); return Ring(r: c.0, g: c.1, b: c.2, amount: Double(i + 1) / 16) }))
    // OCEAN: blues and cyans, a wave of amounts
    store(Look(name: "OCEAN", title: "OCEAN", labels: ["WAVE", "TIDE", "DEEP", "REEF", "FOAM", "SALT", "SURF", "BLUE",
                                                      "KELP", "PEAR", "DRFT", "SWEL", "MIST", "SAIL", "GULL", "BAY"],
               rings: (0..<16).map { i in let c = hue(0.5 + Double(i % 4) * 0.04); return Ring(r: c.0, g: c.1, b: c.2, amount: 0.5 + 0.5 * sin(Double(i) * .pi / 4)) }))
    // FOREST: greens, every second ring full
    store(Look(name: "FOREST", title: "FOREST", labels: ["OAK", "PINE", "FERN", "MOSS", "ELM", "ASH", "YEW", "FIR",
                                                        "BIRC", "LEAF", "ROOT", "BARK", "SEED", "BUD", "VINE", "SAP"],
               rings: (0..<16).map { i in let c = hue(0.28 + Double(i % 3) * 0.04); return Ring(r: c.0, g: c.1, b: c.2, amount: i % 2 == 0 ? 1 : 0.35) }))
    // LIVE MIX: what a mixer page will look like — tracks in Live's own colour order, volume as the ring
    store(Look(name: "LIVE MIX", title: "LIVE MIX", labels: ["KICK", "SNR", "HAT", "PERC", "BASS", "SUB", "KEYS", "PAD",
                                                            "LEAD", "VOX", "FX1", "FX2", "RTNA", "RTNB", "BUS", "MAST"],
               rings: (0..<16).map { i in let c = hue(Double(i) / 16); return Ring(r: c.0, g: c.1, b: c.2, amount: [0.8, 0.7, 0.5, 0.6, 0.85, 0.6, 0.55, 0.45, 0.7, 0.75, 0.3, 0.3, 0.4, 0.4, 0.9, 0.85][i]) }))
    print("seeded: " + all().joined(separator: ", ") + "  in " + dir.path)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "list" {
case "seed":
    seed()
case "list":
    print(all().isEmpty ? "no looks yet: e16looks seed" : all().joined(separator: "\n"))
case "present":
    // PRESENT THE OXI (Marko, 26.10.2026): the light show for [seconds] (0: until Ctrl-C), then the device back
    guard let e16 = E16Port() else { print("e16looks: the OXI E16 (USB1) is not on CoreMIDI"); exit(1) }
    print(e16.enterSigned() ? "remote mode: entered (ACK)" : "remote mode: sent ENTER, no ACK recognised — going on")
    var stopped = false
    signal(SIGINT, SIG_IGN)
    let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global()); sig.setEventHandler { stopped = true }; sig.resume()
    let secs = Double(args.count > 1 ? args[1] : "0") ?? 0
    print("PRESENT THE OXI: \(Present.pictures.count) pictures" + (secs > 0 ? ", \(Int(secs)) s" : ", Ctrl-C ends"))
    e16.present(seconds: secs, stop: { stopped })
    e16.exitRemote(); print("given back")
case "show", "cycle", "exit":
    guard let e16 = E16Port() else { print("e16looks: the OXI E16 (USB1) is not on CoreMIDI"); exit(1) }
    if args.first == "exit" { e16.exitRemote(); print("given back"); exit(0) }
    // MEASURED 26.10.2026: the device blanked (it entered) while the ACK was not recognised here; go on and say so
    print(e16.enterSigned() ? "remote mode: entered (ACK)" : "remote mode: sent ENTER, no ACK recognised — going on")
    if args.first == "show" {
        let name = args.dropFirst().joined(separator: " ")
        guard let look = load(name) else { print("no look \(name): " + all().joined(separator: ", ")); exit(1) }
        e16.show(look); print("showing \(look.name)")
    } else {
        let s = Double(args.count > 1 ? args[1] : "4") ?? 4
        for name in all() { if let l = load(name) { e16.show(l); print("showing \(l.name)"); Thread.sleep(forTimeInterval: s) } }
        e16.exitRemote(); print("given back")
    }
default:
    print("e16looks seed | list | show NAME | cycle [seconds] | present [seconds] | exit")
}
