// PhoneticMapper.swift
// LotsawaCore
//
// Converts phonetic romanization to Tibetan Unicode
// Example: "tashi" -> བཀྲ་ཤིས་
// Uses THL Simplified Phonetic conventions

import Foundation

/// Converts phonetic transliteration to Tibetan Unicode
public struct PhoneticMapper {

    // MARK: - Public Interface

    private let wylieMapper: WylieMapper
    private let languageMode: LanguageMode

    /// Shared SQLite-backed dictionary for phonetic lookups
    private var db: SQLiteDictionary { SQLiteDictionary.shared }

    public init(languageMode: LanguageMode = .tibetan) {
        self.languageMode = languageMode
        self.wylieMapper = WylieMapper()
    }

    /// Punctuation characters to strip and their Tibetan equivalents
    private static let punctuationMap: [Character: String] = [
        "?": "།",   // Question mark → shad
        "!": "།",   // Exclamation → shad
        ".": "།",   // Period → shad
        ",": "་",   // Comma → tsheg
        ";": "།",   // Semicolon → shad
        ":": "༔",   // Colon → gter tsheg (used in terma texts)
    ]

    /// Convert phonetic text to Tibetan Unicode
    /// - Parameter phonetic: Text in phonetic romanization (e.g., "tashi delek")
    /// - Returns: Tibetan Unicode string (e.g., "བཀྲ་ཤིས་བདེ་ལེགས་")
    public func convert(_ phonetic: String) -> String {
        let words = phonetic.lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var result: [String] = []
        var i = 0

        while i < words.count {
            // Strip trailing punctuation and convert it separately
            let (cleanWord, punctuation) = stripPunctuation(words[i])

            if cleanWord.isEmpty {
                // Word was only punctuation
                if let punct = punctuation {
                    result.append(punct)
                }
                i += 1
                continue
            }

            // Try multi-word phrase lookup (up to 5 words ahead)
            var matchedPhrase: String? = nil
            var matchedLen = 0
            let maxLookahead = min(5, words.count - i)
            for len in stride(from: maxLookahead, through: 2, by: -1) {
                let phraseWords = words[i..<(i+len)].map { w -> String in
                    let (clean, _) = stripPunctuation(w)
                    return clean
                }
                let phrase = phraseWords.joined(separator: " ")
                if let tibetanOptions = activeDictionary[phrase] {
                    matchedPhrase = tibetanOptions.first
                    matchedLen = len
                    break
                }
            }

            var tibetan: String
            if let phrase = matchedPhrase {
                tibetan = phrase
                // Handle punctuation from the last word of the phrase
                let (_, lastPunct) = stripPunctuation(words[i + matchedLen - 1])
                if let punct = lastPunct {
                    if punct == "།" && tibetan.hasSuffix("་") {
                        tibetan.removeLast()
                    }
                    tibetan += punct
                }
                result.append(tibetan)
                i += matchedLen
                continue
            } else if let converted = convertWord(cleanWord, useContext: false, useSQLite: false) {
                tibetan = converted
            } else {
                // Fallback: try syllable splitting then direct phonetic conversion
                // SQLite disabled to avoid contaminated entries overriding phonetic conversion
                tibetan = convertWithSyllableSplit(cleanWord, useSQLite: false)
            }

            // Append punctuation, removing trailing tsheg if punctuation is a shad
            if let punct = punctuation {
                if punct == "།" && tibetan.hasSuffix("་") {
                    tibetan.removeLast()  // Remove tsheg before shad
                }
                tibetan += punct
            }
            result.append(tibetan)
            i += 1
        }

        // Join with tsheg, but don't add tsheg after shad punctuation
        var output = ""
        for (i, word) in result.enumerated() {
            output += word
            // Add tsheg separator unless this word ends with shad/tsheg or is the last word
            if i < result.count - 1 && !word.hasSuffix("།") && !word.hasSuffix("༔") && !word.hasSuffix("་") {
                output += String(TibetanUnicode.tsheg)
            }
        }
        return output
    }

    /// Strip trailing punctuation from a word and return (cleanWord, tibetanPunctuation)
    private func stripPunctuation(_ word: String) -> (String, String?) {
        var cleanWord = word
        var punctuation: String? = nil

        // Check for trailing punctuation
        if let lastChar = cleanWord.last, Self.punctuationMap.keys.contains(lastChar) {
            punctuation = Self.punctuationMap[lastChar]
            cleanWord.removeLast()
        }

        return (cleanWord, punctuation)
    }

    /// Try to split a word into syllables and convert each
    private func convertWithSyllableSplit(_ word: String, useSQLite: Bool = true) -> String {
        // First try the word as-is (curated dict only when SQLite disabled)
        if let tibetan = convertWord(word, useSQLite: useSQLite) {
            return tibetan
        }

        // Try to find valid syllable splits
        if let split = findBestSyllableSplit(word, useSQLite: useSQLite) {
            return split
        }

        // Fallback: direct phonetic-to-syllable conversion
        return convertPhoneticSyllable(word)
    }

    /// Strip trailing tshegs from a Tibetan string
    private func stripTrailingTsheg(_ s: String) -> String {
        var result = s
        while result.hasSuffix("་") {
            result.removeLast()
        }
        return result
    }

    /// Find the best way to split a word into known syllables
    /// Uses curated dictionary (and optionally SQLite) for validation
    private func findBestSyllableSplit(_ word: String, useSQLite: Bool = true) -> String? {
        let n = word.count
        guard n >= 2 else { return nil }

        let tsheg = String(TibetanUnicode.tsheg)

        // Collect all valid 2-way splits with scores
        var candidates: [(result: String, score: Int)] = []

        for splitPos in 1..<n {
            let prefix = String(word.prefix(splitPos))
            let suffix = String(word.suffix(n - splitPos))

            // Try converting both parts
            if let prefixTibetan = convertWord(prefix, useSQLite: useSQLite),
               let suffixTibetan = convertWord(suffix, useSQLite: useSQLite) {
                let joined = stripTrailingTsheg(prefixTibetan) + tsheg + stripTrailingTsheg(suffixTibetan)
                // Boost score if found in curated dictionary
                let prefixCurated = activeDictionary[prefix] != nil ? 500 : 0
                let suffixCurated = activeDictionary[suffix] != nil ? 500 : 0
                var score = prefixCurated + suffixCurated
                if useSQLite {
                    let prefixFreq = db.lookupExact(phonetic: prefix).first?.frequency ?? 0
                    let suffixFreq = db.lookupExact(phonetic: suffix).first?.frequency ?? 0
                    score += prefixFreq + suffixFreq
                }
                candidates.append((joined, score))
            }
        }

        // Return the highest-scoring split
        if let best = candidates.max(by: { $0.score < $1.score }) {
            return best.result
        }

        // Try longer prefix first with recursive suffix splitting
        for splitPos in (1..<n).reversed() {
            let prefix = String(word.prefix(splitPos))
            let suffix = String(word.suffix(n - splitPos))

            if let prefixTibetan = convertWord(prefix, useSQLite: useSQLite) {
                if let suffixResult = findBestSyllableSplit(suffix, useSQLite: useSQLite) {
                    return stripTrailingTsheg(prefixTibetan) + tsheg + stripTrailingTsheg(suffixResult)
                }
            }
        }

        return nil
    }

    /// Find compound word suggestions by splitting input into multiple known words
    /// Returns multiple possible compound combinations
    /// Uses both curated dictionary and SQLite for validation
    private func findCompoundSuggestions(_ word: String) -> [String]? {
        let n = word.count
        guard n >= 6 else { return nil }  // Need at least 6 chars for compound

        let tsheg = String(TibetanUnicode.tsheg)
        var results: [String] = []

        // Helper: convert a part using curated dict or SQLite
        func convertPart(_ part: String) -> String? {
            if let options = activeDictionary[part] {
                return options.first
            }
            if let entry = db.lookupExact(phonetic: part).first {
                return entry.tibetan.trimmingCharacters(in: CharacterSet(charactersIn: "།༔"))
            }
            return nil
        }

        // Try splitting at each position (2-way splits)
        for splitPos in 3..<(n - 2) {
            let prefix = String(word.prefix(splitPos))
            let suffix = String(word.suffix(n - splitPos))

            // Check if both parts are valid words in curated dict or trie
            if let p = convertPart(prefix), let s = convertPart(suffix) {
                let compound = stripTrailingTsheg(p) + tsheg + stripTrailingTsheg(s)
                if !results.contains(compound) {
                    results.append(compound)
                }
            }
        }

        // Try 3-way splits for longer words (e.g., "khyedemoyin" -> "khye" + "demo" + "yin")
        if n >= 8 {
            for splitPos1 in 2..<(n - 4) {
                for splitPos2 in (splitPos1 + 2)..<(n - 1) {
                    let part1 = String(word.prefix(splitPos1))
                    let part2 = String(word.dropFirst(splitPos1).prefix(splitPos2 - splitPos1))
                    let part3 = String(word.suffix(n - splitPos2))

                    if let p1 = convertPart(part1), let p2 = convertPart(part2), let p3 = convertPart(part3) {
                        let compound = stripTrailingTsheg(p1) + tsheg + stripTrailingTsheg(p2) + tsheg + stripTrailingTsheg(p3)
                        if !results.contains(compound) {
                            results.append(compound)
                        }
                    }
                }
            }
        }

        return results.isEmpty ? nil : results
    }

    /// Get possible Tibetan matches for a phonetic input
    /// - Parameter phonetic: Phonetic input string
    /// - Parameter useContext: Whether to apply context-based re-ranking (default: true)
    /// - Returns: Array of possible Tibetan matches, ranked by frequency and context
    public func getSuggestions(for phonetic: String, useContext: Bool = true) -> [String] {
        let normalized = phonetic.lowercased()
        var matches: [(String, Int)] = []  // (tibetan, frequency)
        var seen = Set<String>()

        // Helper to add unique matches with frequency
        func addMatch(_ tibetan: String, freq: Int = 100) {
            if !seen.contains(tibetan) {
                matches.append((tibetan, freq))
                seen.insert(tibetan)
            }
        }

        // 0. Pure phonetic transliteration (always show as first option)
        let phoneticResult = convertPhoneticSyllable(normalized)
        if !phoneticResult.isEmpty && phoneticResult != normalized {
            addMatch(phoneticResult, freq: 1500)
        }

        // 1. Check exact matches in curated dictionary (high priority)
        if let exact = activeDictionary[normalized] {
            for (i, word) in exact.enumerated() {
                addMatch(word, freq: 1000 - i * 10)  // Curated gets high priority
            }
        }

        // 2. Use SQLite for fast exact matching (sorted by frequency, capped at 800)
        let dbResults = db.lookupExact(phonetic: normalized)
        for entry in dbResults.prefix(20) {
            addMatch(stripTrailingTsheg(entry.tibetan), freq: min(entry.frequency, 800))
        }

        // 3. Semantic hints (demoted - helps with context but doesn't override)
        if useContext, let semanticHint = ContextEngine.shared.getSemanticHint(for: normalized) {
            addMatch(semanticHint, freq: 700)
        }

        // 4. Compound word splitting (only for longer inputs)
        if matches.isEmpty && normalized.count >= 6 {
            if let compoundSuggestions = findCompoundSuggestions(normalized) {
                for (i, compound) in compoundSuggestions.enumerated() {
                    addMatch(compound, freq: 600 - i * 10)
                }
            }
        }

        // 2.5. Use SQLite prefix matching for partial inputs
        if matches.count < 5 {
            let prefixResults = db.lookupPrefix(phonetic: normalized, limit: 10)
            for entry in prefixResults {
                addMatch(stripTrailingTsheg(entry.tibetan), freq: entry.frequency - 200)
            }
        }

        // 3. Use fuzzy matching with phonetic similarity via SQLite
        if matches.count < 5 {
            // Try dialect and typo variations against SQLite
            let dialectVariations = PhoneticFuzzyMatcher.generateDialectVariations(normalized)
            for variation in dialectVariations {
                for entry in db.lookupExact(phonetic: variation) {
                    addMatch(stripTrailingTsheg(entry.tibetan), freq: entry.frequency - 50)
                }
            }
        }

        // 3.5. Try typo corrections (transpositions, missing vowels, etc.)
        if matches.count < 5 {
            let typoVariations = PhoneticFuzzyMatcher.generateTypoVariations(normalized)
            for variation in typoVariations {
                // Check curated dictionary
                if let values = activeDictionary[variation] {
                    for (i, word) in values.enumerated() {
                        addMatch(word, freq: 600 - i * 10)  // Good priority for typo corrections
                    }
                }
                // Check SQLite
                let dbVariationResults = db.lookupExact(phonetic: variation)
                for entry in dbVariationResults.prefix(5) {
                    addMatch(stripTrailingTsheg(entry.tibetan), freq: entry.frequency - 100)
                }
            }
        }

        // 4. Fallback: check phonetic variations in curated dictionary
        if matches.count < 5 {
            let variations = generateVariations(normalized)
            for variation in variations {
                if let values = activeDictionary[variation] {
                    for (i, word) in values.enumerated() {
                        addMatch(word, freq: 500 - i * 10)
                    }
                }
            }
        }

        // 5. Apply user preference weights
        var weightedMatches = matches.map { (tibetan, freq) -> (String, Int) in
            let userWeight = UserLearningStore.shared.getWeight(phonetic: normalized, tibetan: tibetan)
            let adjustedFreq = Int(Double(freq) * userWeight)
            return (tibetan, adjustedFreq)
        }

        // 6. Apply ML-boosted scoring if model is loaded
        if MLPredictor.shared.isModelLoaded {
            weightedMatches = weightedMatches.map { (tibetan, freq) -> (String, Int) in
                let mlBoost = MLPredictor.shared.getConfidenceBoost(
                    tibetan: tibetan,
                    phonetic: normalized,
                    context: ContextEngine.shared.currentContext
                )
                let adjustedFreq = Int(Double(freq) * mlBoost)
                return (tibetan, adjustedFreq)
            }
        }

        // 7. Apply context-based re-ranking if enabled
        var finalMatches = weightedMatches
        if useContext && ContextEngine.shared.isLoaded {
            finalMatches = ContextEngine.shared.rankWithContext(weightedMatches)
        }

        // 8. Check if user has a preferred word for this input
        if let preferred = UserLearningStore.shared.getPreferred(for: normalized) {
            // Move preferred to front if it exists in matches
            if let idx = finalMatches.firstIndex(where: { $0.0 == preferred }) {
                let item = finalMatches.remove(at: idx)
                finalMatches.insert(item, at: 0)
            }
        }

        // 9. Pin phonetic transliteration to first position (re-ranking may have moved it)
        if !phoneticResult.isEmpty && phoneticResult != normalized {
            if let idx = finalMatches.firstIndex(where: { $0.0 == phoneticResult }) {
                let item = finalMatches.remove(at: idx)
                finalMatches.insert(item, at: 0)
            }
        }

        return Array(finalMatches.prefix(10).map { $0.0 })
    }

