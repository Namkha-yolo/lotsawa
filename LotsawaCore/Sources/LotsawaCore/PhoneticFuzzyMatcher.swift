// PhoneticFuzzyMatcher.swift
// LotsawaCore
//
// Automatic phonetic fuzzy matching for Tibetan transliteration
// Uses phonetic similarity rules + edit distance to match without manual mapping

import Foundation

/// Phonetic fuzzy matcher for automatic word matching
public struct PhoneticFuzzyMatcher {

    // MARK: - Phonetic Equivalence Classes

    /// Characters that sound similar in Tibetan pronunciation
    private static let phoneticEquivalences: [[String]] = [
        // Aspirated/unaspirated pairs
        ["k", "kh", "g"],
        ["c", "ch", "j"],
        ["t", "th", "d"],
        ["p", "ph", "b"],
        ["ts", "tsh", "dz"],

        // Vowel equivalences
        ["e", "ey", "ay", "ai", "é", "è"],
        ["i", "ee", "yi"],
        ["o", "ö", "oe", "oh"],
        ["u", "ü", "ue", "oo"],
        ["a", "ah"],

        // Dialect variations
        ["sh", "s"],
        ["zh", "z"],
        ["r", "l"],  // In some dialects
        ["ng", "n"],

        // Common confusions
        ["y", "i"],
        ["w", "u"],
    ]

    // MARK: - Dialect Equivalence Classes

    /// Lhasa dialect: cluster simplification patterns
    /// br→dr, bl→l, gr→dr, gl→l, skr→tr, sgr→dr, spr→tr
    private static let lhasaClusterSimplification: [(String, String)] = [
        ("br", "dr"), ("bl", "l"),
        ("gr", "dr"), ("gl", "l"),
        ("skr", "tr"), ("sgr", "dr"),
        ("spr", "tr"), ("sbr", "dr"),
        ("dby", "y"), ("dmy", "my"),
        ("rng", "ng"), ("rny", "ny"),
        ("sng", "ng"), ("sny", "ny"),
    ]

    /// Lhasa: silent finals (often dropped in pronunciation)
    private static let lhasaSilentFinals: Set<String> = ["r", "l", "s", "g", "d", "b"]

    /// Dzongkha: palatalization (khy → ch)
    private static let dzongkhaPalatalization: [(String, String)] = [
        ("khy", "ch"), ("khye", "che"), ("khyo", "cho"),
        ("khyö", "chö"), ("khyoe", "choe"),
        ("phy", "ch"),
    ]

    /// Active dialect for matching (default: all dialects)
    public enum Dialect: String, CaseIterable {
        case lhasa = "lhasa"
        case dzongkha = "dzongkha"
        case all = "all"
    }

    /// Current active dialect for matching
    public static var activeDialect: Dialect = .all

    /// Single character equivalences (faster lookup)
    private static let charEquivalences: [Character: [Character]] = [
        "k": ["g", "k"],
        "g": ["k", "g"],
        "c": ["j", "c"],
        "j": ["c", "j"],
        "t": ["d", "t"],
        "d": ["t", "d"],
        "p": ["b", "p"],
        "b": ["p", "b"],
        "e": ["a", "i"],
        "i": ["e", "y"],
        "o": ["u"],
        "u": ["o", "ü"],
        "ö": ["o", "e"],
        "ü": ["u", "i"],
    ]

    // MARK: - Public Interface

    /// Normalize phonetic input to a canonical form
    public static func normalize(_ input: String) -> String {
        var result = input.lowercased()

        // Normalize common variations to canonical form
        let normalizations: [(String, String)] = [
            // Aspirates
            ("kh", "K"),  // Temporary placeholder
            ("ch", "C"),
            ("th", "T"),
            ("ph", "P"),
            ("tsh", "Z"),

            // Digraphs
            ("sh", "S"),
            ("zh", "X"),
            ("ng", "N"),
            ("ny", "Y"),
            ("ts", "Q"),
            ("dz", "D"),

            // Vowel normalization
            ("ee", "i"),
            ("oo", "u"),
            ("ay", "e"),
            ("ai", "e"),
            ("ey", "e"),
            ("ei", "e"),
            ("ou", "o"),
            ("oe", "ö"),
            ("ue", "ü"),
        ]

        for (from, to) in normalizations {
            result = result.replacingOccurrences(of: from, with: to)
        }

        // Restore placeholders
        result = result.replacingOccurrences(of: "K", with: "kh")
        result = result.replacingOccurrences(of: "C", with: "ch")
        result = result.replacingOccurrences(of: "T", with: "th")
        result = result.replacingOccurrences(of: "P", with: "ph")
        result = result.replacingOccurrences(of: "Z", with: "tsh")
        result = result.replacingOccurrences(of: "S", with: "sh")
        result = result.replacingOccurrences(of: "X", with: "zh")
        result = result.replacingOccurrences(of: "N", with: "ng")
        result = result.replacingOccurrences(of: "Y", with: "ny")
        result = result.replacingOccurrences(of: "Q", with: "ts")
        result = result.replacingOccurrences(of: "D", with: "dz")

        return result
    }

