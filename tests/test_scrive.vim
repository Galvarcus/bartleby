vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_scrive.vim: tab completion of scrive names for :BartlebyOpen,
# MatchNames and CompleteNames, and ResolveName of scrive.vim. MatchNames
# takes the names as an argument, so its tests need no files. The tests of
# CompleteNames and ResolveName create scrive folders in the binder root
# and remove them.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/scrive.vim' as S
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/persist.vim' as PE
import 'bartleby/variables/constants.vim' as CO

const NAMES: list<string> = ['Other', 'My Novel', 'My Screenplay']

# FUNCTION: Create a scrive folder for each name in the binder root, and
# return their paths for RemoveScrives.
def MakeScrives(names: list<string>): list<string>
  var paths: list<string> = names->mapnew((_, n) => S.ScrivePath(n))
  for path in paths
    mkdir(path, 'p')
  endfor
  return paths
enddef

def RemoveScrives(paths: list<string>): void
  for path in paths
    delete(path, 'rf')
  endfor
enddef

def Test_prefix_match_ignores_case_and_is_sorted(): void
  assert_equal(['My Novel', 'My Screenplay'], S.MatchNames(NAMES, 'my', 'my'))
  assert_equal(['Other'], S.MatchNames(NAMES, 'o', 'o'))
enddef

def Test_empty_argument_lists_every_name(): void
  assert_equal(['My Novel', 'My Screenplay', 'Other'], S.MatchNames(NAMES, '', ''))
enddef

def Test_name_with_a_space_returns_the_rest_after_the_last_word(): void
  # Typed: My N. Vim replaces only N, the last word.
  assert_equal(['Novel'], S.MatchNames(NAMES, 'My N', 'N'))
  # Typed: My and a space. The last word is empty.
  assert_equal(['Novel', 'Screenplay'], S.MatchNames(NAMES, 'My ', ''))
enddef

def Test_no_match_is_empty(): void
  assert_equal([], S.MatchNames(NAMES, 'xyz', 'xyz'))
enddef

def Test_fuzzy_when_wildoptions_has_fuzzy(): void
  var saved = &wildoptions
  set wildoptions=fuzzy
  assert_equal(['My Novel'], S.MatchNames(NAMES, 'nvl', 'nvl'))
  &wildoptions = saved
enddef

def Test_complete_names_reads_the_whole_argument(): void
  var paths = MakeScrives(NAMES)
  var line = 'BartlebyOpen My N'
  assert_equal(['Novel'], S.CompleteNames('N', line, strlen(line)))
  RemoveScrives(paths)
enddef

def Test_resolve_name(): void
  var paths = MakeScrives(['My Novel'])
  assert_equal('My Novel', S.ResolveName('My Novel'))
  assert_equal('My Novel', S.ResolveName('my novel'))
  assert_equal('Unknown', S.ResolveName('Unknown'))
  RemoveScrives(paths)
enddef

def Test_resolve_name_does_not_guess_between_two_matches(): void
  var paths = MakeScrives(['Draft', 'DRAFT'])
  # Only on a file system that tells the two folders apart.
  if len(S.ListScrives()->filter((_, n) => n ==? 'draft')) == 2
    assert_equal('draft', S.ResolveName('draft'))
  endif
  RemoveScrives(paths)
enddef

# Damaged project.json files, as a crash during a save or a bad edit
# leaves them: what each is, its text, and a part of the error it gets.
const DAMAGED: list<list<string>> = [
  ['truncated', '{"name": "Novel", "items": [{"id": "a", "ti', 'cannot be read'],
  ['empty', '', 'holds no list of binder items'],
  ['not an object', '[1, 2]', 'holds no list of binder items'],
  ['no items', '{"name": "Novel"}', 'holds no list of binder items'],
  ['items not a list', '{"name": "Novel", "items": {}}', 'holds no list of binder items'],
  ['an item not an object', '{"name": "Novel", "items": [1]}', 'holds no list of binder items'],
]

# FUNCTION: A damaged project.json does not open, and stays as it was, so
# that nothing can save an empty tree over it.
def Test_a_damaged_project_file_does_not_open(): void
  var paths = MakeScrives(['Damaged'])
  var file: string = paths[0] .. '/project.json'
  for [what, text, error] in DAMAGED
    writefile([text], file)
    assert_true(S.Open('Damaged') is null_object, what)
    assert_equal([text], readfile(file), what)
    # The error names the file and why.
    var project = PO.Project.new(paths[0])
    assert_false(project.Load(), what)
    assert_match(error, project.loadError, what)
    assert_match('project.json', project.loadError, what)
  endfor
  RemoveScrives(paths)
enddef

def Test_a_project_that_did_not_load_never_saves(): void
  var paths = MakeScrives(['Damaged'])
  var file: string = paths[0] .. '/project.json'
  writefile([DAMAGED[0][1]], file)
  var project = PO.Project.new(paths[0])
  assert_false(project.Load())
  project.Save()
  assert_equal([DAMAGED[0][1]], readfile(file))
  RemoveScrives(paths)
enddef

def Test_a_sound_project_file_opens_and_saves(): void
  var paths = MakeScrives(['Sound'])
  var file: string = paths[0] .. '/project.json'
  writefile([json_encode({name: 'Sound', projectType: CO.TYPE_NOVEL, items: [
    {id: 'm1', title: 'Manuscript', kind: CO.KIND_FOLDER, structureRole: CO.ROLE_MANUSCRIPT, children: []}]})], file)
  var project = S.Open('Sound')
  assert_true(project isnot null_object)
  assert_equal('', project is null_object ? 'no project' : project.loadError)
  if project isnot null_object
    project.Save()
    assert_equal('Manuscript', json_decode(join(readfile(file), "\n")).items[0].title)
  endif
  RemoveScrives(paths)
enddef

# FUNCTION: Each save keeps the version before as a backup, and a load
# that fails names the backup, so that the scrive can be brought back.
def Test_a_save_keeps_a_backup_that_a_failed_load_names(): void
  var paths = MakeScrives(['Backed'])
  var file: string = paths[0] .. '/project.json'
  var project = PO.Project.new(paths[0])
  project.InitNew('Backed', CO.TYPE_NOVEL)
  project.Save()
  project.Save()
  assert_true(filereadable(file .. PE.BACKUP_SUFFIX))
  writefile([DAMAGED[0][1]], file)
  var damaged = PO.Project.new(paths[0])
  assert_false(damaged.Load())
  assert_match('project.json' .. PE.BACKUP_SUFFIX, damaged.loadError)
  RemoveScrives(paths)
enddef

export def RunAll(): void
  Test_prefix_match_ignores_case_and_is_sorted()
  Test_empty_argument_lists_every_name()
  Test_name_with_a_space_returns_the_rest_after_the_last_word()
  Test_no_match_is_empty()
  Test_fuzzy_when_wildoptions_has_fuzzy()
  Test_complete_names_reads_the_whole_argument()
  Test_resolve_name()
  Test_resolve_name_does_not_guess_between_two_matches()
  Test_a_damaged_project_file_does_not_open()
  Test_a_project_that_did_not_load_never_saves()
  Test_a_sound_project_file_opens_and_saves()
  Test_a_save_keeps_a_backup_that_a_failed_load_names()
enddef