    /// Get suggestions with context from previous words
    /// - Parameter phonetic: Current phonetic input
    /// - Parameter previousWords: Previously typed Tibetan words for context
    /// - Returns: Context-ranked suggestions
    public func getSuggestionsWithContext(for phonetic: String, previousWords: [String]) -> [String] {
        // Update context engine with previous words
        ContextEngine.shared.clearContext()
        for word in previousWords.suffix(5) {  // Use last 5 words (increased from 3)
            ContextEngine.shared.addToContext(word)
        }

        return getSuggestions(for: phonetic, useContext: true)
    }

    /// Get suggestions with confidence information for UI display
    /// - Parameter phonetic: The phonetic input to get suggestions for
    /// - Returns: Array of (tibetan, confidence, shouldHighlight) tuples
    public func getSuggestionsWithConfidence(for phonetic: String) -> [(String, Double, Bool)] {
        let normalized = phonetic.lowercased()
        var matches: [(String, Int)] = []
        var seen = Set<String>()

        // Helper to add unique matches with frequency
        func addMatch(_ tibetan: String, freq: Int = 100) {
            if !seen.contains(tibetan) {
                matches.append((tibetan, freq))
                seen.insert(tibetan)
            }
        }

        // 1. Check exact matches in curated dictionary first
        if let exact = activeDictionary[normalized] {
            for (i, word) in exact.enumerated() {
                addMatch(word, freq: 1000 - i * 10)
            }
        }

        // 2. Use SQLite for fast exact matching
        let dbResults = db.lookupExact(phonetic: normalized)
        for entry in dbResults.prefix(20) {
            addMatch(stripTrailingTsheg(entry.tibetan), freq: entry.frequency)
        }

        // 3. Use fuzzy matching with phonetic similarity via SQLite
        if matches.count < 5 {
            let dialectVariations = PhoneticFuzzyMatcher.generateDialectVariations(normalized)
            for variation in dialectVariations {
                for entry in db.lookupExact(phonetic: variation) {
                    addMatch(stripTrailingTsheg(entry.tibetan), freq: entry.frequency - 50)
                }
            }
            let typoVariations = PhoneticFuzzyMatcher.generateTypoVariations(normalized)
            for variation in typoVariations {
                for entry in db.lookupExact(phonetic: variation).prefix(5) {
                    addMatch(stripTrailingTsheg(entry.tibetan), freq: entry.frequency - 50)
                }
            }
        }

        // 4. Fallback: check phonetic variations
        if matches.count < 5 {
            let variations = generateVariations(normalized)
            for variation in variations {
                if let values = activeDictionary[variation] {
                    for (i, word) in values.enumerated() {
                        addMatch(word, freq: 500 - i * 10)
                    }
                }
            }
        }

        // Get confidence scores and check for auto-select
        let ranked = ContextEngine.shared.rankWithConfidence(matches)
        let (autoSelect, bestChoice) = ContextEngine.shared.shouldAutoSelect(matches)

        return ranked.prefix(10).map { (tibetan, _, confidence) in
            let shouldHighlight = autoSelect && tibetan == bestChoice
            return (tibetan, confidence, shouldHighlight)
        }
    }

    // MARK: - Word Conversion

    /// Convert a phonetic word to Tibetan, using context for disambiguation
    /// - Parameters:
    ///   - word: The phonetic word to convert
    ///   - useContext: Whether to use context for disambiguation (default: true)
    /// - Returns: The best Tibetan match, or nil if no match found
    private func convertWord(_ word: String, useContext: Bool = true, useSQLite: Bool = true) -> String? {
        // Check curated dictionary first
        if let tibetanOptions = activeDictionary[word] {
            // Single option: return directly
            if tibetanOptions.count == 1 {
                return tibetanOptions.first
            }

            // Multiple options: use context to choose
            if useContext && ContextEngine.shared.isLoaded {
                return selectBestOption(from: tibetanOptions, for: word)
            }

            return tibetanOptions.first
        }

        // Then use SQLite for fast lookup (only when enabled — disabled in convert() to avoid garbage)
        if useSQLite {
            let dbMatches = db.lookupExact(phonetic: word)
            if !dbMatches.isEmpty {
                if dbMatches.count > 1 && useContext && ContextEngine.shared.isLoaded {
                    let options = dbMatches.map { $0.tibetan }
                    if let best = selectBestOption(from: options, for: word) {
                        return stripTrailingTsheg(best.trimmingCharacters(in: CharacterSet(charactersIn: "།༔")))
                    }
                }
                if let best = dbMatches.first {
                    return stripTrailingTsheg(best.tibetan.trimmingCharacters(in: CharacterSet(charactersIn: "།༔")))
                }
            }
        }

        // Use semantic hints to help disambiguate (demoted from first position)
        if useContext, let hint = ContextEngine.shared.getSemanticHint(for: word) {
            return hint
        }

        // Check phonetic variations (curated dictionary only)
        let variations = generateVariations(word)
        for variation in variations {
            if let tibetanOptions = activeDictionary[variation] {
                if tibetanOptions.count > 1 && useContext && ContextEngine.shared.isLoaded {
                    if let best = selectBestOption(from: tibetanOptions, for: variation) {
                        return stripTrailingTsheg(best)
                    }
                }
                if let first = tibetanOptions.first {
                    return stripTrailingTsheg(first)
                }
            }
            if useSQLite {
                let dbVariation = db.lookupExact(phonetic: variation)
                if let best = dbVariation.first {
                    return stripTrailingTsheg(best.tibetan.trimmingCharacters(in: CharacterSet(charactersIn: "།༔")))
                }
            }
        }

        return nil
    }

    /// Select the best option from multiple Tibetan candidates using context
    /// - Parameters:
    ///   - options: Array of possible Tibetan words
    ///   - phonetic: The original phonetic input (for debugging)
    /// - Returns: The best option based on context scoring
    private func selectBestOption(from options: [String], for phonetic: String) -> String? {
        guard !options.isEmpty else { return nil }
        guard options.count > 1 else { return options.first }

        // Score each option using context
        let scored = options.enumerated().map { (index, tibetan) -> (String, Double) in
            let contextScore = ContextEngine.shared.scoreWithContext(tibetan)
            // Add position bias: first entry (curated default) gets slight boost
            let positionBonus = 1.0 + Double(options.count - index) * 0.05
            return (tibetan, contextScore * positionBonus)
        }

        // Return the highest scoring option
        return scored.max(by: { $0.1 < $1.1 })?.0 ?? options.first
    }

    /// Generate common spelling variations
    private func generateVariations(_ word: String) -> [String] {
        var variations: [String] = []

        // Common phonetic variations
        let replacements: [(String, String)] = [
            ("sh", "s"),
            ("ch", "c"),
            ("th", "t"),
            ("ph", "p"),
            ("kh", "k"),
            ("ee", "i"),
            ("oo", "u"),
            ("ay", "e"),
            ("ai", "e"),
            ("ey", "e"),
            ("ou", "o"),
            ("oe", "ö"),
            ("ue", "ü"),
        ]

        let current = word
        for (from, to) in replacements {
            if current.contains(from) {
                let replaced = current.replacingOccurrences(of: from, with: to)
                if replaced != current {
                    variations.append(replaced)
                }
            }
        }

        return variations
    }

    // MARK: - Direct Phonetic Conversion

    /// Convert a phonetic syllable directly using phoneme mapping
    /// This is the fallback when word isn't in dictionary
    private func convertPhoneticSyllable(_ syllable: String) -> String {
        // First try to convert phonetic to approximate Wylie, then to Tibetan
        let wylie = phoneticToWylie(syllable)
        let result = self.wylieMapper.convertSyllable(wylie)

        // If Wylie conversion worked, return it
        if !result.isEmpty && result != wylie {
            return result
        }

        // Fallback: direct phoneme mapping
        var remaining = syllable
        var output = ""

        // Insert achung (vowel carrier) for vowel-initial syllables
        let vowelChars: Set<Character> = ["a", "e", "i", "o", "u", "ö", "ü"]
        if let first = remaining.first, vowelChars.contains(first) {
            output += "\u{0F68}" // ཨ achung (vowel carrier)
        }

        // Extract initial consonant cluster
        if let (consonant, rest) = extractPhoneticConsonant(from: remaining) {
            if let unicode = phoneticConsonants[consonant] {
                output += unicode
            }
            remaining = rest
        }

        // Extract vowel
        if let (vowel, rest) = extractPhoneticVowel(from: remaining) {
            if vowel != "a", let unicode = phoneticVowels[vowel] {
                output += unicode
            }
            remaining = rest
        }

        // Extract final consonant
        if !remaining.isEmpty {
            if let unicode = phoneticFinals[remaining] {
                output += unicode
            }
        }

        return output.isEmpty ? syllable : output
    }

    /// Convert phonetic spelling to approximate Wylie
    /// This handles common phonetic patterns
    private func phoneticToWylie(_ phonetic: String) -> String {
        var result = phonetic.lowercased()

        // Phonetic → Wylie conversion rules
        // These are approximations based on THL phonetic conventions

        // Aspirated consonants
        result = result.replacingOccurrences(of: "tsh", with: "tsh")

        // Common phonetic patterns → Wylie
        // "ky" often represents "skye" or "khy" in Wylie
        if result.hasPrefix("ky") && !result.hasPrefix("khy") {
            // Could be skye or khye - try khye first for common words
            result = "khy" + result.dropFirst(2)
        }

        // "gy" often represents "rgya" or "gya"
        if result.hasPrefix("gy") && !result.hasPrefix("rgy") {
            result = "rgy" + result.dropFirst(2)
        }

        // "tr" is often "sgr" or "dr"
        if result.hasPrefix("tr") {
            result = "sgr" + result.dropFirst(2)
        }

        // "dr" stays as "dr" or could be "sgr"
        // "ng" at start often has prefix
        if result.hasPrefix("ng") && result.count > 2 {
            // Keep as is - ng is valid start
        }

        // "ny" stays as "ny"

        // Vowel adjustments
        result = result.replacingOccurrences(of: "oe", with: "o")
        result = result.replacingOccurrences(of: "ue", with: "u")
        result = result.replacingOccurrences(of: "ee", with: "i")
        result = result.replacingOccurrences(of: "oo", with: "u")
        result = result.replacingOccurrences(of: "ay", with: "e")
        result = result.replacingOccurrences(of: "ai", with: "e")

        // Final consonants - phonetic often drops them or changes them
        // "k" at end often represents "g" in Wylie
        // "p" at end often represents "b" in Wylie

        return result
    }

    private func extractPhoneticConsonant(from text: String) -> (String, String)? {
        // Try longest matches first
        let consonants = ["tsh", "dzh", "ngh", "nyh",
                         "ch", "sh", "zh", "th", "ph", "kh", "ts", "dz", "ng", "ny",
                         "k", "g", "c", "j", "t", "d", "n", "p", "b", "m",
                         "w", "z", "y", "r", "l", "s", "h"]

        for consonant in consonants {
            if text.hasPrefix(consonant) {
                return (consonant, String(text.dropFirst(consonant.count)))
            }
        }
        return nil
    }

    private func extractPhoneticVowel(from text: String) -> (String, String)? {
        let vowels = ["ee", "oo", "ai", "ei", "ou", "ö", "ü", "i", "u", "e", "o", "a"]

        for vowel in vowels {
            if text.hasPrefix(vowel) {
                return (vowel, String(text.dropFirst(vowel.count)))
            }
        }

        // Implicit 'a'
        if !text.isEmpty && !text.first!.isLetter {
            return ("a", text)
        }

        return ("a", text) // Default implicit vowel
    }

    // MARK: - Phonetic Mappings

    /// Phonetic consonant to Tibetan Unicode
    private let phoneticConsonants: [String: String] = [
        "k": "\u{0F40}",
        "kh": "\u{0F41}",
        "g": "\u{0F42}",
        "ng": "\u{0F44}",
        "c": "\u{0F45}",
        "ch": "\u{0F46}",
        "j": "\u{0F47}",
        "ny": "\u{0F49}",
        "t": "\u{0F4F}",
        "th": "\u{0F50}",
        "d": "\u{0F51}",
        "n": "\u{0F53}",
        "p": "\u{0F54}",
        "ph": "\u{0F55}",
        "b": "\u{0F56}",
        "m": "\u{0F58}",
        "ts": "\u{0F59}",
        "tsh": "\u{0F5A}",
        "dz": "\u{0F5B}",
        "w": "\u{0F5D}",
        "zh": "\u{0F5E}",
        "z": "\u{0F5F}",
        "y": "\u{0F61}",
        "r": "\u{0F62}",
        "l": "\u{0F63}",
        "sh": "\u{0F64}",
        "s": "\u{0F66}",
        "h": "\u{0F67}",
    ]

    /// Phonetic vowel to Tibetan vowel sign
    private let phoneticVowels: [String: String] = [
        "i": "\u{0F72}",
        "ee": "\u{0F72}",
        "u": "\u{0F74}",
        "oo": "\u{0F74}",
        "e": "\u{0F7A}",
        "ai": "\u{0F7A}",
        "ei": "\u{0F7A}",
        "o": "\u{0F7C}",
        "ou": "\u{0F7C}",
        "ö": "\u{0F7A}",  // Approximate
        "ü": "\u{0F72}",  // Approximate
    ]

