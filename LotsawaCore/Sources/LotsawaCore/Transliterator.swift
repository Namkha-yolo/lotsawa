// Transliterator.swift
// LotsawaCore
//
// Main transliteration engine for converting romanized input to Tibetan/Dzongkha
// Supports phonetic input with Tibetan and Dzongkha language modes

import Foundation

/// Language/orthography mode
public enum LanguageMode: String, CaseIterable {
    case tibetan = "tibetan"   // བོད་ཡིག - Standard Tibetan (Lhasa)
    case dzongkha = "dzongkha" // རྫོང་ཁ - Bhutanese
}

/// Main transliteration engine
public class Transliterator {

    // MARK: - Properties

    public var languageMode: LanguageMode

    private var phoneticMapper: PhoneticMapper

    /// Current input buffer (romanized text)
    private var inputBuffer: String = ""

    /// Previously committed words (for context)
    private var committedWords: [String] = []

    /// Maximum words to keep for context
    private let maxContextWords = 5

    /// Predicted next words based on context (populated after each commit)
    public private(set) var nextWordPredictions: [NextWordPrediction] = []

    // MARK: - Initialization

    public init(languageMode: LanguageMode = .tibetan) {
        self.languageMode = languageMode
        self.phoneticMapper = PhoneticMapper(languageMode: languageMode)
    }

    // MARK: - Mode Switching

    /// Switch language mode
    public func setLanguageMode(_ mode: LanguageMode) {
        self.languageMode = mode
        self.phoneticMapper = PhoneticMapper(languageMode: mode)
    }

    /// Toggle between Tibetan and Dzongkha
    public func toggleLanguageMode() {
        switch languageMode {
        case .tibetan:  languageMode = .dzongkha
        case .dzongkha: languageMode = .tibetan
        }
        self.phoneticMapper = PhoneticMapper(languageMode: languageMode)
    }

    /// Get display code for current mode
    public var modeDisplayCode: String {
        languageMode == .tibetan ? "BO" : "DZ"
    }

    // MARK: - Conversion

    /// Convert romanized text to Tibetan/Dzongkha
    /// - Parameter text: Romanized input text
    /// - Returns: Tibetan/Dzongkha Unicode string
    public func convert(_ text: String) -> String {
        return phoneticMapper.convert(text)
    }

    /// Convert a single syllable
    public func convertSyllable(_ syllable: String) -> String {
        return phoneticMapper.convert(syllable)
    }

    /// Get suggestions for current input (with context-based ranking)
    /// - Parameter input: Partial romanized input
    /// - Returns: Array of possible Tibetan matches, ranked by context
    public func getSuggestions(for input: String) -> [String] {
        return phoneticMapper.getSuggestionsWithContext(for: input, previousWords: committedWords)
    }

    // MARK: - Buffer Management (for keyboard integration)

    /// Add character to input buffer
    public func appendToBuffer(_ char: Character) {
        inputBuffer.append(char)
    }

    /// Add string to input buffer
    public func appendToBuffer(_ string: String) {
        inputBuffer.append(string)
    }

    /// Remove last character from buffer
    public func backspace() {
        if !inputBuffer.isEmpty {
            inputBuffer.removeLast()
        }
    }

    /// Clear the input buffer
    public func clearBuffer() {
        inputBuffer = ""
    }

    /// Get current buffer contents
    public var buffer: String {
        return inputBuffer
    }

    /// Get suggestions for current buffer
    public var bufferSuggestions: [String] {
        return getSuggestions(for: inputBuffer)
    }

    /// Convert and clear buffer, tracking for context
    /// - Returns: The converted Tibetan text
    public func commitBuffer() -> String {
        let romanization = inputBuffer
        let result = convert(inputBuffer)
        clearBuffer()

        // Track committed word for context
        if !result.isEmpty {
            committedWords.append(result)
            // Keep only recent words
            if committedWords.count > maxContextWords {
                committedWords.removeFirst()
            }
            // Update context engine
            ContextEngine.shared.addToContext(result)

            // Record for phrase correction
            PhraseCorrector.shared.recordCommit(romanization: romanization, tibetan: result)

            // Refresh next-word predictions
            refreshPredictions()
        }

        return result
    }

