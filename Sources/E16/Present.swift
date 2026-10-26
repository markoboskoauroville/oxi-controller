// Present.swift — PRESENT THE OXI, the entertaining mode (Marko, 26.10.2026: "make a light show with my LEDs. They
// need to go in different directions, making you imagine you have a screen of 4 by 4 pixels, so 16 pixels. Just
// choose 22 ASCII art images and just crossfade between each of them with different colors ... We can call this mode
// "Present the Oxi." ... also entertaining the dot matrix display at the top. You can also display the same ASCII
// art that is down on the knobs").
//
// The sixteen knobs are the pixels (knob 0 top left, row by row). Each picture comes in pixel by pixel along a sweep
// (from the left, the right, the top, the bottom, a corner, the centre, in a spiral), each pixel crossfading from the
// last picture's colour to the new one's; the colours turn round the colour wheel picture by picture and shade across
// the grid. The screen shows the same picture large, its ASCII art and its name (06 02, the 128×64 framebuffer).
import AppKit
import Foundation

struct Picture {
    let name: String
    let rows: [String]          // four strings of four: '#' lit, '.' dark
    var lit: [Bool] { rows.joined().map { $0 == "#" } }
}

enum Present {
    static let pictures: [Picture] = [
        Picture(name: "HEART", rows: [".#.#", "####", "####", ".##."]),
        Picture(name: "SMILE", rows: ["#..#", "....", "#..#", ".##."]),
        Picture(name: "UP", rows: [".##.", "####", ".##.", ".##."]),
        Picture(name: "RIGHT", rows: ["..#.", "####", "####", "..#."]),
        Picture(name: "DOWN", rows: [".##.", ".##.", "####", ".##."]),
        Picture(name: "LEFT", rows: [".#..", "####", "####", ".#.."]),
        Picture(name: "DIAMOND", rows: [".##.", "####", "####", ".##."]),
        Picture(name: "FRAME", rows: ["####", "#..#", "#..#", "####"]),
        Picture(name: "CORE", rows: ["....", ".##.", ".##.", "...."]),
        Picture(name: "CROSS X", rows: ["#..#", ".##.", ".##.", "#..#"]),
        Picture(name: "PLUS", rows: [".#..", "####", ".#..", ".#.."]),
        Picture(name: "CHECKER", rows: ["#.#.", ".#.#", "#.#.", ".#.#"]),
        Picture(name: "SLASH", rows: ["...#", "..#.", ".#..", "#..."]),
        Picture(name: "BACKSLASH", rows: ["#...", ".#..", "..#.", "...#"]),
        Picture(name: "STAIRS", rows: ["#...", "##..", "###.", "####"]),
        Picture(name: "WAVE", rows: ["#...", ".#.#", "..#.", "...."]),
        Picture(name: "CORNERS", rows: ["#..#", "....", "....", "#..#"]),
        Picture(name: "BARS", rows: ["#.#.", "#.#.", "#.#.", "#.#."]),
        Picture(name: "STRIPES", rows: ["####", "....", "####", "...."]),
        Picture(name: "SPIRAL", rows: ["####", "...#", "##.#", "####"]),
        Picture(name: "OM DOT", rows: ["....", ".#..", "....", "..#."]),
        Picture(name: "FULL MOON", rows: ["####", "####", "####", "####"]),
    ]

    enum Sweep: CaseIterable { case left, right, top, bottom, corner, centre, spiral }

    /// When each pixel (0...15) starts to change, 0...1 of the sweep's time.
    static func delays(_ sweep: Sweep) -> [Double] {
        let spiralOrder = [0, 1, 2, 3, 7, 11, 15, 14, 13, 12, 8, 4, 5, 6, 10, 9]
        return (0..<16).map { i in
            let r = Double(i / 4), c = Double(i % 4)
            switch sweep {
            case .left: return c / 3
            case .right: return (3 - c) / 3
            case .top: return r / 3
            case .bottom: return (3 - r) / 3
            case .corner: return (r + c) / 6
            case .centre: return (abs(r - 1.5) + abs(c - 1.5)) / 3
            case .spiral: return Double(spiralOrder.firstIndex(of: i)!) / 15
            }
        }
    }

