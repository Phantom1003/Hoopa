# Hoopa manual

Hoopa is a floating to-do panel for macOS. Each to-do can be bound to the
place you work on it (a window, a browser tab, a sidebar item or editor tab
inside an app, a document) and carry a timer or a date. Clicking the to-do's
chip brings that page back; the countdown and a system notification keep the
deadline in view.

## Principles

* **Public interfaces first, then Accessibility, then the window.** When a
  page is bound, Hoopa probes what the app offers (the log calls this the
  interface probe) and records every anchor it can get, most reliable first:
  the browser's AppleScript dictionary, the window's `AXDocument`, a link
  format the app documents (Slack, Obsidian, VS Code), the Accessibility
  element, and finally the window itself. Jumping back tries them in the
  same order and stops at the first one that is **confirmed** to have
  arrived.
* **No OCR, no in-app search, no private routes.** Hoopa does not read the
  screen, does not type into ⌘K or ⌘F, and does not rely on internal URLs or
  IDs reverse engineered from an app, since those change between versions.
* **The cursor stays put.** Every scroll, click and key press on the way
  back is posted to the target app's process (`CGEvent.postToPid`, AX
  actions), never through the system input queue. A key is sent only after
  the Accessibility focus is confirmed to be on the target, so nothing lands
  in a text field you are typing in.
* **Local data only.** To-dos live in one JSON file under
  `~/Library/Application Support/Hoopa/`. Nothing leaves the machine.

## The panel

The panel is a floating, non-activating window: it stays above your other
windows (switch *Keep Panel on Top* off in the ⋯ menu to let it fall behind),
follows you to every Space, and takes clicks without becoming the active app,
so the window you are working in keeps the keyboard. Drag it by any empty
area; the expanded panel can be resized and remembers its frame.

Show or hide it with **⌃⌥T** or a left click on the menu bar icon. A right
click on the icon gives a menu with *Show/Hide Panel*, *Expand/Collapse* and
*Quit*.

The panel has no header: the list starts at the top. The item count, **+**
(the composer), **⇅** (sort by time), the trash button and the **⋯** menu
float in a glass capsule at the bottom right, and the list leaves room under
its last card so that card can scroll clear of the capsule. The trash button
deletes every to-do, completed ones included, after a confirmation. The ⋯
menu holds *Keep Panel on Top*, *Show Completed*, *Language*, the
Accessibility status, *Clear Completed*, the shortcut reminder and *Quit
Hoopa*. While Accessibility is not granted, an orange banner with a *Grant*
button sits at the top of the panel.

Each to-do is a card:

| | |
|---|---|
| ○ | Marks the to-do done. Completed to-dos disappear unless *Show Completed* is on; *Clear Completed* removes them for good. |
| Title | One line. A small text icon at its end means the to-do has notes; hover it to read them. |
| Chip row | The binding chip (app icon + page name) and the time chip (countdown · absolute time). Clicking the binding chip jumps; clicking the time chip changes the time. Every chip has a × that removes the binding or the time. When the row is too narrow, the absolute time is dropped first (hover the chip to see it), then the page name is truncated. |
| Hover actions | Timer (when the to-do has none), ⌖ (bind, or rebind), trash. They sit at the right end of the chip row, or float over the title when there is no chip row. |

Click a card to open its details: the title and the notes become editable and
save as you type. Click an empty spot in the list, or press Esc, to close
them. The right-click menu has everything as well: *Jump to Bound Page*,
*Rebind…*, *Unbind* (or *Bind to Window / Page…*), *Timer / Date…*, *Remove
Time*, *Mark as Done* and *Delete*.

Drag a card onto another one to reorder: the upper half of the target inserts
before it, the lower half after.

## The collapsed list

The ear is a small tab outside the panel's left edge. It slides out while the
mouse is over the panel and shows ⌃ when the panel is expanded and ⌄ when it
is collapsed, in exactly the same spot, so repeated clicks only toggle.

