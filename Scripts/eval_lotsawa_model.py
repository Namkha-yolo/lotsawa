#!/usr/bin/env python3
"""Evaluate the trained Lotsawa LM against baselines.

Produces:
  - results.json      (metrics for paper tables)
  - homophone_cases.json  (per-case predictions for inspection)

Baselines:
  1. Frequency-only: pick most frequent Tibetan for phonetic key in SQLite
  2. N-gram context: dict + bigram/trigram context via SQLite (simulates
     the production pipeline without the ML model)
  3. Our BiLSTM: the trained neural model
  4. Hybrid (ours + n-gram rerank): how the shipped keyboard actually works

Metrics:
  - Top-1 / Top-5 / Top-10 accuracy on held-out HF test set
  - Homophone disambiguation accuracy on a curated test suite
  - Inference latency (ms/query) on CPU
"""

import argparse
import json
import math
import random
import sqlite3
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import torch

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

# Import model definition from training script
sys.path.insert(0, str(SCRIPT_DIR))
from train_lotsawa_model import (
    LotsawaLM, tokenize_phonetic, tokenize_tibetan, dp_align,
    encode_phonetic, PAD_IDX, UNK_IDX,
)


# ---------------------------------------------------------------------------
# Homophone test suite
# ---------------------------------------------------------------------------
#
# Each case: (phonetic, context_tokens_tibetan, expected_tibetan, description)
# The context tokens are given in their canonical Tibetan form, and represent
# the words typed right before the phonetic being tested.
# ---------------------------------------------------------------------------

HOMOPHONE_CASES = [
    # ------ chu: བཅུ (ten) vs ཆུ (water) ------
    ("chu", ["དགུ"], "བཅུ", "9 → 10 (counting sequence)"),
    ("chu", ["བརྒྱད"], "བཅུ", "8 → should expect 10 in counting ctx (weak)"),
    ("chu", ["ཐུང"], "ཆུ", "drink → water"),
    ("chu", ["འཐུང"], "ཆུ", "drink (honorific) → water"),
    ("chu", ["རྒྱ"], "ཆུ", "ocean context (rgya mtsho)"),
    ("chu", ["མིག"], "ཆུ", "eye → tears (mig chu)"),
    ("chu", ["ཁ"], "ཆུ", "mouth → saliva (kha chu)"),

    # ------ nga: ང (I) vs ལྔ (five) ------
    ("nga", ["བཞི"], "ལྔ", "4 → 5 (counting)"),
    ("nga", ["ཡིན"], "ང", "copula → I (nga yin)"),
    ("nga", ["རེད"], "ང", "factual → I"),
    ("nga", ["བྱེད"], "ང", "do → I"),

    # ------ dak/dag: བདག (self) vs དག (pure) ------
    ("dak", ["བདག"], "བདག", "self doubled (dak dak)"),  # edge case: might go to dg
    ("dak", ["རིག"], "བདག", "awareness → self (rigpé dak)"),
    ("dak", ["སེམས"], "བདག", "mind → self"),
    ("dag", ["སྣང"], "དག", "pure vision (nangdak)"),

    # ------ druk: དྲུག (six) vs འབྲུག (Bhutan/dragon) ------
    ("druk", ["ལྔ"], "དྲུག", "5 → 6"),
    ("druk", ["ལྷོ"], "འབྲུག", "south → Bhutan"),
    ("druk", ["རྒྱལ"], "འབྲུག", "royal → Bhutan (drukyul)"),

    # ------ choe: ཁྱོད (you, Bhutanese) vs ཆོས (dharma) ------
    ("choe", ["སངས"], "ཆོས", "Buddha → dharma (sangye choe)"),
    ("choe", ["རྒྱས"], "ཆོས", "expand → dharma"),
    ("choe", ["བླ"], "ཆོས", "lama → dharma"),
    ("choe", ["ཡིན"], "ཁྱོད", "is → you"),
    ("choe", ["བྱེད"], "ཁྱོད", "do → you"),

    # ------ me: མེ (fire) vs མེད (not-exist) ------
    ("me", ["ཡོད"], "མེད", "yöd → med (have/not-have)"),
    ("me", ["ཤེས"], "མེད", "know → not-know"),
    ("me", ["འབར"], "མེ", "burn → fire"),
    ("me", ["སྲེག"], "མེ", "burn → fire"),

    # ------ je: བྱེད (do/make) vs རྗེ (lord) ------
    ("je", ["རིན"], "རྗེ", "precious → lord (rinpoche je)"),
    ("je", ["བླ"], "རྗེ", "lama → lord"),
    ("je", ["ལས"], "བྱེད", "action → do"),
    ("je", ["འགྲུབ"], "བྱེད", "accomplish → do"),

    # ------ che: ཆེ (big) vs བྱེད (do) ------
    ("che", ["ཐུགས"], "ཆེ", "mind → great (thukjechhe)"),
    ("che", ["བཀའ"], "ཆེ", "speech → great (kadinchhe)"),

    # ------ gye: བརྒྱད (eight) vs རྒྱས (spread) ------
    ("gye", ["བདུན"], "བརྒྱད", "7 → 8"),
    ("gye", ["སངས"], "རྒྱས", "Buddha → spread (sangye)"),

    # ------ gu: དགུ (nine) vs སྐུ (body honorific) ------
    ("gu", ["བརྒྱད"], "དགུ", "8 → 9"),
    ("gu", ["ཆོས"], "སྐུ", "dharma → body (chökyi ku)"),

    # ------ dun: བདུན (seven) vs དོན (meaning) ------
    ("dun", ["དྲུག"], "བདུན", "6 → 7"),
    ("dun", ["ཆོས"], "དོན", "dharma → meaning"),

    # ------ shi: བཞི (four) vs འཆི (death) ------
    ("shi", ["གསུམ"], "བཞི", "3 → 4"),
    ("shi", ["སྐྱེ"], "འཆི", "birth → death"),

    # ------ la: ལ (particle) vs བླ (soul) ------
    ("la", ["ཆོས"], "ལ", "dharma + to (particle)"),
    ("la", ["སྲོག"], "བླ", "life → soul"),

    # ------ sum: གསུམ (three) ------
    ("sum", ["གཉིས"], "གསུམ", "2 → 3"),

    # ------ nyi: གཉིས (two) vs ཉི (sun) ------
    ("nyi", ["གཅིག"], "གཉིས", "1 → 2"),
    ("nyi", ["པད"], "ཉི", "lotus → sun (pé nyi den)"),
]


