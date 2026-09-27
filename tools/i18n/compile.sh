#!/bin/sh
# Compile every lang/<code>.po into lang/<code>/LC_MESSAGES/<domain>.mo,
# the file that Vim reads. Run from the root of the repository. Needs
# msgfmt from GNU gettext. See Localization_README.md.
set -e
domain=$(python3 tools/i18n/extract.py --domain)
for po in lang/*.po; do
  [ -e "$po" ] || exit 0
  code=$(basename "$po" .po)
  mkdir -p "lang/$code/LC_MESSAGES"
  msgfmt --check -o "lang/$code/LC_MESSAGES/$domain.mo" "$po"
  echo "compiled $po"
done
