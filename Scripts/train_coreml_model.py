#!/usr/bin/env python3
"""
Train a lightweight CoreML model for Tibetan word prediction.

Architecture: Simple MLP that takes:
  - phonetic_input: character indices of romanized input (padded to 20 chars)
  - context_word: index of previous Tibetan word (from top-N vocabulary)
And outputs:
  - scores over Tibetan word vocabulary (top-N most frequent words)

The model learns which Tibetan word to predict given phonetic input + context.
Target size: <2MB (well under 5MB keyboard extension limit).

Requirements:
    pip install torch coremltools numpy

Usage:
    python train_coreml_model.py
"""

import json
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from pathlib import Path
from collections import Counter, defaultdict
from typing import List, Dict, Tuple

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

# --- Configuration ---
PHONETIC_MAX_LEN = 20       # Max phonetic input length (characters)
PHONETIC_CHAR_VOCAB = 64    # Number of phonetic characters (a-z + diacritics + specials)
PHONETIC_EMBED_DIM = 16     # Embedding dim for each phonetic character
CONTEXT_EMBED_DIM = 32      # Embedding dim for context word
HIDDEN_DIM = 64             # Hidden layer size
TIBETAN_VOCAB_SIZE = 3000   # Top N Tibetan words to predict
BATCH_SIZE = 256
EPOCHS = 15
LEARNING_RATE = 0.002


def load_data():
    """Load all data files needed for training."""
    # 1. Word frequency: phonetic -> [{t: tibetan, f: freq}, ...]
    with open(LOTSAWA_CORE_DIR / "word_frequency.json", "r", encoding="utf-8") as f:
        word_freq = json.load(f)

    # 2. Context model: bigrams, trigrams
    with open(LOTSAWA_CORE_DIR / "context_model.json", "r", encoding="utf-8") as f:
        context_model = json.load(f)

    # 3. Phonetic dictionary: full phrase mappings
    with open(LOTSAWA_CORE_DIR / "phonetic_dictionary.json", "r", encoding="utf-8") as f:
        phonetic_dict = json.load(f)

    return word_freq, context_model, phonetic_dict


def build_vocabularies(word_freq, context_model):
    """Build phonetic character vocab and Tibetan word vocab."""
    # Phonetic character vocabulary
    phonetic_chars = set()
    for phonetic_key in word_freq.keys():
        phonetic_chars.update(phonetic_key.lower())

    # Sort for determinism, add special tokens
    char_list = sorted(phonetic_chars)
    char_to_idx = {"<PAD>": 0, "<UNK>": 1}
    for c in char_list:
        if c not in char_to_idx:
            char_to_idx[c] = len(char_to_idx)
    print(f"Phonetic char vocab: {len(char_to_idx)} characters")

    # Tibetan word vocabulary (by frequency)
    tibetan_freq = Counter()

    # From word_frequency.json
    for phonetic_key, data in word_freq.items():
        for match in data.get("matches", []):
            tibetan_freq[match["t"]] += match["f"]

    # From bigrams in context model
    for w1, followers in context_model.get("bigrams", {}).items():
        tibetan_freq[w1] += sum(followers.values())
        for w2, count in followers.items():
            tibetan_freq[w2] += count

    # Take top N Tibetan words
    top_tibetan = tibetan_freq.most_common(TIBETAN_VOCAB_SIZE - 2)  # reserve 0,1
    tibetan_to_idx = {"<PAD>": 0, "<UNK>": 1}
    for word, _ in top_tibetan:
        tibetan_to_idx[word] = len(tibetan_to_idx)
    idx_to_tibetan = {v: k for k, v in tibetan_to_idx.items()}
    print(f"Tibetan word vocab: {len(tibetan_to_idx)} words")

    return char_to_idx, tibetan_to_idx, idx_to_tibetan


def encode_phonetic(text, char_to_idx, max_len=PHONETIC_MAX_LEN):
    """Encode phonetic string as padded character indices."""
    text = text.lower().strip()
    indices = []
    unk = char_to_idx["<UNK>"]
    for c in text[:max_len]:
        indices.append(char_to_idx.get(c, unk))
    # Pad
    while len(indices) < max_len:
        indices.append(0)  # PAD
    return indices


