#!/usr/bin/env bash

# Compile the PDFs that the smoke tests compile, so that the tree the cache
# entry carries holds every package the templates reach, and fail unless
# both of them came out.
#
# This is the one step of the cache workflow that must fail the job. The
# warm-up before it is an optimisation, and a failure there is a warning
# because the installer caught whatever it missed. The leg that reads the
# entry has no installer now, so an entry saved from a failed closure
# would fail every run that restores it, and a save over a key that exists
# is refused, so such an entry would have to be deleted by hand.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/68

set -u

vim_exe=${VIM_EXE:-vim}
report=tests/closure_results.txt
wanted=2

rm -f "$report"

"$vim_exe" -es -u NONE -N \
  -c 'set rtp+=.,deps/Logger' \
  -c 'source .github/scripts/make-tex-closure.vim' -c 'quit' || true

if [ ! -f "$report" ]; then
  echo "::error::Vim never wrote $report, so no compile of the closure finished and the entry would carry no package that the templates reach."
  exit 1
fi

made=$(grep -c . "$report" || true)
if [ "$made" -lt "$wanted" ]; then
  echo "::error::Only $made of $wanted closure PDFs compiled, so the entry would be saved without the packages the other needs. What compiled follows."
  cat "$report"
  exit 1
fi

echo "The closure compiled $made PDFs:"
cat "$report"
