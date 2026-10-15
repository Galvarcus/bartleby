vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# bartleby.vim: the plugin entry point, with the global settings, the
# commands, the mappings, and the autocommands. The work is done in
# autoload/bartleby, and this file only connects it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as S
import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/search.vim' as SE
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/profile.vim' as PR
import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/restore.vim' as R
import autoload 'bartleby/snapshot.vim' as SN
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/commandpalette.vim' as CP
import autoload 'bartleby/bartlebymenu.vim' as BM
import autoload 'bartleby/scrivelist.vim' as SL
import autoload 'bartleby/lexicon.vim' as LE
import autoload 'bartleby/lexiconpopup.vim' as LP
import autoload 'bartleby/autosave.vim' as A
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/tty.vim' as TY
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'bartleby/recover.vim' as RC
import autoload 'bartleby/layout.vim' as LY
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/closeall.vim' as CL
import autoload 'bartleby/progress.vim' as PG
import autoload 'bartleby/progressview.vim' as PV
import autoload 'bartleby/locale/common.vim' as MC
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))

# Every g:bartleby setting, with its default. -1 and empty strings mean
# not set, for settings with no real default, such as the Focus margins
# and the Spotlight conceal colors.
g:bartleby_binder_root = get(g:, 'bartleby_binder_root', expand('~/Documents'))
g:bartleby_language = get(g:, 'bartleby_language', '')
g:bartleby_session_auto_restore = get(g:, 'bartleby_session_auto_restore', false)
g:bartleby_autosave = get(g:, 'bartleby_autosave', true)
g:bartleby_autosave_interval = get(g:, 'bartleby_autosave_interval', 30)
# The hour, 0 to 23, at which a writing day starts, for the daily goal.
g:bartleby_day_starts_at = get(g:, 'bartleby_day_starts_at', 0)
# Add the writing progress to the status line when it has no setting of
# its own. vim-airline shows it in the section g:bartleby_airline_section.
g:bartleby_statusline = get(g:, 'bartleby_statusline', true)
g:bartleby_airline_section = get(g:, 'bartleby_airline_section', 'y')
g:bartleby_snapshot_retention = get(g:, 'bartleby_snapshot_retention', 5)
g:bartleby_binder_show_role_labels = get(g:, 'bartleby_binder_show_role_labels', true)
g:bartleby_focus_width = get(g:, 'bartleby_focus_width', 80)
g:bartleby_focus_height = get(g:, 'bartleby_focus_height', '85%')
g:bartleby_focus_margin_top = get(g:, 'bartleby_focus_margin_top', -1)
g:bartleby_focus_margin_bottom = get(g:, 'bartleby_focus_margin_bottom', -1)
g:bartleby_focus_linenr = get(g:, 'bartleby_focus_linenr', 0)
g:bartleby_focus_bg = get(g:, 'bartleby_focus_bg', 'black')
g:bartleby_focus_fullscreen = get(g:, 'bartleby_focus_fullscreen', false)
g:bartleby_focus_guifont = get(g:, 'bartleby_focus_guifont', '')
g:bartleby_tty_colors = get(g:, 'bartleby_tty_colors', true)
g:bartleby_spotlight_default_coefficient = get(g:, 'bartleby_spotlight_default_coefficient', 0.5)
g:bartleby_spotlight_conceal_guifg = get(g:, 'bartleby_spotlight_conceal_guifg', '')
g:bartleby_spotlight_conceal_ctermfg = get(g:, 'bartleby_spotlight_conceal_ctermfg', '')
g:bartleby_spotlight_bop = get(g:, 'bartleby_spotlight_bop', '^\s*$\n\zs')
g:bartleby_spotlight_eop = get(g:, 'bartleby_spotlight_eop', '^\s*$')
g:bartleby_spotlight_paragraph_span = get(g:, 'bartleby_spotlight_paragraph_span', 0)
g:bartleby_spotlight_priority = get(g:, 'bartleby_spotlight_priority', 10)
g:bartleby_spotlight_dialogue_pattern = get(g:, 'bartleby_spotlight_dialogue_pattern', '')
g:bartleby_spotlight_tagger = get(g:, 'bartleby_spotlight_tagger', '')
g:bartleby_spotlight_spacy_model = get(g:, 'bartleby_spotlight_spacy_model', '')
g:bartleby_spotlight_words_add = get(g:, 'bartleby_spotlight_words_add', {})
g:bartleby_spotlight_words_remove = get(g:, 'bartleby_spotlight_words_remove', {})
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
g:bartleby_compile_lang = get(g:, 'bartleby_compile_lang', '')
g:bartleby_compile_papersize = get(g:, 'bartleby_compile_papersize', '')
g:bartleby_compile_log_retention = get(g:, 'bartleby_compile_log_retention', 10)
g:bartleby_dictionary_api_key = get(g:, 'bartleby_dictionary_api_key', '')
g:bartleby_thesaurus_api_key = get(g:, 'bartleby_thesaurus_api_key', '')
g:bartleby_dictionary_reference = get(g:, 'bartleby_dictionary_reference', '')
g:bartleby_thesaurus_reference = get(g:, 'bartleby_thesaurus_reference', '')
g:bartleby_lexicon_cache_max_entries = get(g:, 'bartleby_lexicon_cache_max_entries', 1000)
g:bartleby_lexicon_timeout = get(g:, 'bartleby_lexicon_timeout', 10)
g:bartleby_lexicon_base_url = get(g:, 'bartleby_lexicon_base_url',
  'https://www.dictionaryapi.com/api/v3/references')

