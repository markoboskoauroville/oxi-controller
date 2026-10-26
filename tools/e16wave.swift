// e16wave — a moving wave around the OXI E16's sixteen rings, over plain CC (MANTRA_MANIFEST oxi-e16.md §10: the rings
// take a value on USB2 or USB3, on the knob's own channel; USB1 only flashes). Written 26.10.2026 for the camera's
// stress pass (Marko: "animate the LED rings if you want to have some kind of moving picture").
//
//   swiftc -O tools/e16wave.swift -o build/e16wave && build/e16wave [seconds=30] [channel=2] [port=3] [hz=30]
//
// CC 1-16 on the given channel, each ring a sine a sixteenth of a turn behind the one before. At the end every ring
// is put back to 0. A port that is not there is waited for (the E16 drops off CoreMIDI now and then, §10).
import CoreMIDI
import Foundation

let args = CommandLine.arguments
let seconds = args.count > 1 ? Double(args[1]) ?? 30 : 30
let channel = UInt8((args.count > 2 ? Int(args[2]) ?? 2 : 2) - 1) & 0x0F
let portNumber = args.count > 3 ? Int(args[3]) ?? 3 : 3
let hz = args.count > 4 ? Double(args[4]) ?? 30 : 30

func name(_ e: MIDIEndpointRef) -> String {
    var s: Unmanaged<CFString>?
    MIDIObjectGetStringProperty(e, kMIDIPropertyDisplayName, &s)
    return (s?.takeRetainedValue() as String?) ?? ""
}

func destination() -> MIDIEndpointRef? {
    for i in 0..<MIDIGetNumberOfDestinations() {
        let d = MIDIGetDestination(i)
        let n = name(d)
        if n.contains("OXI E16") && n.contains("Port \(portNumber)") { return d }
    }
    return nil
}

var client = MIDIClientRef()
MIDIClientCreate("e16wave" as CFString, nil, nil, &client)
var out = MIDIPortRef()
MIDIOutputPortCreate(client, "out" as CFString, &out)

func send(_ bytes: [UInt8], to d: MIDIEndpointRef) {
    var list = MIDIPacketList()
    let p = MIDIPacketListInit(&list)
    _ = bytes.withUnsafeBufferPointer { MIDIPacketListAdd(&list, 1024, p, 0, bytes.count, $0.baseAddress!) }
    MIDISend(out, d, &list)
}

var dest = destination()
let waitUntil = Date().addingTimeInterval(5)
while dest == nil && Date() < waitUntil { Thread.sleep(forTimeInterval: 0.25); dest = destination() }
guard let d = dest else {
    let all = (0..<MIDIGetNumberOfDestinations()).map { name(MIDIGetDestination($0)) }
    print("e16wave: no OXI E16 Port \(portNumber) among \(all)")
    exit(1)
}
print("e16wave: \(name(d)), channel \(Int(channel) + 1), \(Int(seconds)) s at \(Int(hz)) Hz")

let start = Date()
var frames = 0
while Date().timeIntervalSince(start) < seconds {
    let t = Date().timeIntervalSince(start)
    for k in 0..<16 {
        let phase = 2 * Double.pi * (t * 0.5 - Double(k) / 16)
        let v = UInt8(max(0, min(127, Int((sin(phase) + 1) / 2 * 127))))
        send([0xB0 | channel, UInt8(k + 1), v], to: d)
    }
    frames += 1
    Thread.sleep(forTimeInterval: 1 / hz)
}
for k in 0..<16 { send([0xB0 | channel, UInt8(k + 1), 0], to: d) }
print("e16wave: \(frames) frames sent, rings back to 0")