Collapsed, the panel is a narrow glass slab with one row per to-do, in the
same order as the panel (your order, or by time when ⇅ is on), at most six
rows and then "N more" (click it to expand):

* **The ball** is the to-do's head: the bound app's icon on a grey disc, or a
  green fuzzy ball with the title's first letter when nothing is bound. A
  to-do with a time gets a ring around it: a faint full track and a solid arc
  for what is left (a timer counts from its full length, a date from its last
  24 hours). The ring, an unbound ball and the countdown turn orange when the
  time is close and red when it has passed.
* **Title · page name**, the page name only when both fit whole.
* **The countdown** at the right edge, `Overdue` once the time has passed.
  The absolute time is on the time chip in the expanded panel.

Click a row and the panel expands with that to-do's details open. Point at a
row and ○ appears at its right end, where the countdown was: click it to mark
the to-do done. The ball stays the to-do's head and is not a button. The
right-click menu offers *Jump to Bound Page*, *Mark as Done*, *Expand* and
*Quit*. When there are no to-dos at all, the slab shows a single "+ Add a
to-do" row that expands the panel with the composer open.

The panel starts in whichever state it was left in.

## Adding a to-do

Press **+** in the capsule (or the "+ Add a to-do" row of an empty collapsed
list). The composer appears above the list, and stays there while the list is
empty:

* **The title** is one line; Return (or ⌘Return) adds the to-do. Notes go in
  the card afterwards.
* **⌖ Bind Window / Page** starts the picker (see below). The chosen page
  appears as a chip; click it to pick again, or its × to clear it.
* **◔ Timer / Date** opens the time picker. A timer only starts counting the
  moment the to-do is added.

Any one of title, binding or time is enough to add a to-do. Esc or the ×
closes the composer and discards what was in it.

## Binding a to-do to a page

The picker dims the screen and follows the mouse:

| Action | How |
|---|---|
| Bind a whole window | Move the mouse to highlight the window, click. |
| Bind something inside it | Hold **⌥**: tabs, sidebar items, buttons and rows under the mouse are highlighted. Click one. |
| Bind a browser tab | Hold **⌥** and click the tab in the tab strip. Clicking the window without ⌥ binds the current tab. |
| Bind a Slack conversation | Clicking the window binds the current conversation; hold **⌥** to pick a DM or channel row in the sidebar. |
| Cancel | Esc or a right click. |

After the click the panel comes back with "Reading page info…" while Hoopa
probes the app's interfaces and collects the anchors, then "Bound: …" with
the result. Hover the chip to see every anchor that was recorded.

Apps that draw their own UI (WeChat 4.x and the like) expose only the three
title bar buttons to the system. The picker says so in ⌥ mode; such windows
can only be bound as a whole.

## Jumping back

Click the binding chip, choose *Jump to Bound Page* from a right-click menu,
or click the to-do's notification. The chip shows a spinner while the jump
runs, and a toast reports the outcome: *Jumped back*, *The page was closed
and has been reopened*, *Triggered the target, but couldn't confirm the page
switched*, *Switched to the window, but couldn't find the exact target*,
*Activated the app, but couldn't find that window*, or why it failed.

| Anchor | Interface | Apps | Jump | Confirmation |
|---|---|---|---|---|
| Tab | The browser's AppleScript dictionary | Safari and the Chromium family (Chrome, Edge, Brave, Vivaldi, Opera, Chromium) | Find the tab by URL and switch to it; open the URL in a new tab if it was closed | Window title equals the tab title |
| Document | The window's `AXDocument` (a standard attribute) | Xcode, Preview, TextEdit, Pages, … | Ask the app to open the file again | The window's `AXDocument` is that path |
| Link | A link format from the app's **official documentation**: Slack deep links `slack://channel?team=…&id=…` (workspace ID from the web area's `AXURL`, conversation ID from the row's `AXDOMIdentifier`), Obsidian `obsidian://open?vault=…&file=…`, VS Code `vscode://file/<absolute path>` (from the explorer row's full path; not for SSH remote windows) | Slack, Obsidian, VS Code | Hand the link to the app | Window title, or the conversation / note name showing somewhere in the window |
| Element | The Accessibility tree: role, text, `AXDOMIdentifier`, path from the window, the enclosing tab panel (`AXTabPanel`), position within the window | Any app with an Accessibility tree (Claude, Codex, VS Code, Finder, …), picked with ⌥ | The flow below | Target becomes selected, its text appears elsewhere, or the window title changes |
| Window | Window ID (`_AXUIElementGetWindow`) and title | Every app | Bring the window to front | — |

