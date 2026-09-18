vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# bartleby.vim - plugin entry point: global config + user commands. All real
# logic lives in autoload/bartleby/*.vim; this file only wires them up.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as Sc
import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/search.vim' as Se
import autoload 'bartleby/state.vim' as St
import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/spotlight.vim' as Sp
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/profile.vim' as Pf
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/session.vim' as Sess
import autoload 'bartleby/snapshot.vim' as Sn
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/picker.vim' as Pk
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))

# All g:bartleby_* globals, defaulted here. -1/'' sentinels mark "user
# did not set this" for options with no real default (focus margins,
# spotlight conceal colors).
g:bartleby_binder_root = get(g:, 'bartleby_binder_root', expand('~/Documents'))
g:bartleby_session_auto_restore = get(g:, 'bartleby_session_auto_restore', false)
g:bartleby_snapshot_retention = get(g:, 'bartleby_snapshot_retention', 5)
g:bartleby_binder_show_role_labels = get(g:, 'bartleby_binder_show_role_labels', true)
g:bartleby_focus_width = get(g:, 'bartleby_focus_width', 80)
g:bartleby_focus_height = get(g:, 'bartleby_focus_height', '85%')
g:bartleby_focus_margin_top = get(g:, 'bartleby_focus_margin_top', -1)
g:bartleby_focus_margin_bottom = get(g:, 'bartleby_focus_margin_bottom', -1)
g:bartleby_focus_linenr = get(g:, 'bartleby_focus_linenr', 0)
g:bartleby_focus_bg = get(g:, 'bartleby_focus_bg', 'black')
g:bartleby_spotlight_default_coefficient = get(g:, 'bartleby_spotlight_default_coefficient', 0.5)
g:bartleby_spotlight_conceal_guifg = get(g:, 'bartleby_spotlight_conceal_guifg', '')
g:bartleby_spotlight_conceal_ctermfg = get(g:, 'bartleby_spotlight_conceal_ctermfg', '')
g:bartleby_spotlight_bop = get(g:, 'bartleby_spotlight_bop', '^\s*$\n\zs')
g:bartleby_spotlight_eop = get(g:, 'bartleby_spotlight_eop', '^\s*$')
g:bartleby_spotlight_paragraph_span = get(g:, 'bartleby_spotlight_paragraph_span', 0)
g:bartleby_spotlight_priority = get(g:, 'bartleby_spotlight_priority', 10)
g:bartleby_spotlight_dialogue_pattern = get(g:, 'bartleby_spotlight_dialogue_pattern',
  '"[^"]*"\|"[^"]*"')
g:bartleby_quill_wrap_mode_default = get(g:, 'bartleby_quill_wrap_mode_default', 'hard')
g:bartleby_quill_textwidth = get(g:, 'bartleby_quill_textwidth', 74)
g:bartleby_quill_autoformat = get(g:, 'bartleby_quill_autoformat', true)
g:bartleby_quill_autoformat_config = get(g:, 'bartleby_quill_autoformat_config', {
  markdown: {
    black: [
      'htmlH[0-9]',
      'markdown(Code|H[0-9]|Url|IdDeclaration|Link|Rule|Highlight[A-Za-z0-9]+)',
      'markdown(FencedCodeBlock|InlineCode|YamlHead)',
    ],
    white: ['markdown(Code|Link)'],
  },
})
g:bartleby_quill_autoformat_aliases = get(g:, 'bartleby_quill_autoformat_aliases',
  {md: 'markdown', mkd: 'markdown', fountain: 'markdown'})
g:bartleby_quill_joinspaces = get(g:, 'bartleby_quill_joinspaces', false)
g:bartleby_quill_cursorwrap = get(g:, 'bartleby_quill_cursorwrap', true)
g:bartleby_quill_conceallevel = get(g:, 'bartleby_quill_conceallevel', 3)
g:bartleby_quill_concealcursor = get(g:, 'bartleby_quill_concealcursor', 'c')
g:bartleby_quill_soft_detect_sample = get(g:, 'bartleby_quill_soft_detect_sample', 20)
g:bartleby_quill_soft_detect_threshold = get(g:, 'bartleby_quill_soft_detect_threshold', 130)
g:bartleby_quill_mode_indicators = get(g:, 'bartleby_quill_mode_indicators',
  {hard: 'H', auto: 'A', soft: 'S', off: ''})
