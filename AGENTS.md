# Notes for agents working on Hoopa

Hoopa is a macOS menu bar app (`Sources/Hoopa`, SwiftPM, SwiftUI + AppKit):
a floating to-do panel where each to-do can be bound to a window, a browser
tab, an element inside an app or a document, and jumped back to with one
click. The user manual is `docs/manual.md`; read its *Principles* and
*Jumping back* sections before touching anything under `Context/`,
`Anchors/` or `AX/`.

There is no test target. Changes are checked by building the bundle and
driving the app by hand.

## Build

```bash
swift build             # compile check only: no bundle, icons or translations
./build.sh              # release build wrapped and signed as build/Hoopa.app
```

* `build.sh` needs Xcode (the SwiftUI macro plugin ships only with Xcode) and
  sets `DEVELOPER_DIR` to `/Applications/Xcode.app` when it is unset.
* It signs with the first *Apple Development* identity in the keychain, or
  the one in `SIGN_IDENTITY`, and **stops with an error rather than falling
  back to ad hoc**: macOS ties the Accessibility grant to the signature, and
  an ad hoc one changes with every build. Signing needs the keychain's
  private key, which the app's shell sandbox cannot reach, so run the script
  from Terminal. `SIGN_IDENTITY=-` signs ad hoc on purpose (what CI does).
* Relaunching the app after a build takes the user's running instance down.
  Ask before doing it while the user is working.

## CI (`.github/workflows/build.yml`)

* Runs on every push to `main`, every PR, every `v*` tag and manual dispatch.
* Matrix: `macos-26` (GA, blocking) and `xcode-27` (preview,
  `continue-on-error`). Both run `SIGN_IDENTITY=- ./build.sh`.
* "Verify bundle" checks structure only: `codesign --verify --strict`,
  `plutil -lint`, the icns and menubar PNGs. No functional test runs on CI.
* A `v*` tag publishes a GitHub Release with the `macos-26` zip, ad hoc
  signed, not notarised.

## How binding and jumping must work

* Order of preference: an interface the system or the app documents
  (AppleScript dictionary, `AXDocument`, official deep-link formats such as
  Slack's or Obsidian's), then the Accessibility tree, then the window.
* Never: OCR or screen recording, in-app search (⌘K / ⌘F plus typing),
  moving the cursor or posting HID-level events, synthetic keyboard input
  into an unconfirmed focus, or internal routes and IDs dug out of an app's
  bundle (they change between versions).
* Trigger with AX actions (`AXPress`, `AXSelected`, `AXScrollToVisible`), then
  `CGEvent.postToPid`; verify after every step; stop as soon as the target
  is reached.
* `AXEnhancedUserInterface` changes how Chromium and VS Code behave. Only set
  it inside `AX.withEnhancedUI` for the one read that needs it, never leave
  it on.
* Before supporting a new app, dump its tree: `open build/Hoopa.app --args
  --dump-ax <bundleID>` writes `axdump.txt` next to the log.

## UI conventions

* User-facing strings are English in the code and are the keys of
  `Resources/zh-Hans.lproj/Localizable.strings`. Every new string needs its
  Simplified Chinese line there; plurals go through
  `en.lproj/Localizable.stringsdict`.
* No fixed widths tuned for one language. Check layouts in both English and
  Chinese (`-AppleLanguages '(zh-Hans)'`); use `ViewThatFits` and
  `layoutPriority` where the languages differ in length.
* The collapse/expand toggle is the ear at the left edge and sits at the same
  spot in both states, so that nothing else ever lands under a just-clicked
  toggle.
* The collapsed list stays narrow (one row per to-do, 220 pt wide). Prefer
  stable, one-click layouts over hover-driven morphs.
* Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`) is used behind
  `#available(macOS 26.0, *)` with material fallbacks in `UI/Style.swift`;
  keep both paths working.

## Data and diagnostics

* To-dos: `~/Library/Application Support/Hoopa/todos.json`. The decoder
  drops a binding or time it cannot read instead of failing the file; keep
  that when changing the model, and do not add migrations beyond that.
* Log: `~/Library/Application Support/Hoopa/hoopa.log` (a pick logs the
  probed interfaces and the anchors kept; a jump logs which anchor won and
  how it was confirmed). Code comments, log lines and UI strings are English.
* Preferences live under the bundle ID `local.phantom.hoopa`.

## Conventions

* Commit messages: `[feature] description` or `[fix] description`, English.
  Do not commit or push unless asked.
* Commit messages name no agent: no `Co-Authored-By` trailer, no "Generated
  with" line, nothing that says which tool wrote the change.
* No personal data (real page titles, account names, Team IDs) in the
  repository, including in screenshots and log excerpts.
