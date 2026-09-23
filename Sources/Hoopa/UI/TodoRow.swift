import SwiftUI
import AppKit

struct TodoRow: View {
    let todo: TodoItem
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var editFocused: Bool

    private var isJumping: Bool { coordinator.jumpingID == todo.id }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { store.toggleDone(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(todo.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                if editing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .focused($editFocused)
                        .onSubmit(commitEdit)
                        .onExitCommand { editing = false }
                } else {
                    Text(todo.title)
                        .strikethrough(todo.isDone)
                        .foregroundStyle(todo.isDone ? .secondary : .primary)
                        .lineLimit(3)
                }
                if let b = todo.binding {
                    BindingChip(binding: b, jumping: isJumping)
                        .onTapGesture { coordinator.jump(todo) }
                        .help(b.detailDescription)
                }
            }
            Spacer(minLength: 4)

            if !editing {
                HStack(spacing: 6) {
                    Button { coordinator.bind(todo) } label: {
                        Image(systemName: todo.binding == nil ? "scope" : "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.plain)
                    .help(todo.binding == nil ? "Bind to Window / Page" : "Rebind")
                    Button { store.delete(todo.id) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .foregroundStyle(todo.binding == nil ? Color.accentColor : Color.secondary)
                .opacity(hovering ? 1 : 0.7)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { startEdit() }
        .onTapGesture { if todo.binding != nil && !editing { coordinator.jump(todo) } }
        .contextMenu {
            if todo.binding != nil {
                Button("Jump to Bound Page") { coordinator.jump(todo) }
                Button("Rebind…") { coordinator.bind(todo) }
                Button("Unbind") { store.setBinding(nil, for: todo.id) }
            } else {
                Button("Bind to Window / Page…") { coordinator.bind(todo) }
            }
            Divider()
            Button("Rename") { startEdit() }
            Button(todo.isDone ? "Mark as Not Done" : "Mark as Done") { store.toggleDone(todo.id) }
            Button("Delete", role: .destructive) { store.delete(todo.id) }
        }
    }

    private func startEdit() {
        draft = todo.title
        editing = true
        DispatchQueue.main.async { editFocused = true }
    }

    private func commitEdit() {
        store.rename(todo.id, to: draft)
        editing = false
    }
}

struct BindingChip: View {
    let binding: ContextBinding
    let jumping: Bool

    private var icon: NSImage? {
        guard let p = binding.appPath else { return nil }
        return NSWorkspace.shared.icon(forFile: p)
    }

    private var kindSymbol: String {
        switch binding.primary {
        case .browserTab: return "safari"
        case .element: return "cursorarrow.click.2"
        case .document: return "doc.text"
        case .link: return "link"
        case .window: return "macwindow"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: kindSymbol).font(.caption)
            }
            Text(binding.shortDescription)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if jumping {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "arrow.up.forward.app").font(.caption2)
            }
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .contentShape(Capsule())
    }
}
