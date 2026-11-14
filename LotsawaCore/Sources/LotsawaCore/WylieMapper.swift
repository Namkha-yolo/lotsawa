// WylieMapper.swift
// LotsawaCore
//
// Converts Extended Wylie Transliteration Scheme (EWTS) to Tibetan Unicode
// Example: "bkra shis" -> བཀྲ་ཤིས་

import Foundation

/// Converts Wylie transliteration to Tibetan Unicode
public struct WylieMapper {

    // MARK: - Public Interface

    public init() {}

    /// Convert Wylie text to Tibetan Unicode
    /// - Parameter wylie: Text in Wylie transliteration (e.g., "bkra shis")
    /// - Returns: Tibetan Unicode string (e.g., "བཀྲ་ཤིས་")
    public func convert(_ wylie: String) -> String {
        let words = wylie.lowercased().split(separator: " ").map(String.init)
        var tibetanSyllables: [String] = []

        for word in words {
            // For space-separated words, convert directly as syllables
            // Only try to split if it's a single long word that might be compound
            // (e.g., "sprulsku" without spaces)
            if words.count == 1 && word.count > 6 {
                // Single word without spaces - try to split compound syllables
                let syllables = splitIntoSyllables(word)
                for syllable in syllables {
                    tibetanSyllables.append(convertSyllable(syllable))
                }
            } else {
                // Space-separated input - each word is already a syllable
                tibetanSyllables.append(convertSyllable(word))
            }
        }

        return tibetanSyllables.joined(separator: String(TibetanUnicode.tsheg))
    }

    /// Split a word into syllables (handles joined syllables like "sprulsku")
    private func splitIntoSyllables(_ word: String) -> [String] {
        var syllables: [String] = []
        var remaining = word

        while !remaining.isEmpty {
            // Find the best syllable boundary
            // Strategy: Find where a suffix consonant is followed by a new syllable start
            var bestLength = remaining.count

            // Look for potential syllable boundaries within the string
            let suffixConsonants = ["ng", "g", "d", "n", "b", "m", "r", "l", "s"]

            for length in 1..<remaining.count {
                let candidate = String(remaining.prefix(length))
                let rest = String(remaining.dropFirst(length))

                // Check if candidate ends with a suffix and rest can start a new syllable
                var candidateEndsSuffix = false
                for suffix in suffixConsonants {
                    if candidate.hasSuffix(suffix) {
                        candidateEndsSuffix = true
                        break
                    }
                }

                if candidateEndsSuffix && couldStartSyllable(rest) {
                    // Verify candidate looks like a valid syllable
                    if looksLikeCompleteSyllable(candidate) {
                        bestLength = length
                        break
                    }
                }
            }

            let syllable = String(remaining.prefix(bestLength))
            syllables.append(syllable)
            remaining = String(remaining.dropFirst(bestLength))
        }

        return syllables
    }

    /// Check if a string could be the start of a new syllable
    private func couldStartSyllable(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        // New syllable typically starts with:
        // - A consonant (possibly with prefix/superscript)
        // - Not a vowel or subscript indicator
        let consonantStarts = ["k", "g", "c", "j", "t", "d", "n", "p", "b", "m",
                               "ts", "dz", "w", "zh", "z", "'", "y", "r", "l",
                               "sh", "s", "h", "a"]
        return consonantStarts.contains { text.hasPrefix($0) }
    }

    /// Check if a string looks like a complete Tibetan syllable
    private func looksLikeCompleteSyllable(_ text: String) -> Bool {
        // A complete syllable should have a vowel (explicit or implicit 'a')
        // After parsing, there should be minimal leftover
        let parsed = parseSyllable(text)

        // Must have a root consonant
        if parsed.root.isEmpty {
            return false
        }

        // A valid syllable needs more than just a superscript consonant
        // e.g., "s" alone could be "sa", but we shouldn't split "sku" into "s" + "ku"
        // Require at least: root (with implicit 'a') or root + explicit vowel
        // Single letters that are superscripts (r, l, s) shouldn't split compound syllables
        let superscripts: Set<String> = ["r", "l", "s"]
        if text.count == 1 && superscripts.contains(text) {
            // Single superscript letter - might be part of next syllable
            // Only valid if we're sure it's not a superscript
            return false
        }

        // If text ends with a suffix consonant, make sure there's vowel content before it
        // e.g., "ng" alone is not valid, but "ang" is
        let suffixConsonants: Set<String> = ["ng", "g", "d", "n", "b", "m", "r", "l", "s"]
        for suffix in suffixConsonants {
            if text.hasSuffix(suffix) && text.count <= suffix.count {
                return false  // Just the suffix alone is not a valid syllable
            }
        }

        return true
    }

