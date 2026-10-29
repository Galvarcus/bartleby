#!/usr/bin/env bash

# Set up a portable MiKTeX, which keeps its configuration in its own tree
# rather than in the registry of the host, and answer the two questions
# that decide whether the compile leg can restore one instead of
# installing MiKTeX for 108 seconds. Whether the setup runs unattended,
# and where the programs land: the documented way to use the edition is
# to double click a command script and read a console icon in the
# notification area, and nothing documents the layout of the tree.
#
# miktexsetup(1) gives the unattended route. --portable=dir sets MiKTeX up
# "for use on a portable device", and the install task, which only the
# standalone utility has, installs from a local package repository. So the
# set is downloaded first, into a folder that no cache entry holds,
# because a whole package set is 150MB at the smallest and the point of
# the entry is to be small.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/46

set -u

portable=${PORTABLE_DIR:?PORTABLE_DIR must name the folder of the tree.}
mirror=${PORTABLE_SET_DIR:?PORTABLE_SET_DIR must name the folder of the package set.}
set_name=${PORTABLE_SET:-basic}
setups=https://mirror.ctan.org/systems/win32/miktex/setup/windows-x64
fallback=https://miktex.org/download/win/miktexsetup-x64.zip
zip=setup-utility/miktexsetup.zip

mkdir -p "$portable" "$mirror" setup-utility

# A mirror of CTAN first, because miktex.org refused a runner for four
# tries of twenty seconds each while CTAN answered, and the packages come
# from a mirror anyway. The name of the utility carries a version and an
# encoded plus sign, so the index is read for it rather than a name
# written here.
echo "Fetching the setup utility"
name=$(curl -fsSL --retry 2 "$setups/" |
  grep -o 'miktexsetup-[^"]*-x64\.zip' | sort -u | tail -1)
if [ -n "$name" ] && curl -fsSL --retry 3 -o "$zip" "$setups/$name"; then
  echo "The utility came from $setups/$name"
elif curl -fsSL --retry 3 -o "$zip" "$fallback"; then
  echo "No mirror of CTAN answered, so the utility came from $fallback"
else
  echo "::error::Neither a mirror of CTAN nor $fallback holds a setup utility that can be fetched, so there is nothing to run."
  exit 1
fi

# The runner carries more than one program that reads a zip file and the
# Git Bash carries none of them for certain, so take whichever answers.
if command -v unzip >/dev/null 2>&1; then
  unzip -q -o "$zip" -d setup-utility
elif command -v 7z >/dev/null 2>&1; then
  7z x -y -osetup-utility "$zip" >/dev/null
else
  echo "::error::Neither unzip nor 7z is on the PATH, so the setup utility cannot be unpacked."
  exit 1
fi

# By name, because the zip holds more than one program and the integrated
# variant of the utility has no install task.
exe=$(find setup-utility -name 'miktexsetup_standalone.exe' | head -1)
if [ -z "$exe" ]; then
  echo "::error::The zip holds no miktexsetup_standalone.exe. What it does hold follows."
  find setup-utility -type f
  exit 1
fi
echo "The setup utility is $exe"

echo "Downloading the $set_name package set"
if ! "$exe" --verbose --local-package-repository="$mirror" \
  --package-set="$set_name" download; then
  echo "::error::The setup utility could not mirror the $set_name package set. Everything it said is above."
  exit 1
fi
du -sh "$mirror"

echo "Setting up the portable tree in $portable"
if ! "$exe" --verbose --portable="$portable" \
  --local-package-repository="$mirror" --package-set="$set_name" install; then
  echo "::error::The setup utility could not set up a portable MiKTeX. Everything it said is above."
  exit 1
fi

# The layout of the tree is undocumented, so the programs are found by
# name. The folder that holds the engine is the folder the job puts on
# its PATH, and printing it is half of what this script is for.
engine=$(find "$portable" -name 'pdflatex.exe' | head -1)
if [ -z "$engine" ]; then
  echo "::error::The portable tree holds no pdflatex.exe, so the setup wrote no engine. The tree holds:"
  find "$portable" -maxdepth 3 -type d
  exit 1
fi
bin=$(dirname "$engine")
echo "The programs are in $bin"
echo "$bin" >> "$GITHUB_PATH"

echo "The tree takes:"
du -sh "$portable"

# A fresh setup asks before it installs a package, which is the 2 of
# AutoInstall, and a job has no one to answer. There is no --admin here:
# a portable tree belongs to no machine.
if ! "$bin/initexmf.exe" --set-config-value='[MPM]AutoInstall=1'; then
  echo "::error::AutoInstall could not be set in the portable tree, so a missing package would stop a compile with a question."
  exit 1
fi
echo "AutoInstall: $("$bin/initexmf.exe" --show-config-value='[MPM]AutoInstall')"

# What the engines say when nothing of the host has been set up for them,
# which is the question this trial exists to answer. The version comes
# from the standard output alone, as check-windows-tools.sh takes it,
# because MiKTeX writes a warning about elevated privileges to the error
# output on every call and that would stand in for the version.
for name in pdflatex xelatex; do
  if said=$("$bin/$name.exe" --version 2>/dev/null); then
    printf '%s runs: %s\n' "$name" "$(printf '%s\n' "$said" | head -1)"
  else
    echo "::error::$name does not run from the portable tree. Everything it said follows."
    "$bin/$name.exe" --version 2>&1 || true
    exit 1
  fi
done
