# ལོ་ཙཱ་བ། Lotsawa — a phonetic input method for Tibetan

**Lotsawa** lets you type Tibetan the way you say it. Type `tashi delek` and get བཀྲ་ཤིས་བདེ་ལེགས; type Wylie `bkra shis bde legs` and get the same. The engine resolves romanized input — phonetic or any of the five legacy Roman schemes (Wylie, EWTS, THL, Tournadre, ZWPY) — to correct Tibetan orthography using corpus n-gram models, a BiLSTM context model, a curated dictionary, and a computational formalization of the Sumtak (སུམ་རྟགས་) grammar. Everything runs on-device.

- **Paper:** *The Lotsawa Standard: A Phonetic Input Protocol for Tibetan, with Statistical Disambiguation and a Computational Sumtak Grammar* — [`paper/main.tex`](paper/main.tex), PDF at [namkhatashioedzer.com/lotsawa-standard.pdf](https://namkhatashioedzer.com/lotsawa-standard.pdf) <!-- TODO: confirm the public URL -->
- **App:** Lotsawa Keyboard on the iOS App Store — https://apps.apple.com/app/id6757952504
- **Author:** Namkha Tashi Oedzer · oedzernamkha@gmail.com

## Why

Chinese has Pinyin; Japanese has romaji-to-kana-to-kanji. Tibetan has had nothing comparable in the thirty years since it entered Unicode. The existing romanization schemes solve the *forward* problem (Tibetan → Roman letters). Keyboard input needs the *inverse*: given what a user typed, which Tibetan form did they mean? Tibetan homophone density makes that hard — `chu` is ཆུ (water) or བཅུ (ten) depending on context.

## Results

Held-out accuracy on 20,000 sentence-level queries (Table 4 of the paper):

| System | Top-1 | Top-5 | Top-10 | ms / query |
| --- | --- | --- | --- | --- |
| Frequency-only dictionary (≈ every current Tibetan keyboard) | 21.4% | 28.1% | 28.5% | 0.03 |
| + n-gram context | 24.6% | 28.4% | 28.5% | 0.06 |
| BiLSTM only | 48.9% | 68.0% | 74.3% | 0.35 |
| **Hybrid (this repo)** | **52.4%** | **71.7%** | **77.1%** | 0.46 |

Latency measured on Apple Silicon. The full pipeline runs inside a 50 MB resident-memory budget (the iOS keyboard-extension limit); the SQLite dictionary is memory-mapped.

## How it works

Three layers, specified normatively in the paper:

1. **Normalization** — `PhoneticMapper`, `WylieMapper`, `PhoneticFuzzyMatcher`: map any romanization or unmarked user phonetics to a canonical phonetic form; dialect variants (Lhasa, Amdo, Kham, Dzongkha) included.
2. **Statistical disambiguation** — `ContextEngine` (66,193 bigrams, 226,524 trigrams, 287,062 4-grams), `MLPredictor` (single-layer BiLSTM, 877K parameters, compiled to a 3.45 MB CoreML model), `SQLiteDictionary` (184,180 phonetic entries), with `sumtak_rules.json` applied as hard constraints on particle selection. Four signals are linearly interpolated (0.40 / 0.30 / 0.20 / 0.10); the dictionary filter and Sumtak override are applied last.
3. **Personalization** — `UserLearningStore`, `PhraseCorrector`: selection history with 30-day half-life decay, retroactive phrase correction, personal vocabulary. All data stays in the App Group container.

```
romanized input
   └─ Normalization (PhoneticMapper · WylieMapper · PhoneticFuzzyMatcher)
        └─ Candidates (TrieIndex over SQLiteDictionary)
             └─ Scoring (ContextEngine n-grams + MLPredictor BiLSTM + frequency + fuzzy)
                  └─ Constraints (dictionary filter · Sumtak rules)
                       └─ Personalization (UserLearningStore · PhraseCorrector)
                            └─ suggestion bar / auto-commit (confidence > 0.80, margin > 0.20)
```

## Repository layout

```
LotsawaCore/        Swift package: the whole three-layer pipeline + LotsawaDemo CLI + tests
LotsawaKeyboard/    iOS app and keyboard extension (SwiftUI + UIKit) that host LotsawaCore
Scripts/            Python: data download, dictionary / n-gram / SQLite builders, BiLSTM training,
                    CoreML export, evaluation and baselines
paper/              LaTeX source of The Lotsawa Standard (XeLaTeX)
LOTSAWA_KEYBOARD_PLAN.md   project documentation and feature list
```

## Build and run

Requirements: Xcode 15+ / Swift 5.9, macOS 12+. Large data files are stored with Git LFS — install it before cloning (`brew install git-lfs && git lfs install`).

```bash
cd LotsawaCore
swift build
swift test                      # unit tests
swift run LotsawaDemo           # interactive demo
swift run LotsawaDemo backtest  # accuracy backtest
swift run LotsawaDemo edge      # edge-case suite
swift run LotsawaDemo splittest # syllable-split regression
```

The iOS app: open `LotsawaKeyboard/LotsawaKeyboard.xcodeproj`, select the `LotsawaKeyboard` scheme, run on a device, then enable the keyboard in Settings → General → Keyboard → Keyboards.

## Rebuilding the data and the model

```bash
cd Scripts
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt            # TODO: generate with pip freeze
python download_dataset.py                 # 98,596 (Tibetan, phonetic) pairs from Hugging Face (billingsmoore)
python build_database.py                   # phonetic dictionary
python build_phonetic_variations.py        # dialect and spelling variants
python build_ngram_model.py && python build_enhanced_ngram.py
python build_semantic_hints.py
python build_sqlite.py && python optimize_database.py   # lotsawa.db
python train_lotsawa_model.py              # BiLSTM, 30 epochs, ~105 min on Apple Silicon (MPS)
python export_coreml.py                    # TibetanLM.mlmodel
python eval_lotsawa_model.py               # Tables 4 and 5; writes LotsawaCore/Sources/LotsawaCore/results.json
```

Training data: Billingsmoore (2024) parallel corpus, the Monlam Grand Dictionary, the SOAS Tibetan Lexicon, `bo-pos`, and `tibetan-verbs-database`. The third-party sets are not vendored; `download_dataset.py` fetches the corpus and the `datasets/` folder is where the others are cloned (see the paper's Data section for sources).

## Status

- iOS: shipping on the App Store.
- macOS (InputMethodKit) and Android (InputMethodService): planned; all language logic in `LotsawaCore` is platform-independent.
- Known gap: the 46-case homophone suite (Table 5) probes contexts rare in the classical-dharma-heavy corpus; the production semantic-hint table, excluded from the paper's evaluation, closes most of it.

## Citation

```bibtex
@misc{oedzer2026lotsawa,
  title  = {The Lotsawa Standard: A Phonetic Input Protocol for Tibetan, with Statistical Disambiguation and a Computational Sumtak Grammar},
  author = {Oedzer, Namkha Tashi},
  year   = {2026},
  note   = {https://github.com/Namkha-yolo/lotsawa}
}
```

## License

TODO — choose one before publishing (MIT or Apache-2.0 for the code; note that the dictionary and corpus carry their own licenses).
