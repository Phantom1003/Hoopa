// Generates the app icon and the menu bar icon from pictures with a transparent background (run by build.sh):
//   swift scripts/icons.swift source.png menubar-source.png output.iconset ResourcesDir
// App icon: trim the transparent margin, centre on a square (5% padding on every side), emit every size from 16 to 1024, packed by iconutil.
// Menu bar icon: the dark parts of the menu bar source (the same picture in the normal colouring); a monochrome template (opacity only, the system tints it to the menu bar colours), 18pt high, plus @2x.
import AppKit

let args = CommandLine.arguments
guard args.count == 5,
      let source = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let markSource = NSImage(contentsOfFile: args[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("Usage: swift scripts/icons.swift source.png menubar-source.png output.iconset ResourcesDir\n".data(using: .utf8)!)
    exit(2)
}
let iconset = URL(fileURLWithPath: args[3]), resources = URL(fileURLWithPath: args[4])
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

/// Reads opacity and lightness per pixel (premultiplied RGBA; row 0 in memory is the top row of the picture), plus the bounding box of the opaque part (image coordinates, origin top left).
func analyse(_ image: CGImage) -> (pixels: CGContext, alpha: [Double], luminance: [Double], bounds: CGRect) {
    let w = image.width, h = image.height
    let ctx = canvas(w, h)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
    var alpha = [Double](repeating: 0, count: w * h), luminance = alpha
    var (x0, y0, x1, y1) = (w, h, -1, -1)
    for i in 0..<(w * h) where px[i * 4 + 3] > 0 {
        let a = Double(px[i * 4 + 3]) / 255
        alpha[i] = a
        if a > 0.03 { x0 = min(x0, i % w); x1 = max(x1, i % w); y0 = min(y0, i / w); y1 = max(y1, i / w) }
        let r = Double(px[i * 4]) / 255 / a, g = Double(px[i * 4 + 1]) / 255 / a, b = Double(px[i * 4 + 2]) / 255 / a
        luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
    guard x1 >= 0 else {
        FileHandle.standardError.write("The source picture is fully transparent\n".data(using: .utf8)!)
        exit(1)
    }
    return (ctx, alpha, luminance, CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1))
}

// MARK: App icon

let bounds = analyse(source).bounds
let picture = source.cropping(to: bounds)!
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

// After Shellder's menubar-template.swift: the whole picture uncropped, "darkness" as opacity, dark parts opaque, light parts transparent,
// with a short ramp in between (lightness up to 0.66 fully kept, from 0.74 fully dropped). Hoopa's hood, horns, eyes and outlines stay; the light grey face, hands and gold rings
// let the background through. No floor opacity under the light parts: with one, the whole figure turns grey. The source must be the normal colouring: in the shiny one the horns are as light as the face and would be dropped with it.
let mark = analyse(markSource)
let mpx = mark.pixels.data!.assumingMemoryBound(to: UInt8.self)
for i in 0..<(mark.pixels.width * mark.pixels.height) {
    let keep = max(0, min(1, (0.74 - mark.luminance[i]) / 0.08)) * mark.alpha[i]
    mpx[i * 4] = 0; mpx[i * 4 + 1] = 0; mpx[i * 4 + 2] = 0
    mpx[i * 4 + 3] = UInt8((keep * 255).rounded())
}
let silhouette = mark.pixels.makeImage()!.cropping(to: mark.bounds)!

// 18pt high, width follows the picture: drawn at 8× first, then halved step by step down to @2x and 1x.
let height = 18
let width = Int((Double(height) * Double(silhouette.width) / Double(silhouette.height)).rounded(.up))
var template: CGImage = {
    let ctx = canvas(width * 8, height * 8)
    let drawnWidth = Double(height * 8) * Double(silhouette.width) / Double(silhouette.height)
    ctx.draw(silhouette, in: CGRect(x: (Double(width * 8) - drawnWidth) / 2, y: 0, width: drawnWidth, height: Double(height * 8)))
    return ctx.makeImage()!
}()
template = halved(halved(template))
write(template, resources.appendingPathComponent("menubar@2x.png"))
write(halved(template), resources.appendingPathComponent("menubar.png"))
print("Icon: \(args[1]) (\(Int(bounds.width))×\(Int(bounds.height))), menu bar icon \(args[2]) (\(Int(mark.bounds.width))×\(Int(mark.bounds.height))) → \(width)×\(height)pt")
