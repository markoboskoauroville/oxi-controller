// Screen.swift — the E16's 128×64 screen drawn by the app, pixel by pixel (v22, Marko, 26.10.2026: "we are removing
// the title of the preset, because I want to use all the space for my custom labels on each knob. It needs to have 2
// labels, turn and press ... 2 lines, so the first line is turning and the second line is pressing").
//
// Sixteen cells of 32×16 pixels, in the knobs' own 4×4 order; in each, the turn's label on top and the push's under
// it, five letters each in a 5×7 bitmap font (sharp at this size, where a system font smears). The framebuffer is
// the E16's: 8 pages of 128 bytes, bit 0 the top row of a page (E16Message.framebuffer).
import Foundation

enum Screen {
    static let w = 128, h = 64

    /// A canvas of 128×64 on/off pixels.
    struct Canvas {
        var px = [Bool](repeating: false, count: Screen.w * Screen.h)
        mutating func set(_ x: Int, _ y: Int, _ on: Bool = true) {
            guard x >= 0, x < Screen.w, y >= 0, y < Screen.h else { return }
            px[y * Screen.w + x] = on
        }
        mutating func fill(_ x: Int, _ y: Int, _ cw: Int, _ ch: Int, _ on: Bool = true) {
            for yy in y..<(y + ch) { for xx in x..<(x + cw) { set(xx, yy, on) } }
        }
        /// Text in the 5×7 font, one pixel between letters, at (x, y) its top left; inverse draws dark on light.
        mutating func text(_ s: String, _ x: Int, _ y: Int, inverse: Bool = false, scale: Int = 1) {
            var cx = x
            for ch in s.uppercased() {
                let g = Screen.font[ch] ?? Screen.font["?"]!
                for (row, bits) in g.enumerated() {
                    for (col, c) in bits.enumerated() where c == "#" {
                        for sy in 0..<scale { for sx in 0..<scale { set(cx + col * scale + sx, y + row * scale + sy, !inverse) } }
                    }
                }
                cx += 6 * scale
            }
        }
        var framebuffer: [UInt8] {
            var out = [UInt8](repeating: 0, count: 1024)
            for page in 0..<8 { for x in 0..<Screen.w {
                var byte: UInt8 = 0
                for bit in 0..<8 where px[(page * 8 + bit) * Screen.w + x] { byte |= 1 << UInt8(bit) }
                out[page * Screen.w + x] = byte
            } }
            return out
        }
    }

    static func width(_ s: String, scale: Int = 1) -> Int { max(0, s.count * 6 * scale - scale) }

    /// The sixteen knobs: (turn line, push line) each, five letters at most; the knob just touched is drawn inverse.
    static func grid(_ cells: [(String, String)], touched: Int?) -> [UInt8] {
        var c = Canvas()
        for i in 0..<16 {
            let x = (i % 4) * 32, y = (i / 4) * 16
            let (top, bottom) = i < cells.count ? cells[i] : ("", "")
            let inv = touched == i
            if inv { c.fill(x, y, 32, 16) }
            let t = String(top.prefix(5)), b = String(bottom.prefix(5))
            c.text(t, x + (32 - width(t)) / 2, y, inverse: inv)
            c.text(b, x + (32 - width(b)) / 2, y + 8, inverse: inv)
        }
        return c.framebuffer
    }

    /// The page cross (v22): the page in big figures, and what the arms do.
    static func nav(page: Int, of count: Int, last: Int) -> [UInt8] {
        var c = Canvas()
        let p = "\(page + 1)"
        c.text("PAGE", (w - width("PAGE")) / 2, 0)
        c.text(p, (w - width(p, scale: 3)) / 2, 11, scale: 3)
        let of = "OF \(count)"
        c.text(of, (w - width(of)) / 2, 35)
        c.text("< BACK", 0, 47); let f = "NEXT >"; c.text(f, w - width(f), 47)
        let u = "UP: \(last + 1)  DOWN: 1"; c.text(u, (w - width(u)) / 2, 56)
        return c.framebuffer
    }

    /// A word or two from Live, big, for a moment (what showLive says).
    static func message(_ s: String) -> [UInt8] {
        var c = Canvas()
        let words = s.uppercased().split(separator: " ").map(String.init)
        var lines: [String] = []; var cur = ""
        for word in words {
            let next = cur.isEmpty ? word : cur + " " + word
            if width(next, scale: 2) <= w { cur = next } else { if !cur.isEmpty { lines.append(cur) }; cur = word }
        }
        if !cur.isEmpty { lines.append(cur) }
        let scale = lines.count <= 3 ? 2 : 1
        if scale == 1 {   // too long for the big letters: again in small ones
            lines = []; cur = ""
            for word in words {
                let next = cur.isEmpty ? word : cur + " " + word
                if width(next) <= w { cur = next } else { if !cur.isEmpty { lines.append(cur) }; cur = word }
            }
            if !cur.isEmpty { lines.append(cur) }
        }
        let lh = 8 * scale + 2
        var y = max(0, (h - lines.count * lh) / 2)
        for l in lines.prefix(h / lh) { c.text(l, (w - width(l, scale: scale)) / 2, y, scale: scale); y += lh }
        return c.framebuffer
    }

