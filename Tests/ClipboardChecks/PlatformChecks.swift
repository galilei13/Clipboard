import AppKit
import AVFoundation
import ClipboardCore
import ClipboardPlatform

extension HistoryChecks {
    func testCapturePersianAndRichText() throws {
        let text = "  سلام 🌱\nHello\n"
        let formats = [NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8),
                       NSPasteboard.PasteboardType.html.rawValue: Data("<b>Hello</b>".utf8)]
        let capture = try unwrap(CaptureProcessor.process(formats, source: "Test"))
        try equal(capture.text, text); try equal(capture.kind, .text)
        try equal(capture.representations, formats)
    }
    func testLinkDetectionDoesNotModifyURL() throws {
        let text = "https://example.com/a?value=1#section"
        let capture = try unwrap(CaptureProcessor.process([NSPasteboard.PasteboardType.string.rawValue: Data(text.utf8)], source: "Test"))
        try equal(capture.kind, .link); try equal(capture.text, text)
        let sentence = try unwrap(CaptureProcessor.process([NSPasteboard.PasteboardType.string.rawValue: Data((text + " extra").utf8)], source: "Test"))
        try equal(sentence.kind, .text)
    }
    func testRTFFallbackExtractsPlainTextAndKeepsOriginal() throws {
        let rich = Data("{\\rtf1\\ansi Hello \\b world\\b0}".utf8)
        let capture = try unwrap(CaptureProcessor.process([NSPasteboard.PasteboardType.rtf.rawValue: rich], source: "Test"))
        try equal(capture.text, "Hello world")
        try equal(capture.representations[NSPasteboard.PasteboardType.rtf.rawValue], rich)
        try equal(capture.representations[NSPasteboard.PasteboardType.string.rawValue], Data("Hello world".utf8))
    }
    func testImageNormalizationAcrossPNGAndTIFF() throws {
        let context = try unwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let rep = NSBitmapImageRep(cgImage: try unwrap(context.makeImage()))
        let png = try unwrap(rep.representation(using: .png, properties: [:]))
        let tiff = try unwrap(rep.representation(using: .tiff, properties: [:]))
        let first = try unwrap(CaptureProcessor.process([NSPasteboard.PasteboardType.png.rawValue: png], source: "Test"))
        let second = try unwrap(CaptureProcessor.process([NSPasteboard.PasteboardType.tiff.rawValue: tiff], source: "Test"))
        try equal(first.kind, .image); try equal(first.fingerprint, second.fingerprint)
        try check(first.thumbnail != nil); try check(second.representations[NSPasteboard.PasteboardType.png.rawValue] != nil)
        try equal(first.text, "Image · 32 × 24")
    }
    @MainActor func testNamedPasteboardCaptureAndOwnWriteSuppression() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Existing content should not be captured", forType: .string)
        let reader = ClipboardReader(pasteboard: board)
        var captures: [Capture] = []
        reader.onCapture = { captures.append($0) }
        reader.poll()
        try check(captures.isEmpty)
        board.clearContents(); board.setString("Captured text", forType: .string)
        reader.poll()
        for _ in 0..<100 {
            if !captures.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try equal(captures.count, 1); try equal(captures.first?.text, "Captured text")
        board.clearContents(); board.setString("Own write", forType: .string)
        reader.markOwnWrite(); reader.poll()
        try await Task.sleep(nanoseconds: 20_000_000)
        try equal(captures.count, 1)
    }
    @MainActor func testNamedPasteboardCapturesMultipleItems() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: board)
        var captures: [Capture] = []
        reader.onCapture = { captures.append($0) }
        let a = NSPasteboardItem(); a.setString("First", forType: .string)
        let b = NSPasteboardItem(); b.setString("Second", forType: .string)
        board.clearContents(); try check(board.writeObjects([a,b])); reader.poll()
        for _ in 0..<100 {
            if captures.count == 2 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try equal(captures.map(\.text), ["First", "Second"])
    }
}

extension HistoryChecks {
    func testColorPreviews() throws {
        let color = try unwrap(ClipColor.parse(" #f80 "))
        try check(abs(color.redComponent - 1) < 0.001)
        try check(abs(color.greenComponent - 136.0 / 255) < 0.001)
        try check(ClipColor.parse("#33669980") != nil)
        try check(ClipColor.parse("rgb(255, 0, 128)") != nil)
        try check(ClipColor.parse("rgba(10, 20, 30, 0.5)") != nil)
        try isNil(ClipColor.parse("#hello")); try isNil(ClipColor.parse("rgb(999, 0, 0)"))
        try isNil(ClipColor.parse("Some text #fff"))
    }
    func testFileImagePreviewKeepsFileRepresentation() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let context = try unwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let rep = NSBitmapImageRep(cgImage: try unwrap(context.makeImage()))
        let url = directory.appendingPathComponent("sample.png")
        try unwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        let raw = [NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8)]
        let capture = try unwrap(CaptureProcessor.process(raw, source: "Finder"))
        try equal(capture.kind, .image); try equal(capture.text, "sample.png")
        try check(capture.thumbnail != nil); try equal(capture.representations, raw)
        let missing = directory.appendingPathComponent("missing.mov")
        let video = try unwrap(CaptureProcessor.process([NSPasteboard.PasteboardType.fileURL.rawValue: Data(missing.absoluteString.utf8)], source: "Finder"))
        try equal(video.kind, .video); try isNil(video.thumbnail)
    }
    func testKeyboardModifiersAndPersianNumbers() throws {
        let arrow = try unwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
            timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125))
        try check(ClipboardKeyboard.modifiers(for: arrow).isEmpty)
        let number = try unwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .capsLock],
            timestamp: 0, windowNumber: 0, context: nil, characters: "۱", charactersIgnoringModifiers: "۱", isARepeat: false, keyCode: 18))
        try equal(ClipboardKeyboard.itemNumber(for: number), 1)
        try equal(ClipboardKeyboard.modifiers(for: number), .command)
    }
    func testDeleteRemovesPinnedPayloadAndPreservesOtherItems() async throws {
        let repo = try HistoryRepository(directory: directory)
        let first = try await repo.capture(value("delete"), now: epoch)
        let second = try await repo.capture(value("keep"), now: epoch)
        try await repo.pin(id: first.id, duration: .forever, now: epoch)
        try await repo.remove(id: first.id)
        let rows = try await repo.items(now: epoch)
        try equal(rows.map(\.id), [second.id])
        try checkFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Payloads/" + first.payloadFile).path))
    }
}

extension HistoryChecks {
    func testVideoThumbnail() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input); try check(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        try equal(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
        let pixels = try unwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 128, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        for _ in 0..<100 where !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
        try check(adaptor.append(pixels, withPresentationTime: .zero))
        input.markAsFinished(); await writer.finishWriting()
        try equal(writer.status, .completed)
        let raw = [NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8)]
        let capture = try unwrap(CaptureProcessor.process(raw, source: "Finder"))
        try equal(capture.kind, .video); try check(capture.thumbnail != nil)
        try equal(capture.representations, raw)
    }
}
