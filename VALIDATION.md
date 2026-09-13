# Release 1.0.0 validation — September 13, 2026

- Production app built with Sparkle 2.9.6. Bundle version is 1.0.0 (build 10000); nested code signature verification passed.
- All 28 history/platform checks passed.
- Generated release ZIP and appcast with Sparkle's official tools, verified the Ed25519 archive signature, version, download URL, file size, and produced SHA-256 checksums.
- Built the official Sparkle command-line driver from pinned 2.9.6 sources and tested disposable bundles with a separate identifier against a loopback feed: newer update discovery, full download and installation, installed-version/signature checks, and correct no-update result all passed.
- Modified an archive byte and retried: Sparkle rejected it with error 4005; the old disposable application remained intact.
- Private update key is stored in the login Keychain, account `local.clipboard.app.sparkle`. Only the public key is committed.
- The real user's app/history were not replaced by integration tests. The standard graphical updater dialog was not manually operated in this session; install mechanics were verified by the official driver.
- This first release is ad-hoc signed, not Developer ID signed or notarized. Apple Silicon was tested; Intel and older macOS runtime compatibility are not claimed.

## Historical preview validation

# Validation — 0.1.0

Environment: Apple Silicon, macOS 26.5.2, Apple Swift 6.3.3 command-line tools.

## Completed

- Debug and optimized release builds compiled successfully.
- The build script produced `dist/Clipboard.app`, including a generated native app icon and ad-hoc code signature. Signature verification passed.
- **20 automated checks passed** using the standalone verification executable:
  - Expiry exactly at 24 hours, including managed payload deletion.
  - Duplicate refresh, replacement of old payloads and source updates.
  - Whitespace, Persian, emoji and line-break preservation.
  - Three-day, week and calendar-month pin boundaries.
  - Forever pins surviving years and clear-recent operations.
  - Recopying pinned content without extending the pin; returning to Recent after expiry.
  - Unpinning recent versus old content.
  - Renewing pins from the current time.
  - End-of-month calendar behavior.
  - Reopening persistent history with payloads and pins intact.
  - Refusing to load or repin expired items.
  - Recovery of orphaned payloads within the managed directory.
  - Rich-format payload round trip.
  - Reuse without duplication or loss of pin state.
  - Persian/rich-text capture, exact link detection and RTF plain-text fallback.
  - Image fingerprint equivalence between PNG and TIFF, and thumbnail creation.
  - Actual macOS pasteboard service integration using isolated named pasteboards, including own-write suppression and multiple-item capture.
- Native UI was launched with a separate sample database. Observed functioning: history list, three-day pin menu and count update, Persian search, Space preview, return from preview, light/dark appearance, settings, shortcut recording and Quit.
- Sample-mode data is separate from normal history; the real clipboard reader is not started in sample mode.
- The final normal-mode bundle was launched and its empty Recent/Pinned lists were observed, confirming sample records do not appear in the user's normal history. It was left running in the menu bar, ready for new copies.

The isolated pasteboard integration checks initially failed in the restricted execution sandbox because macOS pasteboard service access was blocked. All 20 checks passed when run with normal local service access. They did not read or overwrite the user's general clipboard.

## Needs real-use confirmation before 1.0

- End-to-end direct Paste into different applications after the user grants Accessibility access, including formatted text and images. No system permission was granted automatically during verification.
- Capture under the user's general-pasteboard permission setting; isolated pasteboard tests do not prove that macOS has granted the app permission to read the general clipboard.
- Open at login after the user enables it, approves any system prompt and performs an actual login.
- Global shortcut behavior while different applications and full-screen spaces are active, plus conflicts with the user's other utilities. Shortcut recording was observed; changing the displayed shortcut is not by itself proof of every global-hotkey scenario.
- Multi-monitor positioning, actual sleep/wake, long-running use and high-volume/large-image workloads. Clock-driven retention tests do not replace those environment checks.
- Installation and runtime compatibility on older macOS versions or Intel hardware.
- Developer ID signing, notarization and distribution testing for the future public release.

This is a working **0.1.0 preview**, not the stable 1.0 milestone. No GitHub repository or release has been published, and no license has been selected.

## September 9 — user testing fixes

- Rebuilt and verified the ad-hoc signed `dist/Clipboard.app`; restarted the normal app with its existing history.
- 25/25 automated checks passed with local macOS service access. Added coverage for color parsing, file-image thumbnails and exact file URL preservation, video thumbnail generation from a generated H.264 MOV, Persian number keys, arrow modifier normalization, and individual deletion including pinned payload cleanup.
- Observed in the updated native UI: arrow navigation while the search field has focus, scrolling to the selected card, reopening via shortcut at scroll position zero, distinct cards with delete controls, no main-page appearance toggle, and text Done in Settings.
- Command-number routing has automated input-mapping coverage and a panel key-equivalent handler. Direct paste into another app still requires real-use verification; no private history content was pasted during this check.
- Media previews apply to new captures. Older filename-only records lack the original file URL and must be copied again. Video decoding uses macOS AVFoundation; unsupported containers/codecs (including some MKV files), missing files, and unreadable files can lack thumbnails. Copied files preserve their original file URL representation; thumbnails are retained in history, but the external original file is not archived.

## September 9 — settings refinement

- Debug and release builds passed; rebuilt and signature-verified `dist/Clipboard.app`, then restarted it.
- 28/28 checks passed. New retention checks cover all six choices at their expiry boundary, persistence across repository reopening, Forever, shortening retention while preserving pins, payload access and touch beyond 24 hours, recapture identity, and unpinning with indefinite retention.
- Native UI verified in light and dark appearance: all three switches at the trailing edge, a single header Done, no Storage row or footer status text, native glass theme buttons, and all six retention menu choices.
- Toggled Auto paste off and verified that the main action changes to Copy; toggled plain text and themes. Restored Auto paste on, plain text off, and Dark after the checks. Kept the user's retention at the default 24 hours and did not toggle login registration.
- Paste preferences route through the primary button, Return, and Command-number paths. Explicit paste commands can override Auto paste. A real destination paste round trip was not performed during this UI check.

## September 9 — footer cleanup

- Debug and signed release builds passed.
- Native UI confirmed no bottom Copy/Paste controls, version and update button below History, and lower Quit placement.
- Clicked Check for Updates and confirmed the local-preview/unavailable message, then dismissed it. There is no published update source, so this is an explicit unavailable state, not an online update checker.
- This change is confined to view layout and the informational alert. Existing keyboard and context-menu actions remain in place; no new automated tests were added for the reversible UI change.

## Version row placement correction
- Moved the version/update row into the settings ScrollView immediately after History, leaving only Quit in the fixed footer.
- Debug build passed; this is a layout-only correction.

## Collection picker and card context menu
- Debug build passed for the native glass collection selector and context-menu changes.
- The selector spans the same content width as the cards with an 8-point window inset. Older supported macOS versions retain a segmented fallback.
- Pin durations, Unpin, and Delete use the existing model actions from the card context menu; inline action buttons are removed.
- No new automated tests were added for this view-only change. Live UI verification was not performed in this turn.

## September 12 — Tab collection switching
- Debug build passed. The history-only Tab handler runs after shortcut recording and Settings guards, excludes Preview, and accepts only plain Tab or Shift-Tab.
- Existing arrow movement and typing-to-search handlers remain unchanged. Switching explicitly focuses search and chooses the first filtered item.
- Live UI verification was not performed for this change.
