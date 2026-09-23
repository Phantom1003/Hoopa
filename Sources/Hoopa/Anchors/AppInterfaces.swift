import AppKit
import ApplicationServices

/// Which usable interfaces an app provides. Probed once when picking; decides which anchors can be recorded.
struct AppInterfaces {
    /// A browser whose tabs can be read and switched through AppleScript.
    let browserScripting: Bool
    /// A link format from the app's official documentation.
    let links: LinkProvider?
    /// The window has accessible interface elements (self-drawn apps such as WeChat expose only the title bar buttons, nothing can be read).
    let axTree: Bool
    /// Has Chromium web content (Electron / a browser).
    let webContent: Bool

    static func probe(bundleID: String, window: AXUIElement?) -> AppInterfaces {
        var nodes = 0
        var web = false
        if let w = window {
            _ = AX.first(in: w, maxNodes: 400) { el in
                nodes += 1
                if AX.role(el) == "AXWebArea" { web = true }
                return web && nodes > 12
            }
        }
        return AppInterfaces(browserScripting: BrowserScripting.supports(bundleID),
                             links: LinkProviders.for(bundleID),
                             axTree: nodes > 8,
                             webContent: web)
    }

    var description: String {
        var parts: [String] = []
        if browserScripting { parts.append("AppleScript tabs") }
        if let l = links { parts.append("link:\(l.name)") }
        parts.append(axTree ? (webContent ? "AX tree (web)" : "AX tree") : "no AX tree")
        return parts.joined(separator: " ")
    }
}

/// Link formats the app documents officially, assembled from what can be seen / read in the interface.
protocol LinkProvider {
    var name: String { get }
    /// Returns the link, the text used to confirm, and the name shown on the chip.
    func link(for t: HoverTarget) -> (url: String, expect: String?, summary: String)?
}

enum LinkProviders {
    static func `for`(_ bundleID: String) -> LinkProvider? {
        switch bundleID {
        case "com.tinyspeck.slackmacgap": return SlackLinks()
        case "md.obsidian": return ObsidianLinks()
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92": return VSCodeLinks()
        default: return nil
        }
    }
}

/// Slack deep link (https://api.slack.com/reference/deep-linking): slack://channel?team=<T…>&id=<C…>
/// The workspace ID comes from the web area's AXURL (app.slack.com/client/<T…>/<C…>), the conversation ID from the conversation row's AXDOMIdentifier or the current URL.
struct SlackLinks: LinkProvider {
    let name = "Slack deep link"

    func link(for t: HoverTarget) -> (url: String, expect: String?, summary: String)? {
        guard let win = t.axWindow else { return nil }
        // Slack's web area carries AXURL only in full accessibility mode; switch it on briefly to read it.
        let client = AX.withEnhancedUI(AX.app(t.window.pid)) { () -> (team: String, channel: String?)? in
            for _ in 0..<6 {
                if let c = Self.clientURL(in: win) { return c }
                Thread.sleep(forTimeInterval: 0.25)
            }
            return nil
        }
        guard let (team, current) = client else {
            Log.write("Slack: no app.slack.com/client/… AXURL found")
            return nil
        }
        var channel: String?
        var expect: String?
        if let el = t.element {
            // The conversation row picked with ⌥: its own DOM id, or an ancestor's, is the conversation ID.
            var cur: AXUIElement? = el
            for _ in 0..<6 {
                guard let c = cur else { break }
                if let id = AX.string(c, "AXDOMIdentifier"), Self.isChannelID(id) { channel = id; break }
                cur = AX.parent(c)
            }
            guard channel != nil else { return nil }
            expect = AX.staticTexts(in: el).first ?? t.elementLabel
        } else {
            // The whole window: the conversation currently open.
            channel = current
            expect = Self.conversation(in: t.windowTitle)
        }
        guard let channel else { return nil }
        return ("slack://channel?team=\(team)&id=\(channel)", expect, expect ?? channel)
    }

