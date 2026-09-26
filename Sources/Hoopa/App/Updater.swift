import AppKit
import Combine
import Foundation

struct UpdateError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

/// Checks GitHub Releases for a newer Hoopa and swaps the running copy in place.
///
/// A release is a `vX.Y` tag with one asset `Hoopa-vX.Y.zip`, the CI product (see .github/workflows/build.yml).
/// Installing = download the zip, unpack it, confirm it is that version of Hoopa with a valid signature, swap it with the running bundle, relaunch.
/// The automatic check runs a few seconds after launch and once a day after that; nothing is installed without a click on "Update to X and Relaunch".
/// Modelled on Shellder's Updater (github.com/Phantom1003/Shellder).
final class Updater: ObservableObject {
    struct Release: Equatable {
        /// "1.1": the tag without the v.
        let version: String
        let asset: URL
        /// The release page (release notes).
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        /// The fraction downloaded, nil while the size is unknown.
        case downloading(Release, Double?)
        case installing(Release)
        case failed(String)
    }

    /// CFBundleShortVersionString from Info.plist; an executable run straight from swift build has none and shows "?".
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    static let bundleID = "local.phantom.hoopa"
    static let releaseRepo = "Phantom1003/Hoopa"
    /// The "latest release" JSON. The test hook HOOPA_UPDATE_API can point it at a local copy (see AGENTS.md).
    static let api = URL(string: ProcessInfo.processInfo.environment["HOOPA_UPDATE_API"]
                         ?? "https://api.github.com/repos/\(releaseRepo)/releases/latest")!
    static let interval: TimeInterval = 24 * 3600
    private static let autoKey = "autoUpdate"

    @Published private(set) var state: State = .idle
    /// Check at launch and once a day; switched off, only "Check for Updates…" remains.
    @Published var automatic: Bool = UserDefaults.standard.object(forKey: Updater.autoKey) == nil
        ? true : UserDefaults.standard.bool(forKey: Updater.autoKey) {
        didSet {
            UserDefaults.standard.set(automatic, forKey: Self.autoKey)
            schedule()
        }
    }
    /// The one-liner shown to the user (the toast at the bottom of the panel) and how many seconds it stays.
    var notify: ((String, Double) -> Void)?

    var available: Release? {
        if case .available(let r) = state { return r }
        return nil
    }

    private var busy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    /// Running from an .app bundle (an executable run straight from swift build cannot be swapped).
    private static var bundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private var timer: Timer?
    private var download: Download?
    /// The newest version already announced: the same version is not announced again on the next daily check.
    private var announced: String?
    private let work = DispatchQueue(label: "hoopa.updater", qos: .utility)

    func start() {
        guard Self.bundled else { Log.write("Update: not running from an app bundle, no automatic check"); return }
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule() {
        stop()
        guard automatic, Self.bundled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        // Launch is busy enough; check a few seconds later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if let s = self, s.automatic { s.check() }
        }
    }

    // MARK: Check

    /// Asks the release API for the latest version. A manual check reports every outcome in the toast; the automatic one only announces a new version and merely logs failures.
    func check(manual: Bool = false) {
        guard !busy else { return }
        let before = state
        state = .checking
        var req = URLRequest(url: Self.api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let outcome = Self.latest(data, resp, err)
            DispatchQueue.main.async {
                guard let self else { return }
                switch outcome {
                case .success(let r?):
                    Log.write("Update: new version \(r.version) available (running \(Self.version))")
                    self.state = .available(r)
                    if manual || self.announced != r.version {
                        self.announced = r.version
                        self.notify?(String(localized: "Version \(r.version) is available"), 4)
                    }
                case .success(nil):
                    Log.write("Update: already up to date (\(Self.version))")
                    self.state = .upToDate
                    if manual { self.notify?(String(localized: "Hoopa \(Self.version) is up to date"), 2.5) }
                case .failure(let e):
                    Log.write("Update check failed: \(e)")
                    if manual {
                        self.state = .failed(e.description)
                        self.notify?(String(localized: "Check failed: \(e.description)"), 6)
                    } else {
                        self.state = before
                    }
                }
            }
        }.resume()
    }

