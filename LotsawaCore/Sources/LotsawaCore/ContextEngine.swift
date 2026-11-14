// ContextEngine.swift
// LotsawaCore
//
// Context-based disambiguation for Tibetan homophones.
// Uses n-gram model to rank suggestions based on previous words.

import Foundation

/// Text domain for context-aware scoring
public enum TextDomain: String, Codable {
    case dharma = "dharma"
    case colloquial = "colloquial"
    case formal = "formal"
    case number = "number"
    case unknown = "unknown"
}

/// Semantic hint entry for homophone disambiguation
public struct SemanticHintEntry {
    let phonetic: String
    let preferredTibetan: String
}

/// Prediction result with Tibetan word, romanization hint, and confidence
public struct NextWordPrediction {
    public let tibetan: String
    public let romanization: String
    public let confidence: Double
}

/// N-gram context model for Tibetan
public class ContextEngine {

    /// Shared singleton instance
    public static let shared = ContextEngine()

    /// Whether model is loaded
    public private(set) var isLoaded: Bool = false

    /// Context window - previous words typed
    private var contextWindow: [String] = []

    /// Previous phonetic inputs (for semantic hints)
    private var phoneticWindow: [String] = []

    /// Maximum context window size (increased from 3 to 5)
    private let maxContextSize = 5

    /// Confidence threshold for auto-selection (80%)
    public let autoSelectThreshold: Double = 0.80

    /// Semantic hints loaded from JSON: previous Tibetan syllable → phonetic input → preferred Tibetan
    /// Used for common word associations that help disambiguate homophones
    private var semanticHintsPreceding: [String: [String: String]] = [:]

    /// Semantic hints for following context: next syllable → phonetic input → preferred Tibetan
    private var semanticHintsFollowing: [String: [String: String]] = [:]

    /// Domain-specific hints: domain → phonetic input → preferred Tibetan
    private var domainHints: [TextDomain: [String: String]] = [:]

    /// Current detected text domain
    private var currentDomain: TextDomain = .unknown

    /// Dharma vocabulary for domain detection
    private let dharmaVocabulary: Set<String> = [
        "སངས", "རྒྱས", "ཆོས", "དགེ", "འདུན", "བླ", "མ", "སྐུ", "གསུང", "ཐུགས",
        "རིན", "པོ", "ཆེ", "མཆོད", "སྒྲུབ", "ཉམས", "ལེན", "བསྐྱེད", "རྫོགས", "རིམ",
        "སྔགས", "དབང", "ལུང", "ཁྲིད", "བཀའ", "གདམས", "བདག", "སེམས", "རིག", "པ",
        "སྟོང", "ཉིད", "བྱང", "ཆུབ", "དཀོན", "མཆོག", "ཕྱག", "འཚལ", "སྐྱབས", "འགྲོ"
    ]

    /// Number vocabulary for domain detection
    private let numberVocabulary: Set<String> = [
        "གཅིག", "གཉིས", "གསུམ", "བཞི", "ལྔ", "དྲུག", "བདུན", "བརྒྱད", "དགུ", "བཅུ",
        "ཉི", "ཤུ", "སུམ", "ཅུ", "བཞི", "བཅུ", "ལྔ", "བཅུ", "དྲུག", "བཅུ",
        "བདུན", "ཅུ", "བརྒྱད", "ཅུ", "དགུ", "བཅུ", "བརྒྱ", "སྟོང", "ཁྲི", "གྲངས"
    ]

    private init() {
        loadModel()
        loadSemanticHints()
    }

    /// Check that the SQLite-backed context model is available
    private func loadModel() {
        isLoaded = SQLiteDictionary.shared.isLoaded
        if isLoaded {
            print("ContextEngine: Using SQLite-backed context model")
        } else {
            print("ContextEngine: SQLite dictionary not available")
        }
    }

