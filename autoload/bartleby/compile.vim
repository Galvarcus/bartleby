vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# compile.vim: compiles a scrive into one output file. Three kinds:
#   Manuscript  Submission PDF, through Pandoc with pdflatex and
#               tools/latex/manuscript.tex, a template for the sffms class.
#   Book        PDF, HTML, EPUB, or Markdown for readers. PDF uses xelatex
#               and tools/latex/book.tex. HTML and EPUB use Pandoc's own
#               writers and tools/css/book.css.
#   Screenplay  PDF, HTML, or FDX through screenplain, not Pandoc.
#               screenplain has no font option, so
#               g:bartleby_compile_screenplay_font has no effect yet.
#
# Bartleby joins the included documents in binder order and runs the
# converter with the right template. It converts no formats itself.
#
# CompileTarget is defined before the functions that use it because many
# of them name it in their parameter or return type. Vim9 resolves a
# signature when the function is defined, so a class named there must
# already exist. A class used only inside a function body can come later.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/i18n.vim' as IN
import autoload 'bartleby/lang.vim' as LA
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/picker.vim' as PI
import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/profile.vim' as PR
import autoload 'bartleby/slug.vim' as SU
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/helppopup.vim' as H
import autoload 'bartleby/dialog_popup.vim' as DP
import autoload 'dist/vim9.vim' as DV
import autoload 'bartleby/log.vim' as L
import 'bartleby/variables/constants.vim' as CO

var log = L.New(expand('<sfile>:t'))
var compilescriptpath: string = expand('<sfile>:p')
var compilepandocbin: string = g:bartleby_compile_pandoc_bin
var compilescreenplainbin: string = g:bartleby_compile_screenplain_bin
var compilelang: string = g:bartleby_compile_lang
var compiletoc: bool = g:bartleby_compile_toc
var compilestandalone: bool = g:bartleby_compile_standalone
var compilemanuscriptfont: string = g:bartleby_compile_manuscript_font
var compilebookfont: string = g:bartleby_compile_book_font
var compilemanuscriptdoublespaced: bool = g:bartleby_compile_manuscript_double_spaced
var compileindentparagraphs: bool = g:bartleby_compile_indent_paragraphs
var compilebookchapterstyle: string = g:bartleby_compile_book_chapter_style
var compilebookpartstyle: string = g:bartleby_compile_book_part_style
var compileextraargs: list<string> = g:bartleby_compile_extra_args
var compilelogretention: number = g:bartleby_compile_log_retention

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

# CLASS: A saved compile preset: kind, format, font, cover image,
# spacing, separator, and the included documents.

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

def TargetsDir(project: PO.Project): string
  return project.scriveDir .. '/compile/targets'
enddef

def TargetPath(project: PO.Project, name: string): string
  return TargetsDir(project) .. '/' .. SU.Slugify(name) .. '.json'
enddef

export def ListTargets(project: PO.Project): list<string>
  var dir: string = TargetsDir(project)
  if !isdirectory(dir)
    return []
  endif
  return globpath(dir, '*.json', false, true)
    ->mapnew((_, p) => CompileTarget.FromDict(PE.ReadJson(p)).name)
enddef

export def LoadTarget(project: PO.Project, name: string): CompileTarget
  var path: string = TargetPath(project, name)
  if !filereadable(path)
    return null_object
  endif
  return CompileTarget.FromDict(PE.ReadJson(path))
enddef

export def SaveTarget(project: PO.Project, target: CompileTarget): void
  PE.WriteJson(TargetPath(project, target.name), target.ToDict())
enddef

export def DeleteTarget(project: PO.Project, name: string): void
  var path: string = TargetPath(project, name)
  if filereadable(path)
    delete(path)
  endif
enddef

# Contents selection: a tree buffer with a checkbox per document. It is
# separate from the settings popup, and all documents are included by
# default.

const SELECT_HEADER: string = '*** Compile ***'
# Lines above the tree: the header and the project title. Every mapping
# from a cursor line to a row subtracts this.
const SELECT_HEADER_LINES: number = 2
# Only these top-level folders go into a compile, see ConcatenateManuscript
# and ConcatenateBook, so only their contents are listed.
const COMPILE_ROLES: list<string> = [
  CO.ROLE_FRONT_MATTER, CO.ROLE_MANUSCRIPT, CO.ROLE_BACK_MATTER,
]

