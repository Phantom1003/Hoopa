import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        coordinator.onQuit = { NSApp.terminate(nil) }

        let root = RootView()
            .environmentObject(store)
            .environmentObject(permissions)
            .environmentObject(coordinator)
        let hosting = FirstMouseHostingView(rootView: root)
        panel = FloatingPanel(contentView: hosting)

        setupStatusItem()
        setupHotkey()
        panel.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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

    private func startPicking(for todo: TodoItem) {
        Log.write("Pick start todo=\(todo.title) trusted=\(AX.isTrusted) pickerBusy=\(picker != nil)")
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
                self.store.setBinding(binding, for: todo.id)
                self.coordinator.showToast("Bound: \(binding.shortDescription)")
            } else {
                self.coordinator.toast = nil
            }
        }
    }
}
