#!/usr/bin/env python3
"""
Tibetan Phonetic Engine

Generates pronunciation for Tibetan words based on phonological rules.
This allows automatic matching of phonetic input to Tibetan words.

Key insight: Instead of manually mapping phonetic→Tibetan,
we derive Tibetan→phonetic automatically, then reverse index it.
"""

import json
import re
from collections import defaultdict
from pathlib import Path

# Unicode ranges for Tibetan
TIBETAN_CONSONANTS = {
    'ཀ': 'ka', 'ཁ': 'kha', 'ག': 'ga', 'ང': 'nga',
    'ཅ': 'cha', 'ཆ': 'chha', 'ཇ': 'ja', 'ཉ': 'nya',
    'ཏ': 'ta', 'ཐ': 'tha', 'ད': 'da', 'ན': 'na',
    'པ': 'pa', 'ཕ': 'pha', 'བ': 'ba', 'མ': 'ma',
    'ཙ': 'tsa', 'ཚ': 'tsha', 'ཛ': 'dza', 'ཝ': 'wa',
    'ཞ': 'zha', 'ཟ': 'za', 'འ': 'a', 'ཡ': 'ya',
    'ར': 'ra', 'ལ': 'la', 'ཤ': 'sha', 'ས': 'sa',
    'ཧ': 'ha', 'ཨ': 'a',
}

# Root consonant base sounds (without inherent 'a')
# Using THL simplified phonetic (no aspiration distinction for ch/tsh)
ROOT_SOUNDS = {
    'ཀ': 'k', 'ཁ': 'kh', 'ག': 'g', 'ང': 'ng',
    'ཅ': 'ch', 'ཆ': 'ch', 'ཇ': 'j', 'ཉ': 'ny',  # Both ཅ and ཆ → ch
    'ཏ': 't', 'ཐ': 'th', 'ད': 'd', 'ན': 'n',
    'པ': 'p', 'ཕ': 'ph', 'བ': 'b', 'མ': 'm',
    'ཙ': 'ts', 'ཚ': 'ts', 'ཛ': 'dz', 'ཝ': 'w',  # Both ཙ and ཚ → ts
    'ཞ': 'zh', 'ཟ': 'z', 'འ': '', 'ཡ': 'y',
    'ར': 'r', 'ལ': 'l', 'ཤ': 'sh', 'ས': 's',
    'ཧ': 'h', 'ཨ': '',
}

# Valid suffixes in Tibetan (these come AFTER the root+vowel)
SUFFIXES = {'ག', 'ང', 'ད', 'ན', 'བ', 'མ', 'འ', 'ར', 'ལ', 'ས'}

# Valid post-suffixes (come after suffix)
POST_SUFFIXES = {'ད', 'ས'}

# Vowel signs
VOWELS = {
    'ི': 'i',   # gigu
    'ུ': 'u',   # zhapkyu
    'ེ': 'e',   # drengbu
    'ོ': 'o',   # naro
    'ཱ': 'a',   # long a (rare in native words)
}

# Subjoined consonant modifiers (change root sound)
SUBJOINED_MODIFIERS = {
    'ྱ': 'y',  # ya-tak - palatalizes
    'ྲ': 'r',  # ra-tak - adds r
    'ླ': 'l',  # la-tak - adds l
    'ྭ': 'w',  # wa-zur - adds w
}