    /// A colour from the wheel (0...1), 0-127 per channel.
    static func wheel(_ h: Double, _ v: Double = 1) -> (Double, Double, Double) {
        let h = h - floor(h)
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6)), q = 1 - f
        let (r, g, b): (Double, Double, Double) = [(1, f, 0), (q, 1, 0), (0, 1, f), (0, q, 1), (f, 0, 1), (1, 0, q)][i]
        return (r * v * 127, g * v * 127, b * v * 127)
    }

    /// The picture's colour at a pixel: its hue, shaded a little across the grid.
    static func colour(_ k: Int, _ i: Int) -> (Double, Double, Double) {
        wheel(Double(k) * 0.137 + Double(i / 4 + i % 4) * 0.025)
    }

    /// The sixteen rings between picture a (k-1) and b (k), at t 0...1 of the change.
    static func blend(_ a: Picture, _ ka: Int, _ b: Picture, _ kb: Int, _ sweep: Sweep, _ t: Double) -> [Ring] {
        let d = delays(sweep)
        return (0..<16).map { i in
            // each pixel takes half of the change, starting at its place on the sweep
            let p = max(0, min(1, (t - d[i] * 0.5) / 0.5))
            let s = p * p * (3 - 2 * p)                                   // smoothstep: a soft crossfade
            let ca = colour(ka, i), cb = colour(kb, i)
            let la = a.lit[i] ? 1.0 : 0.0, lb = b.lit[i] ? 1.0 : 0.0
            let amount = la + (lb - la) * s
            // the colour slides from the old one to the new one; a dark pixel takes the colour it is going to
            let w = la == 0 ? 1 : (lb == 0 ? 0 : s)
            return Ring(r: Int(ca.0 + (cb.0 - ca.0) * w), g: Int(ca.1 + (cb.1 - ca.1) * w), b: Int(ca.2 + (cb.2 - ca.2) * w), amount: amount)
        }
    }

    // MARK: the screen: 128 × 64, one bit a pixel, SSD1306 pages (8 rows a byte, bit 0 on top), 1024 bytes

    static func framebuffer(_ p: Picture, _ k: Int) -> [UInt8] {
        let w = 128, h = 64
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 1, alpha: 1)
        // the picture large on the left: 4 × 4 blocks of 13 px with a 2 px gap (CG's y goes up)
        for (i, on) in p.lit.enumerated() where on {
            let r = i / 4, c = i % 4
            ctx.fill(CGRect(x: 2 + c * 15, y: h - 2 - (r + 1) * 15, width: 13, height: 13))
        }
        // on the right: its ASCII art, then its name and its number
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let mono = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: mono, .foregroundColor: NSColor.white]
        for (r, row) in p.rows.enumerated() {
            (row as NSString).draw(at: NSPoint(x: 70, y: h - 12 - r * 10), withAttributes: attrs)
        }
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular), .foregroundColor: NSColor.white]
        (p.name as NSString).draw(at: NSPoint(x: 66, y: 9), withAttributes: small)
        (String(format: "%02d/%02d", k % pictures.count + 1, pictures.count) as NSString).draw(at: NSPoint(x: 66, y: 0), withAttributes: small)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data else { return [] }
        let px = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: 1024)
        for page in 0..<8 {
            for x in 0..<w {
                var byte: UInt8 = 0
                for bit in 0..<8 {
                    let y = page * 8 + bit                                    // the bitmap's row 0 is the top
                    if px[y * w + x] > 127 { byte |= 1 << UInt8(bit) }
                }
                out[page * w + x] = byte
            }
        }
        return out
    }
}

extension E16Message {
    /// OLED FRAMEBUFFER (06 02): 1024 bytes, 128×64, "replaces the entire display content".
    static func framebuffer(_ fb: [UInt8]) -> [UInt8] { sysex([0x06, 0x02], fb) }
}

extension E16Port {
    /// The show: every picture in turn, [change] seconds of crossfade and [hold] seconds standing, at [fps], for
    /// [seconds] (0: until stopped). The caller gives the device back (exitRemote) afterwards.
    func present(seconds: Double, change: Double = 1.4, hold: Double = 1.6, fps: Double = 25, stop: () -> Bool = { false }) {
        let start = Date()
        var k = 1
        var sweeps = Present.Sweep.allCases.shuffled()
        while seconds <= 0 || Date().timeIntervalSince(start) < seconds {
            if stop() { return }
            let a = Present.pictures[(k - 1) % Present.pictures.count], b = Present.pictures[k % Present.pictures.count]
            if sweeps.isEmpty { sweeps = Present.Sweep.allCases.shuffled() }
            let sweep = sweeps.removeFirst()
            send(E16Message.framebuffer(Present.framebuffer(b, k)))
            let frames = max(1, Int(change * fps))
            for f in 0...frames {
                if stop() { return }
                send(E16Message.rings(Present.blend(a, k - 1, b, k, sweep, Double(f) / Double(frames))))
                Thread.sleep(forTimeInterval: 1 / fps)
            }
            // standing, the picture breathes a little
            let still = max(1, Int(hold * fps))
            for f in 0..<still {
                if stop() { return }
                let breath = 0.82 + 0.18 * (0.5 + 0.5 * cos(Double(f) / Double(still) * 2 * Double.pi))
                let rings = (0..<16).map { i -> Ring in
                    let c = Present.colour(k, i)
                    return Ring(r: Int(c.0 * breath), g: Int(c.1 * breath), b: Int(c.2 * breath), amount: b.lit[i] ? 1 : 0)
                }
                send(E16Message.rings(rings))
                Thread.sleep(forTimeInterval: 1 / fps)
            }
            k += 1
        }
    }
}

// MARK: - the signature (Marko, 26.10.2026: "name this project DJ Mantra Ableton Remote for Oxi E16 ... write the name
// of the app on the matrix screen when we boot up, so it's with signature")

