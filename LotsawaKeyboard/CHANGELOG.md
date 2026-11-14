# Lotsawa Keyboard - Development Changelog

## Session: January 24, 2026

### Summary
Major enhancements to the Lotsawa Keyboard's n-gram disambiguation system and dictionary expansion, significantly improving the keyboard's ability to suggest the correct Tibetan word based on context.

---

## 1. N-gram Disambiguation Enhancement (v3.0)

### Problem Solved
The keyboard needed to disambiguate homophones - words that sound the same but have different meanings and spellings:
- `chu` → བཅུ (10) vs ཆུ (water)
- `dak` → བདག (self) vs དག (pure)
- `nga` → ང (I) vs ལྔ (5)

### Solution
Enhanced the n-gram model training to use **98,529 full sentences** from the Hugging Face dataset, providing rich phrase-level context.

### Changes Made

**File: `Scripts/build_ngram_model.py`**
- Updated to v3.0
- Added `load_huggingface_sentences()` function to load full Tibetan sentences
- Sentences provide much richer context than dictionary entries alone
- Double-weighted sentence data for stronger phrase patterns

**Results:**
| Metric | Before | After |
|--------|--------|-------|
| Total sequences | ~200K | 550,190 |
| Bigram contexts | ~5K | 8,893 |
| Trigram contexts | ~50K | 112,418 |
| 4-gram contexts | ~100K | 219,984 |
| Model size | 10 MB | 18.3 MB |

### Disambiguation Examples
After enhancement, the system correctly suggests:
- After དགུ (9), "chu" → བཅུ (10) first
- After འཐུང (drink), "chu" → ཆུ (water) first
- After བདག (self), "gi" → གི (genitive) first

---

## 2. Dictionary Expansion

### Problem Solved
The keyboard had limited vocabulary coverage (~36K phonetic entries).

### Solution
Used `bophono` library to generate phonetic romanizations for words from multiple Tibetan lexicons.

### New Scripts Created

**File: `Scripts/expand_dictionary.py`**
- Loads Tibetan words from SOAS lexicon, MGD lexicon, bo-pos entries, and verb database
- Uses bophono (LKT schema) to generate phonetic romanizations
- Merges new entries into existing dictionary

**File: `Scripts/rebuild_lookup.py`**
- Rebuilds `phonetic_lookup.json` from expanded dictionary
- Includes frequency data for ranking
- Creates both spaced and non-spaced lookup keys

### Data Sources Integrated
| Source | Words Added |
|--------|-------------|
| SOAS Lexicon | 15,628 |
| Monlam Grand Dictionary | 107,064 |
| bo-pos entries | 107,064 |
| Tibetan Verbs Database | 3,093 |

### Results
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Phonetic entries | 36,332 | 126,191 | +247% |
| Tibetan mappings | 38,608 | 149,333 | +287% |
| Lookup index entries | 72,884 | 164,120 | +125% |
| Dictionary size | 6 MB | 14.3 MB | +138% |

---

## 3. Bug Fixes

- Fixed `Package.swift` syntax error (corrupted string literal)
- Added missing `word_frequency.json` to resources

---

## 4. Testing

Created `Sources/LotsawaDemo/test_disambiguation.swift` for testing:
- Tests homophones without context
- Tests context-based disambiguation
- Tests semantic hints
- Verifies n-gram model loading

Run tests with:
```bash
cd LotsawaCore && swift run LotsawaDemo test
```

---

## Files Modified/Created

### Modified
- `Scripts/build_ngram_model.py` - v3.0 with Hugging Face sentences
- `LotsawaCore/Package.swift` - Fixed syntax, added resources
- `LotsawaCore/Sources/LotsawaCore/context_model.json` - Rebuilt with 550K sequences
- `LotsawaCore/Sources/LotsawaCore/phonetic_dictionary.json` - Expanded to 126K entries
- `LotsawaCore/Sources/LotsawaCore/phonetic_lookup.json` - Rebuilt with 164K entries

### Created
- `Scripts/expand_dictionary.py` - Dictionary expansion tool
- `Scripts/rebuild_lookup.py` - Lookup index rebuilder
- `LotsawaCore/Sources/LotsawaDemo/test_disambiguation.swift` - Disambiguation tests
- `LotsawaKeyboard/CHANGELOG.md` - This file

---

## Architecture Overview

```
User types: "tashi delek"
     ↓
┌─────────────────────────────────────┐
│ PhoneticMapper                       │
│ - Loads phonetic_lookup.json (164K)  │
│ - TrieIndex for fast prefix lookup   │
└─────────────────────────────────────┘
     ↓
┌─────────────────────────────────────┐
│ ContextEngine                        │
│ - Loads context_model.json (18MB)    │
│ - Bigrams, trigrams, 4-grams         │
│ - Scores candidates by context       │
│ - 80% confidence auto-select         │
└─────────────────────────────────────┘
     ↓
Output: བཀྲ་ཤིས་བདེ་ལེགས
```

---

## Next Steps (Future Work)

1. **User Learning** - Adapt to individual typing patterns
2. **Abbreviations** - "td" → "tashi delek"
3. **Dialect Support** - Amdo and Kham phonetic variations
4. **Cloud Sync** - Sync user dictionary across devices

---

*Last Updated: January 24, 2026*