    /// Load semantic hints from bundled JSON
    private func loadSemanticHints() {
        guard let url = Bundle.module.url(forResource: "semantic_hints", withExtension: "json") else {
            print("ContextEngine: semantic_hints.json not found, using defaults")
            loadDefaultSemanticHints()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            // Load preceding context hints
            if let preceding = json?["preceding"] as? [String: [String: String]] {
                semanticHintsPreceding = preceding
            }

            // Load following context hints
            if let following = json?["following"] as? [String: [String: String]] {
                semanticHintsFollowing = following
            }

            // Load domain hints
            if let domains = json?["domain_hints"] as? [String: [String: String]] {
                for (domainStr, hints) in domains {
                    if let domain = TextDomain(rawValue: domainStr.replacingOccurrences(of: "_domain", with: "")) {
                        domainHints[domain] = hints
                    }
                }
            }

            let totalHints = semanticHintsPreceding.values.reduce(0) { $0 + $1.count }
                + semanticHintsFollowing.values.reduce(0) { $0 + $1.count }
            print("ContextEngine: Loaded \(totalHints) semantic hints from JSON")

        } catch {
            print("ContextEngine: Failed to load semantic hints: \(error)")
            loadDefaultSemanticHints()
        }
    }

    /// Load default hardcoded hints as fallback
    private func loadDefaultSemanticHints() {
        // Fallback to basic hardcoded hints
        semanticHintsPreceding = [
            "ཐུང": ["chu": "ཆུ"],
            "འཐུང": ["chu": "ཆུ"],
            "དགུ": ["chu": "བཅུ"],
            "བརྒྱད": ["gu": "དགུ"],
            "བདུན": ["gye": "བརྒྱད"],
            "དྲུག": ["dun": "བདུན"],
            "ལྔ": ["druk": "དྲུག"],
            "བཞི": ["nga": "ལྔ"],
            "ཡིན": ["nga": "ང"],
            "སངས": ["gye": "རྒྱས"],
            "རྒྱས": ["cho": "ཆོས"],
        ]
        print("ContextEngine: Using default semantic hints")
    }

    // MARK: - Domain Detection

    /// Detect the current text domain based on context window
    public func detectDomain() -> TextDomain {
        guard !contextWindow.isEmpty else {
            return .unknown
        }

        var dharmaScore = 0
        var numberScore = 0

        for syllable in contextWindow {
            if dharmaVocabulary.contains(syllable) {
                dharmaScore += 1
            }
            if numberVocabulary.contains(syllable) {
                numberScore += 1
            }
        }

        // Determine domain based on scores
        if numberScore >= 2 || (numberScore >= 1 && contextWindow.count <= 2) {
            currentDomain = .number
        } else if dharmaScore >= 2 || (dharmaScore >= 1 && contextWindow.count <= 3) {
            currentDomain = .dharma
        } else {
            currentDomain = .colloquial
        }

        return currentDomain
    }

    /// Score a candidate with domain context awareness
    /// - Parameters:
    ///   - candidate: The Tibetan word to score
    ///   - domain: Optional domain override (uses detected domain if nil)
    /// - Returns: A score multiplier (1.0 = no boost, >1.0 = boosted)
    public func scoreWithDomainContext(_ candidate: String, domain: TextDomain? = nil) -> Double {
        let effectiveDomain = domain ?? detectDomain()
        var score = scoreWithContext(candidate)

        // Apply domain-specific boost if candidate matches domain expectations
        let candidateSyllable = extractFirstSyllable(candidate)

        switch effectiveDomain {
        case .dharma:
            if dharmaVocabulary.contains(candidateSyllable) {
                score *= 1.5
            }
        case .number:
            if numberVocabulary.contains(candidateSyllable) {
                score *= 2.0
            }
        case .colloquial, .formal, .unknown:
            break
        }

        return score
    }

    /// Add a word to the context window (call when user commits a word)
    /// - Parameters:
    ///   - word: The Tibetan word that was committed
    ///   - phonetic: Optional phonetic romanization that was typed
    public func addToContext(_ word: String, phonetic: String? = nil) {
        // Extract first syllable for context matching
        let syllable = extractFirstSyllable(word)
        contextWindow.append(syllable)

        // Keep window size limited
        if contextWindow.count > maxContextSize {
            contextWindow.removeFirst()
        }

        // Track phonetic input for semantic hints
        if let phonetic = phonetic {
            phoneticWindow.append(phonetic.lowercased())
            if phoneticWindow.count > maxContextSize {
                phoneticWindow.removeFirst()
            }
        }
    }

