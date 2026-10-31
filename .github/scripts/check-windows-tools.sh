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
font_report=tests/font_results.txt

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

# The font the Book compiles ask for, which a leg that cannot resolve it
# answers with two tests timing out after three minutes each. The family
# is named once, in tests/fixtures.vim, and smoke-font.vim reads it there
# for this check, so the suite and the check cannot ask for two fonts.
#
# The assertion is a compile, not a listing: the fc-list of the MiKTeX
# tree reads a fontconfig cache that the cache entry can carry, so it
# reports a font that this runner may not be able to use, and a probe of
# four routes found the compile to be the only reliable answer.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/68
rm -f "$font_report"

"$vim_exe" -es -u NONE -N \
  -c 'set rtp+=.,deps/Logger' \
  -c 'source .github/scripts/smoke-font.vim' -c 'quit' || true

if [ ! -f "$font_report" ]; then
  echo "::error::Vim never wrote $font_report, so the font that the Book compiles ask for could not be read."
  exit 1
fi

font=$(head -1 "$font_report" | tr -d '\r')
if [ -z "$font" ]; then
  echo "::error::$font_report holds no font family."
  exit 1
fi

probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
cat > "$probe/font.tex" <<TEX
\\documentclass{article}
\\usepackage{fontspec}
\\setmainfont{$font}
\\begin{document}
The engine resolved the font of this line.
\\end{document}
TEX

if ( cd "$probe" && xelatex -interaction=nonstopmode -halt-on-error font.tex ) \
  >"$probe/out" 2>&1 && [ -s "$probe/font.pdf" ]; then
  echo "xelatex resolves $font"
else
  echo "::error::xelatex cannot resolve the font $font, which the Book compiles of the smoke suite ask for. Every PDF test of that suite would time out. What xelatex said follows."
  cat "$probe/out"
  exit 1
fi
