#!/usr/bin/env python3
"""
Rebuild phonetic_lookup.json from the expanded phonetic_dictionary.json.

The lookup includes:
- Both spaced and non-spaced versions of phonetics
- Frequency data from word_frequency.json
- Top 5 Tibetan options per phonetic entry
"""

import json
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"


def load_word_frequencies() -> dict:
    """Load word frequency data."""
    path = LOTSAWA_CORE_DIR / "word_frequency.json"
    if path.exists():
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}


def get_frequency(tibetan: str, freq_data: dict) -> int:
    """Get frequency for a Tibetan word."""
    # Try exact match
    if tibetan in freq_data:
        return freq_data[tibetan]

    # Try first syllable match
    first_syl = tibetan.split('་')[0] if '་' in tibetan else tibetan
    if first_syl in freq_data:
        return freq_data[first_syl] // 2  # Half weight for partial match

    return 1  # Default frequency


def main():
    print("=" * 60)
    print("ལོ་ཙཱ་བ། Rebuilding Phonetic Lookup Index")
    print("=" * 60)

    # Load phonetic dictionary
    print("\n📖 Loading phonetic dictionary...")
    dict_path = LOTSAWA_CORE_DIR / "phonetic_dictionary.json"
    with open(dict_path, 'r', encoding='utf-8') as f:
        phonetic_dict = json.load(f)
    print(f"  Loaded {len(phonetic_dict)} phonetic entries")

    # Load word frequencies
    print("\n📊 Loading word frequencies...")
    freq_data = load_word_frequencies()
    print(f"  Loaded {len(freq_data)} frequency entries")

    # Build lookup index
    print("\n🔨 Building lookup index...")
    lookup = {}
    entry_count = 0

    for phonetic, tibetan_list in phonetic_dict.items():
        # Get entries with frequencies
        entries = []
        for tibetan in tibetan_list:
            freq = get_frequency(tibetan, freq_data)
            entries.append({"t": tibetan, "f": freq})

        # Sort by frequency (descending)
        entries.sort(key=lambda x: -x["f"])

        # Keep top 5
        entries = entries[:5]

        if entries:
            # Add non-spaced version
            non_spaced = phonetic.replace(' ', '')
            lookup[non_spaced] = entries

            # Add spaced version if different
            if non_spaced != phonetic:
                lookup[phonetic] = entries

            entry_count += 1

    print(f"  Created {len(lookup)} lookup entries")

    # Save lookup
    output_path = LOTSAWA_CORE_DIR / "phonetic_lookup.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(lookup, f, ensure_ascii=False, separators=(',', ':'))

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"\n✅ Saved to {output_path}")
    print(f"   Size: {size_mb:.2f} MB")

    # Show some stats
    print("\n📊 Statistics:")
    print(f"   Total phonetic entries: {entry_count:,}")
    print(f"   Total lookup keys: {len(lookup):,}")

    # Show sample entries
    print("\n📝 Sample entries:")
    samples = ['tashi', 'sangye', 'cho', 'lama', 'sem', 'dak', 'nga', 'chu']
    for sample in samples:
        if sample in lookup:
            entries = lookup[sample]
            tibetan_list = [e["t"] for e in entries[:3]]
            print(f"  {sample} → {', '.join(tibetan_list)}")

    print("\n✅ Lookup rebuild complete!")


if __name__ == "__main__":
    main()
