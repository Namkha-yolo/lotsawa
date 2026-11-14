# ལོ་ཙཱ་བ། Lotsawa Keyboard

## Project Documentation

---

> *མཉྫུ་ཤྲཱི་ཀུ་མཱ་ར་བྷཱུ་ཏ་ཡེ་ནམཿ།*
>
> To Longchenpa the brilliant sun that burns darkness constantly,
> Khenrinpoche, the eyes that I never knew I had.
> With deep love and devotion,
> Oedzer
>
> *Manjushri the embodiment of all the buddhas wisdom*
> *Loden Choksey the sharp sword of intellect*
> *Vimalamitra the wish-fulfilling tree*
> *Longchenpa the eyes of the world*
> *Jamyang Gyepe Loden Lord of awareness*
> *Guide my motivation and my actions*
> *May the words of truth never decline*
> *And survive the test of time*
> *May it reach out to and touch everyone's heart*

---


## About

Lotsawa Keyboard is a Tibetan/Dzongkha transliteration keyboard for iOS that converts romanized input — phonetic or Wylie — into Tibetan script (བོད་ཡིག།/རྫོང་ཁ།) with predictive suggestions and contextual disambiguation.

Targeting the internet generation, this project preserves the deep meaning of Tibetan/Dzongkha words that are seldom accurately translated — for a tradition and language developed with the aspiration to keep wisdom and gentleness alive as a living experience. In a bold attempt to prolong the life of such a tradition and vision, to honor the sacrifice of the Three Great Dharma Kings, Guru Rinpoche, and the great translators of old and new traditions.

### Platforms

| Platform | Status | Technology |
|----------|--------|------------|
| **iOS** (iPhone/iPad) | Completed | Custom Keyboard Extension, SwiftUI + UIKit |
| **macOS** | Planned | Input Method Kit (IMKit) |
| **Android** | Planned | InputMethodService API |

---

## Features

### Core Transliteration

- **Phonetic input**: Type "tashi delek" and receive བཀྲ་ཤིས་བདེ་ལེགས
- **Wylie (EWTS) input**: Type "bkra shis bde legs" and receive བཀྲ་ཤིས་བདེ་ལེགས
- **Dual language modes**: Tibetan (བོད་ཡིག།) and Dzongkha (རྫོང་ཁ།)
- **Live mode indicator**: Displays current mode (e.g., "BO-P" for Tibetan-Phonetic, "DZ-W" for Dzongkha-Wylie)
- **Tibetan numerals**: Converts digits to Tibetan (༡༢༣)
- **Tibetan punctuation**: Converts `.` `!` `?` to shad (།) automatically

### Smart Suggestions

- **Trie-based prefix matching**: O(m) lookup across 98K+ words
- **Frequency ranking**: Words ranked by corpus frequency
- **Context-aware suggestions**: N-gram model (bigrams, trigrams, 4-grams from 353K+ sequences) ranks candidates by preceding words
- **Confidence scoring**: 0–1 scale; auto-selects when confidence exceeds 80%, shows options otherwise
- **Homophone disambiguation**: Resolves ambiguity in real time (e.g., "chu" → ཆུ water vs. བཅུ ten, depending on context)

### Grammar and Phrase Correction

- **Sumtak rules**: Automatic particle selection (གི/ཀྱི/གྱི/ཡི) based on the preceding word's final letter
- **Retroactive phrase correction**: Recognizes multi-word phrases after commit and offers corrections
- **Regional phonetic variations**: Supports Tibetan, Dzongkha, Lhasa, Amdo, and Kham pronunciations
- **Phonetic fuzzy matching**: Handles spelling variations (khyö/khyo/choe all resolve to ཁྱོད)

### Keyboard Interface

- **Haptic feedback** on key presses
- **Mode toggle**: Tap the mode indicator to switch between Wylie and Phonetic
- **Suggestion bar**: Top candidates with confidence scores
- **Key press animations**: Scale and shadow effects
- **Standard key support**: Backspace, space (inserts tsheg ་), return, shift, globe key (🌐)

### User Personalization

- **User learning store**: Tracks selections and preferences locally
- **Personal vocabulary**: Add custom words
- **Preference decay**: Weights age over 30-day half-life so the keyboard adapts over time
- **Private local storage**: All data in the App Group container, never transmitted

### Privacy and Performance

