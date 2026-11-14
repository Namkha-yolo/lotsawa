#!/usr/bin/env python3
"""
Download and process Tibetan phonetic dataset from Hugging Face
Creates a Swift dictionary file for PhoneticMapper

Dataset: billingsmoore/tibetan-phonetic-transliteration-dataset
Contains ~98,000 Tibetan ↔ Phonetic pairs
"""

import json
import os
from collections import defaultdict

def download_dataset():
    """Download dataset from Hugging Face"""
    try:
        from datasets import load_dataset
        print("📥 Downloading dataset from Hugging Face...")
        dataset = load_dataset("billingsmoore/tibetan-phonetic-transliteration-dataset")
        return dataset
    except ImportError:
        print("❌ datasets library not installed. Installing...")
        os.system("pip3 install datasets")
        from datasets import load_dataset
        print("📥 Downloading dataset from Hugging Face...")
        dataset = load_dataset("billingsmoore/tibetan-phonetic-transliteration-dataset")
        return dataset

def process_dataset(dataset):
    """Process dataset into phonetic → tibetan mapping"""
    print("⚙️  Processing dataset...")

    # Dictionary: phonetic -> [list of tibetan options]
    phonetic_to_tibetan = defaultdict(set)

    # Get column names - they contain actual data too
    columns = dataset['train'].column_names
    tibetan_col = columns[0]  # First column is Tibetan
    phonetic_col = columns[1]  # Second column is phonetic

    print(f"   Columns: {tibetan_col[:30]}... | {phonetic_col[:30]}...")

    # Process train split
    for item in dataset['train']:
        tibetan = item.get(tibetan_col, '').strip()
        phonetic = item.get(phonetic_col, '').strip().lower()

        if tibetan and phonetic:
            # Clean up phonetic - remove extra spaces, normalize
            phonetic_clean = ' '.join(phonetic.split())

            # Also add individual words for word-level lookup
            phonetic_to_tibetan[phonetic_clean].add(tibetan)

            # Split into words and add those too
            tibetan_words = tibetan.replace('།', ' ').replace('་', ' ').split()
            phonetic_words = phonetic_clean.split()

            # If same number of words, map them individually
            if len(tibetan_words) == len(phonetic_words):
                for tw, pw in zip(tibetan_words, phonetic_words):
                    if tw and pw:
                        phonetic_to_tibetan[pw].add(tw)

    print(f"✅ Processed {len(phonetic_to_tibetan)} unique phonetic entries")
    return phonetic_to_tibetan

def generate_swift_dict(phonetic_to_tibetan, output_path):
    """Generate Swift dictionary literal"""
    print("📝 Generating Swift dictionary...")

    lines = []
    lines.append("// PhoneticDictionary.swift")
    lines.append("// Auto-generated from Hugging Face dataset")
    lines.append("// DO NOT EDIT MANUALLY")
    lines.append("")
    lines.append("import Foundation")
    lines.append("")
    lines.append("/// Phonetic to Tibetan dictionary (~98K entries)")
    lines.append("public let phoneticDictionary: [String: [String]] = [")

    # Sort by phonetic for consistent output
    sorted_entries = sorted(phonetic_to_tibetan.items())

    for i, (phonetic, tibetan_set) in enumerate(sorted_entries):
        # Escape any special characters
        phonetic_escaped = phonetic.replace('\\', '\\\\').replace('"', '\\"')
        tibetan_list = sorted(tibetan_set)  # Sort for consistency
        tibetan_str = ', '.join(f'"{t}"' for t in tibetan_list)

        comma = "," if i < len(sorted_entries) - 1 else ""
        lines.append(f'    "{phonetic_escaped}": [{tibetan_str}]{comma}')

    lines.append("]")
    lines.append("")

    # Write to file
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))

    print(f"✅ Generated {output_path}")
    print(f"   {len(sorted_entries)} entries")

def generate_json(phonetic_to_tibetan, output_path):
    """Generate JSON file for easier loading"""
    print("📝 Generating JSON dictionary...")

    # Convert sets to lists for JSON serialization
    data = {k: sorted(list(v)) for k, v in phonetic_to_tibetan.items()}

    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"✅ Generated {output_path}")

def main():
    print("=" * 60)
    print("ལོ་ཙཱ་བ། Lotsawa Dataset Processor")
    print("=" * 60)
    print()

    # Download
    dataset = download_dataset()

    # Process
    phonetic_to_tibetan = process_dataset(dataset)

    # Output paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(script_dir)

    swift_path = os.path.join(parent_dir, "LotsawaCore", "Sources", "LotsawaCore", "PhoneticDictionary.swift")
    json_path = os.path.join(parent_dir, "LotsawaCore", "Sources", "LotsawaCore", "phonetic_dictionary.json")

    # Generate outputs
    generate_swift_dict(phonetic_to_tibetan, swift_path)
    generate_json(phonetic_to_tibetan, json_path)

    print()
    print("=" * 60)
    print("✅ DONE!")
    print(f"   Swift: {swift_path}")
    print(f"   JSON:  {json_path}")
    print("=" * 60)

if __name__ == "__main__":
    main()
