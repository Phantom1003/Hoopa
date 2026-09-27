import Foundation
import Combine

/// The to-do source: memory + JSON persistence (~/Library/Application Support/Hoopa/todos.json).
/// With sync on, the same document is mirrored into the sync folder (see SyncFolder) and every outside change to that copy is merged back in:
/// each part of a to-do from the copy that changed it last, a deletion beats every change before it, and the order comes from the copy reordered more recently.
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []
    /// Where the to-dos are mirrored for other Macs; .off keeps them on this Mac only.
    @Published private(set) var syncMode: SyncMode = .off
    /// One-liners for the user (the toast at the bottom of the panel): sync switched on or off, a folder that could not be used.
    var notify: ((String) -> Void)?

    private let fileURL: URL
    /// Recent deletions: a merge must not bring back a to-do another Mac still has because it has not seen the deletion yet.
    private var deleted: [Tombstone] = []
    /// When the list was last reordered by hand.
    private var orderedAt: Date?
    private var saveWorkItem: DispatchWorkItem?
    private var sync: SyncFolder?
    private var syncWorkItem: DispatchWorkItem?
    /// Whether the last write to the sync folder failed: the toast is shown once per run of failures, not on every save.
    private var syncFailed = false
    private static let tombstoneLife: TimeInterval = 90 * 24 * 3600

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Hoopa", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("todos.json")
        load()
    }

    var active: [TodoItem] { todos.filter { !$0.isDone } }
    var done: [TodoItem] { todos.filter { $0.isDone }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) } }

    // MARK: - Operations

    @discardableResult
    /// Any one of content, binding or time is enough to create.
    func add(_ title: String, binding: ContextBinding? = nil, due: Due? = nil) -> TodoItem? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || binding != nil || due != nil else { return nil }
        let item = TodoItem(title: t, binding: binding, due: due)
        todos.insert(item, at: 0)
        Notifier.schedule(item)
        scheduleSave()
        return item
    }

    /// A changed time records a new set-at moment: the time ring's first lap starts full from now.
    func setDue(_ due: Due?, for id: UUID) {
        mutate(id) { $0.due = due; $0.dueSetAt = due == nil ? nil : Date() }
    }

    /// The order while collapsed, and while expanded with "sort by time" on: timed to-dos soonest first, the rest in list order.
    var byUrgency: [TodoItem] { Self.urgencyOrder(active) }

    private static func urgencyOrder(_ items: [TodoItem]) -> [TodoItem] {
        let timed = items.filter { $0.due != nil }.sorted { $0.due!.date < $1.due!.date }
        return timed + items.filter { $0.due == nil }
    }

    func toggleDone(_ id: UUID) {
        mutate(id) { item in
            item.isDone.toggle()
            item.completedAt = item.isDone ? Date() : nil
        }
    }

    /// The title is saved as it is typed (may be empty).
    func rename(_ id: UUID, to title: String) {
        mutate(id) { $0.title = title }
    }

    /// The notes are saved as they are typed.
    func setNotes(_ notes: String, for id: UUID) {
        mutate(id) { $0.notes = notes }
    }

    func setBinding(_ binding: ContextBinding?, for id: UUID) {
        mutate(id) { $0.binding = binding }
    }

    func delete(_ id: UUID) {
        Notifier.cancel(id)
        todos.removeAll { $0.id == id }
        bury([id])
        scheduleSave()
    }

    func clearDone() {
        let gone = todos.filter { $0.isDone }
        gone.forEach { Notifier.cancel($0.id) }
        todos.removeAll { $0.isDone }
        bury(gone.map(\.id))
        scheduleSave()
    }

    /// Delete all: every to-do, completed ones included.
    func deleteAll() {
        todos.forEach { Notifier.cancel($0.id) }
        bury(todos.map(\.id))
        todos.removeAll()
        scheduleSave()
    }

    /// Records deletions for the sync merge; tombstones older than 90 days are let go (a Mac away for longer than that sees such a to-do come back).
    private func bury(_ ids: [UUID]) {
        let now = Date()
        deleted.removeAll { $0.at < now - Self.tombstoneLife || ids.contains($0.id) }
        deleted += ids.map { Tombstone(id: $0, at: now) }
    }

    /// Moves dragged before target (after = false) or after it.
    func move(_ dragged: UUID, relativeTo target: UUID, after: Bool) {
        var act = active
        guard let from = act.firstIndex(where: { $0.id == dragged }) else { return }
        let item = act.remove(at: from)
        guard var to = act.firstIndex(where: { $0.id == target }) else { return }
        if after { to += 1 }
        act.insert(item, at: to)
        todos = act + todos.filter { $0.isDone }
        orderedAt = Date()
        scheduleSave()
    }

    /// A drag while sorted by time: moves dragged before / after target in the order on screen (byUrgency).
    /// If the result still respects time order (only untimed to-dos, or ones with the same time, swapped places), only their relative order changes, returns true and the time sort continues;
    /// otherwise the order on screen after the move becomes the list order and it returns false (back to manual order, the list does not jump).
    func moveByUrgency(_ dragged: UUID, relativeTo target: UUID, after: Bool) -> Bool {
        var order = byUrgency
        guard let from = order.firstIndex(where: { $0.id == dragged }) else { return true }
        let item = order.remove(at: from)
        guard var to = order.firstIndex(where: { $0.id == target }) else { return true }
        if after { to += 1 }
        order.insert(item, at: to)
        // To-dos with the same time (or no time) keep their slots in the list and are filled back in the order after the move.
        var groups = Dictionary(grouping: order) { $0.due?.date }
        let refilled = active.map { groups[$0.due?.date]!.removeFirst() }
        let stillByTime = Self.urgencyOrder(refilled).map(\.id) == order.map(\.id)
        todos = (stillByTime ? refilled : order) + todos.filter { $0.isDone }
        orderedAt = Date()
        scheduleSave()
        return stillByTime
    }

    func move(from source: IndexSet, to destination: Int) {
        var act = active
        act.move(fromOffsets: source, toOffset: destination)
        todos = act + todos.filter { $0.isDone }
        orderedAt = Date()
        scheduleSave()
    }

    func item(_ id: UUID) -> TodoItem? { todos.first { $0.id == id } }

    private func mutate(_ id: UUID, _ block: (inout TodoItem) -> Void) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        var item = todos[idx]
        block(&item)
        item.stamp(since: todos[idx], at: Date())
        todos[idx] = item
        Notifier.schedule(item)
        scheduleSave()
    }

    // MARK: - Persistence

    /// Everything the file holds.
    private var document: TodoDocument { TodoDocument(todos: todos, deleted: deleted, orderedAt: orderedAt) }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let doc = try? TodoDocument.decode(data) {
            todos = doc.todos
            deleted = doc.deleted
            orderedAt = doc.orderedAt
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = document
        let url = fileURL
        let work = DispatchWorkItem {
            do {
                try snapshot.encoded().write(to: url, options: .atomic)
            } catch {
                Log.write("Save failed \(error)")
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
        scheduleSyncWrite()
    }

    /// Writes whatever is still pending, now: called when the app quits (and before the updater relaunches it).
    func flush() {
        // Run first, cancel after: a cancelled work item does nothing when performed.
        if let work = saveWorkItem { saveWorkItem = nil; work.perform(); work.cancel() }
        if let sync, let work = syncWorkItem { syncWorkItem = nil; sync.queue.sync { work.perform() }; work.cancel() }
    }

    // MARK: - Sync

    /// Picks up the mode saved last time; called once the toast is wired up, so that a folder that has gone missing is reported.
    func startSync() {
        let mode = SyncMode.load()
        guard mode != .off else { return }
        setSync(mode, announce: false)
    }

    /// Switches the mirror. Off leaves the copy in the folder for the other Macs. On, the folder is created when missing and its copy merged into this one straight away.
    /// A folder that cannot be used (no iCloud Drive on this Mac, a volume not mounted) leaves the mode as it was.
    func setSync(_ mode: SyncMode, announce: Bool = true) {
        if mode == .off {
            syncWorkItem?.cancel()
            sync?.stop()
            sync = nil
            syncMode = .off
            mode.save()
            Log.write("Sync: off")
            if announce { notify?(String(localized: "Sync is off; to-dos stay on this Mac")) }
            return
        }
        guard let folder = mode.folder else { return }
        let s = SyncFolder(folder: folder)
        do {
            try s.start()
        } catch {
            Log.write("Sync: cannot use \(folder.path): \(error)")
            switch mode {
            case .iCloudDrive: notify?(String(localized: "iCloud Drive is not available on this Mac"))
            default: notify?(String(localized: "The sync folder is not available: \(folder.lastPathComponent)"))
            }
            return
        }
        syncWorkItem?.cancel()
        sync?.stop()
        sync = s
        syncMode = mode
        mode.save()
        syncFailed = false
        s.onChange = { [weak self] in self?.pull() }
        Log.write("Sync: folder \(folder.path)")
        if announce {
            switch mode {
            case .iCloudDrive: notify?(String(localized: "Syncing via iCloud Drive"))
            default: notify?(String(localized: "Syncing with the folder \(folder.lastPathComponent)"))
            }
        }
        pull()
    }

    /// Reads the copy in the sync folder (and any conflict versions) and merges it in on the main thread. Nothing is written back unless our copy holds more.
    private func pull() {
        guard let s = sync else { return }
        s.queue.async { [weak self] in
            let data: Data?
            do {
                data = try s.read()
            } catch {
                Log.write("Sync: cannot read \(s.fileURL.path): \(error)")
                s.blocked = true
                return
            }
            var copies: [Data] = []
            if let data { copies.append(data) }
            copies += s.takeConflictVersions()
            // Only our own last write, or a copy already merged: nothing to do. (No file at all: ours gets written, see apply.)
            if let data, data == s.lastData, copies.count <= 1 {
                // Readable again after an unreadable spell: the changes held back meanwhile go out.
                if s.blocked { s.blocked = false; DispatchQueue.main.async { self?.scheduleSyncWrite() } }
                return
            }
            var docs: [TodoDocument] = []
            for d in copies {
                do {
                    docs.append(try TodoDocument.decode(d))
                } catch {
                    // A copy that cannot be read (another app version, a half-written file) is left alone and not overwritten with ours.
                    Log.write("Sync: cannot decode \(s.fileURL.lastPathComponent): \(error)")
                    s.blocked = true
                    return
                }
            }
            // Only bytes that decoded count as seen, so an unreadable copy is read again next time and a readable one lifts the block.
            s.lastData = data
            s.blocked = false
            DispatchQueue.main.async { self?.apply(docs, fresh: data == nil) }
        }
    }

    /// Merges the copies read from the sync folder. `fresh`: there was no file yet, ours is written as the first.
    private func apply(_ docs: [TodoDocument], fresh: Bool) {
        var changed = false
        for doc in docs where merge(doc) { changed = true }
        if changed {
            Log.write("Sync: merged in \(docs.count) cop\(docs.count == 1 ? "y" : "ies"), \(todos.count) to-do(s) now")
            saveWorkItem?.cancel()
            let snapshot = document
            let url = fileURL
            DispatchQueue.global(qos: .utility).async {
                do { try snapshot.encoded().write(to: url, options: .atomic) } catch { Log.write("Save failed \(error)") }
            }
        } else if fresh {
            Log.write("Sync: no file in the folder yet, writing ours")
        }
        // Our copy may hold more than the file (to-dos made while offline, deletions the other Mac has not seen): the write compares and skips when equal.
        scheduleSyncWrite()
    }

    /// Merges another copy into this one; returns whether anything here changed. Notifications follow the to-dos that changed.
    private func merge(_ other: TodoDocument) -> Bool {
        let mine = document
        let merged = Self.merge(mine, other)
        guard merged != mine else { return false }
        let before = Dictionary(uniqueKeysWithValues: todos.map { ($0.id, $0) })
        for item in merged.todos where before[item.id] != item { Notifier.schedule(item) }
        for id in before.keys where !merged.todos.contains(where: { $0.id == id }) { Notifier.cancel(id) }
        todos = merged.todos
        deleted = merged.deleted
        orderedAt = merged.orderedAt
        return true
    }

    /// Two copies of the document into one (a: ours, b: the one read from the folder), so that every Mac settles on the same result:
    /// per to-do part by part, each from the copy that changed it last (a's on a tie, see TodoItem.merged);
    /// a deletion beats every change before it, a change after the deletion brings the to-do back;
    /// the order of the copy reordered more recently, with the to-dos only the other copy has on top. Neither reordered since the other: the copy that
    /// has seen more (to-dos plus deletions) is the later state and keeps its order; the same count, b's.
    static func merge(_ a: TodoDocument, _ b: TodoDocument) -> TodoDocument {
        var tombs: [UUID: Date] = [:]
        for t in a.deleted + b.deleted { tombs[t.id] = max(tombs[t.id] ?? .distantPast, t.at) }
        var items: [UUID: TodoItem] = [:]
        for item in b.todos { items[item.id] = item }
        for item in a.todos { items[item.id] = items[item.id].map { item.merged(with: $0) } ?? item }
        for (id, at) in tombs {
            guard let item = items[id] else { continue }
            if item.updatedAt > at { tombs[id] = nil } else { items[id] = nil }
        }
        let (ta, tb) = (a.orderedAt ?? .distantPast, b.orderedAt ?? .distantPast)
        let aLeads = ta != tb ? ta > tb : a.todos.count + a.deleted.count > b.todos.count + b.deleted.count
        let (base, rest) = aLeads ? (a, b) : (b, a)
        let baseIDs = Set(base.todos.map(\.id))
        let order = rest.todos.map(\.id).filter { !baseIDs.contains($0) } + base.todos.map(\.id)
        let orderedAt = [a.orderedAt, b.orderedAt].compactMap { $0 }.max()
        return TodoDocument(todos: order.compactMap { items[$0] },
                            deleted: tombs.map { Tombstone(id: $0.key, at: $0.value) }.sorted { ($0.at, $0.id.uuidString) < ($1.at, $1.id.uuidString) },
                            orderedAt: orderedAt)
    }

    /// Writes the document into the sync folder a moment after the last change (typing saves on every keystroke; iCloud need not see each one).
    /// Skipped when the file already holds the same bytes.
    private func scheduleSyncWrite() {
        guard let s = sync else { return }
        syncWorkItem?.cancel()
        let snapshot = document
        let work = DispatchWorkItem { [weak self] in
            guard !s.blocked else { Log.write("Sync: the copy in the folder could not be read, not writing over it"); return }
            do {
                let data = try snapshot.encoded()
                guard data != s.lastData else { return }
                try s.write(data)
                Log.write("Sync: wrote \(snapshot.todos.count) to-do(s) to \(s.fileURL.path)")
                DispatchQueue.main.async { self?.syncFailed = false }
            } catch {
                Log.write("Sync: write failed \(error)")
                DispatchQueue.main.async {
                    guard let self, !self.syncFailed else { return }
                    self.syncFailed = true
                    self.notify?(String(localized: "Sync failed: \(error.localizedDescription)"))
                }
            }
        }
        syncWorkItem = work
        s.queue.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
}
