import AppKit
import ApplicationServices

/// A thin wrapper around the Accessibility API. Every function may be called from a background thread.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Triggers the system's Accessibility permission prompt.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func app(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

    /// Explicitly enables the accessibility tree of Chromium / Electron apps (Chrome, VS Code, Slack…).
    static func enableManualAccessibility(_ app: AXUIElement) {
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Temporarily sets the AXEnhancedUserInterface flag VoiceOver uses, runs body, then clears it right away.
    /// The flag switches Chromium to full accessibility mode (only then does Slack's web area expose AXURL, for instance),
    /// but apps such as VS Code decide "a screen reader was detected" and change behaviour, so it is only set briefly and on demand.
    static func withEnhancedUI<T>(_ app: AXUIElement, _ body: () -> T) -> T {
        let key = "AXEnhancedUserInterface" as CFString
        let wasOn = bool(app, key as String) == true
        if !wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanTrue) }
        defer { if !wasOn { AXUIElementSetAttributeValue(app, key, kCFBooleanFalse) } }
        return body()
    }

    /// An earlier version set AXEnhancedUserInterface on every app it touched; clear it once at launch (only when VoiceOver is off).
    static func resetEnhancedUIOnce() {
        let flagKey = "axEnhancedUIReset.1"
        guard !UserDefaults.standard.bool(forKey: flagKey), !NSWorkspace.shared.isVoiceOverEnabled else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            AXUIElementSetAttributeValue(AX.app(app.processIdentifier), "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
        UserDefaults.standard.set(true, forKey: flagKey)
        Log.write("Cleared the AXEnhancedUserInterface flag on every app")
    }

    /// The actions the element supports (AXPress, AXScrollToVisible, AXShowMenu…).
    static func actions(_ el: AXUIElement) -> [String] {
        var arr: CFArray?
        guard AXUIElementCopyActionNames(el, &arr) == .success, let a = arr as? [String] else { return [] }
        return a
    }

    // MARK: Reading attributes

    static func raw(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(el, attr as CFString, &v)
        return r == .success ? v : nil
    }

    static func string(_ el: AXUIElement, _ attr: String) -> String? {
        guard let v = raw(el, attr) else { return nil }
        if let s = v as? String { return s }
        if let a = v as? NSAttributedString { return a.string }
        if let u = v as? URL { return u.absoluteString }
        return nil
    }

    static func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
        guard let v = raw(el, attr) else { return nil }
        return v as? Bool
    }

    static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        guard let v = raw(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
        guard let v = raw(el, attr), CFGetTypeID(v) == CFArrayGetTypeID() else { return [] }
        let arr = v as! NSArray
        var out: [AXUIElement] = []
        out.reserveCapacity(arr.count)
        for item in arr {
            let obj = item as AnyObject
            if CFGetTypeID(obj) == AXUIElementGetTypeID() {
                out.append(obj as! AXUIElement)
            }
        }
        return out
    }

    static func point(_ el: AXUIElement, _ attr: String) -> CGPoint? {
        guard let v = raw(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let av = v as! AXValue
        var p = CGPoint.zero
        return AXValueGetValue(av, .cgPoint, &p) ? p : nil
    }

    static func size(_ el: AXUIElement, _ attr: String) -> CGSize? {
        guard let v = raw(el, attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let av = v as! AXValue
        var s = CGSize.zero
        return AXValueGetValue(av, .cgSize, &s) ? s : nil
    }

    /// The element's position on screen (CG coordinates: origin at the top left of the main screen, y down).
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = point(el, kAXPositionAttribute), let s = size(el, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func role(_ el: AXUIElement) -> String? { string(el, kAXRoleAttribute) }
    static func subrole(_ el: AXUIElement) -> String? { string(el, kAXSubroleAttribute) }
    static func title(_ el: AXUIElement) -> String? { string(el, kAXTitleAttribute) }
    static func parent(_ el: AXUIElement) -> AXUIElement? { element(el, kAXParentAttribute) }
    static func children(_ el: AXUIElement) -> [AXUIElement] { elements(el, kAXChildrenAttribute) }
    static func windows(of app: AXUIElement) -> [AXUIElement] { elements(app, kAXWindowsAttribute) }

    static func pid(_ el: AXUIElement) -> pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(el, &p) == .success ? p : nil
    }

    // MARK: Actions

    @discardableResult
    static func perform(_ el: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(el, action as CFString) == .success
    }

    @discardableResult
    static func set(_ el: AXUIElement, _ attr: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(el, attr as CFString, value) == .success
    }

    /// Hit test inside an app's coordinate space: the deepest element of that app at screen point p.
    static func elementAt(_ app: AXUIElement, _ p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        let r = AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &el)
        return r == .success ? el : nil
    }

    /// The window the element belongs to.
    static func windowOf(_ el: AXUIElement) -> AXUIElement? {
        if role(el) == kAXWindowRole { return el }
        if let w = element(el, kAXWindowAttribute) { return w }
        var cur = el
        for _ in 0..<60 {
            guard let p = parent(cur) else { return nil }
            if role(p) == kAXWindowRole { return p }
            cur = p
        }
        return nil
    }

    /// The window in the app's window list that best matches the given screen rect.
    static func window(of app: AXUIElement, matching bounds: CGRect) -> AXUIElement? {
        var best: (AXUIElement, CGFloat)?
        for w in windows(of: app) {
            guard let f = frame(w) else { continue }
            let inter = f.intersection(bounds)
            guard !inter.isNull else { continue }
            let union = f.union(bounds)
            let iou = (inter.width * inter.height) / max(union.width * union.height, 1)
            if iou > (best?.1 ?? 0.5) { best = (w, iou) }
        }
        return best?.0
    }

    /// The text that best represents the element: title → description → value (static text only) → help.
    static func bestLabel(_ el: AXUIElement) -> String? {
        var attrs = [kAXTitleAttribute, kAXDescriptionAttribute]
        if role(el) == kAXStaticTextRole { attrs.append(kAXValueAttribute) }
        attrs.append(kAXHelpAttribute)
        for a in attrs {
            if let s = string(el, a)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return String(s.prefix(160))
            }
        }
        // A container without text of its own: try the static texts among its direct children.
        for c in children(el).prefix(6) where role(c) == kAXStaticTextRole {
            if let s = string(c, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return String(s.prefix(160))
            }
        }
        return nil
    }

    /// The plain text of the static texts inside the element (up to 4 levels deep), joined; the fallback match when the label carries a status prefix.
    static func innerText(_ el: AXUIElement, maxNodes: Int = 40) -> String? {
        let joined = staticTexts(in: el, maxNodes: maxNodes).joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.prefix(200))
    }

    /// The static texts inside the element (up to 4 levels deep), breadth first.
    static func staticTexts(in el: AXUIElement, maxNodes: Int = 40) -> [String] {
        var texts: [String] = []
        var queue: [(AXUIElement, Int)] = [(el, 0)]
        var head = 0
        while head < queue.count && head < maxNodes && texts.count < 12 {
            let (e, d) = queue[head]
            head += 1
            if d > 0, role(e) == kAXStaticTextRole,
               let v = string(e, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                texts.append(v)
            }
            if d < 4 { for c in children(e) { queue.append((c, d + 1)) } }
        }
        return texts
    }

    /// Similarity between a candidate and the target (label + inner text): label against label first, then the inner text.
    static func matchScore(_ el: AXUIElement, label: String?, text: String?) -> Double {
        let elLabel = bestLabel(el) ?? ""
        let elText = innerText(el) ?? ""
        var s = 0.0
        if let label, !label.isEmpty {
            s = max(s, TitleMatch.score(elLabel, label))
            s = max(s, TitleMatch.score(elText, label) * 0.9)
        }
        if let text, !text.isEmpty {
            s = max(s, TitleMatch.score(elText, text) * 0.95)
            s = max(s, TitleMatch.score(elLabel, text) * 0.9)
        }
        return s
    }

    /// Roles with clear "clickable" semantics: tabs, buttons, list rows, links, menu items…
    static let strongRoles: Set<String> = [
        kAXRadioButtonRole, kAXButtonRole, kAXRowRole, kAXCellRole, "AXLink",
        kAXMenuItemRole, kAXPopUpButtonRole, kAXCheckBoxRole, kAXDisclosureTriangleRole,
        kAXMenuButtonRole, "AXTab", "AXOutlineRow",
    ]
    /// Roles without actions of their own that still make sense as a click target (restoring uses a synthetic click).
    static let weakRoles: Set<String> = [kAXStaticTextRole, kAXImageRole]

    /// Walks up from the deepest element to a suitable "jump target".
    /// Preference: the nearest strongly semantic ancestor within 4 levels → the text / image itself → the deepest element if it is not too large.
    static func actionableAncestor(of el: AXUIElement, within window: AXUIElement?) -> AXUIElement? {
        let winArea: CGFloat = window.flatMap(frame).map { $0.width * $0.height } ?? .greatestFiniteMagnitude
        func tooBig(_ e: AXUIElement, _ ratio: CGFloat) -> Bool {
            guard let f = frame(e) else { return true }
            return f.width * f.height > winArea * ratio
        }
        var chain: [AXUIElement] = []
        var cur: AXUIElement? = el
        for _ in 0..<12 {
            guard let c = cur else { break }
            if let w = window, CFEqual(c, w) { break }
            chain.append(c)
            cur = parent(c)
        }
        for (i, c) in chain.enumerated() where i <= 4 {
            if let r = role(c), strongRoles.contains(r), !tooBig(c, 0.6) { return c }
        }
        if let r = role(el), weakRoles.contains(r), !tooBig(el, 0.5) { return el }
        if !tooBig(el, 0.4) { return el }
        return nil
    }

    /// Whether the element is inside web content (an AXWebArea among its ancestors).
    static func isInWebContent(_ el: AXUIElement) -> Bool {
        var cur: AXUIElement? = el
        for _ in 0..<60 {
            guard let c = cur else { return false }
            if role(c) == "AXWebArea" { return true }
            if role(c) == kAXWindowRole { return false }
            cur = parent(c)
        }
        return false
    }

    /// Whether ancestor is el itself or one of its ancestors.
    static func isSelfOrAncestor(_ ancestor: AXUIElement, of el: AXUIElement) -> Bool {
        var cur: AXUIElement? = el
        for _ in 0..<12 {
            guard let c = cur else { return false }
            if CFEqual(c, ancestor) { return true }
            cur = parent(c)
        }
        return false
    }

    /// The titles of the tab panels (AXTabPanel) the element lives in, outermost first. Restoring switches back to that tab first.
    static func tabPanelChain(of el: AXUIElement, within window: AXUIElement?) -> [String] {
        var labels: [String] = []
        var cur = parent(el)
        for _ in 0..<60 {
            guard let c = cur else { break }
            if let w = window, CFEqual(c, w) { break }
            if subrole(c) == "AXTabPanel", let l = bestLabel(c) { labels.insert(l, at: 0) }
            cur = parent(c)
        }
        return labels
    }

    /// The first element in the window that satisfies the predicate (breadth first).
    static func first(in root: AXUIElement, maxNodes: Int = 4000, where ok: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var head = 0
        while head < queue.count && head < maxNodes {
            let el = queue[head]
            head += 1
            if ok(el) { return el }
            queue.append(contentsOf: children(el))
        }
        return nil
    }

    // MARK: Window ID (private API, used by yabai / AltTab and others; falls back to title matching when unavailable)

    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindowFn: GetWindowFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(sym, to: GetWindowFn.self)
    }()

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        guard let fn = getWindowFn else { return nil }
        var id: CGWindowID = 0
        return fn(el, &id) == .success && id != 0 ? id : nil
    }

    // MARK: Paths and search

    /// Records the path from the window to the element. An incomplete path is fine: restoring falls back to a full-tree search.
    static func path(from root: AXUIElement, to el: AXUIElement) -> [AXPathStep] {
        var steps: [AXPathStep] = []
        var cur = el
        for _ in 0..<60 {
            guard let parent = parent(cur) else { break }
            let siblings = children(parent)
            // In Electron / Chromium the AXParent chain passes through nodes that are not in their parent's AXChildren (such as AXScrollArea);
            // walking down cannot reach them, so they are left out of the path.
            if let idx = siblings.firstIndex(where: { CFEqual($0, cur) }) {
                steps.insert(AXPathStep(role: role(cur) ?? "", index: idx, label: bestLabel(cur)), at: 0)
            }
            if CFEqual(parent, root) { return steps }
            cur = parent
        }
        return steps
    }

    /// Walks the path back down. Every step matches by "role + text" first, then by index.
    static func follow(_ path: [AXPathStep], from root: AXUIElement) -> AXUIElement? {
        var cur = root
        for step in path {
            // Old bindings may contain steps with index=-1 (the element was not found among the parent's children); skip them.
            if step.index < 0 { continue }
            let kids = children(cur)
            guard !kids.isEmpty else { return nil }
            var next: AXUIElement?
            if let label = step.label {
                var best: (AXUIElement, Double)?
                for k in kids where role(k) == step.role {
                    let s = TitleMatch.score(bestLabel(k) ?? "", label)
                    if s > (best?.1 ?? 0.7) { best = (k, s) }
                }
                next = best?.0
            }
            if next == nil, step.index >= 0, step.index < kids.count, role(kids[step.index]) == step.role {
                next = kids[step.index]
            }
            guard let n = next else { return nil }
            cur = n
        }
        return cur
    }

    /// Breadth-first search in the window for the element with the same role and the closest text.
    static func search(in root: AXUIElement, role wanted: String, label: String?, text: String?, maxNodes: Int = 6000, maxDepth: Int = 40) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var head = 0
        var best: (AXUIElement, Double)?
        while head < queue.count && head < maxNodes {
            let (el, depth) = queue[head]
            head += 1
            if role(el) == wanted {
                let s = matchScore(el, label: label, text: text)
                if s >= 0.99 { return el }
                if s > (best?.1 ?? 0.6) { best = (el, s) }
            }
            if depth < maxDepth {
                for c in children(el) { queue.append((c, depth + 1)) }
            }
        }
        return best?.0
    }
}
