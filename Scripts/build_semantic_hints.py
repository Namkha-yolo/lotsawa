#!/usr/bin/env python3
"""
Build comprehensive semantic hints for Tibetan homophone disambiguation.

This script generates 500+ semantic hints that help the keyboard choose
the correct Tibetan word based on surrounding context.

Key homophones covered:
- chu: བཅུ (10) vs ཆུ (water)
- nga: ང (I) vs ལྔ (5) vs མངའ (authority)
- choe: ཁྱོད (you) vs ཆོས (dharma)
- druk: དྲུག (6) vs འབྲུག (Bhutan)
- me: མེད (not-exist) vs མེ (fire)
- dak: བདག (self) vs དག (pure)
- kor: འཁོར (retinue) vs སྐོར (about)
- And many more...

The hints are organized as:
{
    "preceding_context": {
        "tibetan_syllable": {
            "phonetic_input": "preferred_tibetan"
        }
    },
    "following_context": { ... },
    "domain_hints": { ... }
}
"""

import json
from pathlib import Path
from collections import defaultdict

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

# =============================================================================
# HOMOPHONE DEFINITIONS
# =============================================================================

# Primary homophones that need disambiguation
HOMOPHONES = {
    # chu: 10 vs water
    "chu": {
        "བཅུ": {"meaning": "ten", "domain": "number"},
        "ཆུ": {"meaning": "water", "domain": "nature"},
    },

    # nga: I vs 5 vs authority
    "nga": {
        "ང": {"meaning": "I/me", "domain": "pronoun"},
        "ལྔ": {"meaning": "five", "domain": "number"},
        "མངའ": {"meaning": "authority/possession", "domain": "formal"},
    },

    # choe/cho: you (Bhutanese) vs dharma
    "choe": {
        "ཁྱོད": {"meaning": "you (Bhutanese)", "domain": "pronoun"},
        "ཆོས": {"meaning": "dharma/religion", "domain": "dharma"},
    },
    "cho": {
        "ཁྱོད": {"meaning": "you", "domain": "pronoun"},
        "ཆོས": {"meaning": "dharma", "domain": "dharma"},
    },

    # druk: 6 vs Bhutan/dragon
    "druk": {
        "དྲུག": {"meaning": "six", "domain": "number"},
        "འབྲུག": {"meaning": "Bhutan/dragon", "domain": "place"},
    },

    # me: not-exist vs fire
    "me": {
        "མེད": {"meaning": "not exist", "domain": "verb"},
        "མེ": {"meaning": "fire", "domain": "nature"},
    },

    # dak/dag: self vs pure
    "dak": {
        "བདག": {"meaning": "self/I", "domain": "dharma"},
        "དག": {"meaning": "pure", "domain": "dharma"},
    },
    "dag": {
        "བདག": {"meaning": "self/I", "domain": "dharma"},
        "དག": {"meaning": "pure", "domain": "dharma"},
    },

    # kor: retinue vs about
    "kor": {
        "འཁོར": {"meaning": "retinue/circle", "domain": "dharma"},
        "སྐོར": {"meaning": "about/around", "domain": "colloquial"},
    },

    # gye: 8 vs spread
    "gye": {
        "བརྒྱད": {"meaning": "eight", "domain": "number"},
        "རྒྱས": {"meaning": "spread/expand", "domain": "dharma"},
    },

    # gu: 9 vs body
    "gu": {
        "དགུ": {"meaning": "nine", "domain": "number"},
        "སྐུ": {"meaning": "body (honorific)", "domain": "dharma"},
    },

    # dun: 7 vs purpose
    "dun": {
        "བདུན": {"meaning": "seven", "domain": "number"},
        "དོན": {"meaning": "meaning/purpose", "domain": "dharma"},
    },

    # shi: 4 vs death
    "shi": {
        "བཞི": {"meaning": "four", "domain": "number"},
        "འཆི": {"meaning": "death/die", "domain": "dharma"},
    },

    # sum: 3 vs three
    "sum": {
        "གསུམ": {"meaning": "three", "domain": "number"},
    },

    # nyi: 2 vs sun
    "nyi": {
        "གཉིས": {"meaning": "two", "domain": "number"},
        "ཉི": {"meaning": "sun", "domain": "nature"},
    },

    # la: particle vs soul
    "la": {
        "ལ": {"meaning": "to/at (particle)", "domain": "particle"},
        "བླ": {"meaning": "soul/life-force", "domain": "dharma"},
    },

    # pa: nominalizer vs brave
    "pa": {
        "པ": {"meaning": "nominalizer", "domain": "particle"},
        "དཔའ": {"meaning": "brave/hero", "domain": "dharma"},
    },

    # re: question particle vs is (factual)
    "re": {
        "རེ": {"meaning": "question particle", "domain": "particle"},
        "རེད": {"meaning": "is (factual)", "domain": "verb"},
    },

    # je: do/make vs lord
    "je": {
        "བྱེད": {"meaning": "do/make", "domain": "verb"},
        "རྗེ": {"meaning": "lord", "domain": "dharma"},
    },

    # che: big vs tongue
    "che": {
        "ཆེ": {"meaning": "big/great", "domain": "adjective"},
        "ལྕེ": {"meaning": "tongue", "domain": "body"},
        "བྱེད": {"meaning": "do/make", "domain": "verb"},
    },

    # sem: mind
    "sem": {
        "སེམས": {"meaning": "mind", "domain": "dharma"},
    },

    # yin: is (equative)
    "yin": {
        "ཡིན": {"meaning": "is (equative)", "domain": "verb"},
    },

    # yoe/yo: have/exist
    "yoe": {
        "ཡོད": {"meaning": "have/exist", "domain": "verb"},
    },
    "yo": {
        "ཡོད": {"meaning": "have/exist", "domain": "verb"},
    },
}

