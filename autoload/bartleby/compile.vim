vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# compile.vim - Compile pipeline (v2). Three independent export paths:
#   Manuscript (short story/novel/novel w/ parts) - submission PDF only,
#     via xelatex + tools/latex/manuscript.tex.
#   Book (short story/novel/novel w/ parts) - reader-facing PDF/HTML/
#     EPUB/Markdown, via xelatex + tools/latex/book.tex or Pandoc's own
#     HTML/EPUB writers + tools/css/book.css.
#   Screenplay - PDF/HTML/FDX via screenplain, NOT Pandoc - screenplain
#     has no CLI font-override flag, so g:bartleby_compile_screenplay_font
#     is currently unused (reserved for if/when that changes).
#
# Bartleby's own job stops at concatenating the included documents in
# binder order and shelling out with the right resource files - no
# hand-rolled format conversion where Pandoc/LaTeX/screenplain already
# does it (this replaces v1's StripMarkdown() - plaintext output is gone;
# Pandoc's own `plain` writer or plain Markdown output covers that need).
#
# CompileTarget is defined before the functions that use it, not just
# by convention: many of them use CompileTarget in their own parameter
# or return type, and Vim9 resolves a function's signature eagerly at
# definition time - unlike a class used only inside a function body,
# which can forward-reference one defined later in the file just fine.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/project.vim' as Pj
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/picker.vim' as Pk
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/profile.vim' as Pf
import autoload 'bartleby/slug.vim' as Sl
import autoload 'bartleby/persist.vim' as Pe
import autoload 'bartleby/helppopup.vim' as H
import 'Logger/logger.vim' as Log

var log: Log.Logger = Log.Logger.new('Bartleby', expand('<sfile>:t'))
var compilescriptpath: string = expand('<sfile>:p')
var compilepandocbin: string = g:bartleby_compile_pandoc_bin
var compilescreenplainbin: string = g:bartleby_compile_screenplain_bin
var compiletoc: bool = g:bartleby_compile_toc
var compilestandalone: bool = g:bartleby_compile_standalone
var compilemanuscriptfont: string = g:bartleby_compile_manuscript_font
var compilebookfont: string = g:bartleby_compile_book_font
var compilemanuscriptdoublespaced: bool = g:bartleby_compile_manuscript_double_spaced
var compileindentparagraphs: bool = g:bartleby_compile_indent_paragraphs
var compilebookchapterstyle: string = g:bartleby_compile_book_chapter_style
var compilebookpartstyle: string = g:bartleby_compile_book_part_style
var compileextraargs: list<string> = g:bartleby_compile_extra_args

const KIND_MANUSCRIPT: string = 'Manuscript'
const KIND_BOOK: string = 'Book'
const KIND_SCREENPLAY: string = 'Screenplay'
const KINDS: list<string> = [KIND_MANUSCRIPT, KIND_BOOK, KIND_SCREENPLAY]

const KIND_FORMATS: dict<list<string>> = {
  Manuscript: ['PDF'],
  Book: ['PDF', 'HTML', 'EPUB', 'Markdown'],
  Screenplay: ['PDF', 'HTML', 'FDX'],
}
const PANDOC_EXT: dict<string> = {PDF: 'pdf', HTML: 'html', EPUB: 'epub', Markdown: 'md'}
const SCREENPLAY_EXT: dict<string> = {PDF: 'pdf', HTML: 'html', FDX: 'fdx'}

# ---------------------------------------------------------------------
# CompileTarget - a saved preset. Breaking change from v1's shape
# (kind/font/coverImage/doubleSpaced replace the old flat format list) -
# old saved targets are simply incompatible, per your call.
# ---------------------------------------------------------------------

export class CompileTarget
  var name: string = ''
  var kind: string = KIND_MANUSCRIPT
  var format: string = 'PDF'
  var font: string = ''
  var coverImage: string = ''
  var doubleSpaced: bool = true
  var separator: string = '* * *'
  var includedIds: list<string> = []

  static def FromDict(src: dict<any>): CompileTarget
    var t: CompileTarget = CompileTarget.new()
    t.name = get(src, 'name', '')
    t.kind = get(src, 'kind', KIND_MANUSCRIPT)
    t.format = get(src, 'format', 'PDF')
    t.font = get(src, 'font', '')
    t.coverImage = get(src, 'coverImage', '')
    t.doubleSpaced = get(src, 'doubleSpaced', true)
    t.separator = get(src, 'separator', '* * *')
    t.includedIds = get(src, 'includedIds', [])
    return t
  enddef

  def ToDict(): dict<any>
    return {name: this.name, kind: this.kind, format: this.format, font: this.font,
      coverImage: this.coverImage, doubleSpaced: this.doubleSpaced,
      separator: this.separator, includedIds: this.includedIds}
  enddef