def build_training_pairs(word_freq, context_model, char_to_idx, tibetan_to_idx):
    """
    Build training pairs: (phonetic_chars, context_word_idx, target_word_idx).

    We create pairs from:
    1. word_frequency.json: (phonetic, no_context, tibetan) - base mapping
    2. context bigrams: for each (w1 -> w2) bigram, find phonetic for w2,
       create (phonetic_of_w2, w1, w2) - contextual mapping
    """
    pairs = []  # (phonetic_indices, context_idx, target_idx, weight)
    unk_idx = tibetan_to_idx["<UNK>"]

    # --- Source 1: Base word frequency pairs (no context) ---
    print("Building base frequency pairs...")
    for phonetic_key, data in word_freq.items():
        phonetic_enc = encode_phonetic(phonetic_key, char_to_idx)
        for match in data.get("matches", []):
            tibetan = match["t"]
            freq = match["f"]
            target_idx = tibetan_to_idx.get(tibetan, unk_idx)
            if target_idx == unk_idx:
                continue
            # Weight by log frequency
            weight = max(1.0, np.log1p(freq))
            # Context = 0 (no context)
            pairs.append((phonetic_enc, 0, target_idx, weight))

    print(f"  Base pairs: {len(pairs)}")

    # --- Source 2: Build reverse lookup: tibetan -> phonetic ---
    tibetan_to_phonetic = defaultdict(list)
    for phonetic_key, data in word_freq.items():
        for match in data.get("matches", []):
            tibetan_to_phonetic[match["t"]].append(phonetic_key)

    # --- Source 3: Context bigram pairs ---
    print("Building contextual bigram pairs...")
    bigram_pairs = 0
    bigrams = context_model.get("bigrams", {})
    for w1, followers in bigrams.items():
        ctx_idx = tibetan_to_idx.get(w1, unk_idx)
        if ctx_idx == unk_idx:
            continue
        for w2, count in followers.items():
            target_idx = tibetan_to_idx.get(w2, unk_idx)
            if target_idx == unk_idx:
                continue
            # Find phonetic for w2
            phonetics_for_w2 = tibetan_to_phonetic.get(w2, [])
            if not phonetics_for_w2:
                continue
            weight = max(1.0, np.log1p(count))
            for phon in phonetics_for_w2[:2]:  # Limit to avoid explosion
                phonetic_enc = encode_phonetic(phon, char_to_idx)
                pairs.append((phonetic_enc, ctx_idx, target_idx, weight))
                bigram_pairs += 1

    print(f"  Bigram context pairs: {bigram_pairs}")
    print(f"  Total training pairs: {len(pairs)}")
    return pairs


class PredictionDataset(Dataset):
    """PyTorch dataset for training pairs."""

    def __init__(self, pairs):
        self.phonetic = torch.tensor(
            [p[0] for p in pairs], dtype=torch.long
        )
        self.context = torch.tensor(
            [p[1] for p in pairs], dtype=torch.long
        )
        self.target = torch.tensor(
            [p[2] for p in pairs], dtype=torch.long
        )
        self.weight = torch.tensor(
            [p[3] for p in pairs], dtype=torch.float32
        )

    def __len__(self):
        return len(self.target)

    def __getitem__(self, idx):
        return (
            self.phonetic[idx],
            self.context[idx],
            self.target[idx],
            self.weight[idx],
        )


