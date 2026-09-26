# Bartleby User's Guide

This guide explains Bartleby for writers. You need to know only how to
open Vim, type text, and move with the arrow keys. For a compact
reference, see [README.md](README.md).

Bartleby keeps your work in ordinary text files. You can open your
chapters in any editor, back them up with any tool, and stop using
Bartleby without losing anything.

## Contents

- [Vim modes](#vim-modes)
- [New scrive](#new-scrive)
- [Binder](#binder)
- [Writing](#writing)
- [Spotlight modes](#spotlight-modes)
- [Structure](#structure)
- [Dictionary and thesaurus](#dictionary-and-thesaurus)
- [Document details](#document-details)
- [Corkboard](#corkboard)
- [Outliner](#outliner)
- [Screenplays](#screenplays)
- [Palette and menu](#palette-and-menu)
- [Session](#session)
- [Auto-save](#auto-save)
- [Snapshots](#snapshots)
- [Search](#search)
- [Compile](#compile)
- [Author profile](#author-profile)
- [Keys](#keys)
- [Help](#help)
- [Files](#files)

## Vim modes

Vim has two modes that you use all the time:

- **Normal mode** - letters and symbols are commands, not text. You
  press almost every key in this guide in Normal mode.
- **Insert mode** - you type your text. Press `i` to start typing and
  `Esc` to stop.

If a key in this guide does nothing, press `Esc` and try again.

Some keys start with `<leader>`. Unless you changed it, `<leader>` is
the backslash key, `\`.

## New scrive

Bartleby calls a writing project a **scrive**. To start one, run:

```vim
:BartlebyNewScrive My First Novel
```

Bartleby asks for the type:

| Type | Use it for |
| --- | --- |
| Novel | Chapters made of scenes |
| Novel with Parts | Chapters grouped into parts, such as Part One and Part Two |
| Short Story | One piece with no chapters |
| Screenplay | A script in the Fountain format. See [Screenplays](#screenplays) |

Bartleby then opens the Binder with a starter tree: Front Matter,
Manuscript with a first chapter and scene, Back Matter, Characters,
and Research.

To open a scrive later:

- `:BartlebyOpen` reopens the scrive you used last.
- `:BartlebyOpen My First Novel` opens a scrive by name.
- `:BartlebyList` shows all your scrives. Move with `j` and `k`, then
  press `<Enter>` to open one. If you have no scrives, it asks for a
  name and creates one.

## Binder

The Binder is the tree on the left. It shows every folder and
document in your scrive, in the order that they are compiled. The
first line shows the scrive title. Folder names end with `/`. A long
title wraps onto the next line.

Move with the arrow keys or `j` and `k`. Then:

| Key | Does |
| --- | --- |
| `<Enter>` | Open the document, or open or close the folder |
| `<Tab>` | Open or close the folder |
| `a` | Add a document |
| `A` | Add a folder. You can choose Chapter, Part, or a plain folder, depending on the scrive type |
| `r` | Rename |
| `dd` | Delete, after a confirmation |
| `J` / `K` | Move a chapter or part down or up |
| `>>` / `<<` | Move a chapter into a part, or out of it |
| `q` | Close the Binder. It opens again with the scrive |

Five folders are permanent: **Front Matter**, **Manuscript**, **Back
Matter**, **Characters**, and **Research**. You cannot rename, move, or
delete them. `dd` on one of them deletes everything inside it, after a
confirmation, and keeps the empty folder. You can add, move, and
delete everything that you create inside them.

## Writing

Press `<Enter>` on a document in the Binder to open it. Press `i` to
type and `Esc` to stop.

Three tools make Vim work more like a word processor. Use any of them,
all of them, or none.

**Quill** wraps your paragraphs to the window, like a word processor.
It starts by itself for your documents. `<leader>bp` turns it on or
off.

**Focus** shows your text in a centered column and dims the rest of
the screen. `<leader>bz` turns it on or off.
In GVim or MacVim, Focus can also fill the whole screen and use a
larger font. Add these lines to your vimrc, with a font you have:

```vim
let g:bartleby_focus_fullscreen = 1
let g:bartleby_focus_guifont = 'DejaVu Sans Mono 14'
```

When you leave Focus, the window and the font return to how they were.

**Spotlight** dims every paragraph except the one with the cursor.
`<leader>bl` turns it on or off. `<leader>bL` picks a different mode.
See [Spotlight modes](#spotlight-modes).

## Spotlight modes

Spotlight's modes help you revise. Each one keeps one kind of word
bright and dims everything else, so you can see at a glance how often
you use it. Press `<leader>bL`, then type part of a mode's name or
scroll with the arrow keys, and press `<Enter>`.

| Mode | Keeps bright | Use it to |
| --- | --- | --- |
| Paragraph | The paragraph you are in | Concentrate on one paragraph |
| Dialogue | What your characters say | Read the dialogue on its own |
| Adverbs | Words such as "quickly" and "very" | Find adverbs to cut |
| Fillers | Words such as "just", "really", and "actually" | Find words that add nothing |
| Contractions | Words such as "don't" and "it's" | Check the tone of a passage |
| Pronouns | Words such as "she", "they", and "it" | Check that each pronoun is clear |
| Determiners | Words such as "the", "this", and "every" | Check repeated openings |
| Prepositions | Words such as "of", "in", and "by" | Find long chains of phrases |
| Conjunctions | Words such as "and", "but", and "because" | Find sentences that run on |
| Auxiliaries | Helping verbs such as "was", "have", and "can" | Find weak verb phrases |
| Nouns | Nouns | Check concrete detail |
| Verbs | Main verbs | Check that your verbs are strong |
| Adjectives | Adjectives | Find adjectives to cut |
| Passive | Phrases such as "was opened" | Find passive sentences |

Headings, and in screenplays the scene headings and character names,
dim completely.

**"'s".** Bartleby counts "'s" as a contraction only after words such as
"it", "that", "there", and "what", as in "it's" or "that's". After a
name, "'s" usually shows who owns something, as in "John's hat", so it
does not count.

**Nouns, Verbs, Adjectives, and Passive** need a free program called
spaCy, which reads whole sentences. It knows that "run" is a verb in
"they run" and a noun in "a long run". Word lists cannot tell the
difference. Without spaCy, these four modes do not appear in the list.

To install spaCy, run these two commands in a terminal:

```sh
python3 -m pip install spacy
python3 -m spacy download en_core_web_sm
```

Then add this line to your vimrc:

```vim
let g:bartleby_spotlight_tagger = 'spacy'
```

With spaCy set, the other modes use it too and become more accurate.
spaCy does not check a paragraph while you type in it. It checks the
paragraph again when you press `Esc`.

## Structure

The Binder tree is the structure of your book. A chapter is a folder,
and its scenes are the documents in that folder, in the order of the
tree. When you move a scene in the Binder, it moves in the compiled
book.

| Scrive type | Structure |
| --- | --- |
| Novel with Parts | Parts contain chapters, and chapters contain scenes |
| Novel | Chapters contain scenes |
| Short Story | Documents directly in Manuscript |

**Front Matter and Back Matter** hold the pages before and after the
main text, such as a dedication, a copyright notice, and
acknowledgments. Put each one in its own document. When you compile,
each one gets its own unnumbered heading.

**Characters and Research** are notes for you: character sheets,
places, research. They are never compiled.

## Dictionary and thesaurus

Bartleby can show the definition and the synonyms of a word from
Merriam-Webster, in the editor and in Focus.

This needs two free API keys from Merriam-Webster: one for the
Collegiate Dictionary and one for the Collegiate Thesaurus. Register
at [dictionaryapi.com](https://dictionaryapi.com), then add the keys
to your vimrc:

```vim
let g:bartleby_dictionary_api_key = 'your-dictionary-key'
let g:bartleby_thesaurus_api_key = 'your-thesaurus-key'
```

You can set only one of them. Without a key, that lookup is off.

Put the cursor on a word and press:

- `<leader>bd` for its definition.
- `<leader>bt` for its synonyms.

To look up a phrase such as "go-between", select it with `v` first,
then press the same keys.

In the synonym list:

| Key | Does |
| --- | --- |
| `j` / `k` | Move the selection |
| `<Enter>` | Put the selected word in place of the original |
| `a` | Show antonyms, or synonyms again |
| `d` | Show the definition of the selected word |
| `q` | Close without a change |

Bartleby keeps the capitalization of the original word, and `u` undoes
the change. If you misspell a word, Bartleby shows Merriam-Webster's
suggestions. Press `<Enter>` on one to look it up.

Bartleby remembers each lookup. A second lookup of the same word is
instant and does not use your daily allowance of requests.

## Document details

Each document can have a label and a status. You can set both in the
Binder:

- **Label** - a color: Red, Orange, Yellow, Green, Blue, or Purple.
  You decide what each color means, for example "needs a rewrite".
  Press `l` to set it. The Binder shows it after the title.
- **Status** - a state such as To Do, Draft, or Done. Press `s` to set
  it.

The **Inspector** shows all the details of the open document. Press
`<leader>bi` to open it. It follows you when you open another
document. Press `e` on a line to change that detail:

| Detail | Use |
| --- | --- |
| Label and Status | As in the Binder |
| Target | A word-count goal for the document |
| Keywords | Your own tags, separated by commas, such as themes or characters |
| Synopsis | A summary of one or more paragraphs. `<Enter>` starts a new line. `Ctrl-s` saves |

## Corkboard

The Corkboard shows the documents of a folder as index cards, with
each title and synopsis. Use it to try a different scene order. Press
`gc` on a folder in the Binder to open it.

| Key | Does |
| --- | --- |
| Arrow keys | Move between cards |
| `<Enter>` or `<Space>` | Open the selected document |
| `e` | Edit the synopsis |
| `J` / `K` | Move the card later or earlier. This changes the compile order |
| `?` | Show the keys |
| `Esc` | Close |

## Outliner

The Outliner shows everything in a folder as a table: Title, Label,
Status, Words, Target, and Keywords. Press `go` on a folder in the
Binder to open it.

| Key | Does |
| --- | --- |
| `j` / `k` | Move the selection |
| `<Enter>` | Open the selected document |
| `l` / `s` | Set the label or status |
| `gs` | Sort by a column |
| `?` | Show the keys |
| `q` | Close |

Sorting changes only the view. It does not change the order in your
book. To change the order, use the Binder or the Corkboard.

## Screenplays

A Screenplay scrive uses the Fountain format. Fountain is plain text
with simple rules for scene headings, character names, and dialogue.
If Fountain is new to you, search the web for "Fountain screenplay
format". You can learn it in a few minutes.

Spotlight's Dialogue mode knows the Fountain rules. It dims
everything except the current character's lines.

A compiled screenplay is a PDF, an HTML page, or a Final Draft file.
See [Compile](#compile).

## Palette and menu

You can run any Bartleby command without its key:

- `<leader>b<Space>` opens the command palette. Type part of a name,
  such as "compile" or "focus", then press `<Enter>`.
- `<leader>bm` opens the same commands as a menu, in groups.

## Session

Bartleby remembers, for each scrive, the open document, the cursor
position, and which Binder folders are open. It also remembers the
last scrive.

`:BartlebyOpen` with no name restores all of this. To restore it each
time Vim starts, add this line to your vimrc:

```vim
let g:bartleby_session_auto_restore = 1
```

## Auto-save

Bartleby saves your documents while you work. It saves when you stop
typing, when you leave a document, and when you switch to another
program. It saves a document at most once every 30 seconds while you
work in it. It saves only the documents of your scrive and does not
touch other files.

To change the 30 seconds, set `g:bartleby_autosave_interval` in your
vimrc. To turn auto-save off:

```vim
let g:bartleby_autosave = 0
```

## Snapshots

A snapshot is a copy of a document at one moment. Take one before a
large rewrite, or at the end of a writing session.

- `S` on a document in the Binder, or `:BartlebySnapshot` in the
  document, takes a snapshot.
- `gS` or `:BartlebySnapshots` lists the snapshots and restores one.
  Before a restore, Bartleby takes a snapshot of the current text, so
  you can always go back.

Bartleby keeps the 5 newest snapshots of each document. To change the
number, set `g:bartleby_snapshot_retention` in your vimrc.

## Search

Press `/` in the Binder, or run `:BartlebySearch`, to search all
documents in your scrive. The results go to Vim's quickfix list. Use
`:cnext` and `:cprev` to move between them, or `:copen` to see all of
them.

## Compile

When your book, or a part of it, is ready to share, run
`:BartlebyCompile`. It makes a separate output file and does not
change your documents.

1. **Choose the documents.** The pane lists the contents of Front
   Matter, Manuscript, and Back Matter, with a box for each document.
   Press `x` to include or exclude a document. On a folder, `x`
   includes or excludes everything in it. Press `<Enter>` to continue.
2. **Choose a kind.**
   - **Manuscript** - a PDF in the standard submission format for
     agents and publishers: double-spaced Courier with a title page
     that shows your contact information and the word count.
   - **Book** - a PDF, EPUB, HTML page, or Markdown file laid out
     like a printed book, with chapter openings, running headers, a
     table of contents, and an optional cover image.
   - **Screenplay** - a PDF, HTML page, or Final Draft file in the
     standard screenplay format.
3. **Choose a format and the settings** for that kind, such as line
   spacing or a cover image.
4. **Name the target.** Bartleby saves your answers. Next time, run
   `:BartlebyCompile`, pick the name, and choose Run. Choose Edit to
   change the settings, or Delete to remove the target.

Each Front Matter and Back Matter document becomes its own section,
separate from your numbered chapters.

A PDF needs two free programs, Pandoc and LaTeX. If
`:BartlebyCompile` cannot find them, see
[Requirements](README.md#requirements) in the README.

## Author profile

`:BartlebyProfile` stores your name and contact information once for
all scrives. Bartleby puts it on the title page of a manuscript.
`:BartlebyProjectInfo` changes any of these details for the current
scrive only, for example to use a pen name.

## Keys

These keys work in any document:

| Key | Does |
| --- | --- |
| `<leader>bi` | Open or close the Inspector |
| `<leader>bz` | Turn Focus on or off |
| `<leader>bl` | Turn Spotlight on or off |
| `<leader>bL` | Pick a Spotlight mode |
| `<leader>bp` | Turn Quill on or off |
| `<leader>bd` | Define the word under the cursor |
| `<leader>bt` | Synonyms for the word under the cursor |
| `<leader>b<Space>` | Command palette |
| `<leader>bm` | Command menu |

The keys for the Binder, Corkboard, Outliner, Inspector, synonym list,
and scrive list are in their own sections.

## Help

Press `?` in the Binder, Corkboard, Outliner, scrive list, or synonym
list to see its keys. `:help bartleby` opens the full reference in
Vim.

## Files

Each scrive is a folder under `~/Documents/Bartleby/`. In it:

- `binder/` holds your chapters and scenes as plain `.md` files, or
  `.fountain` files for a screenplay. A small file next to each
  document holds its label, status, synopsis, and other details.
- `compile/` holds your compiled files.

You can find, copy, or back up your writing with any file browser. To
keep your scrives in another place, set `g:bartleby_binder_root` in
your vimrc.