g:bartleby_quill_auto = get(g:, 'bartleby_quill_auto', true)
g:bartleby_compile_pandoc_bin = get(g:, 'bartleby_compile_pandoc_bin', 'pandoc')
g:bartleby_compile_screenplain_bin = get(g:, 'bartleby_compile_screenplain_bin', 'screenplain')
g:bartleby_compile_toc = get(g:, 'bartleby_compile_toc', false)
g:bartleby_compile_standalone = get(g:, 'bartleby_compile_standalone', true)
g:bartleby_compile_manuscript_font = get(g:, 'bartleby_compile_manuscript_font', 'Courier New')
g:bartleby_compile_book_font = get(g:, 'bartleby_compile_book_font', 'Georgia')
g:bartleby_compile_screenplay_font = get(g:, 'bartleby_compile_screenplay_font', 'Courier Prime')
g:bartleby_compile_manuscript_double_spaced = get(g:, 'bartleby_compile_manuscript_double_spaced', true)
g:bartleby_compile_indent_paragraphs = get(g:, 'bartleby_compile_indent_paragraphs', true)
g:bartleby_compile_book_chapter_style = get(g:, 'bartleby_compile_book_chapter_style', 'numeral')
g:bartleby_compile_book_part_style = get(g:, 'bartleby_compile_book_part_style', 'numeral')
g:bartleby_compile_extra_args = get(g:, 'bartleby_compile_extra_args', [])

# Built-in confirm() prompt for the four scrive types, used at creation
# time. A popupbuttons.vim/menu.vim-backed picker can replace this once a
# proper prompt widget is wired into the plugin - this is just the built-in
# stopgap so New Scrive doesn't need the type on the command line.
def PromptProjectType(): string
  var choice: number = confirm(
    'Scrive type?',
    "&Novel\nNovel with &Parts\n&Short Story\n&Screenplay",
    1)
  if choice == 2
    return Pj.TYPE_NOVEL_PARTS
  elseif choice == 3
    return Pj.TYPE_SHORT_STORY
  elseif choice == 4
    return Pj.TYPE_SCREENPLAY
  else
    return Pj.TYPE_NOVEL
  endif
enddef

def OpenScrive(name: string): void
  var scriveName: string = name ==# '' ? fnamemodify(Sess.LastScrive(), ':t:r') : name
  if scriveName ==# ''
    log.Warn('no scrive name given, and no previously-opened scrive to fall back to')
    return
  endif
  var project: Pj.Project = Sc.Open(scriveName)
  if project is null_object
    return
  endif
  St.Set(project)
  Sess.RememberLastScrive(project.scriveDir)
  Sess.Restore(project)
enddef

def NewScrive(name: string): void
  var projectType: string = PromptProjectType()
  var project: Pj.Project = Sc.Create(name, projectType)
  if project is null_object
    return
  endif
  St.Set(project)
  Sess.RememberLastScrive(project.scriveDir)
  B.Show(project)
enddef

def ToggleBinder(): void
  if St.Get() is null_object
    log.Warn('no scrive open - run :BartlebyOpen <name> first')
    return
  endif
  B.Toggle(St.Get())
enddef

def RunSearch(): void
  if St.Get() is null_object
    log.Warn('no scrive open - run :BartlebyOpen <name> first')
    return
  endif
  Se.Run(St.Get())
enddef

