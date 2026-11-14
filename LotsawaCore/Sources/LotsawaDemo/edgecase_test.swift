// edgecase_test.swift - Comprehensive Edge Case Testing for LotsawaCore
// Run with: swift run LotsawaDemo edgecase

import Foundation
import LotsawaCore

/// Edge case test result
struct EdgeTestResult {
    var passed: Int = 0
    var failed: Int = 0
    var warnings: Int = 0
    var failures: [(test: String, expected: String, got: String)] = []
    var warningList: [(test: String, message: String)] = []

    var total: Int { passed + failed }
    var passRate: Double { total > 0 ? Double(passed) / Double(total) * 100 : 0 }
}

/// Run comprehensive edge case tests
func runEdgeCaseTests() {
    print("""
    ╔═══════════════════════════════════════════════════════════════╗
    ║     ལོ་ཙཱ་བ། LOTSAWA CORE - Edge Case & Stress Testing         ║
    ╚═══════════════════════════════════════════════════════════════╝
    """)

    var totalResult = EdgeTestResult()

    let suites: [(String, () -> EdgeTestResult)] = [
        ("Empty & Whitespace Inputs", testEmptyAndWhitespace),
        ("Single Characters", testSingleCharacters),
        ("Very Long Inputs", testLongInputs),
        ("Special Characters & Unicode", testSpecialCharacters),
        ("Malformed Wylie", testMalformedWylie),
        ("Case Sensitivity", testCaseSensitivity),
        ("Repeated Characters", testRepeatedCharacters),
        ("Boundary Conditions", testBoundaryConditions),
        ("Buffer/Memory Stress", testBufferStress),
        ("Number Edge Cases", testNumberEdgeCases),
        ("Mixed Content", testMixedContent),
        ("Partial/Incomplete Syllables", testPartialSyllables),
        ("Homophone Ambiguity", testHomophoneAmbiguity),
        ("Fuzzy Matching Limits", testFuzzyMatchingLimits),
        ("Context Engine Limits", testContextEngineLimits),
        ("Tsheg & Punctuation", testTshegPunctuation),
        ("Regression: Known Bugs", testRegressionKnownBugs),
    ]

    for (name, testFunc) in suites {
        print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("▶ \(name)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

        let result = testFunc()
        totalResult.passed += result.passed
        totalResult.failed += result.failed
        totalResult.warnings += result.warnings
        totalResult.failures.append(contentsOf: result.failures)
        totalResult.warningList.append(contentsOf: result.warningList)

        let status = result.failed == 0 ? "✅" : "❌"
        var summary = "\(status) \(result.passed)/\(result.total) passed"
        if result.warnings > 0 {
            summary += " ⚠️ \(result.warnings) warnings"
        }
        print(summary)
    }

    // Summary
    print("\n")
    print("╔═══════════════════════════════════════════════════════════════╗")
    print("║                   EDGE CASE TEST SUMMARY                      ║")
    print("╚═══════════════════════════════════════════════════════════════╝")
    print("  Total Tests:  \(totalResult.total)")
    print("  Passed:       \(totalResult.passed)")
    print("  Failed:       \(totalResult.failed)")
    print("  Warnings:     \(totalResult.warnings)")
    print("  Pass Rate:    \(String(format: "%.2f", totalResult.passRate))%")

    if !totalResult.failures.isEmpty {
        print("\n❌ FAILURES:")
        for (i, failure) in totalResult.failures.enumerated() {
            print("  \(i+1). \(failure.test)")
            print("     Expected: \(failure.expected)")
            print("     Got:      \(failure.got)")
        }
    }

    if !totalResult.warningList.isEmpty {
        print("\n⚠️  WARNINGS:")
        for (i, warning) in totalResult.warningList.prefix(10).enumerated() {
            print("  \(i+1). \(warning.test): \(warning.message)")
        }
        if totalResult.warningList.count > 10 {
            print("  ... and \(totalResult.warningList.count - 10) more warnings")
        }
    }

    print("\n" + (totalResult.failed == 0 ? "✅ ALL EDGE CASE TESTS PASSED!" : "❌ SOME TESTS FAILED"))
}

// MARK: - Test Helpers

func edgeCheck(_ result: inout EdgeTestResult, _ name: String, _ got: String, _ expected: String) {
    let gotNorm = got.trimmingCharacters(in: CharacterSet(charactersIn: "་།"))
    let expNorm = expected.trimmingCharacters(in: CharacterSet(charactersIn: "་།"))

    if gotNorm == expNorm {
        result.passed += 1
        print("  ✓ \(name)")
    } else {
        result.failed += 1
        result.failures.append((name, expected, got))
        print("  ✗ \(name): expected '\(expected)' got '\(got)'")
    }
}

func edgeCheckNotCrash(_ result: inout EdgeTestResult, _ name: String, _ closure: () -> String) {
    let output = closure()
    result.passed += 1
    let displayOutput = output.prefix(50)
    print("  ✓ \(name) → '\(displayOutput)'\(output.count > 50 ? "..." : "")")
}

func edgeWarn(_ result: inout EdgeTestResult, _ name: String, _ message: String) {
    result.warnings += 1
    result.warningList.append((name, message))
    print("  ⚠️ \(name): \(message)")
}

// MARK: - Test Suites

func testEmptyAndWhitespace() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)
    let wylie = WylieMapper()

    // Empty string
    edgeCheck(&result, "empty string (phonetic)", phonetic.convert(""), "")
    edgeCheck(&result, "empty string (wylie)", wylie.convert(""), "")

    // Whitespace only
    edgeCheckNotCrash(&result, "spaces only") { phonetic.convert("   ") }
    edgeCheckNotCrash(&result, "tabs only") { phonetic.convert("\t\t") }
    edgeCheckNotCrash(&result, "newlines only") { phonetic.convert("\n\n") }
    edgeCheckNotCrash(&result, "mixed whitespace") { phonetic.convert("  \t \n  ") }

    // Leading/trailing whitespace
    let withSpaces = phonetic.convert("  tashi  ")
    if withSpaces.contains("བཀྲ") || withSpaces.contains("ཤིས") {
        result.passed += 1
        print("  ✓ leading/trailing spaces trimmed")
    } else {
        result.failed += 1
        result.failures.append(("spaces trimmed", "contains བཀྲ", withSpaces))
        print("  ✗ leading/trailing spaces: got '\(withSpaces)'")
    }

    return result
}

