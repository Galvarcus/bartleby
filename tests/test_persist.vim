vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_persist.vim: the safe writes of persist.vim. A write fills a
# temporary file that then replaces the file, keeps a backup when asked,
# and leaves the file as it was when a step fails. A directory in the way
# of the temporary file makes a write fail, even for root, who can write
# where permissions forbid it.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/persist.vim' as PE

# FUNCTION: Return a path for a JSON file in a new temporary directory.
def NewPath(): string
  var dir: string = tempname()
  mkdir(dir, 'p')
  return dir .. '/data.json'
enddef

def Test_a_write_replaces_the_file_and_leaves_no_temporary_file(): void
  var path: string = NewPath()
  assert_true(PE.WriteJson(path, {version: 1}))
  assert_true(PE.WriteJson(path, {version: 2}))
  assert_equal({version: 2}, PE.ReadJson(path))
  assert_equal(['data.json'], readdir(fnamemodify(path, ':h')))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_a_backup_keeps_the_version_before_the_write(): void
  var path: string = NewPath()
  PE.WriteJson(path, {version: 1}, true)
  assert_false(filereadable(path .. PE.BACKUP_SUFFIX))
  PE.WriteJson(path, {version: 2}, true)
  assert_equal({version: 1}, PE.ReadJson(path .. PE.BACKUP_SUFFIX))
  assert_equal({version: 2}, PE.ReadJson(path))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_no_backup_unless_asked(): void
  var path: string = NewPath()
  PE.WriteJson(path, {version: 1})
  PE.WriteJson(path, {version: 2})
  assert_false(filereadable(path .. PE.BACKUP_SUFFIX))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_a_failed_write_leaves_the_file_as_it_was(): void
  var path: string = NewPath()
  PE.WriteJson(path, {version: 1})
  mkdir(path .. '.tmp')
  assert_false(PE.WriteJson(path, {version: 2}, true))
  assert_equal({version: 1}, PE.ReadJson(path))
  assert_false(filereadable(path .. PE.BACKUP_SUFFIX))
  delete(fnamemodify(path, ':h'), 'rf')
enddef

def Test_a_missing_folder_is_made(): void
  var path: string = tempname() .. '/deeper/data.json'
  assert_true(PE.WriteJson(path, {version: 1}))
  assert_equal({version: 1}, PE.ReadJson(path))
  delete(fnamemodify(path, ':h:h'), 'rf')
enddef

export def RunAll(): void
  Test_a_write_replaces_the_file_and_leaves_no_temporary_file()
  Test_a_backup_keeps_the_version_before_the_write()
  Test_no_backup_unless_asked()
  Test_a_failed_write_leaves_the_file_as_it_was()
  Test_a_missing_folder_is_made()
enddef
