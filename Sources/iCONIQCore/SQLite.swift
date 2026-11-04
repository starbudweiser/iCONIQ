import Foundation
import SQLite3

public enum SQLValue {
    case int(Int64), double(Double), text(String), null
}

public struct DBError: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
}

public struct Row {
    fileprivate let values: [String: SQLValue]
    public func string(_ k: String) -> String? { if case .text(let s)? = values[k] { return s }; return nil }
    public func int(_ k: String) -> Int { if case .int(let i)? = values[k] { return Int(i) }; return 0 }
    public func double(_ k: String) -> Double {
        switch values[k] { case .double(let d)?: return d; case .int(let i)?: return Double(i); default: return 0 }
    }
}

/// Fine couche sur sqlite3 (connexion unique, sérialisée par SQLite).
public final class Database: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let m = db.map { String(cString: sqlite3_errmsg($0)) } ?? "open"
            sqlite3_close(db)
            throw DBError(message: m)
        }
        sqlite3_busy_timeout(db, 5000)
        if !readOnly { try exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;") }
    }

    deinit { sqlite3_close(db) }

    public func exec(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "exec"
            sqlite3_free(err)
            throw DBError(message: m)
        }
    }

    @discardableResult
    public func run(_ sql: String, _ args: [SQLValue] = []) throws -> Int {
        lock.lock(); defer { lock.unlock() }
        let st = try prepare(sql, args)
        defer { sqlite3_finalize(st) }
        let rc = sqlite3_step(st)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw DBError(message: String(cString: sqlite3_errmsg(db))) }
        return Int(sqlite3_changes(db))
    }

    public func query(_ sql: String, _ args: [SQLValue] = []) throws -> [Row] {
        lock.lock(); defer { lock.unlock() }
        let st = try prepare(sql, args)
        defer { sqlite3_finalize(st) }
        var rows: [Row] = []
        let n = sqlite3_column_count(st)
        while true {
            let rc = sqlite3_step(st)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw DBError(message: String(cString: sqlite3_errmsg(db))) }
            var v: [String: SQLValue] = [:]
            for i in 0..<n {
                let name = String(cString: sqlite3_column_name(st, i))
                switch sqlite3_column_type(st, i) {
                case SQLITE_INTEGER: v[name] = .int(sqlite3_column_int64(st, i))
                case SQLITE_FLOAT: v[name] = .double(sqlite3_column_double(st, i))
                case SQLITE_TEXT: v[name] = .text(String(cString: sqlite3_column_text(st, i)))
                default: v[name] = .null
                }
            }
            rows.append(Row(values: v))
        }
        return rows
    }

    /// Exécute `body` dans une transaction (annulée si `body` lève une erreur).
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try exec("BEGIN IMMEDIATE")
        do { let r = try body(); try exec("COMMIT"); return r }
        catch { try? exec("ROLLBACK"); throw error }
    }

    private func prepare(_ sql: String, _ args: [SQLValue]) throws -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { throw DBError(message: String(cString: sqlite3_errmsg(db))) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            switch a {
            case .int(let v): sqlite3_bind_int64(st, idx, v)
            case .double(let v): sqlite3_bind_double(st, idx, v)
            case .text(let v): sqlite3_bind_text(st, idx, v, -1, transient)
            case .null: sqlite3_bind_null(st, idx)
            }
        }
        return st
    }
}

extension SQLValue {
    public static func opt(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
}