# ALL subjoined consonants (0xF90-0xFBC) mapped to base form
# These appear BELOW another letter and represent the actual root consonant
# when preceded by a superscript letter
SUBJOINED_TO_BASE = {
    'ྐ': 'ཀ', 'ྑ': 'ཁ', 'ྒ': 'ག', 'ྔ': 'ང',
    'ྕ': 'ཅ', 'ྖ': 'ཆ', 'ྗ': 'ཇ', 'ྙ': 'ཉ',
    'ྚ': 'ཊ', 'ྛ': 'ཋ', 'ྜ': 'ཌ', 'ྜྷ': 'ཌྷ', 'ྞ': 'ཎ',
    'ྟ': 'ཏ', 'ྠ': 'ཐ', 'ྡ': 'ད', 'ྡྷ': 'དྷ', 'ྣ': 'ན',
    'ྤ': 'པ', 'ྥ': 'ཕ', 'ྦ': 'བ', 'ྦྷ': 'བྷ', 'ྨ': 'མ',
    'ྩ': 'ཙ', 'ྪ': 'ཚ', 'ྫ': 'ཛ', 'ྫྷ': 'ཛྷ', 'ྭ': 'ཝ',
    'ྮ': 'ཞ', 'ྯ': 'ཟ', 'ྰ': 'འ', 'ྱ': 'ཡ',
    'ྲ': 'ར', 'ླ': 'ལ', 'ྴ': 'ཤ', 'ྵ': 'ས',
    'ྶ': 'ས', 'ྷ': 'ཧ', 'ྸ': 'ཨ',
}

# Superscripts that modify pronunciation
SUPERSCRIPTS = {'ར', 'ལ', 'ས'}

# Prefixes (usually silent in pronunciation)
PREFIXES = {'ག', 'ད', 'བ', 'མ', 'འ'}

# Pronunciation transformations for complex consonant clusters
# When superscript + root or prefix + root
CLUSTER_SOUNDS = {
    # Superscript ས (s)
    ('ས', 'ཀ'): 'k',   # སྐ → k
    ('ས', 'ག'): 'g',   # སྒ → g
    ('ས', 'ང'): 'ng',  # སྔ → ng
    ('ས', 'ཏ'): 't',   # སྟ → t
    ('ས', 'ད'): 'd',   # སྡ → d
    ('ས', 'ན'): 'n',   # སྣ → n
    ('ས', 'པ'): 'p',   # སྤ → p
    ('ས', 'བ'): 'b',   # སྦ → b
    ('ས', 'མ'): 'm',   # སྨ → m
    ('ས', 'ར'): 's',   # སྲ → s (rare)

    # Superscript ར (r)
    ('ར', 'ཀ'): 'k',   # རྐ → k
    ('ར', 'ག'): 'g',   # རྒ → g
    ('ར', 'ང'): 'ng',  # རྔ → ng
    ('ར', 'ཏ'): 't',   # རྟ → t (voiced retroflex-ish)
    ('ར', 'ད'): 'd',   # རྡ → d
    ('ར', 'ན'): 'n',   # རྣ → n
    ('ར', 'བ'): 'b',   # རྦ → b
    ('ར', 'མ'): 'm',   # རྨ → m
    ('ར', 'ཇ'): 'j',   # རྗ → j
    ('ར', 'ལ'): 'l',   # རླ → l

    # Superscript ལ (l)
    ('ལ', 'ཀ'): 'k',   # ལྐ → k (or lk)
    ('ལ', 'ག'): 'g',   # ལྒ → g
    ('ལ', 'ང'): 'ng',  # ལྔ → ng
    ('ལ', 'ཅ'): 'ch',  # ལྕ → ch
    ('ལ', 'ཇ'): 'j',   # ལྗ → j
    ('ལ', 'ཏ'): 't',   # ལྟ → t
    ('ལ', 'ད'): 'd',   # ལྡ → d
    ('ལ', 'པ'): 'p',   # ལྤ → p
    ('ལ', 'བ'): 'b',   # ལྦ → b
    ('ལ', 'ཧ'): 'lh',  # ལྷ → lh
}

# Ya-tak (ྱ) palatalization rules
YATAK_SOUNDS = {
    'ཀ': 'ky',   # ཀྱ → ky
    'ཁ': 'khy',  # ཁྱ → khy (often sounds like 'ch')
    'ག': 'gy',   # གྱ → gy
    'པ': 'ch',   # པྱ → ch (palatalizes to ch)
    'ཕ': 'ch',   # ཕྱ → ch
    'བ': 'j',    # བྱ → j
    'མ': 'ny',   # མྱ → ny (nasalized)
}

