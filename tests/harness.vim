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

import './test_tree.vim' as TT
import './test_mutate.vim' as TM
import './test_document.vim' as TD
import './test_compile.vim' as TC
import './test_compile_select.vim' as TCS
import './test_binder.vim' as TB
import './test_syntax.vim' as TSY
import './test_pos.vim' as TP
import './test_lang.vim' as TLA
import './test_i18n.vim' as TIN
import './test_profile.vim' as TPR
import './test_spotlight_pos.vim' as TSP
import './test_tty.vim' as TTY
import './test_trash.vim' as TTR
import './test_persist.vim' as TPE
import './test_recover.vim' as TRC
import './test_wordcount.vim' as TWC
import './test_session.vim' as TSE
import './test_inspector.vim' as TIS
import './test_templates.vim' as TTE
import './test_restore.vim' as TRE
import './test_corkboard.vim' as TCB
import './test_focus.vim' as TFO
import './test_layout.vim' as TLY
import './test_inputpopup.vim' as TI
import './test_dialog_popup.vim' as TDP
import './test_outliner.vim' as TO
import './test_scrivelist.vim' as TSL
import './test_scrive.vim' as TSC
import './test_lexicon.vim' as TL
import './test_binder_directory.vim' as TBD
import './test_autosave.vim' as TAU

var suites: list<func(): void> = [
  TT.RunAll,
  TM.RunAll,
  TD.RunAll,
  TC.RunAll,
  TCS.RunAll,
  TB.RunAll,
  TSY.RunAll,
  TP.RunAll,
  TLA.RunAll,
  TIN.RunAll,
  TPR.RunAll,
  TSP.RunAll,
  TTY.RunAll,
  TTR.RunAll,
  TPE.RunAll,
  TRC.RunAll,
  TWC.RunAll,
  TSE.RunAll,
  TIS.RunAll,
  TTE.RunAll,
  TRE.RunAll,
  TCB.RunAll,
  TFO.RunAll,
  TLY.RunAll,
  TI.RunAll,
  TDP.RunAll,
  TO.RunAll,
  TSL.RunAll,
  TSC.RunAll,
  TL.RunAll,
  TBD.RunAll,
  TAU.RunAll,
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
