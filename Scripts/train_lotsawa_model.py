#!/usr/bin/env python3
"""Full-fledged training for Lotsawa Keyboard language model.

Architecture: char-level BiLSTM encoder + context word embedding + MLP classifier.
Target: ~3-4 MB model, well under the 5 MB iOS keyboard-extension budget.

Training data: parallel (Tibetan, phonetic) sentence pairs from
billingsmoore/tibetan-phonetic-transliteration-dataset (98K classical sentences),
plus word-level pairs from word_frequency.json for rare/short items.

Train/val/test split: 80/10/10 with fixed seed for reproducibility.
Training: Adam + cosine LR schedule, early stopping on val loss.

Outputs (in LotsawaCore/Sources/LotsawaCore/):
    lotsawa_lm.pt          - PyTorch checkpoint (best val loss)
    ml_vocab.json          - phonetic char vocab + Tibetan word vocab
    training_metrics.json  - per-epoch loss/accuracy, hyperparameters, final test scores
"""

import argparse
import json
import math
import os
import random
import re
import sys
import time
from collections import Counter
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset, Subset

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEFAULT_CONFIG = {
    # Architecture
    "char_dim": 32,
    "lstm_hidden": 64,
    "lstm_layers": 1,
    "context_dim": 32,
    "mlp_hidden": 128,
    "dropout": 0.3,
    "phonetic_max_len": 20,
    "tibetan_vocab_size": 5000,

    # Training
    "batch_size": 512,
    "epochs": 30,
    "lr": 1e-3,
    "weight_decay": 1e-5,
    "early_stop_patience": 5,
    "grad_clip": 1.0,

    # Data
    "train_frac": 0.80,
    "val_frac": 0.10,
    "min_char_freq": 2,
    "seed": 42,
}

PAD_TOKEN = "<PAD>"
UNK_TOKEN = "<UNK>"
PAD_IDX = 0
UNK_IDX = 1

# Regex for splitting Tibetan text into syllable tokens. Tsheg ་, shad ། ༑,
# ter-tsheg ༔, whitespace, and Western punctuation all act as boundaries.
_TIBETAN_SPLIT = re.compile(r"[་།༔༑༈༉\s]+")

# Regex for splitting phonetic text into word tokens. Space, pipe, slashes,
# western punctuation.
_PHONETIC_SPLIT = re.compile(r"[\s|/\\()\[\]{}]+")
_PHONETIC_STRIP = ".,!?;:\"'`"


# ---------------------------------------------------------------------------
# Data loading and tokenization
# ---------------------------------------------------------------------------

def tokenize_tibetan(text: str) -> List[str]:
    """Split Tibetan text into syllable/word tokens."""
    tokens = _TIBETAN_SPLIT.split(text.strip())
    return [t for t in tokens if t]


def tokenize_phonetic(text: str) -> List[str]:
    """Split phonetic text into word tokens."""
    tokens = _PHONETIC_SPLIT.split(text.strip().lower())
    clean = []
    for t in tokens:
        t = t.strip(_PHONETIC_STRIP)
        if t and not t.isdigit():
            clean.append(t)
    return clean


