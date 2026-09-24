import AppKit

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--dump-ax"), i + 1 < args.count {
    let text = AXDump.run(bundleID: args[i + 1])
    let url = Log.url.deletingLastPathComponent().appendingPathComponent("axdump.txt")
    try? text.write(to: url, atomically: true, encoding: .utf8)
    exit(0)
}

AppLanguage.applyDefault()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
