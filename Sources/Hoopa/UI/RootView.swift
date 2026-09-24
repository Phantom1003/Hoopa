import SwiftUI

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        if coordinator.isCompact {
            switch coordinator.compactStyle {
            case .pill: CompactPill()
            case .stack: CompactStack()
            }
        } else {
            ExpandedView()
        }
    }
}

/// Expanded: the input pill + the list of sticky-note cards.
struct ExpandedView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var permissions: PermissionState
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var showDone = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if !permissions.accessibility { permissionBanner }
            InputPill().padding(.horizontal, 12)
            list
        }
        .frame(minWidth: 300, minHeight: 320)
        // The NSScrollView under the list is square and would show white sharp corners outside the glass's rounding: clip it round first, then lay the glass.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .windowDraggable()
        .overlay(alignment: .bottom) { toast }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { coordinator.isCompact = true } label: {
                Image(systemName: "chevron.up.circle.fill").font(.system(size: 15)).foregroundStyle(Style.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse")
            Text("Hoopa").font(.system(size: 13, weight: .semibold)).foregroundStyle(Style.text)
            Spacer()
            if !store.active.isEmpty {
                Text("\(store.active.count) items").font(.caption).foregroundStyle(Style.secondary)
            }
            Menu {
                Toggle("Keep Panel on Top", isOn: Binding(
                    get: { coordinator.alwaysOnTop },
                    set: { coordinator.alwaysOnTop = $0; coordinator.onAlwaysOnTopChanged?($0) }))
                Toggle("Show Completed", isOn: $showDone)
                Picker("Collapsed Style", selection: $coordinator.compactStyle) {
                    ForEach(CompactStyle.allCases) { Text($0.label).tag($0) }
                }
                // Switching the language relaunches the app. Language names are not translated.
                Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.switchTo($0) })) {
                    ForEach(AppLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                Divider()
                Button(permissions.accessibility ? "Accessibility Access: Granted" : "Grant Accessibility Access…") { permissions.request() }
                    .disabled(permissions.accessibility)
                Button("Clear Completed") { store.clearDone() }.disabled(store.done.isEmpty)
                Divider()
                Text("Press ⌃⌥T to show / hide the panel")
                Button("Quit Hoopa") { coordinator.onQuit?() }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Style.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .windowDraggable()
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Accessibility access is needed to detect windows and jump back").font(.caption).foregroundStyle(Style.text)
            Spacer()
            Button("Grant") { permissions.request() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.18)))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if store.active.isEmpty && (!showDone || store.done.isEmpty) {
                    emptyState
                }
                ForEach(store.active) { todo in
                    TodoCard(todo: todo)
                        .reorderable(todo.id, store: store)
                }
                if showDone && !store.done.isEmpty {
                    HStack {
                        Text("Completed · \(store.done.count)").font(.caption).foregroundStyle(Style.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    ForEach(store.done) { todo in
                        TodoCard(todo: todo)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope").font(.system(size: 28)).foregroundStyle(Style.secondary)
            Text("No to-dos yet").font(.subheadline).foregroundStyle(Style.secondary)
            Text("Pick a window / page with ⌖ and set a timer or date with ◔, then type and press ⌘Return.\nLater, click the chip to jump straight back to that page.")
                .font(.caption).foregroundStyle(Style.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var toast: some View {
        if let t = coordinator.toast {
            Text(t)
                .font(.caption)
                .foregroundStyle(Style.text)
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.ultraThickMaterial))
                .shadow(radius: 4)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: coordinator.toast)
        }
    }
}

/// Drag to reorder: dropping on the upper half of another card inserts before it, on the lower half after it.
private struct Reorderable: ViewModifier {
    let id: UUID
    let store: TodoStore
    @State private var height: CGFloat = 60
    @State private var targeted = false
    @State private var insertAfter = false

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in Color.clear.onAppear { height = g.size.height }
                .onChange(of: g.size.height) { _, h in height = h } })
            .overlay(alignment: insertAfter ? .bottom : .top) {
                if targeted {
                    Capsule().fill(Style.accent).frame(height: 2).padding(.horizontal, 6)
                }
            }
            .draggable(id.uuidString)
            .dropDestination(for: String.self) { items, location in
                guard let s = items.first, let dragged = UUID(uuidString: s), dragged != id else { return false }
                store.move(dragged, relativeTo: id, after: location.y > height / 2)
                return true
            } isTargeted: { targeted = $0 }
            .onContinuousHover { phase in
                if case .active(let p) = phase, targeted { insertAfter = p.y > height / 2 }
            }
    }
}

extension View {
    func reorderable(_ id: UUID, store: TodoStore) -> some View { modifier(Reorderable(id: id, store: store)) }
}
