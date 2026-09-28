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

/// A change time for the sync merge: a hybrid logical clock stamp. Ordered by the physical time, then a counter, then the Mac that made it.
/// Every stamp a Mac makes is later than every stamp it has seen (see HybridClock), so a change made after another arrived always wins over it,
/// whatever the two clocks say; wall time only orders changes made without knowledge of each other.
/// Written as "2026-09-27T05:45:12.345Z/3/8f3a2c"; a plain date (files from before the clock) reads as counter 0 from nowhere.
struct Stamp: Codable, Equatable, Hashable, Comparable {
    var time: Int64      // milliseconds since 1970
    var counter: Int
    var node: String

    static let zero = Stamp(time: 0, counter: 0, node: "")

    init(time: Int64, counter: Int, node: String) {
        self.time = time
        self.counter = counter
        self.node = node
    }

    init(date: Date) {
        self.init(time: Int64((date.timeIntervalSince1970 * 1000).rounded()), counter: 0, node: "")
    }

    var date: Date { Date(timeIntervalSince1970: TimeInterval(time) / 1000) }

    static func < (a: Stamp, b: Stamp) -> Bool {
        (a.time, a.counter, a.node) < (b.time, b.counter, b.node)
    }

    /// Whole seconds go through the system formatter; the milliseconds are appended by hand (the formatter's fractional seconds do not round trip).
    private static let formatter = ISO8601DateFormatter()

    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        var clockText = String(parts[0])
        var millis: Int64 = 0
        if let dot = clockText.firstIndex(of: "."), let z = clockText.lastIndex(of: "Z") {
            let digits = String(clockText[clockText.index(after: dot)..<z]).prefix(3)
            millis = Int64(digits.padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
            clockText.removeSubrange(dot..<z)
        }
        guard let date = Self.formatter.date(from: clockText) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a stamp: \(text)"))
        }
        self.init(time: Int64(date.timeIntervalSince1970.rounded()) * 1000 + millis, counter: 0, node: "")
        if parts.count == 3 {
            counter = Int(parts[1]) ?? 0
            node = String(parts[2])
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        var clockText = Self.formatter.string(from: Date(timeIntervalSince1970: TimeInterval(time / 1000)))
        clockText.removeLast()   // the Z
        try c.encode(String(format: "%@.%03dZ/%d/%@", clockText, Int(time % 1000), counter, node))
    }
}

/// This Mac's hybrid logical clock: the source of every stamp made here. A new stamp is the wall time when that is ahead of everything seen,
/// otherwise the last stamp with the counter moved on; a stamp that arrives from another Mac moves the clock past it first.
/// The Mac's id and the last stamp (time and counter) are kept in the preferences, so neither a wall clock set back nor a relaunch while
/// the clock is held past the wall by a stamp seen makes old stamps again.
final class HybridClock {
    private static let nodeKey = "syncNode", timeKey = "syncClock", counterKey = "syncCounter"
    let node: String
    private(set) var last: Stamp

    init() {
        let defaults = UserDefaults.standard
        if let n = defaults.string(forKey: Self.nodeKey), !n.isEmpty {
            node = n
        } else {
            node = String(UUID().uuidString.prefix(6)).lowercased()
            defaults.set(node, forKey: Self.nodeKey)
        }
        last = Stamp(time: defaults.object(forKey: Self.timeKey) as? Int64 ?? 0, counter: defaults.integer(forKey: Self.counterKey), node: node)
    }

    private static var wall: Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    /// A stamp later than every stamp made or seen so far.
    func now() -> Stamp {
        let wall = Self.wall
        last = wall > last.time ? Stamp(time: wall, counter: 0, node: node) : Stamp(time: last.time, counter: last.counter + 1, node: node)
        remember()
        return last
    }

    /// A stamp from another Mac: the next stamp made here comes after it.
    func observe(_ seen: Stamp) {
        guard seen > last else { return }
        if seen.time - Self.wall > 3600_000 { Log.write("Sync: a stamp from \(seen.node) is \((seen.time - Self.wall) / 60_000) min ahead of this Mac's clock") }
        last = Stamp(time: seen.time, counter: seen.counter, node: node)
        remember()
    }

    private func remember() {
        let defaults = UserDefaults.standard
        defaults.set(last.time, forKey: Self.timeKey)
        defaults.set(last.counter, forKey: Self.counterKey)
    }
}