endclass

def TargetsDir(project: Pj.Project): string
  return project.scriveDir .. '/compile/targets'
enddef

def TargetPath(project: Pj.Project, name: string): string
  return TargetsDir(project) .. '/' .. Sl.Slugify(name) .. '.json'
enddef

export def ListTargets(project: Pj.Project): list<string>
  var dir: string = TargetsDir(project)
  if !isdirectory(dir)
    return []
  endif
  return globpath(dir, '*.json', false, true)
    ->mapnew((_, p) => CompileTarget.FromDict(Pe.ReadJson(p)).name)
enddef

export def LoadTarget(project: Pj.Project, name: string): CompileTarget
  var path: string = TargetPath(project, name)
  if !filereadable(path)
    return null_object
  endif
  return CompileTarget.FromDict(Pe.ReadJson(path))
enddef

export def SaveTarget(project: Pj.Project, target: CompileTarget): void
  Pe.WriteJson(TargetPath(project, target.name), target.ToDict())
enddef

export def DeleteTarget(project: Pj.Project, name: string): void
  var path: string = TargetPath(project, name)
  if filereadable(path)
    delete(path)
  endif
enddef

# ---------------------------------------------------------------------
# Contents selection - a checkbox-style tree buffer, unchanged in shape
# from v1. Kept outside the unified popup per your decision - defaults
# to "everything," reachable separately to customize a saved target.
# ---------------------------------------------------------------------

const SELECT_BUF: string = 'Bartleby-Compile-Select'

class SelectState
  var project: Pj.Project
  var rows: list<T.Row>
  var included: dict<bool>
  var OnDone: func(list<string>)

  def new(this.project, this.rows, this.included, this.OnDone)
  enddef
endclass

def AllDocIds(project: Pj.Project): list<string>
  return T.Flatten(project)->copy()
    ->filter((_, row) => row.item.IsDocument())
    ->mapnew((_, row) => row.item.id)
enddef

def RenderSelectLines(rows: list<T.Row>, included: dict<bool>): list<string>
  return rows->mapnew((_, row) => {
    var box: string = row.item.IsDocument()
      ? (get(included, row.item.id, false) ? '[x]' : '[ ]') : '   '
    var marker: string = row.item.IsFolder() ? '▸ ' : '· '
    return repeat('  ', row.depth) .. box .. ' ' .. marker .. row.item.title
  })
enddef

def ToggleInclude(rows: list<T.Row>, included: dict<bool>, idx: number): void
  var item: BI.BinderItem = rows[idx].item
  if item.IsDocument()
    included[item.id] = !get(included, item.id, false)
    return
  endif
  var descendantIds: list<string> = []
  var i: number = idx + 1
  while i < len(rows) && rows[i].depth > rows[idx].depth
    if rows[i].item.IsDocument()
      descendantIds->add(rows[i].item.id)
    endif
    i += 1
  endwhile
  if empty(descendantIds)
    return
  endif
  var turnOn: bool = !get(included, descendantIds[0], false)
  for id in descendantIds
    included[id] = turnOn
  endfor
enddef

def RedrawSelect(): void
  var state: SelectState = b:bartleby_compile_select
  setlocal modifiable
  deletebufline('%', 1, '$')
  setline(1, RenderSelectLines(state.rows, state.included))
  setlocal nomodifiable
enddef

def DoToggle(): void
  var state: SelectState = b:bartleby_compile_select
  var lnum: number = line('.')
  if lnum < 1 || lnum > len(state.rows)
    return
  endif
  ToggleInclude(state.rows, state.included, lnum - 1)
  RedrawSelect()
  cursor(lnum, 1)
enddef

def DoConfirm(): void
  var state: SelectState = b:bartleby_compile_select
  var ids: list<string> = AllDocIds(state.project)->copy()
    ->filter((_, id) => get(state.included, id, false))
  var Cb: func(list<string>) = state.OnDone
  close
  Cb(ids)