# =============================================================================
# CONTEXT PATTERNS - Words that commonly precede/follow homophones
# =============================================================================

# Number sequences (counting patterns)
NUMBER_SEQUENCE = {
    "གཅིག": "གཉིས",   # 1 → 2
    "གཉིས": "གསུམ",   # 2 → 3
    "གསུམ": "བཞི",    # 3 → 4
    "བཞི": "ལྔ",      # 4 → 5
    "ལྔ": "དྲུག",     # 5 → 6
    "དྲུག": "བདུན",   # 6 → 7
    "བདུན": "བརྒྱད",  # 7 → 8
    "བརྒྱད": "དགུ",   # 8 → 9
    "དགུ": "བཅུ",     # 9 → 10
}

# Dharma collocations (common dharma term pairs)
DHARMA_COLLOCATIONS = {
    # Buddha contexts
    "སངས": {"gye": "རྒྱས"},      # sang + gye = Buddha
    "རྒྱས": {"cho": "ཆོས", "choe": "ཆོས"},  # Buddha + dharma

    # Dharma contexts
    "ཆོས": {
        "gendun": "དགེ་འདུན",  # dharma + sangha
        "kyi": "ཀྱི",          # dharma + genitive
        "la": "ལ",            # dharma + dative
        "kor": "འཁོར",        # dharma + wheel
    },

    # Three Jewels
    "དཀོན": {"chok": "མཆོག", "chog": "མཆོག"},
    "མཆོག": {"sum": "གསུམ"},

    # Enlightenment terms
    "བྱང": {"chub": "ཆུབ", "chup": "ཆུབ"},
    "ཆུབ": {"sem": "སེམས"},

    # Self/mind terms
    "བདག": {
        "gi": "གི",
        "gyi": "གྱི",
        "nyid": "ཉིད",
        "med": "མེད",
    },

    # Pure vision
    "དག": {
        "pa": "པ",
        "snang": "སྣང",
    },
}

# Pronoun contexts
PRONOUN_CONTEXTS = {
    # Before pronouns (subjects)
    "preceding_pronouns": ["ཡིན", "རེད", "འདུག", "ཡོད", "མེད", "བྱེད", "ཟེར"],

    # After pronouns (possessives, actions)
    "following_pronouns": {
        "ང": ["གི", "གིས", "ལ", "ཡིན", "རང"],
        "ཁྱོད": ["ཀྱི", "ཀྱིས", "ལ", "རང"],
        "ཁྱེད": ["ཀྱི", "ཀྱིས", "ལ", "རང"],
    },
}

