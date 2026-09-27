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
        let t = summary.isEmpty ? (windowTitle.isEmpty ? String(localized: "(Untitled window)") : windowTitle) : summary
        return "\(appName) · \(t)"
    }

    /// The details shown in the hover tooltip.
    var detailDescription: String {
        let title = windowTitle.isEmpty ? String(localized: "(Untitled)") : windowTitle
        var lines = [String(localized: "App: \(appName)"), String(localized: "Window: \(title)")]
        for a in anchors {
            switch a {
            case .browserTab(let url, _): lines.append(String(localized: "Tab: \(url)"))
            case .document(let path): lines.append(String(localized: "Document: \(path)"))
            case .link(let url, _): lines.append(String(localized: "Link: \(url)"))
            case .element(let e): lines.append(String(localized: "Element: \(e.role) \(e.texts.first ?? "")"))
            case .window: break
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// A to-do's time: a countdown (N minutes from when it was set), a plain day, or a moment on a day.
enum Due: Codable, Equatable {
    case countdown(end: Date, minutes: Int)
    case date(Date)
    case dateTime(Date)

    var date: Date {
        switch self {
        case .countdown(let end, _): return end
        case .date(let d), .dateTime(let d): return d
        }
    }

    var isCountdown: Bool {
        if case .countdown = self { return true }
        return false
    }

    /// The notification moment: when the countdown ends; the moment itself for a date with a time; 9:00 that day for a plain date.
    var notifyAt: Date {
        switch self {
        case .countdown(let end, _), .dateTime(let end): return end
        case .date(let d): return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
        }
    }
}

/// A time setting not yet on a to-do: a countdown only keeps the minutes and starts ticking at the moment of submission.
enum DueSpec: Equatable {
    case countdown(minutes: Int)
    case dateTime(Date)

    func resolve(now: Date = Date()) -> Due {
        switch self {
        case .countdown(let m): return .countdown(end: now.addingTimeInterval(TimeInterval(m * 60)), minutes: m)
        case .dateTime(let d): return .dateTime(d)
        }
    }

    /// The setting derived back from an existing time (for editing). A plain date counts as 9:00 that day.
    init(_ due: Due) {
        switch due {
        case .countdown(_, let m): self = .countdown(minutes: m)
        case .dateTime(let d): self = .dateTime(d)
        case .date(let d): self = .dateTime(Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d)
        }
    }
}

/// When each part of a to-do last changed. A sync merge takes every part from the copy that changed it last, so a title edited on one Mac
/// and notes edited on another both survive; a part without a stamp counts as changed at the to-do's updatedAt (data from before the stamps).
struct FieldStamps: Codable, Equatable {
    var title: Date?
    var notes: Date?
    var done: Date?      // isDone and completedAt
    var binding: Date?
    var due: Date?       // due and dueSetAt
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String              // one line; the card and the collapsed list show only this
    var notes: String = ""         // the notes (multi-line), visible once the to-do is opened
    var isDone: Bool = false
    var createdAt: Date = Date()
    var completedAt: Date? = nil
    var binding: ContextBinding? = nil
    var due: Due? = nil
    var dueSetAt: Date? = nil      // when the time was set: the time ring's first lap starts here (missing in old data, falls back to createdAt)
    var updatedAt: Date = Date()   // the last change to any part: decides against a deletion in a sync merge, and stands in for missing part stamps
    var changed = FieldStamps()    // when each part last changed: the sync merge is per part (see TodoItem.merged)

    init(title: String, notes: String = "", binding: ContextBinding? = nil, due: Due? = nil) {
        self.title = title
        self.notes = notes
        self.binding = binding
        self.due = due
        dueSetAt = due == nil ? nil : Date()
        updatedAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, notes, isDone, createdAt, completedAt, binding, due, dueSetAt, updatedAt, changed }

    /// A binding in an old format that cannot be read counts as unbound; the whole file must stay readable.
    /// Old data may hold multi-line content: the first line becomes the title, the rest the notes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        let raw = try c.decode(String.self, forKey: .title)
        var notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        if let nl = raw.firstIndex(of: "\n") {
            title = raw[..<nl].trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = raw[raw.index(after: nl)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { notes = notes.isEmpty ? rest : rest + "\n" + notes }
        } else {
            title = raw
        }
        self.notes = notes
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        binding = try? c.decodeIfPresent(ContextBinding.self, forKey: .binding)
        due = try? c.decodeIfPresent(Due.self, forKey: .due)
        dueSetAt = try? c.decodeIfPresent(Date.self, forKey: .dueSetAt)
        // Old data has no change stamp: the latest moment it does record.
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? [createdAt, completedAt, dueSetAt].compactMap { $0 }.max()!
        changed = (try? c.decodeIfPresent(FieldStamps.self, forKey: .changed)) ?? FieldStamps()
    }

    /// Stamps the parts that differ from `before` with `now`: called after every edit, so each part carries its own change time.
    /// A to-do is stamped all or nothing: the first edit of one from before the stamps first gives every part its last change as the stamp.
    mutating func stamp(since before: TodoItem, at now: Date) {
        if changed == FieldStamps() {
            let u = before.updatedAt
            changed = FieldStamps(title: u, notes: u, done: u, binding: u, due: u)
        }
        if title != before.title { changed.title = now }
        if notes != before.notes { changed.notes = now }
        if isDone != before.isDone || completedAt != before.completedAt { changed.done = now }
        if binding != before.binding { changed.binding = now }
        if due != before.due || dueSetAt != before.dueSetAt { changed.due = now }
        updatedAt = now
    }

    /// A part's change time: its stamp, or the to-do's last change for a copy without stamps (data from before them).
    func time(_ stamp: Date?) -> Date { stamp ?? updatedAt }

    /// This copy and another copy of the same to-do into one: every part from the copy that changed it last (this one's on a tie).
    /// Stamps are kept all or nothing, so the result equals one of the inputs when nothing crossed over and merging it again changes nothing.
    func merged(with other: TodoItem) -> TodoItem {
        var out = self
        func pick(_ mine: Date?, _ theirs: Date?, _ take: (inout TodoItem) -> Void) -> Date? {
            let (tm, tt) = (time(mine), other.time(theirs))
            if tt > tm { take(&out) }
            return mine == nil && theirs == nil ? nil : max(tm, tt)
        }
        out.changed.title = pick(changed.title, other.changed.title) { $0.title = other.title }
        out.changed.notes = pick(changed.notes, other.changed.notes) { $0.notes = other.notes }
        out.changed.done = pick(changed.done, other.changed.done) { $0.isDone = other.isDone; $0.completedAt = other.completedAt }
        out.changed.binding = pick(changed.binding, other.changed.binding) { $0.binding = other.binding }
        out.changed.due = pick(changed.due, other.changed.due) { $0.due = other.due; $0.dueSetAt = other.dueSetAt }
        out.updatedAt = max(updatedAt, other.updatedAt)
        return out
    }
}

/// A deleted to-do's id and when it was deleted: kept for a while so that a sync merge with a copy that still has the to-do does not bring it back.
struct Tombstone: Codable, Equatable {
    var id: UUID
    var at: Date
}

/// The to-do file: the to-dos in list order, the recent deletions and when the list was last reordered by hand
/// (in a sync merge the order of the copy reordered more recently wins). A file from before sync is a bare array of to-dos and still loads.
struct TodoDocument: Codable, Equatable {
    var todos: [TodoItem] = []
    var deleted: [Tombstone] = []
    var orderedAt: Date? = nil

    init(todos: [TodoItem] = [], deleted: [Tombstone] = [], orderedAt: Date? = nil) {
        self.todos = todos
        self.deleted = deleted
        self.orderedAt = orderedAt
    }

    private enum CodingKeys: String, CodingKey { case todos, deleted, orderedAt }

    init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([TodoItem].self) {
            todos = list
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todos = try c.decodeIfPresent([TodoItem].self, forKey: .todos) ?? []
        deleted = (try? c.decodeIfPresent([Tombstone].self, forKey: .deleted)) ?? []
        orderedAt = try? c.decodeIfPresent(Date.self, forKey: .orderedAt)
    }

    /// Dates as ISO 8601 (whole seconds), keys sorted: the same content gives the same bytes, which is how the sync file is told apart from our own last write.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func encoded() throws -> Data { try Self.encoder.encode(self) }
    static func decode(_ data: Data) throws -> TodoDocument { try decoder.decode(TodoDocument.self, from: data) }
}