enddef

export def SelectContents(project: Pj.Project, preselected: list<string>,
    OnDone: func(list<string>)): void
  var included: dict<bool> = {}
  if empty(preselected)
    for id in AllDocIds(project)
      included[id] = true
    endfor
  else
    for id in preselected
      included[id] = true
    endfor
  endif

  execute 'vertical topleft :40split ' .. SELECT_BUF
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodifiable
  setlocal nowrap nonumber norelativenumber nofoldenable
  setlocal winfixwidth
  vertical resize 40
  setlocal filetype=bartleby-compile-select
  b:bartleby_compile_select = SelectState.new(project, T.Flatten(project), included, OnDone)

  RedrawSelect()
  nnoremap <buffer> <silent> x <ScriptCmd>DoToggle()<CR>
  nnoremap <buffer> <silent> <CR> <ScriptCmd>DoConfirm()<CR>
  nnoremap <buffer> <silent> q <ScriptCmd>close<CR>
  nnoremap <buffer> <silent> ? <ScriptCmd>ShowSelectHelp()<CR>
enddef

def ShowSelectHelp(): void
  H.Show('Compile - Select Contents', [
    ['x', 'Toggle inclusion (folders toggle all descendants)'],
    ['<CR>', 'Confirm selection and continue'],
    ['q', 'Cancel'],
    ['?', 'This help'],
  ])
enddef

# ---------------------------------------------------------------------
# Wizard: name -> kind -> format -> (spacing, if Manuscript) -> contents
# -> a single FormPopup for the remaining fields (font, cover image if
# Book, separator if not Screenplay). This is the "reduced to one popup
# where possible" compromise while the fully unified widget (inputpopup.vim)
# is its own separate phase.
# ---------------------------------------------------------------------

def DefaultFont(kind: string): string
  return kind ==# KIND_BOOK ? compilebookfont : compilemanuscriptfont
enddef

# `existing` is null_object for a brand-new target, or the target being
# edited - pre-fills every field and overwrites in place on submit
# (deleting the old file first if the name itself changed).
def FinishWizard(project: Pj.Project, kind: string, format: string,
    doubleSpaced: bool, ids: list<string>, existing: CompileTarget): void
  var fields: list<list<string>> = [['name'], ['font']]
  if kind ==# KIND_BOOK
    fields->add(['coverimage'])
  endif
  if kind !=# KIND_SCREENPLAY
    fields->add(['separator'])
  endif
  var defaults: dict<any> = existing is null_object
    ? {font: DefaultFont(kind), separator: '* * *'}
    : {name: existing.name, font: existing.font, coverimage: existing.coverImage,
       separator: existing.separator}
  var form: IP.InputPopup = IP.InputPopup.new(IP.TextFields(fields), defaults,
    {title: ' Compile Settings ', labels: {coverimage: 'Cover Image'}})
  form.OnSubmit((values: dict<any>) => {
    var name: string = get(values, 'name', '')
    if name ==# ''
      log.Error('compile target name is required')
      return
    endif
    var v: dict<any> = {}
    v.name = name
    v.kind = kind
    v.format = format
    v.font = get(values, 'font', '')
    v.coverImage = get(values, 'coverimage', '')
    v.doubleSpaced = doubleSpaced
    v.separator = get(values, 'separator', '* * *')
    v.includedIds = ids
    var target: CompileTarget = CompileTarget.FromDict(v)
    if existing isnot null_object && existing.name !=# name
      DeleteTarget(project, existing.name)
    endif
    SaveTarget(project, target)
    Execute(project, target)
  })
  form.Open()
enddef

