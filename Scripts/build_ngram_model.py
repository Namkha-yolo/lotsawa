#!/usr/bin/env python3
"""
Enhanced n-gram model builder for Tibetan context-based disambiguation.
Version 3.0 - Now includes Hugging Face sentence dataset for richer context.

This creates bigram, trigram, and 4-gram frequencies showing which Tibetan
words commonly follow other words, allowing the keyboard to make smarter
suggestions based on context.

Key improvement in v3.0: Uses 98K full sentences from Hugging Face dataset,
providing much richer phrase-level context than dictionary entries alone.

Example: After typing ཆོས (dharma), words like ལ, ཀྱི, ཉིད are more likely
than random words, so we boost their ranking.
"""

import json
import re
import os
from collections import defaultdict
from pathlib import Path
from typing import List, Dict, Tuple, Optional

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"
DATASETS_DIR = PROJECT_DIR / "datasets"

# Known homophones that need disambiguation
HOMOPHONES = {
    "chu": ["བཅུ", "ཆུ"],       # 10 vs water
    "nga": ["ང", "ལྔ"],         # I vs 5
    "dak": ["བདག", "དག"],       # self vs pure
    "druk": ["དྲུག", "འབྲུག"],   # 6 vs Bhutan
    "choe": ["ཁྱོད", "ཆོས"],    # you (Bhutanese) vs dharma
    "me": ["མེད", "མེ"],         # not exist vs fire
    "je": ["བྱེད", "རྗེ"],       # do/make vs lord
    "che": ["ཆེ", "བྱེད"],       # big vs do/make
}


def extract_syllables(text: str) -> List[str]:
    """Extract Tibetan syllables from text."""
    # Split by tsheg, shad, and whitespace
    syllables = re.split(r'[་།༔༑\s]+', text.strip())
    return [s.strip() for s in syllables if s.strip() and len(s) > 0]


def load_phonetic_dictionary() -> List[List[str]]:
    """Load sequences from phonetic dictionary."""
    path = LOTSAWA_CORE_DIR / "phonetic_dictionary.json"
    if not path.exists():
        print(f"  Warning: {path} not found")
        return []

    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    sequences = []
    for phonetic, tibetan_list in data.items():
        for tibetan in tibetan_list:
            syllables = extract_syllables(tibetan)
            if len(syllables) >= 2:
                sequences.append(syllables)

    return sequences


def load_entries_txt() -> List[List[str]]:
    """Load vocabulary entries from bo-pos entries.txt."""
    path = DATASETS_DIR / "bo-pos" / "models" / "ngram" / "entries.txt"
    if not path.exists():
        print(f"  Warning: {path} not found")
        return []

    sequences = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            syllables = extract_syllables(line)
            if len(syllables) >= 2:
                sequences.append(syllables)

    return sequences


def load_soas_lexicon() -> List[List[str]]:
    """Load SOAS lexicon entries."""
    path = DATASETS_DIR / "bo-pos" / "rc" / "SOAS-lexicon.txt"
    if not path.exists():
        print(f"  Warning: {path} not found")
        return []

    sequences = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            # Format: word\tPOS_tags...
            parts = line.strip().split('\t')
            if parts:
                tibetan = parts[0].strip()
                syllables = extract_syllables(tibetan)
                if len(syllables) >= 2:
                    sequences.append(syllables)

    return sequences


def load_mgd_lexicon() -> List[List[str]]:
    """Load Monlam Grand Dictionary lexicon."""
    path = DATASETS_DIR / "bo-pos" / "rc" / "mgd-lexicon.txt"
    if not path.exists():
        print(f"  Warning: {path} not found")
        return []

    sequences = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            # Format: tibetan : ['pos_tag']
            if ':' in line:
                tibetan = line.split(':')[0].strip()
                syllables = extract_syllables(tibetan)
                if len(syllables) >= 2:
                    sequences.append(syllables)

    return sequences


