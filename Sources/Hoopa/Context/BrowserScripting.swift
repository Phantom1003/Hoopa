import AppKit

struct BrowserTab {
    let windowIndex: Int   // AppleScript window index (1 is frontmost)
    let tabIndex: Int
    let title: String
    let url: String
    let isActive: Bool
    let windowBounds: CGRect?
}

/// Reads / switches browser tabs through AppleScript.
enum BrowserScripting {
    static let safariIDs: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]
    static let chromiumIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Beta",
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.vivaldi.Vivaldi", "org.chromium.Chromium", "com.operasoftware.Opera",
    ]

    static func supports(_ bundleID: String) -> Bool {
        safariIDs.contains(bundleID) || chromiumIDs.contains(bundleID)
    }

    private static let fs = "\u{1F}"
    private static let rs = "\u{1E}"

    /// Lists every tab of every window (attributes read per window in bulk, fast even with many tabs).
    static func listTabs(_ bundleID: String) -> [BrowserTab] {
        let isSafari = safariIDs.contains(bundleID)
        let app = AppleScriptRunner.quote(bundleID)
        let titleProp = isSafari ? "name" : "title"
        let activeExpr = isSafari ? "index of (current tab of w)" : "active tab index of w"
        let script = """
        set fs to character id 31
        set rs to character id 30
        set out to ""
        tell application id \(app)
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ai to 0
                try
                    set ai to \(activeExpr)
                end try
                set bs to ""
                try
                    set b to bounds of w
                    set bs to ((item 1 of b) as string) & "," & ((item 2 of b) as string) & "," & ((item 3 of b) as string) & "," & ((item 4 of b) as string)
                end try
                try
                    set tts to \(titleProp) of every tab of w
                    set tus to URL of every tab of w
                    repeat with ti from 1 to count of tts
                        set tt to item ti of tts
                        if tt is missing value then set tt to ""
                        set tu to item ti of tus
                        if tu is missing value then set tu to ""
                        set isA to "0"
                        if ti is ai then set isA to "1"
                        set out to out & wi & fs & ti & fs & isA & fs & tt & fs & tu & fs & bs & rs
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        guard case .success(let text) = AppleScriptRunner.run(script) else { return [] }
        var tabs: [BrowserTab] = []
        for rec in text.components(separatedBy: rs) {
            let f = rec.components(separatedBy: fs)
            guard f.count >= 5, let wi = Int(f[0]), let ti = Int(f[1]) else { continue }
            tabs.append(BrowserTab(windowIndex: wi, tabIndex: ti, title: f[3], url: f[4], isActive: f[2] == "1",
                                   windowBounds: f.count >= 6 ? parseBounds(f[5]) : nil))
        }
        return tabs
    }

    /// AppleScript bounds {left, top, right, bottom} (screen coordinates, origin top left).
    private static func parseBounds(_ s: String) -> CGRect? {
        let n = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard n.count == 4 else { return nil }
        return CGRect(x: n[0], y: n[1], width: n[2] - n[0], height: n[3] - n[1])
    }

    /// Activates the given tab of the given window and brings the window to the front.
    @discardableResult
    static func activate(_ bundleID: String, windowIndex: Int, tabIndex: Int) -> Bool {
        let isSafari = safariIDs.contains(bundleID)
        let app = AppleScriptRunner.quote(bundleID)
        let select = isSafari
            ? "set current tab of w to tab \(tabIndex) of w"
            : "set active tab index of w to \(tabIndex)"
        let script = """
        tell application id \(app)
            set w to window \(windowIndex)
            \(select)
            try
                set miniaturized of w to false
            end try
            try
                set minimized of w to false
            end try
            set index of w to 1
            activate
        end tell
        """
        if case .success = AppleScriptRunner.run(script) { return true }
        return false
    }

    /// When the tab is not found: opens the URL in a new tab of the front window.
    @discardableResult
    static func open(_ bundleID: String, url: String) -> Bool {
        let isSafari = safariIDs.contains(bundleID)
        let app = AppleScriptRunner.quote(bundleID)
        let u = AppleScriptRunner.quote(url)
        let script: String
        if isSafari {
            script = """
            tell application id \(app)
                if (count of windows) is 0 then
                    make new document with properties {URL:\(u)}
                else
                    tell front window
                        set current tab to (make new tab with properties {URL:\(u)})
                    end tell
                end if
                activate
            end tell
            """
        } else {
            script = """
            tell application id \(app)
                if (count of windows) is 0 then make new window
                tell front window
                    make new tab with properties {URL:\(u)}
                end tell
                activate
            end tell
            """
        }
        if case .success = AppleScriptRunner.run(script) { return true }
        return false
    }

    // MARK: URL matching

    static func normalizeURL(_ s: String) -> String {
        var u = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = u.firstIndex(of: "#") { u = String(u[..<hash]) }
        while u.hasSuffix("/") { u.removeLast() }
        return u.lowercased()
    }

    /// The best match in the tab list: exact URL → URL without the query → title.
    static func bestMatch(in tabs: [BrowserTab], url: String, title: String?) -> BrowserTab? {
        let target = normalizeURL(url)
        if let t = tabs.first(where: { normalizeURL($0.url) == target }) { return t }
        let stripQuery: (String) -> String = { s in
            if let q = s.firstIndex(of: "?") { return String(s[..<q]) }
            return s
        }
        let targetNoQuery = stripQuery(target)
        if !targetNoQuery.isEmpty, let t = tabs.first(where: { stripQuery(normalizeURL($0.url)) == targetNoQuery }) { return t }
        if let title, !title.isEmpty {
            let scored = tabs.map { ($0, TitleMatch.score($0.title, title)) }.max { $0.1 < $1.1 }
            if let s = scored, s.1 >= 0.85 { return s.0 }
        }
        return nil
    }
}
