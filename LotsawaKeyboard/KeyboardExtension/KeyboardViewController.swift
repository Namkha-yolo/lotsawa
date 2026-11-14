// KeyboardViewController.swift
// Lotsawa Keyboard Extension
//
// Main controller for the iOS custom keyboard

import UIKit
import SwiftUI
import LotsawaCore

class KeyboardViewController: UIInputViewController {

    // MARK: - Properties

    private var transliterator = Transliterator()
    private var inputBuffer: String = ""
    private var hostingController: UIHostingController<KeyboardView>?

    /// Pending phrase correction (shown as first suggestion when buffer is empty)
    private var pendingCorrection: PhraseCorrection?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupKeyboardView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Start loading ML model after delay to avoid memory spike
        MLPredictor.shared.loadModelDelayed()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Unload ML model to free memory when keyboard is dismissed
        MLPredictor.shared.unloadModel()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Update keyboard height
    }

    // MARK: - Setup

    private func setupKeyboardView() {
        let keyboardView = KeyboardView(
            onKeyTap: { [weak self] key in
                self?.handleKeyTap(key)
            },
            onBackspace: { [weak self] in
                self?.handleBackspace()
            },
            onSpace: { [weak self] in
                self?.handleSpace()
            },
            onSpaceChar: { [weak self] in
                self?.handleSpaceChar()
            },
            onReturn: { [weak self] in
                self?.handleReturn()
            },
            onGlobe: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onModeToggle: { [weak self] in
                self?.toggleLanguageMode()
            },
            onSuggestionTap: { [weak self] suggestion in
                self?.insertSuggestion(suggestion)
            },
            onCursorMove: { [weak self] offset in
                self?.handleCursorMove(offset)
            },
            getSuggestions: { [weak self] in
                self?.getCurrentSuggestions() ?? []
            },
            getBuffer: { [weak self] in
                self?.inputBuffer ?? ""
            },
            getModeCode: { [weak self] in
                self?.transliterator.modeDisplayCode ?? "BO"
            }
        )

        let hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        self.hostingController = hostingController
    }

    // MARK: - Input Handling

    /// Insert a tsheg only if the text proxy doesn't already end with one
    private func insertTshegIfNeeded() {
        let tsheg = String(TibetanUnicode.tsheg)
        // Check if the last inserted text already ends with tsheg
        if let before = textDocumentProxy.documentContextBeforeInput,
           before.hasSuffix(tsheg) {
            return  // Already has tsheg, don't double up
        }
        textDocumentProxy.insertText(tsheg)
    }

    private func handleKeyTap(_ key: String) {
        // Check if key is a symbol/punctuation that should be inserted directly
        // (not buffered for phonetic conversion)
        if shouldInsertDirectly(key) {
            commitBuffer()
            textDocumentProxy.insertText(key)
            return
        }
        inputBuffer += key.lowercased()
        updateSuggestions()
    }

    /// Returns true if the key should bypass the phonetic buffer and be inserted directly.
    /// This applies to Tibetan Unicode characters, numerals, punctuation, and symbols.
    private func shouldInsertDirectly(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }
        let v = first.value
        // Tibetan Unicode block (U+0F00–U+0FFF)
        if v >= 0x0F00 && v <= 0x0FFF { return true }
        // Tibetan extended symbols (U+0F00+ range covered above)
        // CJK / special symbols
        if v > 0x2000 && !first.properties.isASCIIHexDigit { return true }
        // ASCII punctuation and digits (from number/symbol rows)
        if key.count == 1 {
            let ch = key.first!
            if ch.isNumber || "()@\"#$%^&*+-~`|/=".contains(ch) { return true }
            // Standard punctuation that maps to shad/tsheg
            if ".,?!;:-'".contains(ch) { return true }
        }
        return false
    }

    private func handleBackspace() {
        if !inputBuffer.isEmpty {
            inputBuffer.removeLast()
            updateSuggestions()
        } else {
            textDocumentProxy.deleteBackward()
        }
    }

    private func handleSpace() {
        commitBuffer()
        insertTshegIfNeeded()
    }

    private func handleSpaceChar() {
        commitBuffer()
        textDocumentProxy.insertText(" ")
    }

    private func handleReturn() {
        commitBuffer()
        textDocumentProxy.insertText("\n")
        // New paragraph typically means new context
        transliterator.clearContext()
    }

    private func commitBuffer() {
        guard !inputBuffer.isEmpty else { return }

        // Use transliterator's buffer management for context tracking
        transliterator.appendToBuffer(inputBuffer)
        let tibetan = transliterator.commitBuffer()
        textDocumentProxy.insertText(tibetan)
        inputBuffer = ""

        // Check for phrase correction after commit
        checkForPhraseCorrection()
        updateSuggestions()
    }

    private func insertSuggestion(_ suggestion: String) {
        // Check if this is a correction suggestion (with arrow prefix)
        if suggestion.hasPrefix("→ ") {
            if let correction = pendingCorrection {
                applyPhraseCorrection(correction)
                return
            }
        }

        // Check if this matches a pending correction without prefix
        if let correction = pendingCorrection, correction.newTibetan == suggestion {
            applyPhraseCorrection(correction)
            return
        }

        // Check if this is a next-word prediction (with ⁺ prefix)
        if suggestion.hasPrefix("⁺") {
            let tibetan = String(suggestion.dropFirst())
            // Insert the predicted word directly
            _ = transliterator.commitSuggestion(tibetan, romanization: "")
            textDocumentProxy.insertText(tibetan)
            insertTshegIfNeeded()
            inputBuffer = ""
            checkForPhraseCorrection()
            updateSuggestions()
            return
        }

        // Record user selection for learning
        let alternatives = getCurrentSuggestions().filter { $0 != suggestion }
        UserLearningStore.shared.recordSelection(
            phonetic: inputBuffer,
            selected: suggestion,
            alternatives: alternatives
        )

        // Track committed suggestion for context
        _ = transliterator.commitSuggestion(suggestion, romanization: inputBuffer)
        textDocumentProxy.insertText(suggestion)
        insertTshegIfNeeded()
        inputBuffer = ""

        // Check for phrase correction after commit
        checkForPhraseCorrection()
        updateSuggestions()
    }

    private func checkForPhraseCorrection() {
        pendingCorrection = transliterator.checkPhraseCorrection()
    }

    private func applyPhraseCorrection(_ correction: PhraseCorrection) {
        // Record the correction for learning
        UserLearningStore.shared.recordCorrection(
            original: correction.oldTibetan,
            corrected: correction.newTibetan
        )

        // Delete the old text
        for _ in 0..<correction.deleteCount {
            textDocumentProxy.deleteBackward()
        }

        // Insert the corrected text with tsheg
        textDocumentProxy.insertText(correction.newTibetan)
        insertTshegIfNeeded()

        // Apply the correction in transliterator
        _ = transliterator.applyPhraseCorrection(correction)

        // Clear pending correction
        pendingCorrection = nil
        inputBuffer = ""
        updateSuggestions()
    }

    private func handlePunctuation(_ punct: String) {
        commitBuffer()
        textDocumentProxy.insertText(punct)

        // Clear context on sentence endings
        if punct == "།" || punct == "." || punct == "!" || punct == "?" {
            transliterator.clearContext()
        }
    }

    private func getCurrentSuggestions() -> [String] {
        // If buffer is empty but we have a pending correction, show it
        if inputBuffer.isEmpty {
            if let correction = pendingCorrection {
                // Show correction as first suggestion with indicator
                return ["→ " + correction.newTibetan]
            }
            // Show proactive next-word predictions when buffer is empty
            let predictions = transliterator.nextWordPredictions
            if !predictions.isEmpty {
                // Prefix with "⁺" to indicate these are predictions (handled in suggestion bar styling)
                return predictions.map { "⁺" + $0.tibetan }
            }
            return []
        }
        return transliterator.getSuggestions(for: inputBuffer)
    }

    private func updateSuggestions() {
        // Trigger SwiftUI view update
        let newView = KeyboardView(
            onKeyTap: { [weak self] key in
                self?.handleKeyTap(key)
            },
            onBackspace: { [weak self] in
                self?.handleBackspace()
            },
            onSpace: { [weak self] in
                self?.handleSpace()
            },
            onSpaceChar: { [weak self] in
                self?.handleSpaceChar()
            },
            onReturn: { [weak self] in
                self?.handleReturn()
            },
            onGlobe: { [weak self] in
                self?.advanceToNextInputMode()
            },
            onModeToggle: { [weak self] in
                self?.toggleLanguageMode()
            },
            onSuggestionTap: { [weak self] suggestion in
                self?.insertSuggestion(suggestion)
            },
            onCursorMove: { [weak self] offset in
                self?.handleCursorMove(offset)
            },
            getSuggestions: { [weak self] in
                self?.getCurrentSuggestions() ?? []
            },
            getBuffer: { [weak self] in
                self?.inputBuffer ?? ""
            },
            getModeCode: { [weak self] in
                self?.transliterator.modeDisplayCode ?? "BO"
            }
        )
        hostingController?.rootView = newView
    }

    // MARK: - Cursor Movement

    private func handleCursorMove(_ offset: Int) {
        commitBuffer()
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
    }

    // MARK: - Mode Switching

    func toggleLanguageMode() {
        transliterator.toggleLanguageMode()
        updateSuggestions()
    }
}
