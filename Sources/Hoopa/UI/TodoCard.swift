import SwiftUI

/// A to-do: a sticky-note card. Normally one row: ○ title (a small icon at the end when there are notes), above it a flush-left row with the binding chip (click to jump) and the time chip (click to change the time),
/// on hover the action buttons appear at the top right. A click opens the details: title and notes are editable (saved as typed) and the action buttons stay; click empty space or press Esc to close.
struct TodoCard: View {
    let todo: TodoItem
    var selected = false
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var hovering = false
    @State private var title = ""
    @State private var notes = ""
    @State private var showDue = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    private var isJumping: Bool { coordinator.jumpingID == todo.id }
    private var hasChips: Bool { todo.binding != nil || todo.due != nil }
    /// The done box's width + its gap to the title: the notes are indented by this much to line up with the title text. The chip row is flush left, not indented.
    private static let textInset: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasChips || selected {
                HStack(spacing: 6) {
                    // Show everything when it fits; otherwise drop the absolute time inside the time chip first (hover shows it), then truncate the page name.
                    ViewThatFits(in: .horizontal) {
                        chips(detail: true)
                        chips(detail: false)
                    }
                    Spacer(minLength: 0)
                    if selected || hovering { actions }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { store.toggleDone(todo.id) } label: {
                    Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(todo.isDone ? Style.accent : Style.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(todo.isDone ? "Mark as not done" : "Mark as done")
                if selected {
                    TextField("To-do", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($titleFocused)
                        .onSubmit { titleFocused = false }
                        .onChange(of: title) { _, t in if t != todo.title { store.rename(todo.id, to: t) } }
                } else {
                    Group {
                        if todo.title.isEmpty { Text("To-do").foregroundStyle(Style.tertiary) } else { Text(todo.title) }
                    }
                    .font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !todo.notes.isEmpty {
                        Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(Style.tertiary)
                            .help(todo.notes)
                    }
                }
            }
            .foregroundStyle(todo.isDone ? Style.secondary : Style.text)
            .opacity(todo.isDone ? 0.7 : 1)
            if selected {
                // Notes: saved as typed; ⌘Return ends editing. The field's text has a built-in 5pt inset, so the indent is 5 less.
                GrowingTextEditor(text: $notes, placeholder: "Notes", font: .system(size: 12),
                                  onCommit: { notesFocused = false }, focused: $notesFocused)
                    .foregroundStyle(Style.secondary)
                    .padding(.leading, Self.textInset - 5)
                    .onChange(of: notes) { _, n in if n != todo.notes { store.setNotes(n, for: todo.id) } }
            }
        }
        // Without a chip row and not open, the actions float at the right end of the title row (with a backdrop so they stay legible over text) instead of taking a row of their own.
        .overlay(alignment: .topTrailing) {
            if hovering && !hasChips && !selected {
                actions
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.06)))
            }
        }
        .popover(isPresented: $showDue, arrowEdge: .bottom) {
            DuePicker(spec: Binding(get: { todo.due.map(DueSpec.init) },
                                    set: { store.setDue($0?.resolve(), for: todo.id) })) { showDue = false }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected || hovering ? Style.cardHover : Style.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selected ? Style.accent.opacity(0.45) : Color.primary.opacity(0.08)))
        // A click on the card: opens the details; a click on empty space while open: closes them. Buttons and text fields handle their own.
        .onTapGesture { coordinator.selectedID = selected ? nil : todo.id }
        .onExitCommand { coordinator.selectedID = nil }
        .onHover { hovering = $0 }
        .onAppear { title = todo.title; notes = todo.notes }
        .onChange(of: todo.title) { _, t in if t != title { title = t } }
        .onChange(of: todo.notes) { _, n in if n != notes { notes = n } }
        .onChange(of: selected) { _, s in if !s { titleFocused = false; notesFocused = false } }
        .onChange(of: coordinator.isCompact) { _, compact in if compact { titleFocused = false; notesFocused = false } }
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

    /// The chip row: the binding chip (click to jump), the time chip (click to change the time). detail: whether the time chip carries the absolute time.
    private func chips(detail: Bool) -> some View {
        HStack(spacing: 6) {
            if let b = todo.binding {
                Button { coordinator.jump(todo) } label: { BindingChip(binding: b, jumping: isJumping) }
                    .buttonStyle(.plain)
                    .help(b.detailDescription)
            }
            if let d = todo.due {
                Button { showDue.toggle() } label: { DueChip(due: d, showDetail: detail) }
                    .buttonStyle(.plain)
                    .help("Change time")
            }
        }
    }

    /// Actions: set a time (when there is none), bind / rebind, delete. Always shown while open, otherwise on hover; as tall as a chip, at the right end of the chip row.
    private var actions: some View {
        HStack(spacing: 8) {
            if todo.due == nil {
                Button { showDue.toggle() } label: { Image(systemName: "timer") }
                    .help("Timer / date")
            }
            Button { coordinator.bind(todo) } label: { Image(systemName: "scope") }
                .help(todo.binding == nil ? "Bind to a window / page" : "Rebind")
            Button { store.delete(todo.id) } label: { Image(systemName: "trash") }
                .help("Delete")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Style.secondary)
        .font(.system(size: 12))
        .frame(height: 25)
    }
}
