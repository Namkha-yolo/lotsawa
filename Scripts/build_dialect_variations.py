#!/usr/bin/env python3
"""
Build comprehensive dialect-specific phonetic variations for Tibetan.

This script generates 2000+ phonetic variations covering:
- Lhasa (Central Tibetan): Cluster simplification, silent finals
- Amdo (Northeastern): Preserved clusters, vowel reduction
- Kham (Eastern): Voicing changes
- Dzongkha (Bhutanese): khy→ch, special word forms

The variations are used by PhoneticFuzzyMatcher to accept inputs
from speakers of different dialects.
"""

import json
from pathlib import Path
from collections import defaultdict
from itertools import product

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

# =============================================================================
# DIALECT TRANSFORMATION RULES
# =============================================================================

# Lhasa dialect: Central Tibetan (Ü-Tsang)
# - Cluster simplification: br→dr, bl→l, gr→dr, gl→l
# - Silent finals: final -r, -l, -s often silent
# - Tonal with high/low register
LHASA_RULES = {
    "cluster_simplification": [
        ("br", "dr"),
        ("bl", "l"),
        ("gr", "dr"),
        ("gl", "l"),
        ("dby", "y"),
        ("dmy", "my"),
        ("rng", "ng"),
        ("rny", "ny"),
        ("rmy", "my"),
        ("sng", "ng"),
        ("sny", "ny"),
        ("smy", "my"),
        ("skr", "tr"),
        ("sgr", "dr"),
        ("spr", "tr"),
        ("sbr", "dr"),
        ("smr", "mr"),
    ],
    "final_simplification": [
        ("gs", ""),
        ("bs", ""),
        ("ms", ""),
        ("ng", "ng"),  # preserved
        ("r$", ""),    # final r often silent
        ("l$", ""),    # final l often silent
        ("s$", ""),    # final s often silent
    ],
    "vowel_changes": [
        # Umlaut from suffix
        ("ag", "e"),
        ("og", "ö"),
        ("ug", "ü"),
        ("ad", "e"),
        ("od", "ö"),
        ("ud", "ü"),
    ],
}

# Amdo dialect: Northeastern Tibetan
# - Preserves consonant clusters more fully
# - Vowel reduction (unstressed i, u → ə)
# - Non-tonal
AMDO_RULES = {
    "preserved_clusters": [
        # Amdo keeps these clusters that Lhasa simplifies
        ("br", "br"),
        ("gr", "gr"),
        ("pr", "pr"),
        ("kr", "kr"),
        ("tr", "tr"),
        ("dr", "dr"),
    ],
    "vowel_reduction": [
        ("i$", "ə"),  # final i can reduce
        ("u$", "ə"),  # final u can reduce
    ],
    "consonant_retention": [
        # Amdo tends to keep final consonants
        ("g$", "g"),
        ("d$", "d"),
        ("b$", "b"),
    ],
}

# Kham dialect: Eastern Tibetan
# - Voicing changes: k→g, t→d, p→b in certain positions
# - Maintains some archaic features
# - Tonal
KHAM_RULES = {
    "initial_voicing": [
        ("k", "g"),
        ("t", "d"),
        ("p", "b"),
        ("ts", "dz"),
        ("ch", "j"),
    ],
    "aspiration_loss": [
        ("kh", "k"),
        ("th", "t"),
        ("ph", "p"),
        ("tsh", "ts"),
    ],
}

# Dzongkha: Bhutanese
# - khy → ch (khyod → choe)
# - Different honorific system
# - Some unique vocabulary
DZONGKHA_RULES = {
    "palatalization": [
        ("khy", "ch"),
        ("khye", "che"),
        ("khyo", "cho"),
        ("khyö", "chö"),
        ("phy", "ch"),
    ],
    "word_specific": {
        "ཁྱོད": ["choe", "cho", "chö"],
        "ཁྱེད": ["che", "chey"],
        "བཀྲ་ཤིས": ["tashi", "trashi"],
        "ལགས": ["la", "laa"],
        "བཞུགས": ["shuk", "zhuk"],
    },
}

# =============================================================================
# BASE CONSONANT SETS
# =============================================================================

TIBETAN_INITIAL_CONSONANTS = [
    "k", "kh", "g", "ng",
    "c", "ch", "j", "ny",
    "t", "th", "d", "n",
    "p", "ph", "b", "m",
    "ts", "tsh", "dz", "w",
    "zh", "z", "y", "r", "l",
    "sh", "s", "h", "a"
]

TIBETAN_VOWELS = ["a", "i", "u", "e", "o", "ö", "ü"]

TIBETAN_FINALS = ["", "g", "ng", "d", "n", "b", "m", "r", "l", "s"]

