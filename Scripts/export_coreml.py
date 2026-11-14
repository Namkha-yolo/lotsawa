#!/usr/bin/env python3
"""Export trained Lotsawa LM to CoreML for iOS deployment.

Loads lotsawa_lm.pt (PyTorch checkpoint) and converts to .mlmodel using the
neuralnetwork backend (required for Python 3.14 / coremltools 9 compatibility).
Writes TibetanLM.mlmodel alongside the existing one, then compiles to
TibetanLM.mlmodelc for the bundle.

Usage:
    python Scripts/export_coreml.py
"""

import json
import sys
from pathlib import Path

import numpy as np
import torch

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
LOTSAWA_CORE_DIR = PROJECT_DIR / "LotsawaCore" / "Sources" / "LotsawaCore"

sys.path.insert(0, str(SCRIPT_DIR))
from train_lotsawa_model import LotsawaLM, PAD_IDX


def main():
    ckpt_path = LOTSAWA_CORE_DIR / "lotsawa_lm.pt"
    if not ckpt_path.exists():
        print(f"Error: {ckpt_path} not found. Run train_lotsawa_model.py first.")
        sys.exit(1)

    print(f"Loading checkpoint from {ckpt_path}...")
    ckpt = torch.load(ckpt_path, map_location="cpu", weights_only=False)
    cfg = ckpt["config"]
    char_vocab = ckpt["char_vocab"]
    tib_vocab = ckpt["tib_vocab"]

    n_chars = len(char_vocab)
    n_words = len(tib_vocab)
    print(f"  n_chars: {n_chars}, n_words: {n_words}")
    print(f"  params: {ckpt['n_params']:,}")

    # Rebuild model with dropout=0 for export
    model = LotsawaLM(
        n_chars=n_chars,
        n_words=n_words,
        char_dim=cfg["char_dim"],
        lstm_hidden=cfg["lstm_hidden"],
        lstm_layers=cfg["lstm_layers"],
        context_dim=cfg["context_dim"],
        mlp_hidden=cfg["mlp_hidden"],
        dropout=0.0,
        max_len=cfg["phonetic_max_len"],
    )
    model.load_state_dict(ckpt["model_state"])
    model.eval()

    # Trace the model with example inputs
    max_len = cfg["phonetic_max_len"]
    example_phonetic = torch.zeros(1, max_len, dtype=torch.long)
    example_context = torch.zeros(1, dtype=torch.long)

    print("\nTracing model...")
    with torch.no_grad():
        traced = torch.jit.trace(model, (example_phonetic, example_context))

    # Sanity check: run traced model and compare to eager
    with torch.no_grad():
        eager_out = model(example_phonetic, example_context)
        traced_out = traced(example_phonetic, example_context)
        if not torch.allclose(eager_out, traced_out, atol=1e-4):
            print("WARNING: traced output differs from eager output!")
            print(f"  max diff: {(eager_out - traced_out).abs().max().item()}")
        else:
            print("  Traced output matches eager output.")

    # Convert to CoreML
    print("\nConverting to CoreML...")
    import coremltools as ct

    coreml_model = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="phonetic_input",
                shape=(1, max_len),
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

    coreml_model.author = "Lotsawa Keyboard"
    coreml_model.short_description = (
        "Tibetan word prediction from phonetic input with previous-word context. "
        "BiLSTM phonetic encoder + word embedding + MLP classifier."
    )
    coreml_model.version = "2.0"

    coreml_model.user_defined_metadata["phonetic_char_vocab"] = json.dumps(
        char_vocab, ensure_ascii=False,
    )
    coreml_model.user_defined_metadata["tibetan_word_vocab"] = json.dumps(
        tib_vocab, ensure_ascii=False,
    )
    coreml_model.user_defined_metadata["config"] = json.dumps(cfg)

    out_path = LOTSAWA_CORE_DIR / "TibetanLM.mlmodel"
    coreml_model.save(str(out_path))
    size_mb = out_path.stat().st_size / (1024 * 1024)
    print(f"\nSaved → {out_path}")
    print(f"Size: {size_mb:.2f} MB")
    if size_mb > 5.0:
        print("WARNING: exceeds 5 MB iOS keyboard-extension budget!")
    elif size_mb > 4.0:
        print("Note: close to 5 MB budget; consider shrinking vocab or hidden dim")
    else:
        print("Within 5 MB budget.")

    # Compile .mlmodelc
    print("\nCompiling to .mlmodelc...")
    import subprocess
    compile_cmd = ["xcrun", "coremlcompiler", "compile", str(out_path), str(LOTSAWA_CORE_DIR)]
    result = subprocess.run(compile_cmd, capture_output=True, text=True)
    if result.returncode == 0:
        mlmodelc = LOTSAWA_CORE_DIR / "TibetanLM.mlmodelc"
        print(f"  → {mlmodelc}")
    else:
        print(f"  coremlcompiler failed: {result.stderr}")
        print("  The .mlmodel is still usable; Xcode will compile it at build time.")

    print("\nDone.")


if __name__ == "__main__":
    main()
