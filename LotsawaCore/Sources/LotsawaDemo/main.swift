// LotsawaDemo - Interactive Tibetan Transliteration Demo
// Run with: swift run LotsawaDemo
// Run backtest with: swift run LotsawaDemo backtest

import Foundation
import LotsawaCore

// Check for backtest or test mode
if CommandLine.arguments.count > 1 {
    if CommandLine.arguments[1] == "backtest" {
        main()  // Run backtest from backtest.swift
        exit(0)
    } else if CommandLine.arguments[1] == "test" {
        testDisambiguation()  // Run disambiguation test
        exit(0)
    } else if CommandLine.arguments[1] == "edgecase" || CommandLine.arguments[1] == "edge" {
        runEdgeCases()  // Run edge case tests
        exit(0)
    } else if CommandLine.arguments[1] == "words" {
        testWordCoverage()  // Run word coverage test
        exit(0)
    } else if CommandLine.arguments[1] == "splittest" {
        runSplitRegressionTests()  // Run syllable split regression test
        exit(0)
    }
}

print("""
╔═══════════════════════════════════════════════════════════════╗
║        ལོ་ཙཱ་བ། LOTSAWA KEYBOARD - Demo                        ║
║        Tibetan Transliteration Engine                         ║
╚═══════════════════════════════════════════════════════════════╝
""")

let transliterator = Transliterator()

// Demo 1: Phonetic Mode (Tibetan)
print("\n📝 PHONETIC MODE (intuitive spelling → Tibetan)")
print("─────────────────────────────────────────────────")

let phoneticExamples = [
    ("tashi delek", "Hello/Greetings"),
    ("sangye", "Buddha"),
    ("cho", "Dharma"),
    ("gendun", "Sangha"),
    ("lama", "Guru/Teacher"),
    ("rinpoche", "Precious One"),
    ("sem", "Mind"),
    ("rigpa", "Awareness"),
    ("nyingje", "Compassion"),
    ("tongpa", "Emptiness"),
    ("yeshe", "Primordial Wisdom"),
    ("dorje", "Vajra"),
    ("om mani peme hung", "Om Mani Padme Hum"),
]

for (phonetic, meaning) in phoneticExamples {
    let tibetan = transliterator.convert(phonetic)
    print("  \(phonetic.padding(toLength: 20, withPad: " ", startingAt: 0)) → \(tibetan)  (\(meaning))")
}

// Demo 2: Dzongkha Mode
print("\n\n🇧🇹 DZONGKHA MODE (Bhutanese)")
print("─────────────────────────────────")

let dzMapper = PhoneticMapper(languageMode: .dzongkha)

let dzongkhaExamples = [
    ("kuzuzangpo", "Hello (Dzongkha)"),
    ("kadinche", "Thank you"),
    ("choe", "You"),
    ("bew", "Do/make"),
    ("ema", "Chili"),
    ("laso", "OK/Yes"),
]

for (phonetic, meaning) in dzongkhaExamples {
    let tibetan = dzMapper.convert(phonetic)
    print("  \(phonetic.padding(toLength: 20, withPad: " ", startingAt: 0)) → \(tibetan)  (\(meaning))")
}

// Demo 3: Tibetan Numbers
print("\n\n🔢 TIBETAN NUMERALS")
print("───────────────────")

for i in 0...10 {
    let tibetanNum = transliterator.convertNumber(i)
    print("  \(i) → \(tibetanNum)")
}

print("\n  2024 → \(transliterator.convertNumber(2024))")
print("  108  → \(transliterator.convertNumber(108))")

// Demo 4: Homophone Disambiguation
print("\n\n🔍 HOMOPHONE SUGGESTIONS (same sound, different meaning)")
print("─────────────────────────────────────────────────────────")

let phoneticMapper = PhoneticMapper(languageMode: .tibetan)

let homophones = ["dak", "nga", "la", "chu", "druk"]
for word in homophones {
    let suggestions = phoneticMapper.getSuggestions(for: word)
    print("  \"\(word)\" → \(suggestions.joined(separator: ", "))")
}

// Demo 5: Interactive Mode
print("\n\n⌨️  INTERACTIVE MODE")
print("────────────────────")
print("Type romanized text and press Enter to convert.")
print("Commands: 'dz'/'dzongkha' or 'bo'/'tibetan' to switch language, 'quit' to exit\n")

var running = true
while running {
    print("[\(transliterator.modeDisplayCode)] Enter text: ", terminator: "")

    guard let input = readLine()?.trimmingCharacters(in: .whitespaces), !input.isEmpty else {
        continue
    }

    switch input.lowercased() {
    case "quit", "exit", "q":
        running = false
        print("\nསརྦ་མངྒ་ལམ། May all be auspicious!")
    case "dz", "dzongkha":
        transliterator.setLanguageMode(.dzongkha)
        print("  → Switched to Dzongkha mode")
    case "bo", "tibetan":
        transliterator.setLanguageMode(.tibetan)
        print("  → Switched to Tibetan mode")
    default:
        let result = transliterator.convert(input)
        print("  → \(result)་")
    }
}
