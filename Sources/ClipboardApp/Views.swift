import SwiftUI
import AppKit
import ServiceManagement
import ClipboardCore
import ClipboardPlatform

struct ClipboardView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @State private var confirmClear = false
    @State private var showUpdateStatus = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "clipboard").foregroundStyle(.blue).frame(width: 30, height: 30)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                Text(model.settings ? "Settings" : "Clipboard").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { model.settings.toggle(); model.recordingShortcut = false; model.updateLoginStatus() } label: {
                    if model.settings { Text("Done").fontWeight(.semibold) }
                    else { Image(systemName: "slider.horizontal.3") }
                }.help(model.settings ? "Done" : "Settings").accessibilityLabel(model.settings ? "Done" : "Settings")
            }.buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 15)

            if let error = model.error {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss error")
                }.padding(12).background(Color.orange.opacity(0.1)).accessibilityElement(children: .combine)
            }
            if model.accessDenied {
                Text("Clipboard access is disabled in macOS. Allow Clipboard in System Settings → Privacy & Security → Paste from Other Apps.")
                    .font(.caption).padding(12).frame(maxWidth: .infinity).background(Color.orange.opacity(0.1))
            }
            if model.settings { settingsView }
            else if model.preview, let clip = model.selected {
                ClipPreview(clip: clip, repository: model.repository) { model.preview = false }
            } else { historyView }


        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: "en_US"))
        .onChange(of: model.searchFocusToken) { _ in searchFocused = true }
        .onChange(of: model.settings) { value in if !value { searchFocused = true } }
        .onChange(of: model.preview) { value in if value { searchFocused = false } }
        .alert("Updates aren’t available yet", isPresented: $showUpdateStatus) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Clipboard \(appVersion) is a local preview. Online update checking will be available when public releases begin.")
        }
        .confirmationDialog("Clear recent history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear recent history", role: .destructive) { model.clearRecent() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Pinned items will be kept. This cannot be undone.") }
    }

    private var historyView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search your clipboard…", text: $model.query).textFieldStyle(.plain)
                    .focused($searchFocused).accessibilityLabel("Search clipboard")
                if !model.query.isEmpty {
                    Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                } else { Text("⌘ F").font(.caption).foregroundStyle(.tertiary) }
            }.padding(10).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
                .padding(.horizontal, 16)
            CollectionPicker(selection: $model.pinnedTab, recentCount: model.recentCount, pinnedCount: model.pinnedCount)
                .frame(maxWidth: .infinity).padding(.horizontal, 8)
                .help("Switch between Recent and Pinned with Tab")
            HStack {
                Text(model.query.isEmpty ? (model.pinnedTab ? "Kept close" : "Recent items") : "Search results")
                Spacer(); Text(model.pinnedTab ? "Your pinned items" : "Newest first")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 19).padding(.top, 4)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if model.filtered.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: model.pinnedTab ? "pin" : "clipboard").font(.system(size: 28)).foregroundStyle(.tertiary)
                                Text(model.query.isEmpty ? (model.pinnedTab ? "Keep something useful here" : "Your next copy will appear here")
                                     : "No matching items").font(.system(size: 13, weight: .medium))
                                Text(model.query.isEmpty ? (model.pinnedTab ? "Pin an item from Recent to keep it longer." : "Copy text, a link or an image to get started.")
                                     : "Try another word or switch collections.").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.vertical, 70)
                        }
                        ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, clip in
                            row(clip, index: index).id(clip.id)
                        }
                    }.padding(.horizontal, 8).padding(.bottom, 10)
                }
                .id(model.openToken)
                .onChange(of: model.selectedID) { id in if let id { proxy.scrollTo(id, anchor: nil) } }
            }
        }.frame(maxHeight: .infinity)
    }

    private func row(_ clip: Clip, index: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                model.selectedID = clip.id; searchFocused = false
            } label: {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(clip.kind == .text ? clip.text : clip.title).font(.system(size: 13, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 5) {
                            Text(clip.source).lineLimit(1)
                            Text("·")
                            Text(clip.isPinned(at: model.now) ? model.pinLabel(clip) : model.age(clip.copiedAt))
                                .foregroundStyle(clip.isPinned(at: model.now) ? Color.accentColor : Color.secondary)
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    thumbnail(clip)
                }.padding(.leading, 12).padding(.vertical, 12).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(clip.title), \(clip.source)")
            if index < 9 { Text("⌘\(index + 1)").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }.padding(.trailing, 12)
        .background(model.selectedID == clip.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(model.selectedID == clip.id ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1)))
        .contextMenu {
            Button("Copy") { model.onCopy?(clip, false, false) }
            Button("Paste") { model.onCopy?(clip, model.pasteAsPlainText && clip.supportsPlainText, true) }
            Button("Paste without formatting") { model.onCopy?(clip, true, true) }.disabled(!clip.supportsPlainText)
            Button("Preview") { model.selectedID = clip.id; model.preview = true }
            Divider()
            Menu("Pin for") {
                ForEach(PinDuration.allCases, id: \.self) { duration in
                    Button(duration.rawValue) { model.pin(clip, duration: duration) }
                }
            }
            if clip.isPinned(at: model.now) {
                Button("Unpin item") { model.pin(clip, duration: nil) }
            }
            Divider()
            Button("Delete item", role: .destructive) { model.delete(clip) }
        }
    }
    @ViewBuilder private func thumbnail(_ clip: Clip) -> some View {
        if clip.kind == .text, let color = ClipColor.parse(clip.text) {
            RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: color))
                .frame(width: 58, height: 58)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))
                .accessibilityLabel("Color preview: \(clip.text)")
        } else if let data = clip.thumbnail, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: 58, height: 58)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: clip.kind == .link ? "link" : clip.kind == .image ? "photo" : clip.kind == .video ? "film" : clip.kind == .file ? "doc" : "text.alignleft")
                .foregroundStyle(.secondary).frame(width: 58, height: 58)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }
    private var settingsView: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsGroup("General") {
                    settingsToggle("Open at login", isOn: Binding(get: { model.loginEnabled || model.loginNeedsApproval }, set: { model.setLogin($0) }))
                    Divider()
                    settingsToggle("Auto paste", isOn: $model.autoPaste)
                    Divider()
                    settingsToggle("Paste as plain text", isOn: $model.pasteAsPlainText)
                    if model.loginNeedsApproval {
                        Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }.font(.caption)
                    }
                    Divider()
                    HStack {
                        Text("Keyboard shortcut"); Spacer()
                        Button(model.recordingShortcut ? "Press shortcut…" : model.shortcut.label) { model.recordingShortcut.toggle() }
                            .accessibilityLabel("Record keyboard shortcut")
                            .accessibilityValue(model.shortcut.label)
                    }
                    if model.recordingShortcut { Text("Include Command or Control. Escape cancels.").font(.caption).foregroundStyle(.secondary) }
                }
                settingsGroup("Appearance") {
                    ThemePicker(selection: $model.appearance)
                }
                settingsGroup("History") {
                    HStack {
                        Text("Keep history for")
                        Spacer()
                        Picker("Keep history for", selection: Binding(get: { model.retention }, set: { model.setRetention($0) })) {
                            ForEach(HistoryRetention.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    Text("Pinned items keep their own expiry.").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Button("Clear recent history…") { confirmClear = true }.buttonStyle(.borderless)
                }
                HStack {
                    Text("Version \(appVersion)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for Updates…") { showUpdateStatus = true }
                        .controlSize(.small)
                }
            }.padding(.horizontal, 18).padding(.bottom, 12)
        }.frame(maxHeight: .infinity)
            HStack {
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 16)
        }.frame(maxHeight: .infinity)
    }
    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                .accessibilityLabel(title)
        }
    }
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        }
    }
}

