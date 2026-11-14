// TibetanUnicode.swift
// LotsawaCore
//
// Tibetan Unicode character constants and mappings
// Based on the Sumtak (སུམ་རྟགས་) grammar rules

import Foundation

/// Tibetan Unicode character definitions
public enum TibetanUnicode {

    // MARK: - 30 Root Consonants (མིང་གཞི)

    public static let consonants: [String: Character] = [
        "ka": "\u{0F40}",   // ཀ
        "kha": "\u{0F41}",  // ཁ
        "ga": "\u{0F42}",   // ག
        "nga": "\u{0F44}",  // ང
        "ca": "\u{0F45}",   // ཅ
        "cha": "\u{0F46}",  // ཆ
        "ja": "\u{0F47}",   // ཇ
        "nya": "\u{0F49}",  // ཉ
        "ta": "\u{0F4F}",   // ཏ
        "tha": "\u{0F50}",  // ཐ
        "da": "\u{0F51}",   // ད
        "na": "\u{0F53}",   // ན
        "pa": "\u{0F54}",   // པ
        "pha": "\u{0F55}",  // ཕ
        "ba": "\u{0F56}",   // བ
        "ma": "\u{0F58}",   // མ
        "tsa": "\u{0F59}",  // ཙ
        "tsha": "\u{0F5A}", // ཚ
        "dza": "\u{0F5B}",  // ཛ
        "wa": "\u{0F5D}",   // ཝ
        "zha": "\u{0F5E}",  // ཞ
        "za": "\u{0F5F}",   // ཟ
        "'a": "\u{0F60}",   // འ (achung)
        "ya": "\u{0F61}",   // ཡ
        "ra": "\u{0F62}",   // ར
        "la": "\u{0F63}",   // ལ
        "sha": "\u{0F64}",  // ཤ
        "sa": "\u{0F66}",   // ས
        "ha": "\u{0F67}",   // ཧ
        "a": "\u{0F68}",    // ཨ (a-chung base)
    ]

    // MARK: - Vowel Signs (དབྱངས)

    public static let vowels: [String: Character] = [
        "i": "\u{0F72}",    // ི (gigu)
        "u": "\u{0F74}",    // ུ (zhabs kyu)
        "e": "\u{0F7A}",    // ེ (dreng bu)
        "o": "\u{0F7C}",    // ོ (na ro)
    ]

    // MARK: - Subscript Letters (འདོགས་ཅན) - Subjoined forms

    public static let subscripts: [String: Character] = [
        "ya": "\u{0FB1}",   // ྱ (ya btags)
        "ra": "\u{0FB2}",   // ྲ (ra btags)
        "la": "\u{0FB3}",   // ླ (la btags)
        "wa": "\u{0FBA}",   // ྭ (wa zur)
    ]

    // MARK: - Superscript Letters (མགོ་ཅན)
    // Note: Superscripts use regular consonants but affect pronunciation

    public static let superscripts: Set<String> = ["ra", "la", "sa"]

    // MARK: - Prefix Letters (སྔོན་འཇུག)

    public static let prefixes: Set<String> = ["ga", "da", "ba", "ma", "'a"]

    // MARK: - Suffix Letters (རྗེས་འཇུག)

    public static let suffixes: Set<String> = [
        "ga", "nga", "da", "na", "ba", "ma", "'a", "ra", "la", "sa"
    ]

    // MARK: - Post-suffix Letters (ཡང་འཇུག)

    public static let postSuffixes: Set<String> = ["da", "sa"]

    // MARK: - Punctuation

    public static let tsheg: Character = "\u{0F0B}"      // ་ (syllable separator)
    public static let shad: Character = "\u{0F0D}"       // ། (sentence end)
    public static let terTsheg: Character = "\u{0F14}"   // ༔ (terma marker)
    public static let yigMgo: String = "\u{0F04}\u{0F05}\u{0F0D}" // ༄༅།

    // MARK: - Numbers

    public static let numbers: [Character: Character] = [
        "0": "\u{0F20}",  // ༠
        "1": "\u{0F21}",  // ༡
        "2": "\u{0F22}",  // ༢
        "3": "\u{0F23}",  // ༣
        "4": "\u{0F24}",  // ༤
        "5": "\u{0F25}",  // ༥
        "6": "\u{0F26}",  // ༦
        "7": "\u{0F27}",  // ༧
        "8": "\u{0F28}",  // ༨
        "9": "\u{0F29}",  // ༩
    ]

    // MARK: - Special Characters

    public static let anusvara: Character = "\u{0F7E}"   // ཾ (rjes su nga ro)
    public static let visarga: Character = "\u{0F7F}"    // ཿ (rnam bcad)
    public static let halanta: Character = "\u{0F84}"    // ྄ (srog med)

    // MARK: - Wylie to Unicode Mapping (Complete)

