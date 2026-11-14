#!/usr/bin/env python3
"""Validate phonetic-to-Tibetan mappings in the Lotsawa dictionary.

Flags entries where the stored phonetic key doesn't plausibly match
the Tibetan value, using edit-distance heuristics.
"""

import argparse
import json
import os
import sys

BASE = os.path.join(os.path.dirname(__file__), "..", "LotsawaCore", "Sources", "LotsawaCore")


def levenshtein(s1: str, s2: str) -> int:
    """Compute Levenshtein edit distance between two strings."""
    if len(s1) < len(s2):
        return levenshtein(s2, s1)
    if len(s2) == 0:
        return len(s1)
    prev = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        curr = [i + 1]
        for j, c2 in enumerate(s2):
            cost = 0 if c1 == c2 else 1
            curr.append(min(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost))
        prev = curr
    return prev[-1]


# Simple Tibetan-to-approximate-phonetic mapping for validation
# Maps Unicode code points to rough phonetic equivalents
TIBETAN_CONSONANTS = {
    "\u0F40": "ka", "\u0F41": "kha", "\u0F42": "ga", "\u0F44": "nga",
    "\u0F45": "ca", "\u0F46": "cha", "\u0F47": "ja", "\u0F49": "nya",
    "\u0F4F": "ta", "\u0F50": "tha", "\u0F51": "da", "\u0F53": "na",
    "\u0F54": "pa", "\u0F55": "pha", "\u0F56": "ba", "\u0F58": "ma",
    "\u0F59": "tsa", "\u0F5A": "tsha", "\u0F5B": "dza",
    "\u0F5D": "wa", "\u0F5E": "zha", "\u0F5F": "za",
    "\u0F61": "ya", "\u0F62": "ra", "\u0F63": "la",
    "\u0F64": "sha", "\u0F66": "sa", "\u0F67": "ha",
    "\u0F68": "a",
}

TIBETAN_VOWELS = {
    "\u0F72": "i", "\u0F74": "u", "\u0F7A": "e", "\u0F7C": "o",
}


def tibetan_to_approx_phonetic(tibetan: str) -> str:
    """Convert Tibetan Unicode to a rough phonetic approximation."""
    result = []
    for ch in tibetan:
        if ch in TIBETAN_CONSONANTS:
            result.append(TIBETAN_CONSONANTS[ch])
        elif ch in TIBETAN_VOWELS:
            result.append(TIBETAN_VOWELS[ch])
        elif ch == "\u0F0B":  # tsheg
            result.append(" ")
        # Skip subjoined forms, other marks
    return "".join(result).strip()


def validate_entry(phonetic: str, tibetan: str, threshold: int = 5) -> bool:
    """Return True if the entry seems plausible, False if it should be flagged."""
    # Skip multi-word phrases (harder to validate)
    if " " in phonetic:
        return True

    approx = tibetan_to_approx_phonetic(tibetan)
    if not approx:
        return True  # Can't validate, keep it

    # Normalize for comparison
    phonetic_clean = phonetic.lower().replace("-", "").replace("'", "")
    approx_clean = approx.lower().replace(" ", "")

    # If they share a common prefix of length >= 2, likely valid
    common = 0
    for a, b in zip(phonetic_clean, approx_clean):
        if a == b:
            common += 1
        else:
            break
    if common >= 2:
        return True

    # Use edit distance
    dist = levenshtein(phonetic_clean, approx_clean)

    # Allow more distance for longer words
    max_len = max(len(phonetic_clean), len(approx_clean))
    if max_len == 0:
        return True

    ratio = dist / max_len
    return ratio < 0.8  # Flag if more than 80% different


def validate_json_file(path: str, threshold: int = 5, dry_run: bool = True):
    """Validate a phonetic JSON file and optionally remove bad entries."""
    with open(path) as f:
        data = json.load(f)

    flagged = []
    clean = {}
    total = 0

    for phonetic, entries in data.items():
        if isinstance(entries, list):
            if entries and isinstance(entries[0], dict):
                # phonetic_lookup.json format: [{t: ..., f: ...}, ...]
                valid = []
                for entry in entries:
                    total += 1
                    tib = entry.get("t", "")
                    if validate_entry(phonetic, tib, threshold):
                        valid.append(entry)
                    else:
                        flagged.append((phonetic, tib))
                if valid:
                    clean[phonetic] = valid
            else:
                # phonetic_dictionary.json format: [tibetan_string, ...]
                valid = []
                for tib in entries:
                    total += 1
                    if validate_entry(phonetic, tib, threshold):
                        valid.append(tib)
                    else:
                        flagged.append((phonetic, tib))
                if valid:
                    clean[phonetic] = valid
        else:
            clean[phonetic] = entries

    print(f"Validated {total} entries in {os.path.basename(path)}")
    print(f"  Flagged: {len(flagged)} entries")
    print(f"  Kept:    {total - len(flagged)} entries")

    if flagged:
        print("\nFlagged entries (sample):")
        for phonetic, tibetan in flagged[:20]:
            approx = tibetan_to_approx_phonetic(tibetan)
            print(f"  {phonetic:20s} -> {tibetan:15s} (approx: {approx})")
        if len(flagged) > 20:
            print(f"  ... and {len(flagged) - 20} more")

    if not dry_run:
        out_path = path
        with open(out_path, "w") as f:
            json.dump(clean, f, ensure_ascii=False, indent=2)
        print(f"\nCleaned file written to {out_path}")

    return flagged


def main():
    parser = argparse.ArgumentParser(description="Validate Lotsawa phonetic data")
    parser.add_argument("--dry-run", action="store_true", default=True,
                        help="Only report issues, don't modify files (default)")
    parser.add_argument("--apply", action="store_true",
                        help="Apply fixes (remove flagged entries)")
    parser.add_argument("--threshold", type=int, default=5,
                        help="Edit distance threshold for flagging")
    args = parser.parse_args()

    dry_run = not args.apply

    lookup_path = os.path.join(BASE, "phonetic_lookup.json")
    dict_path = os.path.join(BASE, "phonetic_dictionary.json")

    if os.path.exists(lookup_path):
        print(f"=== Validating {os.path.basename(lookup_path)} ===")
        validate_json_file(lookup_path, args.threshold, dry_run)
        print()

    if os.path.exists(dict_path):
        print(f"=== Validating {os.path.basename(dict_path)} ===")
        validate_json_file(dict_path, args.threshold, dry_run)


if __name__ == "__main__":
    main()