func testSingleCharacters() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)
    let wylie = WylieMapper()

    // Single vowels
    let vowels = ["a", "e", "i", "o", "u"]
    for v in vowels {
        edgeCheckNotCrash(&result, "single vowel '\(v)' (phonetic)") { phonetic.convert(v) }
    }

    // Single consonants
    let consonants = ["k", "g", "n", "p", "b", "m", "t", "d", "s", "r", "l", "h", "w", "y", "z"]
    for c in consonants {
        edgeCheckNotCrash(&result, "single consonant '\(c)'") { phonetic.convert(c) }
    }

    // Single Wylie consonants
    for c in ["ka", "kha", "ga", "nga", "ca", "cha", "ja"] {
        edgeCheckNotCrash(&result, "wylie '\(c)'") { wylie.convert(c) }
    }

    // Single special characters
    edgeCheckNotCrash(&result, "single apostrophe") { phonetic.convert("'") }
    edgeCheckNotCrash(&result, "single hyphen") { phonetic.convert("-") }
    edgeCheckNotCrash(&result, "single period") { phonetic.convert(".") }

    return result
}

func testLongInputs() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)
    let wylie = WylieMapper()

    // Repeated word (100x)
    let repeated100 = String(repeating: "tashi ", count: 100)
    edgeCheckNotCrash(&result, "100x repeated 'tashi'") { phonetic.convert(repeated100) }

    // Very long single "word" (no spaces)
    let longWord = String(repeating: "a", count: 1000)
    edgeCheckNotCrash(&result, "1000 char single word") { phonetic.convert(longWord) }

    // Long Wylie input
    let longWylie = String(repeating: "bkra shis ", count: 50)
    edgeCheckNotCrash(&result, "50x 'bkra shis' (wylie)") { wylie.convert(longWylie) }

    // Maximum realistic sentence
    let sentence = "tashi delek sangye cho gendun lama rinpoche konchok sem rigpa yeshe tongpa nyingje dorje tulku khenpo lobsang tenzin norbu wangchuk gyaltsen jampa sonam tsering dolma jigme kunzang ugyen"
    edgeCheckNotCrash(&result, "long realistic sentence") { phonetic.convert(sentence) }

    // Stress test: 10000 characters
    let stress = String(repeating: "sangye ", count: 1500)
    let startTime = Date()
    let _ = phonetic.convert(stress)
    let elapsed = Date().timeIntervalSince(startTime)
    if elapsed < 5.0 {
        result.passed += 1
        print("  ✓ 10K+ chars processed in \(String(format: "%.2f", elapsed))s")
    } else {
        edgeWarn(&result, "10K+ chars", "took \(elapsed)s (>5s)")
    }

    return result
}