    /// Check if there's a phrase correction available
    /// - Returns: Correction if found, nil otherwise
    public func checkPhraseCorrection() -> PhraseCorrection? {
        return PhraseCorrector.shared.checkForCorrection()
    }

    /// Apply a phrase correction
    /// - Parameter correction: The correction to apply
    /// - Returns: (deleteCount, newText) for the keyboard to execute
    public func applyPhraseCorrection(_ correction: PhraseCorrection) -> (Int, String) {
        return PhraseCorrector.shared.applyCorrection(correction)
    }

    /// Commit a specific suggestion (from suggestion bar)
    /// - Parameter tibetan: The Tibetan text to commit
    /// - Parameter romanization: Optional romanization (uses buffer if not provided)
    public func commitSuggestion(_ tibetan: String, romanization: String? = nil) -> String {
        let roman = romanization ?? inputBuffer
        clearBuffer()

        // Track committed suggestion for context
        committedWords.append(tibetan)
        if committedWords.count > maxContextWords {
            committedWords.removeFirst()
        }
        ContextEngine.shared.addToContext(tibetan)

        // Record for phrase correction
        PhraseCorrector.shared.recordCommit(romanization: roman, tibetan: tibetan)

        // Refresh next-word predictions
        refreshPredictions()

        return tibetan
    }

    /// Refresh next-word predictions from context engine
    private func refreshPredictions() {
        var predictions: [NextWordPrediction] = []

        // Check for grammatically correct particle prediction first
        if let particlePrediction = ContextEngine.shared.getParticlePrediction() {
            predictions.append(particlePrediction)
        }

        // Add general n-gram predictions
        let ngramPredictions = ContextEngine.shared.getPredictedNextWords(limit: 5)
        for pred in ngramPredictions {
            // Avoid duplicates (particle may already be in the list)
            if !predictions.contains(where: { $0.tibetan == pred.tibetan }) {
                predictions.append(pred)
            }
        }

        nextWordPredictions = Array(predictions.prefix(5))
    }

    /// Clear context (call on new paragraph or sentence end)
    public func clearContext() {
        committedWords.removeAll()
        nextWordPredictions.removeAll()
        ContextEngine.shared.clearContext()
        PhraseCorrector.shared.clearHistory()
    }

    /// Get current context words (for debugging)
    public var contextWords: [String] {
        return committedWords
    }

    /// Check if buffer should auto-commit (e.g., on space or punctuation)
    public func shouldCommit(after char: Character) -> Bool {
        let punctuation: Set<Character> = [".", ",", "!", "?", ";", ":"]
        return punctuation.contains(char)
    }

    /// Check if character is sentence-ending (should clear context)
    public func isSentenceEnd(_ char: Character) -> Bool {
        let sentenceEnd: Set<Character> = [".", "!", "?", "།"]
        return sentenceEnd.contains(char)
    }

    // MARK: - Utility

    /// Check if a character is a vowel in the current input mode
    public func isVowel(_ char: Character) -> Bool {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        return vowels.contains(Character(char.lowercased()))
    }

    /// Convert number to Tibetan numeral
    public func convertNumber(_ number: Int) -> String {
        let digits = String(number)
        var result = ""
        for char in digits {
            if let tibetanDigit = TibetanUnicode.numbers[char] {
                result.append(tibetanDigit)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Add tsheg (syllable separator) to text
    public func addTsheg(_ text: String) -> String {
        if text.isEmpty || text.hasSuffix(String(TibetanUnicode.tsheg)) {
            return text
        }
        return text + String(TibetanUnicode.tsheg)
    }

    /// Add shad (sentence ending) to text
    public func addShad(_ text: String) -> String {
        var result = text
        // Remove trailing tsheg if present
        if result.hasSuffix(String(TibetanUnicode.tsheg)) {
            result.removeLast()
        }
        return result + String(TibetanUnicode.shad)
    }
}

// MARK: - Static Convenience Methods

extension Transliterator {

    /// Quick convert phonetic to Tibetan
    public static func fromPhonetic(_ phonetic: String, languageMode: LanguageMode = .tibetan) -> String {
        let mapper = PhoneticMapper(languageMode: languageMode)
        return mapper.convert(phonetic)
    }
}
