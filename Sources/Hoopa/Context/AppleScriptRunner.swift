import Foundation

enum AppleScriptError: Error {
    case launch(String)
    case script(String)
}

/// Runs AppleScript in an osascript child process so the main thread is not blocked; the permission still belongs to this app.
enum AppleScriptRunner {
    static func run(_ source: String, timeout: TimeInterval = 20) -> Result<String, AppleScriptError> {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("hoopa-\(UUID().uuidString).applescript")
        do {
            try source.write(to: tmp, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.launch(error.localizedDescription))
        }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = [tmp.path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return .failure(.launch(error.localizedDescription)) }

        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        var errData = Data()
        let errGroup = DispatchGroup()
        errGroup.enter()
        DispatchQueue.global().async {
            errData = err.fileHandleForReading.readDataToEndOfFile()
            errGroup.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        errGroup.wait()
        watchdog.cancel()

        if p.terminationStatus != 0 {
            let msg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            Log.write("AppleScript failed code=\(p.terminationStatus) \(msg)")
            return .failure(.script(msg.isEmpty ? "osascript exit code \(p.terminationStatus)" : msg))
        }
        var s = String(decoding: data, as: UTF8.self)
        while s.hasSuffix("\n") || s.hasSuffix("\r") { s.removeLast() }
        return .success(s)
    }

    /// Escapes for the inside of an AppleScript string literal.
    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
