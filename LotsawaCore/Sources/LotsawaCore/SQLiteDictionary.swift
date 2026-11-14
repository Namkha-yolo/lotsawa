// SQLiteDictionary.swift
// LotsawaCore
//
// On-disk dictionary lookups using the native SQLite3 C API.
// Replaces in-memory JSON dictionaries to avoid exceeding the
// 50 MB memory limit of iOS keyboard extensions.

import Foundation
import SQLite3

/// Equivalent to C's `SQLITE_TRANSIENT` -- tells SQLite to copy bound text immediately.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe, read-only SQLite wrapper for phonetic lookup, n-grams, and word frequency.
/// All queries use cached prepared statements and run on a serial queue.
/// Threading model: all post-init DB access is serialized via `queue`.
/// `SQLITE_OPEN_NOMUTEX` is safe because we never access the connection outside this queue.
public final class SQLiteDictionary {

    // MARK: - Singleton

    public static let shared = SQLiteDictionary()

    // MARK: - Private state

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.lotsawa.sqlitedictionary")

    /// Cached prepared statements (created lazily after DB opens)
    private var stmtExactLookup: OpaquePointer?
    private var stmtPrefixLookup: OpaquePointer?
    private var stmtBigrams: OpaquePointer?
    private var stmtTrigrams: OpaquePointer?
    private var stmtFourgrams: OpaquePointer?
    private var stmtWordFreq: OpaquePointer?
    private var stmtMaxFreq: OpaquePointer?
    private var stmtReverseLookup: OpaquePointer?
    private var stmtPhraseLookup: OpaquePointer?

    /// Cached max word frequency (computed once)
    private var cachedMaxFreq: Int?

    /// Whether the database was opened successfully
    public private(set) var isLoaded: Bool = false

    // MARK: - Init / Deinit

    private init() {
        openDatabase()
    }

    deinit {
        // Finalize all prepared statements before closing the database
        let stmts: [OpaquePointer?] = [
            stmtExactLookup, stmtPrefixLookup,
            stmtBigrams, stmtTrigrams, stmtFourgrams,
            stmtWordFreq, stmtMaxFreq,
            stmtReverseLookup, stmtPhraseLookup
        ]
        for stmt in stmts {
            if let s = stmt { sqlite3_finalize(s) }
        }
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard let url = Bundle.module.url(forResource: "lotsawa", withExtension: "db") else {
            print("SQLiteDictionary: lotsawa.db not found in bundle")
            return
        }

        let path = url.path
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, db != nil else {
            print("SQLiteDictionary: Failed to open database – \(errorMessage)")
            db = nil
            return
        }

        prepareStatements()
        isLoaded = true
        print("SQLiteDictionary: Opened \(path)")
    }

    private func prepareStatements() {
        stmtExactLookup = prepare(
            "SELECT tibetan, frequency FROM phonetic_entries WHERE phonetic = ?1 ORDER BY frequency DESC"
        )
        stmtPrefixLookup = prepare(
            "SELECT tibetan, frequency FROM phonetic_entries WHERE phonetic >= ?1 AND phonetic < ?2 ORDER BY frequency DESC LIMIT ?3"
        )
        stmtBigrams = prepare(
            "SELECT word2, count FROM bigrams WHERE word1 = ?1 ORDER BY count DESC"
        )
        stmtTrigrams = prepare(
            "SELECT word, count FROM trigrams WHERE key = ?1 ORDER BY count DESC"
        )
        stmtFourgrams = prepare(
            "SELECT word, count FROM fourgrams WHERE key = ?1 ORDER BY count DESC"
        )
        stmtWordFreq = prepare(
            "SELECT freq FROM word_freq WHERE word = ?1"
        )
        stmtMaxFreq = prepare(
            "SELECT MAX(freq) FROM word_freq"
        )
        stmtReverseLookup = prepare(
            "SELECT phonetic FROM reverse_lookup WHERE tibetan = ?1"
        )
        stmtPhraseLookup = prepare(
            "SELECT tibetan FROM phrases WHERE phonetic = ?1 LIMIT 1"
        )
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if rc != SQLITE_OK {
            print("SQLiteDictionary: Failed to prepare [\(sql)] – \(errorMessage)")
            return nil
        }
        return stmt
    }

