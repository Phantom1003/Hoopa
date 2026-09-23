import AppKit
import CoreGraphics

/// A window on screen (from CGWindowList; no screen recording permission needed because we do not read window titles).
struct OnScreenWindow {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let bounds: CGRect   // CG coordinates
}

enum WindowList {
    /// The visible normal windows, front to back, excluding our own.
    static func frontToBack() -> [OnScreenWindow] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var out: [OnScreenWindow] = []
        for d in arr {
            guard let layer = (d[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard let pid = (d[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != me else { continue }
            guard let num = (d[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            guard let bd = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  bounds.width > 24, bounds.height > 24 else { continue }
            let alpha = (d[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }
            let owner = d[kCGWindowOwnerName as String] as? String ?? ""
            out.append(OnScreenWindow(id: num, pid: pid_t(pid), ownerName: owner, bounds: bounds))
        }
        return out
    }

    static func topWindow(at p: CGPoint) -> OnScreenWindow? {
        frontToBack().first { $0.bounds.contains(p) }
    }
}

/// Conversion between Cocoa (origin bottom left, y up) and CG (origin top left, y down) coordinates.
enum Coord {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cg(fromCocoa p: NSPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    static func cocoaRect(fromCG r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
