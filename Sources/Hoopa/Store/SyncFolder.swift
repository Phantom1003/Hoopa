import Foundation

/// Where the to-dos are mirrored for other Macs: nowhere, the Hoopa folder in iCloud Drive, or any folder some other service keeps in step (Dropbox, Syncthing, …).
/// Stored in the preference `syncFolder` as the folder's path; the iCloud Drive folder's path stands for .iCloudDrive.
enum SyncMode: Equatable {
    case off
    case iCloudDrive
    case folder(URL)

    /// iCloud Drive as the Finder shows it. Plain files there sync without any entitlement, so an ad hoc signed build can use it.
    static let iCloudDriveRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    static let iCloudFolder = iCloudDriveRoot.appendingPathComponent("Hoopa", isDirectory: true)
    private static let key = "syncFolder"

    var folder: URL? {
        switch self {
        case .off: return nil
        case .iCloudDrive: return Self.iCloudFolder
        case .folder(let url): return url
        }
    }

    /// The mode for a folder: the iCloud Drive one, whichever way it was picked, is .iCloudDrive.
    static func forFolder(_ url: URL) -> SyncMode {
        url.standardizedFileURL == iCloudFolder.standardizedFileURL ? .iCloudDrive : .folder(url)
    }

    static func load() -> SyncMode {
        guard let path = UserDefaults.standard.string(forKey: key), !path.isEmpty else { return .off }
        return forFolder(URL(fileURLWithPath: path, isDirectory: true))
    }

    func save() {
        if let folder { UserDefaults.standard.set(folder.path, forKey: Self.key) } else { UserDefaults.standard.removeObject(forKey: Self.key) }
    }
}

/// The copy of the to-do file in the sync folder: coordinated reads and writes (iCloud Drive downloads an evicted file on a coordinated read),
/// the conflict versions iCloud keeps when two Macs wrote at the same time, and a watch on the folder and the file that reports outside changes.
/// Everything here runs on `queue`; the store merges on the main thread.
final class SyncFolder {
    let folder: URL
    let fileURL: URL
    let queue = DispatchQueue(label: "hoopa.sync", qos: .utility)
    /// The bytes last written to or read from the file: a change notice that reads the same is our own write, or one already merged.
    var lastData: Data?
    /// The copy in the folder could not be read or decoded: nothing is written over it until it reads again (changes made meanwhile wait here).
    var blocked = false
    /// Called on `queue`, a moment after the file or the folder changed on disk.
    var onChange: (() -> Void)?

    private var folderSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    struct Unavailable: Error, CustomStringConvertible {
        let description: String
    }

    init(folder: URL) {
        self.folder = folder
        fileURL = folder.appendingPathComponent("todos.json")
    }

    /// Creates the folder (only inside a parent that exists: an unmounted volume must not be conjured up on the boot disk) and starts watching.
    func start() throws {
        let parent = folder.deletingLastPathComponent()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue else {
            throw Unavailable(description: parent.path)
        }
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        queue.sync {
            folderSource = watch(folder.path, mask: .write)
            fileSource = watch(fileURL.path, mask: [.write, .extend, .delete, .rename, .attrib])
        }
    }

    func stop() {
        queue.sync {
            pending?.cancel()
            folderSource?.cancel(); folderSource = nil
            fileSource?.cancel(); fileSource = nil
        }
    }

    /// The file's bytes; nil when there is no file yet (the caller then writes its own copy). Throws when the file exists but cannot be read (offline, half-synced): leave it alone.
    func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
        var data: Data?
        var inner: Error?
        var outer: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &outer) { url in
            do { data = try Data(contentsOf: url) } catch { inner = error }
        }
        if let outer { throw outer }
        if let inner { throw inner }
        return data
    }

    func write(_ data: Data) throws {
        var inner: Error?
        var outer: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &outer) { url in
            do { try data.write(to: url, options: .atomic) } catch { inner = error }
        }
        if let outer { throw outer }
        if let inner { throw inner }
        lastData = data
    }

    /// The versions iCloud Drive set aside because another Mac wrote the file at about the same time: their bytes, each marked resolved once taken.
    func takeConflictVersions() -> [Data] {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: fileURL), !versions.isEmpty else { return [] }
        var out: [Data] = []
        for v in versions {
            if let d = try? Data(contentsOf: v.url) { out.append(d) }
            v.isResolved = true
        }
        Log.write("Sync: \(versions.count) conflict version(s) taken from \(fileURL.lastPathComponent)")
        return out
    }

    // MARK: Watching

    private func watch(_ path: String, mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setEventHandler { [weak self] in self?.changed() }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    /// Settles for a moment first: a sync service writes a file in several steps (create, fill, rename into place, then attributes).
    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // An atomic replacement is a new file: the old descriptor stops reporting, so watch the path afresh.
            fileSource?.cancel()
            fileSource = watch(fileURL.path, mask: [.write, .extend, .delete, .rename, .attrib])
            onChange?()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
