// TrieIndex.swift
// LotsawaCore
//
// Fast Trie-based prefix matching for phonetic lookups
// Provides O(m) lookup where m is the length of the query

import Foundation

/// A node in the Trie
final class TrieNode {
    var children: [Character: TrieNode] = [:]
    var words: [PhoneticEntry] = []
    var isEndOfWord: Bool = false
}

/// An entry in the phonetic lookup
public struct PhoneticEntry: Codable, Hashable {
    public let tibetan: String
    public let frequency: Int

    enum CodingKeys: String, CodingKey {
        case tibetan = "t"
        case frequency = "f"
    }

    public init(tibetan: String, frequency: Int = 0) {
        self.tibetan = tibetan
        self.frequency = frequency
    }
}

/// Trie-based index for fast phonetic prefix matching
public final class TrieIndex {

    private let root = TrieNode()
    private var wordCount = 0

    public init() {}

    // MARK: - Building the Trie

    /// Insert a word into the Trie
    public func insert(phonetic: String, entries: [PhoneticEntry]) {
        let key = phonetic.lowercased()
        var current = root

        for char in key {
            if current.children[char] == nil {
                current.children[char] = TrieNode()
            }
            current = current.children[char]!
        }

        current.isEndOfWord = true
        // Sort entries by frequency (descending) when storing
        current.words = entries.sorted { $0.frequency > $1.frequency }
        wordCount += 1
    }

    /// Build Trie from dictionary
    public func build(from dictionary: [String: [PhoneticEntry]]) {
        for (phonetic, entries) in dictionary {
            insert(phonetic: phonetic, entries: entries)
        }
    }

    // MARK: - Querying

    /// Find exact match for a phonetic string
    public func find(phonetic: String) -> [PhoneticEntry] {
        let key = phonetic.lowercased()
        var current = root

        for char in key {
            guard let next = current.children[char] else {
                return []
            }
            current = next
        }

        return current.isEndOfWord ? current.words : []
    }

    /// Find all words with the given prefix
    /// Returns results sorted by frequency (descending)
    public func findWithPrefix(_ prefix: String, limit: Int = 10) -> [(phonetic: String, entries: [PhoneticEntry])] {
        let key = prefix.lowercased()
        var current = root
        var prefixPath = ""

        // Navigate to the prefix node
        for char in key {
            guard let next = current.children[char] else {
                return []
            }
            current = next
            prefixPath.append(char)
        }

        // Collect all words under this prefix
        var results: [(String, [PhoneticEntry])] = []
        collectWords(from: current, prefix: prefixPath, into: &results, limit: limit * 5)

        // Sort by best frequency in each entry group
        results.sort { lhs, rhs in
            let lhsMax = lhs.1.first?.frequency ?? 0
            let rhsMax = rhs.1.first?.frequency ?? 0
            return lhsMax > rhsMax
        }

        return Array(results.prefix(limit))
    }

    /// Collect all words from a node and its descendants
    private func collectWords(
        from node: TrieNode,
        prefix: String,
        into results: inout [(String, [PhoneticEntry])],
        limit: Int
    ) {
        guard results.count < limit else { return }

        if node.isEndOfWord && !node.words.isEmpty {
            results.append((prefix, node.words))
        }

        for (char, childNode) in node.children {
            collectWords(from: childNode, prefix: prefix + String(char), into: &results, limit: limit)
        }
    }

    /// Get suggestions for a partial input
    /// Prioritizes exact matches, then prefix matches
    public func getSuggestions(for input: String, limit: Int = 10) -> [String] {
        var results: [String] = []
        var seen = Set<String>()

        // First, try exact match
        let exact = find(phonetic: input)
        for entry in exact {
            if !seen.contains(entry.tibetan) {
                results.append(entry.tibetan)
                seen.insert(entry.tibetan)
            }
        }

        // Then, prefix matches
        let prefixMatches = findWithPrefix(input, limit: limit * 2)
        for (_, entries) in prefixMatches {
            for entry in entries {
                if results.count >= limit { break }
                if !seen.contains(entry.tibetan) {
                    results.append(entry.tibetan)
                    seen.insert(entry.tibetan)
                }
            }
        }

        return Array(results.prefix(limit))
    }

    // MARK: - Statistics

    public var count: Int {
        return wordCount
    }
}

// MARK: - Loading (deprecated, now uses SQLiteDictionary)

extension TrieIndex {

    /// Previously loaded 20 MB JSON into memory.
    /// Now returns an empty TrieIndex because all lookups go through SQLiteDictionary.
    public static func loadFromBundle() -> TrieIndex? {
        return TrieIndex()
    }
}

// MARK: - Thread-safe wrapper

/// Thread-safe singleton access to the TrieIndex.
/// Now returns an empty TrieIndex; all lookups go through SQLiteDictionary.shared.
public final class PhoneticIndex {
    public static let shared: TrieIndex = TrieIndex()

    private init() {}
}
