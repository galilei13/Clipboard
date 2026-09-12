import Foundation
import CryptoKit

public enum ClipKind: String, Codable, Sendable { case text, link, image, video, file }

public enum HistoryRetention: Int, CaseIterable, Codable, Sendable {
    case hour = 3600, day = 86400, threeDays = 259200, week = 604800, month = 2592000, forever = 0
    public var label: String {
        switch self {
        case .hour: return "1 hour"
        case .day: return "24 hours"
        case .threeDays: return "3 days"
        case .week: return "7 days"
        case .month: return "30 days"
        case .forever: return "Forever"
        }
    }
}

public enum PinDuration: String, CaseIterable, Sendable {
    case threeDays = "3 days", week = "1 week", month = "1 month", forever = "Forever"
    public func expiration(from date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .threeDays: return date.addingTimeInterval(3 * 86400)
        case .week: return date.addingTimeInterval(7 * 86400)
        case .month: return calendar.date(byAdding: .month, value: 1, to: date)
        case .forever: return nil
        }
    }
}

public struct Clip: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let fingerprint: String
    public var kind: ClipKind
    public var text: String
    public var source: String
    public let createdAt: Date
    public var copiedAt: Date
    public var pinUntil: Date?
    public var pinnedForever: Bool
    public var payloadFile: String
    public var thumbnail: Data?

    public func isPinned(at now: Date) -> Bool { pinnedForever || (pinUntil.map { $0 > now } ?? false) }
    public var supportsPlainText: Bool { kind == .text || kind == .link }
    public func isExpired(at now: Date, retention: HistoryRetention = .day) -> Bool {
        !isPinned(at: now) && retention != .forever && now.timeIntervalSince(copiedAt) >= Double(retention.rawValue)
    }
    public var title: String {
        if kind == .image { return text.isEmpty ? "Copied image" : text }
        return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Empty text"
    }
    public static func fingerprint(kind: ClipKind, bytes: Data) -> String {
        var input = Data(kind.rawValue.utf8); input.append(0); input.append(bytes)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}

public struct Capture: Sendable {
    public let kind: ClipKind
    public let text: String
    public let source: String
    public let fingerprint: String
    public let representations: [String: Data]
    public let thumbnail: Data?
    public init(kind: ClipKind, text: String, source: String, fingerprint: String,
                representations: [String: Data], thumbnail: Data? = nil) {
        self.kind = kind; self.text = text; self.source = source; self.fingerprint = fingerprint
        self.representations = representations; self.thumbnail = thumbnail
    }
}

public enum HistoryError: LocalizedError {
    case database(String), missingItem, unsupportedSchema
    public var errorDescription: String? {
        switch self {
        case .database(let message): return "History could not be saved: \(message)"
        case .missingItem: return "This item has expired or is no longer available."
        case .unsupportedSchema: return "This history was created by a newer version of Clipboard."
        }
    }
}
