import Foundation
import ClipboardCore

final class HistoryChecks {
    var directory: URL!
    let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardTests-" + UUID().uuidString)
    }
    func tearDownWithError() throws { if let directory { try? FileManager.default.removeItem(at: directory) } }
    func value(_ text: String = "Hello", source: String = "Test") -> Capture {
        Capture(kind: .text, text: text, source: source,
                fingerprint: Clip.fingerprint(kind: .text, bytes: Data(text.utf8)),
                representations: ["public.utf8-plain-text": Data(text.utf8)])
    }
    func testExpirationAtExact24HoursDeletesPayload() async throws {
        let repo = try HistoryRepository(directory: directory)
        let clip = try await repo.capture(value(), now: epoch)
        let before = try await repo.items(now: epoch.addingTimeInterval(86399))
        try equal(before.count, 1)
        let after = try await repo.items(now: epoch.addingTimeInterval(86400))
        try check(after.isEmpty)
        try checkFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Payloads/" + clip.payloadFile).path))
    }
    func testDuplicateRefreshesTimeAndReplacesPayload() async throws {
        let repo = try HistoryRepository(directory: directory)
        let first = try await repo.capture(value(), now: epoch)
        let second = try await repo.capture(value(source: "Notes"), now: epoch.addingTimeInterval(80000))
        try equal(first.id, second.id); try equal(second.source, "Notes")
        try notEqual(first.payloadFile, second.payloadFile)
        try checkFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Payloads/" + first.payloadFile).path))
        let rows = try await repo.items(now: epoch.addingTimeInterval(90000))
        try equal(rows.count, 1)
        try equal(rows.first?.copiedAt, epoch.addingTimeInterval(80000))
    }
    func testWhitespaceAndPersianPreserved() async throws {
        let repo = try HistoryRepository(directory: directory)
        let original = "  سلام دنیا 👋\nline 2\n"
        let clip = try await repo.capture(value(original), now: epoch)
        _ = try await repo.capture(value(original.trimmingCharacters(in: .whitespacesAndNewlines)), now: epoch)
        let rows = try await repo.items(now: epoch)
        try equal(rows.count, 2)
        let payload = try await repo.payload(id: clip.id, now: epoch)
        try equal(payload["public.utf8-plain-text"], Data(original.utf8))
    }
    func testEachTimedPinSurvives24HoursThenExpires() async throws {
        for duration in [PinDuration.threeDays, .week, .month] {
            let folder = directory.appendingPathComponent(duration.rawValue)
            let repo = try HistoryRepository(directory: folder)
            let clip = try await repo.capture(value(), now: epoch)
            try await repo.pin(id: clip.id, duration: duration, now: epoch)
            let expiry = try unwrap(duration.expiration(from: epoch))
            let before = try await repo.items(now: expiry.addingTimeInterval(-1))
            try check(try unwrap(before.first).isPinned(at: expiry.addingTimeInterval(-1)))
            let after = try await repo.items(now: expiry)
            try check(after.isEmpty)
        }
    }
    func testForeverSurvivesYearsAndClearRecent() async throws {
        let repo = try HistoryRepository(directory: directory)
        let keep = try await repo.capture(value("Keep"), now: epoch)
        _ = try await repo.capture(value("Remove"), now: epoch)
        try await repo.pin(id: keep.id, duration: .forever, now: epoch)
        try await repo.clearRecent(now: epoch)
        let rows = try await repo.items(now: epoch.addingTimeInterval(10 * 365 * 86400))
        try equal(rows.map(\.id), [keep.id])
    }
    func testRecopyPinnedDoesNotExtendPinAndReturnsToRecent() async throws {
        let repo = try HistoryRepository(directory: directory)
        let clip = try await repo.capture(value(), now: epoch)
        try await repo.pin(id: clip.id, duration: .threeDays, now: epoch)
        let expiry = epoch.addingTimeInterval(3 * 86400)
        let copied = try await repo.capture(value(), now: expiry.addingTimeInterval(-7200))
        try equal(copied.pinUntil, expiry)
        let rows = try await repo.items(now: expiry)
        try equal(rows.count, 1); try checkFalse(rows[0].isPinned(at: expiry))
        try isNil(rows[0].pinUntil)
        let expired = try await repo.items(now: expiry.addingTimeInterval(22 * 3600))
        try check(expired.isEmpty)
    }
    func testUnpinOldDeletesButRecentRemains() async throws {
        let repo = try HistoryRepository(directory: directory)
        let old = try await repo.capture(value("Old"), now: epoch)
        try await repo.pin(id: old.id, duration: .forever, now: epoch)
        let now = epoch.addingTimeInterval(2 * 86400)
        let recent = try await repo.capture(value("Recent"), now: now)
        try await repo.pin(id: recent.id, duration: .week, now: now)
        try await repo.pin(id: old.id, duration: nil, now: now)
        try await repo.pin(id: recent.id, duration: nil, now: now)
        let rows = try await repo.items(now: now)
        try equal(rows.map(\.id), [recent.id])
    }
    func testRenewPinStartsFromNow() async throws {
        let repo = try HistoryRepository(directory: directory)
        let clip = try await repo.capture(value(), now: epoch)
        try await repo.pin(id: clip.id, duration: .threeDays, now: epoch)
        let later = epoch.addingTimeInterval(2 * 86400)
        try await repo.pin(id: clip.id, duration: .week, now: later)
        let rows = try await repo.items(now: later)
        try equal(rows.first?.pinUntil, later.addingTimeInterval(7 * 86400))
    }
    func testCalendarMonthEndClamps() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let jan = try unwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 12)))
        let feb = try unwrap(PinDuration.month.expiration(from: jan, calendar: calendar))
        try equal(calendar.component(.month, from: feb), 2)
        try equal(calendar.component(.day, from: feb), 28)
    }
    func testRestartPreservesPayloadAndPins() async throws {
        let first = try HistoryRepository(directory: directory)
        let clip = try await first.capture(value("Restart"), now: epoch)
        try await first.pin(id: clip.id, duration: .forever, now: epoch)
        let reopened = try HistoryRepository(directory: directory)
        let rows = try await reopened.recover(now: epoch.addingTimeInterval(3 * 86400))
        try equal(rows.map(\.id), [clip.id]); try check(rows[0].pinnedForever)
        let payload = try await reopened.payload(id: clip.id, now: epoch.addingTimeInterval(3 * 86400))
        try equal(payload["public.utf8-plain-text"], Data("Restart".utf8))
    }
    func testExpiredPayloadCannotBeUsedOrRepinned() async throws {
        let repo = try HistoryRepository(directory: directory)
        let clip = try await repo.capture(value(), now: epoch)
        do {
            _ = try await repo.payload(id: clip.id, now: epoch.addingTimeInterval(86400))
            throw CheckFailure(message: "Expired payload returned")
        } catch { try check(error is HistoryError) }
        do { try await repo.pin(id: clip.id, duration: .forever, now: epoch.addingTimeInterval(86400)); throw CheckFailure(message: "Expired pin allowed") }
        catch { try check(error is HistoryError) }
    }
    func testRecoveryRemovesOrphansOnlyInManagedFolder() async throws {
        let repo = try HistoryRepository(directory: directory)
        let clip = try await repo.capture(value(), now: epoch)
        let orphan = directory.appendingPathComponent("Payloads/orphan.clip")
        let unrelated = directory.appendingPathComponent("Payloads/keep.txt")
        try Data([1]).write(to: orphan); try Data([2]).write(to: unrelated)
        let rows = try await repo.recover(now: epoch)
        try equal(rows.map(\.id), [clip.id])
        try checkFalse(FileManager.default.fileExists(atPath: orphan.path))
        try check(FileManager.default.fileExists(atPath: unrelated.path))
    }
    func testFormattedPayloadRoundTrip() async throws {
        let repo = try HistoryRepository(directory: directory)
        let formats = ["public.utf8-plain-text": Data("bold".utf8), "public.rtf": Data("{\\rtf1\\b bold}".utf8)]
        let capture = Capture(kind: .text, text: "bold", source: "Test", fingerprint: "test-rich", representations: formats)
        let clip = try await repo.capture(capture, now: epoch)
        let payload = try await repo.payload(id: clip.id, now: epoch)
        try equal(payload, formats)
    }
    func testTouchDoesNotCreateDuplicateOrLosePin() async throws {
        let repo = try HistoryRepository(directory: directory)
        let clip = try await repo.capture(value(), now: epoch)
        try await repo.pin(id: clip.id, duration: .week, now: epoch)
        try await repo.touch(id: clip.id, now: epoch.addingTimeInterval(50))
        let rows = try await repo.items(now: epoch.addingTimeInterval(50))
        try equal(rows.count, 1); try equal(rows[0].copiedAt, epoch.addingTimeInterval(50))
        try equal(rows[0].pinUntil, epoch.addingTimeInterval(7 * 86400))
    }
}