# Verb patterns
VERB_PATTERNS = {
    # Existential verbs followed by negation
    "ཡོད": {"me": "མེད"},  # yod + me = don't have
    "ཡིན": {"me": "མེད"},  # yin + me = is not

    # Action verbs
    "ཐུང": {"chu": "ཆུ"},  # drink + water
    "འཐུང": {"chu": "ཆུ"},
    "ཟ": {"kha": "ཁ"},     # eat + food

    # Common verb endings
    "བྱེད": {"pa": "པ", "kyi": "ཀྱི"},
}

# Nature/element contexts
NATURE_CONTEXTS = {
    # Fire contexts
    "མེ": {
        "preceded_by": ["འབར", "དམར", "ཚ"],
        "followed_by": ["འབར", "སྟག", "ལྕེ"],
    },

    # Water contexts
    "ཆུ": {
        "preceded_by": ["ཐུང", "འཐུང", "གཙང", "རྒྱུན", "ཆུ"],
        "followed_by": ["ཐུང", "མཚོ", "བོ", "ཁ", "རྒྱུན"],
    },
}

# Place name contexts
PLACE_CONTEXTS = {
    # Bhutan contexts
    "འབྲུག": {
        "preceded_by": ["རྒྱལ", "ལྷོ"],
        "followed_by": ["ཡུལ", "པ", "མི"],
    },
}

# =============================================================================
# HINT GENERATION FUNCTIONS
# =============================================================================

def generate_number_hints():
    """Generate hints for number disambiguation."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # After a number, the next number in sequence is likely
    for prev_num, next_num in NUMBER_SEQUENCE.items():
        # Map the phonetic to the correct number
        hints["preceding"][prev_num] = {}

        # chu after 9 = 10
        if next_num == "བཅུ":
            hints["preceding"][prev_num]["chu"] = "བཅུ"
        # nga after 4 = 5
        elif next_num == "ལྔ":
            hints["preceding"][prev_num]["nga"] = "ལྔ"
        # druk after 5 = 6
        elif next_num == "དྲུག":
            hints["preceding"][prev_num]["druk"] = "དྲུག"
        # dun after 6 = 7
        elif next_num == "བདུན":
            hints["preceding"][prev_num]["dun"] = "བདུན"
        # gye after 7 = 8
        elif next_num == "བརྒྱད":
            hints["preceding"][prev_num]["gye"] = "བརྒྱད"
        # gu after 8 = 9
        elif next_num == "དགུ":
            hints["preceding"][prev_num]["gu"] = "དགུ"
        # shi after 3 = 4
        elif next_num == "བཞི":
            hints["preceding"][prev_num]["shi"] = "བཞི"
        # sum after 2 = 3
        elif next_num == "གསུམ":
            hints["preceding"][prev_num]["sum"] = "གསུམ"
        # nyi after 1 = 2
        elif next_num == "གཉིས":
            hints["preceding"][prev_num]["nyi"] = "གཉིས"

    # Add counting word contexts
    counting_words = ["གྲངས", "བསྡོམས", "ཚད", "རིམ"]
    for word in counting_words:
        hints["preceding"][word] = {
            "chu": "བཅུ",
            "nga": "ལྔ",
            "druk": "དྲུག",
            "dun": "བདུན",
            "gye": "བརྒྱད",
            "gu": "དགུ",
            "shi": "བཞི",
        }

    return hints


def generate_dharma_hints():
    """Generate hints for dharma term disambiguation."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # Add dharma collocations
    for preceding, mappings in DHARMA_COLLOCATIONS.items():
        hints["preceding"][preceding] = {}
        for phonetic, tibetan in mappings.items():
            hints["preceding"][preceding][phonetic] = tibetan

    # Common dharma context words
    dharma_words = [
        "སངས", "རྒྱས", "ཆོས", "དགེ", "འདུན", "བླ", "མ",
        "སྐུ", "གསུང", "ཐུགས", "རིན", "པོ", "ཆེ", "མཆོད",
        "སྒྲུབ", "ཉམས", "ལེན", "བསྐྱེད", "རྫོགས", "རིམ",
        "སྔགས", "དབང", "ལུང", "ཁྲིད", "བཀའ", "གདམས",
    ]

    for word in dharma_words:
        if word not in hints["preceding"]:
            hints["preceding"][word] = {}
        # In dharma context, prefer dharma meanings
        hints["preceding"][word].update({
            "cho": "ཆོས",
            "choe": "ཆོས",
            "dak": "བདག",
            "dag": "དག",
            "sem": "སེམས",
            "kor": "འཁོར",
            "la": "ལ",
            "pa": "པ",
            "je": "རྗེ",  # lord in dharma context
        })

    return hints


