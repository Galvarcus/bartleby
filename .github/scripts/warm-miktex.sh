#!/usr/bin/env bash

# Make MiKTeX ready before the tests run. Each test allows a compile the
# time that MAX_WAIT_MS gives it in tests/test_compile_smoke.vim, and work
# inside that time fails the test as though the compile itself were
# broken.
#
# Two costs, and both are paid here. A missing file, which MiKTeX fetches
# during a plain kpsewhich. And the format of an engine, which MiKTeX
# builds when that engine first runs: a lookup never runs one, so the
# first real compile paid for it and came within ten seconds of the limit,
# then over it.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/45
#
# A failure here is not an error. The work is an optimisation, and
# AutoInstall stays on to catch whatever this misses, see
# .github/scripts/make-portable-miktex.sh, which sets it in the tree.

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

# The lookup is run for its effect, which is an install of whatever is
# missing, so only its answer is printed. MiKTeX writes two lines of its
# own to the error output on every call, one about elevated privileges and
# one about never having checked for updates, which came to 26 lines that
# said nothing about this job.
while IFS= read -r name; do
  [ -z "$name" ] && continue
  if found=$(kpsewhich "$name" 2>/dev/null); then
    printf '%s is at %s\n' "$name" "$found"
  else
    printf '%s was not found, so nothing could be fetched for it in advance.\n' "$name"
  fi
done < "$report"

# Run each engine on each class the templates use, so that the format is
# built and the class loads whatever it loads. The class comes from the
# same list, so nothing here repeats what the templates already say.
warm=$(mktemp -d)
trap 'rm -rf "$warm"' EXIT

while IFS= read -r name; do
  case "$name" in
    *.cls) ;;
    *) continue ;;
  esac
  printf '\\documentclass{%s}\n\\begin{document}x\\end{document}\n' \
    "${name%.cls}" > "$warm/warm.tex"
  for engine in pdflatex xelatex; do
    echo "Warming $engine on ${name%.cls}"
    ( cd "$warm" && "$engine" -interaction=nonstopmode warm.tex >/dev/null 2>&1 ) || true
  done
done < "$report"
