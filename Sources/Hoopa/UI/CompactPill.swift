import SwiftUI

/// Collapsed: a pill showing only the most urgent to-do. Tap the title or the ⌄ on the right to expand; click the app icon to jump; press anywhere to drag.
struct CompactPill: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 6) {
            if let t = store.compactItem {
                if let b = t.binding {
                    Button { coordinator.jump(t) } label: { BindingChip(binding: b, jumping: coordinator.jumpingID == t.id, compact: true) }
                        .buttonStyle(.plain)
                        .help("Return to \(b.shortDescription)")
                }
                // The title area is not a button: a button would swallow the press and the pill could not be dragged. Tap to expand, press and hold to drag.
                HStack(spacing: 6) {
                    let title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        Text(title).lineLimit(1).truncationMode(.tail).frame(maxWidth: 220, alignment: .leading)
                    }
                    if let d = t.due { DueChip(due: d) }
                    if store.active.count > 1 {
                        Text("+\(store.active.count - 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Style.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { coordinator.isCompact = false }
                .help("Tap to expand, press to drag")
                expandButton
            } else {
                Button { coordinator.isCompact = false } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Add a to-do")
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Style.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glass(Capsule())
        .fixedSize()
        .windowDraggable()
        .contextMenu {
            Button("Expand") { coordinator.isCompact = false }
            if let t = store.compactItem {
                if t.binding != nil { Button("Jump to Bound Page") { coordinator.jump(t) } }
                Button("Mark as Done") { store.toggleDone(t.id) }
            }
            Divider()
            Button("Quit Hoopa") { coordinator.onQuit?() }
        }
    }

    /// The expand symbol on the right: a clear place to click even when the content is empty.
    private var expandButton: some View {
        Button { coordinator.isCompact = false } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Style.secondary)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand")
    }
}