def generate_pronoun_hints():
    """Generate hints for pronoun disambiguation."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # After verbs, "nga" is likely "I"
    verbs = ["ཡིན", "རེད", "འདུག", "ཡོད", "མེད", "བྱེད", "ཟེར",
             "སོང", "བྱུང", "ཐུབ", "དགོས", "འདོད"]
    for verb in verbs:
        hints["preceding"][verb] = {
            "nga": "ང",  # I
            "choe": "ཁྱོད",  # you (Bhutanese)
            "cho": "ཁྱོད",
        }

    # Before possessive particles, pronouns
    possessives = ["གི", "གིས", "ཀྱི", "ཀྱིས", "གྱི", "གྱིས", "ཡི", "འི"]
    for poss in possessives:
        hints["following"][poss] = {
            "nga": "ང",
            "choe": "ཁྱོད",
            "cho": "ཁྱོད",
        }

    # After pronouns
    hints["preceding"]["ང"] = {
        "gi": "གི",
        "yi": "ཡི",
        "la": "ལ",
        "yin": "ཡིན",
        "rang": "རང",
    }

    hints["preceding"]["ཁྱོད"] = {
        "kyi": "ཀྱི",
        "kyis": "ཀྱིས",
        "la": "ལ",
        "rang": "རང",
    }

    return hints


def generate_nature_hints():
    """Generate hints for nature/element words."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # Water contexts
    water_verbs = ["ཐུང", "འཐུང", "བླུག", "འབབ", "རྒྱུག"]
    for verb in water_verbs:
        hints["preceding"][verb] = {"chu": "ཆུ"}

    water_adjectives = ["གཙང", "དྲི", "ཚ", "གྲང"]
    for adj in water_adjectives:
        hints["preceding"][adj] = {"chu": "ཆུ"}
        hints["following"][adj] = {"chu": "ཆུ"}

    # Fire contexts
    fire_words = ["འབར", "དམར", "ཚ", "སྲེག", "མེ"]
    for word in fire_words:
        hints["preceding"][word] = {"me": "མེ"}
        hints["following"][word] = {"me": "མེ"}

    # Negation contexts (me = not exist)
    negation_contexts = ["ཡོད", "ཡིན", "འདུག", "རེད", "བྱེད"]
    for word in negation_contexts:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["me"] = "མེད"  # not exist

    return hints


def generate_place_hints():
    """Generate hints for place name disambiguation."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # Bhutan contexts
    bhutan_words = ["རྒྱལ", "ལྷོ", "ཤར", "ཁབ", "ལུང"]
    for word in bhutan_words:
        hints["preceding"][word] = {"druk": "འབྲུག"}

    hints["following"]["ཡུལ"] = {"druk": "འབྲུག"}
    hints["following"]["པ"] = hints["following"].get("པ", {})
    hints["following"]["མི"] = hints["following"].get("མི", {})

    # After druk (Bhutan), common words
    hints["preceding"]["འབྲུག"] = {
        "yul": "ཡུལ",
        "pa": "པ",
        "mi": "མི",
    }

    return hints


def generate_verb_hints():
    """Generate hints for verb disambiguation."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # je/je: do vs lord
    # After dharma terms, "je" = lord
    dharma_titles = ["རིན", "པོ", "ཆེ", "བླ", "མ", "རྒྱལ", "བ"]
    for word in dharma_titles:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["je"] = "རྗེ"

    # In action contexts, "je" = do/make
    action_words = ["ལས", "བྱ", "འགྲུབ", "ཐུབ", "དགོས"]
    for word in action_words:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["je"] = "བྱེད"

    # re: question vs is
    # At end of questions
    question_words = ["ག", "སུ", "ཅི", "གང", "ཇི"]
    for word in question_words:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["re"] = "རེ"

    # In statements
    statement_words = ["འདི", "དེ", "ཡིན", "མིན"]
    for word in statement_words:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["re"] = "རེད"

    return hints