def dp_align(
    phon: List[str],
    tib: List[str],
    max_k: int = 3,
) -> Optional[List[Tuple[str, List[str]]]]:
    """Align phonetic tokens to Tibetan syllables with DP.

    Phonetic almost always has fewer tokens than Tibetan because compound
    phonetic words ("yowa", "trulpé") collapse 2+ Tibetan syllables. Each
    phonetic token consumes k in {1..max_k} Tibetan syllables, minimizing
    total cost (prefer k=1, penalize larger k).

    Returns list of (phonetic_token, [tibetan_syllables]) or None if
    infeasible (e.g., too many extras to distribute).
    """
    N, M = len(phon), len(tib)
    if N == 0 or M == 0:
        return None
    if N > M:
        return None  # Phonetic having MORE tokens is unusual; skip
    if M > N * max_k:
        return None  # Too many Tibetan syllables to distribute

    INF = float("inf")
    dp = [[INF] * (M + 1) for _ in range(N + 1)]
    parent = [[0] * (M + 1) for _ in range(N + 1)]
    dp[0][0] = 0.0

    for i in range(N):
        for j in range(M):
            if dp[i][j] == INF:
                continue
            for k in range(1, min(max_k, M - j) + 1):
                cost = (k - 1) ** 2  # prefer 1-to-1 (cost 0), then 1-to-2 (cost 1), then 1-to-3 (cost 4)
                nj = j + k
                nc = dp[i][j] + cost
                if nc < dp[i + 1][nj]:
                    dp[i + 1][nj] = nc
                    parent[i + 1][nj] = k

    if dp[N][M] == INF:
        return None

    # Backtrack
    result = []
    i, j = N, M
    while i > 0:
        k = parent[i][j]
        result.append((phon[i - 1], tib[j - k:j]))
        i -= 1
        j -= k
    result.reverse()
    return result


def load_hf_dataset() -> List[List[Tuple[str, List[str]]]]:
    """Load parallel (phonetic, [tibetan_syllables]) alignments from the
    Hugging Face dataset, using DP alignment to handle multi-syllable
    phonetic compounds. Returns a list of aligned sentences, where each
    sentence is a list of (phonetic_token, [tibetan_syllables]) pairs."""
    print("Loading Hugging Face dataset...")

    from datasets import load_dataset
    ds = load_dataset("billingsmoore/tibetan-phonetic-transliteration-dataset")
    train = ds["train"]
    columns = train.column_names  # first row gets loaded as headers
    tib_col, phon_col = columns[0], columns[1]

    sentences = []
    stats = {"kept_11": 0, "kept_dp": 0, "dropped_empty": 0, "dropped_dp_fail": 0, "dropped_phon_longer": 0}

    # Recover the first row eaten by HF as column names
    rows_iter = [(tib_col, phon_col)] + [(train[i][tib_col], train[i][phon_col]) for i in range(len(train))]

    for tib_text, phon_text in rows_iter:
        tib_tokens = tokenize_tibetan(tib_text)
        phon_tokens = tokenize_phonetic(phon_text)
        if not tib_tokens or not phon_tokens:
            stats["dropped_empty"] += 1
            continue

        if len(phon_tokens) > len(tib_tokens):
            stats["dropped_phon_longer"] += 1
            continue

        if len(phon_tokens) == len(tib_tokens):
            aligned = [(p, [t]) for p, t in zip(phon_tokens, tib_tokens)]
            sentences.append(aligned)
            stats["kept_11"] += 1
            continue

        aligned = dp_align(phon_tokens, tib_tokens, max_k=3)
        if aligned is None:
            stats["dropped_dp_fail"] += 1
            continue
        sentences.append(aligned)
        stats["kept_dp"] += 1

    total = sum(stats.values())
    kept = stats["kept_11"] + stats["kept_dp"]
    print(f"  Total rows processed: {total}")
    print(f"  Kept 1-to-1 exact: {stats['kept_11']}")
    print(f"  Kept via DP align: {stats['kept_dp']}")
    print(f"  Dropped DP infeasible: {stats['dropped_dp_fail']}")
    print(f"  Dropped phon > tib: {stats['dropped_phon_longer']}")
    print(f"  Dropped empty: {stats['dropped_empty']}")
    print(f"  Yield: {kept} / {total} = {100*kept/max(total,1):.1f}%")
    return sentences


