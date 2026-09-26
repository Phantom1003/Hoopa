# Hoopa

[![Build](https://github.com/Phantom1003/Hoopa/actions/workflows/build.yml/badge.svg)](https://github.com/Phantom1003/Hoopa/actions/workflows/build.yml)

**Hoopa is a to-do list that remembers where each task lives.** It is a small
floating panel for macOS, kept in the menu bar, where every to-do can be bound
to the place you actually work on it: a window, a browser tab, a sidebar item
or editor tab inside an app, a document. Later, one click on the to-do takes
you back to that exact page, not just to the app.

Hoopa finds its way back through the interfaces the system and the apps
already provide (AppleScript dictionaries, `AXDocument`, documented deep
links, the Accessibility tree). It never moves your mouse, never types into a
search box and never reads pixels off the screen.

Named after the genie whose rings open onto faraway places: each to-do is a
ring, and one click through it puts you back on the page it belongs to.

## Why

"Reply to the thread", "finish the review", "fix the flaky test": the note is
short, but the work is a Slack conversation, a pull request tab, a file in an
editor. Every time you come back to it you first have to find the window, then
the tab, then the row. Hoopa captures that place the moment you write the
to-do, shows the countdown next to it, and brings the page back with one
click.

## Features

- **Bind a to-do to a page.** Click ⌖, then click a window. Hold ⌥ to pick
  something inside it: a browser tab, a sidebar entry, an editor tab, a
  button. Slack conversations, Obsidian notes, VS Code files and open
  documents are recognised as such.
- **Jump back with one click.** Hoopa records every way it has to find the
  page, most reliable first, and on the way back stops at the first one that
  is confirmed to have arrived. A closed browser tab is reopened.
- **Nothing hijacked.** Scrolling, clicks and key presses go to the target
  app's process only, never through the system input queue, so the cursor
  stays put and you keep typing. No OCR, no in-app search, no reverse
  engineered URLs.
- **Timers and dates.** A 25-minute timer or a date and time on any to-do,
  with a live countdown. A system notification fires at the moment; clicking
  it jumps to the bound page.
- **A collapsed mini list.** One click on the ear at the panel's left edge
  shrinks it to a glass slab with one row per to-do: a ball (the app's icon
  with a time ring around it), the title and the countdown.
- **Sort by time or by hand.** Timed to-dos soonest first, grouped into
  Overdue, Today, Tomorrow, Later and Unscheduled, or drag the cards into
  your own order.
- **A floating panel that never steals focus.** It stays above your windows,
  takes clicks without activating, and hides behind ⌃⌥T or the menu bar
  icon.
- **English by default, Simplified Chinese built in.**
- **Local data only.** One JSON file in Application Support. No account, no
  sync, no network.

## Quick start

Requires macOS 14 or later (with the Liquid Glass look on macOS 26) and
Xcode, since the SwiftUI macro plugin only ships with Xcode.

```bash
git clone https://github.com/Phantom1003/Hoopa.git
cd Hoopa
./build.sh            # builds and signs build/Hoopa.app
open build/Hoopa.app
```

`build.sh` signs the app with the Apple Development certificate in your login
keychain and refuses to fall back to an ad hoc signature, because macOS ties
the Accessibility grant to the signature and an ad hoc one changes with every
build. Run it from Terminal so the keychain can ask for the key. See
[Build & run](docs/manual.md#build--run) for the details and the overrides.

Prebuilt bundles for every commit are attached to the
[CI runs](https://github.com/Phantom1003/Hoopa/actions/workflows/build.yml),
and tagged versions are published under
[Releases](https://github.com/Phantom1003/Hoopa/releases). Those are ad hoc
signed, so Accessibility has to be granted again after every update.

Then:

1. Grant **Accessibility** access when the panel asks for it (System
   Settings → Privacy & Security → Accessibility). Detecting windows and
   jumping back both depend on it.
2. Press **+**, click **⌖**, click the window you are working in (or hold ⌥
   and click a tab inside it), type the to-do and press Return. The first
   time you bind a browser tab, macOS asks whether Hoopa may control the
   browser; allow it.
3. Later, click the chip on the to-do, and you are back on that page.

## Documentation

The full manual, covering the panel and the collapsed list, picking and
jumping, how the anchors work, timers and notifications, code signing, the
app icon and diagnostics, is in [docs/manual.md](docs/manual.md).