# Alternative ya-tak sounds (more phonetic)
YATAK_PHONETIC = {
    'ཁ': 'ch',   # ཁྱོད → chö (khyod sounds like "chö")
    'ཕ': 'ch',   # ཕྱ → ch
}


class TibetanPhonetics:
    """Generate phonetic pronunciation for Tibetan text."""

    def __init__(self):
        self.cache = {}

    def parse_syllable(self, syllable: str) -> dict:
        """
        Parse a Tibetan syllable into components.
        Returns dict with: prefix, superscript, root, subscript, vowel, suffix, post_suffix

        Tibetan syllable structure:
        (prefix) + (superscript) + ROOT + (subscript/modifier) + (vowel) + (suffix) + (post-suffix)

        Key insight: When a SUBJOINED consonant appears (0xF90-0xFBC),
        IT is the root, and the letter before it is superscript.
        """
        if not syllable:
            return {}

        result = {
            'prefix': None,
            'superscript': None,
            'root': None,
            'subscripts': [],  # modifiers like ྱ ྲ ླ ྭ
            'vowel': 'a',  # default vowel
            'suffix': None,
            'post_suffix': None,
            'original': syllable
        }

        chars = list(syllable)

        # Categorize each character
        base_consonants = []  # (index, char) - base form consonants
        subjoined_consonants = []  # (index, char, base_form) - subjoined consonants
        vowels_found = []
        modifiers_found = []  # ྱ ྲ ླ ྭ

        for i, char in enumerate(chars):
            if char in TIBETAN_CONSONANTS:
                base_consonants.append((i, char))
            elif char in SUBJOINED_TO_BASE:
                base_form = SUBJOINED_TO_BASE[char]
                # Check if it's a modifier (y, r, l, w) or actual root
                if char in SUBJOINED_MODIFIERS:
                    modifiers_found.append(char)
                else:
                    subjoined_consonants.append((i, char, base_form))
            elif char in VOWELS:
                vowels_found.append(char)

        # Determine the root consonant
        # Rule: If there's a subjoined consonant (not modifier), IT is the root
        # The base consonant before it is the superscript

        if subjoined_consonants:
            # The first subjoined consonant is the root
            root_idx, root_subjoined, root_base = subjoined_consonants[0]
            result['root'] = root_base

            # Any base consonant before the root is superscript (or prefix+superscript)
            preceding_bases = [(i, c) for i, c in base_consonants if i < root_idx]
            if len(preceding_bases) == 1:
                result['superscript'] = preceding_bases[0][1]
            elif len(preceding_bases) >= 2:
                result['prefix'] = preceding_bases[0][1]
                result['superscript'] = preceding_bases[1][1]

            # Base consonants AFTER the vowel are suffix/post-suffix
            vowel_idx = next((i for i, c in enumerate(chars) if c in VOWELS), root_idx)
            following_bases = [(i, c) for i, c in base_consonants if i > vowel_idx]
            if len(following_bases) >= 1:
                result['suffix'] = following_bases[0][1]
            if len(following_bases) >= 2:
                result['post_suffix'] = following_bases[1][1]

        else:
            # No subjoined consonant - parse based on Tibetan syllable structure
            # Key insight: The ROOT carries the vowel (explicit or inherent 'a')
            # Structure: (prefix) + ROOT + (suffix) + (post-suffix)
            # Or: (prefix) + (superscript) + ROOT + (suffix) + (post-suffix)

            num_cons = len(base_consonants)
            vowel_idx = next((i for i, c in enumerate(chars) if c in VOWELS), -1)

            if num_cons == 0:
                return result

            elif num_cons == 1:
                result['root'] = base_consonants[0][1]

            elif num_cons == 2:
                first, second = base_consonants[0][1], base_consonants[1][1]
                first_idx, second_idx = base_consonants[0][0], base_consonants[1][0]

                # If vowel is explicitly between them, first=root, second=suffix
                if vowel_idx > first_idx and vowel_idx < second_idx:
                    result['root'] = first
                    result['suffix'] = second
                # If no visible vowel (inherent 'a')
                elif vowel_idx < 0:
                    # For two consonants without vowel, prefer root+suffix
                    # e.g., དག = d+a+g = "dak" (not prefix-d + root-g)
                    # This is because words like དག (pure), ལག (hand) are root+suffix
                    if second in SUFFIXES:
                        result['root'] = first
                        result['suffix'] = second
                    elif first in PREFIXES:
                        result['prefix'] = first
                        result['root'] = second
                    else:
                        result['root'] = first
                        result['suffix'] = second
                # Vowel after both consonants
                elif vowel_idx > second_idx:
                    if first in PREFIXES:
                        result['prefix'] = first
                        result['root'] = second
                    else:
                        result['root'] = first
                        result['suffix'] = second
                else:
                    # Vowel on first consonant
                    result['root'] = first
                    result['suffix'] = second

            elif num_cons == 3:
                first, second, third = [c for _, c in base_consonants[:3]]
                first_idx = base_consonants[0][0]
                second_idx = base_consonants[1][0]
                third_idx = base_consonants[2][0]

                # Determine where vowel falls
                if vowel_idx > second_idx:
                    # Vowel on third or after - third might be suffix
                    if first in PREFIXES:
                        result['prefix'] = first
                        result['root'] = second
                        result['suffix'] = third
                    elif first in SUPERSCRIPTS:
                        result['superscript'] = first
                        result['root'] = second
                        result['suffix'] = third
                    else:
                        result['root'] = first
                        result['suffix'] = second
                        result['post_suffix'] = third
                elif vowel_idx > first_idx:
                    # Vowel on second consonant
                    if first in PREFIXES:
                        result['prefix'] = first
                        result['root'] = second
                        result['suffix'] = third
                    else:
                        result['root'] = first
                        result['suffix'] = second
                        result['post_suffix'] = third
                else:
                    # Vowel on first or no vowel
                    if first in PREFIXES:
                        result['prefix'] = first
                        result['root'] = second
                        result['suffix'] = third
                    else:
                        result['root'] = first
                        result['suffix'] = second
                        result['post_suffix'] = third

            else:  # 4+ consonants
                # (prefix) + (superscript) + ROOT + suffix + (post-suffix)
                first, second, third, fourth = [c for _, c in base_consonants[:4]]

                if first in PREFIXES:
                    result['prefix'] = first
                    if second in SUPERSCRIPTS:
                        result['superscript'] = second
                        result['root'] = third
                        if len(base_consonants) > 3:
                            result['suffix'] = base_consonants[3][1]
                        if len(base_consonants) > 4:
                            result['post_suffix'] = base_consonants[4][1]
                    else:
                        result['root'] = second
                        result['suffix'] = third
                        if len(base_consonants) > 3:
                            result['post_suffix'] = base_consonants[3][1]
                else:
                    result['root'] = first
                    result['suffix'] = second
                    if len(base_consonants) > 2:
                        result['post_suffix'] = base_consonants[2][1]

        # Vowel
        if vowels_found:
            result['vowel'] = VOWELS.get(vowels_found[0], 'a')

        # Subscript modifiers (ྱ ྲ ླ ྭ)
        result['subscripts'] = modifiers_found

        return result

    def get_pronunciation(self, syllable: str) -> list:
        """
        Generate possible pronunciations for a Tibetan syllable.
        Returns list of phonetic strings (most common first).
        """
        if syllable in self.cache:
            return self.cache[syllable]

        parsed = self.parse_syllable(syllable)
        if not parsed.get('root'):
            return [syllable]  # Can't parse, return as-is

        pronunciations = []

        root = parsed['root']
        superscript = parsed.get('superscript')
        subscripts = parsed.get('subscripts', [])
        vowel = parsed.get('vowel', 'a')
        suffix = parsed.get('suffix')

        # Determine consonant sound
        consonant = ''

        # Check for superscript clusters
        if superscript and (superscript, root) in CLUSTER_SOUNDS:
            consonant = CLUSTER_SOUNDS[(superscript, root)]
        else:
            consonant = ROOT_SOUNDS.get(root, '')

        # Prefix འ de-aspirates the root consonant
        # འཕ → p, འཐ → t, འཁ → k, འཆ → ch (already)
        prefix = parsed.get('prefix')
        if prefix == 'འ':
            if root == 'ཕ':
                consonant = 'p'
            elif root == 'ཐ':
                consonant = 't'
            elif root == 'ཁ':
                consonant = 'k'
            elif root == 'ཚ':
                consonant = 'ts'

        # Apply subscript modifier effects (ྱ ྲ ླ ྭ)
        for sub in subscripts:
            if sub == 'ྱ':  # ya-tak - palatalization
                # Special case: ཁྱ sounds like "ch" not "khy"
                if root == 'ཁ':
                    consonant = 'ch'
                elif root in YATAK_SOUNDS:
                    consonant = YATAK_SOUNDS[root]
                else:
                    consonant = consonant + 'y'
            elif sub == 'ྲ':  # ra-tak
                consonant = consonant + 'r'
            elif sub == 'ླ':  # la-tak
                consonant = consonant + 'l'
            elif sub == 'ྭ':  # wa-zur
                consonant = consonant + 'w'

        # Build base pronunciation
        base = consonant + vowel

        # Handle suffix effects on vowel
        # Tibetan suffixes change pronunciation significantly
        if suffix:
            suffix_sound = ROOT_SOUNDS.get(suffix, '')

            # Vowel changes caused by suffixes (Lhasa dialect)
            # -ན suffix: 'a' → 'en', other vowels + n
            # -ས suffix: 'a' → 'é', adds slight aspiration
            # -ག suffix: 'a' → 'ak', other vowels + k
            # -ད suffix: often silent, may nasalize
            # -མ suffix: 'a' → 'am', other vowels + m
            # -ང suffix: 'a' → 'ang', nasalizes
            # -ར suffix: 'a' → 'ar'
            # -ལ suffix: 'a' → 'al' or 'e'
            # -བ suffix: usually silent

            if suffix == 'ན':  # -n suffix
                if vowel == 'a':
                    pronunciations.append(consonant + 'en')
                    pronunciations.append(consonant + 'an')
                else:
                    pronunciations.append(base + 'n')
            elif suffix == 'ས':  # -s suffix (often changes to é)
                if vowel == 'a':
                    pronunciations.append(consonant + 'é')
                    pronunciations.append(consonant + 'e')
                    pronunciations.append(consonant + 'ey')
                else:
                    pronunciations.append(base)  # s often silent
            elif suffix == 'ག':  # -g suffix (becomes k)
                pronunciations.append(base + 'k')
                if vowel == 'a':
                    pronunciations.append(consonant + 'ak')
            elif suffix == 'ད':  # -d suffix (often silent, affects vowel)
                if vowel == 'o':
                    pronunciations.append(consonant + 'ö')
                    pronunciations.append(consonant + 'oe')
                elif vowel == 'u':
                    pronunciations.append(consonant + 'ü')
                    pronunciations.append(consonant + 'ue')
                elif vowel == 'a':
                    # -ad suffix → é sound
                    pronunciations.append(consonant + 'é')
                    pronunciations.append(consonant + 'e')
                    pronunciations.append(consonant + 'ey')
                else:
                    pronunciations.append(base)
            elif suffix == 'བ':  # -b suffix (becomes p sound)
                if vowel == 'a':
                    pronunciations.append(consonant + 'ap')
                    pronunciations.append(consonant + 'ep')
                else:
                    pronunciations.append(base + 'p')
            elif suffix == 'མ':  # -m suffix
                pronunciations.append(base + 'm')
                if vowel == 'a':
                    pronunciations.append(consonant + 'am')
            elif suffix == 'ང':  # -ng suffix
                pronunciations.append(base + 'ng')
                if vowel == 'a':
                    pronunciations.append(consonant + 'ang')
            elif suffix == 'ར':  # -r suffix
                pronunciations.append(base + 'r')
            elif suffix == 'ལ':  # -l suffix
                pronunciations.append(base + 'l')
                if vowel == 'a':
                    pronunciations.append(consonant + 'el')
            else:
                pronunciations.append(base + suffix_sound)
        else:
            # No suffix - just consonant + vowel
            pronunciations.append(base)

        # Generate alternative spellings for vowels
        alternatives = set()
        for pron in pronunciations:
            alternatives.add(pron)
            # ö spellings (o with umlaut effect)
            if 'o' in pron and suffix in {'ད', 'ས'}:
                alternatives.add(pron.replace('o', 'oe'))
                alternatives.add(pron.replace('o', 'ö'))
            # ü spellings
            if 'u' in pron:
                alternatives.add(pron.replace('u', 'ue'))
                alternatives.add(pron.replace('u', 'ü'))
            # é spellings
            if 'e' in pron:
                alternatives.add(pron.replace('e', 'ey'))
                alternatives.add(pron.replace('e', 'é'))

        result = list(alternatives)
        self.cache[syllable] = result
        return result

    def get_word_pronunciations(self, word: str) -> list:
        """
        Get pronunciations for a multi-syllable Tibetan word.
        """
        # Split by tsheg
        syllables = re.split(r'[་།༔\s]+', word.strip())
        syllables = [s for s in syllables if s]

        if not syllables:
            return []

        # Get pronunciations for each syllable
        syllable_prons = [self.get_pronunciation(s) for s in syllables]

        # Combine (take first/most common pronunciation of each)
        result = []

        # Primary pronunciation (first of each)
        primary = ''.join(prons[0] if prons else '' for prons in syllable_prons)
        result.append(primary)

        # Also add spaced version
        spaced = ' '.join(prons[0] if prons else '' for prons in syllable_prons)
        if spaced != primary:
            result.append(spaced)

        return result


