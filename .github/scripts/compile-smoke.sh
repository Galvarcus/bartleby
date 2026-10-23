#!/usr/bin/env bash

# Run the compile smoke tests with the pandoc that is first on PATH, and
# fail unless all of them pass. CI runs it once for each pandoc, so the
# results of one run are removed before the next.

set -u

rm -f tests/smoke_results.txt
pandoc --version | head -1

# Vim reports a failed test in the results file, not in its exit status.
vim -es -u NONE -N -V20/tmp/vim.log \
  -c 'set rtp+=.,deps/Logger' \
  -c 'source tests/test_compile_smoke.vim' -c 'quit' || true

if [ ! -f tests/smoke_results.txt ]; then
  echo "::error::tests/smoke_results.txt was never created. Vim likely failed before it finished. Its verbose log follows."
  cat /tmp/vim.log
  exit 1
fi

cat tests/smoke_results.txt
grep -qx 'All smoke tests passed' tests/smoke_results.txt
