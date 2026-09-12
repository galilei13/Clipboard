# Clipboard for macOS

A native menu bar clipboard history app. **0.1.0 is a local preview release**, intended for daily testing and bug fixes before version 1.0.

## Run

1. Open `dist/Clipboard.app`. For regular use, drag the app to your Applications folder and run that copy.
2. Look for the clipboard icon in the menu bar. Click it or press **⌘⇧V**.
3. Copy some text, a link or an image in another app. Clipboard records new copies while it is running.
4. Choose an item and use **Copy** or **Paste**. The dropdown next to Paste offers **Paste without formatting** for text and links.

This preview is built for Apple Silicon. Its deployment target is macOS 13+, but runtime validation so far is on macOS 26.5.2. Compatibility with older macOS releases and Intel Macs has not been tested.

## System permissions

- On macOS versions that request clipboard access, allow Clipboard in **System Settings → Privacy & Security → Paste from Other Apps**. The app displays a message if access is denied. Reading the clipboard is subject to the system's permission settings.
- **Direct Paste** needs **Accessibility** access. The first direct Paste attempt without permission explains this and requests the system prompt. Enable Clipboard in **System Settings → Privacy & Security → Accessibility**, then retry. Copy works independently of direct Paste; you can use ⌘V in the destination app yourself.
- **Open at login** starts off. Turn it on in Clipboard's settings. If macOS requires approval, the settings show a button to open Login Items.

## History rules

- Recent contains unpinned items within the selected retention period, newest first. Settings offers 1 hour, 24 hours (default), 3 days, 7 days, 30 days, or Forever.
- Copying the same content refreshes its timestamp and source without creating another row. Text whitespace and line breaks are preserved. Equivalent PNG/TIFF representations are compared using normalized image pixels.
- Pin an item for **3 days**, **1 week**, **1 calendar month**, or **Forever**. A new pin duration starts at the moment you choose it.
- Copying a pinned item refreshes the copy time but does not extend its pin.
- When a pin expires or is removed, the item returns to Recent if its latest copy is within the selected retention period (or retention is Forever). Otherwise it is deleted from the app's history and managed storage.
- Search applies to text and links in the selected collection. Images do not have OCR search.
- The app has no pause switch, app exclusions, pin names, cloud sync, or network service.

## Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘⇧V | Toggle Clipboard; configurable in Settings |
| ↑ / ↓ | Select an item |
| Enter | Paste the selected item into the previously active app |
| ⇧Enter | Paste text or a link without formatting |
| ⌘C | Copy the selected item when not editing/selecting text |
| ⌘1–⌘9 | Paste one of the first nine current results |
| Space | Toggle preview when focus is on the list |
| ⌘F | Focus search |
| Escape | Close preview/settings, then the panel |

Click an item to focus the list. Text editing shortcuts retain their normal behavior in the search field. A shortcut registration conflict preserves the previous working shortcut.

## Local storage

The app stores metadata in SQLite and clipboard payloads in managed binary property-list files under:

`~/Library/Application Support/Clipboard/`

Appearance and paste preferences use the `local.clipboard.app` preferences domain. The history retention choice is stored alongside the history database. Cleanup changes only the app's history; it does not clear the system clipboard or delete original files. Expiration is checked on startup, wake, opening the panel, after a capture, and periodically while running. No content is uploaded or included in application logs.

## Build and check

Requires Apple's Swift command-line tools and the macOS SDK. No third-party packages are downloaded.

```sh
bash scripts/check.sh
bash scripts/build.sh
open dist/Clipboard.app
```

`scripts/check.sh` builds and runs a standalone Swift verification executable; a full Xcode installation and XCTest are not required. The pasteboard integration checks use uniquely named, isolated pasteboards and do not alter the user's general clipboard. They need normal access to macOS pasteboard services, so restrictive agent sandboxes may require approval.

The build script produces an ad-hoc signed local `.app` and its app icon. It does not install the app or publish anything. The signing identity is for local preview builds; Developer ID signing and notarization are part of the future public-release work.

An optional UI test mode uses a separate sample history and disables the real clipboard reader:

```sh
open -n dist/Clipboard.app --args --demo
```

Quit the running app before switching between sample and normal mode. Sample mode uses the `local.clipboard.demo` preferences domain and a separate temporary data directory. Normal mode contains no seeded examples.

## Preview limitations and validation

See [VALIDATION.md](VALIDATION.md) for exactly what was checked. In particular, a complete direct-paste round trip with Accessibility enabled and an actual logout/login cycle require user/system interaction; implementation is not the same as verified behavior in those cases.

Clipboard observes the current pasteboard every 250 ms. macOS does not expose the intermediate contents of copies that were overwritten before the app could read them. The app also cannot reconstruct copies made while it was not running. File-copy operations preserve file URLs and generate image/video thumbnails when supported by macOS. Original files are not archived. Arbitrary app-specific pasteboard formats are outside this version’s scope.

## Roadmap and license

Development stays in **0.x** while we test and fix bugs. After the stable **1.0.0** milestone, the project and downloadable app will be published on GitHub with a `v1.0.0` release. There is no GitHub publication yet.

**Update roadmap (agreed September 9, 2026):** Set up GitHub Releases plus Sparkle during final preparation for the official 1.0.0 release, before shipping that build. Include the appcast, update signing, and end-to-end update verification. Defer this work during the current local 0.x testing cycle.

**License: undecided.** We will select it together before public release. No default license has been applied.

The detailed agreed plan is in [PLAN.md](PLAN.md).

### Paste and appearance settings

The three leading switches control Open at login, Auto paste, and Paste as plain text. Auto paste defaults on; turning it off makes Return and Command-number shortcuts copy without inserting into another app. Explicit Paste commands remain available. Paste as plain text defaults off and strips formatting for text and links only; images and files retain their original representation. Shift-Return explicitly requests plain text while respecting Auto paste.

The theme control uses native Liquid Glass on macOS 26 and later, with a segmented control on earlier supported systems. The bottom status text and Settings footer have been removed; Settings has a single Done button in its header.

The main view has no bottom Copy/Paste toolbar. Use Return, Command-number shortcuts, or an item's context menu. Settings shows the bundle version and Check for Updates beneath History, with Quit at the bottom. This local preview has no published update source: Check for Updates explains that online checking is not available yet; it does not claim the app is up to date.

Recent/Pinned uses an equal-width Liquid Glass selector on macOS 26+. Right-click any card to pin it for a chosen duration or delete it; pinned cards also offer Unpin. These actions no longer occupy buttons beside the preview.

In the history view, Tab or Shift-Tab switches between Recent and Pinned, selects the first matching item, and keeps typing directed to search. The existing search query is preserved. Settings and Preview retain normal Tab focus navigation.