private struct ClipPreview: View {
    let clip: Clip
    let repository: HistoryRepository
    let close: () -> Void
    @State private var image: NSImage?
    @State private var loadError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Button(action: close) { Label("Back", systemImage: "chevron.left") }.buttonStyle(.borderless)
                Spacer(); Text(clip.kind.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
            ScrollView {
                if clip.kind == .image || clip.kind == .video {
                    if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity) }
                    else if let loadError { Text(loadError).foregroundStyle(.secondary) }
                    else { ProgressView().padding() }
                } else {
                    Text(clip.text).font(.system(size: 14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text(clip.source + " · " + clip.copiedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxHeight: .infinity)
            .task(id: clip.id) {
                image = nil; loadError = nil
                guard clip.kind == .image || clip.kind == .video else { return }
                if clip.kind == .video {
                    image = clip.thumbnail.flatMap { NSImage(data: $0) }
                    if image == nil { loadError = "Thumbnail unavailable for this video." }
                    return
                }
                do {
                    let payload = try await repository.payload(id: clip.id)
                    let data = payload[NSPasteboard.PasteboardType.png.rawValue] ?? payload[NSPasteboard.PasteboardType.tiff.rawValue]
                    image = data.flatMap { NSImage(data: $0) }
                    if image == nil, let fileData = payload[NSPasteboard.PasteboardType.fileURL.rawValue],
                       let value = String(data: fileData, encoding: .utf8), let url = URL(string: value), url.isFileURL {
                        image = NSImage(contentsOf: url)
                    }
                    if image == nil { image = clip.thumbnail.flatMap { NSImage(data: $0) } }
                    if image == nil { loadError = "This image could not be opened." }
                } catch { loadError = error.localizedDescription }
            }
    }
}

private struct ThemePicker: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var themeNamespace
    private let themes = ["System", "Light", "Dark"]

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(themes, id: \.self) { theme in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = theme }
                        } label: {
                            Label(theme, systemImage: theme == "System" ? "desktopcomputer" : theme == "Light" ? "sun.max" : "moon")
                                .font(.system(size: 12, weight: selection == theme ? .semibold : .regular))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(selection == theme ? Color.accentColor.opacity(0.25) : nil).interactive(), in: .capsule)
                        .glassEffectID(theme, in: themeNamespace)
                        .accessibilityLabel(theme)
                        .accessibilityAddTraits(selection == theme ? [.isSelected] : [])
                    }
                }
            }.accessibilityElement(children: .contain).accessibilityLabel("Theme")
        } else {
            Picker("Theme", selection: $selection) {
                ForEach(themes, id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
        }
    }
}

private struct CollectionPicker: View {
    @Binding var selection: Bool
    let recentCount: Int
    let pinnedCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach([false, true], id: \.self) { pinned in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selection = pinned }
                        } label: {
                            HStack(spacing: 8) {
                                Text(pinned ? "Pinned" : "Recent")
                                Text(String(pinned ? pinnedCount : recentCount))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.system(size: 13, weight: selection == pinned ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(selection == pinned ? Color.accentColor.opacity(0.25) : nil).interactive(), in: .capsule)
                        .glassEffectID(pinned, in: glassNamespace)
                        .accessibilityLabel(pinned ? "Pinned" : "Recent")
                        .accessibilityValue(String(pinned ? pinnedCount : recentCount))
                        .accessibilityAddTraits(selection == pinned ? [.isSelected] : [])
                    }
                }.frame(maxWidth: .infinity)
            }.accessibilityElement(children: .contain).accessibilityLabel("Collection")
        } else {
            Picker("Collection", selection: $selection) {
                Text("Recent  \(recentCount)").tag(false)
                Text("Pinned  \(pinnedCount)").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
        }
    }
}
