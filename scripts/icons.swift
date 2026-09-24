// Generates the app icon and the menu bar icon from a picture with a transparent background (run by build.sh):
//   swift scripts/icons.swift source.png output.iconset ResourcesDir
// App icon: trim the transparent margin, centre on a square (5% padding on every side), emit every size from 16 to 1024, packed by iconutil.
// Menu bar icon: the silhouette of the whole figure with the eyes cut out; a monochrome template (opacity only, the system tints it to the menu bar colours), 18pt high, plus @2x.
import AppKit

let args = CommandLine.arguments
guard args.count == 4,
      let source = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("Usage: swift scripts/icons.swift source.png output.iconset ResourcesDir\n".data(using: .utf8)!)
    exit(2)
}
let iconset = URL(fileURLWithPath: args[2]), resources = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func canvas(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}
/// Halves the size. One big downscale leaves jagged edges; halving step by step is smoother.
func halved(_ image: CGImage) -> CGImage {
    let ctx = canvas(image.width / 2, image.height / 2)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
    return ctx.makeImage()!
}
func write(_ image: CGImage, _ url: URL) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

// Reads opacity and "darkness" per pixel (premultiplied RGBA; row 0 in memory is the top row of the picture).
let w = source.width, h = source.height
let pixels = canvas(w, h)
pixels.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = pixels.data!.assumingMemoryBound(to: UInt8.self)
var alpha = [Double](repeating: 0, count: w * h), darkness = alpha
var (x0, y0, x1, y1) = (w, h, -1, -1)
for i in 0..<(w * h) where px[i * 4 + 3] > 0 {
    let a = Double(px[i * 4 + 3]) / 255
    alpha[i] = a
    if a > 0.03 { x0 = min(x0, i % w); x1 = max(x1, i % w); y0 = min(y0, i / w); y1 = max(y1, i / w) }
    let r = Double(px[i * 4]) / 255 / a, g = Double(px[i * 4 + 1]) / 255 / a, b = Double(px[i * 4 + 2]) / 255 / a
    // Lightness up to 0.15 counts as fully black, from 0.35 as not black, a ramp in between.
    darkness[i] = max(0, min(1, (0.35 - (0.2126 * r + 0.7152 * g + 0.0722 * b)) / 0.2))
}
guard x1 >= 0 else {
    FileHandle.standardError.write("The source picture is fully transparent\n".data(using: .utf8)!)
    exit(1)
}
let bounds = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)   // image coordinates, origin top left
let picture = source.cropping(to: bounds)!

// MARK: App icon

let iconNames = [1024: ["icon_512x512@2x"], 512: ["icon_512x512", "icon_256x256@2x"],
                 256: ["icon_256x256", "icon_128x128@2x"], 128: ["icon_128x128"], 64: ["icon_32x32@2x"],
                 32: ["icon_32x32", "icon_16x16@2x"], 16: ["icon_16x16"]]
var icon: CGImage = {
    let side = 1024.0, ctx = canvas(Int(side), Int(side))
    let scale = side * 0.9 / Double(max(picture.width, picture.height))
    let size = CGSize(width: Double(picture.width) * scale, height: Double(picture.height) * scale)
    ctx.draw(picture, in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
    return ctx.makeImage()!
}()
for side in [1024, 512, 256, 128, 64, 32, 16] {
    if side < 1024 { icon = halved(icon) }
    for name in iconNames[side]! { write(icon, iconset.appendingPathComponent("\(name).png")) }
}

// MARK: Menu bar icon

// A black-and-white split by lightness would cut out the black outlines and joints and scatter the pieces; so the whole silhouette is used and only the eyes are cut out.
// Eyes = large black blobs not connected to the outer outline: flood along the black pixels from outside the picture; what the flood reaches is the outline and the other black on the rim,
// and the remaining black components that are large enough are the eyes (small ones are fur lines and are ignored).
let neighbours = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]
var outside = alpha.map { $0 < 0.5 }
var stack = outside.indices.filter { outside[$0] }
while let i = stack.popLast() {
    for (dx, dy) in neighbours {
        let x = i % w + dx, y = i / w + dy
        guard x >= 0, y >= 0, x < w, y < h, !outside[y * w + x], darkness[y * w + x] > 0.25 else { continue }
        outside[y * w + x] = true
        stack.append(y * w + x)
    }
}
var eyes: [CGRect] = []   // image coordinates, origin top left
var seen = outside
let minArea = pow(Double(max(bounds.width, bounds.height)) * 0.02, 2)
for start in seen.indices where !seen[start] && darkness[start] > 0.5 {
    var area = 0, (ex0, ey0, ex1, ey1) = (w, h, 0, 0)
    seen[start] = true
    stack = [start]
    while let i = stack.popLast() {
        area += 1
        ex0 = min(ex0, i % w); ex1 = max(ex1, i % w); ey0 = min(ey0, i / w); ey1 = max(ey1, i / w)
        for (dx, dy) in neighbours {
            let x = i % w + dx, y = i / w + dy
            guard x >= 0, y >= 0, x < w, y < h, !seen[y * w + x], darkness[y * w + x] > 0.5 else { continue }
            seen[y * w + x] = true
            stack.append(y * w + x)
        }
    }
    if Double(area) >= minArea { eyes.append(CGRect(x: ex0, y: ey0, width: ex1 - ex0 + 1, height: ey1 - ey0 + 1)) }
}

// Silhouette: black + the original opacity; the eyes are cut out as their bounding ellipses, enlarged a little so they do not smear at menu bar size.
for i in 0..<(w * h) {
    px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0
    px[i * 4 + 3] = UInt8((alpha[i] * 255).rounded())
}
pixels.setBlendMode(.clear)
for eye in eyes {
    let grow = 1.35
    pixels.fillEllipse(in: CGRect(x: eye.midX - eye.width * grow / 2, y: Double(h) - eye.midY - eye.height * grow / 2,
                                  width: eye.width * grow, height: eye.height * grow))   // CGContext's y axis points up
}
let silhouette = pixels.makeImage()!.cropping(to: bounds)!

// 18pt high, width follows the picture: drawn at 8× first, then halved step by step down to @2x and 1x.
let height = 18
let width = Int((Double(height) * Double(silhouette.width) / Double(silhouette.height)).rounded(.up))
var mark: CGImage = {
    let ctx = canvas(width * 8, height * 8)
    let drawnWidth = Double(height * 8) * Double(silhouette.width) / Double(silhouette.height)
    ctx.draw(silhouette, in: CGRect(x: (Double(width * 8) - drawnWidth) / 2, y: 0, width: drawnWidth, height: Double(height * 8)))
    return ctx.makeImage()!
}()
mark = halved(halved(mark))
write(mark, resources.appendingPathComponent("menubar@2x.png"))
write(halved(mark), resources.appendingPathComponent("menubar.png"))
print("Icon: \(args[1]) (\(Int(bounds.width))×\(Int(bounds.height))), menu bar icon \(width)×\(height)pt, \(eyes.count) eye(s)")
