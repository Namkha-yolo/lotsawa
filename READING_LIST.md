# Reading List for Lotsawa Keyboard Paper

Priority reading order: **1 → 3 → 4 → 6 → 7 → 8**, then fill in the rest.

---

## The Foundational Analogy (read first)

### 1. A New Statistical Approach to Chinese Pinyin Input
**Zheng Chen, Kai-Fu Lee** — ACL 2000

- https://aclanthology.org/P00-1031/
- PDF: https://aclanthology.org/P00-1031.pdf

Closest sibling paper. Chinese Pinyin faces the same one-to-many phonetic→orthographic mapping, resolved with trigram language models. Gives the template: how to frame the problem, what baseline to compare against, what metrics to report. Paper should explicitly say how Tibetan differs (prefix/suffix orthographic structure, Sumtak particle rules, lower resource availability).

### 2. Processing Homonyms in the Kana-to-Kanji Conversion
**Masahito Takahashi** — COLING 1996

- PDF: https://aclanthology.org/C96-2206.pdf

The Japanese parallel. Kana→kanji conversion second stage (disambiguating homophones using context) is directly analogous to the disambiguation layer. Shorter paper, focused specifically on the homophone problem.

---

## The Theoretical Framework

### 3. A Spelling Correction Program Based on a Noisy Channel Model
**Mark Kernighan, Kenneth Church, William Gale** — COLING 1990

- https://aclanthology.org/C90-2036/

First application of the noisy channel model to text correction. The framework is the same: P(intended | observed) = P(observed | intended) × P(intended). This Bayesian framing is the theoretical backbone. Short and clean.

---

## The Closest Structural Analogy

### 4. Arabic Diacritization with Recurrent Neural Networks
**Yonatan Belinkov, James Glass** — EMNLP 2015

- https://aclanthology.org/D15-1274/
- PDF: https://aclanthology.org/D15-1274.pdf

Arabic diacritization = recovering vowel marks that written Arabic omits = restoring orthographic information lost in the surface form. Structurally identical to the Tibetan problem (recovering prefixes, superscripts, suffixes that pronunciation drops). Framed as sequence labeling. Key difference: Arabic has massive training data; Tibetan doesn't.

---

## The Keyboard/Input Method Literature

### 5. Language Modeling for Soft Keyboards
**Joshua Goodman, Gina Venolia, Keith Steury, Chauncey Parker** — IUI 2002 / AAAI 2002

- https://www.microsoft.com/en-us/research/publication/language-modeling-for-soft-keyboards/
- PDF: https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/p194-goodman.pdf

Directly about using language models to disambiguate touch keyboard input. Establishes the principle that a language model combined with an input model reduces error rates. The Lotsawa suggestion pipeline does exactly this.

---

## The Benchmark You Cited

### 6. TLUE: A Tibetan Language Understanding Evaluation Benchmark
**EMNLP 2025**

- https://aclanthology.org/2025.emnlp-main.1777/
- arXiv: https://arxiv.org/abs/2503.12051
- GitHub: https://github.com/Vicentvankor/TLUE

Already referenced in abstract. Read carefully — need to cite findings precisely (which models, which tasks, how far below random). Validates the claim that general-purpose LLMs can't handle Tibetan and a specialized architecture is necessary.

---

## The Low-Resource Argument

### 7. The State and Fate of Linguistic Diversity and Inclusion in the NLP World
**Pratik Joshi, Sebastin Santy, Amar Budhiraja, Kalika Bali, Monojit Choudhury** — ACL 2020

- https://aclanthology.org/2020.acl-main.560/
- PDF: https://aclanthology.org/2020.acl-main.560.pdf

Classifies languages into 6 resource tiers. Tibetan falls in the lowest. Gives the formal vocabulary to explain why the problem is hard — not just because of orthography, but because data to train general models doesn't exist at scale.

---

## Tibetan NLP Specifically

### 8. Tibetan Language and AI: A Comprehensive Survey of Resources, Methods and Challenges
**arXiv, October 2025**

- https://arxiv.org/abs/2510.19144
- HTML: https://arxiv.org/html/2510.19144v1

Most recent survey of the entire Tibetan NLP landscape. Covers word segmentation, POS tagging, available corpora, existing tools. Essential for the related work section — maps what exists and what doesn't, positioning the contribution.

### 9. Recent Developments in Tibetan NLP
**ACM Transactions on Asian and Low-Resource Language Information Processing, 2021**

- https://dl.acm.org/doi/abs/10.1145/3453692

Earlier survey, useful for tracing historical development of Tibetan computational tools and showing what was missing (namely: a phonetic input framework).

---

## The Quality-of-Data Problem

### 10. Quality at a Glance: An Audit of Web-Crawled Multilingual Datasets
**Julia Kreutzer et al.** — TACL 2022

Found that much "Tibetan" data in web-crawled corpora is noisy or misidentified. Supports the argument for a curated, on-device approach rather than relying on web-scale models trained on unreliable Tibetan data.

---

## How These Map to Paper Sections

| Paper | Informs Section |
|-------|----------------|
| 1 (Chen & Lee, Pinyin) | Related work, problem formulation, evaluation methodology |
| 2 (Takahashi, Kana-Kanji) | Related work (Japanese parallel) |
| 3 (Kernighan et al., Noisy Channel) | Theoretical framework (Bayesian formulation) |
| 4 (Belinkov & Glass, Arabic) | Related work (closest structural analogy) |
| 5 (Goodman, Soft Keyboards) | Related work (keyboard-specific LM application) |
| 6 (TLUE) | Motivation, why specialized architecture is necessary |
| 7 (Joshi et al., Linguistic Diversity) | Motivation, low-resource framing |
| 8 (Tibetan AI Survey 2025) | Related work, positioning the contribution |
| 9 (Tibetan NLP Developments) | Related work, historical context |
| 10 (Kreutzer, Dataset Quality) | Justification for curated on-device approach |