def build_phonetic_index():
    """
    Build reverse phonetic index: pronunciation → [tibetan words]
    """
    SCRIPT_DIR = Path(__file__).parent
    PROJECT_DIR = SCRIPT_DIR.parent
    LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

    phonetics = TibetanPhonetics()

    # Load existing dictionary for Tibetan words
    dict_path = LOTSAWA_CORE_DIR / "phonetic_dictionary.json"

    # Collect all unique Tibetan words/syllables
    tibetan_words = set()
    word_frequencies = defaultdict(int)

    if dict_path.exists():
        with open(dict_path, 'r', encoding='utf-8') as f:
            phrase_dict = json.load(f)

        for phonetic, tibetan_list in phrase_dict.items():
            for tibetan in tibetan_list:
                # Split into syllables
                syllables = re.split(r'[་།༔\s]+', tibetan.strip())
                for syl in syllables:
                    if syl and any('\u0F00' <= c <= '\u0FFF' for c in syl):
                        tibetan_words.add(syl)
                        word_frequencies[syl] += 1

                # Also add full word
                tibetan_clean = tibetan.strip().rstrip('།་')
                if tibetan_clean:
                    tibetan_words.add(tibetan_clean)
                    word_frequencies[tibetan_clean] += 1

    print(f"Collected {len(tibetan_words)} unique Tibetan words/syllables")

    # Build pronunciation → words index
    pron_to_tibetan = defaultdict(list)

    for tibetan in tibetan_words:
        pronunciations = phonetics.get_word_pronunciations(tibetan)
        freq = word_frequencies.get(tibetan, 1)

        for pron in pronunciations:
            # Normalize pronunciation
            pron_lower = pron.lower().strip()
            if pron_lower:
                pron_to_tibetan[pron_lower].append({
                    't': tibetan,
                    'f': freq
                })

    # Also add single syllable pronunciations
    for tibetan in tibetan_words:
        syllables = re.split(r'[་།༔\s]+', tibetan.strip())
        for syl in syllables:
            if syl:
                for pron in phonetics.get_pronunciation(syl):
                    pron_lower = pron.lower().strip()
                    if pron_lower:
                        pron_to_tibetan[pron_lower].append({
                            't': syl,
                            'f': word_frequencies.get(syl, 1)
                        })

    # Sort by frequency and deduplicate
    final_dict = {}
    for pron, entries in pron_to_tibetan.items():
        # Dedupe by tibetan word
        seen = {}
        for entry in entries:
            tib = entry['t']
            if tib not in seen or entry['f'] > seen[tib]['f']:
                seen[tib] = entry

        # Sort by frequency
        sorted_entries = sorted(seen.values(), key=lambda x: -x['f'])
        final_dict[pron] = sorted_entries[:10]  # Keep top 10

    print(f"Generated {len(final_dict)} phonetic entries")

    # Add common phonetic variants manually for high-priority words
    add_phonetic_variants(final_dict, word_frequencies)

    return final_dict


