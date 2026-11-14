#!/usr/bin/env python3
"""
Expand the phonetic dictionary using bophono to generate romanizations
for words from various Tibetan lexicons.

This script:
1. Loads existing phonetic_dictionary.json
2. Loads Tibetan words from lexicon files (SOAS, MGD, entries.txt, verbs)
3. Uses bophono to generate phonetic romanizations
4. Merges new entries into the dictionary
5. Outputs expanded dictionary
"""

import json
import re
import csv
from collections import defaultdict
from pathlib import Path
from typing import Dict, Set, List, Tuple

try:
    import bophono
except ImportError:
    print("Error: bophono not installed. Run: pip install bophono")
    exit(1)

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"
DATASETS_DIR = PROJECT_DIR / "datasets"

# Initialize bophono converter
phonetic_converter = bophono.UnicodeToApi(schema='LKT')


def tibetan_to_phonetic(tibetan: str) -> str:
    """Convert Tibetan Unicode to phonetic romanization using bophono."""
    try:
        # Clean the Tibetan text
        tibetan = tibetan.strip()
        if not tibetan:
            return ""

        # Get phonetic using bophono
        phonetic = phonetic_converter.get_api(tibetan)

        # Post-process: normalize spacing and case
        phonetic = phonetic.lower().strip()

        # Replace dots with spaces (bophono uses dots between syllables)
        phonetic = phonetic.replace('.', ' ')

        # Normalize multiple spaces
        phonetic = ' '.join(phonetic.split())

        return phonetic
    except Exception as e:
        return ""


def extract_tibetan_words(text: str) -> List[str]:
    """Extract individual Tibetan words from text."""
    # Split by tsheg, shad, and whitespace
    syllables = re.split(r'[་།༔༑\s]+', text.strip())
    return [s.strip() for s in syllables if s.strip()]


def load_existing_dictionary() -> Dict[str, List[str]]:
    """Load the existing phonetic dictionary."""
    path = LOTSAWA_CORE_DIR / "phonetic_dictionary.json"
    if path.exists():
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}


def load_soas_lexicon() -> Set[str]:
    """Load Tibetan words from SOAS lexicon."""
    path = DATASETS_DIR / "bo-pos" / "rc" / "SOAS-lexicon.txt"
    words = set()

    if not path.exists():
        print(f"  Warning: {path} not found")
        return words

    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split('\t')
            if parts:
                tibetan = parts[0].strip()
                # Skip punctuation and numbers
                if tibetan and not tibetan.isdigit() and tibetan not in ['།', '༑']:
                    words.add(tibetan)

    return words


def load_mgd_lexicon() -> Set[str]:
    """Load Tibetan words from Monlam Grand Dictionary lexicon."""
    path = DATASETS_DIR / "bo-pos" / "rc" / "mgd-lexicon.txt"
    words = set()

    if not path.exists():
        print(f"  Warning: {path} not found")
        return words

    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            if ':' in line:
                tibetan = line.split(':')[0].strip()
                if tibetan:
                    words.add(tibetan)

    return words


def load_entries_txt() -> Set[str]:
    """Load Tibetan words from bo-pos entries.txt."""
    path = DATASETS_DIR / "bo-pos" / "models" / "ngram" / "entries.txt"
    words = set()

    if not path.exists():
        print(f"  Warning: {path} not found")
        return words

    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            tibetan = line.strip()
            if tibetan:
                words.add(tibetan)

    return words