class TibetanPredictor(nn.Module):
    """
    Lightweight model for Tibetan word prediction.

    Input:
      - phonetic: (batch, PHONETIC_MAX_LEN) character indices
      - context:  (batch,) previous word index

    Output:
      - (batch, TIBETAN_VOCAB_SIZE) log-probabilities over Tibetan vocabulary
    """

    def __init__(
        self,
        phonetic_vocab_size,
        tibetan_vocab_size,
        phonetic_embed_dim=PHONETIC_EMBED_DIM,
        context_embed_dim=CONTEXT_EMBED_DIM,
        hidden_dim=HIDDEN_DIM,
        max_len=PHONETIC_MAX_LEN,
    ):
        super().__init__()
        self.phonetic_embed = nn.Embedding(
            phonetic_vocab_size, phonetic_embed_dim, padding_idx=0
        )
        self.context_embed = nn.Embedding(
            tibetan_vocab_size, context_embed_dim, padding_idx=0
        )
        # Phonetic encoder: simple 1D convolution + pooling
        self.conv1 = nn.Conv1d(phonetic_embed_dim, 32, kernel_size=3, padding=1)
        self.conv2 = nn.Conv1d(32, 32, kernel_size=3, padding=1)
        # After pooling: 32-dim phonetic representation
        # Concat with 32-dim context = 64
        self.fc1 = nn.Linear(32 + context_embed_dim, hidden_dim)
        self.fc2 = nn.Linear(hidden_dim, tibetan_vocab_size)
        self.relu = nn.ReLU()
        self.dropout = nn.Dropout(0.1)

    def forward(self, phonetic, context):
        # Phonetic encoding
        ph = self.phonetic_embed(phonetic)  # (B, L, E)
        ph = ph.transpose(1, 2)  # (B, E, L) for conv1d
        ph = self.relu(self.conv1(ph))
        ph = self.relu(self.conv2(ph))
        ph = ph.mean(dim=2)  # Global average pooling -> (B, 32)

        # Context encoding
        ctx = self.context_embed(context)  # (B, context_embed_dim)

        # Combine
        combined = torch.cat([ph, ctx], dim=1)  # (B, 64)
        combined = self.dropout(combined)
        h = self.relu(self.fc1(combined))
        h = self.dropout(h)
        logits = self.fc2(h)

        return logits


def train(model, dataloader, epochs=EPOCHS, lr=LEARNING_RATE):
    """Train the model."""
    optimizer = optim.Adam(model.parameters(), lr=lr)
    criterion = nn.CrossEntropyLoss(reduction="none")

    model.train()
    for epoch in range(epochs):
        total_loss = 0.0
        correct = 0
        total = 0

        for batch_idx, (phonetic, context, target, weight) in enumerate(dataloader):
            optimizer.zero_grad()
            logits = model(phonetic, context)
            loss_per_sample = criterion(logits, target)
            loss = (loss_per_sample * weight).mean()
            loss.backward()
            optimizer.step()

            total_loss += loss.item() * len(target)
            preds = logits.argmax(dim=1)
            correct += (preds == target).sum().item()
            total += len(target)

        avg_loss = total_loss / total
        accuracy = correct / total
        print(f"  Epoch {epoch+1}/{epochs}: loss={avg_loss:.4f}, acc={accuracy:.4f}")

    return model


def convert_to_coreml(model, char_to_idx, tibetan_to_idx, idx_to_tibetan, output_dir):
    """Convert PyTorch model to CoreML using neuralnetwork backend."""
    import coremltools as ct

    model.eval()

    # Create example inputs for tracing
    example_phonetic = torch.zeros(1, PHONETIC_MAX_LEN, dtype=torch.long)
    example_context = torch.zeros(1, dtype=torch.long)

    # Trace the model
    traced = torch.jit.trace(model, (example_phonetic, example_context))

    # Convert to CoreML using neuralnetwork backend (compatible with Python 3.14)
    print("\nConverting to CoreML (neuralnetwork backend)...")
    coreml_model = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="phonetic_input",
                shape=(1, PHONETIC_MAX_LEN),
                dtype=np.int32,
            ),
            ct.TensorType(
                name="context_word",
                shape=(1,),
                dtype=np.int32,
            ),
        ],
        outputs=[ct.TensorType(name="word_scores")],
        convert_to="neuralnetwork",
    )

    # Add metadata
    coreml_model.author = "Lotsawa Keyboard"
    coreml_model.short_description = (
        "Tibetan word prediction from phonetic input with context"
    )
    coreml_model.version = "1.0"

    # Save vocabs as metadata
    coreml_model.user_defined_metadata["phonetic_char_vocab"] = json.dumps(
        char_to_idx, ensure_ascii=False
    )
    coreml_model.user_defined_metadata["tibetan_word_vocab"] = json.dumps(
        tibetan_to_idx, ensure_ascii=False
    )

    # Save as .mlmodel (single file format for neuralnetwork backend)
    mlmodel_path = output_dir / "TibetanLM.mlmodel"
    coreml_model.save(str(mlmodel_path))

    size_mb = mlmodel_path.stat().st_size / (1024 * 1024)
    print(f"Model saved to {mlmodel_path}")
    print(f"Model size: {size_mb:.2f} MB")
    if size_mb > 5.0:
        print("WARNING: Model exceeds 5MB target!")
    else:
        print("Model is within 5MB target.")

    return mlmodel_path