`AXEnhancedUserInterface` is the flag VoiceOver sets. Chromium switches to
full accessibility mode when it is on, and VS Code and others decide a screen
reader is present and change the editor's behaviour. Hoopa therefore turns
it on only for the moment it reads Slack's `AXURL`, turns it straight back
off, and otherwise sets only Electron's own `AXManualAccessibility`.

### How an element anchor is restored

1. **Switch back to the tab.** If the `AXTabPanel` the target lived in is not
   showing, press the matching `AXTabButton` (Slack's Home, for instance).
2. **Find the target.** Walk the recorded path; then search by
   `AXDOMIdentifier`; then the whole tree by role and text; then by the text
   on screen. If it is not visible, `AXScrollToVisible` it, then scroll the
   column it lives in (scroll wheel events posted to the app's process).
   Among same-named candidates the one in that column wins.
3. **Trigger it.** In turn: `AXPress` (on the target, or on a child that has
   it, such as the path label inside a VS Code explorer row) → set
   `AXSelected` → move the Accessibility focus onto the target and, once the
   focus is confirmed there, send the app a single Space (Return for links
   and buttons) → post a click to the app's process (`CGEvent.postToPid`,
   which Chromium apps do not always accept). After every step Hoopa checks
   whether it has arrived or the target's state (selected, expanded, value,
   window title) changed, and stops, so nothing is triggered twice.
4. **Confirm.** The target is selected, its text shows up elsewhere (the
   title bar, a conversation header) or the window title contains it.
   Otherwise the toast says the target was triggered but the switch could
   not be confirmed.

## Timers, dates and notifications

The ◔ button and the *Timer / Date…* menu item open the time picker:

* **Timer**: a dial and the presets 5, 10, 15, 25, 45 and 60 minutes. On a
  new to-do the timer starts when the to-do is added; on an existing one, when
  you press *Set*.
* **Date & Time**: today, tomorrow, the day after (or any day from the
  calendar) and a clock dial.

The time chip shows the countdown in its two largest units (`1d 03h`,
`20h 00m`, `4m 10s`) followed by the absolute time (`14:30`, or `Tomorrow
14:30`). It turns orange when a timer has less than ten minutes or a date less
than an hour to go, and red with `Overdue` once the time has passed.

At the moment itself Hoopa posts a system notification with the to-do's title
("Timer finished" or "Time's up", plus "Click to go back to …" when the
to-do is bound). Clicking the notification jumps to the bound page, or opens
the panel for an unbound to-do. macOS asks for notification permission the
first time a to-do gets a time. Marking the to-do done or removing the time
cancels the pending notification, and the pending ones are re-scheduled when
Hoopa starts.

## Sorting

⇅ in the capsule switches the list between your own order and time order.
Sorted by time, to-dos with a time come first, soonest first, with overdue
ones at the top, and the rest keep their manual order after them, in the
groups *Overdue*, *Today*, *Tomorrow*, *Later* and *Unscheduled*. New to-dos
and changed times fall into place by themselves, and the groups move with the
clock. Dragging a card while sorted is allowed as long as the time order is
kept; a drag that breaks it switches sorting off and keeps your new order,
with a toast saying so. The collapsed list follows the same setting.

## Language