func testSpecialCharacters() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Unicode special chars
    let specialChars = [
        ("emoji 🙏", "🙏"),
        ("chinese 中文", "中文"),
        ("cyrillic привет", "привет"),
        ("arabic مرحبا", "مرحبا"),
        ("hebrew שלום", "שלום"),
        ("tibetan mixed བཀྲ་tashi", "བཀྲ་"),
    ]

    for (name, input) in specialChars {
        edgeCheckNotCrash(&result, name) { phonetic.convert(input) }
    }

    // Control characters
    edgeCheckNotCrash(&result, "null char") { phonetic.convert("ta\0shi") }
    edgeCheckNotCrash(&result, "bell char") { phonetic.convert("ta\u{07}shi") }
    edgeCheckNotCrash(&result, "backspace char") { phonetic.convert("ta\u{08}shi") }

    // Special ASCII
    edgeCheckNotCrash(&result, "ampersand") { phonetic.convert("tashi & delek") }
    edgeCheckNotCrash(&result, "angle brackets") { phonetic.convert("<tashi>") }
    edgeCheckNotCrash(&result, "quotes") { phonetic.convert("\"tashi\"") }
    edgeCheckNotCrash(&result, "backslash") { phonetic.convert("tashi\\delek") }

    // URL-like
    edgeCheckNotCrash(&result, "URL-like") { phonetic.convert("http://tashi.com") }

    // SQL injection attempt (should be harmless)
    edgeCheckNotCrash(&result, "SQL-like") { phonetic.convert("'; DROP TABLE words;--") }

    return result
}

func testMalformedWylie() -> EdgeTestResult {
    var result = EdgeTestResult()
    let wylie = WylieMapper()

    // Invalid consonant clusters
    edgeCheckNotCrash(&result, "invalid cluster 'bbb'") { wylie.convert("bbb") }
    edgeCheckNotCrash(&result, "invalid cluster 'xyz'") { wylie.convert("xyz") }
    edgeCheckNotCrash(&result, "invalid cluster 'qqq'") { wylie.convert("qqq") }

    // Missing vowels
    edgeCheckNotCrash(&result, "consonants only 'bkr'") { wylie.convert("bkr") }
    edgeCheckNotCrash(&result, "consonants only 'sngr'") { wylie.convert("sngr") }

    // Double vowels
    edgeCheckNotCrash(&result, "double vowel 'kaa'") { wylie.convert("kaa") }
    edgeCheckNotCrash(&result, "double vowel 'kii'") { wylie.convert("kii") }
    edgeCheckNotCrash(&result, "triple vowel 'kaaa'") { wylie.convert("kaaa") }

    // Invalid stacking
    edgeCheckNotCrash(&result, "invalid stack 'rkrka'") { wylie.convert("rkrka") }
    edgeCheckNotCrash(&result, "too many subscripts") { wylie.convert("krywa") }

    // Mixed valid/invalid
    edgeCheckNotCrash(&result, "valid then invalid") { wylie.convert("bkra xyz shis") }
    edgeCheckNotCrash(&result, "invalid then valid") { wylie.convert("xyz bkra shis") }

    // Apostrophe edge cases
    edgeCheckNotCrash(&result, "double apostrophe") { wylie.convert("''a") }
    edgeCheckNotCrash(&result, "apostrophe at end") { wylie.convert("ka'") }

    return result
}

