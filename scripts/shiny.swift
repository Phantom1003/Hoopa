// Recolours Hoopa's official picture (scripts/artwork.png, normal colouring) into the shiny colouring, producing the app icon's source picture:
//   swift scripts/shiny.swift scripts/artwork.png scripts/icon-source.png
// run once after replacing artwork.png; build.sh does not call it.
// Recolours by colour family (hood, face, horns, eyes). Each pixel's new colour = target colour × (its lightness / the family's reference lightness):
// the transform is linear in black, so an anti-aliased pixel that is "the flat colour mixed with the black outline in some ratio" becomes exactly "the new colour mixed with black in the same ratio",
// and the outlines keep their weight and smoothness; shading and highlights are kept in proportion to lightness. Classification looks only at hue, HSV saturation and the blue-red difference (all independent of lightness),
// so the transition pixels on the two sides of one outline never end up in different families.
import AppKit
let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let w = src.width, h = src.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.assumingMemoryBound(to: UInt8.self)

func hue(_ r: Double, _ g: Double, _ b: Double) -> Double {
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    guard d > 1e-6 else { return 0 }
    var hh: Double
    if mx == r { hh = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { hh = (b - r) / d + 2 } else { hh = (r - g) / d + 4 }
    return hh * 60
}
func rgb(_ hh: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
    if s == 0 { return (l, l, l) }
    let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    func f(_ t0: Double) -> Double {
        var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
        if t < 1 / 6 { return p + (q - p) * 6 * t }
        if t < 1 / 2 { return q }
        if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
        return p
    }
    let hn = hh / 360
    return (f(hn + 1 / 3), f(hn), f(hn - 1 / 3))
}
/// One colour family: the reference lightness fromL of the original colour, and the target (hue, saturation, lightness). Reference → target, everything else in proportion to lightness.
struct Family {
    let fromL: Double, target: (Double, Double, Double)
    init(fromL: Double, hue: Double, sat: Double, toL: Double) { self.fromL = fromL; target = rgb(hue, sat, toL) }
}
let hood = Family(fromL: 0.62, hue: 36, sat: 0.58, toL: 0.53)   // pink hood, body, tail → golden brown
let face = Family(fromL: 0.79, hue: 52, sat: 0.88, toL: 0.75)   // light purple-grey face → pale yellow
let horn = Family(fromL: 0.55, hue: 46, sat: 0.72, toL: 0.68)   // grey horns → yellow
let eye  = Family(fromL: 0.43, hue: 8,  sat: 0.66, toL: 0.47)   // green eyes → red
var counts = [String: Int]()
for i in 0..<(w * h) {
    let al = Double(px[i * 4 + 3]) / 255
    guard al > 0 else { continue }
    let r = min(1, Double(px[i * 4]) / 255 / al), g = min(1, Double(px[i * 4 + 1]) / 255 / al), b = min(1, Double(px[i * 4 + 2]) / 255 / al)
    let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2
    let sv = mx > 0 ? (mx - mn) / mx : 0          // HSV saturation: independent of lightness
    let hh = hue(r, g, b)
    var fam: Family?, name = "keep"
    if mx < 0.05 {
        fam = nil                                                   // pure black
    } else if l > 0.93 && sv < 0.25 {
        fam = nil                                                   // white teeth, white highlights
    } else if sv >= 0.3 && hh >= 35 && hh < 70 {
        fam = nil; name = "gold"                                    // the gold rings and the forehead mark
    } else if l > 0.75 && sv >= 0.12 && sv < 0.22 && (hh >= 300 || hh < 35) {
        fam = nil; name = "blush"                                   // the pink blush on the cheeks (light, low saturation): pink in the shiny form too; the hood's pink highlights are more saturated and not included
    } else if sv >= 0.12 && (hh >= 300 || hh < 35) {
        fam = hood; name = "hood"                                   // every pinkish tone counts as hood, light highlights included (face and horns are grey, their saturation never reaches 0.12)
    } else if sv >= 0.25 && hh >= 70 && hh <= 160 {
        fam = eye; name = "eye"
    } else if (b - r) / mx > 0.03 {
        fam = face; name = "face"                                   // bluish grey = face
    } else {
        fam = horn; name = "horn"                                   // neutral grey = horns
    }
    counts[name, default: 0] += 1
    guard let f = fam else { continue }
    let k = l / f.fromL
    var (nr, ng, nb) = (f.target.0 * k, f.target.1 * k, f.target.2 * k)
    // Very light parts (highlights) lean a little towards white, so they do not overflow into neon; only the light parts are affected, the dark pixels beside outlines are not.
    let nl = (max(nr, ng, nb) + min(nr, ng, nb)) / 2
    let toWhite = max(0, min(1, (nl - 0.78) * 2.5))
    nr = min(1, nr + (1 - nr) * toWhite); ng = min(1, ng + (1 - ng) * toWhite); nb = min(1, nb + (1 - nb) * toWhite)
    px[i * 4] = UInt8((nr * al * 255).rounded()); px[i * 4 + 1] = UInt8((ng * al * 255).rounded()); px[i * 4 + 2] = UInt8((nb * al * 255).rounded())
}
try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print(a[2], counts.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
