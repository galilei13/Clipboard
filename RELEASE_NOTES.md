# Clipboard 1.0.0

The first official release of Clipboard, a native macOS menu bar clipboard manager.

- Search clipboard history as you type; navigate cards with arrow keys.
- Switch Recent/Pinned with Tab or Shift-Tab. Use Return or Command-1…9 to reuse an item.
- Preview text, colors, images and supported video thumbnails.
- Right-click to copy, paste, pin for a selected duration, unpin, preview or delete.
- Configure retention from one hour to Forever, login launch, auto paste and plain-text paste.
- Choose System, Light or Dark appearance, with Liquid Glass controls on macOS 26+.
- Check for updates at application launch or manually in Settings. Sparkle validates signed update archives and handles downloading and installation after the user accepts.

## Installation

This download is for **Apple Silicon Macs running macOS 13 or later**. Extract Clipboard.app and place it in Applications before launching. Direct paste requires Accessibility permission. Login launch and clipboard access remain controlled by macOS.

The initial package is **ad-hoc signed, not Developer ID signed or notarized**. macOS may require explicit approval to open the downloaded app. Update archives carry Sparkle Ed25519 signatures. Original copied files must remain accessible; unsupported media formats may lack thumbnails. Intel and older macOS runtime compatibility have not been validated.

The default shortcut is Command-Shift-V. The app stores clipboard history locally. No history content is included in update requests.