    /// The version in the reply that is newer than the running one; nil when already up to date.
    static func latest(_ data: Data?, _ resp: URLResponse?, _ err: Error?) -> Result<Release?, UpdateError> {
        if let err { return .failure(UpdateError(err.localizedDescription)) }
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            return .failure(UpdateError("HTTP \(http.statusCode)"))
        }
        guard let data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
            return .failure(UpdateError("unexpected reply from \(api.host ?? "the release endpoint")"))
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(latest, than: version) else { return .success(nil) }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zips = assets.compactMap { a -> URL? in
            guard let name = a["name"] as? String, name.hasSuffix(".zip"),
                  let url = a["browser_download_url"] as? String else { return nil }
            return URL(string: url)
        }
        guard let asset = zips.first else { return .failure(UpdateError("release \(tag) has no zip asset")) }
        return .success(Release(version: latest, asset: asset, page: page))
    }

    /// Dotted numbers compared segment by segment, missing segments count as 0 ("1.3" > "1.2.9", "1.2.0" == "1.2"); non-numeric segments count as 0 too.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Install

    func install() {
        guard let r = available else { return }
        state = .downloading(r, nil)
        let bundle = Bundle.main.bundleURL
        Log.write("Update: downloading \(r.asset.lastPathComponent)")
        notify?(String(localized: "Downloading \(r.version)…"), 2.5)
        download = Download(r.asset, progress: { [weak self] fraction in
            DispatchQueue.main.async {
                if case .downloading = self?.state { self?.state = .downloading(r, fraction) }
            }
        }, done: { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.download = nil
                switch result {
                case .failure(let e):
                    self.fail(r, e.description)
                case .success(let zip):
                    self.state = .installing(r)
                    self.work.async {
                        do {
                            try Self.replace(bundle, with: zip, expecting: r.version)
                            DispatchQueue.main.async {
                                Log.write("Update: installed \(r.version) into \(bundle.path), relaunching")
                                Relaunch.now(bundle.path)
                            }
                        } catch {
                            DispatchQueue.main.async { self.fail(r, String(describing: error)) }
                        }
                    }
                }
            }
        })
    }

    /// The download or the install failed: log, toast, and go back to "new version available" so the user can retry.
    private func fail(_ r: Release, _ reason: String) {
        Log.write("Update install failed: \(reason)")
        state = .available(r)
        notify?(String(localized: "Update failed: \(reason)"), 6)
    }

    /// Unpacks next to the zip, checks what came out, then swaps it with the bundle at `current`. Both moves are renames inside one directory,
    /// so the app never has a "half there" moment. The old bundle is deleted; the process launched from it keeps its mapped binary until it exits.
    private static func replace(_ current: URL, with zip: URL, expecting version: String) throws {
        let fm = FileManager.default
        guard current.pathExtension == "app" else {
            throw UpdateError(String(localized: "Hoopa is not running from an app bundle"))
        }
        if current.path.contains("/AppTranslocation/") {
            throw UpdateError(String(localized: "Hoopa runs from a quarantined copy; move it to Applications first"))
        }
        let dir = zip.deletingLastPathComponent().appendingPathComponent("unpacked")
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let unzip = run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])
        guard unzip.status == 0 else { throw UpdateError("ditto: \(unzip.stderr)") }

        let apps = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: { $0.pathExtension == "app" }),
              let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            throw UpdateError(String(localized: "the archive holds no app"))
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else {
            throw UpdateError(String(localized: "the download is not Hoopa"))
        }
        let got = info["CFBundleShortVersionString"] as? String ?? "?"
        guard got == version else {
            throw UpdateError(String(localized: "the download is version \(got), not \(version)"))
        }
        let sig = run("/usr/bin/codesign", ["--verify", "--strict", app.path])
        guard sig.status == 0 else { throw UpdateError(String(localized: "code signature check failed: \(sig.stderr)")) }
        // A URLSession download carries no quarantine flag, but strip it once more to be safe.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])

        let old = current.deletingLastPathComponent().appendingPathComponent("." + current.lastPathComponent + ".old")
        try? fm.removeItem(at: old)
        do { try fm.moveItem(at: current, to: old) } catch {
            throw UpdateError(String(localized: "cannot replace \(tilde(current.path)): \(error.localizedDescription)"))
        }
        do { try fm.moveItem(at: app, to: current) } catch {
            try? fm.moveItem(at: old, to: current)
            throw UpdateError(String(localized: "cannot replace \(tilde(current.path)): \(error.localizedDescription)"))
        }
        try? fm.removeItem(at: old)
        try? fm.removeItem(at: zip.deletingLastPathComponent())
    }

    private static func tilde(_ p: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return p.hasPrefix(home + "/") ? "~" + p.dropFirst(home.count) : p
    }

    private static func run(_ binary: String, _ args: [String]) -> (status: Int32, stderr: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        let err = Pipe()
        p.standardError = err
        do { try p.run() } catch { return (-1, "\(error)") }
        let e = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: e, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// One download into its own directory, with progress. The session holds this object until the task ends.
private final class Download: NSObject, URLSessionDownloadDelegate {
    private let progress: (Double?) -> Void
    private let done: (Result<URL, UpdateError>) -> Void
    private var session: URLSession!
    private var saved: Result<URL, UpdateError>?

    init(_ url: URL, progress: @escaping (Double?) -> Void, done: @escaping (Result<URL, UpdateError>) -> Void) {
        self.progress = progress
        self.done = done
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        session.downloadTask(with: req).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil)
    }

    /// The file at `location` is gone once this method returns; move it at once.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("hoopa-update-\(getpid())")
        let dest = dir.appendingPathComponent("update.zip")
        do {
            try? fm.removeItem(at: dir)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.moveItem(at: location, to: dest)
            saved = .success(dest)
        } catch {
            saved = .failure(UpdateError(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if let error { return done(.failure(UpdateError(error.localizedDescription))) }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return done(.failure(UpdateError("HTTP \(http.statusCode)")))
        }
        done(saved ?? .failure(UpdateError("the download left no file")))
    }
}

/// Launches the bundle at `path` (this one by default) after this process has exited, then quits.
/// A plain open would only activate the old process that has not quit yet. The HOOPA_* test hooks travel along, so a test copy is still a test copy after the relaunch.
enum Relaunch {
    static func now(_ path: String = Bundle.main.bundlePath) {
        let hooks = ProcessInfo.processInfo.environment
            .filter { $0.key.hasPrefix("HOOPA_") }
            .flatMap { ["--env", "\($0.key)=\($0.value)"] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; /usr/bin/open \"$@\"", "open"]
            + hooks + [path]
        try? p.run()
        NSApp.terminate(nil)
    }
}
