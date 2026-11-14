#!/usr/bin/env python3
"""
Enhanced domain-aware n-gram model builder for Tibetan context-based disambiguation.
Version 4.0 - Adds domain detection and weighted scoring by text domain.

This builds upon the v3.0 n-gram model by adding:
1. Domain detection (dharma, colloquial, formal, number)
2. Domain-weighted n-gram frequencies
3. Cross-domain patterns for disambiguation
4. Enhanced homophone context analysis

Domains:
- dharma: Buddhist terminology, religious texts
- colloquial: Everyday speech, informal writing
- formal: Official documents, news, formal writing
- number: Counting, dates, quantities
"""

import json
import re
import os
from collections import defaultdict
from pathlib import Path
from typing import List, Dict, Tuple, Optional, Set

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"
DATASETS_DIR = PROJECT_DIR / "datasets"

# =============================================================================
# DOMAIN VOCABULARY
# =============================================================================

# Dharma domain vocabulary
DHARMA_VOCABULARY = {
    # Three Jewels
    "སངས", "རྒྱས", "ཆོས", "དགེ", "འདུན",
    # Teachers and titles
    "བླ", "མ", "རྗེ", "རིན", "པོ", "ཆེ", "མཁན", "པོ", "སྤྲུལ", "སྐུ",
    # Body/Speech/Mind (honorific)
    "སྐུ", "གསུང", "ཐུགས",
    # Practice terms
    "སྒྲུབ", "ཉམས", "ལེན", "བསྐྱེད", "རྫོགས", "རིམ", "སྔགས",
    # Empowerments and teachings
    "དབང", "ལུང", "ཁྲིད", "བཀའ", "གདམས",
    # Self and mind
    "བདག", "སེམས", "རིག", "པ", "ཡེ", "ཤེས",
    # Emptiness and enlightenment
    "སྟོང", "ཉིད", "བྱང", "ཆུབ",
    # Refuge
    "སྐྱབས", "འགྲོ", "ཕྱག", "འཚལ",
    # Compassion and wisdom
    "སྙིང", "རྗེ", "ཤེས", "རབ", "ཐབས",
    # Offering and mandala
    "མཆོད", "དཀྱིལ", "འཁོར",
}

# Colloquial domain vocabulary
COLLOQUIAL_VOCABULARY = {
    # Pronouns
    "ང", "ཁྱོད", "ཁྱེད", "ཁོ", "མོ", "རང",
    # Common verbs
    "ཡིན", "རེད", "ཡོད", "མེད", "འདུག", "བྱེད", "ཟ", "ཐུང", "འགྲོ", "ཡོང",
    # Questions
    "ག", "རེ", "སུ", "ཅི", "ནས", "དུས", "ཚོད",
    # Common nouns
    "མི", "ཁང", "ལམ", "ཆུ", "མེ", "ཁ", "ལག",
    # Adjectives
    "བཟང", "ངན", "ཆེ", "ཆུང", "རིང", "ཐུང", "ཡག",
    # Time words
    "དེང", "སང", "ཁ", "མདང", "ཉིན", "མཚན",
}

# Number domain vocabulary
NUMBER_VOCABULARY = {
    # Cardinal numbers
    "གཅིག", "གཉིས", "གསུམ", "བཞི", "ལྔ", "དྲུག", "བདུན", "བརྒྱད", "དགུ", "བཅུ",
    # Tens
    "ཉི", "ཤུ", "སུམ", "ཅུ", "བཞི", "བཅུ", "ལྔ", "བཅུ",
    # Hundreds and thousands
    "བརྒྱ", "སྟོང", "ཁྲི",
    # Counting words
    "གྲངས", "བསྡོམས", "ཚད", "རིམ",
    # Ordinals
    "དང", "པོ", "གཉིས", "པ", "གསུམ", "པ",
}

# Formal domain vocabulary
FORMAL_VOCABULARY = {
    # Government and official
    "གཞུང", "བཀའ", "ཤག", "དྲུང", "ཡིག", "བློན", "ཆེན",
    # Legal
    "ཁྲིམས", "ལུགས", "བཅའ", "ཁྲིམས",
    # Organizations
    "ཚོགས", "པ", "ལྷན", "ཁང",
    # Titles
    "མཆོག", "དཔོན", "གཙོ",
}

