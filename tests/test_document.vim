vim9script
# tests/test_document.vim - document.vim: DocMeta (de)serialization and
# field setters. FromDict()/ToDict() are pure/in-memory; Load()/Save() are
# the one place in this file needing real file I/O (a real sidecar on
# disk), kept small and self-cleaning.

import autoload 'bartleby/document.vim' as D

def Test_new_docmeta_has_sensible_defaults(): void
  var meta = D.DocMeta.new()
  assert_equal('None', meta.label)
  assert_equal('To Do', meta.status)
  assert_equal('', meta.synopsis)
  assert_equal([], meta.keywords)
  assert_equal(0, meta.wordCountTarget)
  assert_equal({}, meta.custom)
enddef

def Test_from_dict_reads_every_field(): void
  var meta = D.DocMeta.FromDict({
    label: 'Red', status: 'Revised', synopsis: 'A summary.',
    keywords: ['fish', 'river'], wordCountTarget: 5000, custom: {note: 'x'},
  })
  assert_equal('Red', meta.label)
  assert_equal('Revised', meta.status)
  assert_equal('A summary.', meta.synopsis)
  assert_equal(['fish', 'river'], meta.keywords)
  assert_equal(5000, meta.wordCountTarget)
  assert_equal({note: 'x'}, meta.custom)
enddef

def Test_from_dict_tolerates_missing_keys(): void
  # An older/partial sidecar - only label present.
  var meta = D.DocMeta.FromDict({label: 'Blue'})
  assert_equal('Blue', meta.label)
  assert_equal('To Do', meta.status)
  assert_equal([], meta.keywords)
enddef

def Test_to_dict_round_trips_through_from_dict(): void
  var original = D.DocMeta.new()
  original.SetLabel('Green')
  original.SetStatus('Done')
  original.SetSynopsis("Line one.\nLine two.")
  original.SetKeywords(['a', 'b', 'c'])
  original.SetWordCountTarget(2500)
  var restored = D.DocMeta.FromDict(original.ToDict())
  assert_equal(original.label, restored.label)
  assert_equal(original.status, restored.status)
  assert_equal(original.synopsis, restored.synopsis)
  assert_equal(original.keywords, restored.keywords)
  assert_equal(original.wordCountTarget, restored.wordCountTarget)
enddef

def Test_setters_mutate_only_their_own_field(): void
  var meta = D.DocMeta.new()
  meta.SetLabel('Purple')
  assert_equal('Purple', meta.label)
  assert_equal('To Do', meta.status) # unaffected
enddef

def Test_load_of_a_missing_sidecar_yields_plain_defaults(): void
  var meta = D.DocMeta.Load('/tmp/bartleby-test-nonexistent-sidecar.json')
  assert_equal('None', meta.label)
  assert_equal(0, meta.wordCountTarget)
enddef

def Test_save_then_load_round_trips_to_disk(): void
  var path = tempname() .. '.meta.json'
  var meta = D.DocMeta.new()
  meta.SetLabel('Orange')
  meta.SetWordCountTarget(1200)
  meta.SetKeywords(['x', 'y'])
  meta.Save(path)
  var reloaded = D.DocMeta.Load(path)
  assert_equal('Orange', reloaded.label)
  assert_equal(1200, reloaded.wordCountTarget)
  assert_equal(['x', 'y'], reloaded.keywords)
  delete(path)
enddef

export def RunAll(): void
  Test_new_docmeta_has_sensible_defaults()
  Test_from_dict_reads_every_field()
  Test_from_dict_tolerates_missing_keys()
  Test_to_dict_round_trips_through_from_dict()
  Test_setters_mutate_only_their_own_field()
  Test_load_of_a_missing_sidecar_yields_plain_defaults()
  Test_save_then_load_round_trips_to_disk()
enddef
