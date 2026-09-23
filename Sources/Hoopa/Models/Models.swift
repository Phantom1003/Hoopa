import Foundation

/// A path from the window to the target element (walked first when restoring; a full-tree search is the fallback).
struct AXPathStep: Codable, Equatable {
    var role: String
    var index: Int
    var label: String?
}

/// Accessibility element anchor: found and triggered again through the system's Accessibility API.
struct AXAnchor: Codable, Equatable {
    var role: String
    var subrole: String?
    var label: String?
    var text: String?             // the plain text inside the element (the label may carry a changing status prefix, "Idle moir" → "moir")
    var domID: String?            // the id of a Chromium web element (AXDOMIdentifier); searched first when present
    var path: [AXPathStep] = []
    var tabs: [String] = []       // the tab panels the target lives in (outermost first); switched back to before jumping
    var column: [Double]? = nil   // relative position in the window [x, y, w, h] (0…1): picks among same-named targets and decides which column to scroll

    /// The text used to find the target and to confirm afterwards: the inner plain text first.
    var texts: [String] {
        var out: [String] = []
        for t in [text, label] {
            if let t = t?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !out.contains(t) { out.append(t) }
        }
        return out
    }
}

/// One "anchor" back to a page. Binding records every anchor available, most reliable first, and jumping tries them in the same order:
/// the app's public interfaces (scripting, files, documented links) → the Accessibility element → the window.
enum Anchor: Codable, Equatable {
    case browserTab(url: String, title: String)   // switch the tab through the browser's AppleScript interface
    case document(path: String)                   // ask the app to reopen the file (the window's AXDocument)
    case link(url: String, expect: String?)       // a link format from the app's official documentation (Slack, Obsidian); expect is used to confirm
    case element(AXAnchor)                        // an Accessibility element
    case window                                   // the window only

    var kindLabel: String {
        switch self {
        case .browserTab: return "tab"
        case .document: return "document"
        case .link: return "link"
        case .element: return "element"
        case .window: return "window"
        }
    }
}

/// A to-do's binding to a "work context".
struct ContextBinding: Codable, Equatable {
    var appName: String
    var bundleID: String
    var appPath: String?
    var windowTitle: String
    var windowID: UInt32?
    var anchors: [Anchor] = [.window]
    var summary: String = ""      // the target's name shown on the chip (tab title / file name / conversation name / element text / window title)
    var capturedAt: Date = Date()

    var primary: Anchor { anchors.first ?? .window }

    var shortDescription: String {
        let t = summary.isEmpty ? (windowTitle.isEmpty ? "(untitled window)" : windowTitle) : summary
        return "\(appName) · \(t)"
    }

    /// The details shown in the hover tooltip.
    var detailDescription: String {
        var lines = ["App: \(appName)", "Window: \(windowTitle.isEmpty ? "(untitled)" : windowTitle)"]
        for a in anchors {
            switch a {
            case .browserTab(let url, _): lines.append("Tab: \(url)")
            case .document(let path): lines.append("Document: \(path)")
            case .link(let url, _): lines.append("Link: \(url)")
            case .element(let e): lines.append("Element: \(e.role) \(e.texts.first ?? "")")
            case .window: break
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// A to-do's time: a countdown (N minutes from when it was set) or a plain day.
enum Due: Codable, Equatable {
    case countdown(end: Date, minutes: Int)
    case date(Date)

    var date: Date {
        switch self {
        case .countdown(let end, _): return end
        case .date(let d): return d
        }
    }

    var isCountdown: Bool {
        if case .countdown = self { return true }
        return false
    }

    /// The notification moment: when the countdown ends; 9:00 that day for a date.
    var notifyAt: Date {
        switch self {
        case .countdown(let end, _): return end
        case .date(let d): return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
        }
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var binding: ContextBinding? = nil
    var due: Due? = nil

    init(title: String, binding: ContextBinding? = nil, due: Due? = nil) {
        self.title = title
        self.binding = binding
        self.due = due
    }

    private enum CodingKeys: String, CodingKey { case id, title, isDone, createdAt, completedAt, binding, due }

    /// A binding in an old format that cannot be read counts as unbound; the whole file must stay readable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        binding = try? c.decodeIfPresent(ContextBinding.self, forKey: .binding)
        due = try? c.decodeIfPresent(Due.self, forKey: .due)
    }
}