class SelectState
  var project: PO.Project
  var rows: list<T.Row>
  var included: dict<bool>
  var OnDone: func(list<string>)

  def new(this.project, this.rows, this.included, this.OnDone)
  enddef
endclass

# FUNCTION: Return the Front Matter, Manuscript, and Back Matter folders
# and everything under them, in tree order. Characters, Research, and
# custom top-level folders are left out.
def SelectableRows(project: PO.Project): list<T.Row>
  var rows: list<T.Row> = []
  var inCompileRoot: bool = false
  for row in T.Flatten(project)
    if row.depth == 0
      inCompileRoot = index(COMPILE_ROLES, row.item.structureRole) >= 0
    endif
    if inCompileRoot
      rows->add(row)
    endif
  endfor
  return rows
enddef

def AllDocIds(project: PO.Project): list<string>
  return SelectableRows(project)
    ->filter((_, row) => row.item.IsDocument())
    ->mapnew((_, row) => row.item.id)
enddef

def RenderSelectLines(rows: list<T.Row>, included: dict<bool>): list<string>
  return rows->mapnew((_, row) => {
    var box: string = row.item.IsDocument()
      ? (get(included, row.item.id, false) ? '[x]' : '[ ]') : '   '
    var marker: string = row.item.IsFolder() ? '▸ ' : '· '
    # A trailing slash marks a folder, for the Directory highlight in
    # syntax/bartleby-compile-select.vim. Display only.
    var title: string = row.item.IsFolder() ? row.item.title .. '/' : row.item.title
    return repeat('  ', row.depth) .. box .. ' ' .. marker .. title
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
  setline(1, [SELECT_HEADER, state.project.name]
    + RenderSelectLines(state.rows, state.included))
  setlocal nomodifiable
enddef

def DoToggle(): void
  var state: SelectState = b:bartleby_compile_select
  var lnum: number = line('.')
  var idx: number = lnum - 1 - SELECT_HEADER_LINES
  if idx < 0 || idx >= len(state.rows)
    return
  endif
  ToggleInclude(state.rows, state.included, idx)
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

export def SelectContents(project: PO.Project, preselected: list<string>,
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

  execute 'vertical topleft :40split ' .. CO.COMPILE_SELECT_BUF
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodifiable
  # Long titles wrap at word boundaries. shift:6 starts each wrapped line
  # under the title text, after the checkbox and marker.
  setlocal wrap linebreak breakindent breakindentopt=shift:6
  setlocal nonumber norelativenumber nofoldenable
  setlocal winfixwidth
  vertical resize 40
  setlocal filetype=bartleby-compile-select
  b:bartleby_compile_select = SelectState.new(project, SelectableRows(project), included, OnDone)

  RedrawSelect()
  cursor(SELECT_HEADER_LINES + 1, 1)
  nnoremap <buffer> <silent> x <ScriptCmd>DoToggle()<CR>
  nnoremap <buffer> <silent> <CR> <ScriptCmd>DoConfirm()<CR>
  nnoremap <buffer> <silent> q <ScriptCmd>close<CR>
  nnoremap <buffer> <silent> ? <ScriptCmd>ShowSelectHelp()<CR>
enddef

def ShowSelectHelp(): void
  H.Show(IN.T("Compile - Select Contents"), [
    ['x', IN.T("Toggle inclusion (folders toggle all descendants)")],
    ['<CR>', IN.T("Confirm selection and continue")],
    ['q', IN.T("Cancel")],
    ['?', IN.T("This help")],
  ])
enddef

# FUNCTION: Return the default font for a compile kind.

def DefaultFont(kind: string): string
  return kind ==# KIND_BOOK ? compilebookfont : compilemanuscriptfont
enddef

# FUNCTION: Show the settings form: name, font, cover image for Book, and
# separator for all kinds except Screenplay. existing is null_object for a
# new target. For an edited target, it fills every field, and a changed
# name deletes the old target file.
def FinishWizard(project: PO.Project, kind: string, format: string,
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
      log.Error(IN.T("compile target name is required"))
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

# FUNCTION: Run the compile wizard: contents selection first, then kind,
# format, spacing for Manuscript, and the settings form. Each picker
# starts on the existing value when a target is edited.
def RunTargetForm(project: PO.Project, existing: CompileTarget): void
  var preselected: list<string> = existing is null_object ? [] : existing.includedIds
  var kindDefault: string = existing is null_object ? KIND_MANUSCRIPT : existing.kind
  SelectContents(project, preselected, (ids: list<string>) => {
    PI.PickOne(IN.T("Compile Kind"), KINDS, (kind: string) => {
      var formats: list<string> = get(KIND_FORMATS, kind, [])
      var formatDefault: string = (existing isnot null_object && existing.kind ==# kind)
        ? existing.format : formats[0]
      PI.PickOne(IN.T("Format"), formats, (format: string) => {
        if kind ==# KIND_MANUSCRIPT
          var spacingDefault: string = existing isnot null_object
            ? (existing.doubleSpaced ? 'Double' : 'Single')
            : (compilemanuscriptdoublespaced ? 'Double' : 'Single')
          PI.PickOne(IN.T("Line Spacing"), ['Double', 'Single'], (spacing: string) => {
            FinishWizard(project, kind, format, spacing ==# 'Double', ids, existing)
          }, spacingDefault)
        else
          FinishWizard(project, kind, format, true, ids, existing)
        endif
      }, formatDefault)
    }, kindDefault)
  })
enddef

def DeleteTargetConfirm(project: PO.Project, target: CompileTarget): void
  DP.Confirm(printf(IN.T("Delete compile target \"%s\"?"), target.name), () => {
    DeleteTarget(project, target.name)
    log.Info(printf(IN.T("deleted compile target: %s"), target.name))
  })
enddef

##############################################################################
# SECTION: Execution.
##############################################################################

def OutputDir(project: PO.Project): string
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

# FUNCTION: Turn level 2 and deeper headings into plain text, for
# Manuscript only. sffms has a bug: its ulem-based redefinition breaks a
# plain section command, with a Runaway argument error, also without this
# template or Pandoc. A manuscript has no subheadings anyway: scenes use
# the separator. Book does not use sffms and keeps its subheadings.
def FlattenSubheadings(lines: list<string>): list<string>
  return lines->mapnew((_, line) => substitute(line, '^#\{2,\}\s*', '', ''))
enddef

def ConcatenateDocs(project: PO.Project, target: CompileTarget, separator: string): list<string>
  var rows: list<T.Row> = T.Flatten(project)->copy()->filter((_, row) => row.item.IsDocument()
    && index(target.includedIds, row.item.id) >= 0)
  var lines: list<string> = []
  for i in range(len(rows))
    var path: string = rows[i].item.AbsPath(project.BinderRoot())
    if !filereadable(path)
      log.Warn(printf(IN.T("skipping missing file: %s"), path))
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
    log.Warn(printf(IN.T("skipping missing file: %s"), path))
    return []
  endif
  return readfile(path)
enddef

# FUNCTION: Return true when lines start with a Markdown heading. Such a
# block marks its own start, so no separator goes before it. Plain prose,
# such as a scene, needs one.
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

# FUNCTION: Build Manuscript text. A Chapter folder becomes a heading with
# the folder title, never taken from the file content, followed by its
# scenes with separators between them. Other folders, Part included, add
# no heading: sffms has no safe level below chapter, and a manuscript
# shows no parts. A document directly in a folder is included unchanged.
def WalkManuscript(items: list<BI.BinderItem>, target: CompileTarget,
    binderRoot: string, separator: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDocument()
      if index(target.includedIds, item.id) >= 0
        blocks->add(ReadDocLines(item, binderRoot))
      endif
    elseif item.structureRole ==# CO.ROLE_CHAPTER
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

# FUNCTION: Return true when an included item under items is a Part folder.
# This decides whether a Book uses level 1 for parts and level 2 for
# chapters, or level 1 for chapters.
def HasIncludedPart(items: list<BI.BinderItem>, includedIds: list<string>): bool
  for item in items
    if item.IsFolder()
      if item.structureRole ==# CO.ROLE_PART
        return true
      endif
      if HasIncludedPart(item.children, includedIds)
        return true
      endif
    endif
  endfor
  return false
enddef

# FUNCTION: Build Book text with real part and chapter divisions. book.tex
# has no sffms limit on depth. partLevel and chapterLevel are one or two
# number signs: a chapter is level 1 without parts and level 2 with them.
def WalkBook(items: list<BI.BinderItem>, target: CompileTarget, binderRoot: string,
    separator: string, partLevel: string, chapterLevel: string): list<string>
  var blocks: list<list<string>> = []
  for item in items
    if item.IsDocument()
      if index(target.includedIds, item.id) >= 0
        blocks->add(ReadDocLines(item, binderRoot))
      endif
    elseif item.structureRole ==# CO.ROLE_PART
      var body: list<string> = WalkBook(item.children, target, binderRoot, separator,
        partLevel, chapterLevel)
      if !empty(body)
        blocks->add([$'{partLevel} {item.title}', ''] + body)
      endif
    elseif item.structureRole ==# CO.ROLE_CHAPTER
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

# FUNCTION: Build Front Matter or Back Matter text, for Manuscript and
# Book. Each document gets its own unnumbered heading, the Pandoc {-}
# attribute, which LaTeX shows as an unnumbered chapter. Front and back
# matter are separate pieces, such as a dedication and acknowledgments,
# not one block. Nested folders are walked but get no heading.
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

# FUNCTION: Return the top-level item with the given role. Front Matter,
# Manuscript, and Back Matter are always top-level, so a flat scan is
# enough.
def FindTopLevelItem(items: list<BI.BinderItem>, role: string): BI.BinderItem
  for item in items
    if item.structureRole ==# role
      return item
    endif
  endfor
  return null_object
enddef

# FUNCTION: Return a Pandoc raw LaTeX block, copied to the LaTeX output
# unchanged. This is how the frontmatter, mainmatter, and backmatter
# commands of the book class get into a compile built from Markdown.
def RawLatex(cmd: string): list<string>
  return ['```{=latex}', cmd, '```', '']
enddef

export def ConcatenateManuscript(project: PO.Project, target: CompileTarget): list<string>
  var blocks: list<list<string>> = []
  var frontMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_FRONT_MATTER)
  var manuscript: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_MANUSCRIPT)
  var backMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_BACK_MATTER)
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

export def ConcatenateBook(project: PO.Project, target: CompileTarget): list<string>
  var blocks: list<list<string>> = []
  var frontMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_FRONT_MATTER)
  var manuscript: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_MANUSCRIPT)
  var backMatter: BI.BinderItem = FindTopLevelItem(project.items, CO.ROLE_BACK_MATTER)
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

  # No separator here, unlike every other JoinSiblingBlocks call. These
  # three blocks are structural transitions: frontmatter, mainmatter, and
  # backmatter already start new pages, so a scene separator between them
  # would be a stray mark. StartsWithHeading cannot detect this, because
  # each block starts with a raw LaTeX line, not a heading.
  return JoinSiblingBlocks(blocks, '')
enddef

# FUNCTION: Join the nonempty parts with sep. Empty parts leave no stray
# separator.
def JoinNonEmpty(parts: list<string>, sep: string): string
  return join(parts->copy()->filter((_, p) => p !=# ''), sep)
enddef

# FUNCTION: Return City, State, Country Zip. Missing parts are left out,
# with no stray comma or space.
def CityStateLine(info: PR.ProjectInfo): string
  var cityState: string = JoinNonEmpty([info.city, info.state], ', ')
  var cityStateCountry: string = JoinNonEmpty([cityState, info.countrycode], ', ')
  return JoinNonEmpty([cityStateCountry, info.zip], ' ')
enddef

def CountWords(lines: list<string>): number
  return len(split(join(lines, ' ')))
enddef

# FUNCTION: Convert a numbering style to the two booleans that book.tex
# uses: whether to show the word Chapter or Part, and whether to spell
# the number with fmtcount. Styles: numeral, spelled, bare-numeral, and
# bare-spelled.
def BookNumberStyleArgs(prefix: string, style: string): list<string>
  var bare: string = style =~# '^bare' ? 'true' : 'false'
  var spelled: string = style =~# 'spelled' ? 'true' : 'false'
  return [$'--metadata={prefix}bare:{bare}', $'--metadata={prefix}spelled:{spelled}']
enddef

# FUNCTION: Return the Pandoc metadata arguments for a Manuscript, which
# only sffms uses. usecourier maps the target font to the Courier switch
# of sffms, which does not use fontspec, so other font names do not
# apply. manuscript.tex explains more.
def ManuscriptMetadataArgs(project: PO.Project, target: CompileTarget,
    mdLines: list<string>): list<string>
  var args: list<string> = [$'--metadata=wordcount:{CountWords(mdLines)}']
  if project.projectType ==# CO.TYPE_NOVEL || project.projectType ==# CO.TYPE_NOVEL_PARTS
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

def PandocMetadataArgs(project: PO.Project): list<string>
  var info: PR.ProjectInfo = PR.Resolve(project)
  var args: list<string> = [$'--metadata=title:{project.name}']
  if info.EffectiveAuthor() !=# ''
    args->add($'--metadata=author:{info.EffectiveAuthor()}')
  endif
  # realname, from info.name, is the legal name for the contact block on
  # the title page. author is the byline, which may be a pen name.
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

# FUNCTION: Ask whether to open the compiled file, with yes as the
# default. Markdown opens in a new tab, so that no scrive window is
# replaced. Every other format opens in the system viewer with Vim's
# dist#vim9#Open, the function behind :Open.
def OfferToOpen(target: CompileTarget, outputPath: string): void
  log.Info(printf(IN.T("compiled: %s"), fnamemodify(outputPath, ":~")))
  DP.Confirm(printf(IN.T("Compiled \"%s\". Open it?"), target.name), () => {
    if target.format ==# 'Markdown'
      execute 'tabedit ' .. fnameescape(outputPath)
    else
      DV.Open(outputPath)
    endif
  }, true)
enddef

# FUNCTION: Run a compile command. On success, offer to open the output.
# On failure, write the command's error output to logBase .. '.log' and
# offer to open that log in a new tab. Pandoc writes its own log only on
# success, so this failure log is the only record of what went wrong.
def RunJob(label: string, cmd: list<string>, target: CompileTarget,
    outputPath: string, logBase: string): void
  var errLines: list<string> = []
  log.Info(printf(IN.T("compiling \"%s\" (%s)..."), target.name, label))
  job_start(cmd, {
    err_cb: (_, line) => errLines->add(line),
    exit_cb: (_, status) => {
      if status ==# 0
        OfferToOpen(target, outputPath)
      else
        log.Error(printf(IN.T("%s exited with status %s: %s"), cmd[0], status, join(errLines, " | ")))
        OfferFailureLog(target, WriteFailureLog(logBase .. '.log', cmd, status, errLines))
      endif
    },
  })
enddef

# FUNCTION: Write a failed command, its exit status, and its error output
# to path, and return path.
def WriteFailureLog(path: string, cmd: list<string>, status: number,
    errLines: list<string>): string
  var lines: list<string> = [
    $'Command: {join(cmd, " ")}',
    $'Exit status: {status}',
    '',
  ]
  writefile(lines + (empty(errLines) ? ['No error output.'] : errLines), path)
  return path
enddef

# FUNCTION: Ask whether to open the failure log, with yes as the default.
# It opens in a new tab, so that no scrive window is replaced.
def OfferFailureLog(target: CompileTarget, path: string): void
  DP.Confirm(printf(IN.T("Compiling \"%s\" failed. Open the log?"), target.name), () => {
    execute 'tabedit ' .. fnameescape(path)
  }, true)
enddef

def ExecuteScreenplay(project: PO.Project, target: CompileTarget): void
  if !executable(compilescreenplainbin)
    log.Error(printf(IN.T("screenplain not found (%s) - install via pip, or set g:bartleby_compile_screenplain_bin"), compilescreenplainbin))
    return
  endif
  var outDir: string = OutputDir(project)
  if !isdirectory(outDir)
    mkdir(outDir, 'p')
  endif
  var ext: string = get(SCREENPLAY_EXT, target.format, 'pdf')
  var outputPath: string = $'{outDir}/{SU.Slugify(target.name)}.{ext}'
  var fountainPath: string = $'{outDir}/.{SU.Slugify(target.name)}-src.fountain'
  writefile(ConcatenateDocs(project, target, ''), fountainPath)
  RunJob($'{target.kind}/{target.format}', [compilescreenplainbin, fountainPath, outputPath],
    target, outputPath, NewLogBase(project, target))
enddef

def BuildDocLines(project: PO.Project, target: CompileTarget): list<string>
  if target.kind ==# KIND_MANUSCRIPT
    return FlattenSubheadings(ConcatenateManuscript(project, target))
  elseif target.kind ==# KIND_BOOK
    return ConcatenateBook(project, target)
  else
    return ConcatenateDocs(project, target, target.separator)
  endif
enddef

def ExecutePandoc(project: PO.Project, target: CompileTarget): void
  var outDir: string = OutputDir(project)
  if !isdirectory(outDir)
    mkdir(outDir, 'p')
  endif
  var ext: string = get(PANDOC_EXT, target.format, 'pdf')
  var outputPath: string = $'{outDir}/{SU.Slugify(target.name)}.{ext}'

  if target.format ==# 'Markdown'
    writefile(BuildDocLines(project, target), outputPath)
    OfferToOpen(target, outputPath)
    return
  endif

  if !executable(compilepandocbin)
    log.Error(printf(IN.T("pandoc not found (%s) - install it or set g:bartleby_compile_pandoc_bin"), compilepandocbin))
    return
  endif

  var mdPath: string = $'{outDir}/.{SU.Slugify(target.name)}-src.md'
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
    # Pandoc's default engine, pdflatex. manuscript.tex explains why.
    args->add($'--template={ManuscriptTemplatePath()}')
    # Required. Pandoc cannot tell that the custom sffms class is based on
    # report, so without this it maps level 1 headings to sections, sffms
    # chapter styling does not apply, and its numbering collides with the
    # heading text.
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
  # The language of the text, for Pandoc: the lang attribute in HTML, the
  # EPUB language, and LaTeX templates that use $lang$. An empty setting
  # means the pandoc_lang of the language file.
  var lang: string = compilelang ==# '' ? LA.Get('pandoc_lang', '') : compilelang
  if lang !=# ''
    args->add($'--metadata=lang:{lang}')
  endif
  args += compileextraargs
  var logBase: string = NewLogBase(project, target)
  args->add($'--log={logBase}.json')

  RunJob($'{target.kind}/{target.format}', [compilepandocbin] + args, target, outputPath, logBase)
enddef

# FUNCTION: Return a new timestamped log path for this run, without an
# extension:
#   ~/.bartleby/logs/<scrive>_<target>_<YYYYmmdd-HHMMSS>
# Pandoc writes .json there through its log option, but only on success.
# On failure, RunJob writes .log there with the error output. Keep the
# newest g:bartleby_compile_log_retention logs per scrive and target,
# this run included, and delete the rest. 0 keeps every log.
def NewLogBase(project: PO.Project, target: CompileTarget): string
  var logDir: string = expand('~/.bartleby/logs')
  if !isdirectory(logDir)
    mkdir(logDir, 'p')
  endif
  var prefix: string = SU.Slugify(fnamemodify(project.scriveDir, ':t:r'))
    .. '_' .. SU.Slugify(target.name) .. '_'
  if compilelogretention > 0
    var older: list<string> = sort(glob($'{logDir}/{prefix}[0-9]*.*', false, true))
    var excess: number = len(older) - (compilelogretention - 1)
    if excess > 0
      for path in older[0 : excess - 1]
        delete(path)
      endfor
    endif
  endif
  return $'{logDir}/{prefix}{strftime("%Y%m%d-%H%M%S")}'
enddef

export def Execute(project: PO.Project, target: CompileTarget): void
  if target.kind ==# KIND_SCREENPLAY
    ExecuteScreenplay(project, target)
  else
    ExecutePandoc(project, target)
  endif
enddef

# FUNCTION: Pick a saved target and run it, or build a new one. The entry
# point of :BartlebyCompile.

export def Run(project: PO.Project): void
  var names: list<string> = ListTargets(project)
  var options: list<string> = names + ['+ New Target']
  PI.PickOne(IN.T("Compile"), options, (choice: string) => {
    if choice ==# '+ New Target'
      RunTargetForm(project, null_object)
      return
    endif
    var target: CompileTarget = LoadTarget(project, choice)
    if target is null_object
      log.Error(printf(IN.T("target not found: %s"), choice))
      return
    endif
    PI.PickOne(printf(IN.T("\"%s\""), choice), ['Run', 'Edit', 'Delete'], (action: string) => {
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