# Known homophones for enhanced analysis
HOMOPHONES = {
    "chu": ["བཅུ", "ཆུ"],       # 10 vs water
    "nga": ["ང", "ལྔ", "མངའ"], # I vs 5 vs authority
    "dak": ["བདག", "དག"],       # self vs pure
    "druk": ["དྲུག", "འབྲུག"],   # 6 vs Bhutan
    "choe": ["ཁྱོད", "ཆོས"],    # you (Bhutanese) vs dharma
    "me": ["མེད", "མེ"],         # not exist vs fire
    "je": ["བྱེད", "རྗེ"],       # do/make vs lord
    "che": ["ཆེ", "བྱེད"],       # big vs do/make
    "gye": ["བརྒྱད", "རྒྱས"],   # 8 vs spread/expand
    "gu": ["དགུ", "སྐུ"],        # 9 vs body (honorific)
    "dun": ["བདུན", "དོན"],      # 7 vs meaning
    "shi": ["བཞི", "འཆི"],       # 4 vs death
    "la": ["ལ", "བླ"],          # particle vs soul
    "pa": ["པ", "དཔའ"],         # nominalizer vs brave
    "re": ["རེ", "རེད"],         # question vs is
    "kor": ["འཁོར", "སྐོར"],    # retinue vs about
}


def extract_syllables(text: str) -> List[str]:
    """Extract Tibetan syllables from text."""
    syllables = re.split(r'[་།༔༑\s]+', text.strip())
    return [s.strip() for s in syllables if s.strip() and len(s) > 0]


def detect_domain(syllables: List[str]) -> str:
    """Detect the domain of a sequence of syllables."""
    dharma_count = sum(1 for s in syllables if s in DHARMA_VOCABULARY)
    colloquial_count = sum(1 for s in syllables if s in COLLOQUIAL_VOCABULARY)
    number_count = sum(1 for s in syllables if s in NUMBER_VOCABULARY)
    formal_count = sum(1 for s in syllables if s in FORMAL_VOCABULARY)

    total = len(syllables)
    if total == 0:
        return "unknown"

    # Calculate percentages
    dharma_pct = dharma_count / total
    colloquial_pct = colloquial_count / total
    number_pct = number_count / total
    formal_pct = formal_count / total

    # Determine domain based on percentages
    if number_pct >= 0.3 or (number_count >= 2 and total <= 5):
        return "number"
    if dharma_pct >= 0.3 or (dharma_count >= 3 and dharma_pct > colloquial_pct):
        return "dharma"
    if formal_pct >= 0.2:
        return "formal"
    if colloquial_pct >= 0.2 or colloquial_count >= 2:
        return "colloquial"

    return "unknown"


def load_phonetic_dictionary() -> List[Tuple[List[str], str]]:
    """Load sequences from phonetic dictionary with domain."""
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
                domain = detect_domain(syllables)
                sequences.append((syllables, domain))

    return sequences


def load_huggingface_sentences() -> List[Tuple[List[str], str]]:
    """Load Tibetan sentences from Hugging Face dataset with domain detection."""
    try:
        from datasets import load_dataset
    except ImportError:
        print("  Warning: 'datasets' library not installed")
        return []

    print("  Loading Hugging Face dataset...")
    try:
        dataset = load_dataset(
            "billingsmoore/tibetan-phonetic-transliteration-dataset",
            trust_remote_code=True
        )
    except Exception as e:
        print(f"  Warning: Failed to load dataset: {e}")
        return []

    sequences = []
    columns = dataset['train'].column_names
    tibetan_col = columns[0]

    domain_counts = defaultdict(int)

    for item in dataset['train']:
        tibetan = item.get(tibetan_col, '').strip()
        if tibetan:
            syllables = extract_syllables(tibetan)
            if len(syllables) >= 2:
                domain = detect_domain(syllables)
                sequences.append((syllables, domain))
                domain_counts[domain] += 1

    print(f"    → {len(sequences)} sentences")
    print(f"    → Domain distribution: {dict(domain_counts)}")

    return sequences


def load_entries_txt() -> List[Tuple[List[str], str]]:
    """Load vocabulary entries with domain detection."""
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
                domain = detect_domain(syllables)
                sequences.append((syllables, domain))

    return sequences


def build_domain_bigram_model(
    sequences: List[Tuple[List[str], str]]
) -> Dict[str, Dict[str, Dict[str, int]]]:
    """Build domain-aware bigram frequency model.

    Returns: {domain: {word1: {word2: count}}}
    """
    domain_bigrams = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))

    for syllables, domain in sequences:
        for i in range(len(syllables) - 1):
            word1 = syllables[i]
            word2 = syllables[i + 1]
            if word1 and word2:
                domain_bigrams[domain][word1][word2] += 1

    # Convert and filter
    model = {}
    for domain, bigrams in domain_bigrams.items():
        model[domain] = {}
        for word1, following in bigrams.items():
            filtered = {w2: c for w2, c in following.items() if c >= 2}
            if filtered:
                sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:30]
                model[domain][word1] = dict(sorted_following)

    return model