def generate_particle_hints():
    """Generate hints for particle selection (sumtak rules)."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # After words ending in ག, ང → གི
    g_ng_endings = ["བདག", "འཁོར", "སངས", "རྒྱས", "ཆོས", "སྐུ", "ལུང", "དབང",
                   "སྐྱེས", "གསུང", "རྟོག", "དཔག", "འཕྲིན", "སྦྱང", "རྫོང"]
    for word in g_ng_endings:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["gi"] = "གི"
        hints["preceding"][word]["gis"] = "གིས"

    # After words ending in ད, བ, ས → ཀྱི
    d_b_s_endings = ["ཁྱོད", "ཡོད", "མེད", "བྱེད", "ཆོས", "དོན", "ཐབས",
                    "བཀོད", "སྤྱོད", "སྦྱར", "བརྗོད", "གཏོད", "བསྒྱུར"]
    for word in d_b_s_endings:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["kyi"] = "ཀྱི"
        hints["preceding"][word]["kyis"] = "ཀྱིས"

    # After words ending in ན, མ, ར, ལ → གྱི
    n_m_r_l_endings = ["ཡིན", "སེམས", "དཀོན", "ཕྱིར", "བསྐལ", "གཏན", "གཞན",
                      "སྤྱན", "མཚན", "བསམ", "གནམ", "སྐར", "ངོར", "ཕྱིར"]
    for word in n_m_r_l_endings:
        hints["preceding"][word] = hints["preceding"].get(word, {})
        hints["preceding"][word]["gyi"] = "གྱི"
        hints["preceding"][word]["gyis"] = "གྱིས"

    return hints


def generate_common_phrase_hints():
    """Generate hints for common Tibetan phrases and collocations."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # Common two-syllable phrases where second syllable needs disambiguation
    phrases = {
        # Greetings and common expressions
        "བཀྲ": {"shi": "ཤིས"},  # བཀྲ་ཤིས (tashi)
        "བདེ": {"leg": "ལེགས", "mo": "མོ", "po": "པོ"},  # བདེ་ལེགས, བདེ་མོ
        "ཐུགས": {"je": "རྗེ", "che": "ཆེ"},  # ཐུགས་རྗེ་ཆེ

        # Body parts and nature
        "མིག": {"chu": "ཆུ"},  # མིག་ཆུ (tears)
        "ཁ": {"chu": "ཆུ"},   # ཁ་ཆུ (saliva)
        "རྒྱ": {"མཚོ": "མཚོ", "chu": "ཆུ"},  # རྒྱ་མཚོ (ocean)

        # Dharma compounds
        "སྙིང": {"je": "རྗེ", "po": "པོ"},  # སྙིང་རྗེ (compassion)
        "ཤེས": {"rab": "རབ"},  # ཤེས་རབ (wisdom)
        "སྟོང": {"pa": "པ", "nyid": "ཉིད"},  # སྟོང་པ་ཉིད (emptiness)

        # Time expressions
        "ཉིན": {"mo": "མོ"},  # ཉིན་མོ (daytime)
        "མཚན": {"mo": "མོ"},  # མཚན་མོ (nighttime)

        # Titles and honorifics
        "རིན": {"po": "པོ", "che": "ཆེ"},  # རིན་པོ་ཆེ
        "བླ": {"ma": "མ"},  # བླ་མ
        "མཁན": {"po": "པོ"},  # མཁན་པོ

        # Action words
        "བཀའ": {"drin": "དྲིན", "che": "ཆེ"},  # བཀའ་དྲིན་ཆེ (thank you)
        "དགོངས": {"pa": "པ", "dag": "དག"},  # དགོངས་དག (sorry)

        # Mantras and sacred syllables
        "ཨོཾ": {"ma": "མ"},  # ཨོཾ་མ་ཎི
        "མ": {"ni": "ཎི"},
        "པད": {"me": "མེ"},  # པདྨེ (padme) - lotus

        # Nature compounds
        "རླུང": {"po": "པོ"},  # རླུང་པོ (wind)
        "ས": {"cha": "ཆ"},  # ས་ཆ (place)

        # Directions
        "ཤར": {"phyogs": "ཕྱོགས"},  # ཤར་ཕྱོགས (east)
        "ནུབ": {"phyogs": "ཕྱོགས"},  # ནུབ་ཕྱོགས (west)
        "ལྷོ": {"phyogs": "ཕྱོགས"},  # ལྷོ་ཕྱོགས (south)
        "བྱང": {"phyogs": "ཕྱོགས", "chub": "ཆུབ"},  # བྱང་ཕྱོགས/བྱང་ཆུབ

        # Verb phrases
        "ཡག": {"po": "པོ"},  # ཡག་པོ (good)
        "སྡུག": {"po": "པོ", "bsngal": "བསྔལ"},  # སྡུག་བསྔལ (suffering)
    }

    for preceding, mappings in phrases.items():
        hints["preceding"][preceding] = hints["preceding"].get(preceding, {})
        hints["preceding"][preceding].update(mappings)

    return hints


