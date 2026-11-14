#!/usr/bin/env python3
"""
Build comprehensive phonetic variation database for Tibetan.

Sources:
- THL Simplified Phonetic Transcription
- Wylie transliteration
- Dzongkha/Bhutanese variations
- Amdo/Kham dialect variations
- Common romanization variations
- Sumtak grammar rules for particles

This creates training data for ML-based phonetic similarity matching.
"""

import json
from pathlib import Path
from itertools import product
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

# =============================================================================
# CONSONANT VARIATIONS ACROSS SYSTEMS
# =============================================================================

# Base Tibetan consonants with all romanization variants
CONSONANT_VARIATIONS = {
    # Velars
    'ཀ': ['ka', 'k', 'ga'],  # Unaspirated - can sound like 'g' in some dialects
    'ཁ': ['kha', 'kh', 'ka'],  # Aspirated - some dialects drop aspiration
    'ག': ['ga', 'g', 'ka', 'kha'],  # Voiced - devoiced in some positions
    'ང': ['nga', 'ng'],

    # Palatals
    'ཅ': ['ca', 'cha', 'ja', 'ch', 'c'],  # THL uses 'ch' for both ཅ and ཆ
    'ཆ': ['cha', 'ch', 'ca'],
    'ཇ': ['ja', 'j', 'cha'],
    'ཉ': ['nya', 'ny', 'na'],

    # Dentals
    'ཏ': ['ta', 't', 'da'],
    'ཐ': ['tha', 'th', 'ta'],
    'ད': ['da', 'd', 'ta', 'tha'],
    'ན': ['na', 'n'],

    # Labials
    'པ': ['pa', 'p', 'ba'],
    'ཕ': ['pha', 'ph', 'pa'],
    'བ': ['ba', 'b', 'pa', 'wa'],  # བ can be 'wa' in some positions
    'མ': ['ma', 'm'],

    # Affricates
    'ཙ': ['tsa', 'ts', 'za', 'dza'],
    'ཚ': ['tsha', 'tsh', 'tsa'],
    'ཛ': ['dza', 'dz', 'za', 'tsa'],

    # Others
    'ཝ': ['wa', 'w', 'ba'],
    'ཞ': ['zha', 'zh', 'sha'],
    'ཟ': ['za', 'z', 'sa'],
    'འ': ['a', "'a", 'ah'],
    'ཡ': ['ya', 'y'],
    'ར': ['ra', 'r'],
    'ལ': ['la', 'l'],
    'ཤ': ['sha', 'sh', 'sa'],
    'ས': ['sa', 's'],
    'ཧ': ['ha', 'h'],
    'ཨ': ['a', 'ah'],
}

# =============================================================================
# VOWEL VARIATIONS
# =============================================================================

VOWEL_VARIATIONS = {
    'a': ['a', 'ah', 'ä'],
    'i': ['i', 'ee', 'ih'],
    'u': ['u', 'oo', 'ü'],
    'e': ['e', 'ay', 'é', 'ey', 'ei'],
    'o': ['o', 'oh', 'ö', 'oe'],
    'ö': ['ö', 'oe', 'eu', 'o'],  # Umlaut o
    'ü': ['ü', 'ue', 'u'],  # Umlaut u
}

# =============================================================================
# SUFFIX VARIATIONS (pronunciation changes based on suffix)
# =============================================================================

SUFFIX_VARIATIONS = {
    'ག': ['k', 'g', ''],  # Final ག → k (THL), g (Wylie), often silent
    'ང': ['ng', 'n'],
    'ད': ['', 't', 'd'],  # Often silent in modern pronunciation
    'ན': ['n', ''],
    'བ': ['p', 'b', ''],  # Final བ → p (THL), b (Wylie)
    'མ': ['m'],
    'འ': ['', 'a'],
    'ར': ['r', ''],  # Often silent in Lhasa dialect
    'ལ': ['l', ''],  # Often silent in Lhasa dialect
    'ས': ['', 's'],  # Often silent, changes vowel quality
}

# =============================================================================
# SPECIAL COMBINATIONS (khyö, etc.)
# =============================================================================

