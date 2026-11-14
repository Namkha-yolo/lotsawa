// KeyboardView.swift
// Lotsawa Keyboard Extension
//
// Main SwiftUI keyboard layout

import SwiftUI
import LotsawaCore

struct KeyboardView: View {

    // MARK: - Callbacks

    let onKeyTap: (String) -> Void
    let onBackspace: () -> Void
    let onSpace: () -> Void
    let onSpaceChar: () -> Void
    let onReturn: () -> Void
    let onGlobe: () -> Void
    let onModeToggle: () -> Void
    let onSuggestionTap: (String) -> Void
    let onCursorMove: (Int) -> Void
    let getSuggestions: () -> [String]
    let getBuffer: () -> String
    let getModeCode: () -> String

    // MARK: - State

    @State private var isShifted = false
    @State private var showNumbers = false
    @State private var showExtendedSymbols = false
    @State private var pressedKey: String? = nil

    // Haptic feedback generator
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Layout

    private let letterRows = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    // Tibetan numerals (༠-༩) with Tibetan punctuation
    private let numberRows = [
        ["༡", "༢", "༣", "༤", "༥", "༦", "༧", "༨", "༩", "༠"],
        ["།", "༔", "༑", "༈", "(", ")", "༄", "༅", "@", "\""],
        [".", ",", "?", "!", "'", ":", ";", "-", "/", "="]
    ]

    // Extended symbols (Sanskrit/mantra marks and more punctuation)
    private let extendedSymbolRows = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["ཨོཾ", "ཿ", "ཾ", "྄", "࿓", "࿔", "☸", "卐", "࿕", "࿗"],
        ["#", "$", "%", "^", "&", "*", "+", "~", "`", "|"]
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Suggestion Bar
            suggestionBar
                .frame(height: 44)

            // Keyboard Rows
            if showNumbers {
                if showExtendedSymbols {
                    extendedSymbolKeyboard
                } else {
                    numberKeyboard
                }
            } else {
                letterKeyboard
            }