def generate_honorific_hints():
    """Generate hints for honorific vs ordinary word pairs."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # Honorific contexts - when these words appear, prefer honorific forms
    honorific_markers = [
        "སྐུ", "གསུང", "ཐུགས", "ཞབས", "དབུ", "སྤྱན",
        "རིན", "བླ", "རྗེ", "མཁན", "སྤྲུལ"
    ]

    for marker in honorific_markers:
        hints["preceding"][marker] = hints["preceding"].get(marker, {})
        hints["preceding"][marker].update({
            "che": "ཆེ",       # great (honorific)
            "po": "པོ",        # nominalizer
            "mo": "མོ",        # feminine
            "je": "རྗེ",       # lord
            "drin": "དྲིན",    # kindness
        })

    # After honorific body parts
    body_honorific = {
        "སྐུ": ["གདུང", "ཕྲེང", "གསུམ", "ཆེན"],
        "གསུང": ["རབ", "ཆོས", "འཁོར"],
        "ཐུགས": ["རྗེ", "དམ", "ཀ"],
    }

    for body, followers in body_honorific.items():
        for follower in followers:
            if follower not in hints["following"]:
                hints["following"][follower] = {}

    return hints


def generate_negation_hints():
    """Generate hints for negation patterns."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # Common verbs that take མེད negation
    verbs_with_med = [
        "ཡོད", "འདུག", "ཤེས", "གོ", "མཐོང", "ཐོས",
        "རྟོགས", "ཧ", "ཁ", "ཚད", "དགོས"
    ]

    for verb in verbs_with_med:
        hints["preceding"][verb] = hints["preceding"].get(verb, {})
        hints["preceding"][verb]["me"] = "མེད"

    # Common verbs that take མིན negation
    verbs_with_min = ["ཡིན", "རེད"]
    for verb in verbs_with_min:
        hints["preceding"][verb] = hints["preceding"].get(verb, {})
        hints["preceding"][verb]["min"] = "མིན"

    # After མ (negation prefix), common verb stems
    hints["preceding"]["མ"] = {
        "yin": "ཡིན",
        "re": "རེད",
        "yoe": "ཡོད",
        "duk": "འདུག",
        "she": "ཤེས",
    }

    return hints


def generate_question_hints():
    """Generate hints for question word contexts."""
    hints = {
        "preceding": {},
        "following": {},
    }

    # After question words, certain patterns are common
    question_words = ["ག", "སུ", "ཅི", "ཇི", "གང", "ཚོད", "ནས", "དུས"]

    for qw in question_words:
        hints["preceding"][qw] = hints["preceding"].get(qw, {})
        hints["preceding"][qw].update({
            "re": "རེ",     # question particle
            "yin": "ཡིན",   # is
            "yoe": "ཡོད",   # have
        })

    # Specific question patterns
    hints["preceding"]["ག"] = hints["preceding"].get("ག", {})
    hints["preceding"]["ག"].update({
        "re": "རེ",
        "na": "ན",
        "par": "པར",
        "tsod": "ཚོད",
    })

    return hints


