#!/usr/bin/env bash

# Fail unless Vim itself finds the programs that the compile smoke tests
# need. Every test of tests/test_compile_smoke.vim returns early when a
# program is missing, and the results file still reads that all of them
# passed, so a runner without the programs gives a green job that proved
# nothing. The Linux jobs have check-ci-image.sh for the same reason.
#
# Vim answers, not the shell, because the PATH of the Git Bash and the PATH
# of Vim have already differed in this workflow, see the install-vim action.

set -u

vim_exe=${VIM_EXE:-vim}
tools='pandoc pdflatex xelatex'
report=tests/tools_results.txt

rm -f "$report"

"$vim_exe" -es -u NONE -N \
  -c "vim9cmd writefile(split('$tools')->filter((_, p) => !executable(p)), '$report')" \
  -c 'quit' || true

if [ ! -f "$report" ]; then
  echo "::error::Vim never wrote $report, so it failed before it could look for the programs."
  exit 1
fi

missing=$(tr '\n' ' ' < "$report" | sed 's/[[:space:]]*$//')
if [ -n "${missing// /}" ]; then
  echo "::error::Vim does not find these programs that the compile smoke tests need: $missing. Without them every test returns early and still reports that it passed."
  exit 1
fi

echo "Vim finds every program that the compile smoke tests need: $tools"