    /// Phonetic final consonants
    private let phoneticFinals: [String: String] = [
        "k": "\u{0F42}",   // final -k often written as ག
        "ng": "\u{0F44}",
        "n": "\u{0F53}",
        "m": "\u{0F58}",
        "p": "\u{0F56}",   // final -p often written as བ
        "r": "\u{0F62}",
        "l": "\u{0F63}",
        "s": "\u{0F66}",
    ]

    // MARK: - Phonetic Dictionary

    /// Shared dictionary mapping phonetic spellings to Tibetan words
    /// Contains entries common to both Tibetan and Dzongkha modes
    /// Multiple Tibetan options for homophones (disambiguation needed)
    private static let sharedDictionary: [String: [String]] = [
        // Greetings
        "tashi": ["བཀྲ་ཤིས"],
        "tashe": ["བཀྲ་ཤིས"],
        "tashee": ["བཀྲ་ཤིས"],
        "delek": ["བདེ་ལེགས"],
        "deleg": ["བདེ་ལེགས"],
        // Common words
        "khamzang": ["ཁམས་བཟང"],
        "kamsang": ["ཁམས་བཟང"],
        "gongda": ["དགོངས་དག"],
        "gongdak": ["དགོངས་དག"],

        // Food & Drink
        "khalak": ["ཁ་ལག"],      // food
        "kha lag": ["ཁ་ལག"],
        "kha lak": ["ཁ་ལག"],
        "khalag": ["ཁ་ལག"],
        "ja": ["ཇ"],              // tea
        "cha": ["ཇ", "ཆ"],        // tea (also letter cha)
        // "chang" moved to General Terms section
        // "chu" moved to Numbers section (water + 10)
        "sha": ["ཤ"],             // meat
        "tse": ["ཚེ", "རྩེ"],     // life / peak
        "tsampa": ["རྩམ་པ"],      // tsampa
        "mar": ["མར"],            // butter
        "thuk": ["ཐུག"],          // soup/thukpa
        "thukpa": ["ཐུག་པ"],      // noodle soup
        "momo": ["མོག་མོག"],      // dumplings

        // Common verbs - PRIORITY ORDER MATTERS
        "za": ["ཟ"],              // eat
        "thung": ["འཐུང"],        // drink
        "tung": ["འཐུང"],
        "dro": ["འགྲོ"],          // go
        "yong": ["ཡོང"],          // come
        "de": ["དེ", "འདུག", "བསྡད"],   // that / sit/stay
        "duk": ["འདུག"],          // is/are (existential)
        "yoe": ["ཡོད"],           // have/exist
        "yö": ["ཡོད"],
        "yo": ["ཡོད"],
        "yin": ["ཡིན"],           // is (equative)
        "ma yin": ["མ་ཡིན"],      // is not
        // "me" moved to Nature section (fire + not exist)
        "mé": ["མེད"],
        "re": ["རེ", "རེད"],      // question particle FIRST, then "is"
        "ray": ["རེད"],
        "maray": ["མ་རེད"],       // is not (factual)
        "ma re": ["མ་རེད"],
        "je": ["བྱེད", "རྗེ"],    // do/make FIRST, then lord
        "jé": ["བྱེད", "རྗེ"],
        "jey": ["བྱེད"],
        "jay": ["བྱེད"],
        // "che" moved to below (big/do)
        "nang": ["ནང", "གནང"],    // inside / give (honorific)
        "ter": ["སྟེར"],          // give
        "len": ["ལེན"],           // take/receive
        "ta": ["ལྟ"],             // look
        "nyen": ["ཉན"],           // listen
        "lap": ["བསླབ", "ལབ"],   // say/tell
        "lab": ["ལབ"],
        "she": ["ཤེས"],           // know
        "shé": ["ཤེས"],
        "go": ["གོ"],             // understand
        "gor": ["འགོར"],          // take time
        "tsong": ["ཚོང"],         // sell
        "nyo": ["ཉོ"],            // buy

        // Question words - HIGH PRIORITY
        "gare": ["ག་རེ"],         // what
        "ga re": ["ག་རེ"],
        "kare": ["ག་རེ"],
        "ga": ["ག"],              // letter ga (use "gare" or "ga re" for "what")
        "su": ["སུ"],             // who
        "gang": ["གང"],           // which/what
        "gana": ["ག་ན"],          // where
        "ga na": ["ག་ན"],
        "kana": ["ག་ན"],
        "gadu": ["ག་དུས"],        // when
        "ga du": ["ག་དུས"],
        "gatso": ["ག་ཚོད"],       // how much
        "ga tso": ["ག་ཚོད"],
        "gapé": ["ག་པར"],         // where (literary)
        "karé": ["བཀའ་རེ"],       // what (honorific)

        // Dharma terms
        "sangye": ["སངས་རྒྱས"],
        "sanggye": ["སངས་རྒྱས"],
        "sangay": ["སངས་རྒྱས"],
        "cho": ["ཆོས"],
        "chö": ["ཆོས"],
        "chos": ["ཆོས"],
        // "choe" moved to Pronouns section (Bhutanese "you" first, then "dharma")
        "gendun": ["དགེ་འདུན"],
        "gendün": ["དགེ་འདུན"],
        "lama": ["བླ་མ"],
        "la ma": ["བླ་མ"],
        "konchok": ["དཀོན་མཆོག"],
        "könchok": ["དཀོན་མཆོག"],
        "könchog": ["དཀོན་མཆོག"],
        "le": ["ལས"],
        "trinle": ["འཕྲིན་ལས"],
        "drubpa": ["སྒྲུབ་པ"],
        "druppa": ["སྒྲུབ་པ"],
        "nyamlen": ["ཉམས་ལེན"],
        "gompa": ["སྒོམ་པ", "དགོན་པ"],  // meditation or monastery
        "gom": ["སྒོམ"],
        "chepa": ["སྤྱད་པ"],
        "che": ["ཆེ", "བྱེད", "ལྕེ"],  // big / do-make / tongue
        "chung": ["ཆུང"],
        "gyalwa": ["རྒྱལ་བ"],
        "gyelwa": ["རྒྱལ་བ"],

        // Mind/consciousness
        "sem": ["སེམས"],
        "sems": ["སེམས"],
        "rigpa": ["རིག་པ"],
        "rikpa": ["རིག་པ"],
        "yeshe": ["ཡེ་ཤེས"],
        "yeshi": ["ཡེ་ཤེས"],

        // Concepts
        "tongpa": ["སྟོང་པ"],
        "tongpanyi": ["སྟོང་པ་ཉིད"],
        "tongpanyid": ["སྟོང་པ་ཉིད"],
        "nyingje": ["སྙིང་རྗེ"],
        "nyinje": ["སྙིང་རྗེ"],
        "dorje": ["རྡོ་རྗེ"],
        "dorjé": ["རྡོ་རྗེ"],
        "khyepar": ["ཁྱད་པར"],
        "khyepe": ["ཁྱད་པར"],
        "kyepar": ["ཁྱད་པར"],
        "gachi": ["ག་ཅི", "དགའ་ཆེ"],  // what / very happy
        "kachi": ["ག་ཅི"],
        // "gare", "kare", "gang" already defined in Question words section
        "gawa": ["དགའ་བ"],
        "kyewa": ["སྐྱེ་བ"],
        "chiwa": ["འཆི་བ"],
        "dukngal": ["སྡུག་བསྔལ"],
        "dewa": ["བདེ་བ"],
        "dechen": ["བདེ་ཆེན"],   // great bliss
        "demo": ["བདེ་མོ"],
        "depo": ["བདེ་པོ"],
        "dekyi": ["བདེ་སྐྱིད"],
        "skyid": ["སྐྱིད"],
        "denpa": ["བདེན་པ"],
        "zungjuk": ["ཟུང་འཇུག"],
        "nangwa": ["སྣང་བ"],
        "tokpa": ["རྟོགས་པ"],
        "togpa": ["རྟོགས་པ"],
        "shepa": ["ཤེས་པ"],
        "sherab": ["ཤེས་རབ"],
        "sherap": ["ཤེས་རབ"],
        "thab": ["ཐབས"],
        "tab": ["ཐབས"],
        "tabshe": ["ཐབས་ཤེས"],

        // Homophones (multiple options - needs disambiguation)
        "dak": ["བདག", "དག"],      // བདག = self, དག = pure
        "dag": ["བདག", "དག"],
        "la": ["ལ", "བླ"],          // ལ = particle, བླ = life/soul
        "pa": ["པ", "དཔའ"],         // པ = nominalizer, དཔའ = brave
        "pe": ["པའི"],
        "po": ["པོ"],

        // Numbers
        "chik": ["གཅིག"],
        "chig": ["གཅིག"],
        "nyi": ["གཉིས", "ཉི"],      // two / sun
        "nyee": ["གཉིས"],
        "sum": ["གསུམ"],
        "shi": ["བཞི"],
        "shee": ["བཞི"],
        "nga": ["ང", "ལྔ"],    // ང = I (pronoun), ལྔ = 5 (number) - homophone
        "druk": ["དྲུག", "འབྲུག"],  // དྲུག = 6, འབྲུག = Bhutan - homophone
        "dün": ["བདུན"],
        "dun": ["བདུན"],
        "gye": ["བརྒྱད"],
        "gu": ["དགུ"],
        "chu": ["བཅུ", "ཆུ"],  // བཅུ = 10, ཆུ = water - homophone

        // Pronouns - IMPORTANT: ཁྱེད་ (you) not མཁས་ (scholar)
        "khye": ["ཁྱེད"],
        "khe": ["ཁྱེད"],         // common variant
        "khyed": ["ཁྱེད"],
        "khyö": ["ཁྱོད"],
        "khyo": ["ཁྱོད"],
        "khyod": ["ཁྱོད"],
        "khyerang": ["ཁྱེད་རང"],
        "khye rang": ["ཁྱེད་རང"],
        "kho": ["ཁོ"],
        "khorang": ["ཁོ་རང"],
        "morang": ["མོ་རང"],
        "rang": ["རང"],

        // Common particles
        "gi": ["གི"],
        "gyi": ["གྱི"],
        "kyi": ["ཀྱི", "སྐྱིད"],  // particle or happiness
        "yi": ["ཡི"],
        "ni": ["ནི"],
        "na": ["ན"],
        "du": ["དུ"],
        "tu": ["ཏུ"],
        "ru": ["རུ"],
        // "su" already defined in Question words section (who)

        // Honorifics
        "rinpoche": ["རིན་པོ་ཆེ"],
        "rinpoché": ["རིན་པོ་ཆེ"],
        "khenpo": ["མཁན་པོ"],
        "kenpo": ["མཁན་པོ"],
        "tulku": ["སྤྲུལ་སྐུ"],
        "trulku": ["སྤྲུལ་སྐུ"],

        // Places
        "bod": ["བོད"],          // Tibet
        "lhasa": ["ལྷ་ས"],
        // "druk" already defined above as homophone (6/Bhutan)
        "drukyul": ["འབྲུག་ཡུལ"],

        // Bare vowels
        "o": ["ཨོ"],
        "a": ["ཨ"],
        "e": ["ཨེ"],
        "i": ["ཨི"],
        "u": ["ཨུ"],

        // Religious terms
        "om": ["ཨོཾ"],
        "mani": ["མ་ནི"],
        "peme": ["པདྨེ"],
        "padme": ["པདྨེ"],
        "pema": ["པདྨ", "པད་མ"],
        "padma": ["པདྨ"],
        "hung": ["ཧཱུྃ"],
        "hum": ["ཧཱུྃ"],
        "ah": ["ཨཿ"],
        "hrih": ["ཧྲཱིཿ"],
        "hri": ["ཧྲཱི"],
        "tam": ["ཏཱྃ"],
        "bam": ["བཾ"],
        "dzam": ["ཛཾ"],

        // Common names
        "tenzin": ["བསྟན་འཛིན"],
        "tendzin": ["བསྟན་འཛིན"],
        "lobsang": ["བློ་བཟང"],
        "losang": ["བློ་བཟང"],
        "norbu": ["ནོར་བུ"],
        "wangchuk": ["དབང་ཕྱུག"],
        "wangchug": ["དབང་ཕྱུག"],
        "gyaltsen": ["རྒྱལ་མཚན"],
        "gyeltsen": ["རྒྱལ་མཚན"],
        "jampa": ["བྱམས་པ"],
        "champa": ["བྱམས་པ"],
        "sonam": ["བསོད་ནམས"],
        "karma": ["ཀརྨ", "ལས"],
        "tsering": ["ཚེ་རིང"],
        "dolma": ["སྒྲོལ་མ"],
        "drolma": ["སྒྲོལ་མ"],
        "jigme": ["འཇིགས་མེད"],
        "jikme": ["འཇིགས་མེད"],
        "choden": ["ཆོས་ལྡན"],
        "choeden": ["ཆོས་ལྡན"],
        "yangchen": ["དབྱངས་ཅན"],
        "kunzang": ["ཀུན་བཟང"],
        "kunsang": ["ཀུན་བཟང"],
        "dorji": ["རྡོ་རྗེ"],
        "ugyen": ["ཨོ་རྒྱན"],
        "orgyen": ["ཨོ་རྒྱན"],

        // Nature
        "nam": ["གནམ"],         // sky
        "sa": ["ས"],            // earth
        // "chu" already defined above as homophone (10/water)
        "me": ["མེ", "མེད"],    // fire / not exist
        "lung": ["རླུང"],       // wind
        "ri": ["རི"],           // mountain
        "tso": ["མཚོ"],         // lake

        // Time
        "deng": ["དེང"],        // today
        "dangpo": ["དང་པོ"],    // first
        "nyin": ["ཉིན"],        // day
        "tsen": ["མཚན"],        // night
        "lo": ["ལོ"],           // year
        "da": ["ད"],            // month
        "zla": ["ཟླ"],          // month (formal)

        // ============================================
        // HIGH-FREQUENCY WORDS FROM CORPUS ANALYSIS
        // ============================================

        // Particles & Connectors (very common)
        "dang": ["དང"],          // and
        "pi": ["པའི"],           // genitive particle
        "ba": ["བ"],             // nominalizer
        "par": ["པར"],           // locative
        "mey": ["མེད"],          // not exist
        "med": ["མེད"],
        "due": ["དུ"],           // locative particle
        "neyy": ["ནས", "གནས"],  // from / place
        "ney": ["ནས", "གནས"],
        "nes": ["ནས"],
        "pé": ["པས"],            // instrumental
        // DUPLICATE: "pe": ["པས"],
        "béy": ["བས"],
        "be": ["བས"],
        "sü": ["སུ"],            // locative
        "rü": ["རུ"],
        "tü": ["ཏུ"],

        // Common Nouns
        "kuen": ["ཀུན"],         // all
        "kun": ["ཀུན"],
        "chén": ["ཆེན"],         // great
        "chen": ["ཆེན"],
        "sol": ["གསོལ"],         // prayer/request
        "gyal": ["རྒྱལ"],        // king/victory
        "gyalpo": ["རྒྱལ་པོ"],   // king
        "suem": ["གསུམ"],        // three
        // DUPLICATE: "sum": ["གསུམ"],
        // DUPLICATE: "thuk": ["ཐུགས"],        // mind (honorific)
        "thuks": ["ཐུགས"],
        "chok": ["མཆོག", "ཕྱོགས"], // supreme / direction
        "bar": ["བར"],           // between/gap
        "kue": ["སྐུ"],          // body (honorific)
        "ku": ["སྐུ"],
        "sém": ["སེམས"],         // mind
        // DUPLICATE: "sem": ["སེམས"],
        "bang": ["དབང"],         // power
        "wang": ["དབང"],
        "tsok": ["ཚོགས"],        // assembly/gathering
        "tsog": ["ཚོགས"],
        "dam": ["དམ"],           // sacred/oath
        "dzin": ["འཛིན"],        // hold/grasp
        "jin": ["བྱིན"],         // blessing
        "oey": ["འོད"],          // light
        "ö": ["འོད"],
        "od": ["འོད"],
        "peyl": ["དཔལ"],         // glory
        "pal": ["དཔལ"],
        "pel": ["དཔལ"],
        "lha": ["ལྷ"],           // deity
        "nying": ["སྙིང"],       // heart/essence
        // DUPLICATE: "nang": ["སྣང", "གནང"], // appearance / give (hon)
        "don": ["དོན"],          // meaning/purpose
        "lam": ["ལམ"],           // path
        "kham": ["ཁམས"],         // realm/element
        "kha": ["ཁ", "མཁའ"],    // mouth / sky
        "zang": ["བཟང"],         // good
        "sang": ["སངས", "གསང"], // buddha / secret
        "rin": ["རིན"],          // precious
        "zhap": ["ཞབས"],         // feet (honorific)
        "zhab": ["ཞབས"],
        "gon": ["མགོན"],         // protector
        "bu": ["བུ"],            // son/child
        "jang": ["བྱང"],         // north/purify (pronounced "jang")
        "chang": ["ཆང"],             // alcohol

        // Verbs & Actions
        "gruep": ["གྲུབ"],       // accomplish
        "drup": ["གྲུབ", "སྒྲུབ"],
        "drub": ["གྲུབ", "སྒྲུབ"],
        "gro": ["འགྲོ"],         // go
        // DUPLICATE: "dro": ["འགྲོ"],
        "gyuer": ["གྱུར"],       // become
        "gyur": ["གྱུར"],
        "dep": ["འདེབས"],        // plant/establish
        "dzeyy": ["མཛད"],        // do (honorific)
        "dze": ["མཛད"],
        "dzey": ["མཛད"],
        "dzok": ["རྫོགས"],       // complete
        "dzog": ["རྫོགས"],
        "sal": ["གསལ"],          // clear
        "sel": ["གསལ", "བསལ"], // clear / remove
        "thop": ["ཐོབ"],         // obtain
        "tob": ["ཐོབ"],
        "rlop": ["རློབས"],       // bless
        "lob": ["སློབ", "རློབས"], // teach / bless
        "grol": ["གྲོལ"],        // liberate
        "tong": ["སྟོང"],        // empty/thousand
        "sam": ["བསམ"],          // think
        "prül": ["སྤྲུལ"],       // emanate
        "trul": ["སྤྲུལ"],
        "kyey": ["སྐྱེ"],        // be born
        "kye": ["སྐྱེ"],
        "jor": ["འབྱོར"],        // arrive/wealth
        "jüng": ["འབྱུང"],       // arise
        "jung": ["འབྱུང"],
        "rol": ["རོལ"],          // play/enjoy
        "tar": ["ལྟར"],          // like/as
        "zhin": ["བཞིན"],        // according to
        "shok": ["ཤོག"],         // may it be (optative)
        "chep": ["ཁྱབ"],         // pervade
        "khyab": ["ཁྱབ"],
        // DUPLICATE: "yong": ["ཡོངས", "ཡོང"], // all / come

        // Qualities & States
        // DUPLICATE: "chen": ["ཆེན"],         // great
        // DUPLICATE: "chung": ["ཆུང"],        // small
        "gyé": ["རྒྱས"],         // expand/vast
        // DUPLICATE: "gye": ["རྒྱས"],
        "zhi": ["ཞི"],           // peace
        // DUPLICATE: "shi": ["ཞི", "བཞི"],   // peace / four
        "rik": ["རིག", "རིགས"], // awareness / type
        "dan": ["ལྡན"],          // possessing
        "den": ["ལྡན"],
        "chan": ["ཅན"],          // having
        "rep": ["རབ"],           // excellent
        "rab": ["རབ"],
        "tsey": ["ཚེ"],          // life
        // DUPLICATE: "tse": ["ཚེ"],

        // Question & Demonstratives
        "di": ["འདི"],           // this
        // DUPLICATE: "de": ["དེ", "འདུག"],   // that / is (existential)
        // DUPLICATE: "gang": ["གང"],          // which/what

        // Religious & Philosophical
        "ye": ["ཡེ"],            // primordial
        "shey": ["ཤེས"],         // know
        // DUPLICATE: "she": ["ཤེས"],
        "chuep": ["ཆུབ"],        // enlightenment
        "chub": ["ཆུབ"],
        "changchub": ["བྱང་ཆུབ"], // enlightenment
        "byang chub": ["བྱང་ཆུབ"],
        "bodhicitta": ["བྱང་ཆུབ་སེམས"],
        "sem chen": ["སེམས་ཅན"], // sentient being
        "semchen": ["སེམས་ཅན"],
        "semcan": ["སེམས་ཅན"],
        "nyampa": ["མཉམ་པ"],     // equal
        "nyam": ["མཉམ", "ཉམས"], // equal / experience
        "ting": ["ཏིང"],         // samadhi
        "ngeyin": ["ངེས་འབྱིན"], // definite
        "nge": ["ངེས"],          // certain
        "tsa": ["རྩ"],           // root/channel
        "gya": ["རྒྱ"],          // seal/mudra
        "gyachen": ["རྒྱ་ཆེན"],   // mahamudra
        "nyingpo": ["སྙིང་པོ"],  // essence
        "nyngpo": ["སྙིང་པོ"],
        "dzoé": ["མཛོད"],        // treasury
        "dzö": ["མཛོད"],
        "dzod": ["མཛོད"],
        "jing": ["དབྱིངས"],      // expanse
        "ying": ["དབྱིངས"],
        "tha": ["མཐའ"],          // limit/end
        "gyeyn": ["རྒྱན"],       // ornament
        "gyen": ["རྒྱན"],

        // Common phrases
        "yinpe": ["ཡིན་པས"],     // is it?
        "yinpé": ["ཡིན་པས"],
        "yin pe": ["ཡིན་པས"],
        "yinpa": ["ཡིན་པ"],      // being
        "repe": ["རེད་པས"],      // is it? (factual)
        "redpe": ["རེད་པས"],
        "red pe": ["རེད་པས"],
        "dukpe": ["འདུག་གས"],    // is there?
        "dug ge": ["འདུག་གས"],
        "yoepe": ["ཡོད་པས"],     // do you have?
        "yod pe": ["ཡོད་པས"],
        "mindu": ["མིན་འདུག"],   // is not
        "min duk": ["མིན་འདུག"],
        "mepe": ["མེད་པས"],      // don't have?
        "med pe": ["མེད་པས"],

        // More common words
        "tham": ["ཐམས"],         // all
        "thamche": ["ཐམས་ཅད"],   // all/everything
        "thamché": ["ཐམས་ཅད"],
        "tamche": ["ཐམས་ཅད"],
        "chéy": ["ཅད", "བཅས"],  // all / together with
        // "che" already defined in General Terms section
        "chey": ["ཆེ"],
        "ngo": ["དངོས", "ངོ"],  // actual / face
        "ngowo": ["ངོ་བོ"],      // essence/nature
        "ngo wo": ["ངོ་བོ"],
        "sri": ["སྲིད"],         // existence
        "si": ["སྲིད"],
        "sok": ["སོགས"],         // etc.
        "sog": ["སོགས"],
        "lasok": ["ལ་སོགས"],     // and so forth
        "la sok": ["ལ་སོགས"],
        "lasogpa": ["ལ་སོགས་པ"],

        // Body parts & everyday
        "lü": ["ལུས"],           // body
        "lu": ["ལུས"],
        // DUPLICATE: "go": ["མགོ", "གོ"],     // head / understand
        "mgo": ["མགོ"],
        "mik": ["མིག"],          // eye
        "mig": ["མིག"],
        // DUPLICATE: "na": ["རྣ", "ན"],       // ear / be sick / in
        "nawa": ["རྣ་བ"],        // ear
        "lag": ["ལག"],           // hand
        "lakpa": ["ལག་པ"],
        "kangpa": ["རྐང་པ"],     // leg
        "kang": ["རྐང"],

        // More verbs
        "tsal": ["འཚལ", "རྩལ"], // seek / skill
        "tsol": ["འཚོལ"],        // search
        "chöe": ["སྤྱོད", "མཆོད"], // practice / offer
        "chod": ["གཅོད", "ཆོད"], // cut / decide
        "ge": ["དགེ"],           // virtue
        "dge": ["དགེ"],
        // DUPLICATE: "nyen": ["ཉན", "གཉེན"], // listen / relative
        "ten": ["བསྟན", "རྟེན"], // teaching / support
        "bla": ["བླ"],           // lama/soul
        "tseyn": ["མཚན"],        // name/sign
        // DUPLICATE: "tsen": ["མཚན"],
        "bo": ["བོ"],            // Tibet (in bod)

        // Pronouns & demonstratives
        // DUPLICATE: "nga": ["ང", "ལྔ"],     // I / five
        "ngé": ["ངས"],           // I (ergative)
        // DUPLICATE: "nge": ["ངས"],
        "ngas": ["ངས"],
        "ngatso": ["ང་ཚོ"],      // we
        "nga tso": ["ང་ཚོ"],
        "khyetso": ["ཁྱེད་ཚོ"],  // you (plural)
        "khye tso": ["ཁྱེད་ཚོ"],
        "khotso": ["ཁོ་ཚོ"],     // they
        "kho tso": ["ཁོ་ཚོ"],

        // Adjectives & qualities
        "karpo": ["དཀར་པོ"],     // white
        "kar po": ["དཀར་པོ"],
        "nakpo": ["ནག་པོ"],      // black
        "nak po": ["ནག་པོ"],
        "marpo": ["དམར་པོ"],     // red
        "mar po": ["དམར་པོ"],
        "serpo": ["སེར་པོ"],     // yellow
        "ser po": ["སེར་པོ"],
        "ngonpo": ["སྔོན་པོ"],   // blue
        "ngon po": ["སྔོན་པོ"],
        "jangkhu": ["ལྗང་ཁུ"],   // green
        "jang khu": ["ལྗང་ཁུ"],

        // More religious terms
        // DUPLICATE: "gendün": ["དགེ་འདུན"],
        "sangha": ["དགེ་འདུན"],
        // DUPLICATE: "drolma": ["སྒྲོལ་མ"],   // Tara
        "tara": ["སྒྲོལ་མ"],
        "chenrezig": ["སྤྱན་རས་གཟིགས"],
        "chenrezik": ["སྤྱན་རས་གཟིགས"],
        "jampel": ["འཇམ་དཔལ"],   // Manjushri
        "jampal": ["འཇམ་དཔལ"],
        "manjushri": ["འཇམ་དཔལ"],
        "chana": ["ཕྱག་ན"],      // in hand
        "chanadorje": ["ཕྱག་ན་རྡོ་རྗེ"], // Vajrapani
        "vajrapani": ["ཕྱག་ན་རྡོ་རྗེ"],

        // Common greetings & phrases
        "wai": ["ཝ་ཡེ"],             // hey/hello (casual)
        "kuzu zangpo": ["སྐུ་གཟུགས་བཟང་པོ"], // hello (Bhutanese)
        "kuzuzangpo": ["སྐུ་གཟུགས་བཟང་པོ"],
        "kuzu zangpola": ["སྐུ་གཟུགས་བཟང་པོ་ལགས"],
        "kadinche": ["བཀའ་དྲིན་ཆེ"], // thank you (Bhutanese)
        "kadrinche": ["བཀའ་དྲིན་ཆེ"],
        "ka din che": ["བཀའ་དྲིན་ཆེ"],

        // ============================================
        // EVERYDAY VOCABULARY - COMPREHENSIVE
        // ============================================

        // Family Members
        "apa": ["ཨ་པ"],              // father (informal)
        "pala": ["པ་ལགས"],           // father (polite)
        "ama": ["ཨ་མ"],              // mother
        "amala": ["ཨ་མ་ལགས"],        // mother (polite)
        "popo": ["ཕོ་བོ"],            // grandfather
        // DUPLICATE: "momo": ["མོག་མོག", "མོ་མོ"], // grandmother / dumplings
        "acha": ["ཨ་ཅག"],            // older sister
        "achala": ["ཨ་ཅག་ལགས"],
        "acho": ["ཨ་ཇོ"],            // older brother
        "achola": ["ཨ་ཇོ་ལགས"],
        "nomo": ["ནོ་མོ"],            // younger sister
        "nu": ["ནུ་བོ"],              // younger brother
        "pumo": ["བུ་མོ"],            // daughter/girl
        "pu": ["བུ"],                 // son/boy
        "pugu": ["ཕྲུ་གུ"],           // child
        "phugu": ["ཕྲུ་གུ"],
        "kyemen": ["སྐྱེས་དམན"],      // wife
        "kyepa": ["སྐྱེས་པ"],         // husband
        "changsa": ["བཟའ་ཟླ"],        // spouse
        "zala": ["བཟའ་ཟླ"],
        "gyenyen": ["གཉེན་ཉེ"],       // relative
        "nyenpa": ["གཉེན་པ"],
        // DUPLICATE: "tsa": ["ཚ་བོ"],              // nephew/grandson
        "tsamo": ["ཚ་མོ"],            // niece/granddaughter

        // Body Parts
        // DUPLICATE: "go": ["མགོ"],               // head
        // DUPLICATE: "mgo": ["མགོ"],
        "tra": ["སྐྲ"],               // hair
        "kra": ["སྐྲ"],
        "dongpa": ["གདོང་པ"],         // face
        "dong": ["གདོང"],
        // DUPLICATE: "mik": ["མིག"],              // eye
        // DUPLICATE: "mig": ["མིག"],
        "naro": ["རྣ་བ"],            // ear
        // DUPLICATE: "na": ["རྣ"],
        // DUPLICATE: "nawa": ["རྣ་བ"],
        "na ba": ["རྣ་བ"],
        "shangna": ["སྣ"],             // nose
        "na khung": ["སྣ་ཁུང"],
        // DUPLICATE: "kha": ["ཁ"],                // mouth
        "so": ["སོ"],                // tooth
        "lche": ["ལྕེ"],             // tongue (also "che")
        // DUPLICATE: "lakpa": ["ལག་པ"],           // hand/arm
        "lag pa": ["ལག་པ"],
        // DUPLICATE: "lag": ["ལག"],
        "dzumo": ["མཛུབ་མོ"],         // finger
        "dzub mo": ["མཛུབ་མོ"],
        // DUPLICATE: "kangpa": ["རྐང་པ"],          // leg/foot
        "kang pa": ["རྐང་པ"],
        "tröpa": ["གྲོད་པ"],          // stomach
        "trö pa": ["གྲོད་པ"],
        "nyingka": ["སྙིང་ཁ"],        // chest/heart
        // DUPLICATE: "nying": ["སྙིང"],
        "gyap": ["རྒྱབ"],             // back
        "gyab": ["རྒྱབ"],
        "pungpa": ["དཔུང་པ"],         // shoulder
        "kepa": ["སྐེ་པ"],            // neck
        "ke": ["སྐེ"],
        "pukpa": ["སྤུབས་པ"],         // knee
        "lüpo": ["ལུས་པོ"],           // body

        // Food & Drink (expanded)
        // DUPLICATE: "khalak": ["ཁ་ལག"],          // food
        // DUPLICATE: "kha lag": ["ཁ་ལག"],
        "zakhang": ["ཟ་ཁང"],          // restaurant
        "za khang": ["ཟ་ཁང"],
        // DUPLICATE: "thukpa": ["ཐུག་པ"],          // noodle soup
        "thuk pa": ["ཐུག་པ"],
        // DUPLICATE: "momo": ["མོག་མོག"],          // dumplings
        "mo mo": ["མོག་མོག"],
        // DUPLICATE: "tsampa": ["རྩམ་པ"],          // roasted barley flour
        "tsam pa": ["རྩམ་པ"],
        "dre": ["འབྲས"],              // rice
        "drey": ["འབྲས"],
        "shingto": ["ཤིང་ཏོག"],       // fruit
        "shing tog": ["ཤིང་ཏོག"],
        // DUPLICATE: "tse": ["ཚལ"],               // vegetables
        "ngotse": ["སྔོ་ཚལ"],         // vegetables
        "ngo tsal": ["སྔོ་ཚལ"],
        // DUPLICATE: "sha": ["ཤ"],                // meat
        "yaksha": ["གཡག་ཤ"],          // yak meat
        "luksha": ["ལུག་ཤ"],          // mutton
        "chasha": ["བྱ་ཤ"],           // chicken
        "nya": ["ཉ"],                // fish
        "gongma": ["སྒོང་མ"],         // egg
        "gong ma": ["སྒོང་མ"],
        "oma": ["འོ་མ"],              // milk
        "o ma": ["འོ་མ"],
        // DUPLICATE: "mar": ["མར"],               // butter
        "chura": ["ཆུར་བ"],           // cheese
        "chu ra": ["ཆུར་བ"],
        // DUPLICATE: "ja": ["ཇ"],                 // tea
        "jathuk": ["ཇ་ཐུག"],          // butter tea
        "ja thuk": ["ཇ་ཐུག"],
        "pöcha": ["བོད་ཇ"],           // Tibetan tea
        "bö cha": ["བོད་ཇ"],
        "ngamo": ["སྔ་མོ"],           // sweet tea
        "jangya": ["བྱང་ཇ"],
        // "chang" already defined in General Terms section
        "ara": ["ཨ་རག"],             // alcohol/liquor
        "a rak": ["ཨ་རག"],
        // DUPLICATE: "chu": ["ཆུ"],               // water
        // DUPLICATE: "karpo": ["དཀར་པོ"],          // white (sugar, rice)
        "kara": ["ཀ་ར"],              // sugar
        "tsialu": ["ཚྭ་ལུ"],          // salt
        // DUPLICATE: "tsa": ["ཚྭ"],
        "sipen": ["སྤེན"],            // chili
        "ema": ["ཨེ་མ"],              // chili (Dzongkha)

        // Clothing
        "dupta": ["གདུགས་པ"],         // umbrella
        "gö": ["གོས"],               // clothes
        "gos": ["གོས"],
        "chupa": ["ཕྱུ་པ"],           // traditional dress
        "phyu pa": ["ཕྱུ་པ"],
        "lham": ["ལྷམ"],             // boots/shoes
        "zhwa": ["ཞྭ"],              // hat
        "shamthap": ["ཤམ་ཐབས"],       // apron
        "pangden": ["པང་གདན"],        // apron (women's)
        "dingwa": ["སྒྲིང་བ"],        // belt
        "tiru": ["ཐི་རུ"],            // ring
        "gyencha": ["རྒྱན་ཆ"],        // jewelry
        "gyen cha": ["རྒྱན་ཆ"],
        "zi": ["གཟི"],               // dzi bead

        // House & Objects
        "khangpa": ["ཁང་པ"],          // house
        "khang pa": ["ཁང་པ"],
        "khang": ["ཁང"],
        "nangla": ["ནང་ལ"],           // inside
        // DUPLICATE: "nang": ["ནང"],
        "chila": ["ཕྱི་ལ"],           // outside
        "chi": ["ཕྱི"],
        "phyi": ["ཕྱི"],
        // DUPLICATE: "go": ["སྒོ"],               // door
        "sgo": ["སྒོ"],
        "gyeukung": ["སྒེའུ་ཁུང"],     // window
        "gyeu khung": ["སྒེའུ་ཁུང"],
        "thok": ["ཐོག"],             // roof/upstairs
        "ogma": ["འོག་མ"],            // downstairs
        "nye": ["གནས"],              // bed
        "nyetri": ["གཉིད་ཁྲི"],       // bed
        "chokse": ["ཅོག་ཙེ"],         // table
        "chog tse": ["ཅོག་ཙེ"],
        "kukpa": ["སྐུག་པ"],          // chair
        "kyakur": ["སྐྱ་སྐུར"],
        "sangchö": ["གསང་སྤྱོད"],      // bathroom
        "sang chö": ["གསང་སྤྱོད"],
        "thaptsang": ["ཐབ་ཚང"],       // kitchen
        "thap tsang": ["ཐབ་ཚང"],
        "deme": ["སྒྲོན་མེ"],          // lamp/light
        // "ö" already defined above
        "drilpu": ["དྲིལ་བུ"],        // bell
        "dril bu": ["དྲིལ་བུ"],
        "karyu": ["དཀར་ཡོལ"],         // cup
        "phorpa": ["ཕོར་པ"],          // bowl
        "phor pa": ["ཕོར་པ"],
        "derma": ["སྡེར་མ"],          // plate
        "der ma": ["སྡེར་མ"],
        "dingma": ["གདིང་མ"],         // carpet/mattress
        "ding ma": ["གདིང་མ"],

        // Transportation & Places
        // DUPLICATE: "lam": ["ལམ"],              // road/path
        "lamka": ["ལམ་ཁ"],           // road
        "lam kha": ["ལམ་ཁ"],
        "motra": ["སྨོ་ཊ"],           // car
        "mo tra": ["སྨོ་ཊ"],
        "langkhor": ["གླང་འཁོར"],      // bus
        "lang khor": ["གླང་འཁོར"],
        "chimrik": ["གཞིམ་རིག"],       // train
        "chim rik": ["གཞིམ་རིག"],
        "namtru": ["གནམ་གྲུ"],        // airplane
        "nam tru": ["གནམ་གྲུ"],
        "drushi": ["གྲུ་གཞིང"],       // boat
        "dru": ["གྲུ"],
        "kangom": ["རྐང་འགོམ"],       // walking
        "kang gom": ["རྐང་འགོམ"],
        "tsongkhang": ["ཚོང་ཁང"],     // shop
        "tsong khang": ["ཚོང་ཁང"],
        "menkhang": ["སྨན་ཁང"],       // hospital
        "men khang": ["སྨན་ཁང"],
        "lobtra": ["སློབ་གྲྭ"],        // school
        "lob tra": ["སློབ་གྲྭ"],
        "tsukla khang": ["གཙུག་ལག་ཁང"], // temple
        "lhakhang": ["ལྷ་ཁང"],        // temple
        "lha khang": ["ལྷ་ཁང"],
        // DUPLICATE: "gompa": ["དགོན་པ"],          // monastery
        "gom pa": ["དགོན་པ"],
        "chöra": ["ཆོས་ར"],           // dharma center
        "chö ra": ["ཆོས་ར"],
        "drungkhang": ["འགྲུལ་ཁང"],    // hotel
        "drung khang": ["འགྲུལ་ཁང"],
        "tromsa": ["ཁྲོམ་ས"],         // market
        "trom": ["ཁྲོམ"],
        "ngülkhang": ["དངུལ་ཁང"],     // bank
        "ngul khang": ["དངུལ་ཁང"],

        // Nature & Animals
        // DUPLICATE: "ri": ["རི"],                // mountain
        "gangs": ["གངས"],            // snow/glacier
        "gangri": ["གངས་རི"],         // snow mountain
        "gang ri": ["གངས་རི"],
        "mtsho": ["མཚོ"],            // lake
        // DUPLICATE: "tso": ["མཚོ"],
        "chumo": ["ཆུ་མོ"],           // river
        "chu mo": ["ཆུ་མོ"],
        "tsangpo": ["གཙང་པོ"],        // river (big)
        "tsang po": ["གཙང་པོ"],
        "naktso": ["ནག་མཚོ"],         // lake (dark)
        "shing": ["ཤིང"],            // tree/wood
        "naktong": ["ནགས་ཚལ"],        // forest
        "nak tsong": ["ནགས་ཚལ"],
        "metok": ["མེ་ཏོག"],          // flower
        "me tok": ["མེ་ཏོག"],
        // DUPLICATE: "tsa": ["རྩྭ"],              // grass
        // DUPLICATE: "sa": ["ས"],                // earth/ground
        // DUPLICATE: "nam": ["གནམ"],             // sky
        "nyima": ["ཉི་མ"],           // sun/day
        "nyi ma": ["ཉི་མ"],
        "dawa": ["ཟླ་བ"],            // moon/month
        "da wa": ["ཟླ་བ"],
        // DUPLICATE: "karma": ["སྐར་མ"],          // star
        "kar ma": ["སྐར་མ"],
        "char": ["ཆར"],             // rain
        "charpa": ["ཆར་པ"],
        "char pa": ["ཆར་པ"],
        // DUPLICATE: "kha": ["ཁ་བ"],             // snow
        "khawa": ["ཁ་བ"],
        "kha wa": ["ཁ་བ"],
        // DUPLICATE: "lung": ["རླུང"],            // wind
        "lungpa": ["རླུང་པ"],
        "mukpa": ["སྨུག་པ"],          // smoke/fog
        "muk pa": ["སྨུག་པ"],
        "trin": ["སྤྲིན"],            // cloud

        // Animals
        // DUPLICATE: "semchen": ["སེམས་ཅན"],       // animal/sentient being
        // DUPLICATE: "sem chen": ["སེམས་ཅན"],
        "yak": ["གཡག"],              // yak
        "drimo": ["འབྲི་མོ"],         // female yak
        "dri mo": ["འབྲི་མོ"],
        "dzo": ["མཛོ"],              // yak-cow hybrid
        "luk": ["ལུག"],              // sheep
        "ra": ["ར"],                // goat
        "lang": ["གླང"],             // ox
        // DUPLICATE: "ta": ["རྟ"],                // horse
        "bongbu": ["བོང་བུ"],         // donkey
        "bong bu": ["བོང་བུ"],
        "khyi": ["ཁྱི"],             // dog
        "shimi": ["ཞི་མི"],           // cat
        "shi mi": ["ཞི་མི"],
        "bya": ["བྱ"],               // bird
        "jya": ["བྱ"],
        // DUPLICATE: "nya": ["ཉ"],               // fish
        "brul": ["སྦྲུལ"],            // snake
        "sbrul": ["སྦྲུལ"],
        "dom": ["དོམ"],              // bear
        "seng": ["སེང"],             // lion
        "senge": ["སེང་གེ"],
        "seng ge": ["སེང་གེ"],
        "trak": ["སྟག"],             // tiger
        "tak": ["སྟག"],
        // DUPLICATE: "druk": ["འབྲུག"],           // dragon
        "chungchung": ["ཆུང་ཆུང", "བྱིའུ"],  // small/little, also small bird
        "jarmo": ["བྱ་རོག"],          // crow
        "shang": ["ཤང"],             // eagle
        "jia": ["བྱ"],               // chicken

        // ============================================
        // VERB CONJUGATIONS & TENSE FORMS
        // ============================================

        // To go (འགྲོ)
        // DUPLICATE: "dro": ["འགྲོ"],             // go (present)
        // DUPLICATE: "gro": ["འགྲོ"],
        "drogé": ["འགྲོ་གི"],         // going
        "drogi": ["འགྲོ་གི"],
        "dro gi": ["འགྲོ་གི"],
        "drosong": ["འགྲོས་སོང"],     // went
        "dro song": ["འགྲོས་སོང"],
        "chin": ["ཕྱིན"],            // went
        "chinsong": ["ཕྱིན་སོང"],
        "chin song": ["ཕྱིན་སོང"],
        "droki": ["འགྲོ་ཀྱི"],
        "dro kyi": ["འགྲོ་ཀྱི"],

        // To come (ཡོང)
        // DUPLICATE: "yong": ["ཡོང"],             // come
        "yongsong": ["ཡོང་སོང"],      // came
        "yong song": ["ཡོང་སོང"],
        "yonggi": ["ཡོང་གི"],         // coming
        "yong gi": ["ཡོང་གི"],
        "lep": ["སླེབས"],            // arrive
        "lepsong": ["སླེབས་སོང"],     // arrived
        "lep song": ["སླེབས་སོང"],
        "lepki": ["སླེབས་ཀྱི"],
        "lep kyi": ["སླེབས་ཀྱི"],
        // DUPLICATE: "shok": ["ཤོག"],             // come! (imperative)
        "phe": ["ཕེབས"],             // come (honorific)
        "phepsong": ["ཕེབས་སོང"],
        "phep song": ["ཕེབས་སོང"],

        // To eat (ཟ)
        // DUPLICATE: "za": ["ཟ"],                // eat
        "zasong": ["ཟས་སོང"],        // ate
        "za song": ["ཟས་སོང"],
        "zagi": ["ཟ་གི"],            // eating
        "za gi": ["ཟ་གི"],
        // DUPLICATE: "so": ["ཟོ"],               // eat! (imperative)
        // DUPLICATE: "sol": ["གསོལ"],             // eat (honorific)
        "solsong": ["གསོལ་སོང"],
        "sol song": ["གསོལ་སོང"],

        // To drink (འཐུང)
        // DUPLICATE: "thung": ["འཐུང"],           // drink
        // DUPLICATE: "tung": ["འཐུང"],
        "thungsong": ["འཐུང་སོང"],    // drank
        "thung song": ["འཐུངས་སོང"],
        "thunggi": ["འཐུང་གི"],
        "thung gi": ["འཐུང་གི"],
        // DUPLICATE: "thung": ["ཐུངས"],          // drink! (imperative)

        // To see (མཐོང)
        "thong": ["མཐོང"],           // see
        "thongsong": ["མཐོང་སོང"],    // saw
        "thong song": ["མཐོང་སོང"],
        "thonggi": ["མཐོང་གི"],
        "thong gi": ["མཐོང་གི"],
        // DUPLICATE: "ta": ["ལྟ"],               // look
        "tasong": ["ལྟས་སོང"],
        "ta song": ["བལྟས་སོང"],
        "zik": ["གཟིགས"],           // see (honorific)
        "ziksong": ["གཟིགས་སོང"],
        "zik song": ["གཟིགས་སོང"],

        // To hear/listen (གོ/ཉན)
        // DUPLICATE: "go": ["གོ"],               // hear
        "gosong": ["གོ་སོང"],
        "go song": ["གོ་སོང"],
        // DUPLICATE: "nyen": ["ཉན"],             // listen
        "nyensong": ["ཉན་སོང"],
        "nyen song": ["ཉན་སོང"],
        "nyengi": ["ཉན་གྱི"],
        "nyen gyi": ["ཉན་གྱི"],

        // To speak/say (བཤད/ལབ)
        // DUPLICATE: "she": ["བཤད"],             // say/speak
        "shesong": ["བཤད་སོང"],
        "she song": ["བཤད་སོང"],
        "shegi": ["བཤད་ཀྱི"],
        "she gi": ["བཤད་ཀྱི"],
        // DUPLICATE: "lap": ["ལབ"],              // say (colloquial)
        // DUPLICATE: "lab": ["ལབ"],
        "lapsong": ["ལབ་སོང"],
        "lap song": ["ལབ་སོང"],
        "sung": ["གསུངས"],          // say (honorific)
        "sungsong": ["གསུངས་སོང"],
        "sung song": ["གསུངས་སོང"],

        // To do/make (བྱེད / འབད)
        "bew": ["འབད"],             // do/make (Dzongkha)
        // DUPLICATE: "je": ["བྱེད"],             // do/make
        // DUPLICATE: "jé": ["བྱེད"],
        "jesong": ["བྱས་སོང"],
        "je song": ["བྱས་སོང"],
        "jegi": ["བྱེད་ཀྱི"],
        "je gi": ["བྱེད་ཀྱི"],
        "jo": ["བྱོས"],             // do! (imperative)
        // DUPLICATE: "nang": ["གནང"],            // do (honorific)
        "nangsong": ["གནང་སོང"],
        "nang song": ["གནང་སོང"],

        // To know (ཤེས)
        // DUPLICATE: "she": ["ཤེས"],             // know
        // DUPLICATE: "shé": ["ཤེས"],
        // DUPLICATE: "shegi": ["ཤེས་ཀྱི"],
        "she kyi": ["ཤེས་ཀྱི"],
        "mi she": ["མི་ཤེས"],        // don't know
        "mishe": ["མི་ཤེས"],
        "hago": ["ཧ་གོ"],            // understand
        "ha go": ["ཧ་གོ"],
        "hagosong": ["ཧ་གོ་སོང"],
        "ha go song": ["ཧ་གོ་སོང"],

        // To want/need (དགོས)
        // DUPLICATE: "go": ["དགོས"],             // need/want
        // DUPLICATE: "gö": ["དགོས"],
        "goki": ["དགོས་ཀྱི"],
        "go kyi": ["དགོས་ཀྱི"],
        "migo": ["མི་དགོས"],         // don't need
        "mi go": ["མི་དགོས"],

        // To have (ཡོད)
        // DUPLICATE: "yö": ["ཡོད"],              // have/exist
        // DUPLICATE: "yoe": ["ཡོད"],
        // DUPLICATE: "yo": ["ཡོད"],
        "yod": ["ཡོད"],
        // DUPLICATE: "me": ["མེད"],              // don't have
        // DUPLICATE: "med": ["མེད"],
        // DUPLICATE: "mey": ["མེད"],
        "yörey": ["ཡོད་རེད"],        // has (factual)
        "yod red": ["ཡོད་རེད"],
        "yö re": ["ཡོད་རེད"],
        "merey": ["མེད་རེད"],        // doesn't have
        "med red": ["མེད་རེད"],
        "me re": ["མེད་རེད"],

        // To be (yin/red)
        // DUPLICATE: "yin": ["ཡིན"],             // is (personal)
        "mayin": ["མ་ཡིན"],          // is not
        // DUPLICATE: "ma yin": ["མ་ཡིན"],
        // DUPLICATE: "mindu": ["མིན་འདུག"],
        // DUPLICATE: "min duk": ["མིན་འདུག"],
        // DUPLICATE: "re": ["རེད"],              // is (factual)
        "red": ["རེད"],
        "rey": ["རེད"],
        "mare": ["མ་རེད"],           // is not
        // DUPLICATE: "ma re": ["མ་རེད"],
        "mared": ["མ་རེད"],
        "ma red": ["མ་རེད"],
        // DUPLICATE: "duk": ["འདུག"],            // is (observed)
        // DUPLICATE: "du": ["འདུག"],
        // DUPLICATE: "mindu": ["མིན་འདུག"],
        "min du": ["མིན་འདུག"],

        // To give (སྤྲོད/གཏེར)
        "tö": ["སྤྲོད"],             // give
        // DUPLICATE: "ter": ["སྟེར"],
        "tersong": ["སྟེར་སོང"],
        "ter song": ["སྟེར་སོང"],
        // DUPLICATE: "nang": ["གནང"],            // give (honorific)
        // DUPLICATE: "nangsong": ["གནང་སོང"],

        // To take/receive (ལེན)
        // DUPLICATE: "len": ["ལེན"],             // take/receive
        "lensong": ["བླངས་སོང"],
        "len song": ["བླངས་སོང"],
        "lengi": ["ལེན་གྱི"],
        "len gyi": ["ལེན་གྱི"],

        // To buy/sell
        // DUPLICATE: "nyo": ["ཉོ"],              // buy
        "nyosong": ["ཉོས་སོང"],
        "nyo song": ["ཉོས་སོང"],
        "nyogi": ["ཉོ་གི"],
        "nyo gi": ["ཉོ་གི"],
        // DUPLICATE: "tsong": ["ཚོང"],           // sell
        "tsongsong": ["བཙོངས་སོང"],
        "tsong song": ["བཙོངས་སོང"],

        // To sleep/wake
        // DUPLICATE: "nyi": ["ཉལ"],              // sleep
        "nyal": ["ཉལ"],
        "nyalsong": ["ཉལ་སོང"],
        "nyal song": ["ཉལ་སོང"],
        "nyalgi": ["ཉལ་གྱི"],
        "nyal gyi": ["ཉལ་གྱི"],
        "sé": ["སད"],               // wake up
        "sesong": ["སད་སོང"],
        "se song": ["སད་སོང"],

        // ============================================
        // CONVERSATIONAL PHRASES & QUESTIONS
        // ============================================

        // Greetings
        // DUPLICATE: "tashi delek": ["བཀྲ་ཤིས་བདེ་ལེགས"],
        "tashidelek": ["བཀྲ་ཤིས་བདེ་ལེགས"],
        // DUPLICATE: "khamzang": ["ཁམས་བཟང"],      // how are you response
        "kham zang": ["ཁམས་བཟང"],
        "demo yinpe": ["བདེ་མོ་ཡིན་པས"], // are you well?
        "demo yin pe": ["བདེ་མོ་ཡིན་པས"],
        "khye demo": ["ཁྱེད་བདེ་མོ"],    // are you well?
        "khyerang demo": ["ཁྱེད་རང་བདེ་མོ"],
        "khye rang demo": ["ཁྱེད་རང་བདེ་མོ"],
        "demo yin": ["བདེ་མོ་ཡིན"],     // I am well
        "demoyin": ["བདེ་མོ་ཡིན"],
        "lekso": ["ལེགས་སོ"],         // good/fine
        "lek so": ["ལེགས་སོ"],
        "yagpo duk": ["ཡག་པོ་འདུག"],   // it's good
        "yak po duk": ["ཡག་པོ་འདུག"],
        "yakpo": ["ཡག་པོ"],
        "yak po": ["ཡག་པོ"],

        // Thank you / Sorry
        // DUPLICATE: "tukjeche": ["ཐུགས་རྗེ་ཆེ"],   // thank you
        // DUPLICATE: "thukjeche": ["ཐུགས་རྗེ་ཆེ"],
        "thuk je che": ["ཐུགས་རྗེ་ཆེ"],
        // DUPLICATE: "gongdak": ["དགོངས་དག"],      // sorry/excuse me
        "gong dak": ["དགོངས་དག"],
        // DUPLICATE: "gongda": ["དགོངས་དག"],
        "gong da": ["དགོངས་དག"],

        // Questions
        // DUPLICATE: "gare": ["ག་རེ"],            // what?
        // DUPLICATE: "ga re": ["ག་རེ"],
        // DUPLICATE: "kare": ["ག་རེ"],
        "ka re": ["ག་རེ"],
        "garé": ["ག་རེ"],
        // DUPLICATE: "su": ["སུ"],               // who?
        "su yin": ["སུ་ཡིན"],        // who is it?
        "suyin": ["སུ་ཡིན"],
        // DUPLICATE: "gana": ["ག་ན"],            // where?
        // DUPLICATE: "ga na": ["ག་ན"],
        "gapar": ["ག་པར"],          // where?
        "ga par": ["ག་པར"],
        // DUPLICATE: "gadu": ["ག་དུས"],          // when?
        // DUPLICATE: "ga du": ["ག་དུས"],
        "gadü": ["ག་དུས"],
        // DUPLICATE: "gatso": ["ག་ཚོད"],         // how much/many?
        // DUPLICATE: "ga tso": ["ག་ཚོད"],
        "gatsö": ["ག་ཚོད"],
        "gatse": ["ག་ཚད"],
        "ga tse": ["ག་ཚད"],
        "gare che": ["ག་རེ་ཆེ"],     // why?
        "garé che": ["ག་རེ་ཆེ"],
        // DUPLICATE: "gachi": ["ག་ཅི"],          // what?
        "ga chi": ["ག་ཅི"],
        "gaji": ["ག་ཅི"],

        // Common phrases
        "ming gare": ["མིང་ག་རེ"],    // what is your name?
        "minggare": ["མིང་ག་རེ"],
        "khye ming gare": ["ཁྱེད་མིང་ག་རེ"],
        "nga ming": ["ང་མིང"],       // my name is...
        "ngé ming": ["ངའི་མིང"],
        "nge ming": ["ངའི་མིང"],
        "ngala": ["ང་ལ"],           // to me
        "nga la": ["ང་ལ"],
        "khyela": ["ཁྱེད་ལ"],        // to you
        "khye la": ["ཁྱེད་ལ"],
        // DUPLICATE: "khyerang": ["ཁྱེད་རང"],      // you (polite)
        // DUPLICATE: "khye rang": ["ཁྱེད་རང"],
        // DUPLICATE: "khorang": ["ཁོ་རང"],        // he
        "kho rang": ["ཁོ་རང"],
        // DUPLICATE: "morang": ["མོ་རང"],         // she
        "mo rang": ["མོ་རང"],
        "rangtso": ["རང་ཚོ"],        // ourselves
        "rang tso": ["རང་ཚོ"],

        // Useful phrases
        "gana yörey": ["ག་ན་ཡོད་རེད"], // where is it?
        "ga na yö re": ["ག་ན་ཡོད་རེད"],
        "di gare": ["འདི་ག་རེ"],      // what is this?
        "di ga re": ["འདི་ག་རེ"],
        "de gare": ["དེ་ག་རེ"],       // what is that?
        "de ga re": ["དེ་ག་རེ"],
        "gare je": ["ག་རེ་བྱེད"],     // what to do?
        "ga re je": ["ག་རེ་བྱེད"],
        // DUPLICATE: "yagpo duk": ["ཡག་པོ་འདུག"],  // it's good
        // DUPLICATE: "yak po duk": ["ཡག་པོ་འདུག"],
        "dukpo duk": ["སྡུག་པོ་འདུག"], // it's difficult/painful
        "duk po duk": ["སྡུག་པོ་འདུག"],
        "tsawa duk": ["ཚ་བ་འདུག"],    // it's hot
        "tsa wa duk": ["ཚ་བ་འདུག"],
        "trangmo duk": ["གྲང་མོ་འདུག"], // it's cold
        "trang mo duk": ["གྲང་མོ་འདུག"],

        // Numbers (expanded)
        "thampa": ["ཐམ་པ"],          // all/entire
        "tham pa": ["ཐམ་པ"],
        // DUPLICATE: "chik": ["གཅིག"],           // 1
        // DUPLICATE: "chig": ["གཅིག"],
        // DUPLICATE: "nyi": ["གཉིས"],            // 2
        "nyes": ["གཉིས"],
        // DUPLICATE: "sum": ["གསུམ"],            // 3
        // DUPLICATE: "shi": ["བཞི"],             // 4
        "shyi": ["བཞི"],
        // DUPLICATE: "nga": ["ལྔ"],              // 5
        // DUPLICATE: "druk": ["དྲུག"],           // 6
        // DUPLICATE: "dun": ["བདུན"],            // 7
        // DUPLICATE: "gye": ["བརྒྱད"],           // 8
        // DUPLICATE: "gu": ["དགུ"],              // 9
        // DUPLICATE: "chu": ["བཅུ"],             // 10
        "chuchik": ["བཅུ་གཅིག"],     // 11
        "chu chik": ["བཅུ་གཅིག"],
        "chunyi": ["བཅུ་གཉིས"],      // 12
        "chu nyi": ["བཅུ་གཉིས"],
        "nyishu": ["ཉི་ཤུ"],         // 20
        "nyi shu": ["ཉི་ཤུ"],
        "sumchu": ["སུམ་ཅུ"],        // 30
        "sum chu": ["སུམ་ཅུ"],
        "shipchu": ["བཞི་བཅུ"],      // 40
        "shi chu": ["བཞི་བཅུ"],
        "ngapchu": ["ལྔ་བཅུ"],       // 50
        "nga chu": ["ལྔ་བཅུ"],
        "drukchu": ["དྲུག་ཅུ"],      // 60
        "druk chu": ["དྲུག་ཅུ"],
        "dunchu": ["བདུན་ཅུ"],       // 70
        "dun chu": ["བདུན་ཅུ"],
        "gyechu": ["བརྒྱད་ཅུ"],      // 80
        "gye chu": ["བརྒྱད་ཅུ"],
        "gupchu": ["དགུ་བཅུ"],       // 90
        "gu chu": ["དགུ་བཅུ"],
        // DUPLICATE: "gya": ["བརྒྱ"],            // 100
        "nyagya": ["གཉིས་བརྒྱ"],     // 200
        // DUPLICATE: "tong": ["སྟོང"],           // 1000
        "tri": ["ཁྲི"],             // 10000
        "bumpa": ["འབུམ"],          // 100000
        "saya": ["ས་ཡ"],            // million
        "sa ya": ["ས་ཡ"],

        // Days of the week
        // DUPLICATE: "nyima": ["ཉི་མ", "གཟའ་ཉི་མ"],     // Sunday
        "za nyima": ["གཟའ་ཉི་མ"],
        // DUPLICATE: "dawa": ["ཟླ་བ", "གཟའ་ཟླ་བ"],     // Monday
        "za dawa": ["གཟའ་ཟླ་བ"],
        "mikmar": ["གཟའ་མིག་དམར"],        // Tuesday
        "za mikmar": ["གཟའ་མིག་དམར"],
        "lhakpa": ["གཟའ་ལྷག་པ"],          // Wednesday
        "za lhakpa": ["གཟའ་ལྷག་པ"],
        "phurbu": ["གཟའ་ཕུར་བུ"],         // Thursday
        "za phurbu": ["གཟའ་ཕུར་བུ"],
        "pasang": ["གཟའ་པ་སངས"],          // Friday
        "za pasang": ["གཟའ་པ་སངས"],
        "penpa": ["གཟའ་སྤེན་པ"],          // Saturday
        "za penpa": ["གཟའ་སྤེན་པ"],

        // Time expressions
        "diring": ["དེ་རིང"],        // today
        "de ring": ["དེ་རིང"],
        "khasa": ["ཁ་སང"],          // yesterday
        "kha sa": ["ཁ་སང"],
        "sangnyin": ["སང་ཉིན"],      // tomorrow
        "sang nyin": ["སང་ཉིན"],
        "khenyim": ["ཁས་ཉིན"],       // day before yesterday
        "khe nyim": ["ཁས་ཉིན"],
        "nangpar": ["གནང་པར"],       // day after tomorrow
        "nang par": ["གནང་པར"],
        "deta": ["ད་ལྟ"],           // now
        "da ta": ["ད་ལྟ"],
        "dalta": ["ད་ལྟ"],
        "ngonma": ["སྔོན་མ"],        // before
        "ngon ma": ["སྔོན་མ"],
        "jema": ["རྗེས་མ"],          // after
        "je ma": ["རྗེས་མ"],
        "chutso": ["ཆུ་ཚོད"],        // hour/time
        "chu tso": ["ཆུ་ཚོད"],
        // DUPLICATE: "karma": ["སྐར་མ"],          // minute
        // DUPLICATE: "kar ma": ["སྐར་མ"],
        "thodrang": ["ཐོ་རངས"],      // morning
        "tho drang": ["ཐོ་རངས"],
        "nyingang": ["ཉིན་གང"],      // daytime
        "nyin gang": ["ཉིན་གང"],
        "gongmo": ["དགོང་མོ"],       // evening
        "gong mo": ["དགོང་མོ"],
        "tshenmo": ["མཚན་མོ"],       // night
        "tshen mo": ["མཚན་མོ"],

        // ============================================
        // DZONGKHA-SPECIFIC VOCABULARY
        // ============================================

        // DUPLICATE: "kuzuzangpo": ["སྐུ་གཟུགས་བཟང་པོ"], // hello
        // DUPLICATE: "kuzu zangpo": ["སྐུ་གཟུགས་བཟང་པོ"],
        "kuzuzangpola": ["སྐུ་གཟུགས་བཟང་པོ་ལགས"],
        "kuzu zangpo la": ["སྐུ་གཟུགས་བཟང་པོ་ལགས"],
        "kadrinchela": ["བཀའ་དྲིན་ཆེ་ལགས"], // thank you
        "kadrin che la": ["བཀའ་དྲིན་ཆེ་ལགས"],
        // Common Dzongkha phrases
        // How are you?
        "choe gadey bey yoe": ["ཁྱོད་ག་དེ་སྦེ་ཡོད"],
        "choe gadey bay yoe": ["ཁྱོད་ག་དེ་སྦེ་ཡོད"],
        "choe gaday bey yoe": ["ཁྱོད་ག་དེ་སྦེ་ཡོད"],
        "chhoe gadey bey yoe": ["ཁྱོད་ག་དེ་སྦེ་ཡོད"],
        // What are you doing?
        "choe gachi bew mo": ["ཁྱོད་ག་ཅི་འབད་སྨོ"],
        "chhoe gachi bew mo": ["ཁྱོད་ག་ཅི་འབད་སྨོ"],
        "choe gaci bew mo": ["ཁྱོད་ག་ཅི་འབད་སྨོ"],
        "choe gachi beu mo": ["ཁྱོད་ག་ཅི་འབད་སྨོ"],
        // I'm fine
        "nga lekshom bey yoe": ["ང་ལེགས་ཤོམ་སྦེ་ཡོད"],
        "nga leyshom bey yoe": ["ང་ལེགས་ཤོམ་སྦེ་ཡོད"],
        "nga leshom bey yoe": ["ང་ལེགས་ཤོམ་སྦེ་ཡོད"],
        "nga lekshom bay yoe": ["ང་ལེགས་ཤོམ་སྦེ་ཡོད"],
        // What's your name?
        "chhoegi ming gachi mo": ["ཁྱོད་ཀྱི་མིང་ག་ཅི་སྨོ"],
        "choegi ming gachi mo": ["ཁྱོད་ཀྱི་མིང་ག་ཅི་སྨོ"],
        "choe gi ming gachi mo": ["ཁྱོད་ཀྱི་མིང་ག་ཅི་སྨོ"],
        "chhoe gi ming gachi mo": ["ཁྱོད་ཀྱི་མིང་ག་ཅི་སྨོ"],
        "ngagi ming": ["ང་གི་མིང"],       // my name is...
        "nga gi ming": ["ང་གི་མིང"],
        // Where are you from?
        "chhoe gatey lay mo": ["ཁྱོད་ག་ཏེ་ལས་སྨོ"],
        "choe gatey lay mo": ["ཁྱོད་ག་ཏེ་ལས་སྨོ"],
        "choe gatay lay mo": ["ཁྱོད་ག་ཏེ་ལས་སྨོ"],
        "chhoe gatay lay mo": ["ཁྱོད་ག་ཏེ་ལས་སྨོ"],
        // See you later
        "lok shu ley jel gey": ["ལོག་ཤུལ་ལས་འབྱལ་གེ"],
        "lok shu lay jel gay": ["ལོག་ཤུལ་ལས་འབྱལ་གེ"],
        "lok shu ley jel gay": ["ལོག་ཤུལ་ལས་འབྱལ་གེ"],
        // I don't understand
        "nga gi ha migo wai": ["ང་གིས་ཧ་མི་གོ་བས"],
        "nga gi ha mi go wai": ["ང་གིས་ཧ་མི་གོ་བས"],
        "ngagi ha migo wai": ["ང་གིས་ཧ་མི་གོ་བས"],
        // Thank you
        "kadrin chhe": ["བཀའ་དྲིན་ཆེ"],
        "kadrin che": ["བཀའ་དྲིན་ཆེ"],
        // Sorry
        "tsip maza": ["ཙིགཔ་མ་ཟ"],
        "tsip ma za": ["ཙིགཔ་མ་ཟ"],
        "tsigpa maza": ["ཙིགཔ་མ་ཟ"],
        // Please
        "nga lu nang": ["ང་ལུ་གནང"],
        "ngalu nang": ["ང་ལུ་གནང"],
        // Where's the bathroom?
        "chhab sang gatey yue ga": ["ཆབ་གསང་ག་ཏེ་ཡོད་ག"],
        "chab sang gatey yue ga": ["ཆབ་གསང་ག་ཏེ་ཡོད་ག"],
        "chhab sang gatay yue ga": ["ཆབ་གསང་ག་ཏེ་ཡོད་ག"],
        // Individual Dzongkha words
        "gadey": ["ག་དེ"],               // how
        "gaday": ["ག་དེ"],
        "bey": ["སྦེ"],                   // connective particle
        "bay": ["སྦེ"],
        "gatey": ["ག་ཏེ"],               // where
        "gatay": ["ག་ཏེ"],
        "lay": ["ལས"],                   // from
        "ley": ["ལས"],
        // "yoe" already defined above (have/exist)
        "lekshom": ["ལེགས་ཤོམ"],         // fine/well
        "leyshom": ["ལེགས་ཤོམ"],
        "leshom": ["ལེགས་ཤོམ"],
        // "migo" already defined above (don't need); this meaning (not understand) is secondary
        "ema datsi": ["ཨེ་མ་དར་ཚིལ"],  // chili cheese dish
        "emadatsi": ["ཨེ་མ་དར་ཚིལ"],
        "drukpa": ["འབྲུག་པ"],        // Bhutanese person
        "druk pa": ["འབྲུག་པ"],
        // DUPLICATE: "drukyul": ["འབྲུག་ཡུལ"],     // Bhutan
        "druk yul": ["འབྲུག་ཡུལ"],
        "paro": ["སྤ་རོ"],            // Paro
        "thimphu": ["ཐིམ་ཕུ"],        // Thimphu
        "thim phu": ["ཐིམ་ཕུ"],
        "punakha": ["སྤུ་ན་ཁ"],       // Punakha
        "pu na kha": ["སྤུ་ན་ཁ"],
        "bumthang": ["བུམ་ཐང"],       // Bumthang
        "bum thang": ["བུམ་ཐང"],
        "gho": ["གོ"],               // men's dress
        "kira": ["ཀི་ར"],            // women's dress
        "ki ra": ["ཀི་ར"],
        "rachu": ["ར་ཆུ"],           // women's scarf
        "ra chu": ["ར་ཆུ"],
        "kabney": ["བཀབ་ནེ"],        // men's scarf (Dz)
        "kab ney": ["བཀབ་ནེ"],
        "dzong": ["རྫོང"],           // fortress
        // DUPLICATE: "lhakhang": ["ལྷ་ཁང"],       // temple
        // DUPLICATE: "lha khang": ["ལྷ་ཁང"],
        "chorten": ["མཆོད་རྟེན"],     // stupa
        "chö ten": ["མཆོད་རྟེན"],
        "tsechu": ["ཚེས་བཅུ"],       // festival
        "tse chu": ["ཚེས་བཅུ"],
        "cham": ["འཆམ"],            // masked dance
        "zhabje": ["ཞབས་རྗེ"],       // Zhabdrung
        "zhab je": ["ཞབས་རྗེ"],
        // DUPLICATE: "jikme": ["འཇིགས་མེད"],      // fearless (name)
        "jik me": ["འཇིགས་མེད"],
        "singye": ["སེང་གེ"],        // lion (name)
        "sing ye": ["སེང་གེ"],
        // DUPLICATE: "wangchuk": ["དབང་ཕྱུག"],    // powerful (name)
        "wang chuk": ["དབང་ཕྱུག"],

        // Adjectives
        "chenpo": ["ཆེན་པོ"],        // big
        "chen po": ["ཆེན་པོ"],
        // DUPLICATE: "chungchung": ["ཆུང་ཆུང"],    // small
        "chung chung": ["ཆུང་ཆུང"],
        "ringpo": ["རིང་པོ"],        // long
        "ring po": ["རིང་པོ"],
        "thungthung": ["ཐུང་ཐུང"],    // short
        "thung thung": ["ཐུང་ཐུང"],
        // DUPLICATE: "yakpo": ["ཡག་པོ"],          // good
        // DUPLICATE: "yak po": ["ཡག་པོ"],
        "dukpo": ["སྡུག་པོ"],        // bad/difficult
        "duk po": ["སྡུག་པོ"],
        // DUPLICATE: "nyingje": ["སྙིང་རྗེ"],     // compassionate
        "nying je": ["སྙིང་རྗེ"],
        "kyipo": ["སྐྱིད་པོ"],       // happy
        "kyi po": ["སྐྱིད་པོ"],
        "dropo": ["སྐྲག་པོ"],        // scary
        "dro po": ["འགྲོ་པོ"],
        "tropo": ["ཁྲོ་བོ"],         // angry
        "tro po": ["ཁྲོ་བོ"],
        "nyepo": ["ཉེ་པོ"],          // near
        "nye po": ["ཉེ་པོ"],
        // DUPLICATE: "ringpo": ["རིང་པོ"],        // far
        // DUPLICATE: "ring po": ["རིང་པོ"],
        "thakring": ["ཐག་རིང"],      // far
        "thak ring": ["ཐག་རིང"],
        "thaknyé": ["ཐག་ཉེ"],        // near
        "thak nye": ["ཐག་ཉེ"],
        "tsawa": ["ཚ་བ"],           // hot
        "tsa wa": ["ཚ་བ"],
        "trangmo": ["གྲང་མོ"],       // cold
        "trang mo": ["གྲང་མོ"],
        "kyukpo": ["མགྱོགས་པོ"],     // fast
        "kyuk po": ["མགྱོགས་པོ"],
        "bulé": ["བུལ་བ"],          // slow
        "bu le": ["བུལ་བ"],
        // DUPLICATE: "karpo": ["དཀར་པོ"],         // white
        // DUPLICATE: "kar po": ["དཀར་པོ"],
        // DUPLICATE: "nakpo": ["ནག་པོ"],          // black
        // DUPLICATE: "nak po": ["ནག་པོ"],
        // DUPLICATE: "marpo": ["དམར་པོ"],         // red
        // DUPLICATE: "mar po": ["དམར་པོ"],
        // DUPLICATE: "serpo": ["སེར་པོ"],         // yellow
        // DUPLICATE: "ser po": ["སེར་པོ"],
        // DUPLICATE: "ngonpo": ["སྔོན་པོ"],       // blue
        // DUPLICATE: "ngon po": ["སྔོན་པོ"],
        // DUPLICATE: "jangkhu": ["ལྗང་ཁུ"],       // green
        // DUPLICATE: "jang khu": ["ལྗང་ཁུ"],
        "drukpo": ["སྤྲུག་པོ"],      // purple (Dzongkha)

        // Emotions & States
        // DUPLICATE: "gawa": ["དགའ་བ"],          // happy
        "ga wa": ["དགའ་བ"],
        "kyidpo": ["སྐྱིད་པོ"],
        "skyid po": ["སྐྱིད་པོ"],
        "semkyö": ["སེམས་སྐྱོ"],     // sad
        "sem kyo": ["སེམས་སྐྱོ"],
        "semkyo": ["སེམས་སྐྱོ"],
        "trok": ["སྐྲག"],           // afraid
        "trakpo": ["སྐྲག་པོ"],
        "trak po": ["སྐྲག་པོ"],
        "khong": ["ཁོང་ཁྲོ"],        // angry
        "khongkho": ["ཁོང་ཁྲོ"],
        "khong khro": ["ཁོང་ཁྲོ"],
        "ngalso": ["ངལ་གསོ"],       // rest
        "ngal so": ["ངལ་གསོ"],
        "thang": ["ཐང"],            // tired
        "thangche": ["ཐང་ཆད"],       // exhausted
        "thang che": ["ཐང་ཆད"],
        "treko": ["འཁྲེལ་གོ"],       // embarrassed
        "tre ko": ["འཁྲེལ་གོ"],
        "yikche": ["ཡིད་ཆེས"],       // trust
        "yik che": ["ཡིད་ཆེས"],

        // Common expressions
        "laso": ["ལགས་སོ"],         // yes/okay
        "la so": ["ལགས་སོ"],
        "lakso": ["ལགས་སོ"],
        // DUPLICATE: "ma re": ["མ་རེད"],         // no (it isn't)
        // DUPLICATE: "mayin": ["མ་ཡིན"],         // no (I'm not)
        "min": ["མིན"],
        // DUPLICATE: "dre": ["དྲས"],             // okay/alright
        // DUPLICATE: "drey": ["དྲེས"],
        "ong": ["འོང"],             // will come/okay
        "onggi": ["འོང་གི"],
        "ong gi": ["འོང་གི"],
        "digisong": ["འདི་གི་སོང"],
        "di gi song": ["འདི་གི་སོང"],
        "shi shi": ["ཤི་ཤི"],        // shh/quiet
        "am": ["འམ"],               // or (question)

        // ============================================
        // MISSING COMMON WORDS - ADDED FOR COVERAGE
        // ============================================

        // Dharma terms (Sanskrit-origin commonly used in Tibetan)
        "kora": ["སྐོར་ར", "བསྐོར་བ"],     // circumambulation
        "puja": ["མཆོད་པ"],                // ritual offering/worship
        "stupa": ["མཆོད་རྟེན"],            // reliquary monument
        "mandala": ["དཀྱིལ་འཁོར", "མཎྜལ"], // sacred circle
        "nirvana": ["མྱ་ངན་ལས་འདས", "ཉང་འདས"], // liberation beyond suffering
        "bodhisattva": ["བྱང་ཆུབ་སེམས་དཔའ"], // awakened being
        "sutra": ["མདོ"],                  // scripture/discourse
        "mantra": ["སྔགས", "མནྟྲ"],        // sacred syllable/spell
        "mudra": ["ཕྱག་རྒྱ"],              // hand gesture/seal
        "thangka": ["ཐང་ཀ", "ཐང་ཁ"],      // scroll painting
        "thanka": ["ཐང་ཀ"],
        "tangka": ["ཐང་ཀ"],
        "mala": ["ཕྲེང་བ"],                // prayer beads
        "torma": ["གཏོར་མ"],              // ritual cake offering
        "lungta": ["རླུང་རྟ"],             // wind horse (prayer flags)
        "lung ta": ["རླུང་རྟ"],
        "namkha": ["ནམ་མཁའ"],             // sky/space
        "nam kha": ["ནམ་མཁའ"],
        "terma": ["གཏེར་མ"],              // hidden treasure teaching
        "ter ma": ["གཏེར་མ"],
        "geshe": ["དགེ་བཤེས"],             // learned scholar (degree)
        "geshé": ["དགེ་བཤེས"],
        "ge she": ["དགེ་བཤེས"],
        "lopon": ["སློབ་དཔོན"],             // teacher/master
        "lo pon": ["སློབ་དཔོན"],
        "lopen": ["སློབ་དཔོན"],
        "ani": ["ཨ་ནི"],                   // nun
        "a ni": ["ཨ་ནི"],
        "milarepa": ["མི་ལ་རས་པ"],         // the great yogin
        "mi la re pa": ["མི་ལ་རས་པ"],
        "tsongkhapa": ["ཙོང་ཁ་པ"],         // founder of Gelug school
        "tsong kha pa": ["ཙོང་ཁ་པ"],

        // Missing daily/common words
        "mi": ["མི"],                      // person/human
        "pha": ["ཕ"],                      // father
        "phala": ["ཕ་ལགས"],               // father (polite)
        "pha la": ["ཕ་ལགས"],
        "bumo": ["བུ་མོ"],                 // daughter/girl
        "bu mo": ["བུ་མོ"],
        "ming": ["མིང"],                   // name
        "tsho": ["མཚོ"],                   // lake
        // Khyö kyi phrase support
        "khyo kyi": ["ཁྱོད་ཀྱི"],          // your (informal)
        "khyö kyi": ["ཁྱོད་ཀྱི"],
        "khye kyi": ["ཁྱེད་ཀྱི"],          // your (formal)
        "khyö kyi ming gare": ["ཁྱོད་ཀྱི་མིང་ག་རེ"],  // what is your name
        "khye kyi ming gare": ["ཁྱེད་ཀྱི་མིང་ག་རེ"],

        // ============================================
        // COMMON 2-SYLLABLE COMPOUNDS (typed without space)
        // ============================================
        "lodro": ["བློ་གྲོས"],             // wisdom/intelligence
        "lo dro": ["བློ་གྲོས"],
        "thugje": ["ཐུགས་རྗེ"],           // compassion (honorific)
        "thug je": ["ཐུགས་རྗེ"],
        "damtsig": ["དམ་ཚིག"],            // samaya/sacred bond
        "dam tsig": ["དམ་ཚིག"],
        "lobpon": ["སློབ་དཔོན"],           // teacher/master
        "lob pon": ["སློབ་དཔོན"],
        "gyaltsab": ["རྒྱལ་ཚབ"],          // regent
        "gyal tsab": ["རྒྱལ་ཚབ"],
        "shabdro": ["ཞབས་འགྲོ"],          // walking (honorific)
        "shab dro": ["ཞབས་འགྲོ"],
        "choeten": ["མཆོད་རྟེན"],          // stupa
        "choe ten": ["མཆོད་རྟེན"],
        "chörten": ["མཆོད་རྟེན"],
        "labrang": ["བླ་བྲང"],             // lama's residence/estate
        "la brang": ["བླ་བྲང"],
        "kunkhyab": ["ཀུན་ཁྱབ"],          // all-pervading
        "kun khyab": ["ཀུན་ཁྱབ"],
        // "semchen"/"sem chen" already defined in Dharma section
        "ngondro": ["སྔོན་འགྲོ"],          // preliminary practices
        "ngon dro": ["སྔོན་འགྲོ"],
        // "changchub" already defined in Dharma section
        "chang chub": ["བྱང་ཆུབ"],
        "jangchub": ["བྱང་ཆུབ"],
        "jang chub": ["བྱང་ཆུབ"],
        "yenlak": ["ཡན་ལག"],             // branch/limb
        "yen lak": ["ཡན་ལག"],
        "topden": ["སྟོབས་ལྡན"],          // powerful
        "tob den": ["སྟོབས་ལྡན"],
        "shedra": ["བཤད་གྲྭ"],            // Buddhist college
        "she dra": ["བཤད་གྲྭ"],
    ]

