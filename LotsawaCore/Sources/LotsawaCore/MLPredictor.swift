// MLPredictor.swift
// LotsawaCore
//
// CoreML wrapper for Tibetan word prediction from phonetic input.
// Designed for keyboard extension with strict memory constraints (<40MB total).

import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Prediction result from ML model
public struct MLPrediction {
    public let tibetan: String
    public let confidence: Double
    public let source: PredictionSource

    public enum PredictionSource {
        case model       // From CoreML model
        case cache       // From prediction cache
        case fallback    // From fallback rules
    }
}

/// CoreML-based predictor for Tibetan text
public class MLPredictor {

    // MARK: - Singleton

    /// Shared instance (lazy loaded)
    public static let shared = MLPredictor()

    // MARK: - Properties

    /// Whether the model is currently loaded
    public private(set) var isModelLoaded: Bool = false

    /// Whether loading is in progress
    private var isLoading: Bool = false

    /// Model load error (if any)
    public private(set) var loadError: Error?

    #if canImport(CoreML)
    /// The CoreML model (optional - may not exist)
    private var model: MLModel?
    #endif

    /// Prediction cache for frequently used inputs
    private var predictionCache: [String: [MLPrediction]] = [:]

    /// Maximum cache size
    private let maxCacheSize = 500

    /// Model file name
    private let modelFileName = "TibetanLM"

    /// Minimum confidence threshold for predictions
    private let minConfidence: Double = 0.1

    /// Load delay in seconds (to avoid memory spike on keyboard launch)
    private let loadDelay: TimeInterval = 3.0

    // MARK: - Vocabulary

    /// Phonetic character to index mapping
    private var phoneticCharVocab: [String: Int] = [:]

    /// Tibetan word to index mapping
    private var tibetanWordVocab: [String: Int] = [:]

    /// Index to Tibetan word mapping (reverse of tibetanWordVocab)
    private var idxToTibetan: [Int: String] = [:]

    /// Maximum phonetic input length (must match training config)
    private let phoneticMaxLen = 20

    // MARK: - Initialization

    private init() {
        // Don't load model immediately - wait for explicit load call
    }

    // MARK: - Model Lifecycle