def load_word_frequency() -> List[Tuple[str, str, int]]:
    """Load (phonetic, tibetan, frequency) from word_frequency.json.
    Used as supplementary non-contextual data."""
    path = LOTSAWA_CORE_DIR / "word_frequency.json"
    if not path.exists():
        print(f"  Warning: {path} not found, skipping")
        return []

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    triples = []
    for phonetic, entry in data.items():
        phonetic = phonetic.strip().lower()
        if not phonetic:
            continue
        for match in entry.get("matches", []):
            tib = match.get("t", "").strip()
            freq = match.get("f", 0)
            if tib and freq > 0:
                # Use only the first syllable of the Tibetan word
                tib_tokens = tokenize_tibetan(tib)
                if tib_tokens:
                    triples.append((phonetic, tib_tokens[0], freq))
    return triples


def load_bigram_pairs() -> List[Tuple[str, str, int]]:
    """Load (context_word, target_word, count) bigrams from context_model.json.
    These are Tibetan-only word pairs that do not need alignment. We'll
    look up phonetic spellings for targets via the SQLite reverse_lookup
    table at pair-construction time."""
    path = LOTSAWA_CORE_DIR / "context_model.json"
    if not path.exists():
        print(f"  Warning: {path} not found, skipping")
        return []

    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    bigrams = data.get("bigrams", {})
    pairs = []
    for w1, followers in bigrams.items():
        for w2, count in followers.items():
            if count >= 2:
                pairs.append((w1, w2, count))
    return pairs


def load_reverse_lookup() -> Dict[str, str]:
    """Load SQLite reverse_lookup table: tibetan → phonetic."""
    import sqlite3
    path = LOTSAWA_CORE_DIR / "lotsawa.db"
    if not path.exists():
        print(f"  Warning: {path} not found, skipping")
        return {}

    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    cur = conn.cursor()
    result = {}
    for tib, phon in cur.execute("SELECT tibetan, phonetic FROM reverse_lookup"):
        if tib and phon and " " not in phon:
            result[tib] = phon.lower()
    conn.close()
    return result


# ---------------------------------------------------------------------------
# Vocabulary building
# ---------------------------------------------------------------------------

def build_vocabularies(
    sentences: List[List[Tuple[str, List[str]]]],
    word_freq: List[Tuple[str, str, int]],
    bigrams: List[Tuple[str, str, int]],
    max_len: int,
    target_vocab_size: int,
    min_char_freq: int,
) -> Tuple[Dict[str, int], Dict[str, int]]:
    """Build phonetic char vocab and Tibetan word vocab.

    Phonetic vocab: all characters appearing in ≥ min_char_freq training tokens.
    Tibetan vocab: top target_vocab_size-2 words by frequency (reserve PAD, UNK).
    """
    char_counts = Counter()
    tib_counts = Counter()

    # From aligned sentences: count phonetic chars and tibetan first syllables
    for sent in sentences:
        for phon, tib_group in sent:
            for ch in phon[:max_len]:
                char_counts[ch] += 1
            for t in tib_group:
                tib_counts[t] += 1

    # From word_freq: supplementary
    for phon, tib, freq in word_freq:
        for ch in phon[:max_len]:
            char_counts[ch] += freq
        tib_counts[tib] += freq

    # From bigrams: both sides count as Tibetan tokens
    for w1, w2, count in bigrams:
        tib_counts[w1] += count
        tib_counts[w2] += count

    # Char vocab: PAD=0, UNK=1, then sorted chars meeting threshold
    char_vocab = {PAD_TOKEN: PAD_IDX, UNK_TOKEN: UNK_IDX}
    for ch, cnt in sorted(char_counts.items(), key=lambda kv: (-kv[1], kv[0])):
        if cnt >= min_char_freq and ch not in char_vocab:
            char_vocab[ch] = len(char_vocab)

    # Tibetan vocab: PAD=0, UNK=1, then top-N by frequency
    tib_vocab = {PAD_TOKEN: PAD_IDX, UNK_TOKEN: UNK_IDX}
    top = tib_counts.most_common(target_vocab_size - 2)
    for word, _ in top:
        tib_vocab[word] = len(tib_vocab)

    print(f"  Phonetic char vocab: {len(char_vocab)} chars")
    print(f"  Tibetan word vocab:  {len(tib_vocab)} words (target {target_vocab_size})")
    return char_vocab, tib_vocab