# Tab-completion for scrive names is deferred until custom-completion syntax
# is confirmed against the 9.2 test target - flag if you'd like it sooner.
command! -bar -nargs=? BartlebyOpen OpenScrive(<q-args>)
command! -bar -nargs=1 BartlebyNewScrive NewScrive(<q-args>)
command! -bar BartlebyToggleBinder ToggleBinder()
command! -bar BartlebySearch RunSearch()
command! -bar BartlebyToggleInspector I.Toggle()
command! -bar -bang -nargs=? BartlebyFocus F.Execute('<bang>' ==# '!', <q-args>)
command! -bar -bang -nargs=? BartlebySpotlight Sp.Execute('<bang>' ==# '!', <q-args>)
def EditProjectInfo(): void
  if St.Get() is null_object
    log.Warn('no scrive open - run :BartlebyOpen <name> first')
    return
  endif
  Pf.EditForScrive(St.Get())
enddef

# Resolves the current buffer to a BinderItem of the open scrive, or
# null_object (with a warning) if there's no open scrive or the current
# buffer isn't one of its documents.
def CurrentDoc(): BI.BinderItem
  var project: Pj.Project = St.Get()
  if project is null_object
    log.Warn('no scrive open - run :BartlebyOpen <name> first')
    return null_object
  endif
  var doc: BI.BinderItem = project.FindItemByPath(expand('%:p'))
  if doc is null_object
    log.Warn('current buffer is not a document of the open scrive')
  endif
  return doc
enddef

def SnapshotCurrentDoc(): void
  var project: Pj.Project = St.Get()
  var doc: BI.BinderItem = CurrentDoc()
  if doc is null_object
    return
  endif
  IP.PromptText('Snapshot label (optional)', '', (label: string) => {
    Sn.Take(project, doc, label)
  })
enddef

def ViewSnapshotsForCurrentDoc(): void
  var project: Pj.Project = St.Get()
  var doc: BI.BinderItem = CurrentDoc()
  if doc is null_object
    return
  endif
  var snapshots: list<Sn.Snapshot> = reverse(Sn.List(project, doc))
  if empty(snapshots)
    log.Info($'no snapshots for "{doc.title}"')
    return
  endif
  var names: list<string> = snapshots->mapnew((_, s) => s.DisplayName())
  Pk.PickOne('Snapshots', names, (choice: string) => {
    var snapshot: Sn.Snapshot = snapshots[index(names, choice)]
    Pk.PickOne($' {choice} ', ['Restore', 'Cancel'], (action: string) => {
      if action ==# 'Restore'
        Sn.Restore(project, doc, snapshot)
      endif
    })
  })
enddef

command! -bar -nargs=? BartlebyQuill Q.Init(<q-args> ==# '' ? 'detect' : <q-args>)
command! -bar BartlebySnapshot SnapshotCurrentDoc()
command! -bar BartlebySnapshots ViewSnapshotsForCurrentDoc()
command! -bar BartlebyProfile Pf.EditGlobal()
command! -bar BartlebyProjectInfo EditProjectInfo()

def RunCompile(): void
  if St.Get() is null_object
    log.Warn('no scrive open - run :BartlebyOpen <name> first')
    return
  endif
  C.Run(St.Get())
enddef

command! -bar BartlebyCompile RunCompile()

nnoremap <silent> <leader>bi <ScriptCmd>I.Toggle()<CR>
nnoremap <silent> <leader>bz <ScriptCmd>F.Toggle()<CR>
nnoremap <silent> <leader>bl <ScriptCmd>Sp.Toggle()<CR>
nnoremap <silent> <leader>bL <ScriptCmd>Sp.PickMode()<CR>
nnoremap <silent> <leader>bp <ScriptCmd>Q.Toggle()<CR>

augroup bartleby_quill_auto
  autocmd!
  autocmd BufEnter * Q.AutoApply()
augroup END

def AutoRestoreSession(): void
  if g:bartleby_session_auto_restore && Sess.LastScrive() !=# ''
    OpenScrive('')
  endif
enddef

augroup bartleby_session
  autocmd!
  autocmd CursorHold * Sess.CaptureCurrentDoc()
  autocmd VimLeavePre * Sess.CaptureCurrentDoc()
  autocmd VimEnter * AutoRestoreSession()
augroup END