def build_domain_trigram_model(
    sequences: List[Tuple[List[str], str]]
) -> Dict[str, Dict[str, Dict[str, int]]]:
    """Build domain-aware trigram frequency model."""
    domain_trigrams = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))

    for syllables, domain in sequences:
        for i in range(len(syllables) - 2):
            context = f"{syllables[i]}|{syllables[i+1]}"
            word3 = syllables[i + 2]
            if word3:
                domain_trigrams[domain][context][word3] += 1

    # Convert and filter
    model = {}
    for domain, trigrams in domain_trigrams.items():
        model[domain] = {}
        for context, following in trigrams.items():
            filtered = {w: c for w, c in following.items() if c >= 2}
            if filtered:
                sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:15]
                model[domain][context] = dict(sorted_following)

    return model


def merge_bigram_models(domain_bigrams: Dict) -> Dict[str, Dict[str, int]]:
    """Merge domain bigrams into single model with domain weighting."""
    merged = defaultdict(lambda: defaultdict(int))

    # Weight by domain (dharma terms get slight boost in dharma context, etc.)
    for domain, bigrams in domain_bigrams.items():
        for word1, following in bigrams.items():
            for word2, count in following.items():
                merged[word1][word2] += count

    # Convert and filter
    model = {}
    for word1, following in merged.items():
        filtered = {w2: c for w2, c in following.items() if c >= 2}
        if filtered:
            sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:30]
            model[word1] = dict(sorted_following)

    return model


def merge_trigram_models(domain_trigrams: Dict) -> Dict[str, Dict[str, int]]:
    """Merge domain trigrams into single model."""
    merged = defaultdict(lambda: defaultdict(int))

    for domain, trigrams in domain_trigrams.items():
        for context, following in trigrams.items():
            for word, count in following.items():
                merged[context][word] += count

    # Convert and filter
    model = {}
    for context, following in merged.items():
        filtered = {w: c for w, c in following.items() if c >= 2}
        if filtered:
            sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:15]
            model[context] = dict(sorted_following)

    return model


def build_fourgram_model(sequences: List[Tuple[List[str], str]]) -> Dict[str, Dict[str, int]]:
    """Build 4-gram frequency model for stronger phrase context."""
    fourgrams = defaultdict(lambda: defaultdict(int))

    for syllables, _ in sequences:
        for i in range(len(syllables) - 3):
            context = f"{syllables[i]}|{syllables[i+1]}|{syllables[i+2]}"
            word4 = syllables[i + 3]
            if word4:
                fourgrams[context][word4] += 1

    # Convert and filter
    model = {}
    for context, following in fourgrams.items():
        filtered = {w: c for w, c in following.items() if c >= 2}
        if filtered:
            sorted_following = sorted(filtered.items(), key=lambda x: -x[1])[:10]
            model[context] = dict(sorted_following)

    return model


def compute_word_frequencies(sequences: List[Tuple[List[str], str]]) -> Dict[str, int]:
    """Compute overall word frequencies."""
    freq = defaultdict(int)
    for syllables, _ in sequences:
        for word in syllables:
            if word:
                freq[word] += 1
    return {w: c for w, c in freq.items() if c >= 3}


def build_enhanced_homophone_contexts(
    domain_bigrams: Dict,
    merged_bigrams: Dict
) -> Dict:
    """Build enhanced context patterns for homophones with domain awareness."""
    homophone_contexts = {}

    for phonetic, tibetan_options in HOMOPHONES.items():
        contexts = {}
        for tibetan in tibetan_options:
            syllables = extract_syllables(tibetan)
            syllable = syllables[0] if syllables else tibetan

            # Collect preceding words by domain
            preceding_by_domain = defaultdict(list)
            for domain, bigrams in domain_bigrams.items():
                for ctx, followers in bigrams.items():
                    if syllable in followers:
                        preceding_by_domain[domain].append((ctx, followers[syllable]))

            # Collect following words by domain
            following_by_domain = defaultdict(list)
            for domain, bigrams in domain_bigrams.items():
                if syllable in bigrams:
                    for w, count in bigrams[syllable].items():
                        following_by_domain[domain].append((w, count))

            # Sort and limit
            for domain in preceding_by_domain:
                preceding_by_domain[domain] = sorted(
                    preceding_by_domain[domain], key=lambda x: -x[1]
                )[:5]
            for domain in following_by_domain:
                following_by_domain[domain] = sorted(
                    following_by_domain[domain], key=lambda x: -x[1]
                )[:5]

            # Overall preceding/following
            preceding = []
            for ctx, followers in merged_bigrams.items():
                if syllable in followers:
                    preceding.append((ctx, followers[syllable]))
            preceding = sorted(preceding, key=lambda x: -x[1])[:10]

            following = []
            if syllable in merged_bigrams:
                for w, count in merged_bigrams[syllable].items():
                    following.append((w, count))
            following = sorted(following, key=lambda x: -x[1])[:10]

            contexts[tibetan] = {
                "preceding": preceding,
                "following": following,
                "preceding_by_domain": dict(preceding_by_domain),
                "following_by_domain": dict(following_by_domain),
            }

        homophone_contexts[phonetic] = contexts

    return homophone_contexts