    /// Web area AXURL: https://app.slack.com/client/T0ABVP6GQB1/D0BDASRCRCP → (workspace, conversation)
    static func clientURL(in win: AXUIElement) -> (team: String, channel: String?)? {
        guard let web = AX.first(in: win, maxNodes: 200, where: { AX.role($0) == "AXWebArea" && AX.string($0, kAXURLAttribute)?.contains("slack.com/client/") == true }),
              let url = AX.string(web, kAXURLAttribute),
              let r = url.range(of: #"slack\.com/client/(T[A-Z0-9]+)(?:/([CDG][A-Z0-9]+))?"#, options: .regularExpression) else { return nil }
        let parts = url[r].split(separator: "/").map(String.init)   // ["slack.com", "client", "T…", "D…"?]
        guard parts.count >= 3 else { return nil }
        return (parts[2], parts.count >= 4 && isChannelID(parts[3]) ? parts[3] : nil)
    }

    static func isChannelID(_ s: String) -> Bool {
        s.range(of: #"^[CDG][A-Z0-9]{8,}$"#, options: .regularExpression) != nil
    }

    /// “Xiao Jielei (DM) - SEC@SoC - Slack” → “Xiao Jielei”
    static func conversation(in title: String) -> String? {
        guard let first = title.components(separatedBy: " - ").first,
              let r = first.range(of: "\\s*\\((DM|Channel|Private channel|Private Channel|Group DM|\u{79C1}\u{4FE1}|\u{9891}\u{9053}|\u{79C1}\u{4EBA}\u{9891}\u{9053}|\u{7FA4}\u{7EC4}\u{79C1}\u{4FE1})\\)$", options: .regularExpression)   // Slack's own row suffixes, English and Simplified Chinese UI
        else { return nil }
        return String(first[..<r.lowerBound]).trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "^\\* ", with: "", options: .regularExpression)
    }
}

/// Obsidian URI (https://help.obsidian.md/Extending+Obsidian/Obsidian+URI): obsidian://open?vault=…&file=…
/// The window title is "Note - Vault - Obsidian x.y".
struct ObsidianLinks: LinkProvider {
    let name = "Obsidian URI"

    func link(for t: HoverTarget) -> (url: String, expect: String?, summary: String)? {
        guard t.element == nil else { return nil }
        let parts = t.windowTitle.components(separatedBy: " - ")
        guard parts.count >= 3, parts.last!.hasPrefix("Obsidian") else { return nil }
        let vault = parts[parts.count - 2]
        let note = parts[0..<(parts.count - 2)].joined(separator: " - ")
        guard !note.isEmpty, !vault.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let v = vault.addingPercentEncoding(withAllowedCharacters: allowed),
              let n = note.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return ("obsidian://open?vault=\(v)&file=\(n)", note, note)
    }
}

/// `vscode://file/<absolute path>` from the VS Code command line / URL handbook (Cursor and other derived editors use their own scheme).
/// A tree row has a child element carrying the full path ("~/Project/x/y"). Local windows only: in SSH remote windows the path is relative to the remote home and cannot be assembled.
struct VSCodeLinks: LinkProvider {
    let name = "vscode://file"

    func link(for t: HoverTarget) -> (url: String, expect: String?, summary: String)? {
        guard let el = t.element, !t.windowTitle.contains("[SSH:"), !t.windowTitle.contains("[WSL:"),
              !t.windowTitle.contains("[Dev Container"), !t.windowTitle.contains("[Codespaces") else { return nil }
        let path = AX.first(in: el, maxNodes: 60) { e in
            (AX.bestLabel(e) ?? "").range(of: #"^(~/|/)[^\n]+$"#, options: .regularExpression) != nil
        }.flatMap(AX.bestLabel)
        guard var p = path else { return nil }
        if p.hasPrefix("~/") { p = NSHomeDirectory() + String(p.dropFirst(1)) }
        guard FileManager.default.fileExists(atPath: p) else { return nil }
        let scheme = t.bundleID == "com.todesktop.230313mzl4w4u92" ? "cursor" : "vscode"
        let name = (p as NSString).lastPathComponent
        let encoded = p.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? p
        return ("\(scheme)://file\(encoded)", name, name)
    }
}