The interface is English unless you pick Simplified Chinese in the ⋯ menu
under *Language*. The choice does not follow the system language, is stored
in the app's own `AppleLanguages` preference (the same key System Settings
uses for per-app languages) and takes effect after the automatic relaunch.
Dates and plurals follow the interface language.

To add a language, copy `Resources/zh-Hans.lproj/Localizable.strings` to
`Resources/<lang>.lproj/Localizable.strings` (a BCP 47 name such as `ja` or
`zh-Hant`), translate the right-hand sides (the keys are the English text),
add the language to `CFBundleLocalizations` in `Resources/Info.plist` and to
`AppLanguage.swift`. `en.lproj` holds only the plural rules
(`Localizable.stringsdict`). Keys a translation lacks fall back to English.

## App icon

`build.sh` runs `scripts/icons.swift` on `scripts/icon-source.png` (a picture
on a transparent background) at every build:

* **App icon**: the transparent margin is cropped, the picture is centred on a
  square with 5% padding on every side and scaled to every size from 16 to
  1024 px, then packed into `Hoopa.icns`. From macOS 26 on, an icon that is
  not a rounded square is shown by the system inside a grey rounded square.
* **Menu bar icon**: the silhouette of the whole figure with the eyes cut out, as
  a monochrome template image (alpha only, so macOS tints it like its own
  status icons), 18 pt high plus an @2x version. It is a silhouette rather
  than a light/dark split of the picture because a luminance split drops
  the dark outlines and leaves the lighter parts floating apart.

Replace the picture and rebuild to change both icons. A binary built with
plain `swift build` has no bundle and falls back to the checklist symbol in
the menu bar.

## Build & run

```bash
./build.sh            # -> build/Hoopa.app
open build/Hoopa.app
```

Requires macOS 14 or later and Xcode. The SwiftUI macro plugin ships only
with Xcode, so the script points `DEVELOPER_DIR` at `/Applications/Xcode.app`
when it is not set. `swift build` on its own compiles the code but produces
no bundle, icons or translations.

