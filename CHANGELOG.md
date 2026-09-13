# Version 1.0.0 — September 12, 2026

- First official release of the native clipboard history app.
- Sparkle 2.9.6 integration with a background check at every launch and manual checks in Settings.
- User-approved download/install of Ed25519-signed update archives; GitHub Releases-hosted appcast.
- Git Flow release branches, reproducible packaging, archive checksums and automated build checks.
- Includes all preview improvements documented below.

# Changelog

## 0.1.0 — Local preview

- Native macOS menu bar app with configurable ⌘⇧V shortcut.
- Text, link and image history with 24-hour retention and local persistence.
- Duplicate merging, including normalization of PNG/TIFF image content.
- Pins for three days, one week, one calendar month or forever.
- Search, previews, keyboard navigation, quick selection and direct Paste.
- Plain-text Paste while preserving available rich formats for regular Paste.
- System/light/dark appearance, Open at login and clear recent history.
- Standalone automated checks for retention, pins, persistence, image processing and isolated pasteboard integration.

This version is for local testing. GitHub publication is planned after reaching 1.0.0. The license is still undecided.

### User testing fixes — September 9
- Reset Recent selection and scroll position on every panel opening.
- Normalize arrow-key modifiers; route Command-number shortcuts through panel key equivalents and physical number keys for Persian layouts.
- Keep appearance controls in Settings and replace the header checkmark with Done.
- Display distinct cards, multiline text, right-side color/image previews, and individual delete actions.
- Capture file URLs with image previews and static video thumbnails while retaining the original paste representation.

### Settings refinement — September 9
- Align login, Auto paste, and Paste as plain text switches to the trailing edge.
- Remove the extra Settings Done, footer status text, and Storage row.
- Persist selectable history retention: 1 hour, 24 hours, 3/7/30 days, or Forever; enforce it across all repository operations and UI filtering.
- Persist paste preferences, with text-only formatting conversion and copy-only primary actions when Auto paste is off.
- Add native Liquid Glass theme selection on macOS 26+, with an earlier-system fallback.

### Footer cleanup — September 9
- Remove the main Copy/Paste toolbar and its overflow menu.
- Place bundle-derived version and Check for Updates beneath History, with Quit anchored lower in Settings.
- Explain update unavailability in the local preview instead of reporting an unverified up-to-date result.
- Correct version/update placement: the row now follows History inside the settings scroll content; only Quit remains in the fixed footer.

### Collection picker and card controls — September 9
- Use a full-content-width Liquid Glass Recent/Pinned selector on macOS 26+, with equal-width choices, live counts, selection accessibility, and reduced-motion support.
- Remove inline pin/delete buttons from cards. Move pin durations and Unpin into the card context menu alongside Delete.

### Keyboard collection switching — September 12
- Tab and Shift-Tab switch Recent/Pinned in the history view, select the first matching item, and focus search without clearing the query.
- Preserve standard Tab behavior in Settings and Preview and modifier shortcuts such as Command-Tab.