def OpenScrive(name: string): void
  var scriveName: string = name ==# '' ? fnamemodify(SS.LastScrive(), ':t:r') : name
  if scriveName ==# ''
    log.Warn(MI.NoScriveName())
    SL.Show()
    return
  endif
  var project: PO.Project = S.Open(scriveName)
  if project is null_object
    # A last scrive that was moved or deleted gets the same fallback as no
    # last scrive. A typed name that is wrong does not: its error is enough.
    if name ==# ''
      SL.Show()
    endif
    return
  endif
  ST.Set(project)
  StartScriveHooks()
  SS.RememberLastScrive(project.scriveDir)
  R.Restore(project)
enddef

# FUNCTION: Ask for the scrive type with PickOne, as the other pickers
# do, then create the scrive. Esc creates nothing.
def NewScrive(name: string): void
  PI.PickOne(MI.ScriveType(), CO.TYPES, (projectType: string) => {
    CreateScrive(name, projectType)
  }, CO.TYPE_NOVEL, PO.TypeNames())
enddef

def CreateScrive(name: string, projectType: string): void
  var project: PO.Project = S.Create(name, projectType)
  if project is null_object
    return
  endif
  ST.Set(project)
  StartScriveHooks()
  SS.RememberLastScrive(project.scriveDir)
  B.Show(project)
enddef

