vim9script
# tests/test_compile_smoke.vim - gated smoke test for the real compile
# pipeline: does Pandoc/pdflatex/xelatex actually run to completion and
# produce a real, non-empty output file? Not a check of the output's
# visual correctness (see testing_feasibility_report.md - that's
# deliberately left to manual spot-checks), just that the external-tool
# invocation itself works end to end. Skips cleanly (exit 0) if the
# required binaries aren't installed, rather than failing for an
# unrelated reason - tests.yml's compile-smoke job installs them
# explicitly, but this stays safe to run without them too.
#
# job_start() is asynchronous, so this polls for the output file to
# appear rather than waiting on a return value. RunJob()'s success path
# calls a confirm() prompt (offering to open the result) - confirmed via
# direct experiment that confirm() returns its default choice immediately
# in headless -es mode rather than blocking, so this never hangs.
#
# Usage: same invocation shape as harness.vim (see its own usage comment).

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/project.vim' as Pj
import './fixtures.vim' as Fx

const MAX_WAIT_MS: number = 60000
const POLL_INTERVAL_MS: number = 500

# Polls OutputDir (project.scriveDir .. '/compile/output') for any file
# matching `pattern` to appear with non-zero size, up to MAX_WAIT_MS.
# Returns its path, or '' on timeout.
def WaitForOutput(project: Pj.Project, pattern: string): string
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
  var project = Fx.BuildProject()
  var chapter1 = project.ItemAt(1).ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  Fx.WriteDocContent(project, scene1, ['It was a dark and stormy night.'])
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
  Fx.CleanupProjectFiles(fx.project)
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
  Fx.CleanupProjectFiles(fx.project)
enddef

export def RunAll(): void
  Test_manuscript_pdf_compiles_to_a_real_nonempty_file()
  Test_book_pdf_compiles_to_a_real_nonempty_file()
enddef

execute 'source ' .. expand('<sfile>:h') .. '/../plugin/bartleby.vim'
RunAll()
if len(v:errors) > 0
  writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/smoke_results.txt')
  cquit 1
else
  writefile(['All smoke tests passed'], 'tests/smoke_results.txt')
endif