SPECIAL_COMBINATIONS = {
    # "You/your" - critical for disambiguation
    'ཁྱོད': ['khyö', 'khyo', 'khye', 'choe', 'cho', 'kyo', 'kye', 'chö'],
    'ཁྱེད': ['khye', 'khyed', 'khyö', 'che', 'chey', 'kye'],

    # Common particles with variations
    'གི': ['gi', 'ki', 'ge', 'ke'],
    'ཀྱི': ['kyi', 'ki', 'gyi', 'chi', 'kye'],
    'གྱི': ['gyi', 'gi', 'kyi'],
    'ཡི': ['yi', 'i', 'ye'],
    'འི': ["'i", 'i', 'e', 'ai'],

    # Locative particles
    'དུ': ['du', 'tu', 'ru'],
    'ཏུ': ['tu', 'du'],
    'རུ': ['ru', 'du'],
    'སུ': ['su', 'zu'],

    # Common words with many variations
    'ཆོས': ['chö', 'cho', 'choe', 'chos', 'chös'],
    'སངས་རྒྱས': ['sangye', 'sanggye', 'sangay', 'sange'],
    'བླ་མ': ['lama', 'la ma', 'blama'],
    'རྡོ་རྗེ': ['dorje', 'dorjé', 'dorji', 'vajra'],
    'པདྨ': ['pema', 'padma', 'peme', 'péma'],

    # Dharma terms
    'བྱང་ཆུབ': ['changchub', 'jangchub', 'byang chub', 'changchup'],
    'སེམས་དཔའ': ['sempa', 'sempä', 'sems dpa'],
    'བོད': ['bod', 'pö', 'po', 'böd'],  # Tibet
    'འབྲུག': ['druk', 'drug', 'dru', 'bhutan'],  # Bhutan/Dragon
}

# =============================================================================
# SUMTAK GRAMMAR RULES - Particle selection based on preceding letter
# =============================================================================

SUMTAK_RULES = {
    # Genitive/Agentive particle selection
    'genitive': {
        # Preceding suffix → correct particle
        'ག': 'གི',   # After ག, ང → གི
        'ང': 'གི',
        'ད': 'ཀྱི',  # After ད, བ, ས → ཀྱི
        'བ': 'ཀྱི',
        'ས': 'ཀྱི',
        'ན': 'གྱི',  # After ན, མ, ར, ལ → གྱི
        'མ': 'གྱི',
        'ར': 'གྱི',
        'ལ': 'གྱི',
        'འ': 'ཡི',  # After འ → ཡི or འི
        'vowel': 'འི',  # After vowel → འི
    },

    # Locative particle selection
    'locative': {
        'ག': 'ཏུ',   # After ག, ད, བ, ས → ཏུ
        'ད': 'ཏུ',
        'བ': 'ཏུ',
        'ས': 'ཏུ',
        'ང': 'དུ',   # After ང, ན, མ, ར, ལ → དུ
        'ན': 'དུ',
        'མ': 'དུ',
        'ར': 'དུ',
        'ལ': 'དུ',
        'འ': 'རུ',   # After འ, vowel → རུ
        'vowel': 'རུ',
    },

    # Instrumental particle selection (same as genitive for most)
    'instrumental': {
        'ག': 'གིས',
        'ང': 'གིས',
        'ད': 'ཀྱིས',
        'བ': 'ཀྱིས',
        'ས': 'ཀྱིས',
        'ན': 'གྱིས',
        'མ': 'གྱིས',
        'ར': 'གྱིས',
        'ལ': 'གྱིས',
        'འ': 'ཡིས',
        'vowel': 'ས',
    }
}

# Phonetic variants for particles (what users might type)
PARTICLE_PHONETIC_VARIANTS = {
    'གི': ['gi', 'ki', 'ge'],
    'ཀྱི': ['kyi', 'ki', 'chi', 'kye', 'gyi'],
    'གྱི': ['gyi', 'gi', 'kyi'],
    'ཡི': ['yi', 'i', 'ye'],
    'འི': ["'i", 'i', 'e', 'ai'],
    'གིས': ['gis', 'kis', 'gi'],
    'ཀྱིས': ['kyis', 'kis', 'chis'],
    'གྱིས': ['gyis', 'gis'],
    'ཡིས': ['yis', 'is'],
    'ས': ['s', 'se'],
    'ཏུ': ['tu', 'du'],
    'དུ': ['du', 'tu', 'ru'],
    'རུ': ['ru', 'du'],
    'སུ': ['su', 'zu'],
}

