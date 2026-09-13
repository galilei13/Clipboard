import AppKit
import SwiftUI
import ServiceManagement
import ClipboardCore
import ClipboardPlatform

@MainActor final class AppModel: ObservableObject {
    @Published var items: [Clip] = []
    @Published var query = "" { didSet { reconcileSelection() } }
    @Published var pinnedTab = false { didSet { reconcileSelection() } }
    @Published var selectedID: String?
    @Published var preview = false
    @Published var settings = false
    @Published var recordingShortcut = false
    @Published var shortcut = Shortcut.initial
    @Published var message: String?
    @Published var error: String?
    @Published var accessDenied = false
    @Published var now = Date()
    @Published var searchFocusToken = 0
    @Published var openToken = 0
    @Published var appearance: String { didSet { defaults.set(appearance, forKey: "appearance"); onAppearance?() } }
    @Published var loginEnabled = false
    @Published var loginNeedsApproval = false
    @Published var working = false
    @Published var canCheckForUpdates = false
    @Published private(set) var retention: HistoryRetention
    @Published var autoPaste: Bool { didSet { defaults.set(autoPaste, forKey: "autoPaste") } }
    @Published var pasteAsPlainText: Bool { didSet { defaults.set(pasteAsPlainText, forKey: "pasteAsPlainText") } }
    let repository: HistoryRepository
    let defaults: UserDefaults
    var onAppearance: (() -> Void)?
    var onClose: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onCopy: ((Clip, Bool, Bool) -> Void)?
    var onShortcut: ((Shortcut) throws -> Void)?
    private var toastTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(repository: HistoryRepository, defaults: UserDefaults = .standard) {
        self.repository = repository; self.defaults = defaults
        retention = repository.initialRetention
        autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        pasteAsPlainText = defaults.bool(forKey: "pasteAsPlainText")
        appearance = defaults.string(forKey: "appearance") ?? "System"
        if let data = defaults.data(forKey: "shortcut"), let value = try? JSONDecoder().decode(Shortcut.self, from: data) { shortcut = value }
        updateLoginStatus()
    }
    var filtered: [Clip] {
        items.filter { clip in
            !clip.isExpired(at: now, retention: retention) && clip.isPinned(at: now) == pinnedTab &&
            (query.isEmpty || (clip.kind != .image && clip.text.localizedStandardContains(query)))
        }
    }
    var selected: Clip? { filtered.first { $0.id == selectedID } }
    var recentCount: Int { items.filter { !$0.isPinned(at: now) && !$0.isExpired(at: now, retention: retention) }.count }
    var pinnedCount: Int { items.filter { $0.isPinned(at: now) }.count }
    func reconcileSelection() {
        if !filtered.contains(where: { $0.id == selectedID }) { selectedID = filtered.first?.id; preview = false }
    }
    func refresh(recover: Bool = false) async {
        refreshGeneration += 1
        let generation = refreshGeneration
        let date = Date()
        do {
            let result = try await (recover ? repository.recover(now: date) : repository.items(now: date))
            guard generation == refreshGeneration else { return }
            now = date; items = result
            reconcileSelection()
        } catch { self.error = error.localizedDescription }
    }
    func capture(_ value: Capture) async {
        do { try await repository.capture(value); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func pin(_ clip: Clip, duration: PinDuration?) {
        Task {
            do {
                try await repository.pin(id: clip.id, duration: duration)
                await refresh(); toast(duration.map { $0 == .forever ? "Pinned forever" : "Pinned for \($0.rawValue)" } ?? "Item unpinned")
            } catch { self.error = error.localizedDescription }
        }
    }
    func delete(_ clip: Clip) {
        Task {
            do { try await repository.remove(id: clip.id); await refresh(); toast("Item deleted") }
            catch { self.error = error.localizedDescription }
        }
    }
    func clearRecent() {
        Task { do { try await repository.clearRecent(); await refresh(); toast("Recent history cleared") }
            catch { self.error = error.localizedDescription } }
    }
    func move(_ direction: Int) {
        let rows = filtered; guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == selectedID } ?? 0
        selectedID = rows[(current + direction + rows.count) % rows.count].id
    }
    func setRetention(_ value: HistoryRetention) {
        Task {
            do { try await repository.setRetention(value); retention = value; await refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
    func useSelected(plain: Bool? = nil, paste: Bool? = nil) {
        guard !working, let selected else { return }
        onCopy?(selected, (plain ?? pasteAsPlainText) && selected.supportsPlainText, paste ?? autoPaste)
    }
    func saveShortcut(_ value: Shortcut) {
        do {
            try onShortcut?(value)
            shortcut = value; defaults.set(try JSONEncoder().encode(value), forKey: "shortcut")
            recordingShortcut = false; toast("Shortcut updated")
        } catch { self.error = error.localizedDescription }
    }
    func toast(_ text: String) {
        toastTask?.cancel(); message = text
        toastTask = Task { try? await Task.sleep(nanoseconds: 2_500_000_000); if !Task.isCancelled { message = nil } }
    }
    func updateLoginStatus() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { self.error = error.localizedDescription }
        updateLoginStatus()
    }
    func pinLabel(_ clip: Clip) -> String {
        if clip.pinnedForever { return "Pinned forever" }
        guard let date = clip.pinUntil else { return "" }
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 3600 { return "\(max(1, Int(ceil(seconds / 60)))) min left" }
        if seconds < 86400 { return "\(Int(ceil(seconds / 3600))) hours left" }
        return "\(Int(ceil(seconds / 86400))) days left"
    }
    func age(_ date: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) hours ago" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