# ---------------------------------------------------------------------------
# Data loading (shared with training)
# ---------------------------------------------------------------------------

def load_checkpoint(path: Path) -> Tuple[LotsawaLM, Dict, Dict]:
    print(f"Loading checkpoint from {path}...")
    ckpt = torch.load(path, map_location="cpu", weights_only=False)
    cfg = ckpt["config"]
    char_vocab = ckpt["char_vocab"]
    tib_vocab = ckpt["tib_vocab"]
    model = LotsawaLM(
        n_chars=len(char_vocab),
        n_words=len(tib_vocab),
        char_dim=cfg["char_dim"],
        lstm_hidden=cfg["lstm_hidden"],
        lstm_layers=cfg["lstm_layers"],
        context_dim=cfg["context_dim"],
        mlp_hidden=cfg["mlp_hidden"],
        dropout=0.0,  # disable dropout for eval
        max_len=cfg["phonetic_max_len"],
    )
    model.load_state_dict(ckpt["model_state"])
    model.eval()
    return model, char_vocab, tib_vocab


class SQLiteBackend:
    """Wraps the production SQLite dict for baselines."""

    def __init__(self, db_path: Path):
        self.conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        self.cur = self.conn.cursor()

    def freq_lookup(self, phonetic: str, k: int = 10) -> List[Tuple[str, int]]:
        """Top-K Tibetan first-syllable candidates for a phonetic key.

        Deduplicates by first-syllable (multiple DB rows may map to the
        same syllable because of trailing-tsheg variants) and returns the
        highest-frequency occurrence for each unique syllable.
        """
        rows = self.cur.execute(
            "SELECT tibetan, frequency FROM phonetic_entries "
            "WHERE phonetic = ? ORDER BY frequency DESC LIMIT ?",
            (phonetic.lower(), k * 4),
        ).fetchall()
        best: Dict[str, int] = {}
        order: List[str] = []
        for tib, freq in rows:
            tib = tib.strip("་།༔")
            syll = tib.split("་")[0] if "་" in tib else tib
            if not syll:
                continue
            if syll not in best:
                best[syll] = freq
                order.append(syll)
            elif freq > best[syll]:
                best[syll] = freq
        results = [(s, best[s]) for s in order]
        results.sort(key=lambda x: -x[1])
        return results[:k]

    def bigram_candidates(self, prev_word: str) -> Dict[str, int]:
        """What words follow prev_word? Returns word → count."""
        rows = self.cur.execute(
            "SELECT word2, count FROM bigrams WHERE word1 = ? ORDER BY count DESC",
            (prev_word,),
        ).fetchall()
        return {w: c for w, c in rows}

    def trigram_candidates(self, prev_prev: str, prev: str) -> Dict[str, int]:
        key = f"{prev_prev}|{prev}"
        rows = self.cur.execute(
            "SELECT word, count FROM trigrams WHERE key = ? ORDER BY count DESC",
            (key,),
        ).fetchall()
        return {w: c for w, c in rows}

    def close(self):
        self.conn.close()


