vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_compile_smoke.vim: a gated smoke test of the real compile
# pipeline. Checks that Pandoc, pdflatex, and xelatex run to the end and
# write a real, nonempty file. It does not check how the output looks,
# which is left to manual checks, see testing_feasibility_report.md. When
# a program is not installed, the test is skipped with exit code 0
# instead of failing for an unrelated reason. The compile-smoke job of
# tests.yml installs the programs.
#
# job_start is asynchronous, so the test polls for the output file
# instead of waiting for a return value. On success RunJob asks whether
# to open the result, in a popup from dialog_popup.vim. The popup does
# not wait for an answer, so the test never hangs.
#
# Usage: the same command as tests/harness.vim, see its header.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as PO
import './fixtures.vim' as FI

const MAX_WAIT_MS: number = 60000
const POLL_INTERVAL_MS: number = 500

# FUNCTION: Wait for a file matching pattern in the output folder,
# project.scriveDir/compile/output, with a size above 0, up to
# MAX_WAIT_MS. Return its path, or an empty string after the wait.
def WaitForOutput(project: PO.Project, pattern: string): string
  var outDir: string = project.scriveDir .. '/compile/output'
  var waited: number = 0
  while waited < MAX_WAIT_MS
    var matches: list<string> = glob(outDir .. '/' .. pattern, false, true)
      ->filter((_, f) => getfsize(f) > 0)
    if !empty(matches)
      return matches[0]
    endif
    execute $'sleep {POLL_INTERVAL_MS}m'
    waited += POLL_INTERVAL_MS
  endwhile
  return ''
enddef

def BuildProjectWithContent(): dict<any>
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  FI.WriteDocContent(project, scene1, ['It was a dark and stormy night.'])
  return {project: project, scene1: scene1}
enddef

def Test_manuscript_pdf_compiles_to_a_real_nonempty_file(): void
  if !executable('pandoc') || !executable('pdflatex')
    echom 'SKIP: pandoc/pdflatex not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({
    name: 'SmokeManuscript', kind: 'Manuscript', format: 'PDF',
    includedIds: [fx.scene1.id],
  })
  C.Execute(fx.project, target)
  var outputPath = WaitForOutput(fx.project, '*.pdf')
  assert_true(outputPath !=# '', 'Manuscript PDF did not appear within ' .. MAX_WAIT_MS .. 'ms')
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_book_pdf_compiles_to_a_real_nonempty_file(): void
  if !executable('pandoc') || !executable('xelatex')
    echom 'SKIP: pandoc/xelatex not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({
    name: 'SmokeBook', kind: 'Book', format: 'PDF', font: 'DejaVu Serif',
    includedIds: [fx.scene1.id],
  })
  C.Execute(fx.project, target)
  var outputPath = WaitForOutput(fx.project, '*.pdf')
  assert_true(outputPath !=# '', 'Book PDF did not appear within ' .. MAX_WAIT_MS .. 'ms')
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: Wait until logDir has a log whose name is not in before, and
# return it, or an empty string after MAX_WAIT_MS. Pandoc writes its log
# file when it ends, so a new name means that run is done.
def WaitForNewLog(logDir: string, before: list<string>): string
  var waited: number = 0
  while waited < MAX_WAIT_MS
    for path in glob(logDir .. '/*.json', false, true)
      if index(before, path) < 0
        return path
      endif
    endfor
    execute $'sleep {POLL_INTERVAL_MS}m'
    waited += POLL_INTERVAL_MS
  endwhile
  return ''
enddef

# FUNCTION: Run three Book compiles to HTML, with Pandoc only and no
# LaTeX, with g:bartleby_compile_log_retention set to 2 at the end of
# this file, before Bartleby loads. Each run must write a new timestamped
# JSON log, and only the 2 newest may remain.
def Test_pandoc_log_per_run_with_retention(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({
    name: 'Smoke Log', kind: 'Book', format: 'HTML', includedIds: [fx.scene1.id],
  })
  var logDir: string = expand('~/.bartleby/logs')
  for run in range(3)
    var before: list<string> = glob(logDir .. '/*.json', false, true)
    C.Execute(fx.project, target)
    var newLog: string = WaitForNewLog(logDir, before)
    assert_true(newLog !=# '', $'run {run + 1} wrote no log within {MAX_WAIT_MS}ms')
    if newLog !=# ''
      assert_match('/bartleby-test-fixture_smoke-log_\d\{8}-\d\{6}\.json$', newLog)
      assert_equal(v:t_list, type(json_decode(join(readfile(newLog), "\n"))))
    endif
    # Log names show the time to the second.
    sleep 1100m
  endfor
  # Only this target's logs: the other smoke tests write logs here too.
  assert_equal(2, len(glob(logDir .. '/bartleby-test-fixture_smoke-log_*.json', false, true)))
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: A Book PDF with a font that does not exist, so xelatex fails.
# Pandoc writes no log on failure, so Bartleby must write a .log file with
# the error output, and ask whether to open it.
def Test_failure_writes_a_log_and_asks_to_open_it(): void
  if !executable('pandoc') || !executable('xelatex')
    echom 'SKIP: pandoc/xelatex not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({
    name: 'Smoke Fail', kind: 'Book', format: 'PDF', font: 'No Such Font Xyzzy',
    includedIds: [fx.scene1.id],
  })
  var logDir: string = expand('~/.bartleby/logs')
  C.Execute(fx.project, target)
  var failLog: string = ''
  var waited: number = 0
  while failLog ==# '' && waited < MAX_WAIT_MS
    sleep 500m
    waited += 500
    failLog = get(glob(logDir .. '/bartleby-test-fixture_smoke-fail_*.log', false, true), 0, '')
  endwhile
  assert_true(failLog !=# '', 'no failure log within ' .. MAX_WAIT_MS .. 'ms')
  if failLog !=# ''
    var text: list<string> = readfile(failLog)
    assert_match('^Command: pandoc', text[0])
    assert_match('^Exit status: [1-9]', text[1])
    assert_true(len(text) > 3, 'the failure log has no error output')
  endif
  var questions = popup_list()->filter((_, id) => join(getbufline(winbufnr(id), 1, '$')) =~# 'failed')
  assert_equal(1, len(questions), 'no question to open the log')
  for id in popup_list()
    popup_close(id)
  endfor
  FI.CleanupProjectFiles(fx.project)
enddef

export def RunAll(): void
  Test_manuscript_pdf_compiles_to_a_real_nonempty_file()
  Test_book_pdf_compiles_to_a_real_nonempty_file()
  Test_pandoc_log_per_run_with_retention()
  Test_failure_writes_a_log_and_asks_to_open_it()
enddef

# A private home folder, so that the log test counts only its own logs,
# and a small retention. Both are set before Bartleby loads, because
# compile.vim reads the retention setting once, when it loads.
$HOME = tempname()
mkdir($HOME, 'p')
g:bartleby_compile_log_retention = 2
execute 'source ' .. expand('<sfile>:h') .. '/../plugin/bartleby.vim'
RunAll()
if len(v:errors) > 0
  writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/smoke_results.txt')
  cquit 1
else
  writefile(['All smoke tests passed'], 'tests/smoke_results.txt')
endif