def save_vocab_files(char_to_idx, tibetan_to_idx, idx_to_tibetan, output_dir):
    """Save vocabulary files for Swift integration."""
    vocab_data = {
        "phonetic_char_vocab": char_to_idx,
        "tibetan_word_vocab": tibetan_to_idx,
        "tibetan_idx_to_word": {str(k): v for k, v in idx_to_tibetan.items()},
        "config": {
            "phonetic_max_len": PHONETIC_MAX_LEN,
            "tibetan_vocab_size": len(tibetan_to_idx),
        },
    }
    vocab_path = output_dir / "ml_vocab.json"
    with open(vocab_path, "w", encoding="utf-8") as f:
        json.dump(vocab_data, f, ensure_ascii=False, indent=2)
    print(f"Saved vocabulary to {vocab_path}")
    return vocab_path


def main():
    print("=" * 60)
    print("Training CoreML Model for Tibetan Word Prediction")
    print("=" * 60)
    print(f"PyTorch version: {torch.__version__}")

    import coremltools as ct
    print(f"CoreMLTools version: {ct.__version__}")

    # Load data
    print("\nLoading data...")
    word_freq, context_model, phonetic_dict = load_data()
    print(f"  word_frequency entries: {len(word_freq)}")
    print(f"  phonetic_dictionary entries: {len(phonetic_dict)}")
    print(f"  bigram contexts: {len(context_model.get('bigrams', {}))}")

    # Build vocabularies
    print("\nBuilding vocabularies...")
    char_to_idx, tibetan_to_idx, idx_to_tibetan = build_vocabularies(
        word_freq, context_model
    )

    # Build training pairs
    print("\nBuilding training pairs...")
    pairs = build_training_pairs(word_freq, context_model, char_to_idx, tibetan_to_idx)

    if len(pairs) < 100:
        print("ERROR: Not enough training pairs!")
        return

    # Create dataset and dataloader
    dataset = PredictionDataset(pairs)
    dataloader = DataLoader(dataset, batch_size=BATCH_SIZE, shuffle=True)

    # Build model
    print("\nBuilding model...")
    model = TibetanPredictor(
        phonetic_vocab_size=len(char_to_idx),
        tibetan_vocab_size=len(tibetan_to_idx),
    )
    param_count = sum(p.numel() for p in model.parameters())
    print(f"  Model parameters: {param_count:,}")
    print(f"  Estimated size: {param_count * 4 / 1024 / 1024:.2f} MB (float32)")

    # Train
    print("\nTraining...")
    model = train(model, dataloader)

    # Quick evaluation
    print("\nEvaluating...")
    model.eval()
    with torch.no_grad():
        # Test a few phonetic inputs
        test_inputs = ["chö", "la", "pa", "dang", "gyi"]
        for inp in test_inputs:
            enc = encode_phonetic(inp, char_to_idx)
            phonetic_t = torch.tensor([enc], dtype=torch.long)
            context_t = torch.zeros(1, dtype=torch.long)
            logits = model(phonetic_t, context_t)
            probs = torch.softmax(logits, dim=1)
            top5 = torch.topk(probs, 5, dim=1)
            results = []
            for idx_val, prob_val in zip(
                top5.indices[0].tolist(), top5.values[0].tolist()
            ):
                word = idx_to_tibetan.get(idx_val, "<UNK>")
                results.append(f"{word}({prob_val:.3f})")
            print(f"  '{inp}' -> {', '.join(results)}")

    # Convert to CoreML
    output_dir = LOTSAWA_CORE_DIR
    mlpackage_path = convert_to_coreml(
        model, char_to_idx, tibetan_to_idx, idx_to_tibetan, output_dir
    )

    # Save vocabulary files
    save_vocab_files(char_to_idx, tibetan_to_idx, idx_to_tibetan, output_dir)

    print("\nDone!")
    print(f"Model: {mlpackage_path}")


if __name__ == "__main__":
    main()
