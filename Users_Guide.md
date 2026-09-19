# Bartleby: A Guide for Writers

This guide walks through Bartleby from a writer's point of view - no
assumptions that you're a Vim power user, just that you can open Vim,
type in it, and get around with the arrow keys or `h`/`j`/`k`/`l`. If
you're comfortable with Vim already, you may prefer the more compact
reference in [README.md](README.md) instead.

Everything Bartleby does lives in ordinary text files on your
computer - never a database, never a proprietary format. You can
always open your chapters in another editor, back them up with any
tool you like, or move away from Bartleby entirely without losing
anything.

## Contents

- [A few words before you start](#a-few-words-before-you-start)
- [Starting your first project](#starting-your-first-project)
- [Finding your way around the Binder](#finding-your-way-around-the-binder)
- [Writing](#writing)
- [Organizing your manuscript](#organizing-your-manuscript)
- [Tracking your progress](#tracking-your-progress)
- [Shuffling scenes on the Corkboard](#shuffling-scenes-on-the-corkboard)
- [Seeing everything at once: the Outliner](#seeing-everything-at-once-the-outliner)
- [Writing screenplays](#writing-screenplays)
- [Quick access to everything](#quick-access-to-everything)
- [Picking up where you left off](#picking-up-where-you-left-off)
- [Undo insurance: snapshots](#undo-insurance-snapshots)
- [Finding things](#finding-things)
- [Turning your binder into a manuscript](#turning-your-binder-into-a-manuscript)
- [Your author profile](#your-author-profile)
- [Cheat sheet](#cheat-sheet)
- [Getting help without leaving Vim](#getting-help-without-leaving-vim)
- [Where your files actually live](#where-your-files-actually-live)

## A few words before you start

Vim has two kinds of mode you'll move between constantly:

- **Normal mode** - the default. Letters and symbols are commands, not
  text. This is where almost every Bartleby key in this guide is
  pressed.
- **Insert mode** - where you actually type prose. Press `i` to enter
  it from normal mode, and `Esc` to leave it and go back to normal
  mode.

Every Bartleby command in this guide (`a`, `l`, `gc`, and so on) is
pressed in normal mode. If a key doesn't seem to do anything, press
`Esc` first to make sure you're not still in insert mode.

## Starting your first project

In Vim, run:

```vim
:BartlebyNewScrive My First Novel
```

You'll be asked what kind of project this is:

- **Novel** - chapters made of scenes.
- **Novel with Parts** - chapters grouped into parts (Part One, Part
  Two, and so on), for longer or multi-section books.
- **Short Story** - a single flat piece, no chapter structure.
- **Screenplay** - uses the Fountain screenplay format instead of
  plain text (see [Writing screenplays](#writing-screenplays)).

Pick one, and Bartleby creates the project (Bartleby calls a project a
**scrive**) and opens its Binder - the sidebar tree that's the heart
of everything you do. A new scrive starts with a sensible skeleton
already in place: Front Matter, Manuscript (with a first chapter and
scene ready to go), Back Matter, Characters, and Research.

Next time you open Vim, `:BartlebyOpen` with no name reopens whichever
scrive you had open last. To open a different one by name, use
`:BartlebyOpen {name}`.

## Finding your way around the Binder

The Binder is the tree on the left - every folder and document in
your project, in the order they'll appear when you compile.

Move the cursor up and down with the arrow keys (or `j`/`k`), and:

- **`<Enter>`** opens whatever's under the cursor - a document for
  writing, or expands/collapses a folder.
- **`<Tab>`** expands or collapses a folder without opening anything.
- **`a`** adds a new document inside the folder under the cursor (or
  as a sibling, if the cursor is on a document).
- **`A`** adds a new folder. Depending on your project type, you'll be
  offered Chapter, Part, or a plain Custom folder.
- **`r`** renames whatever's under the cursor.
- **`dd`** deletes it, after confirming.

Five folders - **Front Matter**, **Manuscript**, **Back Matter**,
**Characters**, and **Research** - are part of every scrive's
permanent shape. You can't rename, delete, move, or reorganize these
five specifically; think of them as the load-bearing walls of the
project. `dd` on one of them empties its contents (after confirming)
rather than deleting the folder itself, so you always have a fresh
Front Matter or Back Matter to work with even after clearing it out.
Everything you actually create - chapters, scenes, character sheets,
research notes - lives freely inside them and can be added, removed,
and rearranged however you like.

**Chapters and Parts** can be reordered with `J` (move down) and `K`
(move up), and promoted or demoted with `>>` (indent - turn a Chapter
into part of a Part) and `<<` (outdent - the reverse).

When you're done for the session, `q` closes the Binder - it'll come
back automatically the next time you open this scrive.

## Writing

Open any document from the Binder with `<Enter>` and you're in an
ordinary Vim buffer - press `i` to start typing, `Esc` when you want
to move around or run a command again.

A few things make it feel less like a code editor and more like a
word processor:

**Quill** turns on automatically for your documents and gives you
word-processor-style line wrapping - your paragraphs wrap to fit the
window without you ever pressing Enter mid-sentence, exactly like
Word or Google Docs. If you ever need to check or change its mode,
`:BartlebyQuill` (or `<leader>bp`) toggles it, and `:BartlebyQuill
detect` re-checks how a document you opened elsewhere is formatted.

**Focus** narrows the window to a centered column and dims everything
else on screen, so the only thing you're looking at is your prose.
Toggle it with `<leader>bz` or `:BartlebyFocus`.

**Spotlight** dims every paragraph except the one your cursor is in -
useful for editing one passage at a time without the rest of the page
pulling your eye. Toggle it with `<leader>bl`; `<leader>bL` lets you
pick a different mode (for screenplays, a Dialogue mode dims
everything but the current speaker's lines - see
[Writing screenplays](#writing-screenplays)).

All three are independent - use any combination, or none at all.

## Organizing your manuscript

Bartleby doesn't infer your book's structure from headings in the
text the way some tools do - the Binder tree itself *is* the
structure. A Chapter is a folder; the scenes inside it are documents
inside that folder, in the order they appear in the tree. Reordering
scenes in the Binder reorders them in the finished manuscript.

For a Novel with Parts, Parts contain Chapters, which contain Scenes -
three levels deep. For a plain Novel, Chapters contain Scenes
directly. A Short Story generally just holds documents straight
under Manuscript, no Chapter folders at all.

**Front Matter and Back Matter** hold anything that comes before or
after the main text - a dedication, a copyright notice, acknowledgments
- each as its own document. When you compile, each one gets its own
unnumbered heading (a title page of its own, effectively), separate
from your numbered chapters.

**Characters and Research** are for you, not your reader - character
sheets, worldbuilding notes, anything you want alongside your
manuscript but don't intend to publish. Nothing inside them is
included when you compile unless you explicitly include it (see
[Turning your binder into a manuscript](#turning-your-binder-into-a-manuscript)).

## Tracking your progress

Every document can carry a few pieces of metadata, all visible and
editable without leaving the Binder:

- **Label** - a color (Red, Orange, Yellow, Green, Blue, Purple), for
  whatever meaning you want to give it - "needs a rewrite," "point of
  view: Sam," anything. Press `l` on a document to set it; it shows up
  next to the title in the Binder.
- **Status** - a simple state like "To Do," "Draft," or "Done" (press
  `s` to set it).

For a fuller picture - and to set two things the Binder itself doesn't
show - open the **Inspector** with `<leader>bi` while a document is
open. It shows that document's Title, Label, Status, **Target word
count**, **Keywords**, and **Synopsis** all in one place, and follows
you automatically as you switch between documents. Press `e` on any
line to edit that field:

- **Target** - a word-count goal for this document. Handy for scenes
  you want to keep within a certain length, or chapters with a target
  you're writing toward.
- **Keywords** - a short comma-separated list of tags for your own
  use (themes, characters present, anything you want to search or
  scan for later).
- **Synopsis** - a longer, multi-paragraph summary. Press `<Enter>`
  freely while writing one; it inserts a new line rather than closing
  the box. `<Ctrl-s>` saves it when you're done.

## Shuffling scenes on the Corkboard

Sometimes you want to see a folder's scenes as index cards rather than
a list - useful for feeling out pacing or trying a different scene
order without committing to it in the text. Press `gc` on a folder in
the Binder to open its Corkboard: one card per document, showing its
title and synopsis.

Arrow keys move between cards, `<Enter>` or `<Space>` opens the
selected one, `e` edits its synopsis right there, and `J`/`K` reorder
cards - which, unlike the Outliner's sort below, *does* actually
change the order scenes appear in when you compile.

## Seeing everything at once: the Outliner

Press `go` on a folder to open the Outliner - a spreadsheet-style view
of that folder's entire contents: Title, Label, Status, Words, Target,
and Keywords, all in one screen.

`l` and `s` set Label and Status right from this view, same as in the
Binder. `gs` lets you sort the list by any column - handy for
scanning, say, everything still marked "To Do," or everything over
its word-count target - but this sorting is just a different way of
*looking* at your scenes; it doesn't change their actual order in the
manuscript the way Corkboard's reordering does.

## Writing screenplays

Choosing "Screenplay" as your project type switches your documents to
the `.fountain` format - plain text with a simple, readable convention
for scene headings, character cues, and dialogue (if you've never
written in Fountain before, a quick search for "Fountain screenplay
format" will get you up to speed in a few minutes; it's meant to be
learnable in one sitting).

Bartleby understands Fountain's structure well enough that Spotlight's
Dialogue mode dims everything except the current character's actual
spoken lines - not just text between quotation marks, since screenplay
dialogue isn't quoted at all.

Compiling a screenplay produces a PDF, HTML, or Final Draft (`.fdx`)
file in standard screenplay format - see
[Turning your binder into a manuscript](#turning-your-binder-into-a-manuscript).

## Quick access to everything

Two ways to reach any Bartleby command without memorizing its keymap:

- **`<leader>b<Space>`** opens a fuzzy-searchable command palette -
  start typing a few letters of what you want ("compile", "focus",
  "snapshot") and press `<Enter>` on the match.
- **`<leader>bm`** opens the same set of commands organized as a
  categorized menu instead, if you'd rather browse than type.

(If you haven't changed it, your `<leader>` key is almost certainly
the backslash, `\`.)

## Picking up where you left off

Bartleby remembers, per project: which document you had open, your
exact cursor position in it, and which Binder folders were
expanded or collapsed. It also remembers which scrive you had open
last, across Vim restarts entirely.

By default you have to ask for it explicitly - `:BartlebyOpen` with no
name picks up your last scrive and restores all of this. If you'd
rather this happen automatically every time you start Vim, add this
to your vimrc:

```vim
let g:bartleby_session_auto_restore = 1
```

## Undo insurance: snapshots

Beyond Vim's own undo, Bartleby can save a timestamped copy of a
document's exact text whenever you want a checkpoint to come back to -
useful before a big rewrite, or just at the end of a productive
session.

- **`S`** on a document in the Binder (or `:BartlebySnapshot` while
  writing) takes one.
- **`gS`** (or `:BartlebySnapshots`) shows you the list and lets you
  restore any of them. Restoring always takes a fresh snapshot of your
  *current* text first, so restoring an old version is never a
  one-way trip.

By default the 5 most recent snapshots per document are kept; older
ones are dropped automatically. Set
`g:bartleby_snapshot_retention` in your vimrc to change that number.

## Finding things

Press `/` in the Binder, or run `:BartlebySearch` from anywhere, to
search every document in your project at once. Results land in Vim's
quickfix list, which you can step through with `:cnext` and `:cprev`,
or browse all at once with `:copen`.

## Turning your binder into a manuscript

When your project (or even just part of it) is ready to share,
`:BartlebyCompile` walks you through producing a real output file.

**Step 1: choose what to include.** You'll see the full binder tree
with a checkbox next to every document - toggle any of them off if you
want to compile only part of your project (a single chapter to send a
critique partner, for instance).

**Step 2: choose a kind.**

- **Manuscript** produces a submission-ready PDF: double-spaced,
  Courier, a proper title page with your contact information and word
  count - the standard format literary agents and publishers expect.
  This is what you'll use most often while a project is still being
  submitted anywhere.
- **Book** produces a typeset PDF, HTML, EPUB, or Markdown file that
  looks like an actual printed or e-book: styled chapter openings,
  running headers, an optional cover image, and a table of contents.
  This is for when you're ready to self-publish or just want to see
  your work laid out the way a finished book would look.
- **Screenplay** produces a PDF, HTML, or Final Draft file in
  standard screenplay format.

**Step 3: choose a format and a few kind-specific settings** - line
spacing for a Manuscript, a cover image for a Book, and so on.

**Step 4: name it and confirm.** Bartleby saves your answers as a
named target, so next time you just run `:BartlebyCompile`, pick that
name, and choose Run - no need to answer the whole wizard again. Pick
Edit instead if you want to change its settings, or Delete to remove
it.

However you organized your Front Matter and Back Matter, Bartleby
takes care of formatting them correctly for whichever kind you chose -
each becomes its own properly separated section, distinct from your
numbered chapters, exactly as a real dedication page, copyright
notice, or acknowledgments section should look.

A few things worth knowing:

- Compiling to PDF requires a couple of free external programs
  (Pandoc, and a LaTeX installation) to already be installed on your
  computer - see the Requirements section of
  [README.md](README.md#requirements) if `:BartlebyCompile` reports
  it can't find them.
- Nothing about compiling changes your actual documents. It only ever
  reads them and writes a separate output file.

## Your author profile

`:BartlebyProfile` sets your name and contact information once,
globally, so it doesn't have to be re-entered for every new project -
it's pulled automatically into your manuscript's title page when you
compile. `:BartlebyProjectInfo` overrides any of those fields for the
current project only, if this book needs different contact details
than your usual default (a pen name, say).

## Cheat sheet

**Anywhere**

| Key | Does |
| --- | --- |
| `<leader>bi` | Toggle Inspector |
| `<leader>bz` | Toggle Focus |
| `<leader>bl` | Toggle Spotlight |
| `<leader>bL` | Pick a Spotlight mode |
| `<leader>bp` | Toggle Quill |
| `<leader>b<Space>` | Command palette |
| `<leader>bm` | Command menu |

**In the Binder**

| Key | Does |
| --- | --- |
| `<Enter>` | Open document / expand-collapse folder |
| `<Tab>` | Expand/collapse folder |
| `a` | Add document |
| `A` | Add folder |
| `r` | Rename |
| `dd` | Delete (or clear, for the five permanent folders) |
| `J` / `K` | Move a Chapter/Part down/up |
| `>>` / `<<` | Indent/outdent |
| `l` | Set label |
| `s` | Set status |
| `S` / `gS` | Take / view snapshots |
| `gc` | Open Corkboard |
| `go` | Open Outliner |
| `/` | Search everything |
| `?` | Show this list, in Vim |
| `q` | Close the Binder |

**In the Inspector**

| Key | Does |
| --- | --- |
| `e` | Edit the field under the cursor |

**In the Corkboard**

| Key | Does |
| --- | --- |
| arrows | Move between cards |
| `<Enter>` / `<Space>` | Open the selected document |
| `e` | Edit its synopsis |
| `J` / `K` | Reorder cards |

**In the Outliner**

| Key | Does |
| --- | --- |
| `j` / `k` | Move the selection |
| `<Enter>` | Open the selected document |
| `l` / `s` | Set label / status |
| `gs` | Sort by a column |
| `?` | Show this list |
| `q` | Close |

## Getting help without leaving Vim

Press `?` inside the Binder, Corkboard, or Outliner at any time for a
quick list of that screen's own keys. For everything else, `:help
bartleby` opens Bartleby's full reference documentation right inside
Vim.

## Where your files actually live

By default, every project lives under `~/Documents/Bartleby/`, one
folder per scrive. Inside a scrive's folder, `binder/` holds your
actual chapters and scenes as plain `.md` (or `.fountain`) files, and
`compile/` holds anything you've compiled. Every document file sits
right alongside a small sidecar file holding its label, status,
synopsis, and so on - so you can always find, back up, or move your
actual writing with nothing more than a regular file browser. To use a
different location, set `g:bartleby_binder_root` in your vimrc.
