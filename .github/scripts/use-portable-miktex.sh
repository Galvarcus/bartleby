#!/usr/bin/env bash

# Put a restored portable MiKTeX on the PATH, and nothing else. Whether a
# tree that a cache entry carries still works is the question that decides
# the design, because that is where a restored shared install failed: it
# kept its startup configuration outside its own tree and had to be
# registered again before any program would run.
#
# The folder of the programs is found by name rather than written here,
# because the layout of a portable tree is undocumented. It was measured
# as texmfs/install/miktex/bin/x64 in run 40778862488, and a layout that
# moves should fail with that sentence rather than with a program that
# cannot be found.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/46

set -u

portable=${PORTABLE_DIR:?PORTABLE_DIR must name the folder of the tree.}

if [ ! -d "$portable" ]; then
  echo "::error::$portable is not a folder, so no tree was restored."
  exit 1
fi

echo "The restored tree takes:"
du -sh "$portable"

engine=$(find "$portable" -name 'pdflatex.exe' | head -1)
if [ -z "$engine" ]; then
  echo "::error::The restored tree holds no pdflatex.exe. Its top folders follow."
  find "$portable" -maxdepth 3 -type d
  exit 1
fi
bin=$(dirname "$engine")
echo "The programs are in $bin"
echo "$bin" >> "$GITHUB_PATH"

# The setting travels in the tree, so this reads it rather than writing
# it: a 2 would mean the entry carries a MiKTeX that stops to ask.
echo "AutoInstall: $("$bin/initexmf.exe" --show-config-value='[MPM]AutoInstall' 2>/dev/null)"