    /// Clear context (e.g., on sentence end or new field)
    public func clearContext() {
        contextWindow.removeAll()
        phoneticWindow.removeAll()
    }

    /// Get the current context for debugging
    public var currentContext: [String] {
        return contextWindow
    }

    /// Extract first syllable from a Tibetan word
    private func extractFirstSyllable(_ word: String) -> String {
        // Split by tsheg and take first
        let parts = word.split(separator: "་")
        return parts.first.map(String.init) ?? word
    }

    /// Score a candidate word based on context
    /// Returns a multiplier (1.0 = no boost, >1.0 = boosted)
    public func scoreWithContext(_ candidate: String) -> Double {
        guard isLoaded, !contextWindow.isEmpty else {
            return 1.0
        }

        let candidateSyllable = extractFirstSyllable(candidate)
        var score = 1.0

        // Try 4-gram first (strongest signal)
        if contextWindow.count >= 3 {
            let ctx = "\(contextWindow[contextWindow.count - 3])|\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            let results = SQLiteDictionary.shared.getFourgrams(key: ctx)
            if let match = results.first(where: { $0.word == candidateSyllable }) {
                score *= Double(match.count) * 4.0
            }
        }

        // Try trigram (strong signal)
        if contextWindow.count >= 2 {
            let ctx = "\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            let results = SQLiteDictionary.shared.getTrigrams(key: ctx)
            if let match = results.first(where: { $0.word == candidateSyllable }) {
                score *= Double(match.count) * 3.0
            }
        }

        // Try bigram
        if let lastWord = contextWindow.last {
            let results = SQLiteDictionary.shared.getBigrams(word: lastWord)
            if let match = results.first(where: { $0.word == candidateSyllable }) {
                score *= Double(match.count) * 2.0
            }
        }

        return score
    }

    /// Re-rank a list of suggestions based on context
    /// Input: [(tibetan, baseFrequency)]
    /// Output: Same list, sorted by context-adjusted score
    public func rankWithContext(_ suggestions: [(String, Int)]) -> [(String, Int)] {
        guard isLoaded, !contextWindow.isEmpty else {
            return suggestions
        }

        // Calculate context-adjusted scores
        let scored = suggestions.map { (word, freq) -> (String, Int, Double) in
            let contextScore = scoreWithContext(word)
            let adjustedScore = Double(freq) * contextScore
            return (word, freq, adjustedScore)
        }

        // Sort by adjusted score
        let sorted = scored.sorted { $0.2 > $1.2 }

        // Return without the score
        return sorted.map { ($0.0, $0.1) }
    }

    /// Get likely next words based on context (for predictive suggestions)
    public func predictNextWords(limit: Int = 5) -> [String] {
        guard isLoaded, !contextWindow.isEmpty else {
            return []
        }

        var predictions: [String: Int] = [:]

        // Check trigrams first
        if contextWindow.count >= 2 {
            let ctx = "\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            let trigramResults = SQLiteDictionary.shared.getTrigrams(key: ctx)
            for entry in trigramResults {
                predictions[entry.word, default: 0] += entry.count * 3
            }
        }

        // Add bigram predictions
        if let lastWord = contextWindow.last {
            let bigramResults = SQLiteDictionary.shared.getBigrams(word: lastWord)
            for entry in bigramResults {
                predictions[entry.word, default: 0] += entry.count
            }
        }

        // Sort and return top predictions
        let sorted = predictions.sorted { $0.value > $1.value }
        return Array(sorted.prefix(limit).map { $0.key })
    }

    /// Check if a word commonly follows the current context
    public func isLikelyFollower(_ word: String) -> Bool {
        return scoreWithContext(word) > 1.5
    }

    // MARK: - Confidence-Based Disambiguation

