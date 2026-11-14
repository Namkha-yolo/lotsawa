// PhraseCorrector.swift
// LotsawaCore
//
// Retroactive phrase correction system for Tibetan keyboard.
// Tracks romanization history and suggests corrections when
// a sequence of words matches a known phrase.

import Foundation

/// Entry tracking a committed word with its romanization
public struct CommittedWord {
    let romanization: String
    let tibetan: String
    let textLength: Int  // Length in the text field (for deletion)
}

/// Correction suggestion with old and new text
public struct PhraseCorrection {
    public let oldTibetan: String      // What was typed
    public let newTibetan: String      // What it should be
    public let deleteCount: Int        // Characters to delete
    public let reason: String          // Why this correction (for UI)
}

/// Retroactive phrase correction engine
public class PhraseCorrector {

    /// Shared singleton instance
    public static let shared = PhraseCorrector()

    /// History of committed words (romanization + tibetan)
    private var history: [CommittedWord] = []

    /// Maximum history to keep
    private let maxHistory = 5

    /// Phrase dictionary: "romanized phrase" → "correct tibetan"
    private var phraseLookup: [String: String] = [:]

    /// Phonetic variations loaded from phonetic_variations.json
    private var phoneticVariations: [String: [String]] = [:]

    /// Sumtak grammar rules for particle selection
    private var sumtakRules: SumtakRules?

    /// Sumtak rules structure
    struct SumtakRules: Codable {
        let genitive: [String: String]
        let locative: [String: String]
        let instrumental: [String: String]
        let particle_variants: [String: [String]]
    }

    private init() {
        loadPhoneticVariations()
        loadSumtakRules()
        loadPhraseLookup()
    }

    /// Load phonetic variations from JSON
    private func loadPhoneticVariations() {
        guard let url = Bundle.module.url(forResource: "phonetic_variations", withExtension: "json") else {
            print("PhraseCorrector: phonetic_variations.json not found, using defaults")
            loadDefaultVariations()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            phoneticVariations = try JSONDecoder().decode([String: [String]].self, from: data)
            print("PhraseCorrector: Loaded \(phoneticVariations.count) phonetic variations")
        } catch {
            print("PhraseCorrector: Failed to load phonetic variations: \(error)")
            loadDefaultVariations()
        }
    }

    /// Load sumtak grammar rules
    private func loadSumtakRules() {
        guard let url = Bundle.module.url(forResource: "sumtak_rules", withExtension: "json") else {
            print("PhraseCorrector: sumtak_rules.json not found")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            sumtakRules = try JSONDecoder().decode(SumtakRules.self, from: data)
            print("PhraseCorrector: Loaded sumtak rules")
        } catch {
            print("PhraseCorrector: Failed to load sumtak rules: \(error)")
        }
    }

    /// Default phonetic variations if JSON not found
    private func loadDefaultVariations() {
        phoneticVariations = [
            "choe": ["khyö", "khyo", "khye", "chö", "cho"],
            "cho": ["khyo", "kho", "chö", "khye"],
            "khyo": ["khyö", "khye", "choe", "cho"],
            "khye": ["khyö", "khyo", "choe"],
            "gi": ["kyi", "gyi", "yi", "ki"],
            "ki": ["kyi", "gyi", "gi"],
            "kyi": ["gi", "ki", "gyi"],
        ]
    }

    /// Load phrase lookup from SQLite database.
    /// Multi-word phrases are now stored in the `phrases` table.
    private func loadPhraseLookup() {
        // Add common hardcoded phrases
        addCommonPhrases()
        // Note: Multi-word phrases from the dictionary are now looked up
        // on-demand via SQLiteDictionary.shared.getPhraseLookup() in checkForCorrection().
        print("PhraseCorrector: Loaded \(phraseLookup.count) hardcoded phrases (DB has 38K+ on-demand)")
    }

