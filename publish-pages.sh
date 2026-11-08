#!/usr/bin/env bash
# Publie le site https://snoog43.github.io/snoophone-releases/ (branche gh-pages) : les fichiers de main
# plus l'APK, l'installeur PC et latest.json de la derniere version, servis par GitHub Pages quand les liens de telechargement des
# releases renvoient 504. La branche est remplacee a chaque fois (un seul commit) : l'APK ne
# s'accumule pas dans l'historique. A relancer apres chaque nouvelle APK publiee dans la release.
set -euo pipefail
repo="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git -C "$repo" archive main | tar -x -C "$work"
tag=$(gh api repos/Snoog43/snoophone-releases/releases/latest -q '.tag_name')
# Copie un fichier de la release sur le site, empreinte verifiee ; affiche son sha256.
fetch() {
  local name="$1" id digest hash
  id=$(gh api repos/Snoog43/snoophone-releases/releases/latest -q ".assets[] | select(.name == \"$name\") | .id")
  digest=$(gh api "repos/Snoog43/snoophone-releases/releases/assets/$id" -q '.digest')
  gh api "repos/Snoog43/snoophone-releases/releases/assets/$id" -H 'Accept: application/octet-stream' > "$work/$name"
  hash=$(sha256sum "$work/$name" | cut -d' ' -f1)
  [ "$digest" = "sha256:$hash" ] || { echo "$name differente de la release ($digest / $hash)" >&2; exit 1; }
  echo "$hash"
}
hash=$(fetch Snoophone-android.apk)
setup=$(fetch Snoophone-x64-setup.exe)
# Lu par install.ps1 (et les mises a jour) quand l'API des releases renvoie 504.
printf '{"tag":"%s","version":"%s","setup_sha256":"%s","apk_sha256":"%s"}\n' \
  "$tag" "${tag#v}" "$setup" "$hash" > "$work/latest.json"

cd "$work"
git init -q -b gh-pages
git add -A
git commit -q -m "Site : pages de main + APK de la derniere version"
git push -q -f https://github.com/Snoog43/snoophone-releases.git gh-pages
echo "gh-pages publie (APK sha256:$hash)"
