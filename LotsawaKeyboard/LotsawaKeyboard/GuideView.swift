// GuideView.swift
// Lotsawa Keyboard
//
// Usage guide for the keyboard

import SwiftUI

struct GuideView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Section 1: Typing Basics
                    GuideSection(title: "Typing Basics") {
                        VStack(alignment: .leading, spacing: 8) {
                            GuideStep(text: "Type romanized text using the QWERTY keyboard")
                            GuideStep(text: "Press the space bar to convert and insert Tibetan")
                            GuideStep(text: "A tsheg (་) is automatically added between syllables")
                            GuideStep(text: "Tap a suggestion to pick an alternative")
                        }
                    }

                    // Section 2: Space vs Tsheg
                    GuideSection(title: "Space vs Tsheg") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Text("Space bar")
                                    .font(.subheadline.bold())
                                    .frame(width: 80, alignment: .leading)
                                Text("Converts your input to Tibetan and adds a tsheg (་) — the standard syllable separator. Use this for normal typing.")
                                    .font(.subheadline)
                            }
                            HStack(alignment: .top, spacing: 12) {
                                Text("␣ button")
                                    .font(.subheadline.bold())
                                    .frame(width: 80, alignment: .leading)
                                Text("Inserts an actual space character. Use between Tibetan and English text, or for formatting.")
                                    .font(.subheadline)
                            }
                        }
                    }

                    // Section 3: Suggestions
                    GuideSection(title: "Suggestions") {
                        VStack(alignment: .leading, spacing: 8) {
                            GuideStep(text: "The first suggestion is a direct phonetic transliteration")
                            GuideStep(text: "Other suggestions are dictionary matches and homophones")
                            GuideStep(text: "The keyboard learns from your choices over time")
                            GuideStep(text: "Context from previous words helps rank suggestions")
                        }
                    }

                    // Section 4: Language Modes
                    GuideSection(title: "Language Modes") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Text("BO")
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .frame(width: 50, alignment: .leading)
                                Text("Lhasa Tibetan (བོད་སྐད). Standard Central Tibetan. Clusters simplified, finals silent.")
                                    .font(.subheadline)
                            }
                            HStack(alignment: .top, spacing: 12) {
                                Text("DZ")
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .frame(width: 50, alignment: .leading)
                                Text("Dzongkha (རྫོང་ཁ). Bhutanese. \"choe\" → ཁྱོད (you).")
                                    .font(.subheadline)
                            }
                            Text("Tap the mode indicator in the suggestion bar to cycle: BO → DZ.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Section 5: Common Examples
                    GuideSection(title: "Common Examples") {
                        VStack(spacing: 0) {
                            ExampleRow(phonetic: "tashi", tibetan: "བཀྲ་ཤིས", meaning: "auspicious")
                            ExampleRow(phonetic: "delek", tibetan: "བདེ་ལེགས", meaning: "well-being")
                            ExampleRow(phonetic: "sangye", tibetan: "སངས་རྒྱས", meaning: "Buddha")
                            ExampleRow(phonetic: "cho", tibetan: "ཆོས", meaning: "dharma")
                            ExampleRow(phonetic: "lama", tibetan: "བླ་མ", meaning: "teacher")
                            ExampleRow(phonetic: "dorje", tibetan: "རྡོ་རྗེ", meaning: "vajra")
                            ExampleRow(phonetic: "om", tibetan: "ཨོཾ", meaning: "om")
                            ExampleRow(phonetic: "nang", tibetan: "ནང", meaning: "inside")
                            ExampleRow(phonetic: "chu", tibetan: "བཅུ / ཆུ", meaning: "ten / water")
                        }
                    }

                    // Section 6: Tips
                    GuideSection(title: "Tips") {
                        VStack(alignment: .leading, spacing: 8) {
                            GuideStep(text: "Use the ༡༢༣ button for Tibetan numerals and punctuation")
                            GuideStep(text: "Tap #+ = for extended symbols and mantra marks")
                            GuideStep(text: "Punctuation like . ? ! converts to shad (།)")
                            GuideStep(text: "Comma converts to tsheg (་)")
                            GuideStep(text: "For homophones like chu (water/ten), tap the right suggestion")
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Guide")
        }
    }
}

// MARK: - Helper Views

struct GuideSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct GuideStep: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct ExampleRow: View {
    let phonetic: String
    let tibetan: String
    let meaning: String

    var body: some View {
        HStack {
            Text(phonetic)
                .font(.subheadline)
                .frame(width: 70, alignment: .leading)
            Text(tibetan)
                .font(.system(size: 18))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(meaning)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

struct GuideView_Previews: PreviewProvider {
    static var previews: some View {
        GuideView()
    }
}
