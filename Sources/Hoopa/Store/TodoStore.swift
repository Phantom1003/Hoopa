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
    func add(_ title: String) -> TodoItem? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let item = TodoItem(title: t)
        todos.insert(item, at: 0)
        scheduleSave()
        return item
    }

    func toggleDone(_ id: UUID) {
        mutate(id) { item in
            item.isDone.toggle()
            item.completedAt = item.isDone ? Date() : nil
        }
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        mutate(id) { $0.title = t }
    }

    func setBinding(_ binding: ContextBinding?, for id: UUID) {
        mutate(id) { $0.binding = binding }
    }

    func delete(_ id: UUID) {
        todos.removeAll { $0.id == id }
        scheduleSave()
    }

    func clearDone() {
        todos.removeAll { $0.isDone }
        scheduleSave()
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