CONSONANT_CLUSTERS = [
    # kr- clusters
    "kr", "khr", "gr", "ngr",
    # ky- clusters
    "ky", "khy", "gy",
    # pr- clusters
    "pr", "phr", "br", "mr",
    # tr- clusters
    "tr", "thr", "dr", "nr",
    # ts- clusters
    "tsr", "tshr",
    # s- prefix clusters
    "sk", "sg", "sng", "sny", "st", "sd", "sn", "sp", "sb", "sm",
    # r- prefix clusters
    "rk", "rg", "rng", "rj", "rny", "rt", "rd", "rn", "rb", "rm",
    # l- prefix clusters
    "lk", "lg", "lng", "lc", "lj", "lt", "ld", "ln", "lp", "lb", "lm",
    # b- prefix clusters
    "bk", "bg", "bc", "bt", "bd", "bs",
    # m- prefix clusters (archaic)
    "mk", "mg", "mch", "mj", "mt", "md", "mn",
    # Complex clusters
    "skr", "sgr", "spr", "sbr", "smr",
    "bskr", "bsgr", "bspr", "bsbr",
]

# =============================================================================
# VARIATION GENERATION FUNCTIONS
# =============================================================================

def generate_lhasa_variations(base_forms):
    """Generate Lhasa dialect variations."""
    variations = {}

    for tibetan, phonetics in base_forms.items():
        lhasa_vars = set(phonetics)

        for phonetic in phonetics:
            # Apply cluster simplification
            modified = phonetic
            for old, new in LHASA_RULES["cluster_simplification"]:
                if old in modified:
                    lhasa_vars.add(modified.replace(old, new))

            # Apply final simplification (drop silent finals)
            for pattern, replacement in LHASA_RULES["final_simplification"]:
                if pattern.endswith("$"):
                    # Final position pattern
                    suffix = pattern[:-1]
                    if modified.endswith(suffix):
                        lhasa_vars.add(modified[:-len(suffix)] + replacement)
                elif pattern in modified:
                    lhasa_vars.add(modified.replace(pattern, replacement))

        variations[tibetan] = list(lhasa_vars)

    return variations


def generate_amdo_variations(base_forms):
    """Generate Amdo dialect variations."""
    variations = {}

    for tibetan, phonetics in base_forms.items():
        amdo_vars = set(phonetics)

        for phonetic in phonetics:
            # Amdo preserves clusters - add full cluster forms
            for cluster_pair in AMDO_RULES["preserved_clusters"]:
                # If base has simplified form, add cluster form
                simple, full = cluster_pair
                if simple in phonetic and simple != full:
                    amdo_vars.add(phonetic.replace(simple, full))

            # Vowel reduction
            for pattern, replacement in AMDO_RULES["vowel_reduction"]:
                if pattern.endswith("$"):
                    suffix = pattern[:-1]
                    if phonetic.endswith(suffix):
                        reduced = phonetic[:-len(suffix)] + replacement
                        amdo_vars.add(reduced)
                        # Also add schwa variants
                        amdo_vars.add(phonetic[:-len(suffix)] + "e")

        variations[tibetan] = list(amdo_vars)

    return variations


def generate_kham_variations(base_forms):
    """Generate Kham dialect variations."""
    variations = {}

    for tibetan, phonetics in base_forms.items():
        kham_vars = set(phonetics)

        for phonetic in phonetics:
            # Apply voicing changes
            modified = phonetic
            for unvoiced, voiced in KHAM_RULES["initial_voicing"]:
                if phonetic.startswith(unvoiced):
                    kham_vars.add(voiced + phonetic[len(unvoiced):])

            # Apply aspiration loss
            for aspirated, plain in KHAM_RULES["aspiration_loss"]:
                if aspirated in phonetic:
                    kham_vars.add(phonetic.replace(aspirated, plain))

        variations[tibetan] = list(kham_vars)

    return variations


def generate_dzongkha_variations(base_forms):
    """Generate Dzongkha (Bhutanese) variations."""
    variations = {}

    for tibetan, phonetics in base_forms.items():
        dz_vars = set(phonetics)

        # Check for word-specific variations
        if tibetan in DZONGKHA_RULES["word_specific"]:
            dz_vars.update(DZONGKHA_RULES["word_specific"][tibetan])

        for phonetic in phonetics:
            # Apply palatalization rules
            for old, new in DZONGKHA_RULES["palatalization"]:
                if old in phonetic:
                    dz_vars.add(phonetic.replace(old, new))

        variations[tibetan] = list(dz_vars)

    return variations