enum Signature {
    static let app = "DJ MANTRA ABLETON REMOTE"

    /** The name on the 128×64 screen: DJ MANTRA large, ABLETON REMOTE under it, for OXI E16 small, a rule between. */
    static func framebuffer() -> [UInt8] {
        let w = 128, h = 64
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        func centred(_ t: String, _ size: CGFloat, _ weight: NSFont.Weight, _ y: CGFloat) {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white]
            let sz = (t as NSString).size(withAttributes: a)
            (t as NSString).draw(at: NSPoint(x: (CGFloat(w) - sz.width) / 2, y: y), withAttributes: a)
        }
        centred("DJ MANTRA", 17, .heavy, 40)
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 14, y: 36, width: 100, height: 1))
        centred("ABLETON REMOTE", 10, .bold, 21)
        centred("for OXI E16", 8, .regular, 5)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data else { return [] }
        let px = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: 1024)
        for page in 0..<8 { for x in 0..<w {
            var byte: UInt8 = 0
            for bit in 0..<8 where px[(page * 8 + bit) * w + x] > 127 { byte |= 1 << UInt8(bit) }
            out[page * w + x] = byte
        } }
        return out
    }
}

extension Signature {
    /// The smallest letters the 128×64 screen still shows readably (seen 26.10.2026: 7 px was not).
    static let MIN_SIZE: CGFloat = 9.5

    static func bodyAttrs(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping; style.lineSpacing = 0
        return [.font: NSFont.systemFont(ofSize: size, weight: size > 9 ? .semibold : .regular), .foregroundColor: NSColor.white, .paragraphStyle: style]
    }

    static func fits(_ text: String, _ size: CGFloat) -> Bool {
        let need = (text as NSString).boundingRect(with: NSSize(width: 128, height: 1000), options: [.usesLineFragmentOrigin], attributes: bodyAttrs(size))
        return need.height <= 51
    }

    /// A text cut into pages at sentence (or word) ends, each fitting at MIN_SIZE or larger.
    static func pages(for text: String) -> [String] {
        var out: [String] = []; var cur = ""
        let pieces = text.replacingOccurrences(of: ". ", with: ".\u{1}").split(separator: "\u{1}").map(String.init)
        for piece in pieces {
            let next = cur.isEmpty ? piece : cur + " " + piece
            if fits(next, MIN_SIZE) { cur = next; continue }
            if !cur.isEmpty { out.append(cur); cur = "" }
            // a sentence too long alone: by words
            var line = ""
            for word in piece.split(separator: " ") {
                let n = line.isEmpty ? String(word) : line + " " + word
                if fits(n, MIN_SIZE) { line = n } else { out.append(line); line = String(word) }
            }
            cur = line
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// A help page: the title on top, the text wrapped beneath it in the largest letters that fit, the page's number
    /// at the top right.
    static func page(title: String, body: String, number: String) -> [UInt8] {
        let w = 128, h = 64
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return [] }
        ctx.setFillColor(gray: 0, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let white = NSColor.white
        (title as NSString).draw(at: NSPoint(x: 0, y: h - 10), withAttributes: [.font: NSFont.systemFont(ofSize: 8, weight: .heavy), .foregroundColor: white])
        let numAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7, weight: .regular), .foregroundColor: white]
        let nw = (number as NSString).size(withAttributes: numAttrs).width
        (number as NSString).draw(at: NSPoint(x: CGFloat(w) - nw, y: CGFloat(h) - 9), withAttributes: numAttrs)
        ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(CGRect(x: 0, y: h - 12, width: w, height: 1))
        // the largest size at which the whole text fits under the title, never under MIN_SIZE (a longer text is cut
        // into pages beforehand: pages(for:))
        let box = NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h - 13))
        var size: CGFloat = 16
        var attrs = bodyAttrs(size)
        while size > MIN_SIZE, !fits(body, size) { size -= 0.5; attrs = bodyAttrs(size) }
        (body as NSString).draw(with: box, options: [.usesLineFragmentOrigin], attributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = ctx.data else { return [] }
        let px = data.assumingMemoryBound(to: UInt8.self)
        var out = [UInt8](repeating: 0, count: 1024)
        for page in 0..<8 { for x in 0..<w {
            var byte: UInt8 = 0
            for bit in 0..<8 where px[(page * 8 + bit) * w + x] > 110 { byte |= 1 << UInt8(bit) }
            out[page * w + x] = byte
        } }
        return out
    }
}

extension E16Port {
    /// Remote Mode in, with the signature on the screen for [seconds] before anything else.
    @discardableResult
    func enterSigned(seconds: Double = 2) -> Bool {
        let ok = enterRemote()
        send(E16Message.rings(Array(repeating: Ring(r: 0, g: 0, b: 0, amount: 0), count: 16)))
        send(E16Message.framebuffer(Signature.framebuffer()))
        Thread.sleep(forTimeInterval: seconds)
        return ok
    }
}
