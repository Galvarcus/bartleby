vim9script
# tests/test_tagger_smoke.vim - the real spaCy tagger
# (tools/pos/spacy_tagger.py) through tagger.vim. Skips when python3 or
# spaCy with its model is not installed. Run standalone, not through
# harness.vim; writes tests/tagger_results.txt.
#
# Usage: same invocation shape as harness.vim.

import autoload 'bartleby/tagger.vim' as Tg

const TEXT: string = "The door was opened by her.\nShe runs fast. The run was long."

def HasSpacy(): bool
  if !executable('python3')
    return false
  endif
  system($'python3 -c "import spacy; spacy.load(''{g:bartleby_spotlight_spacy_model}'')"')
  return v:shell_error == 0
enddef

# Byte span -> text.
def Pieces(spans: list<any>): list<string>
  return spans->mapnew((_, s) => strpart(TEXT, s[0], s[1] - s[0]))
enddef

def Test_real_tagger(): void
  if !HasSpacy()
    echom 'SKIP: python3 with spaCy and its model not installed'
    return
  endif
  g:bartleby_spotlight_tagger = 'spacy'
  Tg.Reset()
  Tg.Tags(TEXT)
  var tags: dict<any> = {}
  var waited: number = 0
  while empty(tags) && waited < 60000
    sleep 200m
    waited += 200
    tags = Tg.Tags(TEXT)
  endwhile
  assert_false(empty(tags), 'no tagger result within 60 seconds')
  if empty(tags)
    return
  endif
  assert_equal(['was opened'], Pieces(tags.passive))
  var tagOf: dict<string> = {}
  for t in tags.tokens
    tagOf[$'{t[0]}'] = t[2]
  endfor
  # "runs" is a verb and "run" a noun: the tagger uses context.
  assert_equal('VERB', tagOf[string(stridx(TEXT, 'runs'))])
  assert_equal('NOUN', tagOf[string(stridx(TEXT, 'run was'))])
  assert_equal('NOUN', tagOf[string(stridx(TEXT, 'door'))])
  Tg.Reset()
enddef

execute 'source ' .. expand('<sfile>:h') .. '/../plugin/bartleby.vim'
Test_real_tagger()
if len(v:errors) > 0
  writefile(v:errors + [$'{len(v:errors)} assertion(s) failed'], 'tests/tagger_results.txt')
  cquit 1
else
  writefile(['All tagger tests passed'], 'tests/tagger_results.txt')
endif