# ---------------------------------------------------------------------------
# Baselines
# ---------------------------------------------------------------------------

def baseline_freq_only(phonetic: str, context: List[str], db: SQLiteBackend,
                       k: int = 10) -> List[str]:
    """Ignore context; return top-K Tibetan by raw frequency."""
    candidates = db.freq_lookup(phonetic, k=k)
    return [w for w, _ in candidates]


def baseline_ngram_context(phonetic: str, context: List[str], db: SQLiteBackend,
                           k: int = 10) -> List[str]:
    """Dict + bigram rescoring. Approximates the production ContextEngine
    without the ML model.

    Scoring: for each candidate c with raw freq f,
        score(c) = log(1+f) + alpha * log(1 + bigram_count(prev, c))
                              + beta  * log(1 + trigram_count(prev_prev, prev, c))
    Alpha and beta are set so the n-gram signal dominates when present.
    """
    ALPHA = 3.0
    BETA = 4.0
    candidates = db.freq_lookup(phonetic, k=30)
    if not candidates:
        return []

    prev = context[-1] if len(context) >= 1 else None
    prev_prev = context[-2] if len(context) >= 2 else None

    bigram_c = db.bigram_candidates(prev) if prev else {}
    trigram_c = db.trigram_candidates(prev_prev, prev) if prev_prev and prev else {}

    scored = []
    for c, freq in candidates:
        score = math.log1p(freq)
        if c in bigram_c:
            score += ALPHA * math.log1p(bigram_c[c])
        if c in trigram_c:
            score += BETA * math.log1p(trigram_c[c])
        scored.append((c, score))

    scored.sort(key=lambda x: -x[1])
    return [c for c, _ in scored[:k]]


def model_predict(
    model: LotsawaLM,
    char_vocab: Dict[str, int],
    tib_vocab: Dict[str, int],
    idx_to_tib: Dict[int, str],
    phonetic: str,
    context: List[str],
    k: int = 10,
) -> List[str]:
    """Predict using the trained BiLSTM."""
    max_len = model.max_len
    phon_ids = encode_phonetic(phonetic.lower(), char_vocab, max_len)
    phon_t = torch.tensor([phon_ids], dtype=torch.long)

    prev = context[-1] if context else None
    ctx_idx = tib_vocab.get(prev, PAD_IDX) if prev else PAD_IDX
    ctx_t = torch.tensor([ctx_idx], dtype=torch.long)

    with torch.no_grad():
        logits = model(phon_t, ctx_t)
        probs = torch.softmax(logits, dim=1)
        topk = torch.topk(probs, k=min(k, probs.size(1)), dim=1)

    results = []
    for idx in topk.indices[0].tolist():
        if idx in (PAD_IDX, UNK_IDX):
            continue
        word = idx_to_tib.get(idx)
        if word:
            results.append(word)
    return results[:k]


