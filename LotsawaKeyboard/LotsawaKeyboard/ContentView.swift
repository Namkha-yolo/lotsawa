// ContentView.swift
// Lotsawa Keyboard
//
// Main app view with onboarding and demo

import SwiftUI
import LotsawaCore

struct ContentView: View {
    @State private var demoText: String = ""
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Onboarding Tab
            OnboardingView()
                .tabItem {
                    Image(systemName: "keyboard")
                    Text("Setup")
                }
                .tag(0)

            // Demo Tab
            DemoView()
                .tabItem {
                    Image(systemName: "text.cursor")
                    Text("Demo")
                }
                .tag(1)

            // Settings Tab
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)

            // Guide Tab
            GuideView()
                .tabItem {
                    Image(systemName: "book")
                    Text("Guide")
                }
                .tag(3)
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("ལོ་ཙཱ་བ།")
                            .font(.system(size: 48))
                        Text("Lotsawa Keyboard")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("Tibetan Transliteration Keyboard")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)

                    // Setup Steps
                    VStack(alignment: .leading, spacing: 20) {
                        Text("How to Enable")
                            .font(.headline)

                        SetupStepView(
                            number: 1,
                            title: "Open Settings",
                            description: "Go to your iPhone Settings app"
                        )

                        SetupStepView(
                            number: 2,
                            title: "General → Keyboard",
                            description: "Navigate to General, then Keyboard"
                        )

                        SetupStepView(
                            number: 3,
                            title: "Keyboards → Add New",
                            description: "Tap 'Keyboards', then 'Add New Keyboard...'"
                        )

                        SetupStepView(
                            number: 4,
                            title: "Select Lotsawa",
                            description: "Find and tap 'Lotsawa' in the list"
                        )

                        SetupStepView(
                            number: 5,
                            title: "Start Typing!",
                            description: "Use the globe key to switch to Lotsawa"
                        )
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)

                    // Open Settings Button
                    Button(action: openSettings) {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .navigationTitle("Setup")
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

struct SetupStepView: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Demo View

struct DemoView: View {
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var languageMode: LanguageMode = .tibetan

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Language Picker
                Picker("Language", selection: $languageMode) {
                    Text("Tibetan (BO)").tag(LanguageMode.tibetan)
                    Text("Dzongkha (DZ)").tag(LanguageMode.dzongkha)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)

                // Input Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type romanized text:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("e.g., tashi delek", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: inputText) { newValue in
                            convertText(newValue)
                        }
                }
                .padding(.horizontal)

                // Output Display
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tibetan output:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(outputText.isEmpty ? "བོད་ཡིག" : outputText)
                        .font(.system(size: 32))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                // Examples
                VStack(alignment: .leading, spacing: 12) {
                    Text("Try these examples:")
                        .font(.headline)

                    ExampleButton(phonetic: "tashi delek", meaning: "Hello") { text in
                        inputText = text
                    }

                    ExampleButton(phonetic: "sangye", meaning: "Buddha") { text in
                        inputText = text
                    }

                    ExampleButton(phonetic: "om mani peme hung", meaning: "Mantra") { text in
                        inputText = text
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top)
            .navigationTitle("Demo")
        }
    }

    private func convertText(_ text: String) {
        let transliterator = Transliterator(languageMode: languageMode)
        outputText = transliterator.convert(text)
    }
}

struct ExampleButton: View {
    let phonetic: String
    let meaning: String
    let onTap: (String) -> Void

    var body: some View {
        Button(action: { onTap(phonetic) }) {
            HStack {
                Text(phonetic)
                    .font(.subheadline)
                Spacer()
                Text(meaning)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "arrow.right.circle")
            }
            .padding()
            .background(Color(UIColor.tertiarySystemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("languageMode") private var languageMode = "tibetan"
    @AppStorage("hapticFeedback") private var hapticFeedback = true

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Language")) {
                    Picker("Default Language", selection: $languageMode) {
                        Text("Tibetan (BO)").tag("tibetan")
                        Text("Dzongkha (DZ)").tag("dzongkha")
                    }
                }

                Section(header: Text("Feedback")) {
                    Toggle("Haptic Feedback", isOn: $hapticFeedback)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.2.0")
                            .foregroundColor(.secondary)
                    }

                    Link(destination: URL(string: "https://github.com")!) {
                        HStack {
                            Text("Source Code")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }

                Section {
                    VStack(spacing: 8) {
                        Text("སརྦ་མངྒ་ལམ།")
                            .font(.title2)
                        Text("May all be auspicious!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