def load_huggingface_sentences() -> List[List[str]]:
    """
    Load full Tibetan sentences from Hugging Face dataset.
    This provides rich phrase-level context for n-gram training.

    Dataset: billingsmoore/tibetan-phonetic-transliteration-dataset
    Contains ~98,000 Tibetan sentences with their phonetic transliterations.
    """
    try:
        from datasets import load_dataset
    except ImportError:
        print("  Warning: 'datasets' library not installed. Run: pip install datasets")
        print("  Skipping Hugging Face sentence data...")
        return []

    print("  Loading Hugging Face sentence dataset...")
    print("    (This may take a moment on first run to download)")

    try:
        dataset = load_dataset(
            "billingsmoore/tibetan-phonetic-transliteration-dataset",
            trust_remote_code=True
        )
    except Exception as e:
        print(f"  Warning: Failed to load Hugging Face dataset: {e}")
        return []

    sequences = []

    # Get column names - first column is Tibetan text
    columns = dataset['train'].column_names
    tibetan_col = columns[0]  # First column is Tibetan

    # Process each sentence
    sentence_count = 0
    for item in dataset['train']:
        tibetan = item.get(tibetan_col, '').strip()
        if tibetan:
            syllables = extract_syllables(tibetan)
            # Only include sentences with 2+ syllables
            if len(syllables) >= 2:
                sequences.append(syllables)
                sentence_count += 1

    print(f"    → Extracted {sentence_count} sentences with valid syllable sequences")

    # Show average sentence length for debugging
    if sequences:
        avg_len = sum(len(s) for s in sequences) / len(sequences)
        print(f"    → Average sentence length: {avg_len:.1f} syllables")

    return sequences


def build_bigram_model(sequences: List[List[str]]) -> Dict[str, Dict[str, int]]:
    """Build bigram frequency model."""
    bigrams = defaultdict(lambda: defaultdict(int))

    for seq in sequences:
        for i in range(len(seq) - 1):
            word1 = seq[i]
            word2 = seq[i + 1]
            if word1 and word2:
                bigrams[word1][word2] += 1

    # Convert to regular dict and filter
    model = {}
    for word1, following in bigrams.items():
        filtered = {w2: count for w2, count in following.items() if count >= 2}
        if filtered:
            sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:30]
            model[word1] = dict(sorted_following)

    return model


def build_trigram_model(sequences: List[List[str]]) -> Dict[str, Dict[str, int]]:
    """Build trigram frequency model."""
    trigrams = defaultdict(lambda: defaultdict(int))

    for seq in sequences:
        for i in range(len(seq) - 2):
            context = f"{seq[i]}|{seq[i+1]}"
            word3 = seq[i + 2]
            if word3:
                trigrams[context][word3] += 1

    # Convert and filter
    model = {}
    for context, following in trigrams.items():
        filtered = {w: count for w, count in following.items() if count >= 2}
        if filtered:
            sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:15]
            model[context] = dict(sorted_following)

    return model


def build_fourgram_model(sequences: List[List[str]]) -> Dict[str, Dict[str, int]]:
    """Build 4-gram frequency model for stronger phrase context."""
    fourgrams = defaultdict(lambda: defaultdict(int))

    for seq in sequences:
        for i in range(len(seq) - 3):
            context = f"{seq[i]}|{seq[i+1]}|{seq[i+2]}"
            word4 = seq[i + 3]
            if word4:
                fourgrams[context][word4] += 1

    # Convert and filter
    model = {}
    for context, following in fourgrams.items():
        filtered = {w: count for w, count in following.items() if count >= 2}
        if filtered:
            sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:10]
            model[context] = dict(sorted_following)

    return model


def compute_word_frequencies(sequences: List[List[str]]) -> Dict[str, int]:
    """Compute overall word frequencies for smoothing."""
    freq = defaultdict(int)
    for seq in sequences:
        for word in seq:
            if word:
                freq[word] += 1

    # Filter out very rare words
    return {w: c for w, c in freq.items() if c >= 3}


def build_homophone_contexts(bigrams: Dict, trigrams: Dict) -> Dict:
    """Build special context patterns for known homophones."""
    homophone_contexts = {}

    for phonetic, tibetan_options in HOMOPHONES.items():
        contexts = {}
        for tibetan in tibetan_options:
            syllables = extract_syllables(tibetan)
            syllable = syllables[0] if syllables else tibetan

            # Find which words commonly precede this option
            preceding = []
            for ctx, followers in bigrams.items():
                if syllable in followers:
                    preceding.append((ctx, followers[syllable]))

            # Find which words commonly follow this option
            following = []
            if syllable in bigrams:
                for w, count in bigrams[syllable].items():
                    following.append((w, count))

            contexts[tibetan] = {
                "preceding": sorted(preceding, key=lambda x: -x[1])[:10],
                "following": sorted(following, key=lambda x: -x[1])[:10]
            }

        homophone_contexts[phonetic] = contexts

    return homophone_contexts