def main():
    print("=" * 60)
    print("ལོ་ཙཱ་བ། Building Enhanced Domain-Aware N-gram Model v4.0")
    print("=" * 60)

    all_sequences = []

    print("\n📚 Loading corpus sources with domain detection...")

    # Load Hugging Face sentences
    hf_seqs = load_huggingface_sentences()
    # Double weight for sentence data (better context)
    all_sequences.extend(hf_seqs)
    all_sequences.extend(hf_seqs)

    # Load other sources
    print("  Loading phonetic_dictionary.json...")
    phonetic_seqs = load_phonetic_dictionary()
    print(f"    → {len(phonetic_seqs)} sequences")
    all_sequences.extend(phonetic_seqs)

    print("  Loading bo-pos entries.txt...")
    entries_seqs = load_entries_txt()
    print(f"    → {len(entries_seqs)} sequences")
    all_sequences.extend(entries_seqs)
    all_sequences.extend(entries_seqs)

    print(f"\n📊 Total sequences: {len(all_sequences)}")

    if not all_sequences:
        print("No sequences found!")
        return

    # Build domain-aware models
    print("\n🔨 Building domain-aware n-gram models...")

    print("  Building domain bigram model...")
    domain_bigram_model = build_domain_bigram_model(all_sequences)
    for domain, bigrams in domain_bigram_model.items():
        print(f"    → {domain}: {len(bigrams)} words")

    print("  Building domain trigram model...")
    domain_trigram_model = build_domain_trigram_model(all_sequences)
    for domain, trigrams in domain_trigram_model.items():
        print(f"    → {domain}: {len(trigrams)} contexts")

    # Merge models
    print("\n  Merging models...")
    merged_bigrams = merge_bigram_models(domain_bigram_model)
    print(f"    → Merged bigrams: {len(merged_bigrams)} words")

    merged_trigrams = merge_trigram_models(domain_trigram_model)
    print(f"    → Merged trigrams: {len(merged_trigrams)} contexts")

    print("  Building 4-gram model...")
    fourgram_model = build_fourgram_model(all_sequences)
    print(f"    → {len(fourgram_model)} 4-gram contexts")

    print("  Computing word frequencies...")
    word_freq = compute_word_frequencies(all_sequences)
    print(f"    → {len(word_freq)} unique words")

    print("\n🎯 Building enhanced homophone disambiguation contexts...")
    homophone_contexts = build_enhanced_homophone_contexts(
        domain_bigram_model, merged_bigrams
    )
    print(f"    → {len(homophone_contexts)} homophones analyzed")

    # Combine into single model
    context_model = {
        "bigrams": merged_bigrams,
        "trigrams": merged_trigrams,
        "fourgrams": fourgram_model,
        "word_freq": word_freq,
        "homophone_contexts": homophone_contexts,
        "domain_bigrams": domain_bigram_model,
        "domain_trigrams": domain_trigram_model,
        "version": "4.0",
        "features": [
            "domain_aware",
            "enhanced_homophones",
            "4grams",
        ],
        "domains": ["dharma", "colloquial", "formal", "number", "unknown"],
    }

    # Save model
    output_path = LOTSAWA_CORE_DIR / "context_model.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(context_model, f, ensure_ascii=False, separators=(',', ':'))

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"\n✅ Saved to {output_path}")
    print(f"   Size: {size_mb:.2f} MB")

    # Show samples
    print("\n📝 Sample bigrams by domain:")
    for domain in ["dharma", "colloquial", "number"]:
        if domain in domain_bigram_model:
            samples = list(domain_bigram_model[domain].items())[:2]
            print(f"\n  {domain.upper()}:")
            for word, followers in samples:
                top = list(followers.items())[:3]
                print(f"    {word} → {', '.join(f'{w}({c})' for w, c in top)}")

    print("\n🎯 Homophone context examples:")
    for phonetic in ["chu", "nga", "choe"]:
        if phonetic in homophone_contexts:
            print(f"\n  '{phonetic}':")
            for tibetan, ctx in homophone_contexts[phonetic].items():
                prec = ctx['preceding'][:2]
                prec_str = ', '.join(f"{p[0]}({p[1]})" for p in prec) if prec else "none"
                print(f"    {tibetan}: preceded by [{prec_str}]")

    print("\n✅ DONE!")


if __name__ == "__main__":
    main()