    /// Compute phonetic distance between two strings
    /// Lower score = more similar
    public static func phoneticDistance(_ a: String, _ b: String) -> Int {
        let normA = normalize(a)
        let normB = normalize(b)

        // Use weighted Levenshtein with phonetic equivalences
        return weightedLevenshtein(normA, normB)
    }

    /// Weighted Levenshtein distance considering phonetic equivalences
    private static func weightedLevenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)

        let m = aChars.count
        let n = bChars.count

        // Early exit for empty strings
        if m == 0 { return n * 10 }
        if n == 0 { return m * 10 }

        // DP matrix
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        // Initialize base cases
        for i in 0...m { dp[i][0] = i * 10 }
        for j in 0...n { dp[0][j] = j * 10 }

        // Fill matrix
        for i in 1...m {
            for j in 1...n {
                let charA = aChars[i - 1]
                let charB = bChars[j - 1]

                let cost: Int
                if charA == charB {
                    cost = 0
                } else if arePhoneticEquivalent(charA, charB) {
                    cost = 2  // Low cost for phonetically similar
                } else if areVowels(charA, charB) {
                    cost = 3  // Medium cost for vowel confusion
                } else {
                    cost = 10  // High cost for different consonants
                }

                dp[i][j] = min(
                    dp[i - 1][j] + 10,      // deletion
                    dp[i][j - 1] + 10,      // insertion
                    dp[i - 1][j - 1] + cost  // substitution
                )
            }
        }

        return dp[m][n]
    }

    /// Check if two characters are phonetically equivalent
    private static func arePhoneticEquivalent(_ a: Character, _ b: Character) -> Bool {
        if a == b { return true }
        if let equivalents = charEquivalences[a], equivalents.contains(b) {
            return true
        }
        if let equivalents = charEquivalences[b], equivalents.contains(a) {
            return true
        }
        return false
    }

    /// Check if both characters are vowels
    private static func areVowels(_ a: Character, _ b: Character) -> Bool {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "ö", "ü", "é", "è"]
        return vowels.contains(a) && vowels.contains(b)
    }

    // MARK: - Dialect-Aware Transformations

    /// Generate dialect-specific variations of an input
    /// - Parameters:
    ///   - input: The phonetic input to transform
    ///   - dialect: The dialect to apply (default: all)
    /// - Returns: Array of dialect-transformed variations
    public static func generateDialectVariations(_ input: String, dialect: Dialect = .all) -> [String] {
        var variations = Set<String>([input.lowercased()])
        let normalized = normalize(input)
        variations.insert(normalized)

        switch dialect {
        case .lhasa:
            variations.formUnion(applyLhasaTransforms(normalized))
        case .dzongkha:
            variations.formUnion(applyDzongkhaTransforms(normalized))
        case .all:
            variations.formUnion(applyLhasaTransforms(normalized))
            variations.formUnion(applyDzongkhaTransforms(normalized))
        }

        return Array(variations)
    }

    /// Apply Lhasa dialect transformations
    private static func applyLhasaTransforms(_ input: String) -> [String] {
        var results = Set<String>()

        // Cluster simplification
        let modified = input
        for (cluster, simplified) in lhasaClusterSimplification {
            if modified.contains(cluster) {
                let simplified_form = modified.replacingOccurrences(of: cluster, with: simplified)
                results.insert(simplified_form)
            }
            // Also try reverse (in case input is simplified)
            if modified.contains(simplified) && cluster != simplified {
                let cluster_form = modified.replacingOccurrences(of: simplified, with: cluster)
                results.insert(cluster_form)
            }
        }

        // Silent finals - try dropping them
        for final in lhasaSilentFinals {
            if input.hasSuffix(final) {
                results.insert(String(input.dropLast(final.count)))
            }
            // Also try adding them (in case input dropped finals)
            results.insert(input + final)
        }

        return Array(results)
    }

    /// Apply Dzongkha (Bhutanese) transformations
    private static func applyDzongkhaTransforms(_ input: String) -> [String] {
        var results = Set<String>()

        // Palatalization (khy → ch)
        for (original, palatalized) in dzongkhaPalatalization {
            if input.contains(original) {
                results.insert(input.replacingOccurrences(of: original, with: palatalized))
            }
            if input.contains(palatalized) {
                results.insert(input.replacingOccurrences(of: palatalized, with: original))
            }
        }

        // Special Dzongkha word forms
        let dzongkhaSpecial: [(String, String)] = [
            ("choe", "khyö"), ("cho", "khyo"),
            ("che", "khye"), ("chey", "khyed"),
        ]

        for (dz, standard) in dzongkhaSpecial {
            if input == dz {
                results.insert(standard)
            }
            if input == standard {
                results.insert(dz)
            }
        }

        return Array(results)
    }

    // MARK: - Phonetic Key Generation

    /// Generate phonetic keys for a word (similar to Soundex/Metaphone)
    public static func generatePhoneticKeys(_ input: String) -> [String] {
        var keys: [String] = []
        let normalized = normalize(input)

        // Primary key: just the normalized form
        keys.append(normalized)

        // Alternative keys with substitutions
        var alternates: [String] = [normalized]

        // Generate variants with aspirate/unaspirate swaps
        let aspirateSwaps: [(String, String)] = [
            ("kh", "k"), ("k", "kh"),
            ("ch", "c"), ("c", "ch"),
            ("th", "t"), ("t", "th"),
            ("ph", "p"), ("p", "ph"),
        ]

        for (from, to) in aspirateSwaps {
            if normalized.contains(from) {
                alternates.append(normalized.replacingOccurrences(of: from, with: to))
            }
        }

        // Generate variants with voiced/unvoiced swaps
        let voiceSwaps: [(String, String)] = [
            ("g", "k"), ("k", "g"),
            ("j", "ch"), ("ch", "j"),
            ("d", "t"), ("t", "d"),
            ("b", "p"), ("p", "b"),
        ]

        for alt in alternates {
            for (from, to) in voiceSwaps {
                if alt.contains(from) {
                    keys.append(alt.replacingOccurrences(of: from, with: to))
                }
            }
        }

        return Array(Set(keys))  // Remove duplicates
    }

    // MARK: - Typo Correction

    /// Generate possible corrections for common typos
    /// Handles: transpositions, missing vowels, extra repeated chars, missing chars
    public static func generateTypoVariations(_ input: String) -> [String] {
        var variations: [String] = []
        let chars = Array(input.lowercased())
        let n = chars.count

        guard n >= 2 else { return variations }

        // 1. Transpositions (swap adjacent characters): "tasih" -> "tashi"
        for i in 0..<(n - 1) {
            var swapped = chars
            swapped.swapAt(i, i + 1)
            variations.append(String(swapped))
        }

        // 2. Remove duplicate characters: "tashii" -> "tashi", "taashi" -> "tashi"
        var deduped: [Character] = []
        for (i, char) in chars.enumerated() {
            if i == 0 || char != chars[i - 1] {
                deduped.append(char)
            }
        }
        if deduped.count != n {
            variations.append(String(deduped))
        }

        // 3. Insert missing vowels: "tshi" -> "tashi", "tshe" etc.
        let vowels: [Character] = ["a", "e", "i", "o", "u"]
        let consonantClusters = ["ts", "tsh", "tr", "dr", "kr", "gr", "pr", "br", "sk", "sp", "st"]

        // Check if word looks like it's missing a vowel (consonant clusters without vowels)
        for i in 1..<n {
            let prevChar = chars[i - 1]
            let currChar = chars[i]

            // If two consonants are adjacent (not a valid cluster), try inserting vowels
            let isConsonant1 = !vowels.contains(prevChar)
            let isConsonant2 = !vowels.contains(currChar)

            if isConsonant1 && isConsonant2 {
                // Check if this is a valid consonant cluster
                let cluster = String([prevChar, currChar])
                let isValidCluster = consonantClusters.contains(where: { $0.hasPrefix(cluster) || $0.hasSuffix(cluster) })

                if !isValidCluster {
                    // Try inserting each vowel
                    for vowel in vowels {
                        var inserted = chars
                        inserted.insert(vowel, at: i)
                        variations.append(String(inserted))
                    }
                }
            }
        }

        // 4. Delete single characters (for extra chars): "taashi" -> "tashi"
        for i in 0..<n {
            var deleted = chars
            deleted.remove(at: i)
            if deleted.count >= 2 {
                variations.append(String(deleted))
            }
        }

        // 5. Common phonetic confusions in typos
        let confusions: [(String, String)] = [
            ("sh", "s"), ("s", "sh"),
            ("ch", "c"), ("c", "ch"),
            ("th", "t"), ("t", "th"),
            ("ph", "p"), ("p", "ph"),
            ("kh", "k"), ("k", "kh"),
        ]

        let inputStr = input.lowercased()
        for (from, to) in confusions {
            if inputStr.contains(from) {
                variations.append(inputStr.replacingOccurrences(of: from, with: to))
            }
        }

        // Remove duplicates and the original input
        return Array(Set(variations)).filter { $0 != input.lowercased() }
    }

    /// Check if input might be a typo of target
    public static func isLikelyTypo(_ input: String, of target: String) -> Bool {
        let normInput = normalize(input)
        let normTarget = normalize(target)

        // Quick length check - typos usually within 2 chars difference
        let lenDiff = abs(normInput.count - normTarget.count)
        if lenDiff > 2 { return false }

        // Compute edit distance
        let distance = phoneticDistance(normInput, normTarget)

        // Consider it a likely typo if distance is low
        // Threshold: ~2 edits for short words, ~3 for longer
        let threshold = min(30, max(20, normTarget.count * 5))
        return distance <= threshold
    }

    // MARK: - Corpus Matching

    /// Find best matches in corpus for given phonetic input
    public static func findMatches(
        _ input: String,
        in corpus: [(phonetic: String, tibetan: String, frequency: Int)],
        maxResults: Int = 10,
        maxDistance: Int = 30
    ) -> [(tibetan: String, score: Int)] {

        let inputKeys = generatePhoneticKeys(input)
        var candidates: [(tibetan: String, score: Int)] = []

        for entry in corpus {
            let entryKeys = generatePhoneticKeys(entry.phonetic)

            // Check if any keys match exactly
            let hasExactKey = !Set(inputKeys).isDisjoint(with: Set(entryKeys))

            // Compute phonetic distance
            let distance = phoneticDistance(input, entry.phonetic)

            if hasExactKey || distance <= maxDistance {
                // Score combines distance and frequency
                // Lower distance is better, higher frequency is better
                let score = distance - (entry.frequency / 100)
                candidates.append((entry.tibetan, score))
            }
        }

        // Sort by score (lower is better)
        candidates.sort { $0.score < $1.score }

        // Remove duplicates keeping best score
        var seen = Set<String>()
        var results: [(tibetan: String, score: Int)] = []

        for candidate in candidates {
            if !seen.contains(candidate.tibetan) {
                seen.insert(candidate.tibetan)
                results.append(candidate)
                if results.count >= maxResults {
                    break
                }
            }
        }

        return results
    }
}

