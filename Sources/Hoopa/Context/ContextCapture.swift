import AppKit
import ApplicationServices

/// The element under the mouse in ⌥ mode.
struct PickedElement {
    var element: AXUIElement?
    var frame: CGRect?
    var role: String?
    var subrole: String?
    var label: String?
    var text: String?
    var tabPosition: Int?     // browser: the tab's index in the tab bar
    var hint: String?         // shown next to the mouse when there is no element to highlight

    init(element: AXUIElement) {
        self.element = element
        frame = AX.frame(element)
        role = AX.role(element)
        subrole = AX.subrole(element)
        label = AX.bestLabel(element)
        text = AX.innerText(element)
        if label == nil { label = text }
    }

    init(hint: String) { self.hint = hint }
}

struct PickContext {
    let point: CGPoint
    let axApp: AXUIElement
    let axWindow: AXUIElement?
    let deepest: AXUIElement?
}

/// The target resolved while the picker hovers.
struct HoverTarget {
    let point: CGPoint
    let window: OnScreenWindow
    let axWindow: AXUIElement?
    let windowFrame: CGRect
    let windowTitle: String
    let appName: String
    let bundleID: String
    let interfaces: AppInterfaces
    let elementMode: Bool
    let picked: PickedElement?

    var element: AXUIElement? { picked?.element }
    var elementFrame: CGRect? { picked?.frame }
    var elementRole: String? { picked?.role }
    var elementSubrole: String? { picked?.subrole }
    var elementLabel: String? { picked?.label }
    var elementText: String? { picked?.text }
    var hint: String? { picked?.hint }
}

enum ContextCapture {
    private static var loggedApps = Set<String>()

    /// Resolves the window under screen point p (and the element, in ⌥ mode).
    static func resolve(at p: CGPoint, elementMode: Bool) -> HoverTarget? {
        guard let win = WindowList.topWindow(at: p) else { return nil }
        let axApp = AX.app(win.pid)
        AX.enableManualAccessibility(axApp)
        let deepest = AX.elementAt(axApp, p)
        let axWindow = deepest.flatMap { AX.windowOf($0) } ?? AX.window(of: axApp, matching: win.bounds)
        let running = NSRunningApplication(processIdentifier: win.pid)
        let bundleID = running?.bundleIdentifier ?? ""
        let interfaces = AppInterfaces.probe(bundleID: bundleID, window: axWindow)
        if !loggedApps.contains(bundleID) {
            loggedApps.insert(bundleID)
            Log.write("Interface probe \(bundleID): \(interfaces.description)")
        }

        var picked: PickedElement?
        if elementMode {
            let ctx = PickContext(point: p, axApp: axApp, axWindow: axWindow, deepest: deepest)
            if interfaces.browserScripting, let tab = BrowserTabs.pick(ctx) {
                picked = tab
            } else if !interfaces.axTree {
                picked = PickedElement(hint: "This app exposes no accessible elements; only the whole window can be bound")
            } else if let d = deepest, let el = AX.actionableAncestor(of: d, within: axWindow) {
                picked = PickedElement(element: el)
            }
        }
        return HoverTarget(point: p, window: win, axWindow: axWindow,
                           windowFrame: axWindow.flatMap(AX.frame) ?? win.bounds,
                           windowTitle: axWindow.flatMap(AX.title) ?? "",
                           appName: running?.localizedName ?? win.ownerName,
                           bundleID: bundleID, interfaces: interfaces, elementMode: elementMode, picked: picked)
    }

    /// Turns the hover target into a binding: records every anchor available, most reliable first. May call AppleScript; call from a background thread.
    static func capture(_ t: HoverTarget) -> ContextBinding {
        let running = NSRunningApplication(processIdentifier: t.window.pid)
        var b = ContextBinding(appName: t.appName, bundleID: t.bundleID, appPath: running?.bundleURL?.path,
                               windowTitle: t.windowTitle, windowID: t.window.id, anchors: [])
        var summary: String?

        // 1) Browser: the tab URL through AppleScript.
        if t.interfaces.browserScripting, let tab = BrowserTabs.resolve(t) {
            b.anchors.append(.browserTab(url: tab.url, title: tab.title))
            summary = summary ?? tab.title
        }
        // 2) Document window: the app tells us the file path.
        if t.element == nil, let w = t.axWindow,
           let doc = AX.string(w, kAXDocumentAttribute), let url = URL(string: doc), url.isFileURL {
            b.anchors.append(.document(path: doc))
            summary = summary ?? url.lastPathComponent
        }
        // 3) A link format from the app's official documentation.
        if let lp = t.interfaces.links, let l = lp.link(for: t) {
            b.anchors.append(.link(url: l.url, expect: l.expect))
            summary = summary ?? l.summary
        }
        // 4) The Accessibility element.
        if let el = t.element, let role = t.elementRole {
            var a = AXAnchor(role: role, subrole: t.elementSubrole, label: t.elementLabel, text: t.elementText)
            a.domID = AX.string(el, "AXDOMIdentifier").flatMap { $0.isEmpty ? nil : $0 }
            if let w = t.axWindow {
                a.path = AX.path(from: w, to: el)
                a.tabs = AX.tabPanelChain(of: el, within: w)
            }
            if let f = t.elementFrame { a.column = relative(f, in: t.windowFrame) }
            b.anchors.append(.element(a))
            summary = summary ?? a.texts.first
        }
        // 5) The window.
        b.anchors.append(.window)
        b.summary = summary ?? t.windowTitle
        Log.write("Bound \(t.bundleID) anchors=\(b.anchors.map(\.kindLabel).joined(separator: ">")) summary=\(b.summary)")
        return b
    }

    /// Screen rect → relative position inside the window [x, y, w, h] (0…1).
    static func relative(_ r: CGRect, in win: CGRect) -> [Double]? {
        guard win.width > 0, win.height > 0 else { return nil }
        return [Double((r.minX - win.minX) / win.width), Double((r.minY - win.minY) / win.height),
                Double(r.width / win.width), Double(r.height / win.height)]
    }
}
