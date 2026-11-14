// split_regression_test.swift - Syllable Split Regression Testing
// Run with: swift run LotsawaDemo splittest
//
// Tests that words in the dictionary are NOT incorrectly split into
// two parts by findBestSyllableSplit(). The concern is that the new
// trie-based frequency scoring in findBestSyllableSplit() might prefer
// a split over a whole-word dictionary match.
//
// Key insight from reading the code:
//   In convert(), convertWord(cleanWord) is called FIRST (line 111).
//   Only if it returns nil does convertWithSyllableSplit get called (line 115).
//   Inside convertWithSyllableSplit, convertWord is called AGAIN (line 158).
//   So dictionary words should NEVER reach findBestSyllableSplit.
//
// This test validates that assumption empirically.

import Foundation
import LotsawaCore

struct SplitTestResult {
    var passed: Int = 0
    var failed: Int = 0
    var warnings: Int = 0
    var failures: [(input: String, expected: String, got: String, issue: String)] = []
    var warningList: [(input: String, message: String)] = []
}

func runSplitRegressionTests() {
    print("""
    ================================================================
     LOTSAWA CORE - Syllable Split Regression Test
     Testing that dictionary words are NOT incorrectly split
    ================================================================
    """)

    let mapper = PhoneticMapper()
    var result = SplitTestResult()

    // -- Helper --
    func normalize(_ s: String) -> String {
        var r = s
        while r.hasSuffix("\u{0F0D}") || r.hasSuffix("\u{0F0B}") { // shad, tsheg
            r.removeLast()
        }
        return r
    }

    func check(_ input: String, expected: String, label: String, mustNotContainTsheg: Bool = false) {
        let got = mapper.convert(input)
        let normGot = normalize(got)
        let normExp = normalize(expected)
        let tag = label.isEmpty ? "" : " (\(label))"

        if normGot == normExp {
            result.passed += 1
            print("  PASS  \(input.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(got)\(tag)")
        } else {
            result.failed += 1
            result.failures.append((input, expected, got, label))
            print("  FAIL  \(input.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(got)  [expected: \(expected)]\(tag)")
        }
    }

    /// Check that a word does NOT get split (i.e. its output does NOT contain
    /// an internal tsheg that would indicate a split, UNLESS the expected
    /// output itself contains tshegs).
    func checkNotSplit(_ input: String, expectedTibetan: String, label: String) {
        let got = mapper.convert(input)
        let normGot = normalize(got)
        let normExp = normalize(expectedTibetan)

        if normGot == normExp {
            result.passed += 1
            print("  PASS  \(input.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(got) (not split)\(label.isEmpty ? "" : " [\(label)]")")
        } else {
            // Check if it looks like a bad split: the result has MORE tshegs
            // than the expected (meaning it was broken into extra syllables)
            let gotTshegCount = got.filter { $0 == "\u{0F0B}" }.count
            let expTshegCount = expectedTibetan.filter { $0 == "\u{0F0B}" }.count
            let splitWarning = gotTshegCount > expTshegCount ? " [POSSIBLE BAD SPLIT - extra tshegs]" : ""

            result.failed += 1
            result.failures.append((input, expectedTibetan, got, "\(label)\(splitWarning)"))
            print("  FAIL  \(input.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(got)  [expected: \(expectedTibetan)] \(label)\(splitWarning)")
        }
    }

    // ================================================================
    // CATEGORY 1: Single dictionary words that COULD be split
    // These words have valid splits but the whole word is in the dictionary.
    // The whole-word match should win.
    // ================================================================
    print("\n-- Category 1: Dictionary words that could be split (should NOT split) --")
    checkNotSplit("sangye",   expectedTibetan: "སངས་རྒྱས",  label: "Buddha - sang+ye possible")
    checkNotSplit("dorje",    expectedTibetan: "རྡོ་རྗེ",    label: "vajra - dor+je possible")
    checkNotSplit("nyingje",  expectedTibetan: "སྙིང་རྗེ",   label: "compassion - nying+je possible")
    checkNotSplit("lungta",   expectedTibetan: "རླུང་རྟ",    label: "wind horse - lung+ta possible")
    checkNotSplit("torma",    expectedTibetan: "གཏོར་མ",    label: "ritual cake - tor+ma possible")
    checkNotSplit("geshe",    expectedTibetan: "དགེ་བཤེས",   label: "learned one - ge+she possible")
    checkNotSplit("namkha",   expectedTibetan: "ནམ་མཁའ",   label: "sky - nam+kha possible")
    checkNotSplit("terma",    expectedTibetan: "གཏེར་མ",    label: "hidden treasure - ter+ma possible")
    checkNotSplit("yeshe",    expectedTibetan: "ཡེ་ཤེས",    label: "wisdom - ye+she possible")
    checkNotSplit("rigpa",    expectedTibetan: "རིག་པ",     label: "awareness - rig+pa possible")
    checkNotSplit("tongpa",   expectedTibetan: "སྟོང་པ",    label: "emptiness - tong+pa possible")
    checkNotSplit("gyalpo",   expectedTibetan: "རྒྱལ་པོ",   label: "king - gyal+po possible")
    checkNotSplit("chenpo",   expectedTibetan: "ཆེན་པོ",    label: "big - chen+po possible")
    checkNotSplit("nyima",    expectedTibetan: "ཉི་མ",      label: "sun - nyi+ma possible")
    checkNotSplit("dawa",     expectedTibetan: "ཟླ་བ",      label: "moon - da+wa possible")
    checkNotSplit("karma",    expectedTibetan: "ཀརྨ",       label: "action - kar+ma possible")
    checkNotSplit("lama",     expectedTibetan: "བླ་མ",      label: "teacher - la+ma possible")
    checkNotSplit("tara",     expectedTibetan: "སྒྲོལ་མ",   label: "Tara - ta+ra possible")
    checkNotSplit("tulku",    expectedTibetan: "སྤྲུལ་སྐུ",  label: "incarnation - tul+ku possible")
    checkNotSplit("khenpo",   expectedTibetan: "མཁན་པོ",   label: "abbot - khen+po possible")

    // ================================================================
    // CATEGORY 2: Multi-syllable dictionary words
    // These should come from the curated dictionary, not be split.
    // ================================================================
    print("\n-- Category 2: Multi-syllable dictionary words --")
    checkNotSplit("rinpoche",    expectedTibetan: "རིན་པོ་ཆེ",        label: "precious one")
    checkNotSplit("bodhisattva", expectedTibetan: "བྱང་ཆུབ་སེམས་དཔའ", label: "awakened being")
    checkNotSplit("milarepa",    expectedTibetan: "མི་ལ་རས་པ",       label: "yogin name")
    checkNotSplit("tsongkhapa",  expectedTibetan: "ཙོང་ཁ་པ",         label: "founder of Gelug")
    checkNotSplit("chenrezig",   expectedTibetan: "སྤྱན་རས་གཟིགས",    label: "Avalokiteshvara")
    checkNotSplit("manjushri",   expectedTibetan: "འཇམ་དཔལ",         label: "wisdom deity")
    checkNotSplit("mandala",     expectedTibetan: "དཀྱིལ་འཁོར",       label: "sacred circle")
    checkNotSplit("nirvana",     expectedTibetan: "མྱ་ངན་ལས་འདས",    label: "liberation")
    checkNotSplit("thangka",     expectedTibetan: "ཐང་ཀ",            label: "scroll painting")
    checkNotSplit("ngondro",     expectedTibetan: "སྔོན་འགྲོ",        label: "preliminaries")
    checkNotSplit("semchen",     expectedTibetan: "སེམས་ཅན",         label: "sentient being")

    // ================================================================
    // CATEGORY 3: Short words (2-3 chars) that could be split into
    // single characters
    // ================================================================
    print("\n-- Category 3: Short words (must not split into single chars) --")
    checkNotSplit("om",   expectedTibetan: "ཨོཾ",   label: "Om")
    checkNotSplit("la",   expectedTibetan: "ལ",     label: "particle")
    checkNotSplit("me",   expectedTibetan: "མེ",    label: "fire")
    checkNotSplit("bu",   expectedTibetan: "བུ",    label: "son")
    checkNotSplit("mi",   expectedTibetan: "མི",    label: "person")
    checkNotSplit("ri",   expectedTibetan: "རི",    label: "mountain")
    checkNotSplit("sa",   expectedTibetan: "ས",     label: "earth")
    checkNotSplit("ja",   expectedTibetan: "ཇ",     label: "tea")
    checkNotSplit("za",   expectedTibetan: "ཟ",     label: "eat")
    checkNotSplit("sem",  expectedTibetan: "སེམས",  label: "mind")
    checkNotSplit("cho",  expectedTibetan: "ཆོས",   label: "dharma")
    checkNotSplit("lam",  expectedTibetan: "ལམ",    label: "path")
    checkNotSplit("lo",   expectedTibetan: "ལོ",    label: "year")
    checkNotSplit("pha",  expectedTibetan: "ཕ",     label: "father")
    checkNotSplit("ani",  expectedTibetan: "ཨ་ནི",  label: "nun")

    // ================================================================
    // CATEGORY 4: Asymmetric splits - one part is a common word,
    // other is not. The trie scoring might over-weight the common part.
    // ================================================================
    print("\n-- Category 4: Asymmetric split risk (common + uncommon parts) --")
    checkNotSplit("sangye",  expectedTibetan: "སངས་རྒྱས", label: "sang is common, ye less so")
    checkNotSplit("lodro",   expectedTibetan: "བློ་གྲོས",  label: "lo is common, dro less so")
    checkNotSplit("damtsig", expectedTibetan: "དམ་ཚིག",   label: "dam could be split")
    checkNotSplit("lobpon",  expectedTibetan: "སློབ་དཔོན",  label: "lob + pon")
    checkNotSplit("bumo",    expectedTibetan: "བུ་མོ",     label: "bu is common, mo common too")
    checkNotSplit("thugje",  expectedTibetan: "ཐུགས་རྗེ",  label: "thug + je")
    checkNotSplit("labrang", expectedTibetan: "བླ་བྲང",    label: "la is very common")
    checkNotSplit("choeten", expectedTibetan: "མཆོད་རྟེན",  label: "cho is common")
    checkNotSplit("shabdro", expectedTibetan: "ཞབས་འགྲོ",  label: "dro is common")

    // ================================================================
    // CATEGORY 5: Gibberish / unknown words - should fall through
    // gracefully without crashing
    // ================================================================
    print("\n-- Category 5: Gibberish and unknown words (graceful fallthrough) --")
    let gibberish = ["xyzabc", "qqq", "zzzz", "blorp", "fnord", "asdfgh", "qwerty"]
    for word in gibberish {
        let got = mapper.convert(word)
        result.passed += 1
        print("  PASS  \(word.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(got) (no crash)")
    }

    // ================================================================
    // CATEGORY 6: Words where trie frequency could cause wrong split
    // preference. Test that the curated dictionary 500-point bonus
    // keeps the right split winning.
    // ================================================================
    print("\n-- Category 6: Compound words (correct splitting via curated dict) --")
    checkNotSplit("chungchung", expectedTibetan: "ཆུང་ཆུང",  label: "small - chung+chung")
    checkNotSplit("gyaltsab",   expectedTibetan: "རྒྱལ་ཚབ",  label: "regent")
    checkNotSplit("kora",       expectedTibetan: "སྐོར་ར",   label: "circumambulation")
    checkNotSplit("puja",       expectedTibetan: "མཆོད་པ",   label: "ritual offering")
    checkNotSplit("stupa",      expectedTibetan: "མཆོད་རྟེན",  label: "reliquary")
    checkNotSplit("sutra",      expectedTibetan: "མདོ",      label: "scripture")
    checkNotSplit("mantra",     expectedTibetan: "སྔགས",     label: "sacred syllable")
    checkNotSplit("mudra",      expectedTibetan: "ཕྱག་རྒྱ",   label: "hand gesture")
    checkNotSplit("mala",       expectedTibetan: "ཕྲེང་བ",   label: "prayer beads")
    checkNotSplit("tsog",       expectedTibetan: "ཚོགས",     label: "feast offering")

    // ================================================================
    // CATEGORY 7: Edge case - words that are NOT in the dictionary
    // and SHOULD be split. Verify splitting still works correctly.
    // ================================================================
    print("\n-- Category 7: Words that should be correctly split --")
    // "tashidelek" is NOT a single dictionary word; it should split into tashi + delek
    let tashidelek = mapper.convert("tashidelek")
    if tashidelek.contains("བཀྲ") && tashidelek.contains("ལེགས") {
        result.passed += 1
        print("  PASS  tashidelek             -> \(tashidelek) (correctly split)")
    } else {
        result.failed += 1
        result.failures.append(("tashidelek", "should contain བཀྲ + ལེགས", tashidelek, "splitting still works"))
        print("  FAIL  tashidelek             -> \(tashidelek) (split may be broken)")
    }

    // "sangcho" - likely not a dictionary word, should split into sang + cho
    let sangcho = mapper.convert("sangcho")
    // Just check it doesn't crash and produces some output
    result.passed += 1
    print("  PASS  sangcho                -> \(sangcho) (processed without crash)")

    // "lamrim" - could be split into lam + rim
    let lamrim = mapper.convert("lamrim")
    result.passed += 1
    print("  PASS  lamrim                 -> \(lamrim) (processed without crash)")

    // ================================================================
    // SUMMARY
    // ================================================================
    let total = result.passed + result.failed
    let rate = total > 0 ? Double(result.passed) / Double(total) * 100.0 : 0.0

    print("\n================================================================")
    print(" SPLIT REGRESSION RESULTS: \(result.passed)/\(total) passed (\(String(format: "%.1f", rate))%)")
    print("================================================================")

    if !result.failures.isEmpty {
        print("\n FAILURES:")
        for (i, f) in result.failures.enumerated() {
            print("   \(i+1). \"\(f.input)\" expected \"\(f.expected)\" got \"\(f.got)\"")
            if !f.issue.isEmpty {
                print("      Issue: \(f.issue)")
            }
        }
    }

    if result.failed == 0 {
        print("\n ALL SPLIT REGRESSION TESTS PASSED!")
        print(" The trie-frequency scoring change has NOT caused regressions.")
        print(" Dictionary words are correctly resolved before splitting is attempted.")
    } else {
        print("\n SOME TESTS FAILED - possible regression from trie scoring change!")
    }
    print("")
}
