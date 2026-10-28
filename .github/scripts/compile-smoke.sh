#!/usr/bin/env bash

# Run the compile smoke tests with the pandoc that is first on PATH, and
# fail unless all of them pass. CI runs it in a job for each pandoc, and
# it clears the results of an earlier run first.
#
# VIM_EXE names the Vim to run, because the Git Bash of a Windows runner
# carries a Vim of its own that comes first, see .github/actions/install-vim.
# VIM_LOG and VIM_VERBOSE carry the log, because a path of Windows does not
# survive the shell, and level 20 writes every Ex command, which on Windows
# grows faster than the tests run. The defaults are what the Linux jobs
# used before they could be set.

set -u

vim_exe=${VIM_EXE:-vim}
vim_log=${VIM_LOG:-/tmp/vim.log}
vim_verbose=${VIM_VERBOSE:-20}

rm -f tests/smoke_results.txt
pandoc --version | head -1

# Vim reports a failed test in the results file, not in its exit status.
"$vim_exe" -es -u NONE -N "-V${vim_verbose}${vim_log}" \
  -c 'set rtp+=.,deps/Logger' \
  -c 'source tests/test_compile_smoke.vim' -c 'quit' || true

if [ ! -f tests/smoke_results.txt ]; then
  echo "::error::tests/smoke_results.txt was never created. Vim likely failed before it finished. Its verbose log follows."
  cat "$vim_log"
  exit 1
fi

cat tests/smoke_results.txt
if grep -qx 'All smoke tests passed' tests/smoke_results.txt; then
  exit 0
fi

# What the compile said, which no job has ever printed. A test reports
# only that no PDF appeared within its minute, and the reason is in the
# log that Bartleby writes for each run. The tests set a private HOME
# under the temporary folder, so the logs are found there rather than at
# a path this script could name.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/46
temp=${TEMP:-${TMPDIR:-/tmp}}
temp=${temp//\\//}
logs=$(find "$temp" -path '*/.bartleby/logs/*' -type f 2>/dev/null | sort | tail -4)
if [ -z "$logs" ]; then
  echo "::warning::No log of Bartleby lies under $temp, so the compile said nothing that this script can read."
else
  for log in $logs; do
    echo "--- $log"
    cat "$log"
    echo
  done
fi
exit 1