    /// Complete mapping from Wylie transliteration to Tibetan Unicode
    public static let wylieToUnicode: [String: String] = [
        // Basic consonants
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
        "'": "\u{0F60}",
        "y": "\u{0F61}",
        "r": "\u{0F62}",
        "l": "\u{0F63}",
        "sh": "\u{0F64}",
        "s": "\u{0F66}",
        "h": "\u{0F67}",
        "a": "\u{0F68}",

        // Vowels
        "i": "\u{0F72}",
        "u": "\u{0F74}",
        "e": "\u{0F7A}",
        "o": "\u{0F7C}",

        // Long vowels (EWTS capital letters)
        "I": "\u{0F71}\u{0F72}",   // ཱི (aa + i = long i)
        "U": "\u{0F71}\u{0F74}",   // ཱུ (aa + u = long u)
        "A": "\u{0F71}",           // ཱ (long a)

        // Diphthongs
        "ai": "\u{0F7B}",          // ཻ (e + i)
        "au": "\u{0F7D}",          // ཽ (o + u)

        // Subjoined consonants (used after +)
        "+y": "\u{0FB1}",
        "+r": "\u{0FB2}",
        "+l": "\u{0FB3}",
        "+w": "\u{0FBA}",

        // Special
        "M": "\u{0F7E}",  // anusvara
        "H": "\u{0F7F}",  // visarga

        // Punctuation
        " ": "\u{0F0B}",  // tsheg (space becomes tsheg)
        "/": "\u{0F0D}",  // shad
        "//": "\u{0F0E}", // double shad
    ]

    // MARK: - Subjoined Consonant Forms

    public static let subjoinedForms: [String: String] = [
        "k": "\u{0F90}",
        "kh": "\u{0F91}",
        "g": "\u{0F92}",
        "ng": "\u{0F94}",
        "c": "\u{0F95}",
        "ch": "\u{0F96}",
        "j": "\u{0F97}",
        "ny": "\u{0F99}",
        "t": "\u{0F9F}",
        "th": "\u{0FA0}",
        "d": "\u{0FA1}",
        "n": "\u{0FA3}",
        "p": "\u{0FA4}",
        "ph": "\u{0FA5}",
        "b": "\u{0FA6}",
        "m": "\u{0FA8}",
        "ts": "\u{0FA9}",
        "tsh": "\u{0FAA}",
        "dz": "\u{0FAB}",
        "w": "\u{0FAD}",
        "zh": "\u{0FAE}",
        "z": "\u{0FAF}",
        "'": "\u{0FB0}",
        "y": "\u{0FB1}",
        "r": "\u{0FB2}",
        "l": "\u{0FB3}",
        "sh": "\u{0FB4}",
        "s": "\u{0FB6}",
        "h": "\u{0FB7}",
        "a": "\u{0FB8}",
    ]
}

// MARK: - Letter Gender (for prefix rules)

public enum LetterGender {
    case male       // ཕོ - strong/hard
    case female     // མོ - soft/nasal
    case neutral    // མ་ནིང - neither
}

extension TibetanUnicode {

    /// Returns the gender of a Tibetan consonant (for prefix compatibility)
    public static func gender(of consonant: String) -> LetterGender {
        let maleLetters: Set<String> = ["g", "j", "d", "b", "dz", "w", "zh", "z", "'", "r", "l"]
        let femaleLetters: Set<String> = ["ng", "ny", "n", "m"]
        // Neutral: k, c, t, p, ts (and aspirates kh, ch, th, ph, tsh)

        if maleLetters.contains(consonant) {
            return .male
        } else if femaleLetters.contains(consonant) {
            return .female
        } else {
            return .neutral
        }
    }

    /// Valid prefix combinations based on letter gender
    /// Returns which prefixes can precede a given root consonant
    public static func validPrefixes(for root: String) -> Set<String> {
        // Based on Sumtak rules from Tony Duff's grammar
        let prefixRules: [String: Set<String>] = [
            // བ (b) prefix can precede these roots
            "b_prefix": ["k", "c", "t", "ts", "g", "ng", "j", "ny", "d", "n", "dz", "zh", "z", "r", "sh", "s"],
            // ག (g) prefix
            "g_prefix": ["c", "t", "ts", "ny", "d", "n", "zh", "z", "y", "sh", "s"],
            // ད (d) prefix
            "d_prefix": ["k", "p", "g", "b", "ng", "m"],
            // འ (') prefix
            "'_prefix": ["g", "j", "d", "b", "dz", "kh", "ch", "th", "ph", "tsh"],
            // མ (m) prefix
            "m_prefix": ["kh", "ch", "th", "tsh", "g", "j", "d", "dz", "ng", "ny", "n"],
        ]

        var valid: Set<String> = []

        if prefixRules["b_prefix"]!.contains(root) { valid.insert("b") }
        if prefixRules["g_prefix"]!.contains(root) { valid.insert("g") }
        if prefixRules["d_prefix"]!.contains(root) { valid.insert("d") }
        if prefixRules["'_prefix"]!.contains(root) { valid.insert("'") }
        if prefixRules["m_prefix"]!.contains(root) { valid.insert("m") }

        return valid
    }
}