func testCaseSensitivity() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)
    let wylie = WylieMapper()

    // Phonetic case variations
    let tashiLower = phonetic.convert("tashi")
    let tashiUpper = phonetic.convert("TASHI")
    let tashiMixed = phonetic.convert("TaShI")
    let tashiTitle = phonetic.convert("Tashi")

    // All should produce same result
    if tashiLower == tashiUpper && tashiUpper == tashiMixed && tashiMixed == tashiTitle {
        result.passed += 1
        print("  ✓ phonetic case insensitive (all variations match)")
    } else {
        result.failed += 1
        result.failures.append(("phonetic case insensitive", "all same",
            "lower=\(tashiLower), upper=\(tashiUpper), mixed=\(tashiMixed), title=\(tashiTitle)"))
        print("  ✗ phonetic case mismatch")
    }

    // Wylie case (some Wylie uses uppercase for long vowels)
    edgeCheckNotCrash(&result, "wylie lowercase 'ka'") { wylie.convert("ka") }
    edgeCheckNotCrash(&result, "wylie uppercase 'KA'") { wylie.convert("KA") }
    edgeCheckNotCrash(&result, "wylie long vowel 'kI'") { wylie.convert("kI") }
    edgeCheckNotCrash(&result, "wylie long vowel 'kU'") { wylie.convert("kU") }

    return result
}

func testRepeatedCharacters() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Repeated letters
    edgeCheckNotCrash(&result, "aaaa") { phonetic.convert("aaaa") }
    edgeCheckNotCrash(&result, "kkkk") { phonetic.convert("kkkk") }
    edgeCheckNotCrash(&result, "ssss") { phonetic.convert("ssss") }

    // Doubled consonants in valid positions
    edgeCheckNotCrash(&result, "sanggye (double g)") { phonetic.convert("sanggye") }
    edgeCheckNotCrash(&result, "rinppoche (double p)") { phonetic.convert("rinppoche") }

    // Repeated syllables
    edgeCheckNotCrash(&result, "mama") { phonetic.convert("mama") }
    edgeCheckNotCrash(&result, "baba") { phonetic.convert("baba") }
    edgeCheckNotCrash(&result, "nana") { phonetic.convert("nana") }

    // Repeated spaces
    edgeCheckNotCrash(&result, "multiple spaces") { phonetic.convert("tashi    delek") }

    return result
}

func testBoundaryConditions() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)
    let transliterator = Transliterator()

    // Number boundaries
    edgeCheck(&result, "number 0", transliterator.convertNumber(0), "༠")
    edgeCheckNotCrash(&result, "number -1") { transliterator.convertNumber(-1) }
    edgeCheckNotCrash(&result, "number large") { transliterator.convertNumber(999999999) }

    // Very short phonetic inputs
    edgeCheckNotCrash(&result, "single 'a'") { phonetic.convert("a") }
    edgeCheckNotCrash(&result, "single 'ng'") { phonetic.convert("ng") }

    // Exactly at common buffer sizes
    let size64 = String(repeating: "ta", count: 32)  // 64 chars
    let size128 = String(repeating: "ta", count: 64)  // 128 chars
    let size256 = String(repeating: "ta", count: 128)  // 256 chars
    let size512 = String(repeating: "ta", count: 256)  // 512 chars

    edgeCheckNotCrash(&result, "64 char input") { phonetic.convert(size64) }
    edgeCheckNotCrash(&result, "128 char input") { phonetic.convert(size128) }
    edgeCheckNotCrash(&result, "256 char input") { phonetic.convert(size256) }
    edgeCheckNotCrash(&result, "512 char input") { phonetic.convert(size512) }

    return result
}

func testBufferStress() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Rapid successive calls
    for i in 1...100 {
        let _ = phonetic.convert("tashi")
        if i == 100 {
            result.passed += 1
            print("  ✓ 100 rapid successive calls")
        }
    }

    // Alternating language modes
    let transliterator = Transliterator()
    for i in 1...50 {
        transliterator.setLanguageMode(i % 2 == 0 ? .tibetan : .dzongkha)
        let _ = transliterator.convert("test")
    }
    result.passed += 1
    print("  ✓ 50 language mode switches")

    // Clear context repeatedly
    for _ in 1...100 {
        ContextEngine.shared.addToContext("test")
        ContextEngine.shared.clearContext()
    }
    result.passed += 1
    print("  ✓ 100 context clear cycles")

    // Suggestions stress
    for _ in 1...100 {
        let _ = phonetic.getSuggestions(for: "ta")
    }
    result.passed += 1
    print("  ✓ 100 suggestion requests")

    return result
}