    /// Score with confidence (0.0 to 1.0)
    /// Returns (score, confidence) where confidence indicates how certain we are
    public func scoreWithConfidence(_ candidate: String) -> (score: Double, confidence: Double) {
        guard isLoaded, !contextWindow.isEmpty else {
            return (1.0, 0.0)  // No context = no confidence
        }

        let candidateSyllable = extractFirstSyllable(candidate)
        var totalEvidence = 0.0
        var maxPossibleEvidence = 0.0

        // 4-gram evidence (strongest signal)
        if contextWindow.count >= 3 {
            let ctx = "\(contextWindow[contextWindow.count - 3])|\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            maxPossibleEvidence += 40.0

            let fourgramResults = SQLiteDictionary.shared.getFourgrams(key: ctx)
            if !fourgramResults.isEmpty {
                let totalFourgram = fourgramResults.reduce(0) { $0 + $1.count }
                if let match = fourgramResults.first(where: { $0.word == candidateSyllable }) {
                    totalEvidence += (Double(match.count) / Double(max(totalFourgram, 1))) * 40.0
                }
            }
        }

        // Trigram evidence (strong signal)
        if contextWindow.count >= 2 {
            let ctx = "\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            maxPossibleEvidence += 30.0

            let trigramResults = SQLiteDictionary.shared.getTrigrams(key: ctx)
            if !trigramResults.isEmpty {
                let totalTrigram = trigramResults.reduce(0) { $0 + $1.count }
                if let match = trigramResults.first(where: { $0.word == candidateSyllable }) {
                    totalEvidence += (Double(match.count) / Double(max(totalTrigram, 1))) * 30.0
                }
            }
        }

        // Bigram evidence
        if let lastWord = contextWindow.last {
            maxPossibleEvidence += 20.0

            let bigramResults = SQLiteDictionary.shared.getBigrams(word: lastWord)
            if !bigramResults.isEmpty {
                let totalBigram = bigramResults.reduce(0) { $0 + $1.count }
                if let match = bigramResults.first(where: { $0.word == candidateSyllable }) {
                    totalEvidence += (Double(match.count) / Double(max(totalBigram, 1))) * 20.0
                }
            }
        }

        // Word frequency evidence (weak signal)
        let freq = SQLiteDictionary.shared.getWordFrequency(word: candidateSyllable)
        if freq > 0 {
            let maxFreq = SQLiteDictionary.shared.getMaxWordFrequency()
            totalEvidence += (Double(freq) / Double(maxFreq)) * 10.0
            maxPossibleEvidence += 10.0
        }

        let score = totalEvidence
        let confidence = maxPossibleEvidence > 0 ? min(totalEvidence / maxPossibleEvidence, 1.0) : 0.0

        return (score, confidence)
    }

    /// Rank suggestions with confidence info
    /// Returns: [(tibetan, originalFreq, confidence)]
    public func rankWithConfidence(_ suggestions: [(String, Int)]) -> [(String, Int, Double)] {
        guard isLoaded, !contextWindow.isEmpty else {
            return suggestions.map { ($0.0, $0.1, 0.0) }
        }

        let scored = suggestions.map { (word, freq) -> (String, Int, Double, Double) in
            let (score, confidence) = scoreWithConfidence(word)
            let adjustedScore = Double(freq) * (1.0 + score)
            return (word, freq, confidence, adjustedScore)
        }

        // Sort by adjusted score
        let sorted = scored.sorted { $0.3 > $1.3 }

        return sorted.map { ($0.0, $0.1, $0.2) }
    }

    /// Check if top suggestion should be auto-selected
    /// Returns (autoSelect, bestChoice) where autoSelect indicates if we're confident enough
    public func shouldAutoSelect(_ suggestions: [(String, Int)]) -> (autoSelect: Bool, bestChoice: String?) {
        guard !suggestions.isEmpty else {
            return (false, nil)
        }

        let ranked = rankWithConfidence(suggestions)
        guard let best = ranked.first else {
            return (false, nil)
        }

        // Auto-select if confidence >= 80%
        if best.2 >= autoSelectThreshold {
            // Also require significant margin over second choice
            if ranked.count < 2 {
                return (true, best.0)
            }
            let second = ranked[1]
            // Best must be at least 20% more confident than second
            if best.2 - second.2 >= 0.20 {
                return (true, best.0)
            }
        }

        return (false, nil)
    }

    // MARK: - Semantic Hints