def encode_phonetic(text: str, char_vocab: Dict[str, int], max_len: int) -> List[int]:
    """Encode phonetic string as padded character indices."""
    ids = []
    for ch in text[:max_len]:
        ids.append(char_vocab.get(ch, UNK_IDX))
    while len(ids) < max_len:
        ids.append(PAD_IDX)
    return ids


# ---------------------------------------------------------------------------
# Training pair construction
# ---------------------------------------------------------------------------

def build_training_pairs(
    sentences: List[List[Tuple[str, List[str]]]],
    word_freq: List[Tuple[str, str, int]],
    bigrams: List[Tuple[str, str, int]],
    reverse_lookup: Dict[str, str],
    char_vocab: Dict[str, int],
    tib_vocab: Dict[str, int],
    max_len: int,
) -> Tuple[List[Tuple[List[int], int, int, float]], Dict[str, int]]:
    """Emit (phonetic_ids, context_id, target_id, weight) tuples.

    Sources:
      1. Aligned sentences: phon_i → first syllable of tib_group_i, context
         is the first syllable of tib_group_{i-1}. Weight 1.0.
      2. word_freq: (phonetic, PAD context, tibetan, log(1+freq)).
      3. bigrams from context_model: for each (w1 → w2, count), look up
         phonetic for w2 via reverse_lookup and emit
         (phonetic_of_w2, w1, w2, log(1+count)).
    """
    pairs = []
    stats = {"sentence": 0, "wordfreq": 0, "bigram": 0, "bigram_skip_no_phon": 0, "bigram_skip_vocab": 0}

    # --- Source 1: sentence-aligned pairs ---
    for sent in sentences:
        for i, (phon, tib_group) in enumerate(sent):
            target_syll = tib_group[0]
            target_id = tib_vocab.get(target_syll, UNK_IDX)
            if target_id == UNK_IDX:
                continue
            if i == 0:
                context_id = PAD_IDX
            else:
                prev_group = sent[i - 1][1]
                prev_syll = prev_group[0]
                context_id = tib_vocab.get(prev_syll, UNK_IDX)
            phon_ids = encode_phonetic(phon, char_vocab, max_len)
            pairs.append((phon_ids, context_id, target_id, 1.0))
            stats["sentence"] += 1

    # --- Source 2: word frequency (no context) ---
    for phon, tib, freq in word_freq:
        target_id = tib_vocab.get(tib, UNK_IDX)
        if target_id == UNK_IDX:
            continue
        weight = max(1.0, math.log1p(freq))
        phon_ids = encode_phonetic(phon, char_vocab, max_len)
        pairs.append((phon_ids, PAD_IDX, target_id, weight))
        stats["wordfreq"] += 1

    # --- Source 3: bigrams with phonetic via reverse_lookup ---
    for w1, w2, count in bigrams:
        target_id = tib_vocab.get(w2, UNK_IDX)
        if target_id == UNK_IDX:
            stats["bigram_skip_vocab"] += 1
            continue
        phon = reverse_lookup.get(w2)
        if phon is None:
            stats["bigram_skip_no_phon"] += 1
            continue
        context_id = tib_vocab.get(w1, UNK_IDX)
        weight = max(1.0, math.log1p(count))
        phon_ids = encode_phonetic(phon, char_vocab, max_len)
        pairs.append((phon_ids, context_id, target_id, weight))
        stats["bigram"] += 1

    return pairs, stats


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

class LotsawaDataset(Dataset):
    def __init__(self, pairs: List[Tuple[List[int], int, int, float]]):
        self.phonetic = torch.tensor([p[0] for p in pairs], dtype=torch.long)
        self.context = torch.tensor([p[1] for p in pairs], dtype=torch.long)
        self.target = torch.tensor([p[2] for p in pairs], dtype=torch.long)
        self.weight = torch.tensor([p[3] for p in pairs], dtype=torch.float32)

    def __len__(self):
        return len(self.target)

    def __getitem__(self, idx):
        return (
            self.phonetic[idx],
            self.context[idx],
            self.target[idx],
            self.weight[idx],
        )


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------