    // MARK: - Dzongkha-Specific Dictionary

    private static let dzongkhaDictionary: [String: [String]] = [
        // Dzongkha greetings
        "kuzuzangpo": ["སྐུ་གཟུགས་བཟང་པོ"],
        "kuzu zangpo": ["སྐུ་གཟུགས་བཟང་པོ"],
        "kadinche": ["བཀའ་དྲིན་ཆེ"],
        "kadinchey": ["བཀའ་དྲིན་ཆེ"],

        // Dzongkha overrides (same phonetic, different meaning)
        "choe": ["ཁྱོད", "ཆོས"],     // "you" first in Dzongkha
        "choe rang": ["ཁྱོད་རང"],
        "mo": ["སྨོ", "མོ"],          // question particle first in Dzongkha

        // Dzongkha-specific words
        "bew": ["འབད"],              // do/make (Dzongkha)
        "ema": ["ཨེ་མ"],             // chili
        "ezey": ["ཨེ་ཟེ"],           // cheese
        "jow": ["བཅའ"],              // eat (honorific, Dzongkha)
        "gatey": ["ག་ཏེ"],           // where (Dzongkha)
        "ga tey": ["ག་ཏེ"],
        "aum": ["ཨམ"],               // mother (Dz)
        "apa": ["ཨ་པ"],              // father (Dz)
        "laso": ["ལགས་སོ"],          // OK/yes (Dzongkha)
        "la so": ["ལགས་སོ"],
        "men": ["མེན"],               // no/not (Dz)
        "lu": ["ལུས"],               // body (Dzongkha usage)
        "zhindak": ["གཞིས་བདག"],     // landlord (Dzongkha)
    ]

