import AppKit

/// Interface language: English by default, does not follow the system; switchable in the panel menu.
/// Stored in the app's own AppleLanguages (the same key as "language per app" in System Settings), applied at launch; switching relaunches the app.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// A language's name is written in that language and not translated.
    var name: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "\u{7B80}\u{4F53}\u{4E2D}\u{6587}"   // "Simplified Chinese" in Chinese, as language pickers do
        }
    }

    /// The current interface language (the localization the bundle actually chose).
    static var current: AppLanguage {
        AppLanguage(rawValue: Bundle.main.preferredLocalizations.first ?? "") ?? .english
    }

    /// Date, month and weekday formats follow the interface language.
    static var locale: Locale { Locale(identifier: current.rawValue) }

    /// Called at launch, before any localized text is read: English unless a language was chosen.
    static func applyDefault() {
        guard let id = Bundle.main.bundleIdentifier,
              UserDefaults.standard.persistentDomain(forName: id)?["AppleLanguages"] == nil else { return }
        UserDefaults.standard.set([english.rawValue], forKey: "AppleLanguages")
    }

    /// Switch the language: write the preference and relaunch the app so every string changes at once.
    static func switchTo(_ lang: AppLanguage) {
        guard lang != current else { return }
        UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Open only after the current process has exited; otherwise open merely activates the old process that has not quit yet.
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$0\"",
                       Bundle.main.bundlePath]
        try? p.run()
        NSApp.terminate(nil)
    }
}
