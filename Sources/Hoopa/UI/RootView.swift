import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: TodoStore
    @EnvironmentObject var permissions: PermissionState
    @EnvironmentObject var coordinator: AppCoordinator

    @State private var newTitle = ""
    @State private var showDone = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !permissions.accessibility { permissionBanner }
            inputBar
            Divider().padding(.top, 8)
            list
        }
        .frame(minWidth: 300, minHeight: 320)
        .background(VisualEffectView(material: .popover).ignoresSafeArea())
        .overlay(alignment: .bottom) { toast }
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
    }

    // MARK: Top

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist").foregroundStyle(Color.accentColor)
            Text("Hoopa").font(.headline)
            Spacer()
            if !store.active.isEmpty {
                Text("\(store.active.count) to-dos")
                    .font(.caption).foregroundStyle(.secondary)
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
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("The Accessibility permission is needed to recognise windows and jump")
                .font(.caption)
            Spacer()
            Button("Grant") { permissions.request() }.controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
            TextField("Add a to-do, Return confirms", text: $newTitle)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .onSubmit(addTodo)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
    }

    private func addTodo() {
        if store.add(newTitle) != nil { newTitle = "" }
        inputFocused = true
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if store.active.isEmpty && (!showDone || store.done.isEmpty) {
                    emptyState
                }
                ForEach(store.active) { todo in
                    TodoRow(todo: todo)
                }
                if showDone && !store.done.isEmpty {
                    HStack {
                        Text("Completed · \(store.done.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 10)
                    ForEach(store.done) { todo in
                        TodoRow(todo: todo)
                    }
                }
            }
            .padding(8)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scope").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("No to-dos yet").font(.subheadline).foregroundStyle(.secondary)
            Text("Add one, then click ⌖ to bind it to the window, tab or document you are working in.\nAfter that one click takes you straight back to that page.")
                .font(.caption).foregroundStyle(.tertiary)
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
                .lineLimit(2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(.ultraThickMaterial))
                .shadow(radius: 4)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeOut(duration: 0.2), value: coordinator.toast)
        }
    }
}