    /// Convert a single Wylie syllable to Tibetan
    /// - Parameter syllable: Single syllable in Wylie (e.g., "bkra")
    /// - Returns: Tibetan Unicode for that syllable
    public func convertSyllable(_ syllable: String) -> String {
        let parsed = parseSyllable(syllable)
        return buildTibetanSyllable(from: parsed)
    }

    // MARK: - Syllable Parsing

    /// Parsed components of a Tibetan syllable
    struct SyllableComponents {
        var prefix: String?
        var superscript: String?
        var root: String
        var subLetter: String?  // subscript letter (renamed from 'subscript' which is a Swift keyword)
        var vowel: String?
        var suffix: String?
        var suffix2: String?  // post-suffix
    }

    /// Parse a Wylie syllable into its components
    func parseSyllable(_ syllable: String) -> SyllableComponents {
        var remaining = syllable
        var components = SyllableComponents(root: "")

        // Try to identify each component
        // Order matters: prefix, superscript, root, subscript, vowel, suffix, suffix2

        // Check for prefix (g, d, b, m, ')
        if let (prefix, rest) = extractPrefix(from: remaining) {
            components.prefix = prefix
            remaining = rest
        }

        // Check for superscript (r, l, s) followed by root
        if let (superscript, rest) = extractSuperscript(from: remaining) {
            components.superscript = superscript
            remaining = rest
        }

        // Extract root consonant
        if let (root, rest) = extractConsonant(from: remaining) {
            components.root = root
            remaining = rest
        }

        // Check for subscript (+y, +r, +l, +w or just y, r, l, w after root)
        if let (subLetter, rest) = extractSubscript(from: remaining) {
            components.subLetter = subLetter
            remaining = rest
        }

        // Extract vowel (a is implicit, i, u, e, o are explicit)
        if let (vowel, rest) = extractVowel(from: remaining) {
            components.vowel = vowel
            remaining = rest
        }

        // Extract suffix
        if let (suffix, rest) = extractSuffix(from: remaining) {
            components.suffix = suffix
            remaining = rest
        }

        // Extract post-suffix (d or s after suffix)
        if let (suffix2, _) = extractPostSuffix(from: remaining) {
            components.suffix2 = suffix2
        }

        return components
    }

    // MARK: - Component Extraction

    private func extractPrefix(from text: String) -> (String, String)? {
        // Prefixes: g, d, b, m, '
        // A prefix is only valid if followed by a valid root
        let prefixes = ["g", "d", "b", "m", "'"]

        // Check for digraph consonants that should NOT be split
        // e.g., "dz" is a single consonant, not d + z
        let digraphs = ["dz", "ts", "tsh", "sh", "zh", "ng", "ny", "kh", "ch", "th", "ph"]
        for digraph in digraphs {
            if text.hasPrefix(digraph) {
                return nil  // Don't extract prefix from digraph
            }
        }

        // Check for subscript patterns - don't treat first letter as prefix
        // if it forms a valid root+subscript combination
        // e.g., "gya" = g+y+a, not prefix g + root y + a
        let subscriptLetters = ["y", "r", "l", "w"]
        for prefix in prefixes {
            if text.hasPrefix(prefix) {
                let rest = String(text.dropFirst(prefix.count))
                // Don't treat as prefix if it's actually root + subscript
                for sub in subscriptLetters {
                    if rest.hasPrefix(sub) && rest.count > sub.count {
                        // This looks like root + subscript (e.g., "gya" = g + y + a)
                        // Check if this prefix can actually take a subscript
                        let rootsWithSubscripts: Set<String> = ["k", "kh", "g", "p", "ph", "b", "m", "r", "l", "s", "h"]
                        if rootsWithSubscripts.contains(prefix) {
                            return nil  // Let it be parsed as root + subscript
                        }
                    }
                }
                // Check if what follows could be a valid root
                if startsWithConsonant(rest) {
                    return (prefix, rest)
                }
            }
        }
        return nil
    }

    private func extractSuperscript(from text: String) -> (String, String)? {
        // Superscripts: r, l, s
        // But "sh" is a digraph consonant, not superscript s + h
        let superscripts = ["r", "l", "s"]

        for sup in superscripts {
            if text.hasPrefix(sup) {
                let rest = String(text.dropFirst(sup.count))
                // Special case: "sh" is a single consonant, not s + h
                if sup == "s" && rest.hasPrefix("h") {
                    return nil
                }
                // Superscript must be followed by a root consonant
                if startsWithConsonant(rest) && !rest.isEmpty {
                    return (sup, rest)
                }
            }
        }
        return nil
    }

    private func extractConsonant(from text: String) -> (String, String)? {
        // Try longest matches first (tsh, dz, zh, sh, ng, ny, kh, ch, th, ph, ts)
        let consonants = [
            "tsh", "dz", "zh", "sh", "ng", "ny",
            "kh", "ch", "th", "ph", "ts",
            "k", "g", "c", "j", "t", "d", "n", "p", "b", "m",
            "w", "z", "y", "r", "l", "s", "h", "'", "a"
        ]

        for consonant in consonants {
            if text.hasPrefix(consonant) {
                let rest = String(text.dropFirst(consonant.count))
                return (consonant, rest)
            }
        }
        return nil
    }

