import Foundation
import Combine

/// The to-do source: memory + JSON persistence (~/Library/Application Support/Hoopa/todos.json).
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []

    private let fileURL: URL
    private var saveWorkItem: DispatchWorkItem?

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

    func setDue(_ due: Due?, for id: UUID) {
        mutate(id) { $0.due = due }
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
        scheduleSave()
    }

    func clearDone() {
        todos.filter { $0.isDone }.forEach { Notifier.cancel($0.id) }
        todos.removeAll { $0.isDone }
        scheduleSave()
    }

    /// Delete all: every to-do, completed ones included.
    func deleteAll() {
        todos.forEach { Notifier.cancel($0.id) }
        todos.removeAll()
        scheduleSave()
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
        scheduleSave()
        return stillByTime
    }

    func move(from source: IndexSet, to destination: Int) {
        var act = active
        act.move(fromOffsets: source, toOffset: destination)
        todos = act + todos.filter { $0.isDone }
        scheduleSave()
    }

    func item(_ id: UUID) -> TodoItem? { todos.first { $0.id == id } }

    private func mutate(_ id: UUID, _ block: (inout TodoItem) -> Void) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        var item = todos[idx]
        block(&item)
        todos[idx] = item
        Notifier.schedule(item)
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let list = try? decoder.decode([TodoItem].self, from: data) {
            todos = list
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let snapshot = todos
        let url = fileURL
        let work = DispatchWorkItem {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.write("Save failed \(error)")
            }
        }
        saveWorkItem = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