# =============================================================================
# DIALECT-SPECIFIC VARIATIONS
# =============================================================================

DIALECT_VARIATIONS = {
    'lhasa': {
        # Lhasa specific: tonal, simplified clusters
        'description': 'Central Tibetan (Ü-Tsang), tonal',
        'features': {
            'tonal': True,
            'final_r': 'silent',  # Final ར often silent
            'final_l': 'silent',  # Final ལ often silent
            'prefix_g': 'silent',  # Prefix ག often silent
        }
    },
    'kham': {
        'description': 'Eastern Tibetan (Kham), tonal',
        'features': {
            'tonal': True,
            'voiced_initials': True,  # Keeps voiced initials
        }
    },
    'amdo': {
        'description': 'Northeastern Tibetan (Amdo), non-tonal',
        'features': {
            'tonal': False,
            'preserves_clusters': True,  # Keeps consonant clusters
            'vowel_reduction': True,  # i, u → ə
        }
    },
    'dzongkha': {
        'description': 'Bhutanese, tonal',
        'features': {
            'tonal': True,
            'kha_ga_merger': True,  # ཀ་ཁ་ག་ can merge
            'final_stops': 'glottal',  # Final stops → glottal stop
        }
    }
}

# =============================================================================
# GENERATE VARIATION PAIRS
# =============================================================================

def generate_consonant_pairs():
    """Generate all consonant variation pairs for training."""
    pairs = []
    for tibetan, variants in CONSONANT_VARIATIONS.items():
        # All pairs within the same consonant
        for v1 in variants:
            for v2 in variants:
                if v1 != v2:
                    pairs.append({
                        'variant1': v1,
                        'variant2': v2,
                        'tibetan': tibetan,
                        'similarity': 1.0,  # Same consonant
                        'type': 'consonant'
                    })
    return pairs


def generate_vowel_pairs():
    """Generate vowel variation pairs."""
    pairs = []
    for base, variants in VOWEL_VARIATIONS.items():
        for v1 in variants:
            for v2 in variants:
                if v1 != v2:
                    pairs.append({
                        'variant1': v1,
                        'variant2': v2,
                        'base': base,
                        'similarity': 1.0,
                        'type': 'vowel'
                    })
    return pairs


def generate_special_pairs():
    """Generate special word/phrase variation pairs."""
    pairs = []
    for tibetan, variants in SPECIAL_COMBINATIONS.items():
        for v1 in variants:
            for v2 in variants:
                if v1 != v2:
                    pairs.append({
                        'variant1': v1,
                        'variant2': v2,
                        'tibetan': tibetan,
                        'similarity': 1.0,
                        'type': 'word'
                    })
    return pairs


def generate_particle_pairs():
    """Generate particle variation pairs with sumtak rules."""
    pairs = []
    for tibetan, variants in PARTICLE_PHONETIC_VARIANTS.items():
        for v1 in variants:
            for v2 in variants:
                if v1 != v2:
                    pairs.append({
                        'variant1': v1,
                        'variant2': v2,
                        'tibetan': tibetan,
                        'similarity': 1.0,
                        'type': 'particle'
                    })
    return pairs


def generate_cross_dialect_pairs():
    """Generate pairs across different phonetic systems."""
    pairs = []

    # khyö/choe type variations (critical for "you/your")
    you_variants = ['khyö', 'khyo', 'khye', 'choe', 'cho', 'kyo', 'kye', 'chö']
    for v1 in you_variants:
        for v2 in you_variants:
            if v1 != v2:
                pairs.append({
                    'variant1': v1,
                    'variant2': v2,
                    'meaning': 'you/your',
                    'tibetan': 'ཁྱོད',
                    'similarity': 0.9,  # High similarity, same meaning
                    'type': 'cross_dialect'
                })

    # gi/kyi/gyi particle variations
    gi_variants = ['gi', 'ki', 'kyi', 'gyi', 'chi', 'yi', 'i']
    for v1 in gi_variants:
        for v2 in gi_variants:
            if v1 != v2:
                pairs.append({
                    'variant1': v1,
                    'variant2': v2,
                    'meaning': 'genitive_particle',
                    'similarity': 0.8,
                    'type': 'particle_variant'
                })

    return pairs