def generate_domain_hints():
    """Generate domain-based hints."""
    hints = {
        "dharma_domain": {
            "cho": "ཆོས",
            "choe": "ཆོས",
            "dak": "བདག",
            "sem": "སེམས",
            "kor": "འཁོར",
            "je": "རྗེ",
            "la": "བླ",
            "pa": "དཔའ",
        },
        "colloquial_domain": {
            "cho": "ཁྱོད",
            "choe": "ཁྱོད",
            "nga": "ང",
            "me": "མེད",
            "la": "ལ",
            "pa": "པ",
            "re": "རེད",
            "kor": "སྐོར",
        },
        "number_domain": {
            "chu": "བཅུ",
            "nga": "ལྔ",
            "druk": "དྲུག",
            "dun": "བདུན",
            "gye": "བརྒྱད",
            "gu": "དགུ",
            "shi": "བཞི",
            "sum": "གསུམ",
            "nyi": "གཉིས",
        },
    }

    return hints


def merge_hints(*hint_dicts):
    """Merge multiple hint dictionaries."""
    result = {
        "preceding": {},
        "following": {},
    }

    for hints in hint_dicts:
        for context_type in ["preceding", "following"]:
            if context_type in hints:
                for word, mappings in hints[context_type].items():
                    if word not in result[context_type]:
                        result[context_type][word] = {}
                    result[context_type][word].update(mappings)

    return result


def count_hints(hints):
    """Count total number of hints."""
    count = 0
    for context_type in ["preceding", "following"]:
        if context_type in hints:
            for word, mappings in hints[context_type].items():
                count += len(mappings)
    return count


def main():
    print("=" * 60)
    print("Building Semantic Hints for Homophone Disambiguation")
    print("=" * 60)

    # Generate all hints
    print("\nGenerating hints by category...")

    number_hints = generate_number_hints()
    print(f"  Number hints: {count_hints(number_hints)}")

    dharma_hints = generate_dharma_hints()
    print(f"  Dharma hints: {count_hints(dharma_hints)}")

    pronoun_hints = generate_pronoun_hints()
    print(f"  Pronoun hints: {count_hints(pronoun_hints)}")

    nature_hints = generate_nature_hints()
    print(f"  Nature hints: {count_hints(nature_hints)}")

    place_hints = generate_place_hints()
    print(f"  Place hints: {count_hints(place_hints)}")

    verb_hints = generate_verb_hints()
    print(f"  Verb hints: {count_hints(verb_hints)}")

    particle_hints = generate_particle_hints()
    print(f"  Particle hints: {count_hints(particle_hints)}")

    common_phrase_hints = generate_common_phrase_hints()
    print(f"  Common phrase hints: {count_hints(common_phrase_hints)}")

    honorific_hints = generate_honorific_hints()
    print(f"  Honorific hints: {count_hints(honorific_hints)}")

    negation_hints = generate_negation_hints()
    print(f"  Negation hints: {count_hints(negation_hints)}")

    question_hints = generate_question_hints()
    print(f"  Question hints: {count_hints(question_hints)}")

    # Merge all hints
    all_hints = merge_hints(
        number_hints,
        dharma_hints,
        pronoun_hints,
        nature_hints,
        place_hints,
        verb_hints,
        particle_hints,
        common_phrase_hints,
        honorific_hints,
        negation_hints,
        question_hints,
    )

    # Add domain hints
    all_hints["domain_hints"] = generate_domain_hints()

    # Add homophone definitions for reference
    all_hints["homophones"] = HOMOPHONES

    # Add metadata
    all_hints["metadata"] = {
        "version": "1.0",
        "total_preceding_contexts": len(all_hints["preceding"]),
        "total_following_contexts": len(all_hints["following"]),
        "total_hints": count_hints(all_hints),
    }

    print(f"\n{'=' * 60}")
    print(f"Total hints generated: {count_hints(all_hints)}")
    print(f"Preceding contexts: {len(all_hints['preceding'])}")
    print(f"Following contexts: {len(all_hints['following'])}")

    # Save to JSON
    output_path = LOTSAWA_CORE_DIR / "semantic_hints.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(all_hints, f, ensure_ascii=False, indent=2)

    print(f"\nSaved to {output_path}")

    # Print sample hints
    print(f"\n{'=' * 60}")
    print("Sample hints:")
    print("=" * 60)

    samples = ["དགུ", "ཐུང", "སངས", "ཡིན", "མེད"]
    for word in samples:
        if word in all_hints["preceding"]:
            print(f"\n  After '{word}':")
            for phonetic, tibetan in list(all_hints["preceding"][word].items())[:3]:
                print(f"    {phonetic} → {tibetan}")

    print("\nDone!")


if __name__ == "__main__":
    main()
