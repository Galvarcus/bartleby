vim9script
# tests/test_spotlight_pos.vim - Spotlight's part-of-speech modes, run in a
# real buffer. Reads which words stay lit from the window's SpotlightDim
# match. Tagger modes use tests/mock_tagger.py (Python 3 only, no spaCy)
# and wait for its asynchronous results.

import autoload 'bartleby/spotlight.vim' as Sp
import autoload 'bartleby/tagger.vim' as Tg

const MOCK_TAGGER: string = expand('<sfile>:p:h') .. '/mock_tagger.py'
const TEXT: list<string> = [
  '# Chapter One',
  '',
  'She quietly walked away very slowly, "Wait," and the red door was opened by him.',
]

def OpenBuffer(): void
  new
  setlocal buftype=nofile filetype=markdown
  setline(1, TEXT)
  cursor(3, 1)
enddef

def CloseBuffer(): void
  Sp.Execute(true, '')
  bwipe!
enddef

def UseTagger(setting: any): void
  g:bartleby_spotlight_tagger = setting
  Tg.Reset()
enddef

# Dim positions of line `lnum`, from the current window's SpotlightDim match.
def DimmedColumns(lnum: number): dict<bool>
  var dimmed: dict<bool> = {}
  for m in getmatches()->filter((_, x) => x.group ==# 'SpotlightDim')
    for [k, v] in items(m)
      if k =~# '^pos' && v[0] == lnum
        var first: number = len(v) == 1 ? 1 : v[1]
        var last: number = len(v) == 1 ? strlen(getline(lnum)) : v[1] + v[2] - 1
        for c in range(first, last)
          dimmed[c] = true
        endfor
      endif
    endfor
  endfor
  return dimmed
enddef

# The runs of non-space text on line `lnum` that are not dimmed.
def LitWords(lnum: number): list<string>
  var dimmed: dict<bool> = DimmedColumns(lnum)
  var text: string = getline(lnum)
  var words: list<string> = []
  var word: string = ''
  for c in range(1, strlen(text))
    if text[c - 1] =~ '\S' && !has_key(dimmed, c)
      word ..= text[c - 1]
    elseif word !=# ''
      words->add(word)
      word = ''
    endif
  endfor
  if word !=# ''
    words->add(word)
  endif
  return words
enddef

# Waits up to 10 seconds for `expected` on line 3 (tagger results arrive
# asynchronously), then asserts it.
def AssertLitSoon(expected: list<string>, what: string): void
  var waited: number = 0
  while LitWords(3) != expected && waited < 10000
    sleep 100m
    waited += 100
  endwhile
  assert_equal(expected, LitWords(3), what)
enddef

def Test_tagger_modes_hidden_without_a_tagger(): void
  UseTagger('')
  var modes = Sp.AvailableModes()
  for mode in ['Nouns', 'Verbs', 'Adjectives', 'Passive']
    assert_equal(-1, index(modes, mode), mode)
  endfor
  for mode in ['Paragraph', 'Dialogue', 'Adverbs', 'Pronouns', 'Determiners',
      'Prepositions', 'Conjunctions', 'Auxiliaries', 'Contractions', 'Fillers']
    assert_true(index(modes, mode) >= 0, mode)
  endfor
enddef

def Test_word_list_modes_light_their_words(): void
  UseTagger('')
  OpenBuffer()
  Sp.Execute(false, 'Adverbs')
  assert_equal(['quietly', 'away', 'very', 'slowly'], LitWords(3))
  Sp.Execute(false, 'Pronouns')
  assert_equal(['She', 'him'], LitWords(3))
  Sp.Execute(false, 'Fillers')
  assert_equal(['very'], LitWords(3))
  CloseBuffer()
enddef

def Test_heading_line_dims_entirely(): void
  UseTagger('')
  OpenBuffer()
  Sp.Execute(false, 'Adverbs')
  assert_equal([], LitWords(1))
  CloseBuffer()
enddef

def Test_dialogue_lights_quoted_speech(): void
  UseTagger('')
  OpenBuffer()
  Sp.Execute(false, 'Dialogue')
  assert_equal(['"Wait,"'], LitWords(3))
  CloseBuffer()
enddef

def Test_mock_tagger_modes(): void
  UseTagger(['python3', MOCK_TAGGER])
  var modes = Sp.AvailableModes()
  for mode in ['Nouns', 'Verbs', 'Adjectives', 'Passive']
    assert_true(index(modes, mode) >= 0, mode)
  endfor
  OpenBuffer()
  Sp.Execute(false, 'Nouns')
  AssertLitSoon(['away', 'very', 'slowly', 'Wait', 'door'], 'Nouns')
  Sp.Execute(false, 'Verbs')
  AssertLitSoon(['walked', 'opened'], 'Verbs')
  Sp.Execute(false, 'Adjectives')
  AssertLitSoon(['red'], 'Adjectives')
  Sp.Execute(false, 'Passive')
  AssertLitSoon(['was', 'opened'], 'Passive')
  # With a tagger, Adverbs uses its tags, not the -ly heuristic: the mock
  # tags only "quietly" as ADV.
  Sp.Execute(false, 'Adverbs')
  AssertLitSoon(['quietly'], 'Adverbs with a tagger')
  CloseBuffer()
  UseTagger('')
enddef

def Test_failing_tagger_turns_spotlight_off_and_hides_modes(): void
  UseTagger(['python3', '-c', 'import sys; sys.exit(3)'])
  OpenBuffer()
  Sp.Execute(false, 'Nouns')
  var waited: number = 0
  while Sp.IsOn() && waited < 10000
    sleep 100m
    waited += 100
  endwhile
  assert_false(Sp.IsOn())
  assert_equal(-1, index(Sp.AvailableModes(), 'Nouns'))
  assert_true(index(Sp.AvailableModes(), 'Adverbs') >= 0)
  CloseBuffer()
  UseTagger('')
enddef

export def RunAll(): void
  # Spotlight computes its dim color from Normal.
  highlight Normal ctermfg=252 ctermbg=235 guifg=#d0d0d0 guibg=#262626
  set t_Co=256
  Test_tagger_modes_hidden_without_a_tagger()
  Test_word_list_modes_light_their_words()
  Test_heading_line_dims_entirely()
  Test_dialogue_lights_quoted_speech()
  Test_mock_tagger_modes()
  Test_failing_tagger_turns_spotlight_off_and_hides_modes()
enddef