def build_phonetic_map():
    """Build comprehensive phonetic → tibetan mapping with variations."""
    phonetic_map = defaultdict(list)

    # Add special combinations
    for tibetan, variants in SPECIAL_COMBINATIONS.items():
        for variant in variants:
            if tibetan not in phonetic_map[variant]:
                phonetic_map[variant].append(tibetan)

    # Add particle variants
    for tibetan, variants in PARTICLE_PHONETIC_VARIANTS.items():
        for variant in variants:
            if tibetan not in phonetic_map[variant]:
                phonetic_map[variant].append(tibetan)

    return dict(phonetic_map)


def build_sumtak_rules_json():
    """Export sumtak rules for use in Swift."""
    return {
        'genitive': SUMTAK_RULES['genitive'],
        'locative': SUMTAK_RULES['locative'],
        'instrumental': SUMTAK_RULES['instrumental'],
        'particle_variants': PARTICLE_PHONETIC_VARIANTS,
    }


def main():
    print("=" * 60)
    print("Building Phonetic Variation Database")
    print("=" * 60)

    # Generate all pairs
    consonant_pairs = generate_consonant_pairs()
    print(f"Consonant pairs: {len(consonant_pairs)}")

    vowel_pairs = generate_vowel_pairs()
    print(f"Vowel pairs: {len(vowel_pairs)}")

    special_pairs = generate_special_pairs()
    print(f"Special word pairs: {len(special_pairs)}")

    particle_pairs = generate_particle_pairs()
    print(f"Particle pairs: {len(particle_pairs)}")

    cross_dialect_pairs = generate_cross_dialect_pairs()
    print(f"Cross-dialect pairs: {len(cross_dialect_pairs)}")

    # Combine all pairs
    all_pairs = (consonant_pairs + vowel_pairs + special_pairs +
                 particle_pairs + cross_dialect_pairs)
    print(f"\nTotal training pairs: {len(all_pairs)}")

    # Build phonetic map
    phonetic_map = build_phonetic_map()
    print(f"Phonetic mappings: {len(phonetic_map)}")

    # Build sumtak rules
    sumtak_json = build_sumtak_rules_json()

    # Save training pairs
    pairs_output = LOTSAWA_CORE_DIR / "phonetic_pairs.json"
    with open(pairs_output, 'w', encoding='utf-8') as f:
        json.dump(all_pairs, f, ensure_ascii=False, indent=2)
    print(f"\nSaved training pairs to {pairs_output}")

    # Save phonetic map
    map_output = LOTSAWA_CORE_DIR / "phonetic_variations.json"
    with open(map_output, 'w', encoding='utf-8') as f:
        json.dump(phonetic_map, f, ensure_ascii=False, indent=2)
    print(f"Saved phonetic map to {map_output}")

    # Save sumtak rules
    sumtak_output = LOTSAWA_CORE_DIR / "sumtak_rules.json"
    with open(sumtak_output, 'w', encoding='utf-8') as f:
        json.dump(sumtak_json, f, ensure_ascii=False, indent=2)
    print(f"Saved sumtak rules to {sumtak_output}")

    # Print sample variations
    print("\n" + "=" * 60)
    print("Sample Phonetic Variations:")
    print("=" * 60)

    for word in ['khyö', 'choe', 'gi', 'kyi', 'cho']:
        if word in phonetic_map:
            print(f"  {word} → {phonetic_map[word]}")

    print("\n" + "=" * 60)
    print("Sumtak Rules (Genitive particle selection):")
    print("=" * 60)
    for suffix, particle in SUMTAK_RULES['genitive'].items():
        print(f"  After {suffix} → {particle}")

    print("\nDone!")


if __name__ == "__main__":
    main()