**Signing.** macOS records the Accessibility grant against the app's code
signature. An ad hoc signature changes with every build and the grant would
be lost each time, so `build.sh` signs with the first *Apple Development*
certificate in the login keychain and stops with an error when there is none
or the signature fails; it never falls back to ad hoc by itself. Sign into
Xcode with any Apple ID (Settings → Accounts → Manage Certificates → + →
Apple Development; a free account's Personal Team is enough) to get one. The
signing needs the private key, so run the script from Terminal and click
*Always Allow* when the keychain asks. `SIGN_IDENTITY="…" ./build.sh` picks
another identity, and `SIGN_IDENTITY=- ./build.sh` signs ad hoc on purpose.

**Permissions.** On first launch the panel asks for Accessibility (window
detection and jumping). The first time a browser tab is bound, macOS asks
whether Hoopa may control Safari or Chrome (Automation). Notifications are
requested the first time a to-do gets a time. All three are recorded under
the bundle ID `local.phantom.hoopa`.

**CI** (`.github/workflows/build.yml`) runs on every push to `main`, every
pull request, every `v*` tag and on manual dispatch: `SIGN_IDENTITY=-
./build.sh` on `macos-26` (the GA image, blocking) and on `xcode-27` (the
Xcode 27 preview image, allowed to fail), followed by structural checks of
the bundle (`codesign --verify --strict`, `plutil -lint`, the icon files).
There is no functional test. Every run attaches `Hoopa.zip`; a `v*` tag
publishes the `macos-26` build as a GitHub Release. Runners have no
certificate, so CI builds are ad hoc signed and not notarised: the
Accessibility grant does not survive an update to another CI build, and
Gatekeeper may ask you to confirm the first launch. Day to day, build
locally.

## Data and preferences

* To-dos: `~/Library/Application Support/Hoopa/todos.json`, written shortly
  after every change. A binding or time an older version cannot read is
  dropped for that to-do; the file itself still loads.
* Log: `~/Library/Application Support/Hoopa/hoopa.log`, started over once it
  passes 2 MB.
* Preferences (`local.phantom.hoopa`): the panel frame, the collapsed state,
  the sort setting and the interface language.

## Diagnostics

* The log records every pick (the interfaces the app was found to offer, the
  anchors kept), every jump (which anchor succeeded and how it was
  confirmed) and every permission change.
* To see what an app exposes before binding something in it, dump its
  Accessibility tree:

  ```bash
  open build/Hoopa.app --args --dump-ax <bundleID>
  ```

  The result lands in `axdump.txt` next to the log: every element with its
  `AXURL` / `AXDocument`, `AXDOMIdentifier` (`#id`), supported actions
  (`<AXPress>`) and the menu bar. Claude for desktop, for instance
  (`--dump-ax com.anthropic.claudefordesktop`), lists its sidebar
  conversations as `AXButton`s prefixed with "Running / Idle / Archived";
  they can be bound in ⌥ mode and are matched on the inner text when
  jumping.

## Known limitations

* Apps that draw their own UI (WeChat, DingTalk, …) have no Accessibility
  tree; only the window can be bound.
* Browsers without an AppleScript dictionary (Arc, Firefox, …) fall back to
  window + title matching.
* Slack with several workspaces works through the deep link, which carries
  the workspace ID; picking a conversation with ⌥ needs its row visible in
  the sidebar.
* VS Code windows connected over SSH have no local path, so their files
  cannot be bound as links.
* To support a new app, run `--dump-ax` first to see what it exposes
  (`AXURL`, `AXDOMIdentifier`, actions, menu bar), then check whether it
  documents a link format or ships an AppleScript dictionary.

## Code layout

```
Sources/Hoopa/
  main.swift                 Entry point (menu bar accessory app), --dump-ax
  App/AppDelegate.swift      Menu bar item, panel, ⌃⌥T, picking, notifications
  App/FloatingPanel.swift    Non-activating floating panel: clicks work without activating the app
  App/AppCoordinator.swift   Bridge between the SwiftUI views and AppKit; permission state
  App/AppLanguage.swift      Interface language (English by default, stored per app)
  App/Notifier.swift         Due notifications
  App/Log.swift              File log
  Models/Models.swift        TodoItem, ContextBinding, the Anchor kinds, Due
  Store/TodoStore.swift      JSON persistence, ordering, sort by time
  Picker/WindowPicker.swift  Full-screen picking overlay: highlights windows / elements
  Context/ContextCapture.swift   Picking: the window / element under the mouse, anchors in order
  Context/ContextRestore.swift   Jumping: try the anchors in order, confirm each step
  Context/TextLocator.swift      Find, scroll to and confirm a target by its text in the AX tree
  Context/BrowserScripting.swift AppleScript: list, switch and open browser tabs
  Anchors/AppInterfaces.swift    Interface probe; documented link formats (Slack, Obsidian, VS Code)
  Anchors/BrowserTabs.swift      Browser tab anchors (tab strip picking, matching, switching)
  Anchors/WindowMatch.swift      Choosing the window: ID / title / AXDocument / only one / focused
  AX/AX.swift                Accessibility API wrappers, element paths and search
  AX/WindowList.swift        CGWindowList hit testing, coordinate conversion
  AX/TitleMatch.swift        Fuzzy title matching
  AX/AXDump.swift            --dump-ax
  UI/                        SwiftUI: RootView (glass plate, ear), ExpandedView, CompactView,
                             TodoCard, InputPill, Chips, DuePicker, Dials, CalendarGrid, Style
Resources/
  Info.plist
  zh-Hans.lproj/             Simplified Chinese: keys are the English strings in the code
  en.lproj/                  Plural rules (Localizable.stringsdict)
scripts/
  icon-source.png            The picture both icons are made from
  icons.swift                App icon and menu bar template, run by build.sh
```