- **Fully offline**: No network access required
- **Zero data collection**: No analytics, no tracking, no telemetry
- **Memory-conscious**: Designed to fit iOS keyboard extension constraints (<40MB)
- **Lazy loading**: ML model loads after a delay to avoid memory spikes at launch
- **No Full Access required**: Core features work without granting Full Access

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Container App                            │
│  - Onboarding (5-step setup guide)                         │
│  - Demo interface (live conversion)                        │
│  - Settings (input mode, haptic toggle)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   LotsawaCore (Swift Package)               │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ Transliterator       │  │ ContextEngine        │        │
│  │ (main engine)        │  │ (n-gram model)       │        │
│  ├──────────────────────┤  ├──────────────────────┤        │
│  │ WylieMapper          │  │ PhraseCorrector      │        │
│  │ PhoneticMapper       │  │ PhoneticFuzzyMatcher │        │
│  │ TibetanUnicode       │  │ UserLearningStore    │        │
│  │ TrieIndex            │  │ MLPredictor          │        │
│  └──────────────────────┘  └──────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Keyboard Extension                          │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │ KeyboardView    │  │ Keyboard        │                  │
│  │ (SwiftUI)       │◄─┤ ViewController  │                  │
│  └─────────────────┘  └─────────────────┘                  │
│           │                    │                            │
│           ▼                    ▼                            │
│  ┌─────────────────┐  ┌─────────────────┐                  │
│  │ Suggestion Bar  │  │ Input Buffer    │                  │
│  │                 │  │ Management      │                  │
│  └─────────────────┘  └─────────────────┘                  │
└─────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
lotsawa keyboard/
├── LotsawaCore/                          # Shared Swift Package
│   ├── Package.swift
│   └── Sources/LotsawaCore/
│       ├── Transliterator.swift          # Main engine, mode switching, buffer management
│       ├── WylieMapper.swift             # EWTS → Tibetan conversion
│       ├── PhoneticMapper.swift          # THL Phonetic → Tibetan conversion
│       ├── TibetanUnicode.swift          # Unicode constants (30 consonants, vowels, punctuation)
│       ├── TrieIndex.swift               # Trie data structure for prefix matching (36K entries)
│       ├── ContextEngine.swift           # N-gram context disambiguation (353K sequences)
│       ├── PhraseCorrector.swift         # Retroactive phrase correction + sumtak grammar
│       ├── PhoneticFuzzyMatcher.swift    # Dialect-aware fuzzy matching
│       ├── MLPredictor.swift             # CoreML wrapper for character-level prediction
│       ├── UserLearningStore.swift       # Local user preference tracking
│       ├── phonetic_dictionary.json      # 98K+ phonetic → Tibetan mappings
│       ├── phonetic_lookup.json          # Optimized lookup table
│       ├── context_model.json            # N-gram frequencies (bi/tri/4-gram)
│       ├── phonetic_variations.json      # Regional dialect variants
│       ├── phonetic_pairs.json           # Homophone pairs
│       ├── sumtak_rules.json             # Grammar rules for particle selection
│       ├── word_frequency.json           # Word frequency rankings
│       └── semantic_hints.json           # Context hints for disambiguation
│
├── LotsawaKeyboard/                      # iOS App + Keyboard Extension
│   ├── LotsawaKeyboard.xcodeproj
│   └── LotsawaKeyboard/
│       ├── LotsawaKeyboardApp.swift      # App entry point
│       ├── ContentView.swift             # Onboarding, demo, settings views
│       ├── KeyboardViewController.swift  # UIInputViewController (input handling)
│       └── KeyboardView.swift            # SwiftUI keyboard UI
│
├── Scripts/                              # Data processing and build tools
│   ├── download_dataset.py              # Hugging Face dataset fetcher
│   ├── build_database.py                # Multi-source → SQLite builder
│   ├── build_ngram_model.py             # N-gram context model builder (v3.0)
│   ├── build_phonetic_variations.py     # Regional dialect variation generator
│   ├── build_semantic_hints.py          # Homophone disambiguation hints
│   ├── build_enhanced_ngram.py          # Enhanced n-gram with 4-gram support
│   ├── build_dialect_variations.py      # Dialect-specific phonetic patterns
│   ├── tibetan_phonetics.py             # Pronunciation rules engine (40K+ words)
│   ├── train_coreml_model.py            # LSTM → CoreML model training
│   ├── expand_dictionary.py             # Dictionary expansion utilities
│   ├── optimize_database.py             # Database optimization
│   ├── rebuild_lookup.py                # Lookup table rebuilder
│   └── create_app_icon.py               # App icon generator
│
├── datasets/                             # Raw data from Hugging Face and other sources
├── privacy-policy.html                   # Privacy policy (zero data collection)
└── support.html                          # User support and setup guide
```

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| UI Framework | SwiftUI + UIHostingController | Modern, declarative, easier to build |
| Data Storage | JSON bundles + SQLite | Lightweight, fast queries, works in extension |
| Transliteration | Custom Swift implementation | Full control, no external dependencies |
| Prediction | Trie + frequency + n-gram context | Fast prefix matching, memory efficient, context-aware |
| ML Model | CoreML LSTM (optional) | On-device, lazy-loaded, <5MB footprint |
| User Data | App Group UserDefaults + local files | Private, shared between app and extension |
| Full Access | Not required | Core features work entirely offline and locally |

---

## Transliteration Systems

### Wylie (EWTS)

The academic standard for romanizing Tibetan. Represents spelling exactly and is fully reversible.

```
Input:  bkra shis bde legs
Output: བཀྲ་ཤིས་བདེ་ལེགས
```

### THL Simplified Phonetic

Pronunciation-based romanization developed by the Tibetan & Himalayan Library. Intuitive for non-scholars but not reversible.

```
Input:  tashi delek
Output: བཀྲ་ཤིས་བདེ་ལེགས
```

### Comparison

| Tibetan | Wylie | Phonetic | Meaning |
|---------|-------|----------|---------|
| བཀྲ་ཤིས་ | bkra shis | tashi | auspicious |
| སངས་རྒྱས་ | sangs rgyas | sangye | Buddha |
| ཆོས | chos | chö | dharma |
| སེམས | sems | sem | mind |
| ཡེ་ཤེས | ye shes | yeshe | primordial wisdom |
| རྡོ་རྗེ | rdo rje | dorjé | vajra |
| སྙིང་རྗེ | snying rje | nyingjé | compassion |

---

## Tibetan Script Reference

### Syllable Structure (སུམ་རྟགས་ Sumtak)

| Component | Tibetan | Description |
|-----------|---------|-------------|
| **Prefix** | སྔོན་འཇུག | Silent letter before root. Only 5: ག ད བ མ འ |
| **Superscript** | མགོ་ཅན | Letter above root. Only 3: ར ལ ས |
| **Root** | མིང་གཞི | Main consonant, carries pronunciation |
| **Subscript** | འདོགས་ཅན | Letter below root. Only 4: ཡ ར ལ ཝ |
| **Vowel** | དབྱངས | Vowel mark: ི ུ ེ ོ (or inherent 'a') |
| **Suffix** | རྗེས་འཇུག | Letter after root. 10 allowed: ག ང ད ན བ མ འ ར ལ ས |
| **Post-suffix** | ཡང་འཇུག | Final letter. Only 2: ད ས |

### Letter Gender (མིང་གཞི་སྡེ་ཚན)

| Gender | Tibetan | Letters | Role |
|--------|---------|---------|------|
| **Male** | ཕོ | ག ཇ ད བ ཛ ཝ ཞ ཟ འ ར ལ | Strong/hard consonants |
| **Female** | མོ | ང ཉ ན མ | Soft/nasal consonants |
| **Neutral** | མ་ནིང | ཀ ཅ ཏ པ ཙ | Neither hard nor soft |

### Punctuation

| Symbol | Name | Function |
|--------|------|----------|
| ་ | ཚེག (tsheg) | Syllable separator |
| ། | ཤད (shé) | End of sentence/phrase |
| ༔ | གཏེར་ཚེག (ter tsheg) | Terma/treasure text marker |
| ༄༅། | ཡིག་མགོ (yik go) | Document beginning marker |

---

## Data Sources

### Primary Phonetic Datasets

| Source | Entries | Content |
|--------|---------|---------|
| [billingsmoore/tibetan-phonetic-transliteration-dataset](https://huggingface.co/datasets/billingsmoore/tibetan-phonetic-transliteration-dataset) | 98,597 | Tibetan script ↔ THL Phonetic |
| [billingsmoore/tibetan-to-english-translation-dataset](https://huggingface.co/datasets/billingsmoore/tibetan-to-english-translation-dataset) | 90,252 | Tibetan + Phonetic + English |
| [billingsmoore/tibetan-to-french-translation-dataset](https://huggingface.co/datasets/billingsmoore/tibetan-to-french-translation-dataset) | — | Tibetan + Phonetic + French |
| [billingsmoore/phonetic-tibetan-to-english-translation-pairs](https://huggingface.co/datasets/billingsmoore/phonetic-tibetan-to-english-translation-pairs) | — | Full sentences |

### Dictionary Databases

| Source | Entries | Notes |
|--------|---------|-------|
| [Esukhia/bo-pos](https://github.com/Esukhia/bo-pos) (MGD-dict.yml) | 107,064 | Monlam Grand Dictionary, structured YAML |
| [Rangjung Yeshe Wiki](https://rywiki.tsadra.org/) | 276,000 | Buddhist/Classical Tibetan |
| [christiansteinert/tibetan-dictionary](https://github.com/christiansteinert/tibetan-dictionary) | Multiple | Hopkins, Rangjung Yeshe, 84000, dung dkar |
| [84000 Glossary](https://84000.co/glossary-search) | — | Trilingual (Tibetan-Sanskrit-English) |
| [OpenDataBay](https://www.opendatabay.com/data/dataset/870af3f3-dca6-4ad2-a987-0db3073b78cf) | 35,882 | Scraped from Lotsawa House |
| SOAS Lexicon | 15,643 | POS-tagged vocabulary |
| ACTib Corpus | 1,463,920 | Annotated Classical Tibetan |

### NLP Tools Used

| Tool | Purpose | Source |
|------|---------|--------|
| [pyewts](https://github.com/OpenPecha/pyewts) | Wylie ↔ Unicode conversion | `pip install pyewts` |
| [bophono](https://github.com/Esukhia/bophono) | Tibetan → IPA/Phonetics | `pip install bophono` |
| [Botok](https://github.com/OpenPecha/Botok) | Tibetan word tokenizer | OpenPecha |

### Additional Resources

| Resource | URL |
|----------|-----|
| [tibetan-nlp/tibetan-verbs-database](https://github.com/tibetan-nlp/tibetan-verbs-database) | Verb conjugations (past, present, future, imperative) |
| DDC Dictionary (Dzongkha Development Commission) | 12,605 unique words in pronunciation lexicon |
| [Grammar of Dzongkha](https://escholarship.org/content/qt1h4211k0/qt1h4211k0_noSplash_b3843a79888f78f39713ded5f61ad772.pdf) | Dzongkha grammar reference |
| [THL Phonetics Converter](https://old.thlib.org/reference/transliteration/phconverter.php) | THL Simplified Phonetic Transcription |
| [Lotsawa House EWTS Tool](https://www.lotsawahouse.org/Static/tools/ewts.html) | Online Wylie converter |

### Processed Data Totals

| Metric | Count |
|--------|-------|
| Phonetic dictionary entries | 98,597 |
| Indexed words | 196,000+ |
| Definitions and translations | 42,000+ |
| Trie index entries | 36,000+ |
| N-gram context sequences | 353,000+ |
| Phonetic reverse index entries | 72,000+ |

---

## Development Phases

### Phase 1: Core Transliteration Engine — Complete

- Created `LotsawaCore` Swift Package
- Implemented `TibetanUnicode.swift` with 30 consonants, vowels, and punctuation
- Implemented `WylieMapper.swift` for EWTS → Tibetan conversion (full syllable parsing with prefix, superscript, root, subscript, vowel, suffix, post-suffix)
- Implemented `PhoneticMapper.swift` with 98K+ dictionary entries and Trie-based prefix lookup
- Implemented `Transliterator.swift` as the main engine with mode switching (Wylie/Phonetic, Tibetan/Dzongkha)
- Created LotsawaDemo command-line tool for testing
- All unit tests written and passing

### Phase 2: Dictionary and Prediction — Complete

- Downloaded and processed Hugging Face datasets (98K+ entries)
- Built SQLite database from multiple sources (196K words, 42K definitions)
- Implemented Trie-based prefix matching (36K entries, O(m) lookup)
- Implemented frequency-based ranking for suggestion ordering

### Phase 3: iOS Keyboard and App — Complete

- Created `LotsawaKeyboard` Xcode project with keyboard extension target
- Built `KeyboardViewController.swift` (UIInputViewController subclass with full input handling)
- Built `KeyboardView.swift` (SwiftUI keyboard UI with suggestion bar)
- Created container app with onboarding (5-step setup guide), demo interface, and settings
- Integrated LotsawaCore as a Swift Package dependency into both targets
- Set up App Group for shared data between app and extension
- Added haptic feedback on key presses
- Added mode toggle (tap mode indicator to switch Wylie/Phonetic)
- Added key press animations (scale + shadow effects)
- Builds and runs successfully on iOS Simulator

### Phase 4: Context-Based Disambiguation — Complete

- Built `ContextEngine.swift` with confidence scoring (0–1 scale)
- Added 4-gram support for stronger phrase context (116K contexts)
- Implemented semantic hints for common word patterns (e.g., drink + "chu" → ཆུ water)
- Made `PhoneticMapper.convertWord()` context-aware
- Expanded n-gram model with multi-corpus training (353K sequences)
- Hybrid UX: auto-select when confidence >80%, show ranked options otherwise
- Added `getSuggestionsWithConfidence()` for UI integration
- All 43 disambiguation tests passing

### Phase 5: Phrase Correction and Grammar — Complete

- Built `PhraseCorrector` for retroactive phrase correction after commit
- Implemented sumtak grammar rules for particle selection (གི/ཀྱི/གྱི/ཡི)
- Particle correction based on preceding word's final letter and gender
- Multi-word phrase lookup with regional phonetic variations
- Phonetic variations database (choe ↔ khyö, gi ↔ kyi, etc.)
- Common phrase corrections (tashi delek, khyö kyi ming, etc.)
- Built `PhoneticFuzzyMatcher` for approximate phonetic matching across Lhasa, Amdo, Kham, and Dzongkha dialects
- Integrated phrase correction into the Transliterator commit flow

### Remaining Work

| Task | Status |
|------|--------|
| CoreML model training and integration | Framework in place, model generation pending |
| macOS Input Method (IMKit) | Designed, not yet implemented |
| App Store submission | Certificates created, submission pending |
| Real device testing across iOS versions | In progress |
| Android implementation | Planned |

---

## iOS Keyboard Development Reference

| Term | Description |
|------|-------------|
| **UIInputViewController** | Base class for iOS custom keyboards |
| **UITextDocumentProxy** | Interface to insert/delete text in any app |
| **Keyboard Extension** | App extension that provides keyboard functionality |
| **Container App** | Main app that delivers the keyboard extension |
| **App Group** | Shared storage between app and extension |
| **Full Access** | Permission for network/shared container access (not required by Lotsawa) |
| **Globe Key** | System button to switch between keyboards (🌐) |

## macOS Input Method Reference

| Term | Description |
|------|-------------|
| **IMKit** | Input Method Kit — Apple framework for macOS IME |
| **IMKInputController** | Base class for macOS input methods |
| **Candidate Window** | Floating popup showing word suggestions |
| **Input Source** | System-level keyboard/input method |
| **Hardened Runtime** | macOS security requirement for distribution |

---

## Privacy Policy

*Last updated: February 2026*

### Overview

Lotsawa Keyboard is a Tibetan transliteration keyboard that converts romanized input to Tibetan script. This policy explains how the application handles user data.

### Data Collection

**Lotsawa Keyboard does not collect any data.**

- No text you type is collected or stored beyond the active session
- No keystrokes are tracked or logged
- No contacts, photos, location, or other personal data is accessed
- No analytics or tracking tools are used
- No device identifiers are collected

### How the Keyboard Works

All text processing happens entirely on the device:

- Romanized input is converted to Tibetan script locally on the device
- The dictionary, prediction data, and n-gram models are bundled with the app and stored on the device
- User learning preferences (word selections, personal vocabulary) are stored locally in the App Group container
- No text ever leaves the device

### Network Access

Lotsawa Keyboard works completely offline:

- No internet connection is required
- No network requests are made
- No data is sent to any server

### Full Access Permission

Lotsawa Keyboard does not request the "Full Access" permission. The keyboard operates in the most restricted mode possible, ensuring privacy is protected at the system level.

### Third Parties

No data is shared with third parties. No data is collected in the first place.

### Children's Privacy

The app does not collect personal information from anyone, including children under 13.

### Changes to This Policy

If changes are made to this privacy policy, the "Last updated" date above will be updated accordingly.

### Contact

For questions about this privacy policy:
**Email:** [your-email@example.com]

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2024-11 | Initial project conception |
| 0.2 | 2024-11 | Sumtak rules extracted from Tony Duff |
| 0.3 | 2024-11 | Python prototype with 286 words |
| 0.4 | 2025-12 | Comprehensive data sources compiled |
| 0.5 | 2025-12 | LotsawaCore Swift Package (transliteration engine, Wylie + Phonetic) |
| 0.6 | 2025-12 | Dictionary and prediction system (196K words, Trie index) |
| 0.7 | 2026-01 | iOS keyboard extension and container app |
| 0.8 | 2026-01 | Context-based disambiguation (n-gram model, confidence scoring) |
| 0.9 | 2026-01 | Phrase correction, sumtak grammar, dialect fuzzy matching |

---
---

# The Lotsawa Phonetic Standard (LPS)

### A Standardized Romanization System for Tibetan Script

> *As Pinyin is to Chinese, as Romaji is to Japanese — so shall the Lotsawa Standard be to Tibetan.*
>
> For the benefit of all sentient beings, may this bridge between scripts preserve the wisdom of the Dharma Kings, Guru Rinpoche, and the great translators of old and new traditions.

---

## 1. Introduction

Tibetan lacks a universally adopted phonetic romanization standard. Existing systems — EWTS (Extended Wylie Transliteration System), THL Simplified Phonetic, Tournadre's system — each serve specific audiences but none has achieved the universality of Pinyin for Chinese or Romaji for Japanese.

The **Lotsawa Phonetic Standard (LPS)** aims to fill this gap: a complete, formally specified, multi-dialect phonetic romanization for Tibetan script (བོད་ཡིག) that is:

- **Pronunciation-based**: Type how the word sounds, like Pinyin
- **Complete**: Covers every valid Tibetan syllable
- **Multi-dialect**: Supports Lhasa, Dzongkha, Amdo, and Kham pronunciations
- **Hint-compatible**: Optional orthographic hints allow disambiguation without a separate mode
- **Typeable**: Uses only standard keyboard characters (a-z, no diacritics required)
- **Implementable**: Designed as both a formal standard and a practical keyboard input method

### 1.1 The Core Challenge

Tibetan writing is **etymological** — it preserves spellings from the 7th-9th century while pronunciation has evolved dramatically. This creates massive homophony: many different written forms share the same pronunciation.

For example, all of the following are pronounced **"ka"** in Lhasa Tibetan:

| Written | Wylie | Components |
|---------|-------|------------|
| ཀ | ka | root only |
| བཀའ | bka' | prefix + root + suffix |
| སྐ | ska | superscript + root |
| རྐ | rka | superscript + root |
| ལྐ | lka | superscript + root |
| བསྐ | bska | prefix + superscript + root |

This is analogous to Chinese where "shì" can be 是/十/时/石/事/室 — the romanization is the same, and context + user selection resolves the ambiguity.

### 1.2 Design Philosophy

The LPS follows the **Pinyin principle**: spell the pronunciation, let the system handle the orthography. Specifically:

1. **Preserve the three-way voicing distinction** (voiceless / aspirated / historically-voiced) even where dialects have merged them. Pinyin does this — Pinyin "b" is phonetically /p/, "p" is /pʰ/ — and it works because users learn the convention.

2. **Accept dialect variation as input normalization**, not as separate alphabets. Each dialect mode accepts its own pronunciation as valid input alongside the canonical LPS form.

3. **Provide optional hints** for power users who know the orthography, without requiring them for basic use.

---

## 2. The LPS Alphabet

### 2.1 Consonant Inventory (30 Initials)

These correspond exactly to the 30 root letters (མིང་གཞི) of the Tibetan alphabet.

#### Stops and Affricates

| Place | Voiceless | Aspirated | Voiced | Nasal |
|-------|-----------|-----------|--------|-------|
| **Velar** | **k** ཀ /k/ | **kh** ཁ /kʰ/ | **g** ག */k/ low* | **ng** ང /ŋ/ |
| **Palatal** | **c** ཅ /tɕ/ | **ch** ཆ /tɕʰ/ | **j** ཇ */tɕ/ low* | **ny** ཉ /ɲ/ |
| **Dental** | **t** ཏ /t/ | **th** ཐ /tʰ/ | **d** ད */t/ low* | **n** ན /n/ |
| **Labial** | **p** པ /p/ | **ph** ཕ /pʰ/ | **b** བ */p/ low* | **m** མ /m/ |
| **Alveolar** | **ts** ཙ /ts/ | **tsh** ཚ /tsʰ/ | **dz** ཛ */ts/ low* | — |

*IPA values shown for Lhasa dialect. "Low" = low tone from historical voicing.*

#### Fricatives and Approximants

| LPS | Tibetan | IPA (Lhasa) | Description |
|-----|---------|-------------|-------------|
| **sh** | ཤ | /ɕ/ | Voiceless palatal fricative |
| **zh** | ཞ | /ɕ/ low | Voiced palatal fricative (low tone) |
| **s** | ས | /s/ | Voiceless alveolar fricative |
| **z** | ཟ | /s/ low | Voiced alveolar fricative (low tone) |
| **h** | ཧ | /h/ | Glottal fricative |
| **w** | ཝ | /w/ | Labial approximant |
| **y** | ཡ | /j/ | Palatal approximant |
| **r** | ར | /r/ | Alveolar trill/approximant |
| **l** | ལ | /l/ | Lateral approximant |
| **'** | འ | (silent) | Achung (glottal stop, often silent) |

#### Vowel Carrier

| LPS | Tibetan | Usage |
|-----|---------|-------|
| (none / a) | ཨ | Vowel-initial syllables: "a", "e", "i", "o", "u" |

When a syllable begins with a vowel, the achung ཨ is automatically inserted as the vowel carrier. The user simply types the vowel.

### 2.2 Vowel Inventory (5 Basic)

| LPS | Tibetan Sign | IPA | Accepted Aliases |
|-----|-------------|-----|-----------------|
| **a** | (inherent) | /a/ | — |
| **i** | ི (gigu) | /i/ | ee |
| **u** | ུ (zhapkyu) | /u/ | oo |
| **e** | ེ (drengbu) | /e/ | ay, ai, ey |
| **o** | ོ (naro) | /o/ | ou |

**Note on umlaut**: In Lhasa Tibetan, certain suffixes (-d, -s) cause vowel fronting: /a/ → /e/, /o/ → /ø/, /u/ → /y/. These surface forms ("oe", "ue") are accepted as input aliases but normalize internally to the underlying vowel + final combination. This is the standard's position: record the underlying form; accept the surface pronunciation.

### 2.3 Medial Consonants / Subscripts (4)

| LPS | Tibetan | Typed as Cluster |
|-----|---------|-----------------|
| **-y-** | ྱ (ya-btags) | kya, khya, gya, pya... |
| **-r-** | ྲ (ra-btags) | kra, khra, tra, dra, pra... |
| **-l-** | ླ (la-btags) | kla, gla, bla, zla... |
| **-w-** | ྭ (wa-zur) | kwa, khwa, gwa... |

In phonetic mode, medials are implicit in the consonant cluster pronunciation. The user types the cluster naturally (e.g., "kya") and the system resolves it.

### 2.4 Final Consonants (10 + 2 Post-suffixes)

| LPS | Written | Lhasa | Amdo | Notes |
|-----|---------|-------|------|-------|
| **-k** | ག | /ʔ/ unreleased | /k/ | |
| **-ng** | ང | /ŋ/ | /ŋ/ | Always pronounced |
| **-n** | ན | /n/ | /n/ | Always pronounced |
| **-m** | མ | /m/ | /m/ | Always pronounced |
| **-p** | བ | /ʔ/ unreleased | /p/ | |
| **-r** | ར | silent | /r/ | Pronounced in Amdo, Kham |
| **-l** | ལ | silent | /l/ | Pronounced in Amdo, Kham |
| **-s** | ས | silent | /s/ | Triggers umlaut in Lhasa |
| **-d** | ད | silent | /t/ | Triggers umlaut in Lhasa |
| **-'** | འ | silent | silent | |

**Post-suffixes** (ཡང་འཇུག): Only **-d** and **-s** can appear after a suffix. These are silent in Lhasa but may be pronounced in Amdo.

---

## 3. Syllable Structure

### 3.1 The Tibetan Syllable (སུམ་རྟགས)

A Tibetan syllable has up to 7 components:

```
[Prefix] + [Superscript] + Root + [Subscript] + Vowel + [Suffix] + [Post-suffix]
```

| Component | Tibetan Term | Possible Values |
|-----------|-------------|-----------------|
| Prefix | སྔོན་འཇུག | ག ད བ མ འ (5 letters) |
| Superscript | མགོ་ཅན | ར ལ ས (3 letters) |
| Root | མིང་གཞི | All 30 consonants |
| Subscript | འདོགས་ཅན | ཡ ར ལ ཝ (4 letters) |
| Vowel | དབྱངས | ི ུ ེ ོ (or inherent 'a') |
| Suffix | རྗེས་འཇུག | ག ང ད ན བ མ འ ར ལ ས (10) |
| Post-suffix | ཡང་འཇུག | ད ས (2 letters) |

### 3.2 LPS Syllable Template

In LPS, the user types the **pronounced** form:

```
[Initial Consonant/Cluster] + [Vowel] + [Final]
```

Where:
- **Initial** = one of the 30 consonants, optionally with a medial (kya, tra, etc.)
- **Vowel** = a, i, u, e, o
- **Final** = optionally: -k, -ng, -n, -m, -p, -r, -l

The system maps this pronunciation to the correct written form (with prefix, superscript, etc.) using the syllable table + dictionary + context.

### 3.3 Parsing Rules

**Rule 1: Maximal Initial Match** — Parse the longest valid consonant/cluster first.
- `nga` → **ng** + a (not n + ga)
- `tsha` → **tsh** + a (not ts + ha)
- `sha` → **sh** + a (not s + ha)
- `nya` → **ny** + a (not n + ya)

**Rule 2: Onset Maximization** — A consonant between vowels begins the next syllable.
- `ama` → a + **m**a (not am + a)
- `semchen` → sem + **ch**en (ch starts the next syllable)

**Rule 3: Space = Word Boundary** — Always forces a break. Produces tsheg (་) in output.

### 3.4 Multi-Syllable Words

Syllables concatenate directly within a word:

| Input | Syllable Split | Tibetan |
|-------|---------------|---------|
| tashi | ta + shi | བཀྲ་ཤིས |
| sangye | sang + ye | སངས་རྒྱས |
| rinpoche | rin + po + che | རིན་པོ་ཆེ |
| dechen | de + chen | བདེ་ཆེན |
| semchen | sem + chen | སེམས་ཅན |

---

## 4. The Hint System

The hint system is **always optional**. Pure phonetic input works for all common words. Hints allow disambiguation for power users or edge cases.

### 4.1 Full Wylie Hint (Backtick)

Prefix a syllable with `` ` `` to enter it as exact Wylie:

