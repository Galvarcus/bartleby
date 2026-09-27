# Localization

This document describes how to add support for another language of
writing to Bartleby. Bartleby supports English. Each other language is
added on its own, when it is needed.

Bartleby's own messages, menus, and help are in English. Their
translation is a separate task and is not part of this process yet.

## How Bartleby chooses the language

`g:bartleby_language` sets the language code, such as `en`. When it is
empty, Bartleby takes the first two letters of `v:lang`, the language of
Vim itself. When no language file exists for the code, Bartleby uses
English. That fallback is silent when the code came from `v:lang`, and
gives a warning when the user set the code.

Everything that depends on the language of the writing comes from one
file: `tools/lang/<code>.json`. `autoload/bartleby/lang.vim` finds and
reads it.

## What a language file controls

| Field | Used by | English value |
| --- | --- | --- |
| `language` | The name of the language | `English` |
| `lists` | The word lists of the Spotlight modes | See below |
| `adverb_suffixes` | The Adverbs mode without a tagger | `["ly"]` |
| `contraction_suffixes` | The Contractions mode, and word-list lookups of contracted words | `n't`, `'re`, `'ve`, `'ll`, `'d`, `'m` |
| `conditional_contraction_suffixes` | Suffixes that count only after the words of a named list | `'s` after the words in `s_contraction_words` |
| `contraction_bases` | The word a contraction is built on, when that is not the text before the suffix | `ca` gives `can`, `wo` gives `will` |
| `dialogue_pattern` | The Dialogue mode | Straight or curly double quotes |
| `spacy_model` | The tagger | `en_core_web_sm` |
| `tagger_passive` | Whether the tagger has a passive rule for the language | `true` |
| `pandoc_lang` | Compile: the language code for Pandoc | `en-US` |
| `dictionary_reference`, `thesaurus_reference` | The dictionary and thesaurus lookups | `collegiate`, `thesaurus` |

Every field is optional. A missing rule means the language has none: no
adverb suffixes, for example, or no passive rule. The user's settings,
such as `g:bartleby_spotlight_dialogue_pattern`, override the file.

The `lists` object holds the word lists: `pronouns`, `determiners`,
`prepositions`, `conjunctions`, `auxiliaries`, `fillers`, `adverbs`,
`adverb_exceptions`, and `s_contraction_words`. Each list holds single
words in lowercase.

## Add a language

1. **Create the file.** Copy `tools/lang/en.json` to
   `tools/lang/<code>.json`, with the two-letter ISO 639-1 code of the
   language, such as `fr` or `de`.
2. **Write the word lists.** Replace every list with the words of the
   language. Leave out a list that does not apply.
3. **Set the rules.** Set the adverb suffixes and the contraction rules,
   or remove them when the language has none. For example, French
   adverbs often end in `ment` and Spanish adverbs in `mente`. German
   adverbs have no common suffix.
4. **Set the dialogue quotes.** Examples: `«[^»]*»` for French, and
   `„[^“]*“` for German. Dialogue marked with a dash at the start of a
   line, which Spanish and French often use, is not a pair of quotes.
   It needs a new rule in `autoload/bartleby/spotlight.vim`.
5. **Set up the tagger.** See the next section.
6. **Set the compile language.** Set `pandoc_lang` to the full language
   code, such as `fr-FR`. Pandoc uses it for HTML and EPUB. For PDF, the
   LaTeX templates in `tools/latex/` must also load a language package,
   such as `babel`, from Pandoc's `$lang$` variable. That gives correct
   hyphenation and words such as "Chapter" in the language.
7. **Choose the lookups.** See the section on the dictionary and
   thesaurus. Without a reference for the language, set both reference
   fields to an empty string, and the lookups are off.
8. **Test.** See the section on tests.

## The tagger

The tagger is `tools/pos/spacy_tagger.py`. spaCy has models for about 25
languages. Set `spacy_model` to the model name, such as
`fr_core_news_sm`, and install it:

```sh
python3 -m spacy download fr_core_news_sm
```

The part-of-speech modes work in every language without other changes,
because spaCy uses the same part-of-speech tags for all of them. Small
models make more mistakes than larger ones: in a test, the small French
model tagged the verb "court" as an adjective.

The Passive mode needs a rule for each language, because models mark
the passive in different ways. The rules are in `PASSIVE_RULES` in
`spacy_tagger.py`, by language. Tests with the small models showed:

| Model | How it marks the passive | Rule |
| --- | --- | --- |
| English | `auxpass` on the auxiliary | `ud_passive_spans` |
| French | `aux:pass` on the passive auxiliary, `aux:tense` on the other | `ud_passive_spans` works |
| German | Its own label set: the form of *werden* is the head, and the participle hangs under it as `oc` | Needs its own rule |
| Spanish | No passive label: the auxiliary is a plain `aux` | Needs its own rule: a form of *ser* with a participle |

Add the rule to `PASSIVE_RULES`, then set `tagger_passive` to `true` in
the language file. Without a rule, keep it `false`, and Bartleby hides
the Passive mode.

## The dictionary and thesaurus

Each lookup uses a reference from `REFERENCES` in
`import/bartleby/variables/constants.vim`. Each reference names its
provider. The Merriam-Webster provider supports English only.

To add a provider:

1. Write `autoload/bartleby/lexicon_<name>.vim` with two exported
   functions, as `lexicon_mw.vim` does:
   `BuildUrl(ref, word, key)` returns the request URL, and
   `Parse(kind, word, body)` returns a result in the format that
   `lexicon_result.vim` describes.
2. Register it in the `Provider` function of
   `autoload/bartleby/lexicon.vim`. Set `needsKey` to `false` for a
   service without a key.
3. Add its references to `REFERENCES`, with the provider name.
4. Name the references in the language file.

Examples of services for other languages: OpenThesaurus for German
needs no key. The LibreOffice thesaurus files, which many systems have,
work offline for many languages, but they are files, not a web service,
so they need a provider that reads a file instead of building a URL.

## Tests

Add tests for the new language to `tests/test_lang.vim`: a sample
sentence with its expected words for each list, and the adverb and
contraction rules. `tests/test_lang.vim` shows how to switch the
language during a test. When the language has a tagger model, check a
normal sentence and a passive sentence with the real tagger, as
`tests/test_tagger_smoke.vim` does for English.

## Known limits

Languages written without letter case, such as Chinese and Japanese,
need more work:

- The word pattern in `autoload/bartleby/pos.vim` matches letters with
  case only, so it finds no words in these languages.
- Word counts split text at spaces, which these languages do not use
  between words. The usual count is one word per character.
- Their spaCy models need extra Python packages.