    /// Add common phrases that need special handling
    /// Includes all regional phonetic variations
    private func addCommonPhrases() {
        // "your name" - ཁྱོད་ཀྱི་མིང་ - all variations
        let yourName = "ཁྱོད་ཀྱི་མིང"
        // Standard Tibetan
        phraseLookup["khyö kyi ming"] = yourName
        phraseLookup["khyo kyi ming"] = yourName
        phraseLookup["khyö gi ming"] = yourName
        phraseLookup["khyo gi ming"] = yourName
        // Common pronunciation
        phraseLookup["khye ki ming"] = yourName
        phraseLookup["khye kyi ming"] = yourName
        phraseLookup["khye gi ming"] = yourName
        // Bhutanese/Dzongkha pronunciation
        phraseLookup["choe gi ming"] = yourName
        phraseLookup["choe ki ming"] = yourName
        phraseLookup["choe kyi ming"] = yourName
        phraseLookup["cho gi ming"] = yourName
        phraseLookup["cho ki ming"] = yourName

        // "my name" - ང་ཡི་མིང་
        let myName = "ང་ཡི་མིང"
        phraseLookup["ngé ming"] = myName
        phraseLookup["ngai ming"] = myName
        phraseLookup["nga yi ming"] = myName
        phraseLookup["nga'i ming"] = myName
        phraseLookup["nge ming"] = myName

        // "what is your name" - ཁྱོད་ཀྱི་མིང་ལ་ག་རེ
        let whatIsYourName = "ཁྱོད་ཀྱི་མིང་ལ་ག་རེ"
        phraseLookup["khyö kyi ming la gare"] = whatIsYourName
        phraseLookup["khye ki ming la gare"] = whatIsYourName
        phraseLookup["choe gi ming la gare"] = whatIsYourName
        phraseLookup["khyö kyi ming gare"] = whatIsYourName
        phraseLookup["choe gi ming gare"] = whatIsYourName

        // "how are you" - ཁྱོད་བདེ་མོ་ཡིན་པས
        let howAreYou = "ཁྱོད་བདེ་མོ་ཡིན་པས"
        phraseLookup["khyö demo yinpé"] = howAreYou
        phraseLookup["khye demo yinpe"] = howAreYou
        phraseLookup["choe demo yinpe"] = howAreYou

        // Common dharma phrases
        phraseLookup["sangye chö gendün"] = "སངས་རྒྱས་ཆོས་དགེ་འདུན"
        phraseLookup["sangye cho gendun"] = "སངས་རྒྱས་ཆོས་དགེ་འདུན"
        phraseLookup["könchok sum"] = "དཀོན་མཆོག་གསུམ"
        phraseLookup["konchok sum"] = "དཀོན་མཆོག་གསུམ"

        // "I go" vs "I am" disambiguation
        phraseLookup["nga dro"] = "ང་འགྲོ"
        phraseLookup["nga yin"] = "ང་ཡིན"

        // Tashi Delek variations
        phraseLookup["tashi delek"] = "བཀྲ་ཤིས་བདེ་ལེགས"
        phraseLookup["tashee delek"] = "བཀྲ་ཤིས་བདེ་ལེགས"
        phraseLookup["tashi deleg"] = "བཀྲ་ཤིས་བདེ་ལེགས"

        // Common verb phrases - Present continuous (za gi yö = am eating)
        let eating = "ཁ་ལག་ཟ་གི་ཡོད"
        phraseLookup["kha laza gi yoe"] = eating
        phraseLookup["kha laza gi yo"] = eating
        phraseLookup["kha laza gi yö"] = eating
        phraseLookup["khalak za gi yoe"] = eating
        phraseLookup["khalak za gi yo"] = eating
        phraseLookup["kha lag za gi yoe"] = eating
        phraseLookup["kha lag za gi yo"] = eating

        // "I am eating" - full phrase
        let iAmEating = "ང་ཁ་ལག་ཟ་གི་ཡོད"
        phraseLookup["nga kha laza gi yoe"] = iAmEating
        phraseLookup["nga kha laza gi yo"] = iAmEating
        phraseLookup["nga khalak za gi yoe"] = iAmEating
        phraseLookup["nga khalak za gi yo"] = iAmEating
        phraseLookup["nga kha lag za gi yoe"] = iAmEating
        phraseLookup["nga za gi yoe"] = "ང་ཟ་གི་ཡོད"  // I am eating (without "food")
        phraseLookup["nga za gi yo"] = "ང་ཟ་གི་ཡོད"

        // "I am drinking"
        let iAmDrinking = "ང་ཐུང་གི་ཡོད"
        phraseLookup["nga thung gi yoe"] = iAmDrinking
        phraseLookup["nga tung gi yoe"] = iAmDrinking
        phraseLookup["nga thung gi yo"] = iAmDrinking

        // "I am going"
        let iAmGoing = "ང་འགྲོ་གི་ཡོད"
        phraseLookup["nga dro gi yoe"] = iAmGoing
        phraseLookup["nga dro gi yo"] = iAmGoing
        phraseLookup["nga drogi yoe"] = iAmGoing

        // "I am coming"
        let iAmComing = "ང་ཡོང་གི་ཡོད"
        phraseLookup["nga yong gi yoe"] = iAmComing
        phraseLookup["nga yong gi yo"] = iAmComing

        // "I am doing/making"
        let iAmDoing = "ང་བྱེད་ཀྱི་ཡོད"
        phraseLookup["nga je kyi yoe"] = iAmDoing
        phraseLookup["nga che kyi yoe"] = iAmDoing
        phraseLookup["nga jé kyi yo"] = iAmDoing

        // Common nouns that get split incorrectly
        phraseLookup["kha lag"] = "ཁ་ལག"  // food
        phraseLookup["khalak"] = "ཁ་ལག"
        phraseLookup["kha lak"] = "ཁ་ལག"
        phraseLookup["chu"] = "ཆུ"  // water (also number 10)
        phraseLookup["ja"] = "ཇ"  // tea
        phraseLookup["chang"] = "ཆང"  // beer/alcohol
    }

