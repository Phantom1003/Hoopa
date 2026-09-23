import SwiftUI

/// Collapsed: a pill showing only the most urgent to-do. Tap the title to expand; click the app icon to jump; press anywhere to drag.
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
                    Text(t.title).lineLimit(1).truncationMode(.tail).frame(maxWidth: 220, alignment: .leading)
                    if let d = t.due { DueChip(due: d, showDetail: d.isCountdown) }
                    if store.active.count > 1 {
                        Text("+\(store.active.count - 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Style.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { coordinator.isCompact = false }
                .help("Tap to expand, press to drag")
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
}
