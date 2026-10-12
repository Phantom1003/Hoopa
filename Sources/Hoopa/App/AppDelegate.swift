import AppKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = TodoStore()
    let permissions = PermissionState()
    let coordinator = AppCoordinator()
    /// Checks GitHub Releases and updates in place; see Updater.
    let updater = Updater()

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
        updater.notify = { [weak self] text, seconds in self?.coordinator.showToast(text, seconds: seconds) }
        store.notify = { [weak self] text in self?.coordinator.showToast(text) }
        // Collapsed at the last quit: launch straight into the collapsed state without the collapse animation (onCompactChanged is not hooked up yet).
        let startCompact = UserDefaults.standard.bool(forKey: "compact")
        if startCompact { coordinator.restoreCompact() }

        let root = RootView(startCompact: startCompact)
            .environmentObject(store)
            .environmentObject(permissions)
            .environmentObject(coordinator)
            .environmentObject(updater)
            .environment(\.locale, AppLanguage.locale)   // plural rules and the like follow the interface language, not the system region
        let hosting = FirstMouseHostingView(rootView: AnyView(root))
        panel = FloatingPanel(contentView: hosting)
        // The window's layer mask follows the plate and the ear; the root view has already been evaluated once, so hand over the geometry it reported.
        coordinator.onMaskChange = { [weak self] mask in self?.panel.setMask(mask) }
        panel.setMask(coordinator.mask)
        panel.onResize = { [weak self] size in self?.coordinator.panelSize = size }
        panel.dock.onSideChange = { [weak self] side in self?.coordinator.dockSide = side }
        coordinator.dockSide = panel.dock.side
        panel.dock.onTuckChange = { [weak self] tucked in self?.coordinator.dockTucked = tucked }
        coordinator.dockAutoHide = panel.dock.autoHide
        coordinator.onDockAutoHideChanged = { [weak self] on in self?.panel.dock.autoHide = on }
        coordinator.panelSize = panel.frame.size
        if startCompact { panel.setCompact(true, animated: false) }
        coordinator.onCompactChanged = { [weak self] compact in
            self?.panel.setCompact(compact)
            UserDefaults.standard.set(compact, forKey: "compact")
        }
        UNUserNotificationCenter.current().delegate = self

        setupStatusItem()
        setupHotkey()
        panel.show()
        // Notifications scheduled by the last run may be gone; schedule them again.
        store.todos.forEach(Notifier.schedule)
        Log.write("Version \(Updater.version)")
        // The sync folder chosen last time, now that a missing one can be reported in a toast.
        store.startSync()
        updater.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Saves are delayed a moment after each change; the last ones must not be lost to the quit (or to the updater's relaunch).
    func applicationWillTerminate(_ notification: Notification) { store.flush() }

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

    /// The monochrome template image build.sh generates from scripts/icon-source.png (menubar.png / @2x); the system tints it to the menu bar colours.
    /// An executable run straight from swift build has none of these resources; fall back to an SF Symbol.
    private static let menuBarIcon: NSImage? = {
        guard let image = Bundle.main.image(forResource: "menubar") else {
            return NSImage(systemSymbolName: "checklist", accessibilityDescription: "Hoopa")
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hoopa"
        return image
    }()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: panel.isVisible && !panel.isTucked ? String(localized: "Hide Panel") : String(localized: "Show Panel"), action: #selector(togglePanel), keyEquivalent: "")
            menu.addItem(withTitle: coordinator.isCompact ? String(localized: "Expand") : String(localized: "Collapse"), action: #selector(toggleCompact), keyEquivalent: "")
            // The same switch as in the ⋯ menu: a docked panel slides away when the mouse leaves, or stays out at the edge.
            let hide = menu.addItem(withTitle: String(localized: "Hide at the Screen Edge"), action: #selector(toggleDockAutoHide), keyEquivalent: "")
            hide.state = coordinator.dockAutoHide ? .on : .off
            // Settings ▸: the rest of the ⋯ menu's settings, so they can be reached without the panel.
            let settings = menu.addItem(withTitle: String(localized: "Settings"), action: nil, keyEquivalent: "")
            settings.submenu = settingsMenu()
            // One more item while a newer version exists: the same as the one under ⬇ in the panel; click to download, swap and relaunch.
            if let r = updater.available {
                menu.addItem(.separator())
                menu.addItem(withTitle: String(localized: "Update to \(r.version) and Relaunch"), action: #selector(installUpdate), keyEquivalent: "")
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: String(localized: "Quit Hoopa"), action: #selector(quit), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePanel()
        }
    }

    /// A panel tucked away at a screen edge counts as hidden: the hotkey brings it out rather than ordering it out.
    @objc func togglePanel() {
        if panel.isVisible && !panel.isTucked {
            panel.orderOut(nil)
        } else {
            panel.show()
        }
    }

    @objc private func toggleCompact() { coordinator.isCompact.toggle() }
    @objc private func toggleDockAutoHide() { coordinator.setDockAutoHide(!coordinator.dockAutoHide) }

    /// Settings ▸ in the menu bar menu: the same settings as in the panel's ⋯ menu (see RootView.menuButton), as AppKit menu items with a tick for what is on.
    private func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        func toggle(_ title: String, _ on: Bool, _ action: Selector, in menu: NSMenu, enabled: Bool = true) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.state = on ? .on : .off
            item.isEnabled = enabled
        }
        toggle(String(localized: "Keep Panel on Top"), coordinator.alwaysOnTop, #selector(toggleAlwaysOnTop), in: menu)
        toggle(String(localized: "Launch at Login"), LoginItem.enabled, #selector(toggleLaunchAtLogin), in: menu)
        // Language names are not translated; switching relaunches the app.
        let language = NSMenu()
        for l in AppLanguage.allCases {
            let item = language.addItem(withTitle: l.name, action: #selector(switchLanguage(_:)), keyEquivalent: "")
            item.representedObject = l.rawValue
            item.state = l == AppLanguage.current ? .on : .off
        }
        menu.addItem(withTitle: String(localized: "Language"), action: nil, keyEquivalent: "").submenu = language
        let sync = NSMenu()
        toggle(String(localized: "Off"), store.syncMode == .off, #selector(syncOff), in: sync)
        toggle(String(localized: "iCloud Drive"), store.syncMode == .iCloudDrive, #selector(syncICloud), in: sync)
        var folder = false
        if case .folder = store.syncMode { folder = true }
        toggle(String(localized: "Other Folder…"), folder, #selector(syncOtherFolder), in: sync)
        if store.syncMode.folder != nil {
            sync.addItem(.separator())
            sync.addItem(withTitle: String(localized: "Show Sync Folder in Finder"), action: #selector(showSyncFolder), keyEquivalent: "")
        }
        menu.addItem(withTitle: String(localized: "Sync"), action: nil, keyEquivalent: "").submenu = sync
        menu.addItem(.separator())
        let ax = menu.addItem(withTitle: permissions.accessibility ? String(localized: "Accessibility Access: Granted") : String(localized: "Grant Accessibility Access…"),
                              action: #selector(requestAccessibility), keyEquivalent: "")
        ax.isEnabled = !permissions.accessibility
        menu.addItem(.separator())
        toggle(String(localized: "Check for Updates Automatically"), updater.automatic, #selector(toggleAutoUpdate), in: menu)
        menu.addItem(withTitle: String(localized: "Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "")
        menu.autoenablesItems = false
        for m in [menu, language, sync] { m.items.forEach { $0.target = self } }
        return menu
    }

    @objc private func toggleAlwaysOnTop() {
        coordinator.alwaysOnTop.toggle()
        coordinator.onAlwaysOnTopChanged?(coordinator.alwaysOnTop)
    }
    @objc private func toggleLaunchAtLogin() {
        if let message = LoginItem.set(!LoginItem.enabled) { coordinator.showToast(message, seconds: 5) }
    }
    @objc private func switchLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let l = AppLanguage(rawValue: raw) { AppLanguage.switchTo(l) }
    }
    @objc private func syncOff() { store.setSync(.off) }
    @objc private func syncICloud() { store.setSync(store.syncMode == .iCloudDrive ? .off : .iCloudDrive) }
    @objc private func syncOtherFolder() { if let url = SyncFolderChooser.run(current: store.syncMode.folder) { store.setSync(SyncMode.forFolder(url)) } }
    @objc private func showSyncFolder() { if let folder = store.syncMode.folder { NSWorkspace.shared.activateFileViewerSelecting([folder]) } }
    @objc private func requestAccessibility() { permissions.request() }
    @objc private func toggleAutoUpdate() { updater.automatic.toggle() }
    @objc private func checkForUpdates() { updater.check(manual: true) }

    @objc private func installUpdate() { updater.install() }

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
            coordinator.showToast(String(localized: "Please grant Accessibility access first"))
            return
        }
        coordinator.isPicking = true
        panel.orderOut(nil)
        let p = WindowPicker()
        picker = p
        p.onWillCapture = { [weak self] in
            self?.panel.show()
            self?.coordinator.showToast(String(localized: "Reading page info…"), seconds: 15)
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
                self.coordinator.showToast(String(localized: "Bound: \(binding.shortDescription)"))
            } else {
                self.coordinator.toast = nil
            }
        }
    }
}
