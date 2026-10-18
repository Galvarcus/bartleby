vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_compile_smoke.vim: a gated smoke test of the real compile
# pipeline. Checks that Pandoc, pdflatex, and xelatex run to the end and
# write a real, nonempty file. It does not check how the output looks,
# which is left to manual checks, see testing_feasibility_report.md. When
# a program is not installed, the test is skipped with exit code 0
# instead of failing for an unrelated reason. The compile-smoke job of
# ci.yml installs the programs.
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
import autoload 'bartleby/project.vim' as PO
import './fixtures.vim' as FI

# The table filter, for the tests that run it by itself.
const TABLES_FILTER: string = expand('<sfile>:p:h:h') .. '/tools/pandoc/tables.lua'

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
  # A table with a caption and one without, so that every smoke compile
  # checks that the templates load what tables need, see tools/latex.
  FI.WriteDocContent(project, scene1, ['It was a dark and stormy night.', '',
    '| Name | Age |', '| :--- | --: |', '| Mara |  34 |', '', 'Table: The crew', '',
    '| Ship | Port |', '| ---- | ---- |', '| Wren | Hull |'])
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

# FUNCTION: Run tools/pandoc/tables.lua on md, to the format to, with the
# metadata meta, and return what Pandoc writes.
def Filter(md: list<string>, to: string, meta: list<string>): string
  var src: string = tempname()
  writefile(md, src)
  var out: string = system(join(['pandoc', shellescape(src), '-t', to,
    '--lua-filter=' .. shellescape(TABLES_FILTER)] + meta->mapnew((_, m) => '-M ' .. shellescape(m))))
  delete(src)
  return out
enddef

# FUNCTION: A real compile passes the table settings on: the header style
# through the filter, and the lines through the override CSS.
def Test_book_html_tables_get_the_settings(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var fx = BuildProjectWithContent()
  var target = C.CompileTarget.FromDict({
    name: 'SmokeTables', kind: 'Book', format: 'HTML',
    includedIds: [fx.scene1.id],
  })
  C.Execute(fx.project, target)
  var outputPath = WaitForOutput(fx.project, '*.html')
  assert_true(outputPath !=# '', 'Book HTML did not appear within ' .. MAX_WAIT_MS .. 'ms')
  if outputPath !=# ''
    var html: string = join(readfile(outputPath), "\n")
    assert_match('<th[^>]*><em>Name</em></th>', html)
    var css: string = join(readfile(fnamemodify(outputPath, ':h') .. '/.override.css'), "\n")
    assert_match('table { border:', css)
    assert_match('border-left', css)
  endif
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_the_table_filter_draws_lines_only_when_asked(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var md: list<string> = ['| Name | Age |', '|:--|--:|', '| Mara | 34 |']
  var both: string = Filter(md, 'latex', ['table-border=single', 'table-vlines=single'])
  assert_match('\\begin{longtable}\[\]{|l|r|}', both)
  assert_notmatch('\\toprule', both)
  assert_match('{@{}l|r@{}}', Filter(md, 'latex', ['table-vlines=single']))
  var none: string = Filter(md, 'latex', [])
  assert_match('{@{}lr@{}}', none)
  assert_match('\\toprule', none)
enddef

def Test_the_table_filter_styles_the_header(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var md: list<string> = ['| Name | Age |', '|:--|--:|', '| Mara | 34 |']
  assert_match('\\textbf{Name}', Filter(md, 'latex', []))
  assert_match('\\emph{Name}', Filter(md, 'latex', ['table-header=italic']))
  assert_match('<span class="smallcaps">Name</span>', Filter(md, 'html', ['table-header=smallcaps']))
  assert_notmatch('<strong>', Filter(md, 'html', ['table-header=plain']))
enddef

# FUNCTION: The rules take their width from the columns, so that a table of
# long cells is no wider than the text.
def Test_the_table_filter_keeps_the_width_with_rules(): void
  if !executable('pandoc')
    echom 'SKIP: pandoc not installed'
    return
  endif
  var long: string = repeat('a long note about the voyage north ', 6)
  var md: list<string> = ['| Name | Notes |', '|:--|:--|', $'| Mara | {long} |']
  var tex: string = Filter(md, 'latex', ['table-border=single', 'table-vlines=single'])
  assert_match('\\\%(line\|column\)width - 4\\tabcolsep - 3\\arrayrulewidth', tex)
enddef

export def RunAll(): void
  Test_manuscript_pdf_compiles_to_a_real_nonempty_file()
  Test_book_pdf_compiles_to_a_real_nonempty_file()
  Test_pandoc_log_per_run_with_retention()
  Test_failure_writes_a_log_and_asks_to_open_it()
  Test_book_html_tables_get_the_settings()
  Test_the_table_filter_draws_lines_only_when_asked()
  Test_the_table_filter_styles_the_header()
  Test_the_table_filter_keeps_the_width_with_rules()
enddef

# A private home folder, so that the log test counts only its own logs,
# and a small retention. Both are set before Bartleby loads, because
# compile.vim reads the retention setting once, when it loads.
$HOME = tempname()
mkdir($HOME, 'p')
g:bartleby_compile_log_retention = 2
# The table lines and an italic header, so that the PDFs of these tests go
# through tools/pandoc/tables.lua, the way with more to go wrong. The
# default way is in the filter tests.
g:bartleby_compile_table_border = 'single'
g:bartleby_compile_table_vlines = 'single'
g:bartleby_compile_table_header = 'italic'
execute 'source ' .. expand('<sfile>:h') .. '/../plugin/bartleby.vim'
RunAll()
if len(v:errors) > 0
  writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/smoke_results.txt')
  cquit 1
else
  writefile(['All smoke tests passed'], 'tests/smoke_results.txt')
endif