    // MARK: - Public Interface

    /// Record a committed word
    /// - Parameters:
    ///   - romanization: The romanized input (e.g., "choe")
    ///   - tibetan: The committed Tibetan text (e.g., "ཆོས")
    public func recordCommit(romanization: String, tibetan: String) {
        // Calculate text length including tsheg
        let textLength = tibetan.count + 1  // +1 for tsheg

        let entry = CommittedWord(
            romanization: romanization.lowercased(),
            tibetan: tibetan,
            textLength: textLength
        )

        history.append(entry)

        // Keep history bounded
        if history.count > maxHistory {
            history.removeFirst()
        }
    }

    /// Check if the recent history matches a phrase that should be corrected
    /// - Returns: Correction if found, nil otherwise
    public func checkForCorrection() -> PhraseCorrection? {
        guard history.count >= 2 else { return nil }

        // First check for particle corrections based on sumtak rules
        if let particleCorrection = checkSumtakParticleCorrection() {
            return particleCorrection
        }

        // Try combinations of recent words (2, 3, 4 words)
        for windowSize in (2...min(4, history.count)).reversed() {
            let startIndex = history.count - windowSize
            let recentWords = Array(history[startIndex...])

            // Build romanization string
            let romanized = recentWords.map { $0.romanization }.joined(separator: " ")
            let currentTibetan = recentWords.map { $0.tibetan }.joined(separator: "་")

            // Check direct match (hardcoded phrases first, then SQLite)
            let correctTibetan = phraseLookup[romanized]
                ?? SQLiteDictionary.shared.getPhraseLookup(phonetic: romanized)
            if let correctTibetan = correctTibetan,
               correctTibetan != currentTibetan {
                let deleteCount = recentWords.reduce(0) { $0 + $1.textLength }
                return PhraseCorrection(
                    oldTibetan: currentTibetan,
                    newTibetan: correctTibetan,
                    deleteCount: deleteCount,
                    reason: "Phrase: \(romanized)"
                )
            }

            // Check phonetic variations
            if let correction = checkPhoneticVariations(recentWords: recentWords) {
                return correction
            }
        }

        return nil
    }

    // MARK: - Sumtak Grammar Rules

    /// Check if the last particle should be corrected based on sumtak rules
    /// e.g., After ས ending, "gi" should be "kyi" (ཀྱི not གི)
    private func checkSumtakParticleCorrection() -> PhraseCorrection? {
        guard history.count >= 2,
              let rules = sumtakRules else { return nil }

        let lastWord = history[history.count - 1]
        let prevWord = history[history.count - 2]

        // Get the final letter of the previous Tibetan word
        guard let finalLetter = getLastTibetanLetter(prevWord.tibetan) else { return nil }

        // Check if last word is a particle (gi, kyi, gyi, etc.)
        let particleRomanizations = ["gi", "ki", "kyi", "gyi", "yi", "i",
                                      "gis", "kis", "kyis", "gyis", "yis",
                                      "du", "tu", "ru", "su"]

        guard particleRomanizations.contains(lastWord.romanization.lowercased()) else {
            return nil
        }

        // Determine which particle type this is
        let isGenitive = ["gi", "ki", "kyi", "gyi", "yi", "i"].contains(lastWord.romanization.lowercased())
        let isInstrumental = ["gis", "kis", "kyis", "gyis", "yis"].contains(lastWord.romanization.lowercased())
        let isLocative = ["du", "tu", "ru", "su"].contains(lastWord.romanization.lowercased())

        var correctParticle: String?

        if isGenitive {
            correctParticle = rules.genitive[String(finalLetter)]
        } else if isInstrumental {
            correctParticle = rules.instrumental[String(finalLetter)]
        } else if isLocative {
            correctParticle = rules.locative[String(finalLetter)]
        }

        // If we found a correct particle and it's different from what was typed
        if let correct = correctParticle, correct != lastWord.tibetan {
            return PhraseCorrection(
                oldTibetan: lastWord.tibetan,
                newTibetan: correct,
                deleteCount: lastWord.textLength,
                reason: "Sumtak: After \(finalLetter) use \(correct)"
            )
        }

        return nil
    }

