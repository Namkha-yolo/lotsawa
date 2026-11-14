#!/usr/bin/env python3
"""
Build SQLite database from all available Tibetan data sources.

Sources:
1. phonetic_dictionary.json - 98K+ phonetic → Tibetan mappings
2. bo-pos/entries.txt - Tibetan vocabulary with frequency
3. tibetan-verbs-database/db.csv - Verb conjugations
4. tibetan-dictionary/84000 - Buddhist terminology
5. Heart of Tibetan Language - Common phrases
"""

import sqlite3
import json
import csv
import os
import re
from collections import defaultdict
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
DATASETS_DIR = PROJECT_DIR / "datasets"
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"
OUTPUT_DB = LOTSAWA_CORE_DIR / "dictionary.sqlite"

def create_schema(conn):
    """Create database schema"""
    cursor = conn.cursor()

    # Words table - core vocabulary
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS words (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tibetan TEXT NOT NULL,
            phonetic TEXT,
            wylie TEXT,
            frequency INTEGER DEFAULT 0,
            pos_tag TEXT,
            source TEXT,
            UNIQUE(tibetan, phonetic)
        )
    """)

    # Create index on phonetic for fast prefix matching
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_words_phonetic ON words(phonetic)
    """)

    # Create index on tibetan
    cursor.execute("""
        CREATE INDEX IF NOT EXISTS idx_words_tibetan ON words(tibetan)
    """)

    # Definitions table - English translations
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS definitions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            word_id INTEGER,
            english TEXT NOT NULL,
            category TEXT,
            source TEXT,
            FOREIGN KEY(word_id) REFERENCES words(id)
        )
    """)

    # Verbs table - conjugations
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS verbs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            present TEXT,
            past TEXT,
            future TEXT,
            imperative TEXT,
            source TEXT
        )
    """)

    # Prefix index table - for Trie-like lookup
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS phonetic_prefixes (
            prefix TEXT PRIMARY KEY,
            word_ids TEXT  -- JSON array of word IDs
        )
    """)

    conn.commit()
    print("✅ Schema created")

def load_phonetic_dictionary(conn):
    """Load the main phonetic dictionary from JSON"""
    json_path = LOTSAWA_CORE_DIR / "phonetic_dictionary.json"

    if not json_path.exists():
        print(f"⚠️  {json_path} not found, skipping")
        return 0

    print(f"📥 Loading {json_path}...")

    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    cursor = conn.cursor()
    count = 0

    for phonetic, tibetan_list in data.items():
        for tibetan in tibetan_list:
            try:
                cursor.execute("""
                    INSERT OR IGNORE INTO words (tibetan, phonetic, frequency, source)
                    VALUES (?, ?, 1, 'huggingface')
                """, (tibetan.strip(), phonetic.strip()))
                count += 1
            except Exception as e:
                pass  # Skip duplicates silently

    conn.commit()
    print(f"✅ Loaded {count} entries from phonetic_dictionary.json")
    return count

def load_bo_pos_entries(conn):
    """Load vocabulary from bo-pos entries.txt"""
    entries_path = DATASETS_DIR / "bo-pos" / "models" / "ngram" / "entries.txt"

    if not entries_path.exists():
        print(f"⚠️  {entries_path} not found, skipping")
        return 0

    print(f"📥 Loading {entries_path}...")

    cursor = conn.cursor()
    count = 0
    freq_count = defaultdict(int)

    # First pass: count frequencies
    with open(entries_path, 'r', encoding='utf-8') as f:
        for line in f:
            tibetan = line.strip()
            if tibetan:
                freq_count[tibetan] += 1

    # Second pass: insert with frequencies
    for tibetan, freq in freq_count.items():
        try:
            # Update frequency if exists, otherwise insert
            cursor.execute("""
                UPDATE words SET frequency = frequency + ?
                WHERE tibetan = ?
            """, (freq, tibetan))

            if cursor.rowcount == 0:
                cursor.execute("""
                    INSERT OR IGNORE INTO words (tibetan, frequency, source)
                    VALUES (?, ?, 'bo-pos')
                """, (tibetan, freq))
            count += 1
        except Exception as e:
            pass

    conn.commit()
    print(f"✅ Loaded {count} entries from bo-pos with frequencies")
    return count

def load_verb_database(conn):
    """Load verb conjugations from tibetan-verbs-database"""
    csv_path = DATASETS_DIR / "tibetan-verbs-database" / "db.csv"

    if not csv_path.exists():
        print(f"⚠️  {csv_path} not found, skipping")
        return 0

    print(f"📥 Loading {csv_path}...")

    cursor = conn.cursor()
    count = 0

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            present = row.get('ད་ལྟ', '').strip()
            past = row.get('འདས་པ', '').strip()
            future = row.get('མ་འོངས', '').strip()
            imperative = row.get('སྐུལ་ཚིག', '').strip()

            # Get source info
            sources = []
            for src in ['TDC', 'PH', 'GT', 'KN']:
                if row.get(src):
                    sources.append(src)
            source = ','.join(sources) if sources else None

            if present or past or future:
                try:
                    cursor.execute("""
                        INSERT INTO verbs (present, past, future, imperative, source)
                        VALUES (?, ?, ?, ?, ?)
                    """, (present, past, future, imperative, source))
                    count += 1

                    # Also add each form to words table
                    for form in [present, past, future, imperative]:
                        if form and '༼' not in form:  # Skip entries with annotations
                            cursor.execute("""
                                INSERT OR IGNORE INTO words (tibetan, pos_tag, source)
                                VALUES (?, 'VERB', 'verbs-db')
                            """, (form,))
                except Exception as e:
                    pass

    conn.commit()
    print(f"✅ Loaded {count} verb conjugations")
    return count

def load_84000_dictionary(conn):
    """Load 84000 Buddhist terminology"""
    dict_path = DATASETS_DIR / "tibetan-dictionary" / "_input" / "dictionaries" / "conversion" / "84000" / "out" / "Tib_EnSkt" / "43-84000Dict"

    if not dict_path.exists():
        print(f"⚠️  {dict_path} not found, skipping")
        return 0

    print(f"📥 Loading {dict_path}...")

    cursor = conn.cursor()
    count = 0

    with open(dict_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if '|' not in line:
                continue

            parts = line.split('|', 1)
            if len(parts) != 2:
                continue

            tibetan = parts[0].strip()
            definition_raw = parts[1].strip()

            # Parse category and definition
            # Format: <category> definition
            category = None
            definition = definition_raw

            if definition_raw.startswith('<') and '>' in definition_raw:
                end = definition_raw.index('>')
                category = definition_raw[1:end]
                definition = definition_raw[end+1:].strip()

            if not tibetan or not definition:
                continue

            try:
                # Insert word
                cursor.execute("""
                    INSERT OR IGNORE INTO words (tibetan, source)
                    VALUES (?, '84000')
                """, (tibetan,))

                # Get word_id
                cursor.execute("SELECT id FROM words WHERE tibetan = ?", (tibetan,))
                result = cursor.fetchone()
                if result:
                    word_id = result[0]

                    # Insert definition
                    cursor.execute("""
                        INSERT INTO definitions (word_id, english, category, source)
                        VALUES (?, ?, ?, '84000')
                    """, (word_id, definition, category))

                count += 1
            except Exception as e:
                pass

    conn.commit()
    print(f"✅ Loaded {count} entries from 84000 dictionary")
    return count

def extract_tibetan_from_hotl(text):
    """Extract Tibetan text from Heart of Tibetan Language format {bod yig/}"""
    matches = re.findall(r'\{([^}]+)\}', text)
    # Clean up: remove trailing / and spaces
    return [m.rstrip('/').strip() for m in matches if m.strip()]

def load_heart_of_tibetan_language(conn):
    """Load Heart of Tibetan Language vocabulary"""
    hotl_dir = DATASETS_DIR / "tibetan-dictionary" / "_input" / "dictionaries" / "conversion" / "Heart_of_Tibetan_Language"

    if not hotl_dir.exists():
        print(f"⚠️  {hotl_dir} not found, skipping")
        return 0

    print(f"📥 Loading Heart of Tibetan Language...")

    cursor = conn.cursor()
    count = 0

    for csv_file in hotl_dir.glob("*.csv"):
        with open(csv_file, 'r', encoding='utf-8') as f:
            for line in f:
                parts = line.split('|')
                if len(parts) < 2:
                    continue

                english_key = parts[0].strip()
                content = '|'.join(parts[1:])

                # Extract Tibetan from content
                tibetan_list = extract_tibetan_from_hotl(content)

                for tibetan in tibetan_list:
                    if not tibetan:
                        continue

                    try:
                        cursor.execute("""
                            INSERT OR IGNORE INTO words (tibetan, source)
                            VALUES (?, 'hotl')
                        """, (tibetan,))

                        # Get word_id and add definition
                        cursor.execute("SELECT id FROM words WHERE tibetan = ?", (tibetan,))
                        result = cursor.fetchone()
                        if result and english_key:
                            cursor.execute("""
                                INSERT OR IGNORE INTO definitions (word_id, english, source)
                                VALUES (?, ?, 'hotl')
                            """, (result[0], english_key))

                        count += 1
                    except Exception as e:
                        pass

    conn.commit()
    print(f"✅ Loaded {count} entries from Heart of Tibetan Language")
    return count

def build_prefix_index(conn):
    """Build prefix index for fast Trie-like lookup"""
    print("🔨 Building prefix index...")

    cursor = conn.cursor()

    # Get all phonetic entries
    cursor.execute("SELECT id, phonetic FROM words WHERE phonetic IS NOT NULL")
    rows = cursor.fetchall()

    prefix_map = defaultdict(list)

    for word_id, phonetic in rows:
        if not phonetic:
            continue

        # Generate all prefixes (1 to len)
        for i in range(1, min(len(phonetic) + 1, 20)):  # Limit prefix length
            prefix = phonetic[:i].lower()
            prefix_map[prefix].append(word_id)

    # Insert prefix index
    for prefix, word_ids in prefix_map.items():
        try:
            cursor.execute("""
                INSERT OR REPLACE INTO phonetic_prefixes (prefix, word_ids)
                VALUES (?, ?)
            """, (prefix, json.dumps(word_ids[:100])))  # Limit to 100 IDs per prefix
        except Exception as e:
            pass

    conn.commit()
    print(f"✅ Built prefix index with {len(prefix_map)} prefixes")

def print_stats(conn):
    """Print database statistics"""
    cursor = conn.cursor()

    print("\n" + "="*60)
    print("📊 DATABASE STATISTICS")
    print("="*60)

    cursor.execute("SELECT COUNT(*) FROM words")
    print(f"   Total words: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM words WHERE phonetic IS NOT NULL")
    print(f"   Words with phonetic: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM definitions")
    print(f"   Definitions: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM verbs")
    print(f"   Verb conjugations: {cursor.fetchone()[0]:,}")

    cursor.execute("SELECT COUNT(*) FROM phonetic_prefixes")
    print(f"   Prefix index entries: {cursor.fetchone()[0]:,}")

    # Source breakdown
    print("\n   By source:")
    cursor.execute("SELECT source, COUNT(*) FROM words GROUP BY source ORDER BY COUNT(*) DESC")
    for source, count in cursor.fetchall():
        print(f"     - {source or 'unknown'}: {count:,}")

    print("="*60)

def main():
    print("="*60)
    print("ལོ་ཙཱ་བ། Lotsawa Dictionary Builder")
    print("="*60)
    print()

    # Remove old database
    if OUTPUT_DB.exists():
        os.remove(OUTPUT_DB)
        print(f"🗑️  Removed old {OUTPUT_DB}")

    # Create new database
    conn = sqlite3.connect(OUTPUT_DB)

    try:
        # Create schema
        create_schema(conn)

        # Load data sources
        load_phonetic_dictionary(conn)
        load_bo_pos_entries(conn)
        load_verb_database(conn)
        load_84000_dictionary(conn)
        load_heart_of_tibetan_language(conn)

        # Build prefix index
        build_prefix_index(conn)

        # Print stats
        print_stats(conn)

        print(f"\n✅ Database saved to: {OUTPUT_DB}")
        print(f"   Size: {OUTPUT_DB.stat().st_size / 1024 / 1024:.2f} MB")

    finally:
        conn.close()

    print("\n✅ DONE!")

if __name__ == "__main__":
    main()
