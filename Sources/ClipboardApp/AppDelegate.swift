import AppKit
import SwiftUI
import ApplicationServices
import ClipboardCore
import ClipboardPlatform

final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: ClipboardPanel!
    private var model: AppModel!
    private var reader: ClipboardReader!
    private let hotKey = HotKeyManager()
    private var keyboardMonitor: Any?
    private var outsideMonitor: Any?
    private var localMouseMonitor: Any?
    private var maintenance: Timer?
    private var previousApp: NSRunningApplication?
    private var testing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        testing = CommandLine.arguments.contains("--demo")
        if !testing, let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps]); NSApp.terminate(nil); return
        }
        do {
            let directory: URL
            if testing { directory = FileManager.default.temporaryDirectory.appendingPathComponent("Clipboard-Demo", isDirectory: true) }
            else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true).appendingPathComponent("Clipboard", isDirectory: true)
            }
            let repository = try HistoryRepository(directory: directory)
            model = AppModel(repository: repository, defaults: testing ? UserDefaults(suiteName: "local.clipboard.demo")! : .standard)
        } catch {
            let alert = NSAlert(); alert.messageText = "Clipboard could not start"; alert.informativeText = error.localizedDescription
            alert.runModal(); NSApp.terminate(nil); return
        }
        panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 424, height: 610),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Clipboard"
        panel.onKeyEquivalent = { [weak self] event in self?.handle(event) == nil }
        panel.level = .floating; panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = true; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardView(model: model))
        host.wantsLayer = true; host.layer?.cornerRadius = 14; host.layer?.masksToBounds = true
        panel.contentView = host
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard")
        statusItem.button?.toolTip = "Clipboard · \(model.shortcut.label)"
        statusItem.button?.target = self; statusItem.button?.action = #selector(togglePanel)
        model.onAppearance = { [weak self] in self?.applyAppearance() }
        model.onClose = { [weak self] in self?.closePanel() }
        model.onShortcut = { [weak self] shortcut in
            guard let self else { return }; try self.hotKey.register(shortcut)
            self.statusItem.button?.toolTip = "Clipboard · \(shortcut.label)"
        }
        model.onCopy = { [weak self] clip, plain, paste in self?.use(clip, plain: plain, paste: paste) }
        hotKey.onPress = { [weak self] in Task { @MainActor in
            guard let self else { return }
            if self.model.recordingShortcut { self.model.recordingShortcut = false; self.model.toast("Shortcut unchanged") }
            else { self.togglePanel() }
        } }
        do { try hotKey.register(model.shortcut) } catch { model.error = error.localizedDescription }
        applyAppearance()
        reader = ClipboardReader()
        reader.onCapture = { [weak self] capture in await self?.model.capture(capture) }
        reader.onError = { [weak self] message in self?.model.error = message }
        reader.onAccess = { [weak self] denied in if self?.model.accessDenied != denied { self?.model.accessDenied = denied } }
        if !testing { reader.start() }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }; return self.handle(event)
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.panel.isVisible, event.window !== self.panel, event.window !== self.statusItem.button?.window,
               self.panel.attachedSheet == nil { self.closePanel() }
            return event
        }
        maintenance = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.model.refresh() }
        }
        maintenance?.tolerance = 2
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        Task {
            await model.refresh(recover: true)
            if testing { await seedDemo(); showPanel() }
            else if !model.defaults.bool(forKey: "hasLaunched") {
                model.defaults.set(true, forKey: "hasLaunched"); showPanel()
            }
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    @objc private func woke() { Task { await model.refresh(recover: true); reader.poll() } }
    private func applyAppearance() {
        let name: NSAppearance.Name? = model.appearance == "Dark" ? .darkAqua : model.appearance == "Light" ? .aqua : nil
        NSApp.appearance = name.flatMap { NSAppearance(named: $0) }
    }
    @objc func togglePanel() { if panel.isVisible { closePanel() } else { showPanel() } }
    private func showPanel() {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        model.now = Date(); model.settings = false; model.preview = false
        model.recordingShortcut = false; model.query = ""; model.pinnedTab = false
        model.selectedID = model.filtered.first?.id; model.openToken += 1
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let width = min(CGFloat(424), visible.width - 16), height = min(CGFloat(610), visible.height - 16)
        var x = visible.maxX - width - 12
        var y = visible.maxY - height - 7
        if let button = statusItem.button, let window = button.window, window.screen === screen {
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            x = rect.midX - width / 2; y = min(y, rect.minY - height - 7)
        }
        x = max(visible.minX + 8, min(x, visible.maxX - width - 8))
        y = max(visible.minY + 8, y)
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        model.searchFocusToken += 1
        Task { await model.refresh() }
    }
    private func closePanel() {
        guard panel?.attachedSheet == nil else { return }
        panel?.orderOut(nil); model?.recordingShortcut = false
    }
    func windowDidResignKey(_ notification: Notification) {
        // Menus briefly take key focus; their tracking owns outside clicks.
        guard panel.attachedSheet == nil, !model.recordingShortcut else { return }
    }
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, (event.window === panel || panel.isKeyWindow), panel.attachedSheet == nil else { return event }
        if model.recordingShortcut {
            if event.keyCode == 53 { model.recordingShortcut = false }
            else if let shortcut = Shortcut.from(event) { model.saveShortcut(shortcut) }
            else { model.toast("Use Command or Control with a non-reserved key.") }
            return nil
        }
        let flags = ClipboardKeyboard.modifiers(for: event)
        let editor = panel.firstResponder as? NSTextView
        let editingSearch = editor?.isFieldEditor == true
        let selectingText = editor != nil
        if event.keyCode == 53 {
            if model.preview { model.preview = false }
            else if model.settings { model.settings = false }
            else { closePanel() }; return nil
        }
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
            model.settings = false; model.preview = false; model.searchFocusToken += 1; return nil
        }
        guard !model.settings else { return event }
        if !model.preview, event.keyCode == 48, flags.isEmpty || flags == .shift {
            model.pinnedTab.toggle()
            model.selectedID = model.filtered.first?.id
            model.searchFocusToken += 1
            return nil
        }
        if flags == .command, let number = ClipboardKeyboard.itemNumber(for: event) {
            let rows = model.filtered
            if number <= rows.count { model.selectedID = rows[number - 1].id; model.useSelected() }
            return nil
        }
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "c", !selectingText {
            model.useSelected(paste: false); return nil
        }
        if event.keyCode == 36 && !flags.contains(.command) && !flags.contains(.option) {
            model.useSelected(plain: flags.contains(.shift) ? true : nil); return nil
        }
        if !model.preview && (event.keyCode == 125 || event.keyCode == 126) && flags.isEmpty {
            model.move(event.keyCode == 125 ? 1 : -1); return nil
        }
        if event.keyCode == 49, flags.isEmpty, !editingSearch, !selectingText, model.selected != nil {
            model.preview.toggle(); return nil
        }
        return event
    }
    private func use(_ clip: Clip, plain: Bool, paste: Bool) {
        guard !model.working, !plain || clip.supportsPlainText else { return }
        if paste && !AXIsProcessTrusted() {
            model.error = "Direct paste needs Accessibility access. Use Copy, or enable Clipboard in System Settings → Privacy & Security → Accessibility."
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return
        }
        if paste && (previousApp == nil || previousApp?.isTerminated == true) {
            model.error = "Open the destination app, then open Clipboard with your shortcut. You can also use Copy."; return
        }
        let destination = previousApp
        model.working = true
        Task {
            defer { model.working = false }
            do {
                let payload = try await model.repository.payload(id: clip.id)
                let item = NSPasteboardItem()
                if plain { item.setString(clip.text, forType: .string) }
                else { for (type, data) in payload { item.setData(data, forType: NSPasteboard.PasteboardType(type)) } }
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.writeObjects([item]) else {
                    throw NSError(domain: "Clipboard", code: 2, userInfo: [NSLocalizedDescriptionKey: "The item could not be copied. Try again."])
                }
                reader.markOwnWrite()
                try await model.repository.touch(id: clip.id)
                await model.refresh()
                if paste, let destination {
                    closePanel()
                    guard destination.activate(options: [.activateIgnoringOtherApps]) else {
                        model.error = "The destination app could not be activated. The item is copied; paste it manually."; showPanel(); return
                    }
                    // Wait for focus to transfer, then re-check instead of typing into an unrelated app.
                    for _ in 0..<12 {
                        if NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier { break }
                        try await Task.sleep(nanoseconds: 30_000_000)
                    }
                    try await Task.sleep(nanoseconds: 80_000_000)
                    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else {
                        model.error = "Focus changed. The item is copied; paste it manually."; showPanel(); return
                    }
                    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
                          let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return }
                    down.flags = .maskCommand; up.flags = .maskCommand
                    down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
                } else { model.toast("Copied to clipboard") }
            } catch { model.error = error.localizedDescription }
        }
    }
    private func seedDemo() async {
        guard model.items.isEmpty else { return }
        let values = [("Let’s keep the little things within reach.", "Notes"), ("https://developer.apple.com/design/", "Safari"),
                      ("ایده‌های کوچک، برای کارهای هر روز", "Notes"), ("const greeting = \"Hello, world\";", "Visual Studio Code"),
                      ("Launch checklist\n• Test the shortcut\n• Check light and dark appearance", "Notes")]
        for (index, value) in values.enumerated() {
            if let capture = try? CaptureProcessor.process([NSPasteboard.PasteboardType.string.rawValue: Data(value.0.utf8)], source: value.1) {
                do {
                    let clip = try await model.repository.capture(capture, now: Date().addingTimeInterval(Double(-index * 180)))
                    if index == 4 { try await model.repository.pin(id: clip.id, duration: .week) }
                } catch { model.error = error.localizedDescription }
            }
        }
        await model.refresh()
    }
}
