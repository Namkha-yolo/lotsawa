// UserLearningStore.swift
// LotsawaCore
//
// Stores user preferences and learning data for personalized suggestions.
// All data is stored locally in the App Group container.

import Foundation

/// Stores a user's selection for a phonetic input
public struct UserSelection: Codable {
    public let phonetic: String
    public let selected: String
    public let alternatives: [String]
    public let timestamp: Date
    public var count: Int

    public init(phonetic: String, selected: String, alternatives: [String]) {
        self.phonetic = phonetic
        self.selected = selected
        self.alternatives = alternatives
        self.timestamp = Date()
        self.count = 1
    }
}

/// Stores a user correction
public struct UserCorrection: Codable {
    public let original: String
    public let corrected: String
    public let timestamp: Date
    public var count: Int

    public init(original: String, corrected: String) {
        self.original = original
        self.corrected = corrected
        self.timestamp = Date()
        self.count = 1
    }
}

/// Personal vocabulary entry
public struct PersonalWord: Codable {
    public let phonetic: String
    public let tibetan: String
    public let addedDate: Date
    public var usageCount: Int

    public init(phonetic: String, tibetan: String) {
        self.phonetic = phonetic
        self.tibetan = tibetan
        self.addedDate = Date()
        self.usageCount = 0
    }
}

/// Manages user learning data with privacy-focused local storage
public class UserLearningStore {

    // MARK: - Singleton

    /// Shared instance
    public static let shared = UserLearningStore()

    // MARK: - Properties

    /// User selections: phonetic → [selected → count]
    private var selections: [String: [String: Int]] = [:]

    /// User corrections: original → corrected
    private var corrections: [String: String] = [:]

    /// Personal vocabulary: phonetic → tibetan
    private var personalVocabulary: [String: String] = [:]

    /// Full selection history for weight decay
    private var selectionHistory: [UserSelection] = []

    /// Correction history
    private var correctionHistory: [UserCorrection] = []

    /// Maximum stored preferences
    private let maxPreferences = 1000

    /// Maximum stored corrections
    private let maxCorrections = 200

    /// Maximum personal words
    private let maxPersonalWords = 500

    /// Weight decay half-life in days (preferences decay over time)
    private let decayHalfLifeDays: Double = 30.0

    /// Whether data has been loaded
    private var isLoaded = false

    /// App Group identifier for shared storage
    private let appGroupIdentifier = "group.com.lotsawa.keyboard"

    // MARK: - Initialization

    private init() {
        loadData()
    }

    // MARK: - Public Interface

    /// Record when user selects a suggestion
    /// - Parameters:
    ///   - phonetic: The phonetic input (e.g., "chu")
    ///   - selected: The Tibetan word selected (e.g., "ཆུ")
    ///   - alternatives: Other options that were available
    public func recordSelection(phonetic: String, selected: String, alternatives: [String]) {
        let key = phonetic.lowercased()

        // Update quick lookup
        if selections[key] == nil {
            selections[key] = [:]
        }
        selections[key]![selected, default: 0] += 1

        // Add to history
        if let existingIndex = selectionHistory.firstIndex(where: {
            $0.phonetic == key && $0.selected == selected
        }) {
            selectionHistory[existingIndex].count += 1
        } else {
            let selection = UserSelection(
                phonetic: key,
                selected: selected,
                alternatives: alternatives
            )
            selectionHistory.append(selection)
        }

        // Enforce limits
        enforceSelectionLimits()

        // Save asynchronously
        saveDataAsync()
    }

    /// Record when user corrects a word
    /// - Parameters:
    ///   - original: The original Tibetan text
    ///   - corrected: The corrected Tibetan text
    public func recordCorrection(original: String, corrected: String) {
        corrections[original] = corrected

        // Add to history
        if let existingIndex = correctionHistory.firstIndex(where: {
            $0.original == original && $0.corrected == corrected
        }) {
            correctionHistory[existingIndex].count += 1
        } else {
            let correction = UserCorrection(original: original, corrected: corrected)
            correctionHistory.append(correction)
        }

        // Enforce limits
        enforceCorrectionLimits()

        saveDataAsync()
    }

    /// Add a personal vocabulary word
    /// - Parameters:
    ///   - phonetic: The phonetic romanization
    ///   - tibetan: The Tibetan word
    public func addPersonalWord(phonetic: String, tibetan: String) {
        let key = phonetic.lowercased()
        personalVocabulary[key] = tibetan

        // Enforce limits (remove oldest if needed)
        if personalVocabulary.count > maxPersonalWords {
            // Simple FIFO - remove first added
            if let firstKey = personalVocabulary.keys.first {
                personalVocabulary.removeValue(forKey: firstKey)
            }
        }

        saveDataAsync()
    }

    /// Remove a personal vocabulary word
    public func removePersonalWord(phonetic: String) {
        let key = phonetic.lowercased()
        personalVocabulary.removeValue(forKey: key)
        saveDataAsync()
    }

    /// Get personalized weight for a candidate
    /// - Parameters:
    ///   - phonetic: The phonetic input
    ///   - tibetan: The Tibetan candidate
    /// - Returns: Weight multiplier (1.0 = no preference, >1.0 = preferred)
    public func getWeight(phonetic: String, tibetan: String) -> Double {
        let key = phonetic.lowercased()

        // Check personal vocabulary first (highest priority)
        if let personal = personalVocabulary[key], personal == tibetan {
            return 3.0
        }

        // Check corrections (if this was a corrected form)
        for (original, corrected) in corrections {
            if corrected == tibetan {
                return 2.0
            }
            if original == tibetan {
                return 0.5 // Penalize words user corrected away from
            }
        }

        // Check selection history with decay
        guard let selectionCounts = selections[key] else {
            return 1.0
        }

        guard let count = selectionCounts[tibetan] else {
            return 1.0
        }

        // Calculate decayed weight
        let decayedCount = applyDecay(count: count, phonetic: key, tibetan: tibetan)

        // Weight boost based on selection count
        // 1 selection → 1.2x, 5 selections → 2.0x, 10+ selections → 2.5x
        let weight = 1.0 + min(1.5, Double(decayedCount) * 0.2)

        return weight
    }

