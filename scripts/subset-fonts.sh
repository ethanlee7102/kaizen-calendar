#!/bin/zsh
# Downloads the app's three font families from the Google Fonts repo and subsets them to
# Latin + punctuation. The UI never shows Japanese characters (spec-visual-identity.md),
# so the CJK glyphs (~40 MB) are dropped. All three fonts are SIL OFL 1.1 with no
# Reserved Font Names, so subsetting and bundling are allowed.
#
# Usage: scripts/subset-fonts.sh   (needs `pip install fonttools`, i.e. `pyftsubset` on PATH)
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=Packages/UI/Sources/UI/Resources/Fonts
SRC=https://raw.githubusercontent.com/google/fonts/main/ofl
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Basic Latin, Latin-1, Latin Extended-A, general punctuation, currency, letterlike,
# arrows, math minus/times, check marks, geometric circles.
UNICODES="U+0020-007E,U+00A0-00FF,U+0100-017F,U+02C6,U+02DA,U+02DC,U+2000-206F,U+20AC,U+2100-214F,U+2190-21FF,U+2212,U+2713-2717,U+25CB-25CF"

fonts=(
  shipporimincho/ShipporiMincho-Medium.ttf
  shipporimincho/ShipporiMincho-Bold.ttf
  zenkakugothicnew/ZenKakuGothicNew-Regular.ttf
  zenkakugothicnew/ZenKakuGothicNew-Medium.ttf
  zenkakugothicnew/ZenKakuGothicNew-Bold.ttf
  kleeone/KleeOne-Regular.ttf
  kleeone/KleeOne-SemiBold.ttf
)

mkdir -p "$OUT"
for f in $fonts; do
  name=$(basename "$f")
  curl -fsSL -o "$TMP/$name" "$SRC/$f"
  pyftsubset "$TMP/$name" --unicodes="$UNICODES" --layout-features='*' \
    --name-IDs='*' --name-languages='*' --output-file="$OUT/$name"
  echo "$name: $(du -h "$OUT/$name" | cut -f1)"
done

for family in shipporimincho zenkakugothicnew kleeone; do
  curl -fsSL -o "$OUT/OFL-$family.txt" "$SRC/$family/OFL.txt"
done