| Input | Result | Explanation |
|-------|--------|-------------|
| `` `bka' `` | བཀའ | Exact Wylie: prefix-b + root-k + suffix-' |
| `` `ska `` | སྐ | Exact Wylie: superscript-s + root-k |
| `` `rdo `` | རྡོ | Exact Wylie: superscript-r + root-d + vowel-o |

### 4.2 Prefix/Superscript Hint (Dot Separator)

Specify just the prefix or superscript to narrow candidates:

| Input | Result | Explanation |
|-------|--------|-------------|
| `` `b.ka `` | བཀ | b-prefix + ka root |
| `` `s.ka `` | སྐ | s-superscript + ka root |
| `` `r.ka `` | རྐ | r-superscript + ka root |

### 4.3 Tone Hint (Slash/Backslash)

Filter candidates by tone class (Lhasa mode):

| Input | Result | Explanation |
|-------|--------|-------------|
| `ka/` | ཀ, སྐ, རྐ, ལྐ... | High tone only (voiceless roots) |
| `ka\` | ག, དག, བག... | Low tone only (historically voiced roots) |

### 4.4 Final Hint (Plus Sign)

Specify an orthographic final that may be silent:

| Input | Result | Explanation |
|-------|--------|-------------|
| `ka+s` | ཀས | ka with suffix -s |
| `ka+g` | ཀག | ka with suffix -g |
| `lu+s` | ལུས | lu with suffix -s (body) |

### 4.5 Summary of Hint Markers

| Marker | Meaning | Example |
|--------|---------|---------|
| `` ` `` | Full Wylie syllable follows | `` `bka' `` → བཀའ |
| `.` | Prefix/superscript separator | `` `b.ka `` → བཀ |
| `/` | High tone filter | `ka/` → voiceless-root ka |
| `\` | Low tone filter | `ka\` → voiced-root ka |
| `+` | Orthographic final | `ka+s` → ཀས |

---

## 5. Dialect Modes

### 5.1 Overview

The LPS defines four dialect modes, each with its own pronunciation-to-spelling mapping:

| Mode | Code | Region | Basis |
|------|------|--------|-------|
| **Lhasa** | BO | Central Tibet | Prestige dialect, default |
| **Dzongkha** | DZ | Bhutan | National language of Bhutan |
| **Amdo** | AM | Northeastern Tibet | Preserves archaic features |
| **Kham** | KH | Eastern Tibet | Voicing shifts |

### 5.2 Lhasa Mode (BO) — The Reference Dialect

The default and most widely understood form of spoken Tibetan.

**Key phonological features:**
- Consonant clusters simplified (བཀྲ bkra → "tra")
- Prefixes and superscripts silent (but affect tone)
- Finals -r, -l, -s, -d silent (but -s and -d trigger vowel umlaut)
- Two tones: high (from voiceless roots) and low (from voiced roots)
- Historical voicing merged: ག (ga) pronounced same as ཁ (kha) but with low tone

**Input normalization**: Accepts both etymological forms and Lhasa-simplified pronunciation:
- Both `dro` and `tro` find འགྲོ (go/walk)
- Both `gya` and `ja` find རྒྱ

### 5.3 Dzongkha Mode (DZ) — Bhutanese

**Key differences from Lhasa:**
- Palatalization: khyö → choe (ཁྱོད "you" pronounced "choe")
- Some clusters preserved
- Different word frequencies and vocabulary

**Examples:**

| LPS Input (DZ) | Tibetan | Meaning | Lhasa Equivalent |
|-----------------|---------|---------|-------------------|
| kuzuzangpo | སྐུ་གཟུགས་བཟང་པོ | hello | — |
| kadinche | བཀའ་དྲིན་ཆེ | thank you | — |
| choe | ཁྱོད | you | khyoe |
| bew | འབད | do/make | — |
| ema | ཨེ་མ | chili | — |

### 5.4 Amdo Mode (AM) — Northeastern

Amdo Tibetan preserves many archaic features lost in Lhasa:

**Key differences:**
- **Consonant clusters pronounced**: br, gr, pr, kr, tr, dr, bl, gl, pl, kl all articulated
- **Finals pronounced**: -g, -d, -b, -r, -l, -s all articulated
- **No tone**: Amdo is non-tonal
- **Voicing preserved**: g ≠ k, d ≠ t, b ≠ p remain distinct phonemes

**Input normalization**: Amdo speakers type what they hear, which often includes clusters and finals silent in Lhasa:
- `bkra` (Amdo pronunciation with cluster) finds བཀྲ
- `shis` (with final -s) finds ཤིས

### 5.5 Kham Mode (KH) — Eastern

**Key differences:**
- **Voicing shifts**: Some initial voiceless stops may voice (k→g, t→d, p→b in certain positions)
- **Aspiration variation**: kh→k, th→t, ph→p in some positions
- **Tonal**: Tonal like Lhasa but with different patterns
- **More finals pronounced** than Lhasa

---

## 6. The Complete Syllable Table

### 6.1 What It Is

The syllable table is the **core data artifact** of the LPS — a computationally generated, exhaustive mapping of every valid Tibetan syllable to its pronunciation in each dialect.

**Estimated scope**: 6,000-8,000 valid syllable forms (constrained by Sumtak grammar rules on which prefixes, superscripts, roots, subscripts, suffixes, and post-suffixes can co-occur).

### 6.2 Table Structure

| Wylie | Unicode | LPS-Lhasa | LPS-Amdo | LPS-Kham | LPS-Dzongkha | Tone | Frequency |
|-------|---------|-----------|----------|----------|-------------|------|-----------|
| ka | ཀ | ka | ka | ga | ka | H | 500 |
| kha | ཁ | kha | kha | kha | kha | H | 450 |
| ga | ག | ga | ga | ga | ga | L | 600 |
| bka' | བཀའ | ka | ka | ga | ka | H | 300 |
| ska | སྐ | ka | ska | ga | ka | H | 200 |
| rka | རྐ | ka | rka | ga | ka | H | 100 |
| lka | ལྐ | ka | lka | ga | ka | H | 50 |
| bkra | བཀྲ | tra | bkra | dra | tra | H | 400 |
| sgra | སྒྲ | dra | sgra | dra | dra | L | 250 |
| ... | ... | ... | ... | ... | ... | ... | ... |

### 6.3 Reverse Index

The reverse index maps each LPS pronunciation (per dialect) to all matching Tibetan syllables, ranked by frequency:

```
Lhasa "ka" → [ཀ (500), ག (600), བཀའ (300), སྐ (200), རྐ (100), ...]
Amdo "ska" → [སྐ (200)]
Amdo "ka" → [ཀ (500), བཀའ (300)]
```

This is exactly how Pinyin input works: "shi" → [是, 十, 时, 石, 事, ...] ranked by frequency.

### 6.4 Generation Method

**Tools**: `pyewts` (Wylie↔Unicode), `bophono` (pronunciation generation), `botok` (tokenization)

**Process**:
1. Enumerate all valid syllable structures per Sumtak grammar rules
2. Convert each Wylie syllable to Unicode via `pyewts`
3. Generate pronunciation for each dialect via `bophono`
4. Normalize IPA output to LPS romanization
5. Merge with existing frequency data from corpus
6. Output as JSON + import into SQLite

---

## 7. Comparison with Existing Systems

### 7.1 Extended Wylie Transliteration System (EWTS)

| Aspect | EWTS | LPS |
|--------|------|-----|
| Basis | Orthography (spelling) | Pronunciation |
| Reversibility | Fully reversible | Via hint system |
| Learnability | Requires knowing Tibetan spelling | Intuitive for speakers |
| Dialect support | None (orthographic only) | 4 dialects |
| Homophones | No ambiguity | Disambiguation needed |
| Example | bkra shis bde legs | tashi delek |

### 7.2 THL Simplified Phonetic

| Aspect | THL | LPS |
|--------|-----|-----|
| Basis | Lhasa pronunciation | Multi-dialect pronunciation |
| Completeness | Common words only | Every valid syllable |
| Standardization | Informal conventions | Formal specification |
| Dialect support | Lhasa only | 4 dialects |
| Hint system | None | Yes |
| Example | tashi delek | tashi delek (same base) |

### 7.3 Tournadre's System

| Aspect | Tournadre | LPS |
|--------|-----------|-----|
| Basis | Pronunciation | Pronunciation |
| Diacritics | Uses accents (é, ö, ü) | No diacritics (keyboard-friendly) |
| Dialect support | Primarily Lhasa | 4 dialects |
| Input method | Not designed as IME | Designed as both standard and IME |

### 7.4 Pinyin (for comparison)

| Aspect | Pinyin | LPS |
|--------|--------|-----|
| Language | Mandarin Chinese | Tibetan |
| Syllable count | ~400 | ~6,000-8,000 |
| Tone marking | Required (4 tones) | Optional (2 tones in Lhasa) |
| Homophones | Extensive | Extensive |
| Disambiguation | Context + user selection | Context + user selection + hints |
| ISO standard | ISO 7098 | (To be proposed) |

---

## 8. Examples

### 8.1 Basic Input (All Modes)

| English | LPS Input | Tibetan Output |
|---------|-----------|---------------|
| auspicious | tashi | བཀྲ་ཤིས |
| happiness | delek | བདེ་ལེགས |
| Buddha | sangye | སངས་རྒྱས |
| dharma | cho | ཆོས |
| community | gendun | དགེ་འདུན |
| mind | sem | སེམས |
| wisdom | yeshe | ཡེ་ཤེས |
| vajra | dorje | རྡོ་རྗེ |
| compassion | nyingje | སྙིང་རྗེ |
| mountain | ri | རི |
| water | chu | ཆུ |
| fire | me | མེ |
| wind | lung | རླུང |
| sky | nam | གནམ |

### 8.2 Multi-Word Phrases

| LPS Input | Tibetan | Meaning |
|-----------|---------|---------|
| tashi delek | བཀྲ་ཤིས་བདེ་ལེགས | May you be auspicious and happy |
| om mani peme hung | ཨོཾ་མ་ནི་པདྨེ་ཧཱུྃ | The six-syllable mantra |
| semchen thamche | སེམས་ཅན་ཐམས་ཅད | all sentient beings |
| sangye cho gendun | སངས་རྒྱས་ཆོས་དགེ་འདུན | Buddha, Dharma, Sangha |

### 8.3 Dialect Variation

| Meaning | BO (Lhasa) | DZ (Dzongkha) | AM (Amdo) |
|---------|-----------|---------------|-----------|
| hello | tashi delek | kuzuzangpo | tashi delek |
| thank you | tukjeche | kadinche | tukjeche |
| you | khyerang | choe | khyerang |
| where | gana | gatey | gana |
| what | gare | gachi | gare |

### 8.4 Hint System Examples

| Input | Result | Explanation |
|-------|--------|-------------|
| ka | ཀ | Default (most frequent "ka") |
| `` `bka' `` | བཀའ | Exact Wylie: "command/teaching" |
| `` `ska `` | སྐ | Exact Wylie: "waist" |
| ka/ | ཀ, སྐ, རྐ, ལྐ | High-tone candidates only |
| ka\ | ག, དག, བག | Low-tone candidates only |
| lu+s | ལུས | "lu" with orthographic suffix -s = "body" |

---

## 9. Formal Grammar (BNF)

```
syllable       ::= initial vowel final?
initial        ::= cluster | consonant
cluster        ::= consonant medial
consonant      ::= 'k' | 'kh' | 'g' | 'ng' | 'c' | 'ch' | 'j' | 'ny'
                  | 't' | 'th' | 'd' | 'n' | 'p' | 'ph' | 'b' | 'm'
                  | 'ts' | 'tsh' | 'dz' | 'w' | 'zh' | 'z' | "'"
                  | 'y' | 'r' | 'l' | 'sh' | 's' | 'h'