extension HistoryChecks {
    func testRetentionChoicesAndPersistence() async throws {
        for retention in HistoryRetention.allCases {
            let folder = directory.appendingPathComponent(String(retention.rawValue))
            let repo = try HistoryRepository(directory: folder)
            try await repo.setRetention(retention)
            let clip = try await repo.capture(value(), now: epoch)
            let reopened = try HistoryRepository(directory: folder)
            try equal(reopened.initialRetention, retention)
            if retention == .forever {
                let rows = try await reopened.recover(now: epoch.addingTimeInterval(10 * 365 * 86400))
                try equal(rows.map(\.id), [clip.id])
            } else {
                let before = epoch.addingTimeInterval(Double(retention.rawValue) - 1)
                let payload = try await reopened.payload(id: clip.id, now: before)
                try check(!payload.isEmpty)
                let rows = try await reopened.items(now: epoch.addingTimeInterval(Double(retention.rawValue)))
                try check(rows.isEmpty)
            }
        }
    }
    func testRetentionChangePreservesPinsAndExpiresRecent() async throws {
        let repo = try HistoryRepository(directory: directory)
        try await repo.setRetention(.week)
        let recent = try await repo.capture(value("recent"), now: epoch)
        let pinned = try await repo.capture(value("pinned"), now: epoch)
        try await repo.pin(id: pinned.id, duration: .forever, now: epoch)
        let later = epoch.addingTimeInterval(2 * 86400)
        try await repo.touch(id: recent.id, now: later)
        let payload = try await repo.payload(id: recent.id, now: later)
        try check(!payload.isEmpty)
        try await repo.setRetention(.hour)
        let rows = try await repo.recover(now: later.addingTimeInterval(3600))
        try equal(rows.map(\.id), [pinned.id])
    }
    func testRetentionRecaptureAndUnpin() async throws {
        let repo = try HistoryRepository(directory: directory)
        try await repo.setRetention(.forever)
        let first = try await repo.capture(value(), now: epoch)
        let later = epoch.addingTimeInterval(5 * 86400)
        let duplicate = try await repo.capture(value(), now: later)
        try equal(first.id, duplicate.id)
        try await repo.pin(id: first.id, duration: .week, now: later)
        try await repo.pin(id: first.id, duration: nil, now: later.addingTimeInterval(2 * 86400))
        let rows = try await repo.items(now: later.addingTimeInterval(20 * 86400))
        try equal(rows.map(\.id), [first.id])
        try check(rows.first?.isPinned(at: later) == false)
    }
}
