#!/usr/bin/env python3
"""
Optimize the dictionary database for keyboard extension.
- Remove prefix index (use Swift Trie instead)
- Vacuum database
- Create a minimal version with just phonetic lookups
"""

import sqlite3
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"
INPUT_DB = LOTSAWA_CORE_DIR / "dictionary.sqlite"
OUTPUT_DB = LOTSAWA_CORE_DIR / "dictionary_optimized.sqlite"

def optimize():
    print("📦 Optimizing database...")

    # Connect to input
    conn = sqlite3.connect(INPUT_DB)
    cursor = conn.cursor()

    # Remove prefix index table (we'll use Swift Trie)
    cursor.execute("DROP TABLE IF EXISTS phonetic_prefixes")

    # Vacuum to reclaim space
    conn.execute("VACUUM")
    conn.commit()

    # Get new size
    cursor.execute("SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()")

    print(f"✅ Removed prefix index table")
    print(f"   New size: {INPUT_DB.stat().st_size / 1024 / 1024:.2f} MB")

    conn.close()

def create_minimal_phonetic_db():
    """Create a minimal JSON file for phonetic lookups only"""
    print("\n📦 Creating minimal phonetic lookup file...")

    conn = sqlite3.connect(INPUT_DB)
    cursor = conn.cursor()

    # Get all phonetic → tibetan mappings with frequencies
    cursor.execute("""
        SELECT phonetic, tibetan, frequency
        FROM words
        WHERE phonetic IS NOT NULL
        ORDER BY frequency DESC
    """)

    # Build dictionary: phonetic → [(tibetan, freq), ...]
    phonetic_dict = {}
    for phonetic, tibetan, freq in cursor.fetchall():
        if phonetic not in phonetic_dict:
            phonetic_dict[phonetic] = []
        phonetic_dict[phonetic].append({
            "t": tibetan,
            "f": freq or 0
        })

    # Sort by frequency within each phonetic entry
    for key in phonetic_dict:
        phonetic_dict[key].sort(key=lambda x: -x["f"])
        # Keep top 5 for each phonetic
        phonetic_dict[key] = phonetic_dict[key][:5]

    # Save as JSON
    output_path = LOTSAWA_CORE_DIR / "phonetic_lookup.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(phonetic_dict, f, ensure_ascii=False, separators=(',', ':'))

    print(f"✅ Created {output_path}")
    print(f"   Entries: {len(phonetic_dict):,}")
    print(f"   Size: {output_path.stat().st_size / 1024 / 1024:.2f} MB")

    conn.close()
    return output_path

def print_stats():
    """Print optimized database stats"""
    conn = sqlite3.connect(INPUT_DB)
    cursor = conn.cursor()

    print("\n📊 OPTIMIZED DATABASE STATISTICS")
    print("="*50)

    cursor.execute("SELECT COUNT(*) FROM words")
    print(f"   Words: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM words WHERE phonetic IS NOT NULL")
    print(f"   With phonetic: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM definitions")
    print(f"   Definitions: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM verbs")
    print(f"   Verbs: {cursor.fetchone()[0]:,}")

    # Top phonetic entries by frequency
    print("\n   Top entries by frequency:")
    cursor.execute("""
        SELECT phonetic, tibetan, frequency
        FROM words
        WHERE phonetic IS NOT NULL AND frequency > 0
        ORDER BY frequency DESC
        LIMIT 10
    """)
    for phonetic, tibetan, freq in cursor.fetchall():
        print(f"     {phonetic:20} → {tibetan:20} (freq: {freq})")

    print("="*50)
    conn.close()

def main():
    print("="*60)
    print("ལོ་ཙཱ་བ། Database Optimizer")
    print("="*60)

    optimize()
    create_minimal_phonetic_db()
    print_stats()

    print("\n✅ DONE!")

if __name__ == "__main__":
    main()