    /// Get the user's preferred Tibetan for a phonetic input
    /// - Parameter phonetic: The phonetic input
    /// - Returns: User's most selected Tibetan, or nil if no preference
    public func getPreferred(for phonetic: String) -> String? {
        let key = phonetic.lowercased()

        // Check personal vocabulary first
        if let personal = personalVocabulary[key] {
            return personal
        }

        // Check selections
        guard let selectionCounts = selections[key] else {
            return nil
        }

        // Return most selected (with decay applied)
        let best = selectionCounts.max { a, b in
            applyDecay(count: a.value, phonetic: key, tibetan: a.key) <
            applyDecay(count: b.value, phonetic: key, tibetan: b.key)
        }

        // Only return if count is significant
        if let best = best, best.value >= 3 {
            return best.key
        }

        return nil
    }

    /// Check if a correction exists for the given text
    public func getCorrection(for original: String) -> String? {
        return corrections[original]
    }

    /// Get all personal vocabulary words
    public func getAllPersonalWords() -> [(phonetic: String, tibetan: String)] {
        return personalVocabulary.map { ($0.key, $0.value) }
    }

    /// Clear all learning data
    public func clearAllData() {
        selections = [:]
        corrections = [:]
        personalVocabulary = [:]
        selectionHistory = []
        correctionHistory = []
        saveDataAsync()
    }

    // MARK: - Private Methods

    /// Apply time-based decay to selection count
    private func applyDecay(count: Int, phonetic: String, tibetan: String) -> Int {
        // Find the most recent selection timestamp
        guard let selection = selectionHistory.first(where: {
            $0.phonetic == phonetic && $0.selected == tibetan
        }) else {
            return count
        }

        let daysSinceSelection = Date().timeIntervalSince(selection.timestamp) / (24 * 60 * 60)
        let decayFactor = pow(0.5, daysSinceSelection / decayHalfLifeDays)

        return max(1, Int(Double(count) * decayFactor))
    }

    /// Enforce selection history limits
    private func enforceSelectionLimits() {
        if selectionHistory.count > maxPreferences {
            // Remove oldest entries
            selectionHistory.sort { $0.timestamp > $1.timestamp }
            selectionHistory = Array(selectionHistory.prefix(maxPreferences))

            // Rebuild quick lookup
            rebuildSelectionsLookup()
        }
    }

    /// Enforce correction history limits
    private func enforceCorrectionLimits() {
        if correctionHistory.count > maxCorrections {
            // Remove oldest entries
            correctionHistory.sort { $0.timestamp > $1.timestamp }
            correctionHistory = Array(correctionHistory.prefix(maxCorrections))

            // Rebuild corrections lookup
            corrections = [:]
            for correction in correctionHistory {
                corrections[correction.original] = correction.corrected
            }
        }
    }

    /// Rebuild selections lookup from history
    private func rebuildSelectionsLookup() {
        selections = [:]
        for selection in selectionHistory {
            if selections[selection.phonetic] == nil {
                selections[selection.phonetic] = [:]
            }
            selections[selection.phonetic]![selection.selected, default: 0] += selection.count
        }
    }

    // MARK: - Persistence

    /// Get the storage URL for learning data
    private func getStorageURL() -> URL? {
        // Try App Group container first (for keyboard extension)
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            return containerURL.appendingPathComponent("learning_data.json")
        }

        // Fallback to documents directory
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        return documentsURL.appendingPathComponent("lotsawa_learning.json")
    }

    /// Load learning data from storage
    private func loadData() {
        guard !isLoaded else { return }

        guard let url = getStorageURL() else {
            print("UserLearningStore: No storage URL available")
            isLoaded = true
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("UserLearningStore: No existing data file")
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let stored = try JSONDecoder().decode(StoredLearningData.self, from: data)

            self.selectionHistory = stored.selectionHistory
            self.correctionHistory = stored.correctionHistory
            self.personalVocabulary = stored.personalVocabulary

            // Rebuild lookups
            rebuildSelectionsLookup()
            for correction in correctionHistory {
                corrections[correction.original] = correction.corrected
            }

            isLoaded = true
            print("UserLearningStore: Loaded \(selectionHistory.count) selections, \(correctionHistory.count) corrections, \(personalVocabulary.count) personal words")

        } catch {
            print("UserLearningStore: Failed to load data: \(error)")
            isLoaded = true
        }
    }

    /// Save learning data to storage
    private func saveData() {
        guard let url = getStorageURL() else {
            print("UserLearningStore: No storage URL available")
            return
        }

        let stored = StoredLearningData(
            selectionHistory: selectionHistory,
            correctionHistory: correctionHistory,
            personalVocabulary: personalVocabulary
        )

        do {
            let data = try JSONEncoder().encode(stored)
            try data.write(to: url, options: .atomic)
        } catch {
            print("UserLearningStore: Failed to save data: \(error)")
        }
    }

    /// Save data asynchronously to avoid blocking
    private func saveDataAsync() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.saveData()
        }
    }
}

// MARK: - Storage Structure

/// Structure for persisting learning data
private struct StoredLearningData: Codable {
    let selectionHistory: [UserSelection]
    let correctionHistory: [UserCorrection]
    let personalVocabulary: [String: String]
}