# Contents selection happens FIRST - all other information gathering
# (kind, format, spacing, name, font, cover image, separator) happens
# only after <CR> confirms the selection pane, per preference. Every
# picker pre-selects the existing value when editing.
def RunTargetForm(project: Pj.Project, existing: CompileTarget): void
  var preselected: list<string> = existing is null_object ? [] : existing.includedIds
  var kindDefault: string = existing is null_object ? KIND_MANUSCRIPT : existing.kind
  SelectContents(project, preselected, (ids: list<string>) => {
    Pk.PickOne('Compile Kind', KINDS, (kind: string) => {
      var formats: list<string> = get(KIND_FORMATS, kind, [])
      var formatDefault: string = (existing isnot null_object && existing.kind ==# kind)
        ? existing.format : formats[0]
      Pk.PickOne('Format', formats, (format: string) => {
        if kind ==# KIND_MANUSCRIPT
          var spacingDefault: string = existing isnot null_object
            ? (existing.doubleSpaced ? 'Double' : 'Single')
            : (compilemanuscriptdoublespaced ? 'Double' : 'Single')
          Pk.PickOne('Line Spacing', ['Double', 'Single'], (spacing: string) => {
            FinishWizard(project, kind, format, spacing ==# 'Double', ids, existing)
          }, spacingDefault)
        else
          FinishWizard(project, kind, format, true, ids, existing)
        endif
      }, formatDefault)
    }, kindDefault)
  })
enddef

def DeleteTargetConfirm(project: Pj.Project, target: CompileTarget): void
  if confirm($'Delete compile target "{target.name}"?', "&Yes\n&No", 2) ==# 1
    DeleteTarget(project, target.name)
    log.Info($'deleted compile target: {target.name}')
  endif
enddef

# ---------------------------------------------------------------------
# Execution.
# ---------------------------------------------------------------------

def OutputDir(project: Pj.Project): string
  return project.scriveDir .. '/compile/output'
enddef

def PluginRoot(): string
  return fnamemodify(compilescriptpath, ':h:h:h')
enddef

def ManuscriptTemplatePath(): string
  return PluginRoot() .. '/tools/latex/manuscript.tex'
enddef

def BookTemplatePath(): string
  return PluginRoot() .. '/tools/latex/book.tex'
enddef

def BookCssPath(): string
  return PluginRoot() .. '/tools/css/book.css'
enddef

def WriteFontOverrideCss(outDir: string, font: string): string
  var path: string = outDir .. '/.font-override.css'
  writefile([$'body {{ font-family: {font}, Georgia, serif; }}'], path)
  return path
enddef

# sffms.cls has a genuine internal bug: its ulem-based bold/smallcaps
# redefinition breaks plain \section{} (confirmed via a raw LaTeX test,
# independent of our template/hyperref/Pandoc - "Runaway argument" from
# \section's own \@hangfrom/\@svsec machinery). Real manuscript format
# doesn't use sub-headings anyway - scenes within a chapter use the
# separator, not an H2 - so flattening H2+ to plain text for Manuscript
# compiles sidesteps the sffms bug rather than fighting it. Book is
# unaffected (no sffms/ulem involved) and keeps real sub-headings.
def FlattenSubheadings(lines: list<string>): list<string>
  return lines->mapnew((_, line) => substitute(line, '^#\{2,\}\s*', '', ''))
enddef

def ConcatenateDocs(project: Pj.Project, target: CompileTarget, separator: string): list<string>
  var rows: list<T.Row> = T.Flatten(project)->copy()->filter((_, row) => row.item.IsDocument()
    && index(target.includedIds, row.item.id) >= 0)
  var lines: list<string> = []
  for i in range(len(rows))
    var path: string = rows[i].item.AbsPath(project.BinderRoot())
    if !filereadable(path)
      log.Warn($'skipping missing file: {path}')
      continue
    endif
    if i > 0
      lines += separator ==# '' ? [''] : ['', separator, '']
    endif
    lines += readfile(path)
  endfor
  return lines
enddef

def ReadDocLines(item: BI.BinderItem, binderRoot: string): list<string>
  var path: string = item.AbsPath(binderRoot)
  if !filereadable(path)
    log.Warn($'skipping missing file: {path}')
    return []
  endif
  return readfile(path)
enddef

# True when `lines` already opens with its own markdown heading - such
# content self-delineates (a chapter's injected "# Title", or flattened
# content whose first real item is itself a chapter), so no separator
# is needed before it; bare prose (a scene, or a legacy flat-file
# chapter with no heading of its own) does need one.
def StartsWithHeading(lines: list<string>): bool
  return !empty(lines) && lines[0] =~# '^#\s'
enddef

def JoinSiblingBlocks(blocks: list<list<string>>, separator: string): list<string>
  var lines: list<string> = []
  var first: bool = true
  for block in blocks
    if empty(block)
      continue
    endif
    if !first
      lines += StartsWithHeading(block) || separator ==# '' ? [''] : ['', separator, '']
    endif
    lines += block
    first = false
  endfor
  return lines
enddef

# Manuscript structure: a ROLE_CHAPTER folder becomes `# <its own title>`
# (never derived from file content) followed by its scenes, separator-
# joined. Every other folder (ROLE_PART included) is flattened - walked
# through with no heading of its own, since sffms has no safe sectioning
# level below \chapter and real manuscripts don't represent Part
# structure at all (see the design doc). A bare document at any level
# (a pre-restructure flat-file chapter) is included as-is, unchanged
# from the original ConcatenateDocs behavior, for backward compatibility.
def WalkManuscript(items: list<BI.BinderItem>, target: CompileTarget,
    binderRoot: string, separator: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDocument()
      if index(target.includedIds, item.id) >= 0
        blocks->add(ReadDocLines(item, binderRoot))
      endif
    elseif item.structureRole ==# BI.ROLE_CHAPTER
      var body: list<string> = WalkManuscript(item.children, target, binderRoot, separator)
      if !empty(body)
        blocks->add([$'# {item.title}', ''] + body)
      endif
    else
      blocks->add(WalkManuscript(item.children, target, binderRoot, separator))
    endif
  endfor
  return JoinSiblingBlocks(blocks, separator)
enddef

# True if any included item under `items` is a ROLE_PART folder - decides
# whether Book compiles as Part(H1)/Chapter(H2) or plain Chapter(H1).
def HasIncludedPart(items: list<BI.BinderItem>, includedIds: list<string>): bool
  for item in items
    if item.IsFolder()
      if item.structureRole ==# BI.ROLE_PART
        return true
      endif
      if HasIncludedPart(item.children, includedIds)
        return true
      endif
    endif
  endfor
  return false
enddef

# Book structure: real \part/\chapter divisions (book.tex has no sffms-
# style restriction on sectioning depth). partLevel/chapterLevel are '#'
# or '##' depending on whether Parts are present at all for this target -
# a bare Chapter is H1 when there's no enclosing Part, H2 when there is.
def WalkBook(items: list<BI.BinderItem>, target: CompileTarget, binderRoot: string,
    separator: string, partLevel: string, chapterLevel: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDocument()
      if index(target.includedIds, item.id) >= 0
        blocks->add(ReadDocLines(item, binderRoot))
      endif
    elseif item.structureRole ==# BI.ROLE_PART
      var body: list<string> = WalkBook(item.children, target, binderRoot, separator,
        partLevel, chapterLevel)
      if !empty(body)
        blocks->add([$'{partLevel} {item.title}', ''] + body)
      endif
    elseif item.structureRole ==# BI.ROLE_CHAPTER
      var body: list<string> = WalkBook(item.children, target, binderRoot, separator,
        partLevel, chapterLevel)
      if !empty(body)
        blocks->add([$'{chapterLevel} {item.title}', ''] + body)
      endif
    else
      blocks->add(WalkBook(item.children, target, binderRoot, separator, partLevel, chapterLevel))
    endif
  endfor
  return JoinSiblingBlocks(blocks, separator)
enddef

# Front Matter/Back Matter content, for both Manuscript and Book: each
# direct document gets its own unnumbered heading (Pandoc's `{-}`
# attribute, which becomes \chapter*{} in LaTeX output regardless of
# document class) rather than being flattened in as plain, headingless
# content - a book's front/back matter is conventionally a sequence of
# distinct unnumbered pieces (dedication, acknowledgments, ...), not one
# undifferentiated block. Nested folders are walked but don't get a
# heading of their own; only documents do.
def WalkFrontOrBackMatter(items: list<BI.BinderItem>, target: CompileTarget,
    binderRoot: string, separator: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDocument()
      if index(target.includedIds, item.id) >= 0
        blocks->add(['# ' .. item.title .. ' {-}', ''] + ReadDocLines(item, binderRoot))
      endif
    else
      blocks->add(WalkFrontOrBackMatter(item.children, target, binderRoot, separator))
    endif
  endfor
  return JoinSiblingBlocks(blocks, separator)
enddef

# Front Matter/Manuscript/Back Matter are always direct root-level
# siblings (never nested), so finding one by role is a flat scan, not a
# recursive tree search.
def FindTopLevelItem(items: list<BI.BinderItem>, role: string): BI.BinderItem
  for item in items
    if item.structureRole ==# role
      return item
    endif
  endfor
  return null_object
enddef

# A Pandoc raw-LaTeX block: passed through to the LaTeX output verbatim,
# regardless of output format - how Book's \frontmatter/\mainmatter/
# \backmatter (plain `book` class commands, no package needed) get into
# a compile that's otherwise built entirely from Markdown.
def RawLatex(cmd: string): list<string>
  return ['```{=latex}', cmd, '```', '']
enddef

export def ConcatenateManuscript(project: Pj.Project, target: CompileTarget): list<string>
  var blocks: list<list<string>> = []
  var frontMatter: BI.BinderItem = FindTopLevelItem(project.items, BI.ROLE_FRONT_MATTER)
  var manuscript: BI.BinderItem = FindTopLevelItem(project.items, BI.ROLE_MANUSCRIPT)
  var backMatter: BI.BinderItem = FindTopLevelItem(project.items, BI.ROLE_BACK_MATTER)
  var binderRoot: string = project.BinderRoot()

  if frontMatter isnot null_object
    blocks->add(WalkFrontOrBackMatter(frontMatter.children, target, binderRoot, target.separator))
  endif
  if manuscript isnot null_object
    blocks->add(WalkManuscript(manuscript.children, target, binderRoot, target.separator))
  endif
  if backMatter isnot null_object
    blocks->add(WalkFrontOrBackMatter(backMatter.children, target, binderRoot, target.separator))
  endif
  return JoinSiblingBlocks(blocks, target.separator)
enddef

export def ConcatenateBook(project: Pj.Project, target: CompileTarget): list<string>
  var blocks: list<list<string>> = []
  var frontMatter: BI.BinderItem = FindTopLevelItem(project.items, BI.ROLE_FRONT_MATTER)
  var manuscript: BI.BinderItem = FindTopLevelItem(project.items, BI.ROLE_MANUSCRIPT)
  var backMatter: BI.BinderItem = FindTopLevelItem(project.items, BI.ROLE_BACK_MATTER)
  var binderRoot: string = project.BinderRoot()
  var hasPart: bool = manuscript isnot null_object
    && HasIncludedPart(manuscript.children, target.includedIds)
  var partLevel: string = '#'
  var chapterLevel: string = hasPart ? '##' : '#'

  var frontBody: list<string> = frontMatter isnot null_object
    ? WalkFrontOrBackMatter(frontMatter.children, target, binderRoot, target.separator) : []
  if !empty(frontBody)
    blocks->add(RawLatex('\frontmatter') + frontBody)
  endif

  var mainBody: list<string> = manuscript isnot null_object
    ? WalkBook(manuscript.children, target, binderRoot, target.separator, partLevel, chapterLevel)
    : []
  if !empty(mainBody)
    blocks->add((empty(frontBody) ? [] : RawLatex('\mainmatter')) + mainBody)
  endif

  var backBody: list<string> = backMatter isnot null_object
    ? WalkFrontOrBackMatter(backMatter.children, target, binderRoot, target.separator) : []
  if !empty(backBody)
    blocks->add(RawLatex('\backmatter') + backBody)
  endif

  # No separator here (unlike every other JoinSiblingBlocks call): these
  # three blocks are structural transitions - \frontmatter/\mainmatter/
  # \backmatter already provide their own page-level separation, so a
  # "* * *" scene-break style separator between them would be a stray
  # mark with no relationship to the actual prose. StartsWithHeading()
  # can't detect this itself, since each block starts with a raw-LaTeX
  # line rather than a heading.
  return JoinSiblingBlocks(blocks, '')
enddef

# Joins only the non-empty parts of `parts` with `sep` - blank pieces are
# omitted entirely rather than leaving stray separators.
def JoinNonEmpty(parts: list<string>, sep: string): string
  return join(parts->copy()->filter((_, p) => p !=# ''), sep)
enddef

# "City, State, Country Zip" - any missing piece (including all of them)
# is simply absent, never a dangling comma/space.
def CityStateLine(info: Pf.ProjectInfo): string
  var cityState: string = JoinNonEmpty([info.city, info.state], ', ')
  var cityStateCountry: string = JoinNonEmpty([cityState, info.countrycode], ', ')
  return JoinNonEmpty([cityStateCountry, info.zip], ' ')
enddef

def CountWords(lines: list<string>): number
  return len(split(join(lines, ' ')))
enddef

# Manuscript-only metadata - sffms-specific, not shared with Book.
# usecourier maps g:bartleby_compile_manuscript_font to sffms's own
# courier/not-courier switch (see manuscript.tex for why: sffms doesn't
# use fontspec, so arbitrary font names don't apply here).
# "numeral" | "spelled" | "bare-numeral" | "bare-spelled" -> two booleans
# the template branches on (see book.tex): whether to show the word
# ("Chapter"/"Part") at all, and whether the number itself is spelled
# out (via fmtcount's \Numberstring) rather than a plain digit.
def BookNumberStyleArgs(prefix: string, style: string): list<string>
  var bare: string = style =~# '^bare' ? 'true' : 'false'
  var spelled: string = style =~# 'spelled' ? 'true' : 'false'
  return [$'--metadata={prefix}bare:{bare}', $'--metadata={prefix}spelled:{spelled}']
enddef

def ManuscriptMetadataArgs(project: Pj.Project, target: CompileTarget,
    mdLines: list<string>): list<string>
  var args: list<string> = [$'--metadata=wordcount:{CountWords(mdLines)}']
  if project.projectType ==# Pj.TYPE_NOVEL || project.projectType ==# Pj.TYPE_NOVEL_PARTS
    args->add('--metadata=isnovel:true')
  endif
  if target.font =~? 'courier'
    args->add('--metadata=usecourier:true')
  endif
  if !target.doubleSpaced
    args->add('--metadata=singlespaced:true')
  endif
  return args
enddef

def PandocMetadataArgs(project: Pj.Project): list<string>
  var info: Pf.ProjectInfo = Pf.Resolve(project)
  var args: list<string> = [$'--metadata=title:{project.name}']
  if info.EffectiveAuthor() !=# ''
    args->add($'--metadata=author:{info.EffectiveAuthor()}')
  endif
  # realname (info.name, required) is distinct from author (the byline,
  # which may be a pen name) - the manuscript title page's contact block
  # shows the real name, not necessarily the byline.
  if info.name !=# ''
    args->add($'--metadata=realname:{info.name}')
  endif
  if info.address !=# ''
    args->add($'--metadata=address:{info.address}')
  endif
  var cityStateLine: string = CityStateLine(info)
  if cityStateLine !=# ''
    args->add($'--metadata=citystateline:{cityStateLine}')
  endif
  if info.phonenumber !=# ''
    args->add($'--metadata=phonenumber:{info.phonenumber}')
  endif
  if info.email !=# ''
    args->add($'--metadata=email:{info.email}')
  endif
  return args
enddef

def OfferToOpen(target: CompileTarget, outputPath: string): void
  log.Info($'compiled: {outputPath}')
  if confirm($'Compiled "{target.name}". Open it?', "&Yes\n&No", 2) ==# 1
    execute 'edit ' .. fnameescape(outputPath)
  endif
enddef

def RunJob(label: string, cmd: list<string>, target: CompileTarget, outputPath: string): void
  var errLines: list<string> = []
  log.Info($'compiling "{target.name}" ({label})...')
  job_start(cmd, {
    err_cb: (_, line) => errLines->add(line),
    exit_cb: (_, status) => {
      if status ==# 0
        OfferToOpen(target, outputPath)
      else
        log.Error($'{cmd[0]} exited with status {status}: {join(errLines, " | ")}')
      endif
    },
  })
enddef

def ExecuteScreenplay(project: Pj.Project, target: CompileTarget): void
  if !executable(compilescreenplainbin)
    log.Error($'screenplain not found ({compilescreenplainbin}) - install via pip, or set g:bartleby_compile_screenplain_bin')
    return
  endif
  var outDir: string = OutputDir(project)
  if !isdirectory(outDir)
    mkdir(outDir, 'p')
  endif
  var ext: string = get(SCREENPLAY_EXT, target.format, 'pdf')
  var outputPath: string = $'{outDir}/{Sl.Slugify(target.name)}.{ext}'
  var fountainPath: string = $'{outDir}/.{Sl.Slugify(target.name)}-src.fountain'
  writefile(ConcatenateDocs(project, target, ''), fountainPath)
  RunJob($'{target.kind}/{target.format}', [compilescreenplainbin, fountainPath, outputPath],
    target, outputPath)
enddef

def BuildDocLines(project: Pj.Project, target: CompileTarget): list<string>
  if target.kind ==# KIND_MANUSCRIPT
    return FlattenSubheadings(ConcatenateManuscript(project, target))
  elseif target.kind ==# KIND_BOOK
    return ConcatenateBook(project, target)
  else
    return ConcatenateDocs(project, target, target.separator)
  endif
enddef

def ExecutePandoc(project: Pj.Project, target: CompileTarget): void
  var outDir: string = OutputDir(project)
  if !isdirectory(outDir)
    mkdir(outDir, 'p')
  endif
  var ext: string = get(PANDOC_EXT, target.format, 'pdf')
  var outputPath: string = $'{outDir}/{Sl.Slugify(target.name)}.{ext}'

  if target.format ==# 'Markdown'
    writefile(BuildDocLines(project, target), outputPath)
    OfferToOpen(target, outputPath)
    return
  endif

  if !executable(compilepandocbin)
    log.Error($'pandoc not found ({compilepandocbin}) - install it or set g:bartleby_compile_pandoc_bin')
    return
  endif

  var mdPath: string = $'{outDir}/.{Sl.Slugify(target.name)}-src.md'
  var docLines: list<string> = BuildDocLines(project, target)
  writefile(docLines, mdPath)

  var args: list<string> = [mdPath, '-o', outputPath] + PandocMetadataArgs(project)
  if compilestandalone
    args->add('--standalone')
  endif
  if compiletoc
    args->add('--toc')
  endif

  if target.kind ==# KIND_MANUSCRIPT
    # pdflatex, not xelatex - see manuscript.tex for why.
    args->add($'--template={ManuscriptTemplatePath()}')
    # Required: Pandoc can't introspect a custom class name like sffms
    # to know it's report-based, so it silently maps H1 to \section
    # instead of \chapter without this - sffms's own chapter styling
    # then doesn't apply, and its auto-numbering collides visibly with
    # the literal heading text.
    args->add('--top-level-division=chapter')
    args += ManuscriptMetadataArgs(project, target, docLines)
  elseif target.kind ==# KIND_BOOK
    args->add($'--variable=mainfont:{target.font}')
    if target.format ==# 'PDF'
      args->add('--pdf-engine=xelatex')
      args->add($'--template={BookTemplatePath()}')
      var hasPart: bool = HasIncludedPart(project.items, target.includedIds)
      args->add($'--top-level-division={hasPart ? "part" : "chapter"}')
      args->add($'--variable=indentparagraphs:{compileindentparagraphs ? "true" : "false"}')
      args += BookNumberStyleArgs('chapter', compilebookchapterstyle)
      args += BookNumberStyleArgs('part', compilebookpartstyle)
      if target.coverImage !=# ''
        args->add($'--variable=cover-image:{target.coverImage}')
      endif
    else
      args->add($'--css={BookCssPath()}')
      args->add($'--css={WriteFontOverrideCss(outDir, target.font)}')
      if target.format ==# 'EPUB' && target.coverImage !=# ''
        args->add($'--epub-cover-image={target.coverImage}')
      endif
    endif
  endif
  args += compileextraargs

  RunJob($'{target.kind}/{target.format}', [compilepandocbin] + args, target, outputPath)
enddef

export def Execute(project: Pj.Project, target: CompileTarget): void
  if target.kind ==# KIND_SCREENPLAY
    ExecuteScreenplay(project, target)
  else
    ExecutePandoc(project, target)
  endif
enddef

# ---------------------------------------------------------------------
# Public entry point: pick a saved target, or build a new one.
# ---------------------------------------------------------------------

export def Run(project: Pj.Project): void
  var names: list<string> = ListTargets(project)
  var options: list<string> = names + ['+ New Target']
  Pk.PickOne('Compile', options, (choice: string) => {
    if choice ==# '+ New Target'
      RunTargetForm(project, null_object)
      return
    endif
    var target: CompileTarget = LoadTarget(project, choice)
    if target is null_object
      log.Error($'target not found: {choice}')
      return
    endif
    Pk.PickOne($'"{choice}"', ['Run', 'Edit', 'Delete'], (action: string) => {
      if action ==# 'Run'
        Execute(project, target)
      elseif action ==# 'Edit'
        RunTargetForm(project, target)
      elseif action ==# 'Delete'
        DeleteTargetConfirm(project, target)
      endif
    })
  })
enddef
