vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_pos.vim: pos.vim: tokens, classification by word list and
# pattern, which lines are prose, dim gaps, and the word list settings.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/pos.vim' as P

def Words(text: string, spans: list<list<number>>): list<string>
  return spans->mapnew((_, s) => strpart(text, s[0], s[1] - s[0]))
enddef

def Test_tokens_keep_inner_apostrophes(): void
  var text = "Don't stop, it’s late."
  assert_equal(["Don't", 'stop', 'it’s', 'late'], Words(text, P.Tokens(text)))
enddef

def Test_contractions(): void
  var lists = P.Lists('en')
  for word in ["don't", "they're", "we've", "we'll", "I'd", "I'm", "It's", "that’s", "Let's"]
    assert_true(P.IsContraction(word, lists), word)
  endfor
  # After other words, 's usually shows possession.
  for word in ["John's", "cat's", 'dont']
    assert_false(P.IsContraction(word, lists), word)
  endfor
enddef

def Test_heuristic_adverbs(): void
  var lists = P.Lists('en')
  for word in ['quietly', 'Slowly', 'very', 'never']
    assert_true(P.IsHeuristicAdverb(word, lists), word)
  endfor
  for word in ['family', 'friendly', 'reply', 'fly', 'house']
    assert_false(P.IsHeuristicAdverb(word, lists), word)
  endfor
enddef

def Test_lexical_spans_per_mode(): void
  var lists = P.Lists('en')
  var text = "She quietly said it's late, and walked away very slowly by the door."
  assert_equal(['She', "it's"], Words(text, P.LexicalSpans('Pronouns', text, lists)))
  assert_equal(['quietly', 'away', 'very', 'slowly'], Words(text, P.LexicalSpans('Adverbs', text, lists)))
  assert_equal(['and'], Words(text, P.LexicalSpans('Conjunctions', text, lists)))
  assert_equal(['by'], Words(text, P.LexicalSpans('Prepositions', text, lists)))
  assert_equal(['the'], Words(text, P.LexicalSpans('Determiners', text, lists)))
  assert_equal(["it's"], Words(text, P.LexicalSpans('Contractions', text, lists)))
  assert_equal(['very'], Words(text, P.LexicalSpans('Fillers', text, lists)))
  var aux = "They don't know what was said."
  assert_equal(["don't", 'was'], Words(aux, P.LexicalSpans('Auxiliaries', aux, lists)))
enddef

def Test_prose_lines(): void
  assert_false(P.IsProseLine('# Chapter', 'markdown'))
  assert_false(P.IsProseLine('   ', 'markdown'))
  assert_true(P.IsProseLine('She left.', 'markdown'))
  assert_false(P.IsProseLine('INT. HOUSE - DAY', 'fountain'))
  assert_false(P.IsProseLine('BOB (V.O.)', 'fountain'))
  assert_false(P.IsProseLine('> THE END <', 'fountain'))
  assert_true(P.IsProseLine('Bob opens the door.', 'fountain'))
enddef

def Test_gap_positions(): void
  # With bc bright in a bc d, the gaps are a and d, each with its space.
  assert_equal([[3, 1, 2], [3, 5, 2]], P.GapPositions(3, 'a bc d', [[2, 4]]))
  # Gaps of only spaces are skipped.
  assert_equal([], P.GapPositions(1, 'ab cd', [[0, 2], [3, 5]]))
  # Spans that overlap and are not sorted.
  assert_equal([[1, 7, 2]], P.GapPositions(1, 'abcdefgh', [[2, 6], [0, 3]]))
  # Nothing bright: the whole line.
  assert_equal([[2, 1, 3]], P.GapPositions(2, 'abc', []))
enddef

def Test_word_list_settings(): void
  g:bartleby_spotlight_words_add = {Fillers: ['Kinda']}
  g:bartleby_spotlight_words_remove = {Fillers: ['very']}
  P.ClearLists()
  var lists = P.Lists('en')
  assert_true(has_key(lists.fillers, 'kinda'))
  assert_false(has_key(lists.fillers, 'very'))
  g:bartleby_spotlight_words_add = {}
  g:bartleby_spotlight_words_remove = {}
  P.ClearLists()
  assert_true(has_key(P.Lists('en').fillers, 'very'))
enddef

def Test_unknown_language_gives_no_lists(): void
  assert_equal({}, P.Lists('xx'))
enddef

export def RunAll(): void
  Test_tokens_keep_inner_apostrophes()
  Test_contractions()
  Test_heuristic_adverbs()
  Test_lexical_spans_per_mode()
  Test_prose_lines()
  Test_gap_positions()
  Test_word_list_settings()
  Test_unknown_language_gives_no_lists()
enddef
