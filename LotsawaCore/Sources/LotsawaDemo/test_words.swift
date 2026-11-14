// test_words.swift - Systematic word coverage testing for LotsawaCore
// Run with: swift run LotsawaDemo words

import Foundation
import LotsawaCore

/// Test common word conversions and report which ones fail
func testWordCoverage() {
    print("""
    ============================================================
     LOTSAWA CORE - Common Word Coverage Test
    ============================================================
    """)

    let mapper = PhoneticMapper()
    var passed = 0
    var failed = 0
    var failures: [(input: String, expected: String, got: String)] = []

    /// Normalize Tibetan for comparison: strip trailing tsheg and shad
    func normalize(_ s: String) -> String {
        var result = s
        while result.hasSuffix("་") || result.hasSuffix("།") {
            result.removeLast()
        }
        return result
    }

    /// Check a word produces the expected Tibetan
    func check(_ input: String, expected: String, label: String = "") {
        let result = mapper.convert(input)
        let normalizedResult = normalize(result)
        let normalizedExpected = normalize(expected)

        let suffix = label.isEmpty ? "" : " (\(label))"

        if normalizedResult == normalizedExpected {
            passed += 1
            print("  PASS  \(input.padding(toLength: 25, withPad: " ", startingAt: 0)) -> \(result)\(suffix)")
        } else {
            failed += 1
            failures.append((input, expected, result))
            print("  FAIL  \(input.padding(toLength: 25, withPad: " ", startingAt: 0)) -> \(result)  [expected: \(expected)]\(suffix)")
        }
    }

    // ============================================
    // DHARMA TERMS
    // ============================================
    print("\n-- Dharma Terms --")
    check("kora", expected: "སྐོར་ར", label: "circumambulation")
    check("puja", expected: "མཆོད་པ", label: "ritual offering")
    check("stupa", expected: "མཆོད་རྟེན", label: "reliquary monument")
    check("mandala", expected: "དཀྱིལ་འཁོར", label: "sacred circle")
    check("karma", expected: "ཀརྨ", label: "action")
    check("nirvana", expected: "མྱ་ངན་ལས་འདས", label: "liberation")
    check("bodhisattva", expected: "བྱང་ཆུབ་སེམས་དཔའ", label: "awakened being")
    check("sutra", expected: "མདོ", label: "scripture")
    check("mantra", expected: "སྔགས", label: "sacred syllable")
    check("mudra", expected: "ཕྱག་རྒྱ", label: "hand gesture")
    check("thangka", expected: "ཐང་ཀ", label: "scroll painting")
    check("mala", expected: "ཕྲེང་བ", label: "prayer beads")
    check("torma", expected: "གཏོར་མ", label: "ritual cake")
    check("tsog", expected: "ཚོགས", label: "feast offering")
    check("lungta", expected: "རླུང་རྟ", label: "wind horse")
    check("namkha", expected: "ནམ་མཁའ", label: "sky/space")
    check("terma", expected: "གཏེར་མ", label: "hidden treasure")
    check("tulku", expected: "སྤྲུལ་སྐུ", label: "incarnation")
    check("geshe", expected: "དགེ་བཤེས", label: "learned one")
    check("khenpo", expected: "མཁན་པོ", label: "abbot")
    check("lopon", expected: "སློབ་དཔོན", label: "teacher")
    check("ani", expected: "ཨ་ནི", label: "nun")
    check("chenrezig", expected: "སྤྱན་རས་གཟིགས", label: "Avalokiteshvara")
    check("manjushri", expected: "འཇམ་དཔལ", label: "wisdom deity")
    check("tara", expected: "སྒྲོལ་མ", label: "female buddha")
    check("milarepa", expected: "མི་ལ་རས་པ", label: "yogin name")
    check("tsongkhapa", expected: "ཙོང་ཁ་པ", label: "founder of Gelug")

    // ============================================
    // DAILY WORDS
    // ============================================
    print("\n-- Daily Words --")
    check("ga re", expected: "ག་རེ", label: "what")
    check("kha lag", expected: "ཁ་ལག", label: "food")
    check("ja", expected: "ཇ", label: "tea")
    check("dro", expected: "འགྲོ", label: "go")
    check("yong", expected: "ཡོང", label: "come")
    check("za", expected: "ཟ", label: "eat")
    check("nang", expected: "ནང", label: "inside")
    check("chi", expected: "ཕྱི", label: "outside")
    check("nyima", expected: "ཉི་མ", label: "sun")
    check("dawa", expected: "ཟླ་བ", label: "moon")
    check("lo", expected: "ལོ", label: "year")
    check("mi", expected: "མི", label: "person")
    check("pha", expected: "ཕ", label: "father")
    check("ama", expected: "ཨ་མ", label: "mother")
    check("bu", expected: "བུ", label: "son")
    check("bumo", expected: "བུ་མོ", label: "daughter")
    check("gyalpo", expected: "རྒྱལ་པོ", label: "king")
    check("lam", expected: "ལམ", label: "path")
    check("ri", expected: "རི", label: "mountain")
    check("tsho", expected: "མཚོ", label: "lake")
    check("sa", expected: "ས", label: "earth")
    check("me", expected: "མེ", label: "fire")
    check("lung", expected: "རླུང", label: "wind")
    check("nam", expected: "གནམ", label: "sky")

    // ============================================
    // COMPOUND WORDS (typed without space)
    // ============================================
    print("\n-- Compound Words --")
    check("chenpo", expected: "ཆེན་པོ", label: "big")
    check("chungchung", expected: "ཆུང་ཆུང", label: "small")
    check("lodro", expected: "བློ་གྲོས", label: "wisdom")
    check("thugje", expected: "ཐུགས་རྗེ", label: "compassion-hon")
    check("damtsig", expected: "དམ་ཚིག", label: "samaya")
    check("lobpon", expected: "སློབ་དཔོན", label: "teacher")
    check("gyaltsab", expected: "རྒྱལ་ཚབ", label: "regent")
    check("shabdro", expected: "ཞབས་འགྲོ", label: "walking-hon")
    check("choeten", expected: "མཆོད་རྟེན", label: "stupa")
    check("labrang", expected: "བླ་བྲང", label: "lama estate")
    check("ngondro", expected: "སྔོན་འགྲོ", label: "preliminaries")
    check("semchen", expected: "སེམས་ཅན", label: "sentient being")

    // ============================================
    // PHRASES
    // ============================================
    print("\n-- Phrases --")
    check("om mani peme hung", expected: "ཨོཾ་མ་ནི་པདྨེ་ཧཱུྃ", label: "Om Mani Padme Hum")
    check("tashi delek", expected: "བཀྲ་ཤིས་བདེ་ལེགས", label: "hello")
    check("khyo kyi ming gare", expected: "ཁྱོད་ཀྱི་མིང་ག་རེ", label: "what is your name")

    // ============================================
    // SUMMARY
    // ============================================
    let total = passed + failed
    let rate = total > 0 ? Double(passed) / Double(total) * 100.0 : 0.0
    print("\n============================================================")
    print(" RESULTS: \(passed)/\(total) passed (\(String(format: "%.1f", rate))%)")
    print("============================================================")

    if !failures.isEmpty {
        print("\n FAILED WORDS:")
        for f in failures {
            print("   - \"\(f.input)\" expected \"\(f.expected)\" got \"\(f.got)\"")
        }
    }

    print("")
}
