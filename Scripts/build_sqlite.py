#!/usr/bin/env python3
"""Build lotsawa.db SQLite database from JSON dictionary files."""

import json
import os
import sqlite3
import sys

BASE = os.path.join(os.path.dirname(__file__), "..", "LotsawaCore", "Sources", "LotsawaCore")
DB_PATH = os.path.join(BASE, "lotsawa.db")


def load_json(name):
    path = os.path.join(BASE, name)
    print(f"Loading {name} ...", end=" ", flush=True)
    with open(path) as f:
        data = json.load(f)
    print("done")
    return data


def main():
    # Remove old DB if present
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)

    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA journal_mode=DELETE")
    conn.execute("PRAGMA synchronous=OFF")
    cur = conn.cursor()

    # --- phonetic_entries ---
    cur.execute("""
        CREATE TABLE phonetic_entries (
            phonetic TEXT NOT NULL,
            tibetan  TEXT NOT NULL,
            frequency INTEGER NOT NULL DEFAULT 1
        )
    """)

    # Merge phonetic_lookup.json and phonetic_dictionary.json
    # phonetic_lookup has {phonetic: [{t, f}, ...]}
    # phonetic_dictionary has {phonetic: [tibetan_string, ...]}
    # Deduplicate by (phonetic, tibetan), keep higher frequency.

    merged = {}  # (phonetic, tibetan) -> frequency

    lookup = load_json("phonetic_lookup.json")
    for phonetic, entries in lookup.items():
        for entry in entries:
            key = (phonetic, entry["t"])
            freq = entry.get("f", 1)
            if key not in merged or freq > merged[key]:
                merged[key] = freq

    dictionary = load_json("phonetic_dictionary.json")
    for phonetic, tibetan_list in dictionary.items():
        for tib in tibetan_list:
            key = (phonetic, tib)
            if key not in merged:
                merged[key] = 1

    # --- Validate entries: remove implausible phonetic-Tibetan pairs ---
    from validate_phonetic_data import validate_entry
    pre_count = len(merged)
    merged = {k: v for k, v in merged.items() if validate_entry(k[0], k[1])}
    removed = pre_count - len(merged)
    print(f"Validation: removed {removed} implausible entries ({pre_count} -> {len(merged)})")

    print(f"Inserting {len(merged)} phonetic_entries ...", end=" ", flush=True)
    cur.executemany(
        "INSERT INTO phonetic_entries (phonetic, tibetan, frequency) VALUES (?, ?, ?)",
        [(k[0], k[1], v) for k, v in merged.items()],
    )
    cur.execute("CREATE INDEX idx_phonetic ON phonetic_entries (phonetic)")
    print("done")

    del lookup, dictionary, merged

    # --- context_model ---
    context = load_json("context_model.json")

    # bigrams
    cur.execute("""
        CREATE TABLE bigrams (
            word1 TEXT NOT NULL,
            word2 TEXT NOT NULL,
            count INTEGER NOT NULL
        )
    """)
    rows = []
    for w1, nexts in context["bigrams"].items():
        for w2, cnt in nexts.items():
            rows.append((w1, w2, cnt))
    print(f"Inserting {len(rows)} bigrams ...", end=" ", flush=True)
    cur.executemany("INSERT INTO bigrams (word1, word2, count) VALUES (?, ?, ?)", rows)
    cur.execute("CREATE INDEX idx_bigrams_word1 ON bigrams (word1)")
    print("done")

    # trigrams
    cur.execute("""
        CREATE TABLE trigrams (
            key  TEXT NOT NULL,
            word TEXT NOT NULL,
            count INTEGER NOT NULL
        )
    """)
    rows = []
    for key, words in context["trigrams"].items():
        for w, cnt in words.items():
            rows.append((key, w, cnt))
    print(f"Inserting {len(rows)} trigrams ...", end=" ", flush=True)
    cur.executemany("INSERT INTO trigrams (key, word, count) VALUES (?, ?, ?)", rows)
    cur.execute("CREATE INDEX idx_trigrams_key ON trigrams (key)")
    print("done")

    # fourgrams
    cur.execute("""
        CREATE TABLE fourgrams (
            key  TEXT NOT NULL,
            word TEXT NOT NULL,
            count INTEGER NOT NULL
        )
    """)
    rows = []
    for key, words in context["fourgrams"].items():
        for w, cnt in words.items():
            rows.append((key, w, cnt))
    print(f"Inserting {len(rows)} fourgrams ...", end=" ", flush=True)
    cur.executemany("INSERT INTO fourgrams (key, word, count) VALUES (?, ?, ?)", rows)
    cur.execute("CREATE INDEX idx_fourgrams_key ON fourgrams (key)")
    print("done")

    # word_freq (from context_model's word_freq section)
    cur.execute("""
        CREATE TABLE word_freq (
            word TEXT PRIMARY KEY,
            freq INTEGER NOT NULL
        )
    """)
    wf_rows = [(w, f) for w, f in context["word_freq"].items()]
    print(f"Inserting {len(wf_rows)} word_freq ...", end=" ", flush=True)
    cur.executemany("INSERT INTO word_freq (word, freq) VALUES (?, ?)", wf_rows)
    print("done")

    del context

    # --- reverse_lookup: Tibetan syllable → shortest phonetic key ---
    cur.execute("""
        CREATE TABLE reverse_lookup (
            tibetan  TEXT PRIMARY KEY,
            phonetic TEXT NOT NULL
        )
    """)

    # Build from phonetic_entries: for each Tibetan syllable, keep the
    # shortest single-word phonetic key (skip multi-word phrases).
    print("Building reverse_lookup ...", end=" ", flush=True)
    rows = cur.execute(
        "SELECT phonetic, tibetan FROM phonetic_entries"
    ).fetchall()

    reverse = {}  # tibetan_syllable -> shortest phonetic
    for phonetic, tibetan in rows:
        if " " in phonetic:
            continue  # skip multi-word phrases
        # Extract first syllable (before tsheg ་)
        syllable = tibetan.split("་")[0]
        if not syllable:
            continue
        if syllable not in reverse or len(phonetic) < len(reverse[syllable]):
            reverse[syllable] = phonetic

    cur.executemany(
        "INSERT OR IGNORE INTO reverse_lookup (tibetan, phonetic) VALUES (?, ?)",
        list(reverse.items()),
    )
    print(f"{len(reverse)} entries done")
    del reverse

    # --- phrases: multi-word phonetic → Tibetan phrase ---
    cur.execute("""
        CREATE TABLE phrases (
            phonetic TEXT NOT NULL,
            tibetan  TEXT NOT NULL
        )
    """)

    print("Building phrases table ...", end=" ", flush=True)
    phrase_rows = cur.execute(
        "SELECT phonetic, tibetan FROM phonetic_entries WHERE phonetic LIKE '% %'"
    ).fetchall()

    # Deduplicate: keep first (best) Tibetan for each phonetic phrase
    seen_phrases = {}
    deduped = []
    for phonetic, tibetan in phrase_rows:
        if phonetic not in seen_phrases:
            seen_phrases[phonetic] = tibetan
            deduped.append((phonetic, tibetan))

    cur.executemany(
        "INSERT INTO phrases (phonetic, tibetan) VALUES (?, ?)",
        deduped,
    )
    cur.execute("CREATE INDEX idx_phrases_phonetic ON phrases (phonetic)")
    print(f"{len(deduped)} entries done")
    del seen_phrases, deduped, phrase_rows

    # --- Derive phonetic_entries frequencies from word_freq ---
    # The source phonetic_lookup.json has all f=1. Enrich with word_freq data
    # by matching the first Tibetan syllable (before tsheg) to word_freq.word.
    print("Enriching phonetic_entries frequencies from word_freq ...", end=" ", flush=True)
    cur.execute("""
        UPDATE phonetic_entries SET frequency = (
            SELECT wf.freq FROM word_freq wf
            WHERE wf.word = SUBSTR(phonetic_entries.tibetan, 1,
                CASE
                    WHEN INSTR(phonetic_entries.tibetan, '་') > 0
                    THEN INSTR(phonetic_entries.tibetan, '་') - 1
                    ELSE LENGTH(phonetic_entries.tibetan)
                END
            )
        )
        WHERE EXISTS (
            SELECT 1 FROM word_freq wf
            WHERE wf.word = SUBSTR(phonetic_entries.tibetan, 1,
                CASE
                    WHEN INSTR(phonetic_entries.tibetan, '་') > 0
                    THEN INSTR(phonetic_entries.tibetan, '་') - 1
                    ELSE LENGTH(phonetic_entries.tibetan)
                END
            )
        )
    """)
    updated = cur.execute(
        "SELECT COUNT(*) FROM phonetic_entries WHERE frequency > 1"
    ).fetchone()[0]
    print(f"{updated} entries enriched")

    # Optimize database
    print("Running ANALYZE and VACUUM ...", end=" ", flush=True)
    conn.execute("ANALYZE")
    conn.commit()
    conn.execute("VACUUM")
    print("done")

    conn.close()

    size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
    print(f"\nDatabase created: {DB_PATH}")
    print(f"Size: {size_mb:.1f} MB")

    # Verify row counts
    conn = sqlite3.connect(DB_PATH)
    for table in ["phonetic_entries", "bigrams", "trigrams", "fourgrams", "word_freq",
                   "reverse_lookup", "phrases"]:
        count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"  {table}: {count} rows")
    conn.close()


if __name__ == "__main__":
    main()