class LotsawaLM(nn.Module):
    """Char-level BiLSTM encoder + context word embedding + MLP classifier.

    Designed for CoreML neuralnetwork-backend compatibility:
    - Fixed max_len (no packed sequences)
    - Simple mean pooling over LSTM output with mask
    - Standard nn.LSTM (supported by coremltools)
    """

    def __init__(
        self,
        n_chars: int,
        n_words: int,
        char_dim: int = 32,
        lstm_hidden: int = 64,
        lstm_layers: int = 1,
        context_dim: int = 32,
        mlp_hidden: int = 128,
        dropout: float = 0.3,
        max_len: int = 20,
    ):
        super().__init__()
        self.max_len = max_len
        self.n_words = n_words
        self.lstm_hidden = lstm_hidden
        self.lstm_layers = lstm_layers

        # Phonetic char encoder
        self.char_embed = nn.Embedding(n_chars, char_dim, padding_idx=PAD_IDX)
        self.lstm = nn.LSTM(
            input_size=char_dim,
            hidden_size=lstm_hidden,
            num_layers=lstm_layers,
            batch_first=True,
            bidirectional=True,
            dropout=dropout if lstm_layers > 1 else 0.0,
        )
        phonetic_out_dim = lstm_hidden * 2

        # Context word encoder
        self.context_embed = nn.Embedding(n_words, context_dim, padding_idx=PAD_IDX)

        # Classifier
        self.fc1 = nn.Linear(phonetic_out_dim + context_dim, mlp_hidden)
        self.dropout = nn.Dropout(dropout)
        self.fc2 = nn.Linear(mlp_hidden, n_words)

    def forward(self, phonetic_ids: torch.Tensor, context_id: torch.Tensor) -> torch.Tensor:
        # phonetic_ids: (B, L), int
        # context_id:   (B,) or (B, 1), int
        if context_id.dim() == 2:
            context_id = context_id.squeeze(-1)

        B = phonetic_ids.size(0)

        # Encode phonetic: (B, L, C) → BiLSTM → (B, L, 2H)
        ph = self.char_embed(phonetic_ids)
        lstm_out, _ = self.lstm(ph)

        # Masked mean pool (treat PAD_IDX=0 as mask)
        mask = (phonetic_ids != PAD_IDX).float().unsqueeze(-1)  # (B, L, 1)
        ph_sum = (lstm_out * mask).sum(dim=1)
        ph_cnt = mask.sum(dim=1).clamp(min=1.0)
        ph_vec = ph_sum / ph_cnt

        # Context embedding
        ctx_vec = self.context_embed(context_id)

        # Concat and classify
        combined = torch.cat([ph_vec, ctx_vec], dim=1)
        h = F.relu(self.fc1(combined))
        h = self.dropout(h)
        logits = self.fc2(h)
        return logits

    def count_parameters(self) -> int:
        return sum(p.numel() for p in self.parameters() if p.requires_grad)


# ---------------------------------------------------------------------------
# Training
# ---------------------------------------------------------------------------

def train_one_epoch(
    model: LotsawaLM,
    loader: DataLoader,
    optimizer: optim.Optimizer,
    device: torch.device,
    grad_clip: float,
) -> Tuple[float, float]:
    model.train()
    total_loss = 0.0
    total_samples = 0
    correct = 0
    criterion = nn.CrossEntropyLoss(reduction="none")

    for phonetic, context, target, weight in loader:
        phonetic = phonetic.to(device)
        context = context.to(device)
        target = target.to(device)
        weight = weight.to(device)

        optimizer.zero_grad()
        logits = model(phonetic, context)
        per_sample = criterion(logits, target)
        loss = (per_sample * weight).mean()
        loss.backward()
        if grad_clip > 0:
            torch.nn.utils.clip_grad_norm_(model.parameters(), grad_clip)
        optimizer.step()

        bs = target.size(0)
        total_loss += loss.item() * bs
        preds = logits.argmax(dim=1)
        correct += (preds == target).sum().item()
        total_samples += bs

    return total_loss / max(total_samples, 1), correct / max(total_samples, 1)