    /// Load the model asynchronously after a delay
    /// Call this when keyboard appears, model loads after delay to avoid memory spike
    public func loadModelDelayed() {
        guard !isModelLoaded && !isLoading else { return }

        isLoading = true

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + loadDelay) { [weak self] in
            self?.loadModel()
        }
    }

    /// Load the model immediately
    public func loadModelNow() {
        guard !isModelLoaded && !isLoading else { return }

        isLoading = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadModel()
        }
    }

    /// Internal model loading
    private func loadModel() {
        // Load vocabulary first
        loadVocabulary()

        #if canImport(CoreML)

        // Try to find the model in the bundle
        let bundle = Bundle.module

        guard let modelURL = bundle.url(
            forResource: modelFileName,
            withExtension: "mlmodelc"
        ) else {
            // Also try .mlpackage
            if let packageURL = bundle.url(
                forResource: modelFileName,
                withExtension: "mlpackage"
            ) {
                loadFromURL(packageURL)
                return
            }

            print("MLPredictor: Model file not found, using fallback predictions")
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                self?.loadError = MLPredictorError.modelNotFound
            }
            return
        }

        loadFromURL(modelURL)

        #else
        print("MLPredictor: CoreML not available on this platform")
        isLoading = false
        loadError = MLPredictorError.coreMLNotAvailable
        #endif
    }

    /// Load vocabulary from ml_vocab.json
    private func loadVocabulary() {
        let bundle = Bundle.module
        guard let vocabURL = bundle.url(forResource: "ml_vocab", withExtension: "json"),
              let data = try? Data(contentsOf: vocabURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("MLPredictor: Could not load ml_vocab.json")
            return
        }

        if let charVocab = json["phonetic_char_vocab"] as? [String: Int] {
            phoneticCharVocab = charVocab
        }
        if let wordVocab = json["tibetan_word_vocab"] as? [String: Int] {
            tibetanWordVocab = wordVocab
            idxToTibetan = Dictionary(uniqueKeysWithValues: wordVocab.map { ($0.value, $0.key) })
        }

        print("MLPredictor: Loaded vocab - \(phoneticCharVocab.count) chars, \(tibetanWordVocab.count) words")
    }

    #if canImport(CoreML)
    /// Load model from URL
    private func loadFromURL(_ url: URL) {
        do {
            // Configure model for reduced memory usage
            let config = MLModelConfiguration()
            config.computeUnits = .cpuOnly  // Use CPU to reduce memory pressure

            let loadedModel = try MLModel(contentsOf: url, configuration: config)

            DispatchQueue.main.async { [weak self] in
                self?.model = loadedModel
                self?.isModelLoaded = true
                self?.isLoading = false
                self?.loadError = nil
                print("MLPredictor: Model loaded successfully")
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.isLoading = false
                self?.loadError = error
                print("MLPredictor: Failed to load model: \(error)")
            }
        }
    }
    #endif

    /// Unload the model to free memory
    /// Call this when keyboard is dismissed
    public func unloadModel() {
        #if canImport(CoreML)
        model = nil
        #endif
        isModelLoaded = false
        isLoading = false

        // Keep some cache for quick restart
        if predictionCache.count > 100 {
            // Keep only most recent 100 entries
            let sortedKeys = Array(predictionCache.keys.prefix(100))
            let newCache = sortedKeys.reduce(into: [String: [MLPrediction]]()) { result, key in
                result[key] = predictionCache[key]
            }
            predictionCache = newCache
        }

        print("MLPredictor: Model unloaded")
    }

    // MARK: - Prediction

    /// Get ML-boosted predictions for phonetic input
    /// - Parameters:
    ///   - phonetic: The phonetic input string
    ///   - context: Previous Tibetan words for context
    ///   - limit: Maximum number of predictions
    /// - Returns: Array of predictions with confidence scores
    public func predict(
        phonetic: String,
        context: [String] = [],
        limit: Int = 5
    ) -> [MLPrediction] {

        let cacheKey = makeCacheKey(phonetic: phonetic, context: context)

        // Check cache first
        if let cached = predictionCache[cacheKey] {
            return Array(cached.prefix(limit))
        }

        // If model not loaded, use fallback
        guard isModelLoaded else {
            return getFallbackPredictions(phonetic: phonetic, context: context, limit: limit)
        }

        #if canImport(CoreML)
        // Run model prediction
        guard let model = model else {
            return getFallbackPredictions(phonetic: phonetic, context: context, limit: limit)
        }

        do {
            let predictions = try runModelPrediction(
                model: model,
                phonetic: phonetic,
                context: context,
                limit: limit
            )

            // Cache the result
            cacheResult(key: cacheKey, predictions: predictions)

            return predictions
        } catch {
            print("MLPredictor: Prediction failed: \(error)")
            return getFallbackPredictions(phonetic: phonetic, context: context, limit: limit)
        }
        #else
        return getFallbackPredictions(phonetic: phonetic, context: context, limit: limit)
        #endif
    }

    /// Get confidence boost for a specific candidate
    /// - Parameters:
    ///   - tibetan: The Tibetan candidate to score
    ///   - phonetic: The phonetic input
    ///   - context: Previous Tibetan words
    /// - Returns: Confidence multiplier (1.0 = no boost, >1.0 = ML boost)
    public func getConfidenceBoost(
        tibetan: String,
        phonetic: String,
        context: [String] = []
    ) -> Double {

        let predictions = predict(phonetic: phonetic, context: context, limit: 10)

        // Find this candidate in predictions
        if let prediction = predictions.first(where: { $0.tibetan == tibetan }) {
            return 1.0 + prediction.confidence
        }

        return 1.0
    }

    // MARK: - Private Methods

    /// Encode phonetic input string as padded character indices
    private func encodePhonetic(_ text: String) -> [Int32] {
        let lowered = text.lowercased()
        let unkIdx = Int32(phoneticCharVocab["<UNK>"] ?? 1)
        var indices = [Int32]()

        for char in lowered.prefix(phoneticMaxLen) {
            let idx = phoneticCharVocab[String(char)] ?? Int(unkIdx)
            indices.append(Int32(idx))
        }

        // Pad to phoneticMaxLen
        while indices.count < phoneticMaxLen {
            indices.append(0) // PAD
        }

        return indices
    }

    /// Get context word index from previous Tibetan words
    private func encodeContext(_ context: [String]) -> Int32 {
        // Use the most recent context word that's in our vocabulary
        for word in context.reversed() {
            if let idx = tibetanWordVocab[word] {
                return Int32(idx)
            }
        }
        return 0 // No context / PAD
    }

    #if canImport(CoreML)
    /// Run the actual model prediction
    private func runModelPrediction(
        model: MLModel,
        phonetic: String,
        context: [String],
        limit: Int
    ) throws -> [MLPrediction] {

        // Encode inputs
        let phoneticIndices = encodePhonetic(phonetic)
        let contextIdx = encodeContext(context)

        // Create MLMultiArray for phonetic input: shape [1, 20]
        let phoneticArray = try MLMultiArray(shape: [1, NSNumber(value: phoneticMaxLen)], dataType: .int32)
        for i in 0..<phoneticMaxLen {
            phoneticArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: phoneticIndices[i])
        }

        // Create MLMultiArray for context: shape [1]
        let contextArray = try MLMultiArray(shape: [1], dataType: .int32)
        contextArray[0] = NSNumber(value: contextIdx)

        // Create feature provider
        let inputFeatures = try MLDictionaryFeatureProvider(dictionary: [
            "phonetic_input": MLFeatureValue(multiArray: phoneticArray),
            "context_word": MLFeatureValue(multiArray: contextArray)
        ])

        // Run prediction
        let output = try model.prediction(from: inputFeatures)

        // Extract scores from output
        guard let scoresFeature = output.featureValue(for: "word_scores"),
              let scoresArray = scoresFeature.multiArrayValue else {
            throw MLPredictorError.predictionFailed(
                underlying: NSError(domain: "MLPredictor", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "No word_scores output"])
            )
        }

        // Apply softmax and find top-K predictions
        let vocabSize = tibetanWordVocab.count
        var scores = [Float]()
        for i in 0..<min(vocabSize, scoresArray.count) {
            scores.append(scoresArray[i].floatValue)
        }

        // Softmax
        let maxScore = scores.max() ?? 0
        let expScores = scores.map { exp($0 - maxScore) }
        let sumExp = expScores.reduce(0, +)
        let probabilities = expScores.map { $0 / sumExp }

        // Find top-K indices (skip PAD=0 and UNK=1)
        var indexedProbs = [(Int, Float)]()
        for (i, prob) in probabilities.enumerated() {
            if i >= 2 && prob >= Float(minConfidence) {  // Skip PAD and UNK
                indexedProbs.append((i, prob))
            }
        }
        indexedProbs.sort { $0.1 > $1.1 }

        // Convert to MLPrediction results
        var predictions = [MLPrediction]()
        for (idx, prob) in indexedProbs.prefix(limit) {
            guard let tibetanWord = idxToTibetan[idx] else { continue }
            predictions.append(MLPrediction(
                tibetan: tibetanWord,
                confidence: Double(prob),
                source: .model
            ))
        }

        return predictions
    }
    #endif

    /// Get fallback predictions when model is not available
    private func getFallbackPredictions(
        phonetic: String,
        context: [String],
        limit: Int
    ) -> [MLPrediction] {

        // Use context engine hints as fallback
        if let hint = ContextEngine.shared.getSemanticHint(for: phonetic) {
            return [MLPrediction(
                tibetan: hint,
                confidence: 0.8,
                source: .fallback
            )]
        }

        // No predictions available
        return []
    }

    /// Create cache key from input
    private func makeCacheKey(phonetic: String, context: [String]) -> String {
        let contextStr = context.suffix(3).joined(separator: "|")
        return "\(phonetic):\(contextStr)"
    }

    /// Cache prediction result
    private func cacheResult(key: String, predictions: [MLPrediction]) {
        predictionCache[key] = predictions

        // Enforce cache size limit
        if predictionCache.count > maxCacheSize {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = predictionCache.keys.prefix(predictionCache.count - maxCacheSize)
            for key in keysToRemove {
                predictionCache.removeValue(forKey: key)
            }
        }
    }

    /// Clear the prediction cache
    public func clearCache() {
        predictionCache.removeAll()
    }

    // MARK: - Memory Management

    /// Get current memory usage estimate
    public var estimatedMemoryUsage: Int {
        var total = 0

        // Cache memory (rough estimate)
        total += predictionCache.count * 200  // ~200 bytes per cache entry

        // Model memory (if loaded)
        if isModelLoaded {
            total += 2 * 1024 * 1024  // ~2MB for model
        }

        return total
    }

    /// Check if loading would exceed memory budget
    public func canLoadWithinBudget(budgetBytes: Int) -> Bool {
        let estimatedModelSize = 2 * 1024 * 1024  // 2MB estimate
        return estimatedMemoryUsage + estimatedModelSize <= budgetBytes
    }
}

// MARK: - Errors

/// Errors that can occur during ML prediction
public enum MLPredictorError: Error {
    case modelNotFound
    case coreMLNotAvailable
    case predictionFailed(underlying: Error)
    case invalidInput
}

extension MLPredictorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "ML model file not found in bundle"
        case .coreMLNotAvailable:
            return "CoreML is not available on this platform"
        case .predictionFailed(let underlying):
            return "Prediction failed: \(underlying.localizedDescription)"
        case .invalidInput:
            return "Invalid input for prediction"
        }
    }
}
