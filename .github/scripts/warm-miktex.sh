#!/usr/bin/env bash

# Ask MiKTeX for every class and package that the compile templates name,
# so that it installs them before the tests run. Each test allows 60
# seconds for a compile, see MAX_WAIT_MS in tests/test_compile_smoke.vim,
# and an install inside that time would fail the test as though the
# compile itself were broken. A lookup is enough to trigger the install,
# because MiKTeX fetches a missing file during a plain kpsewhich.
#
# A lookup that fails is not an error here. The install is an optimisation,
# and AutoInstall stays on to catch whatever this misses, see
# .github/actions/install-miktex.

set -u

vim_exe=${VIM_EXE:-vim}
report=tests/needs_results.txt

rm -f "$report"

# texcheck.vim already parses the templates, so it answers rather than a
# second reader of the same files.
"$vim_exe" -es -u NONE -N \
  -c 'set rtp+=.,deps/Logger' \
  -c 'source .github/scripts/latex-needs.vim' -c 'quit' || true

if [ ! -f "$report" ]; then
  echo "::warning::Vim never wrote $report, so nothing could be fetched in advance."
  exit 0
fi

while IFS= read -r name; do
  [ -z "$name" ] && continue
  echo "Looking for $name"
  kpsewhich "$name" || true
done < "$report"