            // Bottom Row
            bottomRow
                .frame(height: 50)
        }
        .background(Color(UIColor.systemGray5))
    }

    // MARK: - Suggestion Bar

    private var suggestionBar: some View {
        HStack(spacing: 8) {
            // Mode indicator (tappable to toggle)
            Button(action: {
                impactFeedback.impactOccurred()
                onModeToggle()
            }) {
                Text(getModeCode())
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.systemGray4))
                    .cornerRadius(4)
            }

            // Input buffer preview
            if !getBuffer().isEmpty {
                Text(getBuffer())
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .background(Color(UIColor.systemGray5))
                    .cornerRadius(4)
            }

            Spacer()

            // Suggestions
            let suggestions = getSuggestions()
            ForEach(suggestions.prefix(3), id: \.self) { suggestion in
                let isPrediction = suggestion.hasPrefix("⁺")
                let displayText = isPrediction ? String(suggestion.dropFirst()) : suggestion
                Button(action: {
                    impactFeedback.impactOccurred()
                    onSuggestionTap(suggestion)
                }) {
                    Text(displayText)
                        .font(.system(size: isPrediction ? 16 : 18))
                        .foregroundColor(isPrediction ? .secondary : .primary)
                        .padding(.horizontal, isPrediction ? 10 : 12)
                        .padding(.vertical, 6)
                        .background(isPrediction
                            ? Color(UIColor.systemGray5)
                            : Color(UIColor.systemBackground))
                        .cornerRadius(6)
                        .shadow(color: .black.opacity(isPrediction ? 0.05 : 0.1), radius: 1, y: 1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(UIColor.systemGray6))
    }

    // MARK: - Letter Keyboard

    private var letterKeyboard: some View {
        VStack(spacing: 8) {
            // Row 1: QWERTY
            HStack(spacing: 6) {
                ForEach(letterRows[0], id: \.self) { key in
                    KeyButton(
                        label: isShifted ? key.uppercased() : key,
                        action: { onKeyTap(key) }
                    )
                }
            }

            // Row 2: ASDF
            HStack(spacing: 6) {
                ForEach(letterRows[1], id: \.self) { key in
                    KeyButton(
                        label: isShifted ? key.uppercased() : key,
                        action: { onKeyTap(key) }
                    )
                }
            }

            // Row 3: Shift + ZXCV + Backspace
            HStack(spacing: 6) {
                // Shift key
                Button(action: { isShifted.toggle() }) {
                    Image(systemName: isShifted ? "shift.fill" : "shift")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .background(isShifted ? Color(UIColor.systemGray3) : Color(UIColor.systemGray4))
                        .cornerRadius(6)
                }

                ForEach(letterRows[2], id: \.self) { key in
                    KeyButton(
                        label: isShifted ? key.uppercased() : key,
                        action: { onKeyTap(key) }
                    )
                }

                // Backspace (with long-press repeat)
                BackspaceButton(action: onBackspace)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Number Keyboard (Tibetan Numerals)

    private var numberKeyboard: some View {
        VStack(spacing: 8) {
            // Row 1: Tibetan numerals
            HStack(spacing: 6) {
                ForEach(numberRows[0], id: \.self) { key in
                    KeyButton(
                        label: key,
                        action: { onKeyTap(key) }
                    )
                }
            }

            // Row 2: Tibetan punctuation
            HStack(spacing: 6) {
                ForEach(numberRows[1], id: \.self) { key in
                    KeyButton(
                        label: key,
                        action: { onKeyTap(key) }
                    )
                }
            }

            // Row 3: Symbol toggle + punctuation + backspace
            HStack(spacing: 6) {
                // Extended symbols toggle
                Button(action: { showExtendedSymbols = true }) {
                    Text("#+=")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color(UIColor.systemGray4))
                        .cornerRadius(6)
                }

                ForEach(numberRows[2], id: \.self) { key in
                    KeyButton(
                        label: key,
                        action: { onKeyTap(key) }
                    )
                }

                // Backspace (with long-press repeat)
                BackspaceButton(action: onBackspace)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Extended Symbols Keyboard

    private var extendedSymbolKeyboard: some View {
        VStack(spacing: 8) {
            // Row 1: Western numerals (for when you need them)
            HStack(spacing: 6) {
                ForEach(extendedSymbolRows[0], id: \.self) { key in
                    KeyButton(
                        label: key,
                        action: { onKeyTap(key) }
                    )
                }
            }

            // Row 2: Mantra/Sanskrit symbols
            HStack(spacing: 6) {
                ForEach(extendedSymbolRows[1], id: \.self) { key in
                    KeyButton(
                        label: key,
                        action: { onKeyTap(key) }
                    )
                }
            }

            // Row 3: Back toggle + more symbols + backspace
            HStack(spacing: 6) {
                // Back to Tibetan numerals
                Button(action: { showExtendedSymbols = false }) {
                    Text("༡༢༣")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(Color(UIColor.systemGray4))
                        .cornerRadius(6)
                }

                ForEach(extendedSymbolRows[2], id: \.self) { key in
                    KeyButton(
                        label: key,
                        action: { onKeyTap(key) }
                    )
                }

                // Backspace (with long-press repeat)
                BackspaceButton(action: onBackspace)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Bottom Row

    private var bottomRow: some View {
        HStack(spacing: 6) {
            // Number toggle
            Button(action: {
                showNumbers.toggle()
                if !showNumbers {
                    showExtendedSymbols = false  // Reset when going back to letters
                }
            }) {
                Text(showNumbers ? "ABC" : "༡༢༣")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 50, height: 44)
                    .background(Color(UIColor.systemGray4))
                    .cornerRadius(6)
            }

            // Space character (actual space, not tsheg)
            Button(action: {
                onSpaceChar()
            }) {
                Text("␣")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .background(Color(UIColor.systemGray4))
                    .cornerRadius(6)
            }

            // Space bar (with long-press trackpad cursor movement)
            SpaceBarButton(onSpace: onSpace, onCursorMove: onCursorMove)

            // Return
            Button(action: onReturn) {
                Image(systemName: "return")
                    .font(.system(size: 18))
                    .frame(width: 70, height: 44)
                    .background(Color(UIColor.systemBlue))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - Backspace Button (long-press repeat)

struct BackspaceButton: View {
    let action: () -> Void

    @State private var isPressed = false
    @State private var delayTimer: Timer?
    @State private var repeatTimer: Timer?
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Image(systemName: "delete.left")
            .font(.system(size: 18))
            .frame(width: 44, height: 44)
            .background(isPressed ? Color(UIColor.systemGray3) : Color(UIColor.systemGray4))
            .cornerRadius(6)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        impactFeedback.impactOccurred()
                        action()
                        // After initial delay, start repeating
                        delayTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                                action()
                            }
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        delayTimer?.invalidate()
                        delayTimer = nil
                        repeatTimer?.invalidate()
                        repeatTimer = nil
                    }
            )
    }
}

// MARK: - Space Bar Button (long-press trackpad)

struct SpaceBarButton: View {
    let onSpace: () -> Void
    let onCursorMove: (Int) -> Void

    @State private var isPressed = false
    @State private var isTrackpadMode = false
    @State private var lastDragX: CGFloat = 0
    @State private var accumulatedOffset: CGFloat = 0
    @State private var longPressTimer: Timer?
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let cursorStepPoints: CGFloat = 10

    var body: some View {
        Text(isTrackpadMode ? "cursor ⇔" : "བོད་ཡིག")
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(isTrackpadMode ? Color(UIColor.systemGray4) : Color(UIColor.systemBackground))
            .cornerRadius(6)
            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isPressed {
                            isPressed = true
                            lastDragX = value.location.x
                            accumulatedOffset = 0
                            longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                                DispatchQueue.main.async {
                                    isTrackpadMode = true
                                    impactFeedback.impactOccurred()
                                }
                            }
                        }

                        if isTrackpadMode {
                            let deltaX = value.location.x - lastDragX
                            accumulatedOffset += deltaX
                            lastDragX = value.location.x

                            let chars = Int(accumulatedOffset / cursorStepPoints)
                            if chars != 0 {
                                onCursorMove(chars)
                                accumulatedOffset -= CGFloat(chars) * cursorStepPoints
                            }
                        }
                    }
                    .onEnded { _ in
                        longPressTimer?.invalidate()
                        longPressTimer = nil

                        if !isTrackpadMode {
                            impactFeedback.impactOccurred()
                            onSpace()
                        }

                        isTrackpadMode = false
                        isPressed = false
                    }
            )
    }
}

// MARK: - Key Button

struct KeyButton: View {
    let label: String
    let action: () -> Void

    @State private var isPressed = false
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Button(action: {
            impactFeedback.impactOccurred()
            action()
        }) {
            Text(label)
                .font(.system(size: 22))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isPressed ? Color(UIColor.systemGray4) : Color(UIColor.systemBackground))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: isPressed ? 0 : 1, y: isPressed ? 0 : 1)
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        withAnimation(.easeInOut(duration: 0.05)) {
                            isPressed = true
                        }
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Preview

struct KeyboardView_Previews: PreviewProvider {
    static var previews: some View {
        KeyboardView(
            onKeyTap: { _ in },
            onBackspace: {},
            onSpace: {},
            onSpaceChar: {},
            onReturn: {},
            onGlobe: {},
            onModeToggle: {},
            onSuggestionTap: { _ in },
            onCursorMove: { _ in },
            getSuggestions: { ["བཀྲ་ཤིས", "བདེ་ལེགས", "སངས་རྒྱས"] },
            getBuffer: { "tashi" },
            getModeCode: { "BO" }
        )
        .frame(height: 300)
        .previewLayout(.sizeThatFits)
    }
}