def load_verbs_database() -> Set[str]:
    """Load Tibetan verbs from the verbs database."""
    path = DATASETS_DIR / "tibetan-verbs-database" / "db.csv"
    words = set()

    if not path.exists():
        print(f"  Warning: {path} not found")
        return words

    with open(path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        next(reader, None)  # Skip header
        for row in reader:
            for cell in row[:4]:  # First 4 columns are verb forms
                tibetan = cell.strip()
                # Remove annotations like ༼ད༽
                tibetan = re.sub(r'༼[^༽]+༽', '', tibetan)
                if tibetan:
                    words.add(tibetan)

    return words


def process_words(words: Set[str], existing_dict: Dict[str, List[str]]) -> Tuple[Dict[str, List[str]], int, int]:
    """
    Process words and add to dictionary.
    Returns (updated_dict, new_count, duplicate_count)
    """
    new_dict = defaultdict(list, {k: v.copy() for k, v in existing_dict.items()})
    new_count = 0
    duplicate_count = 0

    for tibetan in words:
        # Generate phonetic romanization
        phonetic = tibetan_to_phonetic(tibetan)

        if not phonetic:
            continue

        # Check if this mapping already exists
        if phonetic in new_dict:
            if tibetan not in new_dict[phonetic]:
                new_dict[phonetic].append(tibetan)
                new_count += 1
            else:
                duplicate_count += 1
        else:
            new_dict[phonetic] = [tibetan]
            new_count += 1

    return dict(new_dict), new_count, duplicate_count


def main():
    print("=" * 60)
    print("ལོ་ཙཱ་བ། Dictionary Expansion Tool")
    print("=" * 60)

    # Load existing dictionary
    print("\n📚 Loading existing dictionary...")
    existing_dict = load_existing_dictionary()
    existing_phonetic_count = len(existing_dict)
    existing_tibetan_count = sum(len(v) for v in existing_dict.values())
    print(f"  Existing: {existing_phonetic_count} phonetic entries → {existing_tibetan_count} Tibetan words")

    # Collect all Tibetan words from lexicons
    print("\n📖 Loading lexicon sources...")
    all_words = set()

    print("  Loading SOAS lexicon...")
    soas_words = load_soas_lexicon()
    print(f"    → {len(soas_words)} words")
    all_words.update(soas_words)

    print("  Loading MGD lexicon...")
    mgd_words = load_mgd_lexicon()
    print(f"    → {len(mgd_words)} words")
    all_words.update(mgd_words)

    print("  Loading entries.txt...")
    entries_words = load_entries_txt()
    print(f"    → {len(entries_words)} words")
    all_words.update(entries_words)

    print("  Loading verbs database...")
    verbs_words = load_verbs_database()
    print(f"    → {len(verbs_words)} words")
    all_words.update(verbs_words)

    print(f"\n📊 Total unique Tibetan words from lexicons: {len(all_words)}")

    # Generate phonetic mappings
    print("\n🔤 Generating phonetic romanizations with bophono...")
    updated_dict, new_count, dup_count = process_words(all_words, existing_dict)
    print(f"  New mappings added: {new_count}")
    print(f"  Duplicates skipped: {dup_count}")

    # Statistics
    final_phonetic_count = len(updated_dict)
    final_tibetan_count = sum(len(v) for v in updated_dict.values())

    print(f"\n📈 Dictionary growth:")
    print(f"  Phonetic entries: {existing_phonetic_count} → {final_phonetic_count} (+{final_phonetic_count - existing_phonetic_count})")
    print(f"  Tibetan mappings: {existing_tibetan_count} → {final_tibetan_count} (+{final_tibetan_count - existing_tibetan_count})")

    # Save updated dictionary
    output_path = LOTSAWA_CORE_DIR / "phonetic_dictionary.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(updated_dict, f, ensure_ascii=False, indent=2)

    size_mb = output_path.stat().st_size / (1024 * 1024)
    print(f"\n✅ Saved to {output_path}")
    print(f"   Size: {size_mb:.2f} MB")

    # Show some sample new entries
    print("\n📝 Sample new phonetic mappings:")
    sample_count = 0
    for phonetic, tibetan_list in updated_dict.items():
        if phonetic not in existing_dict:
            print(f"  {phonetic} → {tibetan_list[0]}")
            sample_count += 1
            if sample_count >= 10:
                break

    print("\n✅ Dictionary expansion complete!")


if __name__ == "__main__":
    main()
