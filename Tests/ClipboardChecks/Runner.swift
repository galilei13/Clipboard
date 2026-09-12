import Foundation
import Darwin

struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
func check(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    if !value { throw CheckFailure(message: "Check failed at \(file):\(line)") }
}
func checkFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) throws { try check(!value, file: file, line: line) }
func equal<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) throws { try check(a == b, file: file, line: line) }
func notEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) throws { try check(a != b, file: file, line: line) }
func isNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) throws { try check(a == nil, file: file, line: line) }
func unwrap<T>(_ a: T?) throws -> T { guard let a else { throw CheckFailure(message: "Expected a value") }; return a }

@main struct CheckRunner {
    static func main() async {
        let checks: [(String, (HistoryChecks) async throws -> Void)] = [
            ("testRetentionChoicesAndPersistence", { try await $0.testRetentionChoicesAndPersistence() }),
            ("testRetentionChangePreservesPinsAndExpiresRecent", { try await $0.testRetentionChangePreservesPinsAndExpiresRecent() }),
            ("testRetentionRecaptureAndUnpin", { try await $0.testRetentionRecaptureAndUnpin() }),
            ("testVideoThumbnail", { try await $0.testVideoThumbnail() }),
            ("testColorPreviews", { try $0.testColorPreviews() }),
            ("testFileImagePreviewKeepsFileRepresentation", { try $0.testFileImagePreviewKeepsFileRepresentation() }),
            ("testKeyboardModifiersAndPersianNumbers", { try $0.testKeyboardModifiersAndPersianNumbers() }),
            ("testDeleteRemovesPinnedPayloadAndPreservesOtherItems", { try await $0.testDeleteRemovesPinnedPayloadAndPreservesOtherItems() }),
            ("testExpirationAtExact24HoursDeletesPayload", { try await $0.testExpirationAtExact24HoursDeletesPayload() }),
            ("testDuplicateRefreshesTimeAndReplacesPayload", { try await $0.testDuplicateRefreshesTimeAndReplacesPayload() }),
            ("testWhitespaceAndPersianPreserved", { try await $0.testWhitespaceAndPersianPreserved() }),
            ("testEachTimedPinSurvives24HoursThenExpires", { try await $0.testEachTimedPinSurvives24HoursThenExpires() }),
            ("testForeverSurvivesYearsAndClearRecent", { try await $0.testForeverSurvivesYearsAndClearRecent() }),
            ("testRecopyPinnedDoesNotExtendPinAndReturnsToRecent", { try await $0.testRecopyPinnedDoesNotExtendPinAndReturnsToRecent() }),
            ("testUnpinOldDeletesButRecentRemains", { try await $0.testUnpinOldDeletesButRecentRemains() }),
            ("testRenewPinStartsFromNow", { try await $0.testRenewPinStartsFromNow() }),
            ("testCalendarMonthEndClamps", { try $0.testCalendarMonthEndClamps() }),
            ("testRestartPreservesPayloadAndPins", { try await $0.testRestartPreservesPayloadAndPins() }),
            ("testExpiredPayloadCannotBeUsedOrRepinned", { try await $0.testExpiredPayloadCannotBeUsedOrRepinned() }),
            ("testRecoveryRemovesOrphansOnlyInManagedFolder", { try await $0.testRecoveryRemovesOrphansOnlyInManagedFolder() }),
            ("testFormattedPayloadRoundTrip", { try await $0.testFormattedPayloadRoundTrip() }),
            ("testTouchDoesNotCreateDuplicateOrLosePin", { try await $0.testTouchDoesNotCreateDuplicateOrLosePin() }),
            ("testCapturePersianAndRichText", { try $0.testCapturePersianAndRichText() }),
            ("testLinkDetectionDoesNotModifyURL", { try $0.testLinkDetectionDoesNotModifyURL() }),
            ("testRTFFallbackExtractsPlainTextAndKeepsOriginal", { try $0.testRTFFallbackExtractsPlainTextAndKeepsOriginal() }),
            ("testImageNormalizationAcrossPNGAndTIFF", { try $0.testImageNormalizationAcrossPNGAndTIFF() }),
            ("testNamedPasteboardCaptureAndOwnWriteSuppression", { try await $0.testNamedPasteboardCaptureAndOwnWriteSuppression() }),
            ("testNamedPasteboardCapturesMultipleItems", { try await $0.testNamedPasteboardCapturesMultipleItems() })
        ]
        var failures = 0
        for (name, run) in checks {
            let suite = HistoryChecks()
            do {
                try suite.setUpWithError()
                defer { try? suite.tearDownWithError() }
                try await run(suite)
                print("PASS \(name)")
            } catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(checks.count - failures)/\(checks.count) checks passed")
        if failures > 0 { exit(1) }
    }
}
