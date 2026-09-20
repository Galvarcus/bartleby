vim9script
# tests/harness.vim - runs every test module's RunAll(), then reports via
# v:errors (populated automatically by every failed assert_*() call - see
# :help testing.txt). Each test_*.vim file exports a single RunAll(): void
# that calls its own (script-local) Test_* functions directly - simpler and
# more explicit than reflection-based test discovery, at the cost of one
# line here per test file.
#
# Usage: vim -es -u NONE -N -c 'set rtp+=/path/to/bartleby,/path/to/Logger' \
#          -c 'source tests/harness.vim' -c 'quit'
#
# -u NONE skips Vim's normal startup entirely, INCLUDING the automatic
# ':packloadall' that would otherwise put a pack/*/start/* install (e.g.
# ~/.vim/pack/vendor/start/bartleby) onto 'runtimepath' - so if Bartleby
# and Logger are installed that way rather than passed explicitly via
# rtp+=, run ':packloadall' first instead:
#   vim -es -u NONE -N -c 'packloadall' \
#     -c 'source tests/harness.vim' -c 'quit'
# Either way this must run from Bartleby's own repo root, since it reads
# and writes tests/results.txt with a path relative to the current
# directory.
#
# Exit code is 0 on success, 1 on any failed assertion (via cquit).

# plugin/bartleby.vim must be sourced before any autoload file that reads
# a g:bartleby_* global at its own script-load time (compile.vim does,
# for its Pandoc/screenplain binary paths) - in a real Vim session this
# always happens automatically (plugin/ loads at startup, autoload/ only
# lazily on first use), but a test harness that only imports autoload
# files directly skips that step unless done explicitly, here.
execute 'source ' .. expand('<sfile>:h:h') .. '/plugin/bartleby.vim'

import './test_tree.vim' as TestTree
import './test_mutate.vim' as TestMutate
import './test_document.vim' as TestDocument
import './test_compile.vim' as TestCompile
import './test_binder.vim' as TestBinder
import './test_syntax.vim' as TestSyntax
import './test_inputpopup.vim' as TestInputPopup
import './test_outliner.vim' as TestOutliner

var suites: list<func(): void> = [
  TestTree.RunAll,
  TestMutate.RunAll,
  TestDocument.RunAll,
  TestCompile.RunAll,
  TestBinder.RunAll,
  TestSyntax.RunAll,
  TestInputPopup.RunAll,
  TestOutliner.RunAll,
]

for RunSuite in suites
  RunSuite()
endfor

if len(v:errors) > 0
  writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/results.txt')
  cquit 1
else
  writefile(['All tests passed'], 'tests/results.txt')
endif