    // MARK: - Tibetan-Specific Dictionary

    private static let tibetanDictionary: [String: [String]] = [
        // Tibetan greetings
        "tashi delek": ["བཀྲ་ཤིས་བདེ་ལེགས"],
        "tukjeche": ["ཐུགས་རྗེ་ཆེ"],
        "thukjeche": ["ཐུགས་རྗེ་ཆེ"],

        // Tibetan overrides (same phonetic, different priority)
        "choe": ["ཆོས", "ཁྱོད"],     // "dharma" first in Tibetan
        "mo": ["མོ", "སྨོ"],          // feminine first in Tibetan
    ]

    // MARK: - Active Dictionary

    /// Get the merged dictionary for the current language mode
    /// Language-specific entries override shared entries
    private var activeDictionary: [String: [String]] {
        var dict = Self.sharedDictionary
        let langDict = languageMode == .dzongkha ? Self.dzongkhaDictionary : Self.tibetanDictionary
        for (key, value) in langDict {
            dict[key] = value
        }
        return dict
    }
}

// MARK: - Convenience Extensions

extension PhoneticMapper {

    /// Convert with automatic tsheg at end
    public func convertWithTsheg(_ phonetic: String) -> String {
        let result = convert(phonetic)
        if !result.isEmpty && !result.hasSuffix(String(TibetanUnicode.tsheg)) {
            return result + String(TibetanUnicode.tsheg)
        }
        return result
    }

    /// Check if a phonetic string has known Tibetan matches
    public func hasMatch(for phonetic: String) -> Bool {
        let normalized = phonetic.lowercased()
        return activeDictionary[normalized] != nil
            || !db.lookupExact(phonetic: normalized).isEmpty
    }

    /// Get the Wylie equivalent for a phonetic word (if known)
    public func getWylie(for phonetic: String) -> String? {
        // This would require a reverse lookup table
        // For now, return nil - to be implemented with dictionary
        return nil
    }
}
