import Foundation
import CSQLite

/// SQLite metadata and atomically written payloads are confined to this actor.
public actor HistoryRepository {
    private var db: OpaquePointer?
    public nonisolated let initialRetention: HistoryRetention
    private var retention: HistoryRetention
    private let retentionURL: URL
    private let payloadDirectory: URL
    private let encoder: PropertyListEncoder
    private let decoder = PropertyListDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL) throws {
        retentionURL = directory.appendingPathComponent("retention.json")
        let saved = (try? Data(contentsOf: retentionURL)).flatMap { try? JSONDecoder().decode(HistoryRetention.self, from: $0) } ?? .day
        initialRetention = saved; retention = saved
        payloadDirectory = directory.appendingPathComponent("Payloads", isDirectory: true)
        encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("history.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw HistoryError.database("Cannot open local database.")
        }
        sqlite3_busy_timeout(db, 3000)
        var versionQuery: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &versionQuery, nil)
        let version = sqlite3_step(versionQuery) == SQLITE_ROW ? sqlite3_column_int(versionQuery, 0) : 0
        sqlite3_finalize(versionQuery)
        guard version <= 1 else { sqlite3_close(db); db = nil; throw HistoryError.unsupportedSchema }
        let schema = """
        PRAGMA journal_mode=DELETE;
        PRAGMA secure_delete=ON;
        CREATE TABLE IF NOT EXISTS clips (
          id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL UNIQUE,
          copied REAL NOT NULL, metadata BLOB NOT NULL
        );
        CREATE INDEX IF NOT EXISTS clips_copied ON clips(copied DESC);
        PRAGMA user_version=1;
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db)); sqlite3_close(db); db = nil
            throw HistoryError.database(error)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    deinit { sqlite3_close(db) }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw dbError() }
        return stmt
    }
    private func dbError() -> HistoryError { .database(String(cString: sqlite3_errmsg(db))) }
    private func bind(_ value: String, to stmt: OpaquePointer, at index: Int32) {
        _ = sqlite3_bind_text(stmt, index, value, -1, transient)
    }
    private func read(_ stmt: OpaquePointer, column: Int32 = 0) throws -> Clip {
        let count = Int(sqlite3_column_bytes(stmt, column))
        guard let bytes = sqlite3_column_blob(stmt, column) else { throw dbError() }
        return try decoder.decode(Clip.self, from: Data(bytes: bytes, count: count))
    }
    private func rawItems() throws -> [Clip] {
        let stmt = try statement("SELECT metadata FROM clips ORDER BY copied DESC, id ASC")
        defer { sqlite3_finalize(stmt) }
        var result: [Clip] = []
        while true {
            let code = sqlite3_step(stmt)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw dbError() }
            result.append(try read(stmt))
        }
        return result
    }
    private func item(id: String) throws -> Clip {
        let stmt = try statement("SELECT metadata FROM clips WHERE id = ?")
        defer { sqlite3_finalize(stmt) }; bind(id, to: stmt, at: 1)
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw HistoryError.missingItem }
        return try read(stmt)
    }
    private func save(_ clip: Clip) throws {
        let data = try encoder.encode(clip)
        let stmt = try statement("INSERT INTO clips(id,fingerprint,copied,metadata) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET copied=excluded.copied,metadata=excluded.metadata")
        defer { sqlite3_finalize(stmt) }
        bind(clip.id, to: stmt, at: 1); bind(clip.fingerprint, to: stmt, at: 2)
        sqlite3_bind_double(stmt, 3, clip.copiedAt.timeIntervalSince1970)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
    }
    private func delete(_ clip: Clip) throws {
        let stmt = try statement("DELETE FROM clips WHERE id=?")
        defer { sqlite3_finalize(stmt) }; bind(clip.id, to: stmt, at: 1)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw dbError() }
        let url = payloadDirectory.appendingPathComponent(clip.payloadFile)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    public func setRetention(_ value: HistoryRetention) throws {
        try JSONEncoder().encode(value).write(to: retentionURL, options: .atomic)
        retention = value
    }

    public func items(now: Date = Date()) throws -> [Clip] {
        let records = try rawItems()
        var valid: [Clip] = []
        for var clip in records {
            if clip.isExpired(at: now, retention: retention) { try delete(clip); continue }
            if let expiry = clip.pinUntil, expiry <= now {
                clip.pinUntil = nil; try save(clip)
            }
            valid.append(clip)
        }
        return valid
    }

    public func recover(now: Date = Date()) throws -> [Clip] {
        let valid = try items(now: now)
        let referenced = Set(valid.map(\.payloadFile))
        // Only remove unreferenced payload files inside our own managed directory.
        for url in try FileManager.default.contentsOfDirectory(at: payloadDirectory, includingPropertiesForKeys: nil)
            where url.pathExtension == "clip" && !referenced.contains(url.lastPathComponent) {
            try FileManager.default.removeItem(at: url)
        }
        return valid
    }

    @discardableResult public func capture(_ capture: Capture, now: Date = Date()) throws -> Clip {
        let stmt = try statement("SELECT metadata FROM clips WHERE fingerprint=?")
        bind(capture.fingerprint, to: stmt, at: 1)
        let code = sqlite3_step(stmt)
        var old: Clip?
        if code == SQLITE_ROW { old = try read(stmt) }
        else if code == SQLITE_DONE { old = nil }
        else { sqlite3_finalize(stmt); throw dbError() }
        sqlite3_finalize(stmt)
        if let previous = old, previous.isExpired(at: now, retention: retention) { try delete(previous); old = nil }
        let filename = UUID().uuidString + ".clip"
        let url = payloadDirectory.appendingPathComponent(filename)
        let payload = try encoder.encode(capture.representations)
        try payload.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let clip = Clip(id: old?.id ?? UUID().uuidString, fingerprint: capture.fingerprint,
                        kind: capture.kind, text: capture.text, source: capture.source,
                        createdAt: old?.createdAt ?? now, copiedAt: now,
                        pinUntil: old?.pinUntil, pinnedForever: old?.pinnedForever ?? false,
                        payloadFile: filename, thumbnail: capture.thumbnail)
        do { try save(clip) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        if let old { try FileManager.default.removeItem(at: payloadDirectory.appendingPathComponent(old.payloadFile)) }
        return clip
    }

    public func payload(id: String, now: Date = Date()) throws -> [String: Data] {
        let clip = try item(id: id)
        guard !clip.isExpired(at: now, retention: retention) else { try delete(clip); throw HistoryError.missingItem }
        let data = try Data(contentsOf: payloadDirectory.appendingPathComponent(clip.payloadFile))
        return try decoder.decode([String: Data].self, from: data)
    }

    public func touch(id: String, now: Date = Date()) throws {
        var clip = try item(id: id)
        guard !clip.isExpired(at: now, retention: retention) else { try delete(clip); throw HistoryError.missingItem }
        clip.copiedAt = now; try save(clip)
    }

    public func pin(id: String, duration: PinDuration?, now: Date = Date(), calendar: Calendar = .current) throws {
        var clip = try item(id: id)
        guard !clip.isExpired(at: now, retention: retention) else { try delete(clip); throw HistoryError.missingItem }
        clip.pinnedForever = duration == .forever
        clip.pinUntil = duration?.expiration(from: now, calendar: calendar)
        if clip.isExpired(at: now, retention: retention) { try delete(clip) } else { try save(clip) }
    }

    public func remove(id: String) throws { try delete(item(id: id)) }

    public func clearRecent(now: Date = Date()) throws {
        for clip in try rawItems() where !clip.isPinned(at: now) { try delete(clip) }
    }
}