    private var errorMessage: String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "no database connection"
    }

    // MARK: - Phonetic Lookups

    /// Exact-match lookup for a phonetic key.
    /// Returns entries sorted by descending frequency.
    public func lookupExact(phonetic: String) -> [PhoneticEntry] {
        guard isLoaded, let stmt = stmtExactLookup else { return [] }

        return queue.sync {
            defer { sqlite3_reset(stmt) }
            sqlite3_bind_text(stmt, 1, phonetic.lowercased(), -1, SQLITE_TRANSIENT)

            var results: [PhoneticEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let tibetan = String(cString: sqlite3_column_text(stmt, 0))
                let frequency = Int(sqlite3_column_int64(stmt, 1))
                results.append(PhoneticEntry(tibetan: tibetan, frequency: frequency))
            }
            return results
        }
    }

    /// Prefix-match lookup using index-friendly range query.
    /// Returns entries sorted by descending frequency, capped at `limit`.
    public func lookupPrefix(phonetic: String, limit: Int = 20) -> [PhoneticEntry] {
        guard isLoaded, let stmt = stmtPrefixLookup else { return [] }
        guard !phonetic.isEmpty else { return [] }

        let lower = phonetic.lowercased()
        // Build an upper bound by incrementing the last character.
        // e.g., "tashi" → lower="tashi", upper="tashj"
        let upper = Self.incrementLastChar(lower)

        return queue.sync {
            defer { sqlite3_reset(stmt) }
            sqlite3_bind_text(stmt, 1, lower, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, upper, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))

            var results: [PhoneticEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let tibetan = String(cString: sqlite3_column_text(stmt, 0))
                let frequency = Int(sqlite3_column_int64(stmt, 1))
                results.append(PhoneticEntry(tibetan: tibetan, frequency: frequency))
            }
            return results
        }
    }

    /// Increment the last character of a string to form an exclusive upper bound.
    /// "abc" → "abd", used for range-based prefix queries on the B-tree index.
    private static func incrementLastChar(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var chars = Array(s.unicodeScalars)
        chars[chars.count - 1] = Unicode.Scalar(chars[chars.count - 1].value + 1)!
        return String(String.UnicodeScalarView(chars))
    }

    // MARK: - N-gram Lookups

    /// Get bigram candidates: words that follow `word`.
    public func getBigrams(word: String) -> [(word: String, count: Int)] {
        return queryWordCount(stmt: stmtBigrams, key: word)
    }

    /// Get trigram candidates.
    /// `key` is formatted as `"word1|word2"`.
    public func getTrigrams(key: String) -> [(word: String, count: Int)] {
        return queryWordCount(stmt: stmtTrigrams, key: key)
    }

    /// Get fourgram candidates.
    /// `key` is formatted as `"word1|word2|word3"`.
    public func getFourgrams(key: String) -> [(word: String, count: Int)] {
        return queryWordCount(stmt: stmtFourgrams, key: key)
    }

    /// Shared helper for n-gram queries that return (word, count) pairs.
    private func queryWordCount(stmt: OpaquePointer?, key: String) -> [(word: String, count: Int)] {
        guard isLoaded, let stmt = stmt else { return [] }

        return queue.sync {
            defer { sqlite3_reset(stmt) }
            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)

            var results: [(word: String, count: Int)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let word = String(cString: sqlite3_column_text(stmt, 0))
                let count = Int(sqlite3_column_int64(stmt, 1))
                results.append((word: word, count: count))
            }
            return results
        }
    }

    // MARK: - Word Frequency

    /// Get the frequency of a single word. Returns 0 if not found.
    public func getWordFrequency(word: String) -> Int {
        guard isLoaded, let stmt = stmtWordFreq else { return 0 }

        return queue.sync {
            defer { sqlite3_reset(stmt) }
            sqlite3_bind_text(stmt, 1, word, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return Int(sqlite3_column_int64(stmt, 0))
            }
            return 0
        }
    }

    // MARK: - Reverse Lookup & Phrases

    /// Reverse lookup: given a Tibetan syllable, return its shortest phonetic key.
    public func getReverseLookup(tibetan: String) -> String? {
        guard isLoaded, let stmt = stmtReverseLookup else { return nil }

        return queue.sync {
            defer { sqlite3_reset(stmt) }
            sqlite3_bind_text(stmt, 1, tibetan, -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            return nil
        }
    }

    /// Phrase lookup: given a multi-word phonetic string, return the Tibetan phrase.
    public func getPhraseLookup(phonetic: String) -> String? {
        guard isLoaded, let stmt = stmtPhraseLookup else { return nil }

        return queue.sync {
            defer { sqlite3_reset(stmt) }
            sqlite3_bind_text(stmt, 1, phonetic.lowercased(), -1, SQLITE_TRANSIENT)

            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            return nil
        }
    }

    /// Get the maximum word frequency across all words.
    /// Cached after the first call.
    public func getMaxWordFrequency() -> Int {
        guard isLoaded, let stmt = stmtMaxFreq else { return 1 }

        return queue.sync {
            if let cached = cachedMaxFreq { return cached }
            defer { sqlite3_reset(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                let result = max(Int(sqlite3_column_int64(stmt, 0)), 1)
                cachedMaxFreq = result
                return result
            }
            cachedMaxFreq = 1
            return 1
        }
    }
}