def main():
    print("=" * 60)
    print("ལོ་ཙཱ་བ། Building Enhanced N-gram Context Model v3.0")
    print("=" * 60)

    all_sequences = []

    # Load from all sources
    print("\n📚 Loading corpus sources...")

    # 1. Hugging Face sentences - MOST VALUABLE for context
    # These are full sentences with rich phrase-level n-grams
    hf_seqs = load_huggingface_sentences()
    print(f"    → {len(hf_seqs)} sentence sequences")
    # Weight sentences higher - they provide real context
    # Each sentence contributes multiple n-grams across its full length
    all_sequences.extend(hf_seqs)
    all_sequences.extend(hf_seqs)  # Double weight for sentence data

    print("\n  Loading phonetic_dictionary.json...")
    phonetic_seqs = load_phonetic_dictionary()
    print(f"    → {len(phonetic_seqs)} sequences")
    all_sequences.extend(phonetic_seqs)

    print("  Loading bo-pos entries.txt...")
    entries_seqs = load_entries_txt()
    print(f"    → {len(entries_seqs)} sequences")
    # Weight these higher (duplicate to increase influence)
    all_sequences.extend(entries_seqs)
    all_sequences.extend(entries_seqs)

    print("  Loading SOAS-lexicon.txt...")
    soas_seqs = load_soas_lexicon()
    print(f"    → {len(soas_seqs)} sequences")
    all_sequences.extend(soas_seqs)

    print("  Loading mgd-lexicon.txt...")
    mgd_seqs = load_mgd_lexicon()
    print(f"    → {len(mgd_seqs)} sequences")
    all_sequences.extend(mgd_seqs)

    print(f"\n📊 Total sequences: {len(all_sequences)}")
    if hf_seqs:
        print(f"   (Including {len(hf_seqs)} full sentences from Hugging Face)")

    if not all_sequences:
        print("No sequences found!")
        return

    # Build models
    print("\n🔨 Building n-gram models...")

    print("  Building bigram model...")
    bigram_model = build_bigram_model(all_sequences)
    print(f"    → {len(bigram_model)} words have context data")

    print("  Building trigram model...")
    trigram_model = build_trigram_model(all_sequences)
    print(f"    → {len(trigram_model)} bigram contexts have data")

    print("  Building 4-gram model...")
    fourgram_model = build_fourgram_model(all_sequences)
    print(f"    → {len(fourgram_model)} trigram contexts have data")

    print("  Computing word frequencies...")
    word_freq = compute_word_frequencies(all_sequences)
    print(f"    → {len(word_freq)} unique words")

    print("\n🎯 Building homophone disambiguation contexts...")
    homophone_contexts = build_homophone_contexts(bigram_model, trigram_model)
    print(f"    → {len(homophone_contexts)} homophones analyzed")

    # Combine into single model
    context_model = {
        "bigrams": bigram_model,
        "trigrams": trigram_model,
        "fourgrams": fourgram_model,
        "word_freq": word_freq,
        "homophone_contexts": homophone_contexts,
        "version": "3.0",
        "sources": {
            "huggingface_sentences": len(hf_seqs),
            "phonetic_dictionary": len(phonetic_seqs),
            "bo_pos_entries": len(entries_seqs),
            "soas_lexicon": len(soas_seqs),
            "mgd_lexicon": len(mgd_seqs),
        }
    }

    # Save model
    output_path = LOTSAWA_CORE_DIR / "context_model.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(context_model, f, ensure_ascii=False, separators=(',', ':'))

    size_kb = output_path.stat().st_size / 1024
    print(f"\n✅ Saved to {output_path}")
    print(f"   Size: {size_kb:.1f} KB")

    # Show sample bigrams
    print("\n📝 Sample bigrams (word → common followers):")
    samples = ['ཆོས', 'སངས', 'རྒྱས', 'བདག', 'སེམས', 'ཡིན', 'ལ', 'གི', 'ཐུང', 'ཆུ']
    for word in samples:
        if word in bigram_model:
            followers = list(bigram_model[word].items())[:3]
            follower_str = ', '.join(f"{w}({c})" for w, c in followers)
            print(f"  {word} → {follower_str}")

    # Show homophone examples
    print("\n🎯 Homophone context examples:")
    for phonetic, options in list(homophone_contexts.items())[:3]:
        print(f"\n  '{phonetic}':")
        for tibetan, ctx in options.items():
            prec = ctx['preceding'][:2]
            foll = ctx['following'][:2]
            prec_str = ', '.join(f"{p[0]}({p[1]})" for p in prec) if prec else "none"
            foll_str = ', '.join(f"{f[0]}({f[1]})" for f in foll) if foll else "none"
            print(f"    {tibetan}: preceded by [{prec_str}], followed by [{foll_str}]")

    print("\n✅ DONE!")


if __name__ == "__main__":
    main()
