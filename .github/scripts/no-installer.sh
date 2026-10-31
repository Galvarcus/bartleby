#!/usr/bin/env bash

# Turn the automatic package installation of a restored MiKTeX off, and
# prove that it is off, so that a package the cache entry does not carry
# fails a compile at once instead of being fetched while a test waits.
#
# Run 40988239065 is what this answers. A compile asked for kvsetkeys.sty,
# which hyperref pulls in and the entry did not hold, and the run before
# it spent the whole budget of two PDF tests on work of this kind.
#
# AutoInstall is the setting that make-portable-miktex.sh writes when it
# builds the tree and use-portable-miktex.sh prints when it restores one,
# so it is the one this reads and writes as well. initexmf --disable-installer
# is documented as overruling the configuration data store, so both are
# applied: the setting for the tree, the flag for this job.
#
# The proof is a compile, not the silence of the two commands. initexmf
# --report carries no AutoInstall line, and a suite that passes proves
# only that nothing was missing from the entry.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/68

set -u

# A package that no repository holds, so that nothing can install it and
# only the time taken tells an installer that tried from one that never
# started.
ABSENT_PACKAGE=bartlebynosuchpackage
# What a compile of a missing package may take once the installer is off.
# A failure that takes longer went looking for it.
MAX_PROBE_SECONDS=15

bin=${PORTABLE_DIR:-}/texmfs/install/miktex/bin/x64
initexmf=$bin/initexmf.exe
if [ ! -x "$initexmf" ]; then
  echo "::error::No initexmf under $bin, so the installer of the restored MiKTeX cannot be turned off."
  exit 1
fi

if ! "$initexmf" --set-config-value='[MPM]AutoInstall=0'; then
  echo "::error::AutoInstall could not be set to 0 in the restored tree."
  exit 1
fi

if ! "$initexmf" --disable-installer; then
  echo "::error::The installer of the restored tree could not be disabled."
  exit 1
fi

echo "AutoInstall: $("$initexmf" --show-config-value='[MPM]AutoInstall' 2>/dev/null)"

probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
printf '\\documentclass{article}\n\\usepackage{%s}\n\\begin{document}x\\end{document}\n' \
  "$ABSENT_PACKAGE" > "$probe/probe.tex"

start=$(date +%s)
( cd "$probe" && pdflatex -interaction=nonstopmode -halt-on-error probe.tex ) \
  >"$probe/out" 2>&1
status=$?
took=$(( $(date +%s) - start ))

if [ "$status" -eq 0 ]; then
  echo "::error::A compile of the absent package $ABSENT_PACKAGE succeeded, so something installed it and the installer is still on."
  cat "$probe/out"
  exit 1
fi

if [ "$took" -gt "$MAX_PROBE_SECONDS" ]; then
  echo "::error::A compile of the absent package $ABSENT_PACKAGE failed after ${took}s, over the ${MAX_PROBE_SECONDS}s that a refusal takes, so the installer went looking for it."
  cat "$probe/out"
  exit 1
fi

echo "A missing package fails a compile in ${took}s, so the installer is off."