@torch.no_grad()
def evaluate(
    model: LotsawaLM,
    loader: DataLoader,
    device: torch.device,
) -> Dict[str, float]:
    model.eval()
    total_loss = 0.0
    total_samples = 0
    top1 = 0
    top5 = 0
    top10 = 0
    criterion = nn.CrossEntropyLoss(reduction="none")

    for phonetic, context, target, weight in loader:
        phonetic = phonetic.to(device)
        context = context.to(device)
        target = target.to(device)
        weight = weight.to(device)

        logits = model(phonetic, context)
        per_sample = criterion(logits, target)
        loss = (per_sample * weight).mean()

        bs = target.size(0)
        total_loss += loss.item() * bs
        total_samples += bs

        # Top-K accuracy
        topk = logits.topk(10, dim=1).indices  # (B, 10)
        tgt_expanded = target.unsqueeze(1)
        top1 += (topk[:, :1] == tgt_expanded).any(dim=1).sum().item()
        top5 += (topk[:, :5] == tgt_expanded).any(dim=1).sum().item()
        top10 += (topk[:, :10] == tgt_expanded).any(dim=1).sum().item()

    return {
        "loss": total_loss / max(total_samples, 1),
        "top1": top1 / max(total_samples, 1),
        "top5": top5 / max(total_samples, 1),
        "top10": top10 / max(total_samples, 1),
        "n": total_samples,
    }