    /// Extract the last base consonant from a Tibetan word
    private func getLastTibetanLetter(_ tibetan: String) -> Character? {
        // Remove tsheg and get last syllable
        let cleaned = tibetan.replacingOccurrences(of: "་", with: "")
        guard !cleaned.isEmpty else { return nil }

        // Tibetan suffix consonants
        let suffixes: Set<Character> = ["ག", "ང", "ད", "ན", "བ", "མ", "འ", "ར", "ལ", "ས"]

        // Check last character
        if let last = cleaned.last, suffixes.contains(last) {
            return last
        }

        // If no suffix, check if it ends in a vowel (འི pattern)
        let vowelSigns: Set<Character> = ["\u{0F72}", "\u{0F74}", "\u{0F7A}", "\u{0F7C}", "\u{0F71}"]
        if let last = cleaned.last, vowelSigns.contains(last) {
            return "vowel".first  // Special marker for vowel ending
        }

        return cleaned.last
    }

    /// Get correct genitive particle for a given final letter
    public func getCorrectGenitive(after finalLetter: Character) -> String? {
        return sumtakRules?.genitive[String(finalLetter)]
    }

    /// Get correct locative particle for a given final letter
    public func getCorrectLocative(after finalLetter: Character) -> String? {
        return sumtakRules?.locative[String(finalLetter)]
    }

    /// Check if phonetic variations of the recent words match a phrase
    private func checkPhoneticVariations(recentWords: [CommittedWord]) -> PhraseCorrection? {
        let romanizations = recentWords.map { $0.romanization }
        let currentTibetan = recentWords.map { $0.tibetan }.joined(separator: "་")

        // Generate all phonetic variations
        let variations = generateVariations(romanizations)

        for variation in variations {
            let varPhrase = variation.joined(separator: " ")

            if let correctTibetan = phraseLookup[varPhrase],
               correctTibetan != currentTibetan {
                let deleteCount = recentWords.reduce(0) { $0 + $1.textLength }
                return PhraseCorrection(
                    oldTibetan: currentTibetan,
                    newTibetan: correctTibetan,
                    deleteCount: deleteCount,
                    reason: "Did you mean: \(varPhrase)?"
                )
            }
        }

        return nil
    }

    /// Generate all phonetic variations of a word sequence
    private func generateVariations(_ words: [String]) -> [[String]] {
        guard !words.isEmpty else { return [[]] }

        let firstWord = words[0]
        let rest = Array(words.dropFirst())

        // Get variations for first word
        var firstVariations = [firstWord]
        if let vars = phoneticVariations[firstWord] {
            firstVariations.append(contentsOf: vars)
        }

        // Recursively get variations for rest
        let restVariations = generateVariations(rest)

        // Combine
        var result: [[String]] = []
        for first in firstVariations {
            for restVar in restVariations {
                result.append([first] + restVar)
            }
        }

        return result
    }

    /// Clear history (call on sentence end or field change)
    public func clearHistory() {
        history.removeAll()
    }

    /// Get current history for debugging
    public var currentHistory: [(String, String)] {
        return history.map { ($0.romanization, $0.tibetan) }
    }

    /// Apply a correction by returning text operations
    /// - Parameter correction: The correction to apply
    /// - Returns: (deleteCount, newText) tuple
    public func applyCorrection(_ correction: PhraseCorrection) -> (Int, String) {
        // Clear the history entries that were corrected
        let wordCount = correction.oldTibetan.split(separator: "་").count
        for _ in 0..<wordCount {
            if !history.isEmpty {
                history.removeLast()
            }
        }

        return (correction.deleteCount, correction.newTibetan)
    }
}