def add_phonetic_variants(pron_dict: dict, freqs: dict):
    """Add phonetic spelling variants that users commonly type."""

    # Base consonants - so "ch" returns ཆ, "k" returns ཀ, etc.
    base_consonants = {
        'k': ['ཀ'], 'ka': ['ཀ'],
        'kh': ['ཁ'], 'kha': ['ཁ'],
        'g': ['ག'], 'ga': ['ག'],
        'ng': ['ང'], 'nga': ['ང'],
        'ch': ['ཆ', 'ཅ'], 'cha': ['ཆ', 'ཅ'],  # ཆ is aspirated, ཅ is not
        'chh': ['ཆ'], 'chha': ['ཆ'],
        'j': ['ཇ'], 'ja': ['ཇ'],
        'ny': ['ཉ'], 'nya': ['ཉ'],
        't': ['ཏ'], 'ta': ['ཏ'],
        'th': ['ཐ'], 'tha': ['ཐ'],
        'd': ['ད'], 'da': ['ད'],
        'n': ['ན'], 'na': ['ན'],
        'p': ['པ'], 'pa': ['པ'],
        'ph': ['ཕ'], 'pha': ['ཕ'],
        'b': ['བ'], 'ba': ['བ'],
        'm': ['མ'], 'ma': ['མ'],
        'ts': ['ཙ'], 'tsa': ['ཙ'],
        'tsh': ['ཚ'], 'tsha': ['ཚ'],
        'dz': ['ཛ'], 'dza': ['ཛ'],
        'w': ['ཝ'], 'wa': ['ཝ'],
        'zh': ['ཞ'], 'zha': ['ཞ'],
        'z': ['ཟ'], 'za': ['ཟ'],
        'y': ['ཡ'], 'ya': ['ཡ'],
        'r': ['ར'], 'ra': ['ར'],
        'l': ['ལ'], 'la': ['ལ'],
        'sh': ['ཤ'], 'sha': ['ཤ'],
        's': ['ས'], 'sa': ['ས'],
        'h': ['ཧ'], 'ha': ['ཧ'],
        'a': ['ཨ'],
    }

    variants = {
        **base_consonants,

        # chö sound - ཆོས and ཁྱོད both sound like "chö"
        'choe': ['ཆོས', 'ཁྱོད'],
        'cho': ['ཆོས', 'ཁྱོད'],
        'chö': ['ཆོས', 'ཁྱོད'],

        # ney/ne - ནས and གནས both sound like "né"
        'ney': ['ནས', 'གནས'],
        'ne': ['ནས', 'གནས', 'ནེ'],
        'nay': ['ནས', 'གནས'],
        'né': ['ནས', 'གནས'],

        # tashi
        'tashi': ['བཀྲ་ཤིས'],
        'tashe': ['བཀྲ་ཤིས'],

        # delek
        'delek': ['བདེ་ལེགས'],
        'deleg': ['བདེ་ལེགས'],

        # sangye (Buddha)
        'sangye': ['སངས་རྒྱས'],
        'sanggye': ['སངས་རྒྱས'],
        'sangay': ['སངས་རྒྱས'],

        # lama
        'lama': ['བླ་མ'],

        # dalta/data (now)
        'data': ['ད་ལྟ'],
        'dalta': ['ད་ལྟ'],
        'tanda': ['ད་ལྟ'],

        # Common words people search for
        'dorje': ['རྡོ་རྗེ'],
        'pema': ['པདྨ', 'པད་མ'],
        'yeshe': ['ཡེ་ཤེས'],
        'rigpa': ['རིག་པ'],
        'nyingje': ['སྙིང་རྗེ'],
        'tongpa': ['སྟོང་པ'],
        'gendun': ['དགེ་འདུན'],
        'sem': ['སེམས'],
        'sems': ['སེམས'],

        # Pronouns
        'nga': ['ང'],
        'kho': ['ཁོ'],
        'khong': ['ཁོང'],

        # Verbs
        'yin': ['ཡིན'],
        'yoe': ['ཡོད'],
        'yo': ['ཡོད'],
        'red': ['རེད'],
        're': ['རེད'],
        'duk': ['འདུག'],
        'dug': ['འདུག'],
        'song': ['སོང'],
        'yong': ['ཡོང'],

        # Particles
        'la': ['ལ'],
        'gi': ['གི'],
        'gyi': ['གྱི'],
        'kyi': ['ཀྱི'],
        'ni': ['ནི'],
        'pa': ['པ'],
        'po': ['པོ'],
        'ma': ['མ', 'མ་'],
        'mo': ['མོ'],

        # Mantras
        'om': ['ཨོཾ', 'ༀ'],
        'ah': ['ཨཱཿ'],
        'hung': ['ཧཱུྃ'],
        'mani': ['མ་ཎི'],
        'padme': ['པདྨེ'],
        'peme': ['པདྨེ'],
    }

    for pron, tibetans in variants.items():
        entries = []
        # Base consonants get highest priority (freq 10000)
        is_base_consonant = pron in base_consonants
        for tib in tibetans:
            freq = freqs.get(tib, 500)
            # Give base consonants very high frequency so they appear first
            if is_base_consonant:
                freq = 10000
            else:
                freq = max(freq, 500)
            entries.append({'t': tib, 'f': freq})

        # Merge with existing if present
        if pron in pron_dict:
            existing = {e['t']: e for e in pron_dict[pron]}
            for e in entries:
                if e['t'] not in existing or e['f'] > existing[e['t']]['f']:
                    existing[e['t']] = e
            entries = list(existing.values())

        pron_dict[pron] = sorted(entries, key=lambda x: -x['f'])[:10]