    private func extractSubscript(from text: String) -> (String, String)? {
        // Subscripts: y, r, l, w (written as +y, +r, +l, +w in EWTS or just after root)
        let subscripts = ["+y", "+r", "+l", "+w", "y", "r", "l", "w"]

        for sub in subscripts {
            if text.hasPrefix(sub) {
                let rest = String(text.dropFirst(sub.count))
                let cleanSub = sub.hasPrefix("+") ? String(sub.dropFirst()) : sub
                return (cleanSub, rest)
            }
        }
        return nil
    }

    private func extractVowel(from text: String) -> (String, String)? {
        // Vowels: i, u, e, o (a is implicit/default)
        // Long vowels: I (ཱི), U (ཱུ)
        // Diphthongs: ai (ཻ), au (ཽ)
        // Include "a" to consume it, but it won't add a vowel sign
        // Order matters: check longer patterns first
        let vowels = ["ai", "au", "I", "U", "i", "u", "e", "o", "a"]

        for vowel in vowels {
            if text.hasPrefix(vowel) {
                let rest = String(text.dropFirst(vowel.count))
                return (vowel, rest)
            }
        }
        return nil
    }

    private func extractSuffix(from text: String) -> (String, String)? {
        // Suffixes: g, ng, d, n, b, m, ', r, l, s
        let suffixes = ["ng", "g", "d", "n", "b", "m", "'", "r", "l", "s"]

        for suffix in suffixes {
            if text.hasPrefix(suffix) {
                let rest = String(text.dropFirst(suffix.count))
                return (suffix, rest)
            }
        }
        return nil
    }

    private func extractPostSuffix(from text: String) -> (String, String)? {
        // Post-suffixes: d, s (only after certain suffixes)
        if text == "d" || text == "s" {
            return (text, "")
        }
        return nil
    }

    private func startsWithConsonant(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        // Note: "a" is NOT included here - it's a vowel carrier, not a consonant
        // that can follow a prefix. Prefixes must be followed by actual consonants.
        let consonantStarts = ["k", "g", "c", "j", "t", "d", "n", "p", "b", "m",
                               "ts", "dz", "w", "zh", "z", "'", "y", "r", "l",
                               "sh", "s", "h"]
        return consonantStarts.contains { text.hasPrefix($0) }
    }

    // MARK: - Unicode Building

    private func buildTibetanSyllable(from components: SyllableComponents) -> String {
        var result = ""

        // Add prefix
        if let prefix = components.prefix,
           let unicode = TibetanUnicode.wylieToUnicode[prefix] {
            result += unicode
        }

        // Add superscript (as regular letter, stacking happens automatically)
        if let superscript = components.superscript,
           let unicode = TibetanUnicode.wylieToUnicode[superscript] {
            result += unicode
        }

        // Add root consonant
        if components.root == "a" {
            // Standalone 'a' uses a-chung
            result += TibetanUnicode.wylieToUnicode["a"] ?? ""
        } else if let unicode = TibetanUnicode.wylieToUnicode[components.root] {
            // If there's a superscript, root becomes subjoined
            if components.superscript != nil {
                result += TibetanUnicode.subjoinedForms[components.root] ?? unicode
            } else {
                result += unicode
            }
        }

        // Add subscript (subjoined form)
        if let subLetter = components.subLetter,
           let unicode = TibetanUnicode.subjoinedForms[subLetter] {
            result += unicode
        }

        // Add vowel (if not 'a' which is implicit/inherent)
        // Long vowels (I, U, A) and diphthongs (ai, au) always produce output
        if let vowel = components.vowel, vowel != "a" {
            if let unicode = TibetanUnicode.wylieToUnicode[vowel] {
                result += unicode
            }
        }

        // Add suffix
        if let suffix = components.suffix,
           let unicode = TibetanUnicode.wylieToUnicode[suffix] {
            result += unicode
        }

        // Add post-suffix
        if let suffix2 = components.suffix2,
           let unicode = TibetanUnicode.wylieToUnicode[suffix2] {
            result += unicode
        }

        return result
    }
}

// MARK: - Convenience Extensions

extension WylieMapper {

    /// Convert with automatic tsheg at end
    public func convertWithTsheg(_ wylie: String) -> String {
        let result = convert(wylie)
        if !result.isEmpty && !result.hasSuffix(String(TibetanUnicode.tsheg)) {
            return result + String(TibetanUnicode.tsheg)
        }
        return result
    }

    /// Convert and add shad (sentence ending)
    public func convertSentence(_ wylie: String) -> String {
        let result = convert(wylie)
        return result + String(TibetanUnicode.shad)
    }
}