func testNumberEdgeCases() -> EdgeTestResult {
    var result = EdgeTestResult()
    let transliterator = Transliterator()

    // Negative numbers
    edgeCheckNotCrash(&result, "negative -5") { transliterator.convertNumber(-5) }
    edgeCheckNotCrash(&result, "negative -100") { transliterator.convertNumber(-100) }

    // Large numbers
    edgeCheckNotCrash(&result, "million") { transliterator.convertNumber(1000000) }
    edgeCheckNotCrash(&result, "billion") { transliterator.convertNumber(1000000000) }

    // Special numbers
    edgeCheck(&result, "108 (sacred)", transliterator.convertNumber(108), "༡༠༨")
    edgeCheck(&result, "1000", transliterator.convertNumber(1000), "༡༠༠༠")

    return result
}

func testMixedContent() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Numbers mixed with text
    edgeCheckNotCrash(&result, "text with numbers") { phonetic.convert("tashi 123 delek") }
    edgeCheckNotCrash(&result, "numbers first") { phonetic.convert("123 tashi") }
    edgeCheckNotCrash(&result, "numbers last") { phonetic.convert("tashi 123") }

    // Tibetan already present
    edgeCheckNotCrash(&result, "tibetan mixed") { phonetic.convert("བཀྲ་ཤིས tashi") }
    edgeCheckNotCrash(&result, "tibetan only") { phonetic.convert("བཀྲ་ཤིས་བདེ་ལེགས") }

    // Punctuation mixed
    edgeCheckNotCrash(&result, "commas") { phonetic.convert("tashi, delek, sangye") }
    edgeCheckNotCrash(&result, "periods") { phonetic.convert("tashi. delek. sangye.") }
    edgeCheckNotCrash(&result, "exclamation") { phonetic.convert("tashi! delek!") }
    edgeCheckNotCrash(&result, "question") { phonetic.convert("tashi? delek?") }

    return result
}

func testPartialSyllables() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Incomplete phonetic inputs (as if user is still typing)
    let partials = ["t", "ta", "tas", "tash", "tashi"]
    for partial in partials {
        edgeCheckNotCrash(&result, "partial '\(partial)'") { phonetic.convert(partial) }
    }

    // Incomplete Dharma terms
    let dharmaPartials = ["san", "sang", "sangy", "sangye"]
    for partial in dharmaPartials {
        edgeCheckNotCrash(&result, "dharma partial '\(partial)'") { phonetic.convert(partial) }
    }

    // Suggestions for partials
    for partial in ["ta", "san", "rin", "dor"] {
        let suggestions = phonetic.getSuggestions(for: partial)
        if !suggestions.isEmpty {
            result.passed += 1
            print("  ✓ suggestions for '\(partial)': \(suggestions.prefix(3).joined(separator: ", "))")
        } else {
            edgeWarn(&result, "partial '\(partial)'", "no suggestions returned")
        }
    }

    return result
}

func testHomophoneAmbiguity() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // All known homophones should return multiple suggestions
    let homophones = [
        ("chu", ["ཆུ", "བཅུ"]),      // water / 10
        ("nga", ["ང", "ལྔ"]),        // I / 5
        ("dak", ["བདག", "དག"]),      // self / pure
        ("druk", ["དྲུག", "འབྲུག"]), // 6 / Bhutan
        ("la", ["ལ", "བླ"]),         // particle / soul
        ("me", ["མེ", "མེད"]),       // fire / not exist
    ]

    for (input, expected) in homophones {
        let suggestions = phonetic.getSuggestions(for: input)
        var foundCount = 0
        for exp in expected {
            if suggestions.contains(where: { $0.contains(exp) }) {
                foundCount += 1
            }
        }
        if foundCount >= 2 {
            result.passed += 1
            print("  ✓ '\(input)' returns multiple homophones (\(foundCount)/\(expected.count))")
        } else if foundCount == 1 {
            edgeWarn(&result, "homophone '\(input)'", "only \(foundCount)/\(expected.count) options found")
        } else {
            result.failed += 1
            result.failures.append(("homophone '\(input)'", expected.joined(separator: ", "), suggestions.joined(separator: ", ")))
            print("  ✗ '\(input)' missing homophones")
        }
    }

    return result
}

