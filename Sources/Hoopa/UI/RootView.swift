import SwiftUI

struct RootView: View {
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        if coordinator.isCompact {
            CompactPill()
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
            InputPill().padding(.horizontal, 10)
            list
        }
        .frame(minWidth: 300, minHeight: 320)
        // The NSScrollView under the list is square and would show white sharp corners outside the glass's rounding: clip it round first, then lay the glass.
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .bottom) { toast }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { coordinator.isCompact = true } label: {
                Image(systemName: "chevron.up.circle.fill").font(.system(size: 15)).foregroundStyle(Style.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse into Pill")
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
                Divider()
                Button(permissions.accessibility ? "Accessibility: Granted" : "Grant Accessibility Permission…") { permissions.request() }
                    .disabled(permissions.accessibility)
                Button("Clear Completed") { store.clearDone() }.disabled(store.done.isEmpty)
                Divider()
                Text("Shortcut ⌃⌥T shows / hides the panel")
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
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("The Accessibility permission is needed to recognise windows and jump").font(.caption).foregroundStyle(Style.text)
            Spacer()
            Button("Grant") { permissions.request() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.18)))
        .padding(.horizontal, 10)
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
                }
                if showDone && !store.done.isEmpty {
                    HStack {
                        Text("Completed · \(store.done.count)").font(.caption).foregroundStyle(Style.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    ForEach(store.done) { todo in
                        TodoCard(todo: todo)
                    }
                }
            }
            .padding(10)
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope").font(.system(size: 28)).foregroundStyle(Style.secondary)
            Text("No to-dos yet").font(.subheadline).foregroundStyle(Style.secondary)
            Text("Click ⌖ to choose the window / page to bind, ◔ to set a countdown or date, then type the content and press Return.\nAfter that one click on the chip takes you straight back to that page.")
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
