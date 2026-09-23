import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = TodoStore()
    let permissions = PermissionState()
    let coordinator = AppCoordinator()

    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private var picker: WindowPicker?
    private var hotkeyMonitors: [Any] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("Launch trusted=\(AX.isTrusted) bundle=\(Bundle.main.bundleURL.path) screens=\(NSScreen.screens.count)")
        if AX.isTrusted { DispatchQueue.global().async { AX.resetEnhancedUIOnce() } }
        coordinator.onStartPicking = { [weak self] todo in self?.startPicking(for: todo) }
        coordinator.onAlwaysOnTopChanged = { [weak self] on in self?.panel.setAlwaysOnTop(on) }
        coordinator.onCompactChanged = { [weak self] compact in
            self?.panel.setCompact(compact)
            UserDefaults.standard.set(compact, forKey: "compact")
        }
        coordinator.onQuit = { NSApp.terminate(nil) }

        let root = RootView()
            .environmentObject(store)
            .environmentObject(permissions)
            .environmentObject(coordinator)
        let hosting = FirstMouseHostingView(rootView: AnyView(root))
        panel = FloatingPanel(contentView: hosting)
        UNUserNotificationCenter.current().delegate = self

        setupStatusItem()
        setupHotkey()
        panel.show()
        if UserDefaults.standard.bool(forKey: "compact") { coordinator.isCompact = true }
        // Notifications scheduled by the last run may be gone; schedule them again.
        store.todos.forEach(Notifier.schedule)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Notifications

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = UUID(uuidString: response.notification.request.identifier), let todo = store.item(id) {
            if todo.binding != nil {
                coordinator.jump(todo)
            } else {
                coordinator.isCompact = false
                panel.show()
            }
        }
        completionHandler()
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Hoopa")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: panel.isVisible ? "Hide Panel" : "Show Panel", action: #selector(togglePanel), keyEquivalent: "")
            menu.addItem(withTitle: coordinator.isCompact ? "Expand" : "Collapse into Pill", action: #selector(toggleCompact), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Hoopa", action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    @objc func togglePanel() {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.show()
        }
    }

    @objc private func toggleCompact() { coordinator.isCompact.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Shortcut ⌃⌥T

    private func setupHotkey() {
        let handle: (NSEvent) -> Bool = { [weak self] e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods == [.control, .option], e.keyCode == 17 else { return false }
            DispatchQueue.main.async { self?.togglePanel() }
            return true
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = handle($0) }) {
            hotkeyMonitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { handle($0) ? nil : $0 }) {
            hotkeyMonitors.append(m)
        }
    }

    // MARK: Binding flow

    /// todo nil: pick for the to-do about to be created in the composer; the result goes to coordinator.pendingBinding.
    private func startPicking(for todo: TodoItem?) {
        Log.write("Pick start todo=\(todo?.title ?? "(new to-do)") trusted=\(AX.isTrusted) pickerBusy=\(picker != nil)")
        guard picker == nil else { return }
        guard AX.isTrusted else {
            Log.write("Pick aborted: Accessibility not granted")
            permissions.request()
            coordinator.showToast("Grant the Accessibility permission first")
            return
        }
        coordinator.isPicking = true
        panel.orderOut(nil)
        let p = WindowPicker()
        picker = p
        p.onWillCapture = { [weak self] in
            self?.panel.show()
            self?.coordinator.showToast("Reading page info…", seconds: 15)
        }
        p.begin { [weak self] binding in
            guard let self else { return }
            self.picker = nil
            self.coordinator.isPicking = false
            self.panel.show()
            Log.write("Pick finished binding=\(binding.map { "\($0.shortDescription) anchors=\($0.anchors.map(\.kindLabel).joined(separator: ">"))" } ?? "cancelled")")
            if let binding {
                if let todo {
                    self.store.setBinding(binding, for: todo.id)
                } else {
                    self.coordinator.pendingBinding = binding
                }
                self.coordinator.showToast("Bound: \(binding.shortDescription)")
            } else {
                self.coordinator.toast = nil
            }
        }
    }
}