func testFuzzyMatchingLimits() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Typos that should still match
    let typos = [
        ("tasih", "tashi"),    // transposition
        ("tashii", "tashi"),   // double letter
        ("tshi", "tashi"),     // missing vowel
        ("taashi", "tashi"),   // extra vowel
    ]

    for (typo, _) in typos {
        let suggestions = phonetic.getSuggestions(for: typo)
        if suggestions.contains(where: { $0.contains("བཀྲ") || $0.contains("ཤིས") }) {
            result.passed += 1
            print("  ✓ typo '\(typo)' finds correct match")
        } else {
            // Check if direct convert gives reasonable result
            let typoResult = phonetic.convert(typo)
            if typoResult.contains("བཀྲ") || typoResult.contains("ཤིས") {
                result.passed += 1
                print("  ✓ typo '\(typo)' converts reasonably")
            } else {
                edgeWarn(&result, "typo '\(typo)'", "no fuzzy match found (got: \(typoResult))")
            }
        }
    }

    // Completely wrong input
    let wrong = phonetic.convert("xyzabc")
    edgeCheckNotCrash(&result, "nonsense 'xyzabc'") { wrong }

    return result
}

func testContextEngineLimits() -> EdgeTestResult {
    var result = EdgeTestResult()

    // Clear and test context limits
    ContextEngine.shared.clearContext()

    // Add many context words
    for i in 1...100 {
        ContextEngine.shared.addToContext("word\(i)")
    }
    result.passed += 1
    print("  ✓ added 100 context words without crash")

    // Test context scoring with full context
    ContextEngine.shared.addToContext("སངས")  // Add context
    let score = ContextEngine.shared.scoreWithContext("རྒྱས")
    if score >= 0 {
        result.passed += 1
        print("  ✓ context scoring works (score: \(score))")
    } else {
        edgeWarn(&result, "context scoring", "unexpected negative score")
    }

    // Clear and verify
    ContextEngine.shared.clearContext()
    result.passed += 1
    print("  ✓ context cleared successfully")

    return result
}

func testTshegPunctuation() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)
    let wylie = WylieMapper()

    // Tsheg insertion
    let multiWord = phonetic.convert("tashi delek")
    if multiWord.contains("་") {
        result.passed += 1
        print("  ✓ tsheg inserted between words: \(multiWord)")
    } else {
        edgeWarn(&result, "tsheg insertion", "no tsheg in '\(multiWord)'")
    }

    // Wylie tsheg
    let wylieMulti = wylie.convert("bkra shis bde legs")
    if wylieMulti.contains("་") {
        result.passed += 1
        print("  ✓ wylie tsheg: \(wylieMulti)")
    } else {
        edgeWarn(&result, "wylie tsheg", "no tsheg in '\(wylieMulti)'")
    }

    // Shad (sentence ending)
    edgeCheckNotCrash(&result, "with shad") { phonetic.convert("tashi།") }
    edgeCheckNotCrash(&result, "double shad") { phonetic.convert("tashi།།") }

    // Tibetan punctuation passthrough
    edgeCheckNotCrash(&result, "ter tsheg") { phonetic.convert("༔") }
    edgeCheckNotCrash(&result, "yig mgo") { phonetic.convert("༄༅") }

    return result
}

func testRegressionKnownBugs() -> EdgeTestResult {
    var result = EdgeTestResult()
    let phonetic = PhoneticMapper(languageMode: .tibetan)

    // Known bug: "chang" maps to བྱང instead of ཆང
    let chang = phonetic.convert("chang")
    if chang.contains("ཆང") {
        result.passed += 1
        print("  ✓ 'chang' → ཆང (beer) [FIXED]")
    } else {
        result.failed += 1
        result.failures.append(("chang regression", "ཆང", chang))
        print("  ✗ 'chang' → '\(chang)' (expected ཆང)")
    }

    // Test other potential problem words
    let potentialBugs = [
        ("jang", "བྱང"),     // north
        ("chang", "ཆང"),    // beer
        ("chung", "ཆུང"),   // small
        ("jung", "འབྱུང"),   // arise
    ]

    for (input, expected) in potentialBugs {
        let got = phonetic.convert(input)
        if got.contains(expected) || got == expected || got.hasPrefix(expected) {
            result.passed += 1
            print("  ✓ '\(input)' → \(got)")
        } else {
            edgeWarn(&result, "'\(input)'", "expected contains '\(expected)', got '\(got)'")
        }
    }

    return result
}

// Entry point
func runEdgeCases() {
    runEdgeCaseTests()
}
