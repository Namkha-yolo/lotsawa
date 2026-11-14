// Quick disambiguation test

import LotsawaCore

func testDisambiguation() {
    print("Testing homophone disambiguation...")
    print("=" * 60)

    let phoneticMapper = PhoneticMapper()

    // Test homophones without context
    print("\n1. Without context:")
    let homophones = ["dak", "nga", "chu", "druk", "choe"]
    for word in homophones {
        let suggestions = phoneticMapper.getSuggestions(for: word, useContext: false)
        print("  \"\(word)\" → \(suggestions.prefix(5).joined(separator: ", "))")
    }

    // Test with context - simulate typing "bdag gi" (my)
    print("\n2. With context (after བདག):")
    ContextEngine.shared.clearContext()
    ContextEngine.shared.addToContext("བདག")  // Add "self/I" to context

    let giSuggestions = phoneticMapper.getSuggestions(for: "gi", useContext: true)
    print("  After བདག, \"gi\" → \(giSuggestions.prefix(3).joined(separator: ", "))")

    // Test with context - after number
    print("\n3. With context (after དགུ - nine):")
    ContextEngine.shared.clearContext()
    ContextEngine.shared.addToContext("དགུ")  // 9

    let chuAfterNine = phoneticMapper.getSuggestions(for: "chu", useContext: true)
    print("  After དགུ, \"chu\" → \(chuAfterNine.prefix(3).joined(separator: ", "))")

    // Test with context - after drink verb
    print("\n4. With context (after འཐུང - drink):")
    ContextEngine.shared.clearContext()
    ContextEngine.shared.addToContext("འཐུང")  // drink

    let chuAfterDrink = phoneticMapper.getSuggestions(for: "chu", useContext: true)
    print("  After འཐུང, \"chu\" → \(chuAfterDrink.prefix(3).joined(separator: ", "))")

    // Test semantic hints
    print("\n5. Semantic hint test:")
    if let hint = ContextEngine.shared.getSemanticHint(for: "chu") {
        print("  Semantic hint for 'chu': \(hint)")
    } else {
        print("  No semantic hint for 'chu' in current context")
    }

    print("\n" + "=" * 60)
    print("Disambiguation test complete!")
}

// Helper to multiply string
func * (left: String, right: Int) -> String {
    return String(repeating: left, count: right)
}
