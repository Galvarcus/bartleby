vim9script
# tests/test_compile_select.vim - compile.vim's selection pane
# (SelectContents). Opens the real pane and drives its buffer-local keys
# with feedkeys('...', 'xt'), like test_binder.vim. Checks the header and
# title lines, that only Front Matter, Manuscript, and Back Matter
# contents are listed, that the cursor-to-row mapping skips the two
# header lines, and the ids returned on <CR>.

import autoload 'bartleby/compile.vim' as C
import autoload 'bartleby/binderitem.vim' as BI
import './fixtures.vim' as Fx

# The fixture project plus one Research document, which must never be
# listed. Returns {project, scene1, scene2}.
def BuildProject(): dict<any>
  var project = Fx.BuildProject()
  project.ItemAt(4).AddChild(BI.BinderItem.NewDocument('Harbor notes', 'research/harbor.md'))
  var manuscript = project.ItemAt(1)
  return {
    project: project,
    scene1: manuscript.ChildAt(0).ChildAt(0),
    scene2: manuscript.ChildAt(1).ChildAt(0),
  }
enddef

# Opens the pane. `result` receives the ids passed to OnDone, under the
# key 'ids', when <CR> confirms the selection.
#
# extend(), not `result.ids = ids`: in Vim 9.2.1108, a lambda that assigns
# to a member of a captured function argument crashes Vim (segmentation
# fault) when it runs after that function has returned.
def OpenPane(project: any, result: dict<any>): void
  C.SelectContents(project, [], (ids: list<string>) => {
    extend(result, {ids: ids})
  })
enddef

def ClosePane(): void
  only!
  silent! bwipe! Bartleby-Compile-Select
enddef

def Test_lists_header_title_and_only_compile_folders(): void
  var fx = BuildProject()
  OpenPane(fx.project, {})
  assert_equal([
    '*** Compile ***',
    'Fixture Project',
    '    ▸ Front Matter/',
    '    ▸ Manuscript/',
    '      ▸ 1/',
    '    [x] · Scene 1',
    '      ▸ 2/',
    '    [x] · Scene 1',
    '    ▸ Back Matter/',
  ], getline(1, '$'))
  ClosePane()
enddef

def Test_cursor_starts_on_the_first_row(): void
  var fx = BuildProject()
  OpenPane(fx.project, {})
  assert_equal(3, line('.'))
  ClosePane()
enddef

def Test_x_toggles_the_row_under_the_cursor(): void
  var fx = BuildProject()
  OpenPane(fx.project, {})
  cursor(6, 1)
  feedkeys('x', 'xt')
  assert_equal('    [ ] · Scene 1', getline(6))
  assert_equal('    [x] · Scene 1', getline(8))
  ClosePane()
enddef

def Test_x_on_a_header_line_changes_nothing(): void
  var fx = BuildProject()
  OpenPane(fx.project, {})
  var before = getline(1, '$')
  cursor(1, 1)
  feedkeys('x', 'xt')
  cursor(2, 1)
  feedkeys('x', 'xt')
  assert_equal(before, getline(1, '$'))
  ClosePane()
enddef

def Test_x_on_a_folder_toggles_its_documents(): void
  var fx = BuildProject()
  OpenPane(fx.project, {})
  cursor(4, 1)
  feedkeys('x', 'xt')
  assert_equal('    [ ] · Scene 1', getline(6))
  assert_equal('    [ ] · Scene 1', getline(8))
  ClosePane()
enddef

def Test_enter_returns_the_included_ids(): void
  var fx = BuildProject()
  var result: dict<any> = {}
  OpenPane(fx.project, result)
  cursor(6, 1)
  feedkeys('x', 'xt')
  feedkeys("\<CR>", 'xt')
  assert_equal([fx.scene2.id], get(result, 'ids', []))
  ClosePane()
enddef

export def RunAll(): void
  Test_lists_header_title_and_only_compile_folders()
  Test_cursor_starts_on_the_first_row()
  Test_x_toggles_the_row_under_the_cursor()
  Test_x_on_a_header_line_changes_nothing()
  Test_x_on_a_folder_toggles_its_documents()
  Test_enter_returns_the_included_ids()
enddef