    /// Get semantic hint for disambiguation based on previous context
    /// - Parameters:
    ///   - phonetic: The phonetic input to disambiguate (e.g., "chu")
    /// - Returns: Preferred Tibetan word if a semantic hint applies, nil otherwise
    public func getSemanticHint(for phonetic: String) -> String? {
        let phonLower = phonetic.lowercased()

        // 1. Check preceding context (most reliable)
        if let lastSyllable = contextWindow.last,
           let hints = semanticHintsPreceding[lastSyllable],
           let tibetan = hints[phonLower] {
            return tibetan
        }

        // 2. Check multiple preceding syllables for stronger context
        if contextWindow.count >= 2 {
            let secondLast = contextWindow[contextWindow.count - 2]
            if let hints = semanticHintsPreceding[secondLast], let tibetan = hints[phonLower] {
                return tibetan
            }
        }

        // 3. Check domain-based hints
        let domain = detectDomain()
        if let hints = domainHints[domain], let tibetan = hints[phonLower] {
            return tibetan
        }

        return nil
    }

    /// Get semantic hint with specific previous Tibetan context
    /// - Parameters:
    ///   - phonetic: The phonetic input to disambiguate
    ///   - previousTibetan: The previous Tibetan word for context
    /// - Returns: Preferred Tibetan word if a semantic hint applies
    public func getSemanticHint(for phonetic: String, after previousTibetan: String) -> String? {
        let prevSyllable = extractFirstSyllable(previousTibetan)
        let phonLower = phonetic.lowercased()

        if let hints = semanticHintsPreceding[prevSyllable], let tibetan = hints[phonLower] {
            return tibetan
        }

        return nil
    }

    /// Get semantic hint considering both preceding and following context
    /// - Parameters:
    ///   - phonetic: The phonetic input to disambiguate
    ///   - followingHint: Optional hint about what might follow
    /// - Returns: Preferred Tibetan word if a semantic hint applies
    public func getSemanticHintWithFollowing(for phonetic: String, followingHint: String? = nil) -> String? {
        let phonLower = phonetic.lowercased()

        // First try preceding context
        if let result = getSemanticHint(for: phonetic) {
            return result
        }

        // Then try following context if provided
        if let following = followingHint,
           let hints = semanticHintsFollowing[following],
           let tibetan = hints[phonLower] {
            return tibetan
        }

        return nil
    }

    /// Get all possible meanings for a homophone with their contexts
    /// - Parameter phonetic: The phonetic input
    /// - Returns: Array of (tibetan, contextDescription) tuples
    public func getHomophoneMeanings(for phonetic: String) -> [(tibetan: String, context: String)] {
        let phonLower = phonetic.lowercased()
        var meanings: [(String, String)] = []

        // Collect from preceding hints
        for (context, hints) in semanticHintsPreceding {
            if let tibetan = hints[phonLower] {
                meanings.append((tibetan, "after \(context)"))
            }
        }

        // Collect from domain hints
        for (domain, hints) in domainHints {
            if let tibetan = hints[phonLower] {
                meanings.append((tibetan, "in \(domain.rawValue) context"))
            }
        }

        // Remove duplicates
        var seen = Set<String>()
        return meanings.filter { meaning in
            if seen.contains(meaning.0) {
                return false
            }
            seen.insert(meaning.0)
            return true
        }
    }

    /// Current detected domain (read-only)
    public var detectedDomain: TextDomain {
        return currentDomain
    }

    // MARK: - Reverse Lookup (Tibetan → Phonetic)

    /// Get romanization for a Tibetan syllable via SQLite reverse_lookup table
    private func getRomanization(for tibetan: String) -> String {
        return SQLiteDictionary.shared.getReverseLookup(tibetan: tibetan) ?? ""
    }

    // MARK: - Proactive Next-Word Predictions

