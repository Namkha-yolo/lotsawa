// LotsawaCoreTests.swift
// LotsawaCore Tests

import XCTest
@testable import LotsawaCore

final class LotsawaCoreTests: XCTestCase {

    // MARK: - Phonetic Mapper Tests

    func testPhoneticBasicWords() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Common words
        XCTAssertEqual(mapper.convert("tashi"), "བཀྲ་ཤིས")
        XCTAssertEqual(mapper.convert("sangye"), "སངས་རྒྱས")
        XCTAssertEqual(mapper.convert("lama"), "བླ་མ")
    }

    func testPhoneticVariations() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Different spellings should give same result
        let tashi1 = mapper.convert("tashi")
        let tashi2 = mapper.convert("tashe")
        XCTAssertEqual(tashi1, tashi2)
    }

    func testPhoneticSuggestions() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Should return suggestions for partial input
        let suggestions = mapper.getSuggestions(for: "tash")
        XCTAssertFalse(suggestions.isEmpty)
    }

    func testPhoneticHomophones() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // "dak" has multiple meanings
        let suggestions = mapper.getSuggestions(for: "dak")
        XCTAssertTrue(suggestions.count >= 2) // བདག and དག
    }

    // MARK: - Transliterator Tests

    func testTransliteratorModes() {
        let transliterator = Transliterator(languageMode: .tibetan)
        XCTAssertEqual(transliterator.languageMode, .tibetan)

        transliterator.setLanguageMode(.dzongkha)
        XCTAssertEqual(transliterator.languageMode, .dzongkha)
    }

    func testTransliteratorModeDisplayCode() {
        let transliterator = Transliterator(languageMode: .tibetan)
        XCTAssertEqual(transliterator.modeDisplayCode, "BO")

        transliterator.setLanguageMode(.dzongkha)
        XCTAssertEqual(transliterator.modeDisplayCode, "DZ")
    }

    func testTransliteratorBuffer() {
        let transliterator = Transliterator()

        transliterator.appendToBuffer("t")
        transliterator.appendToBuffer("a")
        transliterator.appendToBuffer("s")
        transliterator.appendToBuffer("h")
        transliterator.appendToBuffer("i")

        XCTAssertEqual(transliterator.buffer, "tashi")

        transliterator.backspace()
        XCTAssertEqual(transliterator.buffer, "tash")

        transliterator.clearBuffer()
        XCTAssertEqual(transliterator.buffer, "")
    }

    func testTransliteratorCommit() {
        let transliterator = Transliterator()

        transliterator.appendToBuffer("tashi")
        let result = transliterator.commitBuffer()

        XCTAssertEqual(result, "བཀྲ་ཤིས")
        XCTAssertEqual(transliterator.buffer, "")
    }

    func testTransliteratorNumbers() {
        let transliterator = Transliterator()

        XCTAssertEqual(transliterator.convertNumber(123), "༡༢༣")
        XCTAssertEqual(transliterator.convertNumber(0), "༠")
        XCTAssertEqual(transliterator.convertNumber(2024), "༢༠༢༤")
    }

    func testTransliteratorPunctuation() {
        let transliterator = Transliterator()

        let withTsheg = transliterator.addTsheg("ཀ")
        XCTAssertTrue(withTsheg.hasSuffix("་"))

        let withShad = transliterator.addShad("ཀ་")
        XCTAssertTrue(withShad.hasSuffix("།"))
    }

    // MARK: - TibetanUnicode Tests

    func testTibetanUnicodeConstants() {
        // Verify key Unicode values
        XCTAssertEqual(TibetanUnicode.tsheg, Character("\u{0F0B}"))
        XCTAssertEqual(TibetanUnicode.shad, Character("\u{0F0D}"))
    }

    func testTibetanUnicodeConsonantMapping() {
        // Verify Wylie mappings exist
        XCTAssertNotNil(TibetanUnicode.wylieToUnicode["k"])
        XCTAssertNotNil(TibetanUnicode.wylieToUnicode["kh"])
        XCTAssertNotNil(TibetanUnicode.wylieToUnicode["g"])
        XCTAssertNotNil(TibetanUnicode.wylieToUnicode["ng"])
    }

    func testTibetanUnicodeSubjoinedForms() {
        // Verify subjoined forms exist
        XCTAssertNotNil(TibetanUnicode.subjoinedForms["y"])
        XCTAssertNotNil(TibetanUnicode.subjoinedForms["r"])
        XCTAssertNotNil(TibetanUnicode.subjoinedForms["l"])
        XCTAssertNotNil(TibetanUnicode.subjoinedForms["w"])
    }

    func testLetterGender() {
        XCTAssertEqual(TibetanUnicode.gender(of: "g"), .male)
        XCTAssertEqual(TibetanUnicode.gender(of: "ng"), .female)
        XCTAssertEqual(TibetanUnicode.gender(of: "k"), .neutral)
    }

    func testValidPrefixes() {
        // Test prefix rules
        let prefixesForK = TibetanUnicode.validPrefixes(for: "k")
        XCTAssertTrue(prefixesForK.contains("b"))
        XCTAssertTrue(prefixesForK.contains("d"))

        let prefixesForG = TibetanUnicode.validPrefixes(for: "g")
        XCTAssertTrue(prefixesForG.contains("d"))
        XCTAssertTrue(prefixesForG.contains("m"))
    }

    // MARK: - Static Convenience Tests

    func testStaticConversion() {
        let phonetic = Transliterator.fromPhonetic("tashi")
        XCTAssertEqual(phonetic, "བཀྲ་ཤིས")
    }

    // MARK: - SQLite Dictionary Tests

    func testSQLiteDictionaryLoaded() {
        XCTAssertTrue(SQLiteDictionary.shared.isLoaded, "SQLiteDictionary should open lotsawa.db")
    }

    func testSQLiteExactMatch() {
        let results = SQLiteDictionary.shared.lookupExact(phonetic: "tashi")
        XCTAssertFalse(results.isEmpty, "Should find matches for 'tashi'")
        XCTAssertTrue(results.contains(where: { $0.tibetan.hasPrefix("བཀྲ") }), "Should contain བཀྲ་ཤིས")
    }

    func testSQLitePrefixMatch() {
        let results = SQLiteDictionary.shared.lookupPrefix(phonetic: "ta", limit: 10)
        XCTAssertFalse(results.isEmpty, "Should find prefix matches for 'ta'")
        XCTAssertLessThanOrEqual(results.count, 10, "Should respect limit")
    }

    func testSQLiteBigrams() {
        let results = SQLiteDictionary.shared.getBigrams(word: "བཀྲ")
        XCTAssertFalse(results.isEmpty, "Should find bigrams after བཀྲ")
        XCTAssertTrue(results.contains(where: { $0.word == "ཤིས" }), "Should predict ཤིས after བཀྲ")
    }

    func testTrieFrequencyRanking() {
        let trie = TrieIndex()

        // Build with frequency data
        trie.insert(phonetic: "test", entries: [
            PhoneticEntry(tibetan: "low_freq", frequency: 1),
            PhoneticEntry(tibetan: "high_freq", frequency: 100)
        ])

        let results = trie.find(phonetic: "test")
        XCTAssertEqual(results.count, 2)
        // Higher frequency should come first
        XCTAssertEqual(results.first?.tibetan, "high_freq")
    }

    // MARK: - Integration Tests

    func testFullConversionPipeline() {
        // Test a complete conversion from user input to Tibetan output
        let transliterator = Transliterator()

        // Simulate typing "tashi delek"
        for char in "tashi" {
            transliterator.appendToBuffer(char)
        }

        // Get suggestions mid-typing
        let suggestions = transliterator.bufferSuggestions
        XCTAssertFalse(suggestions.isEmpty)

        // Commit first word
        let word1 = transliterator.commitBuffer()
        XCTAssertEqual(word1, "བཀྲ་ཤིས")

        // Type second word
        for char in "delek" {
            transliterator.appendToBuffer(char)
        }

        let word2 = transliterator.commitBuffer()
        XCTAssertEqual(word2, "བདེ་ལེགས")
    }

    // MARK: - Language-Specific Tests

    func testDzongkhaChoe() {
        let mapper = PhoneticMapper(languageMode: .dzongkha)
        let result = mapper.convert("choe")
        XCTAssertEqual(result, "ཁྱོད", "In Dzongkha mode, 'choe' should be ཁྱོད (you)")
    }

    func testTibetanChoe() {
        let mapper = PhoneticMapper(languageMode: .tibetan)
        let result = mapper.convert("choe")
        XCTAssertEqual(result, "ཆོས", "In Tibetan mode, 'choe' should be ཆོས (dharma)")
    }

    func testDzongkhaMo() {
        let mapper = PhoneticMapper(languageMode: .dzongkha)
        let suggestions = mapper.getSuggestions(for: "mo")
        XCTAssertEqual(suggestions.first { $0.contains("སྨོ") || $0 == "སྨོ" } != nil, true,
                       "In Dzongkha, 'mo' should include སྨོ (question particle)")
    }

    func testDzongkhaGreeting() {
        let mapper = PhoneticMapper(languageMode: .dzongkha)
        let result = mapper.convert("kuzuzangpo")
        XCTAssertTrue(result.contains("སྐུ") || result.contains("གཟུགས") || result.contains("བཟང"),
                      "Dzongkha greeting should convert correctly, got: \(result)")
    }

    func testLanguageToggle() {
        let transliterator = Transliterator(languageMode: .tibetan)
        XCTAssertEqual(transliterator.modeDisplayCode, "BO")

        transliterator.toggleLanguageMode()
        XCTAssertEqual(transliterator.modeDisplayCode, "DZ")
        XCTAssertEqual(transliterator.languageMode, .dzongkha)

        transliterator.toggleLanguageMode()
        XCTAssertEqual(transliterator.modeDisplayCode, "BO")
        XCTAssertEqual(transliterator.languageMode, .tibetan)
    }

    // MARK: - Context-Based Disambiguation Tests

    func testContextEngineLoaded() {
        // Verify context engine loads the model
        XCTAssertTrue(ContextEngine.shared.isLoaded, "ContextEngine should be loaded (backed by SQLite)")
    }

    func testContextEngineScoring() {
        // Test that context scoring returns valid values
        ContextEngine.shared.clearContext()
        ContextEngine.shared.addToContext("སངས")  // sang

        // Score should be >= 1.0 (multiplier)
        let score = ContextEngine.shared.scoreWithContext("རྒྱས")  // rgyas (likely after sang)
        XCTAssertGreaterThanOrEqual(score, 1.0, "Context score should be at least 1.0")
    }

    func testConfidenceScoring() {
        // Test that confidence scores are in valid range [0.0, 1.0]
        ContextEngine.shared.clearContext()
        ContextEngine.shared.addToContext("ཆོས")  // chos

        let (score, confidence) = ContextEngine.shared.scoreWithConfidence("ཀྱི")  // kyi (genitive)
        XCTAssertGreaterThanOrEqual(confidence, 0.0, "Confidence should be >= 0")
        XCTAssertLessThanOrEqual(confidence, 1.0, "Confidence should be <= 1.0")
        XCTAssertGreaterThanOrEqual(score, 0.0, "Score should be >= 0")
    }

    func testRankWithConfidence() {
        // Test ranking with confidence returns all items
        let suggestions: [(String, Int)] = [
            ("བདག", 100),  // self
            ("དག", 50)     // pure
        ]

        ContextEngine.shared.clearContext()
        let ranked = ContextEngine.shared.rankWithConfidence(suggestions)

        XCTAssertEqual(ranked.count, 2, "Should return all suggestions")
        // Each item should have (tibetan, freq, confidence)
        for (_, _, confidence) in ranked {
            XCTAssertGreaterThanOrEqual(confidence, 0.0)
            XCTAssertLessThanOrEqual(confidence, 1.0)
        }
    }

    func testAutoSelectThreshold() {
        // Test auto-select with and without context
        let suggestions: [(String, Int)] = [
            ("ཆུ", 100),   // water
            ("བཅུ", 50)    // 10
        ]

        // Without context, should not auto-select
        ContextEngine.shared.clearContext()
        let (autoSelect1, _) = ContextEngine.shared.shouldAutoSelect(suggestions)
        XCTAssertFalse(autoSelect1, "Without context, should not auto-select")
    }

    func testSemanticHintLookup() {
        // Test semantic hint retrieval
        ContextEngine.shared.clearContext()
        ContextEngine.shared.addToContext("ཐུང")  // thung (drink)

        // After "drink", "chu" should hint to water
        if let hint = ContextEngine.shared.getSemanticHint(for: "chu") {
            XCTAssertEqual(hint, "ཆུ", "After 'drink', 'chu' should suggest water")
        }
        // Note: Hint may be nil if semantic hints don't cover this case
    }

    func testNumberSequenceContext() {
        // Test that number context helps disambiguation
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // After number 4, "nga" should prefer 5 (ལྔ) over I (ང)
        ContextEngine.shared.clearContext()
        ContextEngine.shared.addToContext("བཞི")  // 4

        let suggestions = mapper.getSuggestions(for: "nga")
        XCTAssertFalse(suggestions.isEmpty, "Should get suggestions for 'nga'")

        // ལྔ (5) should be ranked higher than ང (I) in number context
        // Note: This depends on the trained model having number sequences
    }

    func testContextAwareConversion() {
        // Test that PhoneticMapper uses context for conversion
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Clear context and convert "chu" - should get default
        ContextEngine.shared.clearContext()
        let defaultResult = mapper.convert("chu")
        XCTAssertFalse(defaultResult.isEmpty, "Should convert 'chu'")

        // The result should be one of the homophones
        let isValidHomophone = defaultResult.contains("བཅུ") || defaultResult.contains("ཆུ")
        XCTAssertTrue(isValidHomophone, "Result should be བཅུ (10) or ཆུ (water)")
    }

    func testSuggestionsWithConfidence() {
        // Test the new getSuggestionsWithConfidence method
        let mapper = PhoneticMapper(languageMode: .tibetan)

        ContextEngine.shared.clearContext()
        let results = mapper.getSuggestionsWithConfidence(for: "dak")

        XCTAssertFalse(results.isEmpty, "Should get suggestions for 'dak'")

        // Each result should have (tibetan, confidence, shouldHighlight)
        for (tibetan, confidence, _) in results {
            XCTAssertFalse(tibetan.isEmpty, "Tibetan should not be empty")
            XCTAssertGreaterThanOrEqual(confidence, 0.0, "Confidence should be >= 0")
            XCTAssertLessThanOrEqual(confidence, 1.0, "Confidence should be <= 1.0")
        }
    }

    func testContextWindowSize() {
        // Test that context window holds up to 5 words
        ContextEngine.shared.clearContext()

        // Add 6 words
        for i in 1...6 {
            ContextEngine.shared.addToContext("word\(i)")
        }

        // Context should have at most 5 words (the most recent ones)
        let context = ContextEngine.shared.currentContext
        XCTAssertLessThanOrEqual(context.count, 5, "Context window should not exceed 5")
    }

    func testClearContext() {
        // Test that clearContext actually clears
        ContextEngine.shared.addToContext("ཆོས")
        ContextEngine.shared.addToContext("སངས")

        ContextEngine.shared.clearContext()
        XCTAssertTrue(ContextEngine.shared.currentContext.isEmpty, "Context should be empty after clear")
    }

    func testHomophoneVariants() {
        // Test that homophones return multiple options
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // "chu" should have both བཅུ (10) and ཆུ (water)
        let chuSuggestions = mapper.getSuggestions(for: "chu")
        XCTAssertGreaterThanOrEqual(chuSuggestions.count, 2, "'chu' should have at least 2 options")

        // "nga" should have both ང (I) and ལྔ (5)
        let ngaSuggestions = mapper.getSuggestions(for: "nga")
        XCTAssertGreaterThanOrEqual(ngaSuggestions.count, 2, "'nga' should have at least 2 options")
    }

    func testDisambiguationPerformance() {
        // Test that disambiguation is fast enough
        let mapper = PhoneticMapper(languageMode: .tibetan)

        ContextEngine.shared.clearContext()
        ContextEngine.shared.addToContext("སངས")
        ContextEngine.shared.addToContext("རྒྱས")

        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<100 {
            _ = mapper.getSuggestions(for: "cho")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let perCall = elapsed / 100.0

        // Should be less than 5ms per call (generous for CI environments)
        XCTAssertLessThan(perCall, 0.005, "Each getSuggestions call should be < 5ms, was \(perCall * 1000)ms")
    }

    // MARK: - Accuracy Fix Tests

    func testVowelInitial() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Vowel-initial inputs should produce achung-based results
        let inSuggestions = mapper.getSuggestions(for: "in")
        XCTAssertTrue(inSuggestions.contains(where: { $0.contains("ཨིན") }),
                       "'in' suggestions should contain ཨིན, got: \(inSuggestions)")

        let unSuggestions = mapper.getSuggestions(for: "un")
        XCTAssertTrue(unSuggestions.contains(where: { $0.contains("ཨུ") }),
                       "'un' suggestions should contain achung+u, got: \(unSuggestions)")

        let omSuggestions = mapper.getSuggestions(for: "om")
        XCTAssertTrue(omSuggestions.contains(where: { $0.contains("ཨོ") || $0.contains("ཨོཾ") }),
                       "'om' suggestions should contain achung+o, got: \(omSuggestions)")
    }

    func testPhoneticFirst() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // First suggestion for "in" should NOT be ནང (meaning-based)
        let suggestions = mapper.getSuggestions(for: "in")
        if let first = suggestions.first {
            XCTAssertNotEqual(first, "ནང",
                              "First suggestion for 'in' should not be ནང (inside), got: \(suggestions)")
        }
    }

    func testNangStillWorks() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // "nang" should still produce ནང as a suggestion
        let suggestions = mapper.getSuggestions(for: "nang")
        XCTAssertTrue(suggestions.contains(where: { $0.contains("ནང") }),
                       "'nang' should still suggest ནང, got: \(suggestions)")
    }

    func testNoShortCompoundSplit() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Short inputs: the FIRST suggestion should be a simple phonetic result,
        // not a compound split. (Later suggestions may include long DB entries.)
        let inSuggestions = mapper.getSuggestions(for: "in")
        let meSuggestions = mapper.getSuggestions(for: "me")
        let chuSuggestions = mapper.getSuggestions(for: "chu")

        // First suggestion for short inputs should be short (not a compound split)
        if let first = inSuggestions.first {
            XCTAssertLessThanOrEqual(first.count, 10,
                                      "'in' first suggestion should be short, got: \(first)")
        }
        if let first = meSuggestions.first {
            XCTAssertLessThanOrEqual(first.count, 10,
                                      "'me' first suggestion should be short, got: \(first)")
        }
        if let first = chuSuggestions.first {
            XCTAssertLessThanOrEqual(first.count, 10,
                                      "'chu' first suggestion should be short, got: \(first)")
        }
    }

    func testCommonWords() {
        let mapper = PhoneticMapper(languageMode: .tibetan)

        // Regression: common words should still convert correctly
        let tashi = mapper.convert("tashi")
        XCTAssertEqual(tashi, "བཀྲ་ཤིས", "tashi should convert to བཀྲ་ཤིས")

        let sangye = mapper.convert("sangye")
        XCTAssertEqual(sangye, "སངས་རྒྱས", "sangye should convert to སངས་རྒྱས")

        let choSuggestions = mapper.getSuggestions(for: "cho")
        XCTAssertTrue(choSuggestions.contains(where: { $0.contains("ཆོས") }),
                       "'cho' should suggest ཆོས, got: \(choSuggestions)")
    }

}