def main():
    SCRIPT_DIR = Path(__file__).parent
    PROJECT_DIR = SCRIPT_DIR.parent
    LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

    print("=" * 60)
    print("ལོ་ཙཱ་བ། Tibetan Phonetic Engine")
    print("=" * 60)

    # Build phonetic index
    pron_dict = build_phonetic_index()

    # Save
    output_path = LOTSAWA_CORE_DIR / "phonetic_lookup.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(pron_dict, f, ensure_ascii=False, separators=(',', ':'))

    print(f"\n✅ Saved to {output_path}")
    print(f"   Size: {output_path.stat().st_size / 1024:.1f} KB")

    # Test some examples
    print("\n📝 Test pronunciations:")
    phonetics = TibetanPhonetics()

    tests = [
        ('ཆོས', 'dharma'),
        ('ཁྱོད', 'you'),
        ('ནས', 'from'),
        ('གནས', 'place'),
        ('བཀྲ་ཤིས', 'tashi'),
        ('སངས་རྒྱས', 'Buddha'),
        ('ད་ལྟ', 'now'),
        ('རྡོ་རྗེ', 'vajra'),
    ]

    for tibetan, meaning in tests:
        prons = phonetics.get_word_pronunciations(tibetan)
        print(f"   {tibetan} ({meaning}): {prons}")

    # Show lookup samples
    print("\n📝 Sample lookups:")
    samples = ['choe', 'cho', 'ney', 'ne', 'tashi', 'data', 'sangye']
    for s in samples:
        if s in pron_dict:
            entries = pron_dict[s][:3]
            tibetans = ', '.join(e['t'] for e in entries)
            print(f"   {s:15} → {tibetans}")
        else:
            print(f"   {s:15} → NOT FOUND")

    print("\n✅ DONE!")


if __name__ == "__main__":
    main()
