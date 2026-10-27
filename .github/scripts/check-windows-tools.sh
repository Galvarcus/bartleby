#!/usr/bin/env bash

# Fail unless Vim can find the programs that the compile smoke tests need,
# and unless each of them runs. Every test of tests/test_compile_smoke.vim
# returns early when a program is missing, and the results file still reads
# that all of them passed, so a runner without the programs gives a green
# job that proved nothing. The Linux jobs have check-ci-image.sh for the
# same reason.
#
# Vim answers the first question, not the shell, because the PATH of the
# Git Bash and the PATH of Vim have already differed in this workflow, see
# the install-vim action.
#
# The second question is the one a cache raises. A MiKTeX restored from a
# cache entry was found by every lookup and could not compile, and the
# first sign of it was two tests timing out after a minute each with
# nothing said about why. A program that answers for its version is a
# program that runs.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/46

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

# The version comes from the standard output alone, because MiKTeX writes
# a warning about elevated privileges to the error output on every call and
# that would stand in for the version and read as a fault. The error output
# is what a failing program is asked for.
for tool in $tools; do
  if said=$("$tool" --version 2>/dev/null); then
    printf '%s runs: %s\n' "$tool" "$(printf '%s\n' "$said" | head -1)"
  else
    status=$?
    # The whole output on its own lines, because an annotation holds one
    # line and MiKTeX writes a preamble of its own before it says what
    # went wrong.
    echo "::error::$tool is on the PATH and exited $status. Everything it said follows."
    "$tool" --version 2>&1 || true
    exit 1
  fi
done