def hybrid_predict(
    model: LotsawaLM,
    char_vocab: Dict[str, int],
    tib_vocab: Dict[str, int],
    idx_to_tib: Dict[int, str],
    phonetic: str,
    context: List[str],
    db: SQLiteBackend,
    k: int = 10,
    alpha_bigram: float = 0.30,
    beta_trigram: float = 0.20,
    gamma_dict: float = 0.10,
) -> List[str]:
    """Linear interpolation in probability space:

        P_hybrid(c) = (1 - a - b - g) * P_model(c)
                    + a * P_bigram(c | prev)
                    + b * P_trigram(c | prev_prev, prev)
                    + g * P_dict(c | phonetic)

    Candidates come from the union of model top-30 and dict top-30.
    Candidates not in a particular source have probability 0 there;
    the model probability is what carries rare-word coverage.
    """
    max_len = model.max_len
    phon_ids = encode_phonetic(phonetic.lower(), char_vocab, max_len)
    phon_t = torch.tensor([phon_ids], dtype=torch.long)
    prev = context[-1] if context else None
    ctx_idx = tib_vocab.get(prev, PAD_IDX) if prev else PAD_IDX
    ctx_t = torch.tensor([ctx_idx], dtype=torch.long)

    with torch.no_grad():
        logits = model(phon_t, ctx_t)
        probs = torch.softmax(logits, dim=1)[0]

    topk_vals, topk_idx = probs.topk(min(30, probs.size(0)))

    # Dict distribution normalized over the returned candidates
    dict_items = db.freq_lookup(phonetic, k=30)
    dict_total = sum(f for _, f in dict_items) or 1
    dict_probs: Dict[str, float] = {
        c: f / dict_total for c, f in dict_items
    }

    # Normalized n-gram distributions
    prev_prev = context[-2] if len(context) >= 2 else None
    bigram_c = db.bigram_candidates(prev) if prev else {}
    trigram_c = db.trigram_candidates(prev_prev, prev) if prev_prev and prev else {}
    bigram_total = sum(bigram_c.values()) or 1
    trigram_total = sum(trigram_c.values()) or 1
    bigram_probs = {w: c / bigram_total for w, c in bigram_c.items()}
    trigram_probs = {w: c / trigram_total for w, c in trigram_c.items()}

    # Candidate set: model top-30 + dict top-30
    candidates = set()
    model_probs: Dict[str, float] = {}
    for idx, p in zip(topk_idx.tolist(), topk_vals.tolist()):
        if idx in (PAD_IDX, UNK_IDX):
            continue
        word = idx_to_tib.get(idx)
        if word:
            candidates.add(word)
            model_probs[word] = p
    for word in dict_probs:
        candidates.add(word)
        if word not in model_probs:
            idx = tib_vocab.get(word)
            if idx is not None and idx not in (PAD_IDX, UNK_IDX):
                model_probs[word] = float(probs[idx])
            else:
                model_probs[word] = 0.0

    if not candidates:
        return []

    w_model = max(0.0, 1.0 - alpha_bigram - beta_trigram - gamma_dict)

    scored = []
    for c in candidates:
        p = (
            w_model * model_probs.get(c, 0.0)
            + alpha_bigram * bigram_probs.get(c, 0.0)
            + beta_trigram * trigram_probs.get(c, 0.0)
            + gamma_dict * dict_probs.get(c, 0.0)
        )
        scored.append((c, p))

    scored.sort(key=lambda x: -x[1])
    return [c for c, _ in scored[:k]]


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------

def evaluate_homophones(
    cases: List[Tuple[str, List[str], str, str]],
    predict_fn,
    label: str,
) -> Dict:
    """Run a list of homophone cases through a predictor, return metrics."""
    correct_top1 = 0
    correct_top5 = 0
    details = []

    for phonetic, context, expected, desc in cases:
        preds = predict_fn(phonetic, context)
        top1 = preds[0] if preds else None
        is_top1 = top1 == expected
        is_top5 = expected in preds[:5]
        correct_top1 += int(is_top1)
        correct_top5 += int(is_top5)
        details.append({
            "phonetic": phonetic,
            "context": context,
            "expected": expected,
            "description": desc,
            "top1": top1,
            "top5": preds[:5],
            "correct_top1": is_top1,
            "correct_top5": is_top5,
        })

    n = len(cases)
    return {
        "label": label,
        "n_cases": n,
        "top1_acc": correct_top1 / n,
        "top5_acc": correct_top5 / n,
        "details": details,
    }