// MARK: - SQLite-backed Fuzzy Search Extension

extension TrieIndex {

    /// Find entries with fuzzy phonetic matching via SQLiteDictionary.
    /// The TrieIndex is no longer populated; all data lives in SQLite.
    public func findFuzzy(phonetic: String, maxDistance: Int = 2) -> [PhoneticEntry] {
        let db = SQLiteDictionary.shared
        let normalized = PhoneticFuzzyMatcher.normalize(phonetic)
        var results: [PhoneticEntry] = []
        var seen = Set<String>()

        // Helper to add unique results
        func addUnique(_ entries: [PhoneticEntry]) {
            for entry in entries {
                if !seen.contains(entry.tibetan) {
                    seen.insert(entry.tibetan)
                    results.append(entry)
                }
            }
        }

        // 1. First, try exact match
        addUnique(db.lookupExact(phonetic: normalized))

        // 2. Try dialect variations (Lhasa, Amdo, Kham, Dzongkha)
        if results.count < 5 {
            let dialectVariations = PhoneticFuzzyMatcher.generateDialectVariations(phonetic)
            for variation in dialectVariations {
                addUnique(db.lookupExact(phonetic: variation))
            }
        }

        // 3. Try typo corrections (transpositions, missing vowels, etc.)
        if results.count < 5 {
            let typoVariations = PhoneticFuzzyMatcher.generateTypoVariations(phonetic)
            for variation in typoVariations {
                addUnique(db.lookupExact(phonetic: variation))
                // Also try the normalized form of the variation
                let normVariation = PhoneticFuzzyMatcher.normalize(variation)
                if normVariation != variation {
                    addUnique(db.lookupExact(phonetic: normVariation))
                }
            }
        }

        // 4. Try phonetic key variations (aspirate/voice swaps)
        if results.count < 5 {
            let phoneticKeys = PhoneticFuzzyMatcher.generatePhoneticKeys(phonetic)
            for key in phoneticKeys {
                if key != normalized {
                    addUnique(db.lookupExact(phonetic: key))
                }
            }
        }

        // 5. Try prefix matching for partial words
        if results.count < 3 && phonetic.count >= 2 {
            addUnique(db.lookupPrefix(phonetic: normalized, limit: 10))
        }

        // Sort by frequency
        results.sort { $0.frequency > $1.frequency }

        return Array(results.prefix(20))
    }
}
