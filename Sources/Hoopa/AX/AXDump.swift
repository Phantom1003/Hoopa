import AppKit

/// Diagnostics: writes the accessibility tree of every window of an app as text (`Hoopa --dump-ax <bundleID>`).
enum AXDump {
    static func run(bundleID: String, maxNodes: Int = 20000) -> String {
        var out = "trusted=\(AX.isTrusted)\n"
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return out + "app not running: \(bundleID)\n"
        }
        let ax = AX.app(app.processIdentifier)
        AX.enableManualAccessibility(ax)
        // Full accessibility mode is switched on for the dump too, so AXURL and more show up; switched off at the end.
        AXUIElementSetAttributeValue(ax, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        defer { AXUIElementSetAttributeValue(ax, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        Thread.sleep(forTimeInterval: 1.5)
        let windows = AX.windows(of: ax)
        out += "app=\(app.localizedName ?? "") pid=\(app.processIdentifier) windows=\(windows.count)\n"
        var budget = maxNodes
        for w in windows {
            dump(w, depth: 0, budget: &budget, into: &out)
        }
        if budget <= 0 { out += "...(truncated)\n" }
        // The menu bar is a native system control, readable even in Electron / self-drawn apps, and often carries "search / quick switch / go to" commands.
        if let bar = AX.element(ax, kAXMenuBarAttribute) {
            out += "--- menu bar ---\n"
            var menuBudget = 3000
            dump(bar, depth: 0, budget: &menuBudget, into: &out)
        }
        return out
    }

    private static func dump(_ el: AXUIElement, depth: Int, budget: inout Int, into out: inout String) {
        guard budget > 0, depth < 40 else { return }
        budget -= 1
        let role = AX.role(el) ?? "?"
        let sub = AX.subrole(el).map { "(\($0))" } ?? ""
        let label = AX.bestLabel(el).map { " \"\($0.prefix(60).replacingOccurrences(of: "\n", with: " "))\"" } ?? ""
        let f = AX.frame(el).map { " [\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))]" } ?? ""
        let kids = AX.children(el)
        // The URLs carried by web areas / links / document windows, often containing the app's internal routes and IDs.
        let url = [kAXURLAttribute, kAXDocumentAttribute].compactMap { AX.string(el, $0) }.first.map { " url=\($0.prefix(200))" } ?? ""
        let dom = AX.string(el, "AXDOMIdentifier").flatMap { $0.isEmpty ? nil : " #\($0)" } ?? ""
        let acts = AX.actions(el).filter { !["AXShowMenu", "AXScrollToVisible", "AXRaise", "AXPick"].contains($0) }
        let a = acts.isEmpty ? "" : " <\(acts.joined(separator: ","))>"
        out += String(repeating: "  ", count: depth) + role + sub + label + f + url + dom + a + (kids.isEmpty ? "" : " {\(kids.count)}") + "\n"
        for k in kids { dump(k, depth: depth + 1, budget: &budget, into: &out) }
    }
}