def set_seed(seed: int) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def pick_device() -> torch.device:
    """Prefer MPS (Apple Silicon), fall back to CUDA, then CPU."""
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Train Lotsawa LM")
    parser.add_argument("--smoke", action="store_true",
                        help="Quick smoke test: 1 epoch on 5K pairs")
    parser.add_argument("--epochs", type=int, default=None)
    parser.add_argument("--batch-size", type=int, default=None)
    parser.add_argument("--lr", type=float, default=None)
    parser.add_argument("--vocab-size", type=int, default=None)
    parser.add_argument("--output-dir", type=str, default=str(LOTSAWA_CORE_DIR))
    parser.add_argument("--device", type=str, default=None,
                        choices=["cpu", "mps", "cuda"])
    args = parser.parse_args()

    cfg = dict(DEFAULT_CONFIG)
    if args.epochs is not None:
        cfg["epochs"] = args.epochs
    if args.batch_size is not None:
        cfg["batch_size"] = args.batch_size
    if args.lr is not None:
        cfg["lr"] = args.lr
    if args.vocab_size is not None:
        cfg["tibetan_vocab_size"] = args.vocab_size
    if args.smoke:
        cfg["epochs"] = 1
        cfg["batch_size"] = 256

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    set_seed(cfg["seed"])

    print("=" * 70)
    print("Lotsawa LM Training")
    print("=" * 70)
    print(f"Config: {json.dumps(cfg, indent=2)}")

    # --- Load data ---
    print("\n[1/6] Loading data...")
    sentences = load_hf_dataset()
    print("  Loading word_frequency.json...")
    word_freq = load_word_frequency()
    print(f"  Word-level entries: {len(word_freq)}")
    print("  Loading context_model.json bigrams...")
    bigrams = load_bigram_pairs()
    print(f"  Bigram pairs: {len(bigrams)}")
    print("  Loading reverse_lookup from SQLite...")
    reverse_lookup = load_reverse_lookup()
    print(f"  Reverse lookup entries: {len(reverse_lookup)}")

    if args.smoke:
        # Use only a small slice for smoke testing
        sentences = sentences[:2000]
        word_freq = word_freq[:500]
        bigrams = bigrams[:2000]
        print(f"  SMOKE TEST: truncated to {len(sentences)} sentences, "
              f"{len(word_freq)} words, {len(bigrams)} bigrams")

    # --- Build vocab ---
    print("\n[2/6] Building vocabularies...")
    char_vocab, tib_vocab = build_vocabularies(
        sentences,
        word_freq,
        bigrams,
        max_len=cfg["phonetic_max_len"],
        target_vocab_size=cfg["tibetan_vocab_size"],
        min_char_freq=cfg["min_char_freq"],
    )

    # --- Build training pairs ---
    print("\n[3/6] Building training pairs...")
    all_pairs, pair_stats = build_training_pairs(
        sentences, word_freq, bigrams, reverse_lookup,
        char_vocab, tib_vocab, cfg["phonetic_max_len"],
    )
    print(f"  Total pairs: {len(all_pairs)}")
    for k, v in pair_stats.items():
        print(f"    {k}: {v}")

    # Shuffle deterministically then split
    rng = random.Random(cfg["seed"])
    rng.shuffle(all_pairs)

    n = len(all_pairs)
    n_train = int(n * cfg["train_frac"])
    n_val = int(n * cfg["val_frac"])
    train_pairs = all_pairs[:n_train]
    val_pairs = all_pairs[n_train:n_train + n_val]
    test_pairs = all_pairs[n_train + n_val:]
    print(f"  Split: train={len(train_pairs)}  val={len(val_pairs)}  test={len(test_pairs)}")

    train_ds = LotsawaDataset(train_pairs)
    val_ds = LotsawaDataset(val_pairs)
    test_ds = LotsawaDataset(test_pairs)

    train_loader = DataLoader(train_ds, batch_size=cfg["batch_size"], shuffle=True, num_workers=0)
    val_loader = DataLoader(val_ds, batch_size=cfg["batch_size"], shuffle=False, num_workers=0)
    test_loader = DataLoader(test_ds, batch_size=cfg["batch_size"], shuffle=False, num_workers=0)

    # --- Build model ---
    print("\n[4/6] Building model...")
    if args.device:
        device = torch.device(args.device)
    else:
        device = pick_device()
    print(f"  Device: {device}")

    model = LotsawaLM(
        n_chars=len(char_vocab),
        n_words=len(tib_vocab),
        char_dim=cfg["char_dim"],
        lstm_hidden=cfg["lstm_hidden"],
        lstm_layers=cfg["lstm_layers"],
        context_dim=cfg["context_dim"],
        mlp_hidden=cfg["mlp_hidden"],
        dropout=cfg["dropout"],
        max_len=cfg["phonetic_max_len"],
    ).to(device)

    n_params = model.count_parameters()
    size_mb = n_params * 4 / 1024 / 1024
    print(f"  Parameters: {n_params:,}")
    print(f"  Estimated float32 size: {size_mb:.2f} MB")

    optimizer = optim.Adam(
        model.parameters(),
        lr=cfg["lr"],
        weight_decay=cfg["weight_decay"],
    )
    scheduler = optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=cfg["epochs"])

    # --- Train ---
    print("\n[5/6] Training...")
    best_val_loss = float("inf")
    patience_count = 0
    history = []
    best_state = None
    t0 = time.time()

    for epoch in range(1, cfg["epochs"] + 1):
        ep_start = time.time()
        train_loss, train_acc = train_one_epoch(
            model, train_loader, optimizer, device, cfg["grad_clip"]
        )
        val_metrics = evaluate(model, val_loader, device)
        scheduler.step()
        ep_time = time.time() - ep_start

        history.append({
            "epoch": epoch,
            "train_loss": train_loss,
            "train_acc": train_acc,
            "val_loss": val_metrics["loss"],
            "val_top1": val_metrics["top1"],
            "val_top5": val_metrics["top5"],
            "val_top10": val_metrics["top10"],
            "lr": scheduler.get_last_lr()[0],
            "time_sec": ep_time,
        })

        print(
            f"  Epoch {epoch:3d}/{cfg['epochs']} "
            f"train_loss={train_loss:.4f} train_acc={train_acc:.4f} "
            f"val_loss={val_metrics['loss']:.4f} val_top1={val_metrics['top1']:.4f} "
            f"val_top5={val_metrics['top5']:.4f} "
            f"lr={scheduler.get_last_lr()[0]:.2e} ({ep_time:.1f}s)"
        )

        if val_metrics["loss"] < best_val_loss - 1e-5:
            best_val_loss = val_metrics["loss"]
            patience_count = 0
            best_state = {
                "epoch": epoch,
                "model_state": {k: v.cpu().clone() for k, v in model.state_dict().items()},
                "val_metrics": val_metrics,
            }
        else:
            patience_count += 1
            if patience_count >= cfg["early_stop_patience"]:
                print(f"  Early stopping at epoch {epoch} (patience {cfg['early_stop_patience']})")
                break

    total_time = time.time() - t0
    print(f"  Total training time: {total_time:.1f}s")

    # Restore best model
    if best_state is not None:
        model.load_state_dict(best_state["model_state"])
        model.to(device)
        print(f"  Restored best checkpoint from epoch {best_state['epoch']}")

    # --- Final evaluation on test set ---
    print("\n[6/6] Evaluating on test set...")
    test_metrics = evaluate(model, test_loader, device)
    print(f"  Test loss:   {test_metrics['loss']:.4f}")
    print(f"  Test top-1:  {test_metrics['top1']:.4f}")
    print(f"  Test top-5:  {test_metrics['top5']:.4f}")
    print(f"  Test top-10: {test_metrics['top10']:.4f}")
    print(f"  Test n:      {test_metrics['n']}")

    # --- Save artifacts ---
    print("\nSaving artifacts...")

    ckpt_path = output_dir / "lotsawa_lm.pt"
    torch.save({
        "model_state": {k: v.cpu() for k, v in model.state_dict().items()},
        "config": cfg,
        "char_vocab": char_vocab,
        "tib_vocab": tib_vocab,
        "n_params": n_params,
    }, ckpt_path)
    print(f"  Checkpoint → {ckpt_path}  ({ckpt_path.stat().st_size / 1024 / 1024:.2f} MB)")

    vocab_path = output_dir / "ml_vocab.json"
    idx_to_tibetan = {v: k for k, v in tib_vocab.items()}
    vocab_data = {
        "phonetic_char_vocab": char_vocab,
        "tibetan_word_vocab": tib_vocab,
        "tibetan_idx_to_word": {str(k): v for k, v in idx_to_tibetan.items()},
        "config": {
            "phonetic_max_len": cfg["phonetic_max_len"],
            "tibetan_vocab_size": len(tib_vocab),
            "char_vocab_size": len(char_vocab),
        },
    }
    with open(vocab_path, "w", encoding="utf-8") as f:
        json.dump(vocab_data, f, ensure_ascii=False, indent=2)
    print(f"  Vocab      → {vocab_path}  ({vocab_path.stat().st_size / 1024:.1f} KB)")

    metrics_path = output_dir / "training_metrics.json"
    metrics = {
        "config": cfg,
        "n_params": n_params,
        "est_size_mb": size_mb,
        "n_train": len(train_pairs),
        "n_val": len(val_pairs),
        "n_test": len(test_pairs),
        "n_chars": len(char_vocab),
        "n_words": len(tib_vocab),
        "history": history,
        "best_epoch": best_state["epoch"] if best_state else None,
        "test_metrics": test_metrics,
        "total_train_time_sec": total_time,
        "device": str(device),
    }
    with open(metrics_path, "w", encoding="utf-8") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=2)
    print(f"  Metrics    → {metrics_path}")

    print("\nDone.")


if __name__ == "__main__":
    main()
