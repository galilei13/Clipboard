import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers
import CryptoKit
import ClipboardCore

public enum CaptureProcessor {
    public static func process(_ raw: [String: Data], source: String) throws -> Capture? {
        var representations = raw
        if let data = raw[NSPasteboard.PasteboardType.fileURL.rawValue],
           let value = String(data: data, encoding: .utf8), let url = URL(string: value), url.isFileURL {
            let type = UTType(filenameExtension: url.pathExtension)
            let kind: ClipKind = type?.conforms(to: .image) == true ? .image : type?.conforms(to: .movie) == true ? .video : .file
            var thumbnail: Data?
            if kind == .image, let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true]
                thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                    .flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
            } else if kind == .video {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 320, height: 240)
                if let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                    thumbnail = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])
                }
            }
            return Capture(kind: kind, text: url.lastPathComponent, source: source,
                fingerprint: Clip.fingerprint(kind: kind, bytes: data), representations: representations, thumbnail: thumbnail)
        }
        if let imageData = raw[NSPasteboard.PasteboardType.png.rawValue] ?? raw[NSPasteboard.PasteboardType.tiff.rawValue],
           let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let pixels = context.data else {
                throw NSError(domain: "Clipboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not enough memory to capture this image."])
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var hash = SHA256()
            hash.update(data: Data("image:\(image.width)x\(image.height):".utf8))
            hash.update(data: Data(bytesNoCopy: pixels, count: context.bytesPerRow * image.height, deallocator: .none))
            let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined()
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceThumbnailMaxPixelSize: 240,
                                          kCGImageSourceCreateThumbnailWithTransform: true]
            let thumb = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
            let thumbnail = thumb.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
            if representations[NSPasteboard.PasteboardType.png.rawValue] == nil {
                representations[NSPasteboard.PasteboardType.png.rawValue] = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            }
            return Capture(kind: .image, text: "Image · \(image.width) × \(image.height)", source: source,
                           fingerprint: fingerprint, representations: representations, thumbnail: thumbnail)
        }
        var text = raw[NSPasteboard.PasteboardType.string.rawValue].flatMap { String(data: $0, encoding: .utf8) }
            ?? raw[NSPasteboard.PasteboardType.URL.rawValue].flatMap { String(data: $0, encoding: .utf8) }
        if text == nil, let rtf = raw[NSPasteboard.PasteboardType.rtf.rawValue] {
            text = NSAttributedString(rtf: rtf, documentAttributes: nil)?.string
        }
        guard let text, !text.isEmpty else { return nil }
        representations[NSPasteboard.PasteboardType.string.rawValue] = Data(text.utf8)
        let url = URL(string: text)
        let isLink = !text.contains(where: \.isWhitespace) && ["http", "https", "mailto"].contains(url?.scheme?.lowercased() ?? "")
        let kind: ClipKind = isLink ? .link : .text
        return Capture(kind: kind, text: text, source: source,
                       fingerprint: Clip.fingerprint(kind: kind, bytes: Data(text.utf8)), representations: representations)
    }
}

@MainActor public final class ClipboardReader {
    private let pasteboard: NSPasteboard
    private var lastChange: Int
    private var timer: Timer?
    private var reading = false
    private var wasDenied = false
    public var onCapture: ((Capture) async -> Void)?
    public var onError: ((String) -> Void)?
    public var onAccess: ((Bool) -> Void)?

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        // Only record changes after launch, not an unknown-age pre-existing value.
        lastChange = pasteboard.changeCount
    }
    public func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        timer?.tolerance = 0.05
    }
    public func markOwnWrite() { lastChange = pasteboard.changeCount }
    public func poll() {
        if #available(macOS 15.4, *) {
            let denied = pasteboard.accessBehavior == .alwaysDeny
            onAccess?(denied)
            if denied { wasDenied = true; return }
            if wasDenied { wasDenied = false; lastChange = -1 }
        }
        guard !reading, pasteboard.changeCount != lastChange else { return }
        let change = pasteboard.changeCount
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown app"
        let types: [NSPasteboard.PasteboardType] = [.string, .URL, .fileURL, .rtf, .html, .png, .tiff]
        let snapshots = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: types.compactMap { type in item.data(forType: type).map { (type.rawValue, $0) } })
        }
        guard pasteboard.changeCount == change else { return }
        lastChange = change
        guard !snapshots.isEmpty else { return }
        reading = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.reading = false }
            do {
                let captures = try await Task.detached(priority: .utility) {
                    try snapshots.compactMap { try CaptureProcessor.process($0, source: source) }
                }.value
                for capture in captures { await self.onCapture?(capture) }
            } catch { self.onError?(error.localizedDescription) }
        }
    }
}
