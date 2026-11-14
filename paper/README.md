# Lotsawa Paper

Single-file LaTeX paper in `main.tex`. Bibliography in `main.bib`.

## Build

XeLaTeX (required for Tibetan glyphs):

```
cd paper
xelatex main.tex
bibtex main
xelatex main.tex
xelatex main.tex
```

Or with latexmk:

```
latexmk -xelatex main.tex
```

## Placeholders

All unresolved numerical values use `\XX{}` macros. After `eval_lotsawa_model.py`
runs, grep for `\XX` and fill in from `LotsawaCore/Sources/LotsawaCore/results.json`.

## Target venue

ACL / EMNLP / NAACL long paper. Replace `\documentclass` front matter with
the official ACL style file (`acl.sty`) before submission.