def evaluate_heldout(
    model: LotsawaLM,
    char_vocab: Dict[str, int],
    tib_vocab: Dict[str, int],
    idx_to_tib: Dict[int, str],
    db: SQLiteBackend,
    test_sentences: List,
    max_cases: int = 5000,
) -> Dict:
    """Run baselines + model on a held-out set of (phon, context, target) tuples
    extracted from aligned sentences."""
    # Extract triples from sentences
    triples = []
    for sent in test_sentences:
        for i, (phon, tib_group) in enumerate(sent):
            target = tib_group[0]
            context = []
            if i > 0:
                context.append(sent[i - 1][1][0])
            if i > 1:
                context.insert(0, sent[i - 2][1][0])
            triples.append((phon, context, target))
            if len(triples) >= max_cases:
                break
        if len(triples) >= max_cases:
            break

    print(f"  Running {len(triples)} held-out queries per system...")

    methods = {
        "freq_only":     lambda p, c: baseline_freq_only(p, c, db),
        "ngram_context": lambda p, c: baseline_ngram_context(p, c, db),
        "model_only":    lambda p, c: model_predict(
                             model, char_vocab, tib_vocab, idx_to_tib, p, c),
        "hybrid":        lambda p, c: hybrid_predict(
                             model, char_vocab, tib_vocab, idx_to_tib, p, c, db),
    }

    results = {}
    for name, fn in methods.items():
        top1 = 0
        top5 = 0
        top10 = 0
        missing = 0
        t0 = time.time()
        for phon, ctx, tgt in triples:
            preds = fn(phon, ctx)
            if not preds:
                missing += 1
                continue
            if preds[0] == tgt:
                top1 += 1
            if tgt in preds[:5]:
                top5 += 1
            if tgt in preds[:10]:
                top10 += 1
        elapsed = time.time() - t0
        n = len(triples)
        results[name] = {
            "n": n,
            "top1": top1 / n,
            "top5": top5 / n,
            "top10": top10 / n,
            "no_prediction": missing / n,
            "total_time_sec": elapsed,
            "ms_per_query": 1000 * elapsed / n,
        }
        print(f"    {name:15s}  top-1 {results[name]['top1']*100:.2f}%  "
              f"top-5 {results[name]['top5']*100:.2f}%  "
              f"top-10 {results[name]['top10']*100:.2f}%  "
              f"({results[name]['ms_per_query']:.2f} ms/q)")
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=str,
                        default=str(LOTSAWA_CORE_DIR / "lotsawa_lm.pt"))
    parser.add_argument("--db", type=str,
                        default=str(LOTSAWA_CORE_DIR / "lotsawa.db"))
    parser.add_argument("--output", type=str,
                        default=str(LOTSAWA_CORE_DIR / "results.json"))
    parser.add_argument("--max-heldout", type=int, default=5000,
                        help="Max held-out cases to evaluate (for speed)")
    parser.add_argument("--quick", action="store_true",
                        help="Skip held-out eval, only run homophones")
    args = parser.parse_args()

    # Load model
    model, char_vocab, tib_vocab = load_checkpoint(Path(args.checkpoint))
    idx_to_tib = {v: k for k, v in tib_vocab.items()}
    print(f"  n_params: {model.count_parameters():,}")
    print(f"  vocab: {len(tib_vocab)} words, {len(char_vocab)} chars")

    # Open DB
    db = SQLiteBackend(Path(args.db))

    # --- Homophone suite ---
    print("\n=== Homophone disambiguation suite ===")
    print(f"  Cases: {len(HOMOPHONE_CASES)}")

    predictors = {
        "freq_only":     lambda p, c: baseline_freq_only(p, c, db),
        "ngram_context": lambda p, c: baseline_ngram_context(p, c, db),
        "model_only":    lambda p, c: model_predict(
                             model, char_vocab, tib_vocab, idx_to_tib, p, c),
        "hybrid":        lambda p, c: hybrid_predict(
                             model, char_vocab, tib_vocab, idx_to_tib, p, c, db),
    }

    homophone_results = {}
    for name, fn in predictors.items():
        homophone_results[name] = evaluate_homophones(HOMOPHONE_CASES, fn, name)
        print(f"  {name:15s}  top-1 {homophone_results[name]['top1_acc']*100:5.2f}%  "
              f"top-5 {homophone_results[name]['top5_acc']*100:5.2f}%")

    # --- Held-out HF sentence eval ---
    heldout_results = None
    if not args.quick:
        print("\n=== Held-out sentence evaluation ===")
        from train_lotsawa_model import load_hf_dataset
        print("  Reloading sentences for held-out split (same seed)...")
        sentences = load_hf_dataset()
        random.seed(42)
        random.shuffle(sentences)
        n_test = int(len(sentences) * 0.10)
        test_sentences = sentences[-n_test:]
        print(f"  Test sentences: {len(test_sentences)}")

        heldout_results = evaluate_heldout(
            model, char_vocab, tib_vocab, idx_to_tib,
            db, test_sentences, max_cases=args.max_heldout,
        )

    # --- Save results ---
    all_results = {
        "homophone_suite": homophone_results,
        "heldout": heldout_results,
        "n_params": model.count_parameters(),
        "vocab_size": len(tib_vocab),
        "n_homophone_cases": len(HOMOPHONE_CASES),
    }
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(all_results, f, ensure_ascii=False, indent=2)
    print(f"\nResults saved → {args.output}")

    db.close()


if __name__ == "__main__":
    main()
