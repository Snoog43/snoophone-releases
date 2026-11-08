#!/usr/bin/env bash
# Publie le site https://snoog43.github.io/snoophone-releases/ (branche gh-pages) : les fichiers de main
# plus l'APK de la derniere version, servi par GitHub Pages quand les liens de telechargement des
# releases renvoient 504. La branche est remplacee a chaque fois (un seul commit) : l'APK ne
# s'accumule pas dans l'historique. A relancer apres chaque nouvelle APK publiee dans la release.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -C "$repo" archive main | tar -x -C "$work"
id=$(gh api repos/Snoog43/snoophone-releases/releases/latest -q '.assets[] | select(.name == "Snoophone-android.apk") | .id')
digest=$(gh api "repos/Snoog43/snoophone-releases/releases/assets/$id" -q '.digest')
gh api "repos/Snoog43/snoophone-releases/releases/assets/$id" -H 'Accept: application/octet-stream' > "$work/Snoophone-android.apk"
hash=$(sha256sum "$work/Snoophone-android.apk" | cut -d' ' -f1)
[ "$digest" = "sha256:$hash" ] || { echo "APK differente de la release ($digest / $hash)" >&2; exit 1; }

cd "$work"
git init -q -b gh-pages
git add -A
git commit -q -m "Site : pages de main + APK de la derniere version"
git push -q -f https://github.com/Snoog43/snoophone-releases.git gh-pages
echo "gh-pages publie (APK sha256:$hash)"