/// When each part of a to-do last changed. A sync merge takes every part from the copy that changed it last, so a title edited on one Mac
/// and notes edited on another both survive. Every part always carries a stamp: data from before the stamps gets its last change for all five.
struct FieldStamps: Codable, Equatable {
    var title: Stamp
    var notes: Stamp
    var done: Stamp      // isDone and completedAt
    var binding: Stamp
    var due: Stamp       // due and dueSetAt

    init(all stamp: Stamp) {
        (title, notes, done, binding, due) = (stamp, stamp, stamp, stamp, stamp)
    }

    /// The last change to any part: decides against a deletion in a sync merge.
    var latest: Stamp { max(title, notes, done, binding, due) }
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
    var changed: FieldStamps       // when each part last changed: the sync merge is per part (see merged)

    /// The last change to any part.
    var updatedAt: Stamp { changed.latest }

    /// `stamp`: the new to-do's change stamp, from the store's clock; the wall time stands in where there is none.
    init(title: String, notes: String = "", binding: ContextBinding? = nil, due: Due? = nil, stamp: Stamp? = nil) {
        self.title = title
        self.notes = notes
        self.binding = binding
        self.due = due
        dueSetAt = due == nil ? nil : Date()
        changed = FieldStamps(all: stamp ?? Stamp(date: createdAt))
    }

    private enum CodingKeys: String, CodingKey { case id, title, notes, isDone, createdAt, completedAt, binding, due, dueSetAt, changed }
    /// Written by the versions between the first stamps and the clock: the last change of the whole to-do.
    private enum OldKeys: String, CodingKey { case updatedAt }

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
        // Data without part stamps: every part counts as changed at the latest moment the to-do does record.
        let whole = (try? decoder.container(keyedBy: OldKeys.self).decodeIfPresent(Stamp.self, forKey: .updatedAt))
            ?? Stamp(date: [createdAt, completedAt, dueSetAt].compactMap { $0 }.max()!)
        changed = (try? c.decodeIfPresent(FieldStamps.self, forKey: .changed)) ?? FieldStamps(all: whole)
    }

    /// Stamps the parts that differ from `before` with `now`: called after every edit, so each part carries its own change time.
    mutating func stamp(since before: TodoItem, at now: Stamp) {
        if title != before.title { changed.title = now }
        if notes != before.notes { changed.notes = now }
        if isDone != before.isDone || completedAt != before.completedAt { changed.done = now }
        if binding != before.binding { changed.binding = now }
        if due != before.due || dueSetAt != before.dueSetAt { changed.due = now }
    }

    /// This copy and another copy of the same to-do into one: every part from the copy that changed it last (this one's on a tie).
    /// The result is this copy when nothing crossed over, so merging the same copies again changes nothing.
    func merged(with other: TodoItem) -> TodoItem {
        var out = self
        if other.changed.title > changed.title { out.title = other.title; out.changed.title = other.changed.title }
        if other.changed.notes > changed.notes { out.notes = other.notes; out.changed.notes = other.changed.notes }
        if other.changed.done > changed.done { out.isDone = other.isDone; out.completedAt = other.completedAt; out.changed.done = other.changed.done }
        if other.changed.binding > changed.binding { out.binding = other.binding; out.changed.binding = other.changed.binding }
        if other.changed.due > changed.due { out.due = other.due; out.dueSetAt = other.dueSetAt; out.changed.due = other.changed.due }
        return out
    }
}

/// The to-do file: the to-dos in list order, the recent deletions (id → when, kept for 90 days so that a sync merge with a copy that still has
/// the to-do does not bring it back) and when the list was last reordered by hand (in a sync merge the order of the copy reordered more recently wins).
/// A file from before sync is a bare array of to-dos and still loads.
struct TodoDocument: Codable, Equatable {
    var todos: [TodoItem] = []
    var deleted: [String: Stamp] = [:]
    var orderedAt: Stamp? = nil

    /// The latest stamp anywhere in the document: what a Mac's clock must get past when the document arrives from another Mac.
    var latest: Stamp? { (todos.map(\.updatedAt) + deleted.values + [orderedAt].compactMap { $0 }).max() }

    init(todos: [TodoItem] = [], deleted: [String: Stamp] = [:], orderedAt: Stamp? = nil) {
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
        deleted = (try? c.decodeIfPresent([String: Stamp].self, forKey: .deleted)) ?? [:]
        orderedAt = try? c.decodeIfPresent(Stamp.self, forKey: .orderedAt)
    }

    /// Dates as ISO 8601 (whole seconds), keys sorted: the same content gives the same bytes, which is how the sync file is told apart from our own last write.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
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