def generate_common_variations(tibetan, base_phonetic):
    """Generate common cross-dialect variations for a single word."""
    variations = set([base_phonetic])

    # Aspiration variations
    aspiration_pairs = [
        ("kh", "k"), ("k", "kh"),
        ("th", "t"), ("t", "th"),
        ("ph", "p"), ("p", "ph"),
        ("ch", "c"), ("c", "ch"),
        ("tsh", "ts"), ("ts", "tsh"),
    ]

    for asp, plain in aspiration_pairs:
        if asp in base_phonetic:
            variations.add(base_phonetic.replace(asp, plain))

    # Voicing variations
    voicing_pairs = [
        ("k", "g"), ("g", "k"),
        ("t", "d"), ("d", "t"),
        ("p", "b"), ("b", "p"),
        ("ch", "j"), ("j", "ch"),
        ("ts", "dz"), ("dz", "ts"),
    ]

    for v1, v2 in voicing_pairs:
        if base_phonetic.startswith(v1):
            variations.add(v2 + base_phonetic[len(v1):])

    # Vowel variations
    vowel_alternations = [
        ("e", "ey"), ("e", "ay"), ("e", "ai"),
        ("o", "ö"), ("o", "oe"),
        ("u", "ü"), ("u", "ue"),
        ("i", "ee"), ("i", "yi"),
        ("a", "ah"),
    ]

    for v1, v2 in vowel_alternations:
        if v1 in base_phonetic:
            variations.add(base_phonetic.replace(v1, v2))
        if v2 in base_phonetic:
            variations.add(base_phonetic.replace(v2, v1))

    # Final consonant variations
    final_variations = [
        ("k", "g"), ("g", "k"), ("g", ""),
        ("p", "b"), ("b", "p"), ("b", ""),
        ("d", "t"), ("t", "d"), ("d", ""),
        ("s", ""), ("r", ""), ("l", ""),
    ]

    for old, new in final_variations:
        if base_phonetic.endswith(old):
            variations.add(base_phonetic[:-len(old)] + new)

    return list(variations)


def generate_systematic_variations():
    """Generate systematic variations for common syllable patterns."""
    variations = defaultdict(list)

    # Common syllables with their base forms
    common_syllables = {
        # Numbers
        "གཅིག": ["chik", "chig", "jik"],
        "གཉིས": ["nyi", "nyee", "nyi"],
        "གསུམ": ["sum", "soom"],
        "བཞི": ["shi", "shee", "zhi"],
        "ལྔ": ["nga", "na"],
        "དྲུག": ["druk", "dru", "truk"],
        "བདུན": ["dun", "dün", "doon"],
        "བརྒྱད": ["gye", "gey", "je"],
        "དགུ": ["gu", "goo", "ku"],
        "བཅུ": ["chu", "choo", "cu"],

        # Pronouns
        "ང": ["nga", "na"],
        "ཁྱོད": ["khyö", "khyo", "choe", "cho", "kyo"],
        "ཁྱེད": ["khye", "khyed", "che", "chey", "kye"],
        "ཁོ": ["kho", "ko"],
        "མོ": ["mo"],
        "རང": ["rang", "ra"],

        # Common verbs
        "ཡིན": ["yin", "yi"],
        "རེད": ["re", "ray", "red"],
        "ཡོད": ["yoe", "yo", "yö", "yod"],
        "མེད": ["me", "mé", "med"],
        "འདུག": ["duk", "du", "dug"],
        "བྱེད": ["je", "jey", "jed", "che"],
        "ཟ": ["za", "sa"],
        "ཐུང": ["thung", "tung", "thun"],
        "འགྲོ": ["dro", "tro", "gro"],
        "ཡོང": ["yong", "yung"],

        # Dharma terms
        "སངས": ["sang", "sa"],
        "རྒྱས": ["gye", "gya", "je"],
        "ཆོས": ["cho", "chö", "choe", "chos"],
        "བླ་མ": ["lama", "la ma"],
        "སེམས": ["sem", "sems"],
        "སྐུ": ["ku", "sku"],
        "གསུང": ["sung", "su"],
        "ཐུགས": ["thuk", "tuk", "thu"],

        # Common words
        "བོད": ["bod", "pö", "po", "böd"],
        "ལྷ་ས": ["lhasa", "lha sa"],
        "འབྲུག": ["druk", "dru", "brug"],
        "དགོན་པ": ["gompa", "gönpa", "gonpa"],
        "རིན་པོ་ཆེ": ["rinpoche", "rinpoché"],
        "བཀྲ་ཤིས": ["tashi", "trashi", "tashee"],
        "བདེ་ལེགས": ["delek", "deleg", "dele"],
    }

    for tibetan, base_forms in common_syllables.items():
        all_vars = set(base_forms)

        # Generate variations for each base form
        for base in base_forms:
            all_vars.update(generate_common_variations(tibetan, base))

        variations[tibetan] = list(all_vars)

    return dict(variations)