    /// Get predicted next words with romanization hints and confidence scores
    /// - Parameter limit: Maximum number of predictions to return
    /// - Returns: Array of predictions with Tibetan word, romanization hint, and confidence
    public func getPredictedNextWords(limit: Int = 5) -> [NextWordPrediction] {
        guard isLoaded, !contextWindow.isEmpty else {
            return []
        }

        var predictions: [String: Double] = [:]
        var totalWeight: Double = 0

        // 4-gram predictions (strongest signal)
        if contextWindow.count >= 3 {
            let ctx = "\(contextWindow[contextWindow.count - 3])|\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            let fourgramResults = SQLiteDictionary.shared.getFourgrams(key: ctx)
            if !fourgramResults.isEmpty {
                let total = Double(fourgramResults.reduce(0) { $0 + $1.count })
                for entry in fourgramResults {
                    let weight = (Double(entry.count) / max(total, 1)) * 4.0
                    predictions[entry.word, default: 0] += weight
                    totalWeight += weight
                }
            }
        }

        // Trigram predictions (strong signal)
        if contextWindow.count >= 2 {
            let ctx = "\(contextWindow[contextWindow.count - 2])|\(contextWindow.last!)"
            let trigramResults = SQLiteDictionary.shared.getTrigrams(key: ctx)
            if !trigramResults.isEmpty {
                let total = Double(trigramResults.reduce(0) { $0 + $1.count })
                for entry in trigramResults {
                    let weight = (Double(entry.count) / max(total, 1)) * 3.0
                    predictions[entry.word, default: 0] += weight
                    totalWeight += weight
                }
            }
        }

        // Bigram predictions
        if let lastWord = contextWindow.last {
            let bigramResults = SQLiteDictionary.shared.getBigrams(word: lastWord)
            if !bigramResults.isEmpty {
                let total = Double(bigramResults.reduce(0) { $0 + $1.count })
                for entry in bigramResults {
                    let weight = (Double(entry.count) / max(total, 1)) * 2.0
                    predictions[entry.word, default: 0] += weight
                    totalWeight += weight
                }
            }
        }

        guard totalWeight > 0 else { return [] }

        // Sort by weight, compute confidence, and add romanization
        let sorted = predictions.sorted { $0.value > $1.value }
        return Array(sorted.prefix(limit).map { (tibetan, weight) in
            let confidence = min(weight / totalWeight, 1.0)
            let romanization = getRomanization(for: tibetan)
            return NextWordPrediction(
                tibetan: tibetan,
                romanization: romanization,
                confidence: confidence
            )
        })
    }

    // MARK: - Proactive Particle Prediction

    /// Check if a grammatical particle is predicted next and return the grammatically correct one
    /// Combines n-gram statistics with sumtak grammar rules
    /// - Returns: The correct particle as a NextWordPrediction, or nil
    public func getParticlePrediction() -> NextWordPrediction? {
        guard isLoaded, !contextWindow.isEmpty else { return nil }

        // Known particle sets
        let genitiveParticles: Set<String> = ["གི", "ཀྱི", "གྱི", "ཡི", "འི"]
        let locativeParticles: Set<String> = ["དུ", "ཏུ", "རུ", "སུ"]
        let instrumentalParticles: Set<String> = ["གིས", "ཀྱིས", "གྱིས", "ཡིས"]
        let allParticles = genitiveParticles.union(locativeParticles).union(instrumentalParticles)

        // Get top predictions from the n-gram model
        let predictions = getPredictedNextWords(limit: 10)
        guard !predictions.isEmpty else { return nil }

        // Check if any top prediction is a particle
        var particlePrediction: NextWordPrediction?
        var particleConfidence: Double = 0

        for pred in predictions {
            if allParticles.contains(pred.tibetan) && pred.confidence > particleConfidence {
                particlePrediction = pred
                particleConfidence = pred.confidence
            }
        }

        guard particlePrediction != nil else { return nil }

        // We know a particle is likely. Now use sumtak rules to get the CORRECT one.
        guard let lastWord = contextWindow.last else { return nil }

        // Get the final letter of the last committed word
        let cleaned = lastWord.replacingOccurrences(of: "་", with: "")
        guard let finalChar = cleaned.last else { return nil }

        // Determine which particle type is predicted
        if genitiveParticles.contains(particlePrediction!.tibetan) {
            if let correct = PhraseCorrector.shared.getCorrectGenitive(after: finalChar) {
                return NextWordPrediction(
                    tibetan: correct,
                    romanization: getRomanization(for: correct),
                    confidence: particleConfidence
                )
            }
        } else if locativeParticles.contains(particlePrediction!.tibetan) {
            if let correct = PhraseCorrector.shared.getCorrectLocative(after: finalChar) {
                return NextWordPrediction(
                    tibetan: correct,
                    romanization: getRomanization(for: correct),
                    confidence: particleConfidence
                )
            }
        }
        // For instrumental and other cases, return the statistical prediction as-is
        return particlePrediction
    }
}
