# ལོ་ཙཱ་བ། Lotsawa Keyboard

Tibetan/Dzongkha transliteration keyboard for iOS.

## Quick Start

### 1. Fix Xcode Developer Tools (one time)
Open Terminal and run:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### 2. Build and Run
1. Open `LotsawaKeyboard.xcodeproj` in Xcode
2. Select your iPhone/Simulator from the device dropdown
3. Press `⌘R` to build and run
4. The container app will open on your device

### 3. Enable the Keyboard
1. Go to **Settings → General → Keyboard → Keyboards**
2. Tap **Add New Keyboard...**
3. Select **Lotsawa**
4. Switch keyboards using the 🌐 key

## Project Structure

```
LotsawaKeyboard/
├── LotsawaKeyboard/           # Main container app
│   ├── LotsawaKeyboardApp.swift
│   ├── ContentView.swift      # Onboarding, Demo, Settings
│   └── Info.plist
├── KeyboardExtension/         # Custom keyboard
│   ├── KeyboardViewController.swift
│   ├── Views/
│   │   └── KeyboardView.swift
│   └── Info.plist
└── ../LotsawaCore/            # Shared Swift Package (transliteration engine)
    ├── Transliterator.swift   # Main engine with mode switching
    ├── WylieMapper.swift      # EWTS → Tibetan
    ├── PhoneticMapper.swift   # Phonetic → Tibetan with context
    ├── ContextEngine.swift    # N-gram disambiguation (353K sequences)
    ├── PhraseCorrector.swift  # Retroactive phrase/grammar correction
    └── TrieIndex.swift        # Fast prefix lookup (196K words)
```

## Usage

Type romanized text and see Tibetan output:

| Input | Output | Mode |
|-------|--------|------|
| tashi delek | བཀྲ་ཤིས་བདེ་ལེགས | Phonetic |
| bkra shis | བཀྲ་ཤིས | Wylie |
| sangye | སངས་རྒྱས | Phonetic |
| om mani peme hung | ཨོཾ་མ་ནི་པདྨེ་ཧཱུྃ | Phonetic |

## Features

- **Phonetic input**: Type "tashi" → བཀྲ་ཤིས
- **Wylie (EWTS) input**: Type "bkra shis" → བཀྲ་ཤིས
- **Smart suggestions**: Context-aware ranking for homophones
- **Phrase correction**: Auto-correct multi-word phrases (tashi delek → བཀྲ་ཤིས་བདེ་ལེགས)
- **Sumtak grammar**: Automatic particle selection (གི/ཀྱི/གྱི based on preceding letter)
- **Regional variants**: Supports Tibetan and Dzongkha phonetic styles
- **Tibetan numerals**: Auto-convert numbers ༡༢༣

## Demo (Command Line)

Test the transliteration engine without iOS:
```bash
cd ../LotsawaCore
swift run LotsawaDemo
```

---
སརྦ་མངྒ་ལམ། May all be auspicious!