def merge_variations(*variation_dicts):
    """Merge multiple variation dictionaries."""
    merged = defaultdict(set)

    for var_dict in variation_dicts:
        for tibetan, phonetics in var_dict.items():
            merged[tibetan].update(phonetics)

    return {k: list(v) for k, v in merged.items()}


def load_existing_variations():
    """Load existing phonetic_variations.json."""
    path = LOTSAWA_CORE_DIR / "phonetic_variations.json"
    if path.exists():
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}


def invert_to_phonetic_map(tibetan_to_phonetic):
    """Convert tibetan→[phonetics] to phonetic→[tibetans]."""
    phonetic_map = defaultdict(list)

    for tibetan, phonetics in tibetan_to_phonetic.items():
        for phonetic in phonetics:
            if tibetan not in phonetic_map[phonetic]:
                phonetic_map[phonetic].append(tibetan)

    return dict(phonetic_map)


def count_total_variations(variations_dict):
    """Count total number of variations."""
    return sum(len(v) for v in variations_dict.values())


def main():
    print("=" * 60)
    print("Building Dialect-Specific Phonetic Variations")
    print("=" * 60)

    # Load existing variations
    print("\nLoading existing variations...")
    existing = load_existing_variations()
    existing_count = count_total_variations(existing)
    print(f"  Existing variations: {existing_count}")

    # Convert existing phonetic→tibetan to tibetan→phonetic for processing
    tibetan_to_phonetic = defaultdict(set)
    for phonetic, tibetans in existing.items():
        for tibetan in tibetans:
            tibetan_to_phonetic[tibetan].add(phonetic)

    tibetan_to_phonetic = {k: list(v) for k, v in tibetan_to_phonetic.items()}

    # Generate systematic variations
    print("\nGenerating systematic variations...")
    systematic = generate_systematic_variations()
    systematic_count = count_total_variations(systematic)
    print(f"  Systematic variations: {systematic_count}")

    # Generate dialect-specific variations
    print("\nGenerating Lhasa dialect variations...")
    lhasa = generate_lhasa_variations(tibetan_to_phonetic)
    lhasa.update(generate_lhasa_variations(systematic))
    lhasa_count = count_total_variations(lhasa)
    print(f"  Lhasa variations: {lhasa_count}")

    print("Generating Amdo dialect variations...")
    amdo = generate_amdo_variations(tibetan_to_phonetic)
    amdo.update(generate_amdo_variations(systematic))
    amdo_count = count_total_variations(amdo)
    print(f"  Amdo variations: {amdo_count}")

    print("Generating Kham dialect variations...")
    kham = generate_kham_variations(tibetan_to_phonetic)
    kham.update(generate_kham_variations(systematic))
    kham_count = count_total_variations(kham)
    print(f"  Kham variations: {kham_count}")

    print("Generating Dzongkha variations...")
    dzongkha = generate_dzongkha_variations(tibetan_to_phonetic)
    dzongkha.update(generate_dzongkha_variations(systematic))
    dzongkha_count = count_total_variations(dzongkha)
    print(f"  Dzongkha variations: {dzongkha_count}")

    # Merge all variations
    print("\nMerging all variations...")
    all_tibetan_to_phonetic = merge_variations(
        tibetan_to_phonetic,
        systematic,
        lhasa,
        amdo,
        kham,
        dzongkha
    )

    # Convert back to phonetic→tibetan format
    phonetic_map = invert_to_phonetic_map(all_tibetan_to_phonetic)

    # Add existing entries that weren't captured
    for phonetic, tibetans in existing.items():
        if phonetic not in phonetic_map:
            phonetic_map[phonetic] = tibetans
        else:
            for t in tibetans:
                if t not in phonetic_map[phonetic]:
                    phonetic_map[phonetic].append(t)

    total_variations = len(phonetic_map)
    total_mappings = sum(len(v) for v in phonetic_map.values())

    print(f"\n{'=' * 60}")
    print(f"Total unique phonetic forms: {total_variations}")
    print(f"Total phonetic→Tibetan mappings: {total_mappings}")

    # Save
    output_path = LOTSAWA_CORE_DIR / "phonetic_variations.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(phonetic_map, f, ensure_ascii=False, indent=2)

    print(f"\nSaved to {output_path}")

    # Print sample variations by dialect
    print(f"\n{'=' * 60}")
    print("Sample variations by dialect:")
    print("=" * 60)

    samples = ["ཁྱོད", "དྲུག", "བཀྲ་ཤིས", "ཆོས"]
    for tibetan in samples:
        if tibetan in all_tibetan_to_phonetic:
            print(f"\n  {tibetan}:")
            vars_list = all_tibetan_to_phonetic[tibetan]
            for v in vars_list[:8]:
                print(f"    - {v}")
            if len(vars_list) > 8:
                print(f"    ... and {len(vars_list) - 8} more")

    print("\nDone!")


if __name__ == "__main__":
    main()
