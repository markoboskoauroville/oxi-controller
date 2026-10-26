// The icon, drawn (Marko, 26.10.2026: "our app is missing a suitable icon"): the E16 itself, its sixteen knobs as
// rings of LED dots, lit in the AUTOMATION profile's colours (orange tracks, green parameter, blue time, gold steps,
// magenta pitch), the rest dim; the version under them (version-visible.md).
import AppKit
let S: CGFloat = 1024
let version = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "1"
let img = NSImage(size: NSSize(width: S, height: S)); img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.setFillColor(NSColor(calibratedRed: 0.07, green: 0.075, blue: 0.085, alpha: 1).cgColor); ctx.fillPath()
let lit: [Int: NSColor] = [
    0: NSColor(calibratedRed: 1, green: 0.58, blue: 0, alpha: 1), 1: NSColor(calibratedRed: 0.2, green: 0.82, blue: 0.48, alpha: 1),
    2: NSColor(calibratedRed: 0.24, green: 0.6, blue: 1, alpha: 1), 3: NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1),
    4: NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.9, alpha: 1), 15: NSColor(calibratedWhite: 0.95, alpha: 1),
]
let fill: [Int: CGFloat] = [0: 0.7, 1: 0.45, 2: 0.85, 3: 0.3, 4: 0.6, 15: 1]
for i in 0..<16 {
    let col = CGFloat(i % 4), row = CGFloat(3 - i / 4)
    let cx = 245 + col * 178, cy = 300 + row * 160
    // the knob
    ctx.setFillColor(NSColor(calibratedWhite: 0.2, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: cx - 38, y: cy - 38, width: 76, height: 76))
    // its ring of 16 dots, lit up to its value
    let colour = lit[i] ?? NSColor(calibratedWhite: 0.3, alpha: 1)
    let on = Int((fill[i] ?? 0) * 16)
    for d in 0..<16 {
        let a = CGFloat.pi * (1.25 - 1.5 * CGFloat(d) / 15)
        let px = cx + cos(a) * 64, py = cy + sin(a) * 64
        ctx.setFillColor((d < on ? colour : NSColor(calibratedWhite: 0.22, alpha: 1)).cgColor)
        ctx.fillEllipse(in: CGRect(x: px - 8, y: py - 8, width: 16, height: 16))
    }
}
let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 70, weight: .heavy), .foregroundColor: NSColor(calibratedRed: 1, green: 0.58, blue: 0, alpha: 1)]
("DJ MANTRA" as NSString).draw(at: NSPoint(x: 170, y: 150), withAttributes: a)
("v" + version as NSString).draw(at: NSPoint(x: 700, y: 152), withAttributes: [.font: NSFont.systemFont(ofSize: 66, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.78, alpha: 1)])
img.unlockFocus()
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "icon_1024.png"))
