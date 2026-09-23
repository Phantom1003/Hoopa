import AppKit
import ApplicationServices

/// The basic ways of choosing a window, combined per anchor kind.
enum WindowMatch {
    /// Exact hit by window ID while the window is still open, unaffected by title changes.
    static func byID(_ windows: [AXUIElement], _ id: CGWindowID?) -> AXUIElement? {
        guard let id else { return nil }
        return windows.first { AX.windowID($0) == id }
    }

    /// Fuzzy title match: the window with the highest score above the threshold.
    static func byTitle(_ windows: [AXUIElement], _ targets: [String], threshold: Double = 0.25) -> AXUIElement? {
        let targets = targets.filter { !$0.isEmpty }
        guard !targets.isEmpty else { return nil }
        var best: (AXUIElement, Double)?
        for w in windows {
            let title = AX.title(w) ?? ""
            let s = targets.map { TitleMatch.score(title, $0) }.max() ?? 0
            if s > (best?.1 ?? threshold) { best = (w, s) }
        }
        return best?.0
    }

    /// Document window: AXDocument is the file path.
    static func byDocument(_ windows: [AXUIElement], _ path: String) -> AXUIElement? {
        windows.first { AX.string($0, kAXDocumentAttribute) == path }
    }

    static func only(_ windows: [AXUIElement]) -> AXUIElement? { windows.count == 1 ? windows[0] : nil }

    static func focused(_ app: AXUIElement) -> AXUIElement? { AX.element(app, kAXFocusedWindowAttribute) }
}
