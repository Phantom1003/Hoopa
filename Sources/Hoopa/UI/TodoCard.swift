import SwiftUI

/// A to-do: a sticky-note card; the title is editable at any time, the binding chip jumps on click, the time chip changes the time on click.
struct TodoCard: View {
    let todo: TodoItem
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var hovering = false
    @State private var draft = ""
    @State private var showDue = false
    @FocusState private var editing: Bool

    private var isJumping: Bool { coordinator.jumpingID == todo.id }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggleDone(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(todo.isDone ? Style.accent : Style.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                TextField("To-do", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(todo.isDone ? Style.secondary : Style.text)
                    .strikethrough(todo.isDone, color: Style.secondary)
                    .lineLimit(1...6)
                    .focused($editing)
                    .onSubmit { commit(); editing = false }
                    .onChange(of: editing) { _, on in if !on { commit() } }
                    .onChange(of: todo.title) { _, t in if !editing { draft = t } }

                HStack(spacing: 6) {
                    if let b = todo.binding {
                        Button { coordinator.jump(todo) } label: { BindingChip(binding: b, jumping: isJumping) }
                            .buttonStyle(.plain)
                            .help(b.detailDescription)
                    }
                    if let d = todo.due {
                        Button { showDue = true } label: { DueChip(due: d) }.buttonStyle(.plain)
                    }
                    if hovering {
                        if todo.due == nil {
                            Button { showDue = true } label: { Image(systemName: "timer") }
                                .buttonStyle(.plain).foregroundStyle(Style.secondary).help("Countdown / Date")
                        }
                        Button { coordinator.bind(todo) } label: {
                            Image(systemName: todo.binding == nil ? "scope" : "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.plain).foregroundStyle(Style.secondary)
                        .help(todo.binding == nil ? "Bind to Window / Page" : "Rebind")
                        Button { store.delete(todo.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(Style.secondary).help("Delete")
                    }
                }
                .font(.system(size: 12))
                .popover(isPresented: $showDue) {
                    DuePicker(due: Binding(get: { todo.due }, set: { store.setDue($0, for: todo.id) })) { showDue = false }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(hovering ? Style.cardHover : Style.card))
        .onHover { hovering = $0 }
        .onAppear { draft = todo.title }
        .contextMenu {
            if todo.binding != nil {
                Button("Jump to Bound Page") { coordinator.jump(todo) }
                Button("Rebind…") { coordinator.bind(todo) }
                Button("Unbind") { store.setBinding(nil, for: todo.id) }
            } else {
                Button("Bind to Window / Page…") { coordinator.bind(todo) }
            }
            Button("Countdown / Date…") { showDue = true }
            if todo.due != nil { Button("Clear Time") { store.setDue(nil, for: todo.id) } }
            Divider()
            Button(todo.isDone ? "Mark as Not Done" : "Mark as Done") { store.toggleDone(todo.id) }
            Button("Delete", role: .destructive) { store.delete(todo.id) }
        }
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { draft = todo.title } else if t != todo.title { store.rename(todo.id, to: t) }
    }
}