def ToggleBinder(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  B.Toggle(ST.Get())
enddef

def RunSearch(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  SE.Run(ST.Get())
enddef

command! -bar -nargs=? -complete=customlist,bartleby#scrive#CompleteNames
  \ BartlebyOpen OpenScrive(<q-args>)
command! -bar -nargs=1 BartlebyNewScrive NewScrive(<q-args>)
command! -bar BartlebyList SL.Show()
command! -bar BartlebyToggleBinder ToggleBinder()
command! -bar BartlebySearch RunSearch()
command! -bar BartlebyToggleInspector I.Toggle()
command! -bar -bang -nargs=? BartlebyFocus F.Execute('<bang>' ==# '!', <q-args>)
command! -bar -bang -nargs=? BartlebySpotlight SP.Execute('<bang>' ==# '!', <q-args>)
def EditProjectInfo(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  PR.EditForScrive(ST.Get())
enddef

# FUNCTION: Return the BinderItem of the current buffer in the open
# scrive, or null_object with a warning when no scrive is open or the
# buffer is not one of its documents.
def CurDoc(): BI.BinderItem
  var project: PO.Project = ST.Get()
  if project is null_object
    log.Warn(MC.NoScriveOpen())
    return null_object
  endif
  var doc: BI.BinderItem = SV.DocHere(project)
  if doc is null_object
    log.Warn(MI.CurBufNot())
  endif
  return doc
enddef

def SnapCurDoc(): void
  var project: PO.Project = ST.Get()
  var doc: BI.BinderItem = CurDoc()
  if doc is null_object
    return
  endif
  IP.PromptText(MC.SnapLabelOptional(), '', (label: string) => {
    SN.Take(project, doc, label)
  })
enddef

def ViewSnapsForCurDoc(): void
  var project: PO.Project = ST.Get()
  var doc: BI.BinderItem = CurDoc()
  if doc is null_object
    return
  endif
  var snaps: list<SN.Snap> = reverse(SN.List(project, doc))
  if empty(snaps)
    log.Info(MC.NoSnaps(doc.title))
    return
  endif
  var names: list<string> = snaps->mapnew((_, s) => s.DisplayName())
  PI.PickOne(MC.Snaps(), names, (choice: string) => {
    var snap: SN.Snap = snaps[index(names, choice)]
    PI.PickOne(MC.Msg(choice), ['Restore', CO.CANCEL], (action: string) => {
      if action ==# CO.ACTION_RESTORE
        SN.Restore(project, doc, snap)
      endif
    }, '', {Restore: MC.Restore(), Cancel: MC.Cancel()})
  })
enddef

command! -bar -nargs=? BartlebyQuill Q.Init(<q-args> ==# '' ? 'detect' : <q-args>)
command! -bar BartlebySnapshot SnapCurDoc()
command! -bar BartlebySnapshots ViewSnapsForCurDoc()
command! -bar BartlebyProfile PR.EditGlobal()
command! -bar BartlebyProjectInfo EditProjectInfo()

def RunCompile(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  C.Run(ST.Get())
enddef

command! -bar BartlebyCompile RunCompile()

def EmptyTrash(): void
  if ST.Get() is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  B.EmptyTrash(ST.Get())
enddef

command! -bar BartlebyEmptyTrash EmptyTrash()

# FUNCTION: Recover the documents that are on disk but not in the Binder.
# With no name, into the open scrive. With the name of a scrive whose
# project.json does not load, rebuild its Binder after a confirmation, see
# recover.vim, and open it.
def Recover(name: string): void
  if name ==# ''
    var project: PO.Project = ST.Get()
    if project is null_object
      log.Warn(MI.NoScriveOpen())
      return
    endif
    var count: number = RC.Recover(project)
    if count == 0
      log.Info(MI.EveryDocDisk())
      return
    endif
    project.Save()
    B.RenderIfOpen(project)
    log.Info(MI.RecoveredDocFolder(count))
    return
  endif
  var dir: string = S.ScrivePath(S.ResolveName(name))
  if !isdirectory(dir)
    log.Error(MC.NoScriveNamed(name, S.BinderRoot()))
    return
  endif
  if PO.Project.new(dir).Load()
    log.Info(MI.OpensOpenThen(name))
    return
  endif
  DP.Confirm(MI.RebuildBinderDamaged(name), () => {
    if RC.Rebuild(dir) isnot null_object
      OpenScrive(fnamemodify(dir, ':t:r'))
    endif
  })
enddef

command! -bar -nargs=? -complete=customlist,bartleby#scrive#CompleteNames
  \ BartlebyRecover Recover(<q-args>)

# FUNCTION: Move the files of the open scrive, so that the folders on disk
# follow the Binder, after a confirmation that says how many move. See
# layout.vim.
def TidyFiles(): void
  var project: PO.Project = ST.Get()
  if project is null_object
    log.Warn(MC.NoScriveOpen())
    return
  endif
  var moves: list<dict<any>> = LY.Plan(project)
  if empty(moves)
    log.Info(MI.FilesAlreadyFollow())
    return
  endif
  DP.Confirm(MI.MoveFileSo(len(moves)), () => {
    var failed: list<string> = LY.Tidy(project, moves)
    B.RenderIfOpen(project)
    if empty(failed)
      log.Info(MI.MovedFile(len(moves)))
    else
      log.Warn(MI.FilesDidNot(
        join(failed, ', ')))
    endif
  })
enddef

command! -bar BartlebyTidyFiles TidyFiles()

# FUNCTION: Open a Scrivening: from the Binder, of the folder under its
# cursor, and from a document, of the folder that holds it, at the line of
# the cursor. With close, save and close the open one instead. See
# scrivenings.vim.
def OpenScrivening(close: bool): void
  if close
    if !SV.IsOpen()
      log.Info(MI.NoScriveningOpen())
    elseif !SV.Close()
      log.Warn(MI.ScriveningStaysOpen())
    endif
    return
  endif
  if bufname() ==# CO.BINDER_BUF
    B.OpenScrivening()
    return
  endif
  var doc: BI.BinderItem = CurDoc()
  if doc is null_object
    return
  endif
  var project: PO.Project = ST.Get()
  var row: T.Row = T.FindRowById(T.Flatten(project), doc.id)
  if row is null_object || row.ownerItem is null_object
    log.Info(MC.ScriveningOpensOnly())
    return
  endif
  var offset: number = SV.IsScrivening(bufnr()) ? SV.LineInDoc() - 1 : line('.') - 1
  SV.Open(project, row.ownerItem, doc.id, offset)
enddef

command! -bar -bang BartlebyScrivenings OpenScrivening('<bang>' ==# '!')
command! -bar -bang BartlebyClose CL.All('<bang>' ==# '!')
command! -bar BartlebyGoals PV.EditGoals()
command! -bar BartlebyProgress PV.Show()
command! -bar BartlebyCommands CP.Open()
command! -bar BartlebyMenu BM.Toggle()
command! -bar -nargs=? BartlebyDefine LP.LookupCmd(CO.KIND_DICT, <q-args>)
command! -bar -nargs=? BartlebyThesaurus LP.LookupCmd(CO.KIND_THESAURUS, <q-args>)
command! -bar BartlebyLexiconClearCache LE.ClearCache()

nnoremap <silent> <leader>bi <ScriptCmd>I.Toggle()<CR>
nnoremap <silent> <leader>bz <ScriptCmd>F.Toggle()<CR>
nnoremap <silent> <leader>bl <ScriptCmd>SP.Toggle()<CR>
nnoremap <silent> <leader>bL <ScriptCmd>SP.PickMode()<CR>
nnoremap <silent> <leader>bp <ScriptCmd>Q.Toggle()<CR>
nnoremap <silent> <leader>b<Space> <ScriptCmd>CP.Open()<CR>
nnoremap <silent> <leader>bm <ScriptCmd>BM.Toggle()<CR>

# The lookup mappings exist only when their kind has an API key, set
# before Bartleby loads. The commands always exist and report what is
# missing.
if LE.IsEnabled(CO.KIND_DICT)
  nnoremap <silent> <leader>bd <ScriptCmd>LP.LookupAtCursor(CO.KIND_DICT)<CR>
  xnoremap <silent> <leader>bd <Esc><ScriptCmd>LP.LookupVisual(CO.KIND_DICT)<CR>
endif
if LE.IsEnabled(CO.KIND_THESAURUS)
  nnoremap <silent> <leader>bt <ScriptCmd>LP.LookupAtCursor(CO.KIND_THESAURUS)<CR>
  xnoremap <silent> <leader>bt <Esc><ScriptCmd>LP.LookupVisual(CO.KIND_THESAURUS)<CR>
endif

# Colors for a console with 8 or 16 colors, after the vimrc has chosen a
# color scheme or not. A plugin that loads late has missed VimEnter.
if v:vim_did_enter
  TY.AutoApply()
else
  augroup bartleby_tty_colors
    autocmd!
    # nested, so that the ColorScheme event of the scheme still fires.
    autocmd VimEnter * ++once ++nested TY.AutoApply()
  augroup END
endif

# FUNCTION: Start the hooks that serve an open scrive. Until a scrive
# opens, Vim runs none of them for the buffers it enters.
def StartScriveHooks(): void
  augroup bartleby_quill_auto
    autocmd!
    autocmd BufEnter * Q.AutoApply()
  augroup END
  # An empty edit window stays when the last one closes beside a pane.
  W.WatchEditWin()
  # Count the words for the goals on pauses and saves, never on each key.
  augroup bartleby_progress
    autocmd!
    autocmd CursorHold,CursorHoldI,InsertLeave,BufWritePost,BufEnter * PG.Refresh()
  augroup END
  PG.Refresh()
enddef

# FUNCTION: Add the writing progress to the status line, when the status
# line has no setting of its own and vim-airline does not draw it, as the
# default status line of Vim, with the ruler. See progress.vim.
def SetupStatusline(): void
  if !g:bartleby_statusline || exists('g:loaded_airline') || &g:statusline !=# ''
    return
  endif
  &g:statusline = '%<%f %h%m%r%=%( %{bartleby#progress#Status()}  %)%-14.(%l,%c%V%) %P'
enddef

augroup bartleby_statusline
  autocmd!
  autocmd VimEnter * SetupStatusline()
augroup END

def AutoRestoreSession(): void
  if g:bartleby_session_auto_restore && SS.LastScrive() !=# ''
    OpenScrive('')
  endif
enddef

# Auto-save for scrive documents, see autoload/bartleby/autosave.vim.
augroup bartleby_autosave
  autocmd!
  autocmd CursorHold,InsertLeave * A.Save(false)
  autocmd FocusLost,BufLeave * A.Save(true)
augroup END

augroup bartleby_session
  autocmd!
  autocmd CursorHold * SS.CaptureCurDoc()
  autocmd VimLeavePre * SS.CaptureCurDoc()
  autocmd VimEnter * AutoRestoreSession()
augroup END

if has('gui_running')
  BM.RegisterNative()
endif