    // MARK: the 5×7 font

    static let font: [Character: [String]] = {
        let rows: [(Character, String)] = [
            ("A", ".###.|#...#|#...#|#####|#...#|#...#|#...#"), ("B", "####.|#...#|#...#|####.|#...#|#...#|####."),
            ("C", ".###.|#...#|#....|#....|#....|#...#|.###."), ("D", "###..|#..#.|#...#|#...#|#...#|#..#.|###.."),
            ("E", "#####|#....|#....|####.|#....|#....|#####"), ("F", "#####|#....|#....|####.|#....|#....|#...."),
            ("G", ".###.|#...#|#....|#.###|#...#|#...#|.####"), ("H", "#...#|#...#|#...#|#####|#...#|#...#|#...#"),
            ("I", ".###.|..#..|..#..|..#..|..#..|..#..|.###."), ("J", "..###|...#.|...#.|...#.|...#.|#..#.|.##.."),
            ("K", "#...#|#..#.|#.#..|##...|#.#..|#..#.|#...#"), ("L", "#....|#....|#....|#....|#....|#....|#####"),
            ("M", "#...#|##.##|#.#.#|#.#.#|#...#|#...#|#...#"), ("N", "#...#|#...#|##..#|#.#.#|#..##|#...#|#...#"),
            ("O", ".###.|#...#|#...#|#...#|#...#|#...#|.###."), ("P", "####.|#...#|#...#|####.|#....|#....|#...."),
            ("Q", ".###.|#...#|#...#|#...#|#.#.#|#..#.|.##.#"), ("R", "####.|#...#|#...#|####.|#.#..|#..#.|#...#"),
            ("S", ".####|#....|#....|.###.|....#|....#|####."), ("T", "#####|..#..|..#..|..#..|..#..|..#..|..#.."),
            ("U", "#...#|#...#|#...#|#...#|#...#|#...#|.###."), ("V", "#...#|#...#|#...#|#...#|#...#|.#.#.|..#.."),
            ("W", "#...#|#...#|#...#|#.#.#|#.#.#|#.#.#|.#.#."), ("X", "#...#|#...#|.#.#.|..#..|.#.#.|#...#|#...#"),
            ("Y", "#...#|#...#|.#.#.|..#..|..#..|..#..|..#.."), ("Z", "#####|....#|...#.|..#..|.#...|#....|#####"),
            ("0", ".###.|#...#|#..##|#.#.#|##..#|#...#|.###."), ("1", "..#..|.##..|..#..|..#..|..#..|..#..|.###."),
            ("2", ".###.|#...#|....#|...#.|..#..|.#...|#####"), ("3", "#####|...#.|..#..|...#.|....#|#...#|.###."),
            ("4", "...#.|..##.|.#.#.|#..#.|#####|...#.|...#."), ("5", "#####|#....|####.|....#|....#|#...#|.###."),
            ("6", "..##.|.#...|#....|####.|#...#|#...#|.###."), ("7", "#####|....#|...#.|..#..|.#...|.#...|.#..."),
            ("8", ".###.|#...#|#...#|.###.|#...#|#...#|.###."), ("9", ".###.|#...#|#...#|.####|....#|...#.|.##.."),
            (" ", ".....|.....|.....|.....|.....|.....|....."), ("-", ".....|.....|.....|#####|.....|.....|....."),
            ("+", ".....|..#..|..#..|#####|..#..|..#..|....."), (".", ".....|.....|.....|.....|.....|.##..|.##.."),
            (":", ".....|.##..|.##..|.....|.##..|.##..|....."), ("/", "....#|....#|...#.|..#..|.#...|#....|#...."),
            ("<", "...#.|..#..|.#...|#....|.#...|..#..|...#."), (">", ".#...|..#..|...#.|....#|...#.|..#..|.#..."),
            ("?", ".###.|#...#|....#|...#.|..#..|.....|..#.."), ("!", "..#..|..#..|..#..|..#..|..#..|.....|..#.."),
            ("%", "##..#|##..#|...#.|..#..|.#...|#..##|#..##"), ("#", ".#.#.|.#.#.|#####|.#.#.|#####|.#.#.|.#.#."),
            ("=", ".....|.....|#####|.....|#####|.....|....."), ("(", "...#.|..#..|.#...|.#...|.#...|..#..|...#."),
            (")", ".#...|..#..|...#.|...#.|...#.|..#..|.#..."), ("·", ".....|.....|.....|..#..|.....|.....|....."),
            ("'", "..#..|..#..|.#...|.....|.....|.....|....."), (",", ".....|.....|.....|.....|.##..|..#..|.#..."),
            ("&", ".##..|#..#.|#.#..|.#...|#.#.#|#..#.|.##.#"), ("*", ".....|#.#.#|.###.|#####|.###.|#.#.#|....."),
            ("▲", ".....|..#..|.###.|#####|.....|.....|....."), ("▼", ".....|.....|#####|.###.|..#..|.....|....."),
        ]
        var f: [Character: [String]] = [:]
        for (c, s) in rows { f[c] = s.split(separator: "|").map(String.init) }
        return f
    }()
}
