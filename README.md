# Hoopa

A floating to-do panel for macOS. Every to-do can be **bound to the place where the work actually happens**: a window, a browser tab,
a sidebar item / editor tab inside an app, or a document. One click takes you straight back to that page, not merely to the app.

## Build & run

```bash
./build.sh
open build/Hoopa.app
```

Requires macOS 14+ and Xcode on this machine (SwiftUI's macro plugin ships only with Xcode; the script switches to `/Applications/Xcode.app` by itself).

After the first launch:
1. The top of the panel asks for the **Accessibility** permission (System Settings → Privacy & Security → Accessibility); recognising windows and jumping both depend on it.
2. The first time you bind a browser tab, macOS asks whether Hoopa may control Safari / Chrome; allow it.

> An ad hoc signed app gets a new signature on every rebuild, the Accessibility grant is lost and has to be removed and added again in System Settings.
> To avoid that, create a self-signed code signing certificate in Keychain Access (named `Hoopa Dev`, say) and run
> `SIGN_IDENTITY="Hoopa Dev" ./build.sh`; the grant then stays.

## Usage

| Action | How |
|---|---|
| Show / hide the panel | The ☑ icon in the menu bar, or the global shortcut ⌃⌥T |
| Add a to-do | Type in the field and press Return |
| Bind a page | Hover a to-do → click the ⌖ icon to enter pick mode |
| Pick: bind a whole window | Move the mouse to highlight a window → click |
| Pick: bind an element inside a window | Hold **⌥** to highlight a tab / sidebar item / button → click |
| Pick: bind a browser tab | Hold **⌥** and point at that tab in the tab bar → click; clicking the window without ⌥ binds the current tab |
| Pick: bind a Slack conversation | Clicking the window without ⌥ = the current conversation; hold ⌥ and point at a DM / channel row |
| Cancel picking | Esc or right click |
| Jump | Click the to-do row or the binding chip under it |
| Rename | Double-click the to-do |
| Rebind / unbind / delete | Context menu |
| Keep the panel on top, show completed | The ⋯ menu at the top right |

## How a binding "remembers" a page

Principle: **first the interfaces the system or the app provides publicly, then the system's Accessibility API, and only then fall back to the window**.
No text recognition, no in-app search, no guessing at an app's private routes. Picking probes which interfaces the app provides (the "interface probe" in the log),
records every anchor it can get in order of reliability, and jumping tries them in the same order; the first one **confirmed to have arrived** wins.

| Anchor | Interface | Applies to | How it jumps | How it confirms |
|---|---|---|---|---|
| Tab | The browser's AppleScript dictionary (Safari / Chrome family) | Browsers | Finds the tab by URL and switches to it; reopens it if closed | Window title = tab title |
| Document | The window's `AXDocument` (a standard system attribute) | Xcode, Preview, TextEdit, Pages… | Asks the app to reopen the file | The window's `AXDocument` equals the path |
| Link | A link format the app **documents officially**: Slack deep links `slack://channel?team=…&id=…` (the workspace ID from the web area's `AXURL`, the conversation ID from the conversation row's `AXDOMIdentifier`), Obsidian URIs `obsidian://open?vault=…&file=…`, VS Code `vscode://file/<absolute path>` (the tree row's child element carries the full path; SSH remote windows do not apply) | Slack, Obsidian, VS Code | Hands the link to the app | The window title / the conversation or note name appears in the window |
| Element | The Accessibility tree: role + text + `AXDOMIdentifier` + path + the enclosing tab panel (`AXTabPanel`) + position inside the window | Apps with an Accessibility tree (Claude, Codex, VS Code, Finder…; pick with ⌥ held) | See the general flow below | The target becomes selected / the text appears elsewhere / the window title |
| Window | Window ID (private API `_AXUIElementGetWindow`), title | Every app | Brings the window to the front | — |

Self-drawn apps such as WeChat 4.x expose only the three title bar buttons even with `AXEnhancedUserInterface` on; the system offers no usable interface at all,
so only the whole window can be bound (⌥ mode says so).

> `AXEnhancedUserInterface` is the flag VoiceOver sets; Chromium switches to full accessibility mode because of it,
> and apps such as VS Code decide "a screen reader was detected" and change the editor's behaviour. It is therefore only switched on while reading Slack's `AXURL` and switched off right after;
> otherwise only Electron's own `AXManualAccessibility` is set.

### The general flow for element anchors

1. **Switch back to the tab**: if the `AXTabPanel` the target lived in is not showing, trigger the matching `AXTabButton` (such as Home in Slack's left bar).
2. **Find the target**: walk the recorded path → by `AXDOMIdentifier` → search the whole tree by role + text → find the text on screen;
   if it is not showing, `AXScrollToVisible` first, then scroll inside the column the target lives in (scroll events are posted straight to the app's process). Among same-named targets the one in that column wins.
3. **Trigger**: in turn AXPress (if the target has none, press the child inside it that has AXPress, such as the path label in a VS Code tree row) → set selected (`AXSelected`)
   → move the accessibility focus onto the target, confirm the focus really landed on it, then post a single space to that app only (links / buttons retry with Return)
   → post the click straight to the app's process (`CGEvent.postToPid`; Chromium apps do not always accept it).
   Check after every step and stop as soon as the target is reached or its state (selected / expanded / value / window title) has changed, so nothing is triggered twice.
4. **Confirm**: the target becomes selected, or its text appears elsewhere (title bar, conversation header), or the window title contains it; otherwise the toast says "Target triggered, but the page change could not be confirmed".

The whole process **never moves the mouse cursor and never goes through the system input queue**: scrolls, clicks and keys are posted to the target process only, so whatever you are doing is not disturbed;
a key is sent only once the accessibility focus is confirmed on the target, so nothing lands in a text field.

## Code layout

```
Sources/Hoopa/
  main.swift                 Entry point (menu bar accessory app)
  App/AppDelegate.swift      Menu bar icon, floating panel, shortcut, bind / jump flow
  App/FloatingPanel.swift    Non-activating floating panel: hovering / a click works right away without activating the app
  App/AppCoordinator.swift   UI ↔ AppKit bridge, permission state
  Models/Models.swift        TodoItem / ContextBinding
  Store/TodoStore.swift      JSON persistence (~/Library/Application Support/Hoopa/todos.json)
  Picker/WindowPicker.swift  Full-screen pick overlay: highlights windows / elements, click to confirm
  Context/ContextCapture.swift   Pick: the window / element under the mouse, collects the anchors in order
  Context/ContextRestore.swift   Jump: tries the anchors in order; bring the window to front, switch tabs, trigger (AXPress / select / posted click), confirm
  Context/TextLocator.swift      Finds the target in the Accessibility tree by the text on screen, scrolls, confirms
  Context/BrowserScripting.swift AppleScript: read / switch browser tabs
  Anchors/AppInterfaces.swift    Probes the interfaces an app provides; officially documented link formats (Slack, Obsidian)
  Anchors/BrowserTabs.swift      Browser tab anchor (pick from the tab bar, resolve, switch)
  Anchors/WindowMatch.swift      Choosing a window: window ID / title / AXDocument / the only one / focused
  AX/AX.swift                Accessibility API wrapper, element paths and search
  AX/WindowList.swift        CGWindowList hit testing, coordinate conversion
  AX/TitleMatch.swift        Fuzzy title matching
  UI/                        SwiftUI panel views
```

## Diagnostics

- Log: `~/Library/Application Support/Hoopa/hoopa.log`
- Dump an app's Accessibility tree (to see whether its tabs / sidebar items can be selected):
  `open build/Hoopa.app --args --dump-ax <bundleID>` writes the result to `axdump.txt` in the same directory.
  The output lists every element's `AXURL` / `AXDocument`, `AXDOMIdentifier` (`#id`), the actions it supports (`<AXPress>`) and the menu bar.
  For example Claude for desktop: `--dump-ax com.anthropic.claudefordesktop`; its sidebar conversations are `AXButton`s with a
  "Running / Idle / Archived" prefix, ⌥ mode binds them directly and restoring matches on the inner plain text.

## Known limitations / possible extensions

- Apps with a self-drawn UI (WeChat, DingTalk…) have no Accessibility tree; only the window can be bound.
- Browsers without AppleScript (Arc, Firefox…) fall back to "window + title" matching.
- With several Slack workspaces the deep link carries the workspace ID and switches directly, but ⌥ picking needs the conversation row visible in the sidebar.
- No timed reminders / system notifications yet; add `dueDate` to `TodoItem` and use `UNUserNotificationCenter`.
- Before supporting a new app, run `--dump-ax <bundleID>` to see what it exposes (`AXURL`, `AXDOMIdentifier`, actions, menu bar),
  then check whether it documents a link format or an AppleScript dictionary.
