vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/harness.vim: runs the RunAll function of every test module, then
# reports the failures in v:errors, which every failed assert function
# fills, see :help testing.txt. Each test_*.vim file exports one RunAll
# that calls its own Test functions. Simpler and clearer than finding
# tests by reflection, for the cost of one line here per test file.
#
# Usage: vim -es -u NONE -N -c 'set rtp+=/path/to/bartleby,/path/to/Logger' \
#          -c 'source tests/harness.vim' -c 'quit'
#
# -u NONE skips Vim's normal startup, including the automatic
# :packloadall that adds a pack/*/start install, such as
# ~/.vim/pack/vendor/start/bartleby, to runtimepath. When Bartleby and
# Logger are installed that way, run :packloadall first instead of rtp+=:
#   vim -es -u NONE -N -c 'packloadall' \
#     -c 'source tests/harness.vim' -c 'quit'
# Run it from the root of the Bartleby repository, because it writes
# tests/results.txt relative to the current folder.
#
# The exit code is 0 on success and 1 on any failed assertion, with cquit.
# License: GNU GPL 3.0
##############################################################################
# Tests contain UTF-8 text such as curly apostrophes. Without a UTF-8
# locale, with LANG unset, Vim starts with encoding latin1 and reads each
# such character as several bytes. Set it here, before any script or
# buffer loads, so results do not depend on the environment.
set encoding=utf-8

# Source plugin/bartleby.vim before any autoload file that reads a
# g:bartleby setting when it loads, as compile.vim does for the paths of
# Pandoc and screenplain. In a Vim session, plugin files load at startup
# and autoload files later, on first use. A harness that imports autoload
# files directly must do this itself.
execute 'source ' .. expand('<sfile>:h:h') .. '/plugin/bartleby.vim'

import './test_tree.vim' as TestTree
import './test_mutate.vim' as TestMutate
import './test_document.vim' as TestDocument
import './test_compile.vim' as TestCompile
import './test_compile_select.vim' as TestCompileSelect
import './test_binder.vim' as TestBinder
import './test_syntax.vim' as TestSyntax
import './test_pos.vim' as TestPos
import './test_spotlight_pos.vim' as TestSpotlightPos
import './test_inputpopup.vim' as TestInputPopup
import './test_outliner.vim' as TestOutliner
import './test_scrivelist.vim' as TestScriveList
import './test_lexicon.vim' as TestLexicon
import './test_binder_directory.vim' as TestBinderDirectory
import './test_autosave.vim' as TestAutoSave

var suites: list<func(): void> = [
  TestTree.RunAll,
  TestMutate.RunAll,
  TestDocument.RunAll,
  TestCompile.RunAll,
  TestCompileSelect.RunAll,
  TestBinder.RunAll,
  TestSyntax.RunAll,
  TestPos.RunAll,
  TestSpotlightPos.RunAll,
  TestInputPopup.RunAll,
  TestOutliner.RunAll,
  TestScriveList.RunAll,
  TestLexicon.RunAll,
  TestBinderDirectory.RunAll,
  TestAutoSave.RunAll,
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
