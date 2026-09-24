import SwiftUI

/// A to-do: a sticky-note card. The first row holds the done box, the binding chip (click to jump), the time chip (click to change the time) and the hover actions;
/// the second row is the content, editable at any time. Styled like the creation card.
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { store.toggleDone(todo.id) } label: {
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(todo.isDone ? Style.accent : Style.secondary)
                }
                .buttonStyle(.plain)

                if let b = todo.binding {
                    Button { coordinator.jump(todo) } label: { BindingChip(binding: b, jumping: isJumping) }
                        .buttonStyle(.plain)
                        .help(b.detailDescription)
                }
                if let d = todo.due {
                    Button { showDue.toggle() } label: { DueChip(due: d) }
                        .buttonStyle(.plain)
                        .help("Change time")
                }
                Spacer(minLength: 0)
                if hovering {
                    HStack(spacing: 8) {
                        if todo.due == nil {
                            Button { showDue.toggle() } label: { Image(systemName: "timer") }
                                .help("Timer / date")
                        }
                        Button { coordinator.bind(todo) } label: {
                            Image(systemName: todo.binding == nil ? "scope" : "arrow.triangle.2.circlepath")
                        }
                        .help(todo.binding == nil ? "Bind to a window / page" : "Rebind")
                        Button { store.delete(todo.id) } label: { Image(systemName: "trash") }
                            .help("Delete")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Style.secondary)
                    .font(.system(size: 12))
                }
            }
            .popover(isPresented: $showDue, arrowEdge: .bottom) {
                DuePicker(spec: Binding(get: { todo.due.map(DueSpec.init) },
                                        set: { store.setDue($0?.resolve(), for: todo.id) })) { showDue = false }
            }

            // The content is saved as typed, no Return needed; ⌘Return only ends editing.
            GrowingTextEditor(text: $draft, placeholder: "To-do",
                              onCommit: { editing = false }, focused: $editing)
                .foregroundStyle(todo.isDone ? Style.secondary : Style.text)
                .opacity(todo.isDone ? 0.7 : 1)
                .onChange(of: draft) { _, t in if t != todo.title { store.rename(todo.id, to: t) } }
                .onChange(of: todo.title) { _, t in if t != draft { draft = t } }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(hovering ? Style.cardHover : Style.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08)))
        .onHover { hovering = $0 }
        .onAppear { draft = todo.title }
        .onChange(of: coordinator.isCompact) { _, compact in if compact { editing = false } }
        .contextMenu {
            if todo.binding != nil {
                Button("Jump to Bound Page") { coordinator.jump(todo) }
                Button("Rebind…") { coordinator.bind(todo) }
                Button("Unbind") { store.setBinding(nil, for: todo.id) }
            } else {
                Button("Bind to Window / Page…") { coordinator.bind(todo) }
            }
            Button("Timer / Date…") { showDue = true }
            if todo.due != nil { Button("Remove Time") { store.setDue(nil, for: todo.id) } }
            Divider()
            Button(todo.isDone ? "Mark as Not Done" : "Mark as Done") { store.toggleDone(todo.id) }
            Button("Delete", role: .destructive) { store.delete(todo.id) }
        }
    }

}