medial         ::= 'y' | 'r' | 'l' | 'w'
vowel          ::= 'a' | 'i' | 'u' | 'e' | 'o'
final          ::= 'k' | 'ng' | 'n' | 'm' | 'p' | 'r' | 'l'

word           ::= syllable+
sentence       ::= word (' ' word)* punctuation?
punctuation    ::= '.' | '?' | '!' | ',' | ';' | ':'

hint_syllable  ::= '`' wylie_syllable          (* full Wylie *)
                  | '`' prefix '.' phonetic     (* prefix hint *)
                  | syllable '/' | syllable '\\' (* tone hint *)
                  | syllable '+' final_hint     (* final hint *)
```

---

## 10. Letter Gender Reference (མིང་གཞི་སྡེ་ཚན)

Understanding letter gender is essential for Sumtak grammar (particle selection) and prefix compatibility:

| Gender | Tibetan | Letters | Characteristics |
|--------|---------|---------|-----------------|
| **Male** (ཕོ) | Hard/voiced | ག ཇ ད བ ཛ ཝ ཞ ཟ འ ར ལ | Take genitive གི |
| **Female** (མོ) | Soft/nasal | ང ཉ ན མ | Take genitive གི |
| **Neutral** (མ་ནིང) | Voiceless | ཀ ཅ ཏ པ ཙ | Take genitive ཀྱི |

---

## Appendix A: Implementation Notes

### A.1 The Syllable Table Generation Pipeline

```python
# Using pyewts + bophono + Sumtak rules
# 1. Enumerate all valid combinations
# 2. Convert Wylie → Unicode (pyewts)
# 3. Generate pronunciation per dialect (bophono)
# 4. Normalize IPA → LPS
# 5. Build reverse indices
# 6. Merge with frequency data
```

### A.2 Keyboard Input Method Behavior

1. User types LPS romanization
2. System tokenizes into syllable candidates
3. Each syllable looked up in reverse index for active dialect
4. Multi-syllable combinations checked against word dictionary
5. Candidates ranked by: frequency × context score × user preference
6. Top candidate auto-selected if confidence > 80%; otherwise suggestion bar shown
7. User taps suggestion or hits space to commit

### A.3 Backward Compatibility

The LPS is designed to be backward-compatible with existing THL Simplified Phonetic input. All existing romanizations (tashi, delek, sangye, dorje, etc.) continue to work unchanged. The standard adds completeness and formalization without breaking existing conventions.

---

## Appendix B: Tibetan Script Quick Reference

### The 30 Root Letters

```
ཀ  ཁ  ག  ང     ka  kha  ga  nga
ཅ  ཆ  ཇ  ཉ     ca  cha  ja  nya
ཏ  ཐ  ད  ན     ta  tha  da  na
པ  ཕ  བ  མ     pa  pha  ba  ma
ཙ  ཚ  ཛ  ཝ     tsa tsha dza wa
ཞ  ཟ  འ  ཡ     zha za  'a  ya
ར  ལ  ཤ  ས     ra  la  sha sa
ཧ  ཨ            ha  a
```

### The 4 Vowel Signs

```
ི  (gigu)    = i
ུ  (zhapkyu) = u
ེ  (drengbu) = e
ོ  (naro)    = o
(inherent)   = a
```

---

*སརྦ་མངྒ་ལམ། May all be auspicious!*

*The Lotsawa Phonetic Standard — bridging scripts in the tradition of the great translators (ལོ་ཙཱ་བ) who first brought wisdom across languages.*
