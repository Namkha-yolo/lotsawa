#!/bin/bash
# Publish the Lotsawa monorepo to GitHub with a fresh history.
# Run from this folder in Terminal:   bash publish.sh
# It never deletes anything: the two old nested .git folders are MOVED to _git_backup/.
set -euo pipefail
cd "$(dirname "$0")"

echo "== 0. preflight"
command -v git >/dev/null || { echo "git missing"; exit 1; }
if ! git lfs version >/dev/null 2>&1; then
  echo "git-lfs missing: brew install git-lfs && git lfs install   (then re-run)"; exit 1
fi
for f in .env.local CertificateSigningRequest.certSigningRequest; do
  [ -e "$f" ] && echo "   note: $f is present and ignored by .gitignore (will NOT be committed)"
done

echo "== 1. move the old nested repos aside (history was 2 commits each, from January)"
mkdir -p _git_backup
[ -d LotsawaCore/.git ]     && mv LotsawaCore/.git     _git_backup/LotsawaCore.git
[ -d LotsawaKeyboard/.git ] && mv LotsawaKeyboard/.git _git_backup/LotsawaKeyboard.git
# the dataset clones are ignored entirely (datasets/ in .gitignore)

echo "== 2. init"
[ -d .git ] || git init -b main
git lfs install --local
git add .gitattributes .gitignore
git add -A

echo "== 3. what would be committed (sizes)"
git ls-files -z | xargs -0 du -ch 2>/dev/null | tail -1
echo "   LFS-tracked:"; git lfs ls-files 2>/dev/null | head || true
echo "   sanity: secrets must not appear below"
git ls-files | grep -E '\.env|certSigning|\.p12|\.ipa$|\.xcarchive' && { echo "STOP: secret or build artifact staged"; exit 1; } || echo "   ok"

echo "== 4. commit"
git commit -m "Lotsawa: phonetic input method for Tibetan — core engine, iOS keyboard, training scripts, paper" \
  || echo "   (nothing new to commit)"

echo "== 5. push"
echo "   Create the repo first (public):  gh repo create Namkha-yolo/lotsawa --public --source=. --remote=origin --push"
echo "   or, without gh: create https://github.com/new  then"
echo "     git remote add origin git@github.com:Namkha-yolo/lotsawa.git && git push -u origin main"
